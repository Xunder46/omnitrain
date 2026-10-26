# Feature: 19e — the wrist's distance model (the package half of GPS)

> Status: SEEDED by the governor (2026-10-10), awaiting the architect's expansion
> Next handoff: @crew-architect
> Binding conventions: docs/global_conventions.md; docs/documentation_standard.md; .github/copilot/pr-scope-budget.md
> Base commit: f4b4bc0 (branch claude_develop). Team: the crew (`.claude/crew.md`). Series: 19e (this, package only) then 19f (the CoreLocation feed, the permission and the wiring; planned after 19e lands).

## Overview

GPS distance and pace on the wrist is split by what an agent can prove. This unit is everything that `swift test` can reach, and it ships DORMANT: nothing on the wrist feeds a fix until 19f, so no behaviour a user sees changes, except that the rules below are right when the feed arrives.

What exists: the recorder already records cumulative `gps` samples and settles a `distance` sample on stop (`WatchSensorRecording.swift`, `WatchSensorRecorder.start/stop`), the logging state prints the live distance and pace (`WatchLoggingState.sensorLabels`, pace floor `WatchSensorPace.minDistanceMeters` = 50), and a logged timed effort carries `distanceMeters` (`WatchLoggingState.windowPayload`). What is missing or wrong, found by reading the code with a real GPS in mind:

1. **Nothing turns raw location fixes into the cumulative metres the seam expects** (`WatchSensorSource.location()` yields `WatchLocationFix(distanceMeters:)`, "the platform already tracks the running total"). CoreLocation gives positions, not a running total, so the wrist has to accumulate them: with an accuracy gate, a speed sanity gate and a jitter gate, or a still wrist walks.
2. **A logged effort carries the whole session's distance, not its own.** `windowPayload` writes `readings.distanceMeters`, the newest sample of the session (`WatchLoggingState.swift:~744-756`). The existing test puts the fix BEFORE the user presses Start and still expects it on the effort (`testS004TheLoggedEffortCarriesTheGpsTotal`, `WatchSensorRecordingTests.swift:~275`). With a fake that is invisible; with real GPS a second run in a session would carry the first run's metres, and the walk to the park would count as running.
3. **The entry never says its distance was measured.** The wire has `distanceSource` (`gps`, `entered`, `estimated`; `PROTOCOL.md` "Summary fields", `SyncProtocolValidator.swift:79`), the phone stores it, and a missing source is read as `entered` ("watch sessions never run GPS (D-335)", `lib/core/services/watch_session_importer.dart:~962`). Measured runs must say `gps`, so they stay eligible for cardio efficiency and are not marked estimated (`DistanceSource.isEstimated`).

What a user will see once 19f lands: during a run or a sports session the exercise screen shows the live distance and pace line; each timed effort logs the metres covered between Start and Log; the phone files them as GPS-measured. This unit alone changes nothing a user can see.

## Acceptance criteria

1. A pure tracker turns raw fixes into the cumulative metres of the seam: accurate, monotonic, still-proof, jump-proof.
2. An adapter exposes any raw fix source as the existing `location()` stream and permission probe; each subscription starts a fresh total.
3. A timed effort logs the distance covered inside its own Start→Log window (never the session total, never metres from before Start), as it is measured.
4. A measured distance travels with `distanceSource: "gps"`; no measurement means no `distanceMeters` and no source (unchanged).
5. Everything validates against the existing protocol (no schema change), and the phone's import needs no behaviour change; its stale comment is corrected.
6. Existing behaviour that is not named here is unchanged (no GPS without distance-capable work, denial is not failure, free training never records GPS).

## Resolved Decisions (Ledger) — seeded, fixed

- **D-2200** Scope: this unit adds no CoreLocation code, no permission prompt, no Info.plist key and touches no file under `ios/`. 19f does all of that. Nothing in the watch app calls the new types in this unit; the proof is the package suite.
- **D-2201** Raw input type, new file `watch/watchos/Sources/WatchSessionEngine/WatchDistanceTracker.swift`: `public struct WatchRawFix: Equatable { latitude: Double; longitude: Double; horizontalAccuracyMeters: Double; timestamp: Date; public init(latitude:longitude:horizontalAccuracyMeters:timestamp:) }` and `public struct WatchDistanceTracker` with `public init()`, `public private(set) var totalMeters: Double` and `public mutating func accept(_ fix: WatchRawFix) -> WatchLocationFix?` (nil when the fix adds nothing). Method names avoid the module guard's mutating verbs (D-2204).
- **D-2202** Tracker rules, numbers fixed here as named constants in the same file (`WatchDistanceTracker.maxAccuracyMeters = 30`, `.maxSpeedMetersPerSecond = 20`, `.movementFloorMeters = 2`, `.earthRadiusMeters = 6_371_008.8`): (a) a fix with a negative or non-finite accuracy, an accuracy above 30 m, or a non-finite coordinate is ignored; (b) the first accepted fix is the origin: it sets the reference point and returns nil (total stays 0); (c) for a later fix the great-circle (haversine) distance `d` from the LAST ACCEPTED point is taken; the fix is ignored if its timestamp is not after the last accepted one, or if `d / dt > 20` m/s (a jump, not a person: sprinting cyclist 12 m/s, with room); (d) the fix is ignored (reference NOT moved) if `d < max(2, 0.5 × its horizontalAccuracyMeters)` so a still wrist's drift never accumulates, while a slow creep still adds up once it clears the floor; (e) otherwise `totalMeters += d`, the reference moves to this fix, and the result is `WatchLocationFix(distanceMeters: totalMeters)`. The total never decreases. These are tuning values: the owner's on-wrist run is the calibration (19f's QA step), not a promise of accuracy.
- **D-2203** Adapter, new file `WatchTrackedLocation.swift`: `public protocol WatchRawFixSource { func permission() async -> WatchSensorPermission; func rawFixes() -> AsyncStream<WatchRawFix> }` and `public final class WatchTrackedLocation` with `public init(source: WatchRawFixSource)`, `public func permission() async -> WatchSensorPermission` (passes the source's answer through) and `public func fixes() -> AsyncStream<WatchLocationFix>`: each call creates a NEW `WatchDistanceTracker` and maps the source's raw stream through `accept`, yielding only non-nil results; the returned stream finishes when the raw one does and cancelling it cancels the raw one. The class is plain (no `@MainActor`, no actor), non-throwing. 19f gives `HealthKitSensorFeed` one of these; the existing `WatchSensorSource` protocol is NOT changed.
- **D-2204** Module guards to respect: `testS004NoMutatingOperationExistsAnywhereInTheModule` (`WatchSessionEngineTests.swift:~322`) forbids a 4-space-indented `func` whose name starts with `update|delete|remove|replace|edit|overwrite|write|clear|purge|wipe|reset|drop|truncate|erase|forget|modify|mutate|destroy|set` (optional leading `_`) under `Sources/`, and any new `*Store.swift`; the count-up guard forbids `restSeconds` and a `WatchTimerKind.rest` line within 3 lines of `plannedDurationMs` (`WatchRestIsCountUpTests.swift`). Shared fakes (`FakeSensorSource`, `Harness`, `FakePlatformStore`) are used, never edited.
- **D-2205** Per-effort distance rule, in `WatchLoggingState.windowPayload` (the only place a timed entry's distance is read). For a timed effort: `end = cumulativeMeters(at: loggedAt)`, `start = cumulativeMeters(at: workTimer.startedAt)`, `distance = max(0, end − start)`, where `cumulativeMeters(at: t)` is the value of the newest stored `gps` sample whose `recordedAt` is at or before `t`, or 0 when there is none. The payload gets `distanceMeters` only when `isMeasuringDistance` and `distance > 0` (as today: `covered > 0`). The settled `distance` sample (written on stop) is not read here: it is the session total for the live readout. The rule is a function of stored samples and timestamps, so it survives a relaunch.
- **D-2206** Source: when `distanceMeters` is added by D-2205 the payload also gets `"distanceSource": "gps"`. Not added in any other case (never alongside a missing distance: the validator refuses that, `distanceSourceRejections`). Round efforts still carry no distance. Nothing in the protocol, the schemas or the fixtures changes: `fixtures/valid/observations_up_distance_source.json` already holds a `gps` event.
- **D-2207** Existing tests changed on purpose, because D-2205 redefines what an effort's distance is (the fix must now arrive between Start and Log): `testS004TheLoggedEffortCarriesTheGpsTotal` (`WatchSensorRecordingTests.swift:~275`) and `testAMeasuredDistanceIsWhatTheObservationCarries` (`:~901`). Their fixtures move the fix after `startWork()`; their expected numbers stay (3000, 3200), and each also asserts `distanceSource == "gps"`. No other existing test is edited; if one turns red unpredicted, stop and report.
- **D-2208** Phone side: no behaviour change. The importer already stores the wire's `gps` (`watch_session_importer.dart:~958-971`, `_knownDistanceSource`) and the cardio-efficiency read admits any non-estimated source. Only two comments say "watch sessions never run GPS" (`watch_session_importer.dart:~962-963`, header of `test/distance_source_import_test.dart:6-7`): they are rewritten to say an absent source means a hand-entered distance.

## Core scenarios — seeded, fixed

Tracker/adapter scenarios in `watch/watchos/Tests/WatchSessionEngineTests/WatchDistanceTrackerTests.swift`; effort scenarios in `.../WatchEffortDistanceTests.swift`. All red today because the types do not exist (compile error at the base: the prover reports `NOT PROVEN: needs mutation`, the governor applies the mutation named). Fixture arithmetic re-derived with the haversine formula on a 6,371,008.8 m sphere at latitude 52°N, longitude 5°E: 0.0010° of latitude = 111.195 m, 0.0020° = 222.390 m, 0.00002° = 2.224 m, 0.045° = 5003.779 m.

- **S-3200 accumulates.** Fixes (lat, lon, accuracy, t): (52.0000, 5.0, 5, t0), (52.0010, 5.0, 5, t0+30 s), (52.0020, 5.0, 5, t0+60 s). Results: nil; 111.195 (±0.01); 222.390 (±0.01). Mutation: drop `totalMeters +=` (assign `d`) → 111.195 on the third.
- **S-3201 accuracy gate.** An origin with accuracy 80 is ignored (nil, then the next accurate fix is the origin); a fix with accuracy −1 and one with accuracy 31 add nothing; accuracy 30 is accepted. Mutation: raise the limit to 100 → red.
- **S-3202 jump gate.** After the origin and one accepted step (111.195), a fix at (52.045, 5.0) one second later (5003.779 m → 5003 m/s) is ignored and does not move the reference; the next fix at (52.0020, 5.0) 30 s after the step is accepted and the total is 222.390. Mutation: remove the speed gate → the total jumps to 5003.779.
- **S-3203 stillness.** Origin, then ten fixes alternating (52.00002, 5.0) and (52.0, 5.0) with accuracy 10 (each 2.224 m from the reference, floor `max(2, 5) = 5`): total stays 0. Mutation: floor 0 → total > 0.
- **S-3204 creep adds up.** Accuracy 3 (floor 2): a fix 2.224 m from the reference adds (total 2.224); the reference moved. Mutation: compare against the previous RAW fix instead of the last accepted → red in S-3203 or here.
- **S-3205 time order.** A fix with a timestamp not after the last accepted one is ignored. Mutation: drop the check → a same-instant fix adds.
- **S-3206 adapter.** A fake `WatchRawFixSource` (permission `.granted`, a stream the test feeds): `permission()` passes through `.denied`, `.unavailable`, `.granted`; `fixes()` yields cumulative metres 111.195 then 222.390 for the S-3200 fixes and nothing for the origin; a SECOND `fixes()` call starts at 0 (feeding the same coordinates again yields 111.195 first). Mutation: share one tracker across calls → the second subscription's first value is 333.585.
- **S-3207 end to end with the recorder.** `WatchSensorRecorder(engine:, source:)` over a source whose `location()` is a `WatchTrackedLocation`'s stream and whose permission is `.granted`, cardio session: after the S-3200 fixes `recorder.readings.distanceMeters ≈ 222.390`, `isMeasuringDistance == true`; `stop()` settles one `distance` sample ≈ 222.390. With raw permission `.denied`: no location subscription, `isMeasuringDistance == false`, `readings.distanceMeters == nil`, a set logged afterwards is stored (denial is not failure).
- **S-3208 an effort carries its own metres.** `Harness`, cardio session, cumulative `gps` samples via `FakeSensorSource.fix`: Start at t0, fix(3000) at t0+600 s, Log at t0+1200 s → payload `distanceMeters == 3000`; second effort: Start at t0+1500 s, fix(4500) at t0+2000 s, Log at t0+2100 s → `distanceMeters == 1500` (today: 4500). Mutation: read `readings.distanceMeters` (the newest sample) instead of the window difference → 4500.
- **S-3209 metres before Start are not the effort's.** fix(800) before `startWork()`; Start; fix(2800) before Log → payload `distanceMeters == 2000` (today: 2800). Mutation: `start = 0`.
- **S-3210 the source travels.** The S-3208 first-effort payload has `distanceSource == "gps"`; it passes `SyncProtocolValidator` as an `observations_up` timed entry (the test builds the event the way `WatchSensorSummaryTests` do and validates it); an effort logged with no fix has NO `distanceMeters` and NO `distanceSource`. Mutation: drop the source line → red.
- **S-3211 negative: a window with no movement.** Start, fix(3000) BEFORE Start only, Log → no `distanceMeters` (end − start = 0), no `distanceSource`; the effort is still logged. Negative guard; mutation: `max(0, …)` → `abs(…)` is not observable here, so the mutation is "use the end value alone" → 3000 appears.
- **S-3212 relaunch.** Same samples as S-3208 first effort, but the state is rebuilt from a restored engine before Log: the payload is the same (the rule reads stored samples, not memory). Mutation: cache the start value in a property → red after the rebuild.
- **S-3213 changed tests.** `testS004TheLoggedEffortCarriesTheGpsTotal` and `testAMeasuredDistanceIsWhatTheObservationCarries` pass with the fix after Start and assert `distanceSource == "gps"` (D-2207).

## Phase outline (each one crew run; at most 8 items)

The two builders share the Swift package, so they run one after the other (a half-written file would break the other's compile).

| Phase | Agent | Write scope (`--scope`) | Parallel? | Goal |
|---|---|---|---|---|
| 1A | crew-builder-watch | `watch/watchos/Sources/WatchSessionEngine/WatchDistanceTracker.swift,watch/watchos/Sources/WatchSessionEngine/WatchTrackedLocation.swift,watch/watchos/Tests/WatchSessionEngineTests/WatchDistanceTrackerTests.swift` | with 2A | D-2201, D-2202, D-2203; S-3200..S-3207 |
| 2A | crew-builder-app | `lib/core/services/watch_session_importer.dart,test/distance_source_import_test.dart` | with 1A | D-2208: the two comments only; the Dart distance tests stay green |
| 1B | crew-builder-watch | `watch/watchos/Sources/WatchSessionEngine/WatchLoggingState.swift,watch/watchos/Tests/WatchSessionEngineTests/WatchEffortDistanceTests.swift,watch/watchos/Tests/WatchSessionEngineTests/WatchSensorRecordingTests.swift` | serial after 1A | D-2205, D-2206, D-2207; S-3208..S-3213 |
| gov | governor | — | after 1B | full `swift test`, `flutter analyze` and `flutter test`; `xcodebuild` watch scheme (the app target is untouched, a regression check) |
| 3 | crew-prover ∥ crew-docs-keeper | `watch/watchos/Tests/**` ∥ `docs/**` | parallel pair | prover: mutation specs for S-3200..S-3213 (with the arithmetic shown); docs: `docs/state_management/watch_sensors.md` (new types, the per-effort rule), `docs/distance_source.md` (a wrist-measured distance now exists as a type and rule; GPS source says what feeds it only in 19f), `docs/watch_session_capture.md` (fix its pointer to the sensors section: now `state_management/watch_sensors.md`), QA index row 19e |
| 4 | crew-reviewer | `docs/plans/**` | serial | review of `git diff f4b4bc0` |

## Code pointers (verified 2026-10-10 by scouts)

`WatchSensorRecording.swift`: `WatchLocationFix` ~:96 (cumulative metres), `WatchSensorSource.location()`, `WatchSensorRecorder.readings` ~:176, `start` ~:199 (location only when `WatchGpsPolicy.isRequired` and permission granted), `stop` ~:216 (settles a `distance` sample from the newest `gps`). `WatchRecords.swift` `WatchSensorKind` ~:126. `WatchLoggingState.swift`: `WatchSensorPace` ~:122, `isMeasuringDistance` ~:248, `sensorLabels` ~:257, `windowPayload(loggedAt:coversDistance:)` ~:744, the timed route ~:726 (`windowPayload(loggedAt: loggedAt, coversDistance: true)`), `workTimer?.startedAt`. `WatchSessionEngine.swift`: `newestSensorSamples` ~:165, `storedSensorSamples`, `sensorSamples`. `WatchPlatformWorkout.swift`: `WatchGpsPolicy` ~:108. Tests: `WatchSensorRecordingTests.swift` `FakeSensorSource` :32 (`fix(_:)` :72), S-002 :197/:213, S-004 :275/:297, S-006 :375, `testAMeasuredDistanceIsWhatTheObservationCarries` ~:901; models for the new test files: `WatchSensorCoordinatorTests.swift` (19d) and `WatchSensorSummaryTests.swift` (`fullCase`, validator use). Protocol: `PROTOCOL.md` "Summary fields" ~:296, `SyncProtocolValidator.swift` :79, :369-379. Phone: `watch_session_importer.dart` :958-971, :1624-1625, :1738-1742; `lib/core/utils/distance_source.dart`; `docs/distance_source.md` :18, :96, :167. Scout sheets: `.work/crew/19e-gps/pointers-{a,b,c}.md`.

## Owner steps

None in this unit (it ships dormant). 19f will ask for the Location permission wording and add the on-wrist run check.

---

# Architect expansion (2026-10-10)

Everything above is the governor's seed and is kept as written. The line numbers below were measured this
run at base commit `f4b4bc0`; where the seed's `~` pointer has drifted, the measured number is named and the
drift is raised under Open questions.

## Decisions added by the architect

- **D-2209** The read path D-2205 needs, named exactly. `WatchLoggingState` already holds the engine
  (`public let engine: WatchSessionEngine`, `WatchLoggingState.swift:153`) and already reads a session's
  stored samples through it (`sensorSummary`, `WatchLoggingState.swift:805-835` → `engine.sensorSamples`).
  `WatchSessionEngine.sensorSamples` is public and filtered to the current session (`WatchSessionEngine.swift:149`),
  while `storedSensorSamples` is **private** (`:55`) — the builder reads `engine.sensorSamples` and never the
  storage array. A `WatchSensorSampleRecord` carries `recordedAt` (`WatchRecords.swift:602`), `sequence`
  (`:603`), `kind` (`:608`) and `value` (`:611`). The window's Start is `workTimer?.startedAt`, the instant the
  event already reports (`WatchLoggingState.swift:761`; `workTimer` `:354`, `workTimerKind` `:339`).
  `cumulativeMeters(at:)` is a **private** helper in `WatchLoggingState.swift` — not in
  `WatchSensorSummaries.swift`, which Phase 1B does not own. It keeps `sample.kind == WatchSensorKind.gps`
  (`WatchRecords.swift:132`; the settled `.distance` kind at `:136` is deliberately not read), requires a
  finite `value` as the summary helpers do, and resolves two samples on one instant the way the engine does:
  the later stored row wins (`WatchSessionEngine.swift:168-172`), which is also `sequence` order.
- **D-2210** A **third** existing test changes on purpose, which D-2207's "no other existing test is edited"
  cannot cover: `WatchLoggingSurfacesTests.testEveryValidObservationsEventIsReproducedByTheSurfaceShape`
  (`watch/watchos/Tests/WatchSessionEngineTests/WatchLoggingSurfacesTests.swift:633`) reads
  `fixtures/valid/observations_up_distance_and_load.json` (`:636`) and asserts the wrist's logged timed event
  has **exactly** that fixture's timed-event key set (`:682-687`). It goes red twice over: its fix arrives
  **before** `surface.startWork()` (`:657-666`), so D-2205 makes the window difference 0 and the event loses
  `distanceMeters`; and once the fix is moved after Start, D-2206 adds `distanceSource`, which that fixture's
  timed event does not carry (`watch/sync_protocol/fixtures/valid/observations_up_distance_and_load.json:22-23`).
  The change, inside Phase 1B: read `fixtures/valid/observations_up_distance_source.json` instead, whose first
  timed event is a measured `gps` distance (`:10-21`), and move `source.fix(2400)` after `surface.startWork()`.
  The fixture files are untouched (D-2206). Phase 1B's `--scope` must therefore also cover
  `watch/watchos/Tests/WatchSessionEngineTests/WatchLoggingSurfacesTests.swift` — see Governor actions.
- **D-2211** What stamps a sample is the clock at arrival, and two samples of one kind at one instant are
  **one** row: `WatchSensorRecorder.record` stamps `recordedAt = clock()` (`WatchSensorRecording.swift:228`) and
  the engine de-duplicates by `sampleId(sessionId:kind:at:)` (`WatchSessionEngine.swift:1281-1288`), pinned by
  `testAppendingTheSameInstantTwiceStoresOneRow` (`WatchSensorRecordingTests.swift:517`). Every fixture in
  `WatchEffortDistanceTests` therefore advances the clock **to** the intended instant, yields the fix, awaits
  the store (`await eventually { … }`), and only then advances again — distinct fixes at distinct instants, or
  the second fix is silently a no-op and the test measures the first one twice.
- **D-2212** The watch's own `session_snapshot` carries the same entries: `WatchSessionEngine.sessionSnapshot()`
  puts `"entries": entries.map(\.payload)` (`WatchSessionEngine.swift:246`) — the stored logged-entry payloads —
  and validates the envelope (`requireConformant`, `:248`). So D-2206's `distanceSource` reaches a snapshot
  entry exactly as it reaches an `observations_up` event, and one rule holds both
  (`SyncProtocolValidator.snapshotRejections` calls `captureRejections`, `SyncProtocolValidator.swift:279`;
  `captureFieldKinds` has `("distanceSource", ["timed"])` at `:79`; `distanceSourceRejections` `:363-379`).
  No schema change: `session_snapshot.schema.json:34` and `observations_up.schema.json` both `$ref` the same
  `envelope.schema.json#/$defs/entry`.
- **D-2213** Cross-platform divergence, recorded and out of this unit's scope: the Dart watch client's timed
  window has no measured-distance rule at all — `lib/watch/logging/watch_logging_state.dart:_windowPayload`
  (`:678-694`) takes `covered` from the dialled `WatchMetricKey.distance` row and derives `startedAt` from a
  dialled duration. After this unit the two clients' `windowPayload` are different functions. Nothing in 19e
  touches `lib/watch/logging/`; the Wear half of the GPS work (after 19f) must mirror D-2205/D-2206 or the two
  clients log different numbers for the same effort.
- **D-2214** Baselines measured by the architect this run (2026-10-10, base commit `f4b4bc0`):
  `gateway.sh swift-test` → **457 tests, 0 failures**; `gateway.sh test test/docs_indexing_contract_test.dart
  test/rest_is_count_up_contract_test.dart test/watch_logging_surfaces_test.dart test/watch_sensor_recording_test.dart
  test/distance_source_import_test.dart` → **95 tests, 0 failures**. These are this unit's baselines; the QA
  index header (`docs/plans/2026-10-08-18-watch-qa-index.md`) carries the older 335/4061 numbers and Phase 3
  corrects the 19e row only.

## Feature invariants (this unit)

- **One place decides an effort's distance.** `windowPayload(loggedAt:coversDistance:)`
  (`WatchLoggingState.swift:759`) is the only reader of a timed entry's distance; `readings`
  (`WatchLoggingState.swift:254` → `WatchSensorRecorder.readings`, `WatchSensorRecording.swift:127-135`) is the
  live readout only. Guarded by S-3208, S-3211, S-3216.
- **A distance is a difference of stored samples, never a value kept in memory.** The rule reads
  `engine.sensorSamples` at log time, so a relaunch between Start and Log changes nothing. Guarded by S-3212.
- **Absence, never zero.** No measurement, or a window that adds nothing, means no `distanceMeters` key; a
  `distanceSource` never travels alone (the validator refuses that). Pinned by the existing
  `testS004WithoutAFixTheTimedSurfaceOffersNoDistanceRow` (`WatchSensorRecordingTests.swift:297`) and
  `testS006AManualDistanceNeverReachesTheObservation` (`WatchLoggingSurfacesTests.swift:447`); guarded by
  S-3211, S-3216, S-3219.
- **Only `gps` is cumulative.** The `gps` sample is the running total, the `distance` sample the settled one
  (`WatchRecords.swift:130-136`); the log rule reads the former, the live readout prefers the latter
  (`WatchSensorRecording.swift:129-136`). Guarded by S-3216.
- **The tracker never goes backwards and never counts a still wrist.** `totalMeters` is monotonic, the reference
  moves only on an accepted fix, and every gate (accuracy, time order, speed, jitter floor) is a reason to
  ignore, not to correct (D-2202). Guarded by S-3200…S-3205.
- **The seam does not change.** `WatchLocationFix` stays "cumulative metres since the session started"
  (`WatchSensorRecording.swift:49`) and `WatchSensorSource` keeps its permission probe and its streams
  (`:60-80`); the new types adapt to it (D-2203). Guarded by S-3206, S-3207 and the existing S-001/S-002/S-008.
- **Nothing new is OS-bound, and no wrist code calls the new types** (D-2200): no `import CoreLocation`, no
  Info.plist key, no file under `ios/`. Searched this run: `WatchDistanceTracker` and `WatchTrackedLocation`
  appear nowhere outside this plan's own files. Guarded by the package suite compiling without the app target.
- **The module guards stay green** (D-2204): the new names (`accept`, `permission`, `fixes`, `totalMeters`,
  `WatchRawFixSource`) avoid the mutating verbs, and no new `*Store.swift` is created.
  `testS004NoMutatingOperationExistsAnywhereInTheModule` (`WatchSessionEngineTests.swift:322`) scans every
  `.swift` under `Sources/WatchSessionEngine` (`Fixtures.swift:27-29`) — exactly where the two new files land.
- **One vocabulary for the sample kinds.** `WatchSensorKind.gps`/`.distance` and
  `watch/contract/watch_sensor_contract.json`, pinned by `testTheSampleKindsAreTheOnesBothClientsAgreedOn`
  (`WatchSensorRecordingTests.swift:495`); no new kind string and no second copy of the numbers.
- **Every sentence this unit adds to `docs/` names an existing test** (`docs/documentation_standard.md` §4.2),
  and the three doc files stay inside the indexing guard's ceiling and warning band.

## Existing-functionality impact

| Touched surface | What already reads it (the search run, with its result) | Effect | Guarded by |
|---|---|---|---|
| `WatchLoggingState.windowPayload` (changed) | `rg windowPayload` → 4 files: the timed route `WatchLoggingState.swift:745`, the drill route `:748`, the Dart twin `lib/watch/logging/watch_logging_state.dart:667,672,678`, a doc comment in `lib/core/sync_protocol/phone_entries.dart:89`. `rg "distanceMeters\|distanceSource" watch/watchos/Tests` → the payload assertions are `WatchSensorRecordingTests.swift:294` (S-004), `:321` (S-004, no fix), `:923` (`testAMeasuredDistanceIsWhatTheObservationCarries`), `WatchTimedWorkTests.swift:120` (S-1300), `WatchLoggingSurfacesTests.swift:463` (S-006), `:682` (the shape test) | two assertions change on purpose (D-2207/S-3213) and the shape test with them (D-2210/S-3218); `:321`, `:463` and `WatchTimedWorkTests.swift:120` assert **absence** where no fix exists at all and stay green | S-3208…S-3219, S-3213, S-3218; the unchanged S-004 no-fix, S-006 and S-1300 |
| `engine.sensorSamples` (read, not changed) | `rg sensorSamples` → 19 files; the Swift readers are `WatchSessionEngine.swift:149` (the accessor) and `WatchLoggingState.swift:805` (`sensorSummary`), plus `WatchSensorRecordingTests.swift` and `WatchSensorCoordinatorTests.swift` | a second reader in the same file, same idiom; no signature, scope or storage change (`storedSensorSamples` stays private) | S-3208, S-3212, S-3214…S-3217 |
| `workTimer?.startedAt` (read, not changed) | already the `startedAt` the event carries (`WatchLoggingState.swift:761`); `WatchTimedWorkTests.testS1300…` (`:99-127`) asserts that field is the Start instant | the window's start becomes the instant the event already reports; no new clock, no new stored field | S-3208, S-3209, S-3214 |
| `WatchSensorSource` / `WatchLocationFix` (consumed, **not** changed) | `rg "WatchSensorSource\|WatchLocationFix"` → `WatchSensorRecording.swift:49,60` (the seam), `ios/OmniTrain Watch App/HealthKitSensorFeed.swift` (5), `WatchSensorSourceSourceTests.swift` (4), `WatchSensorRecordingTests.swift` (4, `FakeSensorSource`), `WatchSensorCoordinatorTests.swift` (5), `lib/watch/sensors/watch_sensor_recording.dart` (8), `lib/watch/debug/watch_session_debug_surface.dart` (3) | `WatchTrackedLocation` **produces** a `WatchLocationFix` stream and is fed to a recorder in tests; 19f gives the app target's feed one. No conformer, protocol or call site changes | S-3206, S-3207; the existing S-001/S-002/S-008 and the Dart sensor suite stay green |
| `fixtures/valid/observations_up_distance_and_load.json` (read, not changed) | `rg observations_up_distance_and_load` → `WatchLoggingSurfacesTests.swift:636`, `watch/sync_protocol/PROTOCOL.md:141`, `fixtures/manifest.json:10`, plus plan files | the fixture stays; the one test that read it moves to the `gps` fixture (D-2210), so its timed event (a distance with no source) is no longer claimed to be the shape a wrist emits | S-3218 (the moved assertion), S-3210 (the validator accepts a measured event); the fixtures suite unchanged |
| `SyncProtocolValidator` (read, not changed) | `captureFieldKinds` `:79`; `captureRejections` reached from both routes (`:279` snapshot, `:347` observations_up); `distanceSourceRejections` `:363-379` | no change: D-2206's field is already legal on a timed entry in either message, and a source without a distance is already refused | S-3210, S-3218, S-3219 |
| `lib/watch/logging/watch_logging_state.dart` (the Dart twin) | its own `_windowPayload` (`:678-694`) and `test/watch_logging_surfaces_test.dart` (4 `WatchLoggingState(` constructions) | **unchanged** — Phase 2A touches only the importer's comments; the two clients' timed windows now differ (D-2213) | the Dart suite stays green at its measured baseline; the divergence is recorded, not proved |
| `lib/core/services/watch_session_importer.dart` comments | `rg "never run GPS"` → exactly two code/test comments: `lib/core/services/watch_session_importer.dart:963` and `test/distance_source_import_test.dart:5-7` (the other hits are 03b's plan files, which stay as history) | comment-only (D-2208); the import's behaviour is unchanged | the Dart distance tests stay green (measured baseline) |
| `docs/state_management/watch_sensors.md`, `docs/distance_source.md`, `docs/watch_session_capture.md`, the QA index | `test/docs_indexing_contract_test.dart` (ceiling, warning band, links, orphans, roadmap) and `test/rest_is_count_up_contract_test.dart` (rest wording; it scans `watch/watchos/Sources` and the docs) | the sensors page gains the two types, the constants and the per-effort rule; the capture page's sensor links point at `watch_sensors.md` (`:25-26`, `:85-86`); the QA index gains the 19e row | both guard suites, measured green at the baseline |

## Edge scenarios (architect-added, continuing S-3213)

All six live in `watch/watchos/Tests/WatchSessionEngineTests/WatchEffortDistanceTests.swift` except S-3218,
which is the existing test D-2210 changes. Each names the mutation the prover applies. The effort fixtures use
the cumulative values of `FakeSensorSource.fix(_:)` (`WatchSensorRecordingTests.swift:72`), separated by
`clock.advance` (D-2211).

- **S-3214 the Start boundary is inclusive.** Cardio session, live recorder; fix(800) at t0; `startWork()` at
  t0 (the sample's `recordedAt` is **equal** to `startedAt`); clock → t0+60, fix(2800); clock → t0+1200; `log()`.
  Expected `distanceMeters == 2000`. Red without the change: **mutation — compare `recordedAt < t` instead of
  `<= t`** → the start value becomes 0 and the payload reads 2800. (S-3209 cannot tell `<` from `<=`: its
  pre-Start fix is at an earlier instant.)
- **S-3215 the newest qualifying sample wins, not the largest and not the first.** gps samples 400 at t0, 1200
  at t0+10, **900** at t0+20 (a total that went backwards — a fresh subscription starts a fresh total,
  D-2203/S-3206); `startWork()` at t0+30; `log()` at t0+40 → **no** `distanceMeters` (900 − 900 = 0); then
  fix(1500) at t0+50 and `log()` at t0+60 → `distanceMeters == 600`. Red without the change:
  **mutation — take the largest qualifying sample** → the second effort reads 300 (start 1200);
  **mutation — take the first** → 1100 (start 400).
- **S-3216 the settled `distance` sample is not the effort's distance.** Cardio; `startWork()` at t0, fix(3000)
  at t0+600, `log()` at t0+1200 → 3000 (S-3208's first effort); `await sensors.stop()` (which settles a
  `distance` sample of 3000, `WatchSensorRecording.swift:170-196`); `startWork()` at t0+1300 and `log()` at
  t0+1400 with no new fix. Expected: the second effort has **no** `distanceMeters`, even though the newest
  sample of the session is a `distance` of 3000. Red without the change: **mutation — read the newest sample of
  any kind (or `engine.newestSensorSample(WatchSensorKind.distance)`) instead of the newest `gps`** → 3000
  appears.
- **S-3217 the Log boundary is inclusive.** `startWork()` at t0; clock → t0+1200; fix(2000) at t0+1200 (the
  instant of the log); `log()`. Expected `distanceMeters == 2000`. Red without the change:
  **mutation — compare `recordedAt < loggedAt`** → the key is absent. (A fix stamped at the instant the user
  pressed Log is the wrist's total at that instant.)
- **S-3218 the surface's shape is the measured fixture's shape (D-2210).**
  `WatchLoggingSurfacesTests.testEveryValidObservationsEventIsReproducedByTheSurfaceShape` (`:633`) reads
  `fixtures/valid/observations_up_distance_source.json`, its fix arrives after `startWork()`, and the logged
  timed event's key set equals that fixture's `gps` event's key set, with `logged.rejections.isEmpty`. Red
  without the change: **mutation — revert the fixture read to
  `fixtures/valid/observations_up_distance_and_load.json`** → the logged event carries `distanceSource` and the
  fixture's timed event does not (and with the fix left before Start, `distanceMeters` goes missing).
- **S-3219 a hold logged while the sensors measure carries no distance.** A drill slot (`["hold", "time"]`, the
  shape `testS004HoldDurationAndExtraLoadAreLoggedTogether` uses, `:418-430`) with a live recorder,
  `isMeasuringDistance == true` and fix(3000) inside the window; `startWork()`, `log()`. Expected: no
  `distanceMeters`, no `distanceSource`, `logged.rejections.isEmpty`. Red without the change: **mutation — the
  drill route calls `windowPayload(loggedAt: loggedAt, coversDistance: true)`** (`WatchLoggingState.swift:748`)
  → the event carries a distance **and** a source the validator refuses for a hold
  (`captureFieldKinds` holds `distanceSource` to `timed` only, `SyncProtocolValidator.swift:79`).

## Acceptance criteria → scenarios

| Criterion | Scenarios |
|---|---|
| 1. the tracker is accurate, monotonic, still-proof, jump-proof | S-3200, S-3201, S-3202, S-3203, S-3204, S-3205 |
| 2. the adapter is the seam's stream, a fresh total per subscription | S-3206, S-3207 |
| 3. a timed effort logs its own window's metres | S-3208, S-3209, S-3211, S-3212, S-3214, S-3215, S-3216, S-3217, S-3219 |
| 4. a measured distance travels with `distanceSource: "gps"`; no measurement, no source | S-3210, S-3211, S-3218, S-3219 |
| 5. everything validates; the phone's import needs no behaviour change, its comment is corrected | S-3210, S-3218, S-3219; D-2208 (Phase 2A, comments only) |
| 6. unnamed existing behaviour is unchanged | the existing S-001/S-002/S-006/S-008/S-1300 tests named in the impact table, S-3219 (a hold carries nothing), D-2200 (nothing on the wrist calls the new types) |

## Phases

Parallelism: **1A ∥ 2A** (disjoint trees: the Swift package vs `lib/` + `test/`). **1B after 1A** (the two
builders share one Swift target; a half-written file breaks the other's compile). **3P ∥ 3D** (tests vs docs).
**4 after 3**.

### Phase 1A — the tracker and the adapter (crew-builder-watch)

1. [ ] Add the raw-fix value type and the tracker's four named constants — `watch/watchos/Sources/WatchSessionEngine/WatchDistanceTracker.swift` · `WatchRawFix`, `WatchDistanceTracker.maxAccuracyMeters/.maxSpeedMetersPerSecond/.movementFloorMeters/.earthRadiusMeters`
2. [ ] Implement the input gates in D-2202's order (non-finite coordinate or accuracy, negative accuracy, accuracy > 30) and the first-fix origin — `watch/watchos/Sources/WatchSessionEngine/WatchDistanceTracker.swift` · `WatchDistanceTracker.accept(_:)`
3. [ ] Implement the haversine step from the last accepted point, the time-order gate and the speed gate — `watch/watchos/Sources/WatchSessionEngine/WatchDistanceTracker.swift` · `WatchDistanceTracker.accept(_:)`
4. [ ] Implement the jitter floor `max(2, 0.5 × accuracy)`, the reference move and the monotonic total — `watch/watchos/Sources/WatchSessionEngine/WatchDistanceTracker.swift` · `WatchDistanceTracker.accept(_:)`, `totalMeters`
5. [ ] Add the raw-fix source seam and the adapter that maps a fresh tracker per `fixes()` call — `watch/watchos/Sources/WatchSessionEngine/WatchTrackedLocation.swift` · `WatchRawFixSource`, `WatchTrackedLocation.fixes()`
6. [ ] Pass the source's permission answer through — `watch/watchos/Sources/WatchSessionEngine/WatchTrackedLocation.swift` · `WatchTrackedLocation.permission()`
7. [ ] Write S-3200…S-3207 with the arithmetic inline (±0.01) — `watch/watchos/Tests/WatchSessionEngineTests/WatchDistanceTrackerTests.swift` · `WatchDistanceTrackerTests`
8. [ ] Run the package suite and the mutating-verb guard over the two new files — `watch/watchos/Tests/WatchSessionEngineTests/WatchSessionEngineTests.swift` · `testS004NoMutatingOperationExistsAnywhereInTheModule` (green, unchanged)

**Done Criteria:** `.github/copilot/scripts/macos/gateway.sh swift-test` → the package total is at least
457 + the new tests with **0 failures** (measured baseline 457/0, D-2214), `WatchDistanceTrackerTests` green,
and `testS004NoMutatingOperationExistsAnywhereInTheModule` green.
**Predicted Files:** the three files in the write scope. `WatchSensorRecording.swift`, `WatchRecords.swift`,
`WatchSessionEngine.swift` and the shared fakes (`Harness`, `FakeSensorSource`, `FakePlatformStore`) are read,
never edited.
**Write scope:** `watch/watchos/Sources/WatchSessionEngine/WatchDistanceTracker.swift,watch/watchos/Sources/WatchSessionEngine/WatchTrackedLocation.swift,watch/watchos/Tests/WatchSessionEngineTests/WatchDistanceTrackerTests.swift`

### Phase 2A — the phone's stale claim (crew-builder-app)

1. [ ] Rewrite the sentence that says a watch session never runs GPS — `lib/core/services/watch_session_importer.dart` · the doc comment at `:963` (the call it explains is `_knownDistanceSource`, `:1625`/`:1741`)
2. [ ] Rewrite the same claim in the test's header — `test/distance_source_import_test.dart` · the file header comment `:5-7`
3. [ ] Confirm nothing else asserts the claim — searched: only those two comments (`rg "never run GPS"`), the rest being 03b's plan files

**Done Criteria:** `.github/copilot/scripts/macos/gateway.sh test test/distance_source_import_test.dart` green
(it is part of the measured 95/0 baseline, D-2214) and `.github/copilot/scripts/macos/gateway.sh lint` at its
baseline issue count. No behaviour change, no other Dart file.
**Predicted Files:** the two files in the write scope.
**Write scope:** `lib/core/services/watch_session_importer.dart,test/distance_source_import_test.dart`

### Phase 1B — the effort's own window (crew-builder-watch)

1. [ ] Add the private window reader over the session's stored `gps` samples — `watch/watchos/Sources/WatchSessionEngine/WatchLoggingState.swift` · `cumulativeMeters(at:)`
2. [ ] Take the window's start and end and write their difference, not the newest reading — `watch/watchos/Sources/WatchSessionEngine/WatchLoggingState.swift` · `windowPayload(loggedAt:coversDistance:)` (`:759`)
3. [ ] Add the source beside the distance and never alone — `watch/watchos/Sources/WatchSessionEngine/WatchLoggingState.swift` · `windowPayload(loggedAt:coversDistance:)`
4. [ ] Move the fixture's fix after Start and assert the source — `watch/watchos/Tests/WatchSessionEngineTests/WatchSensorRecordingTests.swift` · `testS004TheLoggedEffortCarriesTheGpsTotal` (`:275`)
5. [ ] Move the fixture's fix after Start and assert the source — `watch/watchos/Tests/WatchSessionEngineTests/WatchSensorRecordingTests.swift` · `testAMeasuredDistanceIsWhatTheObservationCarries` (`:901`)
6. [ ] Write S-3208…S-3212 and S-3214…S-3217, S-3219 (clock-separated samples, D-2211) — `watch/watchos/Tests/WatchSessionEngineTests/WatchEffortDistanceTests.swift` · `WatchEffortDistanceTests`
7. [ ] Move the shape test to the measured fixture and after Start (D-2210) — `watch/watchos/Tests/WatchSessionEngineTests/WatchLoggingSurfacesTests.swift` · `testEveryValidObservationsEventIsReproducedByTheSurfaceShape` (`:633`)
8. [ ] Run the package suite and confirm the three absence assertions still pass — `watch/watchos/Tests/WatchSessionEngineTests/WatchSensorRecordingTests.swift` · `testS004WithoutAFixTheTimedSurfaceOffersNoDistanceRow` (`:297`), `testS006DeniedLocationLeavesTheSessionWithNoDistanceAtAll` (`:375`), `WatchLoggingSurfacesTests.testS006AManualDistanceNeverReachesTheObservation` (`:447`), `WatchTimedWorkTests.testS1300…` (`:99`)

**Done Criteria:** `.github/copilot/scripts/macos/gateway.sh swift-test` → 0 failures with the new tests
included, and S-3213/S-3218 green.
**Predicted Files:** the four files in the widened write scope (item 7 needs the governor's scope change).
`WatchSensorRecording.swift`, `WatchRecords.swift`, `SyncProtocolValidator.swift` and the fixtures are read,
never edited.
**Write scope:** `watch/watchos/Sources/WatchSessionEngine/WatchLoggingState.swift,watch/watchos/Tests/WatchSessionEngineTests/WatchEffortDistanceTests.swift,watch/watchos/Tests/WatchSessionEngineTests/WatchSensorRecordingTests.swift` — **plus** `watch/watchos/Tests/WatchSessionEngineTests/WatchLoggingSurfacesTests.swift` for item 7 (Governor actions).

### Phase 3P — the prover (crew-prover)

1. [ ] Prove each tracker gate by the named mutation — `watch/watchos/Tests/WatchSessionEngineTests/WatchDistanceTrackerTests.swift` · S-3200…S-3205
2. [ ] Prove the adapter's fresh total per subscription — `watch/watchos/Tests/WatchSessionEngineTests/WatchDistanceTrackerTests.swift` · S-3206
3. [ ] Prove the recorder end to end, including denial — `watch/watchos/Tests/WatchSessionEngineTests/WatchDistanceTrackerTests.swift` · S-3207
4. [ ] Prove the window rule by mutation (newest sample, largest, first, `start = 0`, `<` boundaries) — `watch/watchos/Tests/WatchSessionEngineTests/WatchEffortDistanceTests.swift` · S-3208…S-3217
5. [ ] Prove S-3218 by reverting the fixture read and S-3219 by flipping the drill route's `coversDistance` — `watch/watchos/Tests/WatchSessionEngineTests/WatchLoggingSurfacesTests.swift`, `watch/watchos/Sources/WatchSessionEngine/WatchLoggingState.swift` (mutation only, reverted after)
6. [ ] Record every verdict, with the arithmetic shown, in the evidence file — `docs/plans/2026-10-10-19e-watch-distance-tracking-plan/2026-10-10-19e-watch-distance-tracking-plan.evidence.md` · `## Prover verdicts`

**Done Criteria:** `.github/copilot/scripts/macos/gateway.sh prove-red f4b4bc0 swift-test` reports `NOT PROVEN:
needs mutation` for the new files (they do not exist at the base), and each named mutation turns exactly its
scenario red while the suite is otherwise green.
**Write scope:** `watch/watchos/Tests/**`

### Phase 3D — the docs keeper (crew-docs-keeper)

1. [ ] Document the two types, the four constants and the per-effort rule — `docs/state_management/watch_sensors.md` · Structure table (`:23-34`), Rationale (`:60`), Invariants (`:100`), Vocabulary (`:174`)
2. [ ] Say that a wrist-measured distance now exists as a type and a rule, and that only 19f feeds it — `docs/distance_source.md` · Vocabulary (`:158-178`)
3. [ ] Point the capture page's sensor links at the sensors page — `docs/watch_session_capture.md` · `:25-26`, `:85-86`
4. [ ] Add the 19e row — `docs/plans/2026-10-08-18-watch-qa-index.md` · the PRs table (`:22`)

**Done Criteria:** `.github/copilot/scripts/macos/gateway.sh test test/docs_indexing_contract_test.dart
test/rest_is_count_up_contract_test.dart` green (measured baseline included in 95/0), every new sentence names
an existing test, and no file exceeds the indexing ceiling.
**Write scope:** `docs/**`

### Phase 4 — the reviewer (crew-reviewer)

1. [ ] Review `git diff f4b4bc0` against this plan, the Ledger and the scope budget — `docs/plans/2026-10-10-19e-watch-distance-tracking-plan/2026-10-10-19e-watch-distance-tracking-plan.review.md` · the review file (the reviewer creates it)

**Done Criteria:** every acceptance criterion is traced to a green scenario, and every unplanned change is
listed as a finding. **Write scope:** `docs/plans/**`

## Progress

| Phase | Item | Status |
|---|---|---|
| 1A | 1–8 | done |
| 2A | 1–3 | done |
| 1B | 1–8 | done |
| 3P | 1–6 | done |
| 3D | 1–4 | done |
| 4 | 1 | done (review round 1) |
| fix | round 1 | done (D-2215, S-3221) |

## Assumption Log

Filled after review round 1 (finding 3); the substance lives in Open questions
1–11 and the evidence file.

- **A-1** `storedSensorSamples` is private; the builder reads the public
  `engine.sensorSamples` instead (Open question 1; D-2209; evidence Phase 1B).
- **A-2** A third existing test changes on purpose (D-2210), beyond D-2207's
  "no other existing test is edited" (Open question 2; evidence Phase 1B).
- **A-3** The prover's mutation spec touched production files
  (`WatchLoggingState.swift` for S-3219); the governor applied them, never the
  prover, and restored them byte-identical (Open question 10; evidence Prover
  verdicts).
- **A-4** The prover's shell calls were denied; a closed fix run corrected its
  one non-compiling edit (evidence Prover verdicts).
- **A-5** The restart rule D-2215 was added after review round 1, not seeded
  (Feedback F-1; evidence Review round 1 and fix round).

## Feedback

- **F-1** (governor, after review round 1): review finding 1 (Major) — a
  restart of the location feed inside an effort made the effort lose its
  distance — fixed by **D-2215** and scenario **S-3221**: an effort's metres
  are a chain over the stored `gps` samples inside its window (Start, Log],
  starting from the baseline total at Start; a total below the previous one
  means the subscription restarted and counts as the metres since the restart
  (the same rule the steps summary uses). New test
  `WatchEffortDistanceTests.testS3221ARestartedTotalInsideTheWindowIsTheMetresSinceTheRestart`;
  `swift test` 481 tests / 0 failures; mutations E1–E8 all RED
  (`.work/crew/19e-gps/governor-mutations-fix1.md`). Findings 2 and 3 (minor)
  are docs items, fixed in this fold.

## Open questions

1. **The brief's check on D-2205's read access — workable, with one correction.** `WatchLoggingState.engine`
   is public (`WatchLoggingState.swift:153`) and `engine.sensorSamples` is public (`WatchSessionEngine.swift:149`),
   but `storedSensorSamples` is **private** (`:55`), so the builder must not read it; the seed's Code pointers
   name `storedSensorSamples` and `newestSensorSamples` without saying so. Named in D-2209.
2. **The brief's check on the affected tests — a third one exists (D-2210).**
   `WatchLoggingSurfacesTests.testEveryValidObservationsEventIsReproducedByTheSurfaceShape` (`:633-690`) asserts
   an exact key set against `fixtures/valid/observations_up_distance_and_load.json` (`:636`), whose timed event
   carries `distanceMeters: 2400` and no `distanceSource` (`:22-23`); D-2206 adds the source, so it goes red.
   D-2207 says "no other existing test is edited; if one turns red unpredicted, stop and report" — D-2210
   resolves it inside Phase 1B instead, and the seed's D-2207 text is left as written.
3. **The brief's check on the validator — no schema change is needed.** `captureFieldKinds` lists
   `("distanceSource", ["timed"])` (`SyncProtocolValidator.swift:79`) and `captureRejections` is reached from
   the snapshot route too (`:279`), while `session_snapshot.schema.json:34` and `observations_up.schema.json`
   both `$ref` `envelope.schema.json#/$defs/entry`; and the wrist's snapshot entries are the logged payloads
   (`WatchSessionEngine.swift:246`). Recorded in D-2212, guarded by S-3210/S-3218.
4. **The brief's check on the fixtures' arithmetic — re-derived, two small drifts.** 1° of latitude is
   111,194.9265 m on the 6,371,008.8 m sphere: 0.0010° = 111.195, 0.0020° = 222.390, 0.00002° = 2.224,
   0.045° = **5003.772** (the seed writes 5003.779 — 7 mm, immaterial at S-3202's ±0.01, and S-3202 asserts the
   rejection, not the number). S-3204's 2.224 m clears the `max(2, 1.5) = 2` floor, so it does distinguish
   "the floor is used" from "no floor"; it does **not** distinguish `max(2, 0.5 × accuracy)` from a fixed 2 m
   floor — a second accuracy-3 fix at 2.5 m would. S-3201's boundary (30 accepted, 31 refused) is exact.
5. **The brief's check on S-3211's mutation — the seed is right, the mutation is unobservable, and the
   replacement is named.** `max(0, …)` → `abs(…)` cannot change a window whose end is the start, so the
   mutation is "use the end value alone" → 3000 appears. S-3211's own text already says this; the phase items
   and the prover's list carry the replacement.
6. **The combined boundary is untested, on purpose.** Accuracy exactly 30 **and** `d / dt` exactly 20 m/s
   together are not a scenario: the seed's S-3201 and S-3202 pin each gate's boundary alone, and a combined
   fixture would not tell a `<` from a `<=` in either gate any better. Flagged for the reviewer.
7. **The seed's Code pointers have drifted 15–19 lines.** Measured: `windowPayload` is declared at
   `WatchLoggingState.swift:759` (seed: `~:744`) and called for timed work at `:745` (seed: `~:726`); the drill
   route is `:748`; `WatchLocationFix` is at `WatchSensorRecording.swift:49` (seed: `~:96`); `WatchSensorKind`
   is at `WatchRecords.swift:126` (as seeded). Symbols are authoritative, not the numbers.
8. **A hazard the seed does not mention (D-2211).** `FakeSensorSource` fixes stamped at the same clock instant
   are **one** stored row (`WatchSessionEngine.swift:1281-1288`), so a fixture that yields two fixes without
   advancing the clock measures the first one twice. Every new effort fixture advances the clock and awaits
   `eventually { … }` between fixes (`WatchSensorRecordingTests.swift:106`).
9. **The Dart twin diverges (D-2213).** `lib/watch/logging/watch_logging_state.dart:_windowPayload` (`:678-694`)
   has no measured-distance rule and derives `startedAt` from a dialled duration; 19e does not touch it. The
   Wear half of the GPS work must mirror D-2205/D-2206 or the clients log different numbers. Out of scope here.
10. **The seed's phase-3 write scopes are `watch/watchos/Tests/**` ∥ `docs/**` and phase 4 is `docs/plans/**`;
    the prover's mutation of `WatchLoggingState.swift` (S-3219) is a source edit.** The prover's scope does not
    cover `watch/watchos/Sources/**`. The mutation is applied and reverted inside one run and never committed,
    but if the governor reads a scope violation, the S-3219 mutation should be moved to a scratch copy.
11. **Not checked this run:** the watchOS app target's build (`xcodebuild`) and the full `flutter test` suite —
    both are the governor's, per the seed's `gov` row. The measured baselines are D-2214's two runs.

## Governor actions

- Widen Phase 1B's `--scope` to add `watch/watchos/Tests/WatchSessionEngineTests/WatchLoggingSurfacesTests.swift`
  (item 7, D-2210); the seeded table row stays as written and this line is the delta.
- Run the `gov` row: the full `swift test`, `flutter analyze`, the full `flutter test` suite, and the watch
  scheme under `xcodebuild` (a regression check; the app target is untouched by this unit).
- Phase 3's prover needs one bounded source edit for S-3219's mutation (Open questions 10): either allow it
  inside `watch/watchos/Sources/**` for that run or have the prover work on a scratch copy.
- No new directory and no deletion is needed by any phase; the evidence file is created by the architect at
  the path the brief gives, and the review file is Phase 4's.
