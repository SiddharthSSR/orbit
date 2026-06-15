from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Response, status
from sqlalchemy.orm import Session

from app.db.session import get_session
from app.models.domain import Bill, MemoryItem, MoodLog, Project
from app.models.todo import TodoCreate, TodoRead, TodoUpdate
from app.repositories.memory_repository import repository
from app.repositories.todo_repository import TodoRepository

router = APIRouter()


@router.get("/health", tags=["system"])
def health() -> dict[str, str]:
    return {"status": "ok"}


@router.get("/memory", response_model=list[MemoryItem], tags=["memory"])
def list_memory_items() -> list[MemoryItem]:
    return repository.list_memory_items()


@router.post("/memory", response_model=MemoryItem, status_code=201, tags=["memory"])
def create_memory_item(item: MemoryItem) -> MemoryItem:
    return repository.add_memory_item(item)


@router.get("/todos", response_model=list[TodoRead], tags=["todos"])
def list_todos(session: Session = Depends(get_session)) -> list[TodoRead]:
    return TodoRepository(session).list()


@router.post("/todos", response_model=TodoRead, status_code=201, tags=["todos"])
def create_todo(todo: TodoCreate, session: Session = Depends(get_session)) -> TodoRead:
    return TodoRepository(session).create(todo)


@router.get("/todos/{todo_id}", response_model=TodoRead, tags=["todos"])
def get_todo(todo_id: UUID, session: Session = Depends(get_session)) -> TodoRead:
    todo = TodoRepository(session).get(todo_id)
    if todo is None:
        raise HTTPException(status_code=404, detail="Todo not found")
    return todo


@router.patch("/todos/{todo_id}", response_model=TodoRead, tags=["todos"])
def update_todo(todo_id: UUID, payload: TodoUpdate, session: Session = Depends(get_session)) -> TodoRead:
    todo_repository = TodoRepository(session)
    todo = todo_repository.get(todo_id)
    if todo is None:
        raise HTTPException(status_code=404, detail="Todo not found")
    return todo_repository.update(todo, payload)


@router.delete("/todos/{todo_id}", status_code=status.HTTP_204_NO_CONTENT, tags=["todos"])
def delete_todo(todo_id: UUID, session: Session = Depends(get_session)) -> Response:
    todo_repository = TodoRepository(session)
    todo = todo_repository.get(todo_id)
    if todo is None:
        raise HTTPException(status_code=404, detail="Todo not found")
    todo_repository.delete(todo)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get("/bills", response_model=list[Bill], tags=["bills"])
def list_bills() -> list[Bill]:
    return repository.list_bills()


@router.post("/bills", response_model=Bill, status_code=201, tags=["bills"])
def create_bill(bill: Bill) -> Bill:
    return repository.add_bill(bill)


@router.get("/projects", response_model=list[Project], tags=["projects"])
def list_projects() -> list[Project]:
    return repository.list_projects()


@router.post("/projects", response_model=Project, status_code=201, tags=["projects"])
def create_project(project: Project) -> Project:
    return repository.add_project(project)


@router.get("/moods", response_model=list[MoodLog], tags=["moods"])
def list_mood_logs() -> list[MoodLog]:
    return repository.list_mood_logs()


@router.post("/moods", response_model=MoodLog, status_code=201, tags=["moods"])
def create_mood_log(mood_log: MoodLog) -> MoodLog:
    return repository.add_mood_log(mood_log)
