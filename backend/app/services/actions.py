"""Terminal tools: asking the user something, and proposing a write.

These are the two ways an agent turn can end other than answering. Both stop
the loop immediately, which is what keeps a 3-iteration budget workable —
only *reading* consumes iterations.

Nothing here writes anything. The backend holds no database credentials by
design, so a write tool validates and normalises a draft and hands it back.
The client shows it for confirmation and executes it through the app's own
`AppState` methods, which own every money rule. That makes "confirm before
writing" structural rather than a policy someone has to remember.
"""

from __future__ import annotations

import uuid
from typing import Any

from ..providers.base import ToolSpec
from .parsing import EXPENSE_CATEGORIES, INCOME_CATEGORIES

# ── Tool schemas ─────────────────────────────────────────────────────────

ASK_USER = ToolSpec(
    name="ask_user",
    description=(
        "Ask the user one short question and stop. Use this ONLY when you can "
        "offer 2-4 concrete options they can tap, and the answer would "
        "genuinely change your reply — for example which month they mean, or "
        "which account a payment came from. If you cannot list options, do "
        "not use this tool: assume the most likely reading, say so in one "
        "clause, and answer anyway."
    ),
    parameters={
        "type": "object",
        "properties": {
            "question": {
                "type": "string",
                "description": "One short question, under 12 words.",
            },
            "options": {
                "type": "array",
                "items": {"type": "string"},
                "description": "2-4 short tappable answers.",
            },
            "field": {
                "type": "string",
                "description": "What is being resolved, e.g. 'period', 'account'.",
            },
        },
        "required": ["question", "options"],
        "additionalProperties": False,
    },
)

PROPOSE_ADD = ToolSpec(
    name="propose_add_transaction",
    description=(
        "Propose adding a new transaction. The user confirms before anything "
        "is saved. Only call this once you know the amount and the type; ask "
        "first if either is missing."
    ),
    parameters={
        "type": "object",
        "properties": {
            "type": {"type": "string", "enum": ["income", "expense", "transfer"]},
            "amount": {"type": "number", "description": "Positive, in LKR."},
            "category": {"type": "string", "description": "Exact label from the list."},
            "note": {"type": "string", "description": "Short human label."},
            "date": {"type": "string", "description": "YYYY-MM-DD."},
            "account_name": {
                "type": "string",
                "description": "Which account. Ask if the user has several.",
            },
            "status": {"type": "string", "enum": ["received", "pending"]},
        },
        "required": ["type", "amount", "category", "note"],
        "additionalProperties": False,
    },
)

PROPOSE_EDIT = ToolSpec(
    name="propose_edit_transaction",
    description=(
        "Propose changing an existing transaction. Find it with "
        "query_transactions first to get its id. Pass only the fields that "
        "should change. The user sees a before-and-after and confirms."
    ),
    parameters={
        "type": "object",
        "properties": {
            "transaction_id": {
                "type": "string",
                "description": "The id from query_transactions.",
            },
            "amount": {"type": "number"},
            "category": {"type": "string"},
            "note": {"type": "string"},
            "date": {"type": "string", "description": "YYYY-MM-DD."},
            "status": {"type": "string", "enum": ["received", "pending"]},
            "account_name": {"type": "string"},
        },
        "required": ["transaction_id"],
        "additionalProperties": False,
    },
)

PROPOSE_DELETE = ToolSpec(
    name="propose_delete_transaction",
    description=(
        "Propose deleting a transaction. Find it with query_transactions "
        "first. Propose one at a time and never guess which one the user "
        "meant — if several match, ask which."
    ),
    parameters={
        "type": "object",
        "properties": {
            "transaction_id": {"type": "string"},
            "reason": {
                "type": "string",
                "description": "Why, in a few words. Shown to the user.",
            },
        },
        "required": ["transaction_id"],
        "additionalProperties": False,
    },
)

ACTION_SPECS = [ASK_USER, PROPOSE_ADD, PROPOSE_EDIT, PROPOSE_DELETE]
ACTION_NAMES = {spec.name for spec in ACTION_SPECS}


# ── Building and validating proposals ────────────────────────────────────


def _find_account(snapshot: dict[str, Any], name: str) -> dict[str, Any] | None:
    accounts = snapshot.get("accounts", [])
    if not name:
        # An unambiguous single account needs no asking.
        return accounts[0] if len(accounts) == 1 else None
    lowered = name.strip().lower()
    for a in accounts:
        if (a.get("name") or "").lower() == lowered:
            return a
    for a in accounts:
        if lowered in (a.get("name") or "").lower():
            return a
    return None


def _find_transaction(snapshot: dict[str, Any], tx_id: str) -> dict[str, Any] | None:
    for t in snapshot.get("transactions", []):
        if t.get("id") == tx_id:
            return t
    return None


def _fmt(amount: float) -> str:
    return f"Rs {amount:,.0f}" if amount == int(amount) else f"Rs {amount:,.2f}"


def _valid_category(category: str, tx_type: str) -> str | None:
    allowed = INCOME_CATEGORIES if tx_type == "income" else EXPENSE_CATEGORIES
    if category in allowed:
        return category
    for c in allowed:
        if c.lower() == (category or "").lower():
            return c
    return None


def _duplicate_warning(
    snapshot: dict[str, Any], amount: float, date: str, note: str
) -> list[str]:
    """Flag a near-identical recent entry so a double-add is visible.

    Not a block: legitimately paying the same amount twice happens. The user
    decides, having been told.
    """
    for t in snapshot.get("transactions", []):
        if abs(float(t.get("amount") or 0) - amount) > 0.01:
            continue
        if t.get("date") != date:
            continue
        existing = (t.get("note") or "").lower()
        if existing and note and (existing in note.lower() or note.lower() in existing):
            return [f"Similar entry already on {t.get('date')}: {t.get('note')}"]
        return [f"Another {_fmt(amount)} entry exists on {t.get('date')}"]
    return []


def build_add(args: dict[str, Any], snapshot: dict[str, Any], today: str) -> dict[str, Any]:
    tx_type = args.get("type", "expense")
    try:
        amount = round(float(args.get("amount") or 0), 2)
    except (TypeError, ValueError):
        return {"error": "amount was not a number"}
    if amount <= 0:
        # Deliberately not abs(). Direction lives in `type`, so a negative
        # here means the model is confused about it — and silently flipping
        # the sign would turn "income -1200" into income of +1200, the exact
        # opposite of the intent. Refusing costs one retry and surfaces the
        # confusion instead of burying it.
        return {
            "error": "amount must be a positive number; direction comes from `type`",
        }

    category = _valid_category(args.get("category", ""), tx_type)
    if category is None:
        allowed = INCOME_CATEGORIES if tx_type == "income" else EXPENSE_CATEGORIES
        return {
            "error": f"'{args.get('category')}' is not a category in this app",
            "allowed": allowed,
        }

    account = _find_account(snapshot, args.get("account_name", ""))
    if account is None:
        names = [a.get("name") for a in snapshot.get("accounts", [])]
        return {
            "error": "which account? call ask_user with these options",
            "accounts": names,
        }

    date = args.get("date") or today
    note = (args.get("note") or category).strip()
    status = args.get("status") if args.get("status") in ("received", "pending") else "received"

    return {
        "id": f"prop_{uuid.uuid4().hex[:12]}",
        "kind": "add_transaction",
        "fields": {
            "type": tx_type,
            "amount": amount,
            "category": category,
            "note": note,
            "date": date,
            "accountId": account.get("id"),
            "status": status,
        },
        "summary": f"{_fmt(amount)} · {category} · {account.get('name')} · {date}",
        "warnings": _duplicate_warning(snapshot, amount, date, note),
    }


def build_edit(args: dict[str, Any], snapshot: dict[str, Any]) -> dict[str, Any]:
    tx_id = args.get("transaction_id", "")
    current = _find_transaction(snapshot, tx_id)
    if current is None:
        return {"error": f"no transaction with id '{tx_id}' in this snapshot"}

    fields: dict[str, Any] = {}
    changes: list[str] = []

    if (raw := args.get("amount")) is not None:
        try:
            amount = round(float(raw), 2)
        except (TypeError, ValueError):
            return {"error": "amount was not a number"}
        if amount <= 0:
            return {"error": "amount must be a positive number"}
        if abs(amount - float(current.get("amount") or 0)) > 0.001:
            fields["amount"] = amount
            changes.append(f"amount {_fmt(float(current['amount']))} → {_fmt(amount)}")

    if (category := args.get("category")) is not None:
        resolved = _valid_category(category, current.get("type", "expense"))
        if resolved is None:
            return {"error": f"'{category}' is not a category in this app"}
        if resolved != current.get("category"):
            fields["category"] = resolved
            changes.append(f"category {current.get('category')} → {resolved}")

    for key in ("note", "date", "status"):
        value = args.get(key)
        if value is not None and value != current.get(key):
            fields[key] = value
            changes.append(f"{key} {current.get(key)} → {value}")

    if (name := args.get("account_name")) is not None:
        account = _find_account(snapshot, name)
        if account is None:
            return {"error": f"no account called '{name}'"}
        if account.get("id") != current.get("accountId"):
            fields["accountId"] = account.get("id")
            changes.append(f"account → {account.get('name')}")

    if not fields:
        return {"error": "nothing would change; do not propose an empty edit"}

    return {
        "id": f"prop_{uuid.uuid4().hex[:12]}",
        "kind": "edit_transaction",
        "target_id": tx_id,
        "fields": fields,
        "before": {
            "amount": current.get("amount"),
            "category": current.get("category"),
            "note": current.get("note"),
            "date": current.get("date"),
            "status": current.get("status"),
        },
        "summary": "; ".join(changes),
        "changes": changes,
        "warnings": [],
    }


def build_delete(args: dict[str, Any], snapshot: dict[str, Any]) -> dict[str, Any]:
    tx_id = args.get("transaction_id", "")
    current = _find_transaction(snapshot, tx_id)
    if current is None:
        return {"error": f"no transaction with id '{tx_id}' in this snapshot"}

    warnings: list[str] = []
    # Deleting one of these unwinds derived money rules elsewhere in the app,
    # so the user is told rather than finding out from a moved balance.
    if current.get("loanId"):
        warnings.append("This settles a loan — removing it reopens that loan")
    if current.get("parentId"):
        warnings.append("This is part of a split pending income")
    if current.get("recurringId"):
        warnings.append("Auto-generated by a recurring rule; it will not come back")

    amount = float(current.get("amount") or 0)
    return {
        "id": f"prop_{uuid.uuid4().hex[:12]}",
        "kind": "delete_transaction",
        "target_id": tx_id,
        "fields": {},
        "before": {
            "amount": current.get("amount"),
            "category": current.get("category"),
            "note": current.get("note"),
            "date": current.get("date"),
            "type": current.get("type"),
        },
        "summary": (
            f"Delete {_fmt(amount)} · {current.get('category')} · "
            f"{current.get('date')}"
        ),
        "reason": args.get("reason", ""),
        "warnings": warnings,
    }


def build_proposal(
    name: str, args: dict[str, Any], snapshot: dict[str, Any], today: str
) -> dict[str, Any]:
    """Validate one write tool call into a proposal, or an error the model reads."""
    if name == "propose_add_transaction":
        return build_add(args, snapshot, today)
    if name == "propose_edit_transaction":
        return build_edit(args, snapshot)
    if name == "propose_delete_transaction":
        return build_delete(args, snapshot)
    return {"error": f"unknown action '{name}'"}


def build_question(args: dict[str, Any]) -> dict[str, Any]:
    options = [str(o) for o in (args.get("options") or []) if str(o).strip()]
    return {
        "text": (args.get("question") or "").strip(),
        "options": options[:4],
        "field": args.get("field", ""),
    }
