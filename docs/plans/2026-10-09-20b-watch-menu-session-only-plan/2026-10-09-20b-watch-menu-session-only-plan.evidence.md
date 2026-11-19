# Plan 20b — evidence

Base: HEAD `6051e9d` (`.work/watch-20b/base.txt`), working tree clean but for this plan folder, so `prove-red HEAD` is
exactly the pre-change code. Every command below is `.github/copilot/scripts/macos/gateway.sh <check>`.

## Phase 0 — tests first

Register: S-1200…S-1203, each naming its fixture (Fixture A = 3 slots, Squat carrying 2 logged efforts; fallback catalog
{Squat, Pull-up, Dip}; 3 further efforts on Row for S-1201). S-1202 and S-1203 are source/contract guards, S-1200/S-1201
are negative guards the register itself marks as green at base — proved by mutation below.

`prove-red HEAD swift-test --filter WatchMenuTests -- watch/watchos/Tests/WatchSessionEngineTests/WatchMenuTests.swift`:

```
.../WatchMenuTests.swift:527: error: ... testS1202TheMenuSourceNamesNoExercisePicker : XCTAssertFalse failed - S-1202 WatchMenu.swift must not name pickerRo ...
.../WatchMenuTests.swift:527: error: ... testS1202TheMenuSourceNamesNoExercisePicker : XCTAssertFalse failed - S-1202 WatchMenuView.swift must not name Watc ...
.../WatchMenuTests.swift:527: error: ... testS1202TheMenuSourceNamesNoExercisePicker : XCTAssertFalse failed - S-1202 WatchMenuView.swift must not name addE ...
.../WatchMenuTests.swift:527: error: ... testS1202TheMenuSourceNamesNoExercisePicker : XCTAssertFalse failed - S-1202 WatchMenuView.swift must not name Add  ...
	 Executed 15 tests, with 4 failures (0 unexpected) in 0.117 (0.118) seconds
gateway: prove-red: RED AT HEAD (exit 1). It proves the guard only if an assertion fails for the reason the test guards; a compile or load error means the test could not run there (use a mutation instead).
```

All four failures are the S-1202 assertions, each naming the token the change removes — not a compile or load error. The
test file compiles at base because `pickerRows(addOnly:)` still exists there.

## Phase 1 — implementation

| Item | Result |
|---|---|
| 1 `WatchMenuView.swift`, `WatchMenu.swift` (D-1200) | `addExerciseLabel`, `addingExercise`, the `.sheet` and `addExerciseRow` deleted; body is rows + `finishRow`; `paths` is now `private`; `jump(to:)` reads the slot off `engine.session.exercises` via a new file-private `menuSlotId(of:_:)` and calls `paths.selectExercise(.inSession(slotId:exercise:))` — red at HEAD was the only reader of `pickerRows` |
| 2 `WatchStartView.swift`, `WatchStartPaths.swift` (D-1201) | `WatchExercisePickerView.addOnly` and its doc paragraph deleted; `derivePickerRows` lost its `addOnly` parameter and the `if !addOnly` wrapper; `pickerRows(addOnly:)` deleted and the `pickerRows` property body inlined — the start screen's rows are byte-for-byte what they were (`pickerRows(addOnly: false)` == `derivePickerRows(sessionExercises:fallback:)`) |
| 3 `WatchMenuTests.swift` | S-1105/S-1106 deleted (D-1202), S-1200/S-1201/S-1202 added; file now runs 15 tests |
| 4 `ContentView.swift` comment | now "…to jump to, then Finish (D-25, D-1100, D-1200). Exercises are added on the phone."; the two `WatchMenuView(...)` call arguments are unchanged |
| 5 Docs | `docs/state_management/watch_surface.md` second-surface clause, `docs/watch-app-setup-and-qa.md` surface line, QA index row 20 note (D-1204) |
| 6 Evidence | this file |

## Mutation proofs (S-1200, S-1201 — negative guards)

| Scenario | Mutation (original line recorded) | Observed |
|---|---|---|
| S-1200 | `WatchMenuState.rows` appended the start paths' available catalog: `var rows = deriveMenuRows(...)` then `rows += paths.fallbackExercises.filter { !rows.contains { $0.name == $1.name } }.map { ... }` (original: a bare `deriveMenuRows(...)` expression) | ✅ red: `WatchMenuTests.swift:412: XCTAssertEqual failed: ("["Squat", "Bench Press", "Row", "Pull-up", "Dip"]") is not equal to ("["Squat", "Bench Press", "Row"]") - S-1200 the fallback catalog's Pull-up and Dip stay out of the menu`; S-1202 went red too (`WatchMenu.swift must not name fallbackExercises`). Restored exactly, green |
| S-1201 | `deriveMenuRows` emitted one row per logged effort: the single `rows.append(WatchMenuRow(slotId: slotId, ...))` followed by `for _ in 1..<max(count, 1) { rows.append(WatchMenuRow(slotId: slotId, ...)) }` (original: the single append) | ✅ red: `WatchMenuTests.swift:428: ("7") is not equal to ("3") - S-1201 four efforts on Row still make one row` and `:429: ("3") is not equal to ("7") - S-1201 no slot id repeats, so no effort gets a row of its own`. Restored exactly, green |

Both mutations were reverted before the suites below; the `restored` runs are the `WatchMenuTests` entry in the next section.

## Suites

| Run | Result |
|---|---|
| `swift-test --filter WatchMenuTests` (after restore) | **Executed 15 tests, with 0 failures (0 unexpected) in 0.028 (0.029) seconds** — exit 0 |
| `swift-test` (full watch package) | **Executed 404 tests, with 0 failures (0 unexpected) in 1.398 (1.425) seconds** — exit 0 (log `.work/gateway/swift-test-20261009-164815-24191.log`) |
| `test test/docs_indexing_contract_test.dart` | **9/9 passed** (`00:00 +9: All tests passed!`) — the size, link, hex and prose guards all hold after the doc edit |
| `test` (full Flutter suite) | **`01:50 +4226 ~1: All tests passed!`** — 4226 passed, 1 skipped, 0 failures, exit 0 (log `.work/gateway/test-20261009-164840-24563.log`) |
| `lint` | **196 issues found** = the plan's baseline, all pre-existing `info` notices, none in a file this run touched |

`git-diff --name-only`: the nine predicted files only — `WatchConnectivityBridgeTests.swift` (S-1203, the start picker's
untouched `pickerRows` assertions at `:690`, `:762`, `:803`) is **not** in the diff. Diff stat 96 insertions / 123
deletions; `docs/state_management/watch_surface.md` was 8 replaced lines for 8, net 4 bytes shorter, so it does not grow.

## Tests removed (D-1202)

- `WatchMenuTests.testS1105AddOnlyRowsDropTheLadder` — asserted `paths.pickerRows(addOnly: true)` drops the ladder's rows.
- `WatchMenuTests.testS1106PickingAnAddOnlyRowAppendsAndMoves` — asserted a pick in add-only mode appends a slot and moves
  the session.

Both covered behaviour plan 20 asked for and 20b removes on purpose: the add-only mode no longer exists, so keeping them
would leave tests calling a deleted API. Everything else in the file is unchanged. S-1100…S-1113 minus those two, plus
S-1200…S-1202, is the 15 tests above.
