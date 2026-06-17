import hashlib
import math
from dataclasses import dataclass

from sqlalchemy.orm import Session

from app.models.embedding import MemoryEmbeddingRecord
from app.models.memory import MemoryRecord
from app.repositories.memory_embedding_repository import MemoryEmbeddingRepository
from app.repositories.memory_item_repository import MemoryItemRepository
from app.services.embedding_provider import EmbeddingProvider


@dataclass(frozen=True)
class MemorySearchResult:
    score: float
    memory_item: MemoryRecord


def memory_text(memory_item: MemoryRecord) -> str:
    tags = memory_item.tags if memory_item.tags_json else []
    parts = [
        memory_item.title,
        memory_item.body,
        memory_item.kind,
        " ".join(tags),
        memory_item.source_url or "",
    ]
    return "\n".join(part.strip() for part in parts if part.strip())


def memory_content_hash(memory_item: MemoryRecord) -> str:
    return hashlib.sha256(memory_text(memory_item).encode("utf-8")).hexdigest()


def cosine_similarity(left: list[float], right: list[float]) -> float:
    if len(left) != len(right):
        raise ValueError("Embedding vectors must have the same dimensions")
    left_norm = math.sqrt(sum(component * component for component in left))
    right_norm = math.sqrt(sum(component * component for component in right))
    if left_norm == 0 or right_norm == 0:
        return 0.0
    dot_product = sum(
        left_component * right_component
        for left_component, right_component in zip(left, right)
    )
    return dot_product / (left_norm * right_norm)


class MemoryRetrievalService:
    def __init__(self, session: Session, provider: EmbeddingProvider) -> None:
        self.session = session
        self.provider = provider
        self.memory_repository = MemoryItemRepository(session)
        self.embedding_repository = MemoryEmbeddingRepository(session)

    def index_memory_item(self, memory_item: MemoryRecord) -> MemoryEmbeddingRecord:
        content_hash = memory_content_hash(memory_item)
        existing = self.embedding_repository.get(
            memory_item_id=memory_item.id,
            provider=self.provider.provider_name,
            model=self.provider.model,
        )
        if existing is not None and existing.content_hash == content_hash:
            return existing

        embedding = self.provider.embed(memory_text(memory_item))
        return self.embedding_repository.upsert(
            memory_item_id=memory_item.id,
            provider=self.provider.provider_name,
            model=self.provider.model,
            embedding=embedding,
            content_hash=content_hash,
        )

    def index_all_memory_items(self) -> list[MemoryEmbeddingRecord]:
        return [
            self.index_memory_item(memory_item)
            for memory_item in self.memory_repository.list(include_archived=True)
        ]

    def search(self, query: str, *, top_k: int = 5) -> list[MemorySearchResult]:
        if not query.strip():
            raise ValueError("Search query must not be blank")
        if top_k <= 0:
            raise ValueError("top_k must be positive")

        query_embedding = self.provider.embed(query)
        results: list[MemorySearchResult] = []
        for embedding_record in self.embedding_repository.list_for_provider_model(
            provider=self.provider.provider_name,
            model=self.provider.model,
        ):
            memory_item = self.memory_repository.get(embedding_record.memory_item_id)
            if memory_item is None or memory_item.is_archived:
                continue
            results.append(
                MemorySearchResult(
                    score=cosine_similarity(query_embedding, embedding_record.embedding),
                    memory_item=memory_item,
                )
            )

        return sorted(results, key=lambda result: result.score, reverse=True)[:top_k]
