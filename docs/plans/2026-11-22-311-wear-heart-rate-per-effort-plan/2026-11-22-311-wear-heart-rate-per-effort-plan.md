# Plan 311 — The Wear wrist sends heart rate on each timed, round and hold entry, and a round's paused time (series 310-314)

Plan 310 put the session's heart rate on `session_end`. The Apple wrist also stamps each effort it logs with what it measured over that effort's own window, at log time (`watch/watchos/Sources/WatchSessionEngine/WatchLoggingState.swift` `sensorSummary(of:)` 1360-1397, `metricPayload` 1211-1250): a timed entry and a hold get the heart-rate pair over their window; a round gets the pair over its window with the stretches its countdown was paused left out, plus `pausedMs` (the countdown's pause, never longer than the window); a set carries nothing. The Dart wrist (`lib/watch/logging/watch_logging_state.dart` `_metricPayload` 729-761, `log` 677-724) sends none of it (`grep -rn pausedMs lib/watch` finds nothing). The phone reads all of it for any wrist (validator `message_validator.dart` 144-148, 560-580). Steps stay out (the Wear wrist has no step source). Base commit: `1b61eae7`. Analyze baseline: 174 issues, 0 errors.

## Goal and acceptance

A timed, hold or round entry logged on a Wear watch carries the average and maximum heart rate over its own window when readings exist; a round leaves its paused stretches out of the pair and carries `pausedMs` when it was paused for any time; nothing is sent when nothing was measured; a set stays bare. The engine's validator accepts every logged entry.

Acceptance: S-31101..S-31108 green and each guard red without its change; `flutter analyze` at most 174 issues, 0 errors; no new failure in the watch/wear test set against a clean checkout; Docs delta applied. Not provable without a real watch: owner check 26.

## Decision Ledger

| ID | Decision | Backing |
|---|---|---|
| D-31101 | `WatchSensorSummaries.heartRate` gains `{List<WatchPauseInterval> excluding = const []}`: a reading inside any interval is left out; an interval is half-open `[start, end)` in whole milliseconds (the instant a timer resumes counts again). Plan 310's calls stay valid (default empty). | `WatchSensorSummaries.swift` 93-121 |
| D-31102 | Port `WatchPauseInterval {start, end}`, `WatchSensorSummaries.pauses(rows, startedAt, windowEnd)` (the rows of one round timer that share its `startedAt`, ordered by `sequence`; a pause begins at a row's `pausedAt` and ends at the `recordedAt` of the first later row with no `pausedAt`, else the row's `stoppedAt`, else the window's end) and `pausedMs(countdown, windowStart, windowEnd)` (accumulated pause plus an open pause counted up to the earlier of its stop and the window's end, never longer than the window). | `WatchSensorSummaries.swift` 199-252 |
| D-31103 | `WatchSessionEngine.timerRows(String kind)`: the current session's timer rows of that kind in append order (the Apple `timerRows`); read-only. | `WatchLoggingState.swift` 1377 |
| D-31104 | `WatchLoggingState._metricPayload` round case adds `'pausedMs'` (via `pausedMs(countdown, wireInstant(start), wireInstant(end))`, with the countdown the engine's newest round timer) only when it is above zero and a countdown exists. | `WatchLoggingState.swift` 1220-1230 |
| D-31105 | `WatchLoggingState.log` merges a new `_sensorSummary(kind, event)` into the event before it is stored: for `timed` and `hold` (`WatchObservationKind.hold`), the heart-rate pair over the event's own `startedAt`..`endedAt`; for `round`, the same excluding the round timer's pauses; for a set, nothing. Computed at log time from the stored samples and never again (readings are pruned once the phone holds the session). A window with no qualifying reading adds nothing. | `WatchLoggingState.swift` 1360-1397 |
| D-31106 | Out of scope: steps; the shared capture contract replay (`watch/contract/watch_capture_contract.json` through the Dart engine) which becomes its own plan if wanted; GPS-measured distance windows (the Dart wrist sends the distance field's value as before). | |

## Input-reality checklist

- **Writers/units.** `log` is the only writer of an effort; the summary reads stored samples and timer rows in memory with no await between reading and building the event. Units: bpm, milliseconds.
- **Lifecycle.** A countdown paused and resumed several times yields several rows with one `startedAt`; a countdown still paused at log counts its open pause up to the round's end; a recovered workout keeps its stored samples; a timer row of a previous round (other `startedAt`) never counts.
- **Settings changing while open.** None.
- **Time edges.** A reading exactly at a pause start is excluded, exactly at its end is kept; a window of zero length (a timed effort logged with no duration) takes only a reading at that instant.
- **Load cost.** One pass over the session's samples per logged effort (a few thousand rows at most), at a tap.
- **Wording.** No words change.
- **Slot competition.** None (no screen).

## Scenarios

Fixture clock: `_t0` = `2026-01-05T10:00:00Z`; times below are offsets from it.

| ID | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-31101 | `heartRate` over `[0:00, 1:00]` with readings 100@0:10, 110@0:15, 140@0:30, 150@0:35, 160@0:40 and `excluding: [0:15 -> 0:35]` | readings at 0:15 (pause start) and 0:30 are left out, 0:35 (pause end) kept: average (100+150+160)/3 = 136.667 (`closeTo(136.6667, 1e-3)`), max 160; and with no `excluding` all five count (avg 132, max 160) | the parameter does not exist |
| S-31102 | `pauses` over rows of one timer (`startedAt` 0:00): r1 seq 1 paused at 0:15, r2 seq 2 running (recordedAt 0:35); a second case r1 paused at 0:15 and `stoppedAt` 0:50, no later row; a third r1 paused at 0:15 with nothing after and no stop, window end 1:00; a fourth with a row of another timer (`startedAt` 0:05) mixed in | `[0:15 -> 0:35]`; `[0:15 -> 0:50]`; `[0:15 -> 1:00]`; the other timer's row never contributes | the function does not exist |
| S-31103 | `pausedMs` for a countdown with accumulated 20000 and no open pause over a 60 s window; the same with an open pause from 0:50, not stopped, window end 1:00; accumulated 90000 over 60 s; open pause starting at 1:10 with window end 1:00 | 20000; 30000; 60000 (capped at the window); 20000 (a pause after the window adds nothing) | the function does not exist |
| S-31104 | engine `timerRows` after: a rest started and stopped, a round timer started, paused, resumed; and a second session | only the current session's rows of the asked kind, in append order (round: 3 rows; rest: 2 rows; unknown kind: empty) | the accessor does not exist |
| S-31105 | a timed effort logged through `WatchLoggingState.log` with readings 100@+1:00 and 140@+2:00 inside its window and one 200@+5:00 after it; then the same with no readings; then a set logged with readings present | the entry has avg 120, max 140; no HR keys; the set has no HR keys | `log` sends no heart rate |
| S-31106 | a hold (drill) effort with the same readings | avg 120, max 140 on the entry (and `extraLoadKg` unchanged when set) | the hold path would send none |
| S-31107 | a round logged after its countdown was paused 0:15 -> 0:35 within a 1:00 window, readings at 0:10, 0:20, 0:30, 0:40 (100, 110, 140, 160); then a round never paused; then a round paused for the whole window | HR over 0:10 and 0:40 only (avg 130, max 160) and `pausedMs` 20000; a never-paused round has the pair over all four (avg 127.5, max 160) and NO `pausedMs`; a fully paused round has no HR pair and `pausedMs` equal to the window | pauses would count and `pausedMs` would be absent |
| S-31108 | every entry logged in S-31105..S-31107 goes through the engine's emission validator | accepted (no `WatchEmissionRejected`); a hand-built round with `pausedMs` above its window is refused (proves the test is live) | an over-long `pausedMs` would make the log unsendable |

Readers of the changed code (all must stay green): grep before building `grep -rln "roundNumber\|distanceMeters\|extraLoadKg" test` and run each (the grep found 17 files; the lead runs every `test/watch_*.dart`, `test/wear_*.dart`, `test/live_mirroring_test.dart` and the import readers `test/distance_source_import_test.dart`, `test/row_invariants_guard_test.dart` and compares by name against a clean checkout), notably `test/watch_logging_surfaces_test.dart`, `test/watch_logging_stepping_test.dart`, `test/watch_timed_fill_test.dart`, `test/watch_timed_fill_screen_test.dart`, `test/watch_timer_push_test.dart`, `test/watch_timer_release_test.dart`, `test/watch_sensor_recording_test.dart`, `test/watch_session_auto_push_test.dart`, `test/wear_heart_rate_session_end_test.dart`. A test that compares a timed/round/hold payload whole with no samples stored stays green because nothing is added without a reading and `pausedMs` needs a countdown with a pause.

Mutation pass by the lead over every guard family (half-open pause bounds, pause start/end, the three pause-end fallbacks, the other-timer filter, accumulated plus open pause, the window cap, post-window pause, `> 0` rule, per-kind switch incl. set, round-only exclusion, no-reading absence, the log-time merge).

## Phases

| Phase | Agent | Scope | Marks |
|---|---|---|---|
| P1 | `crew-builder-watch` | `lib/watch/session/watch_sensor_summaries.dart`, `lib/watch/session/watch_session_engine.dart`, `lib/watch/logging/watch_logging_state.dart`, new `test/wear_heart_rate_per_effort_test.dart` | serial; exact code in the brief; no gateway command; the lead runs the tests |
| P2 | `crew-docs-keeper` | `docs/wear_os_app_sensors.md`, `docs/wear_os_app.md`, plan evidence | after the mutation pass |

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| `docs/wear_os_app_sensors.md` | MODIFIED | `time (plan 311), and steps (the Wear wrist has no step source).` | `Each timed, round and hold entry carries its own heart rate` | S-31105, S-31106, S-31107 |
| `docs/wear_os_app_sensors.md` | ADDED | - | `a round leaves its paused stretches out` | S-31107, S-31101 |
| `docs/wear_os_app.md` | ADDED | - | `26. (owner) on a real Wear watch paired with an Android phone` | D-31105 (owner check) |

## Assumption Log

- A-1: the phone's importer stores per-effort heart rate for any wrist and the validator bounds are those quoted (`message_validator.dart` 144-148, 560-580); the reviewer of 310 reads the same bounds for the session end.
- A-2: `WatchTimerRecord.recordedAt` is the instant of each state change (as the Apple row's), so a resume's `recordedAt` is the pause's end; checked by S-31102.
- A-3: scope guard (`pr-scope-guard`): about 90 production lines plus one test file and two doc lines; inside the budget.

## Progress

| Item | Status |
|---|---|
| seed | Done |
| P1 build | Done |
| tests and mutation pass | Done |
| P2 docs | Done |
| commit | Open |
| owner check 26 | Open, needs a real Wear watch paired to a phone |
