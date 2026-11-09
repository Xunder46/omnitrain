# Evidence — 19f watch GPS feed

## Baselines

- `swift-test` at `14c868d`: **481 tests, 0 failures** (D-2311, as given).
- `swift-test` after 2B: **493 tests, 0 failures** (report-2B: baseline 481 + 1A's package scenarios + 7 new guards).
- `flutter test`: **+4240 ~1, all passed** (D-2311, as given).
- `flutter analyze`: **196 issues, 0 errors** (D-2311, as given; report-2B re-ran `lint`: `196 issues found. (ran in 3.2s)`, all `info`).
- Docs guards (`test/docs_indexing_contract_test.dart` + `test/rest_is_count_up_contract_test.dart`): **19 tests, all passed** (D-2311, as given).

## Phase 1A

From `.work/crew/19f/report-1A.md` (crew-builder-watch):

- D-2301 + D-2309: `WatchPlatformWorkoutStore` requires `begin(_:outdoors:)`; the protocol extension
  carries both forwarding defaults (`begin(_:outdoors:)` → `begin(_:)`, `begin(_:)` →
  `begin(_:outdoors:, outdoors: false)`). `FakePlatformStore` and `ScriptedPlatformStore` not edited.
- `WatchPlatformWorkout.start` calls `store.begin(activityType.watchOs, outdoors: WatchGpsPolicy.isRequired(session.modality))`.
- D-2302: `WatchTrackedLocation.init(source:clock:maxFixAgeSeconds:)` with `clock: @escaping () -> Date = Date.init`,
  `maxFixAgeSeconds: TimeInterval = 10`; `fixes()` reads `clock()` once per call and skips, before the
  tracker, any raw fix with `raw.timestamp < clock() - maxFixAgeSeconds` (exactly at the limit is kept).
- S-3300, S-3301 in the new `WatchOutdoorWorkoutTests.swift` (`RecordingOutdoorPlatformStore` implements
  ONLY `begin(_:outdoors:)`, `LegacyShapePlatformStore` ONLY `begin(_:)`); S-3303, S-3304, S-3306 appended
  to `WatchDistanceTrackerTests.swift` with the arithmetic inline at ±0.01 m.
- D-2310's five constructions pass a fixed clock (`{ base }`, `base = t0`); the two constructions that
  never consume fixes are untouched.
- Checks seen: `swift-test --filter WatchOutdoorWorkoutTests` → `Executed 2 tests, with 0 failures`;
  `--filter WatchDistanceTrackerTests` → `Executed 16 tests, with 0 failures`; full `swift-test` →
  `Executed 486 tests, with 1 failure (0 unexpected)` — 486 = 481 + 5 new; the one failure is
  `testS3109TheFeedIsTheRealSourceAndTheStoreReadsBothTypes`, predicted by D-2307 and 2B's to fix.
  `testS004NoMutatingOperationExistsAnywhereInTheModule` green.

## Phase 2A

From `.work/crew/19f/report-2A.md` (crew-builder-watch; no gateway check, per the seed's rule):

- `CoreLocationRawSource.swift` (new, whole file under `#if os(watchOS)`): `nonisolated final class
  CoreLocationRawSource: NSObject, CLLocationManagerDelegate, WatchRawFixSource`; the manager created and
  configured in `init` (`kCLLocationAccuracyBest`, `.fitness`, `delegate = self`); `permission()` answers
  `.unavailable` when `locationServicesEnabled()` is false, maps the status, requests WhenInUse once and
  waits for `locationManagerDidChangeAuthorization(_:)`; `rawFixes()` starts the radio on the first
  subscriber and stops it on the last termination, both via `DispatchQueue.main.async`; one
  `WatchRawFix` per `CLLocation`; `didFailWithError` does nothing.
- `HealthKitSensorFeed.swift`: `init(authorization:location:)`; `locationPermission()` →
  `await location.permission()`; `location()` → `location.fixes()`; header rule 3 rewritten; still no
  `import CoreLocation`, no `requestAuthorization`.
- `HealthKitWorkoutStore.swift`: `init(location: WatchTrackedLocation)`; `begin(_:outdoors:)` with
  `configuration.locationType = outdoors ? .outdoor : .unknown`; `begin(_:)` a one-line forward to
  `begin(activityType, outdoors: false)`.
- `ContentView.swift`: `WatchAppHost.init` builds
  `HealthKitWorkoutStore(location: WatchTrackedLocation(source: CoreLocationRawSource()))`.
- Compiled by the governor's `xcodebuild` (see Governor read-backs).

## Phase 2B

From `.work/crew/19f/report-2B.md` (crew-builder-watch):

- S-3109 rewritten (D-2307): the `locationPermission` body asserts `trackedLocation.permission()` and not
  `.unavailable`; the no-`import CoreLocation`, no-`.granted`, read-set and name assertions kept.
- S-3110 gains the host's new construction (`WatchTrackedLocation(source: CoreLocationRawSource())`).
- New guards: S-3310 (WhenInUse, never Always, the raw source's tokens), S-3311 (the feed delegates),
  S-3312 (the store's init and outdoor begin), S-3313 (the host builds the source and the adapter once),
  S-3314 (the permission sentence, three lines, no Always key), S-3315 (Location off answers
  `.unavailable` before any status is read), S-3316 (the radio follows the subscribers on the main queue).
- Checks seen: `swift-test --filter WatchSensorSourceSourceTests` → `Executed 12 tests, with 0 failures`;
  full `swift-test` → `Executed 493 tests, with 0 failures (0 unexpected) in 2.002 (2.039) seconds`;
  `lint` → `196 issues found. (ran in 3.2s)`, all `info`.
- No `prove-red` run (the governor applies the mutations); no `xcodebuild`, no device.

## Prover verdicts

From `.work/crew/19f/report-prover.md` and `.work/crew/19f/report-prover-fix1.md`:

- **Run 1 (phase 3).** Repaired `testS3306TheClockIsReadOncePerCall` (F5's MISS): the second call now
  feeds, before the 3610 s fix, a fix stamped t0 + 100 s, so under the init-clock mutant the first yield
  reads 555.975 m against the asserted 111.195 m (arithmetic in the test). `swift-test --filter
  WatchDistanceTrackerTests` → 16 tests, 0 failures. Found and closed three source-guard blind spots in
  `WatchSensorSourceSourceTests.swift` (+30/−2): S-3310's manager configuration asserted inside
  `initBody` (moving it out of `override init()` would have stayed green file-wide), S-3310's
  `requestWhenInUseAuthorization()` bounded to one occurrence, S-3312's `locationType` sentence asserted
  inside `functionBody(named: "begin")`. Full suite at the time: 493 tests, 0 failures. The four guards
  needing production mutations (the S-3306 fix, the two S-3310 scoping pins, the S-3312 scoping) were
  left to the governor's apply-and-restore rounds.
- **Run 2 (fix1, review finding 4).** Added `testS3307ALateArrivingFixStampedAfterTheStartIsKept` to
  `WatchDistanceTrackerTests.swift`: the clock advances 50 s mid-stream, and a fix stamped after the
  call's start but arriving late is kept by the per-call gate and dropped by the per-fix mutant
  (`next()` returns nil, `XCTUnwrap` fails). `--filter WatchDistanceTrackerTests` → 17 tests, 0
  failures; full suite 496 tests, 0 failures.

The governor's mutation tables, verbatim (harness `.work/2026-10-10-19f/mutate8.py`; each restored
byte-identical; suite before: 493 tests, 0 failures; the app-target guards read the app files as text):

| # | Guard | Mutation | Result |
|---|---|---|---|
| F1 | S-3300 | `outdoors:` always true in `WatchPlatformWorkout.start` | RED |
| F2 | S-3301 | the forwarding default stops calling `begin(_:)` | RED (also the old-shape stores in 19c tests: S-001, S-007, S-1500 and others) |
| F3 | S-3303, S-3304 | stale gate removed | RED |
| F4 | S-3304 | gate boundary excluded (`>`) | RED |
| F5 | S-3306 | the clock read once at init instead of per subscription | **MISS**: green. Cause: the test's second call only feeds fixes fresh for both clocks (3610 s, 3640 s after t0); the fix stamped t0+100, stale for the second call and fresh for the first, is never fed to it. Fix assigned to the prover. |
| F6 | S-3310 | `nonisolated` removed from the raw source | RED |
| F7 | S-3310 | the raw source asks for Always | RED |
| F8 | S-3311, S-3109 | the feed answers `.unavailable` again | RED (both) |
| F9 | S-3312 | the store registers every workout as not outdoor | RED |
| F10 | S-3313, S-3110 | the host builds the store without the location source | RED (both) |
| F11 | S-3314 | the permission sentence changed in the project file (three lines) | RED |
| F12 | S-3315 | the Location-services check removed | RED |
| F13 | S-3316 | the radio never stopped | RED |

Second table (harnesses `.work/2026-10-10-19f/mutate9.py` and `mutate10.py`; each restored
byte-identical; suite 496 tests, 0 failures; `xcodebuild` BUILD SUCCEEDED, zero warnings in the changed
app files):

| # | Guard | Mutation | Result |
|---|---|---|---|
| F5 (re-run) | testS3306 | the stale gate's clock read once at init | RED (after the prover repair: the t0+100 fix reaches the second call) |
| P1 | testS3310 | the manager configuration moved out of `override init()` | RED |
| P2 | testS3310 | a second `requestWhenInUseAuthorization()` call site | RED |
| P3 | testS3312 | the `locationType` sentence moved out of `begin(_:outdoors:)` | RED |
| G1 | testS3317 | the ask latched again (Allow Once hang) | RED |
| G2 | testS3318 | a revoked permission no longer ends the feed | RED |
| G3 | testS3317 | the waiter re-check resumes unconditionally (double resume) | RED |
| G4 | testS3307 (new) | the stale gate reads the clock per fix instead of per call | RED (S-3307 only; S-3306 is not meant to catch it, which review finding 4 pointed out) |

Reconciliation as written there: 13 (F1–F13) + 4 (P1–P3 and the F5 re-run) + 4 (G1–G4) = **21 mutation
runs**, plus the earlier F5 MISS.

## Review round 1 and fix round

From `.work/crew/19f/governor-mutations-fix1.md` (verbatim facts, finding rulings):

Review round 1 (APPROVE WITH FIXES, 1 blocker, 3 major, 4 minor): finding 1 Blocker (a latched
permission ask, Allow Once) FIXED, G1; finding 5 (waiter race) FIXED, and the fix itself introduced a
double resume that the governor found by reading and had fixed, G3; finding 6 (revocation mid-session)
FIXED, G2; finding 4 (per-fix clock) FIXED, S-3307, G4; finding 3 (verdicts not recorded) and 8 (a
citation) recorded in the docs; finding 2 (Major) NOT changed: a session that ends while the Location
question is on screen keeps its sensors until the user answers, because the stop waits behind the parked
start on the sensors' serial tail. Governor ruling: a wait on a pending modal, not a deadlock; the
proper fix (a cancellable permission wait and a coordinator that cancels an in-flight start) reworks the
19d coordinator's serial tail and its tests; recorded as a known limitation and an open follow-up.
Finding 7 (`scripts/pre_release_check.sh:274` says "OmniTrain has no location feature") is the owner's
file: reported, not edited.

## Governor read-backs

- `swift-test`: 481 (baseline, D-2311) → 493 (after 2B) → 495 (after the review fixes: +testS3317,
  +testS3318) → 496 (after the prover's fix1: +testS3307), 0 failures throughout.
- `flutter analyze` and the Dart suite: re-run by the governor at the end — final: see the next
  read-back.

Other governor facts: `xcodebuild` watch scheme: first build FAILED (`invalid redeclaration of
'location()'`: the feed's new stored property `location` collided with the `location()` method; fixed by
renaming the property to `trackedLocation`, init label unchanged); then BUILD SUCCEEDED with four Sendable
warnings in CoreLocationRawSource.swift, fixed by `@preconcurrency import CoreLocation`; the final build
has zero warnings in the changed app files and the built watch app's Info.plist carries
NSLocationWhenInUseUsageDescription = "OmniTrain uses your location during runs and sports to measure
distance and pace.", the Health string and the workout-processing background mode. `swift test` 493 tests,
0 failures. Crew facts: the DeepSeek architect died twice with the provider's "reasoning_content" 400
error; the plan was written by glm-5.3-flash (32 requests, 6 min, seed intact). Owner item:
`scripts/pre_release_check.sh:274` still says "OmniTrain has no location feature" (it checks only the
phone's Info.plist, so the gate stays green).
