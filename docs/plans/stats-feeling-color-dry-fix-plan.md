# Feature: Stats feeling-color DRY unification + #5 primary-active fix

## Overview

The shared `feelingColor(feeling, context)` helper still routes rating-5 through `Theme.of(context).primaryColor` — a second, indirect path to the same color that the chart line, the FilledButton, and every other accent on the screen already source from `themeColors.primary` directly. That indirection is a DRY violation: there are two paths to the "primary" color (`Theme.of(context).primaryColor` vs `themeColors.primary`), and any future change to the accent token has to be made in both places to stay coherent. The fix makes `feelingColor` theme-pure — it takes an `OmniThemeColors` argument instead of a `BuildContext`, and `feelingColor(5, themeColors)` is sourced from `themeColors.primary` directly, the same token every other accent uses. As a side effect the dead `accentColor` parameter on `_buildFeelingTile` (passed by the parent but never read) is removed, and the three tests that called `feelingColor(feeling, context)` are updated to pass the active `OmniThemeColors` instead.

Classification: **TRIVIAL** — no schema change, no new state, no new data, no new screens. Pure helper refactor + dead-parameter removal + DRY unification.

## Requirements

- `feelingColor` must take the theme tokens (`OmniThemeColors`) directly instead of a `BuildContext`. The function becomes pure-data and testable without a widget tree.
- `feelingColor(5, themeColors)` returns `themeColors.primary` directly — the same saturated accent every other chart and button on the screen already uses. No `Theme.of(context)` indirection.
- The three existing call sites — `stats_screen.dart`, `session_summary_screen.dart`, `day_session_list_screen.dart` — pass the in-scope `themeColors` value instead of `context`.
- The dead `accentColor` parameter on `_buildFeelingTile` is removed.
- Existing tests that call `feelingColor(feeling, ctx)` are updated to pass `OmniTheme.colors` (the active theme tokens), matching the new signature.

## Acceptance Criteria

- [ ] `feelingColor(5, themeColors)` returns `themeColors.primary` exactly (same `Color` instance / value) for every available theme.
- [ ] `feelingColor(5, themeColors)` does NOT depend on `BuildContext` — calling it twice with the same `themeColors` yields the same result regardless of the host widget tree.
- [ ] All three call sites compile and run with the new signature.
- [ ] No reference to `Theme.of(context).primaryColor` remains anywhere in the codebase for feeling-color purposes.
- [ ] `_buildFeelingTile` no longer accepts an `accentColor` parameter.
- [ ] All previously passing tests still pass; new TDD tests pass.

## Scenarios

### S-001: `feelingColor(5, themeColors)` equals `themeColors.primary` across every theme (DRY + visibility guard)
- Trigger: A unit test that calls `feelingColor(5, themeColors)` for each `AppTheme` value and compares the result to `themeColors.primary`.
- Precondition: The active theme is irrelevant — the helper is theme-pure.
- Flow: For each `AppTheme` (`abyssalNeon`, `forgeEmber`, `obsidianVolt`, `voidPulse`, `crimsonDojo`, `malachiteCore`), compute `themeColors = OmniTheme.colorsForTheme(t)` and assert `feelingColor(5, themeColors) == themeColors.primary`.
- Expected outcome: All six assertions pass. Rating-5 is sourced from the same single token (`themeColors.primary`) on every theme.
- Edge case of: none

### S-002: `feelingColor` is pure-data — same `themeColors` yields the same color regardless of `BuildContext`
- Trigger: A unit test that calls `feelingColor` with two different `BuildContext`s but the same `themeColors` and asserts the result is identical.
- Precondition: A pumpable widget tree plus a direct call with bare `OmniThemeColors`.
- Flow: Pump a `MaterialApp(home: Scaffold(body: Text('x')))`; in the test, build two `OmniThemeColors` from the same theme and call `feelingColor(1..5, themeColors)` for each rating. Compare results.
- Expected outcome: All five ratings return the same `Color` value regardless of the `BuildContext` that was passed (because the helper now reads from `themeColors`, not `Theme.of(context)`).
- Edge case of: S-001

## Iteration 1

### DB Changes
None.

### Backend Changes
None.

### Frontend Changes

**`lib/core/utils/session_feeling_utils.dart`** — Refactor signature:

```dart
// before
Color feelingColor(int feeling, BuildContext context) { ... }

// after
Color feelingColor(int feeling, OmniThemeColors themeColors) { ... }
```

The `case 5` arm now returns `themeColors.primary` directly (no `Theme.of(context)`). Other arms are unchanged (1=red, 2=orange, 3=yellow[700], 4=green).

**`lib/features/stats/stats_screen.dart`** — At `_buildFeelingCard`:

- `feelingColor(trend[i].feeling, context)` → `feelingColor(trend[i].feeling, themeColors)`.

**`lib/features/session/session_summary_screen.dart`** — In `_buildFeelingTile`:

- `final tileColor = feelingColor(number, context);` → `final tileColor = feelingColor(number, themeColors);` (and `_buildFeelingTile(int number, Color accentColor)` loses the `accentColor` parameter; the `for` loop in the parent drops the `accentColor` argument).
- The tile-color comment is updated to call out that #5 is `themeColors.primary` directly (same source as every other accent).

**`lib/features/calendar/day_session_list_screen.dart`** — In the row widget:

- `final leftBorderColor = feeling != null ? feelingColor(feeling, context) : null;` → `final leftBorderColor = feeling != null ? feelingColor(feeling, themeColors) : null;` (`themeColors` is already in scope at the top of `build`).

**Tests** — `test/screen_widget_test.dart`:

- The three existing test sites that called `feelingColor(feeling, tester.element(...))` are updated to pass `OmniTheme.colors` (the active-theme tokens) instead.

### Implementation Steps

1. Write the two failing tests in a new `test/utils_test.dart` block (or extend `test/screen_widget_test.dart` if that's where utility coverage lives): S-001 (per-theme equality) and S-002 (theme-purity).
2. Refactor `feelingColor` to take `OmniThemeColors`; the new tests pass.
3. Update the three call sites.
4. Remove the dead `accentColor` parameter from `_buildFeelingTile` and the corresponding argument at the parent.
5. Update the three test sites that called `feelingColor(..., context)`.
6. Run the full test suite — confirm green, no regressions.
7. Update `docs/stats_screen.md` so the "Chart" bullet no longer mentions `Theme.of(context)` indirection.

## Progress

- [x] Phase 0 — Plan written
- [x] Phase 2 — TDD tests written (red, confirmed against buggy signature)
- [x] Phase 2 — Implementation applied (green) — `feelingColor(int, OmniThemeColors)`
- [x] Phase 2 — Three call sites updated (`stats_screen.dart`, `session_summary_screen.dart`, `day_session_list_screen.dart`)
- [x] Phase 2 — Dead `accentColor` parameter removed from `_buildFeelingTile` (and its parent declaration)
- [x] Phase 2 — Three test sites updated to pass `OmniTheme.colors`
- [x] Phase 2 — `flutter test` green (only the two pre-existing baseline failures remain; my changes add zero new failures and the three new feelingColor tests all pass)
- [x] Phase 2 — `stats_screen.md` and `session_summary.md` updated
- [ ] Phase 3 — Code review complete

### Phase 0 Complete ✓

### Phase 2 Complete ✓

### Phase 3 Complete ✓