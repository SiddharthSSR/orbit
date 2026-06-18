#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import sys
from collections.abc import Callable
from datetime import UTC, datetime, timedelta
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import quote
from urllib.request import Request, urlopen


DEFAULT_BASE_URL = "http://127.0.0.1:8000"
PREVIEW_LIMIT = 5


class CleanupSelectionError(ValueError):
    pass


def build_argument_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "Dev-only manual cleanup for legacy Orbit chat sessions. "
            "Defaults to dry-run; deletion requires --confirm-delete."
        )
    )
    parser.add_argument(
        "--base-url",
        default=DEFAULT_BASE_URL,
        help=f"Backend base URL. Default: {DEFAULT_BASE_URL}",
    )
    parser.add_argument("--limit", type=_positive_int, help="Select at most this many sessions.")
    parser.add_argument(
        "--older-than-days",
        type=_non_negative_int,
        help="Select sessions whose updated (or created) timestamp is older than this many days.",
    )
    parser.add_argument(
        "--title-contains",
        help="Select sessions whose title contains this text (case-insensitive).",
    )
    parser.add_argument(
        "--all",
        action="store_true",
        dest="select_all",
        help="Explicitly allow selection from all sessions before other filters/limit.",
    )
    parser.add_argument(
        "--confirm-delete",
        action="store_true",
        help="Actually delete selected sessions. Without this flag, the script is dry-run only.",
    )
    return parser


def main() -> int:
    args = build_argument_parser().parse_args()
    try:
        report = run_cleanup(args)
    except CleanupSelectionError as exc:
        print(f"REFUSED: {exc}", file=sys.stderr)
        return 2
    except RuntimeError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    print_cleanup_report(report)
    return 1 if report["failed_count"] else 0


def run_cleanup(
    args: argparse.Namespace,
    *,
    session_fetcher: Callable[[str], list[dict[str, Any]]] | None = None,
    session_deleter: Callable[[str, str], None] | None = None,
    now: datetime | None = None,
) -> dict[str, Any]:
    if not has_selector(args):
        raise CleanupSelectionError(
            "provide at least one selector: --all, --limit, --older-than-days, or --title-contains."
        )

    fetcher = session_fetcher or fetch_chat_sessions
    deleter = session_deleter or delete_chat_session
    sessions = fetcher(args.base_url)
    selected = select_sessions(
        sessions,
        limit=args.limit,
        older_than_days=args.older_than_days,
        title_contains=args.title_contains,
        now=now,
    )
    if sessions and len(selected) == len(sessions) and not args.select_all:
        raise CleanupSelectionError(
            "the filters selected every session; pass --all to explicitly allow an all-session selection."
        )

    deleted_count = 0
    errors: list[dict[str, str]] = []
    if args.confirm_delete:
        for session in selected:
            session_id = str(session["id"])
            try:
                deleter(args.base_url, session_id)
            except RuntimeError as exc:
                errors.append({"session_id": session_id, "error": str(exc)})
            else:
                deleted_count += 1

    return {
        "base_url": args.base_url.rstrip("/"),
        "sessions_found": len(sessions),
        "sessions_selected": len(selected),
        "mode": "delete" if args.confirm_delete else "dry-run",
        "deleted_count": deleted_count,
        "failed_count": len(errors),
        "errors": errors,
        "selected_sessions": selected,
    }


def has_selector(args: argparse.Namespace) -> bool:
    return bool(
        args.select_all
        or args.limit is not None
        or args.older_than_days is not None
        or (args.title_contains is not None and args.title_contains.strip())
    )


def select_sessions(
    sessions: list[dict[str, Any]],
    *,
    limit: int | None = None,
    older_than_days: int | None = None,
    title_contains: str | None = None,
    now: datetime | None = None,
) -> list[dict[str, Any]]:
    selected = list(sessions)

    if title_contains is not None and title_contains.strip():
        needle = title_contains.strip().casefold()
        selected = [
            session
            for session in selected
            if needle in str(session.get("title") or "").casefold()
        ]

    if older_than_days is not None:
        reference_time = now or datetime.now(UTC)
        if reference_time.tzinfo is None:
            reference_time = reference_time.replace(tzinfo=UTC)
        cutoff = reference_time - timedelta(days=older_than_days)
        selected = [
            session
            for session in selected
            if (timestamp := _session_timestamp(session)) is not None and timestamp < cutoff
        ]

    if limit is not None:
        selected = selected[:limit]
    return selected


def fetch_chat_sessions(base_url: str) -> list[dict[str, Any]]:
    url = f"{base_url.rstrip('/')}/chat/sessions"
    request = Request(url, headers={"Accept": "application/json"}, method="GET")
    try:
        with urlopen(request, timeout=30) as response:
            payload = json.loads(response.read().decode("utf-8"))
    except HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"GET /chat/sessions failed with HTTP {exc.code}: {body}") from exc
    except URLError as exc:
        raise RuntimeError(f"Could not connect to {url}: {exc.reason}") from exc
    except json.JSONDecodeError as exc:
        raise RuntimeError("GET /chat/sessions returned invalid JSON") from exc

    if not isinstance(payload, list) or not all(
        isinstance(session, dict) and isinstance(session.get("id"), str) and session["id"]
        for session in payload
    ):
        raise RuntimeError("GET /chat/sessions returned an invalid session list")
    return payload


def delete_chat_session(base_url: str, session_id: str) -> None:
    path = f"/chat/sessions/{quote(session_id, safe='')}"
    url = f"{base_url.rstrip('/')}{path}"
    request = Request(url, headers={"Accept": "application/json"}, method="DELETE")
    try:
        with urlopen(request, timeout=30):
            return
    except HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"DELETE {path} failed with HTTP {exc.code}: {body}") from exc
    except URLError as exc:
        raise RuntimeError(f"Could not connect to {url}: {exc.reason}") from exc


def print_cleanup_report(report: dict[str, Any]) -> None:
    print("Chat session cleanup (dev-only)")
    print(f"* Base URL: {report['base_url']}")
    print(f"* Sessions found: {report['sessions_found']}")
    print(f"* Sessions selected: {report['sessions_selected']}")
    print(f"* Mode: {report['mode']}")
    if report["mode"] == "dry-run" and report["selected_sessions"]:
        print("* Selected preview:")
        for session in report["selected_sessions"][:PREVIEW_LIMIT]:
            print(f"  - {session.get('title') or '(untitled)'} [{session['id']}]")
    print(f"* Deleted: {report['deleted_count']}")
    print(f"* Failed: {report['failed_count']}")
    for error in report["errors"]:
        print(f"  - {error['session_id']}: {error['error']}")


def _session_timestamp(session: dict[str, Any]) -> datetime | None:
    for key in ("updated_at", "created_at"):
        value = session.get(key)
        if not isinstance(value, str) or not value:
            continue
        try:
            timestamp = datetime.fromisoformat(value.replace("Z", "+00:00"))
        except ValueError:
            continue
        if timestamp.tzinfo is None:
            timestamp = timestamp.replace(tzinfo=UTC)
        return timestamp.astimezone(UTC)
    return None


def _positive_int(value: str) -> int:
    parsed = int(value)
    if parsed < 1:
        raise argparse.ArgumentTypeError("must be at least 1")
    return parsed


def _non_negative_int(value: str) -> int:
    parsed = int(value)
    if parsed < 0:
        raise argparse.ArgumentTypeError("must be non-negative")
    return parsed


if __name__ == "__main__":
    raise SystemExit(main())
