from app.services.relevance import score_text, tokenize_query


def test_tokenize_query_keeps_meaningful_ai_token() -> None:
    tokens = tokenize_query("What did I save about AI and WorldLens?")

    assert tokens == {"ai", "save", "worldlens"}


def test_tokenize_query_keeps_meaningful_product_tokens_case_insensitively() -> None:
    assert tokenize_query("UI UX ideas for iOS") == {"ui", "ux", "ideas", "ios"}


def test_tokenize_query_still_ignores_generic_short_words() -> None:
    assert tokenize_query("I am up to do it on an app") == {"app"}


def test_score_text_scores_relevant_overlap_case_insensitively() -> None:
    query_tokens = tokenize_query("Any bills related to Furlenco?")

    assert score_text(query_tokens, "Furlenco Rent", "Monthly furniture rental") > 0
    assert score_text(query_tokens, "Credit card", "Groceries and fuel") == 0
