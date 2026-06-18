from typing import Protocol

from app.core.config import Settings


SYSTEM_PROMPT = (
    "You are Orbit, Siddharth's personal second-brain assistant. "
    "Answer using the Orbit context first, and do not invent facts that are not in the context. "
    "Start with the direct answer in the first sentence. "
    "When several items are relevant, use short bullet points instead of long paragraphs. "
    "Include concrete details such as dates, amounts, and status when the context provides them. "
    "For bills and todos, prioritize items that are overdue, due today, or due soon. "
    "For memory questions, cite the memory item by its title naturally. "
    "Be concise, and mention uncertainty only when the context is genuinely insufficient; "
    "in that case ask for the missing detail instead of guessing. "
    'Avoid filler phrases such as repeatedly saying "based on the context". '
    'For action-oriented questions, end with a short "Next step:" suggestion when one is helpful.'
)

# Context section headers that carry real Orbit data (excludes the "Today" date stamp).
DATA_SECTIONS = ("Open todos", "Unpaid bills", "Recent memory", "Latest mood", "Active projects")


class AIProvider(Protocol):
    def generate_answer(self, question: str, context: str, history: list[dict[str, str]]) -> str:
        """Generate an assistant answer from the question, Orbit context, and chat history."""


class AIProviderConfigurationError(RuntimeError):
    pass


class MockAIProvider:
    """Deterministic, OpenAI-free provider used by tests and local evals.

    It inspects the Orbit context enough to produce a representative, structured
    answer for the common eval intents (focus_today, upcoming_bills, saved_ai,
    worldlens_status, furlenco_bill, projects_attention, recent_saves,
    mood_next_step, overdue_items, orbit_progress). It never calls a network
    model; output depends only on the question text and context string.
    """

    def generate_answer(self, question: str, context: str, history: list[dict[str, str]]) -> str:
        sections = self._parse_sections(context)
        useful = {name: items for name in DATA_SECTIONS if (items := sections.get(name))}
        if not useful:
            return (
                "I don't have enough Orbit context to answer that yet. "
                "Add the relevant todo, bill, memory, mood, or project and I can give you a specific answer."
            )

        lead, body_items, next_step = self._plan(question, useful)
        lines = [lead]
        lines.extend(f"- {item}" for item in body_items)
        if next_step:
            lines.append(f"Next step: {next_step}")
        return "\n".join(lines)

    def _plan(
        self,
        question: str,
        useful: dict[str, list[str]],
    ) -> tuple[str, list[str], str | None]:
        intent = self._classify(question)

        if intent == "overdue_items":
            urgent = self._collect(
                useful, ("Open todos", "Unpaid bills"), transform=self._urgent_only
            )
            if urgent:
                return (
                    "Here's what's overdue or due today.",
                    urgent,
                    f"Clear {self._short_label(urgent[0])} first.",
                )
            return ("Nothing is overdue or due today.", [], None)

        if intent == "bills":
            bills = useful.get("Unpaid bills", [])
            if not bills:
                return ("You have no unpaid bills in your Orbit context right now.", [], None)
            return (
                f"You have {len(bills)} unpaid bill(s) coming up, most urgent first.",
                bills[:3],
                f"Pay {self._short_label(bills[0])} first.",
            )

        if intent == "memory_recall":
            memory = useful.get("Recent memory", [])
            if not memory:
                return ("I don't see any saved memory for that yet.", [], None)
            return (
                f'The most relevant save is "{self._memory_title(memory[0])}".',
                memory[:3],
                None,
            )

        if intent == "project_status":
            projects = useful.get("Active projects", [])
            lead = (
                f'Here\'s the latest on "{self._memory_title(projects[0])}".'
                if projects
                else "Here's the latest from your projects."
            )
            return (
                lead,
                self._collect(useful, ("Active projects", "Recent memory", "Open todos")),
                self._first_todo_next_step(useful),
            )

        if intent == "projects_attention":
            projects = useful.get("Active projects", [])
            return (
                f"You have {len(projects)} active project(s) to keep moving."
                if projects
                else "You have no active projects that need attention right now.",
                self._collect(useful, ("Active projects", "Open todos", "Recent memory")),
                self._first_todo_next_step(useful),
            )

        if intent == "mood_next_step":
            mood = useful.get("Latest mood", [])
            lead = (
                f"Your latest mood check-in is {self._short_label(mood[0])}."
                if mood
                else "I don't have a recent mood check-in for you."
            )
            return (
                lead,
                self._collect(useful, ("Open todos", "Active projects")),
                self._first_todo_next_step(useful),
            )

        # focus_today and the general fallback.
        return (
            "Here's where to focus today.",
            self._collect(useful, ("Open todos", "Unpaid bills", "Latest mood", "Active projects")),
            self._first_todo_next_step(useful),
        )

    def _collect(
        self,
        useful: dict[str, list[str]],
        section_names: tuple[str, ...],
        *,
        per_section: int = 3,
        transform=None,
    ) -> list[str]:
        items: list[str] = []
        for name in section_names:
            section_items = useful.get(name, [])
            if transform is not None:
                section_items = transform(section_items)
            items.extend(section_items[:per_section])
        return items

    def _classify(self, question: str) -> str:
        q = question.lower()
        if "overdue" in q or "due today" in q:
            return "overdue_items"
        if "bill" in q:
            return "bills"
        if "mood" in q:
            return "mood_next_step"
        if "focus" in q:
            return "focus_today"
        if "worldlens" in q or "orbit" in q or "status" in q or "how is" in q or "how's" in q:
            return "project_status"
        if "project" in q:
            return "projects_attention"
        if "save" in q or "saved" in q or "recently" in q:
            return "memory_recall"
        return "focus_today"

    def _first_todo_next_step(self, useful: dict[str, list[str]]) -> str | None:
        todos = useful.get("Open todos", [])
        if todos:
            return f"Start with {self._short_label(todos[0])}."
        return None

    def _urgent_only(self, items: list[str]) -> list[str]:
        return [item for item in items if "[Overdue]" in item or "[Due today]" in item]

    def _short_label(self, item: str) -> str:
        """Reduce a context bullet to a readable name for a next-step sentence."""
        text = item
        for prefix in ("[Overdue] ", "[Due today] ", "[Due soon] ", "[No due date] "):
            if text.startswith(prefix):
                text = text[len(prefix):]
                break
        for separator in (":", " (due ", " (", " - "):
            index = text.find(separator)
            if index != -1:
                text = text[:index]
        return text.strip().rstrip(".")

    def _memory_title(self, item: str) -> str:
        for separator in (" (", " [", ": "):
            index = item.find(separator)
            if index != -1:
                return item[:index].strip()
        return item.strip()

    def _parse_sections(self, context: str) -> dict[str, list[str]]:
        sections: dict[str, list[str]] = {}
        current: str | None = None
        for raw_line in context.splitlines():
            line = raw_line.strip()
            if not line:
                continue
            if line.endswith(":"):
                current = line[:-1]
                sections.setdefault(current, [])
                continue
            if current is not None and line.startswith("- ") and line != "- None":
                sections[current].append(line[2:].strip())
        return sections


class OpenAIProvider:
    def __init__(
        self,
        *,
        api_key: str,
        model: str,
        timeout_seconds: float = 30,
        client: object | None = None,
    ) -> None:
        self.model = model
        self.timeout_seconds = timeout_seconds
        if client is None:
            from openai import OpenAI

            client = OpenAI(api_key=api_key, timeout=timeout_seconds)
        self.client = client

    def generate_answer(self, question: str, context: str, history: list[dict[str, str]]) -> str:
        messages = self._build_messages(question=question, context=context, history=history)
        response = self.client.chat.completions.create(
            model=self.model,
            messages=messages,
            timeout=self.timeout_seconds,
        )
        answer = response.choices[0].message.content
        return answer.strip() if answer else ""

    def _build_messages(self, *, question: str, context: str, history: list[dict[str, str]]) -> list[dict[str, str]]:
        messages: list[dict[str, str]] = [{"role": "system", "content": SYSTEM_PROMPT}]

        if context.strip():
            messages.append({"role": "system", "content": f"Orbit context:\n{context.strip()}"})

        for message in history[-10:]:
            role = message.get("role", "")
            content = message.get("content", "")
            if role not in {"user", "assistant", "system"} or not content:
                continue
            messages.append({"role": role, "content": content})

        messages.append({"role": "user", "content": question.strip()})
        return messages


def build_ai_provider(settings: Settings) -> AIProvider:
    provider_name = settings.ai_provider.strip().lower()
    if provider_name in {"", "mock"}:
        return MockAIProvider()
    if provider_name == "openai":
        if not settings.openai_api_key:
            raise AIProviderConfigurationError("OPENAI_API_KEY is required when ORBIT_AI_PROVIDER=openai")
        return OpenAIProvider(
            api_key=settings.openai_api_key,
            model=settings.openai_model,
            timeout_seconds=settings.ai_timeout_seconds,
        )
    raise AIProviderConfigurationError(f"Unsupported ORBIT_AI_PROVIDER: {settings.ai_provider}")
