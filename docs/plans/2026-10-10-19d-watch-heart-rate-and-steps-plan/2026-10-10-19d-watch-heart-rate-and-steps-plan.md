# Feature: 19d — the watch measures heart rate and steps

> Status: SEEDED by the governor (2026-10-10), awaiting the architect's expansion
> Next handoff: @crew-architect
> Binding conventions: docs/global_conventions.md; docs/documentation_standard.md; .github/copilot/pr-scope-budget.md
> Base commit: ed14570 (branch claude_develop). Team: the crew (`.claude/crew.md`).

## Overview

Plan 19c opened a HealthKit workout with every session and deliberately wired no sensor (19c D-1500). Everything downstream of a reading already exists and is tested: the recorder stores each beat and step count (`WatchSensorRecorder`, `watch/watchos/Sources/WatchSessionEngine/WatchSensorRecording.swift:100`), the engine turns them into heart-rate and step summaries (`WatchSensorSummaries.swift`, used at `WatchSessionEngine.swift:~1435` and `WatchLoggingState.swift:~803`), the wire carries them (`PROTOCOL.md` "Summary fields"), the phone imports them as `SensorSummary` rows (`lib/core/services/watch_session_importer.dart:~1014-1225`) and Stats shows the averages (`lib/features/stats/widgets/instrument_row.dart:37`). The one missing link: nothing feeds the recorder. `WatchSessionSensors` has no production caller and `WatchAppHost.init` builds `WatchLoggingState(engine: engine)` with no sensors (`ios/OmniTrain Watch App/ContentView.swift:84`). This unit adds the real source and starts/stops it with the session.

What a user sees: while a session runs, the exercise screen shows a small grey "142 bpm" line (already designed: `WatchLoggingView.sensorLine`, `WatchLoggingView.swift:132`); after sync the phone holds average and maximum heart rate for the session and for timed, round and hold entries, and a step total for timed entries. If the user refuses the Health permission, logging, rest, the menu and sync work as before and no number appears. The owner confirmed (2026-10-10): heart rate and steps only; the live line on the exercise screen only (not the rest screen); the Health permission text says OmniTrain reads heart rate and steps.

## Acceptance criteria

1. With the permission granted, a running session stores a heart-rate sample per beat the source reports and a cumulative step count, and the exercise screen's readout shows the newest beat.
2. When the session ends, the session-end event and the timed/round/hold entries carry the summaries the existing builders compute from those samples (no new summary logic).
3. Sensors run exactly while the session is active: start with it, stop when it ends, change of session id stops the old and starts the new, a relaunch mid-session starts them again, repeated refreshes start them once.
4. Refusing the permission, or hardware without a sensor, skips the subscription and nothing else (19c S-1505 spirit; `WatchSensorRecorder` already does this per probe).
5. No GPS: the source reports location as unavailable, so no location subscription is made and no distance row changes.
6. The Health permission request asks to read heart rate and step count in the same request as the workout share; the usage text says OmniTrain reads heart rate and steps (owner-approved wording below).

## Resolved Decisions (Ledger) — seeded, fixed

- **D-2100** Scope: heart rate and steps only. GPS/distance/pace, calories and route stay out (owner, 2026-10-10). The new source answers `locationPermission()` with `.unavailable`; `WatchSensorRecorder.start` then makes no location subscription (`WatchSensorRecording.swift:146-147`: `guard await source.locationPermission() == .granted`), so no change to GPS code is needed. The Wear client (`lib/watch/`) is out of scope (documented divergence, as for 18b–21b).
- **D-2101** One new package type follows the session: `WatchSensorCoordinator` (new file `watch/watchos/Sources/WatchSessionEngine/WatchSensorCoordinator.swift`), shaped exactly like `WatchWorkoutCoordinator` (`WatchPlatformWorkout.swift:254`): plain `final class` (not `@MainActor`, not an actor), `init(recorder: WatchSensorRecorder)`, `public func refresh(_ session: WatchSessionRecord?) async`, one `NSLock`-guarded serial tail, `private(set) var recordingSessionId: String?` (internal). Rule: if `recordingSessionId != nil` and it differs from `session?.sessionId` → `recorder.stop()` and clear; then if `session?.status == WatchSessionStatus.active` and not recording → set `recordingSessionId` FIRST, then `await recorder.start(session)`; if not active and recording → `recorder.stop()` and clear. A pure rule enum like `WatchWorkoutLifecycle` is not added: the rule is two lines inside `apply`. Never throws.
- **D-2102** Module-wide guards the new code must respect: no method on any `.swift` file under `Sources/` named with a mutating verb prefix (`WatchSessionEngineTests.swift:322` `testS004NoMutatingOperationExistsAnywhereInTheModule`: `update|delete|remove|replace|edit|overwrite|write|clear|purge|wipe|reset|drop|truncate|erase|forget|modify|mutate|destroy|set`), and no new `*Store.swift` under `Sources/`; no line containing `restSeconds` and no `WatchTimerKind.rest` within 3 lines of `plannedDurationMs` (`WatchRestIsCountUpTests.swift:51,66`). New prose avoids the banned rest wording (see 19c D-1512 (c)). Shared fakes (`FakeSensorSource`, `WatchSensorRecordingTests.swift:32`; `Harness`, `WatchSessionEngineTests.swift:32`) are used, never edited.
- **D-2103** The real source is a new app-target file `ios/OmniTrain Watch App/HealthKitSensorFeed.swift` (whole file inside `#if os(watchOS)`): `final class HealthKitSensorFeed: NSObject, WatchSensorSource, HKLiveWorkoutBuilderDelegate`. It keeps AsyncStream continuations for heart rate and steps (registered when `heartRate()` / `steps()` is called, removed in `onTermination`), is set as the delegate of the store's `HKLiveWorkoutBuilder`, and in `workoutBuilder(_:didCollectDataOf:)` yields, for `HKQuantityType(.heartRate)`: `statistics.mostRecentQuantity()` in `HKUnit.count().unitDivided(by: .minute())` (beats per minute); for `HKQuantityType(.stepCount)`: `statistics.sumQuantity()` in `HKUnit.count()` (cumulative since the builder began — the contract says each value supersedes the last, `WatchSensorRecording.swift:73-75`). `workoutBuilderDidCollectEvent(_:)` is a no-op. A non-finite or non-positive heart rate is dropped (the wire minimum is 1: `WatchSensorSummaries.lowestHeartRateBpm`). The file imports no CoreLocation.
- **D-2104** Permissions. HealthKit never reveals whether a READ was refused, so the probes answer from what the store knows: `heartRatePermission()` and `stepsPermission()` return `.unavailable` when `HKHealthStore.isHealthDataAvailable()` is false, `.denied` when the store's workout authorization did not resolve to granted (no workout means no builder, so no data can flow), otherwise `.granted`. A refused READ then simply produces no samples, and the existing rule "no reading, no pair — never a zero" (`WatchSessionEngineTests.swift:1097`) keeps the summary absent. `locationPermission()` returns `.unavailable` (D-2100). The store resolves authorization once per process before the probes are asked (the host refreshes the workout first, D-2106), so a probe awaits the store's existing resolution and never opens a second prompt.
- **D-2105** `HealthKitWorkoutStore` (`ios/OmniTrain Watch App/HealthKitWorkoutStore.swift:43`) changes minimally: `resolveAuthorization` requests `read: [HKQuantityType(.heartRate), HKQuantityType(.stepCount)]` in the same call as `toShare: [HKObjectType.workoutType()]` (today `read: []`, `:179-182`); `begin` sets `collection.delegate = sensorFeed` and calls `dataSource.enableCollection(for: HKQuantityType(.heartRate), predicate: nil)` and the same for `.stepCount` before `beginCollection`; the store owns one `HealthKitSensorFeed` and exposes it as `let sensorSource: WatchSensorSource`; the feed asks the store for the authorization outcome through a small closure given at init (no back-reference cycle). Activity-name mapping, `end()` and recovery are untouched. The 19c source guard `testS1509TheStoreMapsEveryContractActivityName` must stay green.
- **D-2106** Wiring in `WatchAppHost.init` (`ContentView.swift:~66-130`): the host keeps the `HealthKitWorkoutStore` it already builds, creates `let recorder = WatchSensorRecorder(engine: engine, source: store.sensorSource)`, builds `WatchLoggingState(engine: engine, sensors: recorder)` (today `:84`), keeps `let sensors = WatchSensorCoordinator(recorder: recorder)`, and in the `$revision` sink runs `await self.workout.refresh(self.engine.session)` and THEN `await self.sensors.refresh(self.engine.session)` in the same task (workout first so the builder, the permission outcome and the feed exist; the sink's first emission is the empty session and starts nothing). `recoverInProgress` needs no sensor counterpart: sensors hold no state across a process.
- **D-2107** Health permission text. The three `INFOPLIST_KEY_NSHealthShareUsageDescription` lines in `ios/Runner.xcodeproj/project.pbxproj` (`:653`, `:705`, `:754`, the watch target's Debug/Release/Profile) become: "OmniTrain reads your heart rate and steps during a workout and saves the workouts you finish to Health." (owner-approved). This is a GOVERNOR ACTION (the project file is Xcode's and outside every crew scope); the Update description keeps its wording.
- **D-2108** Proof. `swift-test` proves everything in the package. The app-target files cannot be compiled or run by the gateway (`#if os(watchOS)`, no test target): they are held by two off-device source guards (S-3107, S-3108), by the governor's `xcodebuild` watch-scheme build, and by the owner's on-wrist check. No agent claims a build, a prompt or a real beat.

## Core scenarios — seeded, fixed (negative = guard marked)

All in `watch/watchos/Tests/WatchSessionEngineTests/WatchSensorCoordinatorTests.swift` unless noted; fixtures from `Harness` + `FakeSensorSource`. Each is red today because `WatchSensorCoordinator` does not exist (compile error at the base: the prover reports `NOT PROVEN: needs mutation`, and the governor applies the listed mutation).

- **S-3100 start.** Active session `s1`, fresh coordinator, `source.heartRateGrant = .granted`. `refresh(session)` → `source.heartRateSubscriptions == 1`, `source.stepsSubscriptions == 1`; `source.beat(96)` → `recorder.readings.heartRate == 96` and one stored `hr` sample for `s1`. Mutation: make `apply` skip `recorder.start` → subscriptions 0.
- **S-3101 end.** After S-3100, the session becomes `completed`; `refresh(completedSession)` → the heart-rate stream is cancelled (a further `beat(120)` stores nothing) and `recordingSessionId == nil`. Mutation: drop the stop branch → the 120 is stored.
- **S-3102 replaced.** Recording for `s1`; `refresh` with an active session `s2` → exactly one stop then one start (`heartRateSubscriptions == 2`), `recordingSessionId == "s2"`, a beat afterwards is stored against `s2`. Mutation: skip the id comparison → no second subscription.
- **S-3103 idempotent.** Five sequential `refresh(active s1)` calls → `heartRateSubscriptions == 1` and `stepsSubscriptions == 1`. Mutation: clear `recordingSessionId` at the end of `apply` → the count rises to 5.
- **S-3104 negative: refused.** A small `CountingSource` declared in the new test file (the shared `FakeSensorSource` is `final` and not edited) answers `.denied` for heart rate and steps and counts probe calls. `refresh(active s1)` twice → no subscription, no sample, probe count 1 per kind (the second refresh does not ask again because the session is already marked recording); `WatchLoggingState.heartRateLabel` is nil; a set logged afterwards is stored (logging unaffected). Negative guard; mutation: clear `recordingSessionId` when the recorder reports no subscription → the probe count rises to 2.
- **S-3105 serial.** Two overlapping `refresh` tasks (one start, one end) via a gate: the calls land in order (start, then stop) and never interleave. Mutation: remove the lock/tail.
- **S-3106 relaunch.** A fresh coordinator over an engine restored with an active session (`engine.restore()`): `refresh` starts sensors (`heartRateSubscriptions == 1`).
- **S-3107 integration to the wire.** Active run (`cardio_endurance`) with the coordinator: beats 120, 140, 160 reported, then the session ends → the emitted session-end event has `avgHeartRateBpm == 140` and `maxHeartRateBpm == 160`; with no beats it has neither field. Mutation: skip `recorder.start` → no fields.
- **S-3108 the live line.** `WatchLoggingState(engine:, sensors: recorder)` while recording: after `beat(142)`, `heartRateLabel == "142"` (the existing view prints "142 bpm"); before any beat it is nil.
- **S-3109 source guard (app target, new file `WatchSensorSourceSourceTests.swift`).** Reads `HealthKitSensorFeed.swift` and `HealthKitWorkoutStore.swift` from `Fixtures.repositoryRoot`: the feed conforms to `WatchSensorSource`; names `HKQuantityType(.heartRate)` and `HKQuantityType(.stepCount)`; `locationPermission()` returns `.unavailable`; no `import CoreLocation`; the store's `requestAuthorization` read set names both types; the store keeps the activity-name labels (19c S-1509 stays green). Mutation: change the store's read list back to `[]` → red.
- **S-3110 host wiring guard (same file).** `ContentView.swift` contains `WatchLoggingState(engine: engine, sensors:`, constructs `WatchSensorCoordinator(`, and the `$revision` sink awaits `workout.refresh` before `sensors.refresh` (line order). Mutation: swap the two awaits → red.

## Phase outline (each one crew run; at most 8 items)

| Phase | Agent | Write scope (`--scope`) | Parallel? | Goal |
|---|---|---|---|---|
| 1A | crew-builder-watch | `watch/watchos/Sources/**,watch/watchos/Tests/WatchSessionEngineTests/WatchSensorCoordinatorTests.swift` | with 2A | `WatchSensorCoordinator` (D-2101, D-2102) + S-3100…S-3108 |
| 2A | crew-builder-watch | `ios/OmniTrain Watch App/HealthKitSensorFeed.swift,ios/OmniTrain Watch App/HealthKitWorkoutStore.swift` | with 1A | the feed and the store changes (D-2103, D-2104, D-2105); NO gateway check run (an in-progress package would not compile); the run reads its own files back |
| gov | governor | — | after 1A and 2A | `xcodebuild` watch scheme build; D-2107 pbxproj text; full `swift-test` + `test` |
| 2B | crew-builder-watch | `ios/OmniTrain Watch App/ContentView.swift,watch/watchos/Tests/WatchSessionEngineTests/WatchSensorSourceSourceTests.swift` | serial | host wiring (D-2106) + S-3109, S-3110 |
| 3 | crew-prover ∥ crew-docs-keeper | `watch/watchos/Tests/**` ∥ `docs/**` | parallel pair | prover: prove-red / mutation list for S-3100…S-3110; docs keeper (update mode): `docs/state_management/watch_surface.md` (51,502 bytes now, ceiling 52,428: REMOVE before adding), `docs/watch-app-setup-and-qa.md` steps 13, 19, 20 (+ new owner step), `docs/watch_session_capture.md` if it claims the wrist does not yet measure, QA index row 19d (`docs/plans/2026-10-08-18-watch-qa-index.md`) |
| 4 | crew-reviewer | `docs/plans/**` | serial | review of `git diff ed14570` |

## Code pointers (verified 2026-10-10 by scouts and the governor)

`WatchSensorRecording.swift`: `WatchSensorSource` :60, `WatchSensorRecorder` :100 (`start` :142, `stop` :161), `WatchSensorWrites` :225, `WatchSessionSensors` :250. `WatchPlatformWorkout.swift`: `WatchWorkoutLifecycle` :230, `WatchWorkoutCoordinator` :254 (`apply` :279, `enqueue` :306). `WatchLoggingState.swift`: `sensors` property :~158, `readings` / `heartRateLabel` :~250-269. `WatchLoggingView.swift`: `sensorLine` :132. `ContentView.swift`: `WatchAppHost.init` :~66, `WatchLoggingState(engine:)` :84, `WatchWorkoutCoordinator(platform: WatchPlatformWorkout(store: HealthKitWorkoutStore()))` :~96-98, the `$revision` sink :~125. `HealthKitWorkoutStore.swift`: class :43, `begin` :62, `end` :96, `inProgressActivityTypes` :114, `resolveAuthorization` :174. Tests: `WatchSensorRecordingTests.swift` `FakeSensorSource` :32, `FakePlatformStore` :84, `testS003TheLoggingSurfaceShowsTheLiveHeartRateAndDistance` :255; `WatchSensorSummaryTests.swift` S-231…S-238; `WatchWorkoutCoordinatorTests.swift` (19c) is the model for the new coordinator tests; `WatchWorkoutStoreSourceTests.swift` is the model for S-3109. Scout sheets: `.work/crew/19d-sensors/pointers-{a,b,c}.md`.

## Owner steps (not simulated, marked (owner) in the QA guide)

Install on a real watch; accept the new Health prompt (workout + heart rate + steps); run a session: the grey "bpm" line moves; end it and sync: the phone's Stats shows an average heart rate for the exercise; decline the permission once and check logging still works.

---

# Architect expansion (2026-10-10)

Everything above is the governor's seed and is unchanged. This section adds the invariants, the impact
table, the edge scenarios, the phased items, and the running records.

## Decisions added by the architect

- **D-2109** Test doubles live in the new test file, and the seam a test can park is the **source**.
  `FakeSensorSource` is `final` (`watch/watchos/Tests/WatchSessionEngineTests/WatchSensorRecordingTests.swift:32`),
  so `WatchSensorCoordinatorTests.swift` declares its own `CountingSource` (probe counts, no streams) and
  `GatedSource` (parks `heartRatePermission()`/`stepsPermission()` on a test-held continuation until
  released). `WatchSensorCoordinator.init(recorder:)` takes the concrete `WatchSensorRecorder`
  (`WatchSensorRecording.swift:100`), so a test cannot park the recorder; parking the source's probe parks
  the recorder inside `start` (`:142-144`), which is the same effect and the only one available.
- **D-2110** Two seeded mutations are replaced by implementable ones, because the seeded forms cannot be
  applied to the code they name (evidence and reasoning in Open questions 1 and 2): S-3104's mutation
  becomes "drop the `recordingSessionId == nil` guard on the start branch of `apply`" (probe count 1 → 2),
  and S-3105's becomes "`refresh` calls `await apply(session)` directly instead of
  `await enqueue { … }.value`" (the parked start's stream is left running → a beat is stored after the end).
  Both are exercised by the architect-added S-3111 and S-3112; the seeded S-3104/S-3105 text stays as
  written and their assertions are unchanged.
- **D-2111** Baselines measured at `ed14570` by the architect this run: `gateway.sh swift-test` →
  **439 tests, 0 failures**; `gateway.sh test test/docs_indexing_contract_test.dart
  test/rest_is_count_up_contract_test.dart` → **19 tests, all passed**. The full `test` suite was not run
  this run; the last recorded full-suite baseline is 19c's (`4240 passed, 1 skipped, 0 failed`), and phase
  3B records today's numbers in the evidence file.
- **D-2112** The docs keeper **removes before it adds** in `docs/state_management/watch_surface.md`: the
  sentence "the sensor seam's implementations are the two suites' fakes and the QA harness's own defaults"
  becomes false the moment `HealthKitSensorFeed` exists, and that page also gains `WatchSensorCoordinator`
  in its structure table. In `docs/watch-app-setup-and-qa.md` the "(needs Phase 8)" tags on steps 19 and
  20 and the paragraph that places them in another plan are roadmap annotations under
  `docs/documentation_standard.md` §3.6/§3.7 and are removed (the steps stay, pointing at this plan and
  its tests). The QA index gains its row 19d. All three files are checked by the two guard suites below.

## Feature invariants (this unit)

- **The sensors follow the session, as the workout does.** One subscription per active session; a change
  of id while recording is a stop then a start; every non-active status (completed, abandoned, gone) stops
  them. The single record of that is `WatchSensorCoordinator.recordingSessionId`. Guarded by S-3100,
  S-3101, S-3102, S-3103, S-3106.
- **The session id is written before the source is asked**, so a refusal is not asked for again while the
  same session is live — the same reason `WatchWorkoutCoordinator.apply` records `openedForSessionId`
  before `platform.start` (`WatchPlatformWorkout.swift:279-292`). Guarded by S-3104/S-3112.
- **The coordinator never throws and never retries.** `refresh` returns `Void`; a refused or absent
  permission cannot fail a log or a sync. The recorder already swallows it per probe
  (`startHeartRate`/`startSteps`, `WatchSensorRecording.swift:182-196`).
- **Nothing measured is absent, never zero** (existing rule, unchanged): a window with no qualifying
  reading gets no field, which is what makes a refused read safe. Pinned by
  `WatchSensorSummaryTests.testS235WithTheSensorsDeniedNoEventCarriesASummary`.
- **`watch/contract/watch_sensor_contract.json` is the one vocabulary.** The feed's units come from it:
  `sampleUnits.hr = beatsPerMinute`, `sampleUnits.steps = cumulativeCount`, and the contract's own
  description ("a sample supersedes the one before it"). The app target adds no second vocabulary.
  Guarded by S-3109 and by the existing contract suites.
- **No new GPS, and the package stays OS-free.** `locationPermission()` answers `.unavailable` and the
  recorder then makes no location subscription (`WatchSensorRecording.swift:146-147`); no file under
  `watch/watchos/Sources/` ever names HealthKit (the module's header states the seam). Guarded by S-3109.
- **Every sentence this unit adds to `docs/` names an existing test**
  (`docs/documentation_standard.md` §4.2), and no doc may call a shipped path pending (§3.6/§3.7).

## Existing-functionality impact

| Touched surface | What already reads it (search, with result) | Effect | Guarded by |
|---|---|---|---|
| `WatchSensorRecorder` (consumed, **not** changed) | `rg WatchSensorRecorder` → 45 matches / 8 files: `WatchSensorRecording.swift:100`, `WatchLoggingState.swift:160,201`, Swift tests `WatchSensorRecordingTests.swift:149,265,737,812` and `WatchLoggingSurfacesTests.swift:652`, the Dart debug surface `lib/watch/debug/watch_session_debug_surface.dart:165`, the Dart recorder `lib/watch/sensors/watch_sensor_recording.dart:89` | the coordinator becomes a second caller; no signature, clock or write-order change | S-3100…S-3108 plus the recorder's own suites unchanged |
| `WatchSessionSensors` | `rg WatchSessionSensors` → only tests and the Dart debug surface: `WatchLoggingSurfacesTests.swift:650`, `WatchSensorRecordingTests.swift:146,735`, `test/watch_sensor_recording_test.dart:151`, `lib/watch/debug/watch_session_debug_surface.dart:160` — **no production caller** (the seed's claim holds) | it keeps its present shape for the Dart debug surface and the existing suites; watchOS production gets the two-coordinator split instead (workout coordinator + sensor coordinator) | the suites above stay green; S-3110 pins the host's two calls |
| `WatchLoggingState` construction | `rg WatchLoggingState(` → production `ios/OmniTrain Watch App/ContentView.swift:78`; tests throughout `watch/watchos/Tests` and `test/`; the `sensors:` parameter is already optional with a `nil` default (`WatchLoggingState.swift:196-201`) | every existing construction keeps compiling and behaving as before; only the host passes a recorder | S-3108, S-3110 |
| `HealthKitWorkoutStore.resolveAuthorization` read set (`:174`, `read: []` at `:181`) | 19c's source guard `WatchWorkoutStoreSourceTests.testS1509TheStoreMapsEveryContractActivityName` reads the file from disk; `ContentView.swift:85` builds the store | one prompt that asks to read two more types; the share set, the activity names, `end()` and recovery are untouched | S-3109 (the read set names both types) + 19c S-1509 must stay green |
| `HealthKitWorkoutStore.begin` (`:62`) | same readers as above | adds `collection.delegate` and two `dataSource.enableCollection` calls before `beginCollection`; begin/end semantics unchanged | S-3109, 19c S-1509, 19c S-1505 (`denial is not failure`) |
| `ios/Runner.xcodeproj/project.pbxproj` usage strings | 19c's Phase 3B read-backs; `scripts/pre_release_check.sh:108-135` (`runner_pbxproj_settings`, which excludes the watch target); `test/pre_release_gate_ios_artifact_test.dart` | text only: three `INFOPLIST_KEY_NSHealthShareUsageDescription` strings; keys, target blocks and the entitlement untouched | the governor's read-back (D-2107) + `gateway.sh test test/pre_release_gate_ios_artifact_test.dart` (12 passed / 0 failed at 19c's close) |
| `WatchSensorSource` protocol (`WatchSensorRecording.swift:60`) | `FakeSensorSource` (Swift, `final`), `_FakeSensorSource` (`test/watch_sensor_recording_test.dart:61`), `_NoSensors` (`lib/watch/debug/watch_session_debug_surface.dart:65`), and the new app-target feed | **no change**: the protocol already carries all three permissions and three streams, which is why this unit is app-target-only and the Dart pair is untouched | the three suites above stay green; S-3109 pins the new conformance |
| docs: `watch_surface.md`, `watch-app-setup-and-qa.md`, `watch_session_capture.md`, the QA index | `test/docs_indexing_contract_test.dart` (ceiling, warning band, links, orphans, hex, flow, roadmap) and `test/rest_is_count_up_contract_test.dart` (rest wording, scans `watch/watchos/Sources` and the docs) | the sensor section's "the sensor seam's implementations are the two suites' fakes and the QA harness's own defaults" goes false and is replaced; the QA guide's "(needs Phase 8)" tags are prohibited roadmap prose and are removed | both guard suites — 19 tests green at HEAD (measured, D-2111) |

## Edge scenarios (architect-added, continuing S-3110)

All in `watch/watchos/Tests/WatchSessionEngineTests/WatchSensorCoordinatorTests.swift`. Every one is red at
HEAD for the same first reason — the file does not exist, so `swift-test` does not compile — and the
mutation named is what the governor applies to prove the assertion (D-2108).

- **S-3111 the serial tail holds while a start is parked mid-probe (S-3105's implementable form).**
  Fixture: `GatedSource`, both kinds `.granted` once released; active `s1`, then a second active session
  `s2`. Sequence: `await coordinator.refresh(s1)` to completion (`heartRateSubscriptions == 1`,
  `recordingSessionId == "s1"`); arm the gate; `let replaced = Task { await coordinator.refresh(s2) }`;
  wait until the gate reports parked (the start's id is already `"s2"`, D-2101); `let ended = Task { await
  coordinator.refresh(nil) }`; release; `await replaced.value`; `await ended.value`. Expected:
  `recordingSessionId == nil`, `heartRateSubscriptions == 2`, and after `source.beat(120)` plus a bounded
  number of scheduler yields (`WatchWorkoutCoordinatorTests.yieldUntil` is the precedent, `:188-196`)
  `engine.newestSensorSample(WatchSensorKind.heartRate)` is still the pre-`s2` sample — the parked start's
  stream was cancelled by the end that waited for it. Red without the change: **mutation — `refresh`
  awaits `apply(session)` directly instead of `enqueue { … }.value`** — `ended` then runs while `replaced`
  is parked, clears the id, and `replaced` resumes and finishes subscribing, so the beat is stored against
  a session that is over. Checked: with a stamped and a counted write the assertion is exact, and no
  `Task.sleep` is needed anywhere.
- **S-3112 the refused probe is asked once (S-3104's implementable form).** Fixture: `CountingSource`
  answering `.denied` for heart rate and steps (`locationPermission()` `.denied` too, so the recorder's
  location guard is exercised), counting each probe. `await coordinator.refresh(s1)` twice with `s1`
  active. Expected: `heartRateSubscriptions == 0`, `stepsSubscriptions == 0`, heart-rate probes 1, steps
  probes 1, `WatchLoggingState(engine: engine, sensors: recorder).heartRateLabel == nil`, and a set logged
  afterwards is stored (the "logging is unaffected" half of S-3104). Red without the change: **mutation —
  drop the `recordingSessionId == nil` guard on the start branch** — the second refresh asks again and the
  probe counts read 2.
- **S-3113 one kind granted, the other refused.** Fixture: `FakeSensorSource` with `heartRateGrant =
  .granted`, `stepsGrant = .denied`. `await coordinator.refresh(s1)`; `source.beat(150)`;
  `source.count(300)`. Expected: `heartRateSubscriptions == 1`, `stepsSubscriptions == 0`, exactly one
  `hr` sample of 150 for `s1` and **no** `steps` sample,
  `WatchLoggingState(engine: engine, sensors: recorder).heartRateLabel == "150"` (`String(Int(rounded))`,
  `WatchLoggingState.swift:258-270`). Red without the change: **mutation — `apply` starts only when
  `source.stepsPermission()` is granted as well** (one probe deciding both kinds) — the heart-rate
  subscription never happens and the label stays nil.
- **S-3114 the feed never opens a prompt of its own (source guard, same file as S-3109).** The guard reads
  `ios/OmniTrain Watch App/HealthKitSensorFeed.swift` and asserts: the text `requestAuthorization` does not
  appear in the feed; the feed names `HKHealthStore.isHealthDataAvailable()`; and it answers `.unavailable`
  when that is false (D-2104's first branch). Negative guard: red today because the file does not exist.
  Mutation: add any `requestAuthorization` call to the feed → red.
- **S-3115 a timed entry carries the step total the coordinator fed it.** Fixture: `Harness`; an active run
  (`cardio_endurance`) on the slot S-235 uses
  (`["sessionExerciseId": "sx-run", "exerciseId": "ex-run", "name": "Run", "capabilities": ["time",
  "distance"]]`, `WatchSensorSummaryTests.swift:236`); a `WatchSensorRecorder(engine:source:clock:)`
  over `FakeSensorSource`; `source.count(0)` before the work window, then `source.count(800)`,
  `source.count(1600)`, `source.count(3200)` with the clock advanced between each (equal instants would
  produce equal record ids and the second row would be a no-op); wait for the four rows to be stored;
  `surface.startWork()`; `surface.log()`. Expected: the entry's `steps` field is **3200** — the chain rule
  of `WatchSensorSummaries.steps` (`previous` = the last count strictly before the window, then each
  forward step added: 800 + 800 + 1600). Red without the change: **mutation — `steps` returns the first
  in-window count instead of the accumulated total** → 800. (The wire field is `steps`, not a
  `stepsTotal`; every field name here is the one `WatchSensorSummaryTests` asserts on.)

### Acceptance criteria → scenarios

| Criterion | Scenarios |
|---|---|
| 1 (samples stored, live readout shows the newest beat) | S-3100, S-3106, S-3108, S-3113 |
| 2 (existing builders carry the summaries) | S-3107, S-3115, and the existing S-231…S-238 unchanged |
| 3 (run exactly while active; id change; relaunch; one start per refresh) | S-3100, S-3101, S-3102, S-3103, S-3106, S-3111 |
| 4 (refusal or absent hardware skips the subscription) | S-3104, S-3112, S-3113, S-3114 |
| 5 (no GPS) | S-3109 (`locationPermission()` → `.unavailable`, no `import CoreLocation`), plus existing S-001/S-002/S-008 |
| 6 (one prompt, both read types, owner-wording usage text) | S-3109, S-3110, S-3114; D-2107 is the governor's text change |

## Phases

### Phase 1A — the coordinator (crew-builder-watch)

**Write scope**: `watch/watchos/Sources/**,watch/watchos/Tests/WatchSessionEngineTests/WatchSensorCoordinatorTests.swift`
**Runs in parallel with 2A** — the write scopes are disjoint (`watch/` vs the app target), and neither
reads the other's files.

1. [ ] Add `WatchSensorCoordinator` — `watch/watchos/Sources/WatchSessionEngine/WatchSensorCoordinator.swift` · `WatchSensorCoordinator` (class, `recordingSessionId`, `refresh(_:)`, `apply(_:)`, `enqueue(_:)`, D-2101)
2. [ ] Cover start, end, replacement and idempotence — `watch/watchos/Tests/WatchSessionEngineTests/WatchSensorCoordinatorTests.swift` · `testS3100…`, `testS3101…`, `testS3102…`, `testS3103…` (S-3100…S-3103)
3. [ ] Declare `CountingSource` and cover the refused probe — same file · `CountingSource`, `testS3104…`, `testS3112…` (S-3104, S-3112)
4. [ ] Declare `GatedSource` and cover the serial tail — same file · `GatedSource`, `testS3111…` (S-3105's seeded text, proved by S-3111's mutation, D-2110)
5. [ ] Cover a relaunch onto a restored active session — same file · `testS3106…` (S-3106)
6. [ ] Cover the session-end pair and the step total through the real recorder — same file · `testS3107…`, `testS3115…` (S-3107, S-3115)
7. [ ] Cover the live label and the mixed and absent permissions — same file · `testS3108…`, `testS3113…` (S-3108, S-3113)
8. [ ] Append phase 1A's rows to the evidence file and record the totals — `…19d-watch-heart-rate-and-steps-plan.evidence.md` · "Phase 1A"

**Done Criteria**: `.github/copilot/scripts/macos/gateway.sh swift-test` — 439 baseline tests (measured at
`ed14570`) plus the new ones, **0 failures**, counts pasted;
`.github/copilot/scripts/macos/gateway.sh prove-red HEAD swift-test` — must FAIL at HEAD, because
`WatchSensorCoordinator` does not exist there (paste the failing line into the evidence file; when
`prove-red` reports `NOT PROVEN: needs mutation`, the listed mutation is the one under each scenario above
and 19c's Assumption Log entry is the precedent).
**Predicted Files**: `watch/watchos/Sources/WatchSessionEngine/WatchSensorCoordinator.swift` (new);
`watch/watchos/Tests/WatchSessionEngineTests/WatchSensorCoordinatorTests.swift` (new); this plan's
`.evidence.md`.

### Phase 2A — the feed and the store (crew-builder-watch) — **no gateway check in this run**

**Write scope**: `ios/OmniTrain Watch App/HealthKitSensorFeed.swift,ios/OmniTrain Watch App/HealthKitWorkoutStore.swift`
**Runs in parallel with 1A.** This phase's Done Criteria are the read-back only: the package does not
compile the app target, and 1A's `WatchSensorCoordinator.swift` is in flight, so a gateway run here would
be measuring an in-progress package. The builder reads its own files back and pastes them into the
evidence file.

1. [ ] Add the feed, its continuations and its delegate conformance — `ios/OmniTrain Watch App/HealthKitSensorFeed.swift` · `HealthKitSensorFeed` (D-2103)
2. [ ] Reduce each collected sample to the wire's unit, dropping a non-finite or sub-1.0 beat — same file · `workoutBuilder(_:didCollectDataOf:)`, `workoutBuilderDidCollectEvent(_:)` (D-2103)
3. [ ] Answer the three permission probes from the store's resolution, never by prompting — same file · `heartRatePermission()`, `stepsPermission()`, `locationPermission()` (D-2104, S-3114)
4. [ ] Ask to read both types in the same authorization call — `ios/OmniTrain Watch App/HealthKitWorkoutStore.swift` · `resolveAuthorization` (`:174`, `read:` at `:181`) (D-2105)
5. [ ] Make the builder collect both types and hand itself the feed as delegate — same file · `begin` (`:62`) — `collection.delegate`, `dataSource.enableCollection(for:predicate:)` (D-2105)
6. [ ] Expose the feed and the authorization outcome without a reference cycle — same file · `sensorSource`, the init closure (D-2105)
7. [ ] Read all three files back and record the read-back in the evidence file — `.evidence.md` · "Phase 2A" (no check run, by the seed's rule)

**Done Criteria**: no gateway check run (an in-progress package would not compile); the evidence file holds
the read-back of the two app-target files and the D-2105/D-2103 claim-by-claim walk. The phase is
*compiled* by the next phase's governor step, not by the builder.
**Predicted Files**: `ios/OmniTrain Watch App/HealthKitSensorFeed.swift` (new);
`ios/OmniTrain Watch App/HealthKitWorkoutStore.swift`; this plan's `.evidence.md`.

### Governor step (after 1A and 2A)

`xcodebuild` on the watch scheme; the D-2107 pbxproj text; the full `swift-test` + `test` runs. Not a crew
run.

### Phase 2B — the host wiring and the app-target guards (crew-builder-watch)

**Write scope**: `ios/OmniTrain Watch App/ContentView.swift,watch/watchos/Tests/WatchSessionEngineTests/WatchSensorSourceSourceTests.swift`
**Serial** — it needs 2A's store to have a `sensorSource`, and its guards read 2A's files; 1A's package
compiles independently.

1. [ ] Keep the store the host already builds, and its feed with it — `ios/OmniTrain Watch App/ContentView.swift` · `WatchAppHost.init` (`:84-85`)
2. [ ] Build the recorder and the coordinator and give the surface its sensors — same file · `WatchLoggingState(engine: engine, sensors: recorder)` (D-2106)
3. [ ] Refresh the workout first, then the sensors, in the one sink — same file · the `$revision` sink (`:133-140`) (D-2106)
4. [ ] Add the source guard for the feed and the store's read set — `watch/watchos/Tests/WatchSessionEngineTests/WatchSensorSourceSourceTests.swift` · `testS3109…` (S-3109)
5. [ ] Add the host-wiring guard for the three host lines — same file · `testS3110…` (S-3110)
6. [ ] Add the feed's no-prompt guard — same file · `testS3114…` (S-3114)
7. [ ] Run the package suite and record the totals and the guard's `prove-red` result — `.evidence.md` · "Phase 2B"

**Done Criteria**: `.github/copilot/scripts/macos/gateway.sh swift-test` — 0 failures, counts pasted;
`.github/copilot/scripts/macos/gateway.sh prove-red HEAD swift-test` — S-3109/S-3110/S-3114 must FAIL at
HEAD (neither file exists there); **(governor)** the watch target compiles with the host wired.
**Predicted Files**: `ios/OmniTrain Watch App/ContentView.swift`;
`watch/watchos/Tests/WatchSessionEngineTests/WatchSensorSourceSourceTests.swift` (new); this plan's
`.evidence.md`.

### Phase 3A — prover (crew-prover) ∥ Phase 3B — docs keeper (crew-docs-keeper)

**Write scopes**: `watch/watchos/Tests/**` ∥ `docs/**`. They run in parallel: disjoint trees, and the
prover only mutates and restores.

**3A items**

1. [ ] Re-package the six coordinator scenarios and prove each red — `watch/watchos/Tests/WatchSessionEngineTests/WatchSensorCoordinatorTests.swift` · S-3100…S-3108, S-3111…S-3113, S-3115
2. [ ] Prove the three source guards red and record the mutation for each — `…WatchSensorSourceSourceTests.swift` · S-3109, S-3110, S-3114
3. [ ] Record the verdict per scenario in the evidence file — `.evidence.md` · "Prover verdicts"

**3B items**

1. [ ] Remove the stale sensor-seam sentence before adding anything — `docs/state_management/watch_surface.md` · "Watch Sensors and the Platform Workout"
2. [ ] Add `WatchSensorCoordinator` and the real feed to the structure table and its seam paragraph — same file · same section (D-2112)
3. [ ] Move steps 19 and 20 out of the other plan and point them at this one and its tests — `docs/watch-app-setup-and-qa.md` · steps 19, 20 and the paragraph above them (D-2112)
4. [ ] Point step 13's sensor path at this plan's tests — same file · step 13
5. [ ] Add the owner step for the new prompt — same file · the `(owner)` block (D-2108's proof boundary)
6. [ ] Correct the wrist code as it is now (the sensor path exists) — `docs/watch_session_capture.md` · the sentence that calls the wrist's measuring unshipped
7. [ ] Add row 19d to the series index — `docs/plans/2026-10-08-18-watch-qa-index.md` · the PRs table (row 19c is at `:21`)
8. [ ] Run the two guard suites and the full suite, and record the numbers — `.evidence.md` · "Phase 3B"

**Done Criteria (3B)**: `.github/copilot/scripts/macos/gateway.sh test test/docs_indexing_contract_test.dart test/rest_is_count_up_contract_test.dart`
— green (19 tests at HEAD, measured; the ceiling, the warning band, the link/orphan guards, the roadmap
guard and the rest-wording scanner are exactly what this phase can break);
`.github/copilot/scripts/macos/gateway.sh test` — the full suite green with 0 failures, counts pasted
(19c's recorded baseline: 4240 passed, 1 skipped); `.github/copilot/scripts/macos/gateway.sh lint` —
compared with the recorded issue count.
**Done Criteria (3A)**: `.github/copilot/scripts/macos/gateway.sh swift-test` — unchanged 0 failures;
`prove-red` receipts for every scenario pasted into the evidence file.
**Predicted Files (3B)**: the four doc files above; this plan's `.evidence.md`.
**Predicted Files (3A)**: `watch/watchos/Tests/WatchSessionEngineTests/WatchSensorCoordinatorTests.swift`
and `…WatchSensorSourceSourceTests.swift` (mutations restored byte-for-byte); this plan's `.evidence.md`.

### Phase 4 — review (crew-reviewer)

**Write scope**: `docs/plans/**`. Serial. Reviews `git diff ed14570` against this plan's Done Criteria and
writes the `.review.md` (the architect does not create it).

## Progress

| Phase | Item | State |
|---|---|---|
| 1A | 1 source file | done |
| 1A | 2 S-3100…S-3103 | done |
| 1A | 3 S-3104, S-3112 | done |
| 1A | 4 S-3105 prose, S-3111 proof | done |
| 1A | 5 S-3106 | done |
| 1A | 6 S-3107, S-3115 | done |
| 1A | 7 S-3108, S-3113 | done |
| 1A | 8 evidence rows | done (recovered from report-1A) |
| 2A | 1 feed | done |
| 2A | 2 sample reduction | done |
| 2A | 3 probes | done |
| 2A | 4 read set | done |
| 2A | 5 collection | done |
| 2A | 6 store seam | done |
| 2A | 7 read-back | done (recovered from report-2A) |
| 2A fix | F-1 / D-2113 `nonisolated` declaration | done (report-2A-fix) |
| gov | xcodebuild, pbxproj text, full suites | xcodebuild ×2 BUILD SUCCEEDED; D-2107 done; 452 by the governor; full `flutter test` + analyze still pending |
| 2B | 1 store kept | done |
| 2B | 2 recorder + coordinator | done |
| 2B | 3 sink order | done |
| 2B | 4 S-3109 | done |
| 2B | 5 S-3110 | done |
| 2B | 6 S-3114 | done |
| 2B | 7 evidence rows | done |
| 3A | 1–3 prove-red | done (RED AT ed14570 from a compile error; guards proved by the governor's mutations, see the evidence file's Prover verdicts) |
| 3B | 1–8 docs | done (full suite + lint are the governor's) |
| gov | mutations, final suites | done (13 mutations + 2 variants, 1 initial MISS on S-3115 fixed and re-proven; 456/0 by the governor; flutter analyze 196/0 errors; flutter test +4240 ~1; layer invariant clean) |
| 4 | review round 1 | done (APPROVE WITH FIXES; see the `.review.md`'s Round 1 outcome) |
| fix | fix round 1 | done |

## Assumption Log

- **2A (crew-builder-watch):** the store's feed is a `private lazy var sensorFeed =
  HealthKitSensorFeed { [weak self] in … }` built on first use over a `[weak self]` authorization
  closure, not an implicitly unwrapped optional assigned in `init()` — it needs no `init()` body
  change, and `init()` stays empty as before (report-2A, item B3).
- **2B (crew-builder-watch):** on disk `HealthKitSensorFeed.locationPermission()` is an
  implicit-return body (`.unavailable`, no `return` keyword), so S-3109 checks the body contains
  `.unavailable` and no `.granted` rather than a literal `return` (report-2B, Open questions).
- **3A (governor):** the S-3115 fixture changed after the governor's mutation run (pre-window count
  500, expected 2700) because the original fixture could not distinguish a chain starting at 0
  (ratified by the governor).

## Feedback

- **F-1 (governor, 2026-10-10, after the first watch-scheme build)** The app target builds with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (Xcode 26.4.1, Swift 5 mode; `project.pbxproj:673`), so `HealthKitSensorFeed` was silently main-actor-bound while HealthKit calls its `HKLiveWorkoutBuilderDelegate` methods on its own queues: two compiler warnings (`HealthKitSensorFeed.swift:93`, `:115`) and a probable runtime isolation trap on a real watch. **D-2113**: the class is declared `nonisolated final class HealthKitSensorFeed`, so none of its members is main-actor-bound; the `HealthKitWorkoutStore` that owns it stays as it is. **S-3116** (source guard, in `WatchSensorSourceSourceTests.swift`, phase 2B): the feed's declaration line contains `nonisolated` and `final class HealthKitSensorFeed`. Mutation: delete `nonisolated` from the declaration, the guard goes red. Proof on the app target: the governor's `xcodebuild` shows no isolation warning for the feed.
- **D-2114 (review round 1, 2026-10-10)** Authorization is one memoised in-flight request shared by the workout and the feed: `HealthKitWorkoutStore.resolveAuthorization` stores the `Task<Bool, Never>` and concurrent callers await its value, instead of a second caller reading a half-settled answer while the first request is still in flight. **S-3117** (source guard, in `WatchSensorSourceSourceTests.swift`, fix round 1): the store source holds `collection.delegate = sensorFeed` and both `dataSource.enableCollection(for: HKQuantityType(.heartRate/.stepCount), predicate: nil)` calls. Mutations N1 (delete the delegate line) and N2 (drop the steps call) each turn exactly S-3117 red; N3 (the recorder built over a second private store) turns exactly S-3110 red.

## Open questions

1. **S-3104's seeded mutation cannot be applied.** "Clear `recordingSessionId` when the recorder reports no
   subscription" needs the recorder to report something back: `WatchSensorRecorder.start` and `.stop` both
   return `Void` (`watch/watchos/Sources/WatchSessionEngine/WatchSensorRecording.swift:142,161`) and nothing
   in the recorder tells its caller what it subscribed to. Two readings of the seed's fixture also need
   pinning: `heartRatePermission()`/`stepsPermission()` are asked once **per `start`** (`:143-144`,
   `:183`, `:194`), so "probe count 1 per kind" holds only while the start is skipped; and "a set logged
   afterwards is stored" needs an exercise slot, because `canLog` is `engine.session?.status == active &&
   slot != nil` (`WatchLoggingState.swift:235`). D-2110's replacement mutation (drop the
   `recordingSessionId == nil` guard on the start branch, probe count 1 → 2) is implementable and
   distinguishes the guard; it is proved by S-3112.
2. **S-3105's seeded mutation ("remove the lock/tail") is applicable but under-specified, and the seed's
   fixture does not say where the gate is.** `WatchSensorCoordinator.init` takes the concrete
   `WatchSensorRecorder` (D-2101), so the only seam a test can park is the `WatchSensorSource` protocol the
   recorder probes. 19c's precedent for the same proof is different in kind: `ScriptedPlatformStore`
   parks the store's own `begin` (`WatchWorkoutCoordinatorTests.swift:45-133`), which is available there
   because `WatchPlatformWorkout` *is* the coordinator's injected dependency. S-3111 therefore parks the
   source's permission probe and asserts the end state the interleave would break; the mutation is
   "`refresh` bypasses `enqueue`". If the reviewer prefers, the alternative is to give the coordinator a
   protocol seam over the recorder — a larger change than this unit's budget allows, and it would
   duplicate `WatchSensorSource`.
3. **S-3108's mutation is not stated in the seed.** The candidate used here is "read the newest sample
   regardless of the session id" — but that lives in `WatchSessionEngine`, not in the new file, and the
   label's own reader is `WatchLoggingState.sensorLabels` (`:258-268`). The scenario may equally be proved
   by the mutation that removes the coordinator's start (S-3100's mutation), which is in the new file; the
   prover should say which it applied.
4. **D-2103's HealthKit spellings are unverified off-device.** The store's *existing* calls are witnessed
   in `ios/OmniTrain Watch App/HealthKitWorkoutStore.swift` (`HKWorkoutSession(healthStore:configuration:)`,
   `opened.associatedWorkoutBuilder()`, `collection.dataSource = HKLiveWorkoutDataSource(…)`,
   `opened.startActivity(with:)`, `beginCollection(at:)`, `endCollection(at:)`, `finishWorkout()`,
   `recoverActiveWorkoutSession()`, `requestAuthorization(toShare:read:)`, `authorizationStatus(for:)`,
   `isHealthDataAvailable()`), and `rg HKQuantityType|mostRecentQuantity|sumQuantity|enableCollection|HKStatistics|HKLiveWorkoutBuilderDelegate|HKUnit`
   found matches **only inside this plan file** — so none of the new spellings (`HKQuantityType(.heartRate)`,
   `HKQuantityType(.stepCount)`, `statistics.mostRecentQuantity()`, `statistics.sumQuantity()`,
   `HKUnit.count().unitDivided(by: .minute())`, `dataSource.enableCollection(for:predicate:)`,
   `HKLiveWorkoutBuilderDelegate`) is witnessed anywhere in the tree. The gateway has no SDK or
   `xcodebuild`, so no agent can compile them: they are confirmed only by the governor's watch-scheme
   build. If a spelling is wrong, the fix is 2A's file and a re-run of the governor's build.
5. **D-2106's `ContentView.swift` line numbers are approximate in the seed** (`:~66-130`, `:~96-98`,
   `:~125`) while the same plan states the other pointers as exact. Measured today: `let logging =
   WatchLoggingState(engine: engine)` at `:78`, `WatchWorkoutCoordinator(platform: WatchPlatformWorkout(store:
   HealthKitWorkoutStore()))` at `:84-85`, the `$revision` sink at `:133-140` with `await
   self.workout.refresh(self.engine.session)` at `:137`. The seeded numbers are kept as written; phase 2B
   should follow the symbols, not the line numbers.
6. **The seed's `docs/state_management/watch_surface.md` figure ("51,502 bytes now, ceiling 52,428") is not
   reproducible from the guards.** `test/docs_indexing_contract_test.dart` sets `_maxDocBytes = 64 * 1024`
   (`:49`) and the warning band at `round(65536 × 0.80) = 52429` bytes (`:59`, `:155-181`), and both apply
   to this file (it is not in `_recordFiles` or `_recordFolders`, `:56-64`). Since the guard is green at
   HEAD (measured: 19 tests pass), the file is already under 52429 bytes, so 52,428 as a "ceiling" is off
   by one byte. The architect could not measure bytes (no shell beyond the gateway). Phase 3B removes
   before it adds and proves it with the guard, as 19c did.
7. **`WatchSessionSensors` remains production-unused after this unit** (searched: only the two test suites
   and `lib/watch/debug/watch_session_debug_surface.dart:160`). The seed's Overview says the same. Nothing
   in this plan retires it; the reviewer may want to note it as dead code on the watchOS side, or leave it
   as the Dart-parity shape.
8. **S-3115's numbers rest on `WatchSensorSummaries.steps`' chain rule, not on a recorded fixture.** The
   rule is read from source (`WatchSensorSummaries.swift:131-152`): `previous` is the last count strictly
   before the window, so a chain 0 → 800 → 1600 → 3200 inside one window totals 800 + 800 + 1600 = 3200.
   S-231's own fixture (`WatchSensorSummaryTests.swift:64-70`) uses different instants; if the builder finds
   the arithmetic disagreeing, S-231 is the authority and this plan's number is what needs correcting.

## Governor actions

- **D-2107**, as seeded: rewrite the three `INFOPLIST_KEY_NSHealthShareUsageDescription` lines in
  `ios/Runner.xcodeproj/project.pbxproj` (`:653`, `:705`, `:754`) to the owner-approved sentence. The
  project file is outside every crew scope.
- **A new folder or file outside the write scopes**: none. Phase 1A/2A/2B create files inside their own
  scopes; the evidence file already exists.
- **The `xcodebuild` watch-scheme build** and the full `swift-test` + `test` runs, between 1A/2A and 2B.
- **The `(owner)` QA walkthrough** after phase 3B: install on a real watch, accept the new prompt, watch the
  grey line move, end and sync.
