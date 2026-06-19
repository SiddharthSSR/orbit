# MVP-3.32 Project Health Checkpoint

Recorded after MVP-3.31 on 2026-06-19. The latest commit before this checkpoint was `7bad6e9e09ed91a56180af147fb3ccd5e8387787`.

## Current capabilities

- Ask stores sessions and messages, derives readable session titles, supports delete/clear, and supplies bounded follow-up continuity.
- Ask context exposes which Orbit sections contributed to an answer. Memory retrieval defaults to keyword ranking; the persisted iOS hybrid toggle remains opt-in.
- Assistant answers render lightweight Markdown without changing the underlying answer text.
- Memory embeddings, deterministic evaluation tooling, and answer-quality gates support RAG development without requiring OpenAI in tests.
- Suggested actions remain response-only metadata and always require explicit user confirmation. Drafts are editable and validated before execution.
- `save_memory` creates a memory, refreshes Inbox, navigates there, briefly highlights the created item, and records local completion status on the originating Ask action.
- `create_todo` provides the equivalent flow for Today and the created todo.
- `review_bills` only navigates to Bills; it does not mutate data.
- Suggested memory/todo payloads are extracted deterministically. Real-world phrase regressions belong in `backend/tests/fixtures/suggested_action_extraction_cases.json`.

## Testing and CI

- The MVP-3.31 backend suite contains 255 passing tests, including ten fixture-driven extraction regressions.
- The most recent iOS validation before this checkpoint contained 173 passing unit tests and one deliberately narrow mock-launch UI smoke test.
- `--orbit-ui-tests` and `ORBIT_USE_MOCKS=1` provide stable seeded dependencies without a backend, development database, OpenAI call, or API key.
- CI runs backend tests and migration smoke, iOS unit tests/build, and the isolated UI smoke job.
- The UI job selects and boots a simulator by UDID, waits for `simctl bootstatus`, captures an xcodebuild log and `.xcresult`, and uploads `orbit-ui-smoke-xcresult` for seven days on failure.

## Known risks and boundaries

- UI automation covers baseline tab content only; it is not broad end-to-end coverage of action execution or CRUD workflows.
- Deterministic phrase extraction will miss language variants. Extend fixtures from observed misses instead of adding speculative parsing rules.
- Executable suggested actions are intentionally limited to memory, todos, and safe Bills navigation. Orbit has no generic or autonomous tool execution.
- Suggested-action completion status is local and in-memory, so session changes intentionally clear it.
- GitHub's `macos-latest`, Xcode, and simulator images can change despite explicit simulator readiness checks.
- Authentication and production security remain outside the current local-development scope.

## Recommended next MVP block

- Improve suggested-action extraction only when real usage supplies a reproducible fixture miss.
- Prefer small, visible polish that clarifies what changed or where navigation landed.
- Deepen one user-confirmed Today, Inbox, or Bills workflow at a time, with focused unit/integration coverage before widening UI automation.
- Add UI coverage selectively for stable, high-value workflows; keep failure artifacts and avoid blanket retries.
- Defer generic agents/tools until there is a concrete use case with explicit confirmation, narrow permissions, and testable failure behavior.

