# Evidence — plan 54 (wrist follows phone effort)

Planner verification notes (conductor-v2, 2026-10-23). Base commit `.work/2026-10-22-54/base.txt` = `39915055`; during planning, plan 53's P3 code landed as `1f7a159d` on the same branch (`claude_develop`, ahead 29 at planning start). Implementers append their suite outputs below the planner sections.

## Planner pointer verification (every file:symbol the seed cites)

| Seed pointer | Verified | Note |
|---|---|---|
| `watch_transport.dart` ~l.250-295 `undelivered` for non-durable frames when unreachable | `WatchConnectivityTransport.send` | root cause 1 stands |
| `watch_sync_wiring.dart` ~l.327 inbound handler flushes `push` only | handler at ~l.327-341, exact line `if (!answeredReset) await push.flush();`; `timerPush` built ~l.298, graph field ~l.355 | D-1 target |
| `watch_timer_push.dart` only trigger is `_onChanged` | full read; `flush()` exists and joins a running drain | root cause 1 stands |
| `session_reconciler.dart` ~l.150 lifecycle | `_applyLifecycle` ~l.146-154 handles `exercise_advanced` by setting the mirror's `_currentExerciseIndex` | D-3/D-5 evidence |
| `WatchMenu.swift` ~l.329 `isLocked` | ~l.322-332; locks on ANY running work timer of the session regardless of slot; `jump(to:)` ~l.334-346 refused while locked | root cause 2 stands |
| `WatchLoggingState.swift` ~l.835 `log()` | ~l.835-880; a set needs no clock → loggable while locked; `workTimer` ~l.428-447 hides another slot's message timer; `canLog` ~l.269-271; `focusSlotId` ~l.566 | root cause 2 stands |
| `WatchSessionEngine.swift` ~l.750 `adoptTimer`, ~l.343 `selectExercise` | `adoptTimer` ~l.752-810 (earlier-start rule slot-scoped at ~l.776-784: `held.sessionExerciseId == slotId`), `adoptTimers` ~l.716-750, `selectExercise(slotId:)` ~l.343-356 (emits `exercise_advanced` via `transitionTo` ~l.1124), `applyTimerState` ~l.691-706 (adoptTimers NOT under mutex), `applySnapshot` ~l.498 / `applySnapshotExclusive` ~l.502 (adoptTimers ~l.562 INSIDE `mutex.exclusive`), `timerFor` ~l.187-189, `isTimerFromMessage` ~l.1807-1809 | D-2/D-7 targets |
| `WatchAsyncMutex` non-reentrant | header comment: "Do not call `exclusive` from inside a body that is itself inside the same mutex: the inner call would wait forever" | D-7 constraint |
| `WatchPagerModel` | `currentIndex` derived from rows' `isCurrent` (~l.41); `isLocked`/`showsPager` ~l.42-43; `focusSlotId(for:)` nil for a locked session (S-7912) | no pager change needed |
| `WatchTimerKind.all` | `WatchRecords.swift` ~l.23-30: `[rest, round, hold, elapsed]` | D-8 tie order |

## D-3 resolution evidence (→ D-5)

The wrist's post-jump `exercise_advanced` + snapshot cannot move the phone's own screen or position:
- `watch_session_adoption_bridge.dart` `onLifecycle` (~l.750-768) acts only on `completed`/`abandoned`; `consider()` (~l.656-697) returns `alreadyHeld` for the phone's own session and acts add-only on slots ("no move of the position or the status", D-92).
- The phone screen keeps its own `_currentExerciseIndex` (`workout_session_screen.dart` ~l.116); the mirror's converged index feeds only `projectedSession()` (`live_session_mirror_state.dart` ~l.299-318), which composes snapshot answers positioned at the receiver's place by design.

## Test readers enumerated (planner)

- `WatchLoggingTimersTests.swift`: `testS6005AnEarlierPhoneStartForAnotherSlotIsStored` ~l.1073 (stays green), `testS6005ALaterTimerForAnotherSlotIsStoredNotIgnored` ~l.1116 (now also jumps; assertions about storage → green), same-slot S-6005 tests ~l.960-1060 (green).
- `WatchTimedWorkTests.swift`: `testS6004APhoneTimerForAnotherSlotIsNotTheWristsWorkClock` ~l.1053 (RED under D-2 → rework in 2B); `testS6004AClockTheWristStartedSurvivesTheJump` ~l.1100 and `testS6004APhoneTimerWithNoSlotIsShownForTheCurrentSlot` ~l.1128 (unaffected).
- `WatchPagerFocusTests.swift`: focus/lock mechanics read; S-7916 covers the refused landing + focus clear (S-8414 builds on it).
- `test/watch_timer_push_test.dart`: `_PhoneRadio` ~l.156-200 (`unreachable`, `attempted`/`sent`, `fromWrist()`), `startGraph()` ~l.232, `wristStartsTimedSession()` ~l.248, `adoptedInterval()` ~l.365; plain `test()` (no FakeAsync); scenario map S-6211..S-7312. The harness's timed slot yields `elapsed`, not `round`.

## Baselines (planner; not re-run)

- `flutter analyze`: 180 issues (the seed's number; not re-run by the planner — see plan Open questions Q3).
- Full `flutter test` and `swift test`: not run by the planner; the gateway checks (`test` 900 s, `swift-test` 900 s) are the implementers' Done Criteria.
- Doc sizes at planning: `watch_session_capture.md` 32.1 KB, `watch_surface_wrist.md` 36.2 KB, `watch_surface.md` 41.2 KB — all under the 52 KB band.
- Working tree at planning: `docs/state_management/watch_surface.md` and `watch_surface_wrist.md` modified (plan 53's uncommitted doc edits); plan-54 and plan-55 folders untracked.

## Implementer evidence

(P1 — paste `gateway.sh test` pass/fail counts, the analyze issue count, and the S-8406/S-8407 red→green table.)

(P2A/P2B — paste `gateway.sh swift-test` counts and the per-S-id red→green table, including the expected-red `testS6004APhoneTimerForAnotherSlotIsNotTheWristsWorkClock` between 2A and 2B.)

(P3 — paste the three docs' sizes after the edits.)
