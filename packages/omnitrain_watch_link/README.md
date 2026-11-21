# omnitrain_watch_link

The phone's own link to the wrist, one package over two platforms: a thin Dart
wrapper over a local plugin that wraps `WCSession` (WatchConnectivity) on iOS and
the Wear OS data layer (`MessageClient` / `DataClient` / `CapabilityClient`) on
Android. On iOS it replaces the `watch_connectivity` package, which only passed
`applicationContext` and dropped whatever arrived while no Dart listener was
attached. On Android it is what the Wear OS shell and the phone app talk to,
because Google's APIs have no such plug-in and the Wear counterpart of each
`WCSession` concept is a different call.

The same Flutter project builds both apps, so the Android half runs on both
devices. It decides which role it is playing from the device's own feature set
(`FEATURE_WATCH`) and discovers the *peer* by the other side's capability, so
nothing in it assumes it is the phone.

Two channels:

- `MethodChannel('omnitrain/watch_link/methods')` for calls:
  - `status` returns a map `{supported, paired, appInstalled, activated, reachable}`
    (booleans) → `WatchLink.status()`. On Android a peer that declares our
    capability counts as paired (the install declares it) and one that is also
    in range counts as reachable.
  - `sendMessage(frame)` completes when the peer confirms the frame (iOS) or when
    the message was accepted (Android). A radio failure arrives as a
    `PlatformException` with code `not_supported`, `not_activated`,
    `not_reachable` or `send_failed`, and no answer within the timeout becomes
    `timeout` → `WatchLink.sendMessage`.
  - `transferUserInfo(frame)` answers `queued`, or `already_queued` when a
    transfer carrying the same `messageId` is still outstanding →
    `WatchLink.transferUserInfo`. On Android each queued frame is one data item
    under its own `messageId`, which the data layer carries when the devices next
    meet.
  - `outstandingTransfers` returns a list of
    `{messageId, type, sessionId?, changeId?}` read from each outstanding
    transfer's frame → `WatchLink.outstandingTransfers`.
  - `cancelTransfers({messageIds})` cancels those transfers and answers how
    many → `WatchLink.cancelTransfers`.
- `EventChannel('omnitrain/watch_link/events')`, one broadcast stream whose
  payloads all carry a `kind`: `message` and `userInfo` (with a `frame` map),
  `reachability` (with a bool), `state` (the status map). The native side
  buffers while no Dart listener is attached (cap 500) and flushes in order on
  the first `listen`; `WatchLink.events` decodes these to the sealed
  `WatchLinkEvent` types and skips unknown kinds.

On Android the data layer replaces watchOS's OS queue, with one rule that
differs: a queued data item is deleted by whichever side takes it, so
`outstandingTransfers` shrinks as the peer receives frames rather than only when
the sender withdraws them.

Every `PlatformException` surfaces as `WatchLinkException` carrying the native
code.
