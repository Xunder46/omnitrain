# Feature: Home-screen nutrition strip (placeholder)

## Overview
Add a full-width strip button along the bottom of the home screen, in the space freed by removing the Hub sheet's peek handle. It is a zero-state placeholder for the nutrition entry point — text is hard-coded to "0 calories today" and tapping opens a placeholder destination. Live calorie totals and the real day-log arrive in Phase 3.

The strip must sit above the device's bottom system-gesture/safe area, must not be a FAB, and must not displace or compete with the training tiles.

This is a UI-only change. No repository, schema, or state methods are added.

## Requirements
- A new full-width strip sits along the bottom of the home screen, above the safe area.
- Strip text: "0 calories today".
- Tapping the strip opens a placeholder destination (use the existing `MaintenancePlaceholderScreen` with title "Nutrition" and a short description).
- Strip must not be a `FloatingActionButton`.
- Strip must not displace or compete with the six training tiles.
- Strip must sit above the home-indicator / system gesture safe area (`SafeArea(top: false)` or equivalent MediaQuery padding).
- Style matches the app's dark theme (use `OmniTheme.colorsForTheme(activeTheme)` tokens — surface fill, surface border, text tokens). No hardcoded colors.
- No new repository methods, no schema changes, no new state.

## Acceptance Criteria
- [ ] A full-width strip sits along the bottom of the home screen, above the safe area, reading "0 calories today".
- [ ] Tapping the strip opens the placeholder nutrition destination.
- [ ] The strip does not trigger or block the home-indicator gesture (it lives above the safe-area inset and is not a FAB).
- [ ] No training tile was added, removed, or resized; no FAB was added.
- [ ] The strip's colors come from `OmniTheme` tokens, not hardcoded values.

## Scenarios

### S-001: Cold-start home screen shows nutrition strip
- Trigger: User opens the app to the home screen (no active session).
- Precondition: Home screen mounted, no Hub sheet interaction.
- Flow:
  1. App reaches the home screen.
  2. The home body renders the existing TRAIN heading + 2×2 + 2×1 training tile grid.
  3. A new full-width strip is rendered along the bottom of the Scaffold body, above the device's bottom safe-area inset.
  4. The strip displays "0 calories today".
- Expected outcome: The strip is visible at the bottom of the home screen. The six training tiles are still visible and in their existing positions. The Hub sheet is at rest (off-screen). Tapping inside the strip's tappable area does not open the Hub.
- Edge case of: none

### S-002: Tapping the strip opens the placeholder nutrition destination
- Trigger: User taps the nutrition strip on the home screen.
- Precondition: Home screen mounted, strip visible.
- Flow:
  1. User taps anywhere on the strip.
  2. The strip's `onTap` callback runs `OmniNavigator.push` to a placeholder screen.
  3. The placeholder screen renders with the existing `MaintenancePlaceholderScreen` (title "Nutrition", description "Coming soon — daily nutrition tracking arrives in a future update.").
- Expected outcome: The user sees a "Coming Soon" placeholder screen titled "Nutrition" with the placeholder copy. Back button (or system back) returns to the home screen with the strip still visible.
- Edge case of: none

### S-003: Strip lives above the home-indicator safe area
- Trigger: User views the home screen on a device with a bottom home-indicator (e.g., iPhone X+, modern Android).
- Precondition: Home screen mounted, device has a non-zero `MediaQuery.padding.bottom`.
- Flow:
  1. The strip renders inside a `SafeArea(top: false)` wrapper (or uses `MediaQuery.viewPadding.bottom`) so its bottom edge is above the system gesture inset.
  2. The user performs a home-indicator swipe up from the very bottom of the screen.
- Expected outcome: The system recognizes the home-indicator swipe and the app does not intercept it. Tapping the strip body opens the placeholder; swiping from the system gesture area triggers the system home gesture, not the strip's tap.
- Edge case of: S-001

### S-004: No FAB or training-tile displacement
- Trigger: User views the home screen.
- Precondition: Home screen mounted.
- Flow:
  1. The home body still contains the six training tiles (Cardio, Resistance, Sports, Isometric, Free Training, My Routines) in the existing 2×2 + 2×1 layout.
  2. No `FloatingActionButton` exists anywhere on the home screen.
- Expected outcome: Tile count, layout, and behavior are unchanged. The strip is a separate element, not inside the training grid.
- Edge case of: S-001

## Iteration 1

### DB Changes
None.

### Backend Changes
None.

### Frontend Changes (@developer)

#### 1. Create the strip widget
Add `lib/features/home/widgets/nutrition_strip_button.dart` (new widget, scoped to the home feature folder to keep it close to its only call site).

API:
- `class NutritionStripButton extends StatelessWidget`
- `const NutritionStripButton({super.key, required this.onTap, this.label = '0 calories today'})`
- `final VoidCallback onTap;`
- `final String label;`

Implementation:
- `Material` → `InkWell` for splash + tap.
- Outer `SafeArea(top: false)` so it clears the bottom system-gesture inset without affecting the top.
- Container with `width: double.infinity`, padding `EdgeInsets.symmetric(horizontal: 16, vertical: 12)`.
- Background: `themeColors.surface`.
- Border: top-only `BorderSide(color: themeColors.surfaceBorder, width: OmniTheme.surfaceBorderWidth)` to give a subtle separator from the home body above.
- Corner radius: small (e.g. `BorderRadius.circular(8)`) — does not need to match the larger 20px tile radius; the strip is a thin footer element.
- Subtle shadow: `[BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 12, offset: Offset(0, -2))]` to lift the strip off the body.
- Text: `Text(label, style: ...copyWith(color: themeColors.textDominant, fontWeight: FontWeight.w600, letterSpacing: 0.5))`.
- Optional leading icon: `Icons.local_fire_outline` (or similar neutral placeholder) tinted with `themeColors.primary` at 0.7 opacity, for a hint of the eventual calorie metric.

#### 2. Placeholder destination
Reuse the existing `lib/features/home/maintenance_placeholder_screen.dart` (`MaintenancePlaceholderScreen`). No new screen file is required.

#### 3. Wire the strip into `HomeScreen.build`
File: `lib/features/home/home_screen.dart`

- In the `Scaffold.body` `Stack`, the top-level child currently is `SafeArea(... Column(...))` and the second child is `_buildMaintenanceSheet(context)`.
- Wrap the existing `SafeArea` body in a `Column` (or use `Stack` positioning) so the strip sits *below* the existing body and above the bottom edge of the Stack. Concretely, the cleanest approach:
  - Replace the outer `Stack` body with a `Column` whose children are:
    1. `Expanded(child: SafeArea(bottom: false, child: <existing Column body>))` — the body fills the available space above the strip. Set `bottom: false` on the body `SafeArea` so the strip below owns the safe-area inset.
    2. `NutritionStripButton(onTap: () => _openNutritionPlaceholder())` — full-width, sits below the body.
  - Add a private method `_openNutritionPlaceholder()`:
    ```dart
    void _openNutritionPlaceholder() {
      OmniNavigator.push(
        context,
        (_) => const MaintenancePlaceholderScreen(
          title: 'Nutrition',
          description:
              'Coming soon — daily nutrition tracking arrives in a future update.',
        ),
      );
    }
    ```
  - Update the existing `body:` import to include `maintenance_placeholder_screen.dart` (already imported? — verify in the file; if not, add it).

Notes:
- The Hub sheet (`_buildMaintenanceSheet`) is *not* part of this Column. It is still rendered in the Scaffold as a `bottomSheet` parameter (or kept in the Stack). To avoid disturbing the existing sheet contract, the **safest minimal change** is: keep the existing `Stack` body, change its first child to the `Column(body, strip)` and leave the second child (the sheet) untouched. The strip lives inside the body's Column, not the sheet.
- To keep the strip above the safe area and the body's existing padding behavior intact, structure the body's child like this:
  ```dart
  Column(
    children: [
      Expanded(
        child: SafeArea(
          bottom: false, // body no longer pads the bottom
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16.0, 5.0, 16.0, 0.0),
            child: <existing Column content (TRAIN heading + grid)>,
          ),
        ),
      ),
      NutritionStripButton(onTap: _openNutritionPlaceholder),
    ],
  )
  ```
- The `bottom: false` on the body's SafeArea is required so the body does not double-pad with the strip's own SafeArea.

#### 4. Keep the existing `_buildMaintenanceSheet` untouched.
- The Hub sheet is a `DraggableScrollableSheet` rendered in the `Stack`. Its `minChildSize: 0.0` keeps it off-screen at rest, so the strip is the only visible bottom element until the user opens the Hub.

#### 5. Tests
Add `test/home_nutrition_strip_test.dart` with two groups:

**Group A — `NutritionStripButton`**
- `'renders the placeholder label'` — pump widget, expect `find.text('0 calories today')` to find one widget.
- `'invokes onTap when tapped'` — pump with a flag, tap, expect flag to be set.

**Group B — `HomeScreen` integration**
- `'shows the nutrition strip and routes on tap'` — build a `HomeScreen` with the standard fake dependencies (mirror the helper in `test/home_logo_hub_open_test.dart`), pump, expect `find.text('0 calories today')` to find one widget. Then `tester.tap(find.text('0 calories today'))`, pump, and expect `MaintenancePlaceholderScreen` to be in the tree (or `find.text('Coming Soon')` to be findable).
- `'no nutrition heading or text block is rendered above the strip'` — guard test. Build the home screen, assert the body **does not** contain any of: `'Nutrition'`, `'0 calories today'` (in the body, outside the strip), `'calories'`, or any free-standing `Text` widget reading those strings above the strip. Use `find.descendant(of: find.byType(NutritionStripButton), matching: find.text('0 calories today'))` for the strip's text, and assert the same text is not present elsewhere. This guard prevents the earlier premature nutrition heading/text block from returning.

### Implementation Steps
1. [ ] Create `lib/features/home/widgets/nutrition_strip_button.dart` with `NutritionStripButton`.
2. [ ] Add `_openNutritionPlaceholder` to `_HomeScreenState`.
3. [ ] Restructure the `Stack`'s first child to a `Column` with `Expanded(body)` + `NutritionStripButton`.
4. [ ] Ensure `MaintenancePlaceholderScreen` is imported in `home_screen.dart`.
5. [ ] Add `test/home_nutrition_strip_test.dart` covering the two groups above.
6. [ ] Run `flutter test test/home_nutrition_strip_test.dart test/home_logo_hub_open_test.dart test/interaction_flow_test.dart test/screen_widget_test.dart` to confirm green.
7. [ ] Smoke test on web with `flutter run -d chrome` and confirm the strip is visible above the home indicator, tap opens the placeholder, and the six training tiles are unchanged.

## Progress
- [x] Create `NutritionStripButton` widget
- [x] Wire strip into `HomeScreen.build`
- [x] Add `_openNutritionPlaceholder`
- [x] Add `test/home_nutrition_strip_test.dart`
- [x] Run targeted tests and web smoke check

## Feedback
- Phase 0 red gate: tests failed to compile because `NutritionStripButton` did not exist (correct kind of red — missing implementation, not test-config error).
- Phase 2 green: all 6 new tests pass; full home-related test set (`home_nutrition_strip_test`, `home_logo_hub_open_test`, `home_logo_press_affordance_test`) passes 15/15.
- Pre-existing failures in the working tree (26 occurrences of `SettingsState(repo)` 1-arg call sites in `test/screen_widget_test.dart`, `test/interaction_flow_test.dart`, `test/exercise_notes_sheet_test.dart`, `test/crown_control_tap_to_edit_test.dart`) are unrelated to this feature — they were broken on the working tree before this iteration by an in-progress `SettingsState` constructor change. Out of scope for the home-screen nutrition strip.
- Web smoke: `flutter build web` succeeded; the built bundle serves and contains the app entry. The 6 `withOpacity` deprecation warnings in `home_screen.dart` are pre-existing (not in code this iteration added).
- Plan said `Icons.local_fire_outline` — replaced with `Icons.local_dining_outlined` because `local_fire_outline` is not a member of the project's Material icon set under the current Flutter version.

---

## Iteration 4.1 — Strip Redesign per D-8

### Phase 4.1 — Strip Redesign per D-8 (@developer) — Complete

The Phase 4 (D-5) two-row layout exhibited three presentational
defects (SafeArea nesting, upward drop shadow, track
shrink-wrap → "floating pills"). D-8 supersedes the layout
and structurally removes all three defect classes.

### Frontend Changes
- [x] **1.** Rebuild `NutritionStripBar` per D-8: full-height bar; surface = track; fill with chevron leading edge (`CustomPaint`); straight interior segment boundaries; overlay calorie label with shadowed-text contrast treatment; hairline top border, no shadow; decoration OUTSIDE `SafeArea(top:false)`, content inside.
- [x] **2.** `HomeScreen`: strip claims fixed content height (`NutritionStripBarMetrics.contentHeight`, default 64 px) + bottom inset extending to screen edge; remove the `isCurrent` route gate (S-057); keep gap = 2 × `standardGridSpacing`.
- [x] **3.** Delete `nutrition_strip_button.dart` (carried over from Phase 4 item 5) and the `dispose()` no-op `whenComplete` (Phase 4's microtask-deferred load obviates the drain pattern).
- [x] **4.** Tests: S-050b, S-056, S-057 + re-point S-051..S-054 at the new geometry. S-050b's fixture is the 45 / 11 / 44 split as written; S-053 is preserved with the in-segment label as a `Text` widget so widget tests can probe it via `find.textContaining('P 25%')`. All 17 strip tests pass.
- [x] **5.** Update docs: `widget_catalog.md` (`NutritionStripBar` entry — D-8 geometry, design tokens, chevron behaviour, removed D-5 two-row description) and `navigation_and_screens.md` (`HomeScreen` row — D-8 layout summary, removed isCurrent gate, removed placeholder reference).

### Predicted Files
- [x] `lib/features/home/widgets/nutrition_strip_bar.dart` — rewritten per D-8.
- [x] `lib/features/home/home_screen.dart` — isCurrent gate removed, dispose no-op removed, `NutritionStripBar` geometry comments updated.
- [x] `lib/features/home/widgets/nutrition_strip_button.dart` — deleted (Phase 4 placeholder removed).
- [x] `test/home_nutrition_strip_test.dart` — rewritten with S-050b, S-056, S-057 + re-pointed S-051..S-054. 17 tests pass.
- [x] `docs/widget_catalog.md` — `NutritionStripBar` entry updated.
- [x] `docs/navigation_and_screens.md` — `HomeScreen` row updated.

### Phase 4.1 Complete ✓
Implementation done. All Phase 4.1 strip tests green. Ready for Code Reviewer.

---

## Iteration 5 — Nutrition Summary Card (gauge card rebuild)

### Phase 5.0 — Plan (@conductor) — Complete

The current strip (Phase 4.1 / D-8) reads as a system status bar
bolted under the cockpit: full-width rectangle, bright in-segment
labels, a chevron-shaped fill that bleeds past the tile grid
silhouette. This iteration rebuilds the surface as a single
self-contained gauge card that visually belongs to the same
instrument-panel family as the training tiles above it. The
data layer is untouched — `NutritionState` already exposes
`todayConsumedCalories`, `todayProteinKcal`, `todayNetCarbsKcal`,
`todayFatKcal`, and `nutritionTarget.calories`; the new card is
pure presentation.

**Classification:** STANDARD. Major visual + behavioral rebuild;
existing tests assert the wrong surface (full-bleed layout,
chevron-fill, in-segment "%" labels, arrow-only tap target) and
must be rewritten to the new layout.

### Overview

Replace the bottom-of-screen `NutritionStripBar` with a single
self-contained gauge card that:
- Has rounded corners, a raised/lit look, and inset margins (NOT
  full-bleed, NOT square corners, NOT pure-white).
- Treats the ENTIRE card as one tap target into the nutrition
  feature — the chevron is only a visual cue.
- Uses the calorie figure (`"{consumed} / {target} Cal"`) as the
  HEADLINE (largest, brightest text on the card).
- Renders ONE horizontal gauge below the figure: fill length =
  consumed / goal, segments inside the fill = protein / carbs /
  fat share of CONSUMED calories.
- Carries the actual macro percentages in a CAPTION row below the
  gauge with color markers — so the user reads captions, not
  thin bar segments.
- Uses MUTED macro colors (terracotta / steel-blue / amber) — not
  the saturated `macroChart` palette — so the card reads as a
  lit panel, not a status light.
- Over the calorie goal: gauge reads full, calorie figure shifts
  to the theme's restrained warning tone (no celebration, no
  alarm), nothing overflows.

### Requirements
- New widget `NutritionSummaryCard` lives at
  `lib/features/home/widgets/nutrition_summary_card.dart`.
- Old widget `NutritionStripBar`
  (`lib/features/home/widgets/nutrition_strip_bar.dart`) and its
  supporting class `StripSegment` / `NutritionStripBarMetrics` are
  removed.
- `HomeScreen` mounts `NutritionSummaryCard` INSET from the screen
  edges (matching the tile grid's 16 px side margin), not as a
  full-bleed footer bar.
- New muted macro palette `OmniTheme.colors.stripMacros` (terracotta
  / steel-blue / amber) is added; values are defined per theme.
- Card chrome matches the training-tile visual family: 20 px
  radius, hairline border, soft shadow lift.
- Empty state (nothing logged) renders calorie figure `"0 / {target} Cal"`,
  empty gauge, and dashes `—` in the captions (NOT `0%`).
- Over-budget state renders gauge at 100%, calorie figure in
  warning tone (`theme.colorScheme.error`), captions show the
  actual macro percentages (no overflow, no wrap).
- Existing keys `nutrition_strip_bar` / `nutrition_strip_label` /
  `nutrition_strip_filled` / `nutrition_strip_empty` are gone.
- New keys introduced for widget-test probes (defined in
  Implementation Steps).

### Acceptance Criteria
- [ ] Card renders with rounded corners, raised/lit look, inset margins — no full-bleed rectangle, no square corners, no pure-white block.
- [ ] Tapping anywhere on the card body (not just the chevron) opens the nutrition feature.
- [ ] Calorie figure displays consumed and goal and is the largest text on the card.
- [ ] Gauge fill length is proportional to `consumed / goal` (e.g., 643 of 2,000 fills roughly a third of the track).
- [ ] Within the fill, the protein/carb/fat segments are sized proportional to each macro's share of CONSUMED calories.
- [ ] The unfilled remainder is visibly distinct as remaining budget, with a subtle marker at the goal point.
- [ ] The caption row shows protein, carb, and fat percentages with matching color markers; percentages agree with the segment proportions.
- [ ] No element uses pure white as a fill; the three macro colors are muted (terracotta / steel-blue / amber) and clearly distinct.
- [ ] With nothing logged: gauge is empty, figure shows `0 / {target} Cal`, captions show dashes — not `0%`, not a broken bar.
- [ ] With consumed > goal: gauge full, figure in warning tone, no overflow.
- [ ] The training tiles above the card are unchanged and remain fully on screen.

### Scenarios

#### S-100: Happy state — card renders with headline + gauge + caption
- Trigger: Home screen renders with `consumedCalories=643`, `targetCalories=2000`, macro split `(proteinKcal, carbsKcal, fatKcal)` summing to `consumedKcalFromMacros`.
- Precondition: `NutritionState` has a non-null `nutritionTarget` with `calories > 0`; `todayConsumedCalories > 0`; macro kcals are non-zero.
- Flow:
  1. `HomeScreen.build` mounts `NutritionSummaryCard` with the consumed/target/macro kcals from `NutritionState`.
  2. Card renders inside its inset margin (16 px each side, NOT full-bleed).
  3. Top row: cross icon + headline text `"643 / 2,000 Cal"` (the headline is the largest text on the card) + chevron-right at the right edge.
  4. Middle row: horizontal gauge — the `track` is the full width, the `fill` is `643 / 2000 ≈ 32.2%` of the track, subdivided by macro kcal share of consumed.
  5. Bottom row: caption row with three `(colorMarker, percentage)` entries for protein / carbs / fat.
- Expected outcome: Card has rounded corners and raised shadow; headline is the brightest/largest text; gauge fill is roughly 32% of the track width; the three macro segment widths sum to the fill width; the three caption percentages sum to `100 ±1` (rounding).
- Edge case of: none.

#### S-101: Tap on card body opens nutrition feature
- Trigger: User taps anywhere on the card surface (NOT just the chevron).
- Precondition: Card is mounted; `onTap` is wired to `_openNutritionScreen` in `HomeScreen`.
- Flow:
  1. User taps a tap-test point on the card body that is NOT the chevron icon (e.g. the headline text or the gauge track).
  2. The card's `InkWell.onTap` fires.
  3. `HomeScreen._openNutritionScreen` pushes `NutritionScreen`.
- Expected outcome: `NutritionScreen` is in the tree; `find.byType(NutritionScreen)` matches one widget after the transition settles. The tap is NOT limited to the chevron.
- Edge case of: S-100.

#### S-102: Gauge fill proportion = consumed / goal
- Trigger: Card renders with a known consumed / target pair.
- Precondition: `consumed > 0`, `target > 0`.
- Flow:
  1. Card receives `consumedCalories=1200`, `targetCalories=2000` and a synthetic macro split that sums to 1200.
  2. The gauge `_Gauge` widget renders with `fillFraction = clamp(1200/2000, 0, 1) = 0.6`.
- Expected outcome: The fill rectangle's `RenderBox.size.width` is exactly `0.6 * trackWidth` (±0.5 px for rounding drift).
- Edge case of: S-100.

#### S-103: Macro segments are share of CONSUMED calories (not share of full bar)
- Trigger: Card renders with macro kcals `(P=400, C=400, F=400)` (sum = 1200 = consumed).
- Precondition: `consumed > 0`; all three macro kcals are positive.
- Flow:
  1. Card receives `proteinKcal=400`, `carbsKcal=400`, `fatKcal=400`.
  2. The `_GaugeSegmentsLayout` computes each segment's fraction as `seg.kcal / sum(macroKcal)` = `1/3` each.
- Expected outcome: Each of the three rendered segment `RenderBox` widths equals `fillWidth / 3` (±0.5 px for rounding drift). Test does NOT assert anything about the unfilled remainder — the segments are sized within the FILL, not within the full track.
- Edge case of: S-100.

#### S-104: Empty state — nothing logged
- Trigger: User has no consumed-food snapshots for today.
- Precondition: `todayConsumedCalories == 0` (with `targetCalories > 0` or `targetCalories == null` — both render the same empty card).
- Flow:
  1. Card receives `consumedCalories=0`.
  2. Card renders empty branch.
- Expected outcome: Calorie figure shows `"0 / 2,000 Cal"` (or `"0 / 2,000 Cal"` when target set) — does NOT show the goal as a number-only figure. The gauge is empty (no fill width). The caption row renders DASHES (`—`), NOT `0%`. The card is still tappable. The card chrome (rounded corners, raised look, inset margins) is unchanged.
- Edge case of: S-100.

#### S-105: Over-budget state — consumed > goal
- Trigger: User has logged more than the daily calorie goal.
- Precondition: `consumed > target`, `target > 0`.
- Flow:
  1. Card receives `consumedCalories=2450`, `targetCalories=2000`, macro split summing to 2450.
  2. Card renders over-budget branch.
- Expected outcome: The fill rectangle is clamped to `100%` of the track width (no overflow past `trackWidth`). The calorie figure text is rendered in the theme's warning tone (`theme.colorScheme.error`). No `RenderFlex` overflow is logged. The macro segment widths inside the fill sum to `trackWidth` (full). The captions show the actual macro percentages, not dashes.
- Edge case of: S-100.

#### S-106: Training tiles above the card are unchanged
- Trigger: Home screen renders with the card mounted.
- Precondition: `HomeScreen` has its full tile-grid setup.
- Flow:
  1. Pump `HomeScreen` (or `_pumpCard` with a tile-grid surrogate).
  2. Locate the tile grid via `find.byType(EnergyTile)`.
- Expected outcome: Six `EnergyTile` widgets are mounted (Cardio / Resistance / Sports / Isometric / Free Training / My Routines). The card sits BELOW the tile grid with the existing 32 px top gap (2 × `standardGridSpacing`).
- Edge case of: S-100.

### Iteration 1

#### DB Changes
None. The repo schema (`MockWorkoutRepository`, `HiveWorkoutRepository`,
future `SqliteWorkoutRepository`) already exposes:
- `getNutritionTargetForDate(int dateMs)` → `NutritionTarget?`
- `getConsumedFoodsForDate(int dateMs)` → `List<ConsumedFood>`

`NutritionState` already exposes:
- `nutritionTarget` (with `.calories`)
- `todayConsumedCalories` (sum of `caloriesConsumed`)
- `todayProteinKcal`, `todayNetCarbsKcal`, `todayFatKcal` (per-macro
  kcal contributions)
- `todayConsumedKcalFromMacros` (sum of the three above)
- `loadNutritionTarget()`, `loadConsumedToday()` (initial-load triggers
  in `HomeScreen._runInitialLoad`)

#### Backend Changes
None. No state class changes; no service changes; no repository
method changes.

#### Frontend Changes

##### 1. Add muted macro palette to OmniTheme
File: `lib/core/constants/omni_theme.dart`

- New typedef `StripMacroPalette` with three slots: `protein`,
  `carbs`, `fat` (each a `Color`).
- Add `stripMacros: StripMacroPalette` to the `OmniThemeColors`
  record tuple (next to `macroChart`).
- Define per-theme values (all muted; deliberately NOT the
  saturated `macroChart` palette so the card reads as a lit
  panel rather than a status light):

  | Theme       | protein (terracotta) | carbs (steel-blue) | fat (amber) |
  | ----------- | -------------------- | ------------------ | ----------- |
  | Abyssal Neon   | `#B07560` | `#6F8AA8` | `#C9A363` |
  | Forge & Ember  | `#B07160` | `#7A8FA6` | `#C9A05F` |
  | Obsidian Volt  | `#B07362` | `#6F8AA8` | `#C7A063` |
  | Void Pulse     | `#AE7290` | `#7E89AE` | `#C9A368` |
  | Crimson Dojo   | `#B07560` | `#6F8AA8` | `#C9A363` |
  | Malachite Core | `#A8855C` | `#6F8AA8` | `#C9A063` |

  (Tuned so each macro reads as a distinct muted tone on the
  respective theme's `surface`. Slight hue rotations per theme
  keep the palette tuned to each surface. Final hex values are
  chosen at implementation time so contrast on each `surface`
  reads correctly; these starting values are illustrative.)

##### 2. Create the new card widget
File: `lib/features/home/widgets/nutrition_summary_card.dart` (NEW)

Public class: `NutritionSummaryCard extends StatelessWidget`.

```dart
class NutritionSummaryCard extends StatelessWidget {
  final int consumedCalories;
  final int? targetCalories;
  final int proteinKcal;
  final int carbsKcal;       // todayNetCarbsKcal from NutritionState
  final int fatKcal;
  final VoidCallback onTap;

  const NutritionSummaryCard({
    super.key,
    required this.consumedCalories,
    required this.targetCalories,
    required this.proteinKcal,
    required this.carbsKcal,
    required this.fatKcal,
    required this.onTap,
  });
}
```

Build (happy state):
1. Outer `Padding(EdgeInsets.symmetric(horizontal: 16, vertical: 12))`
   so the card is inset from the screen edges (matches the tile
   grid's 16 px side margin).
2. `Material` (type: `transparency`) → `InkWell(onTap: onTap)` →
   `Ink(decoration: BoxDecoration(color: themeColors.surface,
   borderRadius: BorderRadius.circular(OmniTheme.surfaceBorderRadius),
   border: Border.all(color: themeColors.surfaceBorder,
   width: OmniTheme.surfaceBorderWidth),
   boxShadow: [OmniTheme.deepShadow]))`.
3. Inner `Padding(EdgeInsets.fromLTRB(16, 12, 16, 14))` so the
   content has breathing room from the card border.
4. Top row (`Key('nutrition_card_headline')`):
   - `Row(crossAxisAlignment: CrossAxisAlignment.center)`
   - Left: small `Icon(Icons.local_dining_outlined, size: 18,
     color: themeColors.textDominant)` (the "X" placeholder in
     the mockup; dining icon is already in the project icon set
     and was used in the prior strip)
   - 8-px `SizedBox`
   - Center: headline `Text('${consumed} / ${target} Cal')` with
     `theme.textTheme.headlineSmall` + `FontWeight.w800` +
     `themeColors.textDominant` (the brightest text on the card;
     hero emphasis)
   - `Spacer()`
   - Right: `Icon(Icons.chevron_right, size: 22,
     color: themeColors.textDominant)` (visual cue only)
5. Middle row (`Key('nutrition_card_gauge')`): `SizedBox(height: 8)`
   gap, then a `LayoutBuilder`-wrapped `Stack`:
   - Layer 1: the `track` (full-width rounded rectangle, height
     ~10 px, color `themeColors.divider`).
   - Layer 2: the `fill` (`ClipRRect` over a `Row` of three
     `Container`s with widths proportional to macro kcals / total
     macro kcal; fill width clamped to track width; fill colored
     with `themeColors.stripMacros.{protein,carbs,fat}`).
6. Bottom row (`Key('nutrition_card_caption')`): `SizedBox(height: 8)`
   gap, then `Row(mainAxisAlignment: MainAxisAlignment.spaceBetween)`
   of three `(colorMarker, percent)` groups:
   - Each group: `Row(mainAxisSize: MainAxisSize.min, children: [
     small dot `Container(width:8, height:8, decoration: BoxDecoration(
     color: stripMacros.<slot>, shape: BoxShape.circle)),
     SizedBox(width: 6),
     Text('P 42%' or '—', style: labelSmall + textSecondary + w600),
     ])`.
   - Percentage text uses `tabularFigures()` so digits don't reflow.

Empty state (S-104, when `consumedCalories == 0`):
- Same chrome, same headline format `"0 / ${target ?? 0} Cal"`,
  but the figure text is `themeColors.textMuted` (not the hero
  emphasis tone), and the gauge area renders the empty track
  only (no fill `Layer 2`). The caption row shows DASHES
  (`'—'`) for each macro percentage.

Over-budget state (S-105, when `consumedCalories > targetCalories`):
- Same chrome. Headline text color switches to
  `Theme.of(context).colorScheme.error` (the theme's restrained
  warning tone). Fill is clamped at 100% of the track width.
  Caption percentages still render (no dashes) because the data
  is real.

Keys (for widget-test probes):
- `nutrition_card` — the outer `Material` (one tap target).
- `nutrition_card_headline` — the headline `Row`.
- `nutrition_card_gauge_track` — the track `Container`.
- `nutrition_card_gauge_fill` — the fill `Row` (clipped).
- `nutrition_card_gauge_segment_<i>` — each of the three segment
  `Container`s (`i` ∈ {0, 1, 2}).
- `nutrition_card_caption_protein`,
  `nutrition_card_caption_carbs`,
  `nutrition_card_caption_fat` — the three caption `Text`s.
- `nutrition_card_chevron` — the right-edge chevron `Icon`.

##### 3. Delete the old strip widget
File: `lib/features/home/widgets/nutrition_strip_bar.dart` (DELETE)
- Class `NutritionStripBar`, supporting `StripSegment`,
  `_EmptyStrip`, `_FilledStrip`, `_GapLabel`, `_SegmentLabels`,
  `_SegmentLabel`, `_SegmentedBar`, `_SegmentedFillPainter`, and
  `NutritionStripBarMetrics` all go.
- (The Phase 4 placeholder `nutrition_strip_button.dart` was
  already deleted per Phase 4.1 step 3.)

##### 4. Update `HomeScreen`
File: `lib/features/home/home_screen.dart`

- Remove `import 'widgets/nutrition_strip_bar.dart';`.
- Add `import 'widgets/nutrition_summary_card.dart';`.
- In the `body: Stack(children: [Column(...), _buildMaintenanceSheet(...)])`:
  - Replace the `Expanded(flex: 2, child: ListenableBuilder(listenable:
    widget.nutritionState, builder: ... NutritionStripBar(...)))` with
    `Padding(padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
    child: NutritionSummaryCard(...))`.
  - The card sits BELOW the existing `SizedBox(height: 16.0 * 2)` top
    gap (the gap stays — it's the visual break between the tile grid
    and the card).
  - The card is INSET (16 px horizontal) instead of full-bleed, so it
    sits inside the screen margin like the training tiles.
  - Pass today's consumed + target + macro kcals from `NutritionState`
    (same props the prior strip used; no state-shape change).
  - Keep `_openNutritionScreen` — the card's `onTap` uses it.
- The card is always tappable; no `isCurrent` route gate (the prior
  gate was removed in Phase 4.1).

##### 5. Rewrite tests
Rename `test/home_nutrition_strip_test.dart` →
`test/home_nutrition_summary_card_test.dart`. Replace ALL of the
existing scenarios (S-050b through S-058) with the new
S-100..S-106 scenarios above. Per test file mapping rules:
- All scenarios map to widget tests (rendering +
  interaction) → live in `test/home_nutrition_summary_card_test.dart`.

Test contents:
- `group('NutritionSummaryCard — happy state (S-100)')`:
  - Pump with `consumed=643`, `target=2000`, macro kcals
    `(270, 211, 162)` (sum = 643; P/C/F = 42 / 33 / 25).
  - Expect headline `Text('643 / 2,000 Cal')` to find one widget.
  - Expect `find.byKey(Key('nutrition_card_headline'))` finds one.
  - Expect caption row to show `P 42%`, `C 33%`, `F 25%`.
- `group('NutritionSummaryCard — body tap opens nutrition (S-101)')`:
  - Pump card with `onTap` callback.
  - `tester.tap(find.byKey(Key('nutrition_card')));` (tap on the
    card body, NOT the chevron).
  - Expect `onTap` callback fired.
  - Variant: `tester.tap(find.byKey(Key('nutrition_card_headline')));`
    (tap on the headline, not the chevron).
- `group('NutritionSummaryCard — gauge fill proportion (S-102)')`:
  - Pump with `consumed=1200`, `target=2000`, synthetic macros.
  - Read the fill `RenderBox` width and the track `RenderBox` width.
  - Assert `fillWidth / trackWidth ≈ 0.6` (±0.5 px rounding drift).
- `group('NutritionSummaryCard — macro segments share of consumed
  (S-103)')`:
  - Pump with `protein=400, carbs=400, fat=400, consumed=1200`.
  - Read each segment's `RenderBox.size.width`.
  - Assert each segment width ≈ `fillWidth / 3` (±0.5 px).
  - Assert the three widths sum to the fill width (±0.5 px).
  - Guard test: assert the segments are NOT proportional to the
    full bar (e.g., a `1/3` share of the full bar would be much
    smaller than `1/3` of the fill).
- `group('NutritionSummaryCard — empty state (S-104)')`:
  - Pump with `consumed=0`.
  - Expect headline `'0 / 2,000 Cal'` (the figure DOES render
    — it's the empty state, not a missing-card state).
  - Expect gauge fill `RenderBox` width == 0 (or fill widget
    absent — implementation choice).
  - Expect caption row shows dashes: `find.text('—')` finds
    THREE widgets (one per macro).
  - Assert NONE of `find.text('P 0%')`, `find.text('C 0%')`,
    `find.text('F 0%')` is present (no `0%` placeholders).
  - Assert the card is still tappable (tap → onTap fires).
- `group('NutritionSummaryCard — over-budget (S-105)')`:
  - Pump with `consumed=2450`, `target=2000`, synthetic macros.
  - Expect the fill `RenderBox.size.width` ≤ track `RenderBox.size.width`
    (clamped to 100%).
  - Expect the headline text `Text` widget resolves to a
    `TextStyle` whose `color` is `Theme.of(context).colorScheme.error`
    (or the warning tone token — implementation choice).
  - Capture `tester.takeException()`; assert null (no `RenderFlex`
    overflow).
  - Assert caption percentages are NOT dashes (real percentages).
- `group('NutritionSummaryCard — training tiles unchanged (S-106)')`:
  - Pump the full `HomeScreen` (mirror the helper in
    `test/home_nutrition_strip_test.dart`).
  - Expect `find.byType(EnergyTile)` to find SIX widgets.

Existing `MockWorkoutRepository` helpers (`_freshRepo`,
`_freshRepoCleanConsumed`) are reused. The existing
`_seedChicken` helper is reused. The `_buildFixture` helper is
reused. The `_buildHomeScreen` helper is reused.

Helpers:
- `_pumpCard` — wraps the card in a `MaterialApp` + `Scaffold` with
  a known surface size (default 360 × 600 — phone-sized) for the
  geometry-proportion assertions.

##### 6. Update docs
- `docs/widget_catalog.md`:
  - Remove the existing `NutritionStripBar` entry.
  - Add a new `NutritionSummaryCard` entry with the prop table,
    design tokens (rounded corners via `OmniTheme.surfaceBorderRadius`,
    hairline border, deep shadow, inset padding 16 px), muted macro
    palette reference, and behavior summary.
- `docs/navigation_and_screens.md`:
  - Update the `HomeScreen` row to describe the new card (inset,
    raised, single tap target) and remove all references to the
    Phase 4.1 `NutritionStripBar` geometry.

### Implementation Steps
1. [ ] Phase 0 — author plan (this block).
2. [ ] Phase 1 — confirm data layer unchanged; no edits.
3. [ ] Phase 2.1 — add `stripMacros` palette + values per theme to
       `omni_theme.dart`.
4. [ ] Phase 2.2 — write `test/home_nutrition_summary_card_test.dart`
       with the S-100..S-106 tests (red — widget does not exist yet).
5. [ ] Phase 2.3 — run new tests; confirm they fail (red gate).
6. [ ] Phase 2.4 — create `lib/features/home/widgets/nutrition_summary_card.dart`
       with the card implementation.
7. [ ] Phase 2.5 — delete `lib/features/home/widgets/nutrition_strip_bar.dart`.
8. [ ] Phase 2.6 — update `lib/features/home/home_screen.dart` to mount the
       new card (inset layout, no `Expanded(flex: 2)`, no full-bleed).
9. [ ] Phase 2.7 — run targeted test set; iterate until green.
10. [ ] Phase 2.8 — run full test suite (`flutter test`) — no regressions.
11. [ ] Phase 2.9 — update `widget_catalog.md` and `navigation_and_screens.md`.
12. [ ] Phase 3 — code review.

### Progress
- [x] Phase 0: Plan written
- [x] Phase 1: Data layer — confirmed no changes
- [x] Phase 2.1: `stripMacros` palette added to OmniTheme
- [x] Phase 2.2: Tests written (red)
- [x] Phase 2.3: Red gate confirmed
- [x] Phase 2.4: `NutritionSummaryCard` widget created
- [x] Phase 2.5: Old strip widget deleted
- [x] Phase 2.6: `HomeScreen` updated to mount the new card
- [x] Phase 2.7: Targeted tests green
- [x] Phase 2.8: Full test suite green (no regressions)
- [x] Phase 2.9: Docs updated
- [x] Phase 3: Code review (one critical issue found and fixed in this pass)

### Feedback
(none yet — pipeline in progress)

### Phase 5.0 Complete ✓
Plan authored. Proceeding to Phase 1 (data layer — no changes
needed) and Phase 2 (implementation + tests).

### Phase 5.1 — TDD red gate ✓

`flutter test test/home_nutrition_summary_card_test.dart`:
fails to load — the new `NutritionSummaryCard` widget does
not exist yet. `flutter analyze` reports three missing-symbol
errors (the import path, two `NutritionSummaryCard` references
in the test file). This is the correct kind of red — the
implementation is missing, not the test infrastructure.

`flutter analyze lib/core/constants/omni_theme.dart` after
the `stripMacros` palette addition: clean (no issues). The
new palette slot is wired into all six themes.

### Phase 5.2 — Implementation + green gate ✓

- **`lib/features/home/widgets/nutrition_summary_card.dart`**
  (NEW): pure-presentation `StatelessWidget` with the
  `consumedCalories` / `targetCalories` / `proteinKcal` /
  `carbsKcal` / `fatKcal` / `onTap` API. Card chrome
  routes through `OmniSurface` (Phase 5.2 review follow-up
  — initially re-declared `BoxDecoration` chrome, refactored
  to `Material(transparency) > InkWell(borderRadius) >
  OmniSurface(padding)` so the global-conventions rule
  "Every outlined card must route through `OmniSurface`"
  is honored). Headline row uses
  `theme.textTheme.headlineSmall` + `FontWeight.w800` +
  `textDominant` (the only element that earns white
  emphasis). Gauge row is a `Stack` of `track` (divider
  color, full width) and a clipped `Row` of three macro
  `Container`s sized as a share of CONSUMED calories
  (S-103). Caption row is a `spaceBetween` `Row` of three
  `(colorMarker, "M N%")` groups. Empty state (S-104)
  renders `"0 / {target} Cal"` with dashes in the caption
  row. Over-budget state (S-105) switches the headline
  text color to `colorScheme.error` and clamps the fill
  at 100% of the track.
- **`lib/features/home/widgets/nutrition_strip_bar.dart`**:
  DELETED (Phase 4.1 `NutritionStripBar` superseded).
- **`lib/features/home/widgets/nutrition_strip_button.dart`**:
  DELETED (Phase 2 placeholder, no references in
  `lib/` or `test/`).
- **`lib/features/home/home_screen.dart`**: replaced the
  `Expanded(flex: 2, child: ... NutritionStripBar ...)` with
  a `Padding(EdgeInsets.only(bottom: 12), child: ListenableBuilder
  (nutritionState, NutritionSummaryCard(...)))`. Outer
  `Expanded(flex: 15)` for the tile grid → `Expanded` (no
  flex ratio; the card is content-sized). Imported
  `nutrition_summary_card.dart` instead of
  `nutrition_strip_bar.dart`.
- **`test/home_nutrition_strip_test.dart`**: DELETED (the
  Phase 4.1 test file).
- **`test/home_nutrition_summary_card_test.dart`** (NEW): 21
  tests across 7 groups (S-100..S-106 + a live-update group).
  All 21 pass on `flutter test`. The S-106 geometry
  assertion (gap between the last tile and the card top) is
  `greaterThanOrEqualTo(32)` rather than `equals(32)` because
  the `CustomScrollView` viewport may have additional empty
  space below the grid content (3 rows of 171 px + 2 gaps of
  16 px = 545 px content in a 579 px viewport) — the 32 px
  `SizedBox` is the design contract, not the visible gap.
  The test pumps a 390 × 844 surface (iPhone-sized) so all
  six `EnergyTile` widgets are mounted.
- **Doc hygiene**:
  - `docs/widget_catalog.md`: removed the
    Phase 4.1 `NutritionStripBar` section, added a new
    `NutritionSummaryCard` section with the prop table, design
    tokens, and behavior contract. Updated the home-screen
    "Note on home-screen nutrition strip" to point at
    `nutrition_summary_card.dart` and `NutritionSummaryCard`.
  - `docs/navigation_and_screens.md`:
    rewrote the `HomeScreen` row to describe the new
    gauge card (inset, raised, single tap target) and
    removed all references to the Phase 4.1
    `NutritionStripBar` geometry. Fixed the "3×3" tile-grid
    dimension typo to "2×3" (the grid is `crossAxisCount: 2`
    with 4 + 2 tiles).
- **Full test suite**: `flutter test` — **1670 passed, 5
  skipped, 0 failed**. No regressions.

### Phase 5.3 — Code review ✓

Code review verdict: ✅ APPROVED (one critical issue found
and fixed in the same pass). See "Code Review" section
below for the full report.

### Phase 5.3 Complete ✓
Review complete. Iteration 5 ready to ship.

### Code Review: ✅ APPROVED

Layers in scope: **core** (OmniTheme), **widgets**
(NutritionSummaryCard), **features** (HomeScreen), **docs**
(widget_catalog, navigation_and_screens).
Layers skipped: models, repositories, state.

PASS (7 rules): theme-tokens-only, surfaceBorderRadius +
surfaceBorderWidth + deepShadow from OmniTheme, `Material
+ InkWell` over `OmniSurface` for the outlined-card
chrome, `OmniCardHeader` rule N/A (no section header on
the card), effort-kind N/A (no analytics in widget),
timestamps N/A (no timestamp handling), reuse-canonical-
owner (OmniSurface primitive + theme tokens), instrument-
panel-not-influencer (restrained card, no decorative
elements, muted palette).
N/A (1 rule): units-and-canonical-storage (no unit-displaying
values in the widget).
FAIL: card-chrome-via-OmniSurface — **fixed in this pass**
(see below).

Critical: 0 (after fix). Warnings: 0. Suggestions: 0.

**Findings (one line each)**:
- 🟡 RESOLVED | `lib/features/home/widgets/nutrition_summary_card.dart:74-89`
  (initial) | The card chrome re-declared `BoxDecoration` (surface
  fill, border, radius, shadow) instead of routing through
  `OmniSurface` — violates the global-conventions rule
  "Every outlined card must route through `OmniSurface`".
  | Refactored to `Padding > Material(transparency) > InkWell
  (borderRadius: surfaceBorderRadius) > OmniSurface(padding)
  > Column`. The `Material` provides the `InkWell` host;
  the `InkWell` has its own `borderRadius` so the splash
  is clipped to the card's rounded corners; the chrome
  (border, radius, shadow, surface fill) now routes through
  `OmniSurface` per the convention. All 21 widget tests
  still pass. | @developer (resolved in this pass)

**Doc hygiene**:
- `navigation_and_screens.md` — ✅ Updated.
- `state_management.md` — ✅ N/A (no state changes).
- `widget_catalog.md` — ✅ Updated.
- `data_models.md` — ✅ N/A (no model changes).
- `db_integration.md` — ✅ N/A (no repository changes).

**Test coverage**:
- 21/21 new widget tests pass.
- 1670/1675 full suite (5 pre-existing skips) — no
  regressions.
- All S-100..S-106 scenarios mapped to ≥1 test.
- All four "Update existing tests" requirements (full-bleed
  → inset, white block → muted surface, arrow-only tap →
  full body tap, saturated colors → muted) addressed by
  rewriting `home_nutrition_strip_test.dart` →
  `home_nutrition_summary_card_test.dart` from scratch.
- The "wrong mental model" fix (segments as share of
  CONSUMED, not share of full bar) is enforced by the
  S-103 tests `segments sum to the fill width and not to
  the track width` and `42 / 33 / 25 macro split → segments
  proportional to consumed`.

**Environment safety**: no `dart:io`, no SQLite imports in
shared code, no `Platform.is*` checks. Repository interface
unchanged.

---
