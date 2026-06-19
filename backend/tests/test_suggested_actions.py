from app.services.suggested_actions import build_suggested_actions


def test_bills_answer_suggests_review_bills() -> None:
    actions = build_suggested_actions(
        question="What bills are coming up?",
        answer="Your overdue bill is due today.",
        context_sections=["Today", "Unpaid bills"],
    )

    assert [action.type for action in actions] == ["review_bills"]
    assert actions[0].title == "Review bills"
    assert actions[0].payload is None


def test_remember_question_suggests_save_memory() -> None:
    actions = build_suggested_actions(
        question="Remember that I like quiet cafes with plants",
        answer="I can help you keep track of that.",
        context_sections=[],
    )

    assert [action.type for action in actions] == ["save_memory"]
    assert actions[0].payload == {
        "memory_text": "I like quiet cafes with plants",
        "memory_title": "Quiet cafes with plants",
    }


def test_save_this_uses_answer_as_safe_memory_fallback() -> None:
    actions = build_suggested_actions(
        question="Save this",
        answer='"The launch checklist is ready."',
        context_sections=[],
    )

    assert actions[0].type == "save_memory"
    assert actions[0].payload == {
        "memory_text": "The launch checklist is ready",
        "memory_title": "The launch checklist is ready",
    }


def test_save_memory_trims_wrapping_quotes_and_terminal_punctuation() -> None:
    actions = build_suggested_actions(
        question='Remember that "I prefer window seats."',
        answer="Noted.",
        context_sections=[],
    )

    assert actions[0].payload == {
        "memory_text": "I prefer window seats",
        "memory_title": "Window seats",
    }


def test_add_todo_extracts_clean_actionable_title() -> None:
    actions = build_suggested_actions(
        question="add a todo to call the dentist tomorrow",
        answer="I can help with that.",
        context_sections=[],
    )

    assert [action.type for action in actions] == ["create_todo"]
    assert actions[0].payload == {"draft_title": "Call the dentist tomorrow"}
    assert actions[0].subtitle == "Call the dentist tomorrow"


def test_remind_me_to_extracts_todo_title_and_trims_quotes() -> None:
    actions = build_suggested_actions(
        question='Remind me to "send the proposal Friday!"',
        answer="I can help with that.",
        context_sections=[],
    )

    assert [action.type for action in actions] == ["create_todo"]
    assert actions[0].payload == {"draft_title": "Send the proposal Friday"}


def test_task_question_suggests_create_todo_with_bounded_subtitle() -> None:
    actions = build_suggested_actions(
        question="Create a task to follow up on the quarterly planning discussion " + "soon " * 20,
        answer="You can follow up next week.",
        context_sections=[],
    )

    assert [action.type for action in actions] == ["create_todo"]
    assert actions[0].subtitle is not None
    assert len(actions[0].subtitle) == 80
    assert actions[0].subtitle.endswith("…")
    assert actions[0].payload is not None
    assert len(actions[0].payload["draft_title"]) == 120


def test_actions_are_unique_and_limited_to_two() -> None:
    actions = build_suggested_actions(
        question="Remember this and create a follow-up task about the bills",
        answer="An overdue bill needs attention.\nNext step: review it.",
        context_sections=["Unpaid bills"],
    )

    assert len(actions) == 2
    assert len({action.type for action in actions}) == 2
    assert [action.type for action in actions] == ["save_memory", "review_bills"]


def test_no_clear_action_returns_empty_list() -> None:
    actions = build_suggested_actions(
        question="How is Orbit going?",
        answer="Orbit is progressing steadily.",
        context_sections=["Active projects"],
    )

    assert actions == []
