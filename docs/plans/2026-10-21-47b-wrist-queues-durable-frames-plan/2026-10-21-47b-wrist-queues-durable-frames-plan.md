# Feature: 47b — the watch hands durable frames to the OS queue when the phone is out of reach

> Status: BUILT, PROVED AND REVIEWED 2026-10-21 (review APPROVE, no findings). Swift 683/0; the watch target builds; on the paired simulators the watch called transferUserInfo for an owed set when the phone was off. Delivery of that transfer to the phone is an owner device check. Base: `.work/2026-10-21-47b/base.txt`. Series: `docs/plans/2026-10-21-47-watch-sync-reliability-series.md` (D-2). Scout sheet: `.work/crew/2026-10-21-47/scout-wrist.md`.
> Binding conventions: docs/global_conventions.md; .github/copilot/pr-scope-budget.md

## Goal and acceptance

| Situation on the watch | Now | After 47b |
|---|---|---|
| You log sets and end the workout while the phone is out of reach | the frames are dropped; they are re-sent only when the watch app is awake near the phone | the set and end-of-session frames are handed to the OS queue; the OS delivers them when the devices meet, even if the watch app is asleep |
| The wrist's sync re-sends the same owed set several times while out of reach | n/a (dropped) | queued once (a transfer with the same `messageId` is not queued again) |
| A timer, a snapshot or a request cannot be sent | reported and dropped | unchanged (live-only: it would arrive stale) |
| The phone's receipt for a queued frame arrives as a queued transfer | not received | received like a message (the wrist stops owing the set) |

## Decision Ledger

- D-1 `WatchConnectivitySession` (`WatchConnectivityBridge.swift:~27`) gains `func queue(_ frame: [String: Any]) throws` ("hands the phone one frame the OS will deliver later; throws when the platform refuses it").
- D-2 `WatchConnectivityBridge.isDurable(_ frame: [String: Any]) -> Bool` (public static): true exactly when `frame["type"]` is `"observations_up"` or `"session_lifecycle"`. `WatchConnectivityBridge.send`: when `session.send(frame)` throws and the frame is durable, call `session.queue(frame)` instead of reporting the send error; a throwing `queue` is reported through `onFailure`; a non-durable frame keeps today's report-and-drop; a send that succeeds is never also queued.
- D-3 App target `OmniTrainWatchConnectivity` (`ios/OmniTrain Watch App/OmniTrainWatchConnectivity.swift`): `queue(_:)` = `transferUserInfo` after the same `isSupported`/`activated` guards as `send`, skipped when `WCSession.default.outstandingUserInfoTransfers` already holds a transfer whose `userInfo["messageId"]` equals the frame's; the `sendMessage` error handler of `send` queues a durable frame instead of only reporting; new delegate method `session(_:didReceiveUserInfo:)` calls `deliver` like `didReceiveMessage`.
- D-4 Out of scope: the phone half (47a), receipts, any status UI (O-3), the engine, the protocol.

## Readers listed

- Implementers of `WatchConnectivitySession`: `OmniTrainWatchConnectivity` (app target) and `FakeWatchConnectivitySession` (`watch/watchos/Tests/WatchSessionEngineTests/FakeWatchConnectivitySession.swift`); grep found no other.
- Tests that must stay green: `WatchConnectivityBridgeTests` (`testASendThePlatformRefusesIsReported` ~:624, `testS206ARefusedFrameIsReportedOnceAndTheRowStaysOwed` ~:641: these set `sendError` and send an `observations_up`; they will now see a queued frame and no report, so they are REWRITTEN for the live-only case or assert the queue, listed in the phase).

## Scenarios (ids S-6701.. checked free)

`FakeWatchConnectivitySession` gains `private(set) var queued: [[String: Any]]`, `var queueError: Error?`, and `func queue` (throws `queueError`, else appends). New file `WatchBridgeQueueTests.swift` using the harness of `WatchConnectivityBridgeTests` (`WatchBridgeHarness`, `isPhoneReachable: false`):
- S-6701 an `observations_up` frame with `sendError` set: `queued` holds it (same `messageId`), `sent` is empty, no failure reported.
- S-6702 a `session_lifecycle` frame, same.
- S-6703 live-only arms, one test each: `timer_state`, `session_snapshot` and a request frame (`WatchTransportRequest.snapshotFrame()`) with `sendError` set: reported once, `queued` empty.
- S-6704 `queueError` set: an `observations_up` is reported once (the queue's error), nothing in `queued`.
- S-6705 a durable frame that sends fine is in `sent` and NOT in `queued`.
- S-6706 `isDurable` is true for exactly those two types and false for `timer_state`, `session_snapshot`, `receipt`, a request frame (no `type`) and an empty frame.
- S-6707 orchestrated: an engine with two logged sets, the phone unreachable, `orchestrator.sync()` called twice: `queued` holds frames for both sets' `messageId`s (the fake does not dedupe; the app target does); the existing refused-frame tests are rewritten per the Readers note.
- S-6708 source scan (helper style `WatchSensorSourceSourceTests.swift:44-75`): `OmniTrainWatchConnectivity.swift` contains `transferUserInfo(`, `outstandingUserInfoTransfers`, `didReceiveUserInfo` and `isDurable(`.
Mutation list for the lead: durable test inverted, `isDurable` including `timer_state`, queue called after a successful send, dedupe removed (S-6708 text), queue error swallowed.

## Phases

| Phase | Agent | Items | Write scope |
|---|---|---|---|
| P1 package: protocol member, `isDurable`, bridge rule, fake, tests S-6701..S-6707 | crew-builder-watch | 6 | `WatchConnectivityBridge.swift`, `watch/watchos/Tests/**` (one run; no parallel builder) |
| P2 app target + S-6708 | crew-builder-watch | 3 | `ios/OmniTrain Watch App/OmniTrainWatchConnectivity.swift`, `WatchQueueSourceTests.swift` |
| P3 docs | crew-docs-keeper | 2 | `docs/**` |
Builders: never run the full `flutter test`; Done lists include `swift-test --filter WatchSessionEngineTests` (append-only guard: no new names starting with set/update/delete/remove/replace/edit/overwrite/write/clear/purge/wipe/reset/drop/truncate/erase/forget/modify/mutate/destroy) and the full `swift-test`. The governor builds the watch target with xcodebuild.

## Owner checks (owner)

- (owner) Real watch + phone: leave the phone at home, log a set and end the workout on the watch, come home; the workout appears on the phone without opening the watch app (needs 47a).
