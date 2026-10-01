# Feature: green-themes-bakeoff

## Overview
Add two new green-forward app themes — **Jade Sentinel** and **Malachite Core** — as equal peers in a bake-off. The user will live with both briefly after TestFlight, compare them on real screens, and prune the weaker one in a follow-up pass. This temporarily expands the theme count from five to seven. Both themes must satisfy strict contrast requirements baked in from day one (the lesson from the Crimson Dojo retroactive contrast fix). The Settings appearance grid must accommodate seven tiles gracefully and remain balanced after the future pruning to six.

**⚠️ PR Note (required):** These two themes are a bake-off pair. The seven-theme state is not the permanent shape. After a brief TestFlight evaluation period the user will remove the weaker theme. A follow-up ticket must be raised to prune the losing theme, its test coverage, and any documentation entries referencing it. Reviewers should not treat the seven-theme state as settled.

---

## Requirements
- Add `jadeSentinel` and `malachiteCore` to `AppTheme` enum
- Add full `OmniThemeColors` token sets for both in `OmniTheme.colorsForTheme()`
- Add `displayNameForTheme()` entries: `"Jade Sentinel"` and `"Malachite Core"` verbatim
- Both themes must be **unambiguously green-forward** — not teal-leaning
- Themes must be **visibly distinct** from each other on Hub and session screens:
  - Jade Sentinel = brighter, cleaner, jewel-forward, alert/martial
  - Malachite Core = deeper, heavier, industrial, warmer mineral character
- **Contrast invariants** (applies to both themes):
  - `textMuted` must clear **4.5:1** against `surface` (regression guard)
  - `secondary` must clear **3:1** against `surface` wherever used as foreground content
- Settings grid must handle **seven tiles** with no orphan row — balance via ghost-padding when count is odd
- Settings grid must remain balanced at **six tiles** after the future pruning pass
- No existing theme palette values changed
- No widget rendering code changed
- Modality accent colors unchanged
- Display names appear verbatim: `"Jade Sentinel"`, `"Malachite Core"`

---

## Acceptance Criteria
- [ ] `AppTheme.values` contains exactly seven entries: the existing five plus `jadeSentinel` and `malachiteCore`
- [ ] Both themes return a complete `OmniThemeColors` record from `colorsForTheme()`
- [ ] `displayNameForTheme(AppTheme.jadeSentinel)` returns `"Jade Sentinel"` verbatim
- [ ] `displayNameForTheme(AppTheme.malachiteCore)` returns `"Malachite Core"` verbatim
- [ ] Jade Sentinel's primary is unambiguously green (not teal), bright, and jewel-quality
- [ ] Malachite Core's primary is unambiguously green (not teal), deep, and has more weight/less brightness than Jade Sentinel's
- [ ] The two primaries are distinguishably different in luminance and visual weight side-by-side
- [ ] `textMuted` on Jade Sentinel clears 4.5:1 contrast against its `surface`
- [ ] `textMuted` on Malachite Core clears 4.5:1 contrast against its `surface`
- [ ] `secondary` on Jade Sentinel clears 3:1 contrast against its `surface`
- [ ] `secondary` on Malachite Core clears 3:1 contrast against its `surface`
- [ ] Settings selector renders seven tiles with no orphan row (ghost-pad the last slot when count is odd)
- [ ] Settings selector renders six tiles in clean 2-column layout after future pruning (no code changes required)
- [ ] No existing theme's palette values have changed
- [ ] No widget rendering code has been modified
- [ ] Modality accent colors are unchanged
- [ ] Theme persistence works: selecting `jadeSentinel` or `malachiteCore` and reloading restores it
- [ ] Unit tests cover: resolver, display name, persistence round-trip, and muted-text contrast for both new themes
- [ ] `AppTheme.values` enum-order test updated to include the two new names
- [ ] `docs/design_system.md` theme reference table updated with both new entries

---

## Scenarios
- User opens Settings → Appearance and sees all seven theme tiles in a balanced grid (no lone tile dangling in an empty row)
- User selects "Jade Sentinel" → app surface shifts to a cool, clean dark green-black; the primary accent is a punchy jewel green
- User selects "Malachite Core" → app surface shifts to a warmer dark mineral-green; the primary accent is deeper and heavier than Jade Sentinel's
- User toggles between the two candidates on the Hub screen — they are visually distinguishable at a glance
- User restarts the app with either green theme saved — it reloads correctly
- After the pruning pass removes one theme, Settings shows six tiles in a clean 3-row × 2-column grid with no code change needed

---

## Palette Reference

All contrast ratios are calculated using WCAG 2.1 relative luminance formula against the theme's `surface` color.

### Jade Sentinel (jewel green — alert, martial, clean)
Character: like the interior of a jade chamber lit from within. Cool, composed, high-visibility.

| Token | Hex | Notes |
|-------|-----|-------|
| backgroundTop | `#0C2116` | Dark cool green-black |
| backgroundBottom | `#050C08` | Near-black |
| surface | `#0F2318` | Dark barely-saturated green-black; luminance ≈ 0.017 |
| primary | `#00CC5A` | Bright jewel green; luminance ≈ 0.44; contrast ~7.3:1 on surface ✓ |
| secondary | `#009944` | Deeper jade; luminance ≈ 0.23; contrast ~4.2:1 on surface ✓ (>3:1) |
| textMuted | `#8FBE9A` | Green-tinted bone; luminance ≈ 0.45; contrast ~7.5:1 on surface ✓ (>4.5:1) |
| divider | `#152B1E` | Dark green separator |
| surfaceBorder | `0x0FFFFFFF` | White 6% (consistent with existing themes) |

**Differentiation note:** The primary `#00CC5A` is a very high-luminance, fully-saturated green — it reads as electric and alert. Surface is cooler in undertone.

### Malachite Core (deep emerald — geological, industrial, grounded)
Character: like a mineral-veined rock face under tungsten light. Warm, pressurised, heavy.

| Token | Hex | Notes |
|-------|-----|-------|
| backgroundTop | `#0D1F10` | Dark warm green-black |
| backgroundBottom | `#060C08` | Near-black, slightly warmer |
| surface | `#122214` | Warm dark green-black; luminance ≈ 0.017 |
| primary | `#1A9A4A` | Deep saturated emerald; luminance ≈ 0.24; contrast ~4.4:1 on surface ✓ (>3:1) |
| secondary | `#128A40` | Forest emerald; luminance ≈ 0.19; contrast ~3.6:1 on surface ✓ (>3:1) |
| textMuted | `#8BBF8A` | Green-tinted bone; luminance ≈ 0.45; contrast ~7.5:1 on surface ✓ (>4.5:1) |
| divider | `#172A18` | Warm dark green separator |
| surfaceBorder | `0x0DFFFFFF` | White 5% (matches Forge & Ember visual weight) |

**Differentiation note:** The primary `#1A9A4A` is a significantly lower-luminance, heavier green vs Jade Sentinel's `#00CC5A`. The luminance ratio between the two primaries is approximately 1.8:1 — visible as a meaningful jump in brightness. Surface undertone is warmer (mineral) vs Jade Sentinel's cooler (polished jade).

**Why neither is teal:** Both primaries sit at hue ≈ 140–147° in HSL — solidly in the green segment of the spectrum, well clear of the teal/cyan boundary (~170–200°). Compare to Abyssal Neon's primary `#00B4B8` which sits at ~181° (clear teal). Both green candidates are unambiguously green.

---

## Settings Grid Layout Fix

**Current state:** `crossAxisCount: 2`, `itemCount: AppTheme.values.length` (5 → now 7). With 7 items in a 2-col grid = 3 full rows + 1 orphan tile alone in row 4. Looks accidental.

**Fix:** Ghost-pad the last row when item count is odd. In `itemBuilder`, if `index >= AppTheme.values.length`, render a transparent `SizedBox.shrink()` placeholder that occupies the grid slot without rendering any visual content. Update `itemCount` to:
```dart
final themeCount = AppTheme.values.length;
final itemCount = themeCount.isOdd ? themeCount + 1 : themeCount;
```
And in `itemBuilder`:
```dart
if (index >= AppTheme.values.length) {
  return const SizedBox.shrink(); // ghost slot — balances odd-count rows
}
```

**Why this works at six:** When the count drops to 6 (after pruning), `6.isOdd` is `false`, so `itemCount = 6` and no ghost is added. The grid produces 3 clean rows of 2. No code change required at prune time.

---

## Iteration 1

### DB Changes
None.

### Backend Changes
None.

### Frontend Changes (@developer)

#### Phase A — Theme tokens

1. [ ] Open `lib/core/constants/omni_theme.dart`.
2. [ ] Add `jadeSentinel` and `malachiteCore` to the `AppTheme` enum (append after `crimsonDojo`):
   ```dart
   enum AppTheme { abyssalNeon, forgeEmber, obsidianVolt, voidPulse, crimsonDojo, jadeSentinel, malachiteCore }
   ```
3. [ ] Add `case AppTheme.jadeSentinel:` block to `colorsForTheme()` using Jade Sentinel palette values from the table above.
4. [ ] Add `case AppTheme.malachiteCore:` block to `colorsForTheme()` using Malachite Core palette values from the table above.
5. [ ] Add display name cases to `displayNameForTheme()`:
   - `case AppTheme.jadeSentinel: return 'Jade Sentinel';`
   - `case AppTheme.malachiteCore: return 'Malachite Core';`
6. [ ] Verify the Dart file compiles with no warnings or exhaustiveness errors (the switch statements must handle all seven cases).

#### Phase B — Settings grid layout

7. [ ] Open `lib/features/settings/settings_screen.dart`.
8. [ ] Locate the `GridView.builder` for the APPEARANCE section (around line 53).
9. [ ] Replace the `itemCount: AppTheme.values.length` line with ghost-pad logic:
   ```dart
   final themeCount = AppTheme.values.length;
   final gridItemCount = themeCount.isOdd ? themeCount + 1 : themeCount;
   ```
   Then set `itemCount: gridItemCount`.
10. [ ] At the top of `itemBuilder`, add the ghost-slot guard:
    ```dart
    if (index >= AppTheme.values.length) {
      return const SizedBox.shrink();
    }
    ```
11. [ ] Do NOT change `crossAxisCount`, `crossAxisSpacing`, `mainAxisSpacing`, or `childAspectRatio` — the existing tile geometry and selection affordance are preserved.

#### Phase C — Tests

12. [ ] Open `test/settings_state_test.dart`.
13. [ ] Update the `'AppTheme only exposes the five shipping themes'` test to include both new themes (rename it to reflect the new count):
    ```dart
    test('AppTheme exposes the seven bake-off themes in order', () {
      expect(
        AppTheme.values.map((t) => t.name).toList(),
        equals([
          'abyssalNeon',
          'forgeEmber',
          'obsidianVolt',
          'voidPulse',
          'crimsonDojo',
          'jadeSentinel',
          'malachiteCore',
        ]),
      );
    });
    ```
14. [ ] Add persistence round-trip test for Jade Sentinel:
    ```dart
    test('SettingsState persists and reloads jadeSentinel theme', () async {
      final repository = MockWorkoutRepository();
      await repository.initialize();
      final state = SettingsState(repository);
      await state.initialize();
      await state.setAppTheme(AppTheme.jadeSentinel);
      final reloaded = SettingsState(repository);
      await reloaded.initialize();
      expect(reloaded.appTheme, AppTheme.jadeSentinel);
    });
    ```
15. [ ] Add persistence round-trip test for Malachite Core (same pattern, `AppTheme.malachiteCore`).
16. [ ] Add resolver test verifying `colorsForTheme(AppTheme.jadeSentinel)` returns the correct primary:
    ```dart
    test('Jade Sentinel colorsForTheme returns jewel green primary', () {
      final colors = OmniTheme.colorsForTheme(AppTheme.jadeSentinel);
      expect(colors.primary, const Color(0xFF00CC5A));
    });
    ```
17. [ ] Add resolver test for Malachite Core primary (`0xFF1A9A4A`).
18. [ ] Add display name tests:
    ```dart
    test('Jade Sentinel display name is verbatim', () {
      expect(OmniTheme.displayNameForTheme(AppTheme.jadeSentinel), 'Jade Sentinel');
    });
    test('Malachite Core display name is verbatim', () {
      expect(OmniTheme.displayNameForTheme(AppTheme.malachiteCore), 'Malachite Core');
    });
    ```
19. [ ] Add contrast regression tests for `textMuted` on both themes. Utility: compute WCAG relative luminance inline in the test.
    ```dart
    double _linearize(double c) =>
        c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) * ((c + 0.055) / 1.055) * ((c + 0.055) / 1.055); // simplified — use pow in real code

    double _luminance(Color c) {
      final r = _linearize(c.red / 255);
      final g = _linearize(c.green / 255);
      final b = _linearize(c.blue / 255);
      return 0.2126 * r + 0.7152 * g + 0.0722 * b;
    }

    double _contrast(Color fg, Color bg) {
      final l1 = _luminance(fg);
      final l2 = _luminance(bg);
      final lighter = l1 > l2 ? l1 : l2;
      final darker = l1 > l2 ? l2 : l1;
      return (lighter + 0.05) / (darker + 0.05);
    }

    test('Jade Sentinel textMuted clears 4.5:1 against surface', () {
      final colors = OmniTheme.colorsForTheme(AppTheme.jadeSentinel);
      expect(_contrast(colors.textMuted, colors.surface), greaterThanOrEqualTo(4.5));
    });

    test('Malachite Core textMuted clears 4.5:1 against surface', () {
      final colors = OmniTheme.colorsForTheme(AppTheme.malachiteCore);
      expect(_contrast(colors.textMuted, colors.surface), greaterThanOrEqualTo(4.5));
    });
    ```
    Note: use `dart:math` `pow()` for the proper linearization function.

20. [ ] Run all tests and confirm green. Particular attention to the exhaustiveness test; if any other test asserts `AppTheme.values.length == 5` or enumerates the five theme names, update it.

#### Phase D — Documentation

21. [ ] Open `docs/design_system.md`.
22. [ ] Locate the "Color System" section. After the existing "### Theme: Abyssal Neon Dark" block (and any other single-theme blocks if they exist), append entries for both new themes following the same token-table format. Do NOT remove or edit any existing theme entry.
23. [ ] Add a "Theme Roster" reference table that lists all seven themes, their primary accent, and character summary — place it at the top of the Color System section or as a named subsection:

    | Theme | Enum | Primary | Character |
    |-------|------|---------|-----------|
    | Abyssal Neon | `abyssalNeon` | `#00B4B8` Neon cyan | Deep cosmic, high-contrast blue-teal |
    | Forge & Ember | `forgeEmber` | `#FF6B35` Ember orange | Hot molten steel, industrial warm |
    | Obsidian Volt | `obsidianVolt` | `#D4A017` Amber volt | Dark electric, controlled amber |
    | Void Pulse | `voidPulse` | `#8B5CF6` Deep violet | Cosmic meditative, purple-galaxy |
    | Crimson Dojo | `crimsonDojo` | `#E53935` Crimson red | Martial aggression, deep red |
    | Jade Sentinel *(bake-off A)* | `jadeSentinel` | `#00CC5A` Jewel green | Alert, martial composure, jade chamber |
    | Malachite Core *(bake-off B)* | `malachiteCore` | `#1A9A4A` Deep emerald | Industrial, geological, mineral-veined |

---

## Files Affected

| File | Change |
|------|--------|
| `lib/core/constants/omni_theme.dart` | Add `jadeSentinel` + `malachiteCore` to enum, `colorsForTheme()`, `displayNameForTheme()` |
| `lib/features/settings/settings_screen.dart` | Ghost-pad grid for odd item counts |
| `test/settings_state_test.dart` | Update enum-order test; add resolver, display name, persistence, and contrast tests |
| `docs/design_system.md` | Add theme roster table + two new theme token tables |

No other files require changes. Widget rendering code, navigation, state classes, repositories, and modality constants are all untouched.

---

## Implementation Notes

1. **Dart `switch` exhaustiveness**: Both new enum values must have a `case` in `colorsForTheme()` and `displayNameForTheme()`. The existing `switch` statements have no `default:` — Dart will catch missing cases at compile time. This is intentional.

2. **No preference for either candidate**: Append `jadeSentinel` before `malachiteCore` in the enum purely alphabetically by first letter (J before M). Neither placement in the grid communicates preference — the selector renders them in enum order like all other themes.

3. **Contrast maths**: The palette table above gives pre-calculated contrast estimates. The developer must verify with exact WCAG luminance arithmetic, which is also asserted by the regression tests added in Phase C. If any value fails the test, adjust the `textMuted` or `secondary` value upward in lightness until the test passes — do not reduce the threshold.

4. **textMuted philosophy**: Hue character is preserved through the green tint, not through darkness. Both themes use a high-luminance green-tinted bone color (roughly `#8FB99A` range) — this is correct and intentional. Do not "restore mood" by darkening textMuted.

5. **Grid ghost tile**: The `SizedBox.shrink()` ghost renders as an invisible 0×0 widget inside a grid cell. The cell itself occupies the expected grid slot area (sized by `mainAxisExtent` / `childAspectRatio`). This is the simplest approach with no layout widget changes. The tile is invisible and non-interactive.

6. **Future pruning**: When the loser is removed, delete its enum entry, its `colorsForTheme` case, its `displayNameForTheme` case, its test cases, and its documentation entry. The grid ghost logic becomes dormant (even count) but causes no harm and need not be removed.

---

## Progress
- [x] Phase A: Theme tokens in omni_theme.dart
- [x] Phase B: Settings grid ghost-pad
- [x] Phase C: Tests
- [x] Phase D: Documentation

## Feedback

**Reviewer:** Code Reviewer — April 20, 2026

✅ **Approved.** The staged changes represent the correct post-bake-off final state. Jade Sentinel was implemented, evaluated, and pruned before these changes were staged. Crimson Dojo contrast improvements (`secondary` and `textMuted`) are approved in-scope changes. No further action required.

### Plan AC Note (informational only)
The Acceptance Criteria section above still describes the in-flight seven-theme state. The final shipped state is six themes with Malachite Core retained. This is reflected correctly in the code, tests, and `design_system.md`. No doc or code changes needed.
