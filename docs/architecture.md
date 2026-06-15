# Orbit Architecture

## Monorepo Layout

- `ios/Orbit` contains the SwiftUI app skeleton.
- `backend` contains the FastAPI service.
- `docs` contains product and engineering notes.

## Backend

The backend exposes a small FastAPI app with:

- `/health` for service health.
- SQLite-backed CRUD endpoints for `Todo`, `Bill`, `Memory`, and `Mood`.
- CRUD-style create/list endpoints for early non-persistent domain objects.
- Pydantic models for `Memory`, `Todo`, `Bill`, `Mood`, and `Project`.
- An in-memory repository still used for `Project`.
- CORS configured for common localhost development origins.

Todo, Bill, Memory, and Mood now have persistence. Their APIs have separate create, read, and update schemas, and store records in SQLite by default at `backend/orbit.db`. Projects remain in-memory until their slice is ready.

## iOS

The iOS app is a SwiftUI shell organized into:

- `App` for app entry and tab wiring.
- `Models` for local domain models and sample data.
- `Screens` for Today, Inbox, Ask, Projects, and Bills.
- `Components` for reusable UI pieces.

The Today, Inbox, and Bills tabs use live backend APIs. Today now includes a live Mood check-in section backed by the Mood API and shows the latest check-in in the dashboard. Ask and Projects still use placeholders or static sample data.

## Future Persistence

Recommended next steps:

- Expand SQLite or Postgres persistence beyond Todo, Bill, Memory, and Mood once each slice is ready.
- Add repository interfaces where they reduce duplication.
- Add API clients in the iOS app.
- Introduce local caching after the API contract is stable.
