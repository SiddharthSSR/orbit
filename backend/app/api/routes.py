from uuid import UUID
from datetime import date

from fastapi import APIRouter, Depends, HTTPException, Response, status
from sqlalchemy.orm import Session

from app.db.session import get_session
from app.models.bill import BillCreate, BillRead, BillUpdate
from app.models.memory import MemoryCreate, MemoryRead, MemoryUpdate
from app.models.mood import MoodCreate, MoodRead, MoodUpdate
from app.models.project import ProjectCreate, ProjectRead, ProjectUpdate
from app.models.todo import TodoCreate, TodoRead, TodoUpdate
from app.repositories.bill_repository import BillRepository
from app.repositories.memory_item_repository import MemoryItemRepository
from app.repositories.mood_repository import MoodRepository
from app.repositories.project_repository import ProjectRepository
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


@router.get("/projects", response_model=list[ProjectRead], tags=["projects"])
def list_projects(
    include_archived: bool = False,
    status: str | None = None,
    tag: str | None = None,
    area: str | None = None,
    session: Session = Depends(get_session),
) -> list[ProjectRead]:
    return ProjectRepository(session).list(
        include_archived=include_archived,
        status=status,
        tag=tag,
        area=area,
    )


@router.post("/projects", response_model=ProjectRead, status_code=201, tags=["projects"])
def create_project(project: ProjectCreate, session: Session = Depends(get_session)) -> ProjectRead:
    return ProjectRepository(session).create(project)


@router.get("/projects/{project_id}", response_model=ProjectRead, tags=["projects"])
def get_project(project_id: UUID, session: Session = Depends(get_session)) -> ProjectRead:
    project = ProjectRepository(session).get(project_id)
    if project is None:
        raise HTTPException(status_code=404, detail="Project not found")
    return project


@router.patch("/projects/{project_id}", response_model=ProjectRead, tags=["projects"])
def update_project(
    project_id: UUID,
    payload: ProjectUpdate,
    session: Session = Depends(get_session),
) -> ProjectRead:
    project_repository = ProjectRepository(session)
    project = project_repository.get(project_id)
    if project is None:
        raise HTTPException(status_code=404, detail="Project not found")
    return project_repository.update(project, payload)


@router.delete("/projects/{project_id}", status_code=status.HTTP_204_NO_CONTENT, tags=["projects"])
def delete_project(project_id: UUID, session: Session = Depends(get_session)) -> Response:
    project_repository = ProjectRepository(session)
    project = project_repository.get(project_id)
    if project is None:
        raise HTTPException(status_code=404, detail="Project not found")
    project_repository.delete(project)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get("/moods", response_model=list[MoodRead], tags=["moods"])
def list_mood_logs(
    limit: int = 30,
    from_date: date | None = None,
    to_date: date | None = None,
    session: Session = Depends(get_session),
) -> list[MoodRead]:
    return MoodRepository(session).list(limit=limit, from_date=from_date, to_date=to_date)


@router.post("/moods", response_model=MoodRead, status_code=201, tags=["moods"])
def create_mood_log(mood_log: MoodCreate, session: Session = Depends(get_session)) -> MoodRead:
    return MoodRepository(session).create(mood_log)


@router.get("/moods/{mood_id}", response_model=MoodRead, tags=["moods"])
def get_mood_log(mood_id: UUID, session: Session = Depends(get_session)) -> MoodRead:
    mood = MoodRepository(session).get(mood_id)
    if mood is None:
        raise HTTPException(status_code=404, detail="Mood check-in not found")
    return mood


@router.patch("/moods/{mood_id}", response_model=MoodRead, tags=["moods"])
def update_mood_log(mood_id: UUID, payload: MoodUpdate, session: Session = Depends(get_session)) -> MoodRead:
    mood_repository = MoodRepository(session)
    mood = mood_repository.get(mood_id)
    if mood is None:
        raise HTTPException(status_code=404, detail="Mood check-in not found")
    return mood_repository.update(mood, payload)


@router.delete("/moods/{mood_id}", status_code=status.HTTP_204_NO_CONTENT, tags=["moods"])
def delete_mood_log(mood_id: UUID, session: Session = Depends(get_session)) -> Response:
    mood_repository = MoodRepository(session)
    mood = mood_repository.get(mood_id)
    if mood is None:
        raise HTTPException(status_code=404, detail="Mood check-in not found")
    mood_repository.delete(mood)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
