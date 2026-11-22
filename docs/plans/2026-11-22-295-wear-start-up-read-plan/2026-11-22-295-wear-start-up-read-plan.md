# Plan 295 — A frame queued while the app was closed is read at start-up (plan 280 open item 11, the part that needs no account)

Item 11 of plan 280 says "a background data-layer listener so a frame reaches a wrist whose app is not running". Reading the plugin shows the real gap is smaller and sits on both devices: a data item raises a change event only to a listener that is attached when it arrives, and `OmniTrainWatchLinkPlugin.kt` attaches its listener when the Flutter engine starts and never reads the items already waiting. So a frame the peer queued while this app was closed (a workout the watch queued apart from the phone, then the phone app opened later; a routines frame the phone queued for a closed wrist) sits in the data layer unread, for ever, because only a change event takes it. This plan reads what is waiting each time the plugin attaches. The background service the item names is not built, on purpose: it would still have to start the Dart app to store anything, which is what launching the app already does once this read exists, and every frame the protocol owes is idempotent and re-offered at the next sync. The Play listing (one listing for the two APKs) is the owner's account and is not code. Kotlin plugin only; no Dart, wire, schema, phone-UI or Swift change. Base commit: `.work/2026-11-22-295-wear-start-up-read/base.txt`. Analyze baseline: 174 issues, 0 errors.

## Goal and acceptance

Start either Android app (watch or phone) while the peer has frames waiting for it in the data layer: each waiting frame arrives in Dart exactly as a frame that arrived while the app was running does (the `userInfo` event), and is then deleted so it is not read twice. Frames this device queued itself, and data items that are not queued frames, are left alone. A frame that arrives at the very moment of start-up may be delivered twice (once by the read, once by the change event); the protocol is idempotent, so that costs a redelivery, never data.

Acceptance: S-29501..S-29504 green and each guard red without the change; S-29505 was to be observed on the Wear emulator (a seeded waiting item is received at launch, and without the read it is not) — NOT observed, see the evidence file; `flutter analyze` at most 174 issues, 0 errors; the Wear debug APK builds; Docs delta applied.

## Feature invariants

- One rule for taking a frame: the change event and the start-up read call the same function, so they cannot disagree about which items are taken.
- A frame is emitted first and deleted after (as today), so a crash between the two costs a redelivery.
- Events still buffer (cap 500) until Dart listens, so a frame read before the Dart listener attaches is not lost.
- The read never throws: a failed listing reads nothing.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-29501 | The body of `onDataChanged`'s per-item work moves unchanged into `takeQueuedItem(item: DataItem)` (path prefix `QUEUE_PREFIX`, readable `DataMap`, role is not this device's, frame decodes, emit `userInfo`, then delete). `onDataChanged` calls it for each `TYPE_CHANGED` event. | `OmniTrainWatchLinkPlugin.kt` 441-460 |
| D-29502 | New `drainWaiting()`: lists `dataClient.dataItems`, calls `takeQueuedItem` for each, always releases the buffer, reads nothing when the task failed. Called once from `onAttachedToEngine`, right after `attachListeners()`. | same file 126-149; Wear docs: a data listener sees only changes after it is registered |
| D-29503 | No dedupe against a concurrent change event: a snapshot's `messageId` does not change with its content (plan 69 D-5), so deduping by id could drop newer content; the protocol already ignores an older or equal snapshot and re-applies idempotent frames. | plan 294 D-29403 |
| D-29504 | Not built: a `WearableListenerService`. It would need a headless Dart engine to store anything; the read at launch plus the sync's re-offer covers every frame the protocol owes. Recorded, not hidden: the wrist does not update while its app is closed, it updates at the next open. | plan 280 item 11 |
| D-29505 | Not in scope: the Play listing (the owner's account); live sensors (item 9); sending diagnostics to the phone. | plan 280 |

## Input-reality checklist

1. **Writers.** The peer writes items; this device deletes what it takes. Two writers to one item: the read and the change event, harmless twice (D-29503).
2. **Units.** None.
3. **Lifecycle.** Cold start (the read finds items queued while closed); hot restart or a second engine (the plugin attaches again: it reads again, finds nothing, since taken items were deleted); the Dart side not listening yet (events buffer, cap 500, then oldest drop: a peer that queued more than 500 waiting frames loses the oldest from the buffer, but they stay in the data layer only until deleted here; with the sync's re-offer nothing owed is lost).
4. **Settings changing while open.** None.
5. **Time.** None.
6. **Load.** One listing per attach; the queue holds a handful of items; the buffer is released after the loop.
7. **Wording.** None.
8. **Slot competition.** None.

Readers: Dart transports already handle `userInfo` events at any time (`WearWatchTransport._onEvent`, `WatchConnectivityChannel`); the Wear shell binds its handler in `initState` before `transport.start()` listens (`wear_app.dart` 169, 226), so a frame flushed at the first listen has a handler.

## Scenarios

Guard (`test/watch_link_start_up_read_test.dart`, new; plain `test()`, reads the Kotlin source with CRLF normalised):

| S-n | fixture | expect | fails without |
|---|---|---|---|
| S-29501 | `onAttachedToEngine` body | calls `drainWaiting()` after `attachListeners()` and before `resolvePeer()` | the start-up read is not run |
| S-29502 | `drainWaiting` body | reads `dataClient`'s `dataItems`, returns when the task failed, calls `takeQueuedItem(item)` per item, and releases the buffer in a `finally` | the read is missing, throws on a failed listing, or leaks the buffer |
| S-29503 | `onDataChanged` body | calls `takeQueuedItem(event.dataItem)` for `TYPE_CHANGED` and no longer holds the role, path or delete logic itself | the two paths can disagree |
| S-29504 | `takeQueuedItem` body | checks `QUEUE_PREFIX`, skips an item whose role is `ownRole()`, decodes the frame, emits `userInfo` and only then calls `deleteDataItems` | an own item is taken, or an item is deleted before it is emitted |

Emulator (lead, observed, S-29505): with a temporary debug hook that makes the app put one peer-role data item at its first launch, then a force-stop and a relaunch: the Diagnostics screen shows `frame_received probe_down` after the relaunch with the read, none without it (the same build with the `drainWaiting()` call removed), and a third launch shows none (the item was deleted). The hook is reverted by inverse replacement and compared with the base.

Guard families the lead proves by mutation: the call site and its position, the failed-listing return, the buffer release, the shared function, the role skip, the path-prefix skip, the emit-before-delete order.

## Phases

Every builder brief opens with "Never run the full `flutter test`" and "do not run any command through the gateway; write the report FIRST as a skeleton, then fill it and stop".

1. **P1 — the read** (`crew-builder-watch`; scope `packages/omnitrain_watch_link/android/src/main/kotlin/dev/sasha/omnitrain/watch_link/OmniTrainWatchLinkPlugin.kt`, `packages/omnitrain_watch_link/README.md`). Exact code in the brief. About 40 lines.
2. **P2 — tests** (lead): the guard file.
3. **P3 — docs** (lead), then **Lead:** analyze, the Wear APK, the mutation pass, the emulator proof, plan-lint.

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| docs/wear_os_app.md | ADDED | - | A frame queued while the app was closed is read when the app starts | S-29501 |
| docs/wear_os_app.md | ADDED | - | `test/watch_link_start_up_read_test.dart` | S-29504 |

Stale-term sweep: `grep -rIn "background data-layer listener\|background listener" docs` outside plans/history/releases finds nothing in `docs/wear_os_app.md`; plan 280's open-item row is a plan record (updated in this plan's Progress).

## Assumption Log

- The Wear data layer's `getDataItems` lists items from every node for this app, including ones the peer wrote, and a change event is raised only for a listener registered when the change happens (platform behaviour; the emulator proof S-29505 observes the first half on a single node with a seeded peer-role item).
- The Wear data layer syncs items between paired nodes while the receiving app is not running (the system, not the app, carries them); not testable without a pair: owner check 15.
- `DataItemBuffer.release()` is required after use; `DataItem`s read inside the loop are valid until then and the plugin copies what it needs (the decoded frame map, the `Uri`) before releasing.

## Progress

- [x] P1 the read (crew builder, 1.4 min)
- [x] P2 tests (lead; S-29501..S-29504, source guards)
- [x] P3 docs (`docs/wear_os_app.md`: the platform paragraph, the tests list, owner check 15)
- [x] Verify: analyze 174 / 0 errors; Wear debug APK builds; 13 of 13 source-guard mutants killed (evidence file)
- [ ] S-29505 NOT observed: the emulator crashes (host segfault, exit 139) when the app writes a data item, which the probe needs (evidence file)
- [ ] (owner) check 15 in `docs/wear_os_app.md` on a paired watch and phone
