"""memory embeddings foundation

Revision ID: 0003_memory_embeddings
Revises: 0002_chat_foundation
Create Date: 2026-06-18
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op


revision: str = "0003_memory_embeddings"
down_revision: str | None = "0002_chat_foundation"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "memory_embeddings",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("memory_item_id", sa.String(length=36), nullable=False),
        sa.Column("provider", sa.String(length=40), nullable=False),
        sa.Column("model", sa.String(length=120), nullable=False),
        sa.Column("embedding_json", sa.Text(), nullable=False),
        sa.Column("content_hash", sa.String(length=64), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["memory_item_id"], ["memory_items.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "memory_item_id",
            "provider",
            "model",
            name="uq_memory_embeddings_item_provider_model",
        ),
    )
    op.create_index(
        "ix_memory_embeddings_memory_item_id",
        "memory_embeddings",
        ["memory_item_id"],
    )


def downgrade() -> None:
    op.drop_index("ix_memory_embeddings_memory_item_id", table_name="memory_embeddings")
    op.drop_table("memory_embeddings")
