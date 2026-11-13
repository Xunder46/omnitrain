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
- **D** — the header's pace divides the metres it prints by the time of their own run, with
  a ceiling; `watch/watchos` tests only.
- **E** — the header's distance is the Distance field's own figure, so the two agree after
  a restart; `watch/watchos` only.
- **F** — the engine's observation and timer lists get Task A's lock box, proved by a TSan
  race test each, and the whole suite runs under TSan once; `watch/watchos` only.

## Decisions

- **D-15001** A private `WatchSensorSampleLog` holds the array behind an `NSLock` (`snapshot`, `append`, `contains`, `prune`, `fill`); the lock never wraps an `await`, the store append stays outside it.
- **D-15002** `append` is a no-op for a `recordId` already held, matching the store's "same reading twice is a no-op" rule, so the racy read-then-append pair can go.
- **D-15003** Other engine arrays (`storedObservations`, `storedTimers`, `sessionRows`) are inspected and reported in the evidence, not changed by Task A. *(Amended by D-15021: the first two were proven racy and boxed by Task F; the rest stay as reported.)*
- **D-15021** `storedObservations` and `storedTimers` move into `WatchObservationLog` and `WatchTimerLog` (`WatchEngineRowLogs.swift`), D-15001's pattern: snapshot for reads, an append that ignores an id already held, and the in-flight claim made in the same operation as the "already held?" check (`claim`/`finishClaim`), so two copies of an entry cannot both store it (F-7). No lock is held across an `await`.
- **D-15022** `sessionRows`, `current`, the correction/deletion lens and `acknowledgedObservationIds` are left plain: TSan reproduced no race on them, and an unproven race is reported, not rewritten (D-15003).
- **D-15004** The coordinator gets `adoptedBeforeRestore`, set by `recover`'s adoption and cleared by `restoreFinished(_:)` or the first non-nil session; `apply` returns early only while it is set and the session is nil. `WatchWorkoutLifecycle.action` stays pure.
- **D-15005** `ContentView.restore()` calls `workout.restoreFinished(session: engine.session)` after `engine.restore()`; app-target code, not compiled by `swift test`.
- **D-15006** `HealthKitWorkoutStore.adoptInProgress()` and `WatchAppDelegate`'s recovery are read and reported, changed only if the nil-adoption cause is clear and small.
- **D-15007** Pace divides one window by itself: the header's metres (the newest stored `gps` reading) over the time since the first fix of that counter's current run — the run after the last total that went backwards (D-125). `session.startedAt` is no longer read (S-15007).
- **D-15008** `WatchSensorPace.maxSecondsPerUnit` (3600, **exclusive**) is the ceiling: at or past it there is no pace and the line is absent, like a reading below the 50 m floor (S-15008). The label is minutes:seconds, never `clock`, so it cannot grow an hours field (S-15010).
- **D-15011** One private `distanceWindow(for:)` answers the header's distance and its pace: with the Distance row it is `windowDistanceMeters()` over `workTimer.startedAt`, the field's own figure, so the two cannot drift (S-15011, S-15014); the pace divides that window (S-15012).
- **D-15012** "The row exists" is `isMeasured(WatchMetricKey.distance)` plus a running work clock. Without it the header keeps D-15007/D-15008 exactly: the newest stored `gps` total over its own run (S-15013).

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
- **S-15011** A counter restart inside the effort window, read after a relaunch: the
  header's distance string equals the Distance field's (`0.6 mi`, not the run's `0.1`).
- **S-15012** That fixture's pace is the window's time over its metres (`6:42 /mi`), one
  colon, not the restarting run's `20:00 /mi`.
- **S-15013** No effort window (no Start): the header keeps the counter's own run
  (`0.1 mi`, `20:00 /mi`).
- **S-15014** The unit switch keeps header and field equal (`0.6 mi` / `1.0 km`), and the
  pace follows (`6:42 /mi` / `4:10 /km`).
- **S-15021** Three logging tasks append 180 sets while three readers hammer `observations`,
  `entries`, `pendingObservations()`, `unconfirmedObservations`, `nutritionLog` and
  `waterLog`: no trap, and each of the 180 ids is held exactly once.
- **S-15022** 60 start/stop rounds race readers of `timerFor`, `timerRows` and
  `sessionSnapshot()`: `timerRows` holds 120 rows, the newest row's state is `.stopped`,
  and nothing traps.
- **S-15023** 80 `advanceExercise` calls and 40 `delete_entry` frames race readers of
  `session`, `currentExercise`, `sessionSnapshot()`, `entries`, `hasEffortRating` and
  `sensorSamples`: the session still answers `s-race` as active and the deleted id stays
  hidden. (Green at HEAD: on the mirror and lens this is a preservation guard.)

## Files

- `watch/watchos/Sources/WatchSessionEngine/WatchSensorSampleLog.swift` (new)
- `watch/watchos/Sources/WatchSessionEngine/WatchEngineRowLogs.swift` (new, Task F)
- `watch/watchos/Sources/WatchSessionEngine/WatchSessionEngine.swift`
- `watch/watchos/Sources/WatchSessionEngine/WatchPlatformWorkout.swift`
- `watch/watchos/Tests/WatchSessionEngineTests/WatchSensorSampleRaceTests.swift` (new)
- `watch/watchos/Tests/WatchSessionEngineTests/WatchEngineListRaceTests.swift` (new, Task F)
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
| E — header distance = Distance field | Complete — S-15011…S-15014 green, red at HEAD; suite 1401/0 |
| F — the other engine lists | Complete — audit + TSan; S-15021/S-15022 red at HEAD and clean after, S-15023 not proven; suite 1404/0, whole suite under TSan 1404/0 |

## Assumption Log

- **A-15001** The box's mutators are `prune`/`fill`, not `removeAll`/`replace`: `testS004NoMutatingOperationExistsAnywhereInTheModule` forbids a mutation-named `func`, so the name moved.
- **A-15002** The fake platform logs an adoption in a separate `adopts` count, not in `calls`: the pre-existing S-1503 asserts the exact `calls` array.
- **A-15003** `.claude/crew.md` was modified (+2 lines) before this run started; the pipeline owns `.claude/`, so it is reported and left alone.
- **A-15004** The second-relaunch `workout_recovered` line is the first relaunch's discard seen again, not a second defect (Task B).
- **A-15005** Task D's ids start at D-15007/S-15007 so committed Task B ids keep their evidence; the ceiling is Swift-only, since the Flutter readout is untouched.
- **A-15006** S-15013 is a preservation guard, green at HEAD by design; a fallback mutation turns it red, then the exact line is restored.
- **A-15007** Before Start the effort window is 0 and the Distance row is absent, so the header keeps the counter's figure and no second number shows.
- **A-15021** The observations and their in-flight claims share one box: splitting them would leave the claim a second unsynchronised list, which is the race S-15021 proves exists.
- **A-15022** `EntryClaim` became internal and moved to `WatchEngineRowLogs.swift`, because a private class cannot be shared with the box's file; no behaviour changed.
- **A-15023** S-15023 stays green at HEAD and is kept as the mirror/lens preservation guard, since TSan reported no race there (D-15022).

## Tasks D and E — pace and the header's distance (2026-11-13/14)

The header now prints the Distance field's own figure (D-15011): one private accessor
answers both labels — the effort window's metres over the effort window's start wherever
the Distance row exists (D-15012), else Task D's pairing, the newest `gps` total timed
from the first fix of its own run (D-15007), so a restarting counter can no longer meet
the session's whole clock. Past an hour a unit (D-15008) there is no pace, and the label
is minutes:seconds so it cannot print hours.

- Files: `watch/watchos/Sources/WatchSessionEngine/WatchLoggingState.swift`,
  `WatchSensorPaceTests.swift` (D, new), `WatchHeaderDistanceTests.swift` (E, new). No doc
  page states the header rule, so no doc changed; `ContentView.swift` untouched.
- D: S-15007…S-15010, red at HEAD (`3:50:00 /mi`, `12:36:15 /km`, `1:00:00 /km`), green
  after; suite 1397/0. E: S-15011…S-15014, red at HEAD (`0.1` vs `0.6`, `20:00 /mi` vs
  `6:42 /mi`), green after; suite **1401 tests, 0 failures** (evidence, Task E).

## Task F — the engine's other lists (2026-11-12)

Every mutable stored property is audited in the evidence file (writers, readers, thread class,
overlap). Two are proven racy under TSan at HEAD — the observation list with its in-flight claims,
and the timer list — and both now sit behind `NSLock` boxes in `WatchEngineRowLogs.swift`
(D-15021). The mirror, lens and acknowledgement set reproduced nothing, so they are reported, not
rewritten (D-15022). Files: `WatchEngineRowLogs.swift` (new), `WatchEngineListRaceTests.swift`
(new), `WatchSessionEngine.swift`, `docs/state_management/watch_sensors.md`. S-15021/S-15022 red
at HEAD (`Swift access race` at `:1760`, `:1755`, `:2297`, then BUS in `observations.getter :203`),
green after; suite **1404/0**, whole suite under TSan **1404/0** (17 warnings, all in test doubles).

## QA for the owner

1. Outdoor walk on the watch: leave the logging screen open for 20+ minutes on build
   1.0.4; the app must not abort.
2. Kill the app mid-walk and relaunch: the Fitness workout from before the relaunch must
   stay open (no `workout_end discarded` in Diagnostics) and the session must reach the
   phone.
3. On that relaunched screen the header's distance must read the same as the Distance row
   (`0.6 mi` beside `0.6 mi`), and its pace that window's time — about `6:42 /mi` for the
   owner's walk, not the restarting counter's `20:00 /mi`.
