from datetime import date, timedelta

from sqlalchemy.orm import Session

from app.repositories.bill_repository import BillRepository
from app.repositories.memory_item_repository import MemoryItemRepository
from app.repositories.mood_repository import MoodRepository
from app.repositories.project_repository import ProjectRepository
from app.repositories.todo_repository import TodoRepository


class OrbitContextBuilder:
    def __init__(
        self,
        session: Session,
        *,
        today: date | None = None,
        section_limit: int = 5,
        mood_limit: int = 3,
        preview_length: int = 180,
    ) -> None:
        self.session = session
        self.today = today or date.today()
        self.section_limit = section_limit
        self.mood_limit = mood_limit
        self.preview_length = preview_length

    def build_context(self) -> str:
        sections = [
            f"Today:\n- {self.today.isoformat()}",
            self._open_todos_section(),
            self._unpaid_bills_section(),
            self._recent_memory_section(),
            self._latest_moods_section(),
            self._active_projects_section(),
        ]
        return "\n\n".join(section for section in sections if section)

    def _open_todos_section(self) -> str:
        todos = sorted(
            [todo for todo in TodoRepository(self.session).list() if not todo.is_complete],
            key=lambda todo: self._optional_due_date_sort_key(todo.due_date),
        )[: self.section_limit]
        if not todos:
            return "Open todos:\n- None"

        lines: list[str] = []
        for todo in todos:
            label = self._optional_due_label(todo.due_date)
            due = f" (due {todo.due_date.isoformat()})" if todo.due_date else ""
            notes = f" - {self._preview(todo.notes)}" if todo.notes else ""
            lines.append(f"- [{label}] {todo.title}{due}{notes}")
        return "Open todos:\n" + "\n".join(lines)

    def _unpaid_bills_section(self) -> str:
        bills = sorted(
            [bill for bill in BillRepository(self.session).list() if not bill.is_paid],
            key=lambda bill: self._due_date_sort_key(bill.due_date),
        )[: self.section_limit]
        if not bills:
            return "Unpaid bills:\n- None"

        lines: list[str] = []
        for bill in bills:
            label = self._due_label(bill.due_date)
            amount = f" ({bill.amount:g} {bill.currency})" if bill.amount is not None else ""
            notes = f" - {self._preview(bill.notes)}" if bill.notes else ""
            lines.append(f"- [{label}] {bill.name}: due {bill.due_date.isoformat()}{amount}{notes}")
        return "Unpaid bills:\n" + "\n".join(lines)

    def _recent_memory_section(self) -> str:
        memory_items = MemoryItemRepository(self.session).list(include_archived=False)[: self.section_limit]
        if not memory_items:
            return "Recent memory:\n- None"

        lines: list[str] = []
        for item in memory_items:
            tags = f" [{', '.join(item.tags)}]" if item.tags else ""
            source_url = f" source: {item.source_url}" if item.source_url else ""
            lines.append(f"- {item.title} ({item.kind}){tags}{source_url}: {self._preview(item.body)}")
        return "Recent memory:\n" + "\n".join(lines)

    def _latest_moods_section(self) -> str:
        moods = MoodRepository(self.session).list(limit=self.mood_limit)
        if not moods:
            return "Latest mood:\n- None"

        lines = [
            f"- {mood.check_in_date.isoformat()}: {mood.mood}, energy {mood.energy}/5"
            f"{f' - {self._preview(mood.notes)}' if mood.notes else ''}"
            for mood in moods
        ]
        return "Latest mood:\n" + "\n".join(lines)

    def _active_projects_section(self) -> str:
        projects = ProjectRepository(self.session).list(status="active")[: self.section_limit]
        if not projects:
            return "Active projects:\n- None"

        lines: list[str] = []
        for project in projects:
            area = f" ({project.area})" if project.area else ""
            tags = f" [{', '.join(project.tags)}]" if project.tags else ""
            description = f": {self._preview(project.description)}" if project.description else ""
            lines.append(f"- {project.name}{area}{tags}{description}")
        return "Active projects:\n" + "\n".join(lines)

    def _optional_due_date_sort_key(self, due_date: date | None) -> tuple[int, date]:
        if due_date is None:
            return (2, date.max)
        if due_date <= self.today:
            return (0, due_date)
        return (1, due_date)

    def _due_date_sort_key(self, due_date: date) -> tuple[int, date]:
        if due_date <= self.today:
            return (0, due_date)
        return (1, due_date)

    def _optional_due_label(self, due_date: date | None) -> str:
        if due_date is None:
            return "No due date"
        return self._due_label(due_date)

    def _due_label(self, due_date: date) -> str:
        if due_date < self.today:
            return "Overdue"
        if due_date == self.today:
            return "Due today"
        if due_date <= self.today + timedelta(days=7):
            return "Due soon"
        return "Due soon"

    def _preview(self, value: str | None) -> str:
        if value is None:
            return ""
        normalized = " ".join(value.split())
        if len(normalized) <= self.preview_length:
            return normalized
        return f"{normalized[: self.preview_length - 3].rstrip()}..."
