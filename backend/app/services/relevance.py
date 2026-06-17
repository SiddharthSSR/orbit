import re


STOPWORDS = {
    "about",
    "after",
    "all",
    "and",
    "any",
    "are",
    "can",
    "did",
    "for",
    "from",
    "going",
    "has",
    "have",
    "how",
    "into",
    "should",
    "that",
    "the",
    "this",
    "was",
    "what",
    "when",
    "with",
    "you",
}

MEANINGFUL_SHORT_TOKENS = {"ai", "ui", "ux", "ml", "llm", "ios"}


def tokenize_query(text: str) -> set[str]:
    tokens = re.findall(r"[a-z0-9]+", text.lower())
    return {
        token
        for token in tokens
        if token not in STOPWORDS and (len(token) >= 3 or token in MEANINGFUL_SHORT_TOKENS)
    }


def score_text(query_tokens: set[str], *fields: str | None) -> int:
    if not query_tokens:
        return 0

    score = 0
    combined_text = " ".join(field.lower() for field in fields if field)
    field_tokens = set(re.findall(r"[a-z0-9]+", combined_text))

    for token in query_tokens:
        if token in field_tokens:
            score += 3
        elif token in combined_text:
            score += 1

    return score
