# Manual iOS Hybrid Ask — Live Backend Verification Checklist

This checklist verifies the iOS "Hybrid memory" Ask flow end-to-end against the
**real backend**, rather than the `MockChatAPIClient` used by unit tests. Use it
after backend or iOS changes that touch hybrid retrieval, before releasing the
feature.

Background:

- MVP-2.9 added the iOS Hybrid memory toggle (default OFF / keyword).
- MVP-2.10 persisted the toggle locally via `UserDefaults`.
- Backend hybrid readiness already passed repeated eval sampling (10 runs,
  average latency delta +0.81 ms, max +1.57 ms, hybrid fallback rate 0%,
  degraded questions 0, result PASS).

This document adds **no app features and no backend behavior changes**. It is a
lightweight, manual procedure only. Keyword retrieval remains the default.

---

## 1. Backend setup

Run from the repository root.

```bash
cd backend
source .venv/bin/activate
alembic upgrade head
python scripts/seed_demo_data.py
curl -s -X POST http://127.0.0.1:8000/memory/embeddings/reindex | python3 -m json.tool
uvicorn app.main:app --reload
```

Notes:

- `seed_demo_data.py` is a local-development helper only; it is never run during
  app startup or deployment. It seeds the demo records this checklist relies on,
  including the **AI Agents Reading List** memory item. Re-running it skips
  records with the same demo title/name.
- The reindex step builds memory embeddings so hybrid retrieval has vectors to
  search. Run it once after seeding (and again after adding/editing memory).
- Keep `uvicorn` running in this terminal; run the sanity checks below from a
  second terminal.

---

## 2. Backend sanity checks

### 2a. Embeddings status

```bash
curl -s http://127.0.0.1:8000/memory/embeddings/status | python3 -m json.tool
```

Expected: a non-zero `indexed_count`, with `missing_count`, `stale_count`, and
`failed_count` all at `0` after a fresh seed + reindex. If items are missing or
stale, re-run the reindex from step 1.

### 2b. Hybrid context preview

```bash
curl -s -X POST http://127.0.0.1:8000/ask/context-preview \
  -H "Content-Type: application/json" \
  -d '{
        "question": "What did I save about AI?",
        "include_context": true,
        "retrieval_mode": "hybrid",
        "memory_top_k": 5,
        "min_vector_score": 0.0
      }' | python3 -m json.tool
```

Expected results:

- The **Recent memory** section's first item is **AI Agents Reading List**.
- `retrieval_diagnostics` reports:
  - `retrieval_mode`: `hybrid`
  - `vector_attempted`: `true`
  - `vector_result_count`: greater than `0`
  - `fallback_used`: `false`

If `retrieval_diagnostics` is `null`, confirm `include_context` is `true`.

---

## 3. iOS simulator steps

Build and run the iOS app against the local backend (the client defaults to
`http://127.0.0.1:8000`, which the simulator can reach on the host Mac).

1. Launch the app on the simulator.
2. Open the **Ask** screen.
3. **Clean install default:** confirm **Hybrid memory is OFF** (this is the
   first-install / keyword default). See troubleshooting if it is ON.
4. With Hybrid memory still OFF, ask: **"What did I save about AI?"** and confirm
   an answer is returned (keyword path).
5. Turn **Hybrid memory ON**.
6. **Preview context** for: **"What did I save about AI?"**
7. Confirm the **Recent memory** section puts **AI Agents Reading List** first.
8. Confirm the diagnostics line shows: **Hybrid**, **vectors > 0**, **fallback
   no**, and a **build ms** value.
9. **Force quit and relaunch** the app.
10. Confirm **Hybrid memory remains ON** (persistence from MVP-2.10).
11. Turn **Hybrid memory OFF**.
12. **Force quit and relaunch** the app again.
13. Confirm **Hybrid memory remains OFF**.

---

## 4. Troubleshooting

- **Vector results are 0:** re-run the reindex
  (`curl -s -X POST http://127.0.0.1:8000/memory/embeddings/reindex`) and check
  `GET /memory/embeddings/status`. A non-zero `missing_count`/`stale_count`
  means embeddings are not built for the seeded memory.
- **Backend unreachable from the simulator:** confirm `uvicorn` is running and
  that the iOS client base URL matches it (`http://127.0.0.1:8000` in
  `ios/Orbit/Orbit/Networking/OrbitAPIClient.swift`). The simulator reaches the
  host Mac via `127.0.0.1`; a physical device needs the Mac's LAN IP instead.
- **`fallback_used` is true:** vector search degraded to keyword ordering. Check
  the backend logs and `GET /memory/embeddings/status` for missing, stale, or
  failed embeddings, then reindex.
- **Clean install does not default OFF:** the device retained a previous
  preference. Reset the app (erase the simulator / delete and reinstall the app)
  or clear its `UserDefaults` so the keyword default applies on first launch.

---

## 5. Pass criteria

The hybrid Ask flow passes when all of the following hold:

- Backend sanity checks (section 2) match the expected diagnostics and ordering.
- The simulator preview ranks **AI Agents Reading List** first under Recent
  memory with Hybrid on, and the diagnostics line shows vectors > 0 / fallback
  no.
- The toggle defaults OFF on a clean install and survives relaunch in both the
  ON and OFF states.
