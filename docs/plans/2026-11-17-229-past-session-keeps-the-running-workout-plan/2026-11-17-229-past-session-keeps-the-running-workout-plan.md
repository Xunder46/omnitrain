# Plan 229 — Opening a past session never loses the running workout

Series: nutrition/calendar/summary pre-launch review (2026-11-16), the first of the two "critical" items (memory `nutrition-calendar-summary-prelaunch-review-2026-11-16`). Phone only (`lib/state/workout`, `lib/features/calendar`), one builder run, then docs. Status: COMMITTED (built, mutation-checked (8 of 8 killed after S-22908 was added), docs applied; full suite pending.

## Goal and acceptance

Tapping a finished session on the calendar (a past day, or a completed row in the day list) loads it into the one in-memory session slot the whole app shares. While a workout is running, that replaces it: `hasActiveSession` turns false, and after the summary closes there is no running workout until the app is relaunched (probe 2026-11-17: viewing a past session left `hasActive=false`; loading the running session again restored its exercises, entries and rests intact). After this change the running workout is put back when the summary is closed.

Acceptance: S-22901..S-22907 green, those marked "fails without" red at the base commit; readers green or reported; `flutter analyze` at baseline (181, 0 errors); full suite no new red.

## What the user sees

- A workout is running. Open Calendar, tap a finished session, read the summary, go back: the running workout is exactly where it was (same exercises, sets, logged rests); the Home "active workout" state is unchanged. Today it is gone.
- Nothing else changes: with no workout running the calendar behaves as before.
- To SEE it: start a workout, log a set, open Calendar, open any past session, go back, open the workout screen.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-1 | `SessionCore` gains a field `String? _suspendedLiveSessionId` and `Future<void> viewHistoricalSession(String sessionId)`: when the current session is open (`endedAtMs == null`) and is not the one being viewed, its id is remembered, then `loadHistoricalSession` runs. A viewed session that is itself ended never overwrites a remembered id (viewing two past sessions in a row keeps the running one). | `session_core_io.dart:73-130`, probe |
| D-2 | `Future<void> resumeSuspendedLiveSession()`: clears the remembered id; does nothing when none; does nothing when the stored session is gone or has ended (the wrist ended it, or the user discarded it); does nothing when the current session is now an open one (the watch adopted another workout meanwhile); otherwise `loadHistoricalSession(id)`, the same path the app uses to restore a running workout at launch. | `home_screen.dart:186-189` |
| D-3 | Only the two calendar entry points use the new pair: `_openSessionSummary` (`calendar_screen.dart:194`) and `_tapCompleted` (`day_session_list_screen.dart:230`) call `viewHistoricalSession`, await the summary route, then call `resumeSuspendedLiveSession`. Home's launch restore and the wrist adoption bridge keep `loadHistoricalSession` unchanged (so a stale remembered id can never be created by them). | callers grep |
| D-4 | `WorkoutState` forwards both methods. | `workout_state.dart:223` |
| D-5 | The second critical item (Start New over a running workout leaves the old one stored and open) is a different cause and an owner call (discard or finish the old one): not in this plan. | review memory |

## Scenarios

| ID | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-22901 | State test, both harnesses. A finished session A; a running session R with two sets (one logged: rest at 1) and an open rest. `viewHistoricalSession(A)`, then `resumeSuspendedLiveSession()`. | after the view: current is A, `hasActiveSession` false. After the resume: current is R, `endedAtMs` null, `hasActiveSession` true, two entries, the rest cache holds R's rest. | the base has no way back: after viewing, R is gone from memory (probe 2026-11-17) |
| S-22902 | No running workout (current is a finished session B or none). `viewHistoricalSession(A)`, `resumeSuspendedLiveSession()`. | current stays A, no error. | passes both ways on purpose (mutation: the resume always loads something) |
| S-22903 | R running; `viewHistoricalSession(A)`; R is ended in the store meanwhile (`endSession` on another state over the same repo, or `updateSession` with an end); resume. | current stays A, no error, nothing reloaded. | a resume that does not check the stored session reloads an ended session as the "running" one |
| S-22904 | R running; view A, then view B (another finished session); resume. | current is R. | an overwrite of the remembered id by the second view loses R |
| S-22905 | R running; view A; the adoption path makes another open session C current (`createNewSession`); resume. | current stays C; R is not loaded over it. | a resume without the open-current check replaces C |
| S-22906 | Screen test, Mock only: a running workout, a finished session on a past day; `CalendarScreen` tap that day (single completed entry) -> summary opens -> pop. | `workoutState.currentSession!.id` is the running session's, `endedAtMs` null. | the base leaves the past session loaded |
| S-22907 | Screen test, Mock only: the same through `DaySessionListScreen` tapping the completed row. | same. | same |

## Input-reality checklist

1. Writers and units: `loadHistoricalSession` reads only; the running session's rows were persisted as logged (set values, rests), so the reload reads them. A rest still open at view time is read back open from its stored row; a timer's elapsed time derives from stored stamps.
2. Lifecycle: the summary route may close by Back, by the app's Done action or by an Edit round-trip; the resume runs after the route future completes in every case. An app kill while viewing leaves the running session stored and open: the launch restore finds it as today.
3. Settings changing while open: none.
4. Time: a long view loses nothing: the running session's clock is stored stamps.
5. Cost: one extra session read on return.
6. Words: none.
7. Slot competition: the shared slot is still one; the pair serialises view and resume. The wrist adopting another session while viewing is covered by S-22905.

## Phases

1. **P1 builder-app**, scope `lib/state/workout/session_core.dart`, `lib/state/workout/session_core_io.dart`, `lib/state/workout/workout_state.dart`, `lib/features/calendar/calendar_screen.dart`, `lib/features/calendar/day_session_list_screen.dart`, `test/past_session_keeps_running_workout_test.dart` (new, S-22901..S-22905), `test/past_session_keeps_running_workout_screen_test.dart` (new, S-22906, S-22907). No full suite.
2. **P2 lead**: docs, mutation pass, full suite.

## Readers

`grep -rln "loadHistoricalSession\|openedFromCalendar\|DaySessionListScreen\|CalendarScreen" test`. A reader that pins the past session staying loaded after the summary closes is reported, not edited.

## Mutation list (lead)

(a) resume removed from `_openSessionSummary`; (b) resume removed from `_tapCompleted`; (c) the id is overwritten by every view; (d) no stored-session check; (e) no open-current check; (f) the id is never cleared (a second resume reloads); (g) `viewHistoricalSession` never remembers.

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| `docs/state_management/workout_state.md` | ADDED | - | `viewHistoricalSession(sessionId)` | S-22901 |
| `docs/calendar_periods.md` | ADDED | - | the running workout is put back when the summary closes | S-22906, S-22907 |

Stale-term sweep: `grep -rIn "loadHistoricalSession" docs` outside plans/history/releases; the `widget_catalog.md:22` and `rest_tracking.md:153` mentions stay true (launch restore, cache load).

## Open items

1. (owner) Start a workout, log a set, open a past session from the calendar and go back: the workout is still running.
2. Start New over a running workout (Home, Routines, day-list plan) leaves the old one stored and open and restores it at the next launch: an owner call, plan 230 candidate.
3. A timer running in the workout while the summary is open keeps its stored stamps; a running interval's UI ticker restarts on return (same as a relaunch).

## Predicted files

`session_core.dart` (+4), `session_core_io.dart` (+35), `workout_state.dart` (+6), two calendar screens (+8 each), two new test files, two docs.

## Progress

- [x] Seeded
- [x] P1 build
- [x] Docs, mutation pass (S-22908 added by the lead: a spent resume reloads nothing)
- [x] Full suite (+7880 ~4 green, analyze 181)

## Assumption Log

- 2026-11-17: base commit in `.work/crew/2026-11-17-229/base.txt`; other sessions' files (plans 223/225/208, watch Swift, gallery test) are outside this plan.
- 2026-11-17: ids S-229xx: none found in `test/`, `docs/`, `watch/`.
- 2026-11-17: the owner said "proceed to the next plan" with the Stats list finished; this is the top item of the open 2026-11-16 review ("two running-workout bugs"), taken as the lead's technical call because no product choice is involved (the running workout should survive).

## Feedback

(none yet)
