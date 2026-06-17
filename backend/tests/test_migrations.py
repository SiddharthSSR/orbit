from alembic import command
from alembic.config import Config
from sqlalchemy import create_engine, inspect


def test_alembic_upgrade_head_creates_expected_tables(tmp_path) -> None:
    database_path = tmp_path / "orbit-migration-test.db"
    alembic_config = Config("alembic.ini")
    alembic_config.set_main_option("sqlalchemy.url", f"sqlite:///{database_path}")

    command.upgrade(alembic_config, "head")

    engine = create_engine(f"sqlite:///{database_path}")
    table_names = set(inspect(engine).get_table_names())

    assert {
        "alembic_version",
        "todos",
        "bills",
        "memory_items",
        "memory_embeddings",
        "moods",
        "projects",
        "chat_sessions",
        "chat_messages",
    }.issubset(table_names)
    assert {
        constraint["name"]
        for constraint in inspect(engine).get_unique_constraints("memory_embeddings")
    } == {"uq_memory_embeddings_item_provider_model"}
