from datetime import date, datetime, timezone
from enum import Enum
from uuid import UUID, uuid4

from pydantic import BaseModel, Field


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


class MemoryKind(str, Enum):
    note = "note"
    link = "link"
    article = "article"
    chat = "chat"
    daily_plan = "daily_plan"


class MemoryItem(BaseModel):
    id: UUID = Field(default_factory=uuid4)
    title: str
    body: str
    kind: MemoryKind = MemoryKind.note
    source_url: str | None = None
    tags: list[str] = Field(default_factory=list)
    created_at: datetime = Field(default_factory=utc_now)
    updated_at: datetime = Field(default_factory=utc_now)


class Todo(BaseModel):
    id: UUID = Field(default_factory=uuid4)
    title: str
    notes: str | None = None
    due_date: date | None = None
    project_id: UUID | None = None
    is_complete: bool = False
    created_at: datetime = Field(default_factory=utc_now)


class Bill(BaseModel):
    id: UUID = Field(default_factory=uuid4)
    name: str
    amount: float | None = None
    currency: str = "USD"
    due_date: date
    is_paid: bool = False
    reminder_days_before: int = 3
    notes: str | None = None
    created_at: datetime = Field(default_factory=utc_now)


class Project(BaseModel):
    id: UUID = Field(default_factory=uuid4)
    name: str
    description: str | None = None
    status: str = "active"
    created_at: datetime = Field(default_factory=utc_now)


class MoodLog(BaseModel):
    id: UUID = Field(default_factory=uuid4)
    mood: str
    energy: int = Field(ge=1, le=5)
    notes: str | None = None
    logged_at: datetime = Field(default_factory=utc_now)
