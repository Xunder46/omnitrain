# omnitrain_watch_link

The phone's own link to the Apple Watch, iOS only: a thin Dart wrapper over a
local iOS plugin that wraps `WCSession` (WatchConnectivity). It replaces the
`watch_connectivity` package, which only passed `applicationContext` and
dropped whatever arrived while no Dart listener was attached.

Two channels:

- `MethodChannel('omnitrain/watch_link/methods')` for calls:
  - `status` returns a map `{supported, paired, appInstalled, activated, reachable}`
    (booleans) → `WatchLink.status()`.
  - `sendMessage(frame)` is answered (null) only when the watch replies; a
    radio failure arrives as a `PlatformException` with code `not_supported`,
    `not_activated`, `not_reachable` or `send_failed`, and no answer within the
    timeout becomes `timeout` → `WatchLink.sendMessage`.
  - `transferUserInfo(frame)` answers `queued`, or `already_queued` when a
    transfer carrying the same `messageId` is still outstanding →
    `WatchLink.transferUserInfo`.
- `EventChannel('omnitrain/watch_link/events')`, one broadcast stream whose
  payloads all carry a `kind`: `message` and `userInfo` (with a `frame` map),
  `reachability` (with a bool), `state` (the status map). The native side
  buffers while no Dart listener is attached (cap 500) and flushes in order on
  the first `listen`; `WatchLink.events` decodes these to the sealed
  `WatchLinkEvent` types and skips unknown kinds.

Every `PlatformException` surfaces as `WatchLinkException` carrying the native
code. iOS only: no Android implementation exists.
