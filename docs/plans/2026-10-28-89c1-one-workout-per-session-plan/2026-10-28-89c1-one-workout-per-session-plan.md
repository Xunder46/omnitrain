# Plan 89c1: one Fitness workout per session (no phone copy on top of the watch's)

> Status: BUILT 2026-10-28, uncommitted (Phase 1 Complete; see Progress). First PR of the 89c series (`docs/plans/2026-10-28-89c-fitness-one-workout-per-session-index.md`). Phone track only, plus one watch-side test. Follows plan 89 (uncommitted at planning time).

## Goal and acceptance

Owner report (2026-10-28, real watch): starting an outdoor walk as a Free session from the watch put two sessions in Apple Fitness, one "Outdoor Walk" and one "Other". Cause, read from source (not yet confirmed on the device):

- The watch registers its own workout for the session, typed from the exercise (Outdoor Walk), through `HKWorkoutSession` (`HealthKitWorkoutStore.begin`).
- When the wrist ends the session, `WatchSessionAdoptionBridge.onLifecycle` ends the phone's copy through the ordinary finish (`watch_session_adoption_bridge.dart:770`, `target.endSession()`), and that finish writes a second workout from the phone (`session_core_lifecycle.dart:52`, `HealthSyncService.onSessionCompleted`), typed from the modality. A Free session has no modality and cardio has no finer type, so it is written as the generic "Other" (`health_modality_mapper.dart`, `pluginActivityTypeFor`).
- Same shape, other direction: a session the phone starts and ends while the wrist follows it also gets a wrist workout (the wrist saves one when the phone's `completed` reaches it) plus the phone's own write-back.

Acceptance: (1) a session the wrist ended leaves exactly one workout in Fitness, the watch's, with the watch's type; (2) a phone-only session (no watch involved) still gets its phone write-back, unchanged; (3) a phone-ended session that the wrist is following leaves one workout, not two (see D-2: only if the phone can know; otherwise this item is reported, not guessed); (4) the "Write workouts" setting, the ledger and the delete-on-discard of plan 89 are unchanged for every session the phone does write.

## Decision Ledger

- D-1 The wrist's end does not write. `WatchSessionAdoptionBridge.onLifecycle` ends the session with a flag that skips the Health write-back: `WorkoutState.endSession({bool writeToHealth = true})` and the same parameter through `SessionCore.endSession`; the bridge's `completed` branch passes `false`. Every other caller keeps the default (`true`). The skipped session is NOT put in the written ledger (it was not written by the phone) - plan 89's `onSessionDeleted` therefore still tries a phone-side delete for it, which finds nothing and is harmless.
- D-2 The phone-ended, wrist-following case. Read what `LiveSessionMirrorState` knows at the moment the phone ends a session (does it hold the wrist's session id and an `active` status for the same session id?). If it does, the phone's end skips the write-back when the wrist holds that same session active, reachable or not (a queued `completed` still reaches the wrist and saves its workout). If it does not hold that, do nothing for this case and report it as an open item for 89c2; never infer it from the setting alone.
- D-3 Known cost, accepted: if the wrist could not register its workout (no Health access on the watch, `lastBeginFailed`), a wrist-ended session leaves nothing in Fitness at all. Today the phone's "Other" copy would have covered it. A `healthWorkoutSaved` flag on the wrist's `session_end` would close it, but it is a wire change (schema, fixtures, both validators): out of scope, recorded for 89c2.
- D-4 The phone's "Other" type for cardio and Free sessions is not changed here; with one writer per session it no longer collides.
- D-5 Out of scope: deleting the watch's workout when a session is deleted (89c2); the wire protocol; the watch's own workout registration; sessions already in Fitness.

## Scenarios

- S-89c1-1 Adoption bridge, wrist `completed` for the held session: the session ends (row has `endedAtMs`), the Health platform fake sees NO `writeWorkout`, and the written ledger does not contain the id. Red today (it writes).
- S-89c1-2 Adoption bridge, wrist `abandoned`: still discards the session, still writes nothing (unchanged, pinned).
- S-89c1-3 A phone-only session ended by the phone's own End button: exactly one `writeWorkout`, as today (unchanged, pinned). With the setting off: none.
- S-89c1-4 (D-2, only if the mirror exposes it) the phone ends session X while the mirror shows the wrist holding X active: no `writeWorkout`; while the wrist holds a different session or none: one `writeWorkout`. Fixture: the wrist holds X but the phone ends Y - Y writes.
- S-89c1-5 Replay safety: the wrist's `completed` arrives twice, or after the phone already ended the session: the second one writes nothing and ends nothing (existing `held.endedAtMs != null` guard, pinned).
- S-89c1-6 Watch side (one Swift test, no production change expected): a Free session started on the wrist whose first exercise is a walk calls the platform store's `begin` once, with the walking type and `outdoors == true`, and one saving `end` when completed - never two begins. If this fails, the duplicate is also on the wrist and the phase stops and reports.
- S-89c1-7 Device check (owner, QA doc): start a Free outdoor walk on the watch, finish it on the watch: Fitness shows ONE workout, "Outdoor Walk". Then open the Health app, Browse, Activity, Workouts, and look at the "Source" of each entry on any earlier duplicate pair: the "Other" one should be sourced to the phone app, which confirms the cause.

Mutation checks (developer records): bridge passes `true` again (S-89c1-1 must fail); the flag defaults to `false` (S-89c1-3 must fail).

## Phase 1 (single)

1. `endSession({writeToHealth})` through `WorkoutState` and `SessionCore` (`workout_state.dart:179`, `session_core.dart`, `session_core_lifecycle.dart`); the bridge passes `false` on `completed`.
2. D-2: read the mirror; implement only if it exposes the wrist's held session id and status; otherwise record the finding in the evidence file and leave S-89c1-4 out.
3. Tests S-89c1-1..6; docs: the Health write-back paragraph of `docs/theme_and_settings.md` and the `endSession` row of `docs/state_management/workout_state.md` (net-zero where near the ceiling, `wc -c`); S-89c1-7 as a QA step (placed by the governor).

Done: `flutter test` on the touched files, `flutter test test/ui_standards_contract_test.dart test/docs_indexing_contract_test.dart`, `flutter analyze` issue count equal to the baseline (180 at plan 89), `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` empty, then the full `flutter test` (900 s) and `swift-test` in `watch/watchos`.

Predicted files: `lib/state/workout/workout_state.dart`, `session_core.dart`, `session_core_lifecycle.dart`, `lib/state/watch/watch_session_adoption_bridge.dart`, tests under `test/` (health platform, adoption bridge) and one Swift test, the two docs above, this plan + evidence.

## Progress

Evidence: `2026-10-28-89c1-one-workout-per-session-plan.evidence.md`.

- [x] 1. `WorkoutState.endSession({writeToHealth = true})` -> `SessionCore.endSession({required writeToHealth})`; the bridge's `completed` passes `false`. S-89c1-1 red then green; M1, M2b killed.
- [x] 2. D-2: the mirror exposes the wrist's session id and status, so it is built as `LiveSessionMirrorState.wristRunsSession` and injected into `WorkoutState` from `main.dart`. S-89c1-4 red then green; limits L-1..L-3 are in the evidence.
- [x] 3. Tests S-89c1-1..6 green (S-89c1-6 Swift, no production change; W1 killed); docs updated; S-89c1-7 QA text is at the end of the evidence file.
- [x] Done checks: touched files +238, contracts +42, analyze 180, grep empty, swift 1141/0. The full suite is +5784 -29; all 29 belong to another session's concurrent adoption change (evidence).

**Phase 1: Complete** (the plan's own items). The full suite is not green until the concurrent `seedFirstEntry` work lands or is fixed.

## Assumption Log

- The duplicate is the phone write-back, not two watch workouts: inferred from the type pair (watch types a walk as Outdoor Walk; the phone has no finer type than Other for cardio and Free). S-89c1-6 and S-89c1-7 settle it.
- A wrist `completed` always means the wrist registered a workout. False when the wrist's Health registration failed (D-3).
- D-2 also requires at least one exercise in the mirror's ladder: without one the wrist has no workout open (S-8807), so the phone keeps writing. Options: id+active only, or id+active+ladder. The ladder clause errs toward today's behaviour.
- `SessionCore.endSession` takes `writeToHealth` as `required`, so the only default is `WorkoutState`'s (mutation M2a survived the double default). The predicate is injected through the constructor from `main.dart` (a file not in the plan's prediction).
