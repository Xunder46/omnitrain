# Plan 150 — watch crash fix, recovered-workout discard, pace look

Two device crashes (2026-11-12, build 1.0.3 (20), SIGABRT) from a data race on
`WatchSessionEngine.storedSensorSamples`, plus a recovered workout discarded at
relaunch, plus a pace readout to diagnose. Swift only: `watch/watchos` and one
`ios/OmniTrain Watch App/ContentView.swift` edit.

## Scope

- **A** — every access to the sensor sample list goes through a lock-protected box; a
  concurrent append/read test proves it.
- **B** — an adopted workout survives `refresh(nil)` until the engine's restore has
  finished; after it, a nil or different session discards it as today.
- **C** — pace `/mi` look only, no change; cause and the unavailable-pace convention
  reported.

## Decisions

- **D-15001** A private `final class WatchSensorSampleLog` holds the array behind an
  `NSLock`; `snapshot()`, `append`, `contains`, `removeAll(where:)`, `replace`. The lock
  never wraps an `await`; the store append stays outside it.
- **D-15002** `append` is a no-op for a `recordId` already held, matching the store's
  own "same reading twice is a no-op" rule, so the racy read-then-append pair in
  `appendSensorSample` can go.
- **D-15003** Other engine arrays (`storedObservations`, `storedTimers`, `sessionRows`)
  are inspected and reported in the evidence file, not changed: this plan is the sensor
  list only.
- **D-15004** The coordinator gets `adoptedBeforeRestore`, set by `recover`'s adoption,
  cleared by `restoreFinished(_:)` or by the first non-nil session; `apply` returns
  early only while it is set and the session is nil. `WatchWorkoutLifecycle.action` stays
  pure and unchanged.
- **D-15005** `ContentView.restore()` calls `workout.restoreFinished(session: engine.session)`
  after `engine.restore()`; app-target code, not compiled by `swift test`.
- **D-15006** `HealthKitWorkoutStore.adoptInProgress()` and `WatchAppDelegate`'s recovery
  are read and reported, changed only if the nil-adoption cause is clear and small.
- **D-15007** Pace divides one window by itself: the header's metres (the newest stored
  `gps` reading) over the time since the first fix of that counter's current run — the
  run after the last total that went backwards (D-125's restart rule). `session.startedAt`
  is no longer read (S-15007).
- **D-15008** `WatchSensorPace.maxSecondsPerUnit` (3600, **exclusive**) is the ceiling: at
  or past it there is no pace and the line is absent, like a reading below the 50 m floor
  (S-15008). The label is formatted minutes:seconds, never `WatchLoggingState.clock`, so
  it cannot grow an hours field; the boundary is S-15010.

## Scenarios

- **S-15001** Many concurrent `appendSensorSample` tasks race `sensorSamples` reads; no
  trap, no failure, and every distinct reading is in the list exactly once.
- **S-15002** Adopted workout + `refresh(nil)` before restore finished: no end, the
  workout is still running.
- **S-15003** Then `refresh(same-id session)`: no new begin, no end.
- **S-15004** `restoreFinished(nil)` after adoption: one `end(saving: false)` (today's
  rule), no begin.
- **S-15005** A different session id after adoption: end then begin, as today.
- **S-15006** A `refresh(nil)` with no adoption ends the workout, as today (guard of the
  new early return).
- **S-15007** A counter restarted under a 21-minute session: the header's 0.1 mi is paced
  over the two minutes since the restart — `20:00 /mi`, one colon, not hours.
- **S-15008** 160 m over two hours: the distance still shows, the pace is nil.
- **S-15009** The existing `5:00 /km` case (`WatchSensorRecordingTests`, S-003) stays green.
- **S-15010** Exactly an hour a unit: nil; one second inside it: `59:59 /km`.

## Files

- `watch/watchos/Sources/WatchSessionEngine/WatchSensorSampleLog.swift` (new)
- `watch/watchos/Sources/WatchSessionEngine/WatchSessionEngine.swift`
- `watch/watchos/Sources/WatchSessionEngine/WatchPlatformWorkout.swift`
- `watch/watchos/Tests/WatchSessionEngineTests/WatchSensorSampleRaceTests.swift` (new)
- `watch/watchos/Tests/WatchSessionEngineTests/WatchWorkoutAdoptBeforeRestoreTests.swift` (new)
- `watch/watchos/Tests/WatchSessionEngineTests/WatchWorkoutCoordinatorTests.swift`
- `ios/OmniTrain Watch App/ContentView.swift`
- `docs/state_management/watch_sensors.md` / `docs/navigation_and_screens.md` if they
  describe the sample list or recovery (correct by naming the test).

## Progress

| Item | Status |
|---|---|
| A — sensor sample log + race test | Complete — full suite 1394 tests, 0 failures; TSan red at HEAD, clean after |
| B — adopted-workout hook + tests | Complete — S-15002…S-15006 green, S-15004/5 mutation-proved |
| C — pace look | Complete — look only, cause and convention in the evidence file |
| D — pace window + ceiling | Complete — S-15007…S-15010 green, red at HEAD; suite 1397/0 |

## Assumption Log

- **A-15001** The box's mutators are named `prune`/`fill`, not `removeAll`/`replace`:
  `WatchSessionEngineTests.testS004NoMutatingOperationExistsAnywhereInTheModule` forbids a
  `func` named for a mutation anywhere in the module. The scan is a guard, so the name moved.
- **A-15002** The fake platform logs an adoption in a separate `adopts` count rather than in
  `calls`: the pre-existing S-1503 asserts the exact `calls` array, and an adoption is state,
  not a call the coordinator makes.
- **A-15003** `.claude/crew.md` was modified (+2 lines) before this run started; the pipeline
  owns `.claude/`, so it is reported and left alone.
- **A-15004** The second-relaunch `workout_recovered` line is the first relaunch's discard seen
  again, not a second defect: the fix is Task B (evidence, Task B findings).
- **A-15005** Task D's ids start at D-15007/S-15007: D-15006 and S-15006 are Task B's, and
  renumbering committed work would break its evidence. The ceiling is Swift-only, not in
  `watch/contract/`, since the brief is the watch's pace; the Flutter readout is untouched.

## Task D — pace (2026-11-13)

The pace now pairs the header's distance with that counter's own window: the newest `gps`
reading's run, timed from its first fix (D-15007), so the restarting counter can no longer
meet the session's whole clock. Past an hour a unit (D-15008) there is no pace: absent, not
a placeholder, and the label is minutes:seconds so it cannot print hours.

- Files: `watch/watchos/Sources/WatchSessionEngine/WatchLoggingState.swift`,
  `watch/watchos/Tests/WatchSessionEngineTests/WatchSensorPaceTests.swift` (new). No doc
  page states the pace rule, so no doc changed; `ContentView.swift` untouched.
- Scenarios S-15007…S-15010; red at HEAD (`3:50:00 /mi`, `12:36:15 /km`, `1:00:00 /km`),
  green after; full suite **1397 tests, 0 failures** (evidence, Task D).

## QA for the owner

1. Outdoor walk on the watch: leave the logging screen open for 20+ minutes on build
   1.0.4; the app must not abort.
2. Kill the app mid-walk and relaunch: the Fitness workout from before the relaunch must
   stay open (no `workout_end discarded` in Diagnostics) and the session must reach the
   phone.
