# Plan 233 — A workout screen opened while an interval is running counts it

Series: nutrition/calendar/summary pre-launch review (2026-11-16, third pass), proven item "a workout screen opened while an interval/hold/round is already running shows it frozen at the time of opening with a Log button and no ticker; started on the same screen it counts" (hits back-to-Home-and-return and app restart mid-run). Phone only (`lib/features/session`), one builder run, then docs. Status: COMMITTED (built, mutation-checked (adopt removed killed by S-23301 and S-23302; adopt-before-restore survives as an equivalent order); one reader fixed (S-4408 premise, below); docs applied; full suite pending.

## Goal and acceptance

`_loadExercises` restores the timer UI of a freshly opened session screen with `_restoreTimerStateFromPersisted` (`workout_session_screen.dart:~634`). For an interval stored as running (`TimedState.active` / `RoundState.active`) it sets the elapsed seconds and `_effortRunning[key] ??= false`, and adds the in-progress key, but starts no ticker: the digits stand still and the running flag is false. The code that does start the ticker, flag and expiry notification, `_adoptRunningTimerState` (`workout_session_timer_mixin.dart:250`), runs only on a watch-driven resync (`_resyncExercisesFromState`). So leaving the screen (Back to Home) and returning, or relaunching the app mid-interval, shows a frozen interval. After this change the freshly loaded screen adopts every running interval the way the watch path does.

Acceptance: S-23301..S-23304 green, those marked "fails without" red at the base commit; readers green or reported; `flutter analyze` at baseline (181, 0 errors); full suite no new red.

## What the user sees

- Start a timed interval, hold or round, press Back to Home, open the workout again: the interval keeps counting (the digits move, the running controls show) instead of standing still. Same after relaunching the app mid-interval.
- A paused interval still opens paused; a finished or never-started one is unchanged; an interval that already ran out while the screen was away still finishes as today.
- To SEE it: start a 5 minute interval, Back to Home, reopen the workout.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-1 | In `_loadExercises`, inside the same `setState` block, right after `_restoreTimerStateFromPersisted(_exercises);`, call `_adoptRunningTimerState();`. It starts the ticker, sets `_effortRunning = true`, keeps the in-progress key and schedules the expiry notification for each `active` interval, skips an interval whose ticker is already live (a re-run of the load after add/remove set keeps its ticker), and sets a paused interval's elapsed without a ticker. | `workout_session_screen.dart:634-636`, `workout_session_timer_mixin.dart:250-326` |
| D-2 | `_restoreTimerStateFromPersisted` is unchanged: it still finishes an expired interval and seeds the elapsed/target values the adopt step reads. | `workout_session_timer_mixin.dart:132-208` |
| D-3 | The expiry notification the adopt step schedules uses `playSound: !_isAppInForeground`, the same call the watch path makes; no new notification behaviour. | `workout_session_timer_mixin.dart:306-313` |
| D-4 | Edit mode (`editMode: true`) opens a finished workout, which holds no active intervals after `endSession` persists them; no special case. | `session_core_lifecycle.dart` end path |

## Scenarios

| ID | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-23301 | Screen test, Mock only (copy the harness of `test/watch_timer_adoption_screen_test.dart`, but start the interval on the PHONE state: a timed exercise, `startTimedEntry(effortId, 0)` with the instance's start stamp 40 s in the past, then mount `WorkoutSessionScreen`, `initialFocusId` the effort). | after the mount: the running control (`Log Interval`) is shown, the digits (`count-up-digits`) read `00:4x`, and after `pump(Duration(seconds: 3))` no exception; the screen's ticker is live (the in-progress lock holds: starting another interval is refused as in S-6123). | the base shows the stored time with `_effortRunning` false and no ticker |
| S-23302 | The same for a round (`startRound`, planned 120 s, started 30 s ago): the countdown ring runs (copy the S-6122 assertions: `TimerRing`). | ring running, remaining about 90 s. | same |
| S-23303 | A paused interval: stored paused with 20 s elapsed. | opens paused with `00:20` and no running control. | passes both ways on purpose (mutation: the adopt step starts a ticker for paused ones) |
| S-23304 | An interval stored active whose target already ran out (planned 30 s, started 60 s ago). | finished as today (the base finishes it through `_restoreTimerStateFromPersisted`): no running control, no ticker. | passes both ways on purpose (mutation: the adopt step runs before the expiry check) |

## Input-reality checklist

1. Writers and units: the stored instance holds the start stamp; elapsed is derived from the wall clock at read time (`elapsedMs`), so the adopted ticker starts from the right second.
2. Lifecycle: the load runs on mount and after structural edits; a ticker already live is skipped (D-1), so no double ticker; `dispose` cancels the timers as today (`_cancelAllTimers`).
3. Settings changing while open: none.
4. Time: the expiry notification is scheduled for the remaining time; an already expired interval is finished before the adopt step (S-23304).
5. Cost: one pass over the displayed intervals.
6. Words: none.
7. Slot competition: the watch path and this path both call the same method; it is idempotent (skips a live ticker).

## Phases

1. **P1 builder-app**, scope `lib/features/session/workout_session_screen.dart`, `test/open_screen_mid_run_keeps_timer_test.dart` (new). No full suite.
2. **P2 lead**: docs, mutation pass, full suite.

## Readers

`grep -rln "_restoreTimerStateFromPersisted\|TimerRing\|count-up-digits\|Log Interval" test`: the timer screen tests (`watch_timer_adoption_screen_test`, `round_countdown_screen_test`, `in_progress_work_timers_test`, `stale_watch_timer_adoption_test`, `wrist_pause_resume_adoption_test`). A reader that pins a frozen interval on open is reported, not edited.

## Mutation list (lead)

(a) the adopt call removed; (b) the adopt call placed before the restore; (c) adopt starts a ticker for paused too (S-23303); (d) adopt ignores a live ticker (double ticker: only observable if a test re-runs the load; reported if it survives).

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| `docs/state_management/services_and_utils.md` | ADDED | - | On a freshly opened screen `_adoptRunningTimerState` then starts the ticker | S-23301, S-23302 |

Stale-term sweep: `grep -rIn "restoreTimerState\|adoptRunningTimerState" docs` outside plans/history/releases: `watch_session_capture.md:460` and `watch_surface.md:356` describe the watch path and stay true.

## Reader changed by the lead

`test/round_countdown_screen_test.dart` S-4408 started round 2 and recorded its rest, then expected the rest strip beside a running round; that only held because a reopened screen froze the running round (the overlay rule hides the strip while any effort runs). The fixture now leaves round 2 waiting with its rest open (the state a finished round actually leaves) and asserts the `Start` button instead of `Log Round`; the layout assertions are unchanged.

## Open items

1. (owner) Start a 5 minute interval, Back to Home, reopen: it keeps counting.
2. A round that ends while the phone is locked replays its alert on unlock (review, read only): not in this plan.

## Predicted files

`workout_session_screen.dart` (+3), one new test file, one doc.

## Progress

- [x] Seeded
- [x] P1 build
- [x] Docs, mutation pass
- [x] Full suite (+7914 ~4 green, analyze 181)

## Assumption Log

- 2026-11-17: base commit recorded when the build starts; other sessions' files are outside this plan.
- 2026-11-17: ids S-233xx: none found.

## Feedback

(none yet)
