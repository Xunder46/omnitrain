# Plan 230 — "Start New Session?" really discards the running workout

Series: nutrition/calendar/summary pre-launch review (2026-11-16), the second "critical" item. Owner rule 2026-11-17: starting a new workout over a running one asks for confirmation of a destructive action; the user either discards it or goes back. Phone only (`lib/state/workout`, `lib/features/home`, `lib/features/routine`, `lib/features/calendar`), one builder run, then docs. Status: COMMITTED (built, mutation-checked (7 of 7 killed; three screen tests S-23007..S-23009 added by the lead), docs applied; full suite pending.

## Goal and acceptance

Five start paths already ask `Start New Session?` ("Your current session will be discarded and cannot be recovered."), but after the user confirms they only empty the in-memory slot (`clearSession`): the old workout stays stored and open. Probe 2026-11-17 (Mock): confirm Start New, finish the new workout, relaunch: `checkForInProgressSession` finds the old workout again and Home restores it as the running workout. The prompt's promise is false. After this change a confirmed Start New deletes the old workout from the store (the same delete as the session screen's Discard button), so it is gone for good and nothing comes back at launch.

Acceptance: S-23001..S-23009 green, those marked "fails without" red at the base commit; readers green or reported; `flutter analyze` at baseline (181, 0 errors); full suite no new red.

## What the user sees

- Running workout, tap another start (Home modality tile, Free Training, Routines, a routine's Start, a planned session on the calendar): the same prompt as today; Cancel changes nothing; confirming discards the old workout for real. Finish the new workout, relaunch the app: no old workout comes back.
- Nothing else changes: no prompt text changes, no new prompt.
- A finished session that happens to be open in the slot (a past summary) is never deleted by a start.
- To SEE it: start a workout, log a set, start another one from Home and confirm, finish it, kill and reopen the app.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-1 | `SessionCore` gains `Future<void> discardUnfinishedSession()`: when the current session exists and has no end (`endedAtMs == null`) it calls `discardCurrentSession()` (the real delete, health delete included, plan 89 D-4); otherwise it calls `clearSession()` (a finished session viewed in the slot is only released, never deleted). | `session_core_lifecycle.dart:269`, `clearSession` |
| D-2 | `WorkoutState.discardUnfinishedSession()` forwards. | `workout_state.dart` |
| D-3 | The five start paths replace their memory-only clear with `await widget.workoutState.discardUnfinishedSession()` AFTER the confirmation (never before it, so Cancel loses nothing): `home_screen.dart` line ~686 (routine tile, before opening My Routines), ~773 (modality tile), ~909 (`_startFreeSession`); `day_session_list_screen.dart` `_tapPlanned` (~275); `my_routines_screen.dart` `_startRoutine` (after its confirmation and before `createNewSession`, where nothing cleared the slot before). | caller grep |
| D-4 | Launch-time `checkForInProgressSession` (newest restored, older deleted) is unchanged. A workout that is open and empty (the tile was tapped, nothing added) is also discarded by the new call: it was equally dangling before. | `workout_state.dart:568` |
| D-5 | The prompt texts and keys do not change. | owner |

## Scenarios

| ID | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-23001 | State test, both harnesses. R open with a logged set; `discardUnfinishedSession()`; `createNewSession` N with a logged set; end N; a fresh `WorkoutState` over the same repo calls `checkForInProgressSession()`. | `repo.getSession(R)` null; `checkForInProgressSession` null. | the base's `clearSession` leaves R stored open: relaunch finds R (probe) |
| S-23002 | A finished session A loaded into the slot (`loadHistoricalSession`); `discardUnfinishedSession()`. | `currentSession` null and A still stored, still ended. | passes both ways on purpose (mutation: the call always deletes) |
| S-23003 | No current session; `discardUnfinishedSession()`. | no error, nothing thrown. | passes both ways on purpose |
| S-23004 | Screen, Mock only: `DaySessionListScreen` with a running workout and a planned session today: tap the plan, Cancel in the prompt. | the running workout is still current and stored. | passes both ways on purpose (mutation: the discard runs before the prompt) |
| S-23005 | Same, Confirm. | the old session is not in the store (`getSession` null); a new session is current. | the base leaves the old one stored |
| S-23007 | Screen, Mock only: Home Routines tile over a running workout, Confirm (`home-routine-open-confirm`). | old row gone. | the base leaves it stored |
| S-23008 | Home Free tile over a running cardio workout, Confirm then Start Session. | old row gone, new current. | same |
| S-23009 | `MyRoutinesScreen` routine Start, Confirm (`routine-start-new-confirm`). | old row gone, new current. | same |
| S-23006 | Screen, Mock only, if a Home harness exists (`grep -rln "HomeScreen(" test`): modality tile over a running non-rolling workout, Confirm (`home-modality-change-confirm`). If none is cheap, a `MyRoutinesScreen` routine Start (`routine-start-new-confirm`) instead; report which. | the old session is gone from the store. | the base leaves it stored |

## Input-reality checklist

1. Writers and units: `discardCurrentSession` deletes the session row and its rests with it; the wrist may hold a mirror of the running workout: the same delete the Discard button performs, so the wrist is told by the existing path.
2. Lifecycle: the delete runs after confirmation and before the new session is created, so a failing delete leaves an error and the old workout intact (`discardCurrentSession` sets the error and returns); the start then continues in memory as before. Accepted; no new failure mode beyond today's.
3. Settings: none.
4. Time: none.
5. Cost: one delete.
6. Words: none.
7. Slot competition: the viewing path of plan 229 sets a remembered id; a start after viewing finds a finished session in the slot and only releases it (D-1).

## Phases

1. **P1 builder-app**, scope `lib/state/workout/session_core.dart` is NOT needed; `lib/state/workout/session_core_lifecycle.dart`, `lib/state/workout/workout_state.dart`, `lib/features/home/home_screen.dart`, `lib/features/calendar/day_session_list_screen.dart`, `lib/features/routine/my_routines_screen.dart`, `test/start_new_really_discards_test.dart` (new, S-23001..S-23003), `test/start_new_really_discards_screen_test.dart` (new, S-23004..S-23006). No full suite.
2. **P2 lead**: docs, mutation pass, full suite.

## Readers

`grep -rln "clearSession\|Start New Session\|start-new-confirm\|home-modality-change" test`. A reader that pins the old workout staying stored after a confirmed Start New is reported, not edited.

## Mutation list (lead)

(a) a call site back to `clearSession()` (five mutants, one per site); (b) the helper always clears; (c) the helper always deletes (S-23002); (d) the discard runs before the prompt (S-23004).

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| `docs/state_management/workout_state.md` | ADDED | - | `discardUnfinishedSession()` | S-23001 |
| `docs/modality_based_exercise_ui.md` | MODIFIED | `Changing modality will start a new session. Current session will not be saved.` | `Your current session will be discarded and cannot be recovered.` | S-23006 |
| `docs/modality_based_exercise_ui.md` | MODIFIED | `End current session, create new session, navigate to new session` | `the running workout is deleted from the store` | S-23005, S-23006 |

Stale-term sweep: `grep -rIn "Start New Session\|cannot be recovered\|clearSession" docs` outside plans/history/releases; each hit is a row.

## Open items

1. (owner) Start a workout, log a set, start another from Home, confirm, finish it, relaunch: the old workout does not come back.
2. The routine tile on Home discards the running workout when the user confirms and opens My Routines, even if they then leave without starting a routine; the prompt says it will be discarded (accepted).

## Predicted files

`session_core_lifecycle.dart` (+14), `workout_state.dart` (+4), three screens (+2 each), two new test files, two docs.

## Progress

- [x] Seeded
- [x] P1 build
- [x] Docs, mutation pass
- [x] Full suite (+7892 ~4 green, analyze 181)

## Assumption Log

- 2026-11-17: base commit in `.work/crew/2026-11-17-230/base.txt`; other sessions' files are outside this plan.
- 2026-11-17: owner clarified the rule after seeing the prompt exists; probe shows the discard half is the defect.
- 2026-11-17: ids S-230xx: none found (grep before building).

## Feedback

(none yet)
