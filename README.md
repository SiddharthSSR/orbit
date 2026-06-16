# Orbit

Orbit is a personal iPhone second brain app. The long-term product direction includes todos, bills and payment reminders, saved links, mood check-ins, project tracking, daily planning, AI chat over personal memory, and Spotify playlist creation.

This repository is a monorepo with:

- `ios/` - SwiftUI iOS app skeleton
- `backend/` - FastAPI backend
- `docs/` - product and engineering documentation

Authentication is intentionally not implemented yet.

## Backend Setup

Requirements:

- Python 3.10+

Run the API locally:

```bash
cd backend
python -m venv .venv
source .venv/bin/activate
pip install ".[dev]"
alembic upgrade head
uvicorn app.main:app --reload
```

The backend uses Alembic migrations for local database schema setup and evolution. `Base.metadata.create_all()` is still used in isolated tests, but it is not the normal app startup path.

For a fresh local database, run:

```bash
cd backend
source .venv/bin/activate
alembic upgrade head
```

If you have an old disposable `backend/orbit.db` created before Alembic, delete it and run `alembic upgrade head` again. If you need to keep an existing local database whose schema already matches the first migration, use `alembic stamp head` instead of recreating it.

Health check:

```bash
curl http://127.0.0.1:8000/health
```

Run tests:

```bash
cd backend
pytest
```

## iOS Setup

Requirements:

- Xcode 16+
- iOS 18 SDK recommended

Open the Xcode project:

```bash
open ios/Orbit/Orbit.xcodeproj
```

The iOS app currently contains a tabbed SwiftUI shell with Today, Inbox, Ask, Projects, and Bills screens.

Run iOS unit tests:

```bash
xcodebuild test -project ios/Orbit/Orbit.xcodeproj -scheme Orbit -destination 'platform=iOS Simulator,name=iPhone 17'
```

## Continuous Integration

GitHub Actions runs lightweight validation on pushes to `main` and pull requests:

- backend dependency install with `uv`, `pytest`, and an Alembic `upgrade head` smoke test against temporary SQLite
- iOS `xcodebuild test` for `OrbitTests`
- generic iOS Debug build with code signing disabled

## Run Backend And iOS Together

Start the backend first:

```bash
cd backend
source .venv/bin/activate
alembic upgrade head
uvicorn app.main:app --reload
```

Then run the iOS app from Xcode using an iPhone simulator. The iOS app's Todo API client defaults to:

```text
http://127.0.0.1:8000
```

That address lets the simulator reach the FastAPI server running on your Mac. The Today tab combines live Todos, Bills, Memory, and the latest Mood check-in into a dashboard. It also lets you submit a simple Mood check-in. The Bills tab uses the live Bill API to load, create, mark paid/unpaid, and delete bills. The Inbox tab uses the live Memory API to load, capture, archive, and delete memory items. The Projects tab uses the live Project API to load, create, update status, archive, filter, and delete projects. The Ask tab uses the backend `/ask` API with the deterministic mock AI provider.

## Backend API Notes

Todos, Bills, Memory items, Mood check-ins, Projects, and chat sessions/messages are backed by SQLite and default to `backend/orbit.db`. Set `ORBIT_DATABASE_URL` to point the backend at another database URL for local experiments or tests.

Todo CRUD endpoints:

- `POST /todos`
- `GET /todos`
- `GET /todos/{todo_id}`
- `PATCH /todos/{todo_id}`
- `DELETE /todos/{todo_id}`

Bill CRUD endpoints:

- `POST /bills`
- `GET /bills`
- `GET /bills/{bill_id}`
- `PATCH /bills/{bill_id}`
- `DELETE /bills/{bill_id}`

Memory CRUD endpoints:

- `POST /memory`
- `GET /memory`
- `GET /memory?include_archived=true`
- `GET /memory?kind=link`
- `GET /memory?tag=inbox`
- `GET /memory/{memory_id}`
- `PATCH /memory/{memory_id}`
- `DELETE /memory/{memory_id}`

Mood CRUD endpoints:

- `POST /moods`
- `GET /moods`
- `GET /moods?limit=30`
- `GET /moods?from_date=2026-06-01&to_date=2026-06-30`
- `GET /moods/{mood_id}`
- `PATCH /moods/{mood_id}`
- `DELETE /moods/{mood_id}`

Project CRUD endpoints:

- `POST /projects`
- `GET /projects`
- `GET /projects?include_archived=true`
- `GET /projects?status=active`
- `GET /projects?area=orbit`
- `GET /projects?tag=app`
- `GET /projects/{project_id}`
- `PATCH /projects/{project_id}`
- `DELETE /projects/{project_id}`

Ask/chat foundation endpoints:

- `POST /ask`
- `GET /chat/sessions`
- `GET /chat/sessions/{session_id}/messages`

The Ask backend and iOS Ask tab currently use a deterministic mock AI provider. They store chat sessions/messages and build a small plain-text context from open todos, unpaid bills, recent memory, latest moods, and active projects. Orbit does not call a real LLM yet, and it does not include embeddings, streaming, semantic search, or tool execution.

To enable the experimental OpenAI-backed provider locally, set environment variables before starting the backend:

```bash
export ORBIT_AI_PROVIDER=openai
export OPENAI_API_KEY=<your-openai-api-key>
export ORBIT_OPENAI_MODEL=gpt-4o-mini
export ORBIT_AI_TIMEOUT_SECONDS=30
```

If `ORBIT_AI_PROVIDER` is unset or set to `mock`, Orbit uses the deterministic mock provider. Tests and CI use the mock provider and must not call external AI services.

The backend enables CORS for common localhost development origins, including `localhost:3000`, `localhost:5173`, `127.0.0.1:3000`, and `127.0.0.1:5173`.

## Repository Structure

```text
.
├── backend/
│   ├── app/
│   │   ├── api/
│   │   ├── core/
│   │   ├── models/
│   │   └── repositories/
│   └── tests/
├── docs/
└── ios/
    └── Orbit/
```
