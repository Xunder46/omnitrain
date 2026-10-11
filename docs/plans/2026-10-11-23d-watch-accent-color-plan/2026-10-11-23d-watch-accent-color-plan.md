# Plan 23d: the watch wears the phone's theme accent

Base: HEAD 7b27577 (after 23c). Governor-seeded. Owner decision 2026-10-11: accent color only; the watch keeps its black
background. Template: plan 22 (the rest ping setting travelled the same way, `preferences_down.restPingSeconds`).

## Goal and acceptance (what the owner sees)
After a Sync, the watch's main buttons (Start / Log, Next, the confirmation's default action, selected rows) use the accent
of the theme chosen on the phone (6 themes); the text on those buttons is dark or light, whichever reads. Before the first Sync,
or when the phone sends no accent, the watch looks as it does today. Changing the theme on the phone shows on the watch at its next
Sync (the same rule as every other setting). Nothing else changes color; black stays black.

## Decision ledger
- D-3701 Wire: `preferences_down.payload` gains OPTIONAL `accentColorHex` (string, pattern `^#[0-9A-Fa-f]{6}$`), closed object otherwise
  (`watch/sync_protocol/schemas/messages/preferences_down.schema.json`, `required` unchanged). Additive, no version bump. We send the color, not a theme
  name: a seventh theme needs no watch update.
- D-3702 Phone sender: `WatchReferenceSync.buildPreferencesDown` (`lib/core/utils/watch_reference_sync.dart:~340`) gets `accentColorHex`
  (nullable) from `OmniTheme.colorsForTheme(settings.appTheme).primary` (`lib/core/constants/omni_theme.dart:236`), formatted `#RRGGBB` upper-case
  without alpha; the message id includes it (so a theme change is a different message, not a dropped duplicate: same rule as the other fields).
  The caller is `WatchSyncRequestHandler._sendRoutines` (`lib/state/watch/watch_sync_request_handler.dart:~74`): `_settings.appTheme`.
- D-3703 Wrist store: `WatchPreferencesRecord` (`watch/watchos/Sources/WatchSessionEngine/WatchPhonePreferences.swift:~26`) gains
  `accentColorHex: String?`; `toJson`, `init(json:)` (~line 90) and the apply path (~157-172: it reads each field with a helper, an invalid or
  absent value is nil) carry it; `WatchPhonePreferences` (~130) exposes `accentColorHex: String? { current?.accentColorHex }`. Dart twin
  (`lib/watch/session/watch_records.dart` preferences record and the apply path in `lib/watch/`) mirrors the field so shared fixtures round-trip.
- D-3704 Rendering rule, a pure package type `WatchAccent` (new file in `watch/watchos/Sources/WatchSessionEngine/`, no SwiftUI import): parses
  `#RRGGBB`, `relativeLuminance` (WCAG), `contrastAgainstBlack`, `labelIsDark` (true when black text has the higher contrast on the accent),
  and `isUsable` (accent contrast vs black >= 3.0; an unusable accent is ignored: the watch keeps its default). The SwiftUI side
  (`ContentView.swift`) applies `.tint(Color(...))` at the root and sets the label color of prominent buttons from `labelIsDark`.
- D-3705 Shared table `watch/contract/watch_accent_contract.json`: the six themes `{theme, hex, labelIsDark}` with the thresholds; read by BOTH
  the Swift suite (`WatchAccent` over each row) and a Dart test that asserts each row equals `OmniTheme.colorsForTheme(<theme>).primary`
  (so a changed theme color fails the Dart test until the table, and with it the watch's expectation, is updated). Measured today
  (contrast vs black, governor): abyssalNeon 2DE2E6 13.13; forgeEmber FF7B45 8.17; obsidianVolt E8B420 10.98; voidPulse A478FF 6.71;
  crimsonDojo FF4C47 6.38; malachiteCore 24B85A 8.08: on all six black text has the higher contrast (white would read 1.6 to 3.3), so `labelIsDark` is true for all six today; the table records the computed value, the code never hard-codes a theme.
- D-3706 No new screen, button or setting on either device. The Wear/Dart client stores the field and does not render it.

## Scenarios (tests first)
Contract: S-3701 valid fixture `preferences_down_accent.json` (all three fields) conforms on both stacks; S-3702 invalid `preferences_down_accent_bad.json`
(`"accentColorHex": "teal"`) rejected as the pattern's code; S-3703 `preferences_down.json` WITHOUT the field still conforms (unchanged fixture).
Wrist (Swift): S-3710 `WatchAccent` over every row of the shared table: parse ok, `isUsable`, `labelIsDark` equals the table; S-3711 `#GGGGGG`, `2DE2E6`
(no hash), `#FFF` -> nil; S-3712 a near-black accent `#101010` is not usable; S-3713 a preferences row with the field restores from the store with it, a row
without restores with nil, a newer row replaces an older one, an older late row does not (same rule as the other fields); S-3714 a `preferences_down` with a bad
hex is refused by the validator and keeps the previous accent.
Phone (Dart): S-3720 `buildPreferencesDown` for each `AppTheme` carries the table's hex and conforms; S-3721 two messages differing only in accent have different
message ids; S-3722 the shared table equals `OmniTheme.colorsForTheme` for the six themes (S-3705); S-3723 `WatchSyncRequestHandler` sends the hex of the CURRENT
theme (change the theme in the fake settings between two syncs).

## Phases
| # | Agent | Scope | Items |
|---|---|---|---|
| D1 | crew-builder-watch | `watch/sync_protocol/**`, `watch/contract/**`, `watch/watchos/**`, `lib/watch/**`, `test/sync_protocol_fixtures_test.dart`, `test/watch_session_start_test.dart`, `docs/**` | D-3701, D-3703, D-3704, D-3705 (table + Swift tests), Dart twin field, fixtures, PROTOCOL row |
| D2 | crew-builder-app | `lib/core/utils/watch_reference_sync.dart`, `lib/state/watch/watch_sync_request_handler.dart`, `test/watch_reference_sync_test.dart`, `test/watch_accent_contract_test.dart` (new) | D-3702, S-3720..S-3723 |
| D3 | crew-builder-watch | `ios/OmniTrain Watch App/ContentView.swift`, `watch/watchos/Sources/**` views, `docs/**` | D-3704 SwiftUI side, docs, QA steps (owner) |
D1 then D2 and D3 (disjoint, parallel).

## Verification (governor)
swift test, flutter test, analyze 196, xcodebuild; mutations: ignore the field on restore; skip the usable check; drop it from the message id; label always white. (owner) pick each of
the 6 themes on the phone, Sync, look at Start/Log and Next on the watch: readable text on every accent.
