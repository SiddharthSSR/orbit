import pytest

from app.core.config import Settings
from app.services.ai_provider import (
    SYSTEM_PROMPT,
    AIProviderConfigurationError,
    MockAIProvider,
    OpenAIProvider,
    build_ai_provider,
)


FOCUS_CONTEXT = (
    "Today:\n- 2026-06-18\n\n"
    "Open todos:\n"
    "- [Overdue] Ship Orbit Ask eval improvements (due 2026-06-16)\n"
    "- [Due today] Review WorldLens prototype (due 2026-06-18)\n\n"
    "Unpaid bills:\n"
    "- [Overdue] Credit Card Payment: due 2026-06-14 (8500 INR)\n"
    "- [Due soon] Furlenco Furniture Rent: due 2026-06-21 (12000 INR)\n\n"
    "Recent memory:\n"
    "- AI Agents Reading List (article) [ai, agents]: Agent memory and retrieval\n"
    "- Weekend Grocery List (note): Coffee and oats\n\n"
    "Latest mood:\n- 2026-06-17: focused, energy 4/5\n\n"
    "Active projects:\n- Orbit (personal) [app]: Personal second brain"
)


def test_default_provider_is_mock_when_env_unset(monkeypatch) -> None:
    monkeypatch.delenv("ORBIT_AI_PROVIDER", raising=False)
    monkeypatch.delenv("OPENAI_API_KEY", raising=False)

    provider = build_ai_provider(Settings())

    assert isinstance(provider, MockAIProvider)


def test_mock_provider_selected_from_env(monkeypatch) -> None:
    monkeypatch.setenv("ORBIT_AI_PROVIDER", "mock")

    provider = build_ai_provider(Settings())

    assert isinstance(provider, MockAIProvider)


def test_openai_provider_without_api_key_raises_clear_error(monkeypatch) -> None:
    monkeypatch.setenv("ORBIT_AI_PROVIDER", "openai")
    monkeypatch.delenv("OPENAI_API_KEY", raising=False)

    with pytest.raises(AIProviderConfigurationError, match="OPENAI_API_KEY is required"):
        build_ai_provider(Settings())


def test_openai_provider_uses_fake_client_without_network() -> None:
    fake_client = FakeOpenAIClient(answer="Focus on the highest-priority todo first.")
    provider = OpenAIProvider(
        api_key="test-key",
        model="test-model",
        timeout_seconds=12,
        client=fake_client,
    )

    answer = provider.generate_answer(
        question="What should I focus on today?",
        context="Open todos:\n- Plan day",
        history=[{"role": "assistant", "content": "Earlier answer"}],
    )

    assert answer == "Focus on the highest-priority todo first."
    request = fake_client.chat.completions.requests[0]
    assert request["model"] == "test-model"
    assert request["timeout"] == 12
    assert request["messages"][0]["role"] == "system"
    assert "personal second-brain assistant" in request["messages"][0]["content"]
    assert request["messages"][1]["content"] == "Orbit context:\nOpen todos:\n- Plan day"
    assert request["messages"][2] == {
        "role": "system",
        "content": "Recent conversation in this Ask session follows.",
    }
    assert request["messages"][3] == {"role": "assistant", "content": "Earlier answer"}
    assert request["messages"][-1] == {"role": "user", "content": "What should I focus on today?"}


def test_system_prompt_contains_answer_quality_instructions() -> None:
    lowered = SYSTEM_PROMPT.lower()

    assert "start with the direct answer" in lowered
    assert "bullet" in lowered
    assert "overdue" in lowered and "due today" in lowered
    assert "next step" in lowered
    assert "do not invent" in lowered
    assert "cite the memory item" in lowered
    assert "recent conversation" in lowered


def test_openai_provider_omits_recent_conversation_block_without_history() -> None:
    provider = OpenAIProvider(
        api_key="test-key",
        model="test-model",
        client=FakeOpenAIClient(answer="Answer"),
    )

    messages = provider._build_messages(question="First question", context="", history=[])

    assert all("Recent conversation" not in message["content"] for message in messages)


def test_system_prompt_requires_overdue_bills_in_coming_up_answers() -> None:
    lowered = SYSTEM_PROMPT.lower()

    assert "coming up" in lowered
    assert "overdue first" in lowered
    assert "never omit an" in lowered and "overdue unpaid bill" in lowered


def test_mock_provider_returns_direct_answer_for_ai_memory_question() -> None:
    provider = MockAIProvider()

    answer = provider.generate_answer(
        question="What did I save about AI?",
        context=FOCUS_CONTEXT,
        history=[],
    )

    # Direct opening that cites the memory title naturally.
    assert answer.startswith("The most relevant save is")
    assert "AI Agents Reading List" in answer


def test_mock_provider_returns_useful_answer_for_bills_question() -> None:
    provider = MockAIProvider()

    answer = provider.generate_answer(
        question="What bills are coming up?",
        context=FOCUS_CONTEXT,
        history=[],
    )

    assert "unpaid bill" in answer.lower()
    assert "Credit Card Payment" in answer
    # Overdue bill is surfaced ahead of the due-soon bill.
    assert answer.index("Credit Card Payment") < answer.index("Furlenco Furniture Rent")
    assert "Next step:" in answer


def test_mock_provider_returns_useful_answer_for_overdue_question() -> None:
    provider = MockAIProvider()

    answer = provider.generate_answer(
        question="What is overdue or due today?",
        context=FOCUS_CONTEXT,
        history=[],
    )

    assert "overdue or due today" in answer.lower()
    assert "Ship Orbit Ask eval improvements" in answer
    assert "Credit Card Payment" in answer
    # The due-soon bill is not urgent and should be excluded.
    assert "Furlenco Furniture Rent" not in answer


def test_mock_provider_falls_back_when_no_useful_context() -> None:
    provider = MockAIProvider()

    answer = provider.generate_answer(
        question="What should I focus on today?",
        context="Today:\n- 2026-06-18\n\nOpen todos:\n- None\n\nUnpaid bills:\n- None",
        history=[],
    )

    assert "Orbit context" in answer


def test_ask_uses_mock_provider_by_default_without_network(client, monkeypatch) -> None:
    monkeypatch.delenv("ORBIT_AI_PROVIDER", raising=False)
    monkeypatch.delenv("OPENAI_API_KEY", raising=False)

    response = client.post("/ask", json={"question": "What should I focus on today?"})

    assert response.status_code == 200
    # Empty test database -> mock provider returns its no-context fallback.
    assert "Orbit context" in response.json()["answer"]


class FakeOpenAIClient:
    def __init__(self, answer: str) -> None:
        self.chat = FakeChat(answer)


class FakeChat:
    def __init__(self, answer: str) -> None:
        self.completions = FakeCompletions(answer)


class FakeCompletions:
    def __init__(self, answer: str) -> None:
        self.answer = answer
        self.requests: list[dict] = []

    def create(self, **kwargs):
        self.requests.append(kwargs)
        return FakeCompletionResponse(self.answer)


class FakeCompletionResponse:
    def __init__(self, answer: str) -> None:
        self.choices = [FakeChoice(answer)]


class FakeChoice:
    def __init__(self, answer: str) -> None:
        self.message = FakeMessage(answer)


class FakeMessage:
    def __init__(self, answer: str) -> None:
        self.content = answer
