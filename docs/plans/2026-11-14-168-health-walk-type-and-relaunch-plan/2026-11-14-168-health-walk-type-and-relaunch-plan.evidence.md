# Plan 168 — evidence

Watch walk: one Apple Health workout across a relaunch, typed by its exercise.
Every count below is copied from a gateway run, not reconstructed.

## Baselines (before any change)

| Gate | Baseline |
|---|---|
| `swift-test` (full, `watch/watchos`) | 1436 tests, 0 failures |
| `gateway.sh lint` | 183 issues (all pre-existing info/warning notices; non-zero exit) |

## Phase 1 — the relaunch's second recovery no longer clobbers the adoption

New file `watch/watchos/Tests/WatchSessionEngineTests/WatchRelaunchRecoveryTests.swift`,
fixture `ScriptedPlatformStore(inProgress:adoptsInProgress:)`: adoption answers once and clears the
stranded name, so a second `recoverStrandedWorkout()` on the same boot finds nothing — the real
`OmniTrainApp` + `ContentView.restore()` pair.

| Scenario | Test | Red at HEAD | Green after |
|---|---|---|---|
| S-16801 | `testS16801TheSecondRecoveryKeepsTheAdoptedWorkout` | FAILED — a second `begin` stood in for the adopted builder | pass |
| S-16802 | `testS16802RecoveryWithNothingStrandedLeavesAHeldWorkoutOpen` | FAILED — `running` went nil with the builder still held | pass |
| S-16803 | `testS16803ASecondRecoveryAfterAFallThroughAddsNoEnd` | FAILED — the fall-through end landed after the adopt | pass |

Prove-red verdict line (`.github/copilot/scripts/macos/gateway.sh prove-red HEAD swift-test
--filter WatchRelaunchRecoveryTests -- watch/watchos/Tests/WatchSessionEngineTests/WatchRelaunchRecoveryTests.swift`):

```
RED AT HEAD (exit 1)
```

Focused green after the fix: `--filter WatchRelaunchRecoveryTests` → **3 tests, 0 failures**.
Fix: `WatchWorkoutCoordinator.recover(_:)` opens with `guard platform.running == nil else { return }`
(D-16801) and `WatchPlatformWorkout.recoverInProgress(saving:)` sets `running = nil` only inside the
branch that actually ended something (D-16802).

## Phase 2 — the exercises' agreed Health kind wins when they name one

`slot(_:_:healthActivity:)` plus `walk()`/`namedRun()` fixtures were added beside the existing
`slot`/`run`; every case builds its own store and engine.

| Scenario | Test | Red at HEAD | Green after |
|---|---|---|---|
| S-16804 | `testS16804AWalkNamedByTheExerciseBeatsTheCardioModality` | FAILED — got `running` (the modality) | pass |
| S-16805 | `testS16805TheNamedKindsMajorityAndItsTie` | FAILED — no majority, so the modality won | pass |
| S-16806 | `testS16806UnnamedExercisesKeepTheModality` | pass (guard) | pass |
| S-16807 | `testS16807AFreeWorkoutKeepsItsExerciseAnswer` | pass (guard) | pass |
| S-16808 | `testS16808ALaterNamedKindNeverRetypesTheOpenWorkout` | pass (guard) | pass |

Red run before the fix: **3 failures** (S-16804, S-16805 and the S-16805 tie half). Prove-red
verdict line (`prove-red HEAD swift-test --filter WatchWorkoutTypeFromExercisesTests --
watch/watchos/Tests/WatchSessionEngineTests/WatchWorkoutTypeFromExercisesTests.swift`):

```
RED AT HEAD (exit 1)
```

Focused green after the fix: `--filter WatchWorkoutTypeFromExercisesTests` → **16 tests, 0 failures**.
Neighbours stayed green: `testS8809AModalityWinsOverTheExercises`, `WatchRoutineFocusTests` S-12560
and its squats case, `WatchHealthActivityTests` (still calls `forExercises`, untouched).
Rule: `namedHealthKinds` / `forNamedHealthKinds(_:)` feed a four-tier `forSession(_:)` —
named Health kind (majority, earliest wins a tie) → modality → exercise capability → nil.

## Phase 3 — the Dart mirror moves with the rule

`lib/watch/sensors/watch_platform_workout.dart`: `WatchActivityTypes` gained `forExercise`,
`forNamedHealthKinds`, `forExercises` and `forSession` with Phase 2's four tiers; `start` now asks
`WatchActivityTypes.forSession(session) ?? WatchActivityTypes.generic`. `forModality` is kept — its
other readers are untouched.

New group in `test/watch_sensor_recording_test.dart`: `S-16810 the mirror types a session like the
wrist` — `a named walk beats the cardio modality`, `unnamed exercises keep the modality`, `a free
workout keeps its exercise answer`. Fixture helper `_namedSlot`; each case gets a fresh engine and
`_FakePlatformStore`.

Proof by mutation (the guarded statement already existed, so `prove-red` cannot isolate it):

| Step | Line | Result |
|---|---|---|
| Original recorded | `WatchActivityTypes.forSession(session) ?? WatchActivityTypes.generic` | focused file 41/41 |
| Mutated | `WatchActivityTypes.forModality(session.modality)` | focused file **RED** (S-16810 named-walk case) |
| Restored exactly | the original line above | 41/41 green |

Focused green: `.github/copilot/scripts/macos/gateway.sh test test/watch_sensor_recording_test.dart`
→ `00:0x +41: All tests passed!` (**41 tests, 0 failures**; baseline 38).

## Phase 4 — the store's outcome is visible, and Health gets its distance

`ios/OmniTrain Watch App/HealthKitWorkoutStore.swift`: a
`diagnostics: WatchDiagnosticsLog?` property, `discarded_held <name>` on the held-discard branch of
`begin`, `workout_saved`/`workout_save_failed <name>` around `finishWorkout()`,
`enableCollection(for: .distanceWalkingRunning, predicate: nil)`, and the type in both `toShare` and
`read`. `ContentView.swift` passes `diagnostics: diagnostics`.

The app target has no test target and `HKWorkoutActivityType` does not exist on macOS, so every guard
is a source scan in `WatchWorkoutStoreSourceTests` — comment lines stripped first, assertions scoped
to one function's brace window, whitespace squeezed so a wrapped statement still matches.

| Scenario | Test | Red at HEAD | Green after |
|---|---|---|---|
| S-16809 | `testS16809TheStoreNotesTheSaveOutcomeAndTheHeldDiscard` | FAILED — no save note, no held-discard note | pass |
| S-16809 | `testS16809TheStoreCollectsAndSharesDistance` | FAILED — distance never collected or shared | pass |

Prove-red verdict line (`prove-red HEAD swift-test --filter WatchWorkoutStoreSourceTests --
watch/watchos/Tests/WatchSessionEngineTests/WatchWorkoutStoreSourceTests.swift`):

```
RED AT HEAD (exit 1)
```

The first red run reported 6 failures; one assertion was wrong (it looked for the literal
`"discarded_held"` while the store writes one detail string `"workout_end"` + `discarded_held <name>`)
and was corrected before the re-proof above.

The initializer is a designated `init(location:diagnostics:)` plus `convenience init(location:)`
forwarding `nil`, because `WatchSensorSourceSourceTests.testS3312` asserts the exact text
`init(location: WatchTrackedLocation)`. That neighbour was red for one round and is green without
being edited.

## Suite counts at handoff

| Gate | Result |
|---|---|
| `swift-test` (full) | **1446 tests, 0 failures** (baseline 1436 + 10 new) |
| `test/watch_sensor_recording_test.dart` | **41 tests, 0 failures** |
| `flutter test` (full) | `+7573 ~4 -6: Some tests failed.` — six failures in files owned by in-flight plan-167 work, listed under Open Items in the plan; none imports the mirror module |
| `gateway.sh lint` | 183 issues, same shape as the baseline; no finding in `lib/watch/sensors/watch_platform_workout.dart` or `test/watch_sensor_recording_test.dart` |
| invariant sweep | `hive_workout_repository` appears only in `lib/main.dart` (the composition root), nowhere in `lib/state`, `lib/features`, `lib/widgets`, `lib/core` |
