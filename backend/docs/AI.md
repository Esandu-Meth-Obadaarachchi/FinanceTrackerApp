# How the AI works

The design decisions behind the AI features, and the reasoning that produced
them. For running the service, endpoints and configuration, see the
[README](../README.md).

---

## 1. The problem being solved

Personal finance apps die the same way. They hand you a blank form and rely
on your discipline. You skip two days, the ledger goes stale, and stale data
is worthless, so you stop opening it. Features never fix this. Friction does.

So the AI here is not a chatbot bolted onto a ledger. Its job is to **invert
the app**: stop asking the user to enter things, and reduce their job to
approving things the app already worked out. The daily interaction should be
a few taps, not a few forms.

That goal drives every choice below, including the ones that look like
over-engineering.

---

## 2. Everything is layered cheapest-first

This is the core architectural idea. Three layers answer in order, and the
model is the last resort rather than the first move.

```
      bank SMS or typed text
               │
               ▼
   ┌───────────────────────┐
   │ 1. Local memory        │  instant · free · offline
   │    CategoryMemory      │  "seen this merchant before"
   └───────────┬───────────┘
               │ miss
               ▼
   ┌───────────────────────┐
   │ 2. Regex               │  instant · free · offline
   │    SmsParser           │  amount + direction + card tail
   └───────────┬───────────┘
               │ miss
               ▼
   ┌───────────────────────┐
   │ 3. The model           │  ~1–3s · costs money · needs network
   │    Gemini → Claude     │  anything genuinely new
   └───────────────────────┘
```

**Why this order matters.** A category question the user has already answered
once should never cost a network round trip again. Reversing these layers
would make the common case slow, paid and useless on a plane, for no gain in
accuracy — local memory is *more* reliable than the model on merchants it has
seen, because it is replaying a decision the user actually confirmed.

The layers live on the client
([`category_memory.dart`](../../lib/models/category_memory.dart),
[`sms_parser.dart`](../../lib/services/sms_parser.dart)) and only layer 3
reaches this service.

### Local memory refuses to guess

`CategoryMemory` scores categories by token, and returns nothing when the top
two are close:

```dart
if (ranked.length > 1) {
  final runnerUp = ranked[1].value;
  if (runnerUp > 0 && best.value / runnerUp < minLead) return null;
}
```

This looks like timidity and is the opposite. A confident wrong suggestion is
worse than silence, because the user stops trusting the fill-in and starts
checking every field by hand — which is exactly the friction the feature
exists to remove. Silence costs one dropdown. A wrong answer costs the
feature.

An exact merchant match is trusted outright, with no score threshold at all.
Banks print merchant strings verbatim, so `KEELLS SUPER COL 03` matching
`KEELLS SUPER COL 03` is not a guess. Free text votes by token instead,
because "lunch at odel" and "lunch odel" should reach the same answer.

---

## 3. Two providers, one interface

`gemini-3.6-flash` handles every request. `claude-haiku-4-5` catches it when
Gemini fails. The client never knows which answered, beyond a `provider`
field it can display.

### The abstraction

The two vendors disagree on nearly every wire detail: tool schema shape, how
a tool call comes back, how a tool result goes in, how the system prompt is
passed. `providers/base.py` defines one vocabulary — `Turn`, `ToolSpec`,
`ToolCall`, `ToolResult`, `LLMResponse` — and each adapter translates at its
own edge.

That is what makes the fallback a loop over two objects rather than two
parallel implementations of the agent.

### The fallback fires on *any* failure

```python
for provider in (self.primary, self.fallback):
    try:
        return await provider.complete(...)
    except ProviderError as exc:
        log.warning("provider %s failed, falling through: %s", provider.name, exc)
```

The first version of this was cleverer and wrong. It treated 4xx as fatal on
the reasoning that a malformed request will be malformed for everyone, and
only fell through on 429 and 5xx.

That assumes both vendors validate the same request identically. They do not.
Gemini 3.x rejects a conversation whose function calls come back without
their `thoughtSignature` — a concept Claude has never heard of. Anthropic
rejects an object schema without an explicit `additionalProperties: false` —
which Gemini does not accept at all and has to be stripped. Each of those is
a 400 from one provider that the other handles without complaint.

Every failure observed while building this — the free tier's daily 429,
overload 503s, transport timeouts, vendor-specific schema rules — was one the
other provider handled. One wasted call on a genuinely bad request is much
cheaper than a dead endpoint.

**This is not theoretical.** During end-to-end testing Gemini hit its
free-tier quota mid-run and the router moved to Claude with no visible change
to any response other than the `provider` field.

### Two Gemini behaviours that cost real debugging time

Both are handled in `providers/gemini.py` and written down so nobody
rediscovers them.

**1. Flash 3.x always thinks, and thinking spends your output budget.**

`thinkingBudget: 0` is rejected outright — you cannot turn it off. Those
thinking tokens come out of `maxOutputTokens`. A 64-token budget spent 61 on
reasoning and returned `finishReason: MAX_TOKENS` with *no content at all*.

An empty success is worse than an error: it looks like the model had nothing
to say. So it is converted into a failure that falls through:

```python
if finish == "MAX_TOKENS" and not parts:
    raise ProviderError(self.name, "output budget exhausted by thinking before any answer")
```

Budgets here are generous for the same reason (4096 for the agent loop).

**2. Function calls carry a `thoughtSignature` that must be echoed back.**

Drop it when replaying history and the next turn is a 400. `ToolCall` carries
a `signature` field purely so this survives the round trip, and it is
provider-opaque data the rest of the system ignores.

Thinking also arrives as response parts flagged `thought`. Those are
reasoning, not the answer, and are skipped — showing them to the user would
leak the model's working into the reply.

### Cost

A parse is roughly 900 tokens in, 100 out.

| Model | Input / Output per 1M | Per parse | 300 parses/month |
|---|---|---|---|
| `gemini-3.6-flash` | free tier | — | — |
| `claude-haiku-4-5` | $1 / $5 | ~$0.0014 | ~$0.42 |

Agent questions cost more — several round trips, each carrying the tool
schemas and accumulated results — but remain in cents per month at personal
usage. The free tier absorbs most of it and Claude picks up the rest.

---

## 4. The RAG design

This is the part worth reading carefully, because it deliberately does *not*
look like a standard RAG stack.

### There is no vector database

The textbook approach would embed every transaction, store the vectors, embed
the question, retrieve the top-k nearest, and stuff them into the prompt.
That is the wrong tool here, for four reasons:

**Money questions need exact filters, not semantic similarity.** "How much
did I spend on fuel in August" is a `WHERE category = 'Fuel' AND date BETWEEN
…` query. Cosine similarity would return things that *read* like fuel
purchases and silently miss a row categorised slightly differently, or pull
in a July row because the text was similar. For a question whose answer is a
number that must be right, approximate retrieval is a bug.

**The corpus is tiny and structured.** A few hundred rows of typed fields,
not a warehouse of prose. The whole dataset is smaller than the embeddings
that would index it.

**An index goes stale.** Every new transaction would need re-embedding, and a
finance app is written to constantly. The snapshot is built fresh per
question and cannot drift.

**No vector store to host, secure or pay for.** For a free-tier personal app,
that infrastructure would exceed the app it serves.

So retrieval is real — the model genuinely fetches data it did not start
with — but it retrieves by **calling filter and aggregate functions** rather
than by nearest-neighbour lookup. It is RAG where the retriever is a query
engine instead of an embedding index.

### The snapshot

The client uploads its own financial data with each question:

```json
{
  "accounts":     [{ "id", "name", "type", "balance" }],
  "transactions": [{ "date", "type", "category", "note",
                     "amount", "status", "accountId" }],
  "loans":        [{ "who", "loanType", "amount", "outstanding",
                     "reason", "date" }],
  "budget":       { "month", "plannedIncome", "allocations" }
}
```

Two properties fall out of this that are worth naming.

**The backend needs no Firestore credentials.** It never reaches into anyone's
data. It sees only what one device chose to send for one question, and
retains none of it after the response. There is no database to breach here
because there is no database.

**Derived figures are computed client-side before upload.** `balance` and
`outstanding` arrive already calculated by
[`AiService.buildSnapshot`](../../lib/services/ai_service.dart), using the
same `loan_math.dart` the rest of the app uses. The model never re-derives
money rules the app already owns — which matters, because those rules are
genuinely subtle (a lent loan deducts its *original* amount for its whole
life, because repayments return separately as income; see the main
[CLAUDE.md](../../CLAUDE.md)). Asking a language model to re-infer that from
raw rows would be inviting it to get it wrong.

### The agent loop

```
question + snapshot
        │
        ▼
   ┌─────────────────────────────────┐
   │ model sees the question and     │◄──────────────┐
   │ the six tool schemas            │               │
   └────────────┬────────────────────┘               │
                │                                    │
        wants tools?                                 │
         │           │                               │
       yes           no ──────► final answer         │
         │                                           │
         ▼                                           │
   run each tool over the snapshot                   │
   (pure Python, no network)                         │
         │                                           │
         └────► append results to the conversation ──┘

   after 6 iterations: ask once more with no tools offered
```

Tools run **server-side over the uploaded snapshot**, not on the client.
There is no round trip to the device per tool call, so a question needing
three tools is still one HTTP request.

`MAX_ITERATIONS = 6` bounds the loop. Hitting it is not an error — the final
request drops the tools and asks for an answer from what was already
gathered, so a complex question degrades to a partial answer rather than an
exception.

### The six tools

All in `services/tools.py`. Each is a pure function of
`(snapshot, arguments)`.

| Tool | Answers |
|---|---|
| `query_transactions` | "What did I spend at X?" — filters by date, type, category, account, note, status. Caps at 50 rows, newest first |
| `aggregate_spending` | "How much on fuel?" — totals grouped by category, month, account or type |
| `get_accounts` | Balances, and the total across all accounts |
| `get_loans` | Lent and borrowed, with outstanding per loan |
| `get_pending_income` | Invoiced but not yet received |
| `get_budget` | Plan versus actual spend per category |

Two rules encoded in the tools rather than the prompt:

- **Pending income is never counted as income.** `aggregate_spending` skips
  it explicitly. It has not arrived, and a model told this only in prose
  would eventually forget.
- **A broken snapshot returns an error object, not an exception.** The model
  reads the error and can try a different tool. A 500 would just fail the
  request.

Purity is what makes them testable — `test_tools.py` covers filtering,
grouping, ordering and the edge cases with no model and no network, in 0.02
seconds.

### Why not let the model write SQL?

Considered and rejected. Fixed tools have a bounded surface: there is no
query the model can compose that reads data the snapshot did not include, and
no expression that can be slow or malformed. Six functions with typed
arguments cannot be injected into. Generated SQL against a real database
would be strictly more capable and strictly less safe, for questions this app
never needs to ask.

---

## 5. Structured output for parsing

Parsing does not use tools. It asks for a JSON object matching a fixed
schema, so the client gets fields it can drop straight into its existing
sheets rather than prose it has to interpret.

Both providers support this, differently:

| | Gemini | Claude |
|---|---|---|
| How | `responseMimeType` + `responseSchema` | `output_config.format` |
| Schema dialect | OpenAPI subset, types in CAPS | JSON Schema |
| `additionalProperties` | rejected — stripped | **required** on objects |

`_to_gemini_schema()` handles the translation. The asymmetry on
`additionalProperties` is the exact kind of vendor difference that makes the
"fall through on any error" rule earn its place.

### Output is never trusted raw

`_coerce()` normalises everything before it leaves the service:

- Amount forced positive and rounded; a non-numeric amount sets
  `understood: false` rather than propagating garbage
- `confidence` clamped to 0–1
- **A category not in the app's list is replaced with the catch-all.** The
  model returning "Groceries" instead of "Food & Groceries" would fail to
  render a category colour in the app, so it is mapped case-insensitively and
  then defaulted
- A zero amount always means `understood: false`

A model that returns confident nonsense should produce a harmless draft, not
a crash or a wrong entry.

---

## 6. Rules that hold across all of it

**Nothing AI-generated is ever saved without confirmation.** Parsing returns
drafts. The SMS inbox queues suggestions. Neither writes a transaction. With
money, one wrong silent write costs more trust than a hundred right ones
earn, and trust lost this way does not come back.

**`confidence` below 0.6 means the model guessed.** The client opens the edit
sheet instead of offering a one-tap approve. Above it, one tap.

**Every suggestion says where it came from.** The review inbox tags each card
`LEARNED`, `AI` or `RULES`. A guess should never be mistaken for a fact, and
the user deciding how much to check a given row is the whole review model
working.

**AI is off by default.** Without a reachable backend every AI path would sit
on a timeout, which is a worse experience than not offering the feature. It
is enabled explicitly in Settings, and every path degrades to manual entry
when it is off or unreachable.

---

## 7. Known gaps

- **`/parse/text` handles transactions only.** "lent nimal 10k" comes back as
  an expense, not a loan. Loan and pending-income intents are not modelled.
- **No prompt caching.** The category list and tool schemas are resent every
  request. Worth adding if agent usage grows.
- **The snapshot is sent whole.** Fine at a few hundred transactions; a user
  with years of history would want it windowed by relevance before upload.
- **No streaming.** Answers arrive complete, so a slow agent question shows a
  spinner for its whole duration rather than filling in progressively.
- **The shared key is coarse.** It authenticates the app, not the user.
  Verifying the Firebase ID token would tie a request to an account.
