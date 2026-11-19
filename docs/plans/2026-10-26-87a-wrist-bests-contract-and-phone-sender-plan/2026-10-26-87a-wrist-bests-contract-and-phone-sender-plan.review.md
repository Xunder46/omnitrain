# Review: 87a — contract + phone sender for `bests_down`

Base: 530995d40dd3170d6d20026d8bf2e8665e677e53. Reviewer: code-reviewer (Copilot CLI edition).

## Findings

(appended as found)

## Scope

Layers in scope: core (sync protocol, services, utils), state (watch handler), contract (`watch/sync_protocol/`), tests, docs.
Layers skipped: models, persistence, features, widgets, components (no changes). No UI on either device — UI standards N/A (evidence: `ui_standards_contract_test.dart` 29 passed, no allowlist entry touched).

Diff vs Predicted Files: conforms — every predicted file changed, nothing out of bounds except `test/watch_sync_idle_reads_test.dart`, declared in Assumption A-14 (an unpredicted fourth reader of the frame stream, adjusted read-based). No unfinished predicted file.

## Test run (my own)

- `gateway.sh test` (full suite): **5760 passed, 2 skipped, 1 failed** — the one failure is `pre_release_gate_upload_destination_test.dart` S-001, which scans the working tree and collided with the prove-red scratch dirs my parallel runs created (rsync errors on vanishing `.work/gateway/base-*` paths). Re-run in isolation: **8 passed, 0 failed**. Effective result matches the implementer's 5761 passed / 2 skipped / 0 failed.
- prove-red `530995d4` on `test/sync_protocol_fixtures_test.dart` **with the manifest, schema and 11 fixtures carried**: RED AT base, 10 failures for the right reasons (3 valid fixtures rejected, 7 invalid ones `unknown_message_type`). Note: carrying only the test file is GREEN AT base (the suite is manifest-driven and reads the repo's fixtures) — the contract files must be carried for the proof to mean anything; the implementer's evidence did carry them.
- prove-red `530995d4` on `test/stats_bests_builder_test.dart`: RED AT base (compile error — `getAllTimeBests`/`buildBestsDown` do not exist at base; the accepted form for a new-API guard).
- prove-red `530995d4` on `test/watch_sync_request_handler_test.dart`: RED AT base, 11 assertion failures for the right reasons (six S-87a tests + five sharpened frame-count assertions).

## Findings (numbered)

1. minor | docs/state_management/services_and_utils.md:239 | the `StatsProgressService` page does not mention the new `getAllTimeBests()` bulk method | add one sentence pointing at `test/stats_bests_builder_test.dart` S-87a-5 (the parity guard) | @developer
2. minor (report only, per brief item 5) | lib/state/watch/watch_sync_request_handler.dart:213 | every routines request — including plan 74's idle raise, which read nothing before — now walks the whole completed-session history: `_loadHistory()` (stats_progress_service.dart:100) issues seven bulk repository reads (all sessions, segments, efforts, observations, timed/round instances, sensor summaries) and builds the full index | acceptable for now: syncs are user-driven and infrequent, and the walk is one bulk read set, not per-exercise re-walks (D-5 already avoided the 166× cost). No cheap guard exists: `referenceRevision` (hive_workout_repository.dart:179) counts only the reference-data boxes (foods, routines, exercises, catalog) and does NOT move on a completed workout, so it cannot gate bests; a session-box revision counter would be the cheap guard but is a design change for the owner, not this PR | @planner (next plan)

No blockers. No critical findings. No test asserts buggy behaviour; no allowlist entry added; no ratchet raised.

## Checklist results

- Acceptance criteria (4a): all four met — (1) family + fixtures + PROTOCOL rows + both validators accept/refuse as stated (S-87a-4/10, RED AT base); (2) numbers equal the per-exercise methods (S-87a-5 parity test over fixture H + seed data); (3) sent on every routines request including since-current (S-87a-6, S-9202, S-10405); (4) unknown-type receivers ignore it (both `receive` defaults untouched; D-6 confirmed — no `lib/watch/` twin change, no `WatchSyncProgress.swift` change).
- Scenarios (4b): S-87a-1..14 each have a test; fixtures conform to the scenarios (fixture H re-derived against `epley1RM`, 301-exercise cap fixture, in-progress-only, empty history); all pass.
- Test-run verification (4c): handoff contains pasted counts (evidence file lines 146-152, 207-214, 279-287); my own runs above agree.
- Renames among the seven adjusted assertions: two tests were renamed — S-9202 ("sends zero frames" → "sends exactly one frame, the bests") and S-10405 ("reads nothing and sends nothing" → "reads nothing and sends only the bests"). The other five (S-3850, S-3851, S-3857, S-7101, S-7103, S-003) kept their names and were tightened (`everyElement` → exact lists including `bests_down`). All sharpened, none loosened.
- DOC FALSIFICATION: ✅ PASS (4 implicated) — PROTOCOL.md, watch_reference_data.md, watch_surface.md updated and true; watch_session_sync.md names no message family (untouched, correct); services_and_utils.md incomplete only (finding 1). No conflicts.
- DOC STANDARD: ✅ PASS — no prohibited content added; the new doc prose points at named tests rather than restating behaviour.
- IMPACT (4g): 11 rows checked; grep re-runs confirm the named readers; the one drift (S-10405) is declared in A-14 and adjusted read-based; no unlisted reader found (residue sweep for `everyElement('exercises_down')` and exact three-frame lists: zero stale readers remain).
- Conventions (4f): PASS (applicable: test placement, Mock-first plain `test()`, no UI standards surface, doc pointers). N/A (UI/design-system rules — no UI in this PR).
- Assumption Log: A-1..A-14 RATIFIED (each is consistent with the recorded decisions and the code; A-14's out-of-predicted-files test adjustment is declared and read-based). No silent guesses found.
- Plan status: Progress section claims match the evidence file; no `## Feedback` section needed (no blocker).

## Cost note (brief item 5, expanded)

`_loadHistory()` reads everything the history index needs in one pass and caches per instance; the handler constructs a fresh `StatsProgressService` per request (D-11), so the cache never helps across requests. The idle raise (S-10405) therefore went from zero reads to one full-history read set per idle sync. The repository exposes no cheap "session history changed" signal — `referenceRevision` covers only reference-data boxes. Verdict: acceptable; if the owner wants the idle raise cheap again, the one-line-shape guard is a session-box revision counter compared across requests (same pattern as plan 74's `referenceRevision`).

## Open questions

1. (Recommended default: accept) The idle-raise cost above is shipped as-is; a session-revision guard is deferred to the owner.
2. (Recommended default: accept) Finding 1 is a doc-completeness nit; fix in 87b's docs pass or now, owner's choice.
