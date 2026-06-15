from fastapi import APIRouter

from app.models.domain import Bill, MemoryItem, MoodLog, Project, Todo
from app.repositories.memory_repository import repository

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


@router.get("/todos", response_model=list[Todo], tags=["todos"])
def list_todos() -> list[Todo]:
    return repository.list_todos()


@router.post("/todos", response_model=Todo, status_code=201, tags=["todos"])
def create_todo(todo: Todo) -> Todo:
    return repository.add_todo(todo)


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

