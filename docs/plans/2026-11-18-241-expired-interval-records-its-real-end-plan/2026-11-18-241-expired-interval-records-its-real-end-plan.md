# Plan 241 — An interval that runs out while the phone sleeps records its real end

Series: nutrition/calendar/summary pre-launch review (2026-11-16), third pass item "a round that ends while the phone is locked replays its alert on unlock and starts the rest from unlock". Probing it showed the replayed alert is the smaller part: the recorded numbers are wrong. Phone only (`lib/state/workout/timer_manager.dart`, `workout_state.dart`, `lib/features/session/workout_session_timer_mixin.dart`). The production edits are exact and already applied by the lead; one builder run writes the tests; then docs. Status: COMMITTED (built, mutation-checked (7 of 7 killed), docs applied; full suite +7978 ~4 green.

## Goal and acceptance

When a timed interval, hold or drill reaches its target while the app is not running its ticker (a locked or backgrounded phone, an app relaunched later), the app notices at the next tick or on the next screen open and then finishes the entry with `finishTimedEntry`, which stamps the end as NOW: `actualDurationSecs` is the time until the app noticed. A 60 s hold that expired while the phone slept for 5 minutes is stored as a 300 s hold; reopened a day later, up to 24 h. Stats read `actualDurationSecs` for total hold time and the longest hold (`stats_progress_service.dart:1745-1810`, `2925`), so one sleeping phone inflates a hold record. A round has the right duration (`completeRound` stamps `start + planned + pauses`) but, like an interval, its REST starts at the instant the app noticed (`restStartMs = now`), so the recorded rest after a late-noticed round or interval is shorter than the real one and the rest pings count from the wrong instant.

After this change an entry that ran out by itself is finished at its real end (start + pauses + target, never later than now), and the rest after it begins at that same instant.

Not changed (open item 1, an owner call): the alert sound the screen plays when it notices late (the background notification already sounded at the real end, so the user can hear twice).

Acceptance: S-24101..S-24107 green, those marked "fails without" red at the base commit or killed by the lead's mutation; readers green or reported; `flutter analyze` at baseline (181, 0 errors); full suite no new red.

## What the user sees

- A hold or interval that finishes while the phone is locked is recorded at its target length (60 s stays 60 s), in the session and in Stats (total and longest hold). Today it is recorded as long as the phone slept.
- The rest after it starts counting from the instant the interval or round ended, so the rest chip shows the real rest, not one that starts at unlock.
- Nothing changes for a manual finish (Log Interval before or after the target still records the real elapsed time) or for a workout ended with an interval still running.
- To SEE it: start a 1-minute hold, lock the phone for 5 minutes, unlock and open the exercise: it shows 60 s, not 5 min.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-1 | `TimerManager.finishTimedEntry(effortId, entryIndex, {int? expiredAfterSecs})` (forwarded by `WorkoutState.finishTimedEntry`): with `expiredAfterSecs` set the end instant is `startedAtMs + totalPausedMs + expiredAfterSecs * 1000` provided that is not after now (otherwise now, as before); `finishedAtMs` is that instant and `actualDurationSecs` is the elapsed time up to it (the target). Without it the behaviour is unchanged. | `timer_manager.dart:finishTimedEntry` |
| D-2 | `TimerManager.recordRestStart(effortId, entryIndex, {int? atMs})` (forwarded by `WorkoutState.recordRestStart`): `restStartMs` is `atMs` when it is not after now, else now. | `timer_manager.dart:recordRestStart` |
| D-3 | `_handleEffortTimerExpired` (the tick and the drain path) finishes a timed/drill entry with `expiredAfterSecs: targetSeconds`, and for both timed and round entries reads the entry's stored `finishedAtMs` after the finish and uses it as the rest's start (`recordRestStart(..., atMs: endMs)`) and as `restStartMs` of the rest pings (past ping times are already skipped by the service). | `workout_session_timer_mixin.dart:_handleEffortTimerExpired` |
| D-4 | `_restoreTimerStateFromPersisted` (a screen opened on an interval that already ran out, after a relaunch or Back) finishes it with `expiredAfterSecs: targetSecs`. | `workout_session_timer_mixin.dart:153` |
| D-5 | Unchanged on purpose: the manual log (`workout_session_screen.dart:959`), the finish-with-intervals-running paths (`workout_session_timer_mixin.dart:877`, `timer_manager.dart:1290`, "the user ended it now"), the watch paths, round completion (already exact). | review |

## Scenarios

| ID | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-24101 | `TimerManager` test (the harness of `test/timer_manager_clock_test.dart`, a clock variable): `addTimedEntry`, `startTimedEntry` at T0, clock moved to T0 + 300 s, `finishTimedEntry('e-t', 0, expiredAfterSecs: 60)`. | stored `actualDurationSecs == 60`, `finishedAtMs == T0 + 60 000`. | the base has no parameter and records 300 s / T0 + 300 s |
| S-24102 | Control: the same, `finishTimedEntry('e-t', 0)` with no parameter at T0 + 300 s. | `actualDurationSecs == 300`, `finishedAtMs == T0 + 300 000`. | passes both ways on purpose (mutation: the parameter ignored and always capped) |
| S-24103 | With a pause: start at T0, `pauseTimedEntry` at T0 + 10 s, `resumeTimedEntry` at T0 + 30 s (20 s paused), clock to T0 + 400 s, `finishTimedEntry(.., expiredAfterSecs: 60)`. | `actualDurationSecs == 60`, `finishedAtMs == T0 + 80 000` (start + 20 s paused + 60 s). | the base records 400 - 20 = 380 s |
| S-24104 | Clock earlier than the cap: start at T0, clock at T0 + 30 s, `expiredAfterSecs: 60`. | falls back to now: `finishedAtMs == T0 + 30 000`, `actualDurationSecs == 30` (never an end in the future). | passes both ways on purpose (mutation: the cap taken without the now check) |
| S-24105 | `recordRestStart('e-t', 1, atMs: <past>)` with the clock at T; then `recordRestStart('e-t', 2, atMs: <T + 10 min>)`; then `recordRestStart('e-t', 3)`. | the stored rests start at the past instant, at T (a future `atMs` is not honoured), and at T. | the base has no parameter and always stamps now |
| S-24106 | Screen test, Mock (the harness and the expired fixture of `test/open_screen_mid_run_keeps_timer_test.dart` S-23304: a timed interval stored active, target 30 s, started 60 s ago): mount the screen, settle. Read the stored instance. | `actualDurationSecs == 30` and `finishedAtMs == startedAtMs + 30 000` exactly. | the base finishes it at now: about 60 s and a later stamp |
| S-24107 | Control, same file: a target 120 s interval started 40 s ago (still running). | not finished: the stored instance is still active (`finishedAtMs` null). | passes both ways on purpose (mutation: the restore path finishes every active interval) |

## Input-reality checklist

1. Writers and units: only the two finish paths named in D-3/D-4 pass the parameter; units are seconds in, epoch ms stored. `targetDurationSecs` on the instance is the target the restore path uses; the tick path uses the cached target (`_getEffortTargetDuration`), which equals it.
2. Lifecycle: the cap needs `startedAtMs > 0` (an unstarted entry falls back to now). A paused interval whose pause outlasted the target (paused, then expired in the pause) folds the final pause as before and then caps at start + pauses + target.
3. Settings changing while open: none.
4. Time: a clock set back (cap after now) falls back to now (S-24104). DST irrelevant (instants).
5. Cost: none.
6. Words: none.
7. Slot competition: `recordRestStart` keeps its once-per-entry rule; `finishTimedEntry` is awaited before the rest is recorded (D-3), so the stored `finishedAtMs` is the one read.

## Phases

1. **P1 lead**: the production edits (already applied: D-1..D-4).
2. **P2 builder-app**, scope `test/expired_interval_records_its_real_end_test.dart` (new). No full suite.
3. **P3 lead**: mutation pass, docs, full suite.

## Readers

All files of `grep -rlE "finishTimedEntry|recordRestStart|completeRound" test` (62 files) were run by the lead after the edits: green (the one red line of that run was a helper file that matched the grep, not a test). A reader that pins an expired interval's `actualDurationSecs` to the wall elapsed time is reported, not edited.

## Mutation list (lead)

(a) the cap removed (`endMs = now` always: S-24101, S-24103, S-24106); (b) the parameter ignored when absent but capped always (S-24102); (c) the cap without the now check (S-24104); (d) `atMs` ignored (S-24105); (e) a future `atMs` honoured (S-24105); (f) the restore path calls `finishTimedEntry` without the parameter (S-24106); (g) the restore path finishes every active interval (S-24107). The tick path (D-3) cannot be exercised deterministically (a widget test's clock does not move wall time), so its wiring is shown by reading and by D-1/D-2 being the same calls as D-4; it is listed in open item 2.

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| `docs/state_management/workout_state.md` | ADDED | - | An entry that ran out by itself passes `expiredAfterSecs` | S-24101, S-24103 |
| `docs/rest_tracking.md` | ADDED | - | `atMs` is the instant the rest really began | S-24105 |

Stale-term sweep: `grep -rIn "restStartMs = now\|current epoch time as" docs` outside plans/history/releases: `workout_state.md:304`, `rest_tracking.md:160` get the same clause (the lead edits them in the rows above).

## Open items

1. (owner) The in-app alert sound a late-noticed expiry plays on unlock duplicates the notification that sounded at the real end. Suppressing it when the expiry is more than a couple of seconds old is a behaviour change (it would silence the only alert if notifications are off): not made here.
2. The tick path's wiring (D-3) has no deterministic test; (owner) check on a device: start a 1-minute hold, lock the phone for 5 minutes, unlock: the hold shows 60 s and the rest chip shows about 4 minutes.

## Predicted files

`timer_manager.dart` (+30), `workout_state.dart` (+12), `workout_session_timer_mixin.dart` (+40), one new test file (~260), two docs.

## Progress

- [x] Seeded
- [x] Production edits (lead)
- [x] P2 tests
- [x] Mutation pass, docs
- [x] Full suite (+7978 ~4 green, analyze 181)

## Assumption Log

- 2026-11-18: base commit in `.work/crew/2026-11-18-241/base.txt` (b7aff1ed); another session's files (stats gallery test, plan 208) are outside this plan.
- 2026-11-18: ids S-241xx: none found.

## Feedback

(none yet)
