# Evidence — plan 40 (watch GPS by exercise)

Baselines, suite outputs, red→green tables and footprints are written here by the implementers, not into the plan.

## Baselines

(not yet recorded)

## Docs keeper — plan 40 (2026-10-18)

Verification facts (from the brief; the code was built and green before docs):

- Swift full suite: 608 tests / 0 failures (`swift test --package-path watch/watchos`).
- Dart: `flutter test test/watch_sensor_recording_test.dart` — 38 / 0.
- Invariant grep over `docs/distance_source.md`, `docs/state_management/watch_surface.md`,
  `docs/state_management.md`, `docs/data_models.md` for "free training / nil modality /
  never records GPS / cannot measure": no match in any of the four. One near-miss fixed:
  `docs/distance_source.md` Vocabulary said the feed is built "when a cardio or sports
  session is allowed to use Location" — reworded to the modality-or-exercise rule
  (`WatchGpsByExerciseTests.testS4800AWalkInAFreeWorkoutStartsGps` added to the citation).
- `flutter analyze`: 181 issues, none in the files this unit touched (docs only).
- The 8 Mix-card tests in `test/mix_layer_screen_test.dart` fail identically at the base
  commit `dc9ada9c` — pre-existing, not from this unit.
- Docs contract: `flutter test test/docs_indexing_contract_test.dart` — 13 / 0 after the edits.

Files changed (docs only):

- `docs/state_management/watch_sensors.md` — GPS table row now names the exercise's
  capabilities; new row for `WatchSensorRecorder.sessionChanged`; the "lifts, holds and
  free training never ask" sentence split (lifts/holds never, free training and routines
  only on a distance exercise); the outdoor-registration sentence carries the
  register-once limit (D-4803); the modality invariant extended to the exercise's
  capabilities; two new invariants (the latch; a refusal asked once per session);
  freshness date 2026-10-18.
- `docs/watch-app-setup-and-qa.md` — step 24 rewritten to the free-workout owner
  walkthrough (Walking, Location question once, metres, Summary DISTANCE with no
  "est.", lift: no question, refuse-once per session, Apple Health lists a generic
  workout). Still marked `(owner)`; nothing here has run on a wrist.
- `docs/distance_source.md` — the one Vocabulary sentence above.

Tests cited (all read in the test files this run): `WatchGpsByExerciseTests`
`testS4800AWalkInAFreeWorkoutStartsGps`, `testS4801ALiftNeverStartsGpsAndNeverAsks`,
`testS4802GpsStartsWhenTheUserReachesTheWalk`,
`testS4803TheFeedStaysOnWhenTheUserMovesBackToALift`,
`testS4804ARefusedSessionIsAskedAboutOnceAndANewOneAgain`,
`testS4805AGrantedWalkSubscribesOnceHoweverOftenTheSensorsRefresh`,
`testS4807TheWorkoutIsRegisteredOutdoorsByTheExerciseTheUserIsOn`,
`testS4814ASecondSessionMeasuresAgain`,
`testS4815UnavailableIsAnsweredOnceLikeDenied`; Dart
`test/watch_sensor_recording_test.dart` `S-4810 the exercise rule answers the
contract's cases`.

Owner device checks (step 24): still unchecked — the walkthrough above is the script
for the first hardware run; no result recorded yet.

## Proof by mutation (governor, 2026-10-18)

Fifteen one-line mutations (prover list, M12 rewritten because the early return made the prover's line unreachable) were applied one at a time, the whole `WatchGpsByExerciseTests` class (and the Dart S-4810 test) run, and the file restored byte for byte (`cmp` against a pristine copy, 0 mismatches). 14 turned red by their named test. M10 (remove `locationAnswered = false` from `stop()`) turned `testS4804ARefusedSessionIsAskedAboutOnceAndANewOneAgain` red but not `testS4814ASecondSessionMeasuresAgain`: its first session is granted, so no refusal latch is set. The behaviour is guarded.

## Governor verification

Full `swift test`: 608 tests, 0 failures (after one fix round: the first full run failed `testS004NoMutatingOperationExistsAnywhereInTheModule` because the new method was named `update`; renamed `sessionChanged`). `flutter test test/watch_sensor_recording_test.dart`: 38 tests, 0 failures. Full `flutter test`: 8 failures, all in `test/mix_layer_screen_test.dart`, identical in a clean checkout of base `dc9ada9c`. `flutter test test/ui_standards_contract_test.dart test/docs_indexing_contract_test.dart`: 42 passed. `xcodebuild -target "OmniTrain Watch App" -sdk watchsimulator build`: BUILD SUCCEEDED (the full scheme build fails earlier on the phone app's missing CocoaPods module `app_settings`, unrelated).
