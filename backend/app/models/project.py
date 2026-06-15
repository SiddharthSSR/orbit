import json
from datetime import datetime
from typing import ClassVar, Literal
from uuid import UUID, uuid4

from pydantic import BaseModel, ConfigDict, Field, field_validator
from sqlalchemy import DateTime, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from app.db.session import Base
from app.models.domain import utc_now


ProjectStatus = Literal["active", "paused", "completed", "archived"]
ALLOWED_PROJECT_STATUSES = {"active", "paused", "completed", "archived"}


class ProjectRecord(Base):
    __tablename__ = "projects"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid4()))
    name: Mapped[str] = mapped_column(String(240), nullable=False)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    status: Mapped[str] = mapped_column(String(40), nullable=False, default="active")
    area: Mapped[str | None] = mapped_column(String(120), nullable=True)
    tags_json: Mapped[str] = mapped_column("tags", Text, nullable=False, default="[]")
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


class ProjectBase(BaseModel):
    allowed_statuses: ClassVar[set[str]] = ALLOWED_PROJECT_STATUSES

    @field_validator("name", check_fields=False)
    @classmethod
    def name_must_not_be_blank(cls, value: str | None) -> str | None:
        if value is None:
            return value
        stripped = value.strip()
        if not stripped:
            raise ValueError("Name must not be blank")
        return stripped

    @field_validator("status", check_fields=False)
    @classmethod
    def status_must_be_allowed(cls, value: str | None) -> str | None:
        if value is None:
            return value
        if value not in cls.allowed_statuses:
            raise ValueError("Invalid project status")
        return value

    @field_validator("area", check_fields=False)
    @classmethod
    def area_must_be_trimmed(cls, value: str | None) -> str | None:
        if value is None:
            return value
        stripped = value.strip()
        return stripped or None

    @field_validator("tags", check_fields=False)
    @classmethod
    def tags_must_be_normalized(cls, value: list[str] | None) -> list[str] | None:
        if value is None:
            return value
        return normalize_tags(value)


class ProjectCreate(ProjectBase):
    name: str = Field(min_length=1, max_length=240)
    description: str | None = None
    status: ProjectStatus = "active"
    area: str | None = None
    tags: list[str] = Field(default_factory=list)


class ProjectUpdate(ProjectBase):
    name: str | None = Field(default=None, min_length=1, max_length=240)
    description: str | None = None
    status: ProjectStatus | None = None
    area: str | None = None
    tags: list[str] | None = None


class ProjectRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    name: str
    description: str | None = None
    status: str
    area: str | None = None
    tags: list[str] = Field(default_factory=list)
    created_at: datetime
    updated_at: datetime
