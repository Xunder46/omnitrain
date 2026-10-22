# Feature: 51g — the phone stops pinging a rest the watch ended

> Status: BUILT, PROVED AND REVIEWED 2026-10-21 (review APPROVE in the 51a plan's review file). Four new tests; mutation pass (line removed, cancel-only, schedule-only) red then restored; full flutter +5416 ~2. Pings with the phone in a pocket is an owner check. Seeded 2026-10-21 (owner, in chat: "include the phone fix that cancels the rest notifications when the watch ends a rest", an explicit exception to "no mobile changes"). Split out of plan 51a by the scope guard (two tracks and four phases). Not built. Base commit: the commit at build time. Team: the crew (`crew-builder-app`). Facts: re-audit `.work/crew/2026-10-21-51-watch-reaudit/scout-restfood.md` (a scout NOTICED line about the double alert, checked by the lead against the code on 2026-10-21).
> Series: 51g of the 51 series listed in `docs/plans/2026-10-21-51a-wrist-crown-and-layout-plan/2026-10-21-51a-wrist-crown-and-layout-plan.md`. Binding conventions: docs/global_conventions.md; docs/rest_tracking.md; .github/copilot/pr-scope-budget.md.

## Goal and acceptance

| What you do | Now | After 51g |
|---|---|---|
| The phone is in your pocket (app in the background) with a rest running; you press Next on the watch | the phone's rest chip stops, but the rest pings the phone scheduled for that rest stay scheduled and keep buzzing | the pings are cancelled |
| Same, and the watch opens the next rest at the same moment (a set logged on the watch) | the old rest's pings stay | the pings follow the NEW rest's start |
| The phone's own Next, log or pause | unchanged | unchanged |

## Decision Ledger

- D-1 `lib/features/session/workout_session_screen.dart` `_onWorkoutStateChanged` (`~:336-340`, the branch that runs `_resyncExercisesFromState()` when `watchRefreshRevision` moved): add one call to the existing `_scheduleActiveRestNotifications()` (`:343`) right after it. That helper already cancels when no rest is open (`restKey == null` and `openRest == null` arms) and reschedules from the open rest's own `restStartMs` otherwise. Reason: pings are scheduled only when the app goes to the background (`didChangeAppLifecycleState`, `:276-281`) or on a settings change (`:285-288`); a rest the watch ends reaches the phone through `WorkoutState.refreshEfforts` (`lib/state/workout/session_core_io.dart:218-262`, which reloads the efforts' rests and bumps `watchRefreshRevision`), and nothing on the screen turned that into a notification change.
- D-2 Cost accepted: one cancel plus reschedule (up to `maxRestPings` = 50 platform calls) per watch resync while a rest is open; a resync happens at human rate (a wrist log, a timer).
- D-3 Not in scope: the wrist's own pings, the rest chip, the importer, the wire, de-duplicating a phone ping against a wrist ping when both devices are in use (the Rest Ping setting sets both; a product question for later).

## Readers listed

- `_scheduleActiveRestNotifications` callers: `workout_session_screen.dart:280, :287`; the fake `test/helpers/fake_rest_notification_service.dart` (`scheduled`, `cancelCallCount`) is the double every screen test passes. Before building, grep the existing tests that count `cancelCallCount` or `scheduled` after a watch resync (`test/watch_timed_fill_screen_test.dart`, `test/watch_live_refresh_screen_test.dart`, `test/rest_timer_*`, `test/rest_notification_service_test.dart`) and list any whose count this changes.

## Core scenarios (ids S-7521.. checked free in `test/`, `docs/`, `watch/`)

`test/rest_pings_watch_end_test.dart` (new; the harness is a copy of the named helper block in `test/watch_live_refresh_screen_test.dart`: shipping-graph wiring, mock repository, `FakeRestNotificationService`; the test never awaits a real `Future.delayed` inside `testWidgets`):
- S-7521 a phone-logged set leaves an open rest; the app goes to the background (`tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused)`), the fake holds one schedule; the wrist ends the rest (the repository row gets `restEndMs`, then `workoutState.refreshEfforts([effortId])`): `cancelCallCount` rises by exactly one and no new schedule is recorded.
- S-7522 the wrist ends the rest AND the next rest is open (second row, a start unlike the first's): the fake's last schedule carries the NEW rest's `restStartMs`.
- S-7523 a watch resync with the same rest still open schedules again from that rest's own start (the new schedule's `restStartMs` equals the old one).
- S-7524 a resync with no rest ever open cancels and never schedules.

## Phases

- P1 (`crew-builder-app`, `--scope "lib/features/session/workout_session_screen.dart,test/rest_pings_watch_end_test.dart,.work/crew/2026-10-21-51g/**"`): D-1 (one added line, exact text in the brief), then S-7521..S-7524 as a separate run (rule z). Done: the new file, then the readers' test files above (touched files only; no full suite).
- P2 (`crew-docs-keeper`): `docs/rest_tracking.md` (the pings follow a rest the watch ends), the plan's evidence file.
- Lead verification: diff vs list, `flutter analyze` count vs baseline, the full `flutter test` once, the invariant grep; the lead's mutation pass: remove the added line (S-7521, S-7522 red), cancel-only variant (S-7522 red), schedule-only variant (S-7521, S-7524 red).

## Owner checks (owner)

- (owner) Phone in the pocket, watch worn: log a set on the phone, press Next on the watch; the phone does not ping for the finished rest.

## Scope budget

About 110 changed lines (one production line, about 90 of test, docs about 15), one track, two phases.
