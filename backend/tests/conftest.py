from collections.abc import Generator

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import StaticPool

from app.db.session import Base, get_session
from app.main import app
from app.models.bill import BillRecord
from app.models.chat import ChatMessageRecord, ChatSessionRecord
from app.models.embedding import MemoryEmbeddingRecord
from app.models.memory import MemoryRecord
from app.models.mood import MoodRecord
from app.models.project import ProjectRecord
from app.models.todo import TodoRecord


@pytest.fixture()
def client() -> Generator[TestClient, None, None]:
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
            MemoryEmbeddingRecord.__table__,
            MoodRecord.__table__,
            ProjectRecord.__table__,
            ChatSessionRecord.__table__,
            ChatMessageRecord.__table__,
        ],
    )
    testing_session_local = sessionmaker(bind=engine, autoflush=False, autocommit=False)

    def override_get_session() -> Generator[Session, None, None]:
        with testing_session_local() as session:
            yield session

    app.dependency_overrides[get_session] = override_get_session
    with TestClient(app) as test_client:
        yield test_client
    app.dependency_overrides.clear()
