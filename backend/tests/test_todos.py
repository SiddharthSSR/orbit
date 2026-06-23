from uuid import uuid4

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from app.db.session import Base
from app.models.todo import TodoCreate, TodoRecord
from app.repositories.todo_repository import TodoRepository


def test_create_todo(client) -> None:
    response = client.post("/todos", json={"title": "Buy milk"})

    assert response.status_code == 201
    data = response.json()
    assert data["title"] == "Buy milk"
    assert data["is_complete"] is False
    assert data["id"]
    assert data["created_at"]
    assert data["updated_at"]


def test_create_todo_requires_title(client) -> None:
    response = client.post("/todos", json={"notes": "Missing title"})

    assert response.status_code == 422


def test_create_todo_rejects_whitespace_title(client) -> None:
    response = client.post("/todos", json={"title": "   "})

    assert response.status_code == 422


def test_list_todos(client) -> None:
    client.post("/todos", json={"title": "First"})
    client.post("/todos", json={"title": "Second"})

    response = client.get("/todos")

    assert response.status_code == 200
    assert [todo["title"] for todo in response.json()] == ["Second", "First"]


def test_list_todos_filtered_by_project_id(client) -> None:
    orbit = client.post("/projects", json={"name": "Orbit"}).json()
    worldlens = client.post("/projects", json={"name": "WorldLens"}).json()
    client.post("/todos", json={"title": "Orbit task", "project_id": orbit["id"]})
    client.post("/todos", json={"title": "WorldLens task", "project_id": worldlens["id"]})

    response = client.get("/todos", params={"project_id": orbit["id"]})

    assert response.status_code == 200
    assert [todo["title"] for todo in response.json()] == ["Orbit task"]
    assert response.json()[0]["project_id"] == orbit["id"]


def test_list_todos_project_filter_excludes_unlinked_todos(client) -> None:
    project = client.post("/projects", json={"name": "Orbit"}).json()
    client.post("/todos", json={"title": "Linked task", "project_id": project["id"]})
    client.post("/todos", json={"title": "Unlinked task"})

    response = client.get("/todos", params={"project_id": project["id"]})

    assert response.status_code == 200
    assert [todo["title"] for todo in response.json()] == ["Linked task"]


def test_list_todos_project_filter_does_not_change_unfiltered_list(client) -> None:
    project = client.post("/projects", json={"name": "Orbit"}).json()
    client.post("/todos", json={"title": "Linked task", "project_id": project["id"]})
    client.post("/todos", json={"title": "Unlinked task"})

    response = client.get("/todos")

    assert response.status_code == 200
    assert [todo["title"] for todo in response.json()] == ["Unlinked task", "Linked task"]


def test_get_todo_by_id(client) -> None:
    created = client.post("/todos", json={"title": "Read article"}).json()

    response = client.get(f"/todos/{created['id']}")

    assert response.status_code == 200
    assert response.json()["id"] == created["id"]
    assert response.json()["title"] == "Read article"


def test_patch_todo_completion(client) -> None:
    created = client.post("/todos", json={"title": "File receipt"}).json()

    response = client.patch(f"/todos/{created['id']}", json={"is_complete": True})

    assert response.status_code == 200
    data = response.json()
    assert data["is_complete"] is True
    assert data["updated_at"] >= created["updated_at"]


def test_patch_todo_rejects_whitespace_title(client) -> None:
    created = client.post("/todos", json={"title": "File receipt"}).json()

    response = client.patch(f"/todos/{created['id']}", json={"title": "   "})

    assert response.status_code == 422


def test_delete_todo(client) -> None:
    created = client.post("/todos", json={"title": "Delete me"}).json()

    delete_response = client.delete(f"/todos/{created['id']}")
    get_response = client.get(f"/todos/{created['id']}")

    assert delete_response.status_code == 204
    assert get_response.status_code == 404


def test_unknown_todo_returns_404(client) -> None:
    missing_id = uuid4()

    assert client.get(f"/todos/{missing_id}").status_code == 404
    assert client.patch(f"/todos/{missing_id}", json={"is_complete": True}).status_code == 404
    assert client.delete(f"/todos/{missing_id}").status_code == 404


def test_todo_persists_across_sessions(tmp_path) -> None:
    engine = create_engine(f"sqlite:///{tmp_path / 'orbit-test.db'}")
    Base.metadata.create_all(bind=engine, tables=[TodoRecord.__table__])
    testing_session_local = sessionmaker(bind=engine, autoflush=False, autocommit=False)

    with testing_session_local() as session:
        created = TodoRepository(session).create(TodoCreate(title="Persistent todo"))
        todo_id = created.id

    with testing_session_local() as session:
        found = TodoRepository(session).get(todo_id)

    assert found is not None
    assert found.title == "Persistent todo"
