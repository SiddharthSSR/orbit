# Orbit Architecture

## Monorepo Layout

- `ios/Orbit` contains the SwiftUI app skeleton.
- `backend` contains the FastAPI service.
- `docs` contains product and engineering notes.

## Backend

The backend exposes a small FastAPI app with:

- `/health` for service health.
- SQLite-backed CRUD endpoints for `Todo`, `Bill`, and `Memory`.
- CRUD-style create/list endpoints for early non-persistent domain objects.
- Pydantic models for `Memory`, `Todo`, `Bill`, `Project`, and `MoodLog`.
- An in-memory repository still used for `Project` and `MoodLog`.
- CORS configured for common localhost development origins.

Todo, Bill, and Memory now have persistence. Their APIs have separate create, read, and update schemas, and store records in SQLite by default at `backend/orbit.db`. Projects and mood logs remain in-memory until their slices are ready.

## iOS

The iOS app is a SwiftUI shell organized into:

- `App` for app entry and tab wiring.
- `Models` for local domain models and sample data.
- `Screens` for Today, Inbox, Ask, Projects, and Bills.
- `Components` for reusable UI pieces.

The Today and Bills tabs use live backend APIs. Inbox, Ask, and Projects still use placeholders or static sample data.

## Future Persistence

Recommended next steps:

- Expand SQLite or Postgres persistence beyond Todo, Bill, and Memory once each slice is ready.
- Add repository interfaces where they reduce duplication.
- Add API clients in the iOS app.
- Introduce local caching after the API contract is stable.
