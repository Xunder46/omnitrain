# Feature: Sensor Recording: Platform Workout Sessions, Heart Rate, GPS

> **Tier 3 — Live sync, sensors, nutrition.**
> Platforms: native watchOS (first) and Flutter Wear OS (to identical
> behaviour in the same working context).
> Depends on:
> - [watch-phone-sync-protocol](./watch-phone-sync-protocol-plan.md)
>   (item 5) — gate.
> - [watch-session-engine](./watch-session-engine-plan.md) (item 6).
> - [live-session-mirroring](./live-session-mirroring-plan.md)
>   (item 9) — sensors flow into the same append-only sync path.
> Last reconciled against source: 2026-07-13.

## Overview

Registering every watch session as a platform workout (HealthKit
workout sessions on watchOS, the equivalent health services on Wear
OS) is what unlocks the rest: live heart rate, correct calorie and
activity attribution in the health stores, the OS-level runtime
priority that keeps a workout app alive, and GPS. GPS was declared a
product must: it auto-records for distance-capable modalities, and
never runs for work that has no distance — a lifting session must not
drain the battery warming up a GPS radio.

## Requirements

- Starting any session on the watch also starts a platform workout
  session with the activity type mapped from the OmniTrain modality,
  so the OS grants workout runtime and the finished workout lands in
  Apple Health / Health Connect with correct type and duration.
- Live heart rate is displayed on the logging surfaces during the
  session and stored with the session record.
- For distance-capable modalities, GPS recording starts automatically
  with the session: live distance (and pace where meaningful) is
  displayed and logged as the distance observation, superseding
  manual entry while GPS is active. Manual distance entry remains
  available for indoor and GPS-denied situations.
- GPS activation is derived from the modality's capability profile,
  never from hardcoded sport names.
- Abandoning a session cleanly ends the platform workout; no stuck
  "in progress" workouts may remain in the health store after a
  crash or force-kill.
- Sensor data flows into the same append-only watch store as all
  other observations, so the live readout survives a kill. The
  distance reaches the phone as the session's distance observation;
  the raw heart-rate and location rows stay watch-side. Decided
  2026-09-20: syncing them would need a new protocol message, a
  phone-side model and repository — which this plan's DB Changes
  section excludes — and the phone has nowhere to show heart rate,
  so it would be stored data with no reader.
- Out of scope: route maps / visualization, heart-rate zones or
  derived training-load metrics (raw data only, per the
  instrument-panel philosophy), phone-side visualization beyond
  storing the data, third-party sensor pairing, and syncing raw
  heart-rate or location samples.

## Acceptance Criteria

- [ ] A watch strength session produces a health-store workout with
      GPS never activated; a running-type session activates GPS and
      produces a workout with distance.
- [ ] Live heart rate appears on the logging surface within seconds
      of session start on real hardware.
- [ ] GPS-measured distance from a completed outdoor session syncs to
      the phone as the session's distance observation.
- [ ] Force-killing the watch app mid-workout ends or recovers the
      platform workout without leaving a stuck in-progress workout in
      the health store.
- [ ] Denying heart-rate or location permission degrades gracefully:
      session logging fully works, sensor fields are simply absent,
      and nothing crashes.
- [ ] The modality → platform activity type mapping exists for all
      seeded modalities; an unmapped modality falls back to a
      generic type.

## Scenarios

### S-001: Strength session does not activate GPS
- Trigger: User starts a strength session on the watch.
- Precondition: Modality `resistance_lifting`; capability profile
  lacks distance.
- Flow: Session starts → platform workout starts with mapped
  activity type → GPS is not activated.
- Expected outcome: Health store shows a strength-training workout;
  no GPS-recorded points are stored.
- Edge case of: none

### S-002: Running session activates GPS and logs distance
- Trigger: User starts a running / distance session outdoors.
- Precondition: Modality has the distance capability.
- Flow: Session starts → platform workout starts → GPS starts →
  live distance updates → user finishes session.
- Expected outcome: Health store shows a running workout with
  distance; the session's distance observation equals the
  GPS-measured distance.
- Edge case of: S-001

### S-003: Live heart rate renders on the logging surface
- Trigger: User starts any session; HR sensor is available.
- Precondition: Heart-rate permission is granted.
- Flow: Session starts → HR sensor starts → HR updates stream to
  the logging surface → HR samples are persisted with the session.
- Expected outcome: HR is visible on the watch within seconds; the
  samples are readable from the watch store after a relaunch. They
  do not leave the wrist (see the sensor-data requirement above).
- Edge case of: none

### S-004: GPS-derived distance syncs to phone
- Trigger: User finishes an outdoor session.
- Precondition: GPS was active and produced N samples.
- Flow: Session completes → distance observation is the GPS-derived
  total → observation is appended to the engine → emitted to the
  phone.
- Expected outcome: Phone session shows the GPS-derived distance.
- Edge case of: S-002

### S-005: Force-kill leaves no stuck platform workout
- Trigger: Watch app is force-killed mid-workout.
- Precondition: Platform workout session is active.
- Flow: Force-kill → on next launch, the watch detects the orphaned
  platform workout and ends it cleanly (or recovers it into the
  current session).
- Expected outcome: No "in progress" workout remains in the health
  store after force-kill + relaunch.
- Edge case of: none

### S-006: Permission denial degrades gracefully
- Trigger: User denies heart-rate or location permission.
- Precondition: Permission prompt presented.
- Flow: Denial captured → sensor subscription is skipped → session
  logging continues normally.
- Expected outcome: Session is fully usable; sensor fields are
  simply absent; nothing crashes.
- Edge case of: S-003, S-004

### S-007: Unmapped modality falls back to a generic type
- Trigger: A new modality is added with no mapping.
- Precondition: Mapping table lacks the modality.
- Flow: Session starts → lookup falls back to a generic platform
  workout type.
- Expected outcome: Workout is written with the generic type and
  correct timing; no crash.
- Edge case of: S-001, S-002

### S-008: GPS activation decision derives from modality capabilities
- Trigger: Modality config changes (e.g. a new modality with distance
  capability is added).
- Precondition: Modality config defines capabilities.
- Flow: Decision function reads the modality's capability profile.
- Expected outcome: Decision reflects the capability, not the
  modality's display name.
- Edge case of: S-001, S-002

## Iteration 1

### DB Changes

- Add `local_sensor_samples` to the on-watch storage schema
  (sessionId, kind — `hr` / `gps` / `distance`, value, timestamp).
- No changes to the phone repository.

### Backend Changes

- `WorkoutSession` engine from item 6 gains a sensor recording layer
  that subscribes to platform sensors and appends samples to the
  append-only store.
- Modality → platform activity type mapper (shared with item 4's
  phone-side mapper where applicable; this is the watch-side variant
  for `HKWorkoutActivityType` / Health Connect exercise types).
- A "GPS activation decision" function that reads the modality's
  capability profile, not its name.
- An orphan-workout recovery routine that runs at app start and
  ends any stale platform workout sessions.

### Frontend Changes

- Live HR readout on the watch logging surface (consumed by item 7's
  rendering).
- Live distance / pace readout where applicable.

### Implementation Steps

1. Add the on-watch sensor-sample storage schema.
2. Implement the modality → platform activity type mapper.
3. Implement the GPS activation decision function.
4. Implement the platform workout session lifecycle hooks (start /
  end / recover).
5. Implement the live HR subscription and distance computation.
6. Implement the orphan-workout recovery routine.
7. Verify graceful degradation under permission denial.
8. Run the shared fixture suite to confirm observation shapes.

### Platform Notes

- **watchOS (native)**: `HKWorkoutSession`, `HKLiveWorkoutBuilder`,
  `CLLocationManager` for GPS, `HKQuantityTypeIdentifier.heartRate`
  for HR.
- **Wear OS (Flutter)**: `HealthServices` (or equivalent Flutter
  plugin) for sensors; `FusedLocationProviderClient` for GPS.
- Both platforms consume the same protocol fixtures from item 5 and
  the same engine API from item 6.

## Unit Tests Required

- `test/watch_sensor_recording_test.dart` — modality → platform
  activity type mapping for all seeded modalities; unmapped falls
  back to a generic type.
- `test/watch_sensor_recording_test.dart` — GPS activation decision
  derives from modality capabilities, not sport names (fixture with
  named-but-no-distance modality).
- `test/watch_sensor_recording_test.dart` — sensor observation
  serialization matches protocol fixtures.
- `test/watch_sensor_recording_test.dart` — orphan-workout recovery
  routine ends stale platform workout sessions on app start.
- `test/watch_sensor_recording_test.dart` — graceful degradation
  under permission denial: no sensor subscriptions, no crashes,
  session logging works.
- `watchTests/watch_sensor_recording_test.swift` — same fixture-
  driven tests on watchOS.

## Progress

- [x] TDD: tests authored, red run recorded
- [x] Phase 1 — Data Layer (sensor-sample storage)
- [x] Phase 2 — Logic & UI (sensors + workout lifecycle + recovery)
- [x] Review findings 1–3 addressed (see `## Feedback` → Remediation)
- [x] Review round 2 — doc-standard, diff-churn and naming items closed
- [ ] Phase 3 — Code Review
- [ ] Device-side seams implemented + app entry wired (blocked on the app target; see finding 4)
- [~] Behaviour parity verified across watchOS + Wear OS

### Test runs

- Red (before implementation): `flutter test test/watch_sensor_recording_test.dart`
  failed to compile — "Type 'WatchSensorSource' not found"; `swift test` failed
  with "cannot find type 'WatchSensorSource' in scope".
- Green: `test/watch_sensor_recording_test.dart` — 30 passing.
  `watch/watchos/Tests/WatchSessionEngineTests/WatchSensorRecordingTests.swift` —
  23 passing, `swift test` 117 overall, 0 failures.
- Full Dart suite — 2730 passing, 0 failures. `flutter analyze` clean on the
  changed Dart files.
- After remediation: `test/watch_sensor_recording_test.dart` — 37 passing;
  `swift test` — 124 overall, 0 failures; full Dart suite — 2737 passing, 0
  failures; `flutter analyze lib/watch` clean, 0 project-wide errors.
- One pre-existing scan test had to be honoured rather than weakened:
  `test/watch_logging_surfaces_test.dart` (`S-006 the logging layer asks no
  location service for anything`) forbids location vocabulary anywhere under
  `lib/watch/logging/`. The live-location flag is therefore named for the
  measurement it represents — `isMeasuringDistance` — on both clients, and the
  logging layer holds no location word at all.

### What landed

- `watch/contract/watch_sensor_contract.json` — the sample kinds and units, the
  modality → platform workout type table, and the capability profile the GPS
  decision is derived from. Both suites assert against it, so a change on one
  client fails the other's tests.
- Sensor samples are records in the append-only store (`sensor_sample`), so a
  kill mid-run keeps the distance already measured; they ride through a relaunch
  like every other row, and a session's log is released once the session is over
  and all of its entries are acknowledged (`pruneSettledSensorSamples`).
- The distance that reaches the phone is the logged effort's `distanceMeters`,
  which is the protocol's own field — no new message type, and no second source
  of truth for how far the user went. Live sensor rows stay watch-side.

## Feedback

**Reviewer, 2026-09-20 — one decision and three fixes before this feature is done.**

1. **Sensor data does not reach the phone, and `## Requirements` says it does.**
   The requirement reads "Sensor data flows into the same append-only store and
   sync path as all other observations, reaching the phone with the session", and
   S-003's expected outcome ends "HR samples arrive at the phone with the
   session." Nothing syncs. Heart-rate and location rows are written to the watch
   store and stay there; the only measurement that crosses is the distance, which
   already had a field — the logged effort's `distanceMeters`.
   **Decide one of two ways.** (a) Keep the design and amend the requirement to
   "the distance reaches the phone as the session's distance observation; raw
   sensor rows stay watch-side", dropping the second half of S-003's expected
   outcome. (b) Add a sensor-samples message to the protocol so the heart-rate and
   GPS logs sync — a `watch/sync_protocol/` change with fixtures, affecting both
   clients and the phone's mirror. Today the code says (a), the docs say (a), and
   the plan says (b); one of the three has to move.
2. **A crown turn overrides the measurement.** While location is recording, the
   distance row is still dial-able, and a turn replaces the measured value in the
   logged `distanceMeters` — contrary to "superseding manual entry while GPS is
   active". Make `adjust` a no-op for a metric being measured, and disable that
   row's own controls, on both clients.
3. **Sensor rows can never be removed.** They are deliberately not gated on the
   phone's receipt, and the store contract test
   (`test/watch_session_engine_test.dart`, S-004) pins the store's interface to
   `append` / `readAll` / `pruneConfirmed` — so there is no path by which a
   reading ever leaves the wrist, and a session's worth of heart rate and GPS
   accumulates for the life of the install. Decide the retention rule
   (session-scoped prune once the session's entries are confirmed is the obvious
   one) and amend that enforcement test deliberately rather than by accident.
4. **Device-side work, unchanged from the previous note.** The platform bindings —
   `HKWorkoutSession` / `HKLiveWorkoutBuilder` / `CLLocationManager`, and the Wear
   OS equivalents — have no implementation on either client: only the seams
   (`WatchPlatformWorkoutStore`, `WatchSensorSource`) exist, implemented by test
   fakes. And `WatchSessionSensors.start`, `.stop` and `.recoverInProgress` have
   no caller — not an app entry, not even the QA harnesses under `lib/watch/debug/`.
   Until both land, no reading is ever taken on a device, AC 2 ("on real
   hardware") is unreachable, and the launch-time recovery the docs describe does
   not happen.

Also, the plan named `watchTests/watch_sensor_recording_test.swift`; the native
suite lives at `watch/watchos/Tests/WatchSessionEngineTests/` because that is
where `swift test` finds it and where the rest of the watchOS register runs.

### Remediation — 2026-09-20

**Finding 1 — decided as option (a), on the record.** The plan's sensor-data
requirement and S-003 now read "the distance reaches the phone as the session's
distance observation; raw heart-rate and GPS rows stay watch-side", matching the
code and the docs. Option (b) was rejected because `## Iteration 1 → DB Changes`
states "No changes to the phone repository", the phone has no sensor model or
screen for one, and `## Out of scope` excludes phone-side visualization — so
syncing the raw logs would add a protocol message, a model, a repository, a Hive
box and a SQL contract for data with no reader. AC 3 asks only that the
GPS-measured distance sync, and it does, as the effort's `distanceMeters`.

**Finding 2 — fixed on both clients.** `WatchMetricField.isMeasured` tells the
UI whether a row is the sensors' to keep; `adjust()` returns early for such a
row, and the logging screens pass null gesture callbacks and render the row's
steppers disabled. The measured-total test asserts the value is unmoved by a
15-detent turn and that the logged `distanceMeters` is the measured total.

**Finding 3 — fixed as session-scoped retention, with the enforcement test
amended deliberately.** `WatchSessionStore` gained a fourth method,
`pruneSensorSamples(sessionIds)`, and the engine gates it on a session that is
over and has no entry awaiting a receipt (`pruneSettledSensorSamples`). A second
prune rather than a wider `pruneConfirmed`, because the two have different gates
and merging them would let a confirmed observation of a running session take
the running session's log with it. The S-004 allowed set in
`test/watch_session_engine_test.dart` and the Swift mirror now read
`{append, readAll, pruneConfirmed, pruneSensorSamples}` with the reason in a
comment beside it.

**Finding 4 — still open, and it is the only thing AC 2 waits on.** Nothing in
this repository can implement `WatchSensorSource` / `WatchPlatformWorkoutStore`:
the app targets they belong to do not exist here, and neither `swift test` nor a
Dart suite can construct `HKWorkoutSession` or `CLLocationManager`. The callerless
half is closed: the QA harness (`lib/watch/debug/watch_session_debug_surface.dart`)
now recovers at boot, starts the sensors on **New session**, stops them on
**Finish**, drops them on **Simulate kill**, and exposes both seams as
constructor parameters (defaulting to a no-permission source and a no-op store),
so the wiring has a real caller and a device run has a place to plug hardware in.

**Also fixed while in here.** The Swift engine's in-memory session mirror was not
kept in step with storage on write, so a session that never relaunched looked
like it never existed and its sensor log would never be released; both clients
now record every written session row in the mirror (`mirrored(_:)` / the Dart
equivalent). The docs' false "sensor rows are never pruned" and "the next launch
ends whatever the health store still reports as running" claims are deleted, and
the retention rule, the no-emit rule and the recover-at-launch behaviour each now
name the test that verifies them. `WatchSensorPace.minDistanceMeters` (50 m) moved
into `watch/contract/watch_sensor_contract.json` as `paceMinDistanceMeters`, and
both suites assert the constant against it rather than restating it.

### Reviewer round 2 — 2026-09-20

Implementation, scenario coverage and conventions all pass. One documentation
blocker remained; all four items from that round are now closed:

**`docs/state_management/services_and_utils.md` — RESOLVED.** The class-6 roadmap
framing is gone: the section now states, present tense, which files implement
the two seams (the two suites' fakes and the QA harness's own no-permission /
no-op defaults) and points at the audit for the open item; the "Added on
2026-09-20" opening is dropped, as is the same stamp on the adjacent
Watch ↔ Phone Live Session Mirroring section. The unresolved record now lives in
`docs-audit-2026-07-26.md` §8.6, alongside the other flagged-not-guessed items.

Two further review items also closed: the five files that a `dart format` pass
had reflowed without semantic change are reverted (the diff is now the feature
only), and the near-twin naming — `WatchSensorReadout` (formatted labels) versus
`WatchSensorReadings` (raw values) — is fixed: the labels object is
`WatchSensorLabels` / `sensorLabels` on both clients, which matches the file's
existing `…Label` vocabulary.

### Reviewer round 3 — 2026-09-21

Approved on the feature. One infrastructure warning, now fixed:

**The three pre-release gate suites copied the watchOS build directory on every
test.** Each of `test/pre_release_gate_ios_artifact_test.dart`,
`test/pre_release_gate_upload_destination_test.dart` and
`test/pre_release_gate_notification_and_build_test.dart` rsyncs the repository
into a temp dir per test, and its exclude list named `build` — which does not
match `watch/watchos/.build`. One of three full-suite runs failed in the iOS
artifact file with its 12 tests taking 52 s instead of the usual ~20 s; it passed
in isolation and in both other runs. All three lists now also exclude `.build`.
Measured on the same machine: the affected suite 58.7 s → 19.3 s, a dry-run copy
9,470 files / 614 MB → 2,269 files / 29 MB, and the full Dart suite 02:54 → 01:06
(2,737 passing, 1 skipped, 0 failing). The three gate suites pass unchanged.

### Phase 0 Complete ✓

### Phase 1 + Phase 2 Complete ✓

Implementation done. All Phase 0 tests green on both clients. Ready for Code
Reviewer.

### Parity

Both clients ship the same behaviour off one shared contract
(`watch/contract/watch_sensor_contract.json`): the sample kinds, the modality →
platform workout type table (with its generic fallback), and the capability
profile the GPS decision is derived from. Both suites assert against it, so a
change on one platform fails the other's tests. `WatchSensorRecorder`,
`WatchSessionSensors`, `WatchPlatformWorkout` and `WatchGpsPolicy` exist in both
`lib/watch/sensors/` and `watch/watchos/Sources/WatchSessionEngine/`.
