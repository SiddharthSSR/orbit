import json
from pathlib import Path
from typing import Any

import pytest

from app.services.suggested_actions import build_suggested_actions


FIXTURE_PATH = (
    Path(__file__).parent
    / "fixtures"
    / "suggested_action_extraction_cases.json"
)
EXTRACTION_CASES: list[dict[str, Any]] = json.loads(
    FIXTURE_PATH.read_text(encoding="utf-8")
)


@pytest.mark.parametrize(
    "case",
    EXTRACTION_CASES,
    ids=[case["name"] for case in EXTRACTION_CASES],
)
def test_suggested_action_extraction_fixture(case: dict[str, Any]) -> None:
    actions = build_suggested_actions(
        question=case["user_message"],
        answer=case["assistant_answer"],
        context_sections=case["context_sections"],
    )

    expected_action_type = case["expected_action_type"]
    if expected_action_type is None:
        assert actions == []
        return

    assert [action.type for action in actions] == [expected_action_type]
    assert actions[0].payload == case["expected_payload"]
