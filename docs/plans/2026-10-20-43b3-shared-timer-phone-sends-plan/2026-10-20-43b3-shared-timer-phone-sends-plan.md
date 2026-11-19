# Feature: 43b3 — a timer started or paused on the phone runs and pauses on the watch

> Status: BUILT, PROVED, docs written, review pending (the Swift end-to-end phase was dropped: 43b1's S-6004/S-6005 cover the wrist side and the shipping-graph tests apply every frame through the real Dart wrist engine). Needs 43b1 (a timer names its exercise) and is best built after 43b2 (so the two directions can be tested together). Third of three. Series outline: `docs/plans/2026-10-19-43-shared-running-timer-plan/`.
> Binding conventions: docs/global_conventions.md; docs/documentation_standard.md; .github/copilot/pr-scope-budget.md
> Base: 43b1 built; 43b2 is NOT built (only the not-sending half of the echo rule ships here: the phone never sends a timer the wrist already holds as earlier or identical; the phone adopting a wrist timer waits for 43b2). Team: the crew. Re-validate line numbers before briefing. Architect step skipped on purpose.
> Scout sheets: `.work/crew/2026-10-20-43b-shared-timer/scout-phone.md`, `scout-wire.md`.

## Goal and acceptance

When you start, pause or resume a cardio interval, hold or round on the phone, the watch shows the same timer for that exercise, and pause on the phone pauses the watch's clock.

| Situation | Now | After 43b3 |
|---|---|---|
| Phone starts an interval of exercise A; the watch is on A | the watch shows Start | the watch shows its logging screen already running (Log) with the phone's start time |
| The watch is on another exercise | — | nothing shows on the wrist's current exercise; when the wrist moves to A it is running |
| Phone pauses / resumes | — | the wrist's clock pauses / resumes with it |
| The watch started the same interval earlier | — | the phone does not send a later start (the wrist keeps the earlier one); with 43b2 the phone also adopts the earlier start so both show it |
| Phone logs or ends the interval | — | the wrist's timer for it is cleared |
| The wrist is out of reach | — | the frame is offered again at the next phone notification |

The wrist has no pause control (A-1 of 43b1): pause only travels phone to wrist.

## Owner decisions (2026-10-19, in chat)

- O-1 interval where it started (the phone's exercise); O-2 pause pauses both; O-3 the earlier start wins.

## Decision Ledger

- D-1 What the phone has to send: for the held session, for each in-progress work interval (a `TimedInstance` of a `timed`/`drill` effort or a `RoundInstance` of a `round` effort whose state is `active` or `paused`): a timer of the wire kind `elapsed` (timed), `hold` (drill) or `round`, `sessionExerciseId` = the effort id, `state` running or paused, `startedAt` = `startedAtMs`, `pausedAt` = `pausedAtMs`, `accumulatedPauseMs` = `totalPausedDurationMs`, `plannedDurationMs` for a round = `plannedDurationSecs * 1000`. New read on the state: `WorkoutState.inProgressWorkTimers()` returning a list of small records with those fields (`lib/state/workout/workout_state.dart` over `TimerManager`'s lists, `getTimedInstancesForEffort`, `getRoundsForEffort`); one entry per wire kind (the phone allows one in-progress timer per effort; across efforts the newest `startedAtMs` wins and a clear is sent for the other).
- D-2 Sender: new `WatchTimerPush` (`lib/state/watch/watch_timer_push.dart`), same shape as `WatchSessionAutoPush` (`bindWorkoutState`, `_onChanged` with a debounce window, `flush()`, `dispose`), constructed in `createWatchSync` beside the existing push and returned on `WatchSyncGraph`, bound in `lib/main.dart` next to `watchSync?.autoPush.bindWorkoutState(workoutState)`. Every pass composes the `timers` map for the current session from D-1, compares its deterministic encoding with the last DELIVERED map, and sends ONE `timer_state` envelope (`phoneEnvelope(type: 'timer_state', ..., payload: {'timers': {...}})`, `lib/core/sync_protocol/phone_envelope.dart`) through the mirror's transport via a new `LiveSessionMirrorState.sendTimers(sessionId, Map timers)` (like `sendRatingFor` in plan 42b). A kind that was in the last delivered map and is no longer in progress is sent as `null` (clear). An undelivered frame leaves the baseline unchanged so the next notification offers it again (D-191 style). Only the phone's current session, only while `status` active.
- D-3 Echo and earlier start: a kind whose mirror timer (`mirror.state['timers'][kind]`) already has the same `sessionExerciseId` and the same `startedAt` is not sent (the wrist's own start adopted by 43b2, or one this push already delivered); a mirror timer for the same slot with an EARLIER `startedAt` than the phone's own wins: the phone does not send its later start (43b2's adoption has moved the phone to the earlier one, so the encodings match); a later wrist start never overrides the phone's (the wrist applies D-4 of 43b1).
- D-2b (added at build, 2026-10-20) A NEW interval started right after the previous one finished inside one debounce window sends TWO frames in order: `{kind: null}` then the new timer, because the wrist (43b1 D-4) ignores a later start while it still holds the earlier, not-stopped timer of the same kind and slot. An undelivered frame stops the pass; nothing after it is sent.
- D-3b (precise echo rule) A kind is skipped when the mirror (only when `mirror.sessionId` is the phone's session) holds the same slot, not stopped, and either every one of state, startedAt, pausedAt, accumulatedPauseMs equals ours (instants compared, not strings) or its startedAt is EARLIER than ours. A skipped kind is not recorded as delivered, so a pause on the phone after an adopted earlier start still goes out (the encodings then differ).
- D-4 Rests are not touched; this sends work timers only. A phone-logged interval (`finishTimedEntry`/`endRoundEarly`) ends its in-progress state, so the next pass sends the clear (the wrist also receives the logged entry through the existing projection).
- D-5 `PROTOCOL.md` already allows the phone to send `timer_state` ("either direction"); the amendment of 43b1 covers the slot. No further contract change.

## Code pointers (current text)

`phone_envelope.dart`: `phoneEnvelope(type:, messageId:, sentAt:, sessionId:, payload:)` (used by `snapshotEnvelope`, `live_session_mirror_state.dart` ~:319). `LiveSessionMirrorState.sendState` ~:350 `_transport.send(snapshotEnvelope(state: state))` returns `WatchDelivery`; `_envelopeFor` ~:680 builds a phone envelope for a named session.
`WatchSessionAutoPush`: `bindWorkoutState` ~:186, `_onChanged` ~:427-439 (debounced `flush`), `_pushOnce` ~:248, owed-frame rule D-191 (only a delivered send moves the baseline), `dispose`.
`TimerManager` notifies on every start/pause/resume/finish (scout Q2 table), so a `WorkoutState` listener hears them all.
Wire: wrist applies a `timer_state` through `applyTimerState` -> `adoptTimers(authoritative: false)` (a kind named `null` stops it; 43b1 stores the slot and applies earlier-start-wins).

## Core scenarios (ids checked unused: `grep -rE "S-62[0-9]{2}"` returns nothing)

State: S-6201 `inProgressWorkTimers()` for a timed effort whose interval 1 is active returns one record `elapsed` with the right fields; paused carries `pausedAt`; a round carries `plannedDurationMs`; finished and notStarted intervals return none; two efforts in progress: the newest start is listed first and the other is flagged for clearing.
Push (`test()`, the graph and a fake radio of `test/watch_session_auto_push_test.dart`, the real Dart wrist engine applying the frame):
- S-6211 Starting an interval on the phone sends one `timer_state` with `elapsed`, the slot, the start; the wrist engine stores it with the slot; a second notification that changes nothing sends nothing.
- S-6212 Pause then resume: two further frames with `pausedAt` set then `accumulatedPauseMs` increased; the wrist's timer reads paused then running.
- S-6213 Logging the interval sends `{elapsed: null}` once.
- S-6214 The wrist's own `elapsed` timer for the same slot, started EARLIER, is in the mirror: the phone's later start is not sent (no frame). Same slot, same `startedAt`: not sent.
- S-6215 An undelivered first frame is offered again at the next notification, then stops once delivered.
- S-6216 Rest timers, `set` efforts, inactive sessions and an unbound push send nothing.
- S-6217 (D-2b) a new interval started right after the previous one finished inside one window: two frames, `{elapsed: null}` first, then the new timer; the wrist ends on the new timer.
Screen/wrist (Swift, `WatchTimedWorkTests`): S-6221 a phone `timer_state` for the wrist's current slot makes `isWorkRunning` true and `primaryTitle` read Log; for another slot it does not (43b1 S-6004 covers the rule; this one is the end-to-end with the frame the push builds, fixture copied into the Swift test).

## Phases (serial)

- P1 `crew-builder-app` — D-1 with S-6201. Scope: `lib/state/workout/workout_state.dart`, `lib/state/workout/timer_manager.dart` (read helper only), new `test/in_progress_work_timers_test.dart`.
- P2 `crew-builder-app` — D-2, D-3 with S-6211..S-6216. Scope: new `lib/state/watch/watch_timer_push.dart`, `lib/state/watch/live_session_mirror_state.dart` (`sendTimers`), `lib/state/watch/watch_sync_wiring.dart`, `lib/main.dart` (one bind and one dispose line), new `test/watch_timer_push_test.dart`.
- P3 `crew-builder-watch` — S-6221 only if 43b1's tests do not already cover the frame the push builds. Scope: `watch/watchos/Tests/WatchSessionEngineTests/WatchTimedWorkTests.swift`.
- P4 `crew-docs-keeper` — `docs/state_management/watch_surface.md`, `docs/state_management/workout_state.md`, `docs/watch_session_capture.md`, plan evidence.
- Then mutations (clear-on-finish, baseline-only-on-delivered, echo guard, earlier-start guard), `crew-reviewer`, full suite, `swift test`, the owner's device check.

Size: about 120 production lines, about 450 test lines, 4 phases, one track plus one Swift test.

## Owner checks (owner)

- (owner) Start an interval on the phone while the watch is on the same exercise: the watch shows it running; pause on the phone: the watch's clock pauses; log on the phone: the watch's running state clears.
- (owner) Start on both within a second or two: both show the earlier start.

## Progress

| Phase | What | Result |
|---|---|---|
| P1 (crew-builder-app) | D-1 `WorkoutState.inProgressWorkTimers()` / `InProgressWorkTimer`, S-6201 | Built 2026-10-20 |
| P2 (crew-builder-app) | D-2/D-3 `WatchTimerPush`, `LiveSessionMirrorState.sendTimers`, `WatchSyncGraph.timerPush` wiring, S-6211–S-6217 | Built 2026-10-20 |
| Fix | 1 test corrected during the build | Done 2026-10-20 |
| P3 (crew-builder-watch) | S-6221 Swift end-to-end | Dropped: 43b1's S-6004/S-6005 cover the wrist side; the shipping-graph tests apply every frame through the real Dart wrist engine |
| Mutations | 17 mutations of the push and `sendTimers`; 14 red at once, 3 after a tests-only gap round; all restored | Proved 2026-10-20 (lead) |
| P4 (crew-docs-keeper) | `workout_state.md`, `watch_session_capture.md`, `watch_surface.md`, plan evidence | Done 2026-10-20 |

## Assumption Log

- A-1 A timer for an exercise other than the one the wrist shows stays on the wrist until the user moves to that exercise (43b1 D-3); the wrist does not navigate.
- A-2 Out-of-reach recovery uses the notification-trigger re-offer only (like plan 42b's rating frame); a reconnect with no phone notification waits for the next one.
