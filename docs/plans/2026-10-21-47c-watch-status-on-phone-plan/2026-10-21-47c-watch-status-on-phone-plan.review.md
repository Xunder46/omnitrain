# Review: 2026-10-21-47c-watch-status-on-phone-plan · P1–P3 · 9ba191e..working tree
Verdict: APPROVE WITH FIXES
Counts: blocker 0 · major 1 · minor 1 · tests: governor-run (state and settings tests green; mutation 17/17 red across the series; paired-simulator run done — plugin activates, reachability false→true, watch frames received, sendMessage replies acknowledged; watch-to-phone transferUserInfo delivery is an owner device check)
Diff vs Predicted Files: conforms — the working-tree diff against the series base also carries 47a/47b files; every 47c scope file is present and nothing else was touched by 47c.

## Findings
1. [Major] lib/state/watch/watch_sync_wiring.dart:337 — `await link?.initialize();` is awaited but a thrown error propagates: if `getPreferenceString('watch_last_heard_ms')` fails (repository/DB error), `createWatchSync` throws, the whole watch graph is lost, and startup fails — for a read-only status readout. This contradicts the wiring's own rule (main.dart:366-369: a wrist that is not there is not a reason to refuse to start) and the brief's question 3 expectation. Fix: wrap the `initialize()` call in a try/catch that leaves `link` in place (or swallow the preference read inside `initialize` the way `refresh` swallows `linkInfo`). Guard: a test where the repository's `getPreferenceString` throws and `createWatchSync` still returns a graph with a `link` whose `lastHeard` is null.
2. [Minor] lib/state/watch/watch_link_state.dart:135-139 — the persist write in `_onHeard` is `unawaited` with no error handling: a failing `setPreferenceString` surfaces as an unhandled async exception (zone handler / Sentry, and a red test). Fix: catch and drop the write error (the throttle already prevents a retry storm). Guard: a test where `setPreferenceString` throws and the state keeps notifying on later heard events.

## Assumption Log rulings
The plan and evidence carry no Assumption Log; the Decision Ledger (D-1..D-6) is the decision record and every entry is implemented as written (D-1 interface + `implements` line verified at watch_transport.dart:136; D-2 constructor/keys/throttle as specified; D-3 three nullable hops verified; D-4 shared pieces, no hex colours, no new button; D-5 wording matches code exactly; D-6 nothing out of scope was built). Nothing to ratify, revert or escalate.

## Scenario coverage
- S-6901 → test/watch_link_state_test.dart · five tests (notPaired, appNotInstalled out of reach, notReachable, connected, before-the-first-answer notReachable) | covered
- S-6902 → test/watch_link_state_test.dart · status label per phase; boundary table 59s/60s/59min/60min/23h/24h/6d; 7d date form `Last synced 12 Oct`; future instant → just now; null → Never synced | covered
- S-6903 → test/watch_link_state_test.dart · first heard persists once, second inside persistEvery notifies without writing, one after writes again (write counts + read-back) | covered
- S-6904 → test/watch_link_state_test.dart · stored value read back; garbage string → null | covered
- S-6905 → test/watch_link_state_test.dart · linkChanges updates phase and notifies; refresh re-reads; throwing linkInfo keeps the phase | covered
- S-6910 → test/settings_watch_status_test.dart · no APPLE WATCH header or row without a state | covered
- S-6911 → test/settings_watch_status_test.dart · four phase tests with status label and last-synced line | covered
- S-6912 → test/settings_watch_status_test.dart · no InkWell and no GestureDetector under the section | covered
- S-6913 → test/settings_watch_status_test.dart · WORKOUT < APPLE WATCH < HEALTH by position | covered
- S-6914 → test/settings_watch_status_test.dart · heard event flips `Never synced` → `Last synced just now` while open | covered

## Answers to the brief's questions
1. No exception path found: `_onInfo`/`_onHeard` both check `_disposed` before `notifyListeners`; `dispose` during a pending `refresh` is safe (the late `_onInfo` returns); subscriptions are attached before the awaited `refresh()`, so a heard event during initialize is handled; the first heard event persists (`_lastPersistedAt` null → write) and the throttle (`now - last < persistEvery` skips) is correct. The one gap is the unhandled write error (finding 2) and the initialize read error (finding 1).
2. `lastSyncedLabel` boundaries are all correct (verified against the plan table and the tests): negative age (now earlier than heard) falls into the `< 1 min` branch → `just now`; no branch can produce a negative or wrong unit; the date form uses `heard.toLocal()`, so a UTC-near-midnight heard time shows the local day/month, which is the intended `12 Oct` form.
3. `link` is created only when `resolved is WatchLinkSource` (watch_sync_wiring.dart:331-337); `initialize()` is awaited, but a thrown error blocks startup (finding 1); the three hops pass the same object: main.dart:442 `watchSync?.link` → MyApp field → HomeScreen field → SettingsScreen field, all nullable.
4. The row follows the standards: `OmniSurface`/`OmniCardHeader`/`_SettingsRow`, no hex colours (`theme.colorScheme.primary`, `OmniTheme.colors.textSecondary`), text sizes from the theme (`bodySmall`), no new button, `onTap` null → no InkWell (settings_screen.dart `_SettingsRow` returns bare content when `onTap == null`); hidden when `watchLinkState` is null; `_WatchSectionState` owns nothing and needs no dispose (the `WatchLinkState` lives for the app's lifetime like the rest of the graph, which is also never disposed — consistent with mirror/inbox). `ListenableBuilder` exists: pubspec requires Dart SDK ^3.10.7 (Flutter well past 3.10, where `ListenableBuilder` landed).
5. Docs check: every name in the new `theme_and_settings.md` text exists (the four status labels `Connected`/`Not reachable`/`Not paired`/`Watch app not installed`, `Never synced`, `Apple Watch`, `APPLE WATCH` match the code strings exactly; `test/settings_watch_status_test.dart` exists and S-6910..S-6914 match its test names). No false claims found.

## Disposition (governor, 2026-10-21)

- Major 1 (initialize failure lost the watch graph): fixed; `createWatchSync` reports the failure and returns the graph with `link: null`; test added.
- Minor 2 (unhandled persist write error): fixed (`catchError`); S-6907 added; mutation red.
