#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import sys
import textwrap
from dataclasses import dataclass, field
from datetime import UTC, datetime
from pathlib import Path
from typing import Any
from uuid import uuid4
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


DEFAULT_BASE_URL = "http://127.0.0.1:8000"
DEFAULT_QUESTIONS_PATH = Path(__file__).resolve().parents[1] / "evals" / "ask_eval_questions.json"
VECTOR_SCORE_ANNOTATION = "[vector_score="


@dataclass(frozen=True)
class AskEvalQuestion:
    id: str
    question: str
    intent: str
    expected_context_sections: list[str]
    notes: str
    expected_top_items: list[str] = field(default_factory=list)
    expected_top_items_by_section: dict[str, list[str]] = field(default_factory=dict)
    expected_absent_items: list[str] = field(default_factory=list)


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
                expected_top_items=_optional_string_list(item, "expected_top_items", index),
                expected_top_items_by_section=_optional_section_item_lists(
                    item, "expected_top_items_by_section", index
                ),
                expected_absent_items=_optional_string_list(item, "expected_absent_items", index),
            )
        )
    return questions


def main() -> int:
    parser = build_argument_parser()
    args = parser.parse_args()

    questions = load_eval_questions(args.questions_file)
    run_id = generate_run_id()
    timestamp = utc_timestamp()
    mode = "ask" if args.ask else "context_preview"
    results: list[dict[str, Any]] = []
    had_error = False

    print(f"Loaded {len(questions)} Ask eval question(s).")
    print(f"Backend: {args.base_url.rstrip('/')}")
    print(f"Mode: {'context preview + ask' if args.ask else 'context preview only'}")
    print(
        "Retrieval: "
        f"{args.retrieval_mode} "
        f"(memory_top_k={args.memory_top_k}, min_vector_score={args.min_vector_score:g})"
    )
    if args.ask and args.retrieval_mode == "hybrid":
        print("Hybrid retrieval applies only to context_preview; /ask remains keyword-only.")
    if args.run_label:
        print(f"Run label: {args.run_label}")
    print(f"Run ID: {run_id}")

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
                build_context_preview_payload(
                    question=question.question,
                    include_context=args.include_context,
                    retrieval_mode=args.retrieval_mode,
                    memory_top_k=args.memory_top_k,
                    min_vector_score=args.min_vector_score,
                ),
            )
        except RuntimeError as exc:
            error = str(exc)
            had_error = True
            print(f"ERROR: {error}", file=sys.stderr)
            results.append(
                build_eval_result(
                    run_id=run_id,
                    run_label=args.run_label,
                    timestamp=timestamp,
                    base_url=args.base_url,
                    mode=mode,
                    question=question,
                    retrieval_mode=args.retrieval_mode,
                    memory_top_k=args.memory_top_k,
                    min_vector_score=args.min_vector_score,
                    error=error,
                )
            )
            continue

        sections = preview.get("context_sections", [])
        context = str(preview.get("context", ""))
        summary = context_summary(preview)
        useful_sections = useful_context_sections(context)
        expected_summary = expected_section_summary(question.expected_context_sections, context, sections)
        ranking = item_ranking_details(question, context)
        print(f"Returned sections: {', '.join(sections) if sections else '(none)'}")
        print(f"Useful sections: {', '.join(useful_sections) if useful_sections else '(none)'}")
        print(
            "Matched expected sections: "
            f"{', '.join(expected_summary['matched_expected_sections']) if expected_summary['matched_expected_sections'] else '(none)'}"
        )
        print(
            "Empty expected sections: "
            f"{', '.join(expected_summary['empty_expected_sections']) if expected_summary['empty_expected_sections'] else '(none)'}"
        )
        print(
            "Missing expected sections: "
            f"{', '.join(expected_summary['missing_expected_sections']) if expected_summary['missing_expected_sections'] else '(none)'}"
        )
        print(
            "Expected top items: "
            f"{', '.join(question.expected_top_items) if question.expected_top_items else '(none)'}"
        )
        print(
            "Found top items: "
            f"{', '.join(ranking['expected_top_items_found']) if ranking['expected_top_items_found'] else '(none)'}"
        )
        print(
            "Missing top items: "
            f"{', '.join(ranking['expected_top_items_missing']) if ranking['expected_top_items_missing'] else '(none)'}"
        )
        print(f"Item ranking summary: {ranking['item_ranking_summary']}")
        if question.expected_top_items_by_section:
            print(f"Section item ranking summary: {ranking['section_item_ranking_summary']}")
        print(f"Context summary: {summary}")
        print("Context preview:")
        print(indent_block(truncate_text(context, args.context_chars) or "(empty)"))

        answer: str | None = None
        error: str | None = None
        if args.ask:
            try:
                ask_response = post_json(
                    args.base_url,
                    "/ask",
                    build_ask_payload(
                        question=question.question,
                        include_context=args.include_context,
                    ),
                )
            except RuntimeError as exc:
                error = str(exc)
                had_error = True
                print(f"ERROR: {error}", file=sys.stderr)
            else:
                answer = str(ask_response.get("answer", ""))
                print("Answer:")
                print(indent_block(answer or "(empty)"))

        results.append(
            build_eval_result(
                run_id=run_id,
                run_label=args.run_label,
                timestamp=timestamp,
                base_url=args.base_url,
                mode=mode,
                question=question,
                retrieval_mode=args.retrieval_mode,
                memory_top_k=args.memory_top_k,
                min_vector_score=args.min_vector_score,
                preview=preview,
                answer=answer,
                error=error,
            )
        )

    eval_summary = summarize_results(results)
    print_eval_summary(eval_summary)

    if args.output:
        write_results(results, args.output, args.format)
        print(f"\nWrote {len(results)} result(s) to {args.output}")

    return 1 if had_error else 0


def build_argument_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Run manual Orbit Ask context evaluation against a local backend.")
    parser.add_argument("--base-url", default=DEFAULT_BASE_URL, help=f"Backend base URL. Default: {DEFAULT_BASE_URL}")
    parser.add_argument("--questions-file", type=Path, default=DEFAULT_QUESTIONS_PATH, help="Path to eval JSON.")
    parser.add_argument("--ask", action="store_true", help="Also call /ask and print the answer.")
    parser.add_argument("--include-context", action=argparse.BooleanOptionalAction, default=True)
    parser.add_argument("--context-chars", type=int, default=700, help="Context preview characters to print.")
    parser.add_argument("--output", type=Path, help="Optional path to write structured eval results.")
    parser.add_argument("--format", choices=["json", "jsonl"], default="json", help="Output format. Default: json.")
    parser.add_argument("--run-label", help="Optional label stored with every result.")
    parser.add_argument(
        "--retrieval-mode",
        choices=["keyword", "hybrid"],
        default="keyword",
        help="Context preview memory retrieval mode. Default: keyword.",
    )
    parser.add_argument("--memory-top-k", type=int, default=5, help="Hybrid memory candidate limit. Default: 5.")
    parser.add_argument(
        "--min-vector-score",
        type=float,
        default=0.0,
        help="Minimum hybrid vector score. Default: 0.0.",
    )
    return parser


def build_context_preview_payload(
    *,
    question: str,
    include_context: bool,
    retrieval_mode: str = "keyword",
    memory_top_k: int = 5,
    min_vector_score: float = 0.0,
) -> dict[str, Any]:
    return {
        "question": question,
        "include_context": include_context,
        "retrieval_mode": retrieval_mode,
        "memory_top_k": memory_top_k,
        "min_vector_score": min_vector_score,
    }


def build_ask_payload(*, question: str, include_context: bool) -> dict[str, Any]:
    return {
        "question": question,
        "include_context": include_context,
    }


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


def build_eval_result(
    *,
    run_id: str,
    run_label: str | None,
    timestamp: str,
    base_url: str,
    mode: str,
    question: AskEvalQuestion,
    retrieval_mode: str = "keyword",
    memory_top_k: int = 5,
    min_vector_score: float = 0.0,
    preview: dict[str, Any] | None = None,
    answer: str | None = None,
    error: str | None = None,
) -> dict[str, Any]:
    preview = preview or {}
    context = str(preview.get("context", ""))
    expected_summary = expected_section_summary(
        question.expected_context_sections,
        context,
        preview.get("context_sections", []),
    )
    ranking = item_ranking_details(question, context)
    vector_score_count = context.count(VECTOR_SCORE_ANNOTATION)
    return {
        "run_id": run_id,
        "run_label": run_label,
        "timestamp": timestamp,
        "base_url": base_url.rstrip("/"),
        "mode": mode,
        "retrieval_mode": retrieval_mode,
        "memory_top_k": memory_top_k,
        "min_vector_score": min_vector_score,
        "vector_score_annotations_present": vector_score_count > 0,
        "vector_score_count": vector_score_count,
        "question_id": question.id,
        "question": question.question,
        "intent": question.intent,
        "expected_context_sections": question.expected_context_sections,
        "returned_context_sections": preview.get("context_sections", []),
        "useful_context_sections": useful_context_sections(context),
        "matched_expected_sections": expected_summary["matched_expected_sections"],
        "missing_expected_sections": expected_summary["missing_expected_sections"],
        "empty_expected_sections": expected_summary["empty_expected_sections"],
        "expected_top_items": question.expected_top_items,
        "expected_item_positions": ranking["expected_item_positions"],
        "expected_top_items_found": ranking["expected_top_items_found"],
        "expected_top_items_missing": ranking["expected_top_items_missing"],
        "expected_top_items_by_section": question.expected_top_items_by_section,
        "expected_item_positions_by_section": ranking["expected_item_positions_by_section"],
        "section_top_items_found": ranking["section_top_items_found"],
        "section_top_items_missing": ranking["section_top_items_missing"],
        "section_item_ranking_summary": ranking["section_item_ranking_summary"],
        "expected_absent_items": question.expected_absent_items,
        "unexpected_absent_item_hits": ranking["unexpected_absent_item_hits"],
        "item_ranking_summary": ranking["item_ranking_summary"],
        "context_summary": context_summary(preview) if preview else "No context",
        "context": context,
        "answer": answer,
        "error": error,
    }


def write_results(results: list[dict[str, Any]], output_path: Path, output_format: str) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    summary = summarize_results(results)
    if output_format == "json":
        output_path.write_text(
            json.dumps({"summary": summary, "results": results}, indent=2, ensure_ascii=False) + "\n",
            encoding="utf-8",
        )
        return
    if output_format == "jsonl":
        lines = [*results, {"type": "summary", "summary": summary}]
        output_path.write_text(
            "".join(json.dumps(line, ensure_ascii=False) + "\n" for line in lines),
            encoding="utf-8",
        )
        return
    raise ValueError(f"Unsupported output format: {output_format}")


def summarize_results(results: list[dict[str, Any]]) -> dict[str, Any]:
    total_questions = len(results)
    questions_with_errors = sum(result.get("error") is not None for result in results)
    first_result = results[0] if results else {}

    section_match_pass_count = sum(
        not result.get("missing_expected_sections")
        and not result.get("empty_expected_sections")
        for result in results
    )
    section_match_fail_count = total_questions - section_match_pass_count

    section_ranking_results = [
        result for result in results if result.get("expected_top_items_by_section")
    ]
    section_item_ranking_pass_count = sum(
        all(not missing_items for missing_items in result.get("section_top_items_missing", {}).values())
        for result in section_ranking_results
    )
    section_item_ranking_evaluated_count = len(section_ranking_results)
    section_item_ranking_fail_count = (
        section_item_ranking_evaluated_count - section_item_ranking_pass_count
    )

    global_ranking_results = [result for result in results if result.get("expected_top_items")]
    global_item_ranking_pass_count = sum(
        not result.get("expected_top_items_missing") for result in global_ranking_results
    )
    global_item_ranking_evaluated_count = len(global_ranking_results)
    global_item_ranking_fail_count = (
        global_item_ranking_evaluated_count - global_item_ranking_pass_count
    )

    return {
        "retrieval_mode": first_result.get("retrieval_mode", "keyword"),
        "memory_top_k": first_result.get("memory_top_k", 5),
        "min_vector_score": first_result.get("min_vector_score", 0.0),
        "vector_score_annotation_result_count": sum(
            bool(result.get("vector_score_annotations_present")) for result in results
        ),
        "vector_score_annotation_total_count": sum(
            int(result.get("vector_score_count", 0)) for result in results
        ),
        "total_questions": total_questions,
        "questions_with_errors": questions_with_errors,
        "section_match_pass_count": section_match_pass_count,
        "section_match_fail_count": section_match_fail_count,
        "section_match_pass_rate": _pass_rate(section_match_pass_count, total_questions),
        "section_item_ranking_evaluated_count": section_item_ranking_evaluated_count,
        "section_item_ranking_pass_count": section_item_ranking_pass_count,
        "section_item_ranking_fail_count": section_item_ranking_fail_count,
        "section_item_ranking_pass_rate": _pass_rate(
            section_item_ranking_pass_count, section_item_ranking_evaluated_count
        ),
        "global_item_ranking_evaluated_count": global_item_ranking_evaluated_count,
        "global_item_ranking_pass_count": global_item_ranking_pass_count,
        "global_item_ranking_fail_count": global_item_ranking_fail_count,
        "global_item_ranking_pass_rate": _pass_rate(
            global_item_ranking_pass_count, global_item_ranking_evaluated_count
        ),
        "unexpected_absent_item_hit_count": sum(
            len(result.get("unexpected_absent_item_hits", [])) for result in results
        ),
    }


def print_eval_summary(summary: dict[str, Any]) -> None:
    print("\nAsk eval summary")
    print(
        "* Retrieval: "
        f"{summary['retrieval_mode']} "
        f"(memory_top_k={summary['memory_top_k']}, "
        f"min_vector_score={summary['min_vector_score']:g})"
    )
    print(f"* Questions: {summary['total_questions']}")
    print(f"* Request errors: {summary['questions_with_errors']}")
    print(
        "* Section match: "
        f"{summary['section_match_pass_count']}/{summary['total_questions']} passed"
    )
    print(
        "* Section item ranking: "
        f"{summary['section_item_ranking_pass_count']}/"
        f"{summary['section_item_ranking_evaluated_count']} passed"
    )
    print(
        "* Global item ranking: "
        f"{summary['global_item_ranking_pass_count']}/"
        f"{summary['global_item_ranking_evaluated_count']} passed"
    )
    print(f"* Unexpected absent hits: {summary['unexpected_absent_item_hit_count']}")
    print(
        "* Vector score annotations: "
        f"{summary['vector_score_annotation_result_count']} result(s), "
        f"{summary['vector_score_annotation_total_count']} total"
    )
    print("* Global item ranking is legacy/informational; section-aware ranking is preferred.")


def _pass_rate(pass_count: int, evaluated_count: int) -> float:
    return pass_count / evaluated_count if evaluated_count else 0.0


def generate_run_id() -> str:
    return str(uuid4())


def utc_timestamp() -> str:
    return datetime.now(UTC).isoformat()


def parse_context_sections(context: str) -> dict[str, list[str]]:
    sections: dict[str, list[str]] = {}
    current_section: str | None = None

    for raw_line in context.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        if line.endswith(":"):
            current_section = line[:-1]
            sections.setdefault(current_section, [])
            continue
        if current_section is not None:
            sections[current_section].append(line)

    return sections


def section_has_useful_data(section_name: str, lines: list[str]) -> bool:
    item_lines = [line.strip() for line in lines if line.strip().startswith("-")]
    if not item_lines:
        return False
    if section_name == "Today":
        return any(line != "- None" for line in item_lines)
    return any(line != "- None" for line in item_lines)


def useful_context_sections(context: str) -> list[str]:
    sections = parse_context_sections(context)
    return [
        section_name
        for section_name, lines in sections.items()
        if section_has_useful_data(section_name, lines)
    ]


def useful_item_lines(context: str) -> list[str]:
    items: list[str] = []
    for section_name, lines in parse_context_sections(context).items():
        if section_name == "Today":
            continue
        items.extend(
            line
            for line in lines
            if line.startswith("-") and line != "- None"
        )
    return items


def find_item_positions(context: str, expected_items: list[str]) -> dict[str, int | None]:
    item_lines = useful_item_lines(context)
    positions: dict[str, int | None] = {}
    for expected_item in expected_items:
        expected_lower = expected_item.lower()
        positions[expected_item] = next(
            (
                position
                for position, line in enumerate(item_lines, start=1)
                if expected_lower in line.lower()
            ),
            None,
        )
    return positions


def top_item_matches(context: str, expected_items: list[str], *, top_n: int = 5) -> dict[str, Any]:
    positions = find_item_positions(context, expected_items)
    found = [item for item in expected_items if positions[item] is not None and positions[item] <= top_n]
    missing = [item for item in expected_items if item not in found]
    return {
        "positions": positions,
        "found": found,
        "missing": missing,
    }


def find_item_positions_by_section(
    context: str,
    expectations: dict[str, list[str]],
) -> dict[str, dict[str, int | None]]:
    sections = parse_context_sections(context)
    positions_by_section: dict[str, dict[str, int | None]] = {}

    for section_name, expected_items in expectations.items():
        item_lines = [
            line
            for line in sections.get(section_name, [])
            if line.startswith("-") and line != "- None"
        ]
        positions_by_section[section_name] = {}
        for expected_item in expected_items:
            expected_lower = expected_item.lower()
            positions_by_section[section_name][expected_item] = next(
                (
                    position
                    for position, line in enumerate(item_lines, start=1)
                    if expected_lower in line.lower()
                ),
                None,
            )

    return positions_by_section


def section_top_item_matches(
    context: str,
    expectations: dict[str, list[str]],
    *,
    top_n: int = 3,
) -> dict[str, Any]:
    positions = find_item_positions_by_section(context, expectations)
    found: dict[str, list[str]] = {}
    missing: dict[str, list[str]] = {}

    for section_name, expected_items in expectations.items():
        found[section_name] = [
            item
            for item in expected_items
            if positions[section_name][item] is not None
            and positions[section_name][item] <= top_n
        ]
        missing[section_name] = [item for item in expected_items if item not in found[section_name]]

    return {"positions": positions, "found": found, "missing": missing}


def absent_item_matches(context: str, expected_absent_items: list[str]) -> list[str]:
    positions = find_item_positions(context, expected_absent_items)
    return [item for item in expected_absent_items if positions[item] is not None]


def item_ranking_details(question: AskEvalQuestion, context: str, *, top_n: int = 5) -> dict[str, Any]:
    top_matches = top_item_matches(context, question.expected_top_items, top_n=top_n)
    section_top_n = 3
    section_matches = section_top_item_matches(
        context,
        question.expected_top_items_by_section,
        top_n=section_top_n,
    )
    absent_hits = absent_item_matches(context, question.expected_absent_items)

    if not question.expected_top_items and not question.expected_absent_items:
        summary = "No item ranking expectations"
    else:
        summary = (
            f"{len(top_matches['found'])}/{len(question.expected_top_items)} expected top item(s) "
            f"in first {top_n}; {len(absent_hits)} unexpected absent item hit(s)"
        )

    section_expected_count = sum(len(items) for items in question.expected_top_items_by_section.values())
    section_found_count = sum(len(items) for items in section_matches["found"].values())
    if not question.expected_top_items_by_section:
        section_summary = "No section item ranking expectations"
    else:
        section_summary = (
            f"{section_found_count}/{section_expected_count} expected section item(s) "
            f"in first {section_top_n}"
        )

    return {
        "expected_item_positions": top_matches["positions"],
        "expected_top_items_found": top_matches["found"],
        "expected_top_items_missing": top_matches["missing"],
        "expected_item_positions_by_section": section_matches["positions"],
        "section_top_items_found": section_matches["found"],
        "section_top_items_missing": section_matches["missing"],
        "section_item_ranking_summary": section_summary,
        "unexpected_absent_item_hits": absent_hits,
        "item_ranking_summary": summary,
    }


def expected_section_summary(
    expected_sections: list[str],
    context: str,
    returned_sections: list[str] | None = None,
) -> dict[str, list[str]]:
    parsed_sections = parse_context_sections(context)
    returned_section_set = set(returned_sections or parsed_sections.keys())
    useful_section_set = set(useful_context_sections(context))

    matched: list[str] = []
    missing: list[str] = []
    empty: list[str] = []

    for section in expected_sections:
        if section in useful_section_set:
            matched.append(section)
        elif section in returned_section_set:
            empty.append(section)
        else:
            missing.append(section)

    return {
        "matched_expected_sections": matched,
        "missing_expected_sections": missing,
        "empty_expected_sections": empty,
    }


def context_summary(preview: dict[str, Any]) -> str:
    if not preview.get("include_context", True):
        return "Context disabled"
    context = str(preview.get("context", ""))
    if not context.strip() or not preview.get("context_sections", []):
        return "No context"
    useful_sections = useful_context_sections(context)
    data_sections = {"Open todos", "Unpaid bills", "Recent memory", "Latest mood", "Active projects"}
    if any(section in data_sections for section in useful_sections):
        return f"Context ready ({len(useful_sections)} useful section(s))"
    return f"Low context ({len(useful_sections)} useful section(s))"


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


def _optional_string_list(item: dict[str, Any], key: str, index: int) -> list[str]:
    value = item.get(key, [])
    if not isinstance(value, list):
        raise ValueError(f"Eval question at index {index} field '{key}' must be a list of strings.")
    if not all(isinstance(entry, str) and entry.strip() for entry in value):
        raise ValueError(f"Eval question at index {index} field '{key}' must contain strings.")
    return value


def _optional_section_item_lists(
    item: dict[str, Any], key: str, index: int
) -> dict[str, list[str]]:
    value = item.get(key, {})
    if not isinstance(value, dict):
        raise ValueError(f"Eval question at index {index} field '{key}' must be an object.")
    for section, expected_items in value.items():
        if not isinstance(section, str) or not section.strip():
            raise ValueError(
                f"Eval question at index {index} field '{key}' must use non-empty section names."
            )
        if not isinstance(expected_items, list):
            raise ValueError(
                f"Eval question at index {index} field '{key}' section '{section}' must be a list of strings."
            )
        if not all(isinstance(entry, str) and entry.strip() for entry in expected_items):
            raise ValueError(
                f"Eval question at index {index} field '{key}' section '{section}' must contain strings."
            )
    return value


if __name__ == "__main__":
    raise SystemExit(main())
