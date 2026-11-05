from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Runtime configuration, read from the environment or a local .env."""

    model_config = SettingsConfigDict(
        env_file=".env", env_file_encoding="utf-8", extra="ignore"
    )

    gemini_api_key: str = ""
    gemini_auth_style: str = "api_key"  # api_key | oauth
    gemini_model: str = "gemini-3.6-flash"

    anthropic_api_key: str = ""
    anthropic_model: str = "claude-haiku-4-5"

    # Which provider is tried first. Claude leads because it is ~14x faster
    # here; see docs/AI.md. Set to "gemini" to lead with the free tier again.
    primary_provider: str = "anthropic"

    cors_origins: str = "http://localhost:8567"
    app_shared_key: str = ""

    @property
    def cors_origin_list(self) -> list[str]:
        return [o.strip() for o in self.cors_origins.split(",") if o.strip()]

    @property
    def _gemini_leads(self) -> bool:
        return self.primary_provider.strip().lower() == "gemini"

    @property
    def primary_model(self) -> str:
        return self.gemini_model if self._gemini_leads else self.anthropic_model

    @property
    def fallback_model(self) -> str:
        return self.anthropic_model if self._gemini_leads else self.gemini_model

    @property
    def gemini_enabled(self) -> bool:
        return bool(self.gemini_api_key)

    @property
    def anthropic_enabled(self) -> bool:
        return bool(self.anthropic_api_key)


@lru_cache
def get_settings() -> Settings:
    return Settings()
