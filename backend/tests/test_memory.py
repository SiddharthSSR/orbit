from uuid import uuid4

import app.api.routes as routes
from app.core.config import settings
from app.repositories.memory_embedding_repository import MemoryEmbeddingRepository
from app.services.embedding_provider import MockEmbeddingProvider


MOCK_PROVIDER = MockEmbeddingProvider()


def test_create_memory_note(client) -> None:
    response = client.post("/memory", json={"title": "Book idea", "body": "Write about Orbit"})

    assert response.status_code == 201
    data = response.json()
    assert data["title"] == "Book idea"
    assert data["body"] == "Write about Orbit"
    assert data["kind"] == "note"
    assert data["tags"] == []
    assert data["is_archived"] is False
    assert data["id"]
    assert data["created_at"]
    assert data["updated_at"]


def test_list_memory_items(client) -> None:
    client.post("/memory", json={"title": "First", "body": "One"})
    client.post("/memory", json={"title": "Second", "body": "Two"})

    response = client.get("/memory")

    assert response.status_code == 200
    assert [item["title"] for item in response.json()] == ["Second", "First"]


def test_get_memory_by_id(client) -> None:
    created = client.post("/memory", json={"title": "Inbox item", "body": "Remember this"}).json()

    response = client.get(f"/memory/{created['id']}")

    assert response.status_code == 200
    assert response.json()["id"] == created["id"]
    assert response.json()["title"] == "Inbox item"


def test_create_memory_with_valid_project(client) -> None:
    project = client.post("/projects", json={"name": "Orbit"}).json()

    response = client.post(
        "/memory",
        json={"title": "Decision", "body": "Ship linking", "project_id": project["id"]},
    )

    assert response.status_code == 201
    assert response.json()["project_id"] == project["id"]


def test_create_memory_rejects_unknown_project(client) -> None:
    response = client.post(
        "/memory",
        json={"title": "Decision", "body": "Ship linking", "project_id": str(uuid4())},
    )

    assert response.status_code == 404
    assert response.json()["detail"] == "Project not found"


def test_patch_memory_links_changes_and_unlinks_project(client) -> None:
    first_project = client.post("/projects", json={"name": "Orbit"}).json()
    second_project = client.post("/projects", json={"name": "WorldLens"}).json()
    memory = client.post("/memory", json={"title": "Note", "body": "Project note"}).json()

    linked = client.patch(
        f"/memory/{memory['id']}",
        json={"project_id": first_project["id"]},
    )
    changed = client.patch(
        f"/memory/{memory['id']}",
        json={"project_id": second_project["id"]},
    )
    unlinked = client.patch(f"/memory/{memory['id']}", json={"project_id": None})

    assert linked.status_code == 200
    assert linked.json()["project_id"] == first_project["id"]
    assert changed.status_code == 200
    assert changed.json()["project_id"] == second_project["id"]
    assert unlinked.status_code == 200
    assert unlinked.json()["project_id"] is None


def test_patch_memory_omitting_project_preserves_link(client) -> None:
    project = client.post("/projects", json={"name": "Orbit"}).json()
    memory = client.post(
        "/memory",
        json={"title": "Note", "body": "Project note", "project_id": project["id"]},
    ).json()

    response = client.patch(f"/memory/{memory['id']}", json={"title": "Updated note"})

    assert response.status_code == 200
    assert response.json()["project_id"] == project["id"]


def test_patch_memory_rejects_unknown_project(client) -> None:
    memory = client.post("/memory", json={"title": "Note", "body": "Project note"}).json()

    response = client.patch(
        f"/memory/{memory['id']}",
        json={"project_id": str(uuid4())},
    )

    assert response.status_code == 404
    assert response.json()["detail"] == "Project not found"
    assert client.get(f"/memory/{memory['id']}").json()["project_id"] is None


def test_patch_memory_title_body_and_tags(client) -> None:
    created = client.post("/memory", json={"title": "Draft", "body": "Old body", "tags": [" inbox "]}).json()

    response = client.patch(
        f"/memory/{created['id']}",
        json={"title": "Updated", "body": "New body", "tags": ["inbox", "ideas", "ideas", " "]},
    )

    assert response.status_code == 200
    data = response.json()
    assert data["title"] == "Updated"
    assert data["body"] == "New body"
    assert data["tags"] == ["inbox", "ideas"]


def test_archive_item_via_patch(client) -> None:
    created = client.post("/memory", json={"title": "Archive me", "body": "Done"}).json()

    response = client.patch(f"/memory/{created['id']}", json={"is_archived": True})

    assert response.status_code == 200
    assert response.json()["is_archived"] is True


def test_list_excludes_archived_by_default(client) -> None:
    client.post("/memory", json={"title": "Visible", "body": "Keep"})
    archived = client.post("/memory", json={"title": "Hidden", "body": "Archive"}).json()
    client.patch(f"/memory/{archived['id']}", json={"is_archived": True})

    response = client.get("/memory")

    assert response.status_code == 200
    assert [item["title"] for item in response.json()] == ["Visible"]


def test_list_include_archived_includes_archived(client) -> None:
    client.post("/memory", json={"title": "Visible", "body": "Keep"})
    archived = client.post("/memory", json={"title": "Hidden", "body": "Archive"}).json()
    client.patch(f"/memory/{archived['id']}", json={"is_archived": True})

    response = client.get("/memory", params={"include_archived": True})

    assert response.status_code == 200
    assert {item["title"] for item in response.json()} == {"Visible", "Hidden"}


def test_filter_memory_by_kind(client) -> None:
    client.post("/memory", json={"title": "Note", "body": "Regular", "kind": "note"})
    client.post("/memory", json={"title": "Link", "body": "Saved URL", "kind": "link"})

    response = client.get("/memory", params={"kind": "link"})

    assert response.status_code == 200
    assert [item["title"] for item in response.json()] == ["Link"]


def test_filter_memory_by_tag(client) -> None:
    client.post("/memory", json={"title": "Tagged", "body": "Has tag", "tags": ["inbox", "article"]})
    client.post("/memory", json={"title": "Other", "body": "No matching tag", "tags": ["project"]})

    response = client.get("/memory", params={"tag": "article"})

    assert response.status_code == 200
    assert [item["title"] for item in response.json()] == ["Tagged"]


def test_delete_memory(client) -> None:
    created = client.post("/memory", json={"title": "Delete me", "body": "Remove"}).json()

    delete_response = client.delete(f"/memory/{created['id']}")
    get_response = client.get(f"/memory/{created['id']}")

    assert delete_response.status_code == 204
    assert get_response.status_code == 404


def test_unknown_memory_returns_404(client) -> None:
    missing_id = uuid4()

    assert client.get(f"/memory/{missing_id}").status_code == 404
    assert client.patch(f"/memory/{missing_id}", json={"title": "Missing"}).status_code == 404
    assert client.delete(f"/memory/{missing_id}").status_code == 404


def test_reindex_and_search_memory_embeddings_with_mock_provider(client) -> None:
    client.post(
        "/memory",
        json={
            "title": "AI Agents Reading List",
            "body": "Notes about agent memory and retrieval",
            "kind": "article",
            "tags": ["ai", "agents"],
        },
    )
    client.post(
        "/memory",
        json={
            "title": "WorldLens Project Update",
            "body": "Camera translation prototype",
            "kind": "project_update",
            "tags": ["worldlens", "ios"],
        },
    )

    reindex_response = client.post("/memory/embeddings/reindex")
    search_response = client.get("/memory/search", params={"query": "AI", "top_k": 1})

    assert reindex_response.status_code == 200
    assert reindex_response.json() == {
        "indexed_count": 2,
        "provider": "mock",
        "model": "mock-token-hash-v2-64d",
    }
    assert search_response.status_code == 200
    assert search_response.json()[0]["memory_item"]["title"] == "AI Agents Reading List"


def test_memory_search_filters_zero_scores_unless_min_score_is_negative(client) -> None:
    client.post(
        "/memory",
        json={"title": "AI Agents Reading List", "body": "Agent retrieval", "tags": ["ai"]},
    )
    client.post(
        "/memory",
        json={"title": "Weekend Grocery List", "body": "Coffee and vegetables"},
    )

    default_response = client.get("/memory/search", params={"query": "AI", "top_k": 5})
    debug_response = client.get(
        "/memory/search",
        params={"query": "AI", "top_k": 5, "min_score": -1},
    )

    assert [result["memory_item"]["title"] for result in default_response.json()] == [
        "AI Agents Reading List"
    ]
    assert [result["memory_item"]["title"] for result in debug_response.json()] == [
        "AI Agents Reading List",
        "Weekend Grocery List",
    ]
    assert debug_response.json()[1]["score"] == 0.0


def test_create_memory_automatically_creates_mock_embedding(client, db_session) -> None:
    created = client.post(
        "/memory",
        json={"title": "AI Notes", "body": "Agent retrieval", "tags": ["ai"]},
    ).json()

    embeddings = MemoryEmbeddingRepository(db_session).list_for_provider_model(
        provider=MOCK_PROVIDER.provider_name,
        model=MOCK_PROVIDER.model,
    )

    assert len(embeddings) == 1
    assert embeddings[0].memory_item_id == created["id"]


def test_update_content_refreshes_hash_and_embedding_without_duplicate(client, db_session) -> None:
    created = client.post(
        "/memory",
        json={"title": "Draft", "body": "Old body", "tags": ["draft"]},
    ).json()
    repository = MemoryEmbeddingRepository(db_session)
    original = repository.get(
        memory_item_id=created["id"],
        provider=MOCK_PROVIDER.provider_name,
        model=MOCK_PROVIDER.model,
    )
    assert original is not None
    original_id = original.id
    original_hash = original.content_hash
    original_embedding = original.embedding

    response = client.patch(
        f"/memory/{created['id']}",
        json={"title": "AI Notes", "body": "Agent retrieval", "tags": ["ai", "agents"]},
    )
    db_session.expire_all()
    updated = repository.get(
        memory_item_id=created["id"],
        provider=MOCK_PROVIDER.provider_name,
        model=MOCK_PROVIDER.model,
    )

    assert response.status_code == 200
    assert updated is not None
    assert updated.id == original_id
    assert updated.status == "indexed"
    assert updated.error_message is None
    assert updated.content_hash != original_hash
    assert updated.embedding != original_embedding
    assert len(
        repository.list_for_provider_model(
            provider=MOCK_PROVIDER.provider_name,
            model=MOCK_PROVIDER.model,
        )
    ) == 1


def test_non_content_update_does_not_create_duplicate_embedding(client, db_session) -> None:
    created = client.post(
        "/memory",
        json={"title": "Stable Note", "body": "Unchanged content"},
    ).json()
    repository = MemoryEmbeddingRepository(db_session)
    original = repository.get(
        memory_item_id=created["id"],
        provider=MOCK_PROVIDER.provider_name,
        model=MOCK_PROVIDER.model,
    )
    assert original is not None

    response = client.patch(f"/memory/{created['id']}", json={"is_archived": False})
    db_session.expire_all()
    embeddings = repository.list_for_provider_model(
        provider=MOCK_PROVIDER.provider_name,
        model=MOCK_PROVIDER.model,
    )

    assert response.status_code == 200
    assert len(embeddings) == 1
    assert embeddings[0].id == original.id
    assert embeddings[0].content_hash == original.content_hash


def test_project_link_update_does_not_change_text_hash_or_regenerate_embedding(
    client,
    db_session,
    monkeypatch,
) -> None:
    provider = CountingMockEmbeddingProvider()
    monkeypatch.setattr(routes, "build_embedding_provider", lambda _settings: provider)
    project = client.post("/projects", json={"name": "Orbit"}).json()
    created = client.post(
        "/memory",
        json={"title": "Stable Note", "body": "Unchanged content", "tags": ["stable"]},
    ).json()
    repository = MemoryEmbeddingRepository(db_session)
    original = repository.get(
        memory_item_id=created["id"],
        provider=provider.provider_name,
        model=provider.model,
    )
    assert original is not None
    original_hash = original.content_hash
    original_embedding = original.embedding

    before_context = client.post(
        "/ask/context-preview",
        json={"question": "What is in the stable note?"},
    ).json()["context"]
    response = client.patch(
        f"/memory/{created['id']}",
        json={"project_id": project["id"]},
    )
    after_context = client.post(
        "/ask/context-preview",
        json={"question": "What is in the stable note?"},
    ).json()["context"]
    db_session.expire_all()
    updated = repository.get(
        memory_item_id=created["id"],
        provider=provider.provider_name,
        model=provider.model,
    )

    assert response.status_code == 200
    assert updated is not None
    assert provider.embed_calls == 1
    assert updated.id == original.id
    assert updated.content_hash == original_hash
    assert updated.embedding == original_embedding
    assert after_context == before_context


def test_archive_and_delete_remove_memory_embeddings(client, db_session) -> None:
    archived = client.post(
        "/memory",
        json={"title": "Archive me", "body": "Temporary"},
    ).json()
    deleted = client.post(
        "/memory",
        json={"title": "Delete me", "body": "Temporary"},
    ).json()
    repository = MemoryEmbeddingRepository(db_session)

    archive_response = client.patch(f"/memory/{archived['id']}", json={"is_archived": True})
    delete_response = client.delete(f"/memory/{deleted['id']}")
    db_session.expire_all()

    assert archive_response.status_code == 200
    assert delete_response.status_code == 204
    assert repository.get(
        memory_item_id=archived["id"],
        provider=MOCK_PROVIDER.provider_name,
        model=MOCK_PROVIDER.model,
    ) is None
    assert repository.get(
        memory_item_id=deleted["id"],
        provider=MOCK_PROVIDER.provider_name,
        model=MOCK_PROVIDER.model,
    ) is None


def test_search_tracks_memory_create_update_and_delete_without_reindex(client) -> None:
    created = client.post(
        "/memory",
        json={"title": "AI Notes", "body": "Agent retrieval", "tags": ["ai"]},
    ).json()

    after_create = client.get("/memory/search", params={"query": "AI"}).json()
    client.patch(
        f"/memory/{created['id']}",
        json={
            "title": "WorldLens Project Update",
            "body": "Camera translation prototype",
            "tags": ["worldlens"],
        },
    )
    after_update_old_query = client.get("/memory/search", params={"query": "AI"}).json()
    after_update_new_query = client.get("/memory/search", params={"query": "WorldLens"}).json()
    client.delete(f"/memory/{created['id']}")
    after_delete = client.get("/memory/search", params={"query": "WorldLens"}).json()

    assert [result["memory_item"]["id"] for result in after_create] == [created["id"]]
    assert after_update_old_query == []
    assert [result["memory_item"]["id"] for result in after_update_new_query] == [created["id"]]
    assert after_delete == []


def test_memory_create_tracks_failure_when_embedding_provider_is_misconfigured(
    client,
    db_session,
    monkeypatch,
) -> None:
    monkeypatch.setattr(settings, "embedding_provider", "openai")
    monkeypatch.setattr(settings, "openai_api_key", None)

    response = client.post("/memory", json={"title": "AI Note", "body": "Not persisted"})
    created = response.json()
    record = MemoryEmbeddingRepository(db_session).get(
        memory_item_id=created["id"],
        provider="openai",
        model=settings.openai_embedding_model,
    )

    assert response.status_code == 201
    assert record is not None
    assert record.status == "failed"
    assert record.error_message == (
        "OPENAI_API_KEY is required when ORBIT_EMBEDDING_PROVIDER=openai"
    )


def test_status_and_retry_endpoints_repair_failed_mock_embedding(
    client,
    monkeypatch,
) -> None:
    monkeypatch.setattr(
        routes,
        "build_embedding_provider",
        lambda _settings: FailingMockEmbeddingProvider(),
    )
    created_response = client.post(
        "/memory",
        json={"title": "AI Notes", "body": "Agent retrieval", "tags": ["ai"]},
    )
    failed_status = client.get("/memory/embeddings/status")

    monkeypatch.setattr(
        routes,
        "build_embedding_provider",
        lambda _settings: MockEmbeddingProvider(),
    )
    failed_search = client.get("/memory/search", params={"query": "AI"})
    retry_response = client.post("/memory/embeddings/retry-failed")
    repaired_status = client.get("/memory/embeddings/status")
    repaired_search = client.get("/memory/search", params={"query": "AI"})

    assert created_response.status_code == 201
    assert failed_status.json()["indexed_count"] == 0
    assert failed_status.json()["failed_count"] == 1
    assert failed_status.json()["stale_count"] == 0
    assert failed_status.json()["missing_count"] == 0
    assert failed_status.json()["failed_items"][0]["title"] == "AI Notes"
    assert failed_status.json()["failed_items"][0]["error_message"] == "mock embedding outage"
    assert failed_search.json() == []
    assert retry_response.json() == {"retried": 1, "indexed": 1, "failed": 0}
    assert repaired_status.json()["indexed_count"] == 1
    assert repaired_status.json()["failed_count"] == 0
    assert repaired_search.json()[0]["memory_item"]["title"] == "AI Notes"


def test_memory_validation_fails_for_blank_title_or_body(client) -> None:
    blank_title = client.post("/memory", json={"title": "   ", "body": "Body"})
    blank_body = client.post("/memory", json={"title": "Title", "body": "   "})

    assert blank_title.status_code == 422
    assert blank_body.status_code == 422


def test_memory_validation_fails_for_invalid_kind(client) -> None:
    response = client.post("/memory", json={"title": "Bad kind", "body": "Body", "kind": "chat"})

    assert response.status_code == 422


class FailingMockEmbeddingProvider:
    provider_name = "mock"
    model = "mock-token-hash-v2-64d"

    def embed(self, text: str) -> list[float]:
        raise RuntimeError("mock embedding outage")


class CountingMockEmbeddingProvider(MockEmbeddingProvider):
    def __init__(self) -> None:
        super().__init__()
        self.embed_calls = 0

    def embed(self, text: str) -> list[float]:
        self.embed_calls += 1
        return super().embed(text)
