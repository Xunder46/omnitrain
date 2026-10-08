# Evidence — 18b the watch's rest is a count-up

Plan: `2026-10-08-18b-watch-rest-count-up-plan.md`. Implementers append to this file; the reviewer
reads it and appends its findings. One row per checklist item, with the command and the pasted
counts. The reviewer's own checklist lives in `2026-10-08-18b-watch-rest-count-up-plan.review.md`.

## Baselines (taken before Phase 1)

| Check | Command | Result |
|---|---|---|
| Dart tests | `.github/copilot/scripts/macos/gateway.sh test` | the brief's measured baseline: 4133 passing, 1 skipped, 0 failures (re-measured green after Phase 1: `01:48 +4133 ~1: All tests passed!`). The plan's own "4061 tests, ~1 pre-existing failure" column predates this run and is stale — the suite is green at the base |
| Analyzer | `.github/copilot/scripts/macos/gateway.sh lint` | 196 issues / 0 errors — reproduced exactly after Phase 1 (`196 issues found. (ran in 2.6s)`), none in a touched file |
| Swift tests | `.github/copilot/scripts/macos/gateway.sh swift-test` | the brief's measured baseline: 348 / 0 (the plan's "335" is stale); 349 / 0 after Phase 1 |

## Phase 1 — the wrist's rest stops having a length (@developer)

| Item | Command | Result |
|---|---|---|
| `restSeconds` deleted, both stacks | `.github/copilot/scripts/macos/gateway.sh git-diff --stat` | 4 source files changed: `watch/watchos/Sources/WatchSessionEngine/WatchLoggingState.swift` `‑20/+4`, `WatchLoggingModel.swift` `‑9/+4`, `lib/watch/logging/watch_logging_state.dart` `‑22/+2`, `lib/watch/logging/watch_logging_screen.dart` `‑10/+5` (`16 insertions, 45 deletions` over all 7 files). `WatchLoggingDefaults` (both stacks), the `restSeconds` field, the init parameter and the assignment are gone; `startFollowOnTimer`/`_startFollowOnTimer` start a rest with no plan |
| `countdown` / `_countdown()` rest fallback gone | mutation (below) | `WatchLoggingModel.countdown` reads `WatchTimerKind.round` only; `WatchLoggingScreen._countdown()` reads `WatchTimerKind.round` only |
| `WatchRestIsCountUpTests.swift` (Swift source scan) | `.github/copilot/scripts/macos/gateway.sh swift-test` | `Executed 349 tests, with 0 failures`; the scan's 2 cases pass, and each fails on its own violation under a mutation (see below) |
| S-160 / S-161 / S-164 in both stacks | `gateway.sh swift-test --filter WatchLoggingTimersTests`; `gateway.sh test test/watch_logging_timers_test.dart test/watch_logging_surfaces_test.dart` | Swift `Executed 26 tests, with 0 failures`; Dart `01:48 +4133 ~1: All tests passed!` (the two named files alone: `All tests passed!`, 44 cases) |

Swift test count: 349 after Phase 1 = the brief's 348 at the base − 5 `S-005 rest timer with
screen-off haptic` cases + 4 new `S-160 / S-161 / S-164` cases + 2 new scan cases. (The plan's Done
Criteria says "the 335-test baseline"; the measured baseline in the brief is 348 — the plan's number
is stale, the arithmetic above is from the diff.)


## Phase 2 — the rest screen, with one control (@developer)

| Item | Command | Result |
|---|---|---|
| `isResting` / `endRest()` / `log()` ends the rest | | pending |
| `WatchRestView.swift` + `ContentView` branch | governor's `xcodebuild` build (app target is not `swift-test`-covered) | pending |
| `watch_rest_screen.dart` (Dart twin) | | pending |
| S-161 / S-162 / S-163 in both stacks | `.github/copilot/scripts/macos/gateway.sh test test/watch_rest_surface_test.dart` | pending |

## Phase 3 — the wire refuses a rest length (@dba)

| Item | Command | Result |
|---|---|---|
| Both validators' rest clause | `.github/copilot/scripts/macos/gateway.sh swift-test` | pending |
| `envelope.schema.json` conditional | | pending |
| Fixtures updated additively | `.github/copilot/scripts/macos/gateway.sh test test/sync_protocol_fixtures_test.dart` | pending |
| `PROTOCOL.md` row | | pending |
| S-165 both halves | | pending |

## Phase 4 — the rule where agents will hit it (@developer)

| Item | Command | Result |
|---|---|---|
| `docs/global_conventions.md` row | | pending |
| Doc sweep (rest, sync, watch surface, QA walkthrough, settings, README) | `watch_surface.md` size before/after (ceiling 51.2 KB) | pending |
| `test/rest_is_count_up_contract_test.dart` | `.github/copilot/scripts/macos/gateway.sh test test/rest_is_count_up_contract_test.dart` | pending |
| Residue sweep + grep | the grep's output, pasted | pending |

## Red → green (prove-red)

| Scenario | Command | At the base | After |
|---|---|---|---|
| S-160/S-164 | `gateway.sh prove-red HEAD test test/watch_logging_timers_test.dart test/watch_logging_surfaces_test.dart` | `gateway: prove-red: RED AT HEAD (exit 1)`, `00:00 +40 -4: Some tests failed.` — failures are the four count-up cases: `S-160 a logged set starts a rest with no planned length` (`Expected: null Actual: <90000>`), `S-164 no alert is ever owed for a rest` (an extra `round` milestone), `S-164 a paused rest is still owed no alert` (`Expected: empty Actual: [WatchTimerMilestone(rest at …17:02:00Z)]`), `S-160 a rest is a count-up with no "left" line` (`Expected: null Actual: <90000>`) | `All tests passed!` (44 cases, the two files) |
| S-161/S-162/S-163 | Phase 2 | n/a | n/a |
| S-165 | Phase 3 | n/a | n/a |
| S-166 | Phase 4 (Dart twin); the Swift half is `WatchRestIsCountUpTests` (Phase 1) | n/a | n/a |

## Mutations (Swift: the change cannot compile without, so a scan/mutation proves it)

Mutation A — restore the rest's length in `WatchLoggingState.startFollowOnTimer`'s `set` branch:

- Original line: `_ = try? await engine.startTimer(WatchTimerKind.rest)`
- Mutant: `_ = try? await engine.startTimer(WatchTimerKind.rest, plannedDurationMs: 90_000)`
- `swift-test --filter WatchLoggingTimersTests` → `Executed 26 tests, with 5 failures`:
  `testS160ALoggedSetStartsARestWithNoLength` (`XCTAssertNil failed: "90000" - a rest has no preset
  length (D-160)`), `testS164ARestIsNeverOwedAnAlert`, `testS164APausedRestIsStillOwedNoAlert`,
  `testTheModelShowsNothingLeftForARestAndOwesNoHaptic`
- `swift-test --filter WatchRestIsCountUpTests` → `Executed 2 tests, with 1 failure`:
  `testS166NoSwiftSourceStartsARestWithAPlannedDuration` (the naming scan correctly stays green — the
  mutant starts a rest with a plan but names no length)
- Restored exactly; `swift-test` → `Executed 349 tests, with 0 failures`

Mutation B — name a preset rest length in a Swift source (proves the naming scan):

- Original lines: `private func startFollowOnTimer() async {` / `switch effortKind {`
- Mutant: inserted `let restSeconds = 90` between them
- `swift-test --filter WatchRestIsCountUpTests` → `Executed 2 tests, with 2 failures`:
  `testS166NoSwiftSourceNamesAPresetRestLength` at `WatchRestIsCountUpTests.swift:50` and the planned
  -duration scan at `:69`
- Restored exactly

Mutation C — make the Swift model's `countdown` read the rest timer again (proves the model
guard; needs A, because a rest without a plan has no remaining time by definition):

- Original lines: `guard let timer = state.timer(for: WatchTimerKind.round),` /
  `timer.state != WatchTimerState.stopped else { return nil }`
- Mutant: `state.timer(for: WatchTimerKind.rest) ?? state.timer(for: WatchTimerKind.round)`, applied
  together with mutation A
- `swift-test --filter WatchLoggingTimersTests` → `Executed 26 tests, with 8 failures`:
  `testTheModelShowsNothingLeftForARestAndOwesNoHaptic` line 314 `XCTAssertNil failed: "90.0" - a rest
  is a count-up, so there is no left…`, plus `testS161ARestSurvivesTheScreenTurningOff` at `:96`
  (`the restored rest renders as elapsed time, never as …`)
- A and C restored exactly; `swift-test` → `Executed 349 tests, with 0 failures`


## Swift-side evidence

| Scenario | Command | Result |
|---|---|---|
| Scenario | Command | Result |
|---|---|---|
| S-160/S-161/S-164 | `.github/copilot/scripts/macos/gateway.sh swift-test --filter WatchLoggingTimersTests`; full `.github/copilot/scripts/macos/gateway.sh swift-test` | `Executed 26 tests, with 0 failures` for the case; `Executed 349 tests, with 0 failures` for the package. S-161's "0:00 at the log instant / 0:07 later / 4:00 after a relaunch mid-rest" splits across Phase 1 (`testS161ARestSurvivesTheScreenTurningOff`) and Phase 2's rest surface |
| S-162/S-163 | `.github/copilot/scripts/macos/gateway.sh swift-test` | pending |
| S-165 | `.github/copilot/scripts/macos/gateway.sh swift-test` | pending |
| `ContentView` branch (S-161/S-162) | governor's watchOS simulator build — agents must not claim it | pending |

## Reviewer findings

[empty — the reviewer fills this: diff versus Predicted Files, per-S-x conformance, the Impact Check
rows re-run, cross-stack agreement (Swift package vs Dart twin), quantified defects, Assumption Log
adjudication.]
