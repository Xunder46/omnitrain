# Feature: 19f — the wrist measures distance and pace (the CoreLocation feed)

> Status: SEEDED by the governor (2026-10-10), awaiting the architect's expansion
> Next handoff: @crew-architect
> Binding conventions: docs/global_conventions.md; docs/documentation_standard.md; .github/copilot/pr-scope-budget.md
> Base commit: 14c868d (branch claude_develop). Team: the crew (`.claude/crew.md`). Series: 19e (done: tracker, adapter, per-effort rule) then 19f (this: the feed and the permission).

## Overview

19e built and proved the distance model in the package and left it dormant. This unit turns it on: a real location source on the watch, the Location permission, and the wiring. Owner decision (2026-10-10, "Agreed"): distance and pace for cardio and sports sessions only (the existing `WatchGpsPolicy`), asked for the first time such a session starts, after the Health prompt; no route, no map is stored.

What the user sees: the first run or sports session after install shows the Location question on the wrist (text below). Allow: the exercise screen shows the distance and pace line (the view code exists: `WatchLoggingView.sensorLine`), each timed effort logs the metres between Start and Log, and after sync the phone shows it as GPS-measured. Refuse: everything else works, no distance appears, nothing is retried. Lifts, holds and free training never ask and never use GPS.

## Acceptance criteria

1. A distance-capable session (cardio, sports) starts location updates after the Location permission is granted, and its raw fixes reach the existing tracker and recorder; no other session type asks for or uses location.
2. The Location question appears at most once per install, only when such a session starts, after the Health question; its text says OmniTrain uses the location during runs and sports to measure distance and pace.
3. Refused or unavailable location: the session logs normally, no `distanceMeters` is sent, nothing crashes or blocks logging.
4. The HealthKit workout for a distance-capable session is registered as an outdoor workout; for every other session as before.
5. A cached fix from before the session cannot become the origin (stale gate).
6. Nothing in the package changes behaviour for existing callers: the new store seam has a default that the 19c fakes use untouched.

## Resolved Decisions (Ledger) — seeded, fixed

- **D-2300** Scope as in the Overview. No route, no map, no calories, no Health location write beyond what `HKWorkoutConfiguration.locationType` implies. The Wear client is out of scope (it also lacks the per-effort rule, 19e D-2213).
- **D-2301** Package seam so the store can tell outdoor from indoor work. In `watch/watchos/Sources/WatchSessionEngine/WatchPlatformWorkout.swift`: `WatchPlatformWorkoutStore` (`:148`) gains a second requirement `func begin(_ activityType: String, outdoors: Bool) async` with a default implementation in a protocol extension that calls `begin(activityType)` (so `FakePlatformStore`, `ScriptedPlatformStore` and the 19c/19d tests compile and behave unchanged, and are NOT edited). `WatchPlatformWorkout.start` (`:176`) calls `store.begin(activityType.watchOs, outdoors: WatchGpsPolicy.isRequired(session.modality))` instead of `begin(_:)`. Nothing else in the package changes for this decision.
- **D-2302** Stale gate in the adapter, `WatchTrackedLocation.swift`: `public init(source: WatchRawFixSource, clock: @escaping () -> Date = Date.init, maxFixAgeSeconds: TimeInterval = 10)`; each `fixes()` call reads `startedAt = clock()` once and drops every raw fix whose `timestamp < startedAt − maxFixAgeSeconds` before it reaches the tracker (CoreLocation delivers a cached position first; it must never become the origin). Fixes at exactly the limit are kept. The existing `init(source:)` call sites (19e tests) keep compiling through the defaults.
- **D-2303** New app-target file `ios/OmniTrain Watch App/CoreLocationRawSource.swift`, whole file inside `#if os(watchOS)`, imports Foundation, CoreLocation, WatchSessionEngine: `nonisolated final class CoreLocationRawSource: NSObject, CLLocationManagerDelegate, WatchRawFixSource` (nonisolated for the reason of 19d D-2113: the target defaults to main-actor isolation and CoreLocation calls its delegate off it). The `CLLocationManager` is created in `init` (the host builds the source on the main actor, and the manager delivers its callbacks on the thread that created it; a manager created lazily from a background task never calls back), configured once: `desiredAccuracy = kCLLocationAccuracyBest`, `activityType = .fitness`, `delegate = self`. `permission() async -> WatchSensorPermission`: `.unavailable` when `CLLocationManager.locationServicesEnabled()` is false; read `manager.authorizationStatus`; `.authorizedWhenInUse`/`.authorizedAlways` → `.granted`; `.denied`/`.restricted` → `.denied`; `.notDetermined` → request once with `requestWhenInUseAuthorization()` dispatched to the main queue, wait for `locationManagerDidChangeAuthorization(_:)` (re-reading the status after every wake-up and waiting again while it is still `.notDetermined`), then answer from the new status. `rawFixes() -> AsyncStream<WatchRawFix>`: registers a continuation under a lock; the first subscriber starts `startUpdatingLocation()` and the last termination calls `stopUpdatingLocation()` (both dispatched to the main queue); `locationManager(_:didUpdateLocations:)` yields one `WatchRawFix(latitude:longitude:horizontalAccuracyMeters:timestamp:)` per `CLLocation` (accuracy passed as CoreLocation gives it: negative means invalid, the tracker refuses it); `locationManager(_:didFailWithError:)` does nothing (a transient error is not a failure and ends nothing). The file requests only WhenInUse, never Always.
- **D-2304** `HealthKitSensorFeed` (`ios/OmniTrain Watch App/HealthKitSensorFeed.swift`): `init(authorization:, location: WatchTrackedLocation)`; `locationPermission()` returns `await location.permission()`; `location()` returns `location.fixes()`; the file still imports no CoreLocation and never calls `requestAuthorization`. The header rule 3 ("No location") is rewritten. `HealthKitWorkoutStore` (`HealthKitWorkoutStore.swift`): `init(location: WatchTrackedLocation)` replaces `init()` and passes it to the feed; it implements `begin(_ activityType: String, outdoors: Bool)` with the current `begin` body plus `configuration.locationType = outdoors ? .outdoor : .unknown` (today a fixed `.unknown`), and `begin(_ activityType: String)` becomes a one-line forward `await begin(activityType, outdoors: false)`. Authorization (`resolveAuthorization`), `end`, recovery and the activity-name table are untouched.
- **D-2305** Host: `ContentView.swift` `WatchAppHost.init` builds `HealthKitWorkoutStore(location: WatchTrackedLocation(source: CoreLocationRawSource()))` where it builds `HealthKitWorkoutStore()` today; nothing else in the host changes (the recorder, the logging state and the coordinators already read the store's `sensorSource`).
- **D-2306** Permission text (owner-approved wording): `INFOPLIST_KEY_NSLocationWhenInUseUsageDescription` = "OmniTrain uses your location during runs and sports to measure distance and pace." in the watch target's Debug/Release/Profile configurations of `ios/Runner.xcodeproj/project.pbxproj` (next to the three `INFOPLIST_KEY_NSHealthShareUsageDescription` lines, ~`:653`, `:705`, `:754`). GOVERNOR ACTION: the project file is outside every crew scope.
- **D-2307** Existing tests that change on purpose: `WatchSensorSourceSourceTests.testS3109TheFeedIsTheRealSourceAndTheStoreReadsBothTypes` (the 19d guard asserts the feed's `locationPermission()` answers `.unavailable` and not `.granted`; it now asserts it delegates to `location.permission()`; its other assertions, including "the feed has no `import CoreLocation`", stay), and `testS3110TheHostWiresTheSensorsAndRefreshesTheWorkoutFirst` (adds the new construction). No other existing test is edited; one that turns red unpredicted: stop and report.
- **D-2308** Proof boundary: the package is proven by `swift-test` and mutations; the app-target files are held by source guards (S-3310..S-3314), compiled by the governor's `xcodebuild`, and verified on a wrist only by the owner. No agent claims a prompt, a fix, an outdoor workout or a distance.

## Core scenarios — seeded, fixed

Package scenarios in `watch/watchos/Tests/WatchSessionEngineTests/WatchOutdoorWorkoutTests.swift` (S-3300..S-3304) and `WatchDistanceTrackerTests.swift` (S-3305, S-3306, appended); source guards in `WatchSensorSourceSourceTests.swift` (S-3310..S-3314). Red today: the seam and the gate do not exist (compile error at the base: the prover reports `NOT PROVEN: needs mutation`; the governor applies the mutation).

- **S-3300 outdoors follows the capability profile.** A recording store (declared in the test file: implements ONLY `begin(_:outdoors:)`, logs the pair) under `WatchPlatformWorkout`: `start` of a `cardio_endurance` session → `(running, true)`; `sports` → `(other, true)`; `resistance_lifting` → `(traditionalStrengthTraining, false)`; `isometric_stretching` → `(flexibility, false)`; a nil modality (free training) → `(other, false)`; an unknown modality string → `(other, false)`. Mutation: pass `true` always → the lift row reads true.
- **S-3301 the default keeps old stores working.** A second store declared in the test file implements only `begin(_:)` (the 19c shape): `WatchPlatformWorkout.start` on it still reaches `begin(_:)` once with the activity name. Mutation: remove the protocol extension's forwarding body → the old-shape store sees no call.
- **S-3302 unchanged lifecycle.** The 19c coordinator suites (`WatchWorkoutCoordinatorTests`, S-1500..S-1510) pass untouched (named in the impact table, no new test).
- **S-3303 stale gate.** `clock` returns t0 = 1_000_000 (fixed); a source whose raw fixes are: origin-quality fix stamped t0 − 60 s (a cached one), then (52.0000, 5.0, 5 m) at t0 + 0, (52.0010, 5.0, 5 m) at t0 + 30, (52.0020, 5.0, 5 m) at t0 + 60 → `fixes()` yields 111.195 then 222.390 (±0.01): the cached fix never became the origin. Without the gate the cached fix is the origin and the first yield is 0.0010° from a point 60 s earlier. Choose the cached fix's position as (52.0050, 5.0), accuracy 5 m: then without the gate the cached fix is the origin and the fix at t0 is 0.0050° = 555.975 m away over 60 s = 9.27 m/s (under the 20 m/s gate), accepted, so the yields would read 555.975, 667.170, 778.366. Mutation: remove the gate → the first value reads 555.975 instead of 111.195.
- **S-3304 gate boundary.** A fix stamped exactly t0 − 10 s is kept (it becomes the origin); one stamped t0 − 10.001 s is dropped. Mutation: `<` → `<=` → red.
- **S-3305 the default clock path.** `WatchTrackedLocation(source:)` (no clock) still compiles and passes the 19e adapter scenarios unchanged (S-3206, S-3207: named, no new test).
- **S-3306 the origin after a restart.** Two sequential subscriptions each start at their own `clock()` read: the second `fixes()` call with a clock advanced by 3600 s drops a fix stamped 3500 s before ITS start, though it was fresh for the first. Mutation: read the clock once in `init` → red.
- **S-3310 source guard: the raw source.** `CoreLocationRawSource.swift` (comment-stripped): contains `import CoreLocation`, `nonisolated final class CoreLocationRawSource`, `WatchRawFixSource`, `CLLocationManagerDelegate`, `requestWhenInUseAuthorization()`, `kCLLocationAccuracyBest`, `.fitness`, `CLLocationManager()` inside `override init()`; does NOT contain `requestAlwaysAuthorization`, `allowsBackgroundLocationUpdates` (not used: the workout keeps the app running), or `HealthKit`. Mutation: remove `nonisolated` → red; add `requestAlwaysAuthorization` → red.
- **S-3311 source guard: the feed delegates.** Feed source: `locationPermission()` body contains `location.permission()` and not `.unavailable`; `location()` body contains `location.fixes()`; still no `import CoreLocation` and no `requestAuthorization`. Mutation: restore `.unavailable` → red.
- **S-3312 source guard: the store.** Store source contains `init(location: WatchTrackedLocation)`, `locationType = outdoors ? .outdoor : .unknown`, and `begin(_ activityType: String, outdoors: Bool)`; the 19c name-table labels are intact. Mutation: `.unknown` back to a fixed value → red.
- **S-3313 source guard: the host.** `ContentView.swift` contains `CoreLocationRawSource()` and `WatchTrackedLocation(source:` in the store's construction, once. Mutation: delete → red.
- **S-3314 source guard: the permission string.** The project file, watch target: three `INFOPLIST_KEY_NSLocationWhenInUseUsageDescription` lines carry the D-2306 sentence and no Always key exists (`NSLocationAlways*`). This reads `ios/Runner.xcodeproj/project.pbxproj` as text from the package test (`Fixtures.repositoryRoot`). Mutation: change the sentence → red.

## Phase outline (each one crew run; at most 8 items)

| Phase | Agent | Write scope (`--scope`) | Parallel? | Goal |
|---|---|---|---|---|
| 1A | crew-builder-watch | `watch/watchos/Sources/WatchSessionEngine/WatchPlatformWorkout.swift,watch/watchos/Sources/WatchSessionEngine/WatchTrackedLocation.swift,watch/watchos/Tests/WatchSessionEngineTests/WatchOutdoorWorkoutTests.swift,watch/watchos/Tests/WatchSessionEngineTests/WatchDistanceTrackerTests.swift` | with 2A | D-2301, D-2302; S-3300, S-3301, S-3303..S-3306 |
| 2A | crew-builder-watch | `ios/OmniTrain Watch App/CoreLocationRawSource.swift,ios/OmniTrain Watch App/HealthKitSensorFeed.swift,ios/OmniTrain Watch App/HealthKitWorkoutStore.swift,ios/OmniTrain Watch App/ContentView.swift` | with 1A; NO gateway check (an unfinished package would not compile) | D-2303, D-2304, D-2305; read-back only |
| gov | governor | — | after 1A and 2A | D-2306 (project file); `xcodebuild` watch scheme; full `swift test` |
| 2B | crew-builder-watch | `watch/watchos/Tests/WatchSessionEngineTests/WatchSensorSourceSourceTests.swift` | serial | D-2307; S-3310..S-3314 |
| 3 | crew-prover ∥ crew-docs-keeper | `watch/watchos/Tests/**` ∥ `docs/**` | parallel pair | prover: mutation specs with arithmetic shown; docs: `docs/state_management/watch_sensors.md`, `docs/watch-app-setup-and-qa.md` (new owner step: the Location prompt, an outdoor run, distance and pace on the wrist, Stats on the phone, refusing once), `docs/distance_source.md`, `docs/watch_session_capture.md` if it says the wrist cannot measure, the 19d/19e sentences that say "location unavailable / no wrist code feeds a fix" (now false), QA index row 19f |
| 4 | crew-reviewer | `docs/plans/**` | serial | review of `git diff 14c868d` |

## Code pointers (verified 2026-10-10)

`WatchPlatformWorkout.swift`: `WatchGpsPolicy.isRequired` :133, `WatchPlatformWorkoutStore` :148, `WatchPlatformWorkout.start` :176. `WatchTrackedLocation.swift` (19e): `init(source:)`, `fixes()` (new tracker per call). `WatchDistanceTracker.swift` (19e). `WatchSensorRecording.swift`: `WatchSensorRecorder.start` ~:199 (asks `locationPermission()` only when `WatchGpsPolicy.isRequired`). App target: `HealthKitWorkoutStore.swift` (`init()`, `begin`, `configuration.locationType = .unknown`, `resolveAuthorization` memo), `HealthKitSensorFeed.swift` (`locationPermission()`, `location()`, `init(authorization:)`), `ContentView.swift` (`WatchAppHost.init`, `let healthStore = HealthKitWorkoutStore()`). Tests: `WatchSensorSourceSourceTests.swift` (19d guards S-3109/S-3110/S-3114/S-3116/S-3117), `WatchWorkoutCoordinatorTests.swift` (`ScriptedPlatformStore`), `WatchSensorRecordingTests.swift` (`FakePlatformStore`, `FakeSensorSource`), `WatchDistanceTrackerTests.swift` (19e: `ScriptedRawFixSource`, helpers). Project file: `INFOPLIST_KEY_NSHealthShareUsageDescription` ~:653, :705, :754.

## Owner steps (not simulated, marked (owner) in the QA guide)

Install on a real watch; start a run (cardio) outdoors: the Health question, then the Location question (Allow While Using); walk or run a few hundred metres: the grey line shows distance and pace; Start/Log an effort; sync; the phone shows the effort's distance as measured; compare with a known distance (the tracker's gates are tuning values: report the error); start a lift: no Location question; refuse the Location question once (reinstall or Settings) and check logging still works.

# Architect expansion (2026-10-10)

Everything above is the governor's seed and is kept as written. The line numbers below were measured this
run against the tree the plan's base commit `14c868d` names; where a seeded `~` pointer has drifted, the
measured number is named and the drift is raised under Open questions. Symbols are authoritative, not the
numbers.

## Decisions added by the architect

- **D-2309** The second default the seam needs for S-3300's fixture. D-2301's single default
  (`begin(_:outdoors:)` → `begin(_:)`) leaves `begin(_:)` with no default, and the protocol requires it
  (`WatchPlatformWorkout.swift:148-155`), so a store implementing ONLY `begin(_:outdoors:)` — S-3300's
  recording store — has no witness for `begin(_:)` and does not conform. The protocol extension therefore
  carries a second default beside D-2301's: `func begin(_ activityType: String) async { await
  begin(activityType, outdoors: false) }`. No existing conformer changes behaviour: `FakePlatformStore`
  (`WatchSensorRecordingTests.swift:84`) and `ScriptedPlatformStore` (`WatchWorkoutCoordinatorTests.swift:45`)
  implement `begin(_:)` themselves, their own witness wins, and the default is never called for them; the
  forwarding default still reaches it, once, with no recursion (the call inside the extension dispatches to
  the conformer's witness). S-3301's mutation becomes "the forwarding default's body stops calling
  `begin(_:)`" — emptied, not removed: removing the default outright stops the old-shape stores conforming,
  which is a compile failure rather than an assertion.
- **D-2310** The five 19e constructions that must pass a fixed clock (the brief's check 2, resolved). The
  19e fixtures stamp their fixes from `testInstant()` = 2026-07-13T06:00:00Z
  (`WatchSessionEngineTests.swift:100-108`) — not from `Date(timeIntervalSince1970:)` — so with D-2302's
  default clock `Date.init` every fix is months older than `now − 10 s` and the gate drops all of them. The
  default stays exactly as seeded (D-2302 is fixed); the constructions pass `clock: { t0 }` explicitly, and
  every edit is inside Phase 1A's scope (`WatchDistanceTrackerTests.swift` is in it):
  - `TrackedLocationSensorSource.init` (`WatchDistanceTrackerTests.swift:80`) gains a `clock` parameter;
    both S-3207 tests pass `{ t0 }` (`testS3207TheRecorderCarriesTheTrackedTotalAndSettlesIt`,
    `testS3207DeniedRawPermissionSkipsLocationAndLoggingCarriesOn` — the denial test never subscribes, but
    it shares the helper).
  - `testS3206TheAdapterMapsTheSourcesFixesIntoOneMonotonicTotal` (`:269`) — goes red without the clock.
  - `testS3206TheMappedStreamFinishesWhenTheRawOneDoes` (`:303`) — stays green but vacuous without the
    clock (every fix dropped, the stream finishes empty, the nil assertion passes for the wrong reason); it
    gets the clock to keep testing what it claims.
  - `testS3206TheAdapterPassesTheSourcesPermissionThrough` (`:258`) and
    `testS3206CancellingTheMappedStreamStopsConsumingTheRawOne` (`:332`) never consume fixes and stay
    untouched.
  This edits existing 19e tests, which D-2307's "no other existing test is edited" does not name; D-2307 is
  about the app-target guards and stays as written — the tension is recorded in Open questions 2.
- **D-2311** Baselines, measured by the governor at `14c868d` and used as given (no gateway check ran in
  this planning run): `swift-test` **481 tests, 0 failures**; `flutter test` **+4240 ~1, all passed**;
  `flutter analyze` **196 issues, 0 errors**; the docs guards (`test/docs_indexing_contract_test.dart` +
  `test/rest_is_count_up_contract_test.dart`) **19 tests, all passed**. Phase 1A's and 2B's Done Criteria
  count from 481; Phase 3's docs keeper counts from 19.
- **D-2312** The feed's stored property is `trackedLocation` (build-found, F-1: a property `location`
  collided with the `location()` method; the init label stays `location:`).
- **D-2313** `@preconcurrency import CoreLocation` in `CoreLocationRawSource.swift` (build-found, F-1:
  four Sendable warnings; the literal `import CoreLocation` the guard matches is kept).

## Feature invariants (this unit)

- **One begin per start, and the outdoor answer travels with it.** `WatchPlatformWorkout.start` asks the
  store once, with the activity name and `WatchGpsPolicy.isRequired(session.modality)`; the fakes' recorded
  `begun` arrays keep their meaning through the forwarding default. Guarded by S-3300, S-3301, S-3302.
- **A cached fix never becomes the origin.** The gate is the adapter's, read once per `fixes()` call
  against that call's own clock read; the boundary is inclusive (a fix at exactly `start − 10 s` is kept).
  Guarded by S-3303, S-3304, S-3306.
- **The package stays OS-free.** No `import CoreLocation` anywhere under `watch/watchos/Sources/`; the raw
  source is an app-target file under `#if os(watchOS)`. Searched this run: `WatchRawFixSource` and
  `WatchTrackedLocation` appear in Sources only in `WatchTrackedLocation.swift`. Guarded by S-3310 and by
  the package suite compiling without the app target.
- **The feed delegates, never decides.** `locationPermission()` and `location()` pass through to the
  `WatchTrackedLocation` they were given; the feed still never prompts and still imports no CoreLocation.
  Guarded by S-3311; S-3114 stays green untouched.
- **One Health prompt, one Location prompt, both only when a distance-capable session starts.** The Health
  prompt fires inside `store.begin` → `resolveAuthorization` (the memo, `HealthKitWorkoutStore.swift:186`),
  reached from the workout refresh; the Location prompt inside `CoreLocationRawSource.permission()`,
  reached from the recorder's probe (`WatchSensorRecording.swift:146-147`), which runs only when
  `WatchGpsPolicy.isRequired` — and the host refreshes the workout before the sensors (the `$revision`
  sink, `ContentView.swift`; S-3110). Guarded by S-3110 (updated), S-3310; the once-per-install half is
  CoreLocation's own behaviour, owner-verified (D-2308).
- **Refusal is absence, never failure.** No granted probe → no subscription → no `gps` rows → no
  `distanceMeters`; the recorder's single `== .granted` guard already treats `.denied` and `.unavailable`
  alike. Guarded by the existing
  `testS3207DeniedRawPermissionSkipsLocationAndLoggingCarriesOn`, and by S-3315.
- **The radio lives exactly as long as a subscriber.** First subscriber starts it, last termination stops
  it, both on the main queue; a transient `didFailWithError` ends nothing. Guarded by S-3316; the
  on-device behaviour is the owner's (D-2308).
- **Every sentence this unit adds to `docs/` names an existing test**
  (`docs/documentation_standard.md` §4.2), and the touched docs stay inside the indexing guard's ceiling
  and warning band.

## Existing-functionality impact

| Touched surface | What already reads it (the search run, with its result) | Effect | Guarded by |
|---|---|---|---|
| `WatchPlatformWorkoutStore.begin(_:)` (protocol, changed) | `rg WatchPlatformWorkoutStore` → three Swift conformers: `HealthKitWorkoutStore.swift:47`, `FakePlatformStore` (`WatchSensorRecordingTests.swift:84`), `ScriptedPlatformStore` (`WatchWorkoutCoordinatorTests.swift:45`); the Dart `interface` (`lib/watch/sensors/watch_platform_workout.dart:134`) is another language and untouched. `rg "\.begin\("` over `*.swift` → the only caller is `WatchPlatformWorkout.start` (`WatchPlatformWorkout.swift:180`) | `start` calls `begin(_:outdoors:)`; the forwarding default reaches the two fakes' own `begin(_:)` unchanged (their `begun` arrays keep their meaning); `HealthKitWorkoutStore` implements the new requirement (D-2304) | S-3300, S-3301, S-3302 (the 19c coordinator suites pass untouched, named, no new test) |
| `WatchTrackedLocation.init`/`fixes()` (changed) | `rg WatchTrackedLocation` over `*.swift` → Sources: `WatchTrackedLocation.swift` only; tests: `WatchDistanceTrackerTests.swift:80, 258, 269, 303, 332` — no other reader | the gate's parameters arrive with defaults; the five constructions D-2310 names pass a fixed clock, the other two stay as they are | S-3303, S-3304, S-3305, S-3306; S-3206/S-3207 stay green |
| `HealthKitSensorFeed.locationPermission()`/`location()` (changed) | the recorder's probes (`WatchSensorRecording.swift:146-147`); the source guards: S-3109 asserts the `locationPermission` body contains `.unavailable` and not `.granted` (`WatchSensorSourceSourceTests.swift:110-119`), S-3114 asserts no `requestAuthorization` and an `.unavailable` window after every `isHealthDataAvailable()` line | S-3109's `.unavailable` body assertion is replaced by the delegation assertion (D-2307; the exact assertion is Phase 2B item 1); the `.granted` false-assertion stays true; S-3114 stays green untouched (its windows are the heart-rate/steps probes, and the feed still never prompts) | S-3311; S-3114 unchanged |
| `HealthKitWorkoutStore.init`/`begin` (changed) | the only construction is `ContentView.swift:87`; the source guards: S-3117 (`collection.delegate = sensorFeed`, both `enableCollection` lines — all three survive the edit), S-1509 (the `case "<name>":` labels and the `default:` → `.other` window — D-2304 touches neither) | `init(location:)`, `begin(_:outdoors:)` carrying the `locationType` line, `begin(_:)` as a one-line forward; `resolveAuthorization`, `end`, recovery and the name table untouched | S-3312; S-3117 and S-1509 stay green |
| `ContentView.swift WatchAppHost.init` (changed) | S-3110's asserted strings — `WatchLoggingState(engine: engine, sensors:`, `WatchSensorCoordinator(`, `source: healthStore.sensorSource`, the sink order — none of them is the store's construction line | the construction becomes `HealthKitWorkoutStore(location: WatchTrackedLocation(source: CoreLocationRawSource()))`; the guard gains the new construction (D-2307) | S-3313; S-3110 updated |
| `ios/Runner.xcodeproj/project.pbxproj` (governor, D-2306) | the three `INFOPLIST_KEY_NSHealthShareUsageDescription` lines verified at `:653`, `:705`, `:754`; no `NSLocation*` key exists yet (searched); `scripts/pre_release_check.sh:273` greps only `ios/Runner/Info.plist` (the phone's, `:42`) for `NSLocation`, and `runner_pbxproj_settings` (`:108-135`) scopes pbxproj checks to Runner's configuration lists — the watch target's new lines are read by neither | three new `INFOPLIST_KEY_NSLocationWhenInUseUsageDescription` lines next to the Health ones, carrying D-2306's sentence | S-3314 (Phase 2B, after the governor's edit) |
| the 19e/19d suites and docs | `testS004NoMutatingOperationExistsAnywhereInTheModule` (`WatchSessionEngineTests.swift:322`) scans every `Sources/WatchSessionEngine/*.swift` for mutating verbs — the new requirement and the gate introduce none; the docs sentences that say the feed reports location unavailable (`docs/state_management/watch_sensors.md:53-54` and `:91-93`; `docs/distance_source.md:178-179`) cite `testS3109…`, which D-2307 changes | the mutating-verb guard stays green; the two docs sentences go false and are Phase 3's to rewrite (each re-cites the changed guard) | the mutating-verb guard; the docs guards in Phase 3 |

## Edge scenarios (architect-added, continuing S-3314)

Both live in `watch/watchos/Tests/WatchSessionEngineTests/WatchSensorSourceSourceTests.swift` (Phase 2B),
both source guards over `CoreLocationRawSource.swift` (comment-stripped, the same reading S-3310 uses),
both red at the base because the file does not exist there.

- **S-3315 the raw source answers `.unavailable` when Location services are off.** The `permission()` body
  contains `CLLocationManager.locationServicesEnabled()` and its false branch answers `.unavailable`
  before any status is read or any request is made. Red without the change: **mutation — delete the
  `locationServicesEnabled()` branch** → the guard's assertion fails. Why it bites: on a wrist with
  Location services off, `requestWhenInUseAuthorization()` never produces an authorization change, so
  without the branch the recorder's probe waits forever inside a session start — the hang the branch
  prevents. (Off-device this is text, not behaviour: the owner's refusal walkthrough is D-2308's.)
- **S-3316 the radio lives exactly as long as a subscriber.** The `rawFixes()` body contains
  `startUpdatingLocation()` and `stopUpdatingLocation()`, and both calls sit inside
  `DispatchQueue.main.async` blocks; the start happens when the first continuation registers and the stop
  when the last one terminates. Red without the change: **mutation — remove the `stopUpdatingLocation()`
  call** → the guard fails. Why it bites: a radio left running after the session's last consumer is gone
  drains the battery the recorder's `isRequired` guard exists to save (`WatchSensorRecording.swift:146`).

## Acceptance criteria → scenarios

| Criterion | Scenarios |
|---|---|
| 1 (a distance-capable session measures; no other session type asks) | S-3300 (outdoors follows the profile), S-3311, S-3316, the existing S-3207 pair, and the recorder's unchanged `isRequired` guard (existing S-001/S-002) |
| 2 (one Location question, after Health, the owner wording) | S-3310 (WhenInUse, never Always), S-3110 (workout refreshed before the sensors), D-2306 (the governor's text, held by S-3314); once-per-install is CoreLocation's own behaviour, owner-verified (D-2308) |
| 3 (refused or unavailable: logging carries on) | the existing `testS3207DeniedRawPermissionSkipsLocationAndLoggingCarriesOn`, S-3315; the crash-free half is the owner's (D-2308) |
| 4 (outdoor workout registration) | S-3300, S-3312 |
| 5 (a cached fix never becomes the origin) | S-3303, S-3304, S-3306 |
| 6 (nothing changes for existing callers) | S-3301, S-3302, S-3305 (with D-2310's construction edits), the untouched fakes, S-3114/S-3116/S-3117/S-1509 green |

## Phases

Parallelism: **1A ∥ 2A** (disjoint trees: the Swift package vs the app target; 2A runs no gateway check —
an unfinished package would not compile). **gov after both** (the project file, `xcodebuild`, the full
suite). **2B serial after gov** (its guards read 2A's files and the governor's pbxproj text). **3 as a
parallel pair** (tests ∥ docs). **4 after 3**.

### Phase 1A — the seam and the gate (crew-builder-watch)

**Write scope** (as seeded): `watch/watchos/Sources/WatchSessionEngine/WatchPlatformWorkout.swift,watch/watchos/Sources/WatchSessionEngine/WatchTrackedLocation.swift,watch/watchos/Tests/WatchSessionEngineTests/WatchOutdoorWorkoutTests.swift,watch/watchos/Tests/WatchSessionEngineTests/WatchDistanceTrackerTests.swift`

1. [ ] Add the second requirement and the two forwarding defaults (D-2301, D-2309) — `watch/watchos/Sources/WatchSessionEngine/WatchPlatformWorkout.swift` · `WatchPlatformWorkoutStore`, the protocol extension
2. [ ] Ask the store for the outdoor answer — same file · `WatchPlatformWorkout.start` (`:176`, the call at `:180`)
3. [ ] Add the stale gate: the clock and max-age parameters, one clock read per `fixes()` call, the inclusive boundary — `watch/watchos/Sources/WatchSessionEngine/WatchTrackedLocation.swift` · `WatchTrackedLocation.init`, `fixes()` (D-2302)
4. [ ] Write S-3300 and S-3301 with the two stores declared in the file (S-3302 is the existing 19c suites passing untouched — named, no new test) — `watch/watchos/Tests/WatchSessionEngineTests/WatchOutdoorWorkoutTests.swift` (new) · `WatchOutdoorWorkoutTests`
5. [ ] Write S-3303, S-3304 and S-3306 with the arithmetic inline (±0.01) — `watch/watchos/Tests/WatchSessionEngineTests/WatchDistanceTrackerTests.swift` · `WatchDistanceTrackerTests` (appended)
6. [ ] Pass the fixed clock in the constructions D-2310 names (S-3305's resolution) — same file · `TrackedLocationSensorSource.init` (`:80`), `testS3206TheAdapterMapsTheSourcesFixesIntoOneMonotonicTotal` (`:269`), `testS3206TheMappedStreamFinishesWhenTheRawOneDoes` (`:303`), both `testS3207…` constructions
7. [ ] Run the package suite and the mutating-verb guard — `watch/watchos/Tests/WatchSessionEngineTests/WatchSessionEngineTests.swift` · `testS004NoMutatingOperationExistsAnywhereInTheModule` (`:322`)
8. [ ] Append phase 1A's rows and the counts to the evidence file — `docs/plans/2026-10-10-19f-watch-gps-feed-plan/2026-10-10-19f-watch-gps-feed-plan.evidence.md` · `## Phase 1A`

**Done Criteria:** `.github/copilot/scripts/macos/gateway.sh swift-test` → the 481 baseline (D-2311) plus
the new tests, **0 failures**, counts pasted; S-3300…S-3306 green; the mutating-verb guard green.
**Predicted Files:** the four files in the write scope and the evidence file. `WatchDistanceTracker.swift`,
`WatchSensorRecording.swift` and the shared fakes (`FakePlatformStore`, `ScriptedPlatformStore`,
`ScriptedRawFixSource`) are read, never edited.
**Write scope:** as seeded above.

### Phase 2A — the raw source, the feed, the store, the host (crew-builder-watch) — **no gateway check in this run**

**Write scope** (as seeded): `ios/OmniTrain Watch App/CoreLocationRawSource.swift,ios/OmniTrain Watch App/HealthKitSensorFeed.swift,ios/OmniTrain Watch App/HealthKitWorkoutStore.swift,ios/OmniTrain Watch App/ContentView.swift`

1. [ ] Create the raw source per D-2303, the whole file under `#if os(watchOS)` — `ios/OmniTrain Watch App/CoreLocationRawSource.swift` (new) · `CoreLocationRawSource` (`override init`, `permission()`, `rawFixes()`, `locationManager(_:didUpdateLocations:)`, `locationManager(_:didFailWithError:)`, `locationManagerDidChangeAuthorization(_:)`)
2. [ ] Give the feed the adapter and delegate both location members; rewrite header rule 3 — `ios/OmniTrain Watch App/HealthKitSensorFeed.swift` · `init(authorization:location:)`, `locationPermission()`, `location()` (D-2304)
3. [ ] Give the store the location-holding init and the outdoor begin with its one-line forward — `ios/OmniTrain Watch App/HealthKitWorkoutStore.swift` · `init(location:)`, `begin(_:outdoors:)`, `begin(_:)` (D-2304)
4. [ ] Build the adapter over the raw source where the store is built — `ios/OmniTrain Watch App/ContentView.swift` · `WatchAppHost.init` (`:87`) (D-2305)
5. [ ] Read all four files back and record the claim-by-claim walk — evidence file · `## Phase 2A` (no check run, by the seed's rule)

**Done Criteria:** no gateway check (1A's package is in flight); the evidence file holds the read-back and
the D-2303/D-2304/D-2305 walk; the phase is compiled by the governor's `xcodebuild`, not by the builder.
**Predicted Files:** the four files in the write scope and the evidence file.
**Write scope:** as seeded above.

### Governor step (after 1A and 2A) — as seeded

D-2306's three pbxproj lines (next to `:653`, `:705`, `:754`); the watch scheme under `xcodebuild`; the
full `swift test`. Not a crew run.

### Phase 2B — the app-target guards (crew-builder-watch)

**Write scope** (as seeded): `watch/watchos/Tests/WatchSessionEngineTests/WatchSensorSourceSourceTests.swift`.
Serial: the guards read 2A's files and the governor's pbxproj text.

1. [ ] Replace S-3109's location-probe assertions with the delegation (D-2307): the `locationPermission` body contains `location.permission()` and not `.unavailable`; keep the no-`import CoreLocation`, no-`.granted`, read-set and name assertions — same file · `testS3109TheFeedIsTheRealSourceAndTheStoreReadsBothTypes`
2. [ ] Add the new host construction to S-3110 (D-2307) — same file · `testS3110TheHostWiresTheSensorsAndRefreshesTheWorkoutFirst`
3. [ ] Write S-3310 (the raw source's tokens and its negatives) — same file · `testS3310…`
4. [ ] Write S-3311 (the feed delegates) — same file · `testS3311…`
5. [ ] Write S-3312 (the store's outdoor begin and its init) — same file · `testS3312…`
6. [ ] Write S-3313 (the host's construction, once) — same file · `testS3313…`
7. [ ] Write S-3314 (the permission string in the project file, no Always key) — same file · `testS3314…`
8. [ ] Write S-3315 and S-3316 (the unavailable answer, the radio's life) and run the package suite — same file · `testS3315…`, `testS3316…`

**Done Criteria:** `.github/copilot/scripts/macos/gateway.sh swift-test` → 0 failures with the guards
included, counts pasted; `.github/copilot/scripts/macos/gateway.sh prove-red 14c868d swift-test` fails at
the base (the guarded files do not exist there) — when it reports `NOT PROVEN: needs mutation`, the
mutations named on each scenario above are the governor's to apply (19d's precedent).
**Predicted Files:** the file in the write scope; the evidence file's `## Phase 2B`.
**Write scope:** as seeded above.

### Phase 3 — prover (crew-prover) ∥ docs keeper (crew-docs-keeper)

**Write scopes** (as seeded): `watch/watchos/Tests/**` ∥ `docs/**`. Disjoint trees; the prover only
mutates and restores.

Prover items:

1. [ ] Prove S-3300 by the always-true mutation, and S-3301 by emptying the forwarding default's body — `watch/watchos/Tests/WatchSessionEngineTests/WatchOutdoorWorkoutTests.swift` · S-3300; `watch/watchos/Sources/WatchSessionEngine/WatchPlatformWorkout.swift` · the protocol extension (mutation only, reverted; a source edit outside the prover's scope — Open questions 6)
2. [ ] Prove S-3303 by removing the gate and S-3304 by `<` → `<=` — `watch/watchos/Sources/WatchSessionEngine/WatchTrackedLocation.swift` · `fixes()` (mutations only, reverted; same scope note)
3. [ ] Prove S-3306 by moving the clock read into `init`, and its variant reading the clock per fix — same file · `fixes()` (mutations only, reverted)
4. [ ] Confirm S-3305 needs no mutation: the two untouched constructions compile and pass against the default clock — `watch/watchos/Tests/WatchSessionEngineTests/WatchDistanceTrackerTests.swift` · `testS3206TheAdapterPassesTheSourcesPermissionThrough` (`:258`), `testS3206CancellingTheMappedStreamStopsConsumingTheRawOne` (`:332`)
5. [ ] Prove the source guards S-3310…S-3316 by the named mutations — the app-target files (mutations applied and reverted by the governor, 19d's precedent)
6. [ ] Record every verdict with the arithmetic shown — evidence file · `## Prover verdicts`

Docs keeper items:

1. [ ] Rewrite the feed's location sentences and re-cite the changed guard — `docs/state_management/watch_sensors.md` · the seam paragraph (`:53-54`) and the 19e paragraph (`:91-93`)
2. [ ] Rewrite "no wrist code feeds a fix yet" — `docs/distance_source.md` · `:178-179`
3. [ ] Check the capture page for a stale wrist-measuring sentence; none was found this run (`docs/watch_session_capture.md:164-168` is about the import and stays true) — `docs/watch_session_capture.md`
4. [ ] Add the owner step: the Location prompt after the Health prompt, an outdoor run, the distance and pace line, Stats on the phone, refusing once — `docs/watch-app-setup-and-qa.md` · the `(owner)` block after `:589-594`
5. [ ] Add the 19f row — `docs/plans/2026-10-08-18-watch-qa-index.md` · the PRs table (after `:23`)
6. [ ] Run the two guard suites and record the numbers in the run report — `.github/copilot/scripts/macos/gateway.sh test test/docs_indexing_contract_test.dart test/rest_is_count_up_contract_test.dart` (the 19-test baseline, D-2311)

**Done Criteria (prover):** every named mutation turns exactly its scenario red while the suite is
otherwise green; the receipts are in `## Prover verdicts`.
**Done Criteria (docs keeper):** the two guard suites green at the 19 baseline; every new sentence names an
existing test; no file over the indexing ceiling.
**Predicted Files:** prover — the test files (mutations restored byte-for-byte) and the evidence file;
docs keeper — the four doc files above.

### Phase 4 — review (crew-reviewer)

1. [ ] Review `git diff 14c868d` against this plan, the Ledger and the scope budget — `docs/plans/2026-10-10-19f-watch-gps-feed-plan/2026-10-10-19f-watch-gps-feed-plan.review.md` (the reviewer creates it)

**Write scope:** `docs/plans/**`. Serial.

## Progress

| Phase | Item | Status |
|---|---|---|
| 1A | 1–8 | done |
| 2A | 1–5 | done |
| gov | D-2306, xcodebuild, full suite | done |
| 2B | 1–8 | done |
| 3 | prover 1–6 ∥ docs 1–6 | pending |
| 4 | 1 | pending |

## Assumption Log

- The architect is glm-5.3-flash: DeepSeek died twice on the provider's
  "reasoning_content" 400 error (governor-mutations-F.md).
- D-2309, the second default, was added by the architect: D-2301's single
  default does not compile S-3300's fixture (Open questions 1).
- D-2310, the five fixed-clock constructions, was added by the architect:
  D-2302's default clock drops every fix the 19e fixtures stamp (Open
  questions 2).
- D-2312, the build-found rename of the feed's stored property (F-1).
- The prover's S-3306 repair (F5's MISS, assigned to the prover): to be
  recorded here after it runs.

## Feedback

- **F-1** (governor, after the first watch build): the feed's stored property
  was renamed `trackedLocation` — a property `location` collided with the
  `location()` method (`invalid redeclaration of 'location()'`); the init
  label is unchanged — and the CoreLocation import is `@preconcurrency` (four
  Sendable warnings). Recorded as D-2312 and D-2313.

## Open questions

1. **D-2301's single default does not compile S-3300's fixture (D-2309).** The protocol requires
   `begin(_:)` with no default (`WatchPlatformWorkout.swift:148-155`), so a store implementing only
   `begin(_:outdoors:)` has no witness for it. The second default (D-2309) is additive: no existing
   conformer's behaviour changes (both fakes implement `begin(_:)` themselves, so their own witness wins).
   The seeded D-2301 text is kept as written.
2. **D-2302's default clock breaks the 19e tests that consume fixes (D-2310).** Their fixes are stamped
   from `testInstant()` = 2026-07-13T06:00:00Z (`WatchSessionEngineTests.swift:100-108`) — the brief's
   "Date(timeIntervalSince1970: 0..120)" is not what the file does — so with `Date.init` every fix is
   older than `now − 10 s` and is dropped. The five constructions are named in D-2310; the edits are inside
   Phase 1A's scope. Two tensions, recorded not resolved: S-3305 says the 19e scenarios pass "unchanged"
   (true for behaviour; two construction lines gain a `clock:` argument), and D-2307 says "no other
   existing test is edited" (D-2307 is about the app-target guards; the 19e edits are Phase 1A's, listed
   here).
3. **D-2303's CoreLocation spellings are right for this target but unverifiable off-device.**
   `authorizationStatus` as an instance property, `locationManagerDidChangeAuthorization(_:)` and
   `locationServicesEnabled()` are the modern forms, and the watch target's deployment target is 26.4
   (`project.pbxproj:679`), so nothing is version-gated; the `nonisolated final class … : NSObject,
   <delegate>, <seam>` shape is witnessed at `HealthKitSensorFeed.swift:47` (19d D-2113). No agent can
   compile them: confirmed only by the governor's `xcodebuild`. If a spelling is wrong, the fix is 2A's
   file and a re-run of the build.
4. **D-2304's call sites and guards, checked.** `HealthKitWorkoutStore()` is constructed only at
   `ContentView.swift:87`; `HealthKitSensorFeed(` only at the store's `sensorFeed` lazy var
   (`HealthKitWorkoutStore.swift:66`, trailing-closure form). Guards whose text the edits could break:
   S-3109's `locationPermission`-body assertions (the `.unavailable` assertion is replaced — Phase 2B
   item 1; the `.granted` false-assertion stays true); S-3114 stays green (checked: its
   `isHealthDataAvailable()` windows are the heart-rate/steps probes, and the feed still contains no
   `requestAuthorization`); S-3116 and S-3117 stay green (the declaration and the three asserted lines
   survive); S-1509 stays green (no `case "…":` label or `default:` arm is touched); S-3110's four
   asserted strings all survive and the guard gains the new construction.
5. **The seeded arithmetic, re-derived.** S-3303: 1° of latitude on the 6,371,008.8 m sphere is
   111,194.9266 m, so 0.0050° = 555.975 m ✓ and 555.975 / 60 = 9.270 m/s ✓ (under the 20 m/s gate, over
   the max(2, 2.5) floor). Without the gate the yields read 555.975, 667.170, **778.364** — the seed
   writes 778.366, a 2 mm drift, immaterial at ±0.01 and asserted nowhere (the mutation asserts the first
   value only). S-3306: a second start at t0+3600 judging a fix stamped t0+100 → 3500 s before its start →
   dropped ✓.
6. **The prover's package-source mutations are outside phase 3's seeded scope.** The S-3301, S-3303,
   S-3304 and S-3306 mutations live in `WatchPlatformWorkout.swift`/`WatchTrackedLocation.swift`, and
   phase 3's scope is `watch/watchos/Tests/**` — 19e's Open question 10 again. Either the governor allows
   the bounded source edits for that run or applies the mutations itself; the app-target mutations are the
   governor's regardless.
7. **The evidence file's fixed headings have no docs-keeper row.** The brief fixes the six headings; the
   docs keeper records its guard-suite numbers in its run report (or the governor may collect them under
   `## Governor read-backs`).
8. **A sentence outside docs goes stale.** `scripts/pre_release_check.sh:274` says "OmniTrain has no
   location feature" — true of the phone's Info.plist it greps (`:42`, `:273`), false of the wrist after
   this unit. The script is outside every crew scope; flagged for the reviewer.
9. **Not checked this run:** the watch scheme's `xcodebuild`, the full `flutter test`/`flutter analyze`,
   and any gateway check (the brief forbids them here); the baselines are D-2311's, as given.
   `docs/watch_session_capture.md` was searched for a "the wrist cannot measure" sentence and none was
   found — the docs keeper's item 3 is a check, not an edit.

## Governor actions

- **D-2306**, as seeded: the three `INFOPLIST_KEY_NSLocationWhenInUseUsageDescription` lines with the
  owner sentence, next to the Health lines at `project.pbxproj:653`, `:705`, `:754`. The project file is
  outside every crew scope.
- The `gov` row: the watch scheme under `xcodebuild`, the full `swift test`, and the flutter baselines as
  given.
- Phase 3's prover needs bounded source edits in `watch/watchos/Sources/**` for the S-3301/S-3303/S-3304/
  S-3306 mutations (Open questions 6): allow them for that run or apply and revert them as the governor
  (19d's precedent).
- No new directory and no deletion is needed by any phase; the evidence file was created by the architect
  this run (headings only), and the review file is Phase 4's.
