import os
from pathlib import Path

from pydantic import BaseModel, Field


BACKEND_DIR = Path(__file__).resolve().parents[2]


class Settings(BaseModel):
    app_name: str = "Orbit API"
    version: str = "0.1.0"
    database_url: str = Field(
        default_factory=lambda: os.getenv("ORBIT_DATABASE_URL", f"sqlite:///{BACKEND_DIR / 'orbit.db'}")
    )
    ai_provider: str = Field(default_factory=lambda: os.getenv("ORBIT_AI_PROVIDER", "mock").strip().lower() or "mock")
    openai_api_key: str | None = Field(default_factory=lambda: os.getenv("OPENAI_API_KEY"))
    openai_model: str = Field(default_factory=lambda: os.getenv("ORBIT_OPENAI_MODEL", "gpt-4o-mini"))
    ai_timeout_seconds: float = Field(default_factory=lambda: float(os.getenv("ORBIT_AI_TIMEOUT_SECONDS", "30")))
    cors_allow_origins: list[str] = Field(
        default_factory=lambda: [
            "http://localhost:3000",
            "http://localhost:5173",
            "http://127.0.0.1:3000",
            "http://127.0.0.1:5173",
        ]
    )


settings = Settings()
