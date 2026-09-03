# FinTrack AI backend

FastAPI service for the parts of FinTrack that need a model. It exists
because a Flutter web app cannot hold an API key: the bundle is fully
inspectable, so the key lives here instead.

## What it does

| Endpoint | Purpose |
|---|---|
| `GET /health` | Which providers are configured, and which models |
| `POST /parse/text` | One line of text to a transaction ("3500 lunch at odel") |
| `POST /parse/sms` | A bank SMS to a categorised transaction |
| `POST /agent/ask` | A question about your money, answered with tools |

Nothing here writes to Firestore, and nothing is stored between requests.

## Providers: Gemini first, Claude second

`gemini-3.6-flash` handles every request. When it fails, the same request
goes to `claude-haiku-4-5` and the caller never notices.

The fallback fires on **any** primary failure, not only the obvious ones.
Treating a 400 as fatal seems right until you learn each vendor validates
differently: Gemini 3.x rejects a tool history missing its
`thoughtSignature`, a rule Claude has never heard of. The failures seen in
practice — the free tier's daily 429, overload 503s, transport timeouts,
vendor schema rules — are all ones the other provider handles.

`response.provider` on every reply says who actually answered.

## Two Gemini quirks worth knowing

Both cost real debugging time, so they are written down rather than
rediscovered:

1. **Flash 3.x always thinks, and thinking spends `maxOutputTokens`.**
   `thinkingBudget: 0` is rejected outright. A stingy token budget gets
   consumed by reasoning and returns `MAX_TOKENS` with empty content, so
   budgets here are generous and an empty result is treated as a failure
   worth falling back on rather than an empty answer.
2. **Function calls carry a `thoughtSignature` that must be echoed back.**
   Drop it from the history and the next request is a 400.

## Running it

```bash
cd backend
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
cp .env.example .env        # then fill in the two keys
.venv/bin/python -m uvicorn app.main:app --reload --port 8099
```

`GET http://127.0.0.1:8099/health` should report both providers `true`.
Interactive docs are at `/docs`.

```bash
.venv/bin/python -m pytest        # 27 tests, no network needed
```

## Configuration

See `.env.example`. `.env` is gitignored and must stay that way.

- `GEMINI_API_KEY` — both the `AIzaSy…` and `AQ.…` formats go in the
  `x-goog-api-key` header. Set `GEMINI_AUTH_STYLE=oauth` only for a real
  OAuth bearer token.
- `ANTHROPIC_API_KEY` — the fallback.
- `APP_SHARED_KEY` — the client sends this as `X-App-Key`. **Set it before
  hosting.** Left blank the check is skipped, which is fine locally and an
  open proxy onto your paid credits anywhere else.
- `CORS_ORIGINS` — comma-separated origins allowed to call the API.

## How the agent works

The client posts its own financial data as a `snapshot` alongside the
question. Tools filter and aggregate that snapshot server-side, so the
backend needs no Firestore credentials and sees only what the device chose
to send for one question.

The loop runs up to six turns: the model calls tools, reads the results,
calls more if it needs them, then answers. Tools live in
`app/services/tools.py` as pure functions of `(snapshot, arguments)`, which
is why they are testable without a model.

Available tools: `query_transactions`, `aggregate_spending`, `get_accounts`,
`get_loans`, `get_pending_income`, `get_budget`.

## Deliberate limits

- **Parsing never saves anything.** Every result goes back to the client for
  confirmation. With money, one wrong silent write costs more trust than a
  hundred right ones earn.
- **`confidence` below 0.6** means the model guessed. The client should open
  the sheet rather than offer a one-tap approve.
- **`/parse/text` handles transactions only.** "lent nimal 10k" comes back as
  an expense, not a loan. Loan and pending-income intents are not modelled
  yet.
