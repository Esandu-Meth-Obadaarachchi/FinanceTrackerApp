"""The agent's toolbox, executed over a client-supplied snapshot.

The client uploads its financial data with the question and the tools filter
and aggregate it here. That keeps the backend free of Firestore credentials
entirely: it never reaches into anyone's data, it only sees what the device
chose to send for this one question.

Every tool is a pure function of (snapshot, arguments), so the whole toolbox
is testable without a model or a network.
"""

from __future__ import annotations

from collections import defaultdict
from typing import Any

from ..providers.base import ToolSpec

# ── Schemas ──────────────────────────────────────────────────────────────

TOOL_SPECS: list[ToolSpec] = [
    ToolSpec(
        name="query_transactions",
        description=(
            "Find transactions matching filters. Use for questions about "
            "specific spending, dates, categories or accounts. Returns at "
            "most 50 rows, newest first."
        ),
        parameters={
            "type": "object",
            "properties": {
                "start_date": {
                    "type": "string",
                    "description": "Earliest date, YYYY-MM-DD inclusive.",
                },
                "end_date": {
                    "type": "string",
                    "description": "Latest date, YYYY-MM-DD inclusive.",
                },
                "type": {
                    "type": "string",
                    "enum": ["income", "expense", "transfer"],
                },
                "category": {"type": "string"},
                "account_name": {"type": "string"},
                "note_contains": {"type": "string"},
                "status": {"type": "string", "enum": ["received", "pending"]},
            },
        },
    ),
    ToolSpec(
        name="aggregate_spending",
        description=(
            "Total amounts grouped by category, month or account. Use for "
            "'how much did I spend on X', trends and comparisons."
        ),
        parameters={
            "type": "object",
            "properties": {
                "group_by": {
                    "type": "string",
                    "enum": ["category", "month", "account", "type"],
                },
                "type": {
                    "type": "string",
                    "enum": ["income", "expense", "transfer"],
                },
                "start_date": {"type": "string"},
                "end_date": {"type": "string"},
            },
            "required": ["group_by"],
        },
    ),
    ToolSpec(
        name="get_accounts",
        description="List every account with its current balance.",
        parameters={"type": "object", "properties": {}},
    ),
    ToolSpec(
        name="get_loans",
        description=(
            "Money lent to or borrowed from people, with how much is still "
            "outstanding on each."
        ),
        parameters={
            "type": "object",
            "properties": {
                "loan_type": {"type": "string", "enum": ["lent", "borrowed"]},
                "only_outstanding": {"type": "boolean"},
            },
        },
    ),
    ToolSpec(
        name="get_pending_income",
        description="Income invoiced or expected but not yet received.",
        parameters={"type": "object", "properties": {}},
    ),
    ToolSpec(
        name="get_budget",
        description=(
            "The monthly plan: planned income, per-category allocations and "
            "actual spend against each."
        ),
        parameters={"type": "object", "properties": {}},
    ),
]

TOOL_NAMES = {spec.name for spec in TOOL_SPECS}


# ── Helpers ──────────────────────────────────────────────────────────────


def _in_range(date: str, start: str | None, end: str | None) -> bool:
    # Dates are YYYY-MM-DD, so string comparison is date comparison.
    if start and date < start:
        return False
    if end and date > end:
        return False
    return True


def _account_names(snapshot: dict[str, Any]) -> dict[str, str]:
    return {a.get("id", ""): a.get("name", "") for a in snapshot.get("accounts", [])}


def _matches(tx: dict[str, Any], args: dict[str, Any], names: dict[str, str]) -> bool:
    if not _in_range(tx.get("date", ""), args.get("start_date"), args.get("end_date")):
        return False
    if (t := args.get("type")) and tx.get("type") != t:
        return False
    if (c := args.get("category")) and c.lower() not in tx.get("category", "").lower():
        return False
    if (s := args.get("status")) and tx.get("status") != s:
        return False
    if note := args.get("note_contains"):
        if note.lower() not in tx.get("note", "").lower():
            return False
    if account := args.get("account_name"):
        actual = names.get(tx.get("accountId", ""), "")
        if account.lower() not in actual.lower():
            return False
    return True


# ── Tool implementations ─────────────────────────────────────────────────


def _query_transactions(snapshot: dict[str, Any], args: dict[str, Any]) -> Any:
    names = _account_names(snapshot)
    rows = [t for t in snapshot.get("transactions", []) if _matches(t, args, names)]
    rows.sort(key=lambda t: t.get("date", ""), reverse=True)
    trimmed = [
        {
            "id": t.get("id"),
            "date": t.get("date"),
            "type": t.get("type"),
            "category": t.get("category"),
            "note": t.get("note"),
            "amount": t.get("amount"),
            "status": t.get("status"),
            "account": names.get(t.get("accountId", ""), "Unknown"),
        }
        for t in rows[:50]
    ]
    return {"count": len(rows), "returned": len(trimmed), "transactions": trimmed}


def _aggregate_spending(snapshot: dict[str, Any], args: dict[str, Any]) -> Any:
    names = _account_names(snapshot)
    group_by = args.get("group_by", "category")
    totals: dict[str, float] = defaultdict(float)
    counts: dict[str, int] = defaultdict(int)

    for tx in snapshot.get("transactions", []):
        if not _in_range(
            tx.get("date", ""), args.get("start_date"), args.get("end_date")
        ):
            continue
        if (t := args.get("type")) and tx.get("type") != t:
            continue
        # Pending income has not arrived, so it never counts as a total.
        if tx.get("type") == "income" and tx.get("status") == "pending":
            continue

        if group_by == "category":
            key = tx.get("category", "Uncategorised")
        elif group_by == "month":
            key = (tx.get("date") or "")[:7]
        elif group_by == "account":
            key = names.get(tx.get("accountId", ""), "Unknown")
        else:
            key = tx.get("type", "unknown")

        totals[key] += float(tx.get("amount") or 0)
        counts[key] += 1

    ranked = sorted(totals.items(), key=lambda kv: kv[1], reverse=True)
    return {
        "group_by": group_by,
        "total": round(sum(totals.values()), 2),
        "groups": [
            {"key": k, "total": round(v, 2), "count": counts[k]} for k, v in ranked
        ],
    }


def _get_accounts(snapshot: dict[str, Any], args: dict[str, Any]) -> Any:
    return {
        "accounts": [
            {
                "name": a.get("name"),
                "type": a.get("type"),
                "balance": a.get("balance"),
            }
            for a in snapshot.get("accounts", [])
        ],
        "total_balance": round(
            sum(float(a.get("balance") or 0) for a in snapshot.get("accounts", [])), 2
        ),
    }


def _get_loans(snapshot: dict[str, Any], args: dict[str, Any]) -> Any:
    loans = snapshot.get("loans", [])
    if lt := args.get("loan_type"):
        loans = [l for l in loans if l.get("loanType") == lt]
    if args.get("only_outstanding"):
        loans = [l for l in loans if float(l.get("outstanding") or 0) > 0]
    return {
        "loans": [
            {
                "who": l.get("who"),
                "type": l.get("loanType"),
                "original_amount": l.get("amount"),
                "outstanding": l.get("outstanding"),
                "reason": l.get("reason"),
                "date": l.get("date"),
            }
            for l in loans
        ]
    }


def _get_pending_income(snapshot: dict[str, Any], args: dict[str, Any]) -> Any:
    pending = [
        t
        for t in snapshot.get("transactions", [])
        if t.get("type") == "income" and t.get("status") == "pending"
    ]
    pending.sort(key=lambda t: t.get("date", ""))
    return {
        "total": round(sum(float(t.get("amount") or 0) for t in pending), 2),
        "items": [
            {
                "date": t.get("date"),
                "category": t.get("category"),
                "note": t.get("note"),
                "amount": t.get("amount"),
            }
            for t in pending
        ],
    }


def _get_budget(snapshot: dict[str, Any], args: dict[str, Any]) -> Any:
    budget = snapshot.get("budget") or {}
    if not budget:
        return {"has_plan": False}
    allocations = budget.get("allocations") or {}
    month = budget.get("month", "")
    spent: dict[str, float] = defaultdict(float)
    for tx in snapshot.get("transactions", []):
        if tx.get("type") == "expense" and (tx.get("date") or "").startswith(month):
            spent[tx.get("category", "")] += float(tx.get("amount") or 0)

    return {
        "has_plan": True,
        "month": month,
        "planned_income": budget.get("plannedIncome"),
        "categories": [
            {
                "category": cat,
                "planned": planned,
                "spent": round(spent.get(cat, 0), 2),
                "remaining": round(float(planned) - spent.get(cat, 0), 2),
            }
            for cat, planned in allocations.items()
        ],
    }


_HANDLERS = {
    "query_transactions": _query_transactions,
    "aggregate_spending": _aggregate_spending,
    "get_accounts": _get_accounts,
    "get_loans": _get_loans,
    "get_pending_income": _get_pending_income,
    "get_budget": _get_budget,
}


def run_tool(name: str, arguments: dict[str, Any], snapshot: dict[str, Any]) -> Any:
    """Execute one tool. Unknown names return an error the model can read."""
    handler = _HANDLERS.get(name)
    if handler is None:
        return {"error": f"unknown tool '{name}'", "available": sorted(TOOL_NAMES)}
    try:
        return handler(snapshot, arguments or {})
    except Exception as exc:  # surfaced to the model, not the user
        return {"error": f"{type(exc).__name__}: {exc}"}
