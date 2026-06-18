#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any


SUMMARY_METRICS = (
    "section_match_pass_rate",
    "section_item_ranking_pass_rate",
    "vector_score_annotation_total_count",
)


class ComparisonInputError(ValueError):
    """Raised when an eval run cannot be compared safely."""


def build_argument_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Compare keyword and hybrid Orbit Ask eval JSON runs."
    )
    parser.add_argument("--keyword", type=Path, required=True, help="Keyword eval JSON path.")
    parser.add_argument("--hybrid", type=Path, required=True, help="Hybrid eval JSON path.")
    parser.add_argument("--output", type=Path, help="Optional comparison JSON output path.")
    return parser


def main() -> int:
    args = build_argument_parser().parse_args()
    try:
        keyword = load_eval_run(args.keyword, "keyword")
        hybrid = load_eval_run(args.hybrid, "hybrid")
        comparison = compare_eval_runs(keyword, hybrid)
    except ComparisonInputError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2

    print_comparison_report(comparison)
    if args.output:
        write_comparison(comparison, args.output)
        print(f"\nWrote comparison to {args.output}")
    return 0


def load_eval_run(path: Path, label: str) -> dict[str, Any]:
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise ComparisonInputError(f"{label} eval file not found: {path}") from exc
    except OSError as exc:
        raise ComparisonInputError(f"could not read {label} eval file {path}: {exc}") from exc
    except json.JSONDecodeError as exc:
        raise ComparisonInputError(
            f"{label} eval file is not valid JSON: {path} ({exc.msg})"
        ) from exc

    validate_eval_run(raw, label)
    return raw


def validate_eval_run(raw: Any, label: str) -> None:
    if not isinstance(raw, dict):
        raise ComparisonInputError(f"{label} eval must be a JSON object.")
    if not isinstance(raw.get("summary"), dict):
        raise ComparisonInputError(f"{label} eval must contain a 'summary' object.")
    if not isinstance(raw.get("results"), list):
        raise ComparisonInputError(f"{label} eval must contain a 'results' array.")

    summary = raw["summary"]
    for metric in SUMMARY_METRICS:
        value = summary.get(metric)
        if not isinstance(value, (int, float)) or isinstance(value, bool):
            raise ComparisonInputError(
                f"{label} eval summary must contain numeric '{metric}'."
            )

    seen_ids: set[str] = set()
    for index, result in enumerate(raw["results"]):
        if not isinstance(result, dict):
            raise ComparisonInputError(f"{label} eval result at index {index} must be an object.")
        question_id = result.get("question_id")
        if not isinstance(question_id, str) or not question_id:
            raise ComparisonInputError(
                f"{label} eval result at index {index} must contain a non-empty 'question_id'."
            )
        if question_id in seen_ids:
            raise ComparisonInputError(
                f"{label} eval contains duplicate question_id '{question_id}'."
            )
        seen_ids.add(question_id)
        if not isinstance(result.get("question"), str):
            raise ComparisonInputError(
                f"{label} eval result '{question_id}' must contain a string 'question'."
            )


def compare_eval_runs(
    keyword: dict[str, Any], hybrid: dict[str, Any]
) -> dict[str, Any]:
    validate_eval_run(keyword, "keyword")
    validate_eval_run(hybrid, "hybrid")

    keyword_results = {result["question_id"]: result for result in keyword["results"]}
    hybrid_results = {result["question_id"]: result for result in hybrid["results"]}
    question_ids = [*keyword_results]
    question_ids.extend(question_id for question_id in hybrid_results if question_id not in keyword_results)

    questions = [
        compare_question(keyword_results.get(question_id), hybrid_results.get(question_id))
        for question_id in question_ids
    ]
    keyword_summary = keyword["summary"]
    hybrid_summary = hybrid["summary"]
    keyword_avg_context_build_ms = _optional_number(
        keyword_summary.get("avg_context_build_ms")
    )
    hybrid_avg_context_build_ms = _optional_number(
        hybrid_summary.get("avg_context_build_ms")
    )
    summary: dict[str, Any] = {
        "keyword_section_match_pass_rate": keyword_summary["section_match_pass_rate"],
        "hybrid_section_match_pass_rate": hybrid_summary["section_match_pass_rate"],
        "section_match_pass_rate_delta": (
            hybrid_summary["section_match_pass_rate"]
            - keyword_summary["section_match_pass_rate"]
        ),
        "keyword_section_item_ranking_pass_rate": keyword_summary[
            "section_item_ranking_pass_rate"
        ],
        "hybrid_section_item_ranking_pass_rate": hybrid_summary[
            "section_item_ranking_pass_rate"
        ],
        "section_item_ranking_pass_rate_delta": (
            hybrid_summary["section_item_ranking_pass_rate"]
            - keyword_summary["section_item_ranking_pass_rate"]
        ),
        "keyword_vector_score_annotation_total_count": keyword_summary[
            "vector_score_annotation_total_count"
        ],
        "hybrid_vector_score_annotation_total_count": hybrid_summary[
            "vector_score_annotation_total_count"
        ],
        "vector_score_annotation_total_count_delta": (
            hybrid_summary["vector_score_annotation_total_count"]
            - keyword_summary["vector_score_annotation_total_count"]
        ),
        "keyword_retrieval_fallback_count": int(
            keyword_summary.get("retrieval_fallback_count", 0)
        ),
        "hybrid_retrieval_fallback_count": int(
            hybrid_summary.get("retrieval_fallback_count", 0)
        ),
        "retrieval_fallback_count_delta": int(
            hybrid_summary.get("retrieval_fallback_count", 0)
        )
        - int(keyword_summary.get("retrieval_fallback_count", 0)),
        "keyword_avg_context_build_ms": keyword_avg_context_build_ms,
        "hybrid_avg_context_build_ms": hybrid_avg_context_build_ms,
        "avg_context_build_ms_delta": (
            hybrid_avg_context_build_ms - keyword_avg_context_build_ms
            if keyword_avg_context_build_ms is not None
            and hybrid_avg_context_build_ms is not None
            else None
        ),
        "keyword_question_count": len(keyword_results),
        "hybrid_question_count": len(hybrid_results),
        "compared_question_count": len(questions),
    }
    for classification in ("improved", "preserved", "degraded", "changed"):
        summary[f"{classification}_count"] = sum(
            question["classification"] == classification for question in questions
        )
    return {"summary": summary, "questions": questions}


def compare_question(
    keyword: dict[str, Any] | None, hybrid: dict[str, Any] | None
) -> dict[str, Any]:
    source = keyword or hybrid
    if source is None:  # Defensive; callers always provide at least one side.
        raise ComparisonInputError("cannot compare a question missing from both eval runs.")

    keyword_missing = _string_list(keyword, "missing_expected_sections")
    hybrid_missing = _string_list(hybrid, "missing_expected_sections")
    keyword_found = _section_item_set(keyword)
    hybrid_found = _section_item_set(hybrid)
    missing_in = "keyword" if keyword is None else "hybrid" if hybrid is None else None

    if missing_in:
        classification = "changed"
    elif len(hybrid_missing) > len(keyword_missing) or keyword_found - hybrid_found:
        classification = "degraded"
    elif len(hybrid_missing) < len(keyword_missing) or hybrid_found - keyword_found:
        classification = "improved"
    elif (
        keyword_missing == hybrid_missing
        and _string_list(keyword, "matched_expected_sections")
        == _string_list(hybrid, "matched_expected_sections")
        and keyword_found == hybrid_found
        and _section_item_pass(keyword) == _section_item_pass(hybrid)
        and _positions(keyword) == _positions(hybrid)
    ):
        classification = "preserved"
    else:
        classification = "changed"

    return {
        "question_id": source["question_id"],
        "question": source["question"],
        "classification": classification,
        "missing_in": missing_in,
        "keyword_missing_expected_sections": keyword_missing,
        "hybrid_missing_expected_sections": hybrid_missing,
        "keyword_matched_expected_sections": _string_list(keyword, "matched_expected_sections"),
        "hybrid_matched_expected_sections": _string_list(hybrid, "matched_expected_sections"),
        "keyword_section_item_ranking_pass": _section_item_pass(keyword),
        "hybrid_section_item_ranking_pass": _section_item_pass(hybrid),
        "keyword_top_expected_item_positions": _positions(keyword),
        "hybrid_top_expected_item_positions": _positions(hybrid),
        "hybrid_vector_score_count": int(hybrid.get("vector_score_count", 0)) if hybrid else 0,
    }


def write_comparison(comparison: dict[str, Any], output_path: Path) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(
        json.dumps(comparison, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )


def print_comparison_report(comparison: dict[str, Any]) -> None:
    summary = comparison["summary"]
    print("Ask eval comparison")
    print(
        "* Section match pass rate: "
        f"keyword {_percent(summary['keyword_section_match_pass_rate'])}, "
        f"hybrid {_percent(summary['hybrid_section_match_pass_rate'])}, "
        f"delta {_signed_percent(summary['section_match_pass_rate_delta'])}"
    )
    print(
        "* Section item ranking pass rate: "
        f"keyword {_percent(summary['keyword_section_item_ranking_pass_rate'])}, "
        f"hybrid {_percent(summary['hybrid_section_item_ranking_pass_rate'])}, "
        f"delta {_signed_percent(summary['section_item_ranking_pass_rate_delta'])}"
    )
    print(
        "* Vector score annotations: "
        f"keyword {summary['keyword_vector_score_annotation_total_count']}, "
        f"hybrid {summary['hybrid_vector_score_annotation_total_count']}, "
        f"delta {summary['vector_score_annotation_total_count_delta']:+g}"
    )
    print(
        "* Retrieval fallbacks: "
        f"keyword {summary['keyword_retrieval_fallback_count']}, "
        f"hybrid {summary['hybrid_retrieval_fallback_count']}, "
        f"delta {summary['retrieval_fallback_count_delta']:+d}"
    )
    if summary["avg_context_build_ms_delta"] is not None:
        print(
            "* Average context build: "
            f"keyword {summary['keyword_avg_context_build_ms']:.2f} ms, "
            f"hybrid {summary['hybrid_avg_context_build_ms']:.2f} ms, "
            f"delta {summary['avg_context_build_ms_delta']:+.2f} ms"
        )
    print(
        "* Classifications: "
        f"{summary['improved_count']} improved, "
        f"{summary['preserved_count']} preserved, "
        f"{summary['degraded_count']} degraded, "
        f"{summary['changed_count']} changed"
    )

    for classification in ("degraded", "improved", "changed"):
        matching = [
            question
            for question in comparison["questions"]
            if question["classification"] == classification
        ]
        if matching:
            print(f"\n{classification.title()} questions")
            for question in matching:
                suffix = f" (missing in {question['missing_in']} run)" if question["missing_in"] else ""
                print(f"- {question['question_id']}: {question['question']}{suffix}")


def _string_list(result: dict[str, Any] | None, key: str) -> list[str]:
    if result is None:
        return []
    value = result.get(key, [])
    return list(value) if isinstance(value, list) else []


def _section_item_set(result: dict[str, Any] | None) -> set[tuple[str, str]]:
    if result is None:
        return set()
    found = result.get("section_top_items_found", {})
    if not isinstance(found, dict):
        return set()
    return {
        (str(section), str(item))
        for section, items in found.items()
        if isinstance(items, list)
        for item in items
    }


def _section_item_pass(result: dict[str, Any] | None) -> bool | None:
    if result is None or not result.get("expected_top_items_by_section"):
        return None
    missing = result.get("section_top_items_missing", {})
    if not isinstance(missing, dict):
        return None
    return all(not items for items in missing.values())


def _positions(result: dict[str, Any] | None) -> dict[str, int | None]:
    if result is None:
        return {}
    positions = result.get("expected_item_positions", {})
    return dict(positions) if isinstance(positions, dict) else {}


def _percent(value: float) -> str:
    return f"{value:.1%}"


def _signed_percent(value: float) -> str:
    return f"{value:+.1%}"


def _optional_number(value: Any) -> float | None:
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        return float(value)
    return None


if __name__ == "__main__":
    raise SystemExit(main())
