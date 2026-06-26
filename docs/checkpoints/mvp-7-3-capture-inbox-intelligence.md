# MVP-7.3 Capture / Inbox Intelligence Checkpoint

Recorded after MVP-7.2 on 2026-06-26. The latest commit before this checkpoint was
`73fe7406aeb94cfc3457712fbd8ab0fa491b20ba` ("Add Inbox memory detail view").

This checkpoint documents the completed Capture / Inbox Intelligence arc — capture
quality metadata, the needs-review cue, Inbox filters, and a read-only memory
detail view — so future work has a clear current state and constraints. It is a
docs-only checkpoint; no product, backend, retrieval, Ask, test, or CI behavior
changed.

## Current Inbox capabilities

- **Capture quality metadata** — each Inbox row derives `MemoryCaptureQuality`
  purely from existing `MemoryDTO` fields: `isLinkedToProject`, `hasTags`,
  `hasSource`. No score is invented and no backend data is required.
- **Needs-review cue** — a calm orange "Needs review" badge appears only for bare
  captures: not linked to a project, untagged, and without a source
  (`needsReview = !isLinkedToProject && !hasTags && !hasSource`). The signal is
  deterministic and conservative, not an AI judgment.
- **Filters** — a compact segmented control filters the already-loaded list:
  **All** (default), **Needs review**, **Linked**, **Has source**, via
  `InboxMemoryFilter`. Filtering is client-side over `memoryItems`; the unfiltered
  list stays the source of truth, so it issues no extra network requests.
- **Memory detail view** — tapping a row's content opens a read-only
  `MemoryDetailView` (pushed via `navigationDestination`). It shows the title,
  kind, needs-review cue, source host + full (selectable) URL, body, tags, linked
  project, and captured date. Missing source/tags/project render calm "omitted"
  rows rather than disappearing. No editing.
- **Preserved row actions** — project link/unlink (menu), archive, delete, and the
  new-capture highlight all continue to work. Only the row's content area is the
  navigation button; the action controls live outside it so their taps are not
  swallowed by row navigation.

## Guardrails

- Inbox intelligence is currently **iOS / client-side only**. All signals are
  derived in the app from fields the memory list already carries.
- **No backend endpoints** were added or changed in this arc. It reuses the
  existing `/memory` list path.
- **No Ask / retrieval changes.** Ask scoping, hybrid/keyword defaults, and
  context preview behavior are untouched.
- **No embedding changes.** Capture-quality derivation, filtering, and the detail
  view never re-embed or alter embedding generation.
- **Needs-review is conservative and not an AI score.** It is a boolean over three
  existing fields; it flags only captures with no organizing metadata at all.
- **Filters operate over already-loaded memories.** Changing the filter reshapes
  the in-memory list and does not reload from the backend.
- **The detail view is read-only.** It adds no editing, archiving, or
  project-linking; those remain row-level actions on the Inbox list.

## Validation coverage

### iOS unit (`ios/Orbit/OrbitTests/MemoryListViewModelTests.swift`)
- **`MemoryCaptureQuality`** — bare capture → needs review; tagged, linked, or
  sourced → not needs review; empty-string source treated as no source.
- **Filters** — `All` returns everything; `Needs review` returns only bare
  captures; `Linked` returns project-linked memories; `Has source` returns
  memories with a source; an empty filter result is handled (list empty while the
  underlying `memoryItems` is non-empty).

### UI smoke (`ios/Orbit/OrbitUITests/OrbitMockLaunchSmokeTests.swift`)
- `testInboxFilterNarrowsCapturesAndReturnsToAll` — All → Needs review (empty
  state, deterministic since no seeded capture is bare) → back to All.
- `testInboxMemoryOpensReadOnlyDetail` — open a capture's detail, assert the full
  source URL (unique to the detail screen), then return to Inbox.
- `testInboxMemoryCanLinkAndUnlinkProject` — project link/unlink still works after
  the row was made tappable for navigation.
- `testMockLaunchShowsStableContentAcrossTabs` — Inbox loads with stable content.

All UI smoke runs in mock launch mode (`--orbit-ui-tests`) with seeded
dependencies — no backend, development database, OpenAI call, or API key.

## Current UI smoke expectations

- Inbox loads with the seeded captures ("AI article link" is the first row).
- The filter control narrows the list and resets:
  - **Needs review** is deterministically empty in the mock (every seeded capture
    is tagged, linked, or sourced), so it shows the "No matching captures" empty
    state.
  - **All** restores the full list.
- The read-only detail opens from a row and returns to Inbox via the back button;
  the row open-button (`Open memory <title>`) exists only on the Inbox list.
- Project link/unlink continues to work from the row's project menu.
- Assertions avoid below-fold rows and dynamic dates; the detail check targets the
  full source URL in the top card.

## CI timing note

- The iOS UI Smoke job has `timeout-minutes: 25` (`.github/workflows/ci.yml`),
  unchanged in this arc. The suite runs in ~8–13 minutes; the variable cost is a
  full from-scratch Swift build plus simulator boot on `macos-latest`.
- First action on a UI Smoke cancellation: inspect the job log/artifacts. If the
  tests passed and the job was cancelled by the timeout, rerun the job rather than
  changing code. Do not change the CI timeout casually — any timeout/caching change
  is a deliberate, infra-only change that belongs in its own MVP.
- One UI smoke assertion in this arc (MVP-7.1) initially failed on CI because it
  targeted a below-fold memory row; the fix was to assert only on-screen / empty
  state content. Keep new smoke assertions on the first row or in-place empty
  states.

## Recommended next steps

- **Move to a Bills / Finance arc** — the Capture / Inbox Intelligence arc can be
  treated as complete and stable; new product work can begin a fresh MVP block.
- **Add source-opening from memory detail** — let the detail open the source URL
  in the browser (read-only-friendly, small, scoped).
- **Add in-detail archive / project-link actions** — only as a separate, scoped
  MVP with its own tests; the detail intentionally stays read-only until then.
