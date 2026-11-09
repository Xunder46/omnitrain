# Evidence — plan 47b (the wrist queues durable frames)

## Tests behind the docs (read this run)

- `watch/watchos/Tests/WatchSessionEngineTests/WatchBridgeQueueTests.swift` —
  S-6701 (a refused `observations_up` is queued), S-6702 (a refused `session_lifecycle`), S-6703
  (live-only frames reported and dropped, one test each), S-6704 (a refusing queue is reported
  once), S-6705 (a durable frame that sends is never also queued), S-6706 (`isDurable` is exactly
  the two types), S-6707 (an unreachable catch-up queues both logged sets).
- `watch/watchos/Tests/WatchSessionEngineTests/WatchQueueSourceTests.swift` — S-6708 source scan
  (`transferUserInfo(`, `outstandingUserInfoTransfers`, `didReceiveUserInfo`, `isDurable(`).
- `WatchConnectivityBridgeTests.testASendThePlatformRefusesIsReported` still asserts the live-only
  case (a refused snapshot *request* is reported once), so the citation in
  `watch_surface_wrist.md` stays true.

## Symbols grepped this run

- `watch/watchos/Sources/WatchSessionEngine/WatchConnectivityBridge.swift`:
  `protocol WatchConnectivitySession` gained `func queue(_ frame: [String: Any]) throws`;
  `WatchConnectivityBridge.isDurable` is true exactly for `observations_up` and `session_lifecycle`.
- `ios/OmniTrain Watch App/OmniTrainWatchConnectivity.swift`: `queue(_:)` over `transferUserInfo`
  with the `outstandingUserInfoTransfers` dedupe, and `session(_:didReceiveUserInfo:)`.

## Owner checks (from the plan; not run here)

- Real watch + phone: log a set and end the workout with the phone at home; the workout appears on
  the phone without opening the watch app (needs 47a). The paired simulators cannot show a queued
  transfer reaching the phone's delegate.

## Docs

- `docs/state_management/watch_surface_wrist.md`: the "nothing is queued on the wrist" paragraph
  rewritten — durable frames queue when the radio refuses, live-only frames keep report-and-drop.
