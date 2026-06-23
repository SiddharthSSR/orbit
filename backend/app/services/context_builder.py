from datetime import date, timedelta
from uuid import UUID

from sqlalchemy.orm import Session

from app.models.memory import MemoryRecord
from app.repositories.bill_repository import BillRepository
from app.repositories.memory_item_repository import MemoryItemRepository
from app.repositories.mood_repository import MoodRepository
from app.repositories.project_repository import ProjectRepository
from app.repositories.todo_repository import TodoRepository
from app.services.relevance import score_text, tokenize_query
from app.services.memory_retrieval import MemorySearchResult


def extract_context_sections(context: str) -> list[str]:
    sections: list[str] = []
    for line in context.splitlines():
        stripped = line.strip()
        if stripped.endswith(":"):
            sections.append(stripped[:-1])
    return sections


def extract_used_context_sections(context: str) -> list[str]:
    lines = context.splitlines()
    sections: list[str] = []
    for index, line in enumerate(lines):
        stripped = line.strip()
        if not stripped.endswith(":") or stripped.startswith("-"):
            continue
        body = lines[index + 1 :]
        next_section = next(
            (
                body_index
                for body_index, body_line in enumerate(body)
                if body_line.strip().endswith(":") and not body_line.strip().startswith("-")
            ),
            len(body),
        )
        body_lines = [body_line.strip() for body_line in body[:next_section] if body_line.strip()]
        if any(body_line != "- None" for body_line in body_lines):
            sections.append(stripped[:-1])
    return sections


class OrbitContextBuilder:
    def __init__(
        self,
        session: Session,
        *,
        question: str | None = None,
        today: date | None = None,
        section_limit: int = 5,
        mood_limit: int = 3,
        preview_length: int = 180,
        vector_memory_results: list[MemorySearchResult] | None = None,
        memory_limit: int | None = None,
        project_id: UUID | str | None = None,
    ) -> None:
        self.session = session
        self.query_tokens = tokenize_query(question or "")
        self.today = today or date.today()
        self.section_limit = section_limit
        self.mood_limit = mood_limit
        self.preview_length = preview_length
        self.vector_memory_results = vector_memory_results
        self.memory_limit = memory_limit or section_limit
        # Opt-in: scope the recent-memory section to one project's linked
        # memories. `None` keeps the existing unscoped behavior.
        self.project_id = project_id

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
            key=lambda todo: (
                -score_text(self.query_tokens, todo.title, todo.notes),
                *self._optional_due_date_sort_key(todo.due_date),
            ),
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
            key=lambda bill: (
                -score_text(self.query_tokens, bill.name, bill.notes, bill.currency, bill.recurrence),
                *self._due_date_sort_key(bill.due_date),
            ),
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
        all_memory_items = MemoryItemRepository(self.session).list(
            include_archived=False,
            project_id=self.project_id,
        )
        keyword_scores = {
            str(item.id): self._memory_keyword_score(item)
            for item in all_memory_items
        }
        keyword_memory_items = sorted(
            all_memory_items,
            key=lambda item: -keyword_scores[str(item.id)],
        )
        vector_scores: dict[str, float] = {}
        if self.vector_memory_results is None:
            memory_items = keyword_memory_items[: self.section_limit]
        else:
            candidates = {str(item.id): item for item in keyword_memory_items}
            for result in self.vector_memory_results:
                if self.project_id is not None and \
                        str(result.memory_item.project_id) != str(self.project_id):
                    continue
                memory_id = str(result.memory_item.id)
                candidates[memory_id] = result.memory_item
                vector_scores[memory_id] = max(
                    vector_scores.get(memory_id, 0.0),
                    result.score,
                )
                keyword_scores.setdefault(memory_id, self._memory_keyword_score(result.memory_item))
            keyword_order = {
                str(item.id): position
                for position, item in enumerate(keyword_memory_items)
            }
            memory_items = sorted(
                candidates.values(),
                key=lambda item: (
                    -(keyword_scores[str(item.id)] + vector_scores.get(str(item.id), 0.0)),
                    -keyword_scores[str(item.id)],
                    -vector_scores.get(str(item.id), 0.0),
                    keyword_order.get(str(item.id), len(keyword_order)),
                ),
            )[: self.memory_limit]
        if not memory_items:
            return "Recent memory:\n- None"

        lines: list[str] = []
        for item in memory_items:
            tags = f" [{', '.join(item.tags)}]" if item.tags else ""
            source_url = f" source: {item.source_url}" if item.source_url else ""
            vector_score = vector_scores.get(str(item.id))
            score = f" [vector_score={vector_score:.3f}]" if vector_score is not None else ""
            lines.append(
                f"- {item.title} ({item.kind}){tags}{source_url}{score}: {self._preview(item.body)}"
            )
        return "Recent memory:\n" + "\n".join(lines)

    def _memory_keyword_score(self, item: MemoryRecord) -> int:
        return score_text(
            self.query_tokens,
            item.title,
            item.body,
            item.kind,
            item.source_url,
            " ".join(item.tags),
        )

    def _latest_moods_section(self) -> str:
        moods = sorted(
            MoodRepository(self.session).list(limit=30),
            key=lambda mood: -score_text(self.query_tokens, mood.mood, mood.notes),
        )[: self.mood_limit]
        if not moods:
            return "Latest mood:\n- None"

        lines = [
            f"- {mood.check_in_date.isoformat()}: {mood.mood}, energy {mood.energy}/5"
            f"{f' - {self._preview(mood.notes)}' if mood.notes else ''}"
            for mood in moods
        ]
        return "Latest mood:\n" + "\n".join(lines)

    def _active_projects_section(self) -> str:
        projects = sorted(
            ProjectRepository(self.session).list(status="active"),
            key=lambda project: -score_text(
                self.query_tokens,
                project.name,
                project.description,
                project.area,
                project.status,
                " ".join(project.tags),
            ),
        )[: self.section_limit]
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
