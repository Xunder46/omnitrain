# Plan 19c — evidence

Implementers append here; one section per phase. Format: what ran, the pasted result
line, and, where the phase has a `prove-red` receipt, the failing line from HEAD.
Receipts live under `.work/gateway/` and are named in each row.

## Baseline (Conductor, 2026-10-10, HEAD)

| Check | Command | Result | Log |
|---|---|---|---|
| swift-test | `.github/copilot/scripts/macos/gateway.sh swift-test` | **passed — 429 tests, 0 failures** | `.work/gateway/swift-test-20261010-013517-73825.log` |
| test (full) | `.github/copilot/scripts/macos/gateway.sh test` | **passed — 4240 passed, 1 skipped, 0 failed, exit 0** (last line `01:50 +4240 ~1: All tests passed!`) | `.work/gateway/test-20261010-013908-74896.log` |
| lint | `.github/copilot/scripts/macos/gateway.sh lint` | **196 issues, 0 errors, exit 1** — the count is the baseline, not a regression | `.work/gateway/lint-20261010-013908-74895.log` |
| build | `.github/copilot/scripts/macos/gateway.sh build` | **red at HEAD, exit 1** — "Watch companion app found. No simulator device ID has been set. A device ID is required to build an app with a watchOS companion app." **Never a Done Criterion.** | `.work/gateway/build-20261010-013517-73824.log` |
| list | `.github/copilot/scripts/macos/gateway.sh list` | checks: `lint`, `test`, `build`, `codegen`, `pub-get`, `format` (requires args, new files only), `swift-test`, `base-setup`; git views `git-status`, `git-diff`, `git-log`, `git-show`; `prove-red <ref> <check>`; `delete-scratch` | — |

Guards measured at the same time (these are the constraints the phases must respect):

- `test/docs_indexing_contract_test.dart`: `_maxDocBytes = 64 * 1024`, warning band
  `round(65536 * 0.80) = 52429` bytes and the band assertion *fails* above it;
  `_recordFiles = ['future-work.md', 'watch-app-setup-and-qa.md']`,
  `_recordFolders = ['plans', 'releases', 'memories']` — `docs/state_management/watch_surface.md`
  is **not** exempt. The full suite is green at HEAD, so that file is at or below 52429 bytes today;
  phase 3B removes before it adds. The planner could not measure bytes (no shell beyond the gateway —
  see Open question 6 of the plan).
- `watch/watchos/Tests/WatchSessionEngineTests/WatchSessionEngineTests.swift:322`
  `testS004NoMutatingOperationExistsAnywhereInTheModule`: no 4-space-indented `func` whose name starts
  with a mutating verb under `Sources/WatchSessionEngine`; any `*Store.swift` there must expose exactly
  `{append, readAll, pruneConfirmed, pruneSensorSamples}`.
- `test/rest_is_count_up_contract_test.dart` + the Swift twin scan
  `watch/watchos/Sources`, `ios/OmniTrain Watch App`, `docs/state_management/watch_surface.md` and
  `docs/watch-app-setup-and-qa.md` for the rest-countdown wording (D-1512(c)).
- `scripts/pre_release_check.sh` `runner_pbxproj_settings` (~`:108-135`) scopes its pbxproj checks to
  `Runner`-owned configurations, so the watch target's settings are not inspected by it;
  `test/pre_release_gate_ios_artifact_test.dart` is the only Dart reader of pbxproj-shaped content.

## Red → green tables

### Phase 1A — the rule, `WatchWorkoutCoordinator`, S-1500/1501/1502/1507

| Scenario | Test | Red at HEAD | Green after |
|---|---|---|---|
| S-1500 | `testS1500OpensForAnActiveSession` | `.work/gateway/swift-test-20261010-015120-83840.log`: `error: cannot find type 'WatchWorkoutCoordinator' in scope`; mutation M1 (`action` returns `.start` for any active session) → `XCTAssertEqual failed: ("start") is not equal to ("none")` at `WatchWorkoutCoordinatorTests.swift:183` | passed (`swift-test-20261010-015204-84493.log`) |
| S-1501 | `testS1501IdempotentAcrossFiveRefreshes` | mutation M1 → `("5") is not equal to ("1")` at `:213`, `("4") is not equal to ("0")` at `:214` | passed (same log) |
| S-1502 | `testS1502ClosesWhenTheSessionEnds` | mutation M2 (`case .end` drops `await platform.end()`) → `("0") is not equal to ("1")` at `:235`, `XCTAssertNil failed` at `:239` | passed (same log) |
| S-1507 | `testS1507ALaunchWithNothingToDo` | mutation M3 (`recover()` skips `platform.recoverInProgress()`) → `("[]") is not equal to ("["inProgressActivityTypes"]")` at `:299` | passed (same log) |

`prove-red HEAD swift-test` receipt (the whole file is absent at HEAD, so the guard is the compile of a
non-existent `WatchWorkoutCoordinator`) — `prove-red: RED AT HEAD (exit 1)`, first failure line:
`WatchWorkoutCoordinatorTests.swift:160:24: error: cannot find type 'WatchWorkoutCoordinator' in scope`
(`.work/gateway/swift-test-20261010-015120-83840.log`). Because that is a compile error, each scenario's
guard is proved by the mutation above instead: original lines recorded, mutated, red observed, restored
byte-for-byte (`git-diff --stat` = 105 insertions, 0 deletions), re-run green.

`swift-test` after the phase: **433 tests, 0 failures** — `Test Suite 'All tests' passed at
2026-10-10 01:52:06.955. Executed 433 tests, with 0 failures (0 unexpected)`; the four new
`passed` lines are in `Test Suite 'WatchWorkoutCoordinatorTests'` (S-1500, S-1501, S-1502, S-1507,
each `passed`), log `.work/gateway/swift-test-20261010-015204-84493.log`.

Other checks after the phase: `gateway.sh test` — **4240 passed, 1 skipped, 0 failed** (last line
`01:52 +4240 ~1: All tests passed!`, `.work/gateway/test-20261010-015228-84781.log`); `gateway.sh test
test/rest_is_count_up_contract_test.dart` — passed, 10 tests; `git-diff --stat` — only
`WatchPlatformWorkout.swift`, `105 insertions(+)`, nothing deleted.


### Phase 1B — S-1503, S-1504, S-1505, S-1508, S-1510

| Scenario | Test | Red at HEAD | Green after |
|---|---|---|---|
| S-1503 | `testS1503RelaunchEndsTheStrandedWorkoutThenOpensTheSessions` | `prove-red HEAD swift-test --filter WatchWorkoutCoordinatorTests -- <the test file>`: **RED AT HEAD (exit 1)**, `error: cannot find type 'WatchWorkoutCoordinator' in scope` at the file's `:170:24` (`.work/gateway/swift-test-20261010-015806-92440.log`) — the coordinator the scenario drives is absent from HEAD's package | passed (`swift-test-20261010-015722-92004.log`) |
| S-1504 | `testS1504ADifferentSessionReplacesTheRunningOne` | same receipt (the scenario needs the coordinator and its `openedForSessionId` comparison) | passed (same log) |
| S-1505 | `testS1505DenialIsNotFailure` | same receipt (`refresh` against a refusing store does not exist at HEAD) | passed (same log) |
| S-1508 | `testS1508TwoRacingRefreshesOpenOneWorkout` | same receipt (the serial tail the scenario parks inside does not exist at HEAD) | passed (same log) |
| S-1510 | `testS1510AKilledWorkoutWithNoSessionToReplaceIt` | same receipt (`recoverInProgress` does not exist at HEAD) | passed (same log) |

The whole `WatchWorkoutCoordinatorTests.swift` is absent at HEAD, so one receipt covers all nine scenarios; it
is a *compile* failure, so per the gateway's own note each scenario's guard is what 1A proved by mutation
(this phase ran no mutation — the brief forbids editing `Sources/`).

`swift-test` after the phase: **438 tests, 0 failures** — `Test Suite 'All tests' passed at
2026-10-10 01:57:24.655. Executed 438 tests, with 0 failures (0 unexpected)`; `Test Suite
'WatchWorkoutCoordinatorTests'` executed 9, with 0 failures (S-1500, S-1501, S-1502, S-1503, S-1504,
S-1505, S-1507, S-1508, S-1510 each `passed`); log `.work/gateway/swift-test-20261010-015722-92004.log`.
No `Sources/` file was touched by this phase.

Other checks after the phase: `gateway.sh test` — **4240 passed, 1 skipped, 0 failed**, last line
`01:48 +4240 ~1: All tests passed!` (`test-20261010-015859-93060.log`); `gateway.sh lint` — **196 issues,
0 errors, exit 1**, the baseline (`lint-20261010-015854-92932.log`); the invariant
`grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` — no output.

### Phase 2A — the real store in the app target

| Scenario | Test | Red at HEAD | Green after |
|---|---|---|---|
| S-1509 | `testS1509TheStoreMapsEveryContractActivityName` | `gateway: prove-red: RED AT HEAD (exit 1)` — `error: -[... testS1509TheStoreMapsEveryContractActivityName] : failed: caught error: "Error Domain=NSCocoaErrorDomain Code=260 ..."` at `WatchWorkoutStoreSourceTests.swift:27` (the app-target file does not exist at HEAD; 1 test, 1 failure) | `Test Case '-[WatchSessionEngineTests.WatchWorkoutStoreSourceTests testS1509TheStoreMapsEveryContractActivityName]' passed (0.001 seconds)`; `Executed 1 test, with 0 failures (0 unexpected)` |

**Mutation receipts (the guard cannot compile at HEAD, so its two arms are proved by mutation of the
new source, each restored byte-for-byte and re-run green).**

- M1 — `case "flexibility":` → `case "flexibilityX":` in `HealthKitWorkoutStore.activityType(for:)`:
  `error: ... : XCTAssertEqual failed: ("["crossTraining", "traditionalStrengthT ...` at
  `WatchWorkoutStoreSourceTests.swift:73`, 1 test / 1 failure; restored → `passed (0.002 seconds)`.
- M2 — the mapping's `default:` arm `.other` → `.running`:
  `error: ... : XCTAssertTrue failed - an unmapped name has to land on the gener ...` at
  `WatchWorkoutStoreSourceTests.swift:80`, 1 test / 1 failure; restored → `passed (0.002 seconds)`.

`swift-test` after the phase: **439 tests, 0 failures** —
`Executed 439 tests, with 0 failures (0 unexpected) in 1.429 (1.456) seconds`
(`swift-test-20261010-023620-29878.log`), i.e. the 438 of 1A+1B plus the S-1509 guard.

Other checks after the phase: `gateway.sh test` — **4240 passed, 1 skipped, 0 failed**, the baseline,
`01:59 +4240 ~1: All tests passed!` (`test-20261010-023852-30962.log`), run because the new file lives
in a directory the Dart contract tests scan; `gateway.sh test test/rest_is_count_up_contract_test.dart` — **10 passed,
0 failed**, `00:00 +10: All tests passed!`, so the new app-target file carries none of D-1512(c)'s
forbidden wording; `gateway.sh lint` — **196 issues, 0 errors, exit 1**, the baseline, none in
`HealthKitWorkoutStore.swift`, `WatchWorkoutStoreSourceTests.swift` or the `WatchSensorRecording.swift`
comment (`lint-20261010-023723-30523.log`); `gateway.sh git-diff --stat` for the comment-only edit —
`WatchSensorRecording.swift | 10 +++++---` (5 comment lines replaced, nothing else).

**API forms used (no fallback needed).** All of D-1502's calls exist in the async form on this
deployment target, so no `withCheckedContinuation` bridge and no `[]`-only recovery was needed:
`HKHealthStore()`, `HKHealthStore.isHealthDataAvailable()`, `try await
healthStore.requestAuthorization(toShare: [HKObjectType.workoutType()], read: [])`,
`healthStore.authorizationStatus(for:)`, `HKWorkoutConfiguration()` (`.activityType`,
`.locationType = .unknown`), `try HKWorkoutSession(healthStore:configuration:)`,
`session.associatedWorkoutBuilder()`, `builder.dataSource = HKLiveWorkoutDataSource(...)`,
`session.startActivity(with:)`, `try await builder.beginCollection(at:)`, `session.end()`,
`try await builder.endCollection(at:)`, `try await builder.finishWorkout()`,
`try await healthStore.recoverActiveWorkoutSession()`. The store never throws: every call is inside a
`do`/`catch` and a failure leaves `session`/`builder` nil.

**(governor)** watch-target compile, `xcodebuild -project ios/Runner.xcodeproj -target "OmniTrain Watch App" -configuration Debug -sdk watchsimulator build`:
(to fill — command, exit status, the last few lines). Nothing off-device compiles the app target:
`HealthKitWorkoutStore.swift` is `#if os(watchOS)` and `HealthKit` does not exist on macOS, so
`swift-test` only exercises the source guard that reads the file. If the compile reports a spelling
difference, it is the store's to fix and the store's alone (the package and the coordinator are
unaffected).

### Phase 2B — the host drives it (compile-only off-device)

No package source changed, so there is no red→green row: the coordinator's behaviour is 1A/1B's, and
`ContentView.swift` is app-target only (`swift test` cannot compile it). What the phase proves is that
the wiring compiles and that nothing in the package moved.

| Check | Command | Result |
|---|---|---|
| package suite unchanged | `.github/copilot/scripts/macos/gateway.sh swift-test` | **439 tests, 0 failures** — `Executed 439 tests, with 0 failures (0 unexpected) in 1.464 (1.492) seconds` (`swift-test-20261010-024502-39149.log`), the same totals as after 2A |
| lint unchanged | `.github/copilot/scripts/macos/gateway.sh lint` | **196 issues, 0 errors, exit 1** (`lint-20261010-024512-39280.log`), the baseline; none in `ContentView.swift` |
| footprint | `.github/copilot/scripts/macos/gateway.sh git-diff --stat` | `ios/OmniTrain Watch App/ContentView.swift | 25 +++++` — 25 insertions, 0 deletions, nothing else (the `.claude/` and `project.pbxproj` entries are the governor's pre-existing modifications, left alone) |
| interface invariant | `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` | no matches (unchanged; this phase touches no Dart) |
| full suite (not required — no Dart changed) | `.github/copilot/scripts/macos/gateway.sh test` | **4240 passed, 1 skipped, 0 failed** — `01:59 +4240 ~1: All tests passed!` (`test-20261010-024724-40108.log`), the baseline |
| docs guards (this run edited two plan files) | `.github/copilot/scripts/macos/gateway.sh test test/docs_indexing_contract_test.dart test/rest_is_count_up_contract_test.dart` | **9 passed / 0 failed** and **10 passed / 0 failed**, both `All tests passed!` |

**What the wiring does (the three brief items).** `WatchAppHost.workout: WatchWorkoutCoordinator` is built
once in `init()` right after `rating`, over `WatchPlatformWorkout(store: HealthKitWorkoutStore())`; the
`$revision` sink beside the `rating.objectWillChange` sink calls `await self.workout.refresh(self.engine.session)`
on every emission (its immediate first emission is the empty pre-`restore()` session, `.none`); `restore()`
opens with `await workout.recoverInProgress()` before `await engine.restore()`. `engine.session` is a
`public var session: WatchSessionRecord?` on a nonisolated class, readable from the main actor.

**(governor)** the compile witness. The plan's `-target` form cannot resolve the local Swift package, so the
governor runs:

```sh
xcodebuild -workspace ios/Runner.xcworkspace -scheme "OmniTrain Watch App" \
  -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (42mm)' build
```

Exit status and the last lines: (to fill — governor). A compile error here is the wiring's to fix; the
package and the coordinator are unaffected.

### Phase 3A — configuration, S-1506

**Implemented (developer).** `ios/OmniTrainWatchApp.entitlements` (new: `com.apple.developer.healthkit` = true,
same plist shape as `ios/Runner/Runner.entitlements`, outside both Xcode groups per D-1510) and the three
watch build configurations only (Debug `46AC7A22…`, Release `46AC7A23…`, Profile `46AC7A24…`; the blocks
whose `PRODUCT_BUNDLE_IDENTIFIER = dev.sasha.omnitrain.watchkitapp`). Four settings per block, alphabetical:
`CODE_SIGN_ENTITLEMENTS = OmniTrainWatchApp.entitlements;` above `CODE_SIGN_STYLE`;
`INFOPLIST_FILE = OmniTrainWatchApp-Info.plist;` below `GENERATE_INFOPLIST_FILE = YES;`;
`INFOPLIST_KEY_NSHealthShareUsageDescription` and `INFOPLIST_KEY_NSHealthUpdateUsageDescription` after
`INFOPLIST_KEY_CFBundleDisplayName`. Footprint: `git-diff --stat` on
`ios/Runner.xcodeproj/project.pbxproj` = **12 insertions(+), 0 deletions** (4 per block — the brief said
"+15 expected: 5 per block", but its own enumerated edits are four settings); `grep -c OmniTrainWatchApp.entitlements
ios/Runner.xcodeproj/project.pbxproj` = **3**. No `PBXFileReference`/`PBXBuildFile`/`PBXGroup`/`exceptions`
entry, phone and RunnerTests blocks untouched (D-1510).

**D-1511 fallback — `WKBackgroundModes` (fix run).** The primary mechanism, `INFOPLIST_KEY_WKBackgroundModes =
workout-processing;` on the same three blocks, was placed in all three and read back by the governor from the
built product (`…/OmniTrain Watch App.app/Info.plist`, full `plutil -p`): the two `NSHealth…UsageDescription`
keys are present and the entitlements witness (`…-Simulated.xcent`) holds
`com.apple.developer.healthkit = true`, but **`WKBackgroundModes` read back MISSING** — no
`INFOPLIST_KEY_WKBackgroundModes` key is generated. D-1511's recorded fallback therefore applies: the build
setting was deleted from all three watch blocks and replaced by
`INFOPLIST_FILE = OmniTrainWatchApp-Info.plist;` pointing at the new fragment `ios/OmniTrainWatchApp-Info.plist`
(holds only `WKBackgroundModes = [workout-processing]`; outside both Xcode groups; `GENERATE_INFOPLIST_FILE = YES`
stays, so Xcode merges the fragment with the generated keys; no `PBXFileReference`/`PBXBuildFile`/group entry).
`grep -c "INFOPLIST_FILE = OmniTrainWatchApp-Info.plist"` = **3**; no `INFOPLIST_KEY_WKBackgroundModes` remains;
3 lines removed and 3 added against the phase-3A state (the HEAD diff stays at 12 insertions, 0 deletions).
Re-checked `.github/copilot/scripts/macos/gateway.sh test test/pre_release_gate_ios_artifact_test.dart`:
**12 passed, 0 failed**, last line `00:35 +12: All tests passed!`. The merged-product read-back (§2 below) is
the governor's to paste.

`.github/copilot/scripts/macos/gateway.sh test test/pre_release_gate_ios_artifact_test.dart`: **12 passed,
0 failed**, last line `00:34 +12: All tests passed!` (the pbxproj's only Dart reader; the watch target is
excluded from `runner_pbxproj_settings`, so it stays green).

All four rows below are the governor's; each command is run exactly as written and its output pasted.
The exact command list (item 6):

```sh
xcodebuild -project ios/Runner.xcodeproj -target "OmniTrain Watch App" -configuration Debug -sdk watchsimulator build
xcodebuild -project ios/Runner.xcodeproj -target "OmniTrain Watch App" -configuration Debug -sdk watchsimulator -showBuildSettings \
  | grep -E ' (TARGET_BUILD_DIR|FULL_PRODUCT_NAME) = '        # resolves the two path variables below
plutil -p ios/OmniTrainWatchApp-Info.plist                                           # the fragment itself (D-1511 fallback)
plutil -p "<TARGET_BUILD_DIR>/<FULL_PRODUCT_NAME>/Info.plist"
codesign -d --entitlements :- "<TARGET_BUILD_DIR>/<FULL_PRODUCT_NAME>"
find ~/Library/Developer/Xcode/DerivedData -name '*.xcent' -newermt '-2 hours' -exec plutil -p {} \;   # fallback witness
find "<TARGET_BUILD_DIR>/<FULL_PRODUCT_NAME>" -name '*.entitlements'                                  # expect no output
```

| # | Command | What it proves | Result |
|---|---|---|---|
| 1 | `xcodebuild -project ios/Runner.xcodeproj -target "OmniTrain Watch App" -configuration Debug -sdk watchsimulator build` | the target builds with the new settings | (governor) |
| 2 | `plutil -p "<TARGET_BUILD_DIR>/<FULL_PRODUCT_NAME>/Info.plist"` | `NSHealthShareUsageDescription`, `NSHealthUpdateUsageDescription`, `WKBackgroundModes` are present with D-1511's exact strings, and nothing else was added | (governor) |
| 3 | `codesign -d --entitlements :- "<TARGET_BUILD_DIR>/<FULL_PRODUCT_NAME>"`; if an unsigned simulator build shows none, the processed file under the intermediates via `plutil -p` on the `**/*.xcent` | `com.apple.developer.healthkit` is on the product | (governor) |
| 4 | `find "<TARGET_BUILD_DIR>/<FULL_PRODUCT_NAME>" -name '*.entitlements'` | no `*.entitlements` file is bundled as a resource | (governor) |

### Phase 3B — docs and the residue sweep

**Implemented (developer).** Six items, four files. Item 1: the stale audit-pointer sentence deleted and the
fakes-only sentence narrowed to the sensor seam, with the true workout-seam sentence added
(`watch_surface.md:695-706`). Item 2: the structure row names `HealthKitWorkoutStore` and a new row names
`WatchWorkoutCoordinator` (`:687-688`). Item 3: the invariant bullet added at `:752-755`. Item 4: the
**(owner)** capability step in §3.4 and two **(owner)** walkthrough steps 21–22, plus the lines the phase
made false (the fragment `ios/OmniTrainWatchApp-Info.plist`, the `INFOPLIST_KEY_*` usage strings, the
step-range sentences). Item 5: row 19c replaced. Footprint: `git-diff --stat` = `watch_surface.md` 18
lines changed, `watch-app-setup-and-qa.md` 52 lines changed, `2026-10-08-18-watch-qa-index.md` 1 line.

| Check | Command | Result |
|---|---|---|
| full suite | `.github/copilot/scripts/macos/gateway.sh test` | **4240 passed, 1 skipped, 0 failed**, last line `01:59 +4240 ~1: All tests passed!` (log `.work/gateway/test-20261010-030057-49663.log`) |
| size band + link + wording guards | `.github/copilot/scripts/macos/gateway.sh test test/docs_indexing_contract_test.dart test/rest_is_count_up_contract_test.dart` | **19 passed, 0 failed**, last line `00:00 +19: All tests passed!` |
| lint | `.github/copilot/scripts/macos/gateway.sh lint` | **196 issues, 0 errors** (exit 1 is the repo's pre-existing info notices; baseline) |
| residue | `grep -n "provides the real bindings" docs` | no output in any doc — only the plan's own two lines (`2026-10-10-19c-...-plan.md:104,183,188`) name the phrase, which is the record, not the claim |
| residue | `grep -n "WatchPlatformWorkoutStore" docs/state_management/watch_surface.md` | one line: `:696` — "`WatchSensorSource` and `WatchPlatformWorkoutStore` are the seam the OS bindings sit behind", which names the seam generally; `:700` names the real binding (`HealthKitWorkoutStore`); no line claims the seam is unimplemented in the app target |
| residue | banned rest wording (D-1512(c)) in the two touched docs | none — `test/rest_is_count_up_contract_test.dart` green above, which is the mechanical proof |

## What the planner could not do (tools denied)

- `xcrun --sdk watchos --show-sdk-path` and reading the HealthKit headers under
  `/Applications/Xcode.app/.../WatchOS.sdk/.../HealthKit.framework/Headers` — denied: the file tools
  reach only paths inside this repository, and the gateway's only command is the gateway itself. The
  Apple API spellings the store needs are therefore unverified and carry named fallbacks (plan,
  Open question 2). **Governor action**: run the `xcrun`/header grep if the spellings are to be
  confirmed before phase 2A.
- `xcodebuild` (the watch target build) and the whole S-1506 read-back chain — governor only.
- A byte count for `docs/state_management/watch_surface.md` (no shell): the plan infers "at or below
  52429 bytes" from the full suite being green at HEAD. **Governor action**: `wc -c` that file if the
  band is to be known before phase 3B.
- `rg` for the phase 3B residue sweep: the rows above are the governor's to fill (the plan records the
  exact patterns). The planner verified the touched files by reading them.
- The directory `docs/plans/2026-10-10-19c-watch-keep-alive-plan/` already existed (it holds the
  plan); no directory had to be created.

## Assumption Log entries recorded by implementers

(Implementers append here as well as in the plan's Assumption Log; one line each, with the phase.)

- (developer, 1A) `prove-red` is a compile error (the type is new), so the four guards are proved by
  mutations M1/M2/M3 of the new source; each red line is in the table above and each mutation was
  restored before the green run (`git-diff --stat`: 105 insertions, 0 deletions).
- (developer, 1A) `ScriptedPlatformStore` routes its state through a synchronous `withState` helper so
  `NSLock` is never called from an `async` body — the direct form warns under Swift 5.9 while compiling
  for Swift 6, and the new file compiles warning-free.
- (developer, 1A) `WatchWorkoutCoordinator.openedForSessionId` is `private(set) var` (internal read,
  private write), the plan's "internal `openedForSessionId`": 1B's S-1504 reads it.
- (developer, 1B) S-1508 waits on `ScriptedPlatformStore.beginIsParked`, a new read-only accessor on the
  1A fake, before releasing the gate: `begun` is appended on entry, so polling it would resume a
  continuation that has not been stored yet and hang. `yieldUntil` polls a bounded `Task.yield()` loop,
  never a wall-clock threshold. No `Sources/` file was touched.
- (developer, 1B) S-1504's replacement session is built on a second `Harness(sessionId: "s-watch-2")`:
  the harness mints one session id per engine, and the coordinator reads only the record's `sessionId`,
  so both legs go through the real engine (`createSession` / `abandonSession`).

