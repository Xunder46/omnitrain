# Plan 89c1 evidence

## Baselines (before any edit)

- `flutter analyze`: 180 issues.
- `git diff --stat`: 21 files, 477 insertions, 53 deletions (plan 89, uncommitted).
- Shared tree: during this phase another session was also editing `workout_state.dart`,
  `session_core_entry.dart`, `watch_session_adoption_bridge.dart` and
  `test/watch_live_refresh_screen_test.dart` (`seedFirstInterval` -> `seedFirstEntry`). That
  work is not mine and was not touched.

## Every path that reaches `HealthSyncService.onSessionCompleted`

The only production caller is `SessionCore.endSession` (`session_core_lifecycle.dart`). It is
reached from:

| # | Path | Watch workout for the session? | Phone write after 89c1 |
|---|---|---|---|
| 1 | Session screen Finish (`workout_session_finish.dart` `_finishSession` -> `endSession()`) | Yes if the wrist is following the session: it saves one when the phone's `completed` reaches it. No if there is no watch, or the wrist is not in this session. | Skipped when the mirror says the wrist is running the session (D-2); otherwise written, as before |
| 2 | Session Summary save (`session_summary_screen.dart` `_finishAndSaveSession` -> `endSession()`, live session only) | Same as 1 (after 1 it is already ended, so this is a no-op) | Same as 1 |
| 3 | Wrist `completed` for the held session (`WatchSessionAdoptionBridge.onLifecycle` -> `endSession(writeToHealth: false)`) | Yes: the wrist saved it, unless the wrist's own Health registration failed (D-3) | Never written (D-1) |

These never reach it: a wrist session the phone was not holding (`watch_session_importer.dart`
writes the rows and calls nothing, so the watch's workout is the only one); a discard, which goes
to `onSessionDeleted` instead; the wrist's `abandoned` (bridge -> `discardCurrentSession`).

## D-2: what the mirror knows at the moment the phone ends a session

Finding: it does expose what the decision needs, so S-89c1-4 is built.

- `LiveSessionMirrorState.sessionId` and `status` / `isActive` are the session the wrist last
  reported. Only a wrist `session_snapshot` moves the mirror onto another session id (`receive`,
  `switchesSession`). Everything the phone sends either names the session the mirror already holds
  (`_sendOwn`, `reportLifecycleFor`, `deleteEntryAs` apply locally only when the ids match) or does
  not apply locally (`sendState`). The startup placeholder (`s-phone-unjoined`) is `abandoned`.
- At the phone's end the mirror still shows the wrist's status. The phone's own `completed`
  reaches the mirror only later, through the auto-push pass (`completeSession` /
  `reportLifecycleFor`), which runs on a debounce timer after the state notifies. Even so,
  `endSession` reads the predicate first, before any await.
- Precedent: plan 86's rest-ping gate already reads "the wrist holds the phone's session" as
  `mirror.isActive && mirror.sessionId == currentSession.id`.
- Built as `LiveSessionMirrorState.wristRunsSession(id)` = same id, `active`, and at least one
  exercise in the ladder. The exercise clause is mine (Assumption Log): the wrist opens no workout
  for a Free session until its first exercise (`WatchWorkoutLifecycle`, S-8807). So without an
  exercise the phone keeps writing.
- The predicate is passed into `WorkoutState(wristRunsSession:)` from `main.dart`, the way
  `watchLateEntryRecovery` is (the watch graph is built before `WorkoutState`).

Limits, reported and not fixed:
- L-1 The mirror learns that the wrist is in a phone-started session only from the wrist's own
  snapshot. The wrist sends one when its app wakes or is raised with the phone in reach (catch-up
  `sync`), on Sync, when an exercise is added on the wrist, and in answer to the phone's resume
  request. Applying the phone's snapshot sends nothing back. A session the wrist joined in the
  background and was never raised for would still get the phone's copy too: today's duplicate,
  with no new loss.
- L-2 Suppose the mirror still shows the session `active` when the wrist has already lost it (the
  watch app was deleted or unpaired mid-session). Then nothing reaches Fitness. A force-quit is
  covered, because the wrist's recovery saves an active session's workout (plan 89 OQ-1).
- L-3 Two cases get no workout from either device. One is a wrist whose Health registration failed
  (D-3); this now covers phone-ended sessions too. The other is a phone-ended session whose mirror
  says `completed` before the phone's end, because the wrist ended it first: the bridge normally
  handles that, and if the phone's End wins the race the phone writes as before.

## Red -> green (`flutter test test/health_platform_test.dart --plain-name "plan 89c1"`)

Red with the API stubbed (the flag accepted and ignored; `wristRunsSession` returning false):
`00:00 +8 -3: Some tests failed.`, each failing with `Expected: empty / Actual: [Instance of
'HealthWorkoutDraft']`.

| Test | Red | Green |
|---|---|---|
| S-89c1-1 the wrist's completed ends the held session and writes no workout | fail | pass |
| S-89c1-2 the wrist's abandoned still discards and writes nothing | pass (pin) | pass |
| S-89c1-3 a phone-only session ended by the phone writes exactly one | pass (pin; M2b) | pass |
| S-89c1-3 with Write workouts off writes none | pass (pin) | pass |
| S-89c1-4 the wrist holds the same session active: no workout | fail | pass |
| S-89c1-4 the wrist holds X while the phone ends Y: Y writes one | pass (pin; M6) | pass |
| S-89c1-4 the wrist holds no session: one workout | pass (pin) | pass |
| S-89c1-4 same session but no longer active: one workout | pass (pin; M4) | pass |
| S-89c1-4 same session with no exercise yet: one workout | pass (pin; M5) | pass |
| S-89c1-5 completed twice ends once and writes nothing | fail (first end wrote) | pass |
| S-89c1-5 completed after the phone already ended: nothing more | pass (pin) | pass |

Green: `00:00 +11: All tests passed!`

## Mutation checks (each restored to the exact original line, then re-run green)

| # | Mutation (original) | Result |
|---|---|---|
| M1 | bridge `await target.endSession(writeToHealth: false);` -> `true` | S-89c1-1 and S-89c1-5 (twice) fail; `+9 -2` |
| M2a | SessionCore default `{bool writeToHealth = true}` -> `false` | survived: `WorkoutState` always passes the flag. The SessionCore parameter was made `required`, so the only default left is `WorkoutState`'s |
| M2b | `WorkoutState.endSession({bool writeToHealth = true})` -> `false` | S-89c1-3 and four S-89c1-4 "writes one" tests fail; `+6 -5` |
| M3 | `if (completedSession != null && writeToHealth && !wristSavesWorkout) {` -> drop `&& !wristSavesWorkout` | S-89c1-4 same-session-active fails |
| M4 | `this.sessionId == sessionId && isActive && exercises.isNotEmpty;` -> drop `isActive` | "no longer active" fails |
| M5 | same line -> drop `&& exercises.isNotEmpty` | "no exercise yet" fails |
| M6 | same line -> drop `this.sessionId == sessionId &&` | "wrist holds X, phone ends Y" fails |
| W1 | Swift `guard running == nil else { return .none }` -> commented out | S-89c1-6 fails: `("2") is not equal to ("1") - one begin` and `[false, true]` ends |

## S-89c1-6 (watch, no production change)

`WatchOneWorkoutPerSessionTests.testS89c1_6AFreeOutdoorWalkBeginsOneWalkingWorkoutAndSavesItOnce`
uses a real engine and coordinator: a Free session, then an outdoor walk inserted, three refreshes,
then finish. Result: `Executed 1 test, with 0 failures`, i.e. one begin (`walking`,
`outdoors == true`) and one end with `saving == true`. The wrist does not duplicate. The store is a
small recording one, not `ScriptedPlatformStore`: that store implements only `begin(_:)`, so it
cannot see `outdoors`.

## Verification runs

- Touched and dependent files (`health_platform_test`, `live_mirroring_test`,
  `watch_session_finish_test`, `watch_finish_once_test`, `rest_pings_watch_end_test`,
  `pr4_session_controls_test`, `watch_session_import_test`): `00:02 +238: All tests passed!`
- Contracts (`ui_standards_contract_test`, `docs_indexing_contract_test`): `00:01 +42: All tests passed!`
- `flutter analyze`: 180 issues (baseline 180); the touched files on their own: `No issues found!`
- Hive import grep: empty (exit 1).
- `swift test` (watch/watchos): `Executed 1141 tests, with 0 failures` (baseline 1140, plus S-89c1-6).
- Full `flutter test` (900 s wrapper, finished at 05:11, no hang): `+5784 ~2 -29: Some tests failed.`
  All 29 failures are in five files: `watch_routine_adoption_test` (18), `watch_session_merge_test` (6),
  `watch_session_adoption_bridge_test` (S-1 parity, S-102), `watch_session_adoption_build_notify_test`
  (S-103, S-111) and `watch_session_rest_timer_append_test` (S-110). None of these files calls
  `endSession`, `onLifecycle` or `wristRunsSession` (grep count 0 each). Each fails on a set row
  written at adoption or append, e.g. `Actual: ['obs-sx-eff-bench-0-reps']` ("A5 no planned row is
  written") and `Actual: [EffortObservation, EffortObservation]` ("S-12 sl-1 is untouched"). That is
  the other session's in-progress `seedFirstInterval` -> `seedFirstEntry` change in the shared tree,
  not this plan. Not edited, as AGENTS.md requires.

## Proposed S-89c1-7 QA step (for the governor to place)

> Phone Settings > Write workouts ON. Watch app open, phone in reach.
> (a) On the watch, start a Free workout, add Outdoor Walk, walk a minute, finish it on the
> watch. Fitness (phone): exactly ONE new OmniTrain workout, "Outdoor Walk".
> (b) On the phone, start a session with one exercise (any type). Let the watch pick it up, then
> raise the wrist once so the watch reports back. Finish it on the phone. Fitness: exactly ONE
> workout, sourced to the watch app.
> (c) With the watch app closed or the watch out of reach, start and finish a session on the phone.
> Fitness: exactly ONE workout, sourced to the phone app (unchanged).
> (d) On any earlier duplicate pair, open Health > Browse > Activity > Workouts > Show All Data and
> look at each entry's Source. The "Other" one should be the phone app, which confirms the cause.
