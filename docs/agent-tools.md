# Agent Tools

Orbit should eventually support personal automation and AI-assisted workflows. This document tracks intended tool surfaces without implementing them yet.

## Planned Tool Areas

- Memory search across notes, links, todos, bills, projects, and mood logs.
- Daily planning suggestions from open todos, calendar context, and recurring obligations.
- Bill reminder generation.
- Project status summaries.
- Saved article summarization.
- Spotify playlist creation from mood or activity context.

## Initial Backend Boundary

The current backend should be treated as the system of record for structured memory types. Todos, bills, memory items, mood check-ins, and projects are SQLite-backed.

The Ask backend foundation now stores chat sessions and messages, builds a small text context from existing Orbit records, and calls a deterministic mock AI provider by default. A real OpenAI provider can be enabled locally through environment variables, but tests and CI must keep using mock/fake providers. Orbit does not perform embeddings, vector search, streaming, semantic retrieval, or tool execution yet.

Memory persistence stores user-supplied content and tags only. It does not summarize articles, fetch link metadata, or perform retrieval-augmented chat yet.

Mood persistence stores user-supplied check-ins only. It does not generate coaching, playlists, or planning personalization yet.

Project persistence stores user-supplied status, area, and tags only. It does not generate AI project mentoring, summaries, or next-step recommendations yet.

Future agent tools should call explicit backend endpoints rather than reaching into storage directly. This keeps automation behavior auditable and testable.

## Safety Notes

- Do not add authentication until the app has a clearer account and storage model.
- Do not perform payment actions automatically.
- Keep Spotify integration opt-in and scoped to playlist creation.
- Make all AI-generated plans editable before saving.
