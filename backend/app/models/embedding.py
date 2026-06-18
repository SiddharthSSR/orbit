import json
from datetime import datetime
from uuid import UUID, uuid4

from pydantic import BaseModel, ConfigDict
from sqlalchemy import DateTime, ForeignKey, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.core.time import utc_now
from app.db.session import Base
from app.models.memory import MemoryRead


class MemoryEmbeddingRecord(Base):
    __tablename__ = "memory_embeddings"
    __table_args__ = (
        UniqueConstraint(
            "memory_item_id",
            "provider",
            "model",
            name="uq_memory_embeddings_item_provider_model",
        ),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid4()))
    memory_item_id: Mapped[str] = mapped_column(
        String(36),
        ForeignKey("memory_items.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    provider: Mapped[str] = mapped_column(String(40), nullable=False)
    model: Mapped[str] = mapped_column(String(120), nullable=False)
    embedding_json: Mapped[str] = mapped_column(Text, nullable=False)
    content_hash: Mapped[str] = mapped_column(String(64), nullable=False)
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="indexed")
    error_message: Mapped[str | None] = mapped_column(Text, nullable=True)
    last_attempted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    indexed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, default=utc_now)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        default=utc_now,
        onupdate=utc_now,
    )

    @property
    def embedding(self) -> list[float]:
        value = json.loads(self.embedding_json)
        if not isinstance(value, list):
            raise ValueError("Stored memory embedding must be a JSON list")
        return [float(component) for component in value]

    @embedding.setter
    def embedding(self, value: list[float]) -> None:
        self.embedding_json = json.dumps(value, separators=(",", ":"))


class MemoryEmbeddingRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    memory_item_id: UUID
    provider: str
    model: str
    content_hash: str
    status: str
    error_message: str | None = None
    last_attempted_at: datetime | None = None
    indexed_at: datetime | None = None
    created_at: datetime
    updated_at: datetime


class MemoryEmbeddingReindexResponse(BaseModel):
    indexed_count: int
    provider: str
    model: str


class MemorySearchResultRead(BaseModel):
    score: float
    memory_item: MemoryRead


class MemoryEmbeddingFailedItemRead(BaseModel):
    memory_item_id: UUID
    title: str
    error_message: str | None = None


class MemoryEmbeddingStatusResponse(BaseModel):
    provider: str
    model: str
    indexed_count: int
    failed_count: int
    stale_count: int
    missing_count: int
    failed_items: list[MemoryEmbeddingFailedItemRead]


class MemoryEmbeddingRetryResponse(BaseModel):
    retried: int
    indexed: int
    failed: int
