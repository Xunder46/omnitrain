# Feature: 58 — the watch saves the Health workout as Strength Training / Running, with calories

> Status: BUILT, PROVED, DOCUMENTED AND REVIEWED 2026-10-23 (uncommitted; evidence and review beside the plan; owner device checks open, QA step 25). Owner: watch audit 3 (2026-10-23), fix order item 3, in chat. Series: 58 (this), 59 (Health and location access asked up front, denial visible), 60 (failed routine start and phone-link notices) — 59 and 60 are planned separately against the code as it is by then. Base commit: `.work/2026-10-23-58/base.txt`. Working branch: the one checked out; never create or switch branches. Binding conventions: docs/global_conventions.md; .github/copilot/pr-scope-budget.md.

## Goal and acceptance

Owner decision (chat, 2026-10-23): the type is decided by the **majority** of the session's exercises.

| What you do | Now | After 58 |
|---|---|---|
| Start a routine of lifts (sets, reps, load) on the watch and finish it | Apple Health shows the workout as **Other** | shows **Strength Training** |
| Start a routine of distance exercises (time + distance) | **Other** | **Running** |
| Start a routine of holds (hold + time) | **Other** | **Flexibility** (the type the older modalities already used) |
| Routine with 3 lifts and 2 runs; or 2 runs and 1 lift | Other | Strength Training; Running (majority wins; a tie goes to the type of the earliest exercise) |
| Free workout: tap Free workout, pick the first exercise | Health workout opens the moment you tap Start, as Other | the Health workout opens the moment you pick the first exercise (a few seconds later) and is typed from it; **a Free workout cannot use the majority**, because Health fixes the type when the workout opens; later exercises never change it |
| Free workout: tap Start, close the picker without picking | (plan 57 cancels it) | no Health workout was ever opened |
| Finish a workout | no calories saved; the Move ring gets nothing from the watch workout | active calories are saved with the workout and count for the Move ring |
| First workout after updating | Health asks for heart rate and steps | the same sheet also lists active energy (one extra line) |
| A phone-started session (it arrives with its exercises) | Other | typed by the same majority rule |

Not in this plan: exercises that carry no modality can only be told apart by capabilities, so a cycling or rowing exercise that has a distance field saves as Running (Health type "Cycling" needs a modality or a name the wrist does not have). Dart wrist engine in `lib/watch` is not changed (drift parked, audit item 13). Owner check on a real watch: the Move ring credit and the type shown in the Health app (the simulator cannot show either).

## Decision Ledger

- D-1 `watch/watchos/Sources/WatchSessionEngine/WatchPlatformWorkout.swift`, `enum WatchActivityTypes` (current l.53-100). Add, beside `forModality`: `public static func forExercise(capabilities: [String]) -> WatchActivityType` — `hold` → flexibility (`byModality["isometric_stretching"]` values: watchOs `flexibility`, wear `exercise_type_flexibility`); else `WatchGpsPolicy.distanceCapability` → running (`running`, `exercise_type_running`); else any of `reps`/`sets`/`load` → strength (`traditionalStrengthTraining`, `exercise_type_strength_training`); else `generic`. Hold is tested first because a plank is `hold`+`sets`. Define the three non-generic types once as private static lets and use them in the new functions only (leave `byModality` literal values as they are: the contract test S-007 pins them).
- D-2 Same enum: `public static func forExercises(_ exercises: [[String: Any]]) -> WatchActivityType?` — nil for an empty list; otherwise map each exercise's `exercise["capabilities"] as? [String] ?? []` through D-1, count per `watchOs` name, take the highest count, ties go to the type of the earliest exercise that reaches that count (`types.first { counts[$0.watchOs] == best }`). And `public static func forSession(_ session: WatchSessionRecord) -> WatchActivityType?` — `session.modality` non-nil → `forModality(modality)` (unchanged behaviour, includes the unmapped → generic fallback); nil → `forExercises(session.exercises)`. Nil means "not yet known". New names avoid the append-only guard's banned verbs (`set…`, `update`, …).
- D-3 `WatchPlatformWorkout.start` (current l.213-223: `let activityType = WatchActivityTypes.forModality(session.modality)`) becomes `WatchActivityTypes.forSession(session) ?? WatchActivityTypes.generic`. `WatchPlatformWorkout.start` stays callable directly (GPS tests do).
- D-4 `WatchWorkoutLifecycle.action` (current l.271-279: `if session?.status == WatchSessionStatus.active { return running == nil ? .start : .none }`): an active session whose type is not yet known and with nothing running returns `.none`; every other branch is unchanged. Known = `WatchActivityTypes.forSession(session) != nil`. So a nil-modality empty session waits; the first `insertExercise` bumps the revision, `ContentView.swift` l.~228 (`await self.workout.refresh(self.engine.session)` on every `$revision`) calls `refresh`, and `.start` fires. `WatchWorkoutCoordinator.apply` needs no change (it records `openedForSessionId` only on `.start`). A session whose modality is set (older phone sessions, tests) starts immediately as before.
- D-5 `ios/OmniTrain Watch App/HealthKitWorkoutStore.swift` `resolveAuthorization` (current l.248-251): `toShare: [HKObjectType.workoutType(), HKQuantityType(.activeEnergyBurned)]`, `read: [HKQuantityType(.heartRate), HKQuantityType(.stepCount), HKQuantityType(.activeEnergyBurned)]` — still ONE request with exactly one `read:` list (S-3109 pins that). `begin` (after the `stepCount` enableCollection line, l.116) gains `dataSource.enableCollection(for: HKQuantityType(.activeEnergyBurned), predicate: nil)`. The share status check (`workoutType() == .sharingAuthorized`) stays the gate. Refresh the file header and the `resolveAuthorization` doc comment (they say "Share the workout type; read heart rate and steps").
- D-6 The name table in the store (`activityType(for:)`) already maps every name D-1 produces (`running`, `traditionalStrengthTraining`, `flexibility`, `other`); do not touch it, `testS1509` stays as is.
- D-7 Not done here: asking before the workout (59), distance saved to Health, the Dart twin, contract JSON (`watch_sensor_contract.json` keeps the modality table; the new rule is capability-based and lives only in Swift).

## Readers listed (grep 2026-10-23)

- `forModality(` has one caller (`WatchPlatformWorkout.start`); `WatchWorkoutLifecycle.action` is read by `WatchWorkoutCoordinatorTests.swift` (testS1500, l.~211-216, modality `sports`: keeps starting), `WatchWorkoutCoordinator.apply`.
- Tests that start a workout through a nil-modality session and pin the begun type, which may now see a different name: `WatchGpsByExerciseTests.swift` (l.~165-171 `activityType`, l.212 `traditionalStrengthTraining`), `WatchOutdoorWorkoutTests.swift`, `WatchSensorRecordingTests.swift` (testS001 l.177), `WatchLoggingSurfacesTests.swift` (l.~657), `WatchWorkoutCoordinatorTests.swift`. Rerun all five by name; touch one only where it breaks, and only to follow the new rule.
- Source-text readers of the store: `WatchSensorSourceSourceTests.swift` (S-3109 l.~252 one request / one `read:` list, S-3117 l.~380 the `enableCollection` lines), `WatchWorkoutStoreSourceTests.swift` (S-1509 name table). All additive: they keep passing.
- Scenario ids S-8801..S-8820 checked free (grep `S-88`/`S-89` in `test docs watch lib`, 2026-10-23).

## Core scenarios

New `watch/watchos/Tests/WatchSessionEngineTests/WatchWorkoutTypeFromExercisesTests.swift`, on `Harness` (`WatchSessionEngineTests.swift` l.32; `await harness.runningEngine()`), `ScriptedPlatformStore` (`WatchWorkoutCoordinatorTests.swift` l.45, internal; `store.begun` is its begin list) and a `WatchWorkoutCoordinator(platform: WatchPlatformWorkout(store:))`. Slots are dictionaries with `sessionExerciseId`, `exerciseId`, `name`, `capabilities`; lift = `["reps","sets","load"]`, run = `["time","distance"]`, hold = `["hold","time"]`, timed = `["time"]`. Every scenario fails without the change (the begun type would be `other`, or the free session would begin at once).

- S-8801 `createSession(modality: nil, exercises: [lift])` then `coordinator.refresh(session)`: begun == `["traditionalStrengthTraining"]`.
- S-8802 `[run]` → begun `["running"]`, and the store was told outdoors (use `RecordingGpsOutdoorStore` from `WatchGpsByExerciseTests.swift` if its `begins` carries the flag; else assert only the name).
- S-8803 `[hold]` → `["flexibility"]`; and a plank `["hold","sets"]` → `["flexibility"]` (hold wins over sets).
- S-8804 majority, two cases: `[lift, lift, run]` → strength; `[run, run, lift]` → running (a value unlike the first exercise's type, so a "first exercise decides" mutant fails).
- S-8805 tie, two arms: `[run, lift]` → running; `[lift, run]` → strength.
- S-8806 `[timed]` → `["other"]`; `[timed, lift, lift]` → strength.
- S-8807 Free workout, empty: `createSession(modality: nil)`, `refresh`: begun == `[]`, `platform.running == nil`. Then `engine.insertExercise(lift, moveTo: true)` and `refresh` again: begun == `["traditionalStrengthTraining"]`; a third `refresh` begins nothing more (still one begin).
- S-8808 After S-8807, `insertExercise(run, moveTo: true)` and `refresh`: begun is still one entry, `platform.running?.watchOs` unchanged.
- S-8809 modality wins and still starts at once: `createSession(modality: "sports", exercises: [lift])` → `["other"]`; `createSession(modality: "sports")` with no exercises → begun `["other"]` (as testS1500 today).
- S-8810 pure lifecycle: `action(session: nilModalityEmpty, running: nil) == .none`; `action(session: nilModalityWithLift, running: nil) == .start`; `action(session: nilModalityEmpty, running: WatchActivityTypes.generic) == .none`; `action(session: nil, running: generic) == .end`.
- S-8811 `forExercises([])` is nil; a slot with no `capabilities` key counts as `other`.
- S-8812 (store source guards, in `WatchSensorSourceSourceTests.swift` beside S-3109/S-3117, helper `storeSource()` already there) the one `requestAuthorization` call: its arguments contain `HKQuantityType(.activeEnergyBurned)` in the share part (text before `read:`) AND in the read part; the share part still contains `HKObjectType.workoutType()`; the file contains the exact statement `dataSource.enableCollection(for: HKQuantityType(.activeEnergyBurned), predicate: nil)`. Assert the statements, not a substring of the type name (plan 56 lesson).

## Phases

- P1 `crew-builder-watch` (6 items): D-1..D-4 and `WatchWorkoutTypeFromExercisesTests.swift` (S-8801..S-8811); follow the five readers. Scope: `watch/watchos/Sources/WatchSessionEngine/WatchPlatformWorkout.swift`, `watch/watchos/Tests/WatchSessionEngineTests/WatchWorkoutTypeFromExercisesTests.swift`, `watch/watchos/Tests/WatchSessionEngineTests/WatchGpsByExerciseTests.swift`, `.../WatchOutdoorWorkoutTests.swift`, `.../WatchSensorRecordingTests.swift`, `.../WatchLoggingSurfacesTests.swift`, `.../WatchWorkoutCoordinatorTests.swift`. Brief: "Never run the full `flutter test`", report first as a skeleton, new function names avoid the banned verbs. Done: `swift test --filter WatchWorkoutTypeFromExercisesTests`, `--filter WatchWorkoutCoordinatorTests`, `--filter WatchGpsByExerciseTests`, `--filter WatchOutdoorWorkoutTests`, `--filter WatchSensorRecordingTests`, `--filter WatchLoggingSurfacesTests`, `--filter WatchSessionEngineTests`.
- P2 `crew-builder-watch` (3 items, serial after P1: same Swift package): D-5 and S-8812. Scope: `ios/OmniTrain Watch App/HealthKitWorkoutStore.swift`, `watch/watchos/Tests/WatchSessionEngineTests/WatchSensorSourceSourceTests.swift`. Done: `--filter WatchSensorSourceSourceTests`, `--filter WatchWorkoutStoreSourceTests`. The governor then runs `xcodebuild` (target "OmniTrain Watch App", sdk watchsimulator): HealthKit cannot compile on macOS.
- P3 `crew-docs-keeper` (after P2): `docs/state_management/watch_sensors.md` (the "Modality → platform workout type" row, l.~38, and the workout-opening text), `docs/watch-app-setup-and-qa.md` (QA step: Health shows Strength Training / Running, Move ring credit, owner check on a real watch), any doc sentence that says every wrist workout is "Other" or that the Free workout opens its Health workout at once (grep `docs/` first). Give it the facts in the brief, no `.work/` paths.

## Verify (governor)

`swift test` full in `watch/watchos` (baseline 802 tests, 0 failures); `xcodebuild`; the two UI-standards/docs contract tests; invariant grep; full `flutter test` (Dart is untouched; one run before the review); mutations: (a) majority replaced by "first exercise decides" (S-8804), (b) tie order reversed (S-8805), (c) hold test after `sets` (S-8803), (d) lifecycle `.none` for unknown type removed (S-8807/S-8810), (e) energy removed from share list / read list / `enableCollection` (S-8812, three separate mutants). Simulator: seed a routine of lifts, start it, confirm in the host log which activity type the store was asked for; Free workout: tap Free workout and confirm no workout opens until the first exercise is picked (the log line); calories and Health type are owner checks.

## Progress

All phases done 2026-10-23: see the evidence file. P1 builder (WatchPlatformWorkout, 11 tests), P2 builder (energy), P3 docs, review APPROVE; 13 of 13 lead mutants killed. Deviation from the owner's "majority decides": a Free workout is typed from its first exercise (Health fixes the type at open); stated in the table above.
