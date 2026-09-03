"""The agentic loop: think, call tools, read results, repeat, answer."""

from __future__ import annotations

import logging
from dataclasses import dataclass, field
from typing import Any

from ..providers.base import ToolResult, Turn
from ..providers.router import ProviderRouter
from .tools import TOOL_SPECS, run_tool

log = logging.getLogger(__name__)

MAX_ITERATIONS = 6

SYSTEM = """You are the money assistant inside FinTrack, a personal finance \
app used by one person in Sri Lanka. All amounts are Sri Lankan rupees (LKR), \
written as "Rs 12,345".

You answer questions about the user's own finances by calling tools. Never \
guess at a number: if a figure is not in a tool result, call another tool or \
say you do not have it. Do not invent transactions, balances or dates.

How to answer:
- Lead with the number or the direct answer, then a short line of context.
- Keep it to a few sentences. This is read on a phone.
- Write plain text. No markdown, no asterisks, no bullet characters, no \
headings. The app renders your reply as-is, so "**Rs 14,500**" shows the \
asterisks to the user.
- Round naturally in prose ("about Rs 45,000"), but stay exact when the user \
asks for a precise figure.
- Compare against the previous period when it makes the answer more useful.
- If the question is vague, make a reasonable assumption, state it in one \
clause, and answer anyway rather than asking a follow-up.
- Pending income has not arrived yet. Never count it as money in hand.
- A lent loan is money owed to the user. A borrowed loan is money they owe.

Today's date is {today}."""


@dataclass
class AgentReply:
    answer: str
    provider: str = ""
    tool_calls: list[dict[str, Any]] = field(default_factory=list)
    iterations: int = 0


async def run_agent(
    router: ProviderRouter,
    *,
    question: str,
    snapshot: dict[str, Any],
    history: list[dict[str, str]] | None = None,
    today: str = "",
) -> AgentReply:
    """Answer `question` about `snapshot`, calling tools as needed."""

    turns: list[Turn] = []
    for message in history or []:
        role = message.get("role", "user")
        text = message.get("content", "")
        if text and role in ("user", "assistant"):
            turns.append(Turn(role=role, text=text))
    turns.append(Turn(role="user", text=question))

    system = SYSTEM.format(today=today or "unknown")
    used: list[dict[str, Any]] = []
    provider = ""

    for iteration in range(1, MAX_ITERATIONS + 1):
        response = await router.complete(
            system=system,
            turns=turns,
            tools=TOOL_SPECS,
            max_tokens=4096,
        )
        provider = response.provider

        if not response.wants_tools:
            return AgentReply(
                answer=response.text or "I could not work that one out.",
                provider=provider,
                tool_calls=used,
                iterations=iteration,
            )

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

    # Out of iterations: ask for a final answer with no tools on offer.
    final = await router.complete(
        system=system + "\n\nAnswer now using what the tools already returned.",
        turns=turns,
        max_tokens=2048,
    )
    return AgentReply(
        answer=final.text or "I could not work that one out.",
        provider=final.provider or provider,
        tool_calls=used,
        iterations=MAX_ITERATIONS,
    )
