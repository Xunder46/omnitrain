# Review — plan 40 (watch GPS by exercise)

Findings from the phase-4 review are written here; the plan's `## Feedback` holds only a pointer to this file.

Verdict: **APPROVE**

Reviewed: the uncommitted tree at base dc9ada9c, plan-40 files only (plan-39 logger/lib files ignored per brief). Diff conforms to the plan's Predicted Files: `WatchPlatformWorkout.swift` (+21), `WatchSensorRecording.swift` (+32), `WatchSensorCoordinator.swift` (+2), `watch_sensor_contract.json` (+9), `watch_platform_workout.dart` (+6), `WatchGpsByExerciseTests.swift` (new, 16 tests), `test/watch_sensor_recording_test.dart` (+1 test), and the three docs. Nothing outside.

Test counts (governor's run, per brief facts — not re-run): Swift suite 608 / 0 failures; `test/watch_sensor_recording_test.dart` 38 / 0; the 8 failing `test/mix_layer_screen_test.dart` tests fail identically at the base commit (pre-existing, plan 39's tree).

## Answers to the brief's five questions

**1. Can the feed start for a finished session while `startLocationIfNeeded` awaits the Location prompt? — No.**
`WatchSensorCoordinator.apply` runs on a serial `NSLock`-guarded tail (`WatchSensorCoordinator.swift:88-107`): every `refresh` is enqueued behind the previous one, so a `stop`-carrying refresh cannot run inside a parked `start` — it runs after `start` returns. `recordingSessionId` is written *before* `recorder.start` (`:69-70`), so a `refresh(nil)` or a status change during the prompt resolves to `recorder.stop()` on the tail, which cancels `fixTask` and resets `locationAnswered` (`WatchSensorRecording.swift:180-190`). No production caller bypasses the coordinator: the host holds only `WatchSensorCoordinator` and calls `sensors.refresh(engine.session)` on revision change (`ios/OmniTrain Watch App/ContentView.swift:42,104,160`); `WatchSessionSensors.start` (which calls `recorder.start` directly) has no caller in `watch/watchos/Sources` outside its own definition — tests only. A same-id `sessionChanged` during a parked start is also impossible for the same serialisation reason.

**2. Acceptance criteria 1–7 → guarding tests** (all read in `WatchGpsByExerciseTests.swift` / `test/watch_sensor_recording_test.dart`; each assertion would fail if the criterion broke):

| AC | Tests |
|---|---|
| 1 | `testS4800AWalkInAFreeWorkoutStartsGps`, `testS4802GpsStartsWhenTheUserReachesTheWalk`, `testS4811APhoneSnapshotMovesTheUserOntoAWalk`, `testS4813bTheRoutineStartsGpsWhenItsFirstExerciseCarriesDistance` |
| 2 | `testS4801ALiftNeverStartsGpsAndNeverAsks` (0 subscriptions *and* 0 permission reads), `testS4812ASlotWithNoCapabilitiesKeyIsNoGpsWork` |
| 3 | `testS4803TheFeedStaysOnWhenTheUserMovesBackToALift` (still measuring, still 1 subscription, total 900 kept, one settled sample) |
| 4 | `testS4804ARefusedSessionIsAskedAboutOnceAndANewOneAgain`, `testS4815UnavailableIsAnsweredOnceLikeDenied` |
| 5 | `testS4808ALateStartStillLogsTheEffortsMetres` (800 = 1050 − 250, `distanceSource: "gps"`) |
| 6 | `testS4807TheWorkoutIsRegisteredOutdoorsByTheExerciseTheUserIsOn` (4 rows incl. the nil-modality/no-slot row), `testS4813ARoutineThatBeginsWithARunIsOutdoorWork`; the "never re-registered mid-session" half is guarded by the existing `WatchWorkoutCoordinatorTests` S-1500…S-1510 (per plan invariant; not re-read this run) |
| 7 | `testS4810TheExerciseRuleAnswersTheContract'sCases` (Dart mirror over the same 7 contract rows); phone-side unchanged is D-4806's no-touch rule, guarded by the existing importer tests named in step 24 |

No criterion is without a test.

**3. Stale/out-of-range `currentExerciseIndex` in `isRequired(_ session:)` — no wrong-exercise answer found.** `WatchRecords.currentExercise` (`WatchRecords.swift:239-242`) clamps to `[0, count-1]` and returns nil for an empty list; `fromJson` defaults a missing index to 0 (`:306`). An out-of-range index therefore answers for the first or last slot — the same slot the wrist's own surface resolves the index to, so the GPS decision follows what the user sees. A snapshot that shrinks `exercises` while keeping a large index picks the last slot; that is the clamp's pre-existing semantics, not something this diff introduced. No finding.

**4. Doc claims vs code — they match.** Every test name the docs cite exists in the diff I read: `testS4800…`, `testS4801…`, `testS4802…`, `testS4803…`, `testS4804…`, `testS4805…`, `testS4807…`, `testS4814…`, `testS4815…` in `WatchGpsByExerciseTests.swift`; `testS3300…`, `testS3207…`, `testS3314…`, `testS3210…` are pre-existing names referenced consistently with prior docs. "Asked once per session" is true: `locationAnswered` is set on any non-granted read and only `stop()` resets it (`WatchSensorRecording.swift:116,150-155,187`). "The workout is registered once, at the session's start" matches D-4803: `WatchPlatformWorkout.start` computes `outdoors` once at begin and nothing in the diff re-registers; the claim is guarded by the existing workout-coordinator tests as the doc says. Step 24's walkthrough (free workout → Walking → one Location question → metres → Summary DISTANCE no "est." → lift no question → refusal not repeated → Health lists generic) matches the code paths and the tests it names. The evidence file records that `watch_surface.md` / `state_management.md` / `data_models.md` carry no "free training never records GPS" sentence, so their lack of change is correct.

**5. Conventions / shared pieces — no violation found.** The diff touches no widget, no colour literal, no button, no allowlist entry; naming follows the file's existing style (`coversDistance`, `sessionChanged` — the latter renamed from `update` per the source guard on `update/set/reset/write` prefixes); comments are doc-comments in the established voice; the contract change is additive (new top-level key, existing readers read named keys — confirmed by reading the diff of both readers' tests). "Fix what you touch": nothing in the plan-40 files carries an allowlist entry or a written-standard violation.

## Findings

1. [Minor] `2026-10-18-40-watch-gps-by-exercise-plan.md:193` (Assumption Log) — the log is empty after the complex 1A/1B/2 build phases, which the standing review rule calls a finding. Ruling: **ratify as vacuous** — the implementation followed the seeded decisions D-4800…D-4805 verbatim (diff matches each decision's letter, checked above), so there was nothing to record; but the prover phase is still `pending` in the Progress table while the brief states 14/15 mutations were proven red — the governor should update that Progress row when the prover closes.
2. [Minor, known] `WatchGpsByExerciseTests.swift` `testS4814ASecondSessionMeasuresAgain` — its first session is granted, so it does not guard the `locationAnswered = false` reset in `stop()` against the refused path; `testS4804` does (its second session reads the permission again, which fails if `stop()` skips the reset). The brief already records this; no action needed — the mutation is caught, just not by the test whose name suggests it.

No Blockers, no Majors.

## Scenario coverage

S-4800 → `testS4800AWalkInAFreeWorkoutStartsGps` · S-4801 → `testS4801ALiftNeverStartsGpsAndNeverAsks` · S-4802 → `testS4802GpsStartsWhenTheUserReachesTheWalk` · S-4803 → `testS4803TheFeedStaysOnWhenTheUserMovesBackToALift` · S-4804 → `testS4804ARefusedSessionIsAskedAboutOnceAndANewOneAgain` · S-4805 → `testS4805AGrantedWalkSubscribesOnceHoweverOftenTheSensorsRefresh` · S-4806 → `testS4806ADistanceModalityStartsWithNoExerciseAtAll` · S-4807 → `testS4807TheWorkoutIsRegisteredOutdoorsByTheExerciseTheUserIsOn` · S-4808 → `testS4808ALateStartStillLogsTheEffortsMetres` · S-4809 → `testS4809TheContractCasesDecideCoverage` · S-4810 → `testS4810TheExerciseRuleAnswersTheContract'sCases` (Dart) · S-4811 → `testS4811APhoneSnapshotMovesTheUserOntoAWalk` · S-4812 → `testS4812ASlotWithNoCapabilitiesKeyIsNoGpsWork` · S-4813 → `testS4813ARoutineThatBeginsWithARunIsOutdoorWork` + `testS4813b…` · S-4814 → `testS4814ASecondSessionMeasuresAgain` · S-4815 → `testS4815UnavailableIsAnsweredOnceLikeDenied`. All present; none missing.
