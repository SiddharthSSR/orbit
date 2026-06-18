from datetime import datetime
from typing import Literal
from uuid import UUID, uuid4

from pydantic import BaseModel, ConfigDict, Field, field_validator
from sqlalchemy import DateTime, ForeignKey, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from app.core.time import utc_now
from app.db.session import Base


ChatRole = Literal["user", "assistant", "system"]


class ChatSessionRecord(Base):
    __tablename__ = "chat_sessions"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid4()))
    title: Mapped[str | None] = mapped_column(String(240), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, default=utc_now)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        default=utc_now,
        onupdate=utc_now,
    )


class ChatMessageRecord(Base):
    __tablename__ = "chat_messages"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid4()))
    session_id: Mapped[str] = mapped_column(
        String(36),
        ForeignKey("chat_sessions.id"),
        nullable=False,
        index=True,
    )
    role: Mapped[str] = mapped_column(String(20), nullable=False)
    content: Mapped[str] = mapped_column(Text, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        default=utc_now,
        index=True,
    )


class ChatSessionCreate(BaseModel):
    title: str | None = Field(default=None, max_length=240)

    @field_validator("title")
    @classmethod
    def title_must_be_trimmed(cls, value: str | None) -> str | None:
        if value is None:
            return value
        stripped = value.strip()
        return stripped or None


class ChatSessionRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    title: str | None = None
    created_at: datetime
    updated_at: datetime


class ChatMessageRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    session_id: UUID
    role: str
    content: str
    created_at: datetime


class RetrievalDiagnostics(BaseModel):
    retrieval_mode: Literal["keyword", "hybrid"]
    memory_top_k: int
    min_vector_score: float
    vector_attempted: bool
    vector_result_count: int
    vector_error: str | None = None
    fallback_used: bool
    context_build_ms: float


class AskRequest(BaseModel):
    question: str = Field(min_length=1)
    session_id: UUID | None = None
    include_context: bool = True
    retrieval_mode: Literal["keyword", "hybrid"] = "keyword"
    memory_top_k: int = Field(default=5, ge=1, le=20)
    min_vector_score: float = 0.0

    @field_validator("question")
    @classmethod
    def question_must_not_be_blank(cls, value: str) -> str:
        stripped = value.strip()
        if not stripped:
            raise ValueError("Question must not be blank")
        return stripped


class AskResponse(BaseModel):
    session: ChatSessionRead
    user_message: ChatMessageRead
    assistant_message: ChatMessageRead
    answer: str
    retrieval_diagnostics: RetrievalDiagnostics | None = None


class AskContextPreviewRequest(BaseModel):
    question: str = Field(min_length=1)
    include_context: bool = True
    retrieval_mode: Literal["keyword", "hybrid"] = "keyword"
    memory_top_k: int = Field(default=5, ge=1, le=20)
    min_vector_score: float = 0.0

    @field_validator("question")
    @classmethod
    def question_must_not_be_blank(cls, value: str) -> str:
        stripped = value.strip()
        if not stripped:
            raise ValueError("Question must not be blank")
        return stripped


class AskContextPreviewResponse(BaseModel):
    question: str
    include_context: bool
    context: str
    context_sections: list[str]
    retrieval_diagnostics: RetrievalDiagnostics | None = None
