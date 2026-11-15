# Plan 173 — evidence

Measured on macOS, debug build, `swift test --package-path watch/watchos` through
`.github/copilot/scripts/macos/gateway.sh`.

## Suite counts

| Run | Command | Count |
|-----|---------|-------|
| Baseline (brief) | full `swift-test` before this plan's guards | 1470 / 0 |
| Final | `gateway.sh swift-test` | **1477 / 0**, replay corpus green (`classes: none`) |
| New file | `swift-test --filter WatchLaunchParseTests` | **7 / 0** |
| Store pins | `--filter WatchFileStoreTests` | 22 / 0 |
| Growth pins | `--filter WatchStoreGrowthTests` | 9 / 0 |
| S-004 scan | `--filter testS004` (all suites) | 18 / 0, incl. `testS004NoMutatingOperationExistsAnywhereInTheModule` |
| TSan (plan-162 filter + this file) | `swift-test --sanitize=thread --filter "WatchSensorSampleRaceTests\|WatchEngineListRaceTests\|WatchEngineSessionStateRaceTests\|WatchStoreGrowthTests\|WatchEngineStateBoxRaceTests\|WatchLaunchParseTests"` | **30 / 0** |
| Lint | `gateway.sh lint` | 181 issues — equal to the plan's baseline, none in `watch/` |

Two intermediate failures were fixed in this run and are recorded here because they changed the
guards: the S-004 scan rejected two names (`withSensorSamples` as a 4-space `func` in a
`*Store.swift`, and `writeSampleSideFile`'s verb), and S-17307's first two forms were flaky
(max-vs-min comparison; then a "no side files" baseline whose directory listing differed).

## Guards at HEAD

```
gateway.sh prove-red HEAD swift-test --filter WatchLaunchParseTests \
  -- watch/watchos/Tests/WatchSessionEngineTests/WatchLaunchParseTests.swift
```

Verdict: **does not compile at HEAD** — 15 diagnostics, all
`error: value of type '…WatchSessionStore' has no member 'readLaunch'` (the new API does not
exist at the base commit), so the guards are proven by mutation instead (plan-156 Phase B part 2).

## Mutation table

| # | Original line | Mutant | Result |
|---|---------------|--------|--------|
| M1 | `launchReadingsOnly(contentsLocked(from: loadRows()))` (`FileWatchSessionStore.readLaunchLocked`) | `contentsLocked(from: loadRows())` | first attempt **GREEN AT** — S-17301 could not see the exclusion because the load-time migration had already moved the readings; the test was strengthened with an adversarial directory (a directory where the side file's temp copy belongs, so the move cannot be written) and then: **RED AT** `WatchLaunchParseTests.swift:413` — `XCTAssertEqual failed: ("["sen-s-stuck-hr-1", "sen-s-stuck-gps-2", …")` for "a launch hands out no finished workout's readings, even inline ones (S-17301)". Restored exactly → **GREEN AT**. |
| M2 | `_ = await store.archiveSensorSamples(row.sessionId)` (`releaseReadingsOfAnEndedSession`) | body reduced to the terminal guard | **RED AT** `WatchLaunchParseTests.swift:536/541/548` — S-17304: side file empty (`0` vs `101`), readings still inline, next launch decodes `125` rows instead of `24`. Restored exactly → **GREEN AT**. |

No step ended with a mutation applied.

## Single terminal-row writer (Phase 3 item 2)

`grep "append\(\.session\(" watch/watchos/Sources/WatchSessionEngine` → three writers:

- `createSessionExclusive` — always `status: WatchSessionStatus.active`, so no release applies.
- `storeSessionRow` (the phone's writers) — ends with `await releaseReadingsOfAnEndedSession(carried)`.
- `transitionTo` (the wrist's own ladder and End, via `finishSession`/`captureSessionEnd`) — ends
  with `await releaseReadingsOfAnEndedSession(live)`.

The wrist's own end was the missing half: `transitionTo` appended the terminal row directly, so
S-17304 failed until the release was extracted and called from both writers.

## Launch cost

- Decode count (S-17301, the real assertion): a launch decodes **22 rows** — marker, 11 session
  rows, 10 end rows — with 0, 57,000, and 285,000 stored readings in ten side files. At HEAD the
  same file is 57,022 rows (the October shape), which is what a launch used to parse.
- Wall-clock tripwire (S-17307): cheapest of five launches over 57,000 stored readings versus the
  cheapest of five over the same main file with ten empty side files — **≤ 3×** (floor 1 ms).
- No 1 / 5 / 10 stored-hour wall table: producing one needs a throwaway test file, which this
  mode may not create (`delete-scratch` refuses non-`test/zz_*` paths). The flat 22-row count at
  10× side-file growth (S-17301) is the size-independent statement; the ratio is the regression
  tripwire. Recorded as an Assumption Log entry, not a decision.

## Residue sweeps

| Sweep | Result |
|-------|--------|
| `grep -rn "\.readAll()" watch/watchos/Sources` | **no matches** — no launch-path reader left |
| `grep -rn "watch-session.jsonl\|watch-samples-" watch/watchos/Sources` | `FileWatchSessionStore.swift`: `fileName = "watch-session.jsonl"`, `sampleFilePrefix = "watch-samples-"`, `sampleFileSuffix = ".jsonl"` — the naming sits beside the main file's; plus the protocol doc comment |
| `grep -n "restore()" "ios/OmniTrain Watch App/ContentView.swift"` | 8 sites, untouched — the file is not in `git-diff HEAD --name-only` (D-17306) |
| `grep -rln "import .*hive_workout_repository" lib/` | only `lib/main.dart` (composition root); nothing in `lib/state`, `lib/features`, `lib/widgets`, `lib/core` |
| `test/ui_standards_contract_test.dart` | no Dart file changed by this plan, so not run; the only Dart entries in the working-tree diff belong to other plans |
