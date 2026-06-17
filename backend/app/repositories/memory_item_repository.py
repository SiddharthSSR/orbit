from uuid import UUID

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.time import utc_now
from app.models.memory import MemoryCreate, MemoryRecord, MemoryUpdate


class MemoryItemRepository:
    def __init__(self, session: Session) -> None:
        self.session = session

    def create(self, payload: MemoryCreate) -> MemoryRecord:
        memory_item = MemoryRecord(
            title=payload.title,
            body=payload.body,
            kind=payload.kind,
            source_url=payload.source_url,
            is_archived=payload.is_archived,
        )
        memory_item.tags = payload.tags
        self.session.add(memory_item)
        self.session.commit()
        self.session.refresh(memory_item)
        return memory_item

    def list(
        self,
        *,
        include_archived: bool = False,
        kind: str | None = None,
        tag: str | None = None,
    ) -> list[MemoryRecord]:
        statement = select(MemoryRecord)
        if not include_archived:
            statement = statement.where(MemoryRecord.is_archived.is_(False))
        if kind is not None:
            statement = statement.where(MemoryRecord.kind == kind)
        statement = statement.order_by(MemoryRecord.created_at.desc())

        memory_items = list(self.session.scalars(statement).all())
        if tag is None:
            return memory_items

        normalized_tag = tag.strip()
        if not normalized_tag:
            return memory_items
        return [item for item in memory_items if normalized_tag in item.tags]

    def get(self, memory_id: UUID | str) -> MemoryRecord | None:
        return self.session.get(MemoryRecord, str(memory_id))

    def update(self, memory_item: MemoryRecord, payload: MemoryUpdate) -> MemoryRecord:
        updates = payload.model_dump(exclude_unset=True)
        tags = updates.pop("tags", None)

        for field, value in updates.items():
            setattr(memory_item, field, value)
        if tags is not None:
            memory_item.tags = tags
        memory_item.updated_at = utc_now()

        self.session.add(memory_item)
        self.session.commit()
        self.session.refresh(memory_item)
        return memory_item

    def delete(self, memory_item: MemoryRecord) -> None:
        self.session.delete(memory_item)
        self.session.commit()
