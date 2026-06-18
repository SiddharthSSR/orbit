from pathlib import Path

import pytest

from scripts.run_ask_eval import DEFAULT_BASE_URL, DEFAULT_QUESTIONS_PATH
from scripts.run_ask_eval_samples import (
    DEFAULT_OUTPUT_DIR,
    aggregate_sample_results,
    build_argument_parser,
    sample_output_paths,
)


def test_aggregate_summary_calculation() -> None:
    summary = aggregate_sample_results(
        [make_eval(1.0), make_eval(2.0)],
        [make_eval(3.0, fallbacks=1, attempts=10), make_eval(5.0, attempts=10)],
        [make_comparison(degraded=1, improved=2, preserved=7), make_comparison(preserved=10)],
        max_hybrid_fallback_rate=0.1,
        max_avg_latency_delta_ms=5.0,
        fail_on_degraded=False,
    )

    assert summary == {
        "runs": 2,
        "keyword_avg_context_build_ms_values": [1.0, 2.0],
        "hybrid_avg_context_build_ms_values": [3.0, 5.0],
        "avg_latency_delta_ms_values": [2.0, 3.0],
        "avg_keyword_context_build_ms": 1.5,
        "avg_hybrid_context_build_ms": 4.0,
        "avg_latency_delta_ms": 2.5,
        "max_latency_delta_ms": 3.0,
        "total_keyword_fallbacks": 0,
        "total_hybrid_fallbacks": 1,
        "hybrid_fallback_rate": 0.05,
        "total_degraded_questions": 1,
        "total_improved_questions": 2,
        "total_preserved_questions": 17,
        "keyword_answer_quality_pass_rate_values": [0.0, 0.0],
        "hybrid_answer_quality_pass_rate_values": [0.0, 0.0],
        "avg_keyword_answer_quality_pass_rate": 0.0,
        "avg_hybrid_answer_quality_pass_rate": 0.0,
        "min_keyword_answer_quality_pass_rate": 0.0,
        "min_hybrid_answer_quality_pass_rate": 0.0,
        "total_keyword_answer_quality_failures": 0,
        "total_hybrid_answer_quality_failures": 0,
        "pass": True,
        "failed_thresholds": [],
    }


def test_aggregate_summary_includes_answer_quality_rates() -> None:
    summary = aggregate_sample_results(
        [make_eval(1.0, answer_quality_pass_rate=1.0)],
        [make_eval(2.0, attempts=10, answer_quality_pass_rate=0.8, answer_quality_fail_count=2)],
        [make_comparison()],
        max_hybrid_fallback_rate=0.0,
        max_avg_latency_delta_ms=25.0,
        fail_on_degraded=False,
    )

    assert summary["keyword_answer_quality_pass_rate_values"] == [1.0]
    assert summary["hybrid_answer_quality_pass_rate_values"] == [0.8]
    assert summary["avg_hybrid_answer_quality_pass_rate"] == 0.8
    assert summary["min_hybrid_answer_quality_pass_rate"] == 0.8
    assert summary["total_hybrid_answer_quality_failures"] == 2
    # Default threshold (0.0) does not gate.
    assert summary["pass"] is True


def test_answer_quality_threshold_passes_when_all_hybrid_runs_are_perfect() -> None:
    summary = aggregate_sample_results(
        [make_eval(1.0, answer_quality_pass_rate=1.0), make_eval(1.0, answer_quality_pass_rate=1.0)],
        [
            make_eval(2.0, attempts=10, answer_quality_pass_rate=1.0),
            make_eval(2.0, attempts=10, answer_quality_pass_rate=1.0),
        ],
        [make_comparison(), make_comparison()],
        max_hybrid_fallback_rate=0.0,
        max_avg_latency_delta_ms=25.0,
        fail_on_degraded=False,
        min_hybrid_answer_quality_pass_rate=1.0,
    )

    assert summary["pass"] is True
    assert summary["failed_thresholds"] == []


def test_answer_quality_threshold_fails_when_hybrid_min_below_threshold() -> None:
    summary = aggregate_sample_results(
        [make_eval(1.0, answer_quality_pass_rate=1.0), make_eval(1.0, answer_quality_pass_rate=1.0)],
        [
            make_eval(2.0, attempts=10, answer_quality_pass_rate=1.0),
            make_eval(2.0, attempts=10, answer_quality_pass_rate=0.8, answer_quality_fail_count=2),
        ],
        [make_comparison(), make_comparison()],
        max_hybrid_fallback_rate=0.0,
        max_avg_latency_delta_ms=25.0,
        fail_on_degraded=False,
        min_hybrid_answer_quality_pass_rate=1.0,
    )

    assert summary["pass"] is False
    assert summary["failed_thresholds"] == ["hybrid_answer_quality_pass_rate"]
    assert summary["min_hybrid_answer_quality_pass_rate"] == 0.8


def test_thresholds_pass_at_limits() -> None:
    summary = aggregate_sample_results(
        [make_eval(2.0)],
        [make_eval(7.0, fallbacks=1, attempts=10)],
        [make_comparison()],
        max_hybrid_fallback_rate=0.1,
        max_avg_latency_delta_ms=5.0,
        fail_on_degraded=True,
    )

    assert summary["pass"] is True
    assert summary["failed_thresholds"] == []


def test_threshold_fails_on_hybrid_fallback_rate() -> None:
    summary = aggregate_sample_results(
        [make_eval(1.0)],
        [make_eval(2.0, fallbacks=2, attempts=10)],
        [make_comparison()],
        max_hybrid_fallback_rate=0.1,
        max_avg_latency_delta_ms=25.0,
        fail_on_degraded=False,
    )

    assert summary["pass"] is False
    assert summary["failed_thresholds"] == ["hybrid_fallback_rate"]


def test_threshold_fails_on_average_latency_delta() -> None:
    summary = aggregate_sample_results(
        [make_eval(1.0), make_eval(2.0)],
        [make_eval(31.0, attempts=10), make_eval(32.0, attempts=10)],
        [make_comparison(), make_comparison()],
        max_hybrid_fallback_rate=0.0,
        max_avg_latency_delta_ms=25.0,
        fail_on_degraded=False,
    )

    assert summary["pass"] is False
    assert summary["failed_thresholds"] == ["avg_latency_delta_ms"]


def test_threshold_fails_on_degraded_when_enabled() -> None:
    summary = aggregate_sample_results(
        [make_eval(1.0)],
        [make_eval(2.0, attempts=10)],
        [make_comparison(degraded=1)],
        max_hybrid_fallback_rate=0.0,
        max_avg_latency_delta_ms=25.0,
        fail_on_degraded=True,
    )

    assert summary["pass"] is False
    assert summary["failed_thresholds"] == ["degraded_questions"]


def test_sample_output_file_names() -> None:
    paths = sample_output_paths(Path("eval-results/samples/latest"), 3)

    assert paths.keyword == Path("eval-results/samples/latest/keyword-run-3.json")
    assert paths.hybrid == Path("eval-results/samples/latest/hybrid-run-3.json")
    assert paths.comparison == Path("eval-results/samples/latest/comparison-run-3.json")


def test_cli_argument_defaults_and_overrides() -> None:
    parser = build_argument_parser()
    defaults = parser.parse_args([])

    assert defaults.runs == 5
    assert defaults.base_url == DEFAULT_BASE_URL
    assert defaults.questions_file == DEFAULT_QUESTIONS_PATH
    assert defaults.output_dir == DEFAULT_OUTPUT_DIR
    assert defaults.memory_top_k == 5
    assert defaults.min_vector_score == 0.0
    assert defaults.ask is False
    assert defaults.fail_on_degraded is False
    assert defaults.max_hybrid_fallback_rate == 0.0
    assert defaults.max_avg_latency_delta_ms == 25.0
    assert defaults.min_hybrid_answer_quality_pass_rate == 0.0

    configured = parser.parse_args(
        [
            "--runs",
            "2",
            "--base-url",
            "http://127.0.0.1:8010",
            "--questions-file",
            "custom.json",
            "--output-dir",
            "samples",
            "--memory-top-k",
            "8",
            "--min-vector-score",
            "0.25",
            "--ask",
            "--fail-on-degraded",
            "--max-hybrid-fallback-rate",
            "0.1",
            "--max-avg-latency-delta-ms",
            "10",
            "--min-hybrid-answer-quality-pass-rate",
            "1.0",
        ]
    )

    assert configured.runs == 2
    assert configured.questions_file == Path("custom.json")
    assert configured.output_dir == Path("samples")
    assert configured.memory_top_k == 8
    assert configured.min_vector_score == 0.25
    assert configured.ask is True
    assert configured.fail_on_degraded is True
    assert configured.max_hybrid_fallback_rate == 0.1
    assert configured.max_avg_latency_delta_ms == 10.0
    assert configured.min_hybrid_answer_quality_pass_rate == 1.0


def test_cli_rejects_out_of_range_answer_quality_threshold() -> None:
    with pytest.raises(SystemExit):
        build_argument_parser().parse_args(["--min-hybrid-answer-quality-pass-rate", "1.5"])


@pytest.mark.parametrize(("flag", "value"), [("--runs", "0"), ("--memory-top-k", "21")])
def test_cli_rejects_invalid_integer_controls(flag, value) -> None:
    with pytest.raises(SystemExit):
        build_argument_parser().parse_args([flag, value])


def make_eval(
    latency: float,
    *,
    fallbacks: int = 0,
    attempts: int = 0,
    answer_quality_pass_rate: float | None = None,
    answer_quality_fail_count: int | None = None,
) -> dict:
    summary = {
        "avg_context_build_ms": latency,
        "retrieval_fallback_count": fallbacks,
        "retrieval_vector_attempt_count": attempts,
    }
    # Older eval outputs omit answer-quality fields; only include when provided
    # so the graceful-missing path stays covered.
    if answer_quality_pass_rate is not None:
        summary["answer_quality_pass_rate"] = answer_quality_pass_rate
    if answer_quality_fail_count is not None:
        summary["answer_quality_fail_count"] = answer_quality_fail_count
    return {"summary": summary}


def make_comparison(*, degraded: int = 0, improved: int = 0, preserved: int = 10) -> dict:
    return {
        "summary": {
            "degraded_count": degraded,
            "improved_count": improved,
            "preserved_count": preserved,
        }
    }
