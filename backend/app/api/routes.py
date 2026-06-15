from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Response, status
from sqlalchemy.orm import Session

from app.db.session import get_session
from app.models.bill import BillCreate, BillRead, BillUpdate
from app.models.domain import MoodLog, Project
from app.models.memory import MemoryCreate, MemoryRead, MemoryUpdate
from app.models.todo import TodoCreate, TodoRead, TodoUpdate
from app.repositories.bill_repository import BillRepository
from app.repositories.memory_item_repository import MemoryItemRepository
from app.repositories.memory_repository import repository
from app.repositories.todo_repository import TodoRepository

router = APIRouter()


@router.get("/health", tags=["system"])
def health() -> dict[str, str]:
    return {"status": "ok"}


@router.get("/memory", response_model=list[MemoryRead], tags=["memory"])
def list_memory_items(
    include_archived: bool = False,
    kind: str | None = None,
    tag: str | None = None,
    session: Session = Depends(get_session),
) -> list[MemoryRead]:
    return MemoryItemRepository(session).list(include_archived=include_archived, kind=kind, tag=tag)


@router.post("/memory", response_model=MemoryRead, status_code=201, tags=["memory"])
def create_memory_item(item: MemoryCreate, session: Session = Depends(get_session)) -> MemoryRead:
    return MemoryItemRepository(session).create(item)


@router.get("/memory/{memory_id}", response_model=MemoryRead, tags=["memory"])
def get_memory_item(memory_id: UUID, session: Session = Depends(get_session)) -> MemoryRead:
    memory_item = MemoryItemRepository(session).get(memory_id)
    if memory_item is None:
        raise HTTPException(status_code=404, detail="Memory item not found")
    return memory_item


@router.patch("/memory/{memory_id}", response_model=MemoryRead, tags=["memory"])
def update_memory_item(
    memory_id: UUID,
    payload: MemoryUpdate,
    session: Session = Depends(get_session),
) -> MemoryRead:
    memory_repository = MemoryItemRepository(session)
    memory_item = memory_repository.get(memory_id)
    if memory_item is None:
        raise HTTPException(status_code=404, detail="Memory item not found")
    return memory_repository.update(memory_item, payload)


@router.delete("/memory/{memory_id}", status_code=status.HTTP_204_NO_CONTENT, tags=["memory"])
def delete_memory_item(memory_id: UUID, session: Session = Depends(get_session)) -> Response:
    memory_repository = MemoryItemRepository(session)
    memory_item = memory_repository.get(memory_id)
    if memory_item is None:
        raise HTTPException(status_code=404, detail="Memory item not found")
    memory_repository.delete(memory_item)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


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


@router.get("/bills", response_model=list[BillRead], tags=["bills"])
def list_bills(session: Session = Depends(get_session)) -> list[BillRead]:
    return BillRepository(session).list()


@router.post("/bills", response_model=BillRead, status_code=201, tags=["bills"])
def create_bill(bill: BillCreate, session: Session = Depends(get_session)) -> BillRead:
    return BillRepository(session).create(bill)


@router.get("/bills/{bill_id}", response_model=BillRead, tags=["bills"])
def get_bill(bill_id: UUID, session: Session = Depends(get_session)) -> BillRead:
    bill = BillRepository(session).get(bill_id)
    if bill is None:
        raise HTTPException(status_code=404, detail="Bill not found")
    return bill


@router.patch("/bills/{bill_id}", response_model=BillRead, tags=["bills"])
def update_bill(bill_id: UUID, payload: BillUpdate, session: Session = Depends(get_session)) -> BillRead:
    bill_repository = BillRepository(session)
    bill = bill_repository.get(bill_id)
    if bill is None:
        raise HTTPException(status_code=404, detail="Bill not found")
    return bill_repository.update(bill, payload)


@router.delete("/bills/{bill_id}", status_code=status.HTTP_204_NO_CONTENT, tags=["bills"])
def delete_bill(bill_id: UUID, session: Session = Depends(get_session)) -> Response:
    bill_repository = BillRepository(session)
    bill = bill_repository.get(bill_id)
    if bill is None:
        raise HTTPException(status_code=404, detail="Bill not found")
    bill_repository.delete(bill)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


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
