"""The agent's toolbox is a pure function of (snapshot, arguments), so its
filtering and totalling can be pinned down without a model or a network."""

import pytest

from app.services.tools import TOOL_NAMES, run_tool

SNAPSHOT = {
    "accounts": [
        {"id": "a1", "name": "cash", "type": "cash", "balance": 12000},
        {"id": "a2", "name": "Sampath", "type": "bank", "balance": 85000},
    ],
    "transactions": [
        {"date": "2026-08-02", "type": "expense", "category": "Fuel",
         "note": "IOC", "amount": 8000, "status": "received", "accountId": "a2"},
        {"date": "2026-08-11", "type": "expense", "category": "Fuel",
         "note": "Lanka IOC", "amount": 6500, "status": "received", "accountId": "a2"},
        {"date": "2026-07-05", "type": "expense", "category": "Fuel",
         "note": "IOC", "amount": 7200, "status": "received", "accountId": "a2"},
        {"date": "2026-08-20", "type": "income", "category": "Freelance / Contract",
         "note": "SLT invoice", "amount": 45000, "status": "pending", "accountId": "a2"},
        {"date": "2026-08-25", "type": "income", "category": "Employment Income",
         "note": "Salary", "amount": 90000, "status": "received", "accountId": "a2"},
    ],
    "loans": [
        {"who": "Nimal", "loanType": "lent", "amount": 14529, "outstanding": 10429},
        {"who": "dad", "loanType": "borrowed", "amount": 500, "outstanding": 0},
    ],
    "budget": {
        "month": "2026-08",
        "plannedIncome": 120000,
        "allocations": {"Fuel": 15000},
    },
}


class TestQueryTransactions:
    def test_date_range_is_inclusive_on_both_ends(self):
        out = run_tool(
            "query_transactions",
            {"start_date": "2026-08-01", "end_date": "2026-08-11"},
            SNAPSHOT,
        )
        assert {t["date"] for t in out["transactions"]} == {"2026-08-02", "2026-08-11"}

    def test_filters_by_category_and_account(self):
        out = run_tool(
            "query_transactions", {"category": "Fuel", "account_name": "Sampath"}, SNAPSHOT
        )
        assert out["count"] == 3

    def test_newest_first(self):
        out = run_tool("query_transactions", {"type": "expense"}, SNAPSHOT)
        dates = [t["date"] for t in out["transactions"]]
        assert dates == sorted(dates, reverse=True)


class TestAggregate:
    def test_totals_by_category_within_a_month(self):
        out = run_tool(
            "aggregate_spending",
            {"group_by": "category", "type": "expense",
             "start_date": "2026-08-01", "end_date": "2026-08-31"},
            SNAPSHOT,
        )
        assert out["total"] == 14500  # July's 7,200 is outside the range

    def test_pending_income_is_never_counted(self):
        # It has not arrived, so treating it as income would overstate things.
        out = run_tool("aggregate_spending", {"group_by": "type", "type": "income"}, SNAPSHOT)
        assert out["total"] == 90000

    def test_groups_are_ranked_by_size(self):
        out = run_tool("aggregate_spending", {"group_by": "month"}, SNAPSHOT)
        totals = [g["total"] for g in out["groups"]]
        assert totals == sorted(totals, reverse=True)


class TestLoansAndIncome:
    def test_only_outstanding_drops_settled_loans(self):
        out = run_tool("get_loans", {"only_outstanding": True}, SNAPSHOT)
        assert [l["who"] for l in out["loans"]] == ["Nimal"]

    def test_filter_by_direction(self):
        out = run_tool("get_loans", {"loan_type": "borrowed"}, SNAPSHOT)
        assert [l["who"] for l in out["loans"]] == ["dad"]

    def test_pending_income_totals_only_pending(self):
        out = run_tool("get_pending_income", {}, SNAPSHOT)
        assert out["total"] == 45000
        assert len(out["items"]) == 1


class TestBudget:
    def test_spend_is_measured_against_the_plan_month(self):
        out = run_tool("get_budget", {}, SNAPSHOT)
        fuel = next(c for c in out["categories"] if c["category"] == "Fuel")
        assert fuel["spent"] == 14500
        assert fuel["remaining"] == 500

    def test_reports_when_no_plan_exists(self):
        assert run_tool("get_budget", {}, {"transactions": []})["has_plan"] is False


class TestSafety:
    def test_unknown_tool_returns_a_readable_error(self):
        out = run_tool("drop_everything", {}, SNAPSHOT)
        assert "error" in out
        assert out["available"] == sorted(TOOL_NAMES)

    def test_a_broken_snapshot_does_not_raise(self):
        # A malformed snapshot must surface to the model, not 500 the request.
        out = run_tool("aggregate_spending", {"group_by": "category"},
                       {"transactions": [{"amount": "not-a-number"}]})
        assert "error" in out

    @pytest.mark.parametrize("name", sorted(TOOL_NAMES))
    def test_every_tool_runs_on_an_empty_snapshot(self, name):
        assert run_tool(name, {"group_by": "category"}, {}) is not None
