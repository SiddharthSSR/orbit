from typing import Protocol

from app.core.config import Settings


SYSTEM_PROMPT = (
    "You are Orbit, Siddharth's personal second-brain assistant. "
    "Use Orbit context first. Give practical next steps. Be concise. "
    "Do not invent facts not in context. If context is missing, ask for the missing detail."
)


class AIProvider(Protocol):
    def generate_answer(self, question: str, context: str, history: list[dict[str, str]]) -> str:
        """Generate an assistant answer from the question, Orbit context, and chat history."""


class AIProviderConfigurationError(RuntimeError):
    pass


class MockAIProvider:
    def generate_answer(self, question: str, context: str, history: list[dict[str, str]]) -> str:
        context_note = "available Orbit context" if context.strip() else "your question"
        sections = self._context_sections(context)
        sections_note = f" Context sections: {', '.join(sections)}." if sections else " Context sections: none."
        history_note = f" I also considered {len(history)} recent chat message(s)." if history else ""
        return (
            f"Based on {context_note}, here is a starting point: {question.strip()} "
            "I can help connect your todos, bills, memory, moods, and projects once a real model is connected."
            f"{sections_note}{history_note}"
        )

    def _context_sections(self, context: str) -> list[str]:
        sections: list[str] = []
        for line in context.splitlines():
            stripped = line.strip()
            if stripped.endswith(":"):
                sections.append(stripped[:-1])
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
