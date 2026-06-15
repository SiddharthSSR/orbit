# Orbit Architecture

## Monorepo Layout

- `ios/Orbit` contains the SwiftUI app skeleton.
- `backend` contains the FastAPI service.
- `docs` contains product and engineering notes.

## Backend

The backend exposes a small FastAPI app with:

- `/health` for service health.
- SQLite-backed CRUD endpoints for `Todo`.
- CRUD-style create/list endpoints for early non-Todo domain objects.
- Pydantic models for `MemoryItem`, `Todo`, `Bill`, `Project`, and `MoodLog`.
- An in-memory repository still used for `MemoryItem`, `Bill`, `Project`, and `MoodLog`.
- CORS configured for common localhost development origins.

Todo is the first vertical slice with persistence. Its API has separate create, read, and update schemas, and stores records in SQLite by default at `backend/orbit.db`. The other domain objects remain in-memory until their slices are ready.

## iOS

The iOS app is a SwiftUI shell organized into:

- `App` for app entry and tab wiring.
- `Models` for local domain models and sample data.
- `Screens` for Today, Inbox, Ask, Projects, and Bills.
- `Components` for reusable UI pieces.

The initial UI uses static sample data. Networking and local persistence should be added behind services once the backend API stabilizes.

## Future Persistence

Recommended next steps:

- Expand SQLite or Postgres persistence beyond Todo once each slice is ready.
- Add repository interfaces where they reduce duplication.
- Add API clients in the iOS app.
- Introduce local caching after the API contract is stable.
