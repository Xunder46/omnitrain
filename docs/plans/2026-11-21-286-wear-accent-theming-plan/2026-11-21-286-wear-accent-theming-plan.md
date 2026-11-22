# Plan 286 — The Wear wrist wears the phone's accent colour (series 286, plan 280 open item 8)

Closes plan 280's open item 8 for the Wear wrist. Wrist only, `lib/watch/`. No wire, phone, schema or Swift change (the preferences copy already carries `accentColorHex` and plan 283a stores it). Base commit: `.work/2026-11-21-286-wear-accent-theming/base.txt`. Analyze baseline: 174 issues, 0 errors.

## Goal and acceptance

What a user sees on a Wear watch, matching the Apple wrist: the watch's buttons, its selected number in the rating question and its progress ring wear the colour of the phone's theme (orange for Forge Ember, purple for Void Pulse, and so on) once a sync has brought it. Before the first sync, or when the phone's copy carries no colour, or a colour too dark to read on a black screen (contrast against black under 3.0), the watch wears the phone's default theme colour, cyan `#2DE2E6`; today it wears Material's default lilac. The text on a coloured button is black where black reads better than white on that colour and white otherwise (every one of the six phone themes takes black). A colour that arrives while the watch is open shows on the next repaint without restarting the app; a colour change survives an app restart.

Acceptance: S-28601..S-28617 green and each guard red without the change; `flutter analyze` at most 174 issues, 0 errors; `test/wear_app_test.dart`, `test/wear_phone_settings_test.dart`, `test/wear_menu_screen_test.dart`, `test/wear_effort_rating_screen_test.dart`, `test/watch_accent_contract_test.dart`, `test/ui_standards_contract_test.dart`, `test/docs_indexing_contract_test.dart` green; no new red in the full suite; Docs delta applied.

## Feature invariants

- The accent decision lives in one Dart class (`WatchAccent`), a port of Apple `WatchAccent.swift`: no screen decides a colour or a label.
- The six accents are the contract table's `watch/contract/watch_accent_contract.json`; the tests walk that file, they do not restate the hexes.
- Only `ColorScheme.primary` and `onPrimary` change; every other colour of the dark Material theme stays as it is today (destructive red, surfaces, tonal buttons).
- A shell built without a preferences object wears the default cyan and nothing else changes.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-28601 | New `WatchAccent` (`lib/watch/widgets/watch_accent.dart`), immutable, channels as `int`s 0..255. `WatchAccent.tryParse(String hex)` accepts exactly `#RRGGBB` (regex `^#[0-9A-Fa-f]{6}$`), else null. `relativeLuminance` is WCAG 2.x (linearise each channel/255 with the 0.03928 / 12.92 / 2.4 rule, weights 0.2126, 0.7152, 0.0722); `contrastAgainstBlack = (L+0.05)/0.05`; `contrastAgainstWhite = 1.05/(L+0.05)`; `labelIsDark = black >= white`; `isUsable = contrastAgainstBlack >= minContrastAgainstBlack` (const 3.0). `static WatchAccent? usable(String? hex)`; `static const String fallbackHex = '#2DE2E6'`; `static WatchAccent worn(String? hex)` is `usable(hex)` or the fallback. `Color get color` (opaque) and `Color get labelColor` (`Colors.black` / `Colors.white`). | Swift `WatchAccent.swift` (the whole file); `watch/contract/watch_accent_contract.json` |
| D-28602 | `WearAppState` builds its `MaterialApp` theme from `WatchAccent.worn(widget.preferences?.accentColorHex)`: `ThemeData(useMaterial3: true, brightness: Brightness.dark)` whose `colorScheme` is copied with `primary: accent.color, onPrimary: accent.labelColor`. The theme is cached by the hex string it was built from (`_themeHex`, `_theme`): the shell rebuilds every second while a session runs, and a new `ThemeData` per tick would re-theme the tree each second. `preferences` null reads as no accent. | `wear_app.dart` `build` (261-268), `_onFrame` (setState after every frame), `_boot` (restore then setState) |
| D-28603 | No new listener: a copy only arrives through `_onFrame` (which already calls `setState`) or `catchUp`, and the restore at launch is followed by `setState` in `_boot`. | `wear_app.dart` `_onFrame`, `_boot` |
| D-28604 | The default look changes on purpose: the fallback accent replaces Material's lilac before any sync (Apple plan 56 D-1: a surface handed no accent wears the phone's default theme colour). Existing Wear tests that assert a colour are listed in the scenarios' readers note. | Swift `WatchAccentStyle.swift` `WatchAccentKey.defaultValue` |
| D-28605 | Not in scope: the desktop harness gets no accent picker (it wears cyan, like a fresh watch); no Kotlin or complication colour; the Apple-only prominent-button modifier has no Dart twin because Flutter reads `primary` everywhere. | - |

## Input-reality checklist

1. **Writers.** The accent string is written only by `WatchPhonePreferences.applyPreferencesDown` (plan 283a). The theme only reads `preferences.accentColorHex`.
2. **Lifecycle.** First launch with no copy: cyan (S-28610). Copy arrives while open: next repaint (S-28611). App killed and relaunched: the restore in `_boot` brings the copy back before the first ready frame (S-28616). A later copy without an accent: cyan again (S-28612), as units reset in plan 283a.
3. **Settings changing while open.** Covered by S-28611/S-28612; a session running meanwhile is the 1 s ticker case (S-28617).
4. **Time.** None.
5. **Load.** One hex compare per build; the theme object is rebuilt only when the hex changes (S-28617).
6. **Words.** No text. The doc sentence "the accent colour still shows nothing" is stale after this plan (Docs delta).
7. **Competition.** The destructive buttons keep `colorScheme.error` (menu Discard); the tonal buttons keep their container colours; both unchanged.

Readers of the default look: `grep -rn "colorScheme.primary\|Colors.deepPurple\|0xFFD0BCFF" test lib/watch` found no Wear test asserting the old lilac (only phone tests); the builder re-runs the five Wear shell test files named in the acceptance.

## Scenarios

`test/watch_accent_test.dart` (new, plain `test()`), fixtures derived with a throwaway script that mirrors the formula:

| S-n | fixture | expect | fails without |
|---|---|---|---|
| S-28601 | every row of the contract's `themes`; `minContrastAgainstBlack` | `tryParse(hex)` not null, `isUsable` true, `labelIsDark` equals the row's, `WatchAccent.minContrastAgainstBlack` equals the file's 3.0; the contrast against black of the six rows is 13.13, 8.17, 10.98, 6.71, 6.38, 8.08 (each within 0.01) | the class is absent, or a luminance weight or the linearisation is wrong |
| S-28602 | `#2DE2E6`, `#2de2e6`; refused: `2DE2E6`, `#2DE2E`, `#2DE2E6F`, `#2DE2E6FF`, `#GGGGGG`, ` #2DE2E6`, `#2DE2E6 `, empty, `#` | the two valid read channels 45, 226, 230 (lower case the same); every refused string gives null | the parser is looser (short form, alpha, trim) or stricter |
| S-28603 | `#5A5A5A` (contrast against black 3.0448) and `#595959` (2.998) | the first `isUsable` and `usable()` returns it; the second is not usable and `usable()` is null | the floor is wrong (the pair straddles 3.0 by one grey step) |
| S-28604 | `#757575` (black 4.5578, white 4.6075), `#777777` (black 4.6895, white 4.4781), `#FFFFFF` | `labelIsDark` false, true, true; `labelColor` is `Colors.white` for the first and `Colors.black` for the other two | the label rule compares the wrong pair or the wrong way round |
| S-28605 | `worn` of: null, empty, `garbage`, `#202020`, `#000000`, `#595959`, `#FF7B45`, `#757575` | the first six give the fallback (`color` is `Color(0xFF2DE2E6)`); the last two give themselves | the fallback is wrong, or an unusable accent is worn |
| S-28606 | `#FF7B45` | `color` equals `Color.fromARGB(255, 255, 123, 69)` | the channels are mixed |

`test/wear_accent_theme_test.dart` (new, `testWidgets`, 227x227): the harness is copied from `test/wear_phone_settings_test.dart` (`_Harness`, `_open`, `_setView`, `_envelope`, `_kindSession`); the theme is read with `Theme.of(tester.element(find.byType(Scaffold).first)).colorScheme`; a frame is delivered with `await harness.transport.deliver(frame)` then `await tester.pump()`.

| S-n | fixture | expect | fails without |
|---|---|---|---|
| S-28610 | shell with preferences, nothing synced; the button check runs once a session exists (the start surface builds no `FilledButton` before routines sync) | `primary` is `Color(0xFF2DE2E6)`, `onPrimary` is black; the first `FilledButton`'s Material colour is that cyan | the theme still uses Material's default lilac |
| S-28611 | deliver a copy with `accentColorHex: '#FF7B45'` | `primary` `Color(0xFFFF7B45)`, `onPrimary` black; the first `FilledButton` wears `0xFFFF7B45` | the shell ignores the copy, or does not repaint after the frame |
| S-28612 | S-28611, then a later copy (`generatedAt` later) with `#A478FF`, then a still later copy with no accent | primary `0xFFA478FF`, then back to `0xFF2DE2E6` | the theme keeps the old colour, or a missing accent keeps the previous one |
| S-28613 | a copy with `#202020`; another with `#757575` | `#202020` gives cyan; `#757575` gives primary `0xFF757575` and `onPrimary` white | an unusable colour is worn, or the label is always black |
| S-28614 | S-28611's state, then deliver an OLDER copy (`generatedAt` earlier) with `#24B85A` | primary stays `0xFFFF7B45` | the theme reads the last frame instead of the applying copy |
| S-28615 | shell built with `preferences: null` | primary `0xFF2DE2E6` | no-preferences shells keep the lilac |
| S-28616 | a store already holding an accent copy (`#E8B420`); a NEW shell over it, after `_open` | primary `0xFFE8B420` on the first settled frame | `_boot` forgets to repaint after the restore, or the theme is built before `restore()` and never again |
| S-28617 | a running session, the accent `#FF7B45`; capture `Theme.of(context)` identity, `pump(1 s)` three times | the same `ThemeData` instance each time; then deliver a copy with `#A478FF` | a new `ThemeData` per tick (no cache), or a cache that never refreshes (second half) |

Guard families proven by the lead's mutations: the luminance weights, the linearisation threshold, the contrast formulas, the `>=` of the floor and of the label, the fallback hex, the regex anchors, `worn`'s two branches, the `onPrimary` assignment, the cache key.

## Phases

Every builder brief opens with "Never run the full `flutter test`" and "write the report FIRST as a skeleton". Serial.

1. **P1 — class and shell** (`crew-builder-watch`; scope `lib/watch/widgets/watch_accent.dart`, `lib/watch/app/wear_app.dart`). Exact code in the brief. About 90 lines.
2. **P2 — tests** (`crew-builder-watch`; scope `test/watch_accent_test.dart`, `test/wear_accent_theme_test.dart`). S-28601..S-28617.
3. **P3 — docs** (`crew-docs-keeper`, no test run).
4. **Lead:** mutation pass, full suite, analyze, plan-lint.

Predicted production code about 90 lines in 2 files: inside the budget.

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| docs/wear_os_app.md | MODIFIED | and the accent colour still shows | the accent colour tints the buttons | S-28611 |
| docs/wear_os_app.md | MODIFIED | nothing — the accent theming stays on the Apple-only list above. | The accent theming is described in `## The accent colour` below. | S-28611 |
| docs/wear_os_app.md | MODIFIED | spoken timer cues and the accent | and spoken timer cues | S-28610 |
| docs/wear_os_app.md | ADDED | - | ## The accent colour | S-28610 |
| docs/wear_os_app.md | ADDED | - | 8. (owner) with a paired phone set to a colour theme | S-28611 |

Stale-term sweep: `grep -rIn -i "accent theming" docs | grep -v "docs/plans\|docs/history\|docs/releases"` hits `docs/wear_os_app.md` lines 273 and 443-444 (rows above); `docs/wear_os_app.md` line 267 ("effort-rating flag and accent colour are stored") stays true. Plan 280's open item 8 in its plan file is a plan record (the keeper adds one line "built by plan 286").

## Assumption Log

- `WatchPhonePreferences.accentColorHex` returns the applying copy's string (null when the copy had none), verified in `lib/watch/start/watch_phone_preferences.dart`.
- `WearApp._onFrame` runs `setState` after `orchestrator.receive`, so a delivered frame repaints the theme; `transport.deliver(frame)` is the path `test/wear_phone_settings_test.dart` and the platform use.
- `ColorScheme.copyWith(primary:, onPrimary:)` leaves every other role alone, so the destructive and tonal buttons keep their colours.

## Progress

- [x] P1 production
- [x] P2 tests
- [x] P3 docs
- [ ] Mutation pass, full suite
