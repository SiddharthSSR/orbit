# Orbit

Orbit is a personal iPhone second brain app. The long-term product direction includes todos, bills and payment reminders, saved links, mood check-ins, project tracking, daily planning, AI chat over personal memory, and Spotify playlist creation.

This repository is a monorepo with:

- `ios/` - SwiftUI iOS app skeleton
- `backend/` - FastAPI backend
- `docs/` - product and engineering documentation

Current project health and the recommended next MVP block are recorded in [`docs/checkpoints/mvp-3-32-project-health.md`](docs/checkpoints/mvp-3-32-project-health.md).

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

Shared visual primitives live in `ios/Orbit/Orbit/Components/OrbitDesignSystem.swift`.
Orbit's UI direction is a warm editorial personal OS: soft paper backgrounds,
rounded surfaces, thin warm borders, soft shadows, small capsule badges, calm
metadata, and minimal animation. The file provides spacing/radius/typography
scales (including a serif display role for emotional/editorial headings only,
using the built-in system serif — no custom font files), warm-neutral colors, a
layered background (`.orbitBackground()`), a
capsule badge (`OrbitBadge`), a section header (`OrbitSectionHeader`), and card
surfaces (`.orbitCardStyle()`, plus `.orbitFloatingCard()` + `.orbitListCardRow()`
for full-width list-row cards). Reach for these primitives before writing ad-hoc
card/badge/list styling so the app stays consistent across light and dark mode.
The Today, Ask, Inbox, and Bills screens already adopt them.

Run iOS unit tests:

```bash
xcodebuild test -project ios/Orbit/Orbit.xcodeproj -scheme Orbit -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:OrbitTests
```

Future UI tests can launch against stable in-process mock clients instead of a
live backend by setting `app.launchArguments = ["--orbit-ui-tests"]` or
`app.launchEnvironment["ORBIT_USE_MOCKS"] = "1"`. Normal launches continue to
use `OrbitAPIClient`.

Run the mock UI smoke tests (no backend or OpenAI key required). The suite in
`OrbitMockLaunchSmokeTests` covers baseline content across tabs plus three
suggested-action execution loops end to end:

- Create Todo: ask → Create a todo chip → preview sheet → execute → navigate to
  Today with the new todo.
- Save to Memory: ask → Save to memory chip → preview sheet (with the extracted
  memory text) → execute → navigate to Inbox with the new memory.
- Review Bills: ask → Review bills chip → preview sheet → confirm → navigate to
  Bills with stable seeded content and no mutation.

The shared runner executes these UI tests serially on one simulator to avoid
XCTest clone-runner launch failures.

```bash
# Default: dynamically selects an available iPhone simulator (what CI uses).
scripts/run_ios_ui_smoke.sh

# Pin a specific simulator by exact name for local debugging.
scripts/run_ios_ui_smoke.sh --simulator "iPhone 16 Pro"

# Or pin by UDID (see `xcrun simctl list devices available`).
scripts/run_ios_ui_smoke.sh --udid <SIMULATOR_UDID>

# Usage and examples.
scripts/run_ios_ui_smoke.sh --help
```

With no arguments the script dynamically selects whatever iPhone simulator is
available on the machine (so it does not depend on a specific simulator name);
`--simulator`/`--udid` pin one instead and are mutually exclusive. In all modes
it boots the simulator, waits for it to be ready, runs
`OrbitUITests/OrbitMockLaunchSmokeTests` in mock launch mode, prints the chosen
simulator, and writes results to `build/reports/` (gitignored):
`OrbitUITests.xcresult` and `orbit-ui-smoke.log`. CI runs this same script in its
default dynamic mode.

If you prefer to run `xcodebuild` directly, you can target a simulator you have
installed (replace the name as needed):

```bash
xcodebuild test -project ios/Orbit/Orbit.xcodeproj -scheme Orbit -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:OrbitUITests/OrbitMockLaunchSmokeTests
```

## Continuous Integration

GitHub Actions runs lightweight validation on pushes to `main` and pull requests:

- backend dependency install with `uv`, `pytest`, and an Alembic `upgrade head` smoke test against temporary SQLite
- iOS `xcodebuild test` for `OrbitTests`
- isolated mock-mode UI smoke coverage via the same `scripts/run_ios_ui_smoke.sh` runner used locally, with no backend required; failed runs upload the `.xcresult` bundle and xcodebuild log as `orbit-ui-smoke-xcresult`
- generic iOS Debug build with code signing disabled

Testing checklist:

- Run the `OrbitTests` command above for iOS unit coverage.
- Run the `OrbitMockLaunchSmokeTests` command above for the UI smoke flow. The test launches the app with `--orbit-ui-tests`, so it uses seeded mock dependencies and needs neither the backend nor an OpenAI key.
- When the CI UI smoke job fails, download `orbit-ui-smoke-xcresult` from the run's Artifacts section. It contains `OrbitUITests.xcresult` and `orbit-ui-smoke.log` and is retained for seven days.
- Inspect the uploaded diagnostics before changing the test or workflow. Add retries only after repeated simulator-related failures remain after the explicit `simctl bootstatus` readiness check; do not use retries to hide assertion failures.

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

That address lets the simulator reach the FastAPI server running on your Mac. The Today tab combines live Todos, Bills, Memory, and the latest Mood check-in into a dashboard. It also lets you submit a simple Mood check-in. The Bills tab uses the live Bill API to load, create, mark paid/unpaid, and delete bills. The Inbox tab uses the live Memory API to load, capture, archive, and delete memory items. The Projects tab uses the live Project API to load, create, update status, archive, filter, and delete projects. The Ask tab uses the backend `/ask` API with the deterministic mock AI provider and includes a lightweight context inspection panel for previewing backend context. Existing clients use keyword retrieval by default; hybrid retrieval is backend-only and opt-in until the iOS client adopts it.

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

The Ask backend and iOS Ask tab currently use a deterministic mock AI provider. They store chat sessions/messages and build a bounded, date-aware plain-text context from open todos, unpaid bills, recent memory, latest moods, and active projects. New chat sessions derive a compact, deterministic title from the first question; follow-up questions do not rename the session. Follow-up asks receive up to six recent messages from the same session in a compact, truncated conversation block; this continuity remains available when `include_context` disables Orbit data, while a new session starts without prior chat history. The iOS Ask tab shows these sessions as single-line chips with a `New Ask` fallback and provides New Chat and delete controls. Each new assistant answer also shows a compact summary of the non-empty Orbit context sections used for that response; the API exposes these as `context_sections` and `context_summary` without returning the raw context. `/ask` also returns up to two deterministic `suggested_actions` as response-only metadata. Suggested actions open draft preview sheets with local-only editing and validation for todo and memory drafts, while bill review and unknown actions are read-only. The `save_memory`, `create_todo`, and `review_bills` actions are executable: a valid memory draft can be confirmed with the "Save to memory" button (creating a memory item through the existing `POST /memory` endpoint, then opening the Inbox tab and briefly highlighting the new memory), a valid todo draft can be confirmed with the "Create todo" button (creating a todo through the existing `POST /todos` endpoint, then opening the Today tab and briefly highlighting the new todo), and `review_bills` can be confirmed with the "Review bills" button, which simply opens the Bills tab ("This will open Bills. Nothing will be changed.") without any mutation. After a successful create the app navigates to the destination tab, which reloads via the centralized refresh notifications so the highlighted item appears without a manual refresh. Execution is always explicit and user-confirmed (never automatic), navigation only happens after a successful create (never on failure or an invalid draft), runs only for a validated draft, and is guarded against duplicate submissions. Unknown action types remain preview-only with a disabled "Coming soon" button, and unsaved edits are still discarded when a sheet closes. Ask applies lightweight keyword relevance from the user's question so matching memory, projects, todos, and bills surface before the default ordering. Todos and bills are labeled as overdue, due today, due soon, or no due date where applicable; memory and project bodies are included only as short previews. `POST /ask/context-preview` is a backend development/debug helper that returns the context string and section names without calling the AI provider or saving chat messages.

Todo and memory suggested-action drafts are deterministically prefilled with cleaned text extracted from the Ask request (or a safe response fallback) and remain editable before explicit execution.

Add new real-world extraction phrases to `backend/tests/fixtures/suggested_action_extraction_cases.json`. The fixture regression test is deterministic and requires neither OpenAI nor an API key.

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

`retrieval_mode` is `keyword` or `hybrid` and defaults to `keyword`; `memory_top_k` accepts 1–20. Hybrid mode affects only the `Recent memory` section. It deduplicates candidates and ranks them with the deterministic guardrail `keyword_score + vector_score`, so exact title/tag/body matches outweigh accidental vector similarity; vector-matched rows retain debug score annotations. Missing, stale, failed, or temporarily unavailable embeddings degrade to keyword memory ordering. The production `/ask` route remains keyword-only; hybrid preview is an evaluation bridge before full Ask integration.

Orbit includes an embeddings/RAG foundation for memory items only. Embeddings are stored as JSON vectors in SQLite and searched with cosine similarity in Python; there is no external vector database. This retrieval path is development-only and is not connected to `/ask`, which continues to use keyword-ranked context. Orbit does not yet include production authentication/security for these development endpoints, streaming, or tool execution.

The default embedding provider is deterministic, local, and lexical. Its v2 tokenizer reuses Orbit relevance tokens, preserves meaningful short terms such as `ai`, `ui`, and `ios`, and removes generic query terms before hashing. Reindex after upgrading from the v1 mock model so existing memory items receive v2 embeddings:

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

To verify the iOS Hybrid memory Ask flow end-to-end against the real backend (not `MockChatAPIClient`), follow the [Manual iOS Hybrid Ask checklist](docs/manual-ios-hybrid-ask-checklist.md).

`seed_demo_data.py` is an explicit local-development helper; it is never run during app startup or deployment. It creates realistic Orbit, WorldLens, AI, Furlenco, mood, and fallback records using today's date. Re-running it skips records with the same demo title/name. Preview writes with:

```bash
python scripts/seed_demo_data.py --dry-run
```

By default, the eval harness only calls `POST /ask/context-preview`, prints returned context sections, and shows a truncated context preview. To also call `POST /ask` and print answers, run:

```bash
python scripts/run_ask_eval.py --ask
```

`--ask` creates real chat sessions in the dev database (one per question), which accumulate in `GET /chat/sessions` and the iOS Ask chat list. For throwaway smoke runs, add `--cleanup-sessions` to delete the sessions this run created once it finishes:

```bash
python scripts/run_ask_eval.py --ask --retrieval-mode hybrid --cleanup-sessions
python scripts/run_ask_eval_samples.py --runs 3 --ask --cleanup-sessions
```

Cleanup is **opt-in and not used by default**. It only deletes the session ids returned by `POST /ask` during that run — never arbitrary or pre-existing sessions — and only runs when `--ask` is also passed (it is a no-op otherwise). Cleanup happens after results are written, so debugging output is preserved even if a deletion fails; per-session failures are recorded in the summary (`cleanup_sessions_requested`, `cleanup_sessions_attempted_count`, `cleanup_sessions_deleted_count`, `cleanup_sessions_failed_count`, `cleanup_session_errors`) without failing the eval. The sampling script forwards `--cleanup-sessions` to each keyword/hybrid run and aggregates `total_cleanup_sessions_attempted_count`, `total_cleanup_sessions_deleted_count`, and `total_cleanup_sessions_failed_count`.

### Dev chat-session maintenance

Legacy sessions created before eval cleanup existed can be reviewed and removed manually with the dev-only maintenance script. It defaults to a dry run, requires at least one selector, and only deletes when `--confirm-delete` is explicitly passed. Deleting a chat session also deletes its messages; it does not delete todos, bills, memory, moods, projects, or embeddings.

Dry-run the first 20 sessions returned by the backend:

```bash
python scripts/cleanup_chat_sessions.py --all --limit 20
```

Delete that explicit selection after reviewing the dry run:

```bash
python scripts/cleanup_chat_sessions.py --all --limit 20 --confirm-delete
```

Filter by title without deleting:

```bash
python scripts/cleanup_chat_sessions.py --title-contains eval
```

No cleanup runs automatically during app startup, tests, or normal evals. This script is intended only for manual local development maintenance.

Save structured eval results locally:

```bash
python scripts/run_ask_eval.py --output eval-results/latest-keyword.json
python scripts/run_ask_eval.py --retrieval-mode hybrid --output eval-results/latest-hybrid.json
python scripts/run_ask_eval.py --ask --retrieval-mode hybrid --output eval-results/latest-hybrid-ask.json
python scripts/run_ask_eval.py --ask --output eval-results/openai-run.jsonl --format jsonl --run-label openai-smoke
```

Compare keyword and hybrid retrieval quality after generating both JSON baselines:

```bash
python scripts/compare_ask_eval_runs.py \
  --keyword eval-results/latest-keyword.json \
  --hybrid eval-results/latest-hybrid.json \
  --output eval-results/latest-comparison.json
```

The comparison reports summary rate deltas and classifies each question as improved, preserved, degraded, or changed. Degradation means hybrid loses expected section coverage or a section-aware expected item; improvement means it gains either signal. Questions present in only one run are marked changed. The comparison also reports an **answer-quality delta**: keyword and hybrid `answer_quality_pass_rate`, their delta, and the hybrid answer-quality failure count. Older eval outputs that predate answer-quality reporting are handled gracefully (missing fields read as `0`/`0.0`), so the comparison never crashes on them.

Run repeated paired samples and enforce initial rollout thresholds:

```bash
python scripts/run_ask_eval_samples.py \
  --runs 5 \
  --output-dir eval-results/samples/latest \
  --fail-on-degraded
```

Each sample writes keyword, hybrid, and comparison JSON files plus an aggregate `summary.json`. The initial local guardrails default to a `0.0` maximum hybrid fallback rate and a `25.0` ms maximum average latency delta; `--fail-on-degraded` additionally requires zero degraded questions. With local mock embeddings, fallback rate should remain zero, the latency delta should remain small, and degraded questions should be zero before hybrid retrieval is exposed in iOS.

Repeated sampling can also gate **answer quality**. The aggregate `summary.json` records per-run keyword/hybrid `answer_quality_pass_rate` values plus averages, minimums, and total failures. `--min-hybrid-answer-quality-pass-rate` (default `0.0`, i.e. no gating) fails the run when the minimum hybrid answer-quality pass rate across runs falls below the threshold:

```bash
python scripts/run_ask_eval_samples.py --runs 5 --ask --min-hybrid-answer-quality-pass-rate 1.0
```

Answer-quality gating requires `--ask` (the rate is `0.0` when no answers are produced). For local mock evals the recommended threshold is `1.0`, because the deterministic mock should pass every question. For real OpenAI runs, choose the threshold from repeated manual smoke results rather than blindly setting `1.0`; answer quality remains deterministic and local for mock evals and is never gated by default.

Both `POST /ask` and `POST /ask/context-preview` support opt-in hybrid retrieval with `retrieval_mode: "hybrid"`, `memory_top_k` (default `5`, range `1` to `20`), and `min_vector_score` (default `0.0`). Keyword retrieval remains the default for backward compatibility. Hybrid retrieval changes only the Recent memory section; the other context sections retain their existing ranking. If vector retrieval is unavailable at runtime, Orbit falls back to keyword-ranked memory. The eval harness sends the selected retrieval settings to both endpoints when `--ask` is enabled.

Both responses include `retrieval_diagnostics` when context is enabled. The object reports the retrieval mode and controls, whether vector search was attempted, its result count and runtime error (if any), whether keyword fallback was used, and total context-build latency in milliseconds. It is `null` when `include_context=false`. Empty vector results and runtime vector-search failures use keyword-ranked memory; embedding provider configuration errors retain the existing HTTP 500 behavior. Diagnostics are returned in the API response only—Orbit does not send them to an external telemetry service.

Eval logs distinguish returned section headers from useful sections with real data, so sections containing only `- None` do not count as matched context. Selected eval questions also declare expected top/absent items and section-aware top items. Logs record case-insensitive global positions, top-five matches, positions within each expected section, top-three section matches, missing expected items, unexpected absence-check hits, retrieval settings, vector-score annotation counts, fallback usage, vector attempts/results, and context-build latency. A compact run summary reports section matching, section-aware ranking, legacy global ranking, request errors, unexpected absence hits, hybrid annotation coverage, fallback count, and average context-build latency. Section-aware ranking is preferred because it evaluates an item relative to the section where it belongs; global ranking remains informational. Scores do not affect the script exit status—only request errors do.

The eval harness measures three families of signals. **Context retrieval metrics** check which expected sections came back with useful (non-`- None`) data — reported as section match pass/fail counts and rate. **Item ranking metrics** check whether expected records appear near the top, both globally (first five across data sections, legacy/informational) and section-aware (first three within the expected section, preferred), plus unexpected-absence hits for items that should not appear. **Answer quality term checks** run only with `--ask`: eval questions may declare optional answer-term expectations. Each evaluated question records `answer_term_matches`, `missing_answer_terms`, `answer_term_group_matches`, `missing_answer_term_groups`, `unexpected_answer_terms`, and an `answer_quality_pass` boolean, and the summary adds `answer_quality_evaluated_count`, `answer_quality_pass_count`, `answer_quality_fail_count`, and `answer_quality_pass_rate`. Answer quality is informational and does not affect the script exit status.

There are three kinds of answer-term expectation, all matched case-insensitively as substrings:

- `expected_answer_terms` — **strict**: every term must be present. Use for hard requirements, such as urgent items that must not be dropped (e.g. `upcoming_bills` requires both `Credit Card Payment` and `Furlenco`, because an overdue unpaid bill still counts as "coming up").
- `expected_answer_term_groups` — **flexible**: a list of groups, where each group is a set of acceptable alternatives and at least one alternative per group must be present. Use for wording that varies (e.g. `[["focus today", "should focus", "focus on"], ["Next step", "next steps"]]`). This keeps checks robust to real-LLM phrasing.
- `absent_answer_terms` — **forbidden**: none may appear (e.g. a paid bill should not be listed).

A question passes answer quality when all strict terms are present, every group has at least one matching alternative, and no absent terms appear. The two forms are independent and backward compatible — a question can use either or both.

Local answer quality is deterministic. When `ORBIT_AI_PROVIDER` is unset or `mock`, the mock provider produces structured, OpenAI-free answers (a direct lead line, short bullets that preserve dates/amounts/status, overdue/due-today/due-soon items listed in that order with overdue unpaid bills never omitted, cited memory titles, and an optional `Next step:`) derived only from the question text and the Orbit context string. This keeps the checks stable for tests and local evals without calling any external model. For real-LLM runs (`ORBIT_AI_PROVIDER=openai`), prefer `expected_answer_term_groups` for any phrasing that can legitimately vary, and reserve strict `expected_answer_terms` for genuine requirements like urgent unpaid bills that must always be surfaced.

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
