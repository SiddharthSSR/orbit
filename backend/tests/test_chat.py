from datetime import date
from uuid import uuid4

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.db.session import Base
from app.models.bill import BillCreate, BillRecord
from app.models.memory import MemoryCreate, MemoryRecord
from app.models.mood import MoodCreate, MoodRecord
from app.models.project import ProjectCreate, ProjectRecord
from app.models.todo import TodoCreate, TodoRecord
from app.repositories.bill_repository import BillRepository
from app.repositories.memory_item_repository import MemoryItemRepository
from app.repositories.mood_repository import MoodRepository
from app.repositories.project_repository import ProjectRepository
from app.repositories.todo_repository import TodoRepository
from app.services.context_builder import OrbitContextBuilder


def test_ask_creates_new_session_and_two_messages(client) -> None:
    response = client.post("/ask", json={"question": "What should I focus on today?"})

    assert response.status_code == 200
    data = response.json()
    assert data["session"]["id"]
    assert data["session"]["title"] == "What should I focus on today?"
    assert data["user_message"]["role"] == "user"
    assert data["user_message"]["content"] == "What should I focus on today?"
    assert data["assistant_message"]["role"] == "assistant"
    assert data["answer"] == data["assistant_message"]["content"]
    assert "available Orbit context" in data["answer"]

    messages_response = client.get(f"/chat/sessions/{data['session']['id']}/messages")
    assert messages_response.status_code == 200
    assert [message["role"] for message in messages_response.json()] == ["user", "assistant"]


def test_ask_with_existing_session_appends_messages(client) -> None:
    first = client.post("/ask", json={"question": "What bills are coming up?"}).json()

    response = client.post(
        "/ask",
        json={
            "question": "What should I do next?",
            "session_id": first["session"]["id"],
        },
    )

    assert response.status_code == 200
    data = response.json()
    assert data["session"]["id"] == first["session"]["id"]

    messages = client.get(f"/chat/sessions/{first['session']['id']}/messages").json()
    assert [message["role"] for message in messages] == ["user", "assistant", "user", "assistant"]
    assert messages[-2]["content"] == "What should I do next?"


def test_ask_with_unknown_session_returns_404(client) -> None:
    response = client.post(
        "/ask",
        json={
            "question": "Can you continue this?",
            "session_id": str(uuid4()),
        },
    )

    assert response.status_code == 404


def test_ask_rejects_blank_question(client) -> None:
    response = client.post("/ask", json={"question": "   "})

    assert response.status_code == 422


def test_list_chat_sessions(client) -> None:
    client.post("/ask", json={"question": "First question"})
    client.post("/ask", json={"question": "Second question"})

    response = client.get("/chat/sessions")

    assert response.status_code == 200
    titles = [session["title"] for session in response.json()]
    assert titles == ["Second question", "First question"]


def test_list_chat_messages_returns_ordered_messages(client) -> None:
    created = client.post("/ask", json={"question": "How are my projects going?"}).json()

    response = client.get(f"/chat/sessions/{created['session']['id']}/messages")

    assert response.status_code == 200
    messages = response.json()
    assert [message["role"] for message in messages] == ["user", "assistant"]
    assert messages[0]["content"] == "How are my projects going?"


def test_context_builder_includes_current_orbit_context() -> None:
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(
        bind=engine,
        tables=[
            TodoRecord.__table__,
            BillRecord.__table__,
            MemoryRecord.__table__,
            MoodRecord.__table__,
            ProjectRecord.__table__,
        ],
    )
    testing_session_local = sessionmaker(bind=engine, autoflush=False, autocommit=False)

    with testing_session_local() as session:
        TodoRepository(session).create(TodoCreate(title="Plan Orbit MVP"))
        TodoRepository(session).create(TodoCreate(title="Completed item", is_complete=True))
        BillRepository(session).create(
            BillCreate(name="Credit card", amount=2500, due_date=date(2026, 6, 20))
        )
        MemoryItemRepository(session).create(
            MemoryCreate(
                title="AI article",
                body="Notes about personal memory systems",
                kind="article",
                tags=["ai"],
            )
        )
        MoodRepository(session).create(MoodCreate(mood="focused", energy=4, check_in_date=date(2026, 6, 16)))
        ProjectRepository(session).create(
            ProjectCreate(
                name="Orbit",
                description="Personal second brain app",
                area="personal",
                tags=["app"],
            )
        )

        context = OrbitContextBuilder(session).build_context()

    assert "Open todos:" in context
    assert "Plan Orbit MVP" in context
    assert "Completed item" not in context
    assert "Unpaid bills:" in context
    assert "Credit card: due 2026-06-20 (2500 INR)" in context
    assert "Recent memory:" in context
    assert "AI article (article) [ai]" in context
    assert "Latest moods:" in context
    assert "focused, energy 4/5" in context
    assert "Active projects:" in context
    assert "Orbit (personal) [app]: Personal second brain app" in context
