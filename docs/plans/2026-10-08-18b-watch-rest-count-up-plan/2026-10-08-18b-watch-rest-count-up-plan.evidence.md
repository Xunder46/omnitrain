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
| `isResting` / `endRest()` / `restElapsedSeconds()` / `log()` ends the rest, both stacks | `.github/copilot/scripts/macos/gateway.sh git-diff --stat` | 4 tracked files changed, `69 insertions(+), 3 deletions(-)`: `lib/watch/logging/watch_logging_state.dart` `+26`, `watch/watchos/Sources/WatchSessionEngine/WatchLoggingState.swift` `+22`, `WatchLoggingView.swift` `+14/-2`, `ContentView.swift` `+10/-1`; 4 new files untracked (`WatchRestView.swift`, `watch_rest_screen.dart`, the two test files). The diff holds the three members and the one-line `log()` guard and nothing else — every mutation below was restored exactly (verified by re-reading the diff) |
| `WatchRestView.swift` + `ContentView` branch | governor's `xcodebuild` watchOS-simulator build — **not claimed green here**: `swift-test` compiles the package only, never the app target | the branch chain is `rating.isPromptOwed` → `logging.isResting` → active session → `WatchStartView`; the rest branch sits second and is the only source of a rest screen |
| `watch_rest_screen.dart` (Dart twin) | `.github/copilot/scripts/macos/gateway.sh test test/watch_rest_surface_test.dart` | one `FilledButton` "Next", one `0:00`/`0:07` text, no `OutlinedButton`/`TextButton`/`IconButton` (`All tests passed!`) |
| S-161 / S-162 / S-163 in both stacks | `.github/copilot/scripts/macos/gateway.sh test test/watch_rest_surface_test.dart test/watch_logging_timers_test.dart test/watch_logging_surfaces_test.dart`; `.github/copilot/scripts/macos/gateway.sh swift-test` | Dart `All tests passed!` (49 cases across the three files); Swift `Executed 353 tests, with 0 failures` |
| Full suite, once | `.github/copilot/scripts/macos/gateway.sh test` | `01:47 +4138 ~1: All tests passed!` — the brief's baseline `+4133 ~1` + this phase's 5 Dart cases; the 1 skip is pre-existing |
| Full Swift suite, once | `.github/copilot/scripts/macos/gateway.sh swift-test` | `Executed 353 tests, with 0 failures (0 unexpected)` — baseline 349 + this phase's 4 Swift cases |
| Analyzer | `.github/copilot/scripts/macos/gateway.sh lint` | `196 issues found. (ran in 2.8s)`, 0 errors — the baseline exactly; no issue names `watch_rest_screen.dart`, `watch_logging_state.dart` or `watch_rest_surface_test.dart` |
| Repository invariant | `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` | no matches — no state or UI file imports a concrete store |
| Dart debug harness (item 5) | — | **not wired**: `lib/watch/debug/watch_logging_debug_main.dart` renders `WatchLoggingScreen` directly and has no surface switch to extend (only a slot picker), so the brief's "only if there is an obvious place" is not met; the Swift shell is the runtime (Assumption Log) |

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
| S-161/S-162/S-163 | Phase 2 — `prove-red` is **not applicable**: `isResting`, `endRest()`, `restElapsedSeconds()` and `watch_rest_screen.dart` do not exist at `3cab789`, so the test file cannot compile there and a prove-red over them would have to delete an untracked new file. Proved by mutation instead (A–D below), as the brief directs | n/a | n/a |
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

### Phase 2 mutations (the members are new, so the tests cannot run at the base)

Mutation A — `isResting` ignores the stopped state, both stacks:

- Original (Swift): `return rest.state != WatchTimerState.stopped` → mutant `return true`
- Original (Dart): `rest.state != WatchTimerState.stopped;` → mutant `true;`
- `gateway.sh test test/watch_rest_surface_test.dart` → `00:00 +1 -1: … S-162 Next ends the rest at the tap instant [E]`
  `Expected: false Actual: <true>` at `test/watch_rest_surface_test.dart:99`; the widget case also
  fails (`Found 1 widget with text "0:07"` becomes the still-counting `0:08`), `+2 -3: Some tests failed.`
- `gateway.sh swift-test --filter WatchRestSurfaceTests` → `Executed 4 tests, with 2 failures`:
  `testS162NextEndsTheRestAtTheTapInstant` (`XCTAssertFalse failed` + `XCTAssertNil failed`), the
  `0:07`/`0:08` widget case is Swift-side n/a
- Both restored exactly; Dart `All tests passed!` (5 cases), Swift `Executed 4 tests, with 0 failures`

Mutation B — drop `if isResting { await endRest() }` from `log()`, both stacks:

- Original lines: `if isResting { await endRest() }` + blank line before `let stored = try await engine.appendObservation(event)`
  (Dart: `if (isResting) await endRest();` before `final stored = await _engine.appendObservation(event);`)
- `gateway.sh test test/watch_rest_surface_test.dart` → `00:00 +2 -1: … S-163 logging ends a running rest first [E]`
  `Bad state: No element` at `:125` — rest #2 was never stopped, so no stopped row for it exists
- `gateway.sh swift-test --filter WatchRestSurfaceTests` → `Executed 4 tests, with 2 failures`:
  `testS163LoggingEndsARunningRestFirst` at `WatchRestSurfaceTests.swift:114-115`
  (`XCTAssertEqual failed: threw error "UnwrappingOptional(errorCode: 105 …)"`)
- Both restored exactly; Dart `All tests passed!`, Swift `Executed 4 tests, with 0 failures`

Mutation C — `restElapsedSeconds()` counts down (`planned - elapsed`), both stacks:

- Original (Swift): `return activeElapsedMs(rest, now: clock()) / 1000` → mutant
  `return (rest.plannedDurationMs ?? 90_000) / 1000 - activeElapsedMs(rest, now: clock()) / 1000`
- Original (Dart): `return activeElapsedMs(rest, _clock()) ~/ 1000;` → the same mutant shape
- `gateway.sh test test/watch_rest_surface_test.dart` → `00:00 +2 -3: Some tests failed.`:
  `S-161 … [E]` `Expected: <0> Actual: <90>` at `:69`, `S-162 … [E]` `Expected: <30> Actual: <60>` at
  `:95`, and the widget case `Found 0 widgets with text "0:00"` at `:169`
- `gateway.sh swift-test --filter WatchRestSurfaceTests` → `Executed 4 tests, with 4 failures`:
  S-161 `("Optional(90)") is not equal to ("Optional(0)")` at `:45`, `("Optional(83)")` vs
  `("Optional(7)")` at `:48`, `("Optional(-150)")` vs `("Optional(240)")` at `:61`; S-162
  `("Optional(60)") is not equal to ("Optional(30)")` at `:77`
- Both restored exactly; Dart `All tests passed!`, Swift `Executed 4 tests, with 0 failures`

Mutation D — the `ContentView` branch order is **not testable by `swift-test`**: the app target is
outside the package, so no package test can reach `body`'s branch chain. Stated, not proved; the
governor's `xcodebuild` watchOS-simulator build is the check, and the branch's position (second, after
`isPromptOwed`) is the claim it must confirm.


## Swift-side evidence

| Scenario | Command | Result |
|---|---|---|
| Scenario | Command | Result |
|---|---|---|
| S-160/S-161/S-164 | `.github/copilot/scripts/macos/gateway.sh swift-test --filter WatchLoggingTimersTests`; full `.github/copilot/scripts/macos/gateway.sh swift-test` | `Executed 26 tests, with 0 failures` for the case; `Executed 349 tests, with 0 failures` for the package. S-161's "0:00 at the log instant / 0:07 later / 4:00 after a relaunch mid-rest" splits across Phase 1 (`testS161ARestSurvivesTheScreenTurningOff`) and Phase 2's rest surface |
| S-162/S-163 | `.github/copilot/scripts/macos/gateway.sh swift-test --filter WatchRestSurfaceTests` | `Executed 4 tests, with 0 failures (0 unexpected) in 0.009 (0.009) seconds` — S-161 (0:00 at the log instant, 0:07 seven seconds later on the injected clock, 4:00 after rebuilding the engine over the same store mid-rest), S-162 (`stoppedAt` is the tap instant, `isResting` false after), S-163 (the log's instant stops the running rest and a new rest starts, 3 rests / 3 entries), plus the finished-session guard |
| `ContentView` branch (S-161/S-162) | governor's watchOS simulator build — agents must not claim it | not run by this agent (`swift-test` does not compile the app target); the branch chain and its position are in the Phase 2 table above |
| S-165 | `.github/copilot/scripts/macos/gateway.sh swift-test` | pending |
| `ContentView` branch (S-161/S-162) | governor's watchOS simulator build — agents must not claim it | pending |

## Reviewer findings

[empty — the reviewer fills this: diff versus Predicted Files, per-S-x conformance, the Impact Check
rows re-run, cross-stack agreement (Swift package vs Dart twin), quantified defects, Assumption Log
adjudication.]
