# Feature: 50a — the phone's rest reaches the watch

> Status: BUILT, PROVED AND REVIEWED 2026-10-21 (review APPROVE WITH FIXES, all fixed: the same-rest tolerance is 500 ms so consecutive rests under 2 s apart stay distinct (S-7311), the stale-copy guard uses the tolerance (S-7312), the unnecessary await removed, the ping sentence cites tests). Rest across devices live is an owner check. Swift 688/0, Flutter +5411 (one unrelated flaky test, S-5115, fails in some full runs and passes alone), analyze 180 (baseline). Series: `docs/plans/2026-10-21-49-watch-food-and-rest-series.md`. Scouts: `.work/crew/2026-10-21-49/scout-rest-phone.md`, `scout-rest-wrist.md`. Reverses D-4 of plan 43b3 ("rests are not this push's") for rest only.

## Goal and acceptance

| On the phone | On the watch now | After 50a |
|---|---|---|
| You log a set (the phone opens a rest) | nothing | the rest screen appears, counting from the moment you logged |
| You pause the rest chip | nothing | the rest time freezes on the watch; resume continues it |
| You log the next set (the rest ends) | the wrist keeps its rest running if it had one | the watch's rest ends and logging returns |
| The watch started the rest (you logged on the watch) | its own rest | unchanged: the phone's rest for the same set is not sent back |

## Decision Ledger

- D-1 `TimerManager.inProgressRest(Iterable<SegmentEffort> efforts) -> InProgressRest?` (new small class beside `InProgressWorkTimer` in `lib/state/workout/timer_manager.dart`: `startedAtMs`, `pausedAtMs`, `accumulatedPauseMs`, `paused`): the open `EntryRest` (`restEndMs == null`) with the newest `restStartMs` across the efforts' `getEntryRests`; null when none. `WorkoutState.inProgressRest()` wraps it like `inProgressWorkTimers()` (empty when no active session).
- D-2 `WatchTimerPush._pushOnce` adds `wanted['rest'] = {'kind': 'rest', 'state': paused ? 'paused' : 'running', 'startedAt': utcIso(startMs), 'accumulatedPauseMs': pauseMs, if paused 'pausedAt': ...}` with NO `sessionExerciseId` and NO `plannedDurationMs` (a rest is a count-up and belongs to no slot; the validator refuses a planned length and `toTimerJson` omits the slot for a rest). A rest the phone no longer holds open goes out as `{rest: null}` (the existing clear path: `_delivered` and `retired`).
- D-3 `_wristHolds` for kind `rest` (no slot to compare): the mirror's rest not stopped and its `startedAt` within 2000 ms of ours is the SAME rest (the phone opens its rest at the set's logged instant, the wrist starts its own a few milliseconds later); `identical` when also the same state, `pausedAt` and `accumulatedPauseMs`, otherwise `no` (a pause or resume still travels; the wrist's rest is exempt from the earlier-start rule and the phone's frame supersedes). A rest never answers `earlier`. The existing `_adopted`/`retired`/`_stale` machinery then clears the wrist's copy when the phone's rest ends first and sends nothing when the wrist ended it. The class comment and the "Rests are not this push's" line are updated.
- D-4 Not in scope: the wrist (it already accepts, times, pings and clears a phone rest, S-336 and S-6006), the wrist's Next reaching the phone (50b), a pause button on the wrist, any wire change.

## Scenarios (ids S-7301.. checked free) in `test/watch_timer_push_test.dart` (its shipping-graph harness over a fake radio and the real Dart wrist engine)
- S-7301 an open phone rest at `restStartMs = T` is sent as one `timer_state` whose `timers.rest` is `{kind: rest, state: running, startedAt: T, accumulatedPauseMs: 0}` with no `sessionExerciseId` and no `plannedDurationMs`; the frame validates.
- S-7302 pausing the phone rest sends `state: paused` with `pausedAt`; resuming sends `running` with the accumulated pause.
- S-7303 closing the rest (the next set) sends `{rest: null}` once.
- S-7304 the mirror already holds a running rest started 800 ms after ours (the wrist's own): nothing is sent (identical); when the phone's rest then closes, a clear is sent (retire).
- S-7305 the mirror's rest is stopped (the wrist ended it) and the phone's rest is closed: no frame.
- S-7306 the mirror holds a running rest started 5 s earlier than ours (a different rest): ours is sent.
- S-7307 an undelivered rest frame leaves the ledger as it was and is offered again at the next pass.
- S-7308 end to end in the real Dart wrist engine (`lib/watch/session/watch_session_engine.dart`): after the frame the engine is resting and counts up from `T`; after the clear it is not resting.
- S-7309 work timers are unaffected: an elapsed timer and a rest in one pass travel as one frame with both kinds.
Mutation list: tolerance 2000 -> 0, rest `sessionExerciseId` added, `earlier` returned for rest, `rest` never cleared, pause fields dropped.

## Phases
P1 (crew-builder-app, 6 items): tests first, `TimerManager.inProgressRest`, `WorkoutState.inProgressRest`, `WatchTimerPush`, comments. Scope: `lib/state/workout/timer_manager.dart`, `lib/state/workout/workout_state.dart`, `lib/state/watch/watch_timer_push.dart`, `test/watch_timer_push_test.dart`, `test/watch_timer_push_rest_test.dart` (new, if the harness is shared by import; else keep in the existing file).
