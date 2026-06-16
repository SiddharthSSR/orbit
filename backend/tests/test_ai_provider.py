import pytest

from app.core.config import Settings
from app.services.ai_provider import AIProviderConfigurationError, MockAIProvider, OpenAIProvider, build_ai_provider


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
    assert request["messages"][-1] == {"role": "user", "content": "What should I focus on today?"}


def test_ask_uses_mock_provider_by_default_without_network(client, monkeypatch) -> None:
    monkeypatch.delenv("ORBIT_AI_PROVIDER", raising=False)
    monkeypatch.delenv("OPENAI_API_KEY", raising=False)

    response = client.post("/ask", json={"question": "What should I focus on today?"})

    assert response.status_code == 200
    assert "available Orbit context" in response.json()["answer"]


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
