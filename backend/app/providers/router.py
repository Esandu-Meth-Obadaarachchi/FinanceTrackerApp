"""Tries Gemini first, falls back to Claude Haiku.

Any primary failure falls through, including a 400. The instinct is to treat
4xx as "the request is malformed, so the next provider will reject it too",
but that assumes both vendors validate the same request identically and they
do not: Gemini 3.x rejects tool histories missing a `thoughtSignature`, a
requirement Claude has no concept of. The failures that actually happen in
practice — the free tier's daily ceiling, overload 503s, transport timeouts,
and vendor-specific schema rules — are all ones the other provider handles.
One wasted call on a genuinely bad request is cheaper than a dead endpoint.
"""

from __future__ import annotations

import logging
from typing import Any

from .base import LLMResponse, LLMProvider, ProviderError, ToolSpec, Turn

log = logging.getLogger(__name__)


class ProviderRouter:
    def __init__(self, primary: LLMProvider, fallback: LLMProvider):
        self.primary = primary
        self.fallback = fallback

    @property
    def available(self) -> list[str]:
        return [p.name for p in (self.primary, self.fallback) if p.enabled]

    async def complete(
        self,
        *,
        system: str,
        turns: list[Turn],
        tools: list[ToolSpec] | None = None,
        json_schema: dict[str, Any] | None = None,
        max_tokens: int = 2048,
    ) -> LLMResponse:
        attempts: list[str] = []

        for provider in (self.primary, self.fallback):
            if not provider.enabled:
                attempts.append(f"{provider.name}: not configured")
                continue
            try:
                return await provider.complete(
                    system=system,
                    turns=turns,
                    tools=tools,
                    json_schema=json_schema,
                    max_tokens=max_tokens,
                )
            except ProviderError as exc:
                attempts.append(str(exc))
                log.warning(
                    "provider %s failed, falling through: %s", provider.name, exc
                )

        raise ProviderError("router", "all providers failed: " + " | ".join(attempts))
