import json
from datetime import date

from sqlalchemy import create_engine, func, select
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.db.session import Base
from app.models.bill import BillRecord
from app.models.memory import MemoryRecord
from app.models.mood import MoodRecord
from app.models.project import ProjectRecord
from app.models.todo import TodoRecord
from scripts.seed_demo_data import build_demo_data, record_exists, seed_demo_data


DEMO_TABLES = [
    TodoRecord.__table__,
    BillRecord.__table__,
    MemoryRecord.__table__,
    MoodRecord.__table__,
    ProjectRecord.__table__,
]


def test_seed_definitions_include_expected_eval_keywords() -> None:
    demo_data = build_demo_data(date(2026, 6, 18))
    serialized = json.dumps(
        [
            {
                "unique_value": item.unique_value,
                "payload": item.payload.model_dump(mode="json"),
            }
            for items in demo_data.values()
            for item in items
        ]
    ).lower()

    for keyword in ["ai", "worldlens", "furlenco", "orbit"]:
        assert keyword in serialized


def test_record_exists_detects_existing_title_and_name() -> None:
    engine, testing_session_local = make_seed_test_session()

    with testing_session_local() as session:
        session.add(TodoRecord(title="Review WorldLens prototype", is_complete=False))
        session.add(
            BillRecord(
                name="Furlenco Furniture Rent",
                currency="INR",
                due_date=date(2026, 6, 21),
                is_paid=False,
                reminder_days_before=3,
            )
        )
        session.commit()

        assert record_exists(session, TodoRecord, "title", "Review WorldLens prototype") is True
        assert record_exists(session, TodoRecord, "title", "Missing todo") is False
        assert record_exists(session, BillRecord, "name", "Furlenco Furniture Rent") is True
        assert record_exists(session, BillRecord, "name", "Missing bill") is False

    engine.dispose()


def test_seed_demo_data_dry_run_does_not_write_records() -> None:
    engine, testing_session_local = make_seed_test_session()

    with testing_session_local() as session:
        counts = seed_demo_data(session, today=date(2026, 6, 18), dry_run=True)

        assert sum(item.would_create for item in counts.values()) == 16
        assert sum(item.created for item in counts.values()) == 0
        for model in [TodoRecord, BillRecord, MemoryRecord, MoodRecord, ProjectRecord]:
            assert session.scalar(select(func.count()).select_from(model)) == 0

    engine.dispose()


def make_seed_test_session():
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(bind=engine, tables=DEMO_TABLES)
    return engine, sessionmaker(bind=engine, autoflush=False, autocommit=False)
