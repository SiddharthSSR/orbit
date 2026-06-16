from app.services.relevance import score_text, tokenize_query


def test_tokenize_query_removes_stopwords_and_short_tokens() -> None:
    tokens = tokenize_query("What did I save about AI and WorldLens?")

    assert tokens == {"save", "worldlens"}


def test_score_text_scores_relevant_overlap_case_insensitively() -> None:
    query_tokens = tokenize_query("Any bills related to Furlenco?")

    assert score_text(query_tokens, "Furlenco Rent", "Monthly furniture rental") > 0
    assert score_text(query_tokens, "Credit card", "Groceries and fuel") == 0
