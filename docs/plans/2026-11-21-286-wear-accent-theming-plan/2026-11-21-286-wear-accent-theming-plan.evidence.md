# Evidence — plan 286 (Wear wrist wears the phone's accent colour)

## Done

- `WatchAccent` (`lib/watch/widgets/watch_accent.dart`) — the Dart twin of the
  Apple client's `WatchAccent.swift`: strict `#RRGGBB` parsing, WCAG 2.x
  relative luminance, both contrast ratios, the 3.0 wearability floor, the
  label rule, `worn` falling back to `#2DE2E6` (D-28601).
- `WearAppState._themeFor` (`lib/watch/app/wear_app.dart`) — the dark Material
  scheme copied with only `primary` and `onPrimary` from the worn accent, the
  `ThemeData` cached by the hex so the once-a-second rebuild does not re-theme
  the tree (D-28602); `build` hands it to `MaterialApp` (D-28603, D-28604).
- `test/watch_accent_test.dart` — S-28601..S-28606, held to
  `watch/contract/watch_accent_contract.json`.
- `test/wear_accent_theme_test.dart` — S-28610..S-28617, harness copied from
  `test/wear_phone_settings_test.dart`.
- Docs delta applied to `docs/wear_os_app.md`: the two MODIFIED sentences, the
  new section `## The accent colour`, check item 8, Doc freshness already
  2026-11-21 (no change needed). Plan 280's open item 8 annotated.

## Files changed

- `lib/watch/widgets/watch_accent.dart` — new, about 95 lines.
- `lib/watch/app/wear_app.dart` — +22/-3 (per the lead's brief).
- `test/watch_accent_test.dart` — new.
- `test/wear_accent_theme_test.dart` — new.
- `docs/wear_os_app.md` — docs delta (P3).
- `docs/plans/2026-11-20-280-wear-os-shell-plan/2026-11-20-280-wear-os-shell-plan.md`
  — open item 8 annotated with one line.

## Test results (lead's counts)

- `test/watch_accent_test.dart` — 6 passed.
- `test/wear_accent_theme_test.dart` — 8 passed.
- Neighbouring Wear files green: `test/wear_app_test.dart` 6,
  `test/wear_phone_settings_test.dart` 6, `test/wear_menu_screen_test.dart` 22,
  `test/wear_effort_rating_screen_test.dart` 19,
  `test/watch_accent_contract_test.dart` green.
- `flutter analyze` — 174 issues, 0 errors (baseline held).

## Findings

- The theme fades for 200 ms because `MaterialApp` animates theme changes;
  tests settle with a 250 ms pump.
- The start surface shows no `FilledButton` before routines are synced, so the
  button check in S-28610/S-28611 runs once a session exists.

Mutation pass (lead, in place, source restored and byte-compared after each): 27 mutants, all killed: three luminance weights, the linear threshold, divisor and exponent, both contrast formulas, the label comparison flipped, the floor at 3.05 and 2.99, `isUsable` always true, the fallback hex, the regex without `^`, without `$` and upper-case only, `worn` and `usable` skipping the floor, channels swapped, the label colours swapped, the parse shifts, `onPrimary` and `primary` dropped, the preferences ignored, the cache always and never hitting, the cache key not stored. Two survived the first pass (the linear divisor and the white-contrast numerator) and were closed by two lead-written fixtures in S-28604: `#767676` (next grey step, black wins) and `#038901` (usable, black 4.582574 vs white 4.582577, white label; the small red and blue channels sit on the linear branch). Not mutated: `>=` to `>` in `labelIsDark` and `isUsable`, equivalent because no 8-bit colour gives exactly equal contrasts or exactly 3.0.
