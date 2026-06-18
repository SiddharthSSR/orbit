"""durable memory embedding status

Revision ID: 0004_embedding_status
Revises: 0003_memory_embeddings
Create Date: 2026-06-18
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op


revision: str = "0004_embedding_status"
down_revision: str | None = "0003_memory_embeddings"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "memory_embeddings",
        sa.Column("status", sa.String(length=20), nullable=False, server_default="indexed"),
    )
    op.add_column(
        "memory_embeddings",
        sa.Column("error_message", sa.Text(), nullable=True),
    )
    op.add_column(
        "memory_embeddings",
        sa.Column("last_attempted_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.add_column(
        "memory_embeddings",
        sa.Column("indexed_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.execute(
        "UPDATE memory_embeddings "
        "SET last_attempted_at = updated_at, indexed_at = updated_at "
        "WHERE status = 'indexed'"
    )


def downgrade() -> None:
    op.drop_column("memory_embeddings", "indexed_at")
    op.drop_column("memory_embeddings", "last_attempted_at")
    op.drop_column("memory_embeddings", "error_message")
    op.drop_column("memory_embeddings", "status")
