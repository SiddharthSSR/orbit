import hashlib
from typing import Protocol

from app.core.config import Settings
from app.services.relevance import tokenize_query


DEFAULT_MOCK_EMBEDDING_DIMENSIONS = 64
DEFAULT_MOCK_EMBEDDING_MODEL = f"mock-token-hash-v2-{DEFAULT_MOCK_EMBEDDING_DIMENSIONS}d"
MOCK_EMBEDDING_STOPWORDS = {"save", "saved"}


class EmbeddingProvider(Protocol):
    provider_name: str
    model: str

    def embed(self, text: str) -> list[float]:
        """Return a vector representation of text."""


class EmbeddingProviderConfigurationError(RuntimeError):
    pass


class MockEmbeddingProvider:
    provider_name = "mock"

    def __init__(self, dimensions: int = DEFAULT_MOCK_EMBEDDING_DIMENSIONS) -> None:
        if dimensions <= 0:
            raise ValueError("Mock embedding dimensions must be positive")
        self.dimensions = dimensions
        self.model = f"mock-token-hash-v2-{dimensions}d"

    def embed(self, text: str) -> list[float]:
        vector = [0.0] * self.dimensions
        tokens = tokenize_query(text) - MOCK_EMBEDDING_STOPWORDS
        for token in tokens:
            digest = hashlib.sha256(token.encode("utf-8")).digest()
            bucket = int.from_bytes(digest[:8], "big") % self.dimensions
            vector[bucket] += 1.0
        return vector


class OpenAIEmbeddingProvider:
    provider_name = "openai"

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

    def embed(self, text: str) -> list[float]:
        response = self.client.embeddings.create(input=text, model=self.model)
        return [float(component) for component in response.data[0].embedding]


def build_embedding_provider(settings: Settings) -> EmbeddingProvider:
    provider_name = settings.embedding_provider.strip().lower()
    if provider_name in {"", "mock"}:
        return MockEmbeddingProvider()
    if provider_name == "openai":
        if not settings.openai_api_key:
            raise EmbeddingProviderConfigurationError(
                "OPENAI_API_KEY is required when ORBIT_EMBEDDING_PROVIDER=openai"
            )
        return OpenAIEmbeddingProvider(
            api_key=settings.openai_api_key,
            model=settings.openai_embedding_model,
            timeout_seconds=settings.ai_timeout_seconds,
        )
    raise EmbeddingProviderConfigurationError(
        f"Unsupported ORBIT_EMBEDDING_PROVIDER: {settings.embedding_provider}"
    )


def configured_embedding_provider_identity(settings: Settings) -> tuple[str, str]:
    provider_name = settings.embedding_provider.strip().lower() or "mock"
    if provider_name == "mock":
        return ("mock", DEFAULT_MOCK_EMBEDDING_MODEL)
    if provider_name == "openai":
        return ("openai", settings.openai_embedding_model)
    return (provider_name, "unconfigured")
