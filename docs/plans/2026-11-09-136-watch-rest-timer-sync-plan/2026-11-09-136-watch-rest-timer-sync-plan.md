# Plan — 136: a rest running on the watch ends when the phone starts a timer

**Status**: P1 built and verified by the lead 2026-11-09 (new file 8 tests green; four related files 142 passed; mutation pass 6 of 7 killed, one equivalent). Docs done with plan 135's; reviewed (APPROVE WITH FIXES: the one Major is an accepted residual, A-4). Owner device check open.
**Binding conventions**: `docs/global_conventions.md`, `docs/state_management/watch_surface.md`.
**Base commit**: `ff398e1a7ec18409d9fc8c890bf35d2fde656e69` (branch `claude_develop`; a mixed uncommitted tree: plans 134a-134e, the Summary pen buttons, plan 135 in progress; scope every diff to this plan's files).
**Parent plans**: `docs/plans/2026-11-02-98-phone-watch-live-sync-audit-plan/` (F-2: any timer start ends every open rest), `docs/plans/2026-10-20-43b3-shared-timer-phone-sends-plan/`.

## Overview

Owner (2026-11-09, real device): "When I started a timer on my phone, the watch was still on the rest; it only picked up when I logged it on the phone and the next rest timer started."

What the user sees today: the watch is resting (it logged a set), the user starts the next hold or interval on the PHONE, and the wrist keeps counting the old rest as if nothing happened, until the phone logs the result and a new rest replaces it. What the user sees after this plan: starting a timer on the phone stops the wrist's rest at once (the wrist goes back to its work screen, which now shows the phone's timer).

Cause, observed. Plan 98 made a phone timer start close every rest THE PHONE HOLDS (`closeAllOpenRestsInSessionInMemory`), and the push tells the wrist with a `{rest: null}` frame. A rest the WRIST started (it logged the set) lives on the phone only as a mirror copy in `LiveSessionMirrorState`: the phone has no stored open rest for it, so `inProgressRest()` is null, `_composeWanted` has no `rest` and the push has nothing to clear (`watch_timer_push.dart` `_pushOnce`: clears come only from `_delivered`, `_adopted` and `_workKinds` reconciliation). The probe `.work/crew/2026-11-09-136/probe_136_wrist_rest_test.dart` (copy of the `watch_timer_push_test.dart` harness): wrist `engine.startTimer(WatchTimerKind.rest)`, frame forwarded to the phone, `phoneState.startTimedEntry('sx-run', 0)`, `timerPush.flush()` → the phone sends one frame `{elapsed: {...}}` with no `rest` key and `engine.timerFor(rest).state` stays `running`. Printed on the base commit: `R1 frames: [{elapsed: ...}]`, `R1 wrist rest after: running`, test FAILED.

## Goal and acceptance

A phone work timer (`elapsed`, `hold`, `round`) that starts while the mirror shows the wrist's rest running or paused makes the push send `{rest: null}` to the wrist, once. Acceptance: S-13601 .. S-13608.

## Decision Ledger

| ID | Decision | Backing |
|---|---|---|
| D-13601 | In `WatchTimerPush._pushOnce` (`lib/state/watch/watch_timer_push.dart`, after the `retired` loop and the existing `clears` building, before the plan 121a D-4 reconcile loop): a new step `rest-superseded` adds `clears['rest'] = null` when ALL hold: `wanted` has no `rest`; the mirror (same session id) holds a `rest` that is NOT `stopped` (running or paused); that rest is not the one this push already cleared (`_stale['rest']` with the same start, the same test `_wristHolds` and `_loggedWristTimer` use); and `wanted` has at least one work kind (`elapsed`, `hold`, `round`) whose `startedAt` is later than the mirror rest's `startedAt`. The condition is read from `wanted` and the mirror, not from `next`, so a clears-only pass (reachability returned, wrist asked) re-offers a clear whose first send the radio refused | `watch_timer_push.dart:300-420`; probe R1 |
| D-13602 | When the clear was delivered the push records the cleared rest in `_stale['rest']` as `(slotId: held['sessionExerciseId'], startedAt: held['startedAt'])` through the same `reconciled` map the plan 121a D-4 branch uses (`reconciled[kind] = held`), so the mirror copy (still `running` until the wrist reports it stopped) is neither cleared again nor treated as held by `_wristHolds` | `watch_timer_push.dart` clear bookkeeping after `_send(session.id, clears)` |
| D-13603 | A wrist rest that started AFTER the phone's work timer is a newer rest (the wrist logged again after the phone timer) and is never cleared by this step. The comparison is the instants (`_instant`), strict `isAfter` on the timer's start vs the rest's start | the wrist's later start wins (`_WristHolds.earlier` rule, 43b3 D-3) |
| D-13604 | Nothing changes on the wrist (it already applies `{rest: null}` as a stop, plan 98 S-9924) and nothing in the protocol; no new frame, no schema change | `test/watch_timer_push_test.dart` S-7303, S-9924 |
| D-13605 | `snapshotTimers()` stays unchanged: it names only timers the ledger delivered or owes; a wrist rest is never named, and the clear frame (D-13601) is what stops it | `watch_timer_push.dart:150-205` |

## Scenarios

Fixture for all: the harness of `test/watch_timer_push_test.dart` (`wristStartsTimedSession`, `engine`, `radio`, `graph`, `mirrorRest`, `_settle`). The wrist's own clock is `_now` (2026-10-19), the phone's interval starts at the real clock, so a wrist rest started through `engine.startTimer(WatchTimerKind.rest)` is always EARLIER than a phone interval started now.

| ID | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-13601 | wrist rest started via `engine.startTimer(WatchTimerKind.rest)` and its frame forwarded (`radio.fromWrist(wristFrames.last)`); then `phoneState.startTimedEntry(_slotId, 0)`, `timerPush.flush()`, apply every `timer_state` frame to `engine` | a frame whose `timers` has key `rest` with value null exists; `engine.timerFor(WatchTimerKind.rest)?.state` is not `running` | the push never clears a rest the phone does not hold (probe R1 red) |
| S-13602 | as S-13601 but the wrist's rest is reported with `mirrorRest(startedAt: <phone interval start + 5 s>, ...)` | no frame clears `rest` | n/a: guard of D-13603 (proven by mutating `isAfter` to `isBefore`) |
| S-13603 | the wrist's rest was already stopped (`engine.stopTimer(kind: rest)` and its frame forwarded) before the phone interval starts | no frame clears `rest` | n/a: guard of the `stopped` condition (mutate: drop the state test) |
| S-13604 | S-13601, then a second `flush()` and then a wrist frame that still shows the rest `running` (the mirror copy not yet updated) | exactly one `rest: null` frame in total | n/a: guard of D-13602 (mutate: skip the `_stale` record) |
| S-13605 | S-13601 with `radio.unreachable = true` during the first flush, then reachable and `graph.timerPush.flushClears()` | the clear is sent at the second pass (exactly one `rest: null` frame) | the clear is computed from `wanted` and the mirror (D-13601); mutate: read it from `next` instead |
| S-13606 | a PAUSED wrist rest (`mirrorRest(state: 'paused', pausedAt: ..., accumulatedPauseMs: 1000)`) and a phone interval | the clear is sent | n/a: guard of the "running or paused" condition |
| S-13607 | the phone holds its own open rest (existing `openPhoneRest`) and starts an interval on the same slot (the fixture of the existing S-9924 test uses another effort; the guard here is that the count stays one) | the existing S-9924 behaviour is unchanged: exactly one `rest: null` (not two) | n/a: guard that D-13601 does not double the existing clear |

| S-13608 | the phone runs an interval, then opens its OWN rest (`openPhoneRest()`), and the wrist reports an older rest (`mirrorRest(startedAt: 2026-10-19 09:00Z)`) | no frame clears `rest` | n/a: guard of the `wanted.containsKey('rest')` condition (added by the lead after the mutation pass left it alive; killed once the test existed) |

Each guard is its own test (two-arm rule (y)). Tests are plain `test()` on the Mock harness, in a NEW file `test/watch_rest_cleared_on_phone_timer_test.dart` that copies the harness block of `test/watch_timer_push_test.dart` lines 93-520 (imports through `setUp`) and adds the scenarios; the probe file already holds the copied block.

## Phases (outline)

| Phase | Agent | Write scope | Parallel |
|---|---|---|---|
| P1 | crew-builder-app | `lib/state/watch/watch_timer_push.dart`, `test/watch_rest_cleared_on_phone_timer_test.dart` | serial; plan 135 touches none of these files |
| P2 docs | crew-docs-keeper | `docs/rest_tracking.md`, `docs/watch_session_sync/what_does_not_sync.md`, `docs/state_management/watch_surface.md` | after P1 |

### P1 (one builder run, 7 items)

1. [ ] New test file: copy `.work/crew/2026-11-09-136/probe_136_wrist_rest_test.dart`'s harness (lines 1-~450 of the probe, i.e. the copy of `watch_timer_push_test.dart` through `setUp`) into `test/watch_rest_cleared_on_phone_timer_test.dart`; write S-13601 .. S-13607 as separate `test()`s. Red first for S-13601 (it fails at the base).
2. [ ] Implement D-13601 in `_pushOnce`.
3. [ ] Implement D-13602 bookkeeping.
4. [ ] Green the new file and `test/watch_timer_push_test.dart`, `test/timer_start_closes_session_rests_test.dart`, `test/watch_session_auto_push_test.dart`.

Done: those four files pass; `flutter analyze` count not above the 181 baseline. Predicted files: the two write-scope files only.

## Input-reality checklist

1. **Writers**: the wrist's rest reaches the phone's mirror only through the wrist's own `timer_state` frames (`LiveSessionMirrorState`); the phone's stored rest rows come from phone logging and the importer (rests that ended). The step reads the mirror, never a stored rest.
2. **Lifecycle**: the clear is owed while the radio is out of reach and re-offered by `flushClears` (D-13601); it ends when the mirror shows the rest stopped or the push has cleared it (`_stale`); a session change resets `_stale` with the rest of the ledger.
3. **Settings**: none; the rest-ping setting does not interact (pings only while the wrist's rest is open; the stop ends them).
4. **Time**: only the comparison of two instants (D-13603, strict: the work timer must start AFTER the rest; equal or earlier clears nothing).
5. **Cost**: no new frame; at most one extra `{rest: null}` per phone timer start.
6. **Words**: none (no screen text changes).
7. **Competition**: a rest the wrist starts after the phone timer (D-13603) and a phone rest (existing path) are untouched.

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| docs/watch_session_sync/what_does_not_sync.md | MODIFIED | `is adopted from the wrist, and tells the wrist with a `{rest: null}` timer` | `is adopted from the wrist, and also stops the rest the wrist itself is running (plan 136), telling the wrist with a `{rest: null}` timer` | S-13601 |
| docs/rest_tracking.md | ADDED | - | `a rest the wrist is running ends too` | S-13601 |
| docs/state_management/watch_surface.md | ADDED | - | `plan 136, S-13601 a rest the wrist is running is cleared when the phone starts a timer` | S-13601 |

## Progress

| Item | What | Status |
|---|---|---|
| P1.1 | new test file, S-13601 red at the base (the lead's probe and the builder both saw it) | Done |
| P1.2 | D-13601 in `_pushOnce` | Done |
| P1.3 | D-13602 bookkeeping (reuses the existing post-send `reconciled` to `_stale` path) | Done |
| P1.4 | green the four files: 142 passed; `flutter analyze` 181 | Done |
| P2 | docs rows 1-3 | Planned |

## Assumption Log

| ID | Assumption | Why |
|---|---|---|
| A-1 | The owner's rest was one the wrist started (it logged the set). If the set was logged on the phone the phone held the rest and plan 98 already clears it (S-9924); the probe shows only the wrist-owned case fails | the owner's words: "the watch was still on the rest" and the cause is observed only for this case |
| A-3 | Lead mutation pass (in place, one test file per mutant, restored and `cmp`ed): killed: `isAfter`→`isBefore`, stopped-guard removed, `_stale` guard removed, paused-not-cleared, always-clear, and (after S-13608) the phone-rest guard. Survived and accepted: removing `!clears.containsKey('rest')` (the map key is the same and the value is null either way: an equivalent mutant) | `.work/crew/2026-11-09-136/` mutate scripts in the scratchpad |
| A-4 | Residual risk accepted (review finding 3, Major): a refused clear is re-offered by `flushClears` from the mirror. If the wrist ended its rest R1 and began a NEWER rest R2 while the phone could not hear it, and the link then returns before any wrist frame has updated the mirror, the phone re-sends `rest: null` and the wrist stops R2 early (the rest's window still travels as an observation, nothing is lost). The alternative (clear only on a phone-state pass) would lose the refused clear until the next phone change, which is the owner's own bug when the radio refuses. Documented in `docs/watch_session_sync/what_does_not_sync.md` | review file |
| A-2 | The architect phase is skipped for this unit: the seed carries exact decisions, fixtures and the probe; 1 production file | cost discipline; recorded here and in the unit summary |
