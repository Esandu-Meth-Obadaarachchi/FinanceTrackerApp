from __future__ import annotations

from typing import Any

from pydantic import BaseModel, Field


class ParseTextRequest(BaseModel):
    text: str = Field(min_length=1, max_length=500)
    today: str = ""
    accounts: list[str] = Field(default_factory=list)


class ParseSmsRequest(BaseModel):
    body: str = Field(min_length=1, max_length=1000)
    sender: str = ""
    today: str = ""


class ChatMessage(BaseModel):
    role: str
    content: str


class AgentRequest(BaseModel):
    question: str = Field(min_length=1, max_length=1000)
    # The client's own financial data, sent per question. The backend keeps
    # none of it.
    snapshot: dict[str, Any] = Field(default_factory=dict)
    history: list[ChatMessage] = Field(default_factory=list)
    today: str = ""


class AgentResponse(BaseModel):
    answer: str
    provider: str
    tool_calls: list[dict[str, Any]]
    iterations: int
