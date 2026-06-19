import re

from app.models.chat import SuggestedActionDTO


MAX_SUGGESTED_ACTIONS = 2
SUBTITLE_MAX_LENGTH = 80
MEMORY_TEXT_MAX_LENGTH = 240
MEMORY_TITLE_MAX_LENGTH = 60
TODO_TITLE_MAX_LENGTH = 120


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
        memory_text = _extract_memory_text(question_text, answer)
        candidates.append(
            SuggestedActionDTO(
                id="save-memory",
                type="save_memory",
                title="Save to memory",
                subtitle="Keep this detail in Orbit memory",
                payload={
                    "memory_text": memory_text,
                    "memory_title": _memory_title(memory_text),
                },
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
        todo_title = _extract_todo_title(question_text, answer)
        candidates.append(
            SuggestedActionDTO(
                id="create-todo",
                type="create_todo",
                title="Create a todo",
                subtitle=_truncate(todo_title),
                payload={"draft_title": todo_title},
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
            r"\b(remember (?:that|this)|"
            r"(?:save|store) (?:this|that|to memory|in memory)|"
            r"note that|make (?:a )?note)\b",
            question,
        )
    )


def _asks_for_task(question: str) -> bool:
    return bool(
        re.search(
            r"\b(todo|to-do|task|follow[ -]up|remind me to|reminder)\b",
            question,
        )
    )


def _extract_memory_text(question: str, answer: str) -> str:
    patterns = (
        r"^(?:(?:please|can you|could you|would you)\s+)*"
        r"remember(?:\s+(?:that|this))?\s*(?P<content>.*)$",
        r"^(?:(?:please|can you|could you|would you)\s+)*"
        r"(?:save|store)(?:\s+(?:this|that))?"
        r"(?:\s+(?:to|in)\s+(?:(?:my|orbit)\s+)?memory)?"
        r"\s*(?P<content>.*)$",
        r"^(?:(?:please|can you|could you|would you)\s+)*note\s+that\s+(?P<content>.*)$",
        r"^(?:(?:please|can you|could you|would you)\s+)*"
        r"make\s+(?:a\s+)?note(?:\s+(?:that|of))?\s*(?P<content>.*)$",
    )
    extracted = _extract_with_patterns(question, patterns, MEMORY_TEXT_MAX_LENGTH)
    if extracted and not _is_generic_reference(extracted):
        return extracted

    answer_fallback = _clean_payload_text(answer, MEMORY_TEXT_MAX_LENGTH)
    if answer_fallback:
        return answer_fallback

    return _clean_payload_text(question, MEMORY_TEXT_MAX_LENGTH) or "Saved from Ask"


def _memory_title(memory_text: str) -> str:
    title_source = re.sub(
        r"^i\s+(?:like|love|prefer|enjoy|want|need|have)\s+",
        "",
        memory_text,
        flags=re.IGNORECASE,
    )
    words = title_source.split()
    title = " ".join(words[:8])
    return _capitalize_lightly(_truncate_to(title, MEMORY_TITLE_MAX_LENGTH))


def _extract_todo_title(question: str, answer: str) -> str:
    patterns = (
        r"^(?:(?:please|can you|could you|would you)\s+)*"
        r"(?:add|create|make)\s+(?:a\s+)?(?:todo|to-do|task)"
        r"(?:\s+(?:to|for|about))?\s*(?P<content>.*)$",
        r"^(?:(?:please|can you|could you|would you)\s+)*remind\s+me\s+to\s+(?P<content>.*)$",
        r"^(?:(?:please|can you|could you|would you)\s+)*"
        r"(?:set|create)\s+(?:a\s+)?reminder\s+to\s+(?P<content>.*)$",
        r"^(?:todo|to-do|task)\s*[:,-]\s*(?P<content>.*)$",
    )
    extracted = _extract_with_patterns(question, patterns, TODO_TITLE_MAX_LENGTH)
    if not extracted or _is_generic_reference(extracted):
        next_step = re.search(r"(?im)^\s*next step:\s*(?P<content>.+)$", answer)
        if next_step:
            extracted = _clean_payload_text(
                next_step.group("content"),
                TODO_TITLE_MAX_LENGTH,
            )
    if not extracted or _is_generic_reference(extracted):
        extracted = _clean_payload_text(question, TODO_TITLE_MAX_LENGTH)
    return _capitalize_lightly(extracted or "Follow up in Orbit")


def _extract_with_patterns(
    value: str,
    patterns: tuple[str, ...],
    max_length: int,
) -> str | None:
    for pattern in patterns:
        match = re.match(pattern, value, flags=re.IGNORECASE)
        if match:
            return _clean_payload_text(match.group("content"), max_length)
    return None


def _clean_payload_text(value: str, max_length: int) -> str:
    normalized = " ".join(value.split()).strip()
    normalized = re.sub(r"^[\s:;,\-–—]+", "", normalized)
    normalized = normalized.strip(" \t\n\"'“”‘’")
    normalized = normalized.rstrip(" \t\n.!?;:\"'“”‘’")
    return _truncate_to(normalized, max_length)


def _is_generic_reference(value: str) -> bool:
    return value.lower().strip() in {
        "",
        "it",
        "something",
        "that",
        "this",
        "this to memory",
        "that to memory",
        "to memory",
    }


def _capitalize_lightly(value: str) -> str:
    if not value:
        return value
    return f"{value[0].upper()}{value[1:]}"


def _truncate_to(value: str, max_length: int) -> str:
    if len(value) <= max_length:
        return value
    return f"{value[: max_length - 1].rstrip()}…"


def _truncate(value: str) -> str:
    return _truncate_to(value, SUBTITLE_MAX_LENGTH)
