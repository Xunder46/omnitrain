# Code Review: plan 87c, PR 87c-1 (phone half: Phases 1A + 1B)

Base: 403d96d98b996f8bbafe0b7dae85e7c911e76b3d
Reviewer: code-reviewer (Copilot CLI)
Findings appended as found. Numbering: F1, F2, …

## Verification log

1. **Send rule** (`watch_sync_request_handler.dart` `_sendBests`, :249-284) — PASS. The revision is the block's first statement, before `StatsProgressService` is created; branch (b) returns with no walk; the compared text is `jsonEncode` of the payload's `bests` entries only (`buildBestsDown` puts `generatedAt` beside, not inside, `bests`; entries sorted by exerciseId — equal bests give equal text); branch (c) refreshes the remembered revision to the start-read; remember ONLY on `WatchDelivery.delivered`, `_bestsHeld = null` on anything else; a throwing walk propagates before any remember (no catch added — today's behaviour, S-87a-7 green); `_sendBests` is awaited after `_sendExerciseList` (frame still last) and `_sendRoutines` still returns `true` regardless of the send result. Write landing mid-request: the remembered revision is the start-read, older than the data → the next request re-walks (S-87c-12). Null-revision repository: branch (b) can never fire, the text comparison still stops a second send, every request walks (S-87c-7).
2. **`historyRevision`** — PASS. The four listened boxes (`_sessionsBox`, `_segmentsBox`, `_effortsBox`, `_observationsBox`) are exactly what `getAllTimeBests` consumes (stats_progress_service.dart:2264+ reads sessions, segmentsOf, effortsOf, observationsOf; timed/round instances and sensor summaries are loaded into the index but contribute nothing). `_listenForHistoryWrites` cancels-then-clears before re-adding (a second `initialize()` does not stack), uses its own `_historyListeners` list, and is called from `initialize()` beside `_listenForReferenceWrites`. Mock answers `null`. Implementers: exactly `HiveWorkoutRepository` and `MockWorkoutRepository` (`implements WorkoutRepository`); every test fake `extends MockWorkoutRepository` and inherits null.
3. **Request parsing** — PASS. `holdsBestsOf` is `frame['holdsBests'] == true` (string `"true"`, `1`, `false`, absent → not held); `routinesFrame` adds the key only when `holdsBests: true`, default false → every existing frame byte-identical; S-87c-9 pins the contract rows (`routines`, `routinesSince`) and the not-held spellings.
4. **Tests / mutations** — PASS. All six planned mutations have observed reds for the right reasons (evidence M1–M6: ignore flag → S-87c-4/14; skip revision compare → S-87c-1 on `sessionReads`; skip text compare → S-87c-3/7/12; remember on any result → S-87c-5 both arms + S-87c-13; read revision after walk → S-87c-12 via `bumpHistoryOnRead`; include `generatedAt` → S-87c-3/7 with the clock moved between raises). prove-red at the base is compile-red (the new API does not exist there) — re-confirmed by this review's own run; assertion-level reds come from the mutations, as the gateway's rule requires. No assertion loosened: the only changed line in an existing test is S-10411's needle; all five of its assertions are intact, comments are stripped before matching so the widened needle still uniquely locates the declaration, and the new block's ordering is guarded behaviourally by S-87c-12. **A-87c-7: RATIFY.**
5. **Seams and conventions** — PASS. `grep import .*hive_workout_repository` over `lib/state lib/features lib/widgets lib/core` → no matches (re-run by this review); the wiring is the one production call site and passes `holdsBestsOf(frame)`; the clock is injected (`_clock()`); the new groups are plain `test()` (the Hive group settles with a zero-duration delay, no `testWidgets`); `test/helpers/revisioned_repository.dart` keeps every counter and override of the old `_RevisionedRepo` and adds only the history side — faithful.
6. **Docs** — PASS for this PR. `watch_reference_data.md` and `watch_surface.md`: the sentences the change made false are replaced with the D-5 rule; every test named exists (S-87c-1, S-87c-3, S-87a-6/7/13, S-9202); nothing unshipped is named. Other implicated docs re-checked: `services_and_utils.md:275`, `nutrition_state.md:180`, `db_integration.md:201` — all still true (the `historyRevision` row is Phase 3's, not a finding here).

## Findings

- F1 | minor | docs/plans/2026-10-26-87-wrist-new-pr-banner-index.md:27 | the 87c-row rewrite + 87d split is outside this PR's Predicted Files (Phase 3 item 6 owns the file, for a status move only) — justified, since the seeded plan redefined 87c and the old row would now be false, but the row's "being planned" status is already stale (1A/1B are complete) | refresh the status when Phase 3 closes, or accept as series bookkeeping | @planner
- F2 | minor | watch_sync_wiring.dart:323 | the wiring's `holdsBestsOf(frame)` pass has no test in this PR, and A-87c-8 defers one to Phase 2 — but no Phase 2 item lands it (item 8 tests the frame builder, not the pass) | add a wiring-level test (the `radio.fromWrist` harness) to Phase 2's items, or accept Phase 3 QA step 36 as the only end-to-end guard | @planner
- F3 | minor | docs/state_management/watch_surface_wrist.md:258 | "the phone sends the bests last on every answer" is true for THIS PR but Phase 2 makes it false, and the plan's Phase 3 residue sweep (item 7) checks only the handler header and the two edited docs — this file is missing from that sweep | add the file to the Phase 3 residue sweep or reword the sentence then | @planner

None of the three blocks this PR: F2/F3 are plan gaps for the NEXT PR, F1 is bookkeeping that keeps the index truthful.

## Assumption Log adjudication

- A-87c-6 (observations counted via `deleteObservationsForEffort`): **RATIFY** — the test asserts +2 for a two-row delete through the public API, the same per-key listener semantics the scenario names.
- A-87c-7 (S-10411 needle widened): **RATIFY** — see verification log 4; the guard's subject is untouched and no assertion moved.
- A-87c-8 (wiring pass untested, deferred): **RATIFY the deferral, with F2** — the deferred test has no Phase 2 item to land it; the planner must give it a home.
- A-87c-9 (the two doc corrections in this PR): **RATIFY** — both sentences are true post-change and name existing tests; the remaining watch-doc sweep stays with Phase 3.

## Test run (this review's own)

`.github/copilot/scripts/macos/gateway.sh test` → `06:05 +5779 ~2: All tests passed!` — **5779 passed, 2 skipped, 0 failures** (matches the plan's Progress entry and the brief's expectation).

## Verdict

No blockers, no majors; 3 minor findings (all forward-looking or bookkeeping).

**VERDICT: APPROVE**
