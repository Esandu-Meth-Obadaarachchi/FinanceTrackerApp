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
.venv/bin/python -m pytest        # 27 tests, no network, no API keys needed
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
      tools.py                  The six tools, pure functions
  tests/
    test_tools.py               Tool filtering and totalling (19 tests)
    test_router.py              Fallback behaviour, with fakes (8 tests)
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

A question about your own money, answered by calling tools over a snapshot
you upload with the question.

```bash
curl -s -X POST http://127.0.0.1:8099/agent/ask \
  -H 'content-type: application/json' \
  -d '{
    "question": "how much did I spend on fuel in August and am I over budget?",
    "today": "2026-09-03",
    "snapshot": {
      "accounts": [{"id":"a2","name":"Sampath","type":"bank","balance":85000}],
      "transactions": [
        {"date":"2026-08-02","type":"expense","category":"Fuel","note":"IOC",
         "amount":8000,"status":"received","accountId":"a2"},
        {"date":"2026-08-11","type":"expense","category":"Fuel","note":"IOC",
         "amount":6500,"status":"received","accountId":"a2"}
      ],
      "loans": [],
      "budget": {"month":"2026-08","plannedIncome":120000,
                 "allocations":{"Fuel":15000}}
    }
  }'
```

```json
{
  "answer": "You spent Rs 14,500 on fuel in August. You're within budget by Rs 500, so no, you're not over. Your budget for fuel that month was Rs 15,000.",
  "provider": "anthropic",
  "tool_calls": [
    {"tool": "query_transactions",
     "arguments": {"category":"fuel","start_date":"2026-08-01",
                   "end_date":"2026-08-31","type":"expense"}},
    {"tool": "get_budget", "arguments": {}}
  ],
  "iterations": 2
}
```

`tool_calls` is returned so the client can show its working. The Flutter app
renders these as chips under each answer — with money, seeing *how* it got
there matters more than the reply sounding sure of itself.

Optional `history` carries prior turns as `[{"role":"user","content":"…"}]`.
The snapshot is **not** persisted, so send it with every question.

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
