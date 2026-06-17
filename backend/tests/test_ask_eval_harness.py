import json

import pytest

from scripts.run_ask_eval import (
    AskEvalQuestion,
    build_eval_result,
    context_summary,
    find_item_positions,
    find_item_positions_by_section,
    load_eval_questions,
    parse_context_sections,
    section_top_item_matches,
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


def test_write_results_json_writes_list_of_result_objects(tmp_path) -> None:
    result = make_result()
    output_path = tmp_path / "results" / "latest.json"

    write_results([result], output_path, "json")

    saved = json.loads(output_path.read_text(encoding="utf-8"))
    assert isinstance(saved, list)
    assert saved[0]["run_id"] == "run-1"
    assert saved[0]["question_id"] == "saved_ai"
    assert saved[0]["returned_context_sections"] == ["Today", "Recent memory"]
    assert saved[0]["useful_context_sections"] == ["Today", "Recent memory"]


def test_write_results_jsonl_writes_one_object_per_line(tmp_path) -> None:
    first = make_result(question_id="saved_ai")
    second = make_result(question_id="focus_today")
    output_path = tmp_path / "results.jsonl"

    write_results([first, second], output_path, "jsonl")

    lines = output_path.read_text(encoding="utf-8").splitlines()
    assert len(lines) == 2
    assert json.loads(lines[0])["question_id"] == "saved_ai"
    assert json.loads(lines[1])["question_id"] == "focus_today"


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
