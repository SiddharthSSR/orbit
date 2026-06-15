from datetime import date, datetime
from uuid import UUID, uuid4

from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import Boolean, Date, DateTime, String
from sqlalchemy.orm import Mapped, mapped_column

from app.db.session import Base
from app.models.domain import utc_now


class TodoRecord(Base):
    __tablename__ = "todos"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid4()))
    title: Mapped[str] = mapped_column(String(240), nullable=False)
    notes: Mapped[str | None] = mapped_column(String, nullable=True)
    due_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    project_id: Mapped[str | None] = mapped_column(String(36), nullable=True)
    is_complete: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, default=utc_now)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        default=utc_now,
        onupdate=utc_now,
    )


class TodoCreate(BaseModel):
    title: str = Field(min_length=1, max_length=240)
    notes: str | None = None
    due_date: date | None = None
    project_id: UUID | None = None
    is_complete: bool = False


class TodoUpdate(BaseModel):
    title: str | None = Field(default=None, min_length=1, max_length=240)
    notes: str | None = None
    due_date: date | None = None
    project_id: UUID | None = None
    is_complete: bool | None = None


class TodoRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    title: str
    notes: str | None = None
    due_date: date | None = None
    project_id: UUID | None = None
    is_complete: bool
    created_at: datetime
    updated_at: datetime

