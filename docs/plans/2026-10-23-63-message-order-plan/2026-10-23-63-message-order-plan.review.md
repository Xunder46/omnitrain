# Review: 63 message-order · P1-P4 · base..working tree
Verdict: APPROVE
Counts: blocker 0 · major 0 · minor 1 · tests: reviewer ran none (brief forbids); governor's facts: `flutter test` green (+5483 passed, 2 skipped), `swift test` 916 passed / 0 failed, `xcodebuild` BUILD SUCCEEDED
Diff vs Predicted Files: conforms — the 13 changed files are exactly the plan's list (plan 62's edits inside `watch_transport.dart` `sinceOf`, `PROTOCOL.md` `since` bullet + amendment row, `watch_surface*.md`/`watch_session_sync.md` plan-61/62/64/65 passages were skipped as out of scope per the brief)

## Findings

1. [Minor] `lib/core/platform/watch_transport.dart:352` (`close`) — a frame whose turn is still queued when `close()` runs is still handled afterwards: `close()` cancels the subscriptions but never awaits `_lane`, and the chained turns keep running the handler captured at arrival (up to N × 30 s later). A maintainer tearing the transport down in a test sees the handler run against a torn-down wiring; its failure is reported through `_onFailure` after `_heard`/`_linkChanges` are closed, so nothing crashes, but the run is surprising. The shipped flow is safe (`onIncoming` is documented "set once"), so this is a robustness nit, not wrong behaviour. Fix: `await _lane;` as the first line of `close()` (bounded by the per-frame timeout), or one doc sentence on `close()` saying queued turns outlive it. Guard: a test that closes the transport with a suspended first handler and asserts the second handler's fate.

## Brief questions

1. Phone `_dispatch` (`watch_transport.dart:329-347`): no permanent deadlock and no lost frame. A handler that awaits a send whose answer is another inbound frame waits on a turn queued behind its own — the 30 s `timeout` in `_handle` (`:349-356`) breaks the wait, reports a `TimeoutException`, and the lane proceeds; the abandoned handler keeps running (documented in D-2, same trade-off as the auto-push). A throw cannot kill the lane: `_handle` catches everything, so `_lane` always completes and the next `.then` runs. `close()` while frames are queued is finding 1.
2. `WatchInboundLane.swift`: order holds. `enqueue` (`:15-23`) appends and reads `running` inside one `lock.lock() … lock.unlock()` region; `next()` (`:33-42`) takes `waiting.first` (or sets `running = false` when empty) inside `lock.lock(); defer { lock.unlock() }`. The race the question names cannot lose a frame: if `enqueue` appends before `next()` finds the queue empty, the running drain's next `next()` takes the frame; if it appends after `next()` set `running = false`, `start` is true and a fresh `Task { drain() }` starts. `running` transitions are atomic with the queue reads under the same lock, so at most one drain is alive and handling order = append order (the radio's delegate queue is serial, per the type comment).
3. `applySnapshotExclusive` (`WatchSessionEngine.swift:543-625`): the stale check (`:553`) is the first statement after the parse guard, before the D-78 foreign-session guard, before `unhideTheIdTheSnapshotNames` (`:576-578`), before `captureSessionEnd` (`:583`), before `storeSessionRow` (`:585`) and the entry store. `newestSnapshotAt = max(...)` (`:603`) sits after `storeSessionRow`, on the apply path only; every refusal path (`return nil`) leaves it untouched. `restore` seeds it from the `snap-` rows' `recordedAt` (`:158-161`), which is the snapshot's `sentAt`.
4. No legitimate flow sends a phone snapshot stamped earlier than an earlier one. Every send composes a fresh envelope: `snapshotEnvelope` stamps `sentAt: _clock()` at composition time (`live_session_mirror_state.dart:355-368`), and all callers go through it — `sendState`/`sendSnapshot` (`:374-376`) and the auto-push's `_mirror.sendState(composed)` (`watch_session_auto_push.dart:298, 310`), so a re-offer recomposes with a later stamp, never replays the original. The transport's OS queue carries receipts only (`isDurable` = `receipt`, `watch_transport.dart:225-227`), never snapshots. The request handler's `snapshot` answer is the mirror's `sendSnapshot` — same fresh stamp. A frozen clock exists only where a test injects one, which the plan's readers list already covers (suite green per the governor).
5. Yes. The two PROTOCOL.md bullets (`watch/sync_protocol/PROTOCOL.md:415-432`) state the 30 s phone timeout, the watch's whole refusal (no structure/status/position/revision/timers/entries/tombstone, answers nothing), the equal-stamp-applies arm, the single cross-workout stamp, the sender's-own-clock basis, the watch stamp surviving a relaunch vs the phone's in-memory stamp, the phone still staging a stale snapshot's entries (true: the router stages via `_inbox.receive` before the mirror answers, `watch_incoming_router.dart:122-124`, so the mirror's early return does not undo staging), and the clock-backwards limit. `docs/state_management/watch_surface.md:441-451` and `docs/state_management/watch_surface_wrist.md:159-173` match the code (`isStaleSnapshot`, `MirrorOutcome.ignored`, `newestSnapshotAt`, `restore()` seeding, the three test files). Every named type, file and test exists — read this run.

## Assumption Log rulings

The plan carries a Decision Ledger, not an Assumption Log; ruled on its entries:
- D-1 (one rule, both devices, one stamp across workouts) — ratify; implemented as stated on both sides, S-9307 and the S-9312 other-workout arm pin the cross-workout part.
- D-2 (phone lane + 30 s timeout, `_heard` on arrival, `_handle` never throws) — ratify; code matches word for word, S-9301..S-9304 pin it.
- D-3 (phone stale rule placement, advance after apply, router untouched, staging kept) — ratify; placement is right after the `_consumedTypes` check (`live_session_mirror_state.dart:223`), advance after `applyMessage` (`:244-254`).
- D-4/D-5 (watch lane, shell `deliver` → `lane.enqueue`, `receiveHandler` stays `@concurrent`) — ratify; `receiveHandler` declaration read (`OmniTrainWatchConnectivity.swift:42`), `lane.enqueue(message)` in `deliver` (`:165`).
- D-6 (watch stale rule, refusal before any side effect, stamp seeded in `restore`) — ratify; see question 3.
- D-7 (PROTOCOL.md text) — ratify; see question 5.
- D-8 (Dart twin, sequence numbers, phone change feed out of scope) — ratify; the twin is untouched by this diff.

## Scenario coverage

Phone (`test/watch_message_order_test.dart`):
- S-9301 → `S-9301 the second handler does not start until the first completes` | present
- S-9302 → `S-9302 the second frame is still handled, the failure reported once` | present
- S-9303 → `S-9303 with a 50 ms timeout the second handler starts within 500 ms and the TimeoutException is reported` | present
- S-9304 → `S-9304 both frames are heard before the first handler completes` | present
- S-9305 → `S-9305 the state stays at the newer snapshot, nothing is notified` | present
- S-9306 → `S-9306a` equal / `S-9306b` later / `S-9306c` unparsable | present, one test per arm
- S-9307 → `S-9307 an older snapshot of an earlier workout is ignored` | present

Watch:
- S-9310 → `WatchInboundLaneTests.testS9310FramesAreHandledOneAtATimeInOfferOrder`, `…AfterTheLaneWentIdleIsStillHandled`, `…TwoPausedRoundsAreBothHandledInOrder` | present (order, no overlap, restart)
- S-9311 → `WatchStaleSnapshotTests.testS9311AnOlderSnapshotIsRefusedAndChangesNothing` | present
- S-9312 → `…EqualStampApplies`, `…LaterSnapshotApplies`, `…OlderSnapshotOfAnotherWorkoutIsRefusedToo`, `…RefusedSnapshotStoresNoRow` | present, one test per arm
- S-9313 → `testS9313ARestoredEngineRefusesTheOlderSnapshotToo` | present
- S-9314 → `testS9314AStaleSnapshotDoesNotUnHideADeletedEntry` | present
- S-9315 → `WatchInboundLaneWiringSourceTests.testS9315DeliverHandsFramesToTheLane`, `…EngineRefusesASnapshotOlderThanTheNewestApplied` | present, on comment-stripped text

Mutation verdicts: the brief gives counts only (phone 9/10 red, watch 8/10 red after a tests-only fix; the non-red ones stated equivalent or fixed), not per-mutation RED AT lines, so no individual guard is confirmed killed by name this run — taken as the governor's established facts, not re-verified.
