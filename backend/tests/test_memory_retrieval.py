from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.db.session import Base
from app.models.embedding import MemoryEmbeddingRecord
from app.models.memory import MemoryCreate, MemoryRecord
from app.repositories.memory_embedding_repository import MemoryEmbeddingRepository
from app.repositories.memory_item_repository import MemoryItemRepository
from app.services.embedding_provider import MockEmbeddingProvider
from app.services.memory_retrieval import (
    MemoryRetrievalService,
    cosine_similarity,
    memory_content_hash,
)


def test_cosine_similarity_behaves_as_expected() -> None:
    assert cosine_similarity([1.0, 0.0], [1.0, 0.0]) == 1.0
    assert cosine_similarity([1.0, 0.0], [0.0, 1.0]) == 0.0
    assert cosine_similarity([0.0, 0.0], [1.0, 0.0]) == 0.0


def test_memory_content_hash_changes_when_embedded_text_changes() -> None:
    memory_item = MemoryRecord(
        title="AI notes",
        body="Agent retrieval ideas",
        kind="note",
    )
    original_hash = memory_content_hash(memory_item)

    memory_item.body = "Updated retrieval ideas"

    assert memory_content_hash(memory_item) != original_hash


def test_memory_embedding_repository_upsert_updates_existing_record() -> None:
    engine, session_local = make_retrieval_test_session()
    with session_local() as session:
        memory_item = MemoryItemRepository(session).create(
            MemoryCreate(title="AI notes", body="Agent retrieval ideas")
        )
        repository = MemoryEmbeddingRepository(session)

        created = repository.upsert(
            memory_item_id=memory_item.id,
            provider="mock",
            model="mock-v1",
            embedding=[1.0, 0.0],
            content_hash="first",
        )
        updated = repository.upsert(
            memory_item_id=memory_item.id,
            provider="mock",
            model="mock-v1",
            embedding=[0.5, 0.5],
            content_hash="second",
        )

        assert updated.id == created.id
        assert updated.embedding == [0.5, 0.5]
        assert updated.content_hash == "second"
        assert len(repository.list_for_provider_model(provider="mock", model="mock-v1")) == 1
        assert repository.delete_for_memory_item(memory_item.id) == 1
        assert repository.get(
            memory_item_id=memory_item.id,
            provider="mock",
            model="mock-v1",
        ) is None
    engine.dispose()


def test_index_all_memory_items_creates_embeddings() -> None:
    engine, session_local = make_retrieval_test_session()
    with session_local() as session:
        memory_repository = MemoryItemRepository(session)
        memory_repository.create(MemoryCreate(title="AI notes", body="Agent retrieval ideas"))
        memory_repository.create(
            MemoryCreate(title="WorldLens update", body="Camera translation prototype")
        )
        provider = MockEmbeddingProvider()
        service = MemoryRetrievalService(session, provider)

        indexed = service.index_all_memory_items()

        assert len(indexed) == 2
        assert len(
            MemoryEmbeddingRepository(session).list_for_provider_model(
                provider=provider.provider_name,
                model=provider.model,
            )
        ) == 2
    engine.dispose()


def test_search_returns_relevant_ai_and_worldlens_memory() -> None:
    engine, session_local = make_retrieval_test_session()
    with session_local() as session:
        memory_repository = MemoryItemRepository(session)
        memory_repository.create(
            MemoryCreate(
                title="AI Agents Reading List",
                body="Notes on agent memory and retrieval",
                kind="article",
                tags=["ai", "agents"],
            )
        )
        memory_repository.create(
            MemoryCreate(
                title="WorldLens Project Update",
                body="Camera translation prototype progress",
                kind="project_update",
                tags=["worldlens", "ios"],
            )
        )
        memory_repository.create(
            MemoryCreate(title="Weekend Grocery List", body="Coffee and vegetables")
        )
        service = MemoryRetrievalService(session, MockEmbeddingProvider())
        service.index_all_memory_items()

        ai_results = service.search("AI", top_k=3)
        worldlens_results = service.search("WorldLens", top_k=3)

        assert ai_results[0].memory_item.title == "AI Agents Reading List"
        assert worldlens_results[0].memory_item.title == "WorldLens Project Update"
        assert len(ai_results) == 1
        assert len(worldlens_results) == 1
    engine.dispose()


def test_search_can_include_zero_score_results_with_negative_minimum() -> None:
    engine, session_local = make_retrieval_test_session()
    with session_local() as session:
        memory_repository = MemoryItemRepository(session)
        memory_repository.create(
            MemoryCreate(title="AI Agents Reading List", body="Agent retrieval", tags=["ai"])
        )
        memory_repository.create(
            MemoryCreate(title="Weekend Grocery List", body="Coffee and vegetables")
        )
        service = MemoryRetrievalService(session, MockEmbeddingProvider())
        service.index_all_memory_items()

        results = service.search("AI", top_k=5, min_score=-1)

        assert [result.memory_item.title for result in results] == [
            "AI Agents Reading List",
            "Weekend Grocery List",
        ]
        assert results[1].score == 0.0
    engine.dispose()


def make_retrieval_test_session():
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(
        bind=engine,
        tables=[MemoryRecord.__table__, MemoryEmbeddingRecord.__table__],
    )
    return engine, sessionmaker(bind=engine, autoflush=False, autocommit=False)
