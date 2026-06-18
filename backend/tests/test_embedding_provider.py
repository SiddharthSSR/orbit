import pytest

from app.core.config import Settings
from app.services.embedding_provider import (
    EmbeddingProviderConfigurationError,
    MockEmbeddingProvider,
    build_embedding_provider,
)
from app.services.memory_retrieval import cosine_similarity


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


def test_mock_embedding_ai_token_matches_ai_memory() -> None:
    provider = MockEmbeddingProvider()

    similarity = cosine_similarity(
        provider.embed("AI"),
        provider.embed("AI Agents Reading List article ai agents"),
    )

    assert similarity > 0


def test_mock_embedding_ignores_generic_query_words_for_ai_ranking() -> None:
    provider = MockEmbeddingProvider()
    query = provider.embed("What did I save about AI?")
    ai_similarity = cosine_similarity(
        query,
        provider.embed("AI Agents Reading List article ai agents"),
    )
    worldlens_similarity = cosine_similarity(
        query,
        provider.embed("WorldLens Project Update camera translation ios"),
    )

    assert ai_similarity > worldlens_similarity
    assert worldlens_similarity == 0.0


def test_mock_embedding_worldlens_query_ranks_worldlens_memory_first() -> None:
    provider = MockEmbeddingProvider()
    query = provider.embed("How is WorldLens going?")
    worldlens_similarity = cosine_similarity(
        query,
        provider.embed("WorldLens Project Update camera translation ios"),
    )
    ai_similarity = cosine_similarity(
        query,
        provider.embed("AI Agents Reading List article ai agents"),
    )

    assert worldlens_similarity > ai_similarity
    assert ai_similarity == 0.0


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
