from collections.abc import Generator

from sqlalchemy import create_engine
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker

from app.core.config import settings


class Base(DeclarativeBase):
    pass


def _connect_args(database_url: str) -> dict[str, bool]:
    if database_url.startswith("sqlite"):
        return {"check_same_thread": False}
    return {}


engine = create_engine(settings.database_url, connect_args=_connect_args(settings.database_url))
SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False)


def init_db() -> None:
    from app.models.bill import BillRecord
    from app.models.memory import MemoryRecord
    from app.models.mood import MoodRecord
    from app.models.project import ProjectRecord
    from app.models.todo import TodoRecord

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


def get_session() -> Generator[Session, None, None]:
    with SessionLocal() as session:
        yield session
