# Evidence — plan 31, Phase 1 (the rest screen's menu + the menu's extra gap)

Developer, 2026-10-13. Base commit `0da2a72669a443ca400e5d42761635f14bf78216` (`.work/2026-10-13-31/base.txt`).
Items 5 and 2: D-3101 (`WatchMenuView.body`), D-3102/D-3114 (`ContentView.swift`), D-3109's executable
reading (S-3102's second half). Scenarios S-3101, S-3102, S-3103, S-3104, S-3111.

All commands are `.github/copilot/scripts/macos/gateway.sh <check>`. No test file, no fixture and no
scratch file was created: the fixtures are inline, and every value of interest is printed by an assertion.

## Phase 0 — the tests, red before the change

Written first, in `watch/watchos/Tests/WatchSessionEngineTests/WatchMenuTests.swift`: one `// Plan:` header
block citing this plan, five file-private scan helpers (`menuSource`, `sourceLines`, `usageLine`,
`nextLine`, `occurrences`) and the five tests under the MARK `S-3101…S-3104, S-3111 the rest screen's menu`.
`menuSource` is `WatchSensorSourceSourceTests.source(_:)`'s shape — comment lines stripped, path resolved
through `Fixtures.repositoryRoot`, so the app target's file is read as text (hosting these two scans in
`WatchMenuTests.swift` is the plan's own option, plan `:588-592`).

### The red run (tests written, no implementation yet)

`swift-test --filter WatchMenuTests/testS31`

```
Executed 5 tests, with 4 failures
```

The two red scenarios and the exact assertions that failed:

| Scenario | Assertion that failed (line in `WatchMenuTests.swift` as written) |
|---|---|
| S-3104 | `:953` "S-3104 the extra gap sits between the divider and Add Exercise" — at base `.padding(.top, 10)` is on `finishRow` |
| S-3104 | `:957` "S-3104 End Session sits at the normal row spacing" — at base `finishRow` carries it |
| S-3103 | `:982` "S-3103 the rest branch is a navigation surface of its own" — at base the rest branch is a bare `WatchRestView` |
| S-3103 | `:986` "S-3103 the rest screen carries the list button the logging surface has" |

S-3101, S-3102 and S-3111 passed at that point: they are guards for existing behaviour (D-3103, D-3109),
so red-at-base is not available for them; each is proven by a mutation below instead. S-3111's first
draft *was* red — it asserted two rows and `rests.first.stoppedAt != nil`, which is the shape
`WatchLoggingTimersTests.testS321` disproves (a stop is its own row, so a closed rest is two rows). The
assertions were rewritten to the two-row shape before anything was implemented; the final file has not
changed since.

### prove-red at the base commit (the red artifact for both scans)

```
gateway: prove-red: RED AT 0da2a72669a443ca400e5d42761635f14bf78216 (exit 1)
```

`prove-red 0da2a72669a443ca400e5d42761635f14bf78216 swift-test --filter WatchMenuTests/testS310 -- watch/watchos/Tests/WatchSessionEngineTests/WatchMenuTests.swift`
runs the new test file against the base sources: S-3104's two assertions and S-3103's two assertions fail
for exactly the reason each guards (no padding on `addExerciseRow`; no `NavigationStack` and no
`list.bullet` button in the rest branch). S-3101/S-3102/S-3111 pass there, as expected of guards.

## Mutation proofs (the three guards)

Each mutation was applied to the original line, the test run, the EXACT original restored, the file
checked clean with `git-diff --stat -- <path>` (empty output) and the test re-run green. No mutation is
left applied.

| Scenario | Mutation | Observed red |
|---|---|---|
| S-3101 | `WatchMenu.swift`, `WatchMenuState.jump`: one added line `_ = await engine.stopTimer(kind: WatchTimerKind.rest)` before the select | `Executed 1 test, with 4 failures` — `:1020` "the rest is not over: a jump is not a log and not a Next", `:1022` "the same rest, not a second one" (rec-2 vs rec-1), `:1024` `stoppedAt` not nil, `:1027` restElapsedSeconds `nil` vs `Optional(20)` |
| S-3102 | `WatchStartPaths.swift`, `WatchStartPaths.addExerciseToEnd`: the same one added line | `Executed 1 test, with 2 failures` — `:1061`, `:1062` (the rest is gone / not the same record) |
| S-3111 | `WatchLoggingState.swift`, `WatchLoggingState.log`: `await startFollowOnTimer()` replaced by `_ = startFollowOnTimer` | `Executed 1 test, with 2 failures` — `:1093` "the log closes the rest it was logged into, and closes only that one" (`0` vs `1` stopped rows), `:1098` the newest rest is nil |

Restores verified: `git-diff --stat -- watch/watchos/Sources/WatchSessionEngine/WatchMenu.swift`,
`… WatchStartPaths.swift` and `… WatchLoggingState.swift` each produced no output.

## S-3111's expected values, taken from `WatchLoggingTimersTests.testS321`

`testS321TheRestTheNextSetEndsTravelsBeforeIt` is where the plan sent item 5 for the expected shape
(`WatchLoggingTimersTests.swift:849-878`): two logs 45 s apart give `emittedKinds == ["set", "rest", "set"]`
("the rest travels before the entry that closed it"), `rests.count == 1`, the one rest observation with
`startedAt == t0`, `endedAt == t0 + 45` and `afterEntryId == first.entryId`, and the closed row's
`stoppedAt == t0 + 45` read as `timerRows(kind).first { $0.stoppedAt != nil }`.

`testS3111ALogClosesTheRunningRestAndStartsTheNext` is the same shape on the menu harness at 30 s, plus
the two things the plan's D-3109 adds: the rest that starts straight after the log is a **new** row
(`recordId` differs from the closed one), running, started at the logged instant, so `isResting` reads
true again; and the closed window's own row stops at the logged instant (`t0 + 30`), not a tick later.

## Done Criteria

### `swift-test` (whole package, run once after implementation)

```
Executed 564 tests, with 0 failures (0 unexpected) in 2.215 (2.252) seconds
Test Suite 'WatchMenuTests' passed at 2026-10-13 23:28:30.819.
	 Executed 40 tests, with 0 failures (0 unexpected) in 0.085 (0.087) seconds
```

40 = the 35 `WatchMenuTests` cases that were there before plus this phase's 5. No pre-existing test
went red: the whole package, including the `Sources/` invariant scans in `WatchSessionEngineTests`
(append-only `func` names, `restSeconds`/`plannedDurationMs`, S-3617/S-1108's forbidden tokens), is
green, and the filter `WatchMenuTests/testS31` is 5/5 green (`Executed 5 tests, with 0 failures`).
Log: `.work/gateway/swift-test-20261013-232827-97358.log`.

The app-target edit is not compiled by any agent check (`swift test` builds the package only; the watch
app needs `xcodebuild` on a watchOS simulator), so `ContentView.swift`'s two edits are held by S-3103
plus the reviewer reading the diff.

### `lint` (`flutter analyze`)

```
181 issues found. (ran in 3.6s)
```

All 181 are pre-existing `info` notices: the log carries no `error •` and no `warning •` line
(`.work/gateway/lint-20261013-232827-97359.log`). This phase changed no Dart file, so this count is the
repository's own and there is nothing in it to attribute to the phase; the plan asked for the count to be
recorded and compared with the phase's first run, and no Dart file was touched between any run in it.

### Doc contract (`test/docs_indexing_contract_test.dart`, a doc changed)

```
00:00 +13: All tests passed!
```

Run after both doc edits. `docs/state_management/watch_surface.md` gained 6 lines (D-3115 allows ~12;
the file stays under the 64 KiB ceiling and the test's warning band, since "+13" includes the
"no documentation file is within the warning band of the ceiling" case).
`docs/watch-app-setup-and-qa.md` is a record file and is not indexed, so its step-10 correction and the
new step 15 are outside that contract.

### Project invariants

`grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` — no matches.

### `test` (the whole Flutter suite, after the doc and plan edits)

```
02:38 +4476 ~1: All tests passed!
```

Run once the work was believed done, after both doc edits and after this evidence file was created
(it lives under `docs/`, so the doc contract test was re-run with it present and stayed 13/13). The
`~1` is the suite's one pre-existing skip. Log: `.work/gateway/test-20261013-233132-98580.log`.

## Files changed

| File | Change |
|---|---|
| `watch/watchos/Tests/WatchSessionEngineTests/WatchMenuTests.swift` | +256 lines: the plan citation header, the five scan helpers, the five tests (S-3103, S-3104 red; S-3101, S-3102, S-3111 guards) |
| `watch/watchos/Sources/WatchSessionEngine/WatchMenuView.swift` | one line moved: `.padding(.top, 10)` from `finishRow` to `addExerciseRow` (`git-diff --stat`: 2 lines) |
| `ios/OmniTrain Watch App/ContentView.swift` | the rest branch wrapped in a `NavigationStack` with the `list.bullet` button; one `menuSheet` helper on the root `Group`; `.onDisappear` dropped, `.onChange` on the session status and on the owed prompt instead; `loggingSurface` reduced to the logging view and its button; the `showingMenu` doc comment rewritten |
| `docs/state_management/watch_surface.md` | +6 lines: the rest screen carries the same list button and both surfaces open the one menu |
| `docs/watch-app-setup-and-qa.md` | step 10's now-false "extra space above End Session" wording corrected to "above Add Exercise"; one new **(owner)** step 15 for the rest screen's button |

Nothing was deleted, no directory was created, and no scratch file was left behind.

# Evidence — plan 31, Phase 2A (the sections function, the letters gate, the picker's order)

Developer, 2026-10-13. Same base commit `0da2a72669a443ca400e5d42761635f14bf78216`. Items 5 and 6:
D-3110 (`WatchMenu.swift`), D-3111 (`WatchStartPaths.swift`). Scenarios S-3105, S-3107, S-3108, S-3113.
Phase 1's evidence above is untouched; the two phases share the working tree, so every count below was
taken on a tree that already carried Phase 1.

## Phase 0 — the tests, red before the change

Four tests written before any implementation, two per file, each file's header gaining a `// Plan: …`
citation block:

- `WatchMenuTests.swift` — `testS3105ASectionsFollowTheListAndTheLettersAgree` (120 mixed names through
  `applyLetterCatalog`: four per letter A–Z, `" stray"`, `"-dash hold"`, `"3x3 press"`, `"Élan"`, and
  twelve lowercase `"<letter> route"` names) and `testS3108ATheLetterGridAppearsOverTwentyRows`
  (20 names → no grid, 21 → the grid, equal to the shared function's output).
- `WatchSessionStartPathsTests.swift` — `testS3107ATheFreePickerOffersTheAvailableExercisesAToZ` and
  `testS3113AThePickerRowsAndTheAvailableExercisesAgree`, plus four file-private helpers (`usedSession`,
  `listedCatalogNames`, `catalogOnlyMessage(names:)`, `assertPickerListsAgree`).

S-3105, S-3107, S-3108 and S-3113 all name API that does not exist at base (`deriveExerciseSections`,
`deriveExerciseListLetters`, `availablePickerExercises`), so they cannot compile there and red-at-base is
not available for them; each is proven by a mutation below. The base-red artifact for this phase's
behaviour is the two bridge tests whose order assertions were re-pointed (item 6) — they compile at base
and now assert A-to-Z, so they fail there.

### prove-red at the base commit (the red artifact for the picker's order)

```
gateway: prove-red: RED AT 0da2a72669a443ca400e5d42761635f14bf78216 (exit 1). It proves the guard only if an assertion fails for the reason the test guards; a compile or load error means the test could not run there (use a mutation instead).
```

`prove-red 0da2a72669a443ca400e5d42761635f14bf78216 swift-test --filter testPickerRows -- watch/watchos/Tests/WatchSessionEngineTests/WatchConnectivityBridgeTests.swift`
— both tests failed for exactly the reason each guards:

```
WatchConnectivityBridgeTests.swift:877: error: … testPickerRowsListTheSessionFirstAndNeverTwice : XCTAssertEqual failed: ("["ex-pull-up" …
WatchConnectivityBridgeTests.swift:913: error: … testPickerRowsFallBackToTheFallbackListWhileTheSessionIsEmpty : XCTAssertEqual failed:  ...
Executed 2 tests, with 2 failures (0 unexpected)
```

The offered rows at base follow the phone's fallback order (`pull-up` first after the ladder), not the
A-to-Z order the tests now read.

## Mutation proofs (the three new guards)

Each mutation was applied to the original line, the test run, the EXACT original restored, the file
checked with `git-diff --stat -- watch/watchos` (the two source files back at +84 / +23 lines) and the
affected tests re-run green (`Executed 9 tests, with 0 failures`). No mutation is left applied.

| Scenario | Mutation | Observed red |
|---|---|---|
| S-3107, S-3113 | `WatchStartPaths.swift`, `pickerRows`: `fallback: addableExercises` → `fallback: fallbackExercises` | `Executed 2 tests, with 3 failures` — S-3107 `:2258` "the available rows are A to Z, not the phone's order" (`["ex-plank", "ex-goblet-squat", …]`) and `:2285` (the list after the add), S-3113 `:2311` "(a) the rows are the available list" |
| S-3108, S-3113 | `WatchMenu.swift`, `deriveExerciseListLetters`: `count > threshold` → `count >= threshold` | `Executed 3 tests, with 4 failures` — S-3108 `:1438` "20 rows carry no grid" and `:1439` (the shared function's output), S-3113 `:2365` "(c) 20 rows carry no grid", plus the untouched `testS3902TheGridNeedsMoreThanTheThreshold` `:1218` |
| S-3105 | `WatchMenu.swift`, `deriveExerciseSections`: `addExerciseLetterKey(of: exercise.name)` → `addExerciseLetterKey(of: exercise.exerciseId)` | `Executed 1 test, with 4 failures` — `:1411` "one section per key, in the list's own order" (`["E"]` vs `["#", "A", …]`), `:1421` (each section opens at its letter's first exercise), `:1426` ("the keys that sort first open the list") and `:1427` ("the accent is its own section, last") |

## Done Criteria

### `swift-test` (whole package, run once after implementation)

```
Executed 568 tests, with 0 failures (0 unexpected) in 2.351 (2.393) seconds
```

568 = Phase 1's 564 plus this phase's 4. The per-file runs while working:
`--filter testS31` → `Executed 27 tests, with 0 failures` (`WatchMenuTests` 7/0 including S-3105 and
S-3108, `WatchSessionStartPathsTests` 2/0); `--filter testPickerRows` → `Executed 2 tests, with 0
failures`; `--filter "testS3105A|testS3107A|testS3108A|testS3113A|testS3902|testPickerRows|testS3900|testS3908"`
→ `Executed 9 tests, with 0 failures` after the last restore. The untouched S-39xx letter tests
(`testS3900`, `testS3902`, `testS3908`) are green on the shared gate: the regression guard the plan asked
for. Log: `.work/gateway/swift-test-20261013-234817-16412.log`.

No view uses the two new functions yet — `WatchExerciseListView.swift` and the picker's body are Phase 2B,
which this run deliberately did not touch (the brief excludes every `*View.swift`).

### `lint` (`flutter analyze`)

```
181 issues found. (ran in 3.7s)
```

The same 181 pre-existing `info` notices as Phase 1's run, with no `error •` and no `warning •` line
(`.work/gateway/lint-20261013-234829-16622.log`). This phase changed no Dart file, so nothing in the
count is attributable to it.

### Doc contract (`test/docs_indexing_contract_test.dart`, two docs changed)

```
00:00 +13: All tests passed!
```

`docs/state_management/watch_reference_data.md` gained 14 lines (15 changed: the picker's list, the
sections identity and the one gate, each sentence citing the test that verifies it);
`docs/state_management/watch_surface.md`'s picker-order sentence is 5 insertions / 2 deletions — within
the plan's ≤6 added lines, and the file stays under the 64 KiB ceiling and its warning band.

### Project invariants

`grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` — no matches
(read with the file tools; this phase touched no Dart file).

### `test` (the whole Flutter suite)

```
02:40 +4476 ~1: All tests passed!
```

The same 4476 passed / 1 pre-existing skip as Phase 1's run, on a tree carrying both phases.
Log: `.work/gateway/test-20261013-234837-16810.log`.

## Files changed

| File | Change |
|---|---|
| `watch/watchos/Sources/WatchSessionEngine/WatchMenu.swift` | +84 lines: `WatchExerciseSection`, `deriveExerciseSections`, `deriveExerciseListLetters` after `deriveAddExerciseLetters`; `WatchMenuState.addExerciseLetters` rewired to the shared gate; `WatchMenuState.addExerciseSections` |
| `watch/watchos/Sources/WatchSessionEngine/WatchStartPaths.swift` | +23 lines: `pickerRows` passes `fallback: addableExercises`; `availablePickerExercises` added beside it (`derivePickerRows` untouched) |
| `watch/watchos/Tests/WatchSessionEngineTests/WatchMenuTests.swift` | +80 of the file's +336 lines (Phase 1 owns the rest): the Phase 2A citation block and S-3105/S-3108 |
| `watch/watchos/Tests/WatchSessionEngineTests/WatchSessionStartPathsTests.swift` | +242 lines: the citation block, the four helpers and S-3107/S-3113 |
| `watch/watchos/Tests/WatchSessionEngineTests/WatchConnectivityBridgeTests.swift` | +13 lines: the citation block, the two order assertions re-pointed to `addableExercises` and the "A to Z (D-3111)" comment |
| `docs/state_management/watch_reference_data.md` | +14 lines: the picker's list, the sections identity, the one gate |
| `docs/state_management/watch_surface.md` | 5 insertions / 2 deletions: the picker's available rows are the menu's A-to-Z list |

Nothing was deleted, no directory was created, no scratch file was left behind, and every file this
phase touched is in the plan's Predicted Files.

# Evidence — plan 31, Phase 2B (the one shared watchOS list)

Developer, 2026-10-13/14. Same base commit `0da2a72669a443ca400e5d42761635f14bf78216`. Items 1-5:
the new `WatchExerciseListView.swift`, D-3105/D-3106/D-3112 in `WatchMenuView.swift` and
`WatchStartView.swift`, and the two docs. Scenario S-3106. Phases 1 and 2A were already in the working
tree, so every count below was taken on a tree that carried all three.

## Phase 0 — the test, red before the change

`testS3106AOneListServesBothEntryPoints` (`WatchMenuTests.swift`, the file's header gaining a `// Plan: …`
citation block) was written first and run before any view existed:

```
swift-test-20261014-000026-30981.log
WatchMenuTests.swift:956: error: … XCTAssertTrue failed - S-3106 WatchMenuView.swift renders the shared exercise list
WatchMenuTests.swift:960: error: … XCTAssertFalse failed - S-3106 WatchMenuView.swift no longer places a row by estimate
WatchMenuTests.swift:956: error: … XCTAssertTrue failed - S-3106 WatchStartView.swift renders the shared exercise list
WatchMenuTests.swift:118: error: … caught error: … "The file “WatchExerciseListView.swift” couldn’t be opened because there is no such file."
Executed 1 test, with 4 failures (1 unexpected)
```

Every failure is the behaviour the scenario asserts being absent, not a configuration error: neither entry
point named the component, the menu still held its `LazyVStack`, and the shared file did not exist yet.
(`WatchStartView.swift`'s own "no longer places a row by estimate" assertion reported nothing because that
file never had a `LazyVStack` to begin with.)

## Why the guard is proven by mutation, not `prove-red`

`prove-red` carries the named test file into a worktree of the base commit, and the carried
`WatchMenuTests.swift` is the Phase 1/2A one: it names `deriveExerciseSections`,
`deriveExerciseListLetters` and the letter tests' helpers, none of which exist at `0da2a72`, so the
worktree cannot compile — the gateway's own note for that case says to use a mutation instead. The
mutation below is therefore this phase's red artifact.

## Mutation proof

The original region (`WatchExerciseListView.swift`, `list(_:)`):

```swift
        List {
            if !letters.isEmpty {
```

Mutated by adding a comment-free lazy stack as the `List`'s first row:

```swift
        List {
            LazyVStack { EmptyView() }
            if !letters.isEmpty {
```

```
swift-test-20261014-000156-32660.log
WatchMenuTests.swift:971: error: … testS3106AOneListServesBothEntryPoints : XCTAssertFalse failed - S-3106 the shared list places no row by estimate
Executed 1 test, with 1 failure (0 unexpected)
```

The mutation reddens the assertion the scenario names (the shared file placing a row by estimate) and
nothing else. The EXACT original was then restored — the two lines are byte-for-byte the ones the file was
created with, checked by re-reading the region — and the same test re-run:

```
swift-test-20261014-000201-32846.log
Test Case '-[… testS3106AOneListServesBothEntryPoints]' passed (0.003 seconds).
Executed 1 test, with 0 failures (0 unexpected)
```

No mutation is left applied: the restored file compiles again in that very run, and the whole-package run
below is green.

## Suites

| Check | Result |
|---|---|
| `swift-test --filter testS3106A` (after the view) | 2 tests / 0 failures — S-3106 plus the untouched `testS3106ARelaunchOntoARestoredActiveSessionStartsSensors` |
| `swift-test --filter "WatchMenuTests\|WatchSessionStartPathsTests"` | 105 tests / 0 failures — `WatchMenuTests` 43, `WatchSessionStartPathsTests` 62 (`swift-test-20261014-000205-32914.log`) |
| `swift-test` (whole package) | **569 tests / 0 failures** — Phase 2A's 568 plus this phase's one (`swift-test-20261014-000326-34103.log`) |
| `test test/docs_indexing_contract_test.dart test/ui_standards_contract_test.dart` | **42 tests / 0 failures** |
| `lint` | 184 issues, **2 of them errors**, every one in `test/mix_layer_screen_test.dart` — a concurrent run's file, untouched here and outside the plan's Predicted Files |
| `test` (whole Dart suite) | **4453 passed / 1 skipped / 66 failed**, every failure in that same `mix_layer_screen_test.dart` (`test-20261014-000342-34763.log`) |
| invariant grep over `lib/state lib/features lib/widgets lib/core` | no matches — this phase changed no Dart file |

The Dart numbers move only with that foreign file: this phase's own tree adds no Dart failure and no lint
issue of its own, so `lint` and `test` are reported here rather than attributed to the phase.

## Files changed

| File | Change |
|---|---|
| `watch/watchos/Sources/WatchSessionEngine/WatchExerciseListView.swift` | **new**, 155 lines: `WatchExerciseLetterList`, the D-3112 API, one `List` + `Section` + `scrollTo`, the grid as the list's first row |
| `watch/watchos/Sources/WatchSessionEngine/WatchMenuView.swift` | −47/+8: `WatchAddExerciseList.body` is the shared view; the local `letterGrid`, the `LazyVStack` and the unused `surfaceInset` deleted |
| `watch/watchos/Sources/WatchSessionEngine/WatchStartView.swift` | −29/+24: `WatchExercisePickerView.body` is the shared view in a `VStack` under a new `inSessionRows`; the empty text became `static let emptyText` |
| `watch/watchos/Tests/WatchSessionEngineTests/WatchMenuTests.swift` | +~46 lines: the Phase 2B citation block and S-3106 |
| `docs/state_management/watch_surface.md` | +5 lines: one shared component serves both entry points, citing S-3106 |
| `docs/watch-app-setup-and-qa.md` | +6 lines in step 14: far letters land, the picker draws the same list, citing S-3106 |

Every file is in the plan's Predicted Files. Nothing was deleted outside file edits, no directory was
created, and no scratch file was left behind.

# Evidence — plan 31, Phase 3 (the live heart rate: diagnose, then fix)

## Phase 0 — the tests, red before the change

Three tests, written before any implementation:

| Scenario | Test | File |
|---|---|---|
| S-3109 | `testS3109ATheLabelFollowsEveryBeat` | `WatchSensorRecordingTests.swift` |
| S-3110 | `testS3110ATheFeedPullsTheNewestBeatWhileAListenerWaits` | `WatchSensorSourceSourceTests.swift` |
| S-3112 | `testS3112ATheStoreAndTheHostRefreshTheHeartRateOnActivation` | `WatchSensorSourceSourceTests.swift` |

S-3109's fixture is the scenario's own: `FakeSensorSource`, a running engine, a `WatchSensorRecorder`
and a `WatchLoggingState(engine:clock:sensors:)`, driven with beats 100, 104, 109, 115, each after
`clock.advance(2)` — the instant has to move or `appendSensorSample`'s `sampleId` dedupe swallows the
beat and the label sticks at `"100"` for the wrong reason. It is run twice, as the brief asks: once over
a real `FileWatchSessionStore(directory:)` in a temp directory (removed by an `addTeardownBlock`) and
once over `InMemoryWatchSessionStore`.

The red run, before implementation:

```
swift-test --filter WatchSensorSourceSourceTests/testS311
Executed 6 tests, with 11 failures (0 unexpected)
  :780 :786 :791 :796 :801 :806 :831 :836 :847 :856  testS3110A…
  :867                                               testS3112A… (XCTUnwrap: the store has no refreshHeartRate)
```

## The S-3109 diagnosis (D-3107) — **GREEN over both stores**

```
swift-test --filter WatchSensorRecordingTests/testS3109A
Executed 1 test, with 0 failures (0 unexpected) in 0.068 seconds
swift-test-20261014-001507-58156.log
```

Both colours were green: the label follows every beat over `FileWatchSessionStore` **and** over
`InMemoryWatchSessionStore`. The package chain (`WatchSensorRecorder` → `appendSensorSample` →
`newestSensorSamples` → `WatchLoggingState.heartRateLabel`) is therefore not the defect: it carries every
beat the source hands it, whichever store is behind it. The beats stop upstream, in the app target, so
the diagnosis branch takes the "both GREEN" arm — D-3108 applies and items 4-5 are **not** skipped.
Root cause line, one sentence: *HealthKit's `didCollectDataOf` callback is missed while the app is
suspended with the wrist down, and nothing re-read the builder on wake, so the last delivered beat stayed
on screen.*

The red proof for a green-at-base test is a mutation, not `prove-red` (recorded below): it fails with
eighteen assertion failures when the label is stopped from following the beat, so it observes what it
claims.

## prove-red at the base commit

```
prove-red 0da2a72669a443ca400e5d42761635f14bf78216 swift-test \
  --filter WatchSensorSourceSourceTests/testS311 \
  -- watch/watchos/Tests/WatchSessionEngineTests/WatchSensorSourceSourceTests.swift
gateway: prove-red: RED AT 0da2a72669a443ca400e5d42761635f14bf78216
Executed 6 tests, with 11 failures (0 unexpected) in 0.140 seconds
```

Every failure is an assertion, none a compile or load error: ten in `testS3110A` on the pull's tokens
(the builder hand-over, the tick, the interval, the strictly-newer gate, the one gate for both paths,
the cancellation at the last listener, the store's `begin`/`end` hooks) and one in `testS3112A` (the
store has no `refreshHeartRate` there at all). The four other tests the filter runs pass at the base.
Log: `.work/gateway/swift-test-20261014-001540-59202.log`, which shows the run in the base workspace
(`.work/gateway/base-59098/watch/…`) with the failing lines 780, 786, 791, 796, 801, 806, 831, 836,
847, 856 and 867.

```
prove-red 0da2a72669a443ca400e5d42761635f14bf78216 swift-test \
  --filter WatchSensorRecordingTests/testS3109A \
  -- watch/watchos/Tests/WatchSessionEngineTests/WatchSensorRecordingTests.swift
gateway: prove-red: GREEN AT 0da2a72669a443ca400e5d42761635f14bf78216
Executed 1 test, with 0 failures (0 unexpected) in 0.064 seconds
```

GREEN here is the finding, not a failure to prove: S-3109 is the diagnostic (D-3107), and its green at
base is what says the package chain carries every beat. Log:
`.work/gateway/swift-test-20261014-001628-60362.log` (base workspace, ten `base-…/watch` paths).

## Mutation proofs

**S-3109** (a test that is green at base proves something only if it can be made to fail). Original line
in `WatchSessionEngine.appendSensorSample`, `:1291`:

```swift
        let alreadyStored = storedSensorSamples.contains { $0.recordId == record.recordId }
```

changed to `{ $0.kind == kind }` — a reading of a kind already stored is swallowed, which is the "the
label froze" defect:

```
WatchSensorRecordingTests.swift:327: error: -[… testS3109ATheLabelFollowsEveryBeat] : failed -
  FileWatchSessionStore: the label never followed the beat 104.0 (S-3109)
WatchSensorRecordingTests.swift:331: error: -[… testS3109A…] : XCTAssertEqual failed:
  ("Optional(100.0)") is not equal to ("Optional(104.0)") - FileWatchSessionStore: the newest stored row is the reading (S-3109)
WatchSensorRecordingTests.swift:336: error: -[… testS3109A…] : XCTAssertEqual failed:
  ("Optional("100")") is not equal to ("Optional("104")") - FileWatchSessionStore: the label follows every beat (S-3109)
… and the same three for 109.0 and 115.0, then all of it again for InMemoryWatchSessionStore
Executed 1 test, with 18 failures (0 unexpected) in 8.458 seconds
```

(the three assertion sites × three beats × two stores = 18; log
`.work/gateway/swift-test-20261014-001651-60804.log`). The line was restored to the exact original and
the test is green again — `WatchSensorRecordingTests` is the 17 tests / 0 failures group of the
whole-package run below. No mutation is left applied.

**S-3112.** `host.refreshHeartRate()` and its two-line `// D-3108:` comment removed from the
`.onChange(of: scenePhase)` active branch in `ContentView.swift`:

```
WatchSensorSourceSourceTests.swift:901: error: -[… testS3112ATheStoreAndTheHostRefreshTheHeartRateOnActivation] :
  XCTAssertTrue failed - activation is the wrist's second read: a suspended app missed the push path's
  callbacks while the wrist was down (D-3108, D-3113)
Executed 1 test, with 1 failure (0 unexpected) in 0.101 seconds
```

(`.work/gateway/swift-test-20261014-001710-61203.log`) restored to the exact original,
`swift-test --filter WatchSensorSourceSourceTests/testS311` → 6 tests / 0 failures
(`swift-test-20261014-001719-61344.log`).

## Done Criteria

| Check | Result |
|---|---|
| `swift-test` (whole package) | **573 tests / 0 failures** (`swift-test-20261014-001857-65405.log`) |
| `swift-test --filter WatchSensorSourceSourceTests` (whole file, the regression guard) | **16 tests / 0 failures** |
| `swift-test --filter WatchSensorRecordingTests/testS3109A` | 1 test / 0 failures |
| `test test/docs_indexing_contract_test.dart test/ui_standards_contract_test.dart` | **42 tests / 0 failures** |
| `lint` | 182 issues, **0 errors** — all info; 181 was the Phase 1/2A baseline and the 1 extra sits in a concurrent run's Dart files (this phase changed no Dart file) (`lint-20261014-001903-65564.log`) |
| `test` (whole Dart suite) | **4519 passed / 1 skipped / 0 failed** (`test-20261014-001914-65707.log`) |
| invariant grep over `lib/state lib/features lib/widgets lib/core` | no matches |

The app target cannot be compiled by an agent check (`swift test` builds only `watch/watchos`), so the
scans above are the off-device proof; the compiler's verdict on `HealthKitSensorFeed.swift`,
`HealthKitWorkoutStore.swift` and `ContentView.swift` comes from the governor's build. No `xcodebuild`
was run.

## Files changed

| File | Change |
|---|---|
| `watch/…/WatchSensorRecordingTests.swift` | +71 lines: the S-3109 citation block, `testS3109ATheLabelFollowsEveryBeat` and its two-store helper |
| `watch/…/WatchSensorSourceSourceTests.swift` | +139 lines: the citation block, `testS3110A…`, `testS3112A…` |
| `ios/OmniTrain Watch App/HealthKitSensorFeed.swift` | the pull: `heartRatePullSeconds = 3`, `heartRateBuilder`, `lastHeartRateEnd`, `heartRatePull`, the `MARK: - The pull` section (`refreshHeartRate(from:)`, `refreshHeartRate()`, `startPull()`), the delegate routed through the new `yieldHeartRateIfNewer`, and `forgetHeartRate` cancelling the pull at the last listener |
| `ios/OmniTrain Watch App/HealthKitWorkoutStore.swift` | +18 lines: the hand-over in `begin`, the clear in `end`, and `func refreshHeartRate()` |
| `ios/OmniTrain Watch App/ContentView.swift` | the host's `private let healthStore` (declared after `init`, so the construction in `init` stays the first `HealthKitWorkoutStore(` the existing S-3110 scan reads), `func refreshHeartRate()`, and the call in the scene-phase handler |
| `docs/watch-app-setup-and-qa.md` | step 23: the heartbeat criterion is now "changes at least every ~5 s, also after lowering and raising the wrist; if it freezes, note the last value and after how many seconds", plus the two lines that say why (the pull's tick and the activation read), citing S-3110/S-3112 |
| `docs/state_management/watch_surface.md` | +6 lines: the live label follows the sensor while the logging screen is up, citing S-3108 and S-3109 |

Every file is in the plan's Predicted Files. No file was deleted, no directory was created, and no
scratch file was left behind.

---

# Fix round 1 (2026-10-14) — the review's three findings and the app-target compile error

Brief: `.work/2026-10-13-31/brief-fix-1.md` (four items, all in this round). New plan entries: D-3117,
D-3118, S-3114.

## Item 1 — the interval-less heart-rate read (`HealthKitSensorFeed.swift`)

`statistics.mostRecentQuantityDateInterval()` is a **method**, so the property read the governor's
`xcodebuild` rejected became a call in both paths (`:194` push, `:253` pull), and a nil interval is now
D-3118's rule rather than a `Date()` fallback:

| Path | Interval known | Interval nil |
|---|---|---|
| push (`workoutBuilder(_:didCollectDataOf:)`) | `yieldHeartRateIfNewer(bpm, end: end)` | `yieldHeartRate(bpm)` — ungated |
| pull (`refreshHeartRate()`) | `yieldHeartRateIfNewer(bpm, end: end)` | `guard … else { return }` — the beat is dropped |

No `Date()` appears in either path. The pre-existing scan `testS3110ATheFeedPullsTheNewestBeatWhileAListenerWaits`
still greps the token `mostRecentQuantityDateInterval` and stays green (below). The app target cannot be
compiled by an agent check, so the compiler's verdict on this file is the governor's `xcodebuild`.

## Item 2 — one scroll id per key that opens two runs (`scrollTargetLetters`, D-3117, S-3114)

`watch/watchos/Sources/WatchSessionEngine/WatchMenu.swift` gains the pure rule next to
`deriveExerciseSections`:

```swift
public func scrollTargetLetters(of sections: [WatchExerciseSection]) -> [String] {
    var seen = Set<String>()
    var letters: [String] = []

    for section in sections where seen.insert(section.letter).inserted {
        letters.append(section.letter)
    }

    return letters
}
```

`WatchExerciseListView.swift` consumes exactly that list, in order, through `scrollIdsBySection()`
(sections are walked by index, so a second run of a key renders its header with **no** `.id`), and the
new `WatchMenuTests.testS3114ARepeatedLetterRunsCarryOneScrollId` asserts the rule *and* that the view
reads `scrollTargetLetters(of:`.

Fixture: `letterCatalogNames` (25 names, `Alpha`…`Whiskey`) + `"3x3 press"` + `"~stretch"` through
`harness.applyLetterCatalog` → 25 sections, the `#` key opening two of them (`"3x3 press"` first,
`"~stretch"` last), 24 targets.

### Red artifact for S-3114

`prove-red HEAD swift-test --filter testS3114ARepeatedLetterRunsCarryOneScrollId -- <WatchMenu.swift>
<WatchMenuTests.swift>`:

```
<WatchMenuTests.swift:123: error: … failed: caught error: "Error Domain=NSCocoaErrorDomain Code=260 …"
gateway: prove-red: RED AT HEAD (exit 1). It proves the guard only if an assertion fails for the reason the test
guards; a compile or load error means the test could not run there (use a mutation instead).
```

The carried test reads `WatchExerciseListView.swift`, which is untracked, so a base checkout has no such
file: the red is a load error, not an assertion. The mutation is the proof instead.

### Mutation proof (the brief's prescribed proof for this item)

| Line | Original | Mutant | Result |
|---|---|---|---|
| `WatchMenu.swift:175-182` | the `Set`-guarded loop above | `return sections.map(\.letter)` (every section's letter) | **RED**: 4 assertion failures — `("2") is not equal to ("1")` `S-3114 the repeated key carries one id`; `("24") is not equal to ("25")` `no id appears twice in one reader`; both list assertions (`the ids are exactly the letters the grid jumps by, in order`, `every key is kept at its first run`) — `swift-test-20261014-003751-*` |
| restored | the exact original lines, re-read in the file | — | **GREEN**: `swift-test --filter testS3114ARepeatedLetterRunsCarryOneScrollId` → 1 test / 0 failures (`swift-test-20261014-003756-*`) |

The restore was verified by reading the function back (`git diff` cannot isolate it: the file carries
Phase 2A's changes too, and `cmp` needs a shell). No mutation is left applied.

## Item 3 — the picker's hint scrolls with the list

`WatchExerciseLetterList` gains `trailing: AnyView? = nil` as its last initialiser parameter
(Assumption 1: the brief's optional-`AnyView` option, since nothing here is compiled by an agent check).
It renders as the `List`'s last row (`.listRowInsets(EdgeInsets())`, the shared inset), and in the empty
state it follows the empty text inside one `VStack` (Assumption 2). `WatchStartView.swift` now passes
`trailing: paths.phoneReachable ? AnyView(WatchSearchOnPhoneHint()) : nil`; the `VStack(spacing: 0)`
wrapper and the pinned hint below the list are gone, so the gate on `paths.phoneReachable` is unchanged.
No `LazyVStack` was introduced, and `testS3106AOneListServesBothEntryPoints` is green (below).

## Item 4 — the doc sentence (review finding 3)

`docs/watch-app-setup-and-qa.md` step 14's picker sentence now reads "draws the same list in the same
order: the grid is its first row, then the exercises the session already holds, then the one section per
letter", replacing "draws the same grid and the same list, with the session's own exercises above the
letters". No non-plan doc states where the hint sits, so item 3 implicates no doc sentence.
`docs/state_management/watch_surface.md`'s "One list serves both entry points" paragraph gained five
lines: only the first run of a key carries the scroll id (S-3114, D-3117 — the doc had not stated the id
rule at all), and the picker hands the list the hint as its last row, with the same "the watch app target
draws it and `swift test` does not compile it" caveat that paragraph already carried for the grid.

## Done Criteria

| Check | Result |
|---|---|
| `swift-test` (whole package) | **574 tests / 0 failures** (baseline 573 + the new test) (`swift-test-20261014-003900-94372.log`) |
| `swift-test --filter WatchMenuTests` (whole file) | **44 tests / 0 failures** |
| `swift-test --filter WatchSensorSourceSourceTests` (whole file, the feed's regression guard) | **16 tests / 0 failures** |
| `swift-test --filter testS3114ARepeatedLetterRunsCarryOneScrollId` | 1 test / 0 failures |
| `test test/docs_indexing_contract_test.dart test/ui_standards_contract_test.dart` | **42 tests / 0 failures** |
| `lint` | 182 issues, **0 errors** — all info, the same 181 baseline + 1 from a concurrent run's Dart files (this round changed no Dart file) (`lint-20261014-003939-94660.log`) |
| invariant grep (`import .*hive_workout_repository` over `lib/state lib/features lib/widgets lib/core`) | no matches |
| `test` (whole Dart suite) | **4519 passed / 1 skipped / 0 failed** (`test-20261014-004055-95193.log`) |
| plan residue | D-3117, D-3118, S-3114, the Progress line and four Assumption Log entries added; `## Feedback` left empty |

## Files changed (this round)

| File | Change |
|---|---|
| `watch/…/WatchMenu.swift` | +20 lines: `scrollTargetLetters(of:)` and its doc comment |
| `watch/…/WatchExerciseListView.swift` (untracked) | `trailing: AnyView?`, `scrollIdsBySection()`, `sectionHeader(_:scrollId:)`, the trailing row, two doc comments |
| `watch/…/WatchStartView.swift` | the picker passes `trailing: phoneHint`; the wrapper `VStack` and the pinned hint removed |
| `watch/…/WatchMenuTests.swift` | +80 lines: the fix-round citation block, `testS3114ARepeatedLetterRunsCarryOneScrollId` |
| `ios/OmniTrain Watch App/HealthKitSensorFeed.swift` | the `()` call in both paths, D-3118's nil rule, the header comment and two doc comments |
| `docs/watch-app-setup-and-qa.md` | step 14's picker sentence |
| `docs/state_management/watch_surface.md` | +5 lines in "One list serves both entry points": the id sits on a key's first run (S-3114, D-3117) and the picker's hint is the list's last row |
| the plan and this evidence file | the ledger, scenario, Progress and Assumption Log entries; this section |

`WatchMenuView.swift` was **not** touched: the menu already renders the shared list and the new parameter
defaults to `nil`. No file was deleted, no directory was created, no scratch file was left behind, and
nothing outside the brief's four items was changed.


