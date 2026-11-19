# Feature: 40 — the wrist measures distance when the exercise can (GPS by exercise)

> Status: BUILT, PROVED AND REVIEWED (2026-10-18); uncommitted; owner device checks open
> Next handoff: owner device walkthrough, then commit
> Binding conventions: docs/global_conventions.md; docs/documentation_standard.md; .github/copilot/pr-scope-budget.md
> Base commit: dc9ada9c (branch claude_develop; the owner's uncommitted plan-39 logger files are unrelated and are not touched). Team: the crew (`.claude/crew.md`). Follows 19e (distance model) and 19f (the CoreLocation feed).

## Overview

Owner report (2026-10-18): an outdoor walk done with the watch showed a blank distance in the phone's Session Summary. Cause found by reading the code: the wrist turns GPS on only when the *session's modality* can cover distance (`WatchGpsPolicy.isRequired(session.modality)`), and every session the wrist can have has modality nil — a free workout (`WatchStartPaths.startFreeWorkout`), a routine started on the wrist (`startFromRoutine`), and a session the phone started (a snapshot carries no modality; `WatchSessionEngine` keeps `existing?.modality`). So GPS never starts, the Location question never appears, and no effort ever carries `distanceMeters`.

Owner decision (2026-10-18, "option 1"): decide by the **exercise**. The wrist starts GPS when the exercise the user is on carries the `distance` capability (Walking, Running, a custom Cardio or Sports exercise with Distance ticked). The decision uses the exercise's capabilities, never its name, and never the modality alone.

What the user sees: start a free workout, pick Walking (or open a routine that begins with a run): the first time, the Location question appears (Allow While Using) and the exercise screen shows distance and pace. Start and Log an effort: the metres between Start and Log travel to the phone as GPS-measured, and the Summary's DISTANCE card shows them with no "est." label. A lift never asks and never uses GPS. A custom Cardio exercise saved with only Time ticked has no Distance capability and does not use GPS (the owner ticks Distance to turn it on).

## Acceptance criteria

1. When the session's current exercise carries `distance`, the wrist starts location updates (after the Location permission is granted), in a free workout and in a routine alike, at the moment the user reaches that exercise.
2. A session whose current exercise never carries `distance` never asks for or uses location (lifts, holds, free training with a lift).
3. Once started, GPS keeps running until the session stops (a latch): moving back to a lift does not stop it and does not reset the cumulative total.
4. Refused or unavailable permission: logging is unchanged, no `distanceMeters`, and the wrist does not ask again for the rest of that session.
5. A distance exercise reached late still logs a correct effort distance: only metres between Start and Log count (D-2205 of plan 19e).
6. The HealthKit workout is registered outdoors when the session's first exercise (or its modality) already covers distance; a workout already registered is not re-registered mid-session.
7. The phone-side behaviour is unchanged (importer, Summary). The Wear/Dart mirror gets the same pure rule, asserted against the same contract cases.

## Resolved Decisions (Ledger) — seeded, fixed

- **D-4800** The rule is one pure function per client. Swift, `WatchPlatformWorkout.swift` `WatchGpsPolicy` (`:112`): add `public static func coversDistance(_ capabilities: [String]) -> Bool` (`capabilities.contains(distanceCapability)`) and `public static func isRequired(_ session: WatchSessionRecord) -> Bool` = `isRequired(session.modality) || coversDistance(capabilities of session.currentExercise)`, where the capabilities are `(session.currentExercise?["capabilities"] as? [String]) ?? []` (`WatchSessionRecord.currentExercise`, `WatchRecords.swift:240`). The existing `isRequired(_ modality: String?)` stays as it is (no caller breaks); its doc comment sentence "Free training has no profile, so it never records GPS" is rewritten to say the modality alone never decides for free training and the exercise does (`isRequired(_ session:)`).
- **D-4801** Recorder, `WatchSensorRecording.swift` `WatchSensorRecorder`: `start(_ session:)` (`:141`) keeps starting heart rate and steps, then calls a new private `startLocationIfNeeded(for session:)`; a new `public func sessionChanged(_ session: WatchSessionRecord) async` calls the same private method. `startLocationIfNeeded` returns at once when `isMeasuringDistance` is already true (the latch, acceptance 3), when `locationAnswered` is already true (a private `Bool`, set once the permission has been read and was not `.granted`, reset by `stop()`: acceptance 4), or when `WatchGpsPolicy.isRequired(session)` is false. Otherwise it reads `source.locationPermission()`; not granted → `locationAnswered = true`, return; granted → the existing body (`isMeasuringDistance = true`, `fixTask = consume(source.location()) {...}`). `stop()` is unchanged except that it also resets `locationAnswered`.
- **D-4802** Coordinator, `WatchSensorCoordinator.swift` `apply` (`:60`): in the branch where the session is active and `recordingSessionId` already equals its id, call `await recorder.sessionChanged(session)` before `return` (today that branch does nothing). The first-time branch (`recordingSessionId == nil`) is unchanged: it calls `recorder.start(session)`. The host already calls `sensors.refresh(engine.session)` on every `revision` change, and `noteSurfaceChange()` bumps it after a pick, an advance, a log and the menu closing (`ios/OmniTrain Watch App/ContentView.swift:155-161`, `:208`, `:257`, `:336`, `:367-371`): no host change is part of this unit.
- **D-4803** Platform workout, `WatchPlatformWorkout.start` (`:197-207`): `outdoors: WatchGpsPolicy.isRequired(session)` (the session overload) instead of `isRequired(session.modality)`. Nothing re-registers a workout mid-session (`WatchWorkoutCoordinator.apply` starts only when none is open): a walk added after a generic workout began still records GPS distance, and Apple Health lists the workout as the generic type it began as. Said in the docs, not fixed here.
- **D-4804** Contract, `watch/contract/watch_sensor_contract.json`: add the top-level key `"exerciseGpsCases"`, a list of `{ "capabilities": [...], "gps": bool }` objects, exactly: `["time","distance"]` true; `["distance"]` true; `["time","distance","rounds"]` true; `["reps","sets","load"]` false; `["time","rounds"]` false; `["hold","time"]` false; `[]` false. Additive: the existing readers read named keys only. Readers of the file (listed so none is missed): `WatchSensorRecordingTests.swift:523-557` (named keys), `Fixtures.swift` (loads the file), `test/watch_sensor_recording_test.dart:610-619` (named keys), and mentions in comments of `WatchLoggingState.swift`, `WatchRecords.swift`, `WatchPlatformWorkout.swift`, `lib/watch/logging/watch_logging_state.dart`, `lib/watch/session/watch_records.dart`, `lib/watch/sensors/watch_platform_workout.dart`. A builder greps every `contract[` read before editing and reports any whole-key-set assertion (none expected).
- **D-4805** Dart mirror, `lib/watch/sensors/watch_platform_workout.dart` `WatchGpsPolicy` (`:111`): add `static bool coversDistance(Iterable<String> capabilities)` (`capabilities.contains(distanceCapability)`). Nothing else on the Dart side changes: the Wear client has no host that refreshes sensors on an exercise change (its only caller is the debug surface, `lib/watch/debug/watch_session_debug_surface.dart`), and 19f D-2300 keeps the Wear client out of scope. The rule is held by the shared contract cases.
- **D-4806** The phone never changes: `lib/` outside `lib/watch/sensors/` is not touched, the importer already stores `distanceSource: "gps"`.
- **D-4807** New tests live in new files, so no existing test is edited: `watch/watchos/Tests/WatchSessionEngineTests/WatchGpsByExerciseTests.swift` (S-4800..S-4809) and a new group in `test/watch_sensor_recording_test.dart` (S-4810). An existing test turning red unpredicted: stop and report. Expected none: every existing sensor test sets a distance modality AND distance capabilities together, or a lift.

## Core scenarios — seeded, fixed

Swift scenarios use the file's own harness pieces named below (copy the pattern of `WatchSensorRecordingTests.swift`: `FakeSensorSource` `:38` with `locationSubscriptions` `:44`, `fix(_:)` `:78`, the `session(engine, modality:, capabilities:)` helper, `sensors(for:)`, and `WatchSensorCoordinator(recorder:)` as in `WatchSensorCoordinatorTests.swift`). All are red at the base: a session with modality nil never subscribes.

- **S-4800 a walk in a free workout starts GPS.** Session modality nil, one slot "Walking" with capabilities `["time","distance"]`; `coordinator.refresh(session)` → `source.locationSubscriptions == 1`, `recorder.isMeasuringDistance == true`; `source.fix(300)` → `readings.distanceMeters == 300`. Red today: 0 subscriptions. Mutation: drop the `|| coversDistance(...)` term → 0.
- **S-4801 a lift never starts GPS and never asks.** Modality nil, one slot capabilities `["reps","sets","load"]`: refresh three times → `locationSubscriptions == 0`, `isMeasuringDistance == false`, and the source's location permission is never read (add a `private(set) var locationPermissionReads = 0` to the test's own subclass or a counting wrapper in the new file; do not edit `FakeSensorSource`). Mutation: make `isRequired(session)` return true for any non-empty exercise list → red.
- **S-4802 GPS starts when the user reaches the walk.** Routine-style session, nil modality, slots [Bench `["reps","sets","load"]`, Run `["time","distance"]`], current index 0: refresh → 0 subscriptions; move to index 1 (`engine.selectExercise(slotId:)`), refresh → 1 subscription and `isMeasuringDistance`. Mutation: have `apply` call `recorder.sessionChanged` only on the first start → stays 0 after the move.
- **S-4803 the latch.** Continue S-4802: `source.fix(400)`, move back to the Bench slot, refresh → `isMeasuringDistance` still true, `locationSubscriptions` still 1; `source.fix(900)` → `readings.distanceMeters == 900`; `stop()` writes one `distance` sample of 900 and `isMeasuringDistance == false`. Mutation: stop the feed when the current exercise has no distance → red.
- **S-4804 refused once is not asked again.** `source.locationGrant = .denied`, nil modality, a walk slot: refresh three times → permission read exactly once, `locationSubscriptions == 0`, no `gps` samples; after `stop()` and a new session with a walk slot the permission is read once more. Mutation: drop `locationAnswered` → three reads.
- **S-4805 idempotent.** Granted, walk slot: refresh five times → `locationSubscriptions == 1`.
- **S-4806 a distance modality still starts GPS with no exercise.** `modality: "cardio_endurance"`, `exercises: []`: `start(session)` → 1 subscription (the old rule is intact). Mutation: replace `||` by `&&` → red.
- **S-4807 the workout is registered outdoors by the first exercise.** The recording store of `WatchOutdoorWorkoutTests.swift` (implements only `begin(_:outdoors:)`): `WatchPlatformWorkout.start` of a nil-modality session whose current slot is `["time","distance"]` → `(other, true)`; current slot `["reps","sets","load"]` → `(other, false)`; no slots → `(other, false)`; `resistance_lifting` with a lift slot → `(traditionalStrengthTraining, false)`. Mutation: keep `isRequired(session.modality)` in `start` → the first row reads false.
- **S-4808 a late start still logs the right metres.** Nil modality, a walk slot added to a started free session at t0 − 90 s (GPS starts); `fix(250)` at t0 − 30 s; user Start at t0; `fix(1050)` at t0 + 300 s; Log at t0 + 600 s → the effort payload `distanceMeters == 800` (1050 − 250, the window rule `WatchLoggingState.cumulativeMeters(at:)`) and `distanceSource == "gps"`. Pattern: S-3208 in `WatchSensorRecordingTests.swift`. Mutation: read the newest sample instead of the window difference → 1050.
- **S-4809 the contract cases (Swift).** For every entry of `exerciseGpsCases`: `WatchGpsPolicy.coversDistance(capabilities) == gps`, and the list has 7 entries. Mutation: `coversDistance` returns `capabilities.contains("time")` → the `["time","rounds"]` row reads true.
- **S-4810 the contract cases (Dart).** `test/watch_sensor_recording_test.dart`, new group: the same loop over the same JSON with `WatchGpsPolicy.coversDistance`. Mutation as S-4809.

## Phase outline (each one crew run; at most 8 items)

| Phase | Agent | Write scope (`--scope`) | Parallel? | Goal |
|---|---|---|---|---|
| 1A | crew-builder-watch | `watch/watchos/Sources/WatchSessionEngine/WatchPlatformWorkout.swift,watch/contract/watch_sensor_contract.json,watch/watchos/Tests/WatchSessionEngineTests/WatchGpsByExerciseTests.swift` | serial first | D-4800, D-4803, D-4804; S-4807, S-4809 (the file is created here, 1B appends) |
| 1B | crew-builder-watch | `watch/watchos/Sources/WatchSessionEngine/WatchSensorRecording.swift,watch/watchos/Sources/WatchSessionEngine/WatchSensorCoordinator.swift,watch/watchos/Tests/WatchSessionEngineTests/WatchGpsByExerciseTests.swift` | with 2 (disjoint) | D-4801, D-4802; S-4800..S-4806, S-4808 |
| 2 | crew-builder-app | `lib/watch/sensors/watch_platform_workout.dart,test/watch_sensor_recording_test.dart` | with 1B | D-4805; S-4810 |
| gov | governor | — | after 1B and 2 | `swift test`, targeted and full `flutter test`, invariant grep, scope guard, device build note |
| 3 | crew-prover then crew-docs-keeper | tests only; then `docs/**` | prover first (mutation list, the governor applies it); docs after the last test | docs: `docs/state_management/watch_sensors.md`, `docs/state_management/watch_surface.md` and `docs/data_models.md` / `docs/state_management.md` wherever they say free training or a nil modality never records GPS, `docs/watch-app-setup-and-qa.md` step 24 (the owner walkthrough: free workout, pick Walking, Location question, a few hundred metres, Summary shows the distance; lift: no question; Health lists the workout as generic), `docs/distance_source.md` if it says the wrist cannot measure |
| 4 | crew-reviewer | review file | after docs | 5 narrow questions in the brief |

Phase 1A and 1B share the new test file and the same Swift package, so they run serially. Phase 2 touches only Dart and starts after 1A (it reads the contract keys).

## Code pointers

`WatchPlatformWorkout.swift`: `WatchGpsPolicy` `:112-143`, `WatchPlatformWorkout.start` `:197-207`. `WatchSensorRecording.swift`: `WatchSensorRecorder` `:100`, `isMeasuringDistance` `:114`, `start` `:141-152`, `stop` `:159-190`. `WatchSensorCoordinator.swift`: `apply` `:60-82`. `WatchRecords.swift`: `WatchSessionRecord.currentExercise` `:240`. `WatchSessionEngine.swift`: `selectExercise(slotId:)` `:325`, `advanceExercise` `:308`. `WatchStartPaths.swift`: `startFromRoutine` `:522-542`, `startFreeWorkout` `:549`, `addExerciseToSession` `:559`. `WatchLoggingState.swift`: `windowPayload` (~`:744`), `cumulativeMeters(at:)`. Host (read only): `ios/OmniTrain Watch App/ContentView.swift:155-161`. Dart: `lib/watch/sensors/watch_platform_workout.dart:111-126`, `lib/watch/sensors/watch_sensor_recording.dart:133`. Tests to model on: `WatchSensorRecordingTests.swift` (S-001 `:188`, S-002 `:197-215`, S-006 `:447`), `WatchSensorCoordinatorTests.swift`, `WatchOutdoorWorkoutTests.swift`, `WatchEffortDistanceTests.swift`, `test/watch_sensor_recording_test.dart:600-625`.

## Risks and `(owner)` checks

- **(owner)** On a real watch: start a free workout, add Walking, confirm the Location question appears once (Allow While Using), walk a few hundred metres, see the distance and pace line, Start and Log an effort, sync, and see the distance in the phone's Summary (DISTANCE card, no "est."). Start a lift: no question. This is the first run of the wrist GPS on hardware (docs/watch-app-setup-and-qa.md step 24 is still unchecked).
- Reaching the walk by the menu list is surfaced to the sensors when the menu sheet closes (`ContentView.swift:367-371`), not at the moment of the tap: GPS may start a moment after the sheet closes. Distance before Start never counts, so this loses nothing.
- Apple Health lists a free-workout walk as a generic workout, not an outdoor walk (D-4803).
- Once started, GPS stays on until the session ends (a mixed routine keeps the radio on while lifting after a run): a battery trade-off the owner may revisit.
- Follow-up, separate PR (not in this plan): a hint under the Distance chip in the exercise editor ("Tick Distance to let the watch measure it with GPS").

## Feature invariants (added)

- A lift never asks for Location and never subscribes: `isRequired(_ session:)` is false whenever the modality cannot cover distance and the current exercise lacks `distance` (S-4801; existing S-001 on both platforms stays green).
- The old modality rule is intact: `isRequired(_ modality:)` keeps its body and its contract assertions (S-4806; existing S-008 in `WatchSensorRecordingTests.swift:521-570` and `test/watch_sensor_recording_test.dart:573-640`, and `WatchOutdoorWorkoutTests.testS3300OutdoorsFollowsTheCapabilityProfile`).
- The per-effort window rule of 19e D-2205 is unchanged: `WatchLoggingState.windowPayload` (`:855`) and `cumulativeMeters(at:)` (`:908`) are not edited; S-4808 only drives them (existing `WatchEffortDistanceTests` stay green).
- Nothing on the phone changes: no file outside `lib/watch/sensors/` and `watch/` is edited (D-4806); the importer already stores `distanceSource: "gps"`.
- The contract change is additive: `exerciseGpsCases` is a new top-level key; every existing reader reads named keys only (D-4804).
- One workout, never re-registered mid-session: `WatchWorkoutCoordinator.apply` begins only when none is open (existing S-1500…S-1505, S-1507, S-1508, S-1510).

## Existing-functionality impact (added)

Search run for every row: `grep -n "WatchGpsPolicy.isRequired"` over the repo (20 hits, 6 code files + plans), and `grep -n "sensors\.start|recorder\.start|\.refresh("` over `watch/watchos/Tests/WatchSessionEngineTests` (102 hits, 7 files) and `test/watch_sensor_recording_test.dart`.

| Touched surface | Effect | Guarded by |
|---|---|---|
| `WatchSensorRecording.swift:146` (`start`'s guard) | becomes `startLocationIfNeeded(for:)` (D-4801) | S-4800, S-4806 |
| `WatchPlatformWorkout.swift:206` (`start`'s `outdoors:`) | becomes the session overload (D-4803) | S-4807, S-4813 |
| `lib/watch/sensors/watch_sensor_recording.dart:133` | unchanged (D-4805: the Wear client has no refresh-on-exercise-change host) | S-4810 |
| `WatchSensorRecordingTests.swift:532, 550-551, 561` | unchanged — they assert the modality overload, which stays | S-4809 |
| `test/watch_sensor_recording_test.dart:583, 602, 605, 613` | unchanged | S-4810 |
| Tests calling `sensors.start`/`recorder.start`/`coordinator.refresh` with a distance slot and a nil or non-distance modality | **none found**: every distance-capability slot sits in a `cardio_endurance` session (`WatchSensorRecordingTests.swift:205, 221, 263…`, `WatchEffortDistanceTests.swift:55-60`, `WatchDistanceTrackerTests.swift:357-366`, `WatchLoggingSurfacesTests.swift:644`, `WatchSensorCoordinatorTests.swift:703-711`); lift slots are `exercise(_:)` = `["reps","sets","load"]` (`WatchSessionEngineTests.swift:85-92`); the nil-modality calls use no slot or `capabilities: []` (`WatchSensorRecordingTests.swift:928`, `test/watch_sensor_recording_test.dart:765`) | D-4807's "expected none" holds; S-4801, S-4812 |
| `watch_sensor_contract.json` readers (grep `watch_sensor_contract`: 31 hits, 13 files) | additive key only. Real readers: `Fixtures.swift:48-57`, `WatchSensorRecordingTests.swift:502-570` (named keys), `WatchWorkoutStoreSourceTests.swift:32`, `test/watch_sensor_recording_test.dart:134-138, 610-619` (named keys); comment mentions: `WatchRecords.swift:125`, `WatchLoggingState.swift:127`, `WatchPlatformWorkout.swift:23`, `HealthKitWorkoutStore.swift:202`, `lib/watch/session/watch_records.dart:112`, `lib/watch/logging/watch_logging_state.dart:91`, `lib/watch/sensors/watch_platform_workout.dart:15` | S-4809, S-4810 |

**`refresh` while `recorder.start` is still awaiting the Location prompt — cannot overlap.** `WatchSensorCoordinator.refresh` runs `apply` on a serial tail (`WatchSensorCoordinator.swift:96-107`):

```swift
private func enqueue(_ work: @escaping () async -> Void) -> Task<Void, Never> {
    lock.lock()
    defer { lock.unlock() }

    let previous = tail
    let next = Task {
        await previous?.value
        await work()
    }
    tail = next
    return next
}
```

A `refresh` that arrives while `start` is parked inside `source.locationPermission()` (the D-2316 shape) is enqueued behind it and waits for it to finish. What `update` then sees: if the answer was `.granted`, `isMeasuringDistance == true` and the latch returns at once; if it was refused or unavailable, `locationAnswered == true` and it returns at once. Either way no second prompt and no second subscription (S-4805, S-4814). D-2316 itself (a stop waiting behind a parked start) is unchanged.

**Does `WatchSessionEngine` change `currentExercise` between refreshes without the host refreshing? No gap found.** `applyExercisePush` (`WatchSessionEngine.swift:412-425`) inserts a slot without moving the user (`insertExercise(_:atIndex:announce:)`, no `moveTo`), so a push alone never changes `currentExercise`. `applySnapshot` (`:480-545`) can: it writes `currentExerciseIndex` from the payload, clamped, and keeps `existing?.modality` (`:510-528`). But every arrival bumps the host's `revision` (`ContentView.swift:123`, inside `bridge.onIncoming`), and `$revision.sink` refreshes the workout then the sensors (`ContentView.swift:155-161`), so a snapshot that moves the user onto a walk is always followed by a refresh that starts GPS. The host wiring is pinned by the source scan `WatchSensorSourceSourceTests.testS3110TheHostWiresTheSensorsAndRefreshesTheWorkoutFirst` (`:313-317`); the engine-level behaviour is new S-4811.

## Edge scenarios (added; `grep S-48` run — S-4811…S-4815 were free)

- **S-4811 a phone snapshot moves the user onto a walk.** Fixture: active nil-modality session, one lift slot, sensors started (0 subscriptions); then `engine.applyMessage(_:)` with `fixtures/valid/session_snapshot.json`'s envelope, its payload's `exercises` replaced by one walk slot (`["time","distance"]`) and `currentExerciseIndex: 0`, same `sessionId`; then `coordinator.refresh(engine.session)`. Expected: 1 subscription, `isMeasuringDistance == true`. Red today: 0 — the snapshot changes `currentExercise`, but the modality-only rule never starts GPS. Mutation: drop the `update` call in `apply`'s already-recording branch → stays 0.
- **S-4812 a slot with no `capabilities` key is no GPS work.** Fixture: nil modality, one slot map without a `"capabilities"` key. Expected: `isRequired(session)` false; refresh → 0 subscriptions, `locationPermissionReads == 0`. Green at base (a nil modality already stays off); it guards the cast in D-4800 — mutation `as! [String]` crashes, defaulting the missing key to `["distance"]` subscribes — either is red.
- **S-4813 a routine that begins with a run.** Fixture: a `routines_down` built from `watch/contract/watch_start_paths_contract.json`'s `routinesDown` with the first routine's first effort's capabilities set to `["time","distance"]` (the exercise stays one the fallback list covers; the `twoRoutineMessage` pattern, `WatchSessionStartPathsTests.swift:213-240`); `paths.applyRoutinesDown`, then `startFromRoutine`. Expected: `WatchPlatformWorkout.start` → `(other, true)` and `coordinator.refresh` → 1 subscription. Red today: `(other, false)`, 0. Mutation: keep `isRequired(session.modality)` in `start` → outdoors false.
- **S-4814 two sessions in a row.** Fixture: session 1 walk, granted: refresh → 1 subscription; `engine.finishSession()`, `coordinator.refresh(completed)` (the stop); session 2 walk: refresh → 2 subscriptions total and `locationPermissionReads == 2`. Expected: the second session measures again — `stop()` reset both the latch and `locationAnswered`. Red today: 0 subscriptions, 0 reads (the modality guard returns first). Mutation: skip either reset in `stop()` → 1 sub or 1 read.
- **S-4815 `.unavailable` is answered once, like denied.** Fixture: `source.locationGrant = .unavailable`, nil modality, a walk slot: refresh three times → `locationPermissionReads == 1`, 0 subscriptions, no `gps` samples. Red today: 0 reads (unreachable at base); the assertion bites on the mutation that latches only `.denied` → 3 reads. Complements existing `testS006HardwareThatIsNotThereIsNotAFailure`, which counts no reads.

## Phases (expanded; scopes are the outline's, verbatim)

### Phase 1A — crew-builder-watch — serial first
Scope: `--scope watch/watchos/Sources/WatchSessionEngine/WatchPlatformWorkout.swift,watch/contract/watch_sensor_contract.json,watch/watchos/Tests/WatchSessionEngineTests/WatchGpsByExerciseTests.swift`

1. [ ] Add `coversDistance(_:)` and the `isRequired(_ session:)` overload; rewrite the modality overload's "Free training has no profile…" sentence (D-4800) — `WatchPlatformWorkout.swift` · `WatchGpsPolicy`
2. [ ] Pass `outdoors: WatchGpsPolicy.isRequired(session)` in `start` (D-4803) — `WatchPlatformWorkout.swift` · `WatchPlatformWorkout.start`
3. [ ] Add the `exerciseGpsCases` key, the seven seeded rows, in order (D-4804) — `watch/contract/watch_sensor_contract.json`
4. [ ] Grep every `contract[` read in both suites; report any whole-key-set assertion (none expected, D-4804) — `WatchSensorRecordingTests.swift`, `test/watch_sensor_recording_test.dart` (read-only)
5. [ ] Create `WatchGpsByExerciseTests.swift`: a counting source (subclass or wrapper carrying `locationPermissionReads`; `FakeSensorSource` is not edited), a local `RecordingOutdoorPlatformStore`-shaped store, and S-4807, S-4809, S-4812, S-4813 — `WatchGpsByExerciseTests.swift`
6. [ ] Run the file and its nearest siblings; record counts in the evidence file

Done criteria: `swift test --filter WatchGpsByExerciseTests` green; `swift test --filter WatchSensorRecordingTests` and `--filter WatchOutdoorWorkoutTests` green with their baseline counts. Expected red before the phase: S-4807 row 1 and S-4813 read `outdoors: false`; S-4809 red until items 1+3 land; S-4812 green once item 1 lands (it guards mutations).

### Phase 1B — crew-builder-watch — after 1A (same test file, same package); parallel with 2 (disjoint writes)
Scope: `--scope watch/watchos/Sources/WatchSessionEngine/WatchSensorRecording.swift,watch/watchos/Sources/WatchSessionEngine/WatchSensorCoordinator.swift,watch/watchos/Tests/WatchSessionEngineTests/WatchGpsByExerciseTests.swift`

1. [ ] Extract `startLocationIfNeeded(for:)`, add `locationAnswered`, reset it in `stop()`, add `public func sessionChanged(_:)` (D-4801) — `WatchSensorRecording.swift` · `WatchSensorRecorder`
2. [ ] Call `await recorder.sessionChanged(session)` in `apply`'s already-recording branch (D-4802) — `WatchSensorCoordinator.swift` · `WatchSensorCoordinator.apply`
3. [ ] Append S-4800, S-4801, S-4802 — `WatchGpsByExerciseTests.swift` (red until items 1–2)
4. [ ] Append S-4803, S-4804, S-4805 — `WatchGpsByExerciseTests.swift`
5. [ ] Append S-4806, S-4808, S-4811, S-4814, S-4815 — `WatchGpsByExerciseTests.swift`
6. [ ] Run the sibling suites; record counts

Done criteria: `swift test --filter WatchGpsByExerciseTests` green; `swift test --filter` green for `WatchSensorRecordingTests`, `WatchSensorCoordinatorTests`, `WatchOutdoorWorkoutTests`, `WatchEffortDistanceTests`, `WatchDistanceTrackerTests` at their baseline counts. Expected red before items 1–2: S-4800/S-4802/S-4803/S-4808/S-4811/S-4814 (0 subscriptions), S-4804/S-4815 (0 reads).

### Phase 2 — crew-builder-app — after 1A (reads the contract key); parallel with 1B
Scope: `--scope lib/watch/sensors/watch_platform_workout.dart,test/watch_sensor_recording_test.dart`

1. [ ] Add `static bool coversDistance(Iterable<String> capabilities)` to `WatchGpsPolicy` (D-4805) — `lib/watch/sensors/watch_platform_workout.dart` · `WatchGpsPolicy`
2. [ ] Add the S-4810 group: the same loop over `exerciseGpsCases` via `_contract()` — `test/watch_sensor_recording_test.dart`
3. [ ] Run the file; record counts

Done criteria: `flutter test test/watch_sensor_recording_test.dart` green at its baseline count plus the new group. Expected red before item 1: S-4810 fails on the true rows.

### Governor verify — after 1B and 2
`swift test --package-path watch/watchos` (900 s), targeted then full `flutter test`, the invariant greps (a lift call site still names no location; `lib/` outside `lib/watch/sensors/` untouched), scope guard, device build note.

### Phase 3 — crew-prover, then crew-docs-keeper — prover first; docs after the last test
Scope (prover): tests only, the mutation list the governor applies. Scope (docs): `docs/**`.

Prover:
1. [ ] Prove red at the base commit for S-4800, S-4802, S-4803, S-4804, S-4807, S-4808, S-4809, S-4810, S-4811, S-4813, S-4814 (`prove-red` with the new test files carried over)
2. [ ] Apply each seeded mutation and confirm the named scenario fails; restore

Docs-keeper (every behaviour sentence names an existing test; each file stays under 52 KB):
3. [ ] `docs/state_management/watch_sensors.md`: the GPS-activation rows and the "GPS activation derives from the modality's capability profile" invariant now say the exercise decides for free training; the "lifts, holds and free training never ask" sentence becomes "lifts and holds never ask; free training asks only on a distance exercise" (`testS3300…` stays the lift guard; S-4800/S-4801 the new ones)
4. [ ] `docs/state_management/watch_surface.md` and `docs/state_management.md` / `docs/data_models.md`: wherever they say a nil modality or free training never records GPS
5. [ ] `docs/watch-app-setup-and-qa.md` step 24: the owner walkthrough (free workout → Walking → Location question once → metres → Summary DISTANCE, no "est."; lift: no question; Health lists the workout as generic)
6. [ ] `docs/distance_source.md`: drop/qualify any "the wrist cannot measure" sentence

### Phase 4 — crew-reviewer — after docs
Scope: the review file. The 5 narrow questions the brief names; findings go to `2026-10-18-40-watch-gps-by-exercise-plan.review.md`, the fix checklist pointer to `## Feedback`.

## Progress

| Item | Result |
|---|---|
| 1A · policy + contract + test file (S-4807, S-4809, S-4812, S-4813) | done |
| 1B · recorder sessionChanged + coordinator branch (S-4800…S-4806, S-4808, S-4811, S-4814, S-4815) | done |
| 2 · Dart mirror (S-4810) | done |
| governor verify | done |
| 3 prover · 15 mutations applied by the governor: 14 red by their named test; M10 (drop the `stop()` reset) caught by S-4804, not S-4814 | done |
| 3 docs | done |
| 4 review · APPROVE, 0 blockers, 0 majors, 2 minors (empty Assumption Log ratified; S-4814 name) | done |

## Assumption Log

## Feedback
