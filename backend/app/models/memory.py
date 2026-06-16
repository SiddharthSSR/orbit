import json
from datetime import datetime
from typing import ClassVar, Literal
from uuid import UUID, uuid4

from pydantic import BaseModel, ConfigDict, Field, field_validator
from sqlalchemy import Boolean, DateTime, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from app.db.session import Base
from app.core.time import utc_now


MemoryKind = Literal["note", "idea", "link", "article", "tweet", "project_update", "daily_plan"]
ALLOWED_MEMORY_KINDS = {"note", "idea", "link", "article", "tweet", "project_update", "daily_plan"}


class MemoryRecord(Base):
    __tablename__ = "memory_items"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid4()))
    title: Mapped[str] = mapped_column(String(240), nullable=False)
    body: Mapped[str] = mapped_column(Text, nullable=False)
    kind: Mapped[str] = mapped_column(String(40), nullable=False, default="note")
    source_url: Mapped[str | None] = mapped_column(String, nullable=True)
    tags_json: Mapped[str] = mapped_column("tags", Text, nullable=False, default="[]")
    is_archived: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, default=utc_now)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        default=utc_now,
        onupdate=utc_now,
    )

    @property
    def tags(self) -> list[str]:
        try:
            value = json.loads(self.tags_json)
        except json.JSONDecodeError:
            return []
        return value if isinstance(value, list) else []

    @tags.setter
    def tags(self, value: list[str]) -> None:
        self.tags_json = json.dumps(normalize_tags(value))


def normalize_tags(tags: list[str]) -> list[str]:
    normalized: list[str] = []
    seen: set[str] = set()
    for tag in tags:
        normalized_tag = tag.strip()
        if not normalized_tag or normalized_tag in seen:
            continue
        normalized.append(normalized_tag)
        seen.add(normalized_tag)
    return normalized


class MemoryBase(BaseModel):
    allowed_kinds: ClassVar[set[str]] = ALLOWED_MEMORY_KINDS

    @field_validator("title", check_fields=False)
    @classmethod
    def title_must_not_be_blank(cls, value: str | None) -> str | None:
        if value is None:
            return value
        stripped = value.strip()
        if not stripped:
            raise ValueError("Title must not be blank")
        return stripped

    @field_validator("body", check_fields=False)
    @classmethod
    def body_must_not_be_blank(cls, value: str | None) -> str | None:
        if value is None:
            return value
        stripped = value.strip()
        if not stripped:
            raise ValueError("Body must not be blank")
        return stripped

    @field_validator("kind", check_fields=False)
    @classmethod
    def kind_must_be_allowed(cls, value: str | None) -> str | None:
        if value is None:
            return value
        if value not in cls.allowed_kinds:
            raise ValueError("Invalid memory kind")
        return value

    @field_validator("tags", check_fields=False)
    @classmethod
    def tags_must_be_normalized(cls, value: list[str] | None) -> list[str] | None:
        if value is None:
            return value
        return normalize_tags(value)


class MemoryCreate(MemoryBase):
    title: str = Field(min_length=1, max_length=240)
    body: str = Field(min_length=1)
    kind: MemoryKind = "note"
    source_url: str | None = None
    tags: list[str] = Field(default_factory=list)
    is_archived: bool = False


class MemoryUpdate(MemoryBase):
    title: str | None = Field(default=None, min_length=1, max_length=240)
    body: str | None = Field(default=None, min_length=1)
    kind: MemoryKind | None = None
    source_url: str | None = None
    tags: list[str] | None = None
    is_archived: bool | None = None


class MemoryRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    title: str
    body: str
    kind: str
    source_url: str | None = None
    tags: list[str] = Field(default_factory=list)
    is_archived: bool
    created_at: datetime
    updated_at: datetime
