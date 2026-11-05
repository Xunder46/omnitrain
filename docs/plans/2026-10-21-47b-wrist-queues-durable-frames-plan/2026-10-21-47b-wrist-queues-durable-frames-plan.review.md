# Review: 2026-10-21-47b-wrist-queues-durable-frames-plan · P1–P3 · series base..working tree
Verdict: APPROVE
Counts: blocker 0 · major 0 · minor 0 · tests: governor-run Swift 683/0, watch target builds with xcodebuild, mutation pass 17/17 red (not re-run per brief)
Diff vs Predicted Files: conforms for 47b's six files. The wider diff carries the 47a/47c series work (lib/**, packages/omnitrain_watch_link/**, test/*.dart, watch_surface.md, theme_and_settings.md, Podfile.lock, pubspec) and one permissions flag (`.github/copilot/permissions/crew-builder-watch.flags` adds `write(packages/**)`, a 47a need) — outside 47b's predicted files, attributable to the series, not findings here.

## Findings

None.

## Brief questions

1. **`WatchConnectivityBridge.send` trace** (`WatchConnectivityBridge.swift:145-170`): frame-check throw → report, return (pre-existing). `session.send` succeeds → done, never queued (S-6705 asserts `queued` empty). Send throws + non-durable → report, return. Send throws + durable → `session.queue`; queue throws → report the queue's error (S-6704 asserts the reported error *is* the queue's); queue succeeds → queued, not reported. A durable frame is exactly one of sent / queued / reported; never both sent and queued, never silently lost. The one "both" appearance — `sendMessage` accepted synchronously, then refused by its async error handler, which queues — is D-3's designed recovery, and the row stays owed (no receipt) so the next sync re-sends under the same id.
2. **App target `send` error handler + `queue`** (`OmniTrainWatchConnectivity.swift:93-117`): the sync path queues only via the bridge after a guard throw; the async handler queues only after `sendMessage` was actually called and failed — mutually exclusive per attempt. Across attempts the owed frame carries the deterministic id `"msg-\(recordId)"` (`WatchSessionEngine.swift:1927`), so the `outstandingUserInfoTransfers` dedupe stops pile-up while the transfer is outstanding. Residual window (transfer delivered, receipt not yet processed → re-queue possible) is covered by the phone's entry-level idempotency (Q3) and ends once `confirmedAt != nil` drops the row from `pendingObservations()` (`WatchSessionEngine.swift:1433`). `activationState != .activated` in `queue` throws `RadioError.notActivated`, which is reported — via `onFailure` on the bridge path, via `onSendFailure` in the async handler. Not silently dropped; consistent with D-2/D-3.
3. **Phone-side idempotency**: `watch_session_inbox.dart:9` — "staged in the repository as it arrives (`WatchInboxEntry`, put-if-absent by `entryId`)"; `:39-41` — `unchanged`: "Everything it carried was already staged: a redelivery… acknowledged again". A frame delivered twice (queued transfer + `sendMessage` re-send) stages each entry once and re-acknowledges. Wrist side: `WatchSessionEngine.swift:1433` `.filter { $0.confirmedAt == nil }` — once the receipt lands the row is no longer re-sent. Idempotent.
4. **`didReceiveUserInfo` default `= [:]`** (`OmniTrainWatchConnectivity.swift:185`): the signature matches the `WCSessionDelegate` optional requirement; the default only affects direct Swift calls that omit the argument, while WCSession delivers the real dictionary through the Obj-C selector into `deliver(userInfo)` — the same handler path as `didReceiveMessage` (`:183`). Satisfies the requirement; delivered identically. The default value is never used by delegate delivery; no behavioural effect, so not a finding.
5. **Docs names** (`watch_surface_wrist.md` new paragraph): all exist — `WatchConnectivitySession` (`WatchConnectivityBridge.swift:31`), `queue` (`:43`), `WatchConnectivityBridge.isDurable` (`:163`) true exactly for `observations_up`/`session_lifecycle` (`:165-166`), `OmniTrainWatchConnectivity`, `transferUserInfo` (`:117`), `messageId` dedupe (`:113-116`), `didReceiveUserInfo` (`:185`), `WatchBridgeQueueTests.swift` and `WatchQueueSourceTests.swift` (new files), `WatchConnectivityBridgeTests.testBridgeSendsNothingUntilAsked` (`:764`), `testASendThePlatformRefusesIsReported` (`:624` — sends a request frame via `requestSnapshot()`, so the doc's "(a refused request frame, the live-only case)" is accurate). The "owner check on real devices" sentence matches the paired-simulator limitation in the brief.

## Assumption Log rulings

The plan carries no Assumption Log; nothing to rule on.

## Scenario coverage

- S-6701 → `WatchBridgeQueueTests.testS6701ARefusedObservationIsQueued`
- S-6702 → `WatchBridgeQueueTests.testS6702ARefusedSessionEndIsQueued`
- S-6703 → `testS6703ARefusedTimerStateIsReportedAndDropped` / `…SessionSnapshot…` / `…Request…` (one test each, as planned)
- S-6704 → `WatchBridgeQueueTests.testS6704AQueueRefusalIsReportedOnce`
- S-6705 → `WatchBridgeQueueTests.testS6705ADurableFrameThatSendsIsNotAlsoQueued`
- S-6706 → `WatchBridgeQueueTests.testS6706OnlyObservationsAndTheEndAreDurable`
- S-6707 → `WatchBridgeQueueTests.testS6707AnUnreachableCatchUpQueuesBothLoggedSets` (asserts the fake's non-dedupe: 4 queued frames across two syncs)
- S-6708 → five `WatchQueueSourceTests` guards (one `transferUserInfo(` call, dedupe, delegate callback, package-owned durable rule)
- Rewritten per the Readers note: `WatchConnectivityBridgeTests.testS206ARefusedFrameIsReportedOnceAndTheRowStaysOwed` (`:641`, both refusals set, queue asserted empty, row stays owed); `testASendThePlatformRefusesIsReported` (`:624`) needed no rewrite — already the live-only request case.

No scenario without a test that would fail without the change; the governor's 17/17 mutation pass corroborates.

## Disposition (governor, 2026-10-21)

No findings.
