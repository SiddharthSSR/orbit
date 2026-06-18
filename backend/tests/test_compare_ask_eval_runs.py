import json

import pytest

from scripts.compare_ask_eval_runs import (
    ComparisonInputError,
    compare_eval_runs,
    load_eval_run,
    write_comparison,
)


def test_valid_comparison_summary_includes_metrics_and_deltas() -> None:
    comparison = compare_eval_runs(
        make_run(
            section_rate=0.8,
            ranking_rate=0.5,
            vector_count=0,
            fallback_count=0,
            avg_context_build_ms=4.0,
        ),
        make_run(
            section_rate=1.0,
            ranking_rate=0.75,
            vector_count=12,
            fallback_count=2,
            avg_context_build_ms=9.5,
        ),
    )

    assert comparison["summary"] == {
        "keyword_section_match_pass_rate": 0.8,
        "hybrid_section_match_pass_rate": 1.0,
        "section_match_pass_rate_delta": pytest.approx(0.2),
        "keyword_section_item_ranking_pass_rate": 0.5,
        "hybrid_section_item_ranking_pass_rate": 0.75,
        "section_item_ranking_pass_rate_delta": 0.25,
        "keyword_vector_score_annotation_total_count": 0,
        "hybrid_vector_score_annotation_total_count": 12,
        "vector_score_annotation_total_count_delta": 12,
        "keyword_retrieval_fallback_count": 0,
        "hybrid_retrieval_fallback_count": 2,
        "retrieval_fallback_count_delta": 2,
        "keyword_avg_context_build_ms": 4.0,
        "hybrid_avg_context_build_ms": 9.5,
        "avg_context_build_ms_delta": 5.5,
        "keyword_question_count": 1,
        "hybrid_question_count": 1,
        "compared_question_count": 1,
        "improved_count": 0,
        "preserved_count": 1,
        "degraded_count": 0,
        "changed_count": 0,
    }


def test_classifies_improved_when_hybrid_finds_missed_section_item() -> None:
    keyword = make_result(
        section_found={"Recent memory": []},
        section_missing={"Recent memory": ["AI Notes"]},
    )
    hybrid = make_result(section_found={"Recent memory": ["AI Notes"]})

    question = compare_eval_runs(make_run(keyword), make_run(hybrid))["questions"][0]

    assert question["classification"] == "improved"
    assert question["keyword_section_item_ranking_pass"] is False
    assert question["hybrid_section_item_ranking_pass"] is True


def test_classifies_degraded_when_hybrid_loses_expected_section() -> None:
    keyword = make_result(missing_sections=[])
    hybrid = make_result(missing_sections=["Recent memory"], matched_sections=[])

    question = compare_eval_runs(make_run(keyword), make_run(hybrid))["questions"][0]

    assert question["classification"] == "degraded"


def test_classifies_preserved_when_key_metrics_are_equal() -> None:
    keyword = make_result(positions={"AI Notes": 1})
    hybrid = make_result(positions={"AI Notes": 1}, vector_score_count=2)

    question = compare_eval_runs(make_run(keyword), make_run(hybrid))["questions"][0]

    assert question["classification"] == "preserved"
    assert question["hybrid_vector_score_count"] == 2


def test_write_comparison_uses_summary_and_questions_shape(tmp_path) -> None:
    output = tmp_path / "comparison.json"
    comparison = compare_eval_runs(make_run(), make_run())

    write_comparison(comparison, output)

    saved = json.loads(output.read_text(encoding="utf-8"))
    assert set(saved) == {"summary", "questions"}
    assert saved["questions"][0]["question_id"] == "saved_ai"


@pytest.mark.parametrize(
    ("payload", "message"),
    [
        ([], "must be a JSON object"),
        ({"results": []}, "'summary' object"),
        ({"summary": {}, "results": {}}, "'results' array"),
    ],
)
def test_invalid_input_shape_has_clear_error(tmp_path, payload, message) -> None:
    path = tmp_path / "invalid.json"
    path.write_text(json.dumps(payload), encoding="utf-8")

    with pytest.raises(ComparisonInputError, match=message):
        load_eval_run(path, "keyword")


def test_invalid_json_has_clear_error(tmp_path) -> None:
    path = tmp_path / "invalid.json"
    path.write_text("not-json", encoding="utf-8")

    with pytest.raises(ComparisonInputError, match="not valid JSON"):
        load_eval_run(path, "hybrid")


def test_missing_question_is_reported_as_changed() -> None:
    keyword = make_run(make_result(question_id="keyword_only"))
    hybrid = make_run(make_result(question_id="hybrid_only"))

    comparison = compare_eval_runs(keyword, hybrid)

    assert comparison["summary"]["changed_count"] == 2
    assert [(item["question_id"], item["missing_in"]) for item in comparison["questions"]] == [
        ("keyword_only", "hybrid"),
        ("hybrid_only", "keyword"),
    ]


def make_run(
    result=None,
    *,
    section_rate=1.0,
    ranking_rate=1.0,
    vector_count=0,
    fallback_count=0,
    avg_context_build_ms=5.0,
):
    if result is None:
        result = make_result()
    return {
        "summary": {
            "section_match_pass_rate": section_rate,
            "section_item_ranking_pass_rate": ranking_rate,
            "vector_score_annotation_total_count": vector_count,
            "retrieval_fallback_count": fallback_count,
            "avg_context_build_ms": avg_context_build_ms,
        },
        "results": [result],
    }


def make_result(
    *,
    question_id="saved_ai",
    missing_sections=None,
    matched_sections=None,
    section_found=None,
    section_missing=None,
    positions=None,
    vector_score_count=0,
):
    if missing_sections is None:
        missing_sections = []
    if matched_sections is None:
        matched_sections = ["Recent memory"]
    if section_found is None:
        section_found = {"Recent memory": ["AI Notes"]}
    if section_missing is None:
        section_missing = {"Recent memory": []}
    if positions is None:
        positions = {"AI Notes": 1}
    return {
        "question_id": question_id,
        "question": "What did I save about AI?",
        "missing_expected_sections": missing_sections,
        "matched_expected_sections": matched_sections,
        "expected_top_items_by_section": {"Recent memory": ["AI Notes"]},
        "section_top_items_found": section_found,
        "section_top_items_missing": section_missing,
        "expected_item_positions": positions,
        "vector_score_count": vector_score_count,
    }
