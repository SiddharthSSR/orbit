from datetime import date, datetime
from uuid import UUID, uuid4

from pydantic import BaseModel, ConfigDict, Field, field_validator
from sqlalchemy import Date, DateTime, Integer, String
from sqlalchemy.orm import Mapped, mapped_column

from app.db.session import Base
from app.core.time import utc_now


def today() -> date:
    return utc_now().date()


class MoodRecord(Base):
    __tablename__ = "moods"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid4()))
    mood: Mapped[str] = mapped_column(String(80), nullable=False)
    energy: Mapped[int] = mapped_column(Integer, nullable=False)
    notes: Mapped[str | None] = mapped_column(String, nullable=True)
    check_in_date: Mapped[date] = mapped_column(Date, nullable=False, default=today)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, default=utc_now)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        default=utc_now,
        onupdate=utc_now,
    )


class MoodBase(BaseModel):
    @field_validator("mood", check_fields=False)
    @classmethod
    def mood_must_not_be_blank(cls, value: str | None) -> str | None:
        if value is None:
            return value
        stripped = value.strip()
        if not stripped:
            raise ValueError("Mood must not be blank")
        return stripped


class MoodCreate(MoodBase):
    mood: str = Field(min_length=1, max_length=80)
    energy: int = Field(ge=1, le=5)
    notes: str | None = None
    check_in_date: date | None = None


class MoodUpdate(MoodBase):
    mood: str | None = Field(default=None, min_length=1, max_length=80)
    energy: int | None = Field(default=None, ge=1, le=5)
    notes: str | None = None
    check_in_date: date | None = None


class MoodRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    mood: str
    energy: int
    notes: str | None = None
    check_in_date: date
    created_at: datetime
    updated_at: datetime
