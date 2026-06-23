from uuid import UUID

from sqlalchemy import select, update
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
            project_id=str(payload.project_id) if payload.project_id else None,
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
        project_id: UUID | str | None = None,
    ) -> list[MemoryRecord]:
        statement = select(MemoryRecord)
        if not include_archived:
            statement = statement.where(MemoryRecord.is_archived.is_(False))
        if kind is not None:
            statement = statement.where(MemoryRecord.kind == kind)
        if project_id is not None:
            statement = statement.where(MemoryRecord.project_id == str(project_id))
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
        if "project_id" in updates and updates["project_id"] is not None:
            updates["project_id"] = str(updates["project_id"])

        for field, value in updates.items():
            setattr(memory_item, field, value)
        if tags is not None:
            memory_item.tags = tags
        memory_item.updated_at = utc_now()

        self.session.add(memory_item)
        self.session.commit()
        self.session.refresh(memory_item)
        return memory_item

    def clear_project_links(self, project_id: UUID | str) -> None:
        self.session.execute(
            update(MemoryRecord)
            .where(MemoryRecord.project_id == str(project_id))
            .values(project_id=None, updated_at=utc_now())
        )

    def delete(self, memory_item: MemoryRecord) -> None:
        self.session.delete(memory_item)
        self.session.commit()
