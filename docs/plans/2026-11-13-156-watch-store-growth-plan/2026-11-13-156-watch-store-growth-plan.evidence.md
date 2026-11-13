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
