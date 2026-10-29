# Plan 89: Apple Fitness workouts follow the session (discard, force-quit, delete)

> Status: BUILT 2026-10-28 (Phases 1-3), uncommitted; governor re-ran watch tests (1140/0) and the watchOS build (succeeded); real-watch checks S-89-6 owed. Open: O-1, O-2, W-1, W-2. Three phases, one commit each; Phase 3 can ship as its own PR (89b) if Phases 1-2 land first. Open owner questions are marked OQ; each has a recommended default the build uses unless the owner says otherwise.

## Goal and acceptance

Owner report (2026-10-28, real watch): (a) after a workout was started and the watch app force-quit, the green heart-rate light kept reading; (b) Apple Fitness holds workouts for test sessions that were later removed in OmniTrain. Causes, read from source (not yet reproduced on the device):

- `HealthKitWorkoutStore.end()` always calls `finishWorkout()` (`ios/OmniTrain Watch App/HealthKitWorkoutStore.swift:215`); the lifecycle ends the workout for every non-active status (`WatchWorkoutLifecycle.action`, `WatchPlatformWorkout.swift`), so an abandoned or deleted session is saved to Fitness exactly like a finished one. There is no discard path anywhere (`grep discardWorkout` is empty).
- Deleting a session on the phone (Session Summary "Discard session?", also reached from the calendar's day list) removes only the Hive row (`SessionCoreLifecycle.discardCurrentSession`, `session_core_lifecycle.dart:106`); nothing touches Health. The phone's own write-back (`HealthSyncService.onSessionCompleted`) keeps only a ledger of session ids, no workout identifier.
- The watch cleans up an unfinished workout only from `ContentView`'s launch task (`ContentView.swift:325`, `recoverInProgress`). There is no `handleActiveWorkoutRecovery` hook, so if the system relaunches the app in the background after a force-quit, nothing ends the workout, and the sensor stays on until the user opens the app.

Acceptance: (1) a session abandoned or removed while it is still running leaves no workout in Fitness and the sensor stops; (2) a session finished normally still saves exactly as today; (3) force-quitting the watch app mid-session stops the sensor without the user reopening the app (OQ-1 says what happens to the workout); (4) deleting a finished session on the phone also removes its workout(s) from Fitness, when the phone holds permission to write workouts; (5) nothing else in Fitness (other apps' workouts, other OmniTrain sessions) is ever deleted.

## Open owner questions (defaults in bold)

- OQ-1 Force-quit while a session is still active: **keep the workout up to that moment and start a new one when the app is reopened and the session carries on** (two Fitness entries for one session), or throw the partial workout away and let the reopened app start one workout from then.
- OQ-2 Deleting a session on the phone when the phone has no permission to write workouts (the "Write workouts" setting was never switched on): **leave the Fitness workout and say nothing**, or ask the watch to delete it (a wire-protocol change, a separate plan).

## Decision Ledger

- D-1 One seam, two endings. `WatchPlatformWorkoutStore` gets `end(saving: Bool)`; `end()` stays as `end(saving: true)`. `HealthKitWorkoutStore` with `saving == false` ends the session, ends collection and calls `discardWorkout()` instead of `finishWorkout()`; the route recorder finishes with `workout: nil` (verify in Phase 1 that a nil workout drops the route and keeps nothing).
- D-2 Who decides. `WatchWorkoutCoordinator.apply` passes `saving = (session?.status == WatchSessionStatus.completed)`: `completed` saves, `abandoned` and a vanished session (`nil`) discard. A session that is replaced by another id (the existing end-then-start branch) saves only if the old session had completed, which is unknown there, so it discards. `WatchPlatformWorkout.end` takes the flag through.
- D-3 Recovery at relaunch. Add a `WKApplicationDelegate` through `@WKApplicationDelegateAdaptor` on the watch app, implementing `handleActiveWorkoutRecovery()`; it calls the same `WatchWorkoutCoordinator.recoverInProgress()` the launch task calls. `recoverInProgress` ends the recovered workout per OQ-1: it asks the engine whether the persisted session is still active; active saves (default), anything else discards. The sensor feed stops with the workout (`refreshHeartRate(from: nil)` already does).
- D-4 Phone delete of the Fitness workout. `HealthPlatformService` gets `deleteWorkouts(start, end)`; the io gateway calls the health plugin's `delete(type: WORKOUT, startTime, endTime)` (`health` 13.3.1, `health_plugin.dart:652`); the web/no-op gateway returns false. `HealthSyncService.onSessionDeleted(TrainingSession)` calls it for the session's span and removes the ledger entry; `SessionCoreLifecycle.discardCurrentSession` calls it (best-effort, never throws, never blocks the discard), mirroring `onSessionCompleted` at `session_core_lifecycle.dart:52`.
- D-5 Safety of the delete window. HealthKit lets an app delete only what it saved itself, which bounds the damage; inside that, the window is exactly the session's `[startedAtMs, endedAtMs]` and only workouts that lie inside it. Phase 3 first reads the plugin's native predicate (`health` iOS source) and the fixture below proves two back-to-back sessions cannot delete each other. If the plugin's predicate is an overlap rather than containment, Phase 3 stops and the fallback is a small native Runner method that deletes by `HKMetadataKeyExternalUUID` = session id, with the watch builder stamping that metadata (`addMetadata`) - a larger change, replanned as 89c.
- D-6 Out of scope: workouts other apps wrote; sessions finished before this plan (their workouts stay unless the user deletes them in Health); the dangling-session cleanup at startup (`checkForInProgressSession`) - those never completed, so the phone never wrote them; the question whether a session run on the watch is written twice (watch workout plus phone write-back) - Phase 3 only checks and reports it.

## Scenarios

- S-89-1 Coordinator: a session that goes `active` then `abandoned` ends the store with `saving == false`; `active` then `completed` ends with `saving == true`; `active` then `nil` ends with `saving == false`; a replaced session id ends the old workout with `saving == false`. Fake store records the flag. Red today (no flag).
- S-89-2 Recovery: with a stranded workout and an active persisted session, recovery ends with `saving == true` (OQ-1 default); with an abandoned or missing session, `saving == false`; with nothing stranded, no store call.
- S-89-3 Structure (source scan, the pattern of `WatchPersonalBestsWiringSourceTests`): the watch app declares a `WKApplicationDelegate` implementing `handleActiveWorkoutRecovery`; `HealthKitWorkoutStore.swift` contains `discardWorkout` and `finishWorkout` once each; `finishWorkout` is only reachable when saving. Must fail on the base commit.
- S-89-4 Phone: discarding a session whose id is in the ledger calls `deleteWorkouts(start, end)` once with the session's span and drops the ledger entry; discarding one that was never written still calls it (a watch-saved workout has no ledger entry); a platform that returns false or throws leaves the discard successful; with the write toggle off nothing is called. Fake `HealthPlatformService`.
- S-89-5 Fixture (adversarial): sessions A 10:00-10:45 and B 10:45-11:30 back to back, both with workouts; deleting B asks for exactly `[10:45, 11:30]` and a fake store that implements the containment rule keeps A's workout; a rolling session spanning a day is passed its own span only.
- S-89-6 Device checks (owner, in QA doc): (a) start, cancel on the wrist: nothing new in Fitness; (b) start, discard on the phone: nothing new in Fitness; (c) finish a short session: one workout; delete it from Session Summary: it leaves Fitness; (d) start, force-quit the watch app: the green light stops within a minute without reopening it (this also shows whether the system relaunches the app at all - if it does not, no app code can stop the sensor and the plan reports that instead of claiming a fix).

Mutation checks (developer records in evidence): always pass `saving: true` (S-89-1 must fail); drop the recovery delegate (S-89-3 must fail); widen the delete window by a minute (S-89-5 must fail); make the phone delete throw (S-89-4 discard must still pass).

## Phase 1 - the wrist discards what is abandoned (D-1, D-2)

1. `end(saving:)` on `WatchPlatformWorkoutStore`, `WatchPlatformWorkout.end`, the coordinator; `HealthKitWorkoutStore` discard branch; confirm the route recorder drops the route for a nil workout.
2. Tests S-89-1, S-89-3 (first half). Done: `bash .github/copilot/scripts/macos/gateway.sh swift-test` green (record count against the 88 baseline of 1127); governor runs the watch `xcodebuild`.

## Phase 2 - force-quit stops the sensor (D-3)

1. `WKApplicationDelegate` with `handleActiveWorkoutRecovery()`; recovery honours OQ-1.
2. Tests S-89-2, S-89-3 (second half). Done: `swift-test` green.

## Phase 3 - deleting a session on the phone removes its Fitness workout (D-4, D-5)

1. Read the `health` plugin's iOS delete predicate first (D-5); stop and replan if it is overlap.
2. `deleteWorkouts` on the platform service and both gateways; `HealthSyncService.onSessionDeleted`; the call from `discardCurrentSession`; check and report the double-write question (D-6).
3. Tests S-89-4, S-89-5. Done: `flutter test test/health_sync_service_test.dart test/ui_standards_contract_test.dart test/docs_indexing_contract_test.dart` green (use the real test file names found in `test/`), `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` empty.

Docs (each phase, net-zero where a file is near its ceiling): `docs/state_management/watch_sensors.md` (the workout is discarded, not saved, when the session is not completed; recovery hook), `docs/watch_session_sync.md` (what abandon does to the Fitness workout), the Health write-back paragraph of `docs/theme_and_settings.md` (delete follows discard), and QA steps for S-89-6 in `docs/watch-app-qa-wrist-logging.md` (check byte sizes with `wc -c`; it is near the 64 KiB ceiling).

Predicted files: `HealthKitWorkoutStore.swift`, the watch app entry file, `WatchPlatformWorkout.swift`, `health_platform_service.dart`, `health_platform_gateway_io.dart`, `health_sync_service.dart`, `session_core_lifecycle.dart`, new/updated tests, the four docs above, this plan + evidence.

## Progress

**Phase 1 - Complete** (watch `xcodebuild` still owed by the governor)
- [x] `end(saving:)` seam, platform, coordinator, HealthKit discard branch; route recorder: live route already discarded on nil, recovered route now discarded too.
- [x] S-89-1, S-89-3 (store half): red 10/13 new on seams, green; `swift-test` 1140/0 (baseline 1127).

**Phase 2 - Complete** (watch `xcodebuild` still owed by the governor)
- [x] `WatchAppDelegate.handleActiveWorkoutRecovery` -> `host.recoverStrandedWorkout()` (also the launch path); recovery saves only an active stored session.
- [x] S-89-2, S-89-3 (delegate half): green; mutations always-save, recovery-always-saves, no-delegate all red then restored. Evidence: `.evidence.md`.

**Phase 3 - Complete** (phone track; owner device check S-89-6(b)/(c) owed)
- [x] D-5: plugin predicate is start-in-window `[start, end)`, own source only - not overlap; back-to-back neighbours safe. Built as planned.
- [x] `deleteWorkouts` (interface, no-op false, io via `Health().delete`), `HealthSyncService.onSessionDeleted`, un-awaited call from `discardCurrentSession`.
- [x] D-6 checked: yes, two Fitness entries when Write workouts is on and the phone holds the session at its end (evidence).
- [x] S-89-4, S-89-5: 11 tests red 9/11 then green; mutations M1-M6 red then restored; full suite 5800/0 (2 skipped); analyze 180 = baseline.

## Assumption Log

- The watch app and the phone app count as one source for HealthKit, so the phone can delete a workout the watch saved. This is the usual HealthKit behaviour but is not proven here; S-89-6(c) is the proof, and OQ-2 covers the case where it does not hold.
- A force-quit app is relaunched by the system to recover a running workout. Not proven; S-89-6(d) decides it (see D-3).
- W-1 (Phases 1-2) Replaced workouts also discard on the two defensive paths (`WatchPlatformWorkout.start`, `HealthKitWorkoutStore.begin`), per D-2. Options: keep saving there. Why: one rule for "replaced".
- W-2 Recovery reads the persisted session through a new `WatchSessionEngine.storedSession()` (no restore) passed to `recoverInProgress(storedSession:)`; the app delegate now owns the one `WatchAppHost` (was `@StateObject`). Why: recovery must run before `restore()`.
- W-3 `HealthKitRouteRecorder.finishRecovered` now discards a recovered route when no workout was saved (it was left unfinished). `WatchSessionSensors` (not used by the app) keeps saving.
- P-1 (Phase 3) The plugin's iOS delete filters by `HKSource.default()` (the phone app), so it cannot select a workout the watch app saved: the first entry above does not hold for this path. Phone delete reaches only phone-written workouts; S-89-6(c) on a watch-run session should confirm.
- P-2 Discarding a session still in progress asks nothing of Health (the phone never wrote it; the wrist discards its own on abandon). Options: delete `[start, now)`. Why: D-6, no phone write exists.
- P-3 The delete is not awaited (the plan said "mirroring" an awaited call); the ledger entry is dropped whatever the store answers. The S-89-5 fake applies the observed start-in-window rule, not "containment". Why: never block the discard; the real rule is the one that catches a widened end.
- W-4 Per D-3, a stranded workout whose stored session is `completed` (killed between Finish and the save) is discarded. If the system relaunch also builds the view, an active session reopens a workout at once (OQ-1); S-89-6(d) shows it.

## Open Items

- O-1 (Phase 3) Deleting a watch-run session on the phone leaves the watch-saved Fitness workout (P-1). Reaching it needs a native delete by `HKMetadataKeyExternalUUID` or a wrist-side delete: owner product call, separate plan (89c).
- O-2 D-6: with Write workouts on, a session the phone holds while the watch also runs it lands in Fitness twice. Owner product call; not fixed here.
