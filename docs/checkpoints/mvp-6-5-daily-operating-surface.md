# MVP-6.5 Daily Operating Surface Checkpoint

Recorded after MVP-6.4 on 2026-06-25. The latest commit before this checkpoint was
`a4bc38c87cc3d25fdb7b510f4a10a9ec3f4597ff` ("Summarize Today project digest").

This checkpoint documents the completed Daily Operating Surface arc — the Today
Project Digest and its supporting cues, states, and summary — so future work has a
clear current state and constraints. It is a docs-only checkpoint; no product,
backend, retrieval, Ask, test, or CI behavior changed.

## Current Today capabilities

- **Project Digest** — Today shows a compact digest of projects with linked
  activity (open/completed todos and non-archived linked memories). Items are
  derived from already-loaded Today data via `TodayProjectDigestItem.derive`,
  sorted by next-due then open count then recent activity, and capped at 4.
- **Digest row navigation** — each digest row opens the corresponding Project
  detail (the row is the project; tapping selects it), reusing the existing
  Project detail surface unchanged.
- **Due cues** — each row shows a deterministic next-due cue for its earliest open
  dated todo: `Overdue: <title>`, `Due today: <title>`, or `Next: <title> · <date>`
  for later/tomorrow.
- **Caught-up state** — a project with linked activity but no open linked todos
  shows a calm "All caught up" signal instead of a silent zero. Per-project empty
  input still shows the section empty state ("No project activity yet").
- **Header summary** — the Project Digest section header shows a compact badge
  summarizing the digest at a glance, e.g. `1 project · All caught up` or
  `4 projects · 2 open`, derived via `TodayProjectDigestSummary.derive`. An empty
  digest shows no badge and preserves the existing empty state.

## Guardrails

- The Today digest is **read-only**. The only mutating actions on Today remain the
  pre-existing todo create/complete and per-todo project-link/unlink flows; the
  digest itself adds no new actions or workflows.
- **No Ask/retrieval changes** were made in this arc. Ask scoping, hybrid/keyword
  defaults, and context preview behavior are untouched.
- **No backend endpoints** were added or changed. The digest is an iOS-only,
  client-derived view.
- The digest **uses existing loaded data** (the todos, memories, and projects
  already fetched for Today). It issues no additional network requests and does not
  re-embed or alter any backend state.
- UI smoke avoids **brittle dynamic date assertions**. Date-bearing cues (e.g.
  "Next: … · <date>") are not asserted with literal dates; smoke assertions target
  stable mock content (the caught-up signal and the deterministic header summary).

## Validation coverage

### iOS unit (`ios/Orbit/OrbitTests/TodayDashboardViewModelTests.swift`)
- **Digest derivation** — counts linked open/completed todos and non-archived
  linked memories; ignores unlinked activity; handles empty input; sorts by
  next-due then open count.
- **Due cue** — overdue, due-today, and upcoming (date-bearing, prefix-asserted)
  cues; ignores completed and undated todos.
- **Caught-up** — caught-up when completed-only or memory-only; not caught-up with
  open todos.
- **Header summary** — multi-project open count (`2 projects · 3 open`), singular
  open (`1 project · 1 open`), all-caught-up (`1 project · All caught up`), and
  `nil` for an empty digest.

### UI smoke (`ios/Orbit/OrbitUITests/OrbitMockLaunchSmokeTests.swift`)
- `testMockLaunchShowsStableContentAcrossTabs` — Today loads with stable content
  and the Project Digest section appears.
- `testTodayProjectDigestOpensProjectDetail` — the Orbit digest row appears, the
  header summary reads `1 project · All caught up`, and tapping the row opens
  Project detail with linked todos/memories.

All UI smoke runs in mock launch mode (`--orbit-ui-tests`) with seeded
dependencies — no backend, development database, OpenAI call, or API key.

## Current UI smoke expectations

- Today loads (default tab) with stable mock content.
- The "Project Digest" section header appears.
- The seeded digest has one project (Orbit) with no open todos, so:
  - the header summary is the stable string `1 project · All caught up`, and
  - the Orbit digest row shows the caught-up signal.
- Tapping the Orbit digest row navigates to Project detail (Activity, Linked
  todos, Linked memories).

## CI timing note

- The iOS UI Smoke job has `timeout-minutes: 25` (`.github/workflows/ci.yml`),
  unchanged in this arc. The suite itself runs in ~7–8 minutes; the variable cost
  is a full from-scratch Swift build plus simulator boot on `macos-latest`.
- First action on a UI Smoke cancellation: inspect the job log/artifacts. If the
  tests passed and the job was cancelled by the timeout, rerun the job rather than
  changing code. Do not change the CI timeout casually — any timeout/caching change
  is a deliberate, infra-only change that belongs in its own MVP.

## Recommended next steps

- **Continue Today polish** — incremental, read-only refinements to the digest and
  surrounding Today surfaces are low-risk and consistent with this arc.
- **Start a new arc** — the Daily Operating Surface arc can be treated as complete
  and stable; new product work can begin a fresh MVP block.
- **Only revisit CI if smoke timing regresses** — if UI Smoke timeouts recur,
  scope a separate infra-only MVP (SwiftPM/derived-data caching or a deliberate
  timeout change); do not bundle it with product work.
