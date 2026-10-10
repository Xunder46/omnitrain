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
| S-1500 | `testS1500OpensForAnActiveSession` | (to fill) | (to fill) |
| S-1501 | `testS1501IdempotentAcrossFiveRefreshes` | (to fill) | (to fill) |
| S-1502 | `testS1502ClosesWhenTheSessionEnds` | (to fill) | (to fill) |
| S-1507 | `testS1507ALaunchWithNothingToDo` | (to fill) | (to fill) |

`prove-red HEAD swift-test` receipt (the whole file is absent at HEAD, so the guard is the compile of a
non-existent `WatchWorkoutCoordinator`): (to fill — paste the failing line).

`swift-test` after the phase: (to fill — expected 433 tests, 0 failures; paste the summary line and the
four `passed` lines).

### Phase 1B — S-1503, S-1504, S-1505, S-1508, S-1510

| Scenario | Test | Red at HEAD | Green after |
|---|---|---|---|
| S-1503 | `testS1503RelaunchEndsTheStrandedWorkoutThenOpensTheSessions` | (covered by 1A's receipt) | (to fill) |
| S-1504 | `testS1504ADifferentSessionReplacesTheRunningOne` | (covered by 1A's receipt) | (to fill) |
| S-1505 | `testS1505DenialIsNotFailure` | (covered by 1A's receipt) | (to fill) |
| S-1508 | `testS1508TwoRacingRefreshesOpenOneWorkout` | (covered by 1A's receipt) | (to fill) |
| S-1510 | `testS1510AKilledWorkoutWithNoSessionToReplaceIt` | (covered by 1A's receipt) | (to fill) |

`swift-test` after the phase: (to fill — expected 438 tests, 0 failures).

### Phase 2A — the real store in the app target

| Scenario | Test | Red at HEAD | Green after |
|---|---|---|---|
| S-1509 | `testS1509TheStoreMapsEveryContractActivityName` | (to fill — the app-target file does not exist at HEAD; `prove-red HEAD swift-test` receipt) | (to fill) |

`swift-test` after the phase: (to fill — expected 439 tests, 0 failures).

**(governor)** watch-target compile, `xcodebuild -project ios/Runner.xcodeproj -target "OmniTrain Watch App" -configuration Debug -sdk watchsimulator build`:
(to fill — command, exit status, the last few lines; record the actual Apple API spellings the
implementer chose if any fallback in phase 2A item 1 was used).

### Phase 3A — configuration, S-1506

All four rows are the governor's; each command is run exactly as written and its output pasted.

| # | Command | What it proves | Result |
|---|---|---|---|
| 1 | `xcodebuild -project ios/Runner.xcodeproj -target "OmniTrain Watch App" -configuration Debug -sdk watchsimulator build` | the target builds with the new settings | (to fill) |
| 2 | `plutil -p "<TARGET_BUILD_DIR>/<FULL_PRODUCT_NAME>/Info.plist"` | `NSHealthShareUsageDescription`, `NSHealthUpdateUsageDescription`, `WKBackgroundModes` are present with D-1511's exact strings, and nothing else was added | (to fill) |
| 3 | `codesign -d --entitlements :- "<TARGET_BUILD_DIR>/<FULL_PRODUCT_NAME>"`; if an unsigned simulator build shows none, the processed file under the intermediates via `plutil -p` on the `**/*.xcent` | `com.apple.developer.healthkit` is on the product | (to fill) |
| 4 | a directory listing of the product directory (`ls`/`find` by the governor) | no `*.entitlements` file is bundled as a resource | (to fill) |

`gateway.sh test test/pre_release_gate_ios_artifact_test.dart`: (to fill — green).

### Phase 3B — docs and the residue sweep

| Check | Command | Result |
|---|---|---|
| full suite | `.github/copilot/scripts/macos/gateway.sh test` | (to fill — expected 4240 passed, 1 skipped, 0 failed) |
| size band + link + wording guards | `.github/copilot/scripts/macos/gateway.sh test test/docs_indexing_contract_test.dart test/rest_is_count_up_contract_test.dart` | (to fill — green) |
| lint | `.github/copilot/scripts/macos/gateway.sh lint` | (to fill — 196 issues, 0 errors) |
| residue | `rg -n "provides the real bindings" docs` | (to fill — no output) |
| residue | `rg -n "WatchPlatformWorkoutStore" docs/state_management/watch_surface.md` | (to fill — only lines naming the real binding or the test fakes) |

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

