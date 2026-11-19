# Feature: 121a — a hold logged on the phone stops on the watch and never comes back

> Status: DRAFT, Iteration 1 ready. No owner question needed (see Questions).
> Next handoff: crew-builder-app (Phase 0: red probes; it writes no production code)
> Binding conventions: docs/global_conventions.md; docs/documentation_standard.md; .github/copilot/pr-scope-budget.md
> Base: working tree on `claude_develop` at `ecf2d050`, shared with other sessions (plans 118 to 120, 121b, 122). Check line numbers before briefing.
> Siblings: 121b (the phone adopting a stale watch copy of a logged hold into the NEXT not-started interval) is NOT in this plan. Every fixture here has exactly ONE interval on the hold slot, except S-12114, which asserts only what the phone sends.
> Prior plans this builds on: `docs/plans/2026-10-20-43c-finish-once-plan/` (the 43c clear and `_adopted`/`_stale`), `docs/plans/2026-11-02-98-phone-watch-live-sync-audit-plan/` (D-2 owed starts, D-3 reachability flush; its F-3 session-end gap stays out of scope).

## Overview

What the owner saw: a hold started on the phone and mirrored on the watch. The owner logged it on the phone, and the phone moved to the next exercise. The watch kept counting that hold for the rest of the session, and stopped only when the phone finished the session. After the watch app was reinstalled, the watch showed the same hold, still counting from its original start.

**Leading hypothesis (H1, from code; Phase 0 must prove or kill it with failing tests).**
1. `timer_state` is live-only: `WatchConnectivityTransport._queueable` (`lib/core/platform/watch_transport.dart:242`) excludes it. With the wrist out of reach, the phone's `{hold: null}` comes back `undelivered` (pinned by `test/watch_transport_test.dart` `S-6811`).
2. `WatchTimerPush` removes a kind from `_delivered` only after a clear is DELIVERED (`watch_timer_push.dart:366-375`).
3. Every snapshot the phone composes goes through the mirror `projection` (`watch_sync_wiring.dart:267-274`). That projection adds `timerPush.deliveredTimers()`, which is all of `_delivered` (`watch_timer_push.dart:137`). Its readers are the auto push (`watch_session_auto_push.dart:265,417,433`), the Sync-request answer (`watch_sync_request_handler.dart:437`), the router's answer (`watch_incoming_router.dart:128`) and the app-resume `sync()` (`watch_sync_wiring.dart:145`). So every snapshot after the log names the logged hold again.
4. `session_snapshot` is durable: when the wrist is out of reach the OS queues the newest copy (`watch_transport.dart:349-352`). Snapshot timers are authoritative on the wrist. A named timer is appended as a new running row under the snapshot's message id (`adoptTimer`, Swift `WatchSessionEngine.swift:836-899`; Dart twin `lib/watch/session/watch_session_engine.dart` `_adoptTimer`). So the snapshot revives the hold, and a reinstalled watch, whose store is empty, gets the hold from the first snapshot it receives, still counting from its original start.

**H2 (any other cause)** is probed in the same phase: the wrist ignoring a delivered clear, the order of the clear and a snapshot, or the wrist re-reporting the hold and the phone re-adopting it.

**Fix for the H1 branch (phone only, no wire change).** (a) A snapshot names only the delivered timers the phone still runs, read from the phone's state at the moment the snapshot is composed (D-1). Leaving a phone-written timer out of a snapshot already stops it on the wrist (Swift D-80, `senderWroteTimer`; pinned by Swift `testS1310APhoneSnapshotLeavesTheWristsWorkClockRunning`, whose second half shows that the phone's own row is stopped). So the durable snapshot carries the clear. (b) A stateless reconcile (D-4) covers the cases (a) cannot reach. The wrist may report a running work timer whose interval the phone has already logged: a timer the wrist started itself, or any timer after the phone restarted and lost its memory-only ledger. In that case the phone sends a clear.

## Questions

None for the owner. Every open point is technical or follows from the owner's stated expectation. The one derived reading of that expectation is D-8, which the owner may veto.

## Resolved Decisions (Ledger)

- **D-1 What a snapshot's `timers` carries.** The projection's `timers` is the result of a new `WatchTimerPush.snapshotTimers()`, computed when it is called and never cached. `wanted` is composed from the bound `WorkoutState`, the way `_pushOnce` composes it at `watch_timer_push.dart:255-297` (`inProgressWorkTimers()` and `inProgressRest()`). For each `(kind, delivered)` in `_delivered`, the delivered JSON is included only when all of these hold:
  - (i) the bound state has an active session whose id equals the ledger's `_sessionId`;
  - (ii) `wanted[kind]` exists;
  - (iii) for a work kind, `wanted[kind]['sessionExerciseId'] == delivered['sessionExerciseId']`;
  - (iv) the starts match: `_sameInstant` for a work kind, `_restStartWithinTolerance` (500 ms) for `rest`;
  - (v) `_wristEnded(sessionId, kind, delivered)` is false, meaning the mirror does not hold that very timer as stopped.

  If no state is bound, or there is no active session, the result is `{}`. The projection keeps its rule of adding `timers` only when the map is not empty (`watch_sync_wiring.dart:270`). Otherwise the projection's own `'timers': {}` stands (`watch_session_adoption_bridge.dart:284`).
- **D-2 Omission, never an explicit null.** A snapshot never writes `kind: null`. Leaving a timer out stops only rows the phone wrote (Swift `adoptTimers` line 793, `authoritative && senderWroteTimer`). A `null` stops the newest row of that kind whoever started it, and a late snapshot from the OS queue could then stop a timer the wrist started after the snapshot was composed. A timer the wrist started stays on the live clear (43c D-3) and the reconcile (D-4).
- **D-3 The value stays the delivered JSON.** A pause the radio refused is still carried as the delivered copy, which is unchanged behaviour (see Noticed, item 3). D-1 only removes entries from what a snapshot carries; it never adds or changes one.
- **D-4 Reconcile: clear a wrist clock the phone has already logged.** Each pass of `_pushOnce`, both the full pass and the clears-only pass, also runs this check. For each work kind `k` in `{elapsed, hold, round}`, the mirror copy `m = _mirror.state['timers'][k]` triggers `clears[k] = null` when all of these hold:
  - (i) `_mirror.sessionId == session.id`;
  - (ii) `m` is a Map, `m['state'] != 'stopped'`, and `m['sessionExerciseId']` is a non-empty String `s`;
  - (iii) `wanted` has no entry for `k`;
  - (iv) `m` is not the `_stale[k]` copy (same slot, and `_sameInstant` start);
  - (v) the phone session's effort `s` has an effort kind that maps to `k` (`timed`→`elapsed`, `drill`→`hold`, `round`→`round`). Among its intervals (`getTimedInstancesForEffort` / `getRoundsForEffort`), at least one is `finished` and has a `startedAtMs` within **1000 ms** of `m['startedAt']`, the same tolerance as `TimerManager._sameStartToleranceMs`. None is `active` or `paused` with a start within 1000 ms.

  The clear joins the pass's `clears` frame. That frame is sent before any `next` frame, which is the existing D-2b order. `rest` is never reconciled. Effect: the timer that interval belonged to is over on the phone, so the wrist's clock for it must stop.
- **D-5 Remember a reconcile clear.** When the clears frame is delivered, the reconcile records `_stale[k] = (slotId: s, startedAt: m['startedAt'])`, so the next wrist frame carrying the same mirror copy sends no second clear. `_stale` stays memory-only. After a phone restart, at most one repeat clear goes out per stale copy. That is accepted: the copy has to match a logged interval of the phone, so no live timer can match it.
- **D-6 No wire, transport, Swift or Dart-engine change.** `timer_state` stays live-only (S-6811). The durable path for the clear is the snapshot leaving the timer out (D-1). The one Swift guard this relies on already exists (`WatchTimedWorkTests.testS1310...`).
- **D-7 The ledger stays memory-only.** `_delivered`, `_adopted`, `_stale` and `_owed` are not persisted. D-1 reads the phone's state rather than the ledger to decide what is still wanted, and D-4 reads the phone's logged intervals, so a restart cannot bring a logged timer back.
- **D-8 (derived, owner may veto) What "immediately" means.** When the wrist is in reach, the live clear stops the watch's clock within the push's 250 ms window, as today. When it is out of reach, the clock stops at the first frame the wrist receives after the log: the durable snapshot the OS carries, the live clear when the wrist comes back in reach, or the answer to its Sync. The watch shows no notice. It offers Start for the next interval, as 43c does.
- **D-9 Phase 0 gate (H1 confirmed).** On the unchanged code, three things must hold. (a) `S-12101` fails both at the assertion on what the snapshot carries and at the assertion on the wrist's state. (b) `S-12103a` fails. (c) The H2 probes `S-12110` and `S-12111` pass. Only then may Phase 1 start. Any other outcome is the H2 branch: Phase 0 ends with its evidence, the plan Status becomes `BLOCKED: H2 branch`, and the governor re-plans. No fix is attempted.
- **D-10 Boundary with 121b.** Phone adoption (`WatchTimerAdoption`, `TimerManager.adoptRemoteTimer`, `needsIntervalFor`) is not touched. Fixtures keep one interval on the hold slot, so adoption has no target (`needsIntervalFor` is false because a finished interval has the same start, `timer_manager.dart:320-340`).
- **D-11 Residue.** `deliveredTimers()` is deleted. `grep -rn "deliveredTimers" lib test` returns nothing.

## Feature Invariants

- A snapshot the phone composes never names a work timer or a rest that the phone no longer runs at that moment (D-1).
- A wrist timer the phone did not start is never stopped by a snapshot's omission (Swift S-1310). Only an explicit clear stops it (43c D-3, D-4).
- 54 D-1a still holds: no pass sends a start for a timer the wrist ended (D-1 (v); the existing `_owe` and `_wristEnded`).
- Plan 98 D-2/D-3 still hold: an owed start is sent on a wrist frame or on reachability (S-9925 to S-9934 stay green).

## Requirements and Acceptance Criteria

| # | Requirement | Scenarios |
|---|---|---|
| AC-1 | After the phone logs a hold the wrist ran from the phone, no frame from the phone brings that hold back on the wrist, whether the wrist was in reach at the log or not | S-12101, S-12102, S-12112, S-12110 |
| AC-2 | A watch app reinstalled after the log shows no running hold | S-12103 |
| AC-3 | Timers the phone still runs keep running on the wrist, and ones it stopped are not named (other kinds, the rest, a new interval) | S-12104, S-12105, S-12105b, S-12114, S-7310 |
| AC-4 | A hold the wrist started and the phone logged stops when the wrist comes in reach, including after the phone app restarted | S-12106, S-12107, S-12113 |
| AC-5 | The reconcile never stops a timer the phone did not log | S-12108 |
| AC-6 | A hold the wrist itself ended is not revived by a snapshot | S-12115 |
| AC-7 | The end of the session is unchanged | S-12109 |
| AC-8 | Re-adoption is not the cause (H2 probe) | S-12111 |

## Existing-Functionality Impact

| Touched surface | Readers (grep) | Effect | Guarded by |
|---|---|---|---|
| `WatchTimerPush.deliveredTimers()` → `snapshotTimers()` | `grep -rn "deliveredTimers" lib test` → `watch_sync_wiring.dart:269` only; no test calls it | Snapshots lose timers the phone no longer runs | D-1, D-11; S-7310 (a delivered rest that is still open stays named) |
| The mirror `projection` (every snapshot the phone composes) | `grep -rn "projectedSession()" lib` → `watch_sync_wiring.dart:145`, `watch_session_auto_push.dart:265,417,433`, `watch_incoming_router.dart:128`, `watch_sync_request_handler.dart:437`; the router's answer goes through `_projection` (`live_session_mirror_state.dart:279`) | As above, in all six paths | S-12101 asserts on `projectedSession()`, so every path is covered |
| Snapshot `timers` asserted by existing tests | `grep -rln "\['timers'\]" test` → `watch_session_auto_push_test.dart` (578, 657), `watch_session_projection_test.dart` (743, 1413, 2926), `live_mirroring_test.dart` (566, 1057), `watch_reconciliation_cross_stack_test.dart:92`, `watch_timer_adoption_test.dart` | Must stay green: none has the phone stop wanting a delivered timer | Done Criteria of Phase 1 re-runs these files |
| `_pushOnce` clears (new reconcile) | `grep -n "flushClears" lib` → `watch_sync_wiring.dart:364,390`; tests `S-8406..S-8408`, `S-9925..S-9934`, `S-6321..S-6330` in `test/watch_timer_push_test.dart` | A clear can now also be sent for a mirror copy that matches a logged interval | S-12107, S-12108; the whole `watch_timer_push_test.dart` stays green |
| `_stale` (written in a second place) | `grep -n "_stale" lib/state/watch/watch_timer_push.dart` → 107, 242, 250, 374, 439 | `_wristHolds` already ignores stale copies, so the phone's next timer of that slot is not blocked | S-6326, S-7312, S-12108d |
| The wrist's snapshot timer semantics (relied on, unchanged) | Swift `WatchSessionEngine.swift:782-822`; Dart twin `watch_session_engine.dart` `_timerActionFor` | None | Swift `testS1310...`; the Dart engine in S-12101 and S-12106 |

## UI Standards Impact

None: there is no screen change.

## Scenarios

**Fixture F-A (every scenario unless it says otherwise).** The harness shape is copied from `test/watch_timer_push_test.dart`, as the shipping graph `createWatchSync` over a fake radio plus the real Dart engine `WatchSessionEngine` over `InMemoryWatchSessionStore`. It goes in a new file, `test/watch_logged_hold_stays_stopped_test.dart`, using plain `test()` only.
- Clock `_now = 2026-11-05T09:00:00Z` for the graph and the engine. Session id `s-w-121a`.
- Catalog: `ex-plank` (Plank, capabilities `[hold, time]`) and `ex-run` (Run, `[time, distance]`), seeded with `seedExercise`.
- The wrist creates the session with two slots: `sx-plank` (`effortKind: drill`) then `sx-run` (`effortKind: timed`). It sends `engine.sessionSnapshot()` and the phone adopts it.
- Fixture asserts: the phone's current session is `s-w-121a`; effort `sx-plank` has kind `drill`; it has EXACTLY ONE `TimedInstance`, `notStarted` (the owner's one set). If the adoption creates more, delete the extras through the repository and record that in the Assumption Log.
- `adoption`, `timerPush`, `timerAdoption` and `autoPush` are all bound to the phone `WorkoutState`, as `lib/main.dart:401-406` binds them.
- Radio `_QueueingPhoneRadio` (also a `WatchLinkSource`, with `emitLink`, as `_LinkedPhoneRadio` does):
  - `unreachable == false`: the frame goes to `sent` and the answer is `delivered`.
  - `unreachable == true` and `WatchConnectivityTransport.isDurable(frame)` is true: the frame goes to `queued`, replacing a waiting frame of the same `type` when that type is `session_snapshot`, `session_lifecycle` or `structure_change`. The answer is `queued`.
  - Otherwise the answer is `undelivered`. Every call is recorded in `attempted`.
  - `deliverQueued()` returns and empties `queued`: the OS carrying it.

**Steps used below.**
- **H-start:** `startTimedEntry('sx-plank', 0)` (S_H = that instance's `startedAtMs`), then `timerPush.flush()`. Every sent `timer_state` is applied to the engine. Fixture assert: `engine.timerFor('hold')` is running, with slot `sx-plank` and start S_H.
- **H-log-away:** `radio.unreachable = true`, then `finishTimedEntry('sx-plank', 0)`, then `timerPush.flush()`, then `autoPush.flush()`. Fixture asserts: one `timer_state` `{hold: null}` in `attempted` that is not in `sent`; exactly one `session_snapshot` in `queued`.

| id | Fixture delta, trigger, flow | Expected (after the fix) | Today |
|---|---|---|---|
| S-12101 | F-A; H-start; H-log-away. Read `graph.mirror.projectedSession()` and the queued snapshot; `engine.applyMessage(queued snapshot)` | (a) `projectedSession()['timers']` has no `hold` key; (b) the queued snapshot's `payload.timers` has no `hold`; (c) after applying it, `engine.timerFor('hold').state == stopped`, start still S_H | RED (a)(b)(c) |
| S-12102 | S-12101 up to before the apply; then `unreachable = false` and `emitLink(reachable: true)`. Apply the `{hold: null}` sent, THEN `deliverQueued()` (the OS delivers late). Then `autoPush.flush()` after any phone change (start `sx-run` interval 0) and apply | The hold is stopped after the clear, after the late snapshot, and after the next snapshot; no frame sent after the log names `hold` with start S_H | RED (late snapshot revives it) |
| S-12103 | **(a)** S-12101 up to before the apply; a SECOND engine over a NEW empty `InMemoryWatchSessionStore` (the reinstall) applies `deliverQueued()`. **(b)** Same, but with `unreachable = false` the new wrist sends `WatchTransportRequest.snapshotFrame()`, and only the phone's first `session_snapshot` sent after it is applied | (a) and (b): the new engine holds session `s-w-121a` and `timerFor('hold')` is null or stopped, never running | RED (a)(b) |
| S-12104 | F-A; H-start; `startTimedEntry('sx-run', 0)` and `flush()` while reachable (`elapsed` delivered, start S_R); H-log-away | The snapshot `timers` equals `{elapsed: <the delivered elapsed JSON>}` exactly; after the apply, engine `elapsed` is running from S_R and `hold` is stopped | RED (hold named) |
| S-12105 | F-A; H-start; H-log-away, but `recordRestStart('sx-plank', 0)` (the session screen's rest after a log) before `timerPush.flush()` | The snapshot names neither `hold` nor `rest`, and after the apply `hold` is stopped. Then `unreachable = false` and `emitLink(true)`: the owed rest is sent (98 D-2), and the engine's `rest` runs from the phone's rest start | RED (hold named) |
| S-12105b | F-A; while reachable the phone opens a rest on `sx-run` entry 0 (the `openPhoneRest` helper copied from `watch_timer_push_test.dart`: `recordRestStart` then pinned stamps) and `timerPush.flush()` delivers it; `unreachable = true`; `startTimedEntry('sx-plank', 0)` (98 D-1 closes every open rest); `timerPush.flush()` | `projectedSession()` names no `rest` (and no `hold`: never delivered) | RED (the delivered rest is named) |
| S-12106 | F-A; the WRIST starts the hold (`engine.startTimer('hold', sessionExerciseId: 'sx-plank')`, start W) and the phone adopts it (interval 0 active, start W; no frame echoed). Then `unreachable = true`, `finishTimedEntry('sx-plank', 0)`, flushes, apply the queued snapshot | The snapshot names no `hold`. The engine `hold` is STILL running: a wrist-started row is not stopped by an omission (S-1310). After `emitLink(true)` the 43c clear is sent, and once applied, `hold` is stopped | GREEN (guard) |
| S-12107 | S-12106 up to before `emitLink`. Then the PHONE RESTARTS: dispose the first graph's pushes and build a second `createWatchSync` graph over the same repository, `WorkoutState` and radio, with everything bound. `unreachable = false`; the wrist sends `engine.sessionSnapshot()` (it reports `hold` running, start W) | The phone sends `timer_state` `{hold: null}` (D-4); after it is applied, `hold` is stopped. A second identical wrist frame sends no second clear (D-5) | RED (no clear: the ledger was lost) |
| S-12108 | Reconcile guards, each on S-12107's restarted graph: **a** the mirror's hold start is W+5000 ms (the wrist began a new hold); **b** the phone has `sx-plank` interval 0 active at start W (not logged); **c** the mirror's copy is `stopped`; **d** after one delivered reconcile clear, the wrist frame repeats: exactly one clear in total; **e** the mirror holds a running `rest` and no phone rest is open; **f** the phone runs a hold on another drill slot `sx-plank2` (`ex-plank`, delivered); **g** the mirror's hold start is W+400 ms | a, b, c, e, f: no `{hold: null}` (no `{rest: null}` for e) is attempted. d: exactly one clear. g: one clear (it is within tolerance) | a,b,c,e,f GREEN; d,g RED |
| S-12109 | F-A; H-start; H-log-away; then `endSession(writeToHealth: false)` on the phone and flushes | Every snapshot composed between the log and the end names no `hold`; after the end the timer push attempts no `timer_state` and the ledger is empty (existing `_pushOnce` rule) | RED at the snapshot assertion only |
| S-12110 | H2 probe. F-A; H-start; the log while REACHABLE: `finishTimedEntry`, `timerPush.flush()`, apply, then two `autoPush` snapshots after phone changes, each applied | The hold is stopped after the clear and stays stopped after both snapshots | GREEN expected (the gate requires it) |
| S-12111 | H2 probe. S-12101 up to the apply; then the wrist (reachable) sends a `timer_state` reporting `hold` running for `sx-plank` from S_H (its revived copy) | `getTimedInstancesForEffort('sx-plank')` is still one `finished` instance; `inProgressWorkTimers()` has no hold; no `timer_state` sent after it names a running hold | GREEN expected (the gate requires it) |
| S-12112 | F-A; H-start; while REACHABLE, `finishTimedEntry` and then `projectedSession()` BEFORE `timerPush.flush()` (the auto push winning the race) | The projection names no `hold`, because D-1 reads the state, not the ledger | RED |
| S-12113 | F-A; H-start; H-log-away; the phone restarts as in S-12107; `unreachable = false`; the wrist sends `engine.sessionSnapshot()`; every phone frame sent after it is applied in order | The engine `hold` is stopped; record which frame stopped it (the snapshot's omission or the D-4 clear) | Record (either outcome; it may be GREEN) |
| S-12114 | F-A, but `sx-plank` has TWO intervals; H-start on interval 0; `unreachable = true`; `finishTimedEntry('sx-plank', 0)`; `startTimedEntry('sx-plank', 1)` (start S_H2 > S_H); flushes | The snapshot names no `hold` (the delivered S_H no longer matches; S_H2 was never delivered). Push only; the adoption is 121b's | RED |
| S-12115 | F-A; H-start; the wrist frame `timer_state` `{hold: {state: stopped, sessionExerciseId: sx-plank, startedAt: S_H, ...}}`, with no entry yet (the phone still runs interval 0; 43c D-4) | `projectedSession()` names no `hold` (D-1 (v)) | RED |

## Iteration 1

### Phase 0: probes, red first (crew-builder-app). No production code
1. [ ] Create `test/watch_logged_hold_stays_stopped_test.dart`: header listing D-ids and S-ids, the F-A harness, and `_QueueingPhoneRadio` as specified.
2. [ ] Write S-12101 to S-12105b and S-12112 asserting the fixed behaviour (Expected column), each with fixture asserts that pass today.
3. [ ] Write S-12106 to S-12111 and S-12113 to S-12115 the same way.
4. [ ] Run the file and record every test's result against the Today column in the evidence file as the D-9 gate table. A fixture assert that fails is a harness bug: fix the harness, never the expectation.
5. [ ] Apply D-9: write `H1 CONFIRMED` or `BLOCKED: H2 branch`, with the failing line of each RED test, in the evidence file and in Progress.
**Done Criteria:** `bash .claude/scripts/macos/with-timeout.sh 300 flutter test test/watch_logged_hold_stays_stopped_test.dart` has been run and its counts pasted (red is expected); `flutter analyze test/watch_logged_hold_stays_stopped_test.dart` shows 0 new issues.
**Predicted Files:** `test/watch_logged_hold_stays_stopped_test.dart` (new), `…-plan.evidence.md`, this plan (Progress, Assumption Log only).

### Phase 1: snapshot timers and reconcile (crew-builder-app). Only after `H1 CONFIRMED`
1. [ ] Add `snapshotTimers()` per D-1 in `lib/state/watch/watch_timer_push.dart`. Compose `wanted` through one helper shared with `_pushOnce`, so the two never disagree.
2. [ ] Delete `deliveredTimers()`. In `lib/state/watch/watch_sync_wiring.dart:267-274` the projection calls `snapshotTimers()`; reword its comment (the snapshot names only what the phone still runs).
3. [ ] Add the D-4 reconcile in `_pushOnce`, run in both pass kinds, before the `clearsOnly` filter (a clear is never withheld).
4. [ ] On a delivered clears frame, record D-5's `_stale` for each reconciled kind; update the `_stale` and class doc comments (plan 121a D-1, D-4, D-5).
5. [ ] Run the new file: everything green. Paste red→green per S-id into the evidence file.
6. [ ] Re-run the dependents (Done Criteria). Fix production code only; an existing test changing expectation is a stop-and-report.
7. [ ] Residue sweep D-11 (paste the grep). Update Progress and the Assumption Log.
**Done Criteria:** `bash .claude/scripts/macos/with-timeout.sh 900 flutter test test/watch_logged_hold_stays_stopped_test.dart test/watch_timer_push_test.dart test/watch_timer_adoption_test.dart test/watch_session_auto_push_test.dart test/watch_session_projection_test.dart test/live_mirroring_test.dart test/watch_reconciliation_cross_stack_test.dart test/watch_transport_test.dart` all green; `flutter analyze` issue count equal to the baseline in the evidence file; `grep -rn "deliveredTimers" lib test` empty; `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` empty.
**Predicted Files:** `lib/state/watch/watch_timer_push.dart`, `lib/state/watch/watch_sync_wiring.dart`, the evidence file, this plan (Progress, Assumption Log only). The new test file only for a harness fix logged in the Assumption Log. Nothing else; there is no `timer_manager.dart` change (the reconcile reads `WorkoutState` getters).

### Phase 2: docs (crew-docs-keeper)
1. [ ] `docs/state_management/watch_surface.md` (46,979 bytes, under the 52 KB band; adds about 1 KB): in the `WatchTimerPush` paragraph (about lines 238-284), state D-1 (a snapshot names only the delivered timers the phone still runs, read at compose time) and D-4/D-5 (the reconcile clear), each with a pointer to the S-id groups of the new test file. Also fix the drift in that same paragraph: it says a wrist rest within "2000 ms" is the same rest, but the code's `_restStartToleranceMs` is 500 ms. Name the constant instead of the number (doc standard §3.4).
2. [ ] `docs/watch_session_sync.md` (32,745 bytes) `## Invariants`: one bullet saying a phone snapshot never names a timer the phone no longer runs, so a logged interval cannot come back on the wrist through the durable path. Verified by `test/watch_logged_hold_stays_stopped_test.dart` (S-12101, S-12103).
**Done Criteria:** `bash .claude/scripts/macos/with-timeout.sh 300 flutter test test/docs_indexing_contract_test.dart test/ui_standards_contract_test.dart` green.
**Predicted Files:** the two docs, this plan's Progress.

Then the governor: the mutations below, crew-reviewer, the full `flutter test`, and `swift test --package-path watch/watchos --filter WatchTimedWorkTests` (no Swift change is expected; that run is only to confirm the S-1310 guard).

## Mutations for the governor (each must turn the named test red, then be restored)

| # | Mutation | Must fail |
|---|---|---|
| M1 | `snapshotTimers()` returns all of `_delivered` (the old behaviour) | S-12101, S-12103, S-12104, S-12105, S-12105b, S-12109 |
| M2 | D-1 reads a `wanted` cached by the last `_pushOnce` instead of composing it | S-12112 |
| M3 | drop D-1 (iv), the start match | S-12114 |
| M4 | drop D-1 (v), `_wristEnded` | S-12115 |
| M5 | D-1 (ii) dropped for `rest` only (a delivered rest stays named after the phone closed it) | S-12105b |
| M6 | remove the reconcile | S-12107 |
| M7 | the reconcile does not write `_stale` | S-12107 (second frame), S-12108d |
| M8 | the reconcile ignores the start match | S-12108a |
| M9 | the reconcile runs even when `wanted` has the kind | S-12108f |
| M10 | the reconcile includes `rest` | S-12108e |
| M11 | reconcile tolerance 1000 → 0 ms | S-12108g |
| M12 | the reconcile ignores an in-progress interval with the same start | S-12108b |
| M13 | D-1 (iii), the slot match, dropped | equivalent by construction (two efforts cannot share a start instant in this fixture); record it |
| M14 | Swift `senderWroteTimer` returns false | `testS1310APhoneSnapshotLeavesTheWristsWorkClockRunning` |

## Files Affected

`lib/state/watch/watch_timer_push.dart`, `lib/state/watch/watch_sync_wiring.dart`, `test/watch_logged_hold_stays_stopped_test.dart` (new), `docs/state_management/watch_surface.md`, `docs/watch_session_sync.md`.
Read only (dependents): `watch_session_auto_push.dart`, `watch_sync_request_handler.dart`, `watch_incoming_router.dart`, `live_session_mirror_state.dart`, the Swift and Dart wrist engines.
Size: about 70 to 100 production lines and about 900 test lines, in 3 phases on one track (phone). Within budget; no split.

## Notes

- Dependency graph: P0 → (gate D-9) → P1 → P2 → governor. P2 can run in parallel with the governor's mutations.
- Intermediate state after P0: the new file is red by design. The governor must not run the full suite between P0 and P1.
- If the gate fails (H2 branch), the next plan should start from the S-12110, S-12111 and S-12113 outcomes and from a device log of both apps around the log tap.
- Possible conflict with 121b: it edits the adoption (`timer_manager.dart`, `watch_timer_adoption.dart`), and this plan edits `watch_timer_push.dart` and `watch_sync_wiring.dart`. The file scopes do not overlap. Once 121b stops the stale copy being adopted into a next interval, D-4 is what clears that copy on the wrist.

## Owner checks (owner)

- (owner) Start a hold on the phone and see it counting on the watch. Lower your wrist. Log the hold on the phone and go to the next exercise. Raise your wrist: the watch no longer counts that hold, and it never starts counting it again during the session.
- (owner) The same, then delete the watch app from the iPhone and reinstall it while the session is still running. The reinstalled watch shows the session with no hold counting.
- (owner) Start a hold on the WATCH, log it on the phone with your wrist down, then force-quit and reopen the phone app before raising your wrist. When you raise it, the watch stops counting.
- (owner) Unchanged: start a hold on the phone and keep your wrist up. Logging it on the phone stops the watch at once.

## Noticed, not planned

1. Next interval on the same slot (121b's territory). A stale running copy on the wrist, with the earlier start, makes the wrist ignore the phone's later start for that slot (Swift `adoptTimer` D-4, earlier start wins). `TimerManager.adoptRemoteTimer` also replaces an in-progress phone interval's start with the stale earlier start. D-4 does not fire while the phone runs that kind (D-4 (iii)). Hand this to the 121b planner.
2. The Dart engine twin has no stale-snapshot guard (Swift `newestSnapshotAt`, `WatchSessionEngine.swift:562`), so the two engines differ when an older snapshot arrives late.
3. A pause on the phone that the radio refuses is carried in snapshots as the delivered, still-running copy (D-3). The wrist keeps counting until the wrist is reachable.
4. A live `timer_state` clear reaching a wrist that holds no session (a fresh install, before its snapshot) is refused by `guardSession`, but the phone counts it as delivered: there is no app-level acknowledgement. D-1 and D-4 make this harmless for this bug.
5. Snapshots still never carry a start the radio refused (plan 98 D-4). Carrying owed starts durably would let a phone timer reach a wrist that is out of reach.
6. Plan 98 F-3 (the phone's end of a session is told once and never owed) is still open.

## Progress

- [x] P0 probes and the D-9 gate (H1 CONFIRMED)
- [x] P1 D-1, D-4, D-5, D-11
- [x] P2 docs
- [x] Governor: mutations M1 to M14 (M10, M12, M13 equivalent); [ ] review (see .review.md); full suites left to the main session

## Assumption Log

- Governor (P0b): the stopped 0b run left 4 harness faults; the lead fixed them in the test file (mirror join after a phone restart, S-12111 fixture assert, S-12114 5 ms pause, tearDown). Expectations unchanged.
- Governor (P1): D-4 (v) start match made ONE-SIDED (wrist copy start <= phone interval start <= copy + 1000 ms). Reason: existing S-6329 pins that a wrist start 2 ms after a cleared copy wins; two-sided clears it. Tests: S-12108g now W-400 ms (clears), new S-12108h W+400 ms (no clear). Mutation M15 (two-sided) killed by S-6329 and S-12108h.
- Governor: `watch_surface_wrist.md:714` still says "2000 ms" for the rest tolerance (stale, outside predicted files, not fixed).

## Feedback

(empty)
