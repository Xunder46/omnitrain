# Evidence — plan 47c (the phone says how the watch is doing)

## Tests behind the docs (read this run)

- `test/watch_link_state_test.dart` — groups `S-6901 the phase follows what the watch reports`,
  `S-6902 the labels`, `S-6903 a heard frame`, `S-6904 initialize`,
  `S-6905 link changes and refresh`.
- `test/settings_watch_status_test.dart` — S-6910 (no section without a link state), S-6911 (the
  row per phase and last-synced line), S-6912 (the row offers no tap target), S-6913 (APPLE WATCH
  sits after WORKOUT and before HEALTH), S-6914 (a heard frame updates the line while Settings is
  open).

## Symbols grepped this run

- `lib/state/watch/watch_link_state.dart`: `WatchLinkState` (`ChangeNotifier`),
  `enum WatchLinkPhase { notPaired, appNotInstalled, notReachable, connected }`, `statusLabel`,
  `lastSyncedLabel`, `lastHeardKey = 'watch_last_heard_ms'`, `persistEvery`.
- `lib/core/platform/watch_link_source.dart`: `WatchLinkSource` (`linkInfo()`, `linkChanges`,
  `heard`); `WatchConnectivityTransport` declares `implements WatchTransport, WatchLinkSource`.
- `lib/state/watch/watch_sync_wiring.dart`: `createWatchSync` builds a `WatchLinkState` when the
  resolved transport is a `WatchLinkSource`, `initialize()`s it, and returns it as
  `WatchSyncGraph.link` (nullable).
- DI hops: `lib/main.dart` (`watchLinkState: watchSync?.link`) → `MyApp` (`lib/app.dart`) →
  `HomeScreen` (`lib/features/home/home_screen.dart`) → `SettingsScreen`
  (`lib/features/settings/settings_screen.dart`), all nullable `watchLinkState` parameters.
- `settings_screen.dart`: `OmniCardHeader(title: 'APPLE WATCH')` + `_WatchSection` (a
  `StatefulWidget` whose `initState` calls `refresh()`, a `ListenableBuilder` over the state) with
  one `_SettingsRow(label: 'Apple Watch', onTap: null)`.

## Owner checks (from the plan; not run here)

- Settings shows APPLE WATCH with the real status on a device; walk away from the phone with the
  watch app open → Not reachable, come back → Connected; the last-synced time moves after a workout
  syncs. So far seen in simulator screenshots only.

## Docs

- `docs/theme_and_settings.md`: the APPLE WATCH paragraph in the Settings Screen section, and the
  section-grouping sentence now includes the watch's link status.
- `docs/state_management/watch_surface.md`: the `WatchLinkState` paragraph in the new phone-link
  subsection.
