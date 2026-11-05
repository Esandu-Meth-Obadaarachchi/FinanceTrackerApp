"""Gemini Flash over raw HTTP.

Deliberately not the google-genai SDK: the key Esandu has is an OAuth-style
token (`AQ.…`) rather than an AI Studio key (`AIzaSy…`), and the two need
different auth headers. Raw HTTP lets us support both and swap without a
dependency change.
"""

from __future__ import annotations

import json
from typing import Any

import httpx

from .base import LLMResponse, LLMProvider, ProviderError, ToolCall, ToolSpec, Turn

_BASE = "https://generativelanguage.googleapis.com/v1beta"

# Gemini wants OpenAPI-flavoured types in caps and rejects the JSON Schema
# keywords below, so they are stripped rather than passed through.
_STRIP_KEYS = {"additionalProperties", "$schema", "default", "examples", "title"}
_TYPE_MAP = {
    "string": "STRING",
    "number": "NUMBER",
    "integer": "INTEGER",
    "boolean": "BOOLEAN",
    "array": "ARRAY",
    "object": "OBJECT",
}


def _to_gemini_schema(schema: dict[str, Any]) -> dict[str, Any]:
    """Translate plain JSON Schema into Gemini's OpenAPI subset."""
    out: dict[str, Any] = {}
    for key, value in schema.items():
        if key in _STRIP_KEYS:
            continue
        if key == "type" and isinstance(value, str):
            out["type"] = _TYPE_MAP.get(value.lower(), value.upper())
        elif key == "properties" and isinstance(value, dict):
            out["properties"] = {k: _to_gemini_schema(v) for k, v in value.items()}
        elif key == "items" and isinstance(value, dict):
            out["items"] = _to_gemini_schema(value)
        else:
            out[key] = value
    return out


class GeminiProvider(LLMProvider):
    name = "gemini"

    def __init__(self, api_key: str, model: str, auth_style: str = "auto"):
        self._api_key = api_key
        self._model = model
        self._auth_style = auth_style

    @property
    def enabled(self) -> bool:
        return bool(self._api_key)

    def _headers(self) -> dict[str, str]:
        # Both the "AIzaSy…" and "AQ.…" key formats authenticate as API keys.
        # OAuth bearer tokens exist but are opt-in: guessing from the prefix
        # got this wrong and produced a 401 that looked like a bad key.
        if self._auth_style == "oauth":
            return {"Authorization": f"Bearer {self._api_key}"}
        return {"x-goog-api-key": self._api_key}

    @staticmethod
    def _turns_to_contents(turns: list[Turn]) -> list[dict[str, Any]]:
        contents: list[dict[str, Any]] = []
        for turn in turns:
            if turn.role == "tool":
                contents.append(
                    {
                        "role": "user",
                        "parts": [
                            {
                                "functionResponse": {
                                    "name": r.name,
                                    "response": {"result": r.content},
                                }
                            }
                            for r in turn.tool_results
                        ],
                    }
                )
                continue

            parts: list[dict[str, Any]] = []
            if turn.text:
                parts.append({"text": turn.text})
            for call in turn.tool_calls:
                part: dict[str, Any] = {
                    "functionCall": {"name": call.name, "args": call.arguments}
                }
                # Gemini 3.x refuses the follow-up request if a function call
                # comes back without the signature it issued.
                if call.signature:
                    part["thoughtSignature"] = call.signature
                parts.append(part)
            if not parts:
                continue
            contents.append(
                {"role": "model" if turn.role == "assistant" else "user", "parts": parts}
            )
        return contents

    async def complete(
        self,
        *,
        system: str,
        turns: list[Turn],
        tools: list[ToolSpec] | None = None,
        json_schema: dict[str, Any] | None = None,
        max_tokens: int = 2048,
    ) -> LLMResponse:
        if not self.enabled:
            raise ProviderError(self.name, "no API key configured", retryable=True)

        body: dict[str, Any] = {
            "contents": self._turns_to_contents(turns),
            "generationConfig": {"maxOutputTokens": max_tokens, "temperature": 0},
        }
        if system:
            body["systemInstruction"] = {"parts": [{"text": system}]}
        if tools:
            body["tools"] = [
                {
                    "functionDeclarations": [
                        {
                            "name": t.name,
                            "description": t.description,
                            "parameters": _to_gemini_schema(t.parameters),
                        }
                        for t in tools
                    ]
                }
            ]
        if json_schema:
            body["generationConfig"]["responseMimeType"] = "application/json"
            body["generationConfig"]["responseSchema"] = _to_gemini_schema(json_schema)

        url = f"{_BASE}/models/{self._model}:generateContent"
        try:
            # Flash thinks before answering, so a structured-output call can
            # sit well past a default timeout before the first byte arrives.
            async with httpx.AsyncClient(timeout=90.0) as client:
                resp = await client.post(url, headers=self._headers(), json=body)
        except httpx.HTTPError as exc:
            # Transport failures often stringify to "", which made the router
            # log say only "request failed:".
            detail = str(exc) or type(exc).__name__
            raise ProviderError(self.name, f"request failed: {detail}") from exc

        if resp.status_code >= 400:
            # 429 is the daily free-tier ceiling, 5xx is transient: both are
            # exactly what the fallback exists for. 4xx otherwise means the
            # request itself is wrong, so trying Claude with it is pointless.
            retryable = resp.status_code == 429 or resp.status_code >= 500
            raise ProviderError(
                self.name,
                f"HTTP {resp.status_code}: {resp.text[:300]}",
                retryable=retryable,
            )

        data = resp.json()
        candidates = data.get("candidates") or []
        if not candidates:
            raise ProviderError(self.name, f"no candidates: {json.dumps(data)[:300]}")

        # Flash 3.x always thinks and cannot be told not to (thinkingBudget 0
        # is rejected), and those tokens come out of maxOutputTokens. A budget
        # spent entirely on thinking returns MAX_TOKENS with no content, so it
        # is treated as a miss and handed to the fallback rather than returned
        # as an empty answer.
        finish = candidates[0].get("finishReason", "")
        parts = candidates[0].get("content", {}).get("parts") or []
        if finish == "MAX_TOKENS" and not parts:
            raise ProviderError(
                self.name,
                "output budget exhausted by thinking before any answer",
            )
        text_chunks: list[str] = []
        calls: list[ToolCall] = []
        for index, part in enumerate(parts):
            # Flash is a thinking model: reasoning arrives as parts flagged
            # `thought`, which are not the answer and must not be shown.
            if part.get("thought"):
                continue
            if "text" in part:
                text_chunks.append(part["text"])
            if "functionCall" in part:
                fc = part["functionCall"]
                calls.append(
                    ToolCall(
                        id=f"gemini-{index}",
                        name=fc.get("name", ""),
                        arguments=fc.get("args") or {},
                        signature=part.get("thoughtSignature", ""),
                    )
                )

        text = "".join(text_chunks).strip()
        if not text and not calls:
            raise ProviderError(self.name, f"empty response (finish={finish})")

        return LLMResponse(text=text, tool_calls=calls, provider=self.name, raw=data)
