from uuid import UUID

from sqlalchemy import delete, select
from sqlalchemy.orm import Session

from app.core.time import utc_now
from app.models.embedding import MemoryEmbeddingRecord


class MemoryEmbeddingRepository:
    def __init__(self, session: Session) -> None:
        self.session = session

    def upsert(
        self,
        *,
        memory_item_id: UUID | str,
        provider: str,
        model: str,
        embedding: list[float],
        content_hash: str,
    ) -> MemoryEmbeddingRecord:
        now = utc_now()
        record = self.get(memory_item_id=memory_item_id, provider=provider, model=model)
        if record is None:
            record = MemoryEmbeddingRecord(
                memory_item_id=str(memory_item_id),
                provider=provider,
                model=model,
                content_hash=content_hash,
            )
        else:
            record.content_hash = content_hash
            record.updated_at = now
        record.embedding = embedding
        record.status = "indexed"
        record.error_message = None
        record.last_attempted_at = now
        record.indexed_at = now
        self.session.add(record)
        self.session.commit()
        self.session.refresh(record)
        return record

    def mark_stale(
        self,
        *,
        memory_item_id: UUID | str,
        provider: str,
        model: str,
        content_hash: str,
    ) -> MemoryEmbeddingRecord:
        now = utc_now()
        record = self.get(memory_item_id=memory_item_id, provider=provider, model=model)
        if record is None:
            record = MemoryEmbeddingRecord(
                memory_item_id=str(memory_item_id),
                provider=provider,
                model=model,
                embedding_json="[]",
                content_hash=content_hash,
            )
        else:
            record.content_hash = content_hash
            record.updated_at = now
        record.status = "stale"
        record.error_message = None
        record.last_attempted_at = now
        self.session.add(record)
        self.session.commit()
        self.session.refresh(record)
        return record

    def mark_failed(
        self,
        *,
        memory_item_id: UUID | str,
        provider: str,
        model: str,
        content_hash: str,
        error_message: str,
    ) -> MemoryEmbeddingRecord:
        now = utc_now()
        record = self.get(memory_item_id=memory_item_id, provider=provider, model=model)
        if record is None:
            record = MemoryEmbeddingRecord(
                memory_item_id=str(memory_item_id),
                provider=provider,
                model=model,
                embedding_json="[]",
                content_hash=content_hash,
            )
        else:
            record.content_hash = content_hash
            record.updated_at = now
        record.status = "failed"
        record.error_message = error_message
        record.last_attempted_at = now
        self.session.add(record)
        self.session.commit()
        self.session.refresh(record)
        return record

    def get(
        self,
        *,
        memory_item_id: UUID | str,
        provider: str,
        model: str,
    ) -> MemoryEmbeddingRecord | None:
        statement = select(MemoryEmbeddingRecord).where(
            MemoryEmbeddingRecord.memory_item_id == str(memory_item_id),
            MemoryEmbeddingRecord.provider == provider,
            MemoryEmbeddingRecord.model == model,
        )
        return self.session.scalar(statement)

    def list_for_provider_model(self, *, provider: str, model: str) -> list[MemoryEmbeddingRecord]:
        statement = (
            select(MemoryEmbeddingRecord)
            .where(
                MemoryEmbeddingRecord.provider == provider,
                MemoryEmbeddingRecord.model == model,
            )
            .order_by(MemoryEmbeddingRecord.created_at)
        )
        return list(self.session.scalars(statement).all())

    def delete_for_memory_item(self, memory_item_id: UUID | str) -> int:
        result = self.session.execute(
            delete(MemoryEmbeddingRecord).where(
                MemoryEmbeddingRecord.memory_item_id == str(memory_item_id)
            )
        )
        self.session.commit()
        return result.rowcount or 0
