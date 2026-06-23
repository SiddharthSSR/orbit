# MVP-4.9 Project Intelligence Checkpoint

Recorded after MVP-4.8 on 2026-06-24. The latest commit before this checkpoint was `eda1601cf3135f40061a1846709064cd3812d1bd`.

This checkpoint documents the completed Project Intelligence arc (linking memories and
todos to projects, project detail surfaces, and optional project-scoped Ask) so future
work has clear constraints and a documented current state. It is a docs-only checkpoint;
no product, backend, retrieval, Ask, or CI behavior changed.

## Current capabilities

- Backend memory and todo records support a nullable `project_id`. `GET /memory` and
  `GET /todos` accept an optional `project_id` filter; omitting it preserves the existing
  unfiltered behavior.
- Inbox can link, change, and unlink a memory's project (explicit-null unlink).
- Today todo rows can link, change, and unlink a todo's project (explicit-null unlink).
- Project detail shows the linked memories, linked todos, and a read-only activity
  summary (linked/open/completed counts, next due todo, last linked memory date) computed
  from the already-loaded linked data.
- Linked-project labels are consistent across Today, Inbox, and Project detail via the
  shared `LinkedProjectLabel`.
- Ask can be optionally scoped to one project. When scoped, the backend limits only the
  Recent memory context section to that project's linked memories; when unscoped, Ask
  behaves exactly as before.
- The Ask context preview honors the same scope and labels itself when project-scoped.

## Guardrails

- Unscoped Ask is the default and must remain unchanged. The request omits `project_id`
  when no project is selected.
- Project scoping is opt-in only: it applies only when the user explicitly selects a
  project, and clearing returns to unscoped behavior.
- Project-scoped Ask only scopes the Recent memory context section. It does not scope
  todos, bills, moods, or active projects sections, and it does not add new retrieval
  inputs.
- Retrieval and hybrid defaults must not change without an explicit MVP and test coverage.
  Hybrid remains opt-in and keyword remains the default.
- Embeddings must not change as a side effect of link/unlink or scoping operations. Linking
  a memory or todo to a project does not re-embed or alter embedding generation.
- No new backend endpoints were introduced for project scoping; it reuses the existing
  `/ask`, `/ask/context-preview`, `/memory`, and `/todos` paths.

## Current UI surfaces

- Inbox: per-memory project link/unlink menu and linked-project label.
- Today: per-todo project link/unlink menu and linked-project label.
- Project detail: linked memories, linked todos (with linked-project label), and the
  read-only activity summary.
- Ask: a sheet-based project scope selector (opt-in, defaults to "All Orbit context") and a
  context preview that labels itself when project-scoped.

## Validation coverage

### Backend (`backend/tests/`)
- `test_chat.py` — Ask and context-preview behavior, including unscoped vs. project-scoped
  context (scoped includes only linked project memories; scoped-empty is graceful; unscoped
  preserves default context).
- `test_memory.py`, `test_todos.py` — CRUD plus `project_id` filtering (filtered list,
  excludes unlinked, unfiltered unchanged).
- `test_projects.py` — project CRUD/status/filter behavior.
- Retrieval/relevance/embedding/eval suites remain unchanged
  (`test_memory_retrieval.py`, `test_relevance.py`, `test_embedding_provider.py`,
  `test_ask_eval_*`, `test_suggested_action*`).

### iOS unit/contract (`ios/Orbit/OrbitTests/`)
- `OrbitAPIClientContractTests.swift` — request encoding, including scoped vs. unscoped Ask
  and context-preview `project_id` (omitted when unscoped), and todo/memory project-link
  encoding (explicit-null unlink).
- `AskViewModelTests.swift` — scoped/unscoped Ask and preview requests, clearing scope,
  preview invalidation on scope change, and project-load failure not blocking Ask.
- `TodayDashboardViewModelTests.swift` — todo project link/unlink local state and
  project-load failure not breaking the todo list; `ProjectActivitySummary` derivations.
- `MemoryListViewModelTests.swift`, `TodoListViewModelTests.swift`,
  `ProjectListViewModelTests.swift` — linking/filtering and list behavior.

### UI smoke (`ios/Orbit/OrbitUITests/OrbitMockLaunchSmokeTests.swift`)
- `testMockLaunchShowsStableContentAcrossTabs`
- `testProjectDetailShowsLinkedMemoriesAndTodos`
- `testAskProjectScopeSelectAndClear`
- `testAskContextPreviewReflectsProjectScope`
- `testTodayTodoCanLinkAndUnlinkProject`
- `testInboxMemoryCanLinkAndUnlinkProject`
- `testCreateTodoSuggestedActionFlowNavigatesToTodayWithNewTodo`
- `testSaveMemorySuggestedActionFlowNavigatesToInboxWithNewMemory`
- `testReviewBillsSuggestedActionNavigatesToBills`

All UI smoke runs in mock launch mode (`--orbit-ui-tests`) with seeded dependencies — no
backend, development database, OpenAI call, or API key.

## CI timing note

- The iOS UI Smoke job has `timeout-minutes: 25` (`.github/workflows/ci.yml`). This was
  raised from 15 in MVP-5.0 after a runner-variance cancellation; see the reasoning below.
- The smoke suite itself runs in ~7 minutes; the variable cost is a full from-scratch Swift
  build plus simulator boot on `macos-latest`. On MVP-4.8 the first attempt was cancelled at
  the old 15-minute mark even though all 9 UI tests had passed; the rerun passed.
- The project has no SwiftPM dependencies to cache, and Xcode DerivedData caching across
  runners is unreliable enough to risk introducing build flakiness, so MVP-5.0 used a modest
  headroom timeout (25 min) instead of a cache. 25 minutes comfortably covers a slow
  build/boot while still bounding a genuinely hung run.
- First action on a UI Smoke cancellation: inspect the job log/artifacts. If the tests
  passed and the job was cancelled by the timeout, rerun the job rather than changing code.
- Do not change the CI timeout casually. Any further timeout change or caching is a
  deliberate, infra-only change that belongs in its own MVP with explicit justification.

## Recommended next steps

- Treat the Project Intelligence arc as complete and stable; avoid expanding project scoping
  beyond Recent memory without an explicit MVP and tests.
- If UI Smoke timeouts recur, scope a separate infra-only MVP to add SwiftPM/derived-data
  caching or adjust the timeout deliberately — do not bundle it with product work.
- Keep new project-linked surfaces read-only unless a confirmed, tested workflow requires
  mutation, consistent with the existing opt-in, explicit-confirmation patterns.
