# Orbit Architecture

## Monorepo Layout

- `ios/Orbit` contains the SwiftUI app skeleton.
- `backend` contains the FastAPI service.
- `docs` contains product and engineering notes.

## Backend

The backend exposes a small FastAPI app with:

- `/health` for service health.
- SQLite-backed CRUD endpoints for `Todo`, `Bill`, `Memory`, `Mood`, and `Project`.
- SQLite-backed chat sessions/messages plus a mock-provider `/ask` endpoint.
- Pydantic models for `Memory`, `Todo`, `Bill`, `Mood`, and `Project`.
- CORS configured for common localhost development origins.

Todo, Bill, Memory, Mood, Project, and chat records now have persistence. Their APIs have separate create, read, and update schemas where useful, and store records in SQLite by default at `backend/orbit.db`.

The Ask backend foundation builds a bounded, date-aware plain-text context from open todos, unpaid bills, recent memory, latest moods, and active projects. It uses lightweight keyword relevance from the user's question to surface matching records before falling back to default recent/date-aware ordering. Todos and bills are prioritized around overdue, due-today, and upcoming dates. Memory and project content is represented as short previews with tags and source URLs where available. It uses a deterministic mock AI provider by default. A real OpenAI provider can be enabled locally with `ORBIT_AI_PROVIDER=openai` and `OPENAI_API_KEY`, with `ORBIT_OPENAI_MODEL` and `ORBIT_AI_TIMEOUT_SECONDS` available for configuration. Tests and CI use the mock provider. There is no streaming, embeddings, vector search, semantic search, or tool execution yet.

Schema changes are managed with Alembic migrations. App startup does not create tables as the normal schema evolution path; local development should run `alembic upgrade head` before starting `uvicorn`. Tests still use isolated in-memory SQLite tables for speed and independence.

## iOS

The iOS app is a SwiftUI shell organized into:

- `App` for app entry and tab wiring.
- `Models` for API DTOs and request payloads.
- `Screens` for Today, Inbox, Ask, Projects, and Bills.
- `Components` for reusable UI pieces.

The Today, Inbox, Bills, Projects, and Ask tabs use live backend APIs. Today now includes a live Mood check-in section backed by the Mood API and shows the latest check-in in the dashboard. Ask uses the backend `/ask` endpoint; by default that endpoint uses the deterministic mock provider, while local development can opt into the OpenAI provider with environment variables. There is no streaming, embeddings, or tool execution yet.

## Future Persistence

Recommended next steps:

- Expand SQLite or Postgres persistence as the next slices need richer relational behavior.
- Add repository interfaces where they reduce duplication.
- Add API clients in the iOS app.
- Introduce local caching after the API contract is stable.
