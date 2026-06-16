from sqlalchemy.orm import Session

from app.repositories.bill_repository import BillRepository
from app.repositories.memory_item_repository import MemoryItemRepository
from app.repositories.mood_repository import MoodRepository
from app.repositories.project_repository import ProjectRepository
from app.repositories.todo_repository import TodoRepository


class OrbitContextBuilder:
    def __init__(self, session: Session, *, section_limit: int = 5) -> None:
        self.session = session
        self.section_limit = section_limit

    def build_context(self) -> str:
        sections = [
            self._open_todos_section(),
            self._unpaid_bills_section(),
            self._recent_memory_section(),
            self._latest_moods_section(),
            self._active_projects_section(),
        ]
        return "\n\n".join(section for section in sections if section)

    def _open_todos_section(self) -> str:
        todos = [todo for todo in TodoRepository(self.session).list() if not todo.is_complete][: self.section_limit]
        if not todos:
            return "Open todos:\n- None"
        return "Open todos:\n" + "\n".join(f"- {todo.title}" for todo in todos)

    def _unpaid_bills_section(self) -> str:
        bills = [bill for bill in BillRepository(self.session).list() if not bill.is_paid][: self.section_limit]
        if not bills:
            return "Unpaid bills:\n- None"

        lines: list[str] = []
        for bill in bills:
            amount = f" ({bill.amount:g} {bill.currency})" if bill.amount is not None else ""
            lines.append(f"- {bill.name}: due {bill.due_date.isoformat()}{amount}")
        return "Unpaid bills:\n" + "\n".join(lines)

    def _recent_memory_section(self) -> str:
        memory_items = MemoryItemRepository(self.session).list(include_archived=False)[: self.section_limit]
        if not memory_items:
            return "Recent memory:\n- None"

        lines: list[str] = []
        for item in memory_items:
            tags = f" [{', '.join(item.tags)}]" if item.tags else ""
            lines.append(f"- {item.title} ({item.kind}){tags}: {item.body}")
        return "Recent memory:\n" + "\n".join(lines)

    def _latest_moods_section(self) -> str:
        moods = MoodRepository(self.session).list(limit=self.section_limit)
        if not moods:
            return "Latest moods:\n- None"

        lines = [
            f"- {mood.check_in_date.isoformat()}: {mood.mood}, energy {mood.energy}/5"
            for mood in moods
        ]
        return "Latest moods:\n" + "\n".join(lines)

    def _active_projects_section(self) -> str:
        projects = ProjectRepository(self.session).list(status="active")[: self.section_limit]
        if not projects:
            return "Active projects:\n- None"

        lines: list[str] = []
        for project in projects:
            area = f" ({project.area})" if project.area else ""
            tags = f" [{', '.join(project.tags)}]" if project.tags else ""
            description = f": {project.description}" if project.description else ""
            lines.append(f"- {project.name}{area}{tags}{description}")
        return "Active projects:\n" + "\n".join(lines)
