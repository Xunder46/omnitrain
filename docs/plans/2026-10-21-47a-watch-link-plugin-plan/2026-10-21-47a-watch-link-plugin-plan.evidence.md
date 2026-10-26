# Evidence — plan 47a (the phone's watch link plugin)

## Tests behind the docs (read this run)

- `test/watch_link_package_test.dart` — groups `S-6801 status`, `S-6802 sendMessage`,
  `S-6803 transferUserInfo`, `S-6804 events`, `S-6805 one broadcast stream`.
- `test/watch_transport_test.dart` — group `S-6810-6815 the transport over a link that queues`
  (S-6810..S-6815) and group `S-6817 the transport attaches its listeners when it starts receiving`.
- `test/watch_connectivity_channel_test.dart` — group `S-6816 the channel over the plugin`.

## Symbols grepped this run

- `packages/omnitrain_watch_link/` — `lib/watch_link.dart` (`WatchLink`: `status()`,
  `sendMessage` with a `timeout` parameter, `transferUserInfo`, `events`),
  `lib/watch_link_event.dart` (`WatchLinkStatus`, sealed `WatchLinkEvent` with
  `WatchLinkMessage`/`WatchLinkUserInfo`/`WatchLinkReachability`/`WatchLinkStateChanged`),
  `ios/Classes/OmniTrainWatchLinkPlugin.swift` (`bufferCap`, pending-event buffer trimmed past it).
- `pubspec.yaml`: path dependency `omnitrain_watch_link: path: packages/omnitrain_watch_link`
  (the `watch_connectivity` dependency is gone).
- `lib/core/platform/watch_connectivity_channel.dart`: `WatchConnectivityChannel` implements the
  seven `WatchMessageChannel` members (`isPaired`, `isReachable`, `messages`, `send`, `queue`,
  `reachability`, `info`); the only `lib/` import of the package.
- `lib/core/platform/watch_link_info.dart`: `WatchLinkInfo`.
- `lib/core/platform/watch_delivery.dart`: `enum WatchDelivery { delivered, queued, undelivered }`.
- `lib/core/platform/watch_transport.dart`: `WatchConnectivityTransport` — `isDurable`
  (`receipt`), `linkChanges`, `linkInfo()`, `heard`, `implements WatchTransport, WatchLinkSource`.

## Governor verification (reported by the governor, not re-verified here)

- Paired simulators (iPhone 17 Pro + Apple Watch Series 11 42mm): the plugin activates, reports
  `reachability false` then `true` when the watch app starts, receives the watch's requests and
  frames (`routines`, `snapshot`, `observations_up`, `session_snapshot`), and its replies are
  acknowledged (`sendMessage` with reply handler: `kNoErr`); with the phone off, the watch calls
  `transferUserInfo` for the owed set.
- NOT verified (simulator limit: watch-to-phone `transferUserInfo` never reached the phone's
  delegate there): the OS delivering a queued transfer to the closed phone app — an owner check on
  real devices. Also unverified: the Settings row on a device, and the buffer-cap behaviour.

## Docs

- `docs/state_management/watch_surface.md`: new subsection "The phone's link: the plugin, the
  channel, the queue and the status"; the package-boundary sentence now names
  `omnitrain_watch_link` (it named the removed `watch_connectivity` dependency).

## Governor re-runs (final)

- Full `flutter test` +5375 ~2 all passed; `flutter analyze` 180 issues (the unchanged baseline); Swift 683/0. Mutation pass: 19 of 19 mutants red across the series (Swift bridge/source arms Q1-Q6, transport T1-T6, state L1-L4, Settings row L5, review fixes F1-F2). Paired simulators (iPhone 17 Pro + Watch 42mm): plugin activation, `reachability false` then `true`, watch frames (`routines`, `snapshot`, `observations_up`, `session_snapshot`) received, the phone's replies acknowledged; watch-to-phone `transferUserInfo` could not be delivered by the simulator (owner device check).
- An unrelated flaky test (`watch_session_auto_push_test` S-144, a real-clock race) fails about one run in three alone; recorded in `.work/friction.md`.
