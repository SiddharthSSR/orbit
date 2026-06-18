from app.services.suggested_actions import build_suggested_actions


def test_bills_answer_suggests_review_bills() -> None:
    actions = build_suggested_actions(
        question="What bills are coming up?",
        answer="Your overdue bill is due today.",
        context_sections=["Today", "Unpaid bills"],
    )

    assert [action.type for action in actions] == ["review_bills"]
    assert actions[0].title == "Review bills"


def test_remember_question_suggests_save_memory() -> None:
    actions = build_suggested_actions(
        question="Remember that I like quiet cafes",
        answer="I can help you keep track of that.",
        context_sections=[],
    )

    assert [action.type for action in actions] == ["save_memory"]


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
