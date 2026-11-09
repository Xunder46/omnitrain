# Feature: 43b2 — a timer started on the watch runs on the phone

> Status: BUILT AND PROVED (2026-10-20); docs written, review pending. Built on 43b1 (a timer names its exercise on the wire). Second of three (43b1 wire + wrist, 43b2 phone receives, 43b3 phone sends). Series outline: `docs/plans/2026-10-19-43-shared-running-timer-plan/`.
> Binding conventions: docs/global_conventions.md; docs/documentation_standard.md; .github/copilot/pr-scope-budget.md
> Base: 43b1 built. Team: the crew. Re-validate every line number against the tree before briefing (43a and 43b1 touch nearby files). Architect step skipped on purpose.
> Scout sheets: `.work/crew/2026-10-20-43b-shared-timer/scout-phone.md` (quotes read from it).

## Goal and acceptance

When you start a cardio interval, a hold or a round on the watch, the phone shows that exercise's interval running with the same clock, without you touching the phone.

| Situation | Now | After 43b2 |
|---|---|---|
| Watch starts an interval of exercise A; the phone is on A or anywhere else | phone shows nothing running | the first unfinished interval of A is running on the phone with the watch's start time; if the phone is looking at A it counts up live |
| The phone already had its own timer running on A's in-progress interval, started EARLIER | — | the phone's start stands |
| The phone's timer on A started LATER than the watch's | — | the phone adopts the watch's earlier start |
| Watch timer for an exercise the phone does not hold, or the wrong kind for it | — | ignored |
| Watch stops/finishes | — | unchanged here: the watch's logged entry fills and finishes the interval (43a); no stop signal is applied (43c) |

Pause and the phone's own start reaching the watch are 43b3. No new screen, modal or button.

## Owner decisions (2026-10-19, in chat)

- O-1 interval where it started (the wrist's exercise); O-3 the earlier start wins. (Pause both is 43b3.)

## Decision Ledger

- D-1 Target interval: for the effort named by the timer's `sessionExerciseId` (slot id = effort id), the effort's IN-PROGRESS interval if it has one (a `TimedInstance`/`RoundInstance` whose state is `active` or `paused`; the phone allows one in-progress timer per effort, `_getAnotherInProgressKey` lock), else its first not-finished interval (the same ordering 43a uses: `getTimedInstances`/`getRoundInstances` sorted by `entryIndex`/`roundIndex`). No unfinished interval: ignore. Wire kind to effort kind: `elapsed` -> `timed`, `hold` -> `drill`, `round` -> `round`; any other pairing ignored.
- D-2 New `TimerManager.adoptRemoteTimer(String effortId, RemoteWorkTimer remote)` (`lib/state/workout/timer_manager.dart`; no method takes explicit timestamps today: scout Q3, `startTimedEntry` ~:517 stamps `DateTime.now()`; model the writes on it). `RemoteWorkTimer` is a small immutable value in the same file: `wireKind`, `startedAtMs`, `pausedAtMs?`, `accumulatedPauseMs`, `plannedDurationMs?`, `running` (not stopped). For a running/paused remote: target `notStarted` -> `active` (or `paused` when `pausedAtMs` set) with `startedAtMs = remote.startedAtMs`, `totalPausedDurationMs = remote.accumulatedPauseMs`, `targetDurationSecs: 0` for timed (as `startTimedEntry` does), a round keeps its own `plannedDurationSecs` unless the remote carries one; target already `active`/`paused`: replace ONLY when `remote.startedAtMs < target.startedAtMs` (the earlier start wins), copying the remote's pause bookkeeping, else keep it; a remote `stopped` timer is ignored (43c). Closes the effort's open rests in memory the way `startTimedEntry` does. Persist through the repository (`updateTimedInstance`/`updateRoundInstance`), bump `_watchRefreshRevision` (so the open screen resyncs, D-3506) and notify once. Returns whether anything changed.
- D-3 Delivery to it (the 'disposed with the graph' clause was dropped: like every other graph object it lives for the app run): new `WatchTimerAdoption` (`lib/state/watch/watch_timer_adoption.dart`): listens to the `LiveSessionMirrorState` (a `ChangeNotifier`; the reconciler folds every `timer_state` and snapshot timers into `state['timers']`, `session_reconciler.dart:67,132-144`), and on each notification, for each work kind (`round`, `hold`, `elapsed`) whose timer map is non-null, carries a `sessionExerciseId`, and is not `stopped`, builds the `RemoteWorkTimer` and calls a bound adopt function (`WorkoutState.adoptRemoteTimer(effortId, remote)` facade in `workout_state.dart`). It remembers the encoding it last applied per kind and skips repeats. Ignores a mirror whose session id is not the phone's current session. Constructed in `createWatchSync` (`watch_sync_wiring.dart` ~:216, beside the push), returned on `WatchSyncGraph`, bound in `lib/main.dart` next to `watchSync?.autoPush.bindWorkoutState(workoutState)` (~:395-398), disposed with the graph.
- D-4 Screen: a persisted interval that turns `active` by an outside write gets NO ticker today (scout Q3: `_restoreTimerStateFromPersisted` sets `_effortRunning[key] ??= false`; tickers are made only in `_toggleEffortTimer` and `_rekeyTimerStateAfterDelete`). Add `_adoptRunningTimerState()` to `workout_session_timer_mixin.dart`, called in `_resyncExercisesFromState`'s `apply()` next to `_dropFinishedTimerState()` (plan 43a): for every displayed timed/drill/round effort and every instance that is `active` without a ticker: set `_effortRunning[key] = true`, add the key to `_inProgressKeys`, seed `_effortElapsed`, and create the same periodic ticker `_toggleEffortTimer` creates (extract its ticker creation into one private `_startEffortTicker(effortId, entryIndex, effortKind)` and call it from both places; the existing four creation sites ~:461/:496/:544/:578 per plan 41 notes may stay unless the extraction is trivial); a `paused` instance: `_effortRunning[key] = false`, key in `_inProgressKeys`, elapsed seeded. Never touches another effort's or interval's state. (As built, the ticker is what the round ring's sweep and the expiry notification need; a timed interval's count-up digits already follow the screen's one-second rebuild, because the digits read the instance's wall-clock elapsed at each rebuild.)
- D-5 No echo: 43b3's sender must not send back what this adopted (it compares to the mirror's timers); this PR sends nothing.

## Code pointers (current text)

`timer_manager.dart` `startTimedEntry` ~:517-560: `closeAllOpenRestsInMemory(effortId)`, `final list = _timedInstances[effortId]; ... final old = list[entryIndex]; if (!_isValidTimedTransition(old.state, TimedState.active)) return; final now = DateTime.now().millisecondsSinceEpoch; final offsetMs = old.targetDurationSecs > 0 ? old.targetDurationSecs * 1000 : 0; final updated = old.copyWith(state: TimedState.active, startedAtMs: now - offsetMs, targetDurationSecs: 0, updatedAtMs: now); await _repository.updateTimedInstance(updated); list[entryIndex] = updated; _notify();`. `startRound` ~:106 is the round counterpart (`RoundState.active`, `startedAtMs`).
`session_core_io.dart` `refreshEfforts` ends with `_watchRefreshRevision++; _notify();`; the screen's listener (`workout_session_screen.dart` ~:335-341) runs `_resyncExercisesFromState()` when the revision moved.
`live_session_mirror_state.dart` `timerEnd` ~:178 reads `state['timers'][kind]`; nothing else reads them (scout Q1).
`watch_sync_wiring.dart` `createWatchSync` builds `WatchSessionAutoPush(...)` ~:262 and returns `WatchSyncGraph(mirror:, ratings:, lateEntryRecovery:, adoption:, autoPush:)` ~:316.

## Core scenarios (ids checked unused: `grep -rE "S-61[0-9]{2}"` returns nothing; S-60xx are 43b1's)

State (`test()`, Mock and Hive for stored data):
- S-6101 A `timed` effort with two intervals (idx 0 finished, idx 1 `notStarted`); `adoptRemoteTimer` for `elapsed` started at T: idx 1 is `active`, `startedAtMs == T`, idx 0 untouched, `_watchRefreshRevision` +1, one notification. Fails without: nothing adopted.
- S-6102 The phone's own interval 1 is `active` since T+10 s; a remote start at T (earlier): `startedAtMs == T`. A remote start at T+20 s: unchanged, returns false, no revision bump.
- S-6103 Hold (`drill`) with `hold` kind and round with `round` kind (with `plannedDurationMs` 60000 -> `plannedDurationSecs` 60) adopt the same way; a `round` timer for a `timed` effort and an unknown effort id are ignored.
- S-6104 A remote timer carrying `pausedAtMs` and `accumulatedPauseMs 5000` adopts as `paused` with those values.
- S-6105 Every interval finished: ignored, returns false.
- S-6106 The in-progress interval is idx 2 while idx 1 is `notStarted`: the in-progress one is the target (D-1), idx 1 untouched.
Adoption (`WatchTimerAdoption`, the graph from `watch_session_auto_push_test.dart` over a fake radio, real Dart wrist engine):
- S-6111 The wrist engine starts an `elapsed` timer for slot `sl-run` (43b1) and its frame reaches the phone: the phone's idx becomes active once; the same frame redelivered and a later unrelated snapshot change nothing more (no second revision bump).
- S-6112 A `stopped` timer or one with no `sessionExerciseId` is ignored; a mirror session that is not the phone's current session is ignored.
Screen (`testWidgets`, Mock, live-refresh harness):
- S-6121 Phone screen on `sl-run` interval 1 of 2 not started; the wrist's `elapsed` timer arrives (started 5 s ago by the pinned clock): after `pump` the interval shows running with about 5 s elapsed, `Log Interval` offered (as `S-010/S-011` of `test/session_toolbar_rework_test.dart` read a running interval). The digits are asserted as a real-clock range — `RegExp(r'00:4\d')` under the `count-up-digits` key — because elapsed derives from the wall clock (`DateTime.now()`), which a fake `pump(Duration)` does not advance; the planned "after `pump(const Duration(seconds: 3))` the digits advance" assertion was replaced by that, and the pump step only asserts no exception. Fails without: the interval not running and the digits not counting the wrist's start.
- S-6122 The same with the phone looking at another exercise: nothing on screen changes, the interval is running when navigated to.

## Phases (serial)

- P1 `crew-builder-app` — D-1, D-2 with S-6101..S-6106. Scope: `lib/state/workout/timer_manager.dart`, `lib/state/workout/workout_state.dart`, `lib/data/models/models.dart` only if `RemoteWorkTimer` cannot live in timer_manager, new `test/remote_work_timer_state_test.dart`.
- P2 `crew-builder-app` — D-3 with S-6111, S-6112. Scope: new `lib/state/watch/watch_timer_adoption.dart`, `lib/state/watch/watch_sync_wiring.dart`, `lib/main.dart` (one bind line only), new `test/watch_timer_adoption_test.dart`.
- P3 `crew-builder-app` — D-4 with S-6121, S-6122. Scope: `lib/features/session/workout_session_timer_mixin.dart`, `lib/features/session/workout_session_screen.dart` (the resync only), new `test/watch_timer_adoption_screen_test.dart`.
- P4 `crew-docs-keeper` — `docs/state_management/watch_surface.md`, `docs/state_management/workout_state.md`, `docs/watch_session_capture.md`, plan evidence (not `docs/watch_session_sync.md`).
- Then the lead's mutations (earlier-start comparison, in-progress-first target, kind pairing, repeat suppression, ticker creation), `crew-reviewer`, full suite, a simulator look at a running adopted interval (screen shows a running timer the user did not start: look at it).

Size: about 140 production lines, about 500 test lines, 4 phases, one track (phone).

## Owner checks (owner)

- (owner, after 43b1 and 43b2) Start an interval on the watch with the phone on the same exercise: the phone shows it running with the watch's time, live.
- (owner) Start on the watch with the phone on another exercise, then open that exercise on the phone: it is already running.

## Progress

| Phase | What | Result |
|---|---|---|
| P1 | D-1, D-2 — `RemoteWorkTimer`, `TimerManager.adoptRemoteTimer`, the `WorkoutState.adoptRemoteWorkTimer` facade | Built; `test/remote_work_timer_state_test.dart` (S-6101–S-6106, groups `Mock` and `Hive`, 34 tests) |
| P2 | D-3 — `WatchTimerAdoption`, `WatchSyncGraph.timerAdoption`, the bind in `lib/main.dart` | Built; `test/watch_timer_adoption_test.dart` (S-6111–S-6115, 13 tests) |
| P3a | D-4 screen code — `_adoptRunningTimerState` in `workout_session_timer_mixin.dart` | Built |
| P3b | Screen tests | Built; `test/watch_timer_adoption_screen_test.dart` (S-6121, S-6122 ×2, S-6123, S-6124, S-6125 timed; the S-6125 round variant is `skip: true` — the S-4408 premise, see the evidence file) |
| P3c | The resync wiring — `_resyncExercisesFromState`'s `apply()` calls `_adoptRunningTimerState` (`workout_session_screen.dart`) | Built |
| Fix rounds | Two tests-only gap rounds, then 37 lead mutations, all made a named test red; the P3b builder's stale round-target-cache fix (`_effortTargetDuration` refreshed by `_adoptRunningTimerState`) | Proved; see the evidence file |
| P4 docs | `workout_state.md`, `watch_session_capture.md`, `watch_surface.md`, this plan's evidence | Written (2026-10-20) |

## Assumption Log

- A-1 Applying a timer to the effort's in-progress interval first (D-1) keeps the phone's one-timer-per-effort lock intact.
- A-2 A remote `stopped` is ignored until 43c: the wrist's logged entry already fills and finishes the interval (43a), which stops the phone's ticker (`_dropFinishedTimerState`).
