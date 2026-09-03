# FinTrack AI backend

FastAPI service behind the AI features in the FinTrack Flutter app. It turns
text and bank SMS into draft transactions, and answers questions about your
own money using an agent that calls tools.

**Why it exists at all:** a Flutter web bundle is fully inspectable, so it
cannot hold an API key. Anything that talks to a model has to run somewhere
the key is not shipped to the browser. That is this.

For how the AI itself works — the provider fallback, the RAG design, the
agent loop, prompt rules — see **[docs/AI.md](docs/AI.md)**. This file covers
running and operating the service.

---

## Quickstart

```bash
cd backend
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
cp .env.example .env          # then fill in the two keys
.venv/bin/python -m uvicorn app.main:app --reload --port 8099
```

Check it came up:

```bash
curl -s http://127.0.0.1:8099/health
```

```json
{
  "ok": true,
  "providers": { "gemini": true, "anthropic": true },
  "primary": "gemini-3.6-flash",
  "fallback": "claude-haiku-4-5"
}
```

Both providers should read `true`. Interactive docs are at
`http://127.0.0.1:8099/docs`.

```bash
.venv/bin/python -m pytest        # 54 tests, no network, no API keys needed
```

> **Python version.** `requirements.txt` uses floors rather than exact pins
> because the dev machine runs Python 3.14, which has no prebuilt wheels for
> older `pydantic-core` (it tries to build from source and needs Rust). Pin
> exactly once you have chosen a hosting runtime.

---

## Layout

```
backend/
  app/
    main.py                     FastAPI app, routes, auth dependency, CORS
    config.py                   Settings from env / .env
    schemas.py                  Request and response models
    providers/
      base.py                   Provider-neutral vocabulary (Turn, ToolSpec, …)
      gemini.py                 Gemini Flash over raw HTTP
      anthropic_provider.py     Claude via the official SDK
      router.py                 Primary, then fallback
    services/
      parsing.py                Text and SMS to structured transactions
      agent.py                  The agentic loop
      tools.py                  Six read tools, pure functions
      actions.py                ask_user + the propose_* write tools
  tests/
    test_tools.py               Tool filtering and totalling (19 tests)
    test_router.py              Fallback behaviour, with fakes (8 tests)
    test_actions.py             Proposal validation (27 tests)
  docs/AI.md                    How the AI works
```

---

## Endpoints

All POST endpoints require the `X-App-Key` header when `APP_SHARED_KEY` is
set. Every response body includes `provider`, naming which model answered.

### `GET /health`

Which providers are configured and which models are in use. No auth. Use it
as your uptime check.

### `POST /parse/text`

One line of everyday text to a draft transaction.

```bash
curl -s -X POST http://127.0.0.1:8099/parse/text \
  -H 'content-type: application/json' \
  -d '{"text":"3500 lunch with amma at odel","today":"2026-09-03",
       "accounts":["cash","Sampath"]}'
```

```json
{
  "understood": true,
  "type": "expense",
  "amount": 3500.0,
  "category": "Entertainment & Dining",
  "note": "Lunch with Amma at Odel",
  "date": "2026-09-03",
  "account_hint": "",
  "status": "received",
  "confidence": 0.95,
  "reasoning": "Clear dining expense with a named venue.",
  "provider": "gemini"
}
```

| Field | Notes |
|---|---|
| `text` | Required, 1–500 chars |
| `today` | `YYYY-MM-DD`. Defaults to the server's date |
| `accounts` | Account names, so the model can fill `account_hint` |

`understood: false` means the text was not a financial entry at all. Check
it before reading any other field.

### `POST /parse/sms`

A bank SMS to a categorised transaction, for the review inbox.

```bash
curl -s -X POST http://127.0.0.1:8099/parse/sms \
  -H 'content-type: application/json' \
  -d '{"body":"Purchase at KEELLS SUPER COL 03 for LKR 4,250.00 on card ending 6709",
       "sender":"HNB","today":"2026-09-03"}'
```

Returns the same shape plus `merchant` (the raw string as printed) and
`card_tail`. OTP codes, promotions, balance enquiries and declined
transactions come back `understood: false`.

### `POST /agent/ask`

Ask about your money, or tell it to record something. Replies one of three
ways, told apart by `kind`.

```bash
curl -s -X POST http://127.0.0.1:8099/agent/ask \
  -H 'content-type: application/json' \
  -d '{
    "question": "how much did I spend on fuel in August?",
    "today": "2026-09-03",
    "snapshot": { "accounts": [...], "transactions": [...] }
  }'
```

**`kind: "answer"`** — a reply to show.

```json
{
  "kind": "answer",
  "answer": "Rs 14,500 on fuel in August, across 2 transactions.",
  "provider": "gemini",
  "tool_calls": [{"tool": "aggregate_spending", "arguments": {...}}],
  "iterations": 2
}
```

**`kind: "question"`** — it needs something before it answers. Render the
options as tappable chips and send the chosen one as the next `question`,
**echoing `state` back unchanged**.

```json
{
  "kind": "question",
  "answer": "Which period for your income?",
  "question": {
    "text": "Which period for your income?",
    "options": ["This month", "Last month", "This year"],
    "field": "period"
  },
  "state": {"pending": {"asked": "Which period for your income?", "collected": {}}}
}
```

**`kind: "proposal"`** — it wants to write. **Nothing has been saved.**
Render a confirmation card; on Apply, the client performs the write itself.

```json
{
  "kind": "proposal",
  "answer": "Check these details and tap Apply if they look right.",
  "proposal": {
    "id": "prop_a1b2c3d4e5f6",
    "kind": "add_transaction",
    "fields": {"type": "expense", "amount": 2500, "category": "Fuel",
               "note": "Fuel", "date": "2026-09-03",
               "accountId": "a2", "status": "received"},
    "summary": "Rs 2,500 · Fuel · Sampath · 2026-09-03",
    "warnings": []
  }
}
```

`proposal.kind` is `add_transaction`, `edit_transaction` or
`delete_transaction`. Edits and deletes carry `target_id` plus `before`, so
the card shows what is being replaced or removed; edits also carry `changes`
as readable lines. `id` is unique per proposal — track applied ones so a
double tap cannot write twice.

| Field | Notes |
|---|---|
| `question` | Required, 1–1000 chars |
| `snapshot` | The client's data. Not persisted, so send it every time |
| `history` | Prior turns, `[{"role","content"}]` |
| `state` | Echo back verbatim from the previous reply |
| `today` | `YYYY-MM-DD` |

The loop runs at most **3 read iterations**. `ask_user` and the `propose_*`
tools end the turn immediately, so a question or a write costs one model
call rather than spending the budget.

The snapshot schema is documented in [docs/AI.md](docs/AI.md#the-snapshot).

---

## Configuration

Everything comes from the environment, or a local `.env`. See
`.env.example`. **`.env` is gitignored and must stay that way.**

| Variable | Default | Notes |
|---|---|---|
| `GEMINI_API_KEY` | — | Primary provider. Blank disables it |
| `GEMINI_AUTH_STYLE` | `api_key` | `api_key` sends `x-goog-api-key`; `oauth` sends `Authorization: Bearer` |
| `GEMINI_MODEL` | `gemini-3.6-flash` | |
| `ANTHROPIC_API_KEY` | — | Fallback. Blank disables it |
| `ANTHROPIC_MODEL` | `claude-haiku-4-5` | |
| `CORS_ORIGINS` | `http://localhost:8567` | Comma-separated origins |
| `APP_SHARED_KEY` | empty | Sent by the client as `X-App-Key` |

### On the Gemini key format

Both the `AIzaSy…` (AI Studio) and `AQ.…` formats authenticate as **API
keys** in the `x-goog-api-key` header. Only set `GEMINI_AUTH_STYLE=oauth` if
you genuinely have an OAuth bearer token.

This is worth stating because guessing the style from the key prefix was the
original implementation and it was wrong: an `AQ.…` key sent as a bearer
token returns `401 UNAUTHENTICATED`, which reads exactly like a bad key
rather than a bad header.

### Before hosting

- **Set `APP_SHARED_KEY`.** Left blank the check is skipped. That is fine on
  localhost and an open proxy onto your paid API credits anywhere else.
- **Set `CORS_ORIGINS`** to your real origin.
- Consider verifying the Firebase ID token rather than a shared key, so a
  leaked key cannot be replayed. The shared key is the smaller first step.

---

## Deployment notes

The service is stateless: no database, no session store, nothing written to
disk. Scale it horizontally without coordination.

```bash
.venv/bin/python -m uvicorn app.main:app --host 0.0.0.0 --port 8099
```

Two things to size for:

- **Requests are slow and mostly idle.** A single agent question can take
  10–30 seconds across several model round trips. It is all `async` and
  awaits network, so concurrency costs little, but any proxy in front needs
  a read timeout above 120s or it will cut answers off.
- **Outbound HTTPS to both `generativelanguage.googleapis.com` and
  `api.anthropic.com`** must be allowed, or the fallback has nowhere to go.

---

## Troubleshooting

| Symptom | Cause |
|---|---|
| `/health` shows a provider `false` | That key is blank in the environment |
| `401 UNAUTHENTICATED` from Gemini | `GEMINI_AUTH_STYLE=oauth` with an API key |
| `404` on a Gemini model | Model retired. `curl .../v1beta/models` to list live ones |
| `503` from an endpoint | Both providers failed. The detail names each attempt |
| `502 bad model output` | The model returned unparseable JSON |
| Answers arrive but always `"provider": "anthropic"` | Gemini is failing every time. Check the server log for the fall-through warning |
| Browser console shows a CORS error | The app's origin is not in `CORS_ORIGINS` |

The router logs a warning on every fall-through, naming the provider and the
reason. That log is the fastest way to see the free tier running out.
