# Feature: 69 (series 67, piece 67b) — the watch's workout state waits for the phone instead of being dropped

> Status: Iteration 1 active. Planned 2026-10-24 against HEAD 88406be6 (`claude_develop`, tree clean). One owner question (Q1) is open with a recommended default; the plan is written on that default and Phase 1 may start on it.
> Next handoff: @developer (Phase 1)
> Series: `docs/plans/2026-10-23-67-phone-keeps-watch-current-series.md` (shared decisions D-1, D-3, D-4, D-7 of 67a apply, restated here for the wrist where they differ)
> Binding conventions: docs/global_conventions.md; .github/copilot/pr-scope-budget.md; watch/sync_protocol/PROTOCOL.md ("Idempotency and reconciliation", amendment rows 2026-10-08 "Honest delivery" and 2026-10-23 "The phone's workout messages can wait"); docs/state_management/watch_surface_wrist.md ("The wrist's half of the same radio").
> Working branch: the one checked out. Never create or switch branches. Evidence goes in `2026-10-24-69-watch-queues-workout-state-plan.evidence.md`, review findings in `…review.md`, both beside this file.

## Overview

| What happens on the watch while the phone is out of reach | Today | After 69 |
|---|---|---|
| You log sets, rests, a rating, a food | queued by the OS (plan 47b) | unchanged; each one still waits on its own |
| You start a workout, or add an exercise to it | the workout's state (its snapshot) is dropped; the phone learns the shape only when the watch app is next open near the phone | the newest state of each running workout waits; older waiting copies are withdrawn |
| You press Sync on the watch while apart | the snapshot it sends is dropped | it waits (replacing the older copy) |
| You move between exercises 25 times | 25 "moved" messages wait | only the newest move waits |
| You finish or give up the workout | the end waits (47b) | the end waits and is never withdrawn; the waiting live state of that workout is withdrawn (Q1 default) |
| A running timer | dropped | still dropped |

No screen changes. No phone code changes. The phone already ignores a snapshot older than the newest it applied (plan 63 D-1) and treats a repeated lifecycle as a no-op.

## Facts from source (read 2026-10-24)

- The wrist sends exactly four message types, all built in `watch/watchos/Sources/WatchSessionEngine/WatchSessionEngine.swift`: `session_snapshot` (`sessionSnapshot`, messageId `msg-snapshot-<session row recordId>`, `sentAt` = clock at build), `observations_up` (`observationsUp`, messageId `msg-<recordId>`), `timer_state` (`timerState`), `session_lifecycle` (`lifecycle`, messageId `msg-<row recordId>`, `sentAt` = row `recordedAt`; states `started`, `exercise_advanced`, `completed`, `abandoned`). Plus two requests with no `type` (`WatchTransportRequest.routinesFrame`, `snapshotFrame`). It sends no `receipt`, `structure_change` or `exercise_push` (`grep -rn '"type": "' watch/watchos/Sources`).
- **A snapshot's messageId is not unique per content.** Logging a set writes no session row, so a snapshot rebuilt after it (Sync button, catch-up) carries the same messageId with newer entries and a later `sentAt`. The app target's `queue` skips a frame whose messageId is outstanding, so with today's dedupe a newer snapshot would be refused behind its older twin.
- Snapshot emission sites: `createSessionExclusive` (after the `started` lifecycle), `insertExercise(announce: true)` (the wrist's own add), `WatchSyncOrchestrator.sync` → `answerSnapshotRequest` (Sync button and catch-up), and the refusal answer in `receive`. A logged set emits only `observations_up`; an exercise move emits only `session_lifecycle(exercise_advanced)`.
- `WatchConnectivityBridge.send`: on a throwing `session.send`, a frame passing `isDurable` (`observations_up`, `session_lifecycle`) goes to `session.queue`; others are reported and dropped. A send that succeeds is never queued.
- App target `ios/OmniTrain Watch App/OmniTrainWatchConnectivity.swift`: `send` throws `phoneNotReachable` when unreachable; its `sendMessage` error handler (a late refusal, on WCSession's queue) calls `self.queue(frame)` for a durable frame directly, bypassing the bridge. `queue` = activation guards, skip if messageId outstanding, one `transferUserInfo`. It has no list or cancel.
- Bookkeeping: `WatchSyncTransport.send` returns nothing. The only thing that settles a wrist frame is the phone's `receipt` (`confirmObservations`); `unconfirmedObservations` feeds the "N entries waiting for your phone" line. A send or a queue changes no store row.
- The phone adopts a running wrist workout only from a snapshot with status `active` (`WatchSessionAdoptionBridge.consider`); an ended wrist workout reaches history through the `session_end` observation (importer). A lifecycle naming a session the phone does not hold changes nothing (`onLifecycle`, `_namesMirroredSession`).
- Package targets `.macOS(.v13), .watchOS(.v9)`. `outstandingUserInfoTransfers` and `WCSessionUserInfoTransfer.cancel()` exist since watchOS 2. The append-only guard (`WatchSessionEngineTests.testS004NoMutatingOperationExistsAnywhereInTheModule`) bans any `Sources` func name starting with update/delete/remove/replace/edit/overwrite/write/clear/purge/wipe/reset/drop/truncate/erase/forget/modify/mutate/destroy/set.

## Owner question (one round)

- **Q1.** You start and finish a workout on the watch while the phone is out of reach (phone at home). When the two meet again, what should the phone do? **Recommended default (A): the workout simply appears in the phone's history, as it does today.** (B): the phone first opens it as a running workout, then finishes it, as it does when the phone was nearby the whole time; this also keeps an exercise you added on the watch to a workout the phone started, at the cost of the phone briefly treating an old workout as live. The plan is written on (A): D-3's terminal arm. (B) means deleting that arm and S-9908's withdrawal half.

## Resolved Decisions (Ledger)

- **D-1 A queued copy is a carrier, not a delivery.** Queuing writes nothing to the wrist store. An owed observation stays owed (and counted in "waiting for your phone") until the phone's `receipt`. Matches 67a D-1.
- **D-2 Queued types.** When the radio refuses a frame (at the call, or later in the `sendMessage` error handler), these are queued: `observations_up` (unchanged), `session_lifecycle` of any state (unchanged), and `session_snapshot` whose `payload.status` is `"active"` (new). Never queued, reported and dropped as today: `timer_state`; requests (no `type`); a snapshot whose status is `completed`, `abandoned` or missing; anything else.
- **D-3 Replacement keys.** For a frame F about session s (F's top-level `sessionId`), the withdraw set W is:
  - F is `session_snapshot`: every outstanding `session_snapshot` of s.
  - F is a non-terminal lifecycle (`started`, `exercise_advanced`): every outstanding non-terminal `session_lifecycle` of s.
  - F is a terminal lifecycle (`completed`, `abandoned`) — **derived from the owner's "newest copy only" rule, vetoable via Q1**: every outstanding `session_snapshot` of s and every outstanding non-terminal lifecycle of s.
  - F is `observations_up`: nothing.
  Never in any W: an `observations_up`; a terminal lifecycle; a transfer of another session; a transfer whose frame lacks a string `messageId` or `type`.
- **D-4 Newest wins, by the wrist's own `sentAt`.** Only copies whose `sentAt` is earlier than or equal to F's join W. If a copy that would be in W has a later `sentAt` than F, F is stale: on the queue path F is not queued and nothing is withdrawn (not reported: not a failure); on the live path F is still sent, and that newer copy stays. A terminal F is never stale: it is always queued and withdraws its whole W. An unreadable `sentAt` counts as oldest on an outstanding copy and as newest on F.
- **D-5 Same messageId.** For a snapshot F, an outstanding snapshot with F's own messageId is in W like any other (same id, possibly newer entries). For every other type, an outstanding transfer with F's messageId means F already waits: F is not queued again and keeps its place. This dedupe moves into the package; the app target keeps its own check as a second line.
- **D-6 When it runs.** (a) Before queuing a refused durable frame, on both refusal paths. (b) After a durable frame is handed to the radio live: W is withdrawn, nothing is queued. If that live send then fails, path (a) queues F.
- **D-7 One step, one lock.** List → withdraw → queue runs as one step under one lock shared by every path (bridge call path and app-target late-refusal path), so two hand-overs at once cannot both keep a copy.
- **D-8 Failures.** A queue refusal is reported once (unchanged), after W was withdrawn; the older copy is then gone and the next trigger re-sends. Listing and cancelling do not throw: an unsupported or not-activated session lists nothing and cancels 0.
- **D-9 Order and scope.** Queue order is OS order (first in, first out); withdrawal only removes. The OS queue is the only queue: no app-layer buffer, retry or timer. The bridge still sends nothing unsolicited.
- **D-10 Seam.** `WatchConnectivitySession` gains exactly two members: list the outstanding transfers' frames in OS order, and cancel the outstanding transfers whose messageId is in a given list, answering the count. All replacement logic (D-2…D-7) lives in the package behind one entry point that takes the session. The app target implements the two members over `outstandingUserInfoTransfers` / `cancel()`, and its late-refusal path calls the package entry point instead of `self.queue`. New names must pass the append-only guard (suggested: `outstandingTransfers()`, `cancelTransfers(messageIds:)`, `WatchConnectivityBridge.queueNewest(_:on:)`).
- **D-11 Contract.** One amendment row in `watch/sync_protocol/PROTOCOL.md` plus one sentence in "Idempotency and reconciliation": the wrist MAY queue `observations_up`, `session_lifecycle` and an active `session_snapshot` through the OS; it MAY withdraw a queued copy per D-3/D-4; it never withdraws an `observations_up` or a terminal lifecycle; it never queues `timer_state` or a request; a queued copy settles nothing (D-1). It supersedes the 2026-10-08 "Honest delivery" row's "Nothing is queued then or now" for these wrist-sent types, as 67a's row did for the phone's. No shape, schema, fixture or version change.
- **D-12 Supersedures.** S-6706 → S-9901; S-6703's snapshot arm → S-9902; S-6707's "four queued, all `observations_up`" → S-9909. The other S-6701…S-6708 assertions stand.

## Feature Invariants

- After any hand-over completes, the OS queue holds at most one `session_snapshot` per session and at most one non-terminal `session_lifecycle` per session.
- An `observations_up` and a terminal lifecycle, once queued, are never withdrawn. `timer_state` and requests are never queued.
- Queuing and withdrawing write nothing to the wrist store (append-only rule, S-004).

## Acceptance Criteria

- AC-1 An active workout's newest state waits for the phone; older copies are withdrawn; a stale copy never replaces a newer one (S-9901…S-9907, S-9916).
- AC-2 The end of a workout and every logged entry always wait; repeats do not pile up (S-9908…S-9910).
- AC-3 Live sends clear older waiting copies; nothing is counted as delivered by being queued (S-9911, S-9912).
- AC-4 Failures and concurrent hand-overs stay within the invariants (S-9913, S-9914).
- AC-5 The app target uses the package's rule on both refusal paths (S-9915).

## Existing-Functionality Impact

| Touched surface | Readers (grep) | Effect | Guard |
|---|---|---|---|
| `isDurable` | `grep -rn "isDurable" watch/watchos ios` → the bridge, the app target's error handler, `WatchBridgeQueueTests` (S-6706), `WatchQueueSourceTests` (S-6708) | an active snapshot becomes durable | S-9901 supersedes S-6706; S-6708 unchanged |
| `WatchConnectivitySession` | `grep -rln "WatchConnectivitySession" watch/watchos/Sources watch/watchos/Tests "ios/OmniTrain Watch App"` → bridge, `FakeWatchConnectivitySession.swift`, `WatchConnectivityBridgeTests.swift` (harness), `OmniTrainWatchConnectivity.swift` | two members added; all conformers implement them | Phase 1 compiles the fake; Phase 2 + governor `xcodebuild` the app |
| Bridge refused-frame tests | `WatchConnectivityBridgeTests`: `testASendThePlatformRefusesIsReported` (a request), `testS206ARefusedFrameIsReportedOnceAndTheRowStaysOwed` (an observation, queue refuses) | none: neither sends a snapshot | rerun unchanged |
| S-6707 orchestrated catch-up | `WatchBridgeQueueTests.testS6707…` | `sync()` now also queues the snapshot, and the package dedupes, so "4, all observations_up" no longer holds | S-9909 supersedes it |
| Phone receiving a late wrist snapshot | `LiveSessionMirrorState.isStaleSnapshot` (plan 63 D-3) | receives queued copies | `test/watch_message_order_test.dart` S-9305…S-9307, unchanged (no Dart change) |
| Phone adopting a running wrist workout | `WatchSessionAdoptionBridge.consider`, `WatchIncomingRouter.receive` (D-182 two-workouts answer) | now reached from a queued copy, the same path a live snapshot takes | `test/live_mirroring_test.dart`, `test/pr4_session_controls_test.dart` S-213, unchanged |
| Phone ending an ended wrist workout | `WatchSessionAdoptionBridge.onLifecycle`; importer via `session_end` | with Q1 (A) the phone receives no live state for an ended apart workout, as today | S-9908 |
| Waiting line on the watch | `WatchSessionEngine.unconfirmedObservations`, `deriveSyncNotice` | none | S-9912 |
| Docs | `docs/state_management/watch_surface_wrist.md` 49,273 bytes (band 52 KB) | one paragraph rewritten | Phase 2 size check |
| Standing invariants (docs/global_conventions.md) | no UI, no repository, no Dart | N/A | — |

## UI Standards Impact

None: no UI change.

## Scenarios

Fixture **Q** (Phase 1): `FakeWatchConnectivitySession` extended with an `outstanding` list of frames (OS order). A queue call appends to it (and still to `queued`, the call record; the fake does not dedupe), cancel removes matching messageIds and records them in `cancels`; `sendError`/`queueError` as today; all members thread-safe. "Apart" = `sendError` set. Clock T0 = 2026-07-13T06:00:00.000Z (`testInstant()`); tN = T0 + N s. Shorthand: snap(s, m, t[, status]) = `{type: session_snapshot, messageId: m, sessionId: s, sentAt: t, payload: {sessionId: s, status: status ?? "active"}}`; lc(s, state, m, t); obs(s, m); hand over = `bridge.send(frame)`.

### Phase 1
### S-9901 (supersedes S-6706): which frames may wait
- Fixture: frames snap(s-1,m,t1,"active"), snap(…,"completed"), snap(…,"abandoned"), a snapshot with no `payload`, lc(s-1, each of the four states), obs(s-1,m), `timer_state`, `receipt`, `snapshotFrame()`, `[:]`.
- Expected: `isDurable` true for the active snapshot, the four lifecycles and the observation; false for the other seven.
- Edge case of: S-6706
### S-9902 (supersedes S-6703 snapshot arm): a refused snapshot waits, an ended one does not
- Fixture: harness (`WatchBridgeHarness`), apart. A: `createSession(exercises: [exercise("sx-bench")])`, `sessionSnapshot()`. B: the same, then `finishSession()`, `sessionSnapshot()` (status completed).
- Expected: A `queued` holds it under its messageId, `sent` empty, failures 0. B reported once, `queued` empty.
- Edge case of: S-6703
### S-9903: only the newest snapshot of a workout waits
- Fixture: Q apart; outstanding `[snap(s-1,mA,t1), snap(s-2,mB,t1), obs(s-1,mO), lc(s-1,started,mL,t0), {"foo": 1}, {"messageId": "x"}]`.
- Trigger: hand over snap(s-1,mC,t2).
- Expected: cancels exactly `[mA]`; outstanding `[mB, mO, mL, {"foo":1}, {"messageId":"x"}, mC]`; failures 0.
- Edge case of: none
### S-9904: same messageId, newer content (near-twin)
- Fixture: A Q apart; outstanding `[snap(s-1,mA,t1)]` with `payload.entries` `[]`. B harness apart: `createSession`, its emitted snapshot (messageId M, `sentAt` T0) handed over; one set `e-1` logged (no new session row, so M is unchanged); clock +60 s; `orchestrator.sync()`.
- Trigger: A hand over snap(s-1,mA,t2) with entries `[e-1]`.
- Expected: A cancels `[mA]`; exactly one outstanding transfer with id mA, `sentAt` t2, one entry. B exactly one outstanding snapshot: messageId M, `sentAt` T0+60, entries `[e-1]`.
- Edge case of: S-9903
### S-9905: a stale copy handed over late (out of order)
- Fixture: Q apart; outstanding `[snap(s-1,mN,t3)]`.
- Trigger: A hand over snap(s-1,mO,t2). B then hand over snap(s-1,mE,t3) (equal stamp).
- Expected: A no cancel, mO not queued, outstanding `[mN]`, failures 0. B cancels `[mN]`, outstanding `[mE]`.
- Edge case of: S-9903
### S-9906: 40 exercises added while apart (overflow)
- Fixture: harness apart; `createSession(exercises: [exercise("sx-0")])`; then `insertExercise(exercise("sx-\(i)"))` for i = 1…40, clock +1 s before each; every emitted frame handed over in emission order.
- Expected: after each hand-over exactly one outstanding `session_snapshot`; 41 snapshots handed over, 40 snapshot cancels; the survivor carries 41 exercises. Exactly one outstanding lifecycle (`started`).
- Edge case of: S-9903
### S-9907: 25 exercise moves while apart
- Fixture: harness apart; `createSession` with slots sx-a, sx-b, sx-c; then 25 `selectExercise` calls cycling sx-b, sx-c, sx-a (clock +1 s each); every emitted frame handed over in order.
- Expected: exactly one outstanding lifecycle: `exercise_advanced` with `exerciseIndex` 1 (25th pick = sx-b); 25 lifecycle cancels (the `started` one and 24 moves); the snapshot from the start remains.
- Edge case of: none
### S-9908: the end always waits and withdraws the workout's live state (Q1 default)
- Fixture: Q apart; outstanding `[lc(s-1,started,mS,t0), snap(s-1,mP,t1), obs(s-1,mO1), lc(s-1,exercise_advanced,mA,t2), lc(s-2,started,mS2,t0), lc(s-3,abandoned,mX,t1)]`.
- Trigger: A hand over lc(s-1,completed,mC,t3). B hand over the same frame again (the D-199 replay). C hand over lc(s-3,started,mY,t2).
- Expected: A cancels exactly {mS, mP, mA}; outstanding `[mO1, mS2, mX, mC]`. B no cancel, not queued again, mC outstanding once. C mX stays; mY queued.
- Edge case of: S-6702
### S-9909 (supersedes S-6707's count): two catch-ups apart
- Fixture: harness apart; session with sets q-1, q-2 (clock +90 s between).
- Trigger: `orchestrator.sync()` twice.
- Expected: outstanding exactly `[obs q-1, obs q-2, snapshot]` in that order; one snapshot cancel (the second sync's equal-stamp copy replaces the first); no observation queued twice.
- Edge case of: S-6707
### S-9910: entries are never withdrawn; timers and requests never wait
- Fixture: Q apart; outstanding `[obs(s-1,mO1)]`.
- Trigger: hand over obs(s-1,mO2), snap(s-1,mP,t1), lc(s-1,completed,mC,t2); then a `timer_state` for s-1; then `requestSnapshot()`.
- Expected: mO1 and mO2 outstanding, never in a cancel; the timer and the request are each reported once, not queued, no cancel.
- Edge case of: S-6703
### S-9911: a live send clears older waiting copies
- Fixture: Q reachable (no `sendError`); outstanding `[snap(s-1,mA,t1), lc(s-1,started,mS,t0), obs(s-1,mO)]`.
- Trigger: A send snap(s-1,mB,t2). B send lc(s-1,completed,mC,t3). C outstanding reset to `[snap(s-1,mN,t5)]`, send snap(s-1,mOld,t4).
- Expected: A `sent` `[mB]`, cancels `[mA]`, nothing queued. B cancels `[mS]`; outstanding `[mO]`. C mOld is sent; no cancel; mN stays.
- Edge case of: S-6705
### S-9912: waiting is not delivered
- Fixture: harness apart; session with sets e-1, e-2; `orchestrator.sync()`.
- Expected: `unconfirmedObservations.count` 2; `deriveSyncNotice` with reachability unreachable says "2 entries waiting for your phone"; store holds no confirmation row.
- Edge case of: S-206
### S-9913: failures
- Fixture: Q apart; outstanding `[snap(s-1,mA,t1)]`. A `queueError` set. B a fake session reporting not activated (lists `[]`, cancels 0, `queue` throws).
- Trigger: hand over snap(s-1,mB,t2).
- Expected: A cancels `[mA]`, mB not outstanding, one failure (the queue's error). B no cancel, one failure.
- Edge case of: S-6704
### S-9914: two hand-overs at once leave one copy
- Fixture: Q apart; the fake's first `outstandingTransfers()` call waits up to 200 ms for a second caller to enter it (a deterministic race window).
- Trigger: two tasks hand over snap(s-1,m1,t1) and snap(s-1,m2,t2) at once.
- Expected: exactly one outstanding s-1 snapshot, m2. Without D-7's lock, both read the same list and two remain.
- Edge case of: S-9903
### S-9916: copies left by an earlier run are matched
- Fixture: Q apart with outstanding pre-seeded `[snap(s-watch-1,mOld,t0)]` before the harness launches (a previous app run); a fresh harness, restored, with an active session s-watch-1.
- Trigger: `orchestrator.sync()` (clock T0 + 30 s).
- Expected: cancels `[mOld]`; one outstanding snapshot with `sentAt` T0+30.
- Edge case of: S-9903

### Phase 2
### S-9915: the app target uses the package rule (source guard)
- Fixture: `OmniTrainWatchConnectivity.swift`, comment-stripped (the `WatchQueueSourceTests` helper).
- Expected: contains `func outstandingTransfers(` (or the chosen names), `outstandingUserInfoTransfers`, `.cancel()`, and the package entry point call inside the `sendMessage` error handler; does not contain `try self.queue(frame)`; exactly one `transferUserInfo(` (S-6708 kept); both new members contain `activationState == .activated`.
- Edge case of: S-6708

## Iteration 1

### Phase 1: the package keeps only the newest workout state waiting (@developer)
1. [ ] Gate G-1: paste the empty output of `git status --porcelain -- watch/watchos/Sources/WatchSessionEngine/WatchConnectivityBridge.swift watch/watchos/Tests/WatchSessionEngineTests/FakeWatchConnectivitySession.swift watch/watchos/Tests/WatchSessionEngineTests/WatchBridgeQueueTests.swift` into evidence; stop if it is not empty.
2. [ ] Two seam members (D-10); rewrite the "five members" and rule-2 header comments — `WatchConnectivityBridge.swift` · `WatchConnectivitySession`
3. [ ] `isDurable` per D-2 — same file · `WatchConnectivityBridge.isDurable`
4. [ ] Replacement entry point D-3…D-8 under one lock; `send` uses it on refusal and withdraws W after a live hand-off (D-6) — same file · `WatchConnectivityBridge.send` + new static entry point
5. [ ] Fixture Q — `FakeWatchConnectivitySession.swift`
6. [ ] Supersede S-6706, S-6703 snapshot arm, S-6707 with S-9901, S-9902, S-9909 (rename the test functions to the new ids) — `WatchBridgeQueueTests.swift`
7. [ ] S-9903…S-9908, S-9910…S-9914, S-9916 — new `watch/watchos/Tests/WatchSessionEngineTests/WatchBridgeReplacementTests.swift` (reuse `WatchBridgeHarness`)
8. [ ] Red proof: each mutation in the Verification table run once, killed; table in evidence

**Done Criteria** (run until green):
- `bash .claude/scripts/macos/with-timeout.sh 900 swift test --package-path watch/watchos --filter WatchSessionEngineTests` (append-only guard) and the full `swift test --package-path watch/watchos` (Copilot: gateway `swift-test`); paste the counts.
- `flutter test test/ui_standards_contract_test.dart test/docs_indexing_contract_test.dart`.
- The AGENTS.md invariant grep is empty.

**Predicted Files**: `watch/watchos/Sources/WatchSessionEngine/WatchConnectivityBridge.swift`, `watch/watchos/Tests/WatchSessionEngineTests/FakeWatchConnectivitySession.swift`, `watch/watchos/Tests/WatchSessionEngineTests/WatchBridgeQueueTests.swift`, `watch/watchos/Tests/WatchSessionEngineTests/WatchBridgeReplacementTests.swift` (new), the evidence file. About 150 lines of production Swift.

### Phase 2: the watch app, the contract and the docs (@developer) — after Phase 1
1. [ ] Gate G-2: empty `git status --porcelain -- "ios/OmniTrain Watch App/OmniTrainWatchConnectivity.swift" watch/watchos/Tests/WatchSessionEngineTests/WatchQueueSourceTests.swift watch/sync_protocol/PROTOCOL.md docs/state_management/watch_surface_wrist.md`, pasted into evidence.
2. [ ] The two seam members over `WCSession` (D-8 guards; skip a transfer with no string messageId); the `sendMessage` error handler calls the package entry point; `queue` keeps its dedupe and its single `transferUserInfo` — `ios/OmniTrain Watch App/OmniTrainWatchConnectivity.swift`
3. [ ] S-9915 — `WatchQueueSourceTests.swift` (new test functions; the S-6708 ones stay)
4. [ ] D-11 row and sentence — `watch/sync_protocol/PROTOCOL.md` (append the row after the 2026-10-23 rows; the sentence in the "A frame the sender handed to the platform queue…" bullet)
5. [ ] Rewrite the "A live-only frame that fails…" paragraph (l.58-75) to D-2…D-8 with the new test file — `docs/state_management/watch_surface_wrist.md` (49,273 bytes now; net growth at most 1,500 bytes; `wc -c` must stay below 52,000)
6. [ ] Residue sweep, each empty: `grep -rn "a snapshot would arrive stale" watch/watchos/Tests`; `grep -n "true exactly for .observations_up. and .session_lifecycle." docs/state_management/watch_surface_wrist.md`; `grep -n "try self.queue(frame)" "ios/OmniTrain Watch App/OmniTrainWatchConnectivity.swift"`; `grep -n "Deliberately five members" watch/watchos/Sources/WatchSessionEngine/WatchConnectivityBridge.swift`.

**Done Criteria**: full `swift test --package-path watch/watchos` (900 s wrapper), counts pasted; `flutter test test/ui_standards_contract_test.dart test/docs_indexing_contract_test.dart`; the size check; the residue greps; the invariant grep. **Governor (not the implementer):** `xcodebuild -workspace ios/Runner.xcworkspace -scheme "OmniTrain Watch App" -destination "platform=watchOS Simulator,name=Apple Watch Series 11 (42mm)"` → BUILD SUCCEEDED (revert any `project.pbxproj` rewrite the build makes).

**Predicted Files**: `ios/OmniTrain Watch App/OmniTrainWatchConnectivity.swift`, `watch/watchos/Tests/WatchSessionEngineTests/WatchQueueSourceTests.swift`, `watch/sync_protocol/PROTOCOL.md`, `docs/state_management/watch_surface_wrist.md`, the evidence file. About 40 lines of production Swift.

## Verification (Code Reviewer)

Diff vs Predicted Files per phase; per-S conformance to the fixtures; Impact greps re-run. Each mutation must turn a test red:

| Mutation | Test that must fail |
|---|---|
| active snapshot not durable | S-9901, S-9902 A |
| ended snapshot durable | S-9901, S-9902 B |
| withdraw ignores `sessionId` | S-9903 |
| snapshot's own messageId not withdrawn | S-9904 |
| no `sentAt` comparison (newest-wins removed) | S-9905 A |
| `<` instead of `<=` for withdrawal | S-9905 B |
| terminal lifecycle withdrawn by a later frame | S-9908 C |
| terminal arm removed (Q1 (B)) | S-9908 A |
| observation withdrawn | S-9910 |
| no withdraw after a live hand-off | S-9911 A/B |
| package dedupe removed | S-9908 B, S-9909 |
| lock removed | S-9914 |
| late-refusal path back to `self.queue` | S-9915 |

## Owner device checks (owner, after Phase 2)

1. Turn Bluetooth and Wi-Fi off on the phone. On the watch start a Free workout, add two exercises, log one set, then lower your wrist so the watch app goes to the background. Turn the phone's radios back on and open the phone app without touching the watch: the workout shows as in progress with both exercises and the set.
2. Same, but finish the workout on the watch before turning the radios back on: the workout appears once in the phone's history, and the phone does not open it as a running workout (Q1 default).
3. With the radios off, move between exercises on the watch several times, then turn them on: with the workout open on the phone, it shows the exercise you ended on.

## Files Affected

Phase lists above. Dependents that only read a touched surface: the phone's mirror, router and adoption bridge (`lib/state/watch/`), unchanged and not edited.

## Notes

- Dependency graph: Phase 1 → Phase 2 (Phase 2's app code calls the Phase 1 entry point). No reordering is useful.
- Intermediate state after Phase 1: the package rule is live on the bridge path (refused at the call, which is the unreachable case), but the app's late-refusal path still queues directly, so a late refusal can leave an older copy beside the new one. Harmless (the phone ignores the stale one); Phase 2 closes it.
- Known and left:
  - A transfer already being sent cannot be cancelled; that copy may reach the phone after a newer one. A snapshot is then ignored (plan 63 D-1). A late `started` after a live `completed` would set the phone mirror's status back to active; the phone's own session stays ended. This existed before (lifecycles were queued since 47b) and is narrower now (D-6 (b)).
  - The phone handles a wrist workout that conflicts with its own the same way it does on a live catch-up (D-182); it just learns earlier.
- iOS/watchOS only.

## Progress

- Phase 1: built 2026-10-24, uncommitted (evidence in the evidence file); Q1 answered (A).
- Phase 2: built 2026-10-24, uncommitted (owner device checks open).

## Assumption Log

- Deviation: the two new seam members (`outstandingTransfers()`,
  `cancelTransfers(messageIds:)`) have default implementations in a protocol
  extension (so the app target compiled between the phases); Phase 2 gives the
  app the real ones.

## Feedback
