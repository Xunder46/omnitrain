# Evidence — 2026-10-06-15e watch-session-sync PR 4a, Phase 1 (the file store)

Every number below is observed output from a gateway check, not inference.

## Baselines

| Check | Baseline | After Phase 1 |
|---|---|---|
| `.github/copilot/scripts/macos/gateway.sh swift-test` | 275 passing / 0 failing | **284 passing / 0 failing** (9 new cases in `WatchFileStoreTests`) |
| `.github/copilot/scripts/macos/gateway.sh lint` | 196 issues / 0 errors | **196 issues / 0 errors** (unchanged; no Dart file touched) |

`lint` exits non-zero on the repo's pre-existing info notices; the count is identical to the baseline
and none of the notices names a file this phase touched.

## Footprint

`.github/copilot/scripts/macos/gateway.sh git-status`:

```
?? watch/watchos/Sources/WatchSessionEngine/FileWatchSessionStore.swift
?? watch/watchos/Tests/WatchSessionEngineTests/WatchFileStoreTests.swift
```

Two new files, both named in the plan's Predicted Files. No existing file is modified — no Dart file,
no shell file, no doc, no existing Swift source, and no test file.

## S-004 (unchanged test, extended reach)

`testS004NoMutatingOperationExistsAnywhereInTheModule` passed in the green run
(`.work/gateway/swift-test-20261006-123850-70556.log`). It walks `Sources/WatchSessionEngine` itself,
so it picked up the new `FileWatchSessionStore.swift` with no edit to the test: the file's only
exposed members are `append`, `readAll`, `pruneConfirmed`, `pruneSensorSamples`, and no method name at
member indentation matches the mutating-verb pattern.

## New cases

| Test | Scenario |
|---|---|
| `testS49ATornLastRecordCostsThatRecordOnly` | S-49 |
| `testS50AFirstLaunchOnAnEmptyStoreWritesOneMarker` | S-50 |
| `testS51TwoRelaunchesKeepEveryRowAndItsSequence` | S-51 |
| `testS53AVersionThisBinaryDoesNotKnowIsNeverDamaged` | S-53 |
| `testS54TheTwoStoresAgreeOnOneSequence` | S-54 |
| `testS44ALoggedSetSurvivesTheProcess` | S-44 |
| `testS45ExactlyOneDeliveryAfterARelaunch` | S-45 |
| `testS46ACountdownThatWasRunningIsStillRight` | S-46 |
| `testS47TheOwedRatingQuestionSurvivesTheKill` | S-47 |

## Red → green (mutation checks)

Each mutation was applied to the exact line named, the file-store suite was run
(`swift-test --filter WatchFileStoreTests`), the EXACT original line was restored, and the suite was
re-run green. No step ends with a mutation applied.

| # | Original line | Mutation | Observed red |
|---|---|---|---|
| a | `timers: timers,` in `readAllLocked` | `timers: [],` | **3 failures** — S-44 (`S-44 the rest timer survived with its startedAt`), S-46 (`XCTUnwrap failed: expected non-nil value of type "WatchTimerRecord"`), S-54 (family parity) |
| b | `where row.recordId == record.recordId && row.recordType == record.recordType` in `appendLocked` | `where false && …` | **1 test, 2 failures** — S-51 (`("6") is not equal to ("3")`, `("7") is not equal to ("6")`) |
| c | `if let record = parseLine(line) { loaded.append(record) }` in `loadRows` | `guard let record = parseLine(line) else { loaded = []; break }` | **1 test, 2 failures** — S-49 (`("[]") is not equal to ("["s-1", "s-2"]")` and `("[]") is not equal to ("["s-1", "s-2", "s-4"]")`) |
| d | `guard !unsupported else { return record }` in `appendLocked` | removed | **1 test, 3 failures** — S-53 (returned record differs, `("1") is not equal to ("0")`, `("565 bytes") is not equal to ("306 bytes")`) |
| e | `(rows?.map(\.sequence).max() ?? 0) + 1` in `nextSequence` | `1` | **3 tests, 4 failures** — S-51 (`("[1, 1, 1, 1, 1]") is not equal to ("[1, 2, 3, 4, 5]")`, `("1") is not equal to ("3")`), S-44 (ladder position), S-54 (parity) |
| f | `(rows?.map(\.sequence).max() ?? 0) + 1` in `nextSequence` | `(rows?.count ?? 0) + 1` | **1 failure** — S-51 (`("9") is not equal to ("10")`): the count-based sequence collides with a row a prune left behind |

Mutation (f) is beyond the brief's list; it was added after (e) showed the brief's five mutations do
not distinguish "one more than the highest stored row" from "one more than the row count". S-51 gained
the prune-then-append stage that tells them apart (see the Assumption Log).

## First red run (before the store existed)

The test file was written first and run against the incomplete store. The first `swift-test` run
compiled and reported:

```
Executed 284 tests, with 1 failure (0 unexpected) in 1.118 (1.137) seconds
testS49ATornLastRecordCostsThatRecordOnly : XCTAssertEqual failed: ("["s-1", "s-2"]") is not equal to ("["s-1", "s-2", "s-4"]")
```

That failure was a real defect the test caught: a torn tail has no trailing newline, so the next
append was glued onto the torn fragment. The fix writes a line boundary first (`tornTail` in
`FileWatchSessionStore`), and the case is red under mutation (c) and green after it.

## Invariant

`grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` returns
nothing. No Dart file was touched in this phase, so the invariant is unchanged — confirmed by reading
the four trees with the file-search tool.

## Not run

- `gateway.sh build` / `codegen` / `pub-get` / `format`: not implicated — no Dart file, no dependency
  manifest, and no new Dart file to format.

## Full Flutter suite (standing rule)

`.github/copilot/scripts/macos/gateway.sh test` — run even though no Dart file changed, because the
standing rules require it before finishing:

```
01:33 +3945 ~1: All tests passed!
```

3945 passing, 1 skipped, 0 failing, exit 0. Identical to what a Dart change would have to preserve:
this phase cannot move a Dart test.
