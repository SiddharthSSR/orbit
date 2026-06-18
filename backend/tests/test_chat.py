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
from app.services.memory_retrieval import MemoryRetrievalService, MemorySearchResult


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


def test_ask_with_mock_provider_includes_relevant_context_section_names(client) -> None:
    client.post(
        "/memory",
        json={
            "title": "AI retrieval notes",
            "body": "Lightweight relevance before embeddings",
            "kind": "note",
            "tags": ["ai"],
        },
    )

    response = client.post("/ask", json={"question": "What did I save about AI?"})

    assert response.status_code == 200
    assert "Context sections: Today, Open todos, Unpaid bills, Recent memory" in response.json()["answer"]


def test_ask_context_preview_returns_context_for_question(client) -> None:
    client.post(
        "/todos",
        json={
            "title": "Plan Orbit MVP",
            "notes": "Focus on Ask context inspection",
        },
    )

    response = client.post("/ask/context-preview", json={"question": "What should I focus on today?"})

    assert response.status_code == 200
    data = response.json()
    assert data["question"] == "What should I focus on today?"
    assert data["include_context"] is True
    assert "Today:" in data["context"]
    assert "Open todos:" in data["context"]
    assert "Plan Orbit MVP" in data["context"]


def test_ask_context_preview_includes_expected_sections(client) -> None:
    response = client.post("/ask/context-preview", json={"question": "What should I focus on today?"})

    assert response.status_code == 200
    assert response.json()["context_sections"] == [
        "Today",
        "Open todos",
        "Unpaid bills",
        "Recent memory",
        "Latest mood",
        "Active projects",
    ]


def test_ask_context_preview_respects_include_context_false(client) -> None:
    response = client.post(
        "/ask/context-preview",
        json={"question": "What should I focus on today?", "include_context": False},
    )

    assert response.status_code == 200
    data = response.json()
    assert data["include_context"] is False
    assert data["context"] == ""
    assert data["context_sections"] == []


def test_ask_context_preview_rejects_blank_question(client) -> None:
    response = client.post("/ask/context-preview", json={"question": "   "})

    assert response.status_code == 422


def test_ask_context_preview_does_not_create_chat_sessions_or_messages(client) -> None:
    response = client.post("/ask/context-preview", json={"question": "What did I save about AI?"})

    assert response.status_code == 200
    sessions_response = client.get("/chat/sessions")
    assert sessions_response.status_code == 200
    assert sessions_response.json() == []


def test_ask_context_preview_reflects_relevance_ordering(client) -> None:
    client.post(
        "/memory",
        json={
            "title": "Weekend plan",
            "body": "Buy groceries and clean desk",
            "kind": "note",
        },
    )
    client.post(
        "/memory",
        json={
            "title": "AI retrieval notes",
            "body": "Lightweight relevance before embeddings",
            "kind": "note",
            "tags": ["ai"],
        },
    )

    response = client.post("/ask/context-preview", json={"question": "What did I save about AI?"})

    assert response.status_code == 200
    context = response.json()["context"]
    assert context.index("AI retrieval notes (note) [ai]") < context.index("Weekend plan (note)")


def test_context_preview_defaults_to_unchanged_keyword_mode(client) -> None:
    client.post(
        "/memory",
        json={"title": "AI Notes", "body": "Agent retrieval", "tags": ["ai"]},
    )
    client.post(
        "/memory",
        json={"title": "Weekend Plan", "body": "Groceries and cleaning"},
    )

    default_response = client.post(
        "/ask/context-preview",
        json={"question": "What did I save about AI?"},
    )
    keyword_response = client.post(
        "/ask/context-preview",
        json={
            "question": "What did I save about AI?",
            "retrieval_mode": "keyword",
            "memory_top_k": 1,
            "min_vector_score": -1,
        },
    )

    assert default_response.status_code == 200
    assert keyword_response.status_code == 200
    assert default_response.json()["context"] == keyword_response.json()["context"]
    assert "vector_score=" not in default_response.json()["context"]
    assert "Weekend Plan" in keyword_response.json()["context"]


def test_hybrid_context_preview_prioritizes_ai_memory_and_dedupes(client, monkeypatch) -> None:
    client.post(
        "/memory",
        json={
            "title": "WorldLens Project Update",
            "body": "Camera translation prototype",
            "kind": "project_update",
            "tags": ["worldlens", "ios"],
        },
    )
    client.post(
        "/memory",
        json={
            "title": "AI Agents Reading List",
            "body": "Agent memory and retrieval",
            "kind": "article",
            "tags": ["ai", "agents"],
        },
    )

    def misleading_vector_order(service, query, *, top_k=5, min_score=0.0):
        items = {
            item.title: item
            for item in service.memory_repository.list()
        }
        return [
            MemorySearchResult(score=0.187, memory_item=items["WorldLens Project Update"]),
            MemorySearchResult(score=0.170, memory_item=items["AI Agents Reading List"]),
        ]

    monkeypatch.setattr(MemoryRetrievalService, "search", misleading_vector_order)

    response = client.post(
        "/ask/context-preview",
        json={
            "question": "What did I save about AI?",
            "retrieval_mode": "hybrid",
            "memory_top_k": 5,
        },
    )

    assert response.status_code == 200
    context = response.json()["context"]
    assert context.index("AI Agents Reading List") < context.index("WorldLens Project Update")
    assert context.count("AI Agents Reading List") == 1
    assert context.count("WorldLens Project Update") == 1
    assert "vector_score=" in context


def test_hybrid_context_preview_prioritizes_worldlens_memory(client) -> None:
    client.post(
        "/memory",
        json={"title": "Orbit Design Notes", "body": "Navigation and visual polish"},
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

    response = client.post(
        "/ask/context-preview",
        json={
            "question": "How is WorldLens going?",
            "retrieval_mode": "hybrid",
            "memory_top_k": 5,
        },
    )

    assert response.status_code == 200
    context = response.json()["context"]
    assert context.index("WorldLens Project Update") < context.index("Orbit Design Notes")
    assert "WorldLens Project Update (project_update)" in context
    assert "vector_score=" in context


def test_hybrid_context_preview_falls_back_when_embeddings_are_missing(client, db_session) -> None:
    MemoryItemRepository(db_session).create(
        MemoryCreate(title="AI Fallback Note", body="Keyword-only retrieval", tags=["ai"])
    )
    MemoryItemRepository(db_session).create(
        MemoryCreate(title="Weekend Fallback", body="Groceries")
    )

    response = client.post(
        "/ask/context-preview",
        json={
            "question": "What did I save about AI?",
            "retrieval_mode": "hybrid",
            "memory_top_k": 2,
        },
    )

    assert response.status_code == 200
    context = response.json()["context"]
    assert context.index("AI Fallback Note") < context.index("Weekend Fallback")
    assert "vector_score=" not in context


def test_context_preview_validates_hybrid_controls(client) -> None:
    invalid_mode = client.post(
        "/ask/context-preview",
        json={"question": "AI?", "retrieval_mode": "vector"},
    )
    too_small = client.post(
        "/ask/context-preview",
        json={"question": "AI?", "memory_top_k": 0},
    )
    too_large = client.post(
        "/ask/context-preview",
        json={"question": "AI?", "memory_top_k": 21},
    )

    assert invalid_mode.status_code == 422
    assert too_small.status_code == 422
    assert too_large.status_code == 422


def test_ask_remains_keyword_only_and_does_not_call_vector_search(client, monkeypatch) -> None:
    def fail_if_called(*args, **kwargs):
        raise AssertionError("/ask must not call vector retrieval")

    monkeypatch.setattr(MemoryRetrievalService, "search", fail_if_called)

    response = client.post("/ask", json={"question": "What did I save about AI?"})

    assert response.status_code == 200


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

        context = OrbitContextBuilder(session, today=date(2026, 6, 16)).build_context()

    assert "Today:\n- 2026-06-16" in context
    assert "Open todos:" in context
    assert "[No due date] Plan Orbit MVP" in context
    assert "Completed item" not in context
    assert "Unpaid bills:" in context
    assert "[Due soon] Credit card: due 2026-06-20 (2500 INR)" in context
    assert "Recent memory:" in context
    assert "AI article (article) [ai]" in context
    assert "Latest mood:" in context
    assert "focused, energy 4/5" in context
    assert "Active projects:" in context
    assert "Orbit (personal) [app]: Personal second brain app" in context


def test_context_builder_prioritizes_overdue_and_today_todos_before_no_due_todos() -> None:
    engine, testing_session_local = make_context_test_session()

    with testing_session_local() as session:
        TodoRepository(session).create(TodoCreate(title="No due todo"))
        TodoRepository(session).create(TodoCreate(title="Future todo", due_date=date(2026, 6, 19)))
        TodoRepository(session).create(TodoCreate(title="Today todo", due_date=date(2026, 6, 16)))
        TodoRepository(session).create(TodoCreate(title="Overdue todo", due_date=date(2026, 6, 15)))

        context = OrbitContextBuilder(session, today=date(2026, 6, 16)).build_context()

    assert context.index("[Overdue] Overdue todo") < context.index("[Due today] Today todo")
    assert context.index("[Due today] Today todo") < context.index("[Due soon] Future todo")
    assert context.index("[Due soon] Future todo") < context.index("[No due date] No due todo")
    engine.dispose()


def test_context_builder_prioritizes_overdue_and_today_bills() -> None:
    engine, testing_session_local = make_context_test_session()

    with testing_session_local() as session:
        BillRepository(session).create(BillCreate(name="Future bill", due_date=date(2026, 6, 20)))
        BillRepository(session).create(BillCreate(name="Today bill", due_date=date(2026, 6, 16)))
        BillRepository(session).create(BillCreate(name="Overdue bill", due_date=date(2026, 6, 14)))

        context = OrbitContextBuilder(session, today=date(2026, 6, 16)).build_context()

    assert context.index("[Overdue] Overdue bill") < context.index("[Due today] Today bill")
    assert context.index("[Due today] Today bill") < context.index("[Due soon] Future bill")
    engine.dispose()


def test_context_builder_truncates_long_memory_body_and_includes_source_url() -> None:
    engine, testing_session_local = make_context_test_session()
    long_body = " ".join(["memory"] * 80)

    with testing_session_local() as session:
        MemoryItemRepository(session).create(
            MemoryCreate(
                title="Long AI article",
                body=long_body,
                kind="article",
                source_url="https://example.com/ai",
                tags=["ai"],
            )
        )

        context = OrbitContextBuilder(session, today=date(2026, 6, 16), preview_length=60).build_context()

    assert "source: https://example.com/ai" in context
    assert "Long AI article (article) [ai]" in context
    assert "..." in context
    assert long_body not in context
    engine.dispose()


def test_context_builder_includes_latest_mood_and_active_projects() -> None:
    engine, testing_session_local = make_context_test_session()

    with testing_session_local() as session:
        MoodRepository(session).create(MoodCreate(mood="focused", energy=4, check_in_date=date(2026, 6, 16)))
        ProjectRepository(session).create(
            ProjectCreate(
                name="Orbit",
                description="Build a personal second brain with reliable capture and planning.",
                area="personal",
                tags=["ios", "backend"],
            )
        )
        ProjectRepository(session).create(ProjectCreate(name="Archived project", status="archived"))

        context = OrbitContextBuilder(session, today=date(2026, 6, 16), preview_length=80).build_context()

    assert "Latest mood:" in context
    assert "2026-06-16: focused, energy 4/5" in context
    assert "Active projects:" in context
    assert "Orbit (personal) [ios, backend]: Build a personal second brain" in context
    assert "Archived project" not in context
    engine.dispose()


def test_context_builder_prioritizes_ai_memory_when_question_asks_about_ai() -> None:
    engine, testing_session_local = make_context_test_session()

    with testing_session_local() as session:
        MemoryItemRepository(session).create(
            MemoryCreate(
                title="Weekend plan",
                body="Things I saved for the weekend",
                kind="note",
            )
        )
        MemoryItemRepository(session).create(
            MemoryCreate(
                title="AI article",
                body="Notes about AI memory and retrieval",
                kind="article",
                tags=["ai"],
            )
        )

        context = OrbitContextBuilder(
            session,
            question="What did I save about AI?",
            today=date(2026, 6, 16),
        ).build_context()

    assert context.index("AI article (article) [ai]") < context.index("Weekend plan (note)")
    engine.dispose()


def test_context_builder_prioritizes_worldlens_project_when_question_asks_about_worldlens() -> None:
    engine, testing_session_local = make_context_test_session()

    with testing_session_local() as session:
        ProjectRepository(session).create(
            ProjectCreate(
                name="Orbit",
                description="Personal second brain app",
                area="personal",
            )
        )
        ProjectRepository(session).create(
            ProjectCreate(
                name="WorldLens",
                description="Camera translation and visual language learning app",
                area="learning",
                tags=["ios"],
            )
        )

        context = OrbitContextBuilder(
            session,
            question="How is WorldLens going?",
            today=date(2026, 6, 16),
        ).build_context()

    assert context.index("WorldLens (learning) [ios]") < context.index("Orbit (personal)")
    engine.dispose()


def test_context_builder_prioritizes_furlenco_bill_when_question_asks_about_furlenco() -> None:
    engine, testing_session_local = make_context_test_session()

    with testing_session_local() as session:
        BillRepository(session).create(BillCreate(name="Credit card", due_date=date(2026, 6, 14)))
        BillRepository(session).create(
            BillCreate(
                name="Furlenco rent",
                due_date=date(2026, 6, 20),
                recurrence="monthly",
                notes="Furniture rental",
            )
        )

        context = OrbitContextBuilder(
            session,
            question="Any bills related to Furlenco?",
            today=date(2026, 6, 16),
        ).build_context()

    assert context.index("Furlenco rent") < context.index("Credit card")
    engine.dispose()


def test_context_builder_falls_back_to_date_order_when_question_has_no_matches() -> None:
    engine, testing_session_local = make_context_test_session()

    with testing_session_local() as session:
        TodoRepository(session).create(TodoCreate(title="No due todo"))
        TodoRepository(session).create(TodoCreate(title="Today todo", due_date=date(2026, 6, 16)))
        TodoRepository(session).create(TodoCreate(title="Overdue todo", due_date=date(2026, 6, 15)))

        context = OrbitContextBuilder(
            session,
            question="Tell me about quantum cooking",
            today=date(2026, 6, 16),
        ).build_context()

    assert context.index("[Overdue] Overdue todo") < context.index("[Due today] Today todo")
    assert context.index("[Due today] Today todo") < context.index("[No due date] No due todo")
    engine.dispose()


def make_context_test_session():
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
    return engine, sessionmaker(bind=engine, autoflush=False, autocommit=False)
