# Feature: 47c — the phone says how the watch is doing

> Status: BUILT, PROVED AND REVIEWED 2026-10-21 (review APPROVE WITH FIXES, both fixed: a failing status read no longer loses the watch graph, a failing persist write is swallowed). Settings row verified by widget tests; not looked at on a device screen (the Mac was locked): owner check. Base: `.work/2026-10-21-47c/base.txt`. Series: `docs/plans/2026-10-21-47-watch-sync-reliability-series.md` (O-2, D-4). Needs 47a (`WatchConnectivityTransport.linkChanges`, `linkInfo()`, `heard`). Scout sheet: `.work/crew/2026-10-21-47/scout-status.md`.
> Binding conventions: docs/global_conventions.md; docs/design_system.md ("Shared pieces and rules per job"); docs/documentation_standard.md; .github/copilot/pr-scope-budget.md

## Goal and acceptance

Settings gets a section APPLE WATCH (between WORKOUT and HEALTH), shown only on a build with watch support, with one read-only row:

| Row part | Shows |
|---|---|
| Label | `Apple Watch` |
| Right side (coloured status) | `Connected` (theme primary colour) when the watch is reachable; `Not reachable` (secondary) when paired with the app installed but out of reach; `Not paired` (secondary) when no watch is paired; `Watch app not installed` (secondary) when a watch is paired without the app |
| Line under the label | `Last synced just now` (under a minute), `Last synced 5 min ago`, `Last synced 3 h ago`, `Last synced 2 d ago`, `Last synced 12 Oct` (a week or more), or `Never synced` |
"Last synced" is the moment the phone last heard a frame from the watch (any frame the app took); it survives a restart. The row updates while the screen is open (reachability changes) and re-reads the pairing when Settings opens. The row is not tappable.

## Decision Ledger

- D-1 `WatchLinkSource` (new `lib/core/platform/watch_link_source.dart`): `abstract interface class WatchLinkSource { Future<WatchLinkInfo> linkInfo(); Stream<WatchLinkInfo> get linkChanges; Stream<DateTime> get heard; }`; `WatchConnectivityTransport` declares `implements WatchTransport, WatchLinkSource`-compatible members (it already has all three after 47a: add `implements WatchLinkSource` to the class; no behaviour change).
- D-2 `WatchLinkState` (new `lib/state/watch/watch_link_state.dart`, `ChangeNotifier`): constructor `WatchLinkState({required WatchLinkSource source, required WorkoutRepository repository, DateTime Function()? clock, Duration persistEvery = const Duration(seconds: 30)})`; `Future<void> initialize()` reads `watch_last_heard_ms` (`repository.getPreferenceString`) and the initial `linkInfo()` and starts listening to `linkChanges` and `heard`; `WatchLinkPhase get phase` (`notPaired`, `appNotInstalled`, `notReachable`, `connected`, from the last `WatchLinkInfo`: not paired -> notPaired; paired but no app -> appNotInstalled; reachable -> connected; else notReachable; before the first answer: notReachable); `DateTime? get lastHeard`; `String get statusLabel`; `String lastSyncedLabel(DateTime now)` (the table above; `Never synced` when null; a future timestamp reads `just now`); `Future<void> refresh()` re-reads `linkInfo()` (errors swallowed, state kept); a `heard` event sets `lastHeard` and notifies at once but persists (`setPreferenceString('watch_last_heard_ms', ms.toString())`) only when `persistEvery` has passed since the last write; `dispose` cancels both subscriptions. Persistence goes through `WorkoutRepository` only.
- D-3 DI: `createWatchSync` (`lib/state/watch/watch_sync_wiring.dart`) builds a `WatchLinkState` when the resolved transport is a `WatchLinkSource` (and `initialize()`s it) and puts it on `WatchSyncGraph.link` (nullable field). `main.dart` hands `watchSync?.link` to `MyApp(watchLinkState:)` -> `HomeScreen(watchLinkState:)` -> `SettingsScreen(watchLinkState:)` (nullable constructor parameters, three hops; `home_screen.dart` builds `SettingsScreen` at ~:1177).
- D-4 UI: in `settings_screen.dart` a private `_WatchSection` (a `StatefulWidget`: `initState` calls `watchLinkState.refresh()`; a `ListenableBuilder` over the state) inside an `OmniSurface` like the other sections, built only when `widget.watchLinkState != null`, under `OmniCardHeader(title: 'APPLE WATCH')` between the WORKOUT and HEALTH sections. One `_SettingsRow(label: 'Apple Watch', subtitle: state.lastSyncedLabel(now), trailing: Text(state.statusLabel, style: bodySmall, color: connected ? theme.colorScheme.primary : OmniTheme.colors.textSecondary), onTap: null)` (the first read-only row; the notification row at ~:352 shows the colouring pattern). No new shared widget, no hex colours, no new button.
- D-5 Wording is the lead's choice (owner delegated it): the four status labels and the `Last synced ...` strings above are the contract; docs name them.
- D-6 Out of scope: a retry or "sync now" button, Home or session-screen indicators, Android, the wrist (O-3).

## Readers listed (grep 2026-10-21)

- `SettingsScreen(` constructions: `lib/features/home/home_screen.dart:~1177` and tests (`test/settings_*_test.dart`: grep); the new parameter is optional so existing tests keep compiling.
- `MyApp(` constructions: `lib/main.dart` and tests (grep `MyApp(`); `HomeScreen(`: `lib/app.dart` and tests.
- `WatchSyncGraph` constructors/readers: `watch_sync_wiring.dart` and tests (`test/watch_*_test.dart` that build the graph: grep `WatchSyncGraph(`).
- Section order is pinned by the Settings test in `test/header_standardization_test.dart` (check before editing).

## Scenarios (ids S-6901.. checked free)

`test/watch_link_state_test.dart` (plain `test()`, fake `WatchLinkSource` with controllers, `MockWorkoutRepository`, injected clock):
- S-6901 phase per `WatchLinkInfo`: notPaired, appNotInstalled, notReachable, connected (four tests; a paired watch with no app is `appNotInstalled` even when reachable is false).
- S-6902 labels: `statusLabel` per phase; `lastSyncedLabel` boundaries: null -> `Never synced`; 59 s -> `just now`; 60 s -> `1 min ago`; 59 min -> `59 min ago`; 60 min -> `1 h ago`; 23 h -> `23 h ago`; 24 h -> `1 d ago`; 6 d -> `6 d ago`; 7 d -> the date (`12 Oct` form: day + three-letter month, English); a future instant -> `just now`.
- S-6903 a `heard` event sets `lastHeard`, notifies, and persists once; a second event within `persistEvery` notifies but does not write; one after it writes again (count `setPreferenceString` calls through a recording repository wrapper or the mock's read-back).
- S-6904 `initialize()` reads the stored value (`lastHeard` equals it) and a garbage stored string reads as null.
- S-6905 `linkChanges` events update the phase and notify; `refresh()` re-reads; a throwing `linkInfo()` keeps the previous phase.
`test/settings_watch_status_test.dart` (widget tests, Mock-first, pump with a fake state; one `await tester.pump()` per frame, no real delays): S-6910 with `watchLinkState: null` the section header `APPLE WATCH` is absent; S-6911 with a state in each phase the row shows `Apple Watch`, the status label and the `Last synced ...` line; S-6912 the row is not tappable (no `InkWell` under it); S-6913 the section sits between WORKOUT and HEALTH (header order); S-6914 a `heard` event updates the line while the screen is open.
Mutation list for the lead: phase mapping arms, each label boundary, persist throttle, `initialize` garbage handling, section placement, `onTap` set.

## Phases

| Phase | Agent | Items | Write scope |
|---|---|---|---|
| P1 source interface + state + tests S-6901..S-6905 | crew-builder-app | 5 | `lib/core/platform/watch_link_source.dart`, `lib/core/platform/watch_transport.dart` (one line), `lib/state/watch/watch_link_state.dart`, `test/watch_link_state_test.dart` |
| P2 DI (wiring, main, app, home) + Settings section + S-6910..S-6914 | crew-builder-app | 6 | `lib/state/watch/watch_sync_wiring.dart`, `lib/main.dart`, `lib/app.dart`, `lib/features/home/home_screen.dart`, `lib/features/settings/settings_screen.dart`, `test/settings_watch_status_test.dart`, constructors' tests |
| P3 docs | crew-docs-keeper | 3 | `docs/**` |
Builders: never run the full `flutter test`; UI units follow `docs/design_system.md`; the lead looks at Settings on the iPhone simulator (needs the Mac unlocked for screenshots through simctl: they work headless).

## Owner checks (owner)

- (owner) Settings shows APPLE WATCH with the real status; walk away from the phone with the watch app open and see Not reachable, come back and see Connected; the "Last synced" time moves after a workout syncs.
