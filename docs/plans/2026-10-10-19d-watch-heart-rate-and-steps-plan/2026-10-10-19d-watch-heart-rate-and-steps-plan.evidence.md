# Evidence — 2026-10-10-19d watch heart rate and steps

Headings are fixed; each owner appends raw command output under its heading. Never rewrite another
section.

## Baselines

Base commit: `ed14570` (branch `claude_develop`), measured by crew-architect on 2026-10-10.

- `.github/copilot/scripts/macos/gateway.sh swift-test` — 439 tests, 0 failures.
- `.github/copilot/scripts/macos/gateway.sh test test/docs_indexing_contract_test.dart
  test/rest_is_count_up_contract_test.dart` — 19 tests, all passed.
- After phases 1A + 2B: `swift-test` — 456 tests, 0 failures (439 baseline + 13 coordinator tests +
  4 source guards).
- Full `flutter test` (all files) not run this session; the last recorded whole-suite figure on disk is
  4240 passed / 1 skipped (plan 19c), to be re-run by the governor.
- `flutter analyze` baseline issue count not re-measured this session (the repo carries pre-existing
  info notices; compare against the count the builder records in Phase 1A).

## Phase 1A

From `.work/crew/19d/report-1A.md` (the builder could not write that file at the time — every write
returned "Permission denied" — and the report was recovered into `.work/crew/19d/report-1A.md`
afterwards; the same happened to report-2A).

- `watch/watchos/Sources/WatchSessionEngine/WatchSensorCoordinator.swift` — new; public final class
  (not `@MainActor`, not an actor) over the concrete recorder, NSLock-guarded serial `enqueue` tail,
  `public func refresh(_:) async` awaiting `enqueue{…}.value`, internal `private(set) var
  recordingSessionId: String?`, never throws; `apply` = drift-stop → (active, nil) set id first then
  `start` → (not active, set) stop+clear. D-2102 holds (no mutating-verb method names, no
  `*Store.swift`, no `restSeconds`, no rest-length/rest-countdown spelling).
- `watch/watchos/Tests/WatchSessionEngineTests/WatchSensorCoordinatorTests.swift` — new; 13 tests,
  one per scenario (`testS3100…S3108`, `testS3111…S3113`, `testS3115`), with `CountingSource` and
  `GatedSource` declared in-file (D-2109); shared `FakeSensorSource` untouched. Written first: the
  filtered run was red while `WatchSensorCoordinator` did not exist. All waits are bounded polls
  (`eventually`/`yieldUntil`/`drainYields`) — no `Task.sleep`, no real-clock threshold.
- Filtered run then full run, both green:

```
swift-test --filter WatchSensorCoordinatorTests
  Executed 13 tests, with 0 failures (0 unexpected) in 0.140 (0.141) seconds
swift-test (full package)
  Executed 452 tests, with 0 failures (0 unexpected) in 1.614 (1.643) seconds   # 439 baseline + 13
lint: 196 issues found (exit 1), all `info` in Dart; no `watch/` path in the log
```

- Not run by the builder: `prove-red`, `xcodebuild`, Dart tests.

## Phase 2A

From `.work/crew/19d/report-2A.md` (written to the session folder at the time because the builder's
write tools denied `.work/…`; recovered to `.work/crew/19d/report-2A.md` afterwards). **No gateway
check run this phase**, per the brief: phase 1A was editing `watch/watchos` in parallel and the
gateway cannot compile the app target (`#if os(watchOS)`). Evidence is the read-back of the two
files.

- `ios/OmniTrain Watch App/HealthKitSensorFeed.swift` — new, whole file in `#if os(watchOS)`,
  `Foundation` + `HealthKit` + `WatchSessionEngine`, no location framework import; probes answer
  `.unavailable` without health data, `.denied` when the store's authorization did not resolve to
  granted, `.granted` otherwise; `locationPermission()` → `.unavailable` and `location()` finishes at
  once; continuations behind an `NSLock`, removed in `onTermination`, yielded outside the lock;
  `workoutBuilder(_:didCollectDataOf:)` yields heart rate as
  `statistics(for:)?.mostRecentQuantity()` in `HKUnit.count().unitDivided(by: HKUnit.minute())` only
  when finite and ≥ 1, steps as `statistics(for:)?.sumQuantity()` in `HKUnit.count()`;
  `workoutBuilderDidCollectEvent(_:)` empty; the feed never calls `requestAuthorization` (grep over
  `ios/OmniTrain Watch App/` matches only `HealthKitWorkoutStore.swift:207`).
- `ios/OmniTrain Watch App/HealthKitWorkoutStore.swift` — minimal edits (D-2105):
  `resolveAuthorization` now asks `read: [HKQuantityType(.heartRate), HKQuantityType(.stepCount)]` in
  the same call as `toShare: [HKObjectType.workoutType()]`; `begin` enables collection for both
  quantity types on the data source and sets `collection.delegate = sensorFeed`; the store owns one
  feed and exposes `var sensorSource: WatchSensorSource { sensorFeed }`. `activityType(for:)`,
  `name(for:)`, `end()`, `inProgressActivityTypes()` untouched.
- Assumption logged (see the plan's Assumption Log): the feed is a `private lazy var` built on first
  use over a `[weak self]` authorization closure, not an implicitly unwrapped optional assigned in
  `init()` — it needs no `init()` body change, and `init()` stays empty as before.
- Closed fix (F-1 / D-2113, `.work/crew/19d/report-2A-fix.md`): the declaration became
  `nonisolated final class HealthKitSensorFeed: NSObject, WatchSensorSource,
  HKLiveWorkoutBuilderDelegate` because the target's `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`
  bound the delegate methods to the main actor while HealthKit calls them on its own queues; the
  header's rule 2 gained one sentence saying so. No behaviour, names or lock handling changed.

## Phase 2B

From `.work/crew/19d/report-2B.md`.

- `ios/OmniTrain Watch App/ContentView.swift` — the host keeps the `HealthKitWorkoutStore` it already
  builds; `WatchSensorRecorder(engine: engine, source: healthStore.sensorSource)`;
  `WatchLoggingState(engine: engine, sensors: recorder)`; `let sensors =
  WatchSensorCoordinator(recorder: recorder)` as a stored property; the `$revision` sink awaits
  `self.workout.refresh(self.engine.session)` and then `await
  self.sensors.refresh(self.engine.session)` in the same task, workout first (D-2106). Diff: 1 file
  changed, 19 insertions(+), 3 deletions(-).
- `watch/watchos/Tests/WatchSessionEngineTests/WatchSensorSourceSourceTests.swift` — new; four
  guards reading the app-target files through `Fixtures.repositoryRoot`, comment-only lines blanked
  with the line count kept: `testS3109…` (feed conforms, names both quantity types, no
  `import CoreLocation`, `locationPermission()` body contains `.unavailable` and no `.granted`, the
  store's `requestAuthorization` read list names both types), `testS3110…` (host wiring and the
  sink's line order), `testS3114…` (no `requestAuthorization` in the feed; every
  `isHealthDataAvailable()` line has `return .unavailable` within three lines), `testS3116…` (the
  declaration line contains `nonisolated` and `final class HealthKitSensorFeed`).
- Assumption logged (see the plan's Assumption Log): on disk `locationPermission()` is an
  implicit-return body (`.unavailable`, no `return` keyword), so S-3109 checks the body contains
  `.unavailable` and no `.granted` rather than a literal `return`.
- Checks run:

```
gateway.sh swift-test --filter WatchSensorSourceSourceTests
  Executed 4 tests, with 0 failures (0 unexpected) in 0.004 (0.004) seconds
gateway.sh swift-test (full, once)
  Executed 456 tests, with 0 failures (0 unexpected) in 1.641 (1.672) seconds
```

  456 = the 452 after 1A + this phase's 4 guards; 0 failures; no prior suite went red. `prove-red`
  and `xcodebuild` were not run by the builder, per the brief.

## Prover verdicts

From `.work/crew/19d/report-prover.md` (phase 3A):

- **Prove-red at the base (`ed14570`): RED AT from a compile error, not proof** —
  `WatchSensorCoordinatorTests.swift:238:24: error: cannot find type 'WatchSensorCoordinator' in
  scope` (plus contextual-`nil` errors at :479 and :617, same missing type). The coordinator does
  not exist at the base, so no guard is proved there; every guard is proved by mutation instead.
- **Trailing-comment hole fixed in `WatchSensorSourceSourceTests.swift`**: full-line comments were
  blanked, but trailing `//` comments on code lines were not — a trailing
  `// HKQuantityType(.heartRate)` could have satisfied a `contains` guard and a trailing
  `// import CoreLocation` could have tripped an `XCTAssertFalse`. `strippingCommentLines` now also
  blanks the trailing-`//` part of code lines; after the fix
  `swift-test --filter WatchSensorSourceSourceTests` → Executed 4 tests, 0 failures, and the full
  package → Executed 456 tests, 0 failures.
- **The prover's four findings**:
  1. S-3112 is subsumed by S-3104 (same fixture, same mutation, same primary failing assertion;
     S-3104 additionally covers the location kind). Left in place; the governor may merge or
     differentiate them in a later unit.
  2. S-3106 has no mutation of its own — it dies by S-3100's skip-start; its added value is the
     restored-engine fixture. Kept as an integration guard.
  3. S-3108's label-specific mutation lives outside the new file
     (`WatchLoggingState.heartRateLabel`, WatchLoggingState.swift:269); S-3100's skip-start also
     kills S-3108. Both recorded; the governor chooses one.
  4. S-3103's mutation needs a two-line change (an addition, not a replacement), spelled out in the
     prover's table.

Mutation results applied by the governor, copied verbatim from
`.work/crew/19d/governor-mutations.md` (each mutation restored byte-identical; full suite before
each mutation: 456 tests, 0 failures; the "tests failing" column is the failing set read from the
run's `Test Case ... failed` lines):

| # | Guard (test) | Mutation (file) | Result |
|---|---|---|---|
| M1 | testS3100, testS3106, testS3107 | `WatchSensorCoordinator.swift`: `if let session { await recorder.start(session) }` commented out | RED (52 failures overall; all three named tests among them) |
| M2 | testS3101 | `WatchSensorCoordinator.swift`: `await recorder.stop()` removed in the not-active branch | RED (2 failures) |
| M3 | testS3102 | `WatchSensorCoordinator.swift`: the replaced-session test `if let recording = ..., recording != session?.sessionId` replaced by `if false` | RED (7: S-3102 and S-3111 among them) |
| M4 | testS3103 | `WatchSensorCoordinator.swift`: `recordingSessionId = nil` added on the active path before `return` | RED (16) |
| M5 | testS3104, testS3112 | `WatchSensorCoordinator.swift`: `if recordingSessionId == nil {` -> `if true {` | RED (S-3103, S-3104, S-3112 among 7) |
| M6 | testS3105, testS3111 | `WatchSensorCoordinator.swift`: `await enqueue { ... }.value` -> `await apply(session)` | RED (exactly these 2) |
| M7 | testS3108 | `WatchLoggingState.swift`: `heartRateLabel` returns nil | RED (4, incl. the 19c `testS003TheLoggingSurfaceShowsTheLiveHeartRateAndDistance`) |
| M8 | testS3113 | `WatchSensorRecording.swift`: steps permission result ignored | RED (6, incl. S-3104, S-3112, S-239) |
| M9 | testS3115 | `WatchSensorSummaries.swift`: `var previous = ...` -> `var previous = 0.0` | FIRST RUN: MISS (the pre-window count was 0, so the fixture could not tell the two apart; the prover's predicted 5600 was wrong). Fixed (pre-window count 500, expected 2700): RED (3 failures incl. S-3115) |
| M9b | testS3115 | steps summed as if not cumulative | RED (7) |
| M9c | testS3115 | only the first in-window count returned | RED (7) |
| M10 | testS3109 | `HealthKitWorkoutStore.swift`: `read: [...]` -> `read: []` | RED (2) |
| M11 | testS3110 | `ContentView.swift`: the two refresh awaits swapped | RED (1) |
| M12 | testS3114 | `HealthKitSensorFeed.swift`: no-health-data branch returns `.denied` | RED (1) |
| M13 | testS3116 | `HealthKitSensorFeed.swift`: `nonisolated` removed from the declaration | RED (1) |
| S-3117 | testS3117 | (new guard from review round 1, no own mutation; killed by N1 and N2) | — |
| N1 | testS3117 | `HealthKitWorkoutStore.swift`: `collection.delegate = sensorFeed` deleted | RED (exactly S-3117) |
| N2 | testS3117 | `HealthKitWorkoutStore.swift`: the steps `enableCollection` call dropped | RED (exactly S-3117) |
| N3 | testS3110 | `ContentView.swift`: the recorder built over a second private `HealthKitWorkoutStore()` | RED (exactly S-3110) |

On M9: the prover's predicted failing value was wrong (it had not computed it); the governor's
application of the corrected fixture (pre-window count 500, expected 2700) is the proof.

## Governor read-backs

Pasted from `.work/2026-10-10-19d/governor-readbacks.md` (as it stands on disk):

> # Governor read-backs, plan 2026-10-10-19d (base ed14570)
> - 1A+2A together (2026-10-10 ~19:27): `swift test --package-path watch/watchos` -> Executed 452 tests, 0 failures (439 baseline + 13 new), run by the governor.
> - `xcodebuild -workspace ios/Runner.xcworkspace -scheme "OmniTrain Watch App" -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (42mm)' build` -> BUILD SUCCEEDED with HealthKitSensorFeed.swift and the changed HealthKitWorkoutStore.swift (HealthKit spellings of D-2103/D-2105 compile). Log: .work/2026-10-10-19d/xcodebuild-2A.log
> - pbxproj: three INFOPLIST_KEY_NSHealthShareUsageDescription lines (653, 705, 754) set to the owner-approved text (D-2107); nothing else changed by the governor.
> - Not yet verified: wiring (2B), full `flutter test`, analyze count, prove-red / mutations, docs.

Second watch-scheme build, after 2B and the F-1 isolation fix (read from
`.work/2026-10-10-19d/xcodebuild-2B.log:1728`): `** BUILD SUCCEEDED **`, with
`HealthKitSensorFeed.swift` compiled (log lines 250–251, 271–273) and no isolation warning or error
naming `HealthKitSensorFeed` anywhere in the log — the two warnings F-1 reported
(`HealthKitSensorFeed.swift:93`, `:115`) are gone. The read-backs file on disk does not yet record
this second build or a governor-run 456-test figure; the 456 figure on disk is the builder's own
full-package run in report-2B.

**Final** (from `.work/2026-10-10-19d/governor-readbacks.md`, 2026-10-10 ~20:05, all run by the
governor):

> - Final (2026-10-10 ~20:05): `swift test --package-path watch/watchos` -> Executed 456 tests, 0 failures (governor, after the prover's guard fix and the S-3115 fix). `flutter analyze` -> 196 issues (baseline 196), 0 errors. Full `flutter test` -> +4240 ~1: All tests passed (equals the 19c baseline). Layer invariant grep -> no matches. Mutations: see .work/crew/19d/governor-mutations.md (13 distinct mutations + 2 variants; 1 initial MISS on S-3115, fixed and re-proven).

Correction to the earlier note: the governor reproduced **both** figures — 452 (after 1A+2A,
~19:27) and 456 (after the prover's guard fix and the S-3115 fix, ~20:05) — so "456 tests is the
builder's own run" no longer holds; the builder's run in report-2B is corroborated by the
governor's.

## Review round 1 and fix round

From the review (`.review.md`, verdict APPROVE WITH FIXES) and the fix commit
`fix(watch): review round 1 of plan 19d`:

- Finding 1 (pbxproj churn, `objectVersion 70` etc.) is the OWNER's staged Xcode format upgrade of
  `ios/Runner.xcodeproj/project.pbxproj`, not crew work: no fix; left for the owner to commit
  together with the three D-2107 usage strings.
- Finding 2 fixed: new guard `testS3117TheStoreMakesTheBuilderCollectAndHandsItTheFeed` (S-3117, in
  `WatchSensorSourceSourceTests.swift`) asserts the store source holds
  `collection.delegate = sensorFeed` and both `enableCollection(for: HKQuantityType…)` calls.
- Finding 3 fixed: S-3110 also asserts `source: healthStore.sensorSource`.
- Finding 4 fixed: `HealthKitWorkoutStore.resolveAuthorization` memoises the in-flight `Task`, so
  concurrent callers share one request.
- Governor verification after the fix: swift test 457 tests / 0 failures; xcodebuild watch scheme
  BUILD SUCCEEDED with no warning in the changed app files; the mutations N1–N3 (rows added to the
  table above) each turned exactly the named guard red and were restored byte-identical.
- The review's coverage table uses mutation numbers that do not match this table's M-numbers
  (cosmetic; this table is the authority). Finding 4 has no off-device guard: S-3110's order pin
  plus the in-flight memo hold it; the on-wrist prompt check is the owner's.
