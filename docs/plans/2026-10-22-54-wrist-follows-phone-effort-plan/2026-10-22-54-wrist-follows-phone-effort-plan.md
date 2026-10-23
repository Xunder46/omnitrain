# Feature: 54 — the watch follows an effort the phone starts, and never stays locked after it ends

> Status: SEEDED 2026-10-22 (governor), not planned yet. Owner: watch testing round 2026-10-22 item 4, in chat ("I started a round on the phone while the watch was on a different exercise; the watch refused to switch because an effort was running, yet let me log the exercise I was on, and it started a rest. I then logged the effort on the phone, and the watch still said I can't switch"). Owner decision: **the watch jumps to the exercise the phone's effort is running on.** Series: PR 2 of 3 (53 food is before this; 55 sync progress after). Base commit: `.work/2026-10-22-54/base.txt`. Working branch: the one checked out; never create or switch branches. Binding conventions: docs/global_conventions.md; .github/copilot/pr-scope-budget.md.
> Status update 2026-10-23 (conductor-v2): expanded in place; next handoff @developer (Phase 1). Seeded text is unchanged; everything the planner added is marked or lives under `## Iteration 1` and below.

## Goal and acceptance

| What happens | Now | After 54 |
|---|---|---|
| The phone starts a round / hold / timed effort on exercise A while the watch shows B | the watch stays on B, says "An effort is running" when you try to switch, yet lets you log a set of B (and starts a rest) | the watch moves to A as soon as the phone's timer arrives; Log is the running effort's Log; nothing of B can be logged by mistake |
| The phone logs/ends that effort while the watch cannot be reached for a moment | the watch keeps saying "An effort is running" and refuses to switch until the phone happens to change something else | the end of the effort reaches the watch as soon as the watch next talks to the phone, so the lock clears |
| A rest, a paused or stopped timer, or a timer for the exercise already shown | unchanged | unchanged: no jump |

## Root cause (read in code; not proven on a device)

1. Lock never clears: `WatchTimerPush` (`lib/state/watch/watch_timer_push.dart`) sends `timer_state` through `WatchMirrorTransport.send`; `WatchConnectivityTransport.send` (`lib/core/platform/watch_transport.dart` ~l.250-295) answers `undelivered` for a non-durable frame when the watch is unreachable, and the push "re-offers at its next trigger" — but its only trigger is a change of the bound `WorkoutState` (`_onChanged`). The inbound-frame handler (`lib/state/watch/watch_sync_wiring.dart` ~l.327) flushes `push` (the session auto push) on every frame the wrist sends ("D-192(c): the frame proves the radio works") but NOT `timerPush`. So the `{round: null}` frame that releases the wrist stays unsent until the phone's state next changes.
2. Logs while locked: `WatchMenuState.isLocked` (`WatchMenu.swift` ~l.329) locks the jump; but `WatchLoggingState.log()` (`WatchLoggingState.swift` ~l.835) for a set effort needs no clock, and `workTimer` (~l.428) hides a phone timer of another slot from the current exercise, so the screen is a loggable set of B while the session is locked.

## Decision Ledger

- D-1 (phone) In the inbound handler of `lib/state/watch/watch_sync_wiring.dart` (`resolved.onIncoming`, ~l.327), where `if (!answeredReset) await push.flush();` is, the timer push is flushed too under the same gate: `if (!answeredReset) { await push.flush(); await timerPush.flush(); }`. Nothing else in `WatchTimerPush` changes; its ledger rules (earlier start wins, clears first, stale/adopted bookkeeping) stand.
- D-2 (watch) When `WatchSessionEngine` adopts a timer FROM A MESSAGE (`adoptTimer`, `WatchSessionEngine.swift` ~l.750; shared by `timer_state` and `session_snapshot`) that is a work kind (`elapsed`, `hold`, `round`), not stopped, and names a `sessionExerciseId` the session holds that is not the current exercise, the engine moves to that exercise with its own `selectExercise(slotId:)` (~l.343) after the timer row is stored. Not for `rest`, not for a stopped or cleared timer, not for a slot the session does not hold, not when the timer's slot is already current. The lock rule (`WatchMenuState.isLocked`) and the pager lock are unchanged.
- D-3 The jump uses the engine's existing select path, which emits an `exercise_advanced` lifecycle frame to the phone. The planner must check what the phone does with it (`lib/core/sync_protocol/session_reconciler.dart` ~l.150, `LiveSessionMirrorState`) and confirm it cannot move the phone's own screen or session position away from where the user is; if it can, the jump must not emit (a local-only selection) — raise under Open questions with the evidence.
- D-4 No wire, schema or contract change. No change to the Dart twin under `lib/watch` (not shipped on the Apple Watch).
- D-5 (resolves D-3; derived, vetoable until Phase 2A closes) The jump's `exercise_advanced` emission is safe: it cannot move the phone's own screen or session position. Evidence: the phone's inbound lifecycle for `exercise_advanced` only updates the mirror's record of where the wrist is (`lib/core/sync_protocol/session_reconciler.dart` `_applyLifecycle` ~l.146-154 sets the mirror's `_currentExerciseIndex`); the phone's own session screen keeps its own index (`lib/features/session/workout_session_screen.dart` ~l.116); the adoption bridge acts only on `completed`/`abandoned` (`lib/state/watch/watch_session_adoption_bridge.dart` `onLifecycle` ~l.750-768) and `consider()` is add-only for a session the phone already holds (~l.656-697, "no move of the position or the status", D-92); the mirror's converged index feeds only `projectedSession()` (`lib/state/watch/live_session_mirror_state.dart` ~l.299-318), which composes snapshot answers positioned at the receiver's place by design. So the jump emits normally; no local-only selection is needed.
- D-6 The jump fires only while the engine's held session is active. A timer frame that arrives when no session is held, or after the held session is completed or abandoned, stores per the existing rules but never jumps and never emits `exercise_advanced`; the jump candidate is discarded.
- D-7 Jump placement versus the non-reentrant mutex. `WatchAsyncMutex` is non-reentrant (`WatchAsyncMutex.swift`: "Do not call `exclusive` from inside a body that is itself inside the same mutex: the inner call would wait forever") and `selectExercise(slotId:)` reaches `transitionTo` (~l.1124), which is mutex-wrapped. Therefore the adopt path only COLLECTS a jump target; the jump is performed after the adopt call returns: in `applyTimerState` (~l.691-706) directly after `adoptTimers` returns (that call already runs outside the mutex), and in `applySnapshot` (~l.498) after `mutex.exclusive` returns (the exclusive body `applySnapshotExclusive` ~l.502 collects the target during its `adoptTimers` at ~l.562). Never call `selectExercise` from inside `mutex.exclusive`.
- D-8 Several jump candidates in one frame (a snapshot carrying running work timers for two different non-current slots): the earliest `startedAt` wins; a tie on `startedAt` resolves by `WatchTimerKind.all` order (`WatchRecords.swift` ~l.23-30: `[rest, round, hold, elapsed]`, so among work kinds round, then hold, then elapsed). At most one jump per frame.

## Readers listed

- `adoptTimer` / `adoptTimers` callers: `applyTimerState`, `applySnapshot`; tests in `watch/watchos/Tests/WatchSessionEngineTests/` that adopt a phone timer for another slot and expect the current exercise unchanged (grep `timer_state`, `isTimerFromMessage`, `S-1403`, `S-6004`, `WatchPagerFocusTests`, `WatchSharedTimerWireTests`): the builder lists each and what changes.
- `WatchLoggingState.workTimer`: "a clock the wrist started stays the running one across a jump" (S-1403) stays true; D-2 does not touch it.
- `lib/state/watch/watch_sync_wiring.dart`: tests that count frames after an inbound frame (grep `onIncoming`, `timerPush`, `test/watch_*wiring*`, `test/watch_timer_push_test.dart`).
- Scenario ids S-8401..S-8410 to be checked free by the builder.
- (planner enumeration 2026-10-23) The concrete Swift readers: `WatchLoggingTimersTests.swift` — `testS6005AnEarlierPhoneStartForAnotherSlotIsStored` (~l.1073; slot not held → no jump, stays green), `testS6005ALaterTimerForAnotherSlotIsStoredNotIgnored` (~l.1116; slot held → the test now also jumps; its assertions are about storage, not position, so they stay green), the same-slot S-6005 tests (~l.960-1060; current slot → no jump, green). `WatchTimedWorkTests.swift` — `testS6004APhoneTimerForAnotherSlotIsNotTheWristsWorkClock` (~l.1053) goes RED under D-2 (after adoption the engine jumps to `sx-other`, so `XCTAssertNil(surface.workTimer)` fails) and is reworked in Phase 2B; `testS6004AClockTheWristStartedSurvivesTheJump` (~l.1100) and `testS6004APhoneTimerWithNoSlotIsShownForTheCurrentSlot` (~l.1128) are unaffected (no slot id → no jump). `WatchSharedTimerWireTests` does not exist as a file — see Open questions Q2.
- (planner enumeration 2026-10-23) The concrete Dart readers of the inbound flush: `test/watch_timer_push_test.dart` (the S-200/S-205 groups count frames after inbound frames; the file's scenario map lists S-6211..S-7312). No dedicated wiring test file exists; `createWatchSync` is exercised across many test files, so the full suite is the guard.

## Core scenarios

Swift (`watch/watchos/Tests/WatchSessionEngineTests/WatchFollowPhoneEffortTests.swift`, new):
- S-8401 session with slots A, B, current B; a phone `timer_state` carrying a running `round` for A: `engine.currentExercise` is A, the lock is on, `WatchLoggingState` for A has `workTimer != nil`. Red: current stays B.
- S-8402 the same with kind `rest`, with a stopped round, with `{round: null}`, with a slot the session does not hold, with the current slot: current unchanged and no `exercise_advanced` frame emitted.
- S-8403 a `session_snapshot` whose timers name a running hold for A: moves to A (same rule on the snapshot path).
- S-8404 after the jump a clear `{round: null}` frame releases the lock (`isLocked == false`) and the wrist stays on A.
- S-8405 the wrist's own running clock (started on the wrist for B) is not displaced: a phone timer for A with an LATER start than the wrist's held timer of that kind is dropped by the earlier-start rule (D-4 of the engine) and causes no jump.

Dart (`test/watch_timer_push_test.dart` or the wiring test the planner finds):
- S-8406 a `timer_state` clear `{round: null}` returns `undelivered` once; then an inbound frame from the wrist arrives through the wiring's `onIncoming`: the clear is sent again and delivered. Red: no second send until the workout state changes.
- S-8407 an inbound frame the router answered with a reset (`answeredReset`) does not flush the timers (the same gate as `push`).

### Appended scenarios (Iteration 1)

- S-8411 an earlier-start drop causes no jump (mechanism correction for S-8405 — see Open questions Q1).
  - Fixture: engine holds a live session with slots A, B; current exercise B; the engine already holds a running `round` row stamped A (startedAt T0 — adopted earlier, surviving the position move per S-6004); a phone `timer_state` message carries a running `round` for A with startedAt T1 > T0.
  - Trigger: `applyTimerState` with that frame.
  - Flow: `adoptTimer`'s earlier-start rule is slot-scoped (`held.sessionExerciseId == slotId`, `WatchSessionEngine.swift` ~l.776-784), so the row is dropped and nothing is stored.
  - Expected: current exercise stays B; no `exercise_advanced` frame emitted; the held row (T0) unchanged.
  - Edge case of: S-8405, S-8401.
- S-8412 a paused phone timer still jumps.
  - Fixture: slots A, B, current B; a phone `timer_state` carries a `hold` for A with `stoppedAt == nil` and a pause stamp, startedAt T0.
  - Trigger: `applyTimerState`.
  - Flow: the paused row applies per the existing rules; D-2's "not stopped" reads `stoppedAt == nil`, so a paused timer is a jump candidate.
  - Expected: current exercise A; `WatchLoggingState.workTimer` for A is the paused hold; one `exercise_advanced` frame.
  - Edge case of: S-8401.
- S-8413 no jump for a session that is not active.
  - Fixture: engine adopted a session (slots A, B), then processed `session_finished` (status completed); a late phone `timer_state` carries a running `round` for A.
  - Trigger: `applyTimerState` after the finish.
  - Flow: D-6 gate — the held session's status is not active.
  - Expected: no jump, no `exercise_advanced` frame; the row stores (or is ignored) exactly per the existing rules — the test asserts only no-jump and no-frame.
  - Edge case of: S-8401.
- S-8414 a swipe in flight when the jump lands (existing behavior; no new code — the test documents the interaction).
  - Fixture: slots A, B, C; current B; a swipe toward A is in flight (`WatchLoggingState.focusSlotId == A`, engine still B); a phone `timer_state` carries a running `round` for C.
  - Trigger: the jump to C lands, then the in-flight swipe settles on A.
  - Flow: the jump locks the menu (a running work timer of the session is on, `WatchMenuState.isLocked` ~l.322-332); the settled swipe is refused by the lock and `land(on:)` clears the focus (existing S-7916 behavior).
  - Expected: current exercise C; exactly one `exercise_advanced` frame (the jump's); focus nil; no second select.
  - Edge case of: S-8401.
- S-8415 two candidates in one snapshot — earliest start wins.
  - Fixture: slots A, B, C; current B; one `session_snapshot` whose timers carry a running `round` for A (startedAt T0) and a running `hold` for C (startedAt T1 > T0).
  - Trigger: `applySnapshot`.
  - Flow: D-8 tie-break during the adopt pass.
  - Expected: current exercise A; one `exercise_advanced` frame; both rows stored.
  - Edge case of: S-8403.

## Phases

- P1 `developer` — Dart: D-1 and S-8406, S-8407. Done: the touched test files and `flutter analyze` (180 baseline).
- P2 `developer` — Swift: D-2 (and D-3's outcome) with S-8401..S-8405 and the listed reader updates. Done: `swift test`.
- P3 `developer` — docs: `docs/state_management/watch_surface_wrist.md` (lock and follow rules), the doc that describes `WatchTimerPush` (grep `WatchTimerPush` in `docs/`), plan Progress.
- Governor after P3: full `swift test`, `xcodebuild`, `flutter analyze`, full `flutter test` once, `prove-red`, review, commit per phase.

## Owner checks (owner)

- (owner) Start a round on the phone while the watch shows another exercise: the watch jumps to the running exercise. Log the round on the phone while the wrist is down/asleep, then raise the wrist: the watch lets you switch exercises again.

## Scope budget

About 40 production lines (Swift ~35, Dart ~3), about 300 of test. Two tracks, three phases.
- (planner 2026-10-23) Measured against `.github/copilot/pr-scope-budget.md`: 3 implementation phases (≤ 5), 8 ledger decisions (≤ 20), 12 scenarios (≤ 30), ~40 production lines (≤ ~1,500). Two tracks and a plan near the 500-line soft line are two soft signals, but the governor seeded this exact shape as one PR (the scope line above is the seed's); the hard limits are not hit, so no split.

## Feature Invariants

- The lock rule is unchanged: `WatchMenuState.isLocked` locks on any running work timer of the session regardless of slot and clears when it ends; 54 adds a jump, never a second lock or an unlock.
- The jump reuses the engine's own select path (`selectExercise(slotId:)`); no second movement mechanism is added, and the pager needs no change (`WatchPagerModel.currentIndex` is derived from the rows' `isCurrent` on every access, `WatchPagerModel.swift` ~l.41).
- `WatchTimerPush`'s ledger rules stand (earlier start wins, clears first, stale/adopted bookkeeping); D-1 only adds a trigger.
- No wire, schema or contract change (D-4); the Dart twin under `lib/watch/` is untouched.
- Every rule here is engine-level: the jump is decided in `WatchSessionEngine`, not in a view or the pager.

## Requirements

- R1 The wrist moves to the exercise a phone-started work effort is running on, as soon as the timer arrives (D-2; S-8401, S-8403, S-8412, S-8415).
- R2 The wrist does not move for a rest, a stopped or cleared timer, an unheld slot, the current slot, a dropped (earlier-start) row, or an inactive session (S-8402, S-8411, S-8413).
- R3 The end of the phone's effort reaches the wrist at the next conversation, not only at the next phone state change (D-1; S-8406); a reset-answered frame still flushes nothing (S-8407).
- R4 Nothing of the previously shown exercise can be logged by mistake after the jump: the lock is on while the effort runs and the running effort's Log is the one shown (S-8401, S-8404, S-8414).

## Acceptance Criteria

- AC1 → S-8401, S-8403, S-8412, S-8415 (jump happens, one `exercise_advanced` frame each).
- AC2 → S-8402, S-8411, S-8413 (no jump, no frame).
- AC3 → S-8406, S-8407 (re-offer on an inbound frame; gate respected).
- AC4 → S-8404, S-8414 (lock clears on the clear frame; a swipe in flight is refused and the focus clears).

## Existing-Functionality Impact

| Touched surface | What already reads it (grep that found it) | Effect | Guarded by |
|---|---|---|---|
| `watch_sync_wiring.dart` inbound handler (`resolved.onIncoming`, ~l.327-341) | `grep -n "onIncoming" lib/state/watch/watch_sync_wiring.dart`; frame-counting tests: `test/watch_timer_push_test.dart` S-200/S-205 groups | one more flush per inbound frame, under the existing reset gate | S-8406, S-8407 |
| `WatchTimerPush.flush()` (`lib/state/watch/watch_timer_push.dart`) | `grep -rn "timerPush" lib test` → wiring (~l.298 build, ~l.355 graph), `lib/main.dart` binding, `test/watch_timer_push_test.dart` | now also called for `timerPush`; `flush()` joins a running drain, so a concurrent pass is safe | S-8406 |
| `WatchSessionEngine.adoptTimer` / `adoptTimers` (`WatchSessionEngine.swift` ~l.752-810 / ~l.716-750) | `grep -rn "adoptTimers\|adoptTimer(" watch/watchos/Sources` → `applyTimerState` (~l.691), `applySnapshotExclusive` (~l.562) | after a stored row, a jump target is collected; the jump runs after the adopt call returns (D-7) | S-8401..S-8405, S-8411..S-8413, S-8415 |
| `WatchSessionEngine.selectExercise(slotId:)` (~l.343-356) | `grep -rn "selectExercise" watch/watchos` → menu select path, pager `land(on:)`, engine | gains one caller (adoption); emission unchanged | S-8402 (no frame when no jump), S-8414 (one frame) |
| `WatchTimedWorkTests.testS6004APhoneTimerForAnotherSlotIsNotTheWristsWorkClock` (~l.1053) | `grep -rn "S-6004" watch/watchos/Tests` | goes RED under D-2; reworked in Phase 2B | Phase 2B item 6 |
| `WatchLoggingTimersTests` S-6005 group (~l.960-1180) | `grep -rn "S-6005" watch/watchos/Tests` | stays green (assertions are about storage, not position); ~l.1116 test now also jumps | Phase 2B item 6 re-check |
| `WatchLoggingState.workTimer` (~l.428-447) | `grep -rn "workTimer" watch/watchos` | unchanged; the S-1403 hiding rule stands | existing S-6004/S-1403 tests |
| `WatchPagerModel` (`WatchPagerModel.swift` ~l.41) | `grep -rn "currentIndex" watch/watchos/Sources/WatchSessionEngine/WatchPagerModel.swift` | no change; the jump moves the pager because the index is derived | existing S-6607 (`testS6607APhoneSideAdvanceIsVisibleOnTheNextRead`) |
| `session_reconciler.dart` `_applyLifecycle` (~l.146-154) | `grep -n "exercise_advanced" lib/core/sync_protocol/session_reconciler.dart` | receives the jump's frame; moves only the mirror's wrist-position record, never the phone's screen (D-5) | D-5 evidence; existing mirror tests |
| `watch_session_adoption_bridge.dart` `consider` / `onLifecycle` (~l.656-697 / ~l.750-768) | `grep -n "consider\|onLifecycle" lib/state/watch/watch_session_adoption_bridge.dart` | unaffected: add-only for a held session, acts only on `completed`/`abandoned` (D-5) | D-5 evidence |
| `live_session_mirror_state.dart` `projectedSession()` (~l.299-318) | `grep -n "projectedSession" lib/state/watch/live_session_mirror_state.dart` | unaffected: composes snapshot answers positioned at the receiver's place by design (D-5) | D-5 evidence |

## UI Standards Impact

None — no widget, layout or copy change. The jump reuses the existing select path and the existing lock/pager rendering (`docs/state_management/watch_surface_wrist.md`, sections "The work clock names its exercise" and "The logging screen pages the session's exercises", describe both and stay true).

## Iteration 1 — expanded phases

Shell for every phase: only `.github/copilot/scripts/macos/gateway.sh` (`lint`, `test`, `swift-test`, `prove-red`, git views). `xcodebuild` is the governor's only — never in Done Criteria. `flutter analyze` exits non-zero while the repo carries pre-existing notices: compare the issue count with the 180 baseline. A widget test that opens the Hive harness or awaits a real `Future.delayed` inside `testWidgets` hangs forever (FakeAsync): the Dart tests here are plain `test()` in `test/watch_timer_push_test.dart`, which is safe.

### Phase 1: Dart — the timer push flushes on an inbound frame (@developer)

1. [x] Red test S-8406 — `test/watch_timer_push_test.dart`, new plain `test()` beside the S-6321..S-6330 clear groups (symbol: `test("S-8406 an inbound frame from the wrist re-offers an undelivered timer clear")`). Fixture: `startGraph()` (~l.232) + `wristStartsTimedSession()` (~l.248) + `adoptedInterval()` (~l.365); `_PhoneRadio` (~l.156-200) with `unreachable = true`. Trigger: the phone ends the adopted interval while unreachable, so a clear (`{elapsed: null}` — the harness's timed slot yields `elapsed`, not `round`; the clear rule is kind-independent) is owed; then the radio becomes reachable and an inbound wrist frame arrives through the wiring's `onIncoming`. Expected: the clear appears in `radio.sent` and is delivered. Red: no second send until the bound `WorkoutState` changes.
2. [x] Apply D-1 — `lib/state/watch/watch_sync_wiring.dart`, the inbound handler (`resolved.onIncoming`, ~l.327-341): replace `if (!answeredReset) await push.flush();` with `if (!answeredReset) { await push.flush(); await timerPush.flush(); }` (`timerPush` is built at ~l.298, in scope). Nothing else changes.
3. [x] Guard test S-8407 — same file, `test("S-8407 a reset-answered inbound frame does not flush the timers")`: an inbound frame the router answered with a reset (`answeredReset`) sends no `timer_state` frame (`radio.sent` gains nothing). Red state produced by the mutation "flush `timerPush` unconditionally, outside the `answeredReset` gate"; green with D-1 as written.
4. [x] Run `.github/copilot/scripts/macos/gateway.sh test` (full suite, 900 s) and `.github/copilot/scripts/macos/gateway.sh lint`; paste pass/fail counts and the analyze issue count into the evidence file; update Progress and the Assumption Log.

**Results** (evidence: `.evidence.md`, "Implementer evidence → P1"): S-8406 red at HEAD, green after; S-8407 green, mutation-proven red. Item 2 was delivered as `timerPush.flushClears()` (clears only), not a full `flush()` — see Assumption Log (a full flush re-offered a start to a wrist that had already ended the timer and turned S-6322/S-6323/S-6324/S-7305 red). Full suite 5436 passed / 2 skipped / 0 failed; lint 180 issues, 0 errors; file +43. Outside Predicted Files: `lib/state/watch/watch_timer_push.dart` (+15, the clears-only mode).

**Done Criteria** (run until green): `.github/copilot/scripts/macos/gateway.sh lint` (≤ 180 issues), `.github/copilot/scripts/macos/gateway.sh test` (S-8406 and S-8407 passing, no previously green test red).
**Predicted Files**: `test/watch_timer_push_test.dart`, `lib/state/watch/watch_sync_wiring.dart` — nothing else.

### Phase 2A: Swift — the engine jump, happy path and negatives (@developer)

1. [ ] Red test S-8401 — new file `watch/watchos/Tests/WatchSessionEngineTests/WatchFollowPhoneEffortTests.swift`, `testS8401APhoneTimerForAnotherSlotMovesTheEngineToItsSlot`: engine with slots A, B, current B; `applyTimerState` with a message-borne running `round` for A. Assert `currentExercise` is A, the menu lock is on, `WatchLoggingState` for A has `workTimer != nil`, and exactly one `exercise_advanced` frame was emitted. Red: current stays B.
2. [ ] Implement D-2 + D-6 — `watch/watchos/Sources/WatchSessionEngine/WatchSessionEngine.swift`, `adoptTimer` (~l.752-810): on the stored-row path (the earlier-start drop at ~l.776-784 returns false and stores nothing), if the kind is a work kind (`elapsed`, `hold`, `round` — not `rest`), `stoppedAt == nil` (a paused timer counts as running), the `sessionExerciseId` is held by the session, is not the current slot, and the held session's status is active, record the slot as the frame's jump target (D-8's tie-break applies when `adoptTimers` collects several). Do not jump here (D-7).
3. [ ] Implement D-7 — same file: `applyTimerState` (~l.691-706) performs the jump via `selectExercise(slotId:)` directly after `adoptTimers` returns; `applySnapshot` (~l.498) performs it after `mutex.exclusive` returns, using the target `applySnapshotExclusive` (~l.502, `adoptTimers` at ~l.562) collected. Never call `selectExercise` from inside `mutex.exclusive` (`WatchAsyncMutex` is non-reentrant).
4. [ ] Green S-8402 — same new file, the negative matrix (`testS8402...` per case): kind `rest`, a stopped round, `{round: null}`, a slot the session does not hold, the current slot — current unchanged, no `exercise_advanced` frame. Red state produced by the mutation "drop the kind/stopped checks so a rest or a stopped timer also jumps".
5. [ ] Green S-8403 — `testS8403ASnapshotTimerForAnotherSlotMovesTheEngine`: a `session_snapshot` whose timers name a running hold for A moves to A (the snapshot path shares the rule). Red before item 3's snapshot-side jump.
6. [ ] Green S-8415 — `testS8415TwoCandidatesInOneSnapshotEarliestStartWins` (fixture above; D-8). Red before item 2's tie-break.
7. [ ] Run `.github/copilot/scripts/macos/gateway.sh swift-test` (900 s); paste counts into the evidence file; update Progress and the Assumption Log.

**Done Criteria**: `.github/copilot/scripts/macos/gateway.sh swift-test` green with S-8401..S-8403 and S-8415 passing and the existing S-6004/S-6005 groups still green — except the one known red, `testS6004APhoneTimerForAnotherSlotIsNotTheWristsWorkClock`, which is expected red here and reworked in Phase 2B (record it; do not fix it in 2A).
**Predicted Files**: `watch/watchos/Sources/WatchSessionEngine/WatchSessionEngine.swift`, `watch/watchos/Tests/WatchSessionEngineTests/WatchFollowPhoneEffortTests.swift` — nothing else.

### Phase 2B: Swift — edges and the reader rework (@developer) — BLOCKS Phase 2A closure

1. [ ] Guard S-8404 — `WatchFollowPhoneEffortTests.swift`, `testS8404AClearFrameReleasesTheLockAndTheWristStays`: after the S-8401 jump, a `{round: null}` frame makes `isLocked == false` and the wrist stays on A. Red state produced by the mutation "treat a cleared timer as a jump candidate" (D-2's not-stopped/cleared exclusion).
2. [ ] Edge S-8411 — `testS8411AnEarlierStartDropCausesNoJump` (fixture above): the slot-scoped earlier-start drop stores nothing, so no jump and no frame. Red state produced by the mutation "jump on a dropped row" (removing D-2's stored-row-only condition).
3. [ ] Edge S-8412 — `testS8412APausedPhoneTimerStillJumps` (fixture above). Red state produced by the mutation "require a running (unpaused) timer to jump".
4. [ ] Edge S-8413 — `testS8413NoJumpForAnInactiveSession` (fixture above; D-6). Red state produced by the mutation "remove the active-session gate".
5. [ ] Interaction S-8414 — `testS8414ASwipeInFlightWhenTheJumpLandsIsRefusedAndTheFocusClears` (fixture above; existing S-7916 behavior, no production change expected).
6. [ ] Rework the red reader — `watch/watchos/Tests/WatchSessionEngineTests/WatchTimedWorkTests.swift`, `testS6004APhoneTimerForAnotherSlotIsNotTheWristsWorkClock` (~l.1053): under D-2 the engine jumps to `sx-other` after adoption, so `XCTAssertNil(surface.workTimer)` fails. Rework so the S-1403 hiding rule stays covered: move the hiding assertion to a fixture whose timer's slot the session does NOT hold (no jump), and assert the new jump outcome in the held-slot case (or split into two tests). Re-check `testS6005ALaterTimerForAnotherSlotIsStoredNotIgnored` (~l.1116) stays green (it now also jumps; its assertions are about storage).
7. [ ] Run `.github/copilot/scripts/macos/gateway.sh swift-test`; paste counts; update Progress and the Assumption Log.

**Done Criteria**: `.github/copilot/scripts/macos/gateway.sh swift-test` fully green (S-8404, S-8411..S-8414 passing; the reworked S-6004 test green; no other test red).
**Predicted Files**: `watch/watchos/Tests/WatchSessionEngineTests/WatchFollowPhoneEffortTests.swift`, `watch/watchos/Tests/WatchSessionEngineTests/WatchTimedWorkTests.swift` — nothing else (no production change expected; if S-8414 or the rework forces one, log it in the Assumption Log).

### Phase 3: docs (@developer)

1. [ ] `docs/state_management/watch_surface_wrist.md` — in "The work clock names its exercise" (~l.281-311), after the adoption-rules sentence (ending "…the earlier start wins at adoption`)"), add the follow rule: a phone timer for another slot, adopted from a message, moves the wrist to that exercise with the engine's own select path (one `exercise_advanced` frame); not for a rest, a stopped or cleared timer, an unheld slot or the current slot; the earlier-start drop stores nothing and causes no jump; the lock and pager rules are unchanged. Name `WatchFollowPhoneEffortTests.swift` and the S-8401..S-8415 ids. The doc is 36.2 KB (under the 52 KB band) and carries plan 53's uncommitted food edits — edit on top, never revert them.
2. [ ] `docs/state_management/watch_surface.md` — the `WatchTimerPush` paragraph (~l.222-240): add that the inbound-frame handler flushes the timer push too, under the same reset gate as the auto push (D-1), so a wrist out of reach is served at the next frame the wrist sends, not only at the next phone state change. The doc is 41.2 KB (under the 52 KB band); same plan-53 caution.
3. [ ] `docs/watch_session_capture.md` — in "Why the phone's running timer is told to the wrist", the "Limits, stated not fixed" list (~l.310): update "a wrist out of reach is served at the next phone notification" to "…at the next phone notification or the next frame the wrist sends" (D-1). The doc is 32.1 KB (under the 52 KB band).
4. [ ] Update this plan's Progress and adjudicate the Assumption Log (RATIFY/REVERT each entry).

**Done Criteria**: the three docs each stay under 52 KB; `test/docs_indexing_contract_test.dart` (runs inside `gateway.sh test`) still green; no doc claims a behavior the code does not have.
**Predicted Files**: the three docs and this plan file — nothing else.

## Files Affected

- `lib/state/watch/watch_sync_wiring.dart` (P1, D-1)
- `test/watch_timer_push_test.dart` (P1, S-8406/S-8407)
- `watch/watchos/Sources/WatchSessionEngine/WatchSessionEngine.swift` (P2A, D-2/D-6/D-7/D-8)
- `watch/watchos/Tests/WatchSessionEngineTests/WatchFollowPhoneEffortTests.swift` (new, P2A/P2B)
- `watch/watchos/Tests/WatchSessionEngineTests/WatchTimedWorkTests.swift` (P2B, the S-6004 rework)
- `docs/state_management/watch_surface_wrist.md`, `docs/state_management/watch_surface.md`, `docs/watch_session_capture.md` (P3)
- Readers that only observe a touched surface (no edit expected): `WatchLoggingTimersTests.swift`, `WatchPagerModel.swift`, `WatchMenu.swift`, `WatchLoggingState.swift`, `lib/core/sync_protocol/session_reconciler.dart`, `lib/state/watch/watch_session_adoption_bridge.dart`, `lib/state/watch/live_session_mirror_state.dart`, `lib/state/watch/watch_timer_push.dart`.

## Notes

- Phase dependency graph: P1 is independent of P2A/P2B (different tracks); P2B needs P2A; P3 needs P2B (it documents the final behavior). P1 could run after P2 with no change; running P1 first gives the lock-clear fix (the owner's second complaint) earliest.
- Intermediate state after P1 alone: the lock clears at the next conversation, but the wrist still does not follow the phone's effort. After P2A alone: the jump works on the timer path and the snapshot path; the S-6004 reader test is red until 2B.
- The harness's timed slot yields `elapsed`, not `round` (S-8406 fixture note); the clear-frame rule is kind-independent, so the test asserts on `{elapsed: null}`.
- The engine holds one timer row per kind; a row for A survives the position moving to B (S-6004), which is what makes S-8411's fixture reachable.
- `WatchAsyncMutex` is non-reentrant — the D-7 placement rule is a correctness constraint, not a style choice; a jump inside `mutex.exclusive` deadlocks.
- The builder may use scenario ids S-8408..S-8410 (seeded as free) for scenarios it finds; S-8411..S-8415 are taken by this expansion.

## Progress

- [x] P1 Dart flush (Phase 1) — **Complete**: the wrist's inbound frame re-offers the owed timer clear via `timerPush.flushClears()` under the `!answeredReset` gate; S-8406/S-8407 green, file +43, full suite 5436/2 skipped/0 failed, lint 180/0 errors.
- [ ] P2A Swift jump (Phase 2A) —
- [ ] P2B edges + reader rework (Phase 2B) —
- [ ] P3 docs (Phase 3) —
- [ ] Governor: full suites, `xcodebuild`, `prove-red`, review, commits —

## Assumption Log

- (planner, D-5) D-3's open check resolved as "the jump may emit": options were emit normally vs a local-only selection; chose emit because the phone's inbound `exercise_advanced` handling only records where the wrist is (evidence in D-5). Vetoable until Phase 2A closes.
- (builder, S-8406) The harness's timed slot yields `elapsed`, not `round`; the clear rule is kind-independent, so the test uses `{elapsed: null}`. Options: force a round fixture vs use the harness's kind; chose the harness's kind.
- (builder, D-2) "Not stopped" reads `stoppedAt == nil`, so a paused timer is a jump candidate (S-8412). Options: running-only vs not-stopped; chose not-stopped, matching the adoption rules' own treatment of paused rows.
- (builder, D-7) The jump target is collected during adopt and performed after the adopt call returns. Options: jump inside adopt (deadlocks under `mutex.exclusive`) vs deferred; chose deferred.
- (builder, D-1) The trigger flushes clears only (`timerPush.flushClears()`), not a full `flush()`. A full flush re-offered the phone's still-running timer as a start to a wrist that had already ended it and turned S-6322/S-6323/S-6324/S-7305 red; clears still go out at once, starts keep their phone-state-change trigger.
- (builder, S-8407) The fixture's debt is a delivered rest's clear, not an adopted timer's: a reset answer switches the mirror session, which retires an adopted timer (`_mirrorHolds` false), while a `_delivered` clear survives the switch — the only shape that shows the gate withholding a frame it still owes.

## Open questions

- Q1 (seed inconsistency, kept verbatim) S-8405's fixture text says the wrist's held timer is "for B" while the phone's later timer is "for A" — but the engine's earlier-start rule is slot-scoped (`held.sessionExerciseId == slotId`, `WatchSessionEngine.swift` ~l.776-784), so a cross-slot later timer is STORED (and now jumps), not dropped. The drop needs the held row and the incoming timer to name the SAME slot. S-8405 is kept as written (seeded); S-8411 is the corrected mechanism. The builder should implement S-8405's intent (no jump on a drop) via S-8411's fixture.
- Q2 (seed pointer correction) `WatchSharedTimerWireTests` does not exist as a file in `watch/watchos/Tests/WatchSessionEngineTests/`; the shared-timer wire tests the seed's grep hint points at live in `WatchLoggingTimersTests.swift` (the S-6005 group) and `WatchTimedWorkTests.swift` (the S-6004 group). No seeded entry depends on the file name.
- Q3 (baseline not re-verified) The 180-issue `flutter analyze` baseline is the seed's number; the planner did not run `lint` (the implementer's Done Criteria re-check it anyway). If the count differs at P1, record the actual baseline in the evidence file and compare against that.
- Q4 (shared files with plan 53) `docs/state_management/watch_surface.md` and `watch_surface_wrist.md` carry plan 53's uncommitted edits in the working tree (and 53's P3 code landed as commit `1f7a159d` during planning). P3 edits on top of whatever the tree holds and must not revert 53's text.

## Feedback

[empty — fold into a new Iteration block when non-empty, then clear]
