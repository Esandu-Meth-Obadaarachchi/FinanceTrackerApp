"""Fallback behaviour, pinned with fakes so it never touches the network.

The failures these cover are the ones seen live during development: Gemini's
free-tier 429, its 503 under load, and a vendor-specific 400 that Claude
accepts happily.
"""

import pytest

from app.providers.base import LLMResponse, ProviderError, Turn
from app.providers.router import ProviderRouter


class FakeProvider:
    def __init__(self, name, *, fails_with=None, enabled=True):
        self.name = name
        self._fails_with = fails_with
        self._enabled = enabled
        self.calls = 0

    @property
    def enabled(self):
        return self._enabled

    async def complete(self, **kwargs):
        self.calls += 1
        if self._fails_with:
            raise self._fails_with
        return LLMResponse(text=f"answer from {self.name}", provider=self.name)


TURNS = [Turn(role="user", text="hello")]


@pytest.mark.asyncio
async def test_primary_answers_and_fallback_is_left_alone():
    primary = FakeProvider("gemini")
    fallback = FakeProvider("anthropic")
    result = await ProviderRouter(primary, fallback).complete(system="", turns=TURNS)

    assert result.provider == "gemini"
    assert fallback.calls == 0


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "failure",
    [
        ProviderError("gemini", "HTTP 429: quota exceeded"),
        ProviderError("gemini", "HTTP 503: overloaded"),
        ProviderError("gemini", "request failed: ReadTimeout"),
        # Vendor-specific rejection Claude has no concept of.
        ProviderError("gemini", "HTTP 400: missing thought_signature", retryable=False),
    ],
)
async def test_any_primary_failure_falls_through(failure):
    primary = FakeProvider("gemini", fails_with=failure)
    fallback = FakeProvider("anthropic")
    result = await ProviderRouter(primary, fallback).complete(system="", turns=TURNS)

    assert result.provider == "anthropic"
    assert fallback.calls == 1


@pytest.mark.asyncio
async def test_unconfigured_primary_is_skipped_entirely():
    primary = FakeProvider("gemini", enabled=False)
    fallback = FakeProvider("anthropic")
    result = await ProviderRouter(primary, fallback).complete(system="", turns=TURNS)

    assert result.provider == "anthropic"
    assert primary.calls == 0


@pytest.mark.asyncio
async def test_both_failing_reports_both_reasons():
    primary = FakeProvider("gemini", fails_with=ProviderError("gemini", "quota"))
    fallback = FakeProvider("anthropic", fails_with=ProviderError("anthropic", "down"))

    with pytest.raises(ProviderError) as exc:
        await ProviderRouter(primary, fallback).complete(system="", turns=TURNS)

    assert "quota" in str(exc.value)
    assert "down" in str(exc.value)


@pytest.mark.asyncio
async def test_available_lists_only_configured_providers():
    router = ProviderRouter(
        FakeProvider("gemini", enabled=False), FakeProvider("anthropic")
    )
    assert router.available == ["anthropic"]
