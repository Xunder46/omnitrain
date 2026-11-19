# Plan 251 — Finishing a routine on its planned day completes the plan

Review item 14 (owner list: "Plans complete only when started from the calendar day list or the watch. Suggested: starting the same routine on the planned day completes the plan").
Phone only. No wire, watch, storage or schema change.

## Goal and acceptance

Today a planned routine session is marked done only when the workout was started from its row on the calendar day list or from the watch. A user who plans "Push day" for Thursday and then starts Push day from the Routines list (or from Home) finishes it and the plan stays "Planned" forever.

After this change: when a workout that was started from a routine is finished (Finish stores it), the app looks for an unstarted plan for THE SAME ROUTINE on THE DAY THE WORKOUT STARTED and marks it completed and linked to that workout, exactly like the day-list path does.

- Same routine and same day only. A plan for another routine, another day, a free-training plan (no routine) and a workout with no routine are untouched.
- A plan that is already completed or already linked to a workout is never taken again.
- Two unstarted plans for the same routine on that day: the one created first is completed, the other stays planned.
- Starting from the day list or the watch behaves as before (their own link still runs; when it names the same plan it is the same write).
- A failed lookup never fails the Finish.

Acceptance: S-25101..S-25107 green, the "fails without" ones red at the base commit; `flutter analyze` not above 178 issues, 0 errors; no new red in the full suite against the base failing set; Docs delta applied.

## What the user sees

- Plan Push day for today. Start Push day from My Routines, finish it: the calendar shows the plan completed, linked to the workout, as if started from the day list.
- Start Pull day the same day: the Push plan is not touched. A plan for tomorrow is not touched.
- To SEE it: plan a routine for today, start it from the Routines list, Finish, open the calendar day.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-25101 | `WorkoutState` and `SessionCore` get a constructor callback `Future<void> Function(TrainingSession session)? onSessionEnded` (same pattern as `afterPendingWristImports`). `SessionCore.endSession` calls it once, after the end is stored and the active-energy settle ran, inside its own `try`/`catch` (a throw is swallowed: the end is never turned into an error), only on the path that actually ended the session (an already-ended session returns before). | `session_core_lifecycle.dart:18-100`, `session_core.dart:135-153`, `workout_state.dart:60-90` |
| D-25102 | `CalendarState.completePlanFor(TrainingSession session)`: returns when `session.routineTemplateId` is null or when any stored plan is already linked to `session.id`; otherwise takes the stored plans that are not completed, have no `linkedSessionId`, have `routineTemplateId == session.routineTemplateId` and whose day equals the day of `session.startedAtMs` (both as `OmniDateUtils.startOfDayMs(OmniDateUtils.fromMs(ms))`, the calendar's own key), sorts them by `createdAtMs` then id, and calls `completePlannedSession(first.id, session.id)`. | `calendar_state.dart:30-50,259-292` |
| D-25103 | `lib/main.dart` wires `onSessionEnded: calendarState.completePlanFor` into the `WorkoutState` constructor (the calendar state already exists there, `onPlanStarted: calendarState.completePlannedSession` is its neighbour). | `main.dart:395-425` |
| D-25104 | Free-training plans (modality only, no routine) are not matched (open item 1). The day-list path keeps linking the plan the user tapped when the summary opens (`onSessionSaved`), which runs after this hook: with two plans for one routine on one day the hook links the first and the day-list link then also links the tapped one (open item 3). | `day_session_list_screen.dart:315` |

## Scenarios

Fixtures. Clock `DateTime(2026, 11, 18, 10)` for the `WorkoutState` (`clock:`) so "today" is Nov 18; routines `tpl-push` and `tpl-pull` (`WorkoutTemplate`, written with `repo.createTemplate`); plans written with `repo.createPlannedSession` (`PlannedSession`, `scheduledDateMs: OmniDateUtils.startOfDayMs(DateTime(2026, 11, 18))` for today, `createdAtMs` set explicitly). `final calendar = CalendarState(repo); await calendar.init();` then `WorkoutState(repo, clock: ..., onSessionEnded: calendar.completePlanFor)`. A workout: `await state.createNewSession(modality: Modality.resistanceLifting, routineTemplateId: 'tpl-push', intent: 'routine', includeDefaultSegment: false)` (see `lib/features/routine/my_routines_screen.dart` for the call), then `await state.endSession(writeToHealth: false)`. Plans read back with `repo.getPlannedSessions()`. Mock AND Hive through `harnessFactories`; plain `test()`.

| ID | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-25101 | plan P1 for `tpl-push` today; the workout is `tpl-push`; end it | P1 `isCompleted` true, `linkedSessionId` equals the session id | nothing links it |
| S-25102 | plans for `tpl-push` on Nov 17 and on Nov 19; the workout started today | both untouched (not completed, no link) | a day check missing would link a wrong day |
| S-25103 | plan for `tpl-pull` today and a free plan (modality only) today; the workout is `tpl-push`; and a second workout with no routine | all plans untouched | a routine check missing |
| S-25104 | a completed plan for `tpl-push` today (linked to `s-old`) and an unstarted one P2 | P2 is linked, the completed one is unchanged (still `s-old`) | a started plan would be linked again |
| S-25105 | two unstarted `tpl-push` plans today, A (`createdAtMs` 1000) and B (`createdAtMs` 2000), B written first | A is linked, B untouched | order not defined |
| S-25106 | plan P1; call `state.endSession` twice | P1 linked to the session once; no second write (its `updatedAtMs` unchanged by the second call) | a second call would write again |
| S-25107 | `onSessionEnded` throws; plan P1 | `endSession` completes: the stored session has `endedAtMs`, `state.error` is null, P1 untouched | a throw would turn the end into an error |

## Input-reality checklist

1. Writers: plans are written by the day-list form and by `completePlannedSession` (day list, watch bridge, this hook); sessions by `createNewSession` and `endSession`. Units: day keys (local midnight ms), ids.
2. Lifecycle: a plan deleted mid-workout leaves no match (the hook finds nothing); a routine deleted after the plan leaves the plan's `routineTemplateId` dangling but still equal to the session's.
3. Settings: none read.
4. Time: the day is the day the workout STARTED (a workout started 23:50 and finished 00:20 completes the plan of the day it started); a zone change keeps the calendar's own day key logic (plan 235).
5. Cost: for a routine workout, one `getPlannedSessions` read in `completePlanFor`; when a plan matches, `completePlannedSession` reads the plans again, writes one row and reloads the month; nothing for a workout without a routine.
6. Words: no new copy.
7. Competition: the day-list and watch paths link their own plan (D-25104, open item 3); the wrist's end also runs `endSession` on the phone: the hook then finds the plan the wrist named and the bridge's own link no-ops on an already completed plan.

## Phases

1. **P1 builder-app**, scope `lib/state/workout/session_core.dart`, `lib/state/workout/session_core_lifecycle.dart`, `lib/state/workout/workout_state.dart`, `lib/state/calendar/calendar_state.dart`, `lib/main.dart`: D-25101..D-25103 (exact code in the brief). No full suite.
2. **P2 builder-app** (after P1), scope `test/plan_completes_on_routine_finish_test.dart` (new): S-25101..S-25107.
3. **P3 lead**: readers set, full suite against the base failing set, analyze, mutation pass, docs, reviewer.

## Readers

`test/state_test.dart` (WorkoutState constructor, `endSession`), `test/calendar_*` tests (CalendarState), `test/watch_*adoption*` tests that end sessions and link plans (grep `onPlanStarted`), `test/start_new_really_discards_screen_test.dart`, `test/planned_routine_calendar_modality_test.dart`, `test/screen_widget_test.dart`; every `WorkoutState(` caller keeps compiling (the new parameter is optional).

## Mutation list (lead)

(a) the hook not called from `endSession` (S-25101); (b) day check removed (S-25102); (c) routine check removed (S-25103); (d) completed plans not skipped (S-25104); (e) first plan chosen by write order, not `createdAtMs` (S-25105); (f) the already-linked guard removed (S-25106); (g) the hook's throw not caught (S-25107); (h) the day taken from the end time, not the start (S-25108 below).

Scenario S-25108 (added for (h)): a workout started 2026-11-18 23:50 and ended 2026-11-19 00:20 (state clock moved between) completes the Nov 18 plan, not a Nov 19 plan.

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| `docs/calendar_periods.md` | MODIFIED | linked via `linkedSessionId`. | linked via `linkedSessionId`. A routine workout started anywhere else (the Routines list, Home) completes the unstarted plan for the same routine on the day it started when it is finished (`completePlanFor`: the first created when there are several; free-training plans are not matched). | S-25101, S-25105 |

The lead applies the row by script (one sentence, CRLF file). Stale-term sweep (lead): `grep -rIn -i "originating .PlannedSession\|only when started from" docs` outside plans, history, releases.

## As built

Three scenarios were added after the lead's mutation pass: S-25109 (a plan that is linked but not completed is skipped), S-25110 (a plan that is completed but not linked is skipped), S-25111 (a plan already linked to the workout being ended stops the hook from taking a second one). The review's cost note (two reads) is in the checklist above.

## Open items

1. (owner) Free-training plans (a modality, no routine) are not completed by a matching free workout.
2. (owner) A plan completes when the workout is FINISHED (stored), not when it starts; a discarded workout never completes a plan.
3. With two plans for the same routine on one day, started from the day list: the first-created one is completed at Finish and the tapped one at the summary (both link the same workout).
