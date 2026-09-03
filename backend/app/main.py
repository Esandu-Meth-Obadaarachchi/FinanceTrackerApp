from __future__ import annotations

import logging
from datetime import date

from fastapi import Depends, FastAPI, Header, HTTPException
from fastapi.middleware.cors import CORSMiddleware

from .config import Settings, get_settings
from .providers.anthropic_provider import AnthropicProvider
from .providers.base import ProviderError
from .providers.gemini import GeminiProvider
from .providers.router import ProviderRouter
from .schemas import (
    AgentRequest,
    AgentResponse,
    ParseSmsRequest,
    ParseTextRequest,
)
from .services.agent import run_agent
from .services.parsing import parse_sms, parse_text

logging.basicConfig(level=logging.INFO)
log = logging.getLogger("fintrack.ai")

app = FastAPI(
    title="FinTrack AI",
    version="0.1.0",
    description="Parsing and agentic Q&A for the FinTrack app.",
)

_settings = get_settings()
app.add_middleware(
    CORSMiddleware,
    allow_origins=_settings.cors_origin_list,
    allow_credentials=False,
    allow_methods=["POST", "GET", "OPTIONS"],
    allow_headers=["*"],
)


def get_router(settings: Settings = Depends(get_settings)) -> ProviderRouter:
    """Gemini Flash first, Claude Haiku when it fails."""
    return ProviderRouter(
        primary=GeminiProvider(
            settings.gemini_api_key, settings.gemini_model, settings.gemini_auth_style
        ),
        fallback=AnthropicProvider(
            settings.anthropic_api_key, settings.anthropic_model
        ),
    )


def require_app_key(
    x_app_key: str = Header(default=""),
    settings: Settings = Depends(get_settings),
) -> None:
    """Stops the endpoint being an open proxy onto paid API credits."""
    if not settings.app_shared_key:
        return
    if x_app_key != settings.app_shared_key:
        raise HTTPException(status_code=401, detail="bad or missing X-App-Key")


def _today(given: str) -> str:
    return given or date.today().isoformat()


@app.get("/health")
def health(settings: Settings = Depends(get_settings)) -> dict:
    return {
        "ok": True,
        "providers": {
            "gemini": settings.gemini_enabled,
            "anthropic": settings.anthropic_enabled,
        },
        "primary": settings.gemini_model,
        "fallback": settings.anthropic_model,
    }


@app.post("/parse/text", dependencies=[Depends(require_app_key)])
async def parse_text_endpoint(
    req: ParseTextRequest, router: ProviderRouter = Depends(get_router)
) -> dict:
    """One line of text to a transaction the client can confirm."""
    try:
        return await parse_text(
            router, text=req.text, today=_today(req.today), accounts=req.accounts
        )
    except ProviderError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=502, detail=f"bad model output: {exc}") from exc


@app.post("/parse/sms", dependencies=[Depends(require_app_key)])
async def parse_sms_endpoint(
    req: ParseSmsRequest, router: ProviderRouter = Depends(get_router)
) -> dict:
    """A bank SMS to a categorised transaction for the review inbox."""
    try:
        return await parse_sms(
            router, body=req.body, sender=req.sender, today=_today(req.today)
        )
    except ProviderError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=502, detail=f"bad model output: {exc}") from exc


@app.post("/agent/ask", dependencies=[Depends(require_app_key)])
async def agent_endpoint(
    req: AgentRequest, router: ProviderRouter = Depends(get_router)
) -> AgentResponse:
    """Ask a question about your own money. The agent calls tools to answer."""
    try:
        reply = await run_agent(
            router,
            question=req.question,
            snapshot=req.snapshot,
            history=[m.model_dump() for m in req.history],
            today=_today(req.today),
        )
    except ProviderError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    return AgentResponse(
        answer=reply.answer,
        provider=reply.provider,
        tool_calls=reply.tool_calls,
        iterations=reply.iterations,
    )
