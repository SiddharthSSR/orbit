from uuid import uuid4


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


def test_memory_validation_fails_for_blank_title_or_body(client) -> None:
    blank_title = client.post("/memory", json={"title": "   ", "body": "Body"})
    blank_body = client.post("/memory", json={"title": "Title", "body": "   "})

    assert blank_title.status_code == 422
    assert blank_body.status_code == 422


def test_memory_validation_fails_for_invalid_kind(client) -> None:
    response = client.post("/memory", json={"title": "Bad kind", "body": "Body", "kind": "chat"})

    assert response.status_code == 422
