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
uvicorn app.main:app --reload
```

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

## Run Backend And iOS Together

Start the backend first:

```bash
cd backend
source .venv/bin/activate
uvicorn app.main:app --reload
```

Then run the iOS app from Xcode using an iPhone simulator. The iOS app's Todo API client defaults to:

```text
http://127.0.0.1:8000
```

That address lets the simulator reach the FastAPI server running on your Mac. The Today tab uses the live Todo API to load, create, toggle, and delete todos. The Bills tab uses the live Bill API to load, create, mark paid/unpaid, and delete bills. The Inbox tab uses the live Memory API to load, capture, archive, and delete memory items.

## Backend API Notes

Todos, Bills, and Memory items are backed by SQLite and default to `backend/orbit.db`. Set `ORBIT_DATABASE_URL` to point the backend at another database URL for local experiments or tests.

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
