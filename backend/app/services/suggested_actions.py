import re

from app.models.chat import SuggestedActionDTO


MAX_SUGGESTED_ACTIONS = 2
SUBTITLE_MAX_LENGTH = 80


def build_suggested_actions(
    *,
    question: str,
    answer: str,
    context_sections: list[str],
) -> list[SuggestedActionDTO]:
    question_text = " ".join(question.split())
    question_lower = question_text.lower()
    answer_lower = answer.lower()
    candidates: list[SuggestedActionDTO] = []

    if _asks_to_save(question_lower):
        candidates.append(
            SuggestedActionDTO(
                id="save-memory",
                type="save_memory",
                title="Save to memory",
                subtitle="Keep this detail in Orbit memory",
            )
        )

    mentions_bill = "bill" in answer_lower or "Unpaid bills" in context_sections
    mentions_due_status = any(
        phrase in answer_lower
        for phrase in ("overdue", "due today", "due soon", "coming up")
    )
    if mentions_bill and mentions_due_status:
        candidates.append(
            SuggestedActionDTO(
                id="review-bills",
                type="review_bills",
                title="Review bills",
                subtitle="Check overdue and upcoming bills",
            )
        )

    if "next step:" in answer_lower or _asks_for_task(question_lower):
        candidates.append(
            SuggestedActionDTO(
                id="create-todo",
                type="create_todo",
                title="Create a todo",
                subtitle=_truncate(f"Follow up: {question_text}"),
            )
        )

    unique_actions: list[SuggestedActionDTO] = []
    seen_types: set[str] = set()
    for action in candidates:
        if action.type in seen_types:
            continue
        seen_types.add(action.type)
        unique_actions.append(action)
        if len(unique_actions) == MAX_SUGGESTED_ACTIONS:
            break
    return unique_actions


def _asks_to_save(question: str) -> bool:
    return bool(
        re.search(
            r"\b(remember (?:that|this)|save (?:this|that)|note that|make (?:a )?note)\b",
            question,
        )
    )


def _asks_for_task(question: str) -> bool:
    return any(term in question for term in ("todo", "to-do", "task", "follow up", "follow-up"))


def _truncate(value: str) -> str:
    if len(value) <= SUBTITLE_MAX_LENGTH:
        return value
    return f"{value[: SUBTITLE_MAX_LENGTH - 1].rstrip()}…"
