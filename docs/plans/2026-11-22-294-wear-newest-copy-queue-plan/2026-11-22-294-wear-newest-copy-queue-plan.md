# Plan 294 — Only the newest copy of a workout waits in the Wear wrist's queue (plan 280 open item 10)

When the phone is out of reach, the Apple wrist hands the OS one copy of each workout's live state and withdraws the copy it replaces (plan 69 D-2..D-8: "only the newest copy waits"). The Wear wrist queues the same frames (`WearWatchTransport.isDurable`) but never withdraws anything, so a workout done apart from the phone leaves one queued snapshot per change and one queued lifecycle per exercise move: 41 snapshots for 40 added exercises. The phone ignores an older snapshot (plan 63 D-1) and treats a repeated lifecycle as a no-op, so nothing is wrong when they arrive; the cost is a queue that grows with every change and a burst of stale frames the phone must read when the devices meet. This plan ports the rule. **Finding while seeding:** the rule is Dart, in the transport (`wear_watch_transport.dart` line 19 records it as a follow-up); the Kotlin plugin already lists and cancels queued items. Kotlin needs one small extension, because the rule needs each queued copy's lifecycle `state` and `sentAt`, which the plugin does not return today. No wire, schema, phone or Swift change. Base commit: `.work/2026-11-22-294-wear-newest-copy-queue/base.txt`. Analyze baseline: 174 issues, 0 errors.

## Goal and acceptance

On a Wear watch that cannot reach the phone, a workout leaves at most: one queued `session_snapshot` per session, one queued non-terminal `session_lifecycle` per session, every logged observation, and every terminal lifecycle. A newer copy of a snapshot replaces the older one; a lifecycle replaces the older non-terminal lifecycles; a terminal lifecycle (`completed`, `abandoned`) also replaces the snapshot and the non-terminal lifecycles of its session and is never stale. A copy stamped later than the frame being queued wins: the frame is not queued. When a durable frame goes out live, the older copies still waiting for it are withdrawn. A wrist whose queue cannot be listed or cancelled still queues. The user sees nothing different on the wrist; the phone receives fewer, newer frames.

Acceptance: S-29401..S-29415 green and each guard red without the change; `flutter analyze` at most 174 issues, 0 errors; `flutter build apk --flavor wear -t lib/watch/wear_main.dart` compiles the Kotlin; Docs delta applied.

## Feature invariants

- An `observations_up` is never withdrawn and never replaces anything. A `timer_state` and a request are never queued and never trigger a list.
- Nothing is written to the wrist's store by queuing: a queued copy is a carrier, not a delivery (plan 69 D-1). The orchestrator's bookkeeping is untouched.
- The rule never throws to the caller: a list or cancel that fails is reported through `onFailure` and the queue call still runs.
- Wire unchanged: the frames are built exactly as before; the plugin's channel answer gains two optional keys that an older reader ignores.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-29401 | The rule is the Apple bridge's, unchanged: W for a snapshot = the session's queued snapshots; for a non-terminal lifecycle = the session's non-terminal lifecycles; for a terminal lifecycle = both, and it is never stale; an `observations_up` has no W. Never in W: an observation, a terminal lifecycle, another session's frame, a copy with no string `messageId` or `type`. | `WatchConnectivityBridge.swift` `superseded(by:in:)` 339-372; plan 69 D-3 |
| D-29402 | Newest wins by the frame's top-level `sentAt`: a copy joins W when its `sentAt` is earlier than or equal to the frame's. If a copy that would be in W is LATER, the frame is stale: on the queue path it is not queued and nothing is withdrawn (not a failure); on the live path it is still sent and the later copy stays. An unreadable `sentAt` counts as oldest on a copy and as newest on the frame. | plan 69 D-4; `sentAt(of:missing:)` 381 |
| D-29403 | A non-snapshot whose own `messageId` already waits is not queued again; a snapshot with its own id waiting is in W like any other (its id does not change with its content). | plan 69 D-5; `queueNewest` 303-307 |
| D-29404 | When it runs: (a) before queuing a durable frame the radio refused, (b) after a snapshot or lifecycle went out live (W withdrawn, nothing queued). List, withdraw and queue are one step on one lane, so two hand-overs at once cannot both keep a copy. | plan 69 D-6, D-7 |
| D-29405 | Failures: a list or cancel that throws a `WatchLinkException` is reported once and treated as "nothing to withdraw"; the queue call still runs. A queue refusal is reported as today, after W was withdrawn (the next trigger re-sends). | plan 69 D-8; today's `send` 207-214 |
| D-29406 | Plugin: `WatchLinkTransfer` gains optional `state` (the frame's `payload.state`) and `sentAt` (its top-level `sentAt`), read from the channel's `state` and `sentAt` keys when they are strings, else null; equality and hash include them. The iOS half does not send them (the phone's link is not this transport) and the Dart read tolerates their absence. | `watch_link.dart` 20-50, 105-130 |
| D-29407 | Kotlin: `outstandingTransfers` decodes each item's stored frame bytes (`KEY_FRAME`, already stored whole) and adds `state` and `sentAt` to the entry when the frame has them. No change to what is stored, so a copy queued by an older build is read the same way. | `OmniTrainWatchLinkPlugin.kt` 362-387 (`decodeFrame` 521) |
| D-29408 | Not in scope: `structure_change` and `exercise_push` (the Wear wrist sends neither); the app-layer buffer or a timer (D-9: the OS queue is the only queue); the Swift plugin; sending the diagnostics log. | plan 69 D-9 |

## Input-reality checklist

1. **Writers.** The transport's `send` is the only writer to the queue; the Kotlin side deletes an item when the peer takes it (so the list can shrink between listing and cancelling: a cancel that finds nothing answers a smaller count, never an error). The orchestrator re-offers frames at each trigger; a re-offer of a waiting observation is deduped by its `messageId` (the plugin answers `already_queued`).
2. **Units.** `sentAt` is a UTC ISO string; compared as instants.
3. **Lifecycle.** Cold start with copies left by the previous run: the list reads the OS queue, so they are matched with no memory (S-29413 reads them from the fake). Reachability flips mid-run: `send` reads reachability through the radio's own refusal.
4. **Settings changing while open.** None.
5. **Time.** Equal stamps: the older-or-equal copy is withdrawn (S-29403). A clock moved back on the wrist makes a new frame older than a waiting copy: the frame is then not queued, and the next sync (a later stamp) replaces both; the phone is unaffected. Recorded in the Assumption Log.
6. **Load.** One list and at most one cancel per durable send; the queue holds a handful of items for one workout; the list decodes each frame once.
7. **Wording.** No user-visible text.
8. **Slot competition.** None.

Concurrent paths: `WearWatchTransport.send` can be reached by the orchestrator, the engine's hand-overs and the shell at once (Dart's single isolate interleaves at each `await`). The lane in D-29404 serialises the list-withdraw-queue step; S-29412 interleaves two sends.

Readers of the plugin's transfer value: `grep -rn "WatchLinkTransfer\|outstandingTransfers" lib test packages` finds `watch_link_package_test.dart` (constructs and compares transfers) and `lib/core/platform/watch_connectivity_channel.dart` (maps the package's transfer to `WatchQueuedTransfer`, which is unchanged); the older tests that pin the transport's queue behaviour are `test/wear_watch_transport_test.dart` S-28012/S-28013 (unchanged: a durable frame refused still queues exactly once, with the default mock returning `null` for `outstandingTransfers`), and `test/wear_diagnostics_transport_test.dart` S-29311 (queued outcome line, unchanged).

## Scenarios

Fixture frame helper: `snap(session, id, sentAt)` = `{type: 'session_snapshot', messageId: id, sessionId: session, sentAt: <ISO>, payload: {status: 'active'}}`; `lc(session, state, id, sentAt)` = `{type: 'session_lifecycle', ..., payload: {state: state}}`; `obs(session, id)` = `{type: 'observations_up', ...}`. The mock channel keeps a mutable list of outstanding transfers (cancel removes ids) and records every call in order. The radio refuses by answering `not_reachable` to `sendMessage`.

Transport (`test/wear_queue_newest_test.dart`, new; the channel mocks of `wear_watch_transport_test.dart`; plain `test()`):

| S-n | fixture | expect | fails without |
|---|---|---|---|
| S-29401 | queue `[snap(s-1,mA,t1), snap(s-2,mB,t1), obs(s-1,mO), lc(s-1,started,mL,t0), {foo: 1}, {messageId: x}]`, radio refuses; send snap(s-1,mC,t2) | cancels exactly `[mA]`; queue ends `[mB, mO, mL, {foo}, {x}, mC]`; no failure reported | no replacement: mA stays |
| S-29402 | queue `[snap(s-1,mA,t1)]`; send snap(s-1,mA,t2) (same id, newer) | cancels `[mA]` then one `transferUserInfo` of mA with `t2` (cancel is called before queue) | a same-id copy is left, and the plugin answers `already_queued` so the new content is lost |
| S-29403 | queue `[snap(s-1,mN,t3)]`; A: send snap(s-1,mO,t2); B: send snap(s-1,mE,t3) | A: no cancel, no queue call, queue `[mN]`, no failure; B: cancels `[mN]`, queue `[mE]` | stale frame replaces a newer one, or an equal stamp does not replace |
| S-29404 | queue `[lc(s-1,started,mS,t0), snap(s-1,mP,t1), obs(s-1,mO1), lc(s-1,exercise_advanced,mA,t2), lc(s-2,started,mS2,t0), lc(s-3,abandoned,mX,t1)]`; A: send lc(s-1,completed,mC,t3); B: send the same frame again; C: send lc(s-3,started,mY,t2) | A: cancels exactly `{mS, mP, mA}`; queue `[mO1, mS2, mX, mC]`; B: no cancel, one `mC` still; C: mX stays, mY queued | a terminal leaves live state waiting; an observation or another session is withdrawn; a terminal copy is withdrawn |
| S-29405 | queue `[lc(s-1,started,mS,t0), snap(s-1,mP,t1), lc(s-1,completed,mZ,t1)]`; send lc(s-1,exercise_advanced,mA,t2) | cancels exactly `[mS]`; the snapshot and the terminal lifecycle stay; mA queued | a non-terminal lifecycle withdraws a snapshot or a terminal copy |
| S-29406 | queue `[obs(s-1,mO1)]`; send obs(s-1,mO2), snap(s-1,mP,t1), lc(s-1,completed,mC,t2); then a `timer_state` frame; then a routines request | mO1 and mO2 are never in a cancel; the snapshot is cancelled by the terminal; the timer and the request are each reported once and never queued; the timer and the request make no list call | an observation is withdrawn, or a non-durable frame queues or lists |
| S-29407 | 40 snapshots handed over in order, each stamped one second later, radio refusing (the 40-exercise overflow) | after each, exactly one queued snapshot; 39 cancels in total; the survivor is the last | the queue grows with every change |
| S-29408 | radio accepts; queue `[snap(s-1,mA,t1), lc(s-1,started,mS,t0), obs(s-1,mO)]`; A: send snap(s-1,mB,t2); B: send lc(s-1,completed,mC,t3); C: queue reset to `[snap(s-1,mN,t5)]`, send snap(s-1,mOld,t4) | A: `sendMessage` called, cancels `[mA]`, nothing queued; B: cancels `[mS]`, queue `[mO]`; C: `sendMessage` called, no cancel, mN stays | a live send leaves older waiting copies, or withdraws a newer one |
| S-29409 | queue `[snap(s-1,mOld)]` where the copy has no `sentAt`; and a frame with no `sentAt` sent against `[snap(s-1,mLate,t9)]` | the copy with no stamp is withdrawn by any frame (oldest); the frame with no stamp withdraws the later copy (newest) and is queued | an unreadable stamp is treated as newest on a copy or oldest on the frame |
| S-29410 | `outstandingTransfers` answers a PlatformException `send_failed`; send snap(s-1,mB,t2) | one failure reported; no cancel; mB queued | a list failure stops the queue |
| S-29411 | `cancelTransfers` throws; and the queue call throws | cancel throws: one failure reported, mB queued; queue throws: one failure reported (the queue's error), the older copy was cancelled, mB not queued | a cancel failure stops the queue; a queue failure is lost |
| S-29412 | the first `outstandingTransfers` call waits on a gate; start `send(snap(s-1,m1,t1))` and `send(snap(s-1,m2,t2))` together; release | only one list call is in flight while the first waits; afterwards exactly one s-1 snapshot is queued, m2 | two sends both list the same empty queue and both queue |
| S-29413 | queue pre-seeded with `[snap(s-watch-1,mOld,t0)]` before the transport is built (a previous run); a new transport; send snap(s-watch-1,mNew,t1) | cancels `[mOld]`; one queued snapshot | copies of an earlier run are not matched |

Plugin (`test/watch_link_package_test.dart`, extended):

| S-n | fixture | expect | fails without |
|---|---|---|---|
| S-29414 | the channel answers `[{messageId: a, type: session_lifecycle, sessionId: s, state: completed, sentAt: 2026-11-22T10:00:00Z}, {messageId: b, type: observations_up}, {messageId: c, state: 7, sentAt: 8}]` | transfer a carries `state` completed and `sentAt` the string; b has both null; c (non-string values) has both null; equality distinguishes a transfer with a different `state` or `sentAt` | the two fields are not read |

Kotlin: a source guard in `test/wear_queue_newest_test.dart` (S-29415): the plugin source's `outstandingTransfers` function decodes the stored frame (`decodeFrame(`), puts `"sentAt"` and `"state"` into the entry, and the stored data map is unchanged (`dataMapFor` writes the same five keys). The lead compiles it with `flutter build apk --flavor wear -t lib/watch/wear_main.dart`. Device behaviour (the data layer's delete-then-put at the same path) is an owner check.

Guard families the lead proves by mutation: each arm of the replacement table (snapshot-snapshot, lifecycle-snapshot only when terminal, lifecycle-lifecycle only when the copy is non-terminal), the stale rule and its equal-stamp edge, the unreadable-stamp sides, the own-id dedupe for non-snapshots, the live-path withdraw, the lane, the failure handling, the plugin's two reads.

## Phases

Every builder brief opens with "Never run the full `flutter test`" and "do not run any command through the gateway; write the report FIRST as a skeleton, then fill it and stop".

1. **P1 — plugin descriptor** (`crew-builder-watch`; scope `packages/omnitrain_watch_link/lib/watch_link.dart`, `packages/omnitrain_watch_link/android/src/main/kotlin/dev/sasha/omnitrain/watch_link/OmniTrainWatchLinkPlugin.kt`, `packages/omnitrain_watch_link/README.md`). Exact code in the brief. About 35 lines.
2. **P2 — the rule in the transport** (`crew-builder-watch`; scope `lib/watch/app/wear_watch_transport.dart`). Exact code in the brief; serial after P1 (it reads the new fields). About 130 lines.
3. **P3 — tests** (lead): `test/wear_queue_newest_test.dart` (new), `test/watch_link_package_test.dart` (extended).
4. **P4 — docs** (lead or keeper), then **Lead:** analyze, readers, the wear APK build, mutation pass, plan-lint.

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| docs/wear_os_app.md | MODIFIED | Its durability table is the same one the Swift | newest-copy rule are the same ones the Swift | S-29401 |
| docs/wear_os_app.md | ADDED | - | A queued frame is read back with its lifecycle state and its sentAt | S-29414 |
| docs/wear_os_app.md | ADDED | - | `test/wear_queue_newest_test.dart` | S-29401 |

The transport's header comment (lines 19-21) says the rule is "not here yet": P2 rewrites it. Stale-term sweep: `grep -rIn "not here yet\|newest-copy" docs` outside plans/history/releases hits only `wear_os_app.md` (the row above) and Apple-side pages that describe the Swift bridge (true, unchanged). The `(owner)` check 14 below is added to `docs/wear_os_app.md` "Checks on a watch" as a numbered item (ADDED; New marker `14. (owner) on a Wear watch with the phone out of reach`).

14. (owner) on a Wear watch with the phone's Bluetooth off: do a workout (add three exercises, log sets), end it, turn Bluetooth on; the phone shows the workout once, complete, with every logged set; the watch's Diagnostics lines (plan 293) show one `frame_sent session_snapshot queued` per change but the phone's history has one workout, not several.

## Assumption Log

- The Kotlin data layer deletes a data item before `putDataItem` at the same path is accepted again: `cancelTransfers` waits for each `deleteDataItems` task to complete, then the transport queues, and `transferUserInfo` lists again. Not provable without a watch: owner check 14.
- The wrist's frames carry a top-level `sentAt` (PROTOCOL.md line 58, required) and a lifecycle frame's `payload.state` (Swift `isTerminal`).
- `outstandingTransfers` returns only this device's own items (`role` filter, plugin line 374).
- Dart's single isolate means the lane needs no lock, only chaining: `_inQueueLane` runs each step after the previous one finished, including one that threw.
- A wrist clock moved back leaves a newer-stamped copy that blocks the frame; the next sync's later stamp repairs it. Accepted (the phone's own stale-snapshot rule makes the same trade).

## Progress

- [x] P1 plugin descriptor (crew builder, 1.3 min)
- [x] P2 the rule in the transport (crew builder, 1.7 min)
- [x] P3 tests (lead; S-29401..S-29415, 21 new transport tests and 2 package tests)
- [x] P4 docs (`docs/wear_os_app.md`: platform paragraph, transport paragraph, tests list, owner check 14)
- [x] Verify and prove: analyze 174 / 0 errors; Wear debug APK builds (Kotlin compiles); mutation pass 28 of 30 killed, 2 equivalent (evidence file)
- [ ] (owner) check 14 in `docs/wear_os_app.md` on a watch
