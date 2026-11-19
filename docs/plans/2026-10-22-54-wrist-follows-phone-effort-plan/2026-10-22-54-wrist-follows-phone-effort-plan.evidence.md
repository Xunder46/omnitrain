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

### P2A — the wrist follows the phone's effort (developer, 2026-10-23)

New file `watch/watchos/Tests/WatchSessionEngineTests/WatchFollowPhoneEffortTests.swift` (8 tests,
fixture: slots `sx-a` / `sx-b` with `sx-b` current, plus the adversarial near-duplicates each
negative names). Production change: `watch/watchos/Sources/WatchSessionEngine/WatchSessionEngine.swift`.

Base for prove-red: `826d9379fd04a737a977130497dd4bcc47494f66` (the brief's base).

Prove-red verdict (`gateway.sh prove-red 826d9379 swift-test --filter WatchFollowPhoneEffortTests -- <test file>`):

```
gateway: prove-red: RED AT 826d9379fd04a737a977130497dd4bcc47494f66 (exit 1). It proves the guard
only if an assertion fails for the reason the test guards; a compile or load error means the test
could not run there (use a mutation instead).
```

The three positive tests fail at the base for the reason they guard:

```
WatchFollowPhoneEffortTests.swift:198: error: testS8401A... : XCTAssertEqual failed: ("Optional("sx-b")")
  is not equal to ("Optional("sx-a")") - the wrist follows the running effort
WatchFollowPhoneEffortTests.swift:312: error: testS8403A... : XCTAssertEqual failed: ("Optional("sx-b")")
  is not equal to ("Optional("sx-a")") - a snapshot's running hold moves the wrist too
WatchFollowPhoneEffortTests.swift:339: error: testS8415T... : XCTAssertEqual failed: ("Optional("sx-b")")
  is not equal to ("Optional("sx-a")") - the earliest running effort is the one to follow
```

The five S-8402 negatives pass at the base — nothing moves there, which is what they assert — so
each is proven by mutation below. (The base run's suite line reads "Executed 8 tests, with 8
failures" while its five negative case lines read "passed"; the case lines are the record.)

| Scenario | Test | Base | After |
|---|---|---|---|
| S-8401 | `testS8401APhoneTimerForAnotherSlotMovesTheEngineToItsSlot` | RED (`sx-b` ≠ `sx-a`) | PASS |
| S-8402 | `testS8402ARestForAnotherSlotDoesNotMoveTheEngine` | PASS (guard — mutation 1) | PASS |
| S-8402 | `testS8402AStoppedRoundForAnotherSlotDoesNotMoveTheEngine` | PASS (guard — mutation 1) | PASS |
| S-8402 | `testS8402AClearedTimerDoesNotMoveTheEngine` | PASS (guard) | PASS |
| S-8402 | `testS8402ATimerForASlotTheSessionDoesNotHoldDoesNotMoveTheEngine` | PASS (guard) | PASS |
| S-8402 | `testS8402ATimerForTheCurrentSlotDoesNotMoveTheEngine` | PASS (guard) | PASS |
| S-8403 | `testS8403ASnapshotTimerForAnotherSlotMovesTheEngine` | RED (`sx-b` ≠ `sx-a`) | PASS |
| S-8415 | `testS8415TwoCandidatesInOneSnapshotEarliestStartWins` | RED (`sx-b` ≠ `sx-a`) | PASS |

Mutation 1 — the D-6 kind/stopped guard (original, verbatim):

```swift
        guard kind != WatchTimerKind.rest,
              stoppedAt == nil,
              let slotId,
```

Mutant: the first two predicates deleted, leaving `guard let slotId,` → the rest and
stopped-round negatives failed (`the wrist does not follow a rest` / `… a stopped round`), the other
six green. The exact original was restored and the file re-ran green (8/8).

Mutation 2 — the D-8 earliest-start comparison (original, verbatim):

```swift
            if let candidate = adopted.jump,
               outcome.jump.map({ candidate.startedAt < $0.startedAt }) ?? true {
                outcome.jump = candidate
            }
```

Mutant: `outcome.jump = candidate`, i.e. the last candidate wins → only S-8415 failed, with
`("Optional("sx-c")") is not equal to ("Optional("sx-a")")` (the fixture's third, later-starting
candidate). The exact original was restored and the file re-ran green (8/8).

Regression found by the full suite and fixed: the first cut returned the adopt outcome from
`applySnapshotExclusive`, which callers read as the applied/refused verdict, so every delivered
snapshot reported "not applied" and five existing tests went red
(`WatchConnectivityBridge` S-186/S-187, `S-4811GPS`, `S-77` ×2). `applySnapshotExclusive` now returns
`TimerAdoption?` — nil is the refusal, any outcome is an application — and `applySnapshot` still
answers `outcome != nil`. Those five are green again.

Suite outputs (real counts):

- `gateway.sh swift-test --filter WatchFollowPhoneEffortTests` → `Executed 8 tests, with 0 failures`
- full `gateway.sh swift-test` → `Executed 764 tests, with 2 failures (0 unexpected) in 2.716 (2.771) seconds`;
  both failures are assertions in the one expected-red
  `testS6004APhoneTimerForAnotherSlotIsNotTheWristsWorkClock` (`WatchTimedWorkTests.swift:1087`/`:1088`,
  "WatchTimerRecord(recordId: "tms-m-6004-elapsed" …)" and `XCTAssertFalse failed`), whose rework is
  Phase 2B. No other test is red.
- `gateway.sh lint` → `180 issues found.` — unchanged from the plan's baseline (no Dart file in this
  change; the repo's pre-existing info notices are the whole count).

Diff footprint: 2 files, 1 created (+8 tests) and 1 modified, +106 −20. No Dart and no docs changed:
Phase 3 owns the doc pass, and nothing in `lib/` reads the watch engine directly.

### P2B — Swift edges and the S-6004 reader rework (developer, 2026-10-23)

Files: `watch/watchos/Tests/WatchSessionEngineTests/WatchFollowPhoneEffortTests.swift` (five tests
added, harness `timer(_:…)` gained `pausedAt:`), `watch/watchos/Tests/WatchSessionEngineTests/WatchTimedWorkTests.swift`
(the S-6004 reader split in two). **No production file changed** — the engine, pager and logging
state are byte-identical to the 2A tree.

`prove-red` is not available for this phase: the new file is untracked (2A) and the split reader's
test names do not exist at HEAD, so a base run cannot compile or select them. Every guard is proven
by mutation instead: one line changed, the named test run, the exact original restored, and the
restoration checked with `git-diff --stat` (identical footprint before and after: 4 files,
271 insertions, 34 deletions — engine `+126` from 2A, `WatchPagerModel.swift` and
`WatchLoggingState.swift` clean again).

| Scenario | Test | Guard proven by | Red observed |
|---|---|---|---|
| S-8404 | `testS8404AClearFrameReleasesTheLockAndTheWristStays` | M1 — a clear must stop the row it clears | `WatchFollowPhoneEffortTests.swift:389` `XCTAssertFalse failed - S-8404 the end of the effort releases the lock` |
| S-8411 | `testS8411AnEarlierStartDropCausesNoJump` | M2 — a dropped row never jumps | `:420` `("sx-a") is not equal to ("sx-b")`, `:421` `a dropped row announces no move` |
| S-8412 | `testS8412APausedPhoneTimerStillJumps` | M3 — a paused row is still a candidate | `:458` `("sx-b") ≠ ("sx-a")`, `:460`/`:461` nil timer, `:462` `0 ≠ 1` frames |
| S-8413 | `testS8413NoJumpForAnInactiveSession` | M4 — the active-session gate | `:492` `("sx-a") ≠ ("sx-b")`, `:493` `no move is announced` |
| S-8414 | `testS8414ASwipeInFlightWhenTheJumpLandsIsRefusedAndTheFocusClears` | M5 — a locked landing is refused with its notice | `:536` `XCTAssertTrue failed - S-8414 the refusal says why` |
| S-6004 (hiding) | `testS6004APhoneTimerForASlotTheLadderDoesNotHoldIsNotTheWristsWorkClock` | M6 — another slot's message timer is hidden | `WatchTimedWorkTests.swift:1088` `XCTAssertNil failed: "WatchTimerRecord(recordId: "tms-m…"`, `:1089` `XCTAssertFalse failed` |
| S-6004 (jump) | `testS6004APhoneTimerForAHeldSlotMovesTheWristToIt` | M7 — the adopted held-slot timer jumps | `:1136` `("sx-run") ≠ ("sx-other")`, `:1141`/`:1142` nil clock, `:1148` `0 ≠ 1` frames |

M1 — `WatchSessionEngine.stopTimerFromMessage`, original verbatim:

```swift
                timerRowFrom(
                    timer,
                    recordId: recordId,
                    recordedAt: stoppedAt,
                    stoppedAt: stoppedAt
                )
```

Mutant: `stoppedAt: nil` (the clear stores a still-running row) → only S-8404 red. Restored.

M2 — `WatchSessionEngine.adoptTimer`'s earlier-start drop, original verbatim:

```swift
           held.startedAt < startedAt {
            return TimerAdoption()
        }
```

Mutant: `return TimerAdoption(jump: jumpTarget(kind: kind, slotId: slotId, startedAt: startedAt, stoppedAt: stoppedAt, sessionId: sessionId))`
→ only S-8411 red (2 failures). Restored.

M3 — `WatchSessionEngine.adoptTimer`'s return, original verbatim:

```swift
        return TimerAdoption(
            changed: true,
            jump: jumpTarget(
                kind: kind,
                slotId: slotId,
                startedAt: startedAt,
                stoppedAt: stoppedAt,
                sessionId: sessionId
            )
        )
```

Mutant: `jump: timer["pausedAt"] == nil ? jumpTarget(…) : nil` (running only) → only S-8412 red
(4 failures). Restored.

M4 — `WatchSessionEngine.jumpTarget`'s guard, original verbatim:

```swift
              let session = current,
              session.sessionId == sessionId,
              session.status == WatchSessionStatus.active,
```

Mutant: the `session.status == WatchSessionStatus.active,` line deleted → only S-8413 red (2
failures), confirming the message is still adopted after the phone ends the session and only the
jump's own gate stops the move. Restored.

M5 — `WatchPagerModel.land(on:)`, original verbatim:

```swift
        if rows[index].isCurrent { return true }
        guard !isLocked else {
            noteLockedSwipe()
            return false
        }
        return await menu.jump(to: rows[index].slotId)
```

Mutant: the guard replaced by `_ = isLocked` → only S-8414 red, on the refusal notice. Restored.
(`moved` stays false either way because `menu.jump` refuses under the lock; the notice is the
model's own half and the one a mutation can remove.)

M6 — `WatchLoggingState.workTimer`, original verbatim:

```swift
        if engine.isTimerFromMessage(timer),
           let slotId = timer.sessionExerciseId,
```

Mutant: `if !engine.isTimerFromMessage(timer),` (the slot-hiding rule inverted) → only the S-6004
hiding test red. Restored.

M7 — `WatchSessionEngine.adoptTimer`'s return (the original quoted under M3). Mutant:
`jump: nil` → only the S-6004 jump test red (4 failures). Restored.

Suite outputs (real counts):

- `gateway.sh swift-test --filter WatchFollowPhoneEffortTests` → `Executed 13 tests, with 0 failures (0 unexpected)`
  (S-8401..S-8404, S-8411..S-8415)
- `gateway.sh swift-test --filter WatchTimedWorkTests` → `Executed 36 tests, with 0 failures (0 unexpected)`
  (the split S-6004 pair and every other S-1300..S-6331 test green; S-6005 unchanged, still green
  although it now also jumps — its assertions are about storage)
- full `gateway.sh swift-test` → `Executed 770 tests, with 0 failures (0 unexpected) in 2.627 (2.682) seconds`
  (exit 0; 764 in 2A plus the 6 added here — five new in the new file, one net from the S-6004 split)
- `gateway.sh lint` → `180 issues found.` — the plan's 180 baseline, unchanged (no Dart file in this run)
- `gateway.sh test test/ui_standards_contract_test.dart` → `00:00 +29: All tests passed!`
- project invariant (`import .*hive_workout_repository` under `lib/state`, `lib/features`, `lib/widgets`,
  `lib/core`) → no matches; only `lib/main.dart`, the composition root, imports it

Diff footprint: `git-diff --stat` = 4 files, +271 −34 — engine `+126` and both docs are 2A's/planner's;
this phase's own change is `WatchTimedWorkTests.swift` +67 (the reader split) plus the untracked
`WatchFollowPhoneEffortTests.swift` now holding 13 tests. No production file, no Dart file, no doc
outside this plan.

### P3 — docs (developer, 2026-10-23)

Files: `docs/state_management/watch_surface_wrist.md` (+17 −4), `docs/state_management/watch_surface.md`
(+13 −2), `docs/watch_session_capture.md` (+11 −6) — `git-diff --stat` reports 3 files, +41 −12. No
code, no Swift, no plan-53 text reverted.

What now says what, and the test each claim names:

- `watch_surface_wrist.md`, "The work clock names its exercise": the follow rule (a message-borne
  running or paused work timer — `elapsed`, `hold`, `round` — naming another slot the live session
  holds moves the wrist there through the engine's own select path, one `exercise_advanced` frame),
  its negatives (rest, stopped or cleared timer, unheld slot, current slot, inactive session, an
  earlier-start drop), the per-frame earliest-start tie-break, and the unchanged lock, pager and
  in-flight-swipe rules. Names `WatchFollowPhoneEffortTests.swift` S-8401..S-8415 (S-8405 excepted, see
  the plan's Q1) plus the two S-6004 names Phase 2B shipped; the pre-rework name
  `testS6004APhoneTimerForAnotherSlotIsNotTheWristsWorkClock` no longer exists and is gone from the doc.
- `watch_surface.md`, the `WatchTimerPush` paragraph: the inbound-frame trigger under the auto push's
  reset gate (D-1), clears only (`flushClears()`), and an ordinary `flush()` that joins or follows a
  clears-only drain still getting its full pass (S-8408). Verified-by extended with the S-8406..S-8408
  groups.
- `watch_session_capture.md`: "a wrist out of reach is served at the next phone notification or the
  next frame the wrist sends", the follow-by-jump limit (S-8401), and the Verified-by extended with
  the S-8406..S-8408 groups. The seeded limit "applies a phone timer only for the exercise it is
  showing" was removed because D-2 falsified it (Assumption Log).

Suite outputs (real counts):

- `gateway.sh test test/docs_indexing_contract_test.dart test/ui_standards_contract_test.dart` →
  `00:00 +42: All tests passed!` (42 passed, 0 failed). The contract's ceiling-band check
  ("no documentation file is within the warning band of the ceiling") passes, so all three docs are
  under 52 KB.
- full `gateway.sh test` → `03:07 +5437 ~2: All tests passed!` (5437 passed, 2 skipped, 0 failed; the
  same counts as the P1 tree — no code changed in this phase)
- `gateway.sh lint` → `180 issues found. (ran in 3.4s)`, 0 errors and 0 warnings — the plan's 180
  baseline, unchanged
- `gateway.sh git-diff --stat` → 3 files, +41 −12, the three docs only; `git-status` shows this plan and
  its evidence as the only other modified files

Prove-red: N/A — this phase adds no test and no guard; it is prose plus this plan's bookkeeping. The
falsifiable evidence is the two contract test files above and the named test functions, each of which
was located in the tree (the Swift names in `WatchFollowPhoneEffortTests.swift` and
`WatchTimedWorkTests.swift`, the Dart groups in `test/watch_timer_push_test.dart`).

Out of this phase's Predicted Files: `watch/sync_protocol/PROTOCOL.md` ~l.314 names the S-6004 test
name Phase 2B split away; recorded in the plan's Assumption Log for the governor (one-line rename).

### Fix round 2 — review findings 1–5, documentation and comments only (developer, 2026-10-23)

No behaviour change and no test added, so no prove-red: every guard named here (S-6322/S-6323/S-6324/
S-7305/S-8401/S-8408) already exists and was located in the tree.

- **Finding 1 (plan file):** D-1 is annotated in place and D-1a follows it without renumbering; D-1a
  records the shipped form — `timerPush.flushClears()` plus the clears-only mode in `WatchTimerPush`
  (`flushClears()`, `_flush({required bool clearsOnly})`, `_fullAgain`), not `timerPush.flush()`, for
  the reason the review gives (a full flush re-offers a start for a clock the wrist ended:
  S-6322/S-6323/S-6324/S-7305), with S-8408 as the proof an ordinary flush still gets a full pass.
  The same correction is in the root-cause §1 paragraph, Phase 1 item 2 and the Impact row
  "`WatchTimerPush.flushClears()`".
- **Finding 2:** `watch/sync_protocol/PROTOCOL.md` names the two shipped names,
  `testS6004APhoneTimerForASlotTheLadderDoesNotHoldIsNotTheWristsWorkClock` (l.1056) and
  `testS6004APhoneTimerForAHeldSlotMovesTheWristToIt` (l.1101), both confirmed present in
  `WatchTimedWorkTests.swift`; the removed name is gone from the file.
- **Finding 3:** the 2026-10-20 amendment row (~l.697) scopes the hiding to a slot the session does not
  hold and points at the follow rule (`docs/state_management/watch_surface_wrist.md`, S-8401,
  `testS8401APhoneTimerForAnotherSlotMovesTheEngineToItsSlot`). The same one-sentence scoping was added
  to the normative "Timer state" section (~l.290), which carried the identical now-false claim — logged
  in the Assumption Log. No wire change, no schema edit, no version change.
- **Finding 4:** the D-7 comment at both jump sites (`applySnapshot` ~l.518, `applyTimerState` ~l.738)
  now states that the D-6 active-session gate is checked at collect time, that a lifecycle frame
  landing between collect and select can at worst move a just-finished session's position, and that
  `selectExercise` re-validates the slot against the held session. Comment only.
- **Finding 5:** `_flush`'s doc comment names the accepted window — a clears-only flush joining a
  running full drain makes the follow-up pass clears-only, so a failed full pass leaves the start it
  owed to the next phone-state trigger (D-202); a full follow-up on a wrist-frame trigger is what
  D-1a rules out. Comment only.

Suite outputs (real counts):

- `gateway.sh test test/docs_indexing_contract_test.dart test/watch_timer_push_test.dart` →
  `00:00 +57: All tests passed!` (57 passed, 0 failed)
- full `gateway.sh test` → `03:07 +5437 ~2: All tests passed!` (5437 passed, 2 skipped, 0 failed)
- `gateway.sh lint` → `180 issues found.`, 0 errors — the plan's 180 baseline, unchanged
- `gateway.sh swift-test` → `Executed 770 tests, with 0 failures` (0 unexpected)
- `gateway.sh git-diff --stat` for this round's files: `watch/sync_protocol/PROTOCOL.md` +5 −2,
  `lib/state/watch/watch_timer_push.dart` +6, `WatchSessionEngine.swift` +8 −2; plus this plan and its
  evidence. No other file this round.

PROTOCOL.md is read by `test/sync_protocol_fixtures_test.dart` only as prose naming fixtures it walks;
the fixtures, the schema and the validators are untouched, and that suite is inside the full run above.

## Feedback

- P1 fix round 1 (developer, 2026-10-23): `flushClears()`' instance-wide `_clearsOnly` made a joining ordinary `flush()` run clears-only and withhold the phone's new start; the pass mode is now per request (`_flush({required bool clearsOnly})` plus `_fullAgain`). S-8408 added and shown red before the fix and green after; full suite 5437 passed / 2 skipped / 0 failed, lint 180 issues. Only `watch_timer_push.dart` and `watch_timer_push_test.dart` changed; the plan's Progress and Assumption Log were left to the governor per the brief's file restriction.
