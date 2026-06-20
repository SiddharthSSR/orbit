from alembic import command
from alembic.config import Config
from sqlalchemy import create_engine, inspect, text


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
    embedding_columns = {column["name"] for column in inspect(engine).get_columns("memory_embeddings")}
    assert {"status", "error_message", "last_attempted_at", "indexed_at"} <= embedding_columns
    memory_columns = {column["name"]: column for column in inspect(engine).get_columns("memory_items")}
    assert memory_columns["project_id"]["nullable"] is True
    assert "ix_memory_items_project_id" in {
        index["name"] for index in inspect(engine).get_indexes("memory_items")
    }


def test_memory_project_link_migration_preserves_existing_memory(tmp_path) -> None:
    database_path = tmp_path / "orbit-memory-project-migration.db"
    database_url = f"sqlite:///{database_path}"
    alembic_config = Config("alembic.ini")
    alembic_config.set_main_option("sqlalchemy.url", database_url)
    command.upgrade(alembic_config, "0004_embedding_status")

    engine = create_engine(database_url)
    with engine.begin() as connection:
        connection.execute(
            text(
                "INSERT INTO memory_items "
                "(id, title, body, kind, source_url, tags, is_archived, created_at, updated_at) "
                "VALUES ('memory-1', 'Existing note', 'Preserve me', 'note', NULL, '[]', 0, "
                "'2026-06-20 00:00:00', '2026-06-20 00:00:00')"
            )
        )
    engine.dispose()

    command.upgrade(alembic_config, "head")

    engine = create_engine(database_url)
    with engine.connect() as connection:
        row = connection.execute(
            text("SELECT title, project_id FROM memory_items WHERE id = 'memory-1'")
        ).one()

    assert row.title == "Existing note"
    assert row.project_id is None


def test_embedding_status_migration_preserves_existing_embeddings_as_indexed(tmp_path) -> None:
    database_path = tmp_path / "orbit-embedding-status-migration.db"
    database_url = f"sqlite:///{database_path}"
    alembic_config = Config("alembic.ini")
    alembic_config.set_main_option("sqlalchemy.url", database_url)
    command.upgrade(alembic_config, "0003_memory_embeddings")

    engine = create_engine(database_url)
    with engine.begin() as connection:
        connection.execute(
            text(
                "INSERT INTO memory_items "
                "(id, title, body, kind, source_url, tags, is_archived, created_at, updated_at) "
                "VALUES ('memory-1', 'AI Notes', 'Agents', 'note', NULL, '[]', 0, "
                "'2026-06-18 00:00:00', '2026-06-18 00:00:00')"
            )
        )
        connection.execute(
            text(
                "INSERT INTO memory_embeddings "
                "(id, memory_item_id, provider, model, embedding_json, content_hash, "
                "created_at, updated_at) VALUES "
                "('embedding-1', 'memory-1', 'mock', 'mock-v1', '[1.0]', 'hash', "
                "'2026-06-18 00:00:00', '2026-06-18 00:00:00')"
            )
        )
    engine.dispose()

    command.upgrade(alembic_config, "head")

    engine = create_engine(database_url)
    with engine.connect() as connection:
        row = connection.execute(
            text(
                "SELECT status, error_message, last_attempted_at, indexed_at "
                "FROM memory_embeddings WHERE id = 'embedding-1'"
            )
        ).one()

    assert row.status == "indexed"
    assert row.error_message is None
    assert row.last_attempted_at is not None
    assert row.indexed_at is not None
