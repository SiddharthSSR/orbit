from datetime import UTC, datetime

import pytest

from scripts.cleanup_chat_sessions import (
    CleanupSelectionError,
    build_argument_parser,
    print_cleanup_report,
    run_cleanup,
    select_sessions,
)


SESSIONS = [
    {
        "id": "session-new",
        "title": "Recent planning chat",
        "created_at": "2026-06-17T10:00:00Z",
        "updated_at": "2026-06-18T08:00:00Z",
    },
    {
        "id": "session-eval-old",
        "title": "Eval: saved AI",
        "created_at": "2026-05-01T10:00:00Z",
        "updated_at": "2026-05-02T10:00:00Z",
    },
    {
        "id": "session-eval-mid",
        "title": "Hybrid EVAL smoke",
        "created_at": "2026-06-01T10:00:00Z",
        "updated_at": "2026-06-02T10:00:00Z",
    },
]


def test_dry_run_deletes_nothing() -> None:
    deleted: list[str] = []
    args = parse_args("--all", "--limit", "2")

    report = run_cleanup(
        args,
        session_fetcher=lambda _: SESSIONS,
        session_deleter=lambda _, session_id: deleted.append(session_id),
    )

    assert report["mode"] == "dry-run"
    assert report["sessions_selected"] == 2
    assert report["deleted_count"] == 0
    assert deleted == []


def test_destructive_run_requires_confirm_delete() -> None:
    args = parse_args("--title-contains", "eval")

    report = run_cleanup(
        args,
        session_fetcher=lambda _: SESSIONS,
        session_deleter=lambda *_: pytest.fail("DELETE must not run without --confirm-delete"),
    )

    assert report["mode"] == "dry-run"
    assert report["deleted_count"] == 0


def test_no_filters_without_all_refuses_before_fetch_even_with_confirmation() -> None:
    args = parse_args("--confirm-delete")

    with pytest.raises(CleanupSelectionError, match="provide at least one selector"):
        run_cleanup(
            args,
            session_fetcher=lambda _: pytest.fail("GET must not run without a selector"),
        )


def test_all_with_limit_selects_limited_sessions() -> None:
    args = parse_args("--all", "--limit", "2")

    report = run_cleanup(args, session_fetcher=lambda _: SESSIONS)

    assert [session["id"] for session in report["selected_sessions"]] == [
        "session-new",
        "session-eval-old",
    ]


def test_limit_cannot_select_every_session_without_all() -> None:
    args = parse_args("--limit", "99", "--confirm-delete")

    with pytest.raises(CleanupSelectionError, match="selected every session"):
        run_cleanup(
            args,
            session_fetcher=lambda _: SESSIONS,
            session_deleter=lambda *_: pytest.fail("DELETE must not run without --all"),
        )


def test_title_contains_filters_case_insensitively() -> None:
    selected = select_sessions(SESSIONS, title_contains="EvAl")

    assert [session["id"] for session in selected] == [
        "session-eval-old",
        "session-eval-mid",
    ]


def test_older_than_days_filters_using_available_timestamps() -> None:
    selected = select_sessions(
        [*SESSIONS, {"id": "no-time", "title": "No timestamp"}],
        older_than_days=14,
        now=datetime(2026, 6, 18, 12, 0, tzinfo=UTC),
    )

    assert [session["id"] for session in selected] == [
        "session-eval-old",
        "session-eval-mid",
    ]


def test_deletion_failures_are_counted_and_reported(capsys) -> None:
    args = parse_args("--all", "--confirm-delete")

    def delete_session(_base_url: str, session_id: str) -> None:
        if session_id == "session-eval-old":
            raise RuntimeError("HTTP 500: boom")

    report = run_cleanup(
        args,
        session_fetcher=lambda _: SESSIONS,
        session_deleter=delete_session,
    )
    print_cleanup_report(report)
    output = capsys.readouterr().out

    assert report["deleted_count"] == 2
    assert report["failed_count"] == 1
    assert report["errors"] == [
        {"session_id": "session-eval-old", "error": "HTTP 500: boom"}
    ]
    assert "session-eval-old: HTTP 500: boom" in output


def test_cli_parsing_supports_filters_and_confirmation() -> None:
    args = parse_args(
        "--base-url",
        "http://127.0.0.1:8010",
        "--limit",
        "10",
        "--older-than-days",
        "30",
        "--title-contains",
        "eval",
        "--all",
        "--confirm-delete",
    )

    assert args.base_url == "http://127.0.0.1:8010"
    assert args.limit == 10
    assert args.older_than_days == 30
    assert args.title_contains == "eval"
    assert args.select_all is True
    assert args.confirm_delete is True


def parse_args(*arguments: str):
    return build_argument_parser().parse_args(list(arguments))
