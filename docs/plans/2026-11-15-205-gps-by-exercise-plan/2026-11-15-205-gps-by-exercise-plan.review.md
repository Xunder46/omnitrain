# Review: 205 + 206 · phases P1/P2 of both plans · base 7664f126..working tree
Verdict: APPROVE WITH FIXES
Counts: blocker 0 · major 1 · minor 1 · tests: not re-run (governor already ran: Swift whole package 1559 tests 0 failures; Flutter 7712 passed 4 skipped 0 failed)
Diff vs Predicted Files: conforms for the in-scope set (WatchPlatformWorkout.swift, WatchLoggingState.swift, WatchStartPaths.swift, watch_sensor_recording.dart, watch_platform_workout.dart, watch_sensor_contract.json, WatchGpsExerciseOnlyTests, WatchModalityKindTests, the eight rewritten Swift pin files, the three rewritten Dart pin files, watch_wrist_declared_kind_test.dart). Other files in the working diff belong to plans 201–204 and to other sessions' stats/diagnostics work; out of scope per the brief.

## Findings
1. [Major] `watch/watchos/Sources/WatchSessionEngine/WatchSensorRecording.swift:170-173` — the `start(_:)` doc comment still says "Location is recorded only where the modality, or the exercise the user is on, can cover distance". Plan 205 D-20501 deleted the modality arm of `WatchGpsPolicy.isRequired(_ session:)`, so the comment's modality half is now false: a maintainer reading it could treat the deleted rule as intended and restore it (the comment is the only remaining statement of it in Sources). Fix: one comment line — "Location is recorded only when the exercise the user is on covers `distance` (plan 205)". Guard: none needed (comment-only); the invariant is held by `WatchGpsExerciseOnlyTests.testS20501BoxingUnderSportsIsIndoor`.
2. [Minor] `ios/OmniTrain Watch App/HealthKitWorkoutStore.swift:132-134` — the `begin(_:outdoors:)` doc comment still says "a modality that measures distance registers as `.outdoor`". The diff changed the caller (`WatchPlatformWorkout.swift:392` now passes `WatchGpsPolicy.isRequired(session)`, exercise-based), so the comment states the old rule. Fix: reword to "the caller decides; it passes whether the first exercise covers distance (plan 205)". Guard: none needed (comment-only).

## Q1 — remaining readers assuming the modality turns GPS on / marks outdoor
Verdict: OK.
Every production reader of the changed surface now reads the exercise:
- `WatchPlatformWorkout.swift:392` `outdoors: WatchGpsPolicy.isRequired(session)` — begin-time, first exercise (D-20502).
- `WatchSensorRecording.swift:196` `guard WatchGpsPolicy.isRequired(session)` — exercise-based; `sessionChanged` at :189 re-evaluates for the late start (S-20507).
- `WatchLoggingState.swift:442` `coversDistance(capabilities)` — the "No distance" notice, already exercise-based.
- Dart twin: `lib/watch/sensors/watch_sensor_recording.dart:138` (exercise capabilities); `lib/watch/sensors/watch_platform_workout.dart:286` (forActivityType, capability-based, unchanged).
- `ios/OmniTrain Watch App/`: no reader of `WatchGpsPolicy`/`isRequired`/`capabilitiesByModality` (grep over the app target returned none). `HealthKitWorkoutStore` only consumes the `outdoors` bool; `ContentView`/`CoreLocationRawSource`/`HealthKitSensorFeed` carry no modality→GPS logic.
- `WatchSensorCoordinator`: no GPS/modality match at all.
- Phone `lib/`: no other `isRequired`/modality-GPS reader (grep over `lib/**`); the deleted symbols have no remaining callers in `lib/` or `watch/watchos/Sources`.
The only stale statements are the two comments in the Findings; `capabilitiesByModality` is gone from code (only unrelated test-source-scan pins over the app target remain).

## Q2 — distance arriving for a workout registered indoors
Verdict: OK.
- `WatchRouteKeeper` (`watch/watchos/Sources/WatchSessionEngine/WatchRouteKeeper.swift`) takes only `routeSharingAllowed` and `beganAt`; its verdict is two points ≥ 50 m apart. No outdoor precondition; the outdoors verdict never reaches it (pinned by `WatchRouteSourceTests` S-10606).
- `HealthKitWorkoutStore.openRoute` opens a route for every workout while route sharing is allowed, on the builder — independent of `locationType`. `configuration.locationType = outdoors ? .outdoor : .unknown` (line 155) is metadata only; `HKLiveWorkoutDataSource` enables `distanceWalkingRunning` regardless of the flag.
- A late `startLocationIfNeeded` (Swift) / none in the twin (documented D-20504 harness limit) is the only path a distance fix needs; both are outdoor-flag-blind.
No code misbehaves when a run is logged into a workout registered indoors; the distance row is honest (S-3219-style exclusion is by effort kind, not by the outdoor flag).

## Q3 — `toSlot(` callers in `watch/watchos/Sources`
Verdict: OK.
Three call sites add an exercise to a live session; each declares the right kind:
- `WatchStartPaths.swift:804` (`startModalityWorkout` create path): `effortKind: WatchEffortKind.forModality(modality)` — the tapped modality.
- `WatchStartPaths.swift:838` (`addExerciseToSession`): `effortKind ?? forModality(engine.session?.modality)` — D-20603.
- `WatchStartPaths.swift:903` (`addExerciseToEnd`): `forModality(engine.session?.modality)`.
- `WatchRoutineRecords.swift:251` (`WatchRoutineEffort.slot`) is unchanged and correctly passes the routine's own declared kind — a routine's own slots were not re-kinded (D-20603's competition rule, S-20608).
- No engine/phone-push path calls `toSlot` (grep over Sources found only the definition, `WatchRoutineEffort.slot`, and the three start-path sites); pushed slots arrive as dictionaries already declared by the phone's projection.
No call was wrongly changed.

## Q4 — callers of `addExerciseToSession` / `addExerciseToEnd` vs the phone
Verdict: OK.
Callers: `WatchMenu.swift:337` (Add Exercise → `addExerciseToEnd`), `WatchStartPaths.swift:921` (`selectExercise` .available → `addExerciseToSession`), and `startModalityWorkout`'s held-session branch (`:799`, D-20105/D-20606, passes the tapped modality's kind explicitly). Every implicit kind comes from `engine.session?.modality` through the new table; a routine session starts with `modality: routine.startModality` (`WatchStartPaths.swift:725`), so an added exercise takes the Focus's kind, matching the phone.
The tables agree: `WatchEffortKind.forModality` (`WatchLoggingState.swift:84-93`) and `ModalityConfig.effortKind` (`lib/core/constants/modality_config.dart:62, 80, 98, 116`) both map cardio_endurance→timed, resistance_lifting→set, isometric_stretching→drill, sports→round. No caller contradicts what the phone would declare for the same exercise in the same session; D-20606's tapped-kind-over-held-session case is pinned by S-20609.

## Q5 — the five fixture fixes kept their intent
Verdict: OK.
- `WatchEffortDistanceTests` S-3219 (`:417-447`): fixture Plank gains `distance` so the wrist is measuring, as the test name says ("while measuring"); assertions unchanged (effortKind drill, no distanceMeters/distanceSource in the log, no rejections). Intent kept, now stronger.
- `WatchGpsDistanceTileTests` S-16008 (`:319-336`): fixture becomes Run then Row with a `selectExercise`; the "no distance → no tile" assertion (`fields.map(\.metricKey) == []`) is unchanged and now also holds while the GPS feed is latched on. Intent kept, strengthened.
- `WatchSnapshotFocusTests` S-12593 (`:85-90, 350-360`): the `gps` column flips true→false for cardio_endurance and sports with the test names renamed Outdoors→Indoors; Health kind and round word unchanged. This is the plan's documented change (plan 205's impact table lists S-12593 as rewritten), not a weakening.
- `WatchSensorCoordinatorTests` S-3104 (`:427-440`): fixture `sx-bench` gains `distance` so the location probe is asked at all; the "asked once, logging unaffected" assertions are unchanged. The comment's claim that the logger stays a set is verified in code: `precedence = ["hold", "rounds", "reps", "sets", "load", "time", "distance"]` (`WatchLoggingState.swift:55`) — reps precedes distance.
- `WatchGpsByExerciseTests` S-4806 (`:459-477`): renamed and inverted ("a distance modality alone starts no GPS", 0 subscriptions, `isMeasuringDistance` false). Deliberate: the plan's impact table names this test as rewritten and S-20501/S-20508 hold the new answer. Not a weakening.
None of the five lost its protection.

## Docs delta (plan 205)
- docs/state_management/watch_sensors.md `to a distance modality…` MODIFIED -> applied
- docs/state_management/watch_sensors.md `GPS activation derives from the modality's capability profile…` MODIFIED -> applied
- docs/state_management/watch_sensors.md `reading the modality's capability profile and the current…` MODIFIED -> applied
- docs/my_routines.md `registers as Running with GPS on` MODIFIED -> applied
- docs/distance_source.md `when the session's modality or the exercise…` MODIFIED -> applied
- docs/watch-app-qa-wrist-logging.md Cardio-Focus-squats line MODIFIED -> applied
- docs/watch-app-qa-wrist-logging.md Sports-"Periods" line MODIFIED -> applied
- docs/watch-app-qa-wrist-logging.md `**GPS follows the exercise — (owner, plan 205).**` ADDED -> applied
Doc edits the table does not name: `docs/distance_source.md` and `docs/state_management/watch_sensors.md` also swap the renamed `testS3300OutdoorsFollowsTheCapabilityProfile` for `WatchGpsExerciseOnlyTests.testS20502AWalkUnderCardioIsOutdoor` — the rename consequence of the same change, correct. Every test name I checked in these docs exists (`WatchGpsExerciseOnlyTests` S-20501/S-20502/S-20503/S-20504/S-20505/S-20507, `testS4806ADistanceModalityAloneStartsNoGps`, `testS12593ASportsFocusOpensOtherIndoorsPeriods`, `testS12571CardioFocusOverStrengthExercisesStaysRunning`).

## Docs delta (plan 206)
- docs/state_management/watch_surface_wrist.md `the slot keeps the exercise's own capabilities and Health kind` MODIFIED -> applied
- docs/modality_tracking.md ADDED `a slot the watch creates under a modality declares that modality's kind` -> applied
- docs/watch-app-qa-wrist-logging.md ADDED `**The watch logs by the modality — (owner, plan 206).**` -> applied
Doc edits the table does not name: `docs/state_management/watch_surface_wrist.md:255` and `docs/watch-app-qa-wrist-logging.md` swap `testS17605ASecondPickReturnsTheHeldSessionAndEmitsNothing` for `…AndAddsThePick` — plan 201's rename flowing through the same paragraph; the renamed test exists (`WatchModalityStartTests.swift:227`). All `WatchModalityKindTests` names quoted in the docs exist.

## Assumption Log rulings
- 205 A-1 (architect step skipped): ratify — the seed named files, symbols and fixtures and all were found as stated.
- 205 A-2 (owner to confirm: no Sports GPS; bike/treadmill stay GPS): the code and the pins match the owner's stated decision (S-20503, S-20505, QA item 50); ratify as owner-approved.
- 206 A-1 (architect step skipped): ratify, same reason.
- 206 A-2 (Plank logs as reps under Resistance; reps-only logs as time under Cardio): matches `forModality` + D-20604's declared-kind-wins rule; S-20602 pins both; ratify as owner-approved.
- 206 A-3 (pre-update running session keeps capability-resolved slots): code does no migration; the QA doc states it (item 51, "already running before the update keeps its old screens"); ratify.

## Scenario coverage
S-20501 → WatchGpsExerciseOnlyTests.testS20501BoxingUnderSportsIsIndoor
S-20502 → WatchGpsExerciseOnlyTests.testS20502AWalkUnderCardioIsOutdoor
S-20503 → WatchGpsExerciseOnlyTests.testS20503AStationaryBikeUnderCardioStaysGpsUntilAnIndoorFlagExists
S-20504 → WatchGpsExerciseOnlyTests.testS20504ACardioFocusRoutineOfSquatsAsksForNoGps (+ WatchRoutineFocusTests S-12571)
S-20505 → WatchGpsExerciseOnlyTests.testS20505ASportsExerciseWithoutDistanceIsIndoor
S-20506 → WatchGpsExerciseOnlyTests.testS20506AFreeWorkoutDecidesByTheExerciseExactlyAsBefore
S-20507 → WatchGpsExerciseOnlyTests.testS20507CardioOnJumpRopeThenTheRunStartsLocationLate
S-20508 → WatchSensorRecordingTests.testS20508TheContractNamesNoModalityForGps (+ Dart S-008 group)
S-20509 → test/watch_sensor_recording_test.dart S-20509 (jump rope / run / sports)
S-20601 → WatchModalityKindTests.testS20601ACardioPickWithSetsAndTimeDeclaresTimed
S-20602 → WatchModalityKindTests.testS20602EveryModalityDeclaresItsOwnKind
S-20603 → WatchModalityKindTests.testS20603AFreeSessionSlotDeclaresNothing
S-20604 → WatchModalityKindTests.testS20604AnExerciseAddedToAModalitySessionDeclaresTheModalitysKind
S-20605 → WatchModalityKindTests.testS20605TheRestLabelsAndTheScreenReadTheSameDeclaredKind
S-20606 → test/watch_wrist_declared_kind_test.dart (three tests: declared timed; no declared kind; declared drill and round)
S-20607 → WatchModalityKindTests.testS20607ForModalityMapsTheFourKeysAndNothingElse
S-20608 → WatchModalityKindTests.testS20608ARoutinesOwnSlotKeepsItsKindAndAnAddedOneTakesTheFocus
S-20609 → WatchModalityKindTests.testS20609AModalityPickOverAHeldSessionWithNoModalityDeclaresTheTappedKind
No MISSING rows.
