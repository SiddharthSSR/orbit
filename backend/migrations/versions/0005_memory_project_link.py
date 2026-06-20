"""link memory items to projects

Revision ID: 0005_memory_project_link
Revises: 0004_embedding_status
Create Date: 2026-06-20
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op


revision: str = "0005_memory_project_link"
down_revision: str | None = "0004_embedding_status"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "memory_items",
        sa.Column("project_id", sa.String(length=36), nullable=True),
    )
    op.create_index(
        "ix_memory_items_project_id",
        "memory_items",
        ["project_id"],
    )


def downgrade() -> None:
    op.drop_index("ix_memory_items_project_id", table_name="memory_items")
    op.drop_column("memory_items", "project_id")
