#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable

try:
    from scripts.compare_ask_eval_runs import compare_eval_runs, load_eval_run, write_comparison
    from scripts.run_ask_eval import DEFAULT_BASE_URL, DEFAULT_QUESTIONS_PATH
except ModuleNotFoundError:  # Support direct execution from backend/scripts.
    from compare_ask_eval_runs import compare_eval_runs, load_eval_run, write_comparison
    from run_ask_eval import DEFAULT_BASE_URL, DEFAULT_QUESTIONS_PATH


SCRIPT_DIR = Path(__file__).resolve().parent
RUN_EVAL_SCRIPT = SCRIPT_DIR / "run_ask_eval.py"
DEFAULT_OUTPUT_DIR = Path("eval-results/samples")


class SamplingError(RuntimeError):
    pass


@dataclass(frozen=True)
class SamplePaths:
    keyword: Path
    hybrid: Path
    comparison: Path


def build_argument_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Run repeated keyword/hybrid Orbit Ask eval samples and enforce thresholds."
    )
    parser.add_argument("--runs", type=_positive_int, default=5, help="Number of paired runs. Default: 5.")
    parser.add_argument("--base-url", default=DEFAULT_BASE_URL, help=f"Backend base URL. Default: {DEFAULT_BASE_URL}")
    parser.add_argument("--questions-file", type=Path, default=DEFAULT_QUESTIONS_PATH)
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT_DIR)
    parser.add_argument("--memory-top-k", type=_memory_top_k, default=5)
    parser.add_argument("--min-vector-score", type=float, default=0.0)
    parser.add_argument("--ask", action="store_true", help="Also exercise /ask for every eval.")
    parser.add_argument(
        "--fail-on-degraded",
        action="store_true",
        help="Fail when any comparison contains a degraded question.",
    )
    parser.add_argument(
        "--max-hybrid-fallback-rate",
        type=_non_negative_float,
        default=0.0,
        help="Maximum allowed hybrid fallback rate. Default: 0.0.",
    )
    parser.add_argument(
        "--max-avg-latency-delta-ms",
        type=_non_negative_float,
        default=25.0,
        help="Maximum allowed average hybrid-keyword latency delta. Default: 25.0 ms.",
    )
    return parser


def main() -> int:
    args = build_argument_parser().parse_args()
    try:
        summary = run_samples(args)
    except (SamplingError, ValueError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2

    print_sample_report(summary)
    return 0 if summary["pass"] else 1


def run_samples(
    args: argparse.Namespace,
    *,
    runner: Callable[..., subprocess.CompletedProcess[str]] = subprocess.run,
) -> dict[str, Any]:
    args.output_dir.mkdir(parents=True, exist_ok=True)
    keyword_runs: list[dict[str, Any]] = []
    hybrid_runs: list[dict[str, Any]] = []
    comparisons: list[dict[str, Any]] = []

    for run_number in range(1, args.runs + 1):
        paths = sample_output_paths(args.output_dir, run_number)
        _run_eval(args, "keyword", paths.keyword, runner)
        _run_eval(args, "hybrid", paths.hybrid, runner)

        keyword_run = load_eval_run(paths.keyword, f"keyword run {run_number}")
        hybrid_run = load_eval_run(paths.hybrid, f"hybrid run {run_number}")
        comparison = compare_eval_runs(keyword_run, hybrid_run)
        write_comparison(comparison, paths.comparison)
        keyword_runs.append(keyword_run)
        hybrid_runs.append(hybrid_run)
        comparisons.append(comparison)
        print(f"Completed sample {run_number}/{args.runs}")

    summary = aggregate_sample_results(
        keyword_runs,
        hybrid_runs,
        comparisons,
        max_hybrid_fallback_rate=args.max_hybrid_fallback_rate,
        max_avg_latency_delta_ms=args.max_avg_latency_delta_ms,
        fail_on_degraded=args.fail_on_degraded,
    )
    (args.output_dir / "summary.json").write_text(
        json.dumps(summary, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    return summary


def sample_output_paths(output_dir: Path, run_number: int) -> SamplePaths:
    return SamplePaths(
        keyword=output_dir / f"keyword-run-{run_number}.json",
        hybrid=output_dir / f"hybrid-run-{run_number}.json",
        comparison=output_dir / f"comparison-run-{run_number}.json",
    )


def aggregate_sample_results(
    keyword_runs: list[dict[str, Any]],
    hybrid_runs: list[dict[str, Any]],
    comparisons: list[dict[str, Any]],
    *,
    max_hybrid_fallback_rate: float,
    max_avg_latency_delta_ms: float,
    fail_on_degraded: bool,
) -> dict[str, Any]:
    if not keyword_runs or len(keyword_runs) != len(hybrid_runs) or len(keyword_runs) != len(comparisons):
        raise ValueError("keyword, hybrid, and comparison samples must have the same non-zero length.")

    keyword_latency_values = [
        _required_number(run["summary"], "avg_context_build_ms") for run in keyword_runs
    ]
    hybrid_latency_values = [
        _required_number(run["summary"], "avg_context_build_ms") for run in hybrid_runs
    ]
    latency_delta_values = [
        hybrid - keyword
        for keyword, hybrid in zip(keyword_latency_values, hybrid_latency_values, strict=True)
    ]
    total_keyword_fallbacks = sum(
        int(run["summary"].get("retrieval_fallback_count", 0)) for run in keyword_runs
    )
    total_hybrid_fallbacks = sum(
        int(run["summary"].get("retrieval_fallback_count", 0)) for run in hybrid_runs
    )
    total_hybrid_attempts = sum(
        int(run["summary"].get("retrieval_vector_attempt_count", 0)) for run in hybrid_runs
    )
    hybrid_fallback_rate = (
        total_hybrid_fallbacks / total_hybrid_attempts if total_hybrid_attempts else 0.0
    )
    total_degraded_questions = sum(
        int(comparison["summary"].get("degraded_count", 0)) for comparison in comparisons
    )
    total_improved_questions = sum(
        int(comparison["summary"].get("improved_count", 0)) for comparison in comparisons
    )
    total_preserved_questions = sum(
        int(comparison["summary"].get("preserved_count", 0)) for comparison in comparisons
    )
    avg_latency_delta_ms = _average(latency_delta_values)

    failed_thresholds: list[str] = []
    if hybrid_fallback_rate > max_hybrid_fallback_rate:
        failed_thresholds.append("hybrid_fallback_rate")
    if avg_latency_delta_ms > max_avg_latency_delta_ms:
        failed_thresholds.append("avg_latency_delta_ms")
    if fail_on_degraded and total_degraded_questions > 0:
        failed_thresholds.append("degraded_questions")

    return {
        "runs": len(keyword_runs),
        "keyword_avg_context_build_ms_values": keyword_latency_values,
        "hybrid_avg_context_build_ms_values": hybrid_latency_values,
        "avg_latency_delta_ms_values": latency_delta_values,
        "avg_keyword_context_build_ms": _average(keyword_latency_values),
        "avg_hybrid_context_build_ms": _average(hybrid_latency_values),
        "avg_latency_delta_ms": avg_latency_delta_ms,
        "max_latency_delta_ms": max(latency_delta_values),
        "total_keyword_fallbacks": total_keyword_fallbacks,
        "total_hybrid_fallbacks": total_hybrid_fallbacks,
        "hybrid_fallback_rate": hybrid_fallback_rate,
        "total_degraded_questions": total_degraded_questions,
        "total_improved_questions": total_improved_questions,
        "total_preserved_questions": total_preserved_questions,
        "pass": not failed_thresholds,
        "failed_thresholds": failed_thresholds,
    }


def print_sample_report(summary: dict[str, Any]) -> None:
    print("\nAsk eval sampling summary")
    print(f"* Runs completed: {summary['runs']}")
    print(f"* Average keyword context build: {summary['avg_keyword_context_build_ms']:.2f} ms")
    print(f"* Average hybrid context build: {summary['avg_hybrid_context_build_ms']:.2f} ms")
    print(f"* Average latency delta: {summary['avg_latency_delta_ms']:+.2f} ms")
    print(f"* Maximum latency delta: {summary['max_latency_delta_ms']:+.2f} ms")
    print(f"* Hybrid fallback rate: {summary['hybrid_fallback_rate']:.2%}")
    print(f"* Degraded questions: {summary['total_degraded_questions']}")
    print(f"* Result: {'PASS' if summary['pass'] else 'FAIL'}")
    if summary["failed_thresholds"]:
        print(f"* Failed thresholds: {', '.join(summary['failed_thresholds'])}")


def _run_eval(
    args: argparse.Namespace,
    retrieval_mode: str,
    output_path: Path,
    runner: Callable[..., subprocess.CompletedProcess[str]],
) -> None:
    command = [
        sys.executable,
        str(RUN_EVAL_SCRIPT),
        "--base-url",
        args.base_url,
        "--questions-file",
        str(args.questions_file),
        "--retrieval-mode",
        retrieval_mode,
        "--memory-top-k",
        str(args.memory_top_k),
        "--min-vector-score",
        str(args.min_vector_score),
        "--output",
        str(output_path),
        "--format",
        "json",
    ]
    if args.ask:
        command.append("--ask")
    completed = runner(command, capture_output=True, text=True, check=False)
    if completed.returncode != 0:
        detail = (completed.stderr or completed.stdout or "unknown eval error").strip()
        raise SamplingError(f"{retrieval_mode} eval failed for {output_path.name}: {detail}")


def _average(values: list[float]) -> float:
    return sum(values) / len(values)


def _required_number(summary: dict[str, Any], key: str) -> float:
    value = summary.get(key)
    if not isinstance(value, (int, float)) or isinstance(value, bool):
        raise ValueError(f"sample summary must contain numeric '{key}'.")
    return float(value)


def _positive_int(value: str) -> int:
    parsed = int(value)
    if parsed < 1:
        raise argparse.ArgumentTypeError("must be at least 1")
    return parsed


def _memory_top_k(value: str) -> int:
    parsed = int(value)
    if not 1 <= parsed <= 20:
        raise argparse.ArgumentTypeError("must be between 1 and 20")
    return parsed


def _non_negative_float(value: str) -> float:
    parsed = float(value)
    if parsed < 0:
        raise argparse.ArgumentTypeError("must be non-negative")
    return parsed


if __name__ == "__main__":
    raise SystemExit(main())
