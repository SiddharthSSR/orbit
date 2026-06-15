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

The current backend should be treated as the system of record for structured memory types. Todos and bills are SQLite-backed; memory items, projects, and mood logs are still early in-memory endpoints.

Future agent tools should call explicit backend endpoints rather than reaching into storage directly. This keeps automation behavior auditable and testable.

## Safety Notes

- Do not add authentication until the app has a clearer account and storage model.
- Do not perform payment actions automatically.
- Keep Spotify integration opt-in and scoped to playlist creation.
- Make all AI-generated plans editable before saving.
