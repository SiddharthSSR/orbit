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

That address lets the simulator reach the FastAPI server running on your Mac. The Today tab combines live Todos, Bills, Memory, and the latest Mood check-in into a dashboard. It also lets you submit a simple Mood check-in. The Bills tab uses the live Bill API to load, create, mark paid/unpaid, and delete bills. The Inbox tab uses the live Memory API to load, capture, archive, and delete memory items. The Projects tab uses the live Project API to load, create, update status, archive, filter, and delete projects. The Ask tab uses the backend `/ask` API with the deterministic mock AI provider and includes a lightweight context inspection panel for previewing backend context.

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

Memory embedding development endpoints:

- `POST /memory/embeddings/reindex`
- `POST /memory/embeddings/retry-failed`
- `GET /memory/embeddings/status`
- `GET /memory/search?query=AI&top_k=5&min_score=0`

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
- `POST /ask/context-preview`
- `GET /chat/sessions`
- `GET /chat/sessions/{session_id}/messages`

The Ask backend and iOS Ask tab currently use a deterministic mock AI provider. They store chat sessions/messages and build a bounded, date-aware plain-text context from open todos, unpaid bills, recent memory, latest moods, and active projects. Ask applies lightweight keyword relevance from the user's question so matching memory, projects, todos, and bills surface before the default ordering. Todos and bills are labeled as overdue, due today, due soon, or no due date where applicable; memory and project bodies are included only as short previews. `POST /ask/context-preview` is a backend development/debug helper that returns the context string and section names without calling the AI provider or saving chat messages.

Context preview defaults to the existing keyword behavior and optionally supports hybrid memory evaluation:

```bash
curl -X POST http://127.0.0.1:8000/ask/context-preview \
  -H 'Content-Type: application/json' \
  -d '{
    "question": "What did I save about AI?",
    "retrieval_mode": "hybrid",
    "memory_top_k": 5,
    "min_vector_score": 0.0
  }'
```

`retrieval_mode` is `keyword` or `hybrid` and defaults to `keyword`; `memory_top_k` accepts 1–20. Hybrid mode affects only the `Recent memory` section: current vector hits appear first with debug score annotations, followed by deduplicated keyword-only fallbacks. Missing, stale, failed, or temporarily unavailable embeddings degrade to keyword memory ordering. The production `/ask` route remains keyword-only; hybrid preview is an evaluation bridge before full Ask integration.

Orbit includes an embeddings/RAG foundation for memory items only. Embeddings are stored as JSON vectors in SQLite and searched with cosine similarity in Python; there is no external vector database. This retrieval path is development-only and is not connected to `/ask`, which continues to use keyword-ranked context. Orbit does not yet include production authentication/security for these development endpoints, streaming, or tool execution.

The default embedding provider is deterministic and local:

```bash
curl -X POST http://127.0.0.1:8000/memory/embeddings/reindex
curl --get http://127.0.0.1:8000/memory/search \
  --data-urlencode 'query=AI' \
  --data-urlencode 'top_k=5'
```

Memory embeddings are maintained automatically for API mutations: active items are indexed after creation, content changes refresh the configured provider's embedding, archiving removes all embeddings for the item, and deletion cleans embeddings before removing the memory row. Non-content updates reuse the existing content hash and do not create duplicate embeddings. Automatic indexing is best-effort: memory create/update still succeeds if provider construction or embedding generation fails, and the embedding row records `failed` status, the error, and the attempt time. Each attempt is durably marked `stale` before provider work and transitions to `indexed` or `failed`; search uses only current `indexed` rows.

Inspect embedding health and retry incomplete active items locally:

```bash
curl http://127.0.0.1:8000/memory/embeddings/status
curl -X POST http://127.0.0.1:8000/memory/embeddings/retry-failed
```

The status response reports indexed, failed, stale, and missing counts for the configured provider/model, plus failed item details. Retry processes failed, stale, missing, and hash-mismatched active items. `POST /memory/embeddings/reindex` remains available for full backfills and local repair; it skips provider work for current hashes and removes embeddings from archived items.

Search embeds the query and compares it only with current, non-archived embeddings for the active provider/model. Results must have `score > min_score`; the default `min_score=0` excludes zero-score results. Use a negative value for debugging when zero-score candidates are useful:

```bash
curl --get http://127.0.0.1:8000/memory/search \
  --data-urlencode 'query=AI' \
  --data-urlencode 'top_k=5' \
  --data-urlencode 'min_score=-1'
```

To opt into OpenAI embeddings locally, reuse the runtime API key and select the provider before starting the backend:

```bash
export ORBIT_EMBEDDING_PROVIDER=openai
export OPENAI_API_KEY=<your-openai-api-key>
export ORBIT_OPENAI_EMBEDDING_MODEL=text-embedding-3-small
```

The OpenAI embedding client is constructed only when embedding work is requested and `ORBIT_EMBEDDING_PROVIDER=openai`. During automatic memory mutations, missing credentials or provider failures are recorded without failing the memory response. Explicit search, reindex, and retry requests still return a configuration error when the configured provider cannot be constructed. Tests and CI remain mock-only and make no external embedding calls.

To enable the experimental OpenAI-backed provider locally, set environment variables before starting the backend:

```bash
export ORBIT_AI_PROVIDER=openai
export OPENAI_API_KEY=<your-openai-api-key>
export ORBIT_OPENAI_MODEL=gpt-4o-mini
export ORBIT_AI_TIMEOUT_SECONDS=30
```

If `ORBIT_AI_PROVIDER` is unset or set to `mock`, Orbit uses the deterministic mock provider. Tests and CI use the mock provider and must not call external AI services.

Run the manual Ask eval harness against a local backend:

```bash
cd backend
source .venv/bin/activate
alembic upgrade head
python scripts/seed_demo_data.py
python scripts/run_ask_eval.py
```

`seed_demo_data.py` is an explicit local-development helper; it is never run during app startup or deployment. It creates realistic Orbit, WorldLens, AI, Furlenco, mood, and fallback records using today's date. Re-running it skips records with the same demo title/name. Preview writes with:

```bash
python scripts/seed_demo_data.py --dry-run
```

By default, the eval harness only calls `POST /ask/context-preview`, prints returned context sections, and shows a truncated context preview. To also call `POST /ask` and print answers, run:

```bash
python scripts/run_ask_eval.py --ask
```

Save structured eval results locally:

```bash
python scripts/run_ask_eval.py --output eval-results/latest.json
python scripts/run_ask_eval.py --ask --output eval-results/openai-run.jsonl --format jsonl --run-label openai-smoke
```

Eval logs distinguish returned section headers from useful sections with real data, so sections containing only `- None` do not count as matched context. Selected eval questions also declare expected top/absent items and section-aware top items. Logs record case-insensitive global positions, top-five matches, positions within each expected section, top-three section matches, missing expected items, and unexpected absence-check hits. A compact run summary reports section matching, section-aware ranking, legacy global ranking, request errors, and unexpected absence hits. Section-aware ranking is preferred because it evaluates an item relative to the section where it belongs; global ranking remains informational. Scores do not affect the script exit status—only request errors do.

JSON output now uses the breaking shape `{"summary": {...}, "results": [...]}` instead of a top-level result list. JSONL remains one result per line for compatibility and appends a final `{"type": "summary", "summary": {...}}` line.

Ask mode uses whichever provider the running backend is configured with. It stays mock-only unless the backend process was started with `ORBIT_AI_PROVIDER=openai` and a valid `OPENAI_API_KEY`.

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
