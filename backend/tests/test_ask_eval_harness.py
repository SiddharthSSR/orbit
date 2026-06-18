import json
import sys

import pytest
import scripts.run_ask_eval as ask_eval

from scripts.run_ask_eval import (
    AskEvalQuestion,
    build_argument_parser,
    build_ask_payload,
    build_context_preview_payload,
    build_eval_result,
    context_summary,
    find_item_positions,
    find_item_positions_by_section,
    load_eval_questions,
    parse_context_sections,
    section_top_item_matches,
    summarize_results,
    useful_context_sections,
    write_results,
)


def test_ask_eval_questions_have_expected_shape() -> None:
    questions = load_eval_questions()

    assert 8 <= len(questions) <= 12
    ids = {question.id for question in questions}
    assert len(ids) == len(questions)
    assert "focus_today" in ids
    assert "saved_ai" in ids
    assert "furlenco_bill" in ids
    saved_ai = next(question for question in questions if question.id == "saved_ai")
    assert saved_ai.expected_top_items == ["AI Agents Reading List"]
    assert saved_ai.expected_top_items_by_section == {
        "Recent memory": ["AI Agents Reading List"]
    }

    for question in questions:
        assert question.question
        assert question.intent
        assert question.expected_context_sections
        assert question.notes


def test_default_eval_request_uses_keyword_retrieval() -> None:
    args = build_argument_parser().parse_args([])
    payload = build_context_preview_payload(
        question="What did I save about AI?",
        include_context=True,
        retrieval_mode=args.retrieval_mode,
        memory_top_k=args.memory_top_k,
        min_vector_score=args.min_vector_score,
    )

    assert payload == {
        "question": "What did I save about AI?",
        "include_context": True,
        "retrieval_mode": "keyword",
        "memory_top_k": 5,
        "min_vector_score": 0.0,
    }


def test_hybrid_flags_are_sent_to_context_preview() -> None:
    args = build_argument_parser().parse_args(
        [
            "--retrieval-mode",
            "hybrid",
            "--memory-top-k",
            "8",
            "--min-vector-score",
            "0.25",
        ]
    )

    payload = build_context_preview_payload(
        question="How is WorldLens going?",
        include_context=True,
        retrieval_mode=args.retrieval_mode,
        memory_top_k=args.memory_top_k,
        min_vector_score=args.min_vector_score,
    )

    assert payload["retrieval_mode"] == "hybrid"
    assert payload["memory_top_k"] == 8
    assert payload["min_vector_score"] == 0.25


def test_ask_payload_remains_keyword_only() -> None:
    assert build_ask_payload(question="What did I save about AI?", include_context=True) == {
        "question": "What did I save about AI?",
        "include_context": True,
    }


def test_load_eval_questions_rejects_invalid_shape(tmp_path) -> None:
    invalid_file = tmp_path / "invalid_eval_questions.json"
    invalid_file.write_text(json.dumps([{"id": "missing_fields"}]), encoding="utf-8")

    with pytest.raises(ValueError, match="question"):
        load_eval_questions(invalid_file)


def test_load_eval_questions_rejects_non_string_expected_top_items(tmp_path) -> None:
    invalid_file = tmp_path / "invalid_top_items.json"
    invalid_file.write_text(
        json.dumps(
            [
                {
                    "id": "saved_ai",
                    "question": "What did I save about AI?",
                    "intent": "memory_recall",
                    "expected_context_sections": ["Recent memory"],
                    "expected_top_items": ["AI Agents Reading List", 42],
                    "notes": "Invalid ranking fixture.",
                }
            ]
        ),
        encoding="utf-8",
    )

    with pytest.raises(ValueError, match="expected_top_items"):
        load_eval_questions(invalid_file)


def test_load_eval_questions_rejects_non_list_section_expectations(tmp_path) -> None:
    invalid_file = tmp_path / "invalid_section_top_items.json"
    invalid_file.write_text(
        json.dumps(
            [
                {
                    "id": "saved_ai",
                    "question": "What did I save about AI?",
                    "intent": "memory_recall",
                    "expected_context_sections": ["Recent memory"],
                    "expected_top_items_by_section": {
                        "Recent memory": "AI Agents Reading List"
                    },
                    "notes": "Invalid section ranking fixture.",
                }
            ]
        ),
        encoding="utf-8",
    )

    with pytest.raises(ValueError, match="expected_top_items_by_section.*must be a list"):
        load_eval_questions(invalid_file)


def test_parse_context_sections_parses_sections_and_body_lines() -> None:
    context = """
    Today:
    - 2026-06-17

    Open todos:
    - None

    Unpaid bills:
    - [Due soon] Furlenco: due 2026-06-21
    """

    sections = parse_context_sections(context)

    assert sections == {
        "Today": ["- 2026-06-17"],
        "Open todos": ["- None"],
        "Unpaid bills": ["- [Due soon] Furlenco: due 2026-06-21"],
    }


def test_useful_context_sections_excludes_sections_with_none() -> None:
    context = """
    Today:
    - 2026-06-17

    Open todos:
    - None

    Unpaid bills:
    - [Due soon] Furlenco: due 2026-06-21

    Recent memory:
    - None
    """

    assert useful_context_sections(context) == ["Today", "Unpaid bills"]


def test_context_summary_is_low_context_when_data_sections_are_empty() -> None:
    preview = {
        "include_context": True,
        "context_sections": ["Today", "Open todos", "Unpaid bills", "Recent memory"],
        "context": """
        Today:
        - 2026-06-17

        Open todos:
        - None

        Unpaid bills:
        - None

        Recent memory:
        - None
        """,
    }

    assert context_summary(preview) == "Low context (1 useful section(s))"


def test_find_item_positions_finds_items_case_insensitively() -> None:
    context = """
    Today:
    - 2026-06-18

    Open todos:
    - [Overdue] Ship Orbit Ask eval improvements

    Recent memory:
    - Weekend Grocery List (note): Coffee
    - AI Agents Reading List (article) [ai, agents]: Agent notes
    """

    positions = find_item_positions(context, ["orbit", "ai agents reading list"])

    assert positions == {"orbit": 1, "ai agents reading list": 3}


def test_find_item_positions_reports_missing_item_as_none() -> None:
    context = "Recent memory:\n- AI Agents Reading List (article): Agent notes"

    positions = find_item_positions(context, ["AI Agents Reading List", "WorldLens"])

    assert positions["AI Agents Reading List"] == 1
    assert positions["WorldLens"] is None


def test_find_item_positions_by_section_is_case_insensitive_and_section_local() -> None:
    context = """
    Open todos:
    - Review WorldLens prototype
    - Ship Orbit Ask eval improvements

    Recent memory:
    - WorldLens Project Update (note): Status
    - AI Agents Reading List (article): Notes
    """

    positions = find_item_positions_by_section(
        context,
        {
            "Open todos": ["review worldlens prototype", "AI Agents Reading List"],
            "Recent memory": ["ai agents reading list"],
        },
    )

    assert positions == {
        "Open todos": {"review worldlens prototype": 1, "AI Agents Reading List": None},
        "Recent memory": {"ai agents reading list": 2},
    }


def test_section_top_item_matches_does_not_count_item_from_wrong_section() -> None:
    context = "Open todos:\n- AI Agents Reading List\n\nRecent memory:\n- Weekend notes"

    matches = section_top_item_matches(
        context,
        {"Recent memory": ["AI Agents Reading List"]},
    )

    assert matches["found"] == {"Recent memory": []}
    assert matches["missing"] == {"Recent memory": ["AI Agents Reading List"]}


def test_write_results_json_writes_summary_and_result_objects(tmp_path) -> None:
    result = make_result()
    output_path = tmp_path / "results" / "latest.json"

    write_results([result], output_path, "json")

    saved = json.loads(output_path.read_text(encoding="utf-8"))
    assert saved["summary"]["total_questions"] == 1
    assert saved["summary"]["retrieval_mode"] == "keyword"
    assert saved["summary"]["section_match_pass_count"] == 1
    assert saved["results"][0]["run_id"] == "run-1"
    assert saved["results"][0]["question_id"] == "saved_ai"
    assert saved["results"][0]["returned_context_sections"] == ["Today", "Recent memory"]
    assert saved["results"][0]["useful_context_sections"] == ["Today", "Recent memory"]


def test_write_results_jsonl_appends_summary_line(tmp_path) -> None:
    first = make_result(question_id="saved_ai")
    second = make_result(question_id="focus_today")
    output_path = tmp_path / "results.jsonl"

    write_results([first, second], output_path, "jsonl")

    lines = output_path.read_text(encoding="utf-8").splitlines()
    assert len(lines) == 3
    assert json.loads(lines[0])["question_id"] == "saved_ai"
    assert json.loads(lines[1])["question_id"] == "focus_today"
    summary_line = json.loads(lines[2])
    assert summary_line["type"] == "summary"
    assert summary_line["summary"]["total_questions"] == 2
    assert summary_line["summary"]["retrieval_mode"] == "keyword"


def test_summarize_results_computes_section_match_pass_and_fail_counts() -> None:
    results = [
        make_summary_result(),
        make_summary_result(missing_expected_sections=["Recent memory"]),
        make_summary_result(empty_expected_sections=["Unpaid bills"], error="Request failed"),
    ]

    summary = summarize_results(results)

    assert summary["total_questions"] == 3
    assert summary["questions_with_errors"] == 1
    assert summary["section_match_pass_count"] == 1
    assert summary["section_match_fail_count"] == 2
    assert summary["section_match_pass_rate"] == pytest.approx(1 / 3)


def test_summarize_results_computes_section_item_ranking_counts() -> None:
    results = [
        make_summary_result(
            expected_top_items_by_section={"Recent memory": ["AI Notes"]},
            section_top_items_missing={"Recent memory": []},
        ),
        make_summary_result(
            expected_top_items_by_section={"Open todos": ["Ship Orbit"]},
            section_top_items_missing={"Open todos": ["Ship Orbit"]},
        ),
        make_summary_result(),
    ]

    summary = summarize_results(results)

    assert summary["section_item_ranking_evaluated_count"] == 2
    assert summary["section_item_ranking_pass_count"] == 1
    assert summary["section_item_ranking_fail_count"] == 1
    assert summary["section_item_ranking_pass_rate"] == 0.5


def test_summarize_results_computes_global_ranking_and_absent_hit_counts() -> None:
    results = [
        make_summary_result(
            expected_top_items=["AI Notes"],
            expected_top_items_missing=[],
            unexpected_absent_item_hits=["Archived note"],
        ),
        make_summary_result(
            expected_top_items=["WorldLens"],
            expected_top_items_missing=["WorldLens"],
            unexpected_absent_item_hits=["Paid bill", "Archived project"],
        ),
        make_summary_result(),
    ]

    summary = summarize_results(results)

    assert summary["global_item_ranking_evaluated_count"] == 2
    assert summary["global_item_ranking_pass_count"] == 1
    assert summary["global_item_ranking_fail_count"] == 1
    assert summary["global_item_ranking_pass_rate"] == 0.5
    assert summary["unexpected_absent_item_hit_count"] == 3


def test_summarize_results_includes_retrieval_and_vector_annotation_counts() -> None:
    results = [
        make_summary_result(
            retrieval_mode="hybrid",
            memory_top_k=8,
            min_vector_score=0.25,
            vector_score_annotations_present=True,
            vector_score_count=2,
        ),
        make_summary_result(
            retrieval_mode="hybrid",
            memory_top_k=8,
            min_vector_score=0.25,
            vector_score_annotations_present=False,
            vector_score_count=0,
        ),
    ]

    summary = summarize_results(results)

    assert summary["retrieval_mode"] == "hybrid"
    assert summary["memory_top_k"] == 8
    assert summary["min_vector_score"] == 0.25
    assert summary["vector_score_annotation_result_count"] == 1
    assert summary["vector_score_annotation_total_count"] == 2


def test_build_eval_result_represents_per_question_error() -> None:
    question = make_question()

    result = build_eval_result(
        run_id="run-1",
        run_label="mock-smoke",
        timestamp="2026-06-17T00:00:00+00:00",
        base_url="http://127.0.0.1:8000/",
        mode="context_preview",
        question=question,
        error="Could not connect",
    )

    assert result["run_id"] == "run-1"
    assert result["run_label"] == "mock-smoke"
    assert result["base_url"] == "http://127.0.0.1:8000"
    assert result["mode"] == "context_preview"
    assert result["question_id"] == "saved_ai"
    assert result["returned_context_sections"] == []
    assert result["useful_context_sections"] == []
    assert result["matched_expected_sections"] == []
    assert result["missing_expected_sections"] == ["Recent memory"]
    assert result["empty_expected_sections"] == []
    assert result["context_summary"] == "No context"
    assert result["context"] == ""
    assert result["answer"] is None
    assert result["error"] == "Could not connect"


def test_build_eval_result_includes_matched_missing_and_empty_expected_sections() -> None:
    question = AskEvalQuestion(
        id="mixed",
        question="What should I do?",
        intent="daily_planning",
        expected_context_sections=["Open todos", "Unpaid bills", "Recent memory"],
        notes="Mixed section state.",
    )

    result = build_eval_result(
        run_id="run-1",
        run_label=None,
        timestamp="2026-06-17T00:00:00+00:00",
        base_url="http://127.0.0.1:8000",
        mode="context_preview",
        question=question,
        preview={
            "include_context": True,
            "context_sections": ["Today", "Open todos", "Unpaid bills"],
            "context": """
            Today:
            - 2026-06-17

            Open todos:
            - [Due today] Plan day

            Unpaid bills:
            - None
            """,
        },
    )

    assert result["useful_context_sections"] == ["Today", "Open todos"]
    assert result["matched_expected_sections"] == ["Open todos"]
    assert result["empty_expected_sections"] == ["Unpaid bills"]
    assert result["missing_expected_sections"] == ["Recent memory"]
    assert result["context_summary"] == "Context ready (2 useful section(s))"


def test_build_eval_result_includes_item_ranking_fields() -> None:
    question = AskEvalQuestion(
        id="saved_ai",
        question="What did I save about AI?",
        intent="memory_recall",
        expected_context_sections=["Recent memory"],
        notes="AI memory should rank highly.",
        expected_top_items=["AI Agents Reading List", "Missing AI Note"],
        expected_top_items_by_section={
            "Recent memory": ["AI Agents Reading List", "Missing AI Note"],
            "Unpaid bills": ["Internet Bill Paid"],
        },
        expected_absent_items=["Internet Bill Paid"],
    )

    result = build_eval_result(
        run_id="run-1",
        run_label=None,
        timestamp="2026-06-18T00:00:00+00:00",
        base_url="http://127.0.0.1:8000",
        mode="context_preview",
        question=question,
        preview={
            "include_context": True,
            "context_sections": ["Today", "Recent memory", "Unpaid bills"],
            "context": """
            Today:
            - 2026-06-18

            Recent memory:
            - AI Agents Reading List (article) [ai, agents]: Agent notes

            Unpaid bills:
            - Internet Bill Paid: due 2026-06-17
            """,
        },
    )

    assert result["expected_top_items"] == ["AI Agents Reading List", "Missing AI Note"]
    assert result["expected_item_positions"] == {
        "AI Agents Reading List": 1,
        "Missing AI Note": None,
    }
    assert result["expected_top_items_found"] == ["AI Agents Reading List"]
    assert result["expected_top_items_missing"] == ["Missing AI Note"]
    assert result["expected_top_items_by_section"] == {
        "Recent memory": ["AI Agents Reading List", "Missing AI Note"],
        "Unpaid bills": ["Internet Bill Paid"],
    }
    assert result["expected_item_positions_by_section"] == {
        "Recent memory": {"AI Agents Reading List": 1, "Missing AI Note": None},
        "Unpaid bills": {"Internet Bill Paid": 1},
    }
    assert result["section_top_items_found"] == {
        "Recent memory": ["AI Agents Reading List"],
        "Unpaid bills": ["Internet Bill Paid"],
    }
    assert result["section_top_items_missing"] == {
        "Recent memory": ["Missing AI Note"],
        "Unpaid bills": [],
    }
    assert result["section_item_ranking_summary"] == (
        "2/3 expected section item(s) in first 3"
    )
    assert result["expected_absent_items"] == ["Internet Bill Paid"]
    assert result["unexpected_absent_item_hits"] == ["Internet Bill Paid"]
    assert result["item_ranking_summary"] == (
        "1/2 expected top item(s) in first 5; 1 unexpected absent item hit(s)"
    )


def test_build_eval_result_includes_retrieval_metadata_and_vector_annotations() -> None:
    result = build_eval_result(
        run_id="run-1",
        run_label=None,
        timestamp="2026-06-18T00:00:00+00:00",
        base_url="http://127.0.0.1:8000",
        mode="context_preview",
        question=make_question(),
        retrieval_mode="hybrid",
        memory_top_k=8,
        min_vector_score=0.25,
        preview={
            "include_context": True,
            "context_sections": ["Recent memory"],
            "context": (
                "Recent memory:\n"
                "- AI Notes (note) [vector_score=0.500]: Agents\n"
                "- WorldLens (note) [vector_score=0.300]: Camera"
            ),
        },
    )

    assert result["retrieval_mode"] == "hybrid"
    assert result["memory_top_k"] == 8
    assert result["min_vector_score"] == 0.25
    assert result["vector_score_annotations_present"] is True
    assert result["vector_score_count"] == 2


def test_hybrid_ask_run_warns_and_keeps_ask_payload_unchanged(
    tmp_path,
    monkeypatch,
    capsys,
) -> None:
    questions_file = tmp_path / "questions.json"
    questions_file.write_text(
        json.dumps(
            [
                {
                    "id": "saved_ai",
                    "question": "What did I save about AI?",
                    "intent": "memory_recall",
                    "expected_context_sections": ["Recent memory"],
                    "notes": "Hybrid smoke test.",
                }
            ]
        ),
        encoding="utf-8",
    )
    calls: list[tuple[str, dict]] = []

    def fake_post_json(base_url: str, path: str, payload: dict) -> dict:
        calls.append((path, payload))
        if path == "/ask/context-preview":
            return {
                "include_context": True,
                "context_sections": ["Recent memory"],
                "context": "Recent memory:\n- AI Notes [vector_score=0.500]",
            }
        return {"answer": "Mock answer"}

    monkeypatch.setattr(ask_eval, "post_json", fake_post_json)
    monkeypatch.setattr(
        sys,
        "argv",
        [
            "run_ask_eval.py",
            "--questions-file",
            str(questions_file),
            "--ask",
            "--retrieval-mode",
            "hybrid",
            "--memory-top-k",
            "8",
            "--min-vector-score",
            "0.25",
        ],
    )

    assert ask_eval.main() == 0
    output = capsys.readouterr().out
    assert "Hybrid retrieval applies only to context_preview; /ask remains keyword-only." in output
    assert calls[0] == (
        "/ask/context-preview",
        {
            "question": "What did I save about AI?",
            "include_context": True,
            "retrieval_mode": "hybrid",
            "memory_top_k": 8,
            "min_vector_score": 0.25,
        },
    )
    assert calls[1] == (
        "/ask",
        {
            "question": "What did I save about AI?",
            "include_context": True,
        },
    )


def make_result(question_id: str = "saved_ai") -> dict:
    return build_eval_result(
        run_id="run-1",
        run_label=None,
        timestamp="2026-06-17T00:00:00+00:00",
        base_url="http://127.0.0.1:8000",
        mode="ask",
        question=make_question(question_id=question_id),
        preview={
            "include_context": True,
            "context_sections": ["Today", "Recent memory"],
            "context": "Today:\n- 2026-06-17\n\nRecent memory:\n- AI notes",
        },
        answer="Mock answer",
    )


def make_question(question_id: str = "saved_ai") -> AskEvalQuestion:
    return AskEvalQuestion(
        id=question_id,
        question="What did I save about AI?",
        intent="memory_recall",
        expected_context_sections=["Recent memory"],
        notes="Should prioritize AI memory.",
    )


def make_summary_result(**overrides) -> dict:
    result = {
        "error": None,
        "missing_expected_sections": [],
        "empty_expected_sections": [],
        "expected_top_items_by_section": {},
        "section_top_items_missing": {},
        "expected_top_items": [],
        "expected_top_items_missing": [],
        "unexpected_absent_item_hits": [],
    }
    result.update(overrides)
    return result
