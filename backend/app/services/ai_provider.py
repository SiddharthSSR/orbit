from typing import Protocol


class AIProvider(Protocol):
    def generate_answer(self, question: str, context: str, history: list[dict[str, str]]) -> str:
        """Generate an assistant answer from the question, Orbit context, and chat history."""


class MockAIProvider:
    def generate_answer(self, question: str, context: str, history: list[dict[str, str]]) -> str:
        context_note = "available Orbit context" if context.strip() else "your question"
        history_note = f" I also considered {len(history)} recent chat message(s)." if history else ""
        return (
            f"Based on {context_note}, here is a starting point: {question.strip()} "
            "I can help connect your todos, bills, memory, moods, and projects once a real model is connected."
            f"{history_note}"
        )
