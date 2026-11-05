"""The agentic loop: read, then answer, ask, or propose a write.

A turn ends one of four ways. Reading keeps the loop going; the other three
stop it dead:

  answer     the model wrote prose
  question   it called ask_user and is waiting on you
  proposal   it called a write tool and is waiting for Apply

Only reading consumes an iteration, which is what makes a 3-iteration budget
workable. A write or a clarification costs one model call, not three.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass, field
from typing import Any

from ..providers.base import ToolResult, Turn
from ..providers.router import ProviderRouter
from .actions import ACTION_NAMES, ACTION_SPECS, build_proposal, build_question
from .tools import TOOL_SPECS, run_tool

log = logging.getLogger(__name__)

# Only read tools spend this. Terminal tools end the turn immediately, so in
# practice a question or a write costs one call.
MAX_ITERATIONS = 3

SYSTEM = """You are the money assistant inside FinTrack, a personal finance \
app used by one person in Sri Lanka. All amounts are Sri Lankan rupees (LKR), \
written as "Rs 12,345".

You work by calling tools. Never guess at a number: if a figure is not in a \
tool result, call another tool or say you do not have it. Do not invent \
transactions, balances or dates.

WHAT YOU CAN DO
- Answer questions about their money, using the read tools.
- Add, change or delete a transaction, using the propose_* tools. These do \
not save anything. The user sees exactly what you propose and taps Apply.
- Ask one short question with ask_user when you genuinely need to.

CALLING TOOLS
- Call every tool you need for a question in ONE turn. You have very few \
turns, so do not fetch one thing, think, then fetch another when both could \
have been asked for together.
- To change or delete something, find it with query_transactions first and \
use the `id` it returns. Never invent an id.
- If several transactions match what the user described, ask which one \
rather than picking.

WHEN TO ASK, AND WHEN NOT TO
Use ask_user ONLY when you can offer 2 to 4 concrete options the user can \
tap, and the answer would genuinely change your reply.

Two cases where you MUST ask rather than assume:
1. A question about a total, an amount or a comparison that names no time \
period. "What is my income?", "how much do I spend on food?" and "what did I \
earn?" are all ambiguous, because the answer for this month, last month and \
this year are different numbers. Ask with options like [This month] \
[Last month] [This year]. Do not answer with an all-time total and do not \
pick a period silently.
2. Which account something came from or went into, when the user holds more \
than one and did not say. Call get_accounts first so your options are their \
real account names.

Otherwise, do NOT ask. If you cannot list concrete options, assume the most \
likely reading, say the assumption in one short clause, and answer anyway. \
Asking a vague open question is worse than a stated assumption.
Never ask two questions at once. Never ask for something a tool would tell \
you. Once the user has given you a period, do not ask again in that \
conversation — carry it forward.

HOW TO WRITE YOUR REPLY
- Lead with the number or the direct answer, then a short line of context.
- Keep it to a few sentences. This is read on a phone.
- Plain text only. No markdown, no asterisks, no bullets, no headings. The \
app shows your reply as-is, so "**Rs 14,500**" displays the asterisks.
- Round naturally in prose ("about Rs 45,000"), stay exact when asked for a \
precise figure.
- Pending income has not arrived. Never count it as money in hand.
- A lent loan is money owed to the user. A borrowed loan is money they owe.

Today's date is {today}."""

_RESUME = """

The user is answering your question "{asked}". Treat their message as that \
answer and carry on with what you were doing. Details you already have: \
{collected}"""


def _account_question(rejection: dict[str, Any]) -> dict[str, Any]:
    """Turn an account rejection into a question the user answers with a tap."""
    names = [n for n in rejection.get("accounts", []) if n]
    wanted = (rejection.get("asked_for") or "").strip()
    if not names:
        return {
            "text": "You have no accounts yet. Add one under Accounts, then ask again.",
            "options": [],
            "field": "account",
        }
    if wanted:
        text = f"I don't see an account called {wanted}. Which one should I use?"
    else:
        text = "Which account should this go to?"
    # More than four accounts cannot all be chips; the first four are offered
    # and the rest are reachable by typing the name.
    return {"text": text, "options": names[:4], "field": "account"}


@dataclass
class AgentReply:
    """One turn's outcome. `kind` says which of the three shapes this is."""

    kind: str = "answer"  # answer | question | proposal
    answer: str = ""
    provider: str = ""
    tool_calls: list[dict[str, Any]] = field(default_factory=list)
    iterations: int = 0
    question: dict[str, Any] | None = None
    proposal: dict[str, Any] | None = None
    state: dict[str, Any] = field(default_factory=dict)


def _rebuild_turns(
    history: list[dict[str, str]] | None, question: str
) -> list[Turn]:
    turns: list[Turn] = []
    for message in history or []:
        role = message.get("role", "user")
        text = (message.get("content") or "").strip()
        if text and role in ("user", "assistant"):
            turns.append(Turn(role=role, text=text))
    turns.append(Turn(role="user", text=question))
    return turns


async def run_agent(
    router: ProviderRouter,
    *,
    question: str,
    snapshot: dict[str, Any],
    history: list[dict[str, str]] | None = None,
    state: dict[str, Any] | None = None,
    today: str = "",
) -> AgentReply:
    """Answer, ask, or propose. `state` is the client's echo of the last turn."""

    turns = _rebuild_turns(history, question)
    system = SYSTEM.format(today=today or "unknown")

    # Resuming a clarification. Chat history alone would leave the model to
    # re-infer its own half-finished intent from prose, which is exactly where
    # these loops go wrong, so the intent is restated explicitly.
    pending = (state or {}).get("pending") or {}
    if pending.get("asked"):
        system += _RESUME.format(
            asked=pending.get("asked", ""),
            collected=pending.get("collected") or "none yet",
        )

    all_tools = TOOL_SPECS + ACTION_SPECS
    used: list[dict[str, Any]] = []
    provider = ""

    for iteration in range(1, MAX_ITERATIONS + 1):
        response = await router.complete(
            system=system, turns=turns, tools=all_tools, max_tokens=4096
        )
        provider = response.provider

        if not response.wants_tools:
            return AgentReply(
                kind="answer",
                answer=response.text or "I could not work that one out.",
                provider=provider,
                tool_calls=used,
                iterations=iteration,
            )

        # A terminal tool ends the turn. If the model asked for one alongside
        # reads, the terminal one wins: it is the thing it actually decided.
        terminal = next(
            (c for c in response.tool_calls if c.name in ACTION_NAMES), None
        )
        if terminal is not None:
            used.append({"tool": terminal.name, "arguments": terminal.arguments})

            if terminal.name == "ask_user":
                asked = build_question(terminal.arguments)
                return AgentReply(
                    kind="question",
                    answer=asked["text"],
                    provider=provider,
                    tool_calls=used,
                    iterations=iteration,
                    question=asked,
                    state={
                        "pending": {
                            "asked": asked["text"],
                            "field": asked.get("field", ""),
                            "collected": pending.get("collected") or {},
                        }
                    },
                )

            proposal = build_proposal(
                terminal.name, terminal.arguments, snapshot, today
            )
            if "error" not in proposal:
                return AgentReply(
                    kind="proposal",
                    answer=response.text
                    or "Check these details and tap Apply if they look right.",
                    provider=provider,
                    tool_calls=used,
                    iterations=iteration,
                    proposal=proposal,
                )

            # A draft that only lacks a usable account is not worth a model
            # round trip. The fix is a tap, so ask for it here. Leaving it to
            # the model burned the iteration budget on retries, and what came
            # out the far end was prose with no chips and no Apply card.
            if proposal.get("needs") == "account":
                asked = _account_question(proposal)
                return AgentReply(
                    kind="question" if asked["options"] else "answer",
                    answer=asked["text"],
                    provider=provider,
                    tool_calls=used,
                    iterations=iteration,
                    question=asked if asked["options"] else None,
                    state={
                        "pending": {
                            "asked": asked["text"],
                            "field": "account",
                            "collected": {
                                "action": terminal.name,
                                "draft": terminal.arguments,
                            },
                        }
                    }
                    if asked["options"]
                    else {},
                )

            # A rejected draft goes back as a tool result so the model can fix
            # it, rather than surfacing a validation error to the user.
            turns.append(
                Turn(role="assistant", text=response.text, tool_calls=[terminal])
            )
            turns.append(
                Turn(
                    role="tool",
                    tool_results=[
                        ToolResult(
                            id=terminal.id,
                            name=terminal.name,
                            content=proposal,
                            is_error=True,
                        )
                    ],
                )
            )
            continue

        turns.append(
            Turn(
                role="assistant",
                text=response.text,
                tool_calls=response.tool_calls,
            )
        )
        results: list[ToolResult] = []
        for call in response.tool_calls:
            output = run_tool(call.name, call.arguments, snapshot)
            used.append({"tool": call.name, "arguments": call.arguments})
            log.info("tool %s(%s)", call.name, call.arguments)
            results.append(
                ToolResult(
                    id=call.id,
                    name=call.name,
                    content=output,
                    is_error=isinstance(output, dict) and "error" in output,
                )
            )
        turns.append(Turn(role="tool", tool_results=results))

    # Out of read iterations: one more call with no tools, answering from what
    # was already gathered. A hard question degrades to a partial answer.
    final = await router.complete(
        system=system
        + "\n\nAnswer now using what the tools already returned. You cannot "
        "propose or save anything in this reply, so never tell the user to "
        "tap Apply or say something was added. If they wanted a change, say "
        "what you still need from them.",
        turns=turns,
        max_tokens=2048,
    )
    return AgentReply(
        kind="answer",
        answer=final.text or "I could not work that one out.",
        provider=final.provider or provider,
        tool_calls=used,
        iterations=MAX_ITERATIONS,
    )
