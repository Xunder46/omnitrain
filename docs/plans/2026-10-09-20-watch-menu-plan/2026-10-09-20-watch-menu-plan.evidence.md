# Plan 20 — the watch menu: evidence

Companion to `2026-10-09-20-watch-menu-plan.md`. Implementers append to the tables below; the Code Reviewer reads
them against the plan's Predicted Files and Done Criteria. Results are pasted counts and verdicts, never a claim of
success.

## Baselines

From `docs/plans/2026-10-08-18-watch-qa-index.md:8-10` (every PR in the series compares against these):

| Check | Command | Baseline |
|---|---|---|
| Flutter suite | `.github/copilot/scripts/macos/gateway.sh test` | 4061 tests / ~1 pre-existing failure |
| Flutter analysis | `.github/copilot/scripts/macos/gateway.sh lint` | 196 issues / 0 errors |
| Watch package | `.github/copilot/scripts/macos/gateway.sh swift-test` | 335 tests / 0 failures |

Phase 2's checks: `.github/copilot/scripts/macos/gateway.sh test test/docs_indexing_contract_test.dart` (green), and the
governor-only watch-scheme `xcodebuild` for the `OmniTrain Watch App` target.

## Phase 1 — the menu model and the add-only picker (@developer)

| Check | Command | Expectation | Result |
|---|---|---|---|
| Package suite | `.github/copilot/scripts/macos/gateway.sh swift-test` | all green, count ≥ 335 + the new tests | ✅ `Executed 403 tests, with 0 failures (0 unexpected)` — 14 of them `WatchMenuTests`; run twice (`15:22`, `15:23`), both green |
| Red on base | `.github/copilot/scripts/macos/gateway.sh prove-red HEAD swift-test -- watch/watchos/Tests/WatchSessionEngineTests/WatchMenuTests.swift` | FAIL on HEAD (`WatchMenu.swift` absent → the test target does not compile) | ✅ `prove-red: RED AT HEAD (exit 1)` — a compile error (`cannot find type 'WatchMenuState'`, `cannot find 'deriveMenuRows'`, `cannot call value of non-function type '[WatchExercisePickerRow]'`), so the gateway's own caveat applies: per-guard proof is the mutation table below |
| Existing picker assertions untouched | `gateway.sh git-diff --name-only` | `WatchConnectivityBridgeTests.swift` absent (S-1105, D-1104) | ✅ absent; the list is `WatchStartPaths.swift`, `WatchStartView.swift`, and the pre-existing `docs/plans/2026-10-08-18-watch-qa-index.md` |
| Diff in bounds | `gateway.sh git-diff --name-only` | exactly the Predicted Files | ✅ the two edited files plus the untracked new ones (`WatchMenu.swift`, `WatchMenuTests.swift`), which `git diff` does not list until staged |
| Analysis | `.github/copilot/scripts/macos/gateway.sh lint` | no worse than baseline (196 / 0 errors) | ✅ `196 issues found`, 0 errors — the baseline exactly; no new file appears in the output |

Red → green per scenario (red first, on the unmodified tree, then green):

| S-id | Test | Red how | Green |
|---|---|---|---|
| S-1100 | `testS1100MenuRowsCarryNameCountAndCurrent` | `deriveMenuRows` does not exist | ✅ green (❋ red on the count when the counts came from `engine.observations`) |
| S-1101 | `testS1101EmptyLadderAndNamelessSlot` | same | ✅ green |
| S-1102 | `testS1102OutOfRangeIndexMarksTheLastRow` | same | ✅ green (❋ red `[false, false, false]` ≠ `[false, false, true]` with the clamp removed) |
| S-1103 | `testS1103JumpMovesTheSessionAndLogsNothing` | no jump API | ✅ green |
| S-1104 | `testS1104JumpToAVanishedSlotChangesNothing` | no jump API | ✅ green |
| S-1105 | `testS1105AddOnlyRowsDropTheLadder` | no `addOnly` | ✅ green (❋ red `["Squat", "Bench Press", "Row", "Pull-up", "Dip"]` ≠ `["Pull-up", …]` with the in-session rows kept) |
| S-1106 | `testS1106PickingAnAddOnlyRowAppendsAndMoves` | no add-only path through the menu | ✅ green |
| S-1107 | `testS1107FinishEndsAndOwesTheRating` | no `finish()` | ✅ green |
| S-1108 | `testS1108TheMenuSourceNamesNoRestEditOrDelete` | the scanned file is absent → the guard cannot be armed | ✅ green (❋ red with `deleteEntry` planted in `WatchMenu.swift`) |
| S-1109 | `testS1109MenuCountsReadTheCorrectedProjection` | `deriveMenuRows` does not exist | ✅ green (❋ red `[3, 0, 1]` ≠ `[1, 0, 2]` on the raw `engine.observations`) |
| S-1110 | `testS1110ARestIsNotACountedEffort` | same | ✅ green (❋ red `[3, 0, 1]` ≠ `[2, 0, 1]` when every entry kind counts) |
| S-1111 | `testS1111ASkippedSlotDoesNotShiftTheMark` | same | ✅ green (❋ red `[false, false]` ≠ `[false, true]` on the derived position) |
| S-1112 | `testS1112MenuRowsAreDerivedOnEveryRead` | same | ✅ green (❋ red `0` ≠ `3` rows with `rows` cached at init) |
| S-1113 | `testS1113FinishLeavesNothingToLogInto` | no `finish()` | ✅ green |

Green = the named test passes in `WatchMenuTests`'s `Executed 14 tests, with 0 failures` run. ❋ marks a row whose guard
also went red at **assertion** level in the mutation runs above; the unmarked rows went red at HEAD as compile errors
only (their types do not exist there), which is the file's Phase-0 red. All guards were restored before the green run
(`Executed 14 tests, with 0 failures` again at `15:24:09`).

Mutation verdicts (the Code Reviewer's re-run of the plan's stated mutations — flip the source, the named scenario
must go red, then restore):

| Mutation | Scenario that must fail | Verdict |
|---|---|---|
| count every entry kind instead of `WatchObservationKind.efforts` | S-1110 | ✅ red: `("[3, 0, 1]") is not equal to ("[2, 0, 1]")` at `WatchMenuTests.swift:290`; restored, green |
| mark the row's position in the derived array instead of the ladder index | S-1111 | ✅ red: `("[false, false]") is not equal to ("[false, true]")` at `:309` (compared `rows.count == current`); restored, green |
| cache `rows` at init | S-1112 | ✅ red: `("0") is not equal to ("3")` at `:320`, cascade to 12 of 14 (the harness reads rows before the session exists); restored, green |
| add `deleteEntry` to `WatchMenu.swift` | S-1108 | ✅ red: `XCTAssertFalse failed - S-1108 the menu source must not name deleteEntry` at `:515`; restored, green |
| derive counts from `engine.observations` instead of `engine.entries` | S-1109 | ✅ red: `("[3, 0, 1]") is not equal to ("[1, 0, 2]")` at `:352`; S-1100 and S-1110 red too, both correctly — the raw projection still carries the deleted entry; restored, green |
| drop the clamp on `currentIndex` (implementer addition, S-1102) | S-1102 | ✅ red: `("[false, false, false]") is not equal to ("[false, false, true]")` at `:272`; restored, green |
| keep the `.inSession` rows in `addOnly` (implementer addition, S-1105) | S-1105 | ✅ red: `("["Squat", "Bench Press", "Row", "Pull-up", "Dip"]") is not equal to ("["Pull-up", …` at `:409` and the `allSatisfy` at `:414`; restored, green |

Every mutation was reverted to the exact original line and confirmed green (`Executed 14 tests, with 0 failures`) before
the next one; the final state is the green run above. No mutation is left applied.

## Phase 2 — the wrist surfaces and the docs (@developer)

| Check | Command | Expectation | Result |
|---|---|---|---|
| Package suite | `.github/copilot/scripts/macos/gateway.sh swift-test` | green (view files are `#if os(watchOS)`-gated, so they are not compiled here) | |
| Docs contract | `.github/copilot/scripts/macos/gateway.sh test test/docs_indexing_contract_test.dart` | green | |
| Diff in bounds | `gateway.sh git-diff --name-only` | exactly the Predicted Files | |
| Watch scheme build | `xcodebuild` (watchOS simulator, `OmniTrain Watch App`) | **governor only** — no agent run may claim it | not run by any agent |

Prose checks the reviewer makes by hand (no command covers them):

- `grep -rn WatchEndSessionView` leaves no source hit (D-1105); `docs/watch_session_capture.md:229` no longer names it.
- `docs/state_management/watch_surface.md` shrank (the stale narration is gone with D-1105's sentence change) and does
  not approach the 64 KiB per-file ceiling.
- `docs/watch-app-setup-and-qa.md` says the menu, not "End and the exercise picker".
