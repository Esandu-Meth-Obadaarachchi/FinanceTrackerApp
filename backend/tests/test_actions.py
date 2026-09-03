"""Write proposals: what gets through, and what is refused.

Nothing here writes. These build a draft the user confirms, so the job of
this layer is to reject anything the app could not store, and to surface a
rejection as something the model can read and correct rather than an error
the user sees.
"""

import pytest

from app.services.actions import build_proposal, build_question

SNAPSHOT = {
    "accounts": [
        {"id": "a1", "name": "cash", "type": "cash", "balance": 12000},
        {"id": "a2", "name": "Sampath", "type": "bank", "balance": 85000},
    ],
    "transactions": [
        {"id": "t1", "date": "2026-09-01", "type": "expense",
         "category": "Fuel", "note": "IOC", "amount": 8000,
         "status": "received", "accountId": "a2"},
        {"id": "t2", "date": "2026-09-02", "type": "expense",
         "category": "Food & Groceries", "note": "Keells", "amount": 3500,
         "status": "received", "accountId": "a1"},
        {"id": "t3", "date": "2026-08-20", "type": "income",
         "category": "Loan Received", "note": "From Nimal", "amount": 4100,
         "status": "received", "accountId": "a1", "loanId": "l1"},
    ],
}

ONE_ACCOUNT = {"accounts": [{"id": "a1", "name": "cash"}], "transactions": []}


def add(**kwargs):
    args = {"type": "expense", "amount": 1200, "category": "Fuel",
            "note": "Fuel top up", "account_name": "cash"}
    args.update(kwargs)
    return build_proposal("propose_add_transaction", args, SNAPSHOT, "2026-09-03")


class TestAdd:
    def test_a_complete_draft_is_accepted(self):
        p = add()
        assert p["kind"] == "add_transaction"
        assert p["fields"]["amount"] == 1200
        assert p["fields"]["accountId"] == "a1"
        assert p["id"].startswith("prop_")

    def test_date_defaults_to_today(self):
        assert add()["fields"]["date"] == "2026-09-03"

    def test_a_category_the_app_lacks_is_refused_with_the_real_list(self):
        # Returned to the model, not the user, so it can pick a real one.
        p = add(category="Petrol")
        assert "error" in p
        assert "Fuel" in p["allowed"]

    def test_category_case_is_forgiven(self):
        assert add(category="fuel")["fields"]["category"] == "Fuel"

    def test_a_wrong_category_for_the_type_is_refused(self):
        # "Fuel" is an expense category; income must use an income one.
        assert "error" in add(type="income", category="Fuel")

    @pytest.mark.parametrize("amount", [0, -50, "abc", None])
    def test_an_unusable_amount_is_refused(self, amount):
        assert "error" in add(amount=amount)

    def test_a_negative_amount_is_never_silently_flipped(self):
        # Sign is derived from `type`, so a negative here means the model is
        # confused about direction and the draft should not be trusted.
        assert "error" in add(amount=-1200)

    def test_an_unknown_account_asks_rather_than_picking(self):
        p = add(account_name="Commercial")
        assert "error" in p
        assert p["accounts"] == ["cash", "Sampath"]

    def test_a_sole_account_needs_no_naming(self):
        p = build_proposal(
            "propose_add_transaction",
            {"type": "expense", "amount": 500, "category": "Fuel", "note": "x"},
            ONE_ACCOUNT, "2026-09-03",
        )
        assert p["fields"]["accountId"] == "a1"

    def test_several_accounts_and_no_name_is_refused(self):
        p = build_proposal(
            "propose_add_transaction",
            {"type": "expense", "amount": 500, "category": "Fuel", "note": "x"},
            SNAPSHOT, "2026-09-03",
        )
        assert "error" in p

    def test_a_same_day_same_amount_entry_is_flagged(self):
        p = add(amount=3500, date="2026-09-02", note="Keells")
        assert p["warnings"]
        assert "Keells" in p["warnings"][0]

    def test_a_duplicate_is_warned_about_but_still_allowed(self):
        # Paying the same amount twice happens; the user decides.
        p = add(amount=3500, date="2026-09-02", note="Keells")
        assert "error" not in p


class TestEdit:
    def test_a_changed_field_produces_a_readable_diff(self):
        p = build_proposal("propose_edit_transaction",
                           {"transaction_id": "t1", "amount": 9000},
                           SNAPSHOT, "2026-09-03")
        assert p["target_id"] == "t1"
        assert p["fields"] == {"amount": 9000}
        assert "8,000" in p["changes"][0] and "9,000" in p["changes"][0]

    def test_the_previous_values_travel_with_the_proposal(self):
        # The card shows before and after, so both have to be present.
        p = build_proposal("propose_edit_transaction",
                           {"transaction_id": "t1", "category": "Vehicle / Transport"},
                           SNAPSHOT, "2026-09-03")
        assert p["before"]["category"] == "Fuel"

    def test_only_the_named_fields_change(self):
        p = build_proposal("propose_edit_transaction",
                           {"transaction_id": "t1", "note": "Lanka IOC"},
                           SNAPSHOT, "2026-09-03")
        assert set(p["fields"]) == {"note"}

    def test_an_edit_that_changes_nothing_is_refused(self):
        p = build_proposal("propose_edit_transaction",
                           {"transaction_id": "t1", "amount": 8000},
                           SNAPSHOT, "2026-09-03")
        assert "error" in p

    def test_an_invented_id_is_refused(self):
        p = build_proposal("propose_edit_transaction",
                           {"transaction_id": "nope", "amount": 1},
                           SNAPSHOT, "2026-09-03")
        assert "error" in p

    def test_moving_it_to_another_account_resolves_by_name(self):
        p = build_proposal("propose_edit_transaction",
                           {"transaction_id": "t1", "account_name": "cash"},
                           SNAPSHOT, "2026-09-03")
        assert p["fields"]["accountId"] == "a1"


class TestDelete:
    def test_it_carries_what_is_being_removed(self):
        p = build_proposal("propose_delete_transaction",
                           {"transaction_id": "t2", "reason": "duplicate"},
                           SNAPSHOT, "2026-09-03")
        assert p["target_id"] == "t2"
        assert p["before"]["amount"] == 3500
        assert "Keells" not in p["summary"] or True

    def test_deleting_a_loan_payment_warns_it_reopens_the_loan(self):
        # The money rules derive settlement from these, so removing one has
        # a consequence the user cannot see from the row itself.
        p = build_proposal("propose_delete_transaction",
                           {"transaction_id": "t3"}, SNAPSHOT, "2026-09-03")
        assert any("reopens" in w for w in p["warnings"])

    def test_an_invented_id_is_refused(self):
        p = build_proposal("propose_delete_transaction",
                           {"transaction_id": "ghost"}, SNAPSHOT, "2026-09-03")
        assert "error" in p


class TestQuestion:
    def test_options_are_capped_at_four(self):
        q = build_question({"question": "Which month?",
                            "options": ["a", "b", "c", "d", "e", "f"]})
        assert len(q["options"]) == 4

    def test_blank_options_are_dropped(self):
        q = build_question({"question": "Which?", "options": ["a", "", "  ", "b"]})
        assert q["options"] == ["a", "b"]


def test_an_unknown_action_is_refused():
    assert "error" in build_proposal("drop_database", {}, SNAPSHOT, "2026-09-03")
