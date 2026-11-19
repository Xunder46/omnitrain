# Plan 23b: rest after every effort on the watch, a clearer End Session, the phone screen follows the watch live

Base: HEAD after plan 23a (f814361). Governor-seeded, no architect run. Owner QA 2026-10-11, second round.
Two independent tracks (disjoint scopes, may run in parallel; only one runs a full suite at a time):
W = watch (Swift), P = phone session screen. No wire change. Not in this plan: Add exercise (23c), the
phone's colour theme on the watch (asked, needs the owner's scope answer).

## Goal and acceptance (what the owner sees)

1. (W) Logging ANY effort on the watch starts a rest, as on the phone: after a set (already), a timed
   entry (cardio), a hold, and a sports period. The rest screen counts up with "Rest"; Next, or Start of
   the next effort, ends it; the rest reaches the phone like a set's rest does. Phone parity: the phone
   starts a rest after every logged entry kind (`lib/features/session/workout_session_screen.dart` ~872
   `recordRestStart`, all kinds).
2. (W) The menu's End Session button sits apart from the exercise list: a divider and extra space above it,
   so it is not mistaken for another exercise row.
3. (P) The phone's open session screen shows what the watch logs (or adds) without leaving and re-opening
   the session: a set, timed entry, hold, period, or a whole exercise the watch added appears within a
   moment of the watch's Log. The screen keeps what the user is doing: the exercise and set being edited,
   running timers, scroll position are not reset.

## Decision ledger

- D-3501 W: the follow-on rule becomes "every effort kind starts a rest". `startFollowOnTimer`
  (`watch/watchos/Sources/WatchSessionEngine/WatchLoggingState.swift` ~903): current body
  `guard effortKind == WatchEffortKind.set else { return }; _ = try? await engine.startTimer(WatchTimerKind.rest)`.
  Remove the guard. A period no longer ends on a bare logging screen: after Log of a period, rest starts.
  The next period is still the user's own Start (D-1306 "no new countdown", keep), which ends the rest
  (`startWork()` already does: `if isResting { await endRest(at: startedAt) }`).
- D-3502 W: the Dart/Wear twin (`lib/watch/logging/watch_logging_state.dart` `_startFollowOnTimer`) is NOT
  changed: it keeps its own older behaviour (documented divergence, same as D-3406 of plan 23a).
- D-3503 W: wording of the rule: `docs/global_conventions.md` row "Rest rule" says "from the moment a set is
  logged"; make it "from the moment an effort (a set, a timed entry, a hold or a period) is logged to the
  moment the next one starts". `test/rest_is_count_up_contract_test.dart` scans the rule: keep it green.
  Also `docs/rest_tracking.md`, `docs/state_management/watch_surface.md` where they say "a logged set
  starts a rest".
- D-3504 W: End Session separation is view-only (`WatchMenuView.finishRow` placement: a `Divider()` and
  `.padding(.top, 10)` above it; keep the alert). No logic.
- D-3505 P: signal, not polling. `WorkoutState` gets a read-only `int get watchRefreshRevision`
  (`lib/state/workout/workout_state.dart`, backed by a counter in `SessionCore`) incremented exactly where
  watch-driven writes change the screen's data: end of `refreshEfforts` (`session_core_io.dart:218`, success
  path before `_notify()`) and `appendSessionSlots` (`session_core_entry.dart:82`, before `_notify()`).
  Own notifications never bump it, so the screen cannot loop on its own reload.
- D-3506 P: the screen (`lib/features/session/workout_session_screen.dart`, `_onWorkoutStateChanged` ~284)
  remembers the last revision it applied. When the revision moved and the session is still the mounted one
  and active, it calls a new `_resyncExercisesFromState()`: re-read `widget.workoutState.getExercisesWithEntries()`,
  apply the same display ordering `_loadExercises` applies (extract that ordering into a private helper used
  by both; no behaviour change for `_loadExercises`), `setState` the new list. (The first draft also added the logged
  entries to `_loggedSetKeys`; removed after review: a set is logged exactly when a rest covers it, the screen shows LOGGED and offers no
  Log button there, so the fill was unobservable, see S-3515.) It does NOT call `loadSessionData`, `_restoreTimerStateFromPersisted`,
  `_loadExercises`, reset `_currentSet`, move the detail index, or touch timers. Never calls `setState`
  during build (post-frame if the framework is building: guard with `SchedulerBinding.instance.schedulerPhase`).
- D-3507 P: no new screens, buttons or settings.

## Scenarios (tests first; each must fail without the change)

W (Swift, in `WatchTimedWorkTests.swift` / `WatchRestSurfaceTests.swift` / `WatchLoggingSurfacesTests.swift`):
- S-3501 Log of a set starts a rest (existing behaviour, keeps passing).
- S-3502 Start then Log of a timed (cardio) entry leaves `isResting == true` and one stopped-not rest timer row.
- S-3503 same for a hold (drill), and for a period (round): rest row exists after Log, and the period's
  own countdown is not restarted (the existing "a logged period starts nothing" assertion on milestones
  stays true; the one that said `timedRests.isEmpty` "(D-1306)" must be changed to expect one rest).
- S-3504 Start of the next timed effort while resting ends the rest at Start's instant, and the rest
  observation (kind `rest`, `afterEntryId` = the previous entry) is emitted once.
- S-3505 Ending the rest with `endRest()` after a timed entry emits kind `rest` whose `afterEntryId` is that
  timed entry.
P (Dart, new `test/watch_live_refresh_screen_test.dart`, Mock repository; copy the harness of
`test/session_screen_build_phase_notify_test.dart`; plain `test()` for state, `testWidgets` for the screen with
`tester.pump()` not real delays):
- S-3510 (state) `watchRefreshRevision` increases after `refreshEfforts([...])` with a watch-merged effort, and
  after `appendSessionSlots`; does not increase after `addEntry`/`updateEntryValue` (phone's own writes).
- S-3511 (screen) mount the screen on a held session with one set exercise and no sets; then deliver a wrist set
  through the same path production uses (stage + merge: see `test/watch_session_merge_test.dart` S-9 for
  the `_phone` wiring with `refreshHeldEfforts`), pump; the screen's list shows the set's reps/load text
  without any navigation. Fails today (screen keeps its first snapshot).
- S-3512 (screen) a wrist timed entry on a timed effort appears too (use effortKind timed, capabilities
  time,distance).
- S-3513 (screen) a slot the wrist added (`appendSessionSlots`) shows as a new exercise row at the end.
- S-3514 (screen) the phone user's open entry is not reset: with the exercise detail open at set 2 and a
  running timer flag, a wrist merge leaves `_currentSet` and the running-timer state as they were (assert the
  visible set number and that the timer chip still shows running).

## Phases

| # | Agent | Scope | Items |
|---|---|---|---|
| W1 | crew-builder-watch | `watch/watchos/**`, `docs/global_conventions.md`, `docs/rest_tracking.md`, `docs/state_management/watch_surface.md`, `docs/watch-app-setup-and-qa.md`, `test/rest_is_count_up_contract_test.dart` | D-3501, D-3503, D-3504, S-3501..3505, QA steps (owner) |
| P1 | crew-builder-app | `lib/state/workout/**`, `lib/features/session/**`, `test/watch_live_refresh_screen_test.dart`, `docs/state_management/workout_state.md` | D-3505, D-3506, S-3510..3514 |

W1 and P1 run in parallel (disjoint). The governor runs the full suites after both.

## Verification (governor, observed)

`swift test` (baseline 504), `flutter test` (+4240 ~1; will grow), `flutter analyze` (196), xcodebuild watch
scheme, invariant grep, mutations: remove the guard back to set-only; stop bumping the revision in
`appendSessionSlots`; make the revision bump on `addEntry`; (the `_loggedSetKeys` fill was removed as unobservable).
(owner) Watch: log a hold, a cardio interval and a sports period: the Rest screen follows each; End Session
sits below a divider. Phone: open a session on the phone, log sets/intervals on the watch, the phone's open
screen updates by itself.
