# Review: 2026-10-10-19d-watch-heart-rate-and-steps-plan · phases 1A, 2A, 2B · ed14570..HEAD (working tree)
Verdict: APPROVE WITH FIXES
Counts: blocker 0 · major 2 · minor 2 · tests: governor-run swift-test 456/0, flutter test +4240 ~1, flutter analyze 196 issues 0 errors, 2× xcodebuild BUILD SUCCEEDED, 13 mutations RED (evidence file); reviewer spot-check `swift-test --filter WatchSensorSourceSourceTests` → "Executed 4 tests, with 0 failures (0 unexpected) in 0.004 (0.005) seconds"
Diff vs Predicted Files: conforms for code, tests and docs; `ios/Runner.xcodeproj/project.pbxproj` carries uncommitted churn beyond D-2107's three strings (finding 1); crew-infra files (`.work/`, `.github/copilot/`, `AGENTS.md`) and governor-only artifacts are outside the plan by design.

## Findings

1. [Major] `ios/Runner.xcodeproj/project.pbxproj` (working tree, uncommitted) — the plan's impact table claims the change is "text only: three INFOPLIST_KEY_NSHealthShareUsageDescription strings; keys, target blocks and the entitlement untouched", and the governor's read-back records the pbxproj as untouched by the governor. Both are true of the commits, but the working tree carries far more: `objectVersion 54 → 70`, the `PBXFileSystemSynchronizedRootGroup` block reformatting, the package-reference comment rename (`watchos` → `../watch/watchos`), empty `inputPaths`/`outputPaths` added to the Pods embed phase, and `INFOPLIST_FILE` quoting changes. No commit contains any of it (checked all five commits with `git-show --name-only`). A maintainer pulling the branch gets a project file whose minimum Xcode rises with `objectVersion 70` and whose provenance nobody can account for; the next `xcodebuild` or pod install may rewrite it again. The three D-2107 usage strings themselves are correct on disk (lines 653, 705, 754 read exactly the D-2107 sentence). Fix: revert everything except the three usage strings, or commit the churn and record it in the evidence file as deliberate. Guard: a read-back that diffs the pbxproj against base and lists every changed line.
2. [Major] `ios/OmniTrain Watch App/HealthKitWorkoutStore.swift:101-105` — the two `dataSource.enableCollection(for:)` calls and `collection.delegate = sensorFeed` are the only lines that turn the builder into a collecting one wired to the feed (D-2105 item 5), and no test reads them: reverting all three lines passes the full swift suite (456/0), both Dart suites and every mutation, because the app target has no source guard for its own `begin`. On the wrist the builder would collect nothing, the feed would never fire, and acceptance criteria 1–4 would fail silently while every suite stays green. Fix: extend `testS3109TheFeedIsTheRealSourceAndTheStoreReadsBothTypes` (or add a fifth guard) to assert the store source contains `collection.delegate = sensorFeed` and both `enableCollection(for: HKQuantityType` calls. Guard: a mutation deleting the delegate line must go RED.
3. [Minor] `watch/watchos/Tests/WatchSessionEngineTests/WatchSensorSourceSourceTests.swift:196-233` — S-3110 pins the two constructions and the sink order but not that the recorder reads the shared store: `WatchSensorRecorder(engine: engine, source: healthStore.sensorSource)` is unasserted, so a drift to a second `HealthKitWorkoutStore()` (two Health prompts, two authorization outcomes, D-2106's one-outcome rule broken) passes the guard. Fix: one more `XCTAssertTrue(view.contains("source: healthStore.sensorSource"))` in the same test. Guard: the same assertion.
4. [Minor] `ios/OmniTrain Watch App/HealthKitWorkoutStore.swift:204` — `resolveAuthorization` sets `authorizationResolved = true` before awaiting `requestAuthorization`, so a second concurrent caller reads the not-yet-resolved `authorizationGranted == false` and answers `.denied` for the life of the process. Today's wiring cannot overlap the callers (the `$revision` sink refreshes the workout before the sensors and both coordinators serialize on their own tails; S-3110 pins the order), so this is latent, but the diff itself adds the feed's authorization closure as a second caller path. Fix: memoize the in-flight task (store the `Task<Bool, Never>` and await its value) instead of setting the flag before the await. Guard: none possible off-device (app target); S-3110's ordering pin is what currently holds this up — note it in the plan's Open questions if unfixed.

## Assumption Log rulings

- A-1 (2A: `lazy var sensorFeed` initialises on first `begin`, so the closure's `self` capture is safe) — RATIFY. `HealthKitWorkoutStore.swift:66` matches; the feed is built on first use and the store is its only holder.
- A-2 (2B: `locationPermission` may be an implicit-return single expression) — RATIFY. The guard's `permissionLines` reader matches the actual single-expression form.
- A-3 (3A: S-3115's fixture 500/2700 arithmetic) — RATIFY. 300 + 800 + 1600 = 2700; the pre-window count of 500 makes the mutation M9 red, as the prover's corrected verdict records.

## Scenario coverage

- S-3100 -> `WatchSensorCoordinatorTests.testS3100StartSubscribesAndTheFirstBeatIsStored` (mutation M1)
- S-3101 -> `WatchSensorCoordinatorTests.testS3101EndStopsAndClearsTheRecordingSessionId` (M2)
- S-3102 -> `WatchSensorCoordinatorTests.testS3102AReplacedSessionStopsOneAndStartsTheOther` (M3)
- S-3103 -> `WatchSensorCoordinatorTests.testS3103FiveRefreshesSubscribeOnce` (M4)
- S-3104 -> `WatchSensorCoordinatorTests.testS3104RefusedProbesAreAskedOnceAndLoggingIsUnaffected` (M5)
- S-3105 -> `WatchSensorCoordinatorTests.testS3105TwoOverlappingRefreshesLandInOrder` (M6)
- S-3106 -> `WatchSensorCoordinatorTests.testS3106ARelaunchOntoARestoredActiveSessionStartsSensors` (no own mutation; dies by M1 per prover verdict 2)
- S-3107 -> `WatchSensorCoordinatorTests.testS3107TheSessionEndCarriesTheHeartRateTheSensorsFedIt` (M7)
- S-3108 -> `WatchSensorCoordinatorTests.testS3108TheLiveLabelShowsTheNewestBeat` (M8)
- S-3109 -> `WatchSensorSourceSourceTests.testS3109TheFeedIsTheRealSourceAndTheStoreReadsBothTypes` (M9b/M9c; see finding 2 for the unguarded store half)
- S-3110 -> `WatchSensorSourceSourceTests.testS3110TheHostWiresTheSensorsAndRefreshesTheWorkoutFirst` (M10; see finding 3)
- S-3111 -> `WatchSensorCoordinatorTests.testS3111TheSerialTailHoldsWhileAStartIsParked` (M11)
- S-3112 -> `WatchSensorCoordinatorTests.testS3112TheRefusedProbeIsAskedOncePerSession` (M12)
- S-3113 -> `WatchSensorCoordinatorTests.testS3113OneKindGrantedTheOtherRefused` (M13)
- S-3114 -> `WatchSensorSourceSourceTests.testS3114TheFeedNeverPromptsAndAnswersUnavailableWithoutHealthData` (M9)
- S-3115 -> `WatchSensorCoordinatorTests.testS3115ATimedEntryCarriesTheStepTotalTheRecorderFedIt` (M9's pre-window fix)
- S-3116 -> `WatchSensorSourceSourceTests.testS3116TheFeedIsDeclaredNonisolated` (D-2113)

None MISSING. Every named test was read this run; every doc-named test (`watch_surface.md` ×9, `watch-app-setup-and-qa.md` ×3, `WatchLoggingView.sensorLine`) exists.

## Round 1 outcome

- Finding 1 (pbxproj churn, `objectVersion 70` etc.) — the OWNER's staged Xcode format upgrade, not
  crew work: no fix; the owner commits it with the three D-2107 usage strings.
- Finding 2 — fixed: new guard `testS3117TheStoreMakesTheBuilderCollectAndHandsItTheFeed` (S-3117)
  asserts the store source holds `collection.delegate = sensorFeed` and both `enableCollection` calls.
- Finding 3 — fixed: S-3110 also asserts `source: healthStore.sensorSource`.
- Finding 4 — fixed: `resolveAuthorization` memoises the in-flight `Task`; concurrent callers share one request.
- Governor verification: swift test 457/0; xcodebuild BUILD SUCCEEDED, no warning in the changed app
  files; mutations N1/N2/N3 each turned exactly S-3117/S-3117/S-3110 red, restored byte-identical.
- The coverage table's mutation numbers do not match the evidence table's M-numbers (cosmetic; the
  evidence table is the authority). Finding 4 has no off-device guard: S-3110's order pin plus the
  in-flight memo hold it; the on-wrist prompt check is the owner's.
