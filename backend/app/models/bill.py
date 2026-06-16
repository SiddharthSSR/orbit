from datetime import date, datetime
from uuid import UUID, uuid4

from pydantic import BaseModel, ConfigDict, Field, field_validator
from sqlalchemy import Boolean, Date, DateTime, Float, Integer, String
from sqlalchemy.orm import Mapped, mapped_column

from app.db.session import Base
from app.core.time import utc_now


class BillRecord(Base):
    __tablename__ = "bills"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid4()))
    name: Mapped[str] = mapped_column(String(240), nullable=False)
    amount: Mapped[float | None] = mapped_column(Float, nullable=True)
    currency: Mapped[str] = mapped_column(String(3), nullable=False, default="INR")
    due_date: Mapped[date] = mapped_column(Date, nullable=False)
    recurrence: Mapped[str | None] = mapped_column(String(40), nullable=True)
    is_paid: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    reminder_days_before: Mapped[int] = mapped_column(Integer, nullable=False, default=3)
    notes: Mapped[str | None] = mapped_column(String, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, default=utc_now)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        default=utc_now,
        onupdate=utc_now,
    )


class BillCreate(BaseModel):
    name: str = Field(min_length=1, max_length=240)
    amount: float | None = None
    currency: str = Field(default="INR", min_length=3, max_length=3)
    due_date: date
    recurrence: str | None = None
    is_paid: bool = False
    reminder_days_before: int = Field(default=3, ge=0)
    notes: str | None = None

    @field_validator("name")
    @classmethod
    def name_must_not_be_blank(cls, value: str) -> str:
        stripped = value.strip()
        if not stripped:
            raise ValueError("Name must not be blank")
        return stripped


class BillUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=240)
    amount: float | None = None
    currency: str | None = Field(default=None, min_length=3, max_length=3)
    due_date: date | None = None
    recurrence: str | None = None
    is_paid: bool | None = None
    reminder_days_before: int | None = Field(default=None, ge=0)
    notes: str | None = None

    @field_validator("name")
    @classmethod
    def name_must_not_be_blank(cls, value: str | None) -> str | None:
        if value is None:
            return value
        stripped = value.strip()
        if not stripped:
            raise ValueError("Name must not be blank")
        return stripped


class BillRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    name: str
    amount: float | None = None
    currency: str
    due_date: date
    recurrence: str | None = None
    is_paid: bool
    reminder_days_before: int
    notes: str | None = None
    created_at: datetime
    updated_at: datetime
