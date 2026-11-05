"""The agent loop, driven by a scripted model so it never touches the network.

These pin the failure seen live: asked to add income to an account that does
not exist, the model proposed a draft twice, both were rejected, the iteration
budget ran out, and what the user got was prose with no chips and no Apply card.
"""

from app.providers.base import LLMResponse, ToolCall
from app.services.agent import run_agent

SNAPSHOT = {
    "accounts": [
        {"id": "a1", "name": "Commercial Bank"},
        {"id": "a2", "name": "Cash"},
    ],
    "transactions": [],
}


class ScriptedRouter:
    """Plays back canned responses and records how many calls were made."""

    def __init__(self, *responses):
        self._responses = list(responses)
        self.calls = 0
        self.systems: list[str] = []

    async def complete(self, *, system, turns, tools=None, max_tokens=0):
        self.calls += 1
        self.systems.append(system)
        return self._responses.pop(0)


def propose(account_name, call_id="c1"):
    return LLMResponse(
        text="",
        provider="fake",
        tool_calls=[
            ToolCall(
                id=call_id,
                name="propose_add_transaction",
                arguments={
                    "type": "income",
                    "amount": 5000,
                    "category": "Employment Income",
                    "note": "Salary",
                    "account_name": account_name,
                },
            )
        ],
    )


async def test_an_unknown_account_becomes_a_tappable_question():
    router = ScriptedRouter(propose("Savings"))
    reply = await run_agent(
        router, question="add 5000 salary to Savings", snapshot=SNAPSHOT,
        today="2026-11-05",
    )

    assert reply.kind == "question"
    assert reply.question["options"] == ["Commercial Bank", "Cash"]
    assert "Savings" in reply.answer
    assert reply.proposal is None
    # No retry round trip: the rejection is answered locally.
    assert router.calls == 1


async def test_the_draft_is_kept_in_state_for_the_next_turn():
    router = ScriptedRouter(propose("Savings"))
    reply = await run_agent(
        router, question="add 5000 salary to Savings", snapshot=SNAPSHOT,
        today="2026-11-05",
    )

    pending = reply.state["pending"]
    assert pending["field"] == "account"
    assert pending["collected"]["draft"]["amount"] == 5000


async def test_naming_no_account_among_several_asks_which():
    router = ScriptedRouter(propose(""))
    reply = await run_agent(
        router, question="add 5000 salary", snapshot=SNAPSHOT, today="2026-11-05"
    )

    assert reply.kind == "question"
    assert reply.answer == "Which account should this go to?"


async def test_answering_the_question_reaches_a_proposal_with_a_card():
    router = ScriptedRouter(propose("Cash"))
    reply = await run_agent(
        router,
        question="Cash",
        snapshot=SNAPSHOT,
        history=[
            {"role": "user", "content": "add 5000 salary to Savings"},
            {"role": "assistant", "content": "Which account?"},
        ],
        state={"pending": {"asked": "Which account?", "collected": {}}},
        today="2026-11-05",
    )

    assert reply.kind == "proposal"
    assert reply.proposal["fields"]["accountId"] == "a2"


async def test_no_accounts_at_all_says_so_instead_of_offering_chips():
    router = ScriptedRouter(propose("Savings"))
    reply = await run_agent(
        router, question="add 5000 salary", snapshot={"accounts": []},
        today="2026-11-05",
    )

    assert reply.kind == "answer"
    assert reply.question is None
    assert "no accounts" in reply.answer.lower()


async def test_the_final_no_tools_call_is_told_not_to_mention_apply():
    # Three rejections that are not about the account burn the whole budget.
    bad = lambda i: LLMResponse(
        text="",
        provider="fake",
        tool_calls=[
            ToolCall(
                id=f"c{i}",
                name="propose_add_transaction",
                arguments={"type": "income", "amount": -1, "category": "Employment Income",
                           "account_name": "Cash"},
            )
        ],
    )
    router = ScriptedRouter(
        bad(1), bad(2), bad(3), LLMResponse(text="Sorry.", provider="fake")
    )
    reply = await run_agent(
        router, question="add salary", snapshot=SNAPSHOT, today="2026-11-05"
    )

    assert reply.kind == "answer"
    assert router.calls == 4
    assert "never tell the user to tap Apply" in router.systems[-1]


# ── Asking for the note with buttons ─────────────────────────────────────

WITH_NOTES = {
    **SNAPSHOT,
    "notePresets": {"income": ["Tehan class", "Freelance design"]},
}


def propose_income(**extra):
    args = {"type": "income", "amount": 5000, "category": "Employment Income",
            "account_name": "Cash", **extra}
    return LLMResponse(
        text="", provider="fake",
        tool_calls=[ToolCall(id="c1", name="propose_add_transaction", arguments=args)],
    )


async def test_a_missing_note_is_asked_with_the_saved_notes_as_buttons():
    router = ScriptedRouter(propose_income())
    reply = await run_agent(
        router, question="add 5000 income", snapshot=WITH_NOTES, today="2026-11-05"
    )

    assert reply.kind == "question"
    assert reply.question["options"] == ["Tehan class", "Freelance design", "No note"]
    assert reply.state["pending"]["field"] == "note"
    assert router.calls == 1


async def test_tapping_a_saved_note_reaches_the_card():
    router = ScriptedRouter(propose_income(note="Tehan class"))
    reply = await run_agent(
        router, question="Tehan class", snapshot=WITH_NOTES, today="2026-11-05",
        state={"pending": {"field": "note", "asked": "What's this for?",
                           "collected": {}}},
    )

    assert reply.kind == "proposal"
    assert reply.proposal["fields"]["note"] == "Tehan class"


async def test_the_note_question_is_never_asked_twice():
    # The model forgets the note again after being answered; the user is not
    # asked a second time and the entry falls back to its category.
    router = ScriptedRouter(propose_income())
    reply = await run_agent(
        router, question="No note", snapshot=WITH_NOTES, today="2026-11-05",
        state={"pending": {"field": "note", "asked": "What's this for?",
                           "collected": {}}},
    )

    assert reply.kind == "proposal"
    assert reply.proposal["fields"]["note"] == "Employment Income"


async def test_the_system_prompt_forbids_asking_for_a_yes():
    router = ScriptedRouter(LLMResponse(text="Hello", provider="fake"))
    await run_agent(router, question="hi", snapshot=SNAPSHOT, today="2026-11-05")
    assert "Never write a question that expects" in router.systems[0]
