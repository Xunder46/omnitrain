# Plan 156 evidence

## Measurement 2026-11-13 (lead, throwaway test, deleted afterwards)

Mac, debug build (`swift test`), `FileWatchSessionStore` in a temp directory, 5,700 readings per stored hour (Fable's estimate for outdoor, kinds hr/gps/steps/energy rotating), old finished workouts only; then a fresh store and engine (`restore()` = a launch), a new running workout, 20 appended readings, 20 reads of `newestSensorSamples()`.

| Stored outdoor hours | Rows | File | Launch (`restore`) | Per new reading | Per screen tick read |
|---|---|---|---|---|---|
| 1 | 5,700 | 0.9 MB | 0.16 s | 2.8 ms | 0.7 ms |
| 5 | 28,500 | 4 MB | 0.82 s | 14.5 ms | 3.3 ms |
| 10 | 57,000 | 9 MB | 1.66 s | 28.7 ms | 6.5 ms |

Writing the 57,000 rows through `append` took 585 s (146 s for 28,500; 5.8 s for 5,700): quadratic. Everything is linear in stored size except that, which is quadratic in total. Debug build, so absolute numbers are pessimistic for the engine's own code and optimistic for a real watch's CPU. Fable's table (13 s launch at 50 h) was not reproduced; the shape matches. Memory was not measured.

## Facts read from the code

- `pruneSettledSensorSamples()` gate: session not active, no entry awaiting a receipt, the wrist-created session's `session_end` acknowledged. It has no caller in `Sources` or the app. `engine.pruneConfirmed()` likewise; only `pruneWaterTaps` has a caller (`WatchWaterState.restore()`).
- `FileWatchSessionStore.appendLocked` scans `loadRows()` for the id; `WatchSensorSampleLog.append` scans its rows; `newestSensorSamples()` copies the whole list and filters by the current session every tick; `pruneConfirmedLocked` compacts (rewrites the file) even when it drops nothing.

## Phase A — wiring, valve, compact-only-when-dropping (developer, 2026-11-13)

`prove-red HEAD swift-test --filter WatchStoreGrowthTests -- watch/watchos/Tests/WatchSessionEngineTests/WatchStoreGrowthTests.swift`

> gateway: prove-red: **RED AT HEAD (exit 1).** It proves the guard only if an assertion fails
> for the reason the test guards.
> Executed 5 tests, with 7 failures.

| Test | Red at HEAD because |
|---|---|
| `testS15601TheLaunchRestoreAsksForThePrunes` | `ContentView.restore()` never calls the settle prune (`XCTUnwrap` at :213) |
| `testS15602TheLastReceiptReleasesTheReadingsInPlace` | the receipt frame releases nothing, in memory or on disk (:256, :261) |
| `testS15603AnUnacknowledgedWorkoutKeepsItsReadingsForFourteenDays` | no valve exists: 0 readings released at 15 days (:294, :300, :303) |
| `testS15604APruneThatDropsNothingDoesNotRewriteTheFile` | the prune rewrites the file: the inode changes (:329) |
| `testS15601TheLaunchPruneReleasesFinishedReadingsOnly` | **passes at HEAD**: it calls `pruneSettledSensorSamples()` itself, and that gate is pre-existing code. The new guard for the launch is the source scan above; this test pins what the launch does with it (ten settled workouts, a running one, an unacknowledged one). |

Green after the change:

- `swift-test --filter WatchStoreGrowthTests`: **5 tests, 0 failures**.
- `swift-test --filter WatchSensorRecordingTests`: **39 tests, 0 failures** (the S-237 family).
- `swift-test --filter WatchWaterBarSourceTests`: **5 tests, 0 failures**.
- Full `swift-test`: **1425 tests, 0 failures** in 18.4 s (baseline 1420 + the 5 new ones).

Two plan decisions collided with existing pins and were resolved by moving the code, not the
pins (Assumption Log A-156-01, A-156-02):

- The receipt trigger sits in `applyReceipt` (the receipt frame) rather than in
  `confirmObservations`. A release inside `confirmObservations` made the two plan-150 S-237 tests
  in `WatchSensorRecordingTests` report `0` where they assert the count a later explicit prune
  returns — an existing test going red on an unpredicted reason, and order-dependent.
- `ContentView.restore()` calls the settled prune only. A production `pruneConfirmed()` would drop
  water taps the water count still reads, which plan 96 D-43 pins
  (`WatchWaterBarSourceTests.testS94b25aPruneConfirmedHasNoCallerAndOnlyLaunchPrunesTaps`).

Prerequisite found on the way (A-156-03): `InMemoryWatchSessionStore` had no synchronisation at
all, so the receipt-triggered prune racing an engine turn crashed the full suite with
`Fatal error: Index out of range`. The twin is now `NSLock`-protected, method for method.

## Phase B — constant-time appends (developer, 2026-11-13)

D-15604 landed: a `Set<String> ids` beside `WatchSensorSampleLog`, `WatchObservationLog` and
`WatchTimerLog`, kept under the existing lock, and a `heldIds` superset keyed `recordType + id` in
`FileWatchSessionStore`. A prune never shrinks `heldIds`, so a miss proves the row is new and a hit
is confirmed against `rows`; `loadRows()` returns the in-memory array once loaded, so an append no
longer walks the file's rows.

`prove-red HEAD swift-test --filter WatchStoreGrowthTests -- watch/watchos/Tests/WatchSessionEngineTests/WatchStoreGrowthTests.swift`

> gateway: prove-red: **RED AT HEAD (exit 1).**
> Executed 6 tests, with 8 failures (0 unexpected) in 99.043 s
> `testS15605TwentyThousandAppendsStayInsideTheBound`: `XCTAssertLessThan failed: ("98.18671905994415")`

| Test | HEAD | With the index |
|---|---|---|
| `testS15605TwentyThousandAppendsStayInsideTheBound` | 98.2 s, fails the 8 s bound | 6.55 s, 6.48 s (two runs) |
| the five Phase A tests | unchanged red | green |

The count is asserted as well as the time — 20,000 rows in the engine's log and 20,000 in the file —
and a repeated reading at 20,000 rows is still one row, so the index does not change what a
duplicate is (S-15604's "public behaviour unchanged").

Margin: 6.5 s against the 8 s bound on this Mac. The remaining cost is the store's per-append
`FileHandle` open plus `synchronize()` — one fsync per reading, a durability choice this plan does
not change — not scanning; the same run is 15× faster than at HEAD (A-156-05).

## Final verification after Phase A + B (2026-11-13)

- Full `swift-test`: **1426 tests, 0 failures** in 24.7 s (1420 baseline + 6 growth tests).
- `swift-test --sanitize=thread --filter WatchSensorSampleRaceTests`: **1 test, 0 failures**.
- `swift-test --sanitize=thread --filter WatchEngineListRaceTests`: **5 tests, 0 failures**.
- `lint`: **181 issues**, all pre-existing notices in `test/` and `lib/` files this run did not
  touch (no Dart file changed here). The plan carried no lint baseline; this is the count to compare
  against.
- Full `test`: **7522 passed, 5 skipped, 10 failed**. No failing file or its source is part of this
  run's diff. The only Dart production file dirty in the working tree is
  `lib/state/workout/session_core_lifecycle.dart` (+48 lines, another run's uncommitted work), and
  the failures are its symptoms (`totalVolume` 0.0 where 980.0 is expected, rest records, watch
  session finish). Reported, not touched.

Not done in this run: D-15605 (per-session reads, S-15606) and the 1/5/10-hour re-measurement — see
the plan's Progress table.



## Lead review 2026-11-13

- **End entry carries the summaries (D-15602 precondition, checked by the lead, not the agent):** `captureSessionEnd` (`WatchSessionEngine.swift` ~2020) stores the `session_end` observation (`appendObservation`, built by `sessionEndEvent` from the readings at that moment) the first time a session becomes completed or abandoned, and never re-emits it with different values (`!knowsObservation(...)`). The readings are therefore redundant for the phone once that row exists; the 14-day valve loses nothing the end entry holds.
- **Change made by the lead:** `FileWatchSessionStore.heldIds` was a never-shrinking superset; it is now exact (`adopt(_:)` rebuilds it after every prune), so a pruned workout's keys are not held for the life of the process.
- **Not done (D-15605 and the re-measurement table):** per-session reads and the newest-per-kind cache, S-15606; after the prunes the log is bounded, so this matters for one very long workout and for the per-tick copy, and is its own run.

## Re-measurement after the change (lead, 2026-11-13, throwaway test, deleted)

Same method and machine as the first table (debug build, no prune because nothing is acknowledged, so this is the worst case).

| Stored outdoor hours | Rows | Launch | Per new reading | Per screen tick read |
|---|---|---|---|---|
| 1 | 5,700 | 0.42 s | 0.10 ms | 1.2 ms |
| 5 | 28,500 | 1.42 s | 0.10 ms | 5.3 ms |
| 10 | 57,000 | 3.34 s | 0.12 ms | 11.4 ms |

Per new reading was 2.8 / 14.5 / 28.7 ms: now flat. Writing 57,000 rows through `append` took 5.0 s (was 585 s). Launch and the tick read are still linear (launch is machine-load sensitive: the first table's 1.66 s at 10 h was taken on a quieter machine). They are the work left: the prunes bound the stored size for acknowledged workouts, and D-15605 makes the tick read independent of it.

## Lead fix 2026-11-13 (a second cause of the growth)

The agent's index made the duplicate check constant-time, but `FileWatchSessionStore.appendLocked` still held a local copy of the whole row array (`let loaded = loadRows()`) while it ran `rows?.append`. Two references to one buffer make that append copy the whole array (copy on write), so each append still cost more as the store grew (file store alone: 0.08 s / 0.29 s / 0.53 s per 1,000 appends at the start, middle and end of 20,000). The local copy is gone (`heldRow(for:)` returns only the row it finds); 20,000 appends through the engine and the file store now take about 2 s, not 6.8 s. S-15605 was rewritten from a wall-time bound (6.8 s against 8 s, and 35 s under Thread Sanitizer) to a ratio of the same machine's timings (the last 1,000 appends against the first 1,000, bound 3x): at HEAD sources it fails (14.0 s against 1.7 s allowed), with the change it passes in a normal and a Thread Sanitizer build.
