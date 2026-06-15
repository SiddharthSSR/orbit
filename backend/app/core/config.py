import os
from pathlib import Path

from pydantic import BaseModel


BACKEND_DIR = Path(__file__).resolve().parents[2]


class Settings(BaseModel):
    app_name: str = "Orbit API"
    version: str = "0.1.0"
    database_url: str = os.getenv("ORBIT_DATABASE_URL", f"sqlite:///{BACKEND_DIR / 'orbit.db'}")
    cors_allow_origins: list[str] = [
        "http://localhost:3000",
        "http://localhost:5173",
        "http://127.0.0.1:3000",
        "http://127.0.0.1:5173",
    ]


settings = Settings()
