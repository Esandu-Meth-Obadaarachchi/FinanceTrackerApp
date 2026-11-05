"""Provider-neutral chat + tool-calling interface.

Gemini and Claude disagree on almost every wire detail: what a tool schema
looks like, how a tool call comes back, how its result goes in. Everything
above this module speaks the vocabulary defined here, and each provider
adapter translates at its own edge. That is what makes the fallback in
`router.py` a one-line swap rather than a second implementation.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Protocol


class ProviderError(Exception):
    """A provider failed in a way worth trying the next provider for."""

    def __init__(self, provider: str, message: str, *, retryable: bool = True):
        super().__init__(f"{provider}: {message}")
        self.provider = provider
        self.retryable = retryable


@dataclass
class ToolSpec:
    """A tool the model may call. `parameters` is plain JSON Schema."""

    name: str
    description: str
    parameters: dict[str, Any]


@dataclass
class ToolCall:
    """A model's request to run one tool.

    `signature` carries provider-specific opaque data that has to survive the
    round trip. Gemini 3.x rejects a conversation whose function calls come
    back without their `thoughtSignature`.
    """

    id: str
    name: str
    arguments: dict[str, Any]
    signature: str = ""


@dataclass
class ToolResult:
    """The outcome of running a [ToolCall], fed back to the model."""

    id: str
    name: str
    content: Any
    is_error: bool = False


@dataclass
class Turn:
    """One step of a conversation.

    `role` is "user", "assistant" or "tool". A tool turn carries results
    only; an assistant turn may carry text, tool calls, or both.
    """

    role: str
    text: str = ""
    tool_calls: list[ToolCall] = field(default_factory=list)
    tool_results: list[ToolResult] = field(default_factory=list)


@dataclass
class LLMResponse:
    text: str
    tool_calls: list[ToolCall] = field(default_factory=list)
    provider: str = ""
    raw: dict[str, Any] | None = None

    @property
    def wants_tools(self) -> bool:
        return bool(self.tool_calls)


class LLMProvider(Protocol):
    """What the agent and parsers rely on. Implemented per vendor."""

    name: str

    @property
    def enabled(self) -> bool: ...

    async def complete(
        self,
        *,
        system: str,
        turns: list[Turn],
        tools: list[ToolSpec] | None = None,
        json_schema: dict[str, Any] | None = None,
        max_tokens: int = 2048,
    ) -> LLMResponse:
        """Run one model turn.

        Passing `json_schema` asks for a JSON object matching that schema
        instead of prose. Passing `tools` lets the model call them.
        """
        ...
