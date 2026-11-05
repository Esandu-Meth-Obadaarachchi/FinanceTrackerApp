"""Turning free text and bank SMS into structured transactions.

Both paths ask the model for JSON against a fixed schema rather than prose,
so the client gets fields it can drop straight into its existing sheets.
Neither path ever saves anything: the client always shows the result for
confirmation first. With money, a wrong silent write costs more trust than
a hundred correct ones earn.
"""

from __future__ import annotations

import json
from typing import Any

from ..providers.base import Turn
from ..providers.router import ProviderRouter

INCOME_CATEGORIES = [
    "Employment Income",
    "Freelance / Contract",
    "Business / Trade Income",
    "Rental Income",
    "Interest Income",
    "Dividends / Investment",
    "Capital Gains",
    "Scholarship / Bursary",
    "Reimbursement",
    "Loan Received",
    "Gift / Inheritance",
    "Other Assessable Income",
]

EXPENSE_CATEGORIES = [
    "Loan Repayment",
    "Rent / Housing",
    "Utilities & Bills",
    "Insurance Premiums",
    "Vehicle / Transport",
    "Food & Groceries",
    "Fuel",
    "Healthcare / Medical",
    "Pharmacy & Medicine",
    "Education & Training",
    "Shopping & Clothing",
    "Entertainment & Dining",
    "Pet Care",
    "Software & Subscriptions",
    "Marketing & Advertising",
    "Office & Stationery",
    "Business Travel",
    "Professional Fees",
    "Equipment & Technology",
    "Family Support",
    "Gifts & Donations",
    "Savings / Investment",
    "Other",
]

TRANSACTION_SCHEMA: dict[str, Any] = {
    "type": "object",
    "properties": {
        "understood": {
            "type": "boolean",
            "description": "False if the text is not a financial entry at all.",
        },
        "type": {"type": "string", "enum": ["income", "expense", "transfer"]},
        "amount": {"type": "number", "description": "Positive figure in LKR."},
        "category": {
            "type": "string",
            "description": "Exactly one label from the allowed list.",
        },
        "note": {
            "type": "string",
            "description": "Short human label, e.g. 'Lunch at Odel'.",
        },
        "date": {"type": "string", "description": "YYYY-MM-DD."},
        "account_hint": {
            "type": "string",
            "description": "Account name if the text names one, else empty.",
        },
        "status": {"type": "string", "enum": ["received", "pending"]},
        "confidence": {
            "type": "number",
            "description": "0 to 1. Below 0.6 the client asks the user.",
        },
        "reasoning": {"type": "string", "description": "One short clause."},
    },
    "required": ["understood", "type", "amount", "category", "note", "confidence"],
    # Anthropic rejects an object schema without this set explicitly.
    "additionalProperties": False,
}

_NL_SYSTEM = """You convert one line of everyday text into a single financial \
transaction for a Sri Lankan personal finance app. Amounts are LKR.

Rules:
- "k" means thousands: "10k" is 10000, "4.5k" is 4500.
- Pick `category` from the allowed list for the type, matching exactly.
- Money going out is "expense". Money arriving is "income". Moving between \
the user's own accounts is "transfer".
- If the text says money is owed, invoiced or expected rather than received, \
set status "pending". Otherwise "received".
- Default `date` to today unless the text says otherwise ("yesterday", \
"on the 3rd").
- `note` is a short human label, not a copy of the input.
- If the text is not a financial entry, set understood false and confidence 0.
- Set confidence below 0.6 whenever the amount or the category is a guess.

Today is {today}.
Income categories: {income}
Expense categories: {expense}
Known accounts: {accounts}"""

_SMS_SYSTEM = """You read one bank SMS from a Sri Lankan bank and extract the \
transaction it describes. Amounts are LKR unless the message says otherwise.

Rules:
- Only extract a real completed transaction. OTP codes, balance enquiries, \
promotions, failed or declined transactions and payment reminders are not \
transactions: set understood false for those.
- A debit, purchase, withdrawal or payment is an "expense". A credit, deposit \
or salary is "income".
- Infer `category` from the merchant name. Supermarkets are "Food & \
Groceries", filling stations are "Fuel", restaurants are \
"Entertainment & Dining", utilities are "Utilities & Bills".
- `note` is the cleaned-up merchant name, title case, no card numbers or \
reference codes. "KEELLS SUPER COL 03" becomes "Keells Super".
- `merchant` is the raw merchant string as printed.
- Use the date in the message if present, otherwise today.
- Set confidence below 0.6 if the merchant is unrecognisable.

Today is {today}.
Expense categories: {expense}
Income categories: {income}"""

SMS_SCHEMA: dict[str, Any] = {
    "type": "object",
    "properties": {
        **TRANSACTION_SCHEMA["properties"],
        "merchant": {"type": "string", "description": "Raw merchant string."},
        "card_tail": {
            "type": "string",
            "description": "Card or account digits shown, else empty.",
        },
    },
    "required": TRANSACTION_SCHEMA["required"],
    "additionalProperties": False,
}


def _coerce(payload: dict[str, Any]) -> dict[str, Any]:
    """Normalise a model's JSON into the shape the client expects."""
    out = dict(payload)
    out["understood"] = bool(out.get("understood", False))
    try:
        out["amount"] = round(abs(float(out.get("amount") or 0)), 2)
    except (TypeError, ValueError):
        out["amount"] = 0.0
        out["understood"] = False
    try:
        out["confidence"] = max(0.0, min(1.0, float(out.get("confidence") or 0)))
    except (TypeError, ValueError):
        out["confidence"] = 0.0

    if out.get("type") not in ("income", "expense", "transfer"):
        out["type"] = "expense"
    if out.get("status") not in ("received", "pending"):
        out["status"] = "received"

    # A category the app does not know would fail to render, so anything
    # unrecognised falls back to the catch-all for its type.
    allowed = INCOME_CATEGORIES if out["type"] == "income" else EXPENSE_CATEGORIES
    if out.get("category") not in allowed:
        match = next(
            (c for c in allowed if c.lower() == str(out.get("category", "")).lower()),
            None,
        )
        out["category"] = match or (
            "Other Assessable Income" if out["type"] == "income" else "Other"
        )

    if out["amount"] <= 0:
        out["understood"] = False
    for key in ("note", "date", "account_hint", "reasoning", "merchant", "card_tail"):
        out.setdefault(key, "")
    return out


def _extract_json(text: str) -> dict[str, Any]:
    """Read a JSON object out of a model response, fenced or bare."""
    cleaned = text.strip()
    if cleaned.startswith("```"):
        cleaned = cleaned.split("```")[1]
        if cleaned.startswith("json"):
            cleaned = cleaned[4:]
    cleaned = cleaned.strip()
    try:
        return json.loads(cleaned)
    except json.JSONDecodeError:
        start, end = cleaned.find("{"), cleaned.rfind("}")
        if start >= 0 and end > start:
            return json.loads(cleaned[start : end + 1])
        raise


async def parse_text(
    router: ProviderRouter,
    *,
    text: str,
    today: str,
    accounts: list[str] | None = None,
) -> dict[str, Any]:
    system = _NL_SYSTEM.format(
        today=today,
        income=", ".join(INCOME_CATEGORIES),
        expense=", ".join(EXPENSE_CATEGORIES),
        accounts=", ".join(accounts or []) or "none given",
    )
    response = await router.complete(
        system=system,
        turns=[Turn(role="user", text=text)],
        json_schema=TRANSACTION_SCHEMA,
        max_tokens=2048,
    )
    parsed = _coerce(_extract_json(response.text))
    parsed["provider"] = response.provider
    return parsed


async def parse_sms(
    router: ProviderRouter, *, body: str, today: str, sender: str = ""
) -> dict[str, Any]:
    system = _SMS_SYSTEM.format(
        today=today,
        income=", ".join(INCOME_CATEGORIES),
        expense=", ".join(EXPENSE_CATEGORIES),
    )
    prompt = f"From: {sender}\n\n{body}" if sender else body
    response = await router.complete(
        system=system,
        turns=[Turn(role="user", text=prompt)],
        json_schema=SMS_SCHEMA,
        max_tokens=2048,
    )
    parsed = _coerce(_extract_json(response.text))
    parsed["provider"] = response.provider
    return parsed
