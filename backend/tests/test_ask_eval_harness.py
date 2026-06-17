import json

import pytest

from scripts.run_ask_eval import load_eval_questions


def test_ask_eval_questions_have_expected_shape() -> None:
    questions = load_eval_questions()

    assert 8 <= len(questions) <= 12
    ids = {question.id for question in questions}
    assert len(ids) == len(questions)
    assert "focus_today" in ids
    assert "saved_ai" in ids
    assert "furlenco_bill" in ids

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
