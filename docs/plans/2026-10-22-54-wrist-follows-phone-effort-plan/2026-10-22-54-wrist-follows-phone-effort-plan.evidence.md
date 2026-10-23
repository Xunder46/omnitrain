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

### P1 — the wrist's frame re-offers the timer clear (developer, 2026-10-23)

Baselines re-checked: `gateway.sh lint` → `180 issues found`, 0 errors (equals the plan's
180 baseline — plan Open question Q3 answered: unchanged), no issue in either touched file.
Base for `prove-red`: `HEAD` (the change is uncommitted in the working tree).

| Scenario | Test | Before the change | After |
|---|---|---|---|
| S-8406 | `S-8406 an inbound frame from the wrist re-offers an undelivered timer clear` | RED — `Expected: an object with length of <1>, Actual: []` at `test/watch_timer_push_test.dart:1622` | PASS |
| S-8407 | `S-8407 a reset-answered inbound frame withholds the clear it owes, and the debt survives for the next call` | PASS at HEAD (guard — proven by mutation below) | PASS |

Prove-red verdict (`gateway.sh prove-red HEAD test test/watch_timer_push_test.dart`):

```
gateway: prove-red: RED AT HEAD (exit 1). It proves the guard only if an assertion fails for
the reason the test guards; a compile or load error means the test could not run there
00:00 +24 -1: S-8406 ...[E]
  Expected: an object with length of <1>
    Actual: []
  S-8406 the frame the wrist sent proves the radio works, so the owed clear goes out now,
  not at the next phone state change
  test/watch_timer_push_test.dart 1622:9
```

S-8407 mutation (the guard cannot fail at HEAD, so a mutation proves it). Original wiring line
recorded verbatim:

```
    if (!answeredReset) {
      await push.flush();
      await timerPush.flushClears();
    }
```

Mutant: `await timerPush.flushClears();` moved below the block, so a reset-answered frame flushes
too → only S-8407 red:

```
00:00 +25 -1: S-8407 ...[E]  Expected: an object with length of <1>, Actual: [<rest start>, <rest: null>]
  S-8407 the reset answer flushes no timers        test/watch_timer_push_test.dart 1712:7
```

The exact original was restored and the file re-ran green (+43).

Second guard, observed rather than asserted: the trigger sends **clears only** (`flushClears()`),
not a full `flush()`. Reading D-1 literally (a full `timerPush.flush()` at the trigger) turned four
existing readers red in the same file — S-6322 (`:1157`), S-6323, S-6324, S-7305 — each because the
pass re-offered the phone's still-running timer as a *start* to a wrist that had already ended it
(S-6322's `Actual` shows the `elapsed` start then its clear; S-7305's the running `rest` then its
clear). They are green before and after the delivered change, and are the guard for the clears-only
reading. Mid-run state for the record: that file was `+39 -4` under the literal reading.

Suite outputs (real counts):

- `gateway.sh test -- test/watch_timer_push_test.dart` → `00:00 +43: All tests passed!`
- full `gateway.sh test` → `03:09 +5436 ~2: All tests passed!` (5436 passed, 2 skipped, 0 failed)
- `gateway.sh test -- test/ui_standards_contract_test.dart` → `00:00 +29: All tests passed!` (no allowlist entry added, no ratchet raised)

Diff footprint: 3 files, +190 −1 (`watch_sync_wiring.dart` +8 −1, `watch_timer_push.dart` +15,
`watch_timer_push_test.dart` +168). No Swift, no docs in P1 (P3 owns the doc pass; the new
`WatchTimerPush.flushClears()` belongs in P3's `watch_surface.md` / `watch_surface_wrist.md` write-up).

### P1 fix round 1 — an ordinary flush is not starved by a clears-only drain (S-8408)

Defect: `flushClears()` set the instance flag `_clearsOnly` before calling `flush()`. A `flush()`
that joined the running drain only set `_again`, so the extra pass still saw `_clearsOnly == true`
and dropped `next`, withholding the phone's NEW start with nothing recording or re-triggering it.

Fix (per-request pass mode, not an instance flag):

```dart
  Future<void> flushClears() => _flush(clearsOnly: true);
  Future<void> flush() => _flush(clearsOnly: false);
  ...
    if (running != null) {
      _again = true;
      if (!clearsOnly) _fullAgain = true;
      return running;
    }
  ...
        onlyClears = !_fullAgain;
        _fullAgain = false;
```

Test S-8408 (`test/watch_timer_push_test.dart`, after the S-8407 group) uses the fixture S-8406
starts from (`adoptedInterval()`), then: `finishTimedEntry` owes a clear → `_PhoneRadio.holdSend()`
holds the clears-only frame in flight → the phone starts its next interval → `flush()` joins →
`releaseSend()`. Asserted: two `timer_state` frames (clear, then the start), the second carries the
phone's own `startedAt`, and the wrist clock ends on it.

Red before the fix (current tree, S-8408 the only failure; the other 43 in the file green):

```
00:00 +26 -1: S-8408 ... [E]
  Expected: an object with length of <2>
    Actual: [{'type': 'timer_state', 'payload': {'timers': {'elapsed': null}}}]
     Which: has length of <1>
  S-8408 the clear and then the start the phone owes are two frames
```

Mutation (prove-red cannot use HEAD: HEAD predates `flushClears`). Original line recorded
verbatim — `        onlyClears = !_fullAgain;` — replaced by `        onlyClears = true;`:
same single failure (`+43 -1`, length 1, only the `elapsed: null` frame). The exact original was
restored and the file re-ran green.

Suite outputs (real counts):

- `gateway.sh test test/watch_timer_push_test.dart` → `00:00 +44: All tests passed!`
- full `gateway.sh test` → `03:08 +5437 ~2: All tests passed!` (5437 passed, 2 skipped, 0 failed)
- `gateway.sh lint` → `180 issues found`, 0 errors (unchanged baseline)
- `gateway.sh test test/ui_standards_contract_test.dart` → `00:00 +29: All tests passed!`

Diff footprint of this round: `watch_timer_push.dart` +21 −9, `watch_timer_push_test.dart` +107.
No Swift, no docs; the public contract of `flush()` / `flushClears()` is unchanged.

(P2A/P2B — paste `gateway.sh swift-test` counts and the per-S-id red→green table, including the expected-red `testS6004APhoneTimerForAnotherSlotIsNotTheWristsWorkClock` between 2A and 2B.)

(P3 — paste the three docs' sizes after the edits.)

## Feedback

- P1 fix round 1 (developer, 2026-10-23): `flushClears()`' instance-wide `_clearsOnly` made a joining ordinary `flush()` run clears-only and withhold the phone's new start; the pass mode is now per request (`_flush({required bool clearsOnly})` plus `_fullAgain`). S-8408 added and shown red before the fix and green after; full suite 5437 passed / 2 skipped / 0 failed, lint 180 issues. Only `watch_timer_push.dart` and `watch_timer_push_test.dart` changed; the plan's Progress and Assumption Log were left to the governor per the brief's file restriction.
