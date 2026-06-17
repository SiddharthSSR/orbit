import pytest

from app.core.config import Settings
from app.services.embedding_provider import (
    EmbeddingProviderConfigurationError,
    MockEmbeddingProvider,
    build_embedding_provider,
)


def test_mock_embedding_provider_is_deterministic() -> None:
    provider = MockEmbeddingProvider(dimensions=32)

    first = provider.embed("AI agents and memory")
    second = provider.embed("AI agents and memory")

    assert first == second
    assert len(first) == 32
    assert any(component > 0 for component in first)


def test_embedding_provider_defaults_to_mock() -> None:
    provider = build_embedding_provider(Settings(embedding_provider="mock"))

    assert isinstance(provider, MockEmbeddingProvider)
    assert provider.provider_name == "mock"


def test_openai_embedding_provider_requires_api_key() -> None:
    settings = Settings(
        embedding_provider="openai",
        openai_api_key=None,
    )

    with pytest.raises(
        EmbeddingProviderConfigurationError,
        match="OPENAI_API_KEY is required when ORBIT_EMBEDDING_PROVIDER=openai",
    ):
        build_embedding_provider(settings)
