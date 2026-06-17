#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import sys
import textwrap
from dataclasses import dataclass
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


DEFAULT_BASE_URL = "http://127.0.0.1:8000"
DEFAULT_QUESTIONS_PATH = Path(__file__).resolve().parents[1] / "evals" / "ask_eval_questions.json"


@dataclass(frozen=True)
class AskEvalQuestion:
    id: str
    question: str
    intent: str
    expected_context_sections: list[str]
    notes: str


def load_eval_questions(path: Path = DEFAULT_QUESTIONS_PATH) -> list[AskEvalQuestion]:
    with path.open("r", encoding="utf-8") as file:
        raw_questions = json.load(file)

    if not isinstance(raw_questions, list):
        raise ValueError("Eval questions file must contain a list.")

    questions: list[AskEvalQuestion] = []
    for index, item in enumerate(raw_questions):
        if not isinstance(item, dict):
            raise ValueError(f"Eval question at index {index} must be an object.")
        questions.append(
            AskEvalQuestion(
                id=_required_string(item, "id", index),
                question=_required_string(item, "question", index),
                intent=_required_string(item, "intent", index),
                expected_context_sections=_required_string_list(item, "expected_context_sections", index),
                notes=_required_string(item, "notes", index),
            )
        )
    return questions


def main() -> int:
    parser = argparse.ArgumentParser(description="Run manual Orbit Ask context evaluation against a local backend.")
    parser.add_argument("--base-url", default=DEFAULT_BASE_URL, help=f"Backend base URL. Default: {DEFAULT_BASE_URL}")
    parser.add_argument("--questions-file", type=Path, default=DEFAULT_QUESTIONS_PATH, help="Path to eval JSON.")
    parser.add_argument("--ask", action="store_true", help="Also call /ask and print the answer.")
    parser.add_argument("--include-context", action=argparse.BooleanOptionalAction, default=True)
    parser.add_argument("--context-chars", type=int, default=700, help="Context preview characters to print.")
    args = parser.parse_args()

    questions = load_eval_questions(args.questions_file)
    print(f"Loaded {len(questions)} Ask eval question(s).")
    print(f"Backend: {args.base_url.rstrip('/')}")
    print(f"Mode: {'context preview + ask' if args.ask else 'context preview only'}")

    for question in questions:
        print("\n" + "=" * 88)
        print(f"{question.id} [{question.intent}]")
        print(f"Q: {question.question}")
        print(f"Expected sections: {', '.join(question.expected_context_sections)}")
        print(f"Notes: {question.notes}")

        try:
            preview = post_json(
                args.base_url,
                "/ask/context-preview",
                {
                    "question": question.question,
                    "include_context": args.include_context,
                },
            )
        except RuntimeError as exc:
            print(f"ERROR: {exc}", file=sys.stderr)
            return 1

        sections = preview.get("context_sections", [])
        context = str(preview.get("context", ""))
        print(f"Returned sections: {', '.join(sections) if sections else '(none)'}")
        print(f"Context summary: {context_summary(preview)}")
        print("Context preview:")
        print(indent_block(truncate_text(context, args.context_chars) or "(empty)"))

        if args.ask:
            try:
                ask_response = post_json(
                    args.base_url,
                    "/ask",
                    {
                        "question": question.question,
                        "include_context": args.include_context,
                    },
                )
            except RuntimeError as exc:
                print(f"ERROR: {exc}", file=sys.stderr)
                return 1
            print("Answer:")
            print(indent_block(str(ask_response.get("answer", "")) or "(empty)"))

    return 0


def post_json(base_url: str, path: str, payload: dict[str, Any]) -> dict[str, Any]:
    url = f"{base_url.rstrip('/')}{path}"
    request = Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Accept": "application/json", "Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urlopen(request, timeout=30) as response:
            return json.loads(response.read().decode("utf-8"))
    except HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"{path} failed with HTTP {exc.code}: {body}") from exc
    except URLError as exc:
        raise RuntimeError(f"Could not connect to {url}: {exc.reason}") from exc


def context_summary(preview: dict[str, Any]) -> str:
    if not preview.get("include_context", True):
        return "Context disabled"
    sections = preview.get("context_sections", [])
    if not sections:
        return "No context"
    useful_sections = {"Open todos", "Unpaid bills", "Recent memory", "Latest mood", "Active projects"}
    if any(section in useful_sections for section in sections):
        return f"Context ready ({len(sections)} section(s))"
    return f"Low context ({len(sections)} section(s))"


def truncate_text(value: str, max_chars: int) -> str:
    if max_chars <= 0 or len(value) <= max_chars:
        return value
    return f"{value[: max_chars - 3].rstrip()}..."


def indent_block(value: str) -> str:
    return textwrap.indent(value, "  ")


def _required_string(item: dict[str, Any], key: str, index: int) -> str:
    value = item.get(key)
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"Eval question at index {index} requires non-empty string field '{key}'.")
    return value


def _required_string_list(item: dict[str, Any], key: str, index: int) -> list[str]:
    value = item.get(key)
    if not isinstance(value, list) or not value:
        raise ValueError(f"Eval question at index {index} requires non-empty list field '{key}'.")
    if not all(isinstance(section, str) and section.strip() for section in value):
        raise ValueError(f"Eval question at index {index} field '{key}' must contain strings.")
    return value


if __name__ == "__main__":
    raise SystemExit(main())
