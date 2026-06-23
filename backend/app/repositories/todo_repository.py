from uuid import UUID

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.time import utc_now
from app.models.todo import TodoCreate, TodoRecord, TodoUpdate


class TodoRepository:
    def __init__(self, session: Session) -> None:
        self.session = session

    def create(self, payload: TodoCreate) -> TodoRecord:
        todo = TodoRecord(
            title=payload.title,
            notes=payload.notes,
            due_date=payload.due_date,
            project_id=str(payload.project_id) if payload.project_id else None,
            is_complete=payload.is_complete,
        )
        self.session.add(todo)
        self.session.commit()
        self.session.refresh(todo)
        return todo

    def list(self, project_id: UUID | str | None = None) -> list[TodoRecord]:
        statement = select(TodoRecord).order_by(TodoRecord.created_at.desc())
        if project_id is not None:
            statement = statement.where(TodoRecord.project_id == str(project_id))
        return list(self.session.scalars(statement).all())

    def get(self, todo_id: UUID) -> TodoRecord | None:
        return self.session.get(TodoRecord, str(todo_id))

    def update(self, todo: TodoRecord, payload: TodoUpdate) -> TodoRecord:
        updates = payload.model_dump(exclude_unset=True)
        if "project_id" in updates and updates["project_id"] is not None:
            updates["project_id"] = str(updates["project_id"])

        for field, value in updates.items():
            setattr(todo, field, value)
        todo.updated_at = utc_now()

        self.session.add(todo)
        self.session.commit()
        self.session.refresh(todo)
        return todo

    def delete(self, todo: TodoRecord) -> None:
        self.session.delete(todo)
        self.session.commit()
