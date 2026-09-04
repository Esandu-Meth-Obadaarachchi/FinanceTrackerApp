"""Claude Haiku via the official Anthropic SDK — the fallback provider."""

from __future__ import annotations

import json
from typing import Any

import anthropic

from .base import LLMResponse, LLMProvider, ProviderError, ToolCall, ToolSpec, Turn


class AnthropicProvider(LLMProvider):
    name = "anthropic"

    def __init__(self, api_key: str, model: str):
        self._api_key = api_key
        self._model = model
        self._client = (
            anthropic.AsyncAnthropic(api_key=api_key) if api_key else None
        )

    @property
    def enabled(self) -> bool:
        return self._client is not None

    @staticmethod
    def _turns_to_messages(turns: list[Turn]) -> list[dict[str, Any]]:
        messages: list[dict[str, Any]] = []
        for turn in turns:
            if turn.role == "tool":
                # Every result for one assistant turn goes back in a single
                # user message. Splitting them teaches Claude to stop
                # calling tools in parallel.
                messages.append(
                    {
                        "role": "user",
                        "content": [
                            {
                                "type": "tool_result",
                                "tool_use_id": r.id,
                                "content": json.dumps(r.content, default=str),
                                **({"is_error": True} if r.is_error else {}),
                            }
                            for r in turn.tool_results
                        ],
                    }
                )
                continue

            if turn.role == "assistant":
                blocks: list[dict[str, Any]] = []
                if turn.text:
                    blocks.append({"type": "text", "text": turn.text})
                for call in turn.tool_calls:
                    blocks.append(
                        {
                            "type": "tool_use",
                            "id": call.id,
                            "name": call.name,
                            "input": call.arguments,
                        }
                    )
                if blocks:
                    messages.append({"role": "assistant", "content": blocks})
                continue

            if turn.text:
                messages.append({"role": "user", "content": turn.text})
        return messages

    async def complete(
        self,
        *,
        system: str,
        turns: list[Turn],
        tools: list[ToolSpec] | None = None,
        json_schema: dict[str, Any] | None = None,
        max_tokens: int = 2048,
    ) -> LLMResponse:
        if self._client is None:
            raise ProviderError(self.name, "no API key configured", retryable=False)

        kwargs: dict[str, Any] = {
            "model": self._model,
            "max_tokens": max_tokens,
            "messages": self._turns_to_messages(turns),
        }
        if system:
            # No cache_control here on purpose. Prompt caching was tried on
            # the tools prefix and again on tools+system (~2.4k tokens) and
            # cache_read_input_tokens came back zero both times — the prefix
            # is under this model's minimum cacheable length. A breakpoint
            # that never hits is worse than none: it reads as an optimisation
            # that is running when it is not. Revisit if the tool set grows.
            kwargs["system"] = system
        if tools:
            spec = [
                {
                    "name": t.name,
                    "description": t.description,
                    "input_schema": t.parameters,
                }
                for t in tools
            ]
            kwargs["tools"] = spec
        if json_schema:
            kwargs["output_config"] = {
                "format": {
                    "type": "json_schema",
                    "schema": json_schema,
                }
            }

        try:
            message = await self._client.messages.create(**kwargs)
        except anthropic.RateLimitError as exc:
            raise ProviderError(self.name, f"rate limited: {exc}") from exc
        except anthropic.APIStatusError as exc:
            raise ProviderError(
                self.name,
                f"HTTP {exc.status_code}: {exc}",
                retryable=exc.status_code >= 500,
            ) from exc
        except anthropic.APIConnectionError as exc:
            raise ProviderError(self.name, f"connection failed: {exc}") from exc

        text_chunks: list[str] = []
        calls: list[ToolCall] = []
        for block in message.content:
            if block.type == "text":
                text_chunks.append(block.text)
            elif block.type == "tool_use":
                # Inputs may carry provider-specific JSON escaping, so they
                # are read as parsed objects rather than matched as strings.
                args = block.input
                if isinstance(args, str):
                    args = json.loads(args)
                calls.append(
                    ToolCall(id=block.id, name=block.name, arguments=args or {})
                )

        return LLMResponse(
            text="".join(text_chunks).strip(),
            tool_calls=calls,
            provider=self.name,
            raw=message.model_dump(),
        )
