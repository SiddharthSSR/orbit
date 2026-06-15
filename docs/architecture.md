# Orbit Architecture

## Monorepo Layout

- `ios/Orbit` contains the SwiftUI app skeleton.
- `backend` contains the FastAPI service.
- `docs` contains product and engineering notes.

## Backend

The backend exposes a small FastAPI app with:

- `/health` for service health.
- CRUD-style create/list endpoints for early domain objects.
- Pydantic models for `MemoryItem`, `Todo`, `Bill`, `Project`, and `MoodLog`.
- An in-memory repository used as the first persistence boundary.

The repository is intentionally isolated behind `InMemoryRepository` so a database-backed implementation can replace it without rewriting route handlers.

## iOS

The iOS app is a SwiftUI shell organized into:

- `App` for app entry and tab wiring.
- `Models` for local domain models and sample data.
- `Screens` for Today, Inbox, Ask, Projects, and Bills.
- `Components` for reusable UI pieces.

The initial UI uses static sample data. Networking and local persistence should be added behind services once the backend API stabilizes.

## Future Persistence

Recommended next steps:

- Add SQLite or Postgres to the backend.
- Add repository interfaces and persistence tests.
- Add API clients in the iOS app.
- Introduce local caching after the API contract is stable.

