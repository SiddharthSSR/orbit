from uuid import uuid4


def test_create_project(client) -> None:
    response = client.post(
        "/projects",
        json={
            "name": "Orbit",
            "description": "Personal second brain",
            "area": "personal",
            "tags": [" app ", "ai", "app", " "],
        },
    )

    assert response.status_code == 201
    data = response.json()
    assert data["name"] == "Orbit"
    assert data["description"] == "Personal second brain"
    assert data["status"] == "active"
    assert data["area"] == "personal"
    assert data["tags"] == ["app", "ai"]
    assert data["id"]
    assert data["created_at"]
    assert data["updated_at"]


def test_default_status_is_active(client) -> None:
    response = client.post("/projects", json={"name": "WorldLens"})

    assert response.status_code == 201
    assert response.json()["status"] == "active"


def test_list_projects(client) -> None:
    client.post("/projects", json={"name": "Completed", "status": "completed"})
    client.post("/projects", json={"name": "Paused", "status": "paused"})
    client.post("/projects", json={"name": "Active", "status": "active"})

    response = client.get("/projects")

    assert response.status_code == 200
    assert [project["name"] for project in response.json()] == ["Active", "Paused", "Completed"]


def test_list_excludes_archived_by_default(client) -> None:
    client.post("/projects", json={"name": "Visible"})
    client.post("/projects", json={"name": "Hidden", "status": "archived"})

    response = client.get("/projects")

    assert response.status_code == 200
    assert [project["name"] for project in response.json()] == ["Visible"]


def test_list_include_archived_includes_archived(client) -> None:
    client.post("/projects", json={"name": "Visible"})
    client.post("/projects", json={"name": "Hidden", "status": "archived"})

    response = client.get("/projects", params={"include_archived": True})

    assert response.status_code == 200
    assert {project["name"] for project in response.json()} == {"Visible", "Hidden"}


def test_filter_projects_by_status(client) -> None:
    client.post("/projects", json={"name": "Active", "status": "active"})
    client.post("/projects", json={"name": "Paused", "status": "paused"})

    response = client.get("/projects", params={"status": "paused"})

    assert response.status_code == 200
    assert [project["name"] for project in response.json()] == ["Paused"]


def test_filter_projects_by_area(client) -> None:
    client.post("/projects", json={"name": "Orbit", "area": "personal"})
    client.post("/projects", json={"name": "Work CRM", "area": "work"})

    response = client.get("/projects", params={"area": "work"})

    assert response.status_code == 200
    assert [project["name"] for project in response.json()] == ["Work CRM"]


def test_filter_projects_by_tag(client) -> None:
    client.post("/projects", json={"name": "Tagged", "tags": ["orbit", "app"]})
    client.post("/projects", json={"name": "Other", "tags": ["learning"]})

    response = client.get("/projects", params={"tag": "orbit"})

    assert response.status_code == 200
    assert [project["name"] for project in response.json()] == ["Tagged"]


def test_get_project_by_id(client) -> None:
    created = client.post("/projects", json={"name": "Inbox overhaul"}).json()

    response = client.get(f"/projects/{created['id']}")

    assert response.status_code == 200
    assert response.json()["id"] == created["id"]
    assert response.json()["name"] == "Inbox overhaul"


def test_patch_project_name_description_status_and_tags(client) -> None:
    created = client.post("/projects", json={"name": "Draft", "tags": ["old"]}).json()

    response = client.patch(
        f"/projects/{created['id']}",
        json={
            "name": "Updated",
            "description": "New direction",
            "status": "paused",
            "tags": ["roadmap", "roadmap", " personal "],
        },
    )

    assert response.status_code == 200
    data = response.json()
    assert data["name"] == "Updated"
    assert data["description"] == "New direction"
    assert data["status"] == "paused"
    assert data["tags"] == ["roadmap", "personal"]


def test_delete_project(client) -> None:
    created = client.post("/projects", json={"name": "Delete me"}).json()

    delete_response = client.delete(f"/projects/{created['id']}")
    get_response = client.get(f"/projects/{created['id']}")

    assert delete_response.status_code == 204
    assert get_response.status_code == 404


def test_unknown_project_returns_404(client) -> None:
    missing_id = uuid4()

    assert client.get(f"/projects/{missing_id}").status_code == 404
    assert client.patch(f"/projects/{missing_id}", json={"name": "Missing"}).status_code == 404
    assert client.delete(f"/projects/{missing_id}").status_code == 404


def test_project_validation_fails_for_blank_name(client) -> None:
    response = client.post("/projects", json={"name": "   "})

    assert response.status_code == 422


def test_project_validation_fails_for_invalid_status(client) -> None:
    response = client.post("/projects", json={"name": "Bad status", "status": "blocked"})

    assert response.status_code == 422
