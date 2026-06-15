# Orbit

Orbit is a personal iPhone second brain app. The long-term product direction includes todos, bills and payment reminders, saved links, mood check-ins, project tracking, daily planning, AI chat over personal memory, and Spotify playlist creation.

This repository is a monorepo with:

- `ios/` - SwiftUI iOS app skeleton
- `backend/` - FastAPI backend
- `docs/` - product and engineering documentation

Authentication is intentionally not implemented yet.

## Backend Setup

Requirements:

- Python 3.9+

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
