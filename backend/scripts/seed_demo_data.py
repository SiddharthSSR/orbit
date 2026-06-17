#!/usr/bin/env python3
from __future__ import annotations

import argparse
from dataclasses import dataclass
from datetime import date, timedelta
from typing import Any, Callable

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db.session import SessionLocal
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


@dataclass
class SeedCounts:
    created: int = 0
    skipped: int = 0
    would_create: int = 0


@dataclass(frozen=True)
class SeedItem:
    model: type[Any]
    unique_field: str
    unique_value: str
    payload: Any


def build_demo_data(today: date) -> dict[str, list[SeedItem]]:
    return {
        "todos": [
            SeedItem(
                TodoRecord,
                "title",
                "Ship Orbit Ask eval improvements",
                TodoCreate(
                    title="Ship Orbit Ask eval improvements",
                    notes="Review context relevance and eval results for Orbit.",
                    due_date=today - timedelta(days=2),
                ),
            ),
            SeedItem(
                TodoRecord,
                "title",
                "Review WorldLens prototype",
                TodoCreate(
                    title="Review WorldLens prototype",
                    notes="Capture translation flow issues and next steps.",
                    due_date=today,
                ),
            ),
            SeedItem(
                TodoRecord,
                "title",
                "Read AI agents research",
                TodoCreate(
                    title="Read AI agents research",
                    notes="Summarize useful patterns for personal second-brain agents.",
                ),
            ),
        ],
        "bills": [
            SeedItem(
                BillRecord,
                "name",
                "Furlenco Furniture Rent",
                BillCreate(
                    name="Furlenco Furniture Rent",
                    amount=2499,
                    currency="INR",
                    due_date=today + timedelta(days=3),
                    recurrence="monthly",
                    notes="Monthly Furlenco furniture subscription.",
                ),
            ),
            SeedItem(
                BillRecord,
                "name",
                "Credit Card Payment",
                BillCreate(
                    name="Credit Card Payment",
                    amount=8650,
                    currency="INR",
                    due_date=today - timedelta(days=4),
                    notes="Overdue card statement requiring attention.",
                ),
            ),
            SeedItem(
                BillRecord,
                "name",
                "Internet Bill Paid",
                BillCreate(
                    name="Internet Bill Paid",
                    amount=1199,
                    currency="INR",
                    due_date=today - timedelta(days=1),
                    recurrence="monthly",
                    is_paid=True,
                    notes="Paid broadband bill for filtering checks.",
                ),
            ),
        ],
        "memory": [
            SeedItem(
                MemoryRecord,
                "title",
                "AI Agents Reading List",
                MemoryCreate(
                    title="AI Agents Reading List",
                    body="Notes on agent planning, memory, tool boundaries, and reliable evaluation patterns.",
                    kind="article",
                    source_url="https://example.com/ai-agents",
                    tags=["ai", "agents"],
                ),
            ),
            SeedItem(
                MemoryRecord,
                "title",
                "WorldLens Project Update",
                MemoryCreate(
                    title="WorldLens Project Update",
                    body="The camera translation prototype works; next focus is faster language switching and review UX.",
                    kind="project_update",
                    tags=["worldlens"],
                ),
            ),
            SeedItem(
                MemoryRecord,
                "title",
                "Orbit iOS Design Notes",
                MemoryCreate(
                    title="Orbit iOS Design Notes",
                    body="Keep Ask practical, make context confidence visible, and preserve quick capture workflows.",
                    kind="note",
                    tags=["orbit", "ios"],
                ),
            ),
            SeedItem(
                MemoryRecord,
                "title",
                "Weekend Grocery List",
                MemoryCreate(
                    title="Weekend Grocery List",
                    body="Coffee, fruit, oats, and cleaning supplies.",
                    kind="note",
                    tags=["personal"],
                ),
            ),
        ],
        "moods": [
            SeedItem(
                MoodRecord,
                "notes",
                "Ready to improve Orbit Ask evaluation.",
                MoodCreate(
                    mood="focused",
                    energy=4,
                    notes="Ready to improve Orbit Ask evaluation.",
                    check_in_date=today,
                ),
            ),
            SeedItem(
                MoodRecord,
                "notes",
                "Lower energy after a long WorldLens review session.",
                MoodCreate(
                    mood="tired",
                    energy=2,
                    notes="Lower energy after a long WorldLens review session.",
                    check_in_date=today - timedelta(days=1),
                ),
            ),
            SeedItem(
                MoodRecord,
                "notes",
                "Calm morning with space for AI reading.",
                MoodCreate(
                    mood="calm",
                    energy=3,
                    notes="Calm morning with space for AI reading.",
                    check_in_date=today - timedelta(days=3),
                ),
            ),
        ],
        "projects": [
            SeedItem(
                ProjectRecord,
                "name",
                "Orbit",
                ProjectCreate(
                    name="Orbit",
                    description="Personal iPhone second-brain app with reliable capture, planning, and Ask context.",
                    status="active",
                    area="personal",
                    tags=["orbit", "ios", "backend"],
                ),
            ),
            SeedItem(
                ProjectRecord,
                "name",
                "WorldLens",
                ProjectCreate(
                    name="WorldLens",
                    description="Camera translation and visual language learning experience.",
                    status="active",
                    area="learning",
                    tags=["worldlens", "ios"],
                ),
            ),
            SeedItem(
                ProjectRecord,
                "name",
                "SwiftUI Learning Sprint",
                ProjectCreate(
                    name="SwiftUI Learning Sprint",
                    description="Paused learning project used to verify active-project filtering.",
                    status="paused",
                    area="learning",
                    tags=["swiftui"],
                ),
            ),
        ],
    }


def record_exists(session: Session, model: type[Any], field_name: str, value: str) -> bool:
    field = getattr(model, field_name)
    statement = select(model).where(field == value).limit(1)
    return session.scalar(statement) is not None


def seed_demo_data(session: Session, *, today: date, dry_run: bool = False) -> dict[str, SeedCounts]:
    repositories: dict[str, Callable[[Any], Any]] = {
        "todos": TodoRepository(session).create,
        "bills": BillRepository(session).create,
        "memory": MemoryItemRepository(session).create,
        "moods": MoodRepository(session).create,
        "projects": ProjectRepository(session).create,
    }
    counts: dict[str, SeedCounts] = {}

    for category, items in build_demo_data(today).items():
        category_counts = SeedCounts()
        create = repositories[category]
        for item in items:
            if record_exists(session, item.model, item.unique_field, item.unique_value):
                category_counts.skipped += 1
            elif dry_run:
                category_counts.would_create += 1
            else:
                create(item.payload)
                category_counts.created += 1
        counts[category] = category_counts

    return counts


def print_counts(counts: dict[str, SeedCounts], *, dry_run: bool) -> None:
    for category, category_counts in counts.items():
        parts = [f"created={category_counts.created}", f"skipped={category_counts.skipped}"]
        if dry_run:
            parts.append(f"would_create={category_counts.would_create}")
        print(f"{category}: {', '.join(parts)}")

    print(
        "total: "
        f"created={sum(item.created for item in counts.values())}, "
        f"skipped={sum(item.skipped for item in counts.values())}, "
        f"would_create={sum(item.would_create for item in counts.values())}"
    )


def main() -> int:
    parser = argparse.ArgumentParser(description="Seed local Orbit demo data for Ask evaluation.")
    parser.add_argument("--dry-run", action="store_true", help="Show what would be created without writing records.")
    args = parser.parse_args()

    with SessionLocal() as session:
        counts = seed_demo_data(session, today=date.today(), dry_run=args.dry_run)

    print("Orbit demo seed (local development only)")
    print_counts(counts, dry_run=args.dry_run)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
