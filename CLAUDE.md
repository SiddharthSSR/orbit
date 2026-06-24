# Orbit

Personal iPhone "second brain" app. Monorepo:
- `ios/` — SwiftUI iOS app (`ios/Orbit/Orbit.xcodeproj`)
- `backend/` — FastAPI backend (Alembic migrations, SQLAlchemy)
- `docs/` — product & engineering docs; project health and current MVP block live in `docs/checkpoints/`

Auth is intentionally not implemented yet.

## iOS

Xcode project: `ios/Orbit/Orbit.xcodeproj` · Scheme: `Orbit` · Targets: `Orbit`, `OrbitTests`, `OrbitUITests`.

```bash
# Build (run from ios/Orbit)
xcodebuild build -scheme Orbit -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
# Unit tests
xcodebuild test -scheme Orbit -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:OrbitTests
# UI smoke tests
./scripts/run_ios_ui_smoke.sh
```

- Prefer running a single target/test over the full suite for speed.
- iPhone 16 Pro simulator is the default destination (available locally).

## Backend

```bash
cd backend
source .venv/bin/activate
alembic upgrade head        # set up / migrate local DB (the normal startup path)
uvicorn app.main:app --reload
pytest                      # tests live in backend/tests
```

- Schema changes go through Alembic migrations, not `Base.metadata.create_all()` (that's test-only).
- Python 3.10+.

## Conventions & gotchas
- Check `docs/checkpoints/` for the current MVP block and guardrails before starting feature work.
- Some features are intentionally preview-only (e.g. `review_bills`) — verify a capability is wired end-to-end before assuming it's live.
