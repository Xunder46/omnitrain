# Plan 162 — evidence

Plan: `2026-11-14-162-engine-state-lock-box-plan.md`. Phase 1 only (slice 1, commit 1 / PR 1).
All commands are the gateway form; the logs named are under `.work/gateway/`.

## Phase 1 — slice 1: the energy marks get one critical section

### 1. Red at HEAD (prove-red, TSan)

```
.github/copilot/scripts/macos/gateway.sh prove-red HEAD swift-test --sanitize=thread \
  --filter WatchEngineStateBoxRaceTests -- \
  watch/watchos/Tests/WatchSessionEngineTests/WatchEngineStateBoxRaceTests.swift
```

Verdict line:

```
gateway: prove-red: RED AT HEAD (exit 1). It proves the guard only if an assertion fails for the
reason the test guards; a compile or load error means the test could not run there (use a mutation
instead).
```

Log: `.work/gateway/swift-test-20261114-161517-17057.log` (1129 lines).
**10 TSan warnings, every one naming `WatchSessionEngine.swift` `announceEnergy` (1901 / 1902);
none named anything else.**

The first report (the guard's read racing the mark writes — `:1879` is the read, `:1901` the write):

```
==================
WARNING: ThreadSanitizer: data race (pid=17715)
  Write of size 8 at 0x00010e407328 by thread T4:
    #0 WatchSessionEngine.announceEnergy(kilocalories:at:) WatchSessionEngine.swift:1901
    #1 closure #1 in announcingCaller #1 () in WatchEngineStateBoxRaceTests.testS16201EnergyMarksSurviveTwoAnnouncingCallers() WatchEngineStateBoxRaceTests.swift:149

  Previous read of size 8 at 0x00010e407328 by thread T6:
    #0 WatchSessionEngine.announceEnergy(kilocalories:at:) WatchSessionEngine.swift:1879
    #1 closure #1 in announcingCaller #1 () in WatchEngineStateBoxRaceTests.testS16201EnergyMarksSurviveTwoAnnouncingCallers() WatchEngineStateBoxRaceTests.swift:149

  Location is heap block of size 401 at 0x00010e4071c0 allocated by thread T1

  Thread T4 (tid=28402782, running) is a GCD worker thread
  Thread T6 (tid=28402784, running) is a GCD worker thread

SUMMARY: ThreadSanitizer: data race WatchSessionEngine.swift:1901 in WatchSessionEngine.announceEnergy(kilocalories:at:)
==================
```

The remaining nine, all between the two announcing callers and all on the marks:

| # | Access A | Access B |
|---|---|---|
| 2 | write size 8, `:1901` (T6) | read size 8, `:1901` (T4) |
| 3 | write size 8, `:1901` (T4) | write size 8, `:1901` (T6) |
| 4 | write size 8, `:1902` (T6) | write size 8, `:1902` (T4) |
| 5 | write size 1, `:1902` (T6) | write size 1, `:1902` (T4) |
| 6 | write size 8, `:1901` (T6) | write size 8, `:1901` (T4) |
| 7-10 | same pairs, `:1901` / `:1902`, failing test names one per pair | |

TSan's own tally, from the end of the log:

```
ThreadSanitizer: reported 10 warnings
```

S-16202 was also observably red at HEAD without TSan — its one-shot pin is worth recording:

```
WatchEngineStateBoxRaceTests.swift:221: error: … testS16202TwoSimultaneousAnnouncementsEmitOneFrame
  : XCTAssertEqual failed: ("2") is not equal to ("1") - S-16202 two simultaneous announcements of
  one total emit one frame
```

(That makes A-16204's "red not guaranteed" stronger than planned: this run did catch the two-caller
window. It stays a pin — the TSan run is the deterministic red.)

### 2. Green after slice 1

Focused, no sanitizer (`.work/gateway/swift-test-20261114-161634-18356.log`):

```
Test Case …testS16201EnergyMarksSurviveTwoAnnouncingCallers passed (1.550 seconds).
Test Case …testS16202TwoSimultaneousAnnouncementsEmitOneFrame passed (0.002 seconds).
Executed 2 tests, with 0 failures (0 unexpected) in 1.552 (1.553) seconds
```

**Before the fix**, the same file reported `Executed 2 tests, with 1 failure` — S-16202 produced two
frames (`.work/gateway/swift-test-20261114-161435-16733.log`).

### 3. TSan filter, three runs

Command (the plan's item 6):

```
.github/copilot/scripts/macos/gateway.sh swift-test --sanitize=thread \
  --filter "WatchSensorSampleRaceTests|WatchEngineListRaceTests|WatchEngineSessionStateRaceTests|WatchStoreGrowthTests|WatchEngineStateBoxRaceTests"
```

| Run | Result | Log |
|---|---|---|
| 1 | `Executed 21 tests, with 0 failures (0 unexpected) in 29.853 (29.872) seconds`; grep for `ThreadSanitizer\|data race` over the log → **no matches** | `.work/gateway/swift-test-20261114-161702-19413.log` |
| 2 | `Executed 21 tests, with 0 failures (0 unexpected) in 27.767 (27.787) seconds`; no TSan line in the output at all | printed in full, no log file |
| 3 | `Executed 21 tests, with 0 failures (0 unexpected) in 29.623 (29.640) seconds`; no TSan line in the output at all | printed in full, no log file |

All three runs included `WatchEngineStateBoxRaceTests` (2 tests, green) — the class the red run's 10
warnings named. Baseline before the change: the same filter at HEAD produced the warnings in §1.

### 4. Full suite

```
.github/copilot/scripts/macos/gateway.sh swift-test
```

```
Test Suite 'All tests' passed at 2026-11-14 16:20:12.916.
	 Executed 1432 tests, with 0 failures (0 unexpected) in 29.436 (29.610) seconds
```

Log: `.work/gateway/swift-test-20261114-161925-20643.log`. Re-run after the final whitespace
tidy-up of the engine diff: **1432 tests, 0 failures** in 23.350 s
(`.work/gateway/swift-test-20261114-162131-23481.log`).

**1432, not the plan's 1431**: baseline 1430 + 2 new tests = 1432 (the plan's item 7 arithmetic
added two to 1430 but wrote 1431; D-16207's baseline is 1430). `WatchReplayTests` 4/4 passed within
it, including `testS15208EveryRecordingReplaysWithNamedOutcome`, which replays the whole corpus.

### 5. Files

Modified: `watch/watchos/Sources/WatchSessionEngine/WatchSessionEngine.swift` (+43/−5);
`docs/state_management/watch_sensors.md` (+8/−1).
Created: `watch/watchos/Tests/WatchSessionEngineTests/WatchEngineStateBoxRaceTests.swift`;
this plan and this evidence file.
Nothing under `lib/`, `test/`, `watch/contract/`, `watch/sync_protocol/` or `ios/` was touched
(`git-diff --stat` shows only the two tracked files above; the rest of the tree is the parallel
Dart run's work, already modified before this phase started).
