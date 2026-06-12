# Widget Catalog

## Overview

Reusable UI components live in `lib/widgets/` and are organized by purpose. All widgets follow these conventions:
- Presentation-only (no repository or service access)
- Local UI state only (e.g., `_isPressed`, animation controllers)
- Design tokens from `OmniTheme` (never hardcoded colors/sizes)

Note on resume dialog:
- The cold-start `Unfinished Session` dialog is implemented as a private, screen-local widget in `HomeScreen` (`_ResumeSessionDialog`).
- It is intentionally not promoted into `lib/widgets/` because it is feature-specific and not reused across screens.

Note on home-screen nutrition strip:
- The home-screen footer strip is implemented as a screen-local widget in `lib/features/home/widgets/nutrition_strip_bar.dart` (`NutritionStripBar`).
- It is feature-scoped (only the home screen needs it) but is still presentation-only and theme-reactive. Phase 4.1 (D-8) supersedes the Phase 4 (D-5) two-row layout with a full-strip bar where the surface is the track; the previous placeholder `NutritionStripButton` widget was removed.

---

## Directory Structure

```
lib/widgets/
├── buttons/              # (empty — reserved for future button components)
├── cards/                # Tile and card components for the home screen
├── layout/               # Foundational layout primitives
├── logo/                 # Brand elements (Zen Halo)
├── models/               # Presentation-layer data classes
├── pickers/              # Selection dialogs
└── session/              # Workout session metric widgets
```

---

## Layout Primitives

### `OmniGradientBackground`

**File**: `lib/widgets/layout/omni_gradient_background.dart`

Full-screen cosmic gradient backdrop used on every screen.

| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `child` | `Widget` | required | Content to overlay |
| `showRadialHighlight` | `bool` | `true` | White radial glow at top-center |

**Layers** (bottom to top):
1. Vertical linear gradient (`backgroundGradientTop` → `backgroundGradientBottom`)
2. Optional radial white highlight (10% opacity)
3. Optional film-grain noise overlay (`NoiseOverlayPainter`) — controlled by `OmniTheme.enableBackgroundNoise`

### `OmniBackHeader`

**File**: `lib/widgets/layout/omni_back_header.dart`

Standardized back-and-title header used by all secondary screens. Implements `PreferredSizeWidget` so it slots directly into `Scaffold.appBar`.

| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `title` | `String` | required | Primary header text |
| `subtitle` | `String?` | `null` | Optional second line below the title in `bodySmall` + `OmniTheme.colors.textSecondary` |
| `onBack` | `VoidCallback?` | `null` | Called on back arrow tap; defaults to `Navigator.of(context).pop()` |
| `actions` | `List<Widget>?` | `null` | Trailing widgets forwarded to `AppBar.actions` |

**Behavior**:
- `preferredSize` is always `Size.fromHeight(kToolbarHeight)` (56 px)
- `backgroundColor` and `surfaceTintColor` are `Colors.transparent`, `elevation: 0` — gradient background shows through
- Back arrow color: `OmniTheme.colors.textDominant` (never inherits from theme's `foregroundColor`)
- `titleTextStyle`: `titleLarge` + `FontWeight.w600` + `OmniTheme.titleLetterSpacing` (0.4) + `OmniTheme.colors.textDominant`
- Screens must set `extendBodyBehindAppBar: true` on their `Scaffold` for the gradient to render behind the transparent header

**Usage notes**:
- Calendar uses `actions: [FilledButton('+')]` for the Periods shortcut
- `SessionSummaryScreen` uses `actions: [PopupMenuButton]` for the Edit/Save/Discard overflow
- `SessionOverviewScreen` and `RoutineSetupScreen` use `subtitle` for contextual secondary text

### `OmniSurface`

**File**: `lib/widgets/layout/omni_surface.dart`

Base container for all cards and panels. Dark navy with border + shadow.

| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `child` | `Widget` | required | Content |
| `padding` | `EdgeInsets?` | `null` | Optional inner padding |
| `showShadow` | `bool` | `true` | Deep shadow toggle |

Uses `OmniTheme.colors.surface`, `surfaceBorderRadius`, `OmniTheme.colors.surfaceBorder`, `surfaceBorderWidth`, `deepShadow`.

### `OmniBottomCTA`

**File**: `lib/widgets/layout/omni_bottom_cta.dart`

Shared full-width bottom call-to-action used by screens with a single persistent footer action.

| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `label` | `String` | required | Button text; a leading `+` triggers the shared add affordance |
| `onPressed` | `VoidCallback?` | required | Tap handler; `null` disables the CTA |
| `isDestructive` | `bool` | `false` | Uses the active theme’s destructive/error colors |

**Behavior**:
- Fixed height: `OmniTheme.buttonPrimaryHeight`
- Fixed radius: `OmniTheme.buttonBorderRadius`
- Footer-safe spacing via `SafeArea(top: false)` with shared padding
- Theme-reactive fade gradient behind the button using `colorScheme.surface`
- Prevents per-screen CTA styling drift by centralizing footer layout and colors

### `NoiseOverlayPainter`

**File**: `lib/widgets/layout/noise_overlay_painter.dart`

`CustomPainter` that renders a subtle film-grain texture over the gradient background. Creates a premium aesthetic without being distracting.

---

## Home Screen Cards

### `EnergyTile`

**File**: `lib/widgets/cards/energy_tile.dart`

Primary home-screen modality tile. `StatefulWidget` with press-scale animation. Renders one of two visual tiers (primary or secondary) and optionally an active-state pulse dot.

| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `title` | `String` | required | Tile label (e.g., "Cardio / Endurance") |
| `icon` | `IconData?` | `null` | Tile icon (use when `iconWidget` is null) |
| `iconWidget` | `Widget?` | `null` | Custom icon widget (e.g. `OverheadPressIcon`) |
| `accentColor` | `Color` | required | Per-tile accent color (used for fill, glow, label) |
| `onTap` | `VoidCallback` | required | Tap handler |
| `isSecondary` | `bool` | `false` | Secondary-tier rendering (8% fill, 56-pt icon at white @ 75%, no rim/shadow). Used for Free and Routines. |
| `isActive` | `bool` | `false` | Highlights when session matches this modality; renders the pulsing "Workout in progress" dot. |

**Behavior**:
- Press scale: `OmniTheme.pressedScale` (0.96) with 180ms animation.
- Solid low-opacity accent fill (primary ~18%, secondary ~8%) — no gradient.
- Primary tier: 1-px white top rim highlight (white @ 8%) + 1-px black bottom inner shadow (black @ 20%), full width, clipped to the 20-pt rounded corners.
- Secondary tier: no rim highlight, no inner shadow, no drop shadow.
- Active state: enhanced accent-color glow (blur 48/28, no animation) + a small pulsing white dot (~8-pt, top-right ~10-pt inset) that animates opacity 80% → 100% → 80% over a 1.8-s `TweenSequence` cycle. Dot is decorative (`ExcludeSemantics`); tile announces `<title>, Workout in progress` via `Semantics`.
- Content layout: `Positioned.fill` + `Column` with `Expanded(flex: 3)` for the icon band and a fixed `Padding(bottom: 12)` for the label — the label baseline is anchored to a fixed bottom offset so it does not float when the icon size changes.
- Responsive: text labels hide below 100-px width via `LayoutBuilder`.

### `EnergyCore`

**File**: `lib/widgets/cards/energy_core.dart`

Circular icon widget inside `EnergyTile`. Radial gradient background with glow shadow.

| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `icon` | `IconData` | required | Center icon |
| `gradientColors` | `List<Color>` | required | Radial fill |
| `glowColor` | `Color` | required | Outer glow |
| `isActive` | `bool` | `false` | Glow intensity boost |
| `size` | `double` | `OmniTheme.energyCoreSize` | Circle diameter |

### `MaintenanceTile`

**File**: `lib/widgets/cards/maintenance_tile.dart`

Small tile used inside the home screen's maintenance bottom sheet for system features (Profile, Stats, Settings). Simpler styling than `EnergyTile`.

### `OmnitrainCategoryTile` / `WorkoutCategoryCard`

**Files**: `lib/widgets/cards/omnitrain_category_tile.dart`, `lib/widgets/cards/workout_category_card.dart`

Legacy/alternative tile implementations. May be deprecated stubs — check code for current usage.

### `ModalityTileWidget`

**File**: `lib/widgets/cards/modality_tile_widget.dart`

**DEPRECATED.** Returns `SizedBox.shrink()`. Replaced by `EnergyTile`.

---

## Home Screen Footer

### `NutritionStripBar`

**File**: `lib/features/home/widgets/nutrition_strip_bar.dart`

Full-height footer bar on the home screen (D-8 / S-050b / S-051..S-057 — supersedes the Phase 4 D-5 two-row layout). Sits below the training-tile grid with top gap = 2 × `standardGridSpacing` and extends to the physical bottom edge of the screen; the strip's `Material`/`Ink` decoration lives outside the inner `SafeArea(top: false)` so the track background reaches the bottom edge while the content (label / empty message) respects the bottom home-indicator inset. The fixed content height is `NutritionStripBarMetrics.contentHeight` (default 64 px, tunable per D-8). Pure presentation — no state access, no business logic, no math. All colors come from `OmniTheme.colors`; per-macro calorie math lives on `NutritionState` (D-4 getters) and is passed in.

| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `consumedCalories` | `int` | required | Today's consumed calories (already rounded by the caller) |
| `targetCalories` | `int?` | required | Today's calorie target, or `null` for "no goal" |
| `proteinKcal` | `int` | required | Protein calorie contribution (D-4: `protein × 4`) |
| `totalCarbsKcal` | `int` | required | Total-carbs calorie contribution (D-8 inherits D-5: "total-carb calories for blue", not net carbs) |
| `fatKcal` | `int` | required | Fat calorie contribution (D-4: `fat × 9`) |
| `onTap` | `VoidCallback` | required | Tap handler — the strip is always tappable (S-051) |
| `emptyMessage` | `String` | `'Track your nutrition — tap to start'` | Copy for the empty state |
| `segmentsOverride` | `List<StripSegment>?` | `null` | Optional pre-built segment list. The default constructs Protein / Carbs / Fat segments in that order with `OmniTheme.colors.macroChart.<slot>` colors. Tests use this to inject custom labels or colors. |

**Public helper class** `StripSegment` carries a per-macro segment: `kcal` (calorie contribution), `color` (from the macro chart palette), and `label` (the prefix rendered inside the segment, e.g. `"P"`).

**Design tokens** — `NutritionStripBarMetrics`:
- `contentHeight` (default 64 px): the strip's full painted height. All in-strip measurements (label-fit budget, chevron depth) derive from this constant. Tunable per D-8.
- `chevronReserve` (default 12 px): the trailing segment's right-edge clearance so the in-segment label does not collide with the arrow tip.

**Behavior (D-8)**:
- **Geometry**: the whole strip IS the bar. The strip is a single full-height region; the surface is the track. The fill (when present) is painted inside the strip; the track visibly continues past the fill to 100% (S-050b).
- **Empty state** (S-051): when `targetCalories == null || targetCalories <= 0 || consumedCalories <= 0`, renders a single centered inviting message. No bar, no numbers. The surface is still tappable.
- **Happy state** (S-050b / S-052 / S-053):
  - Calorie label `"{consumed} / {target} cal"` (comma-grouped thousands) overlays top-left in one line with the chevron-right at top-right. Both carry a dark text-shadow contrast treatment (D-8) so the label is legible over the fill and the track.
  - Fill width = `min(consumed / target, 1.0) × stripWidth` (S-052). The fill is subdivided P → C → F by calorie contribution (D-4 math, total carbs for blue) with **straight vertical interior segment boundaries**. ONLY the fill's leading (right) edge is chevron-shaped; the chevron is carried by the trailing segment.
  - Each segment shows `"{M} {pct}%"` inside; the label is measured against the segment pixel width via `TextPainter` (via the same `_SegmentLabel` math) and hidden when it doesn't fit (S-053). The D-8 full-strip content height widens the label-fit budget substantially — the v1 14-px-tall floating-pill failure case (S-050b) cannot recur.
- The widget never picks a color of its own — `OmniTheme.colors.macroChart.{protein,netCarbs,fat}` (where `netCarbs` fills the carbs slot per the D-5 / D-8 spec).
- Tap on any region calls `onTap`. The empty state does NOT disable the surface.
- Hairline top border (1 px `surfaceBorder`); NO upward drop shadow over the tile grid.

---

### `NutritionSummaryCard`

**File**: `lib/features/nutrition/widgets/nutrition_summary_card.dart`

A card that displays the user's current daily nutrition targets as
"goal" lines (e.g., `Calories: 2500`).

| Prop | Type | Description |
|---|---|---|
| `nutritionState` | `NutritionState` | Source of the current target. Required. |

**Behavior**:
- Displays a title "Daily Targets".
- Renders one row per non-zero macro (`Calories`, `Protein`, `Carbs`,
  `Fat`). Macros whose target is `0.0` are hidden — they would otherwise
  render as `0 / 0` and trip the "no goal" / division-by-zero guard.
- Renders "No nutrition targets set." when `nutritionTarget` is `null`
  or `isUnset` (all four macros are `0.0`).
- Reads only the target side of `NutritionState`; the calorie ring on
  the page above owns the consumed-vs-target visualization.

### `CalorieRing`

**File**: `lib/features/nutrition/widgets/calorie_ring.dart`

Pure-presentation donut widget for the top of the nutrition page. Paints
a track + filled arc and centers a label column with today's consumed
calories vs the daily target.

| Prop | Type | Default | Description |
|---|---|---|---|
| `consumed` | `double` | required | Today's consumed calories (non-negative). Fractional values are rounded for display. |
| `target` | `double?` | required | Daily calorie target. `null` OR `<= 0` means consumed-only mode (no goal arc). |
| `size` | `double` | `160` | Outer diameter in logical pixels. |
| `strokeWidth` | `double` | `14` | Track and arc stroke width. |
| `emptyHint` | `String` | `'Log a food to start filling'` | Subtext shown when consumed is zero (both target set and target unset). |
| `centerOverride` | `Widget?` | `null` | Optional widget to render in the ring's center in place of the default calories text. When `null` (the default), the ring renders its standard `consumed / target kcal` view. When non-null, the override is shown in the same centered column and the default calories text is hidden. An internal `AnimatedSwitcher` cross-fades the swap. Used by `CalorieRingCard` to show a focused macro's `MacroFocusContent` while a section is focused. |

**Behavior**:
- Renders four label branches in the center column:
  - Target set + consumed > 0: `"<consumed> / <target> kcal"` and a
    secondary `"over by N"` caption when consumed > target.
  - Target set + consumed == 0: `"0 / <target> kcal"` with the
    `emptyHint` subtext.
  - Target null + consumed > 0: `"<consumed> kcal"` with `"no goal set"`
    subtext.
  - Target null + consumed == 0: `"0 kcal"` with the `emptyHint` subtext.
- Fill fraction is `consumed / target` clamped to `0..1` (no overflow
  past the track). The numeric label still shows the real `consumed`
  value so the user can see they exceeded the target.
- Track color: `OmniTheme.colors.divider`. Arc color:
  `OmniTheme.colors.primary`. No hardcoded colors.
- Numbers use `FontFeature.tabularFigures()` for stable column
  alignment, comma-grouped via an in-widget helper.
- Wraps the painter + label in a `Semantics(container: true, label: ...)`
  node announcing `"Calories: X of Y"` (or `"X, no goal set"`).
- Pure presentation — no `BuildContext` lookups, no repository access,
  no business logic. All math is local; safe to use in tests with no
  extra setup.

### `CalorieRingCard`

**File**: `lib/features/nutrition/widgets/calorie_ring_card.dart`

`Card` wrapper around `CalorieRing` for the top of `NutritionScreen`.
Hosts the section title ("Today") and a small edit-targets icon button
in the card's top-right corner. Reads consumed + target data from the
injected `NutritionState` and rebuilds on every notification. Owns the
**focus state** that drives the macro-donut tap-to-focus interaction.

| Prop | Type | Description |
|---|---|---|
| `nutritionState` | `NutritionState` | Source of today's target and consumed-foods cache. Required. |
| `onEditTap` | `VoidCallback` | Tap handler for the edit icon. The widget does not navigate itself — the parent screen owns the routing contract. |

**Behavior**:
- Treats `nutritionTarget.calories == 0` (or a `null` target) as
  "no goal" so the ring renders consumed-only.
- Composes the new `MacroDonutChart` (outer) with the existing
  `CalorieRing` (inner) in a `Stack` so the calorie ring sits inside
  the macro donut's hollow center. The donut **hides** when no macros
  are logged (sum of the four macro grams is 0) — the calorie ring
  stays visible alone at its full 160 px size. The macro donut sits on
  top of the calorie ring in the `Stack` so its `GestureDetector` owns
  hit testing for the entire chart area; the calorie ring is never the
  tap target.
- **Tap-to-focus** (Iteration 2, S-008..S-014): the card owns the
  focused-section index. Tapping a section focuses it; tapping the same
  section again, or tapping the empty center, deselects. The card passes
  per-section opacities (1.0 for the focused section, 0.4 for the rest —
  tuned per the Q&A as a mild fade so all sections remain readable) to
  the donut, wraps the calorie ring in `AnimatedOpacity(opacity: 0.4)`
  when a section is focused, and passes a `MacroFocusContent` as the
  ring's `centerOverride`. The ring cross-fades to the override via its
  built-in `AnimatedSwitcher`. On first paint, no section is focused —
  the donut is at full opacity, the ring is at full opacity, the center
  shows calories (the existing default). When the focused section's
  grams drop to 0 (e.g. the user deletes the only protein food), the
  card's focus falls back to `null` and the default state returns.
- The four macro grams are read from `NutritionState`:
  `protein = todayConsumedProtein`,
  `netCarbs = max(0, todayConsumedCarbs - todayConsumedFiber)`,
  `fiber = todayConsumedFiber`, `fat = todayConsumedFat`.
- Edit icon (`Icons.tune`, `Key('edit_targets_icon')`, tooltip "Edit
  targets") lives in the top-right of the card. The icon button has an
  explicit `shape:` override (`OmniTheme.buttonIconRadius` = 10) to
  avoid Material 3's default `StadiumBorder`. The icon is **not** part of
  the focus state — tapping it navigates to the targets editor as before.
- `ListenableBuilder` over `nutritionState` — every `notifyListeners()`
  (target load/save, consumed-food load, log/delete) rebuilds the ring
  and the donut. The focus survives a rebuild as long as the focused
  section still has non-zero grams (S-013); it clears if the section
  disappears (S-014), but does not flicker because the fallback is a no-op.
- Pure presentation — no repository access, no business logic.

### `MacroDonutChart`

**File**: `lib/features/nutrition/widgets/macro_donut_chart.dart`

Interactive donut widget that wraps the calorie ring on the daily
nutrition screen. Renders up to four colored arc sections — **Net
Carbs** (blue), **Fiber** (green), **Fat** (yellow), **Protein**
(white) — in fixed visual order. **Iteration 2** removed the
external labels and made the donut thicker (`strokeWidth` default
raised from 14 to 36, ~2.5× the calorie ring's stroke) and
**tap-to-focusable**: tapping a section focuses it. The chart owns
its own internal focus state (and surfaces a `Semantics` label of
`"<name> focused, <N> grams, <P> percent. Tap again or tap the
center to clear."` for screen readers and tests). The parent
**drives the visible focus via `sectionOpacities`** and an
`onSectionFocusChange` callback — typical use is for the parent to
compute per-section opacities (1.0 for the focused index, 0.4 for
the rest) and pass them in. When all four macros are 0, renders an
empty `SizedBox` so the parent can fall back to the calorie ring
alone.

| Prop | Type | Default | Description |
|---|---|---|---|
| `protein` | `int` | required | Today's consumed protein grams. Negative inputs are clamped to 0. |
| `netCarbs` | `int` | required | Today's consumed net carbs (`carbs − fiber`) grams. The parent computes this — the chart does not derive it. Negative inputs are clamped to 0. |
| `fiber` | `int` | required | Today's consumed fiber grams. Negative inputs are clamped to 0. |
| `fat` | `int` | required | Today's consumed fat grams. Negative inputs are clamped to 0. |
| `size` | `double` | `240` | Outer diameter in logical pixels. The calorie ring should be sized to fit inside the donut's hole. |
| `strokeWidth` | `double` | `36` | Donut band thickness. Substantially thicker than the calorie ring's 14 px stroke so the donut reads as a wide ring around the ring. |
| `gapDegrees` | `double` | `1.5` | Angular gap between adjacent sections in degrees. `0` produces a seamless donut. |
| `sectionOpacities` | `List<double>?` | `null` | Per-section opacity values (length must equal the number of non-zero sections). When `null`, every section renders at 1.0. The parent passes 0.4 for unfocused sections when a focus is active. |
| `onSectionFocusChange` | `ValueChanged<int?>?` | `null` | Fired when the user taps inside the donut and the focus changes. Receives the new focused section index, or `null` when the focus is cleared (tap on the same section, or tap on the empty center). Not fired when the focus is unchanged. |

**Behavior**:
- Section sweep angles are proportional to grams. Non-zero sections
  share the full 360°; a half-gap is applied on the leading edge of
  each section so the donut closes cleanly.
- A `GestureDetector` with `HitTestBehavior.opaque` wraps the
  `CustomPaint` and owns hit testing for the entire chart. Tap
  regions are the donut sections themselves; taps inside the inner
  edge of the band (where the calorie ring lives) resolve to the
  `resolveSectionHitCenterSentinel` and deselect; taps outside the
  chart are a no-op. Hit-test math is the pure top-level function
  `resolveSectionHit(...)`, which takes the section list, the local
  tap position, the chart size, and the band's inner/outer radii.
  Unit-testable without a widget tree.
- **Angle convention.** The hit-test uses the raw `atan2(dy, dx)`
  angle directly — no offset. This matches `Canvas.drawArc`, which
  also measures angles from the +X axis (3 o'clock) CCW. A section
  whose `startAngleRadians == -π/2` is drawn from 12 o'clock and
  sweeps clockwise; the matching atan2 angle for a tap at 12
  o'clock is also `-π/2`, so the section range is hit-testable
  directly. Each section's range is treated as the half-open
  interval `[start, start+sweep)` so a tap on a boundary between
  two sections resolves to the **next** section (the boundary is
  owned by the section whose range contains it on its leading
  edge, not its trailing edge). When only one macro is non-zero,
  the single section wraps past the 0/2π boundary; the resolver
  splits the range accordingly.
- Tapping a section focuses it; the chart's internal state updates
  (so the `Semantics` label reflects the focus) and the
  `onSectionFocusChange` callback fires with the new index. Tapping
  the same section again, or tapping the empty center, fires the
  callback with `null` (deselect).
- Per-section opacity is applied by the painter as the alpha channel
  of the section's color. A section whose opacity is 0 is skipped
  entirely (no transparent arc rendered), keeping the donut quiet
  when one macro is focused.
- Colors come from `OmniTheme.colors.macroChart.protein / .netCarbs /
  .fiber / .fat` (themed palette; defined for all six themes). No
  hardcoded colors.
- A `Semantics(container: true, label: ...)` wrapper announces the
  current focus state (or `"Macro distribution. Tap a section for
  details."` when no section is focused).
- The section-angles math is factored into the pure top-level
  `computeMacroSections(...)` function (returns a `List<MacroSection>`)
  so it can be unit-tested without a widget tree.
- The widget mounts a `Key('macro_donut_chart')` on its `SizedBox`
  when at least one section is rendered (the key is absent in the
  empty-day branch by design). The key is the stable handle tests
  use to find the chart.
- Pure presentation — no repository access, no business logic, no
  `BuildContext` lookups beyond `Theme.of(context).textTheme`.

### `MacroFocusContent`

**File**: `lib/features/nutrition/widgets/macro_donut_chart.dart`

Small `StatelessWidget` rendered in the calorie ring's center when
a macro section is focused. Shows the macro name on line 1 with a
small colored dot (using the focused macro's color) and
`"<N>g · <P>%"` on line 2. Sized to fit inside the 160 px calorie
ring with its 8 px horizontal padding (144 px usable width).

| Prop | Type | Description |
|---|---|---|
| `name` | `String` | Section name (e.g. `"Protein"`). |
| `grams` | `int` | Section weight in grams. |
| `percent` | `int` | Section percentage of today's macros (0..100). |
| `color` | `Color` | Accent color for the dot beside the name. Comes from `OmniTheme.colors.macroChart.<slot>`. |

Used as the `centerOverride` argument on `CalorieRing` by
`CalorieRingCard` when a section is focused.

---

### `FoodLibraryBrowseSection` (private to `NutritionScreen`)

**File**: `lib/features/nutrition/nutrition_screen.dart` (private `_FoodLibraryBrowseSection`,
plus private `_GroupBlock` and `_FoodRow` helpers)

Read-only, scrollable, grouped list of foods for the "Food Library" card on `NutritionScreen`.
Drives three branches from `FoodLibraryState`:

| State | Renders |
|---|---|
| `isLoadingGroups \|\| isLoadingFoods` | Centered `CircularProgressIndicator` |
| `foodGroups.isEmpty && foods.isEmpty` | Centered muted "No foods in library" text |
| Data | One header per sorted `FoodGroup` (alphabetical, case-insensitive) followed by its sorted foods, then a trailing "Ungrouped" section for any foods with `groupId == null` |

| Prop | Type | Description |
|---|---|---|
| `foodLibraryState` | `FoodLibraryState` | Source of groups + foods cache. Required. |

**Behavior**:
- Renders one `LogFoodRow` per food. The `LogFoodRow` is the actual
  logging affordance (checkbox + multiplier + 2×2 macro grid); this
  section is responsible for the grouped list layout only.
- Computes calories per food with `calculateCalories(food)` from
  `lib/core/utils/food_helpers.dart`; calories are never stored on
  the `Food` model.
- Excludes archived groups and archived foods (the default
  `includeArchived: false` is used by `loadFoodGroups()` /
  `loadFoods()`).
- Theme tokens only — colors come from `OmniTheme.colors` and the
  active `ThemeData`; no hardcoded colors.

---

## Logo & Brand

### `HomeLogoButton`

**File**: `lib/widgets/common/home_logo_button.dart`

Circular menu/avatar control for the home-screen AppBar that hosts the brand logo. Tapping opens the Hub sheet (Calendar / Stats / Profile / Nutrition / Settings).

**Visual chrome** (rendered in this order, back to front):
- 56×56 circular surface with a subtle ~6% white overlay (`Color(0x0FFFFFFF)`, matching the `OmniTheme.colors.surfaceBorder` token value) so the button has presence on the dark navy header
- 1px `surfaceBorder` ring (~6% white) reinforcing the circle edge — stays monochrome
- `OmniTheme.softShadow` for a low-elevation drop that gives the button its 3D feel against the dark header
- Brand logo artwork (`assets/icon/omnitrain_logo.png`) centered inside, sized to fill the circle (default 55×55 in a 55×55 circle)

**Theme tint** (logo recolor):
- The brand logo's own aqua-cyan matches the **Abyssal Neon** primary (`0xFF2DE2E6`), so on Abyssal Neon the logo is rendered untouched
- On every other theme the logo is recolored to that theme's `OmniTheme.colors.primary` via a `ColorFiltered` with `BlendMode.srcATop` (preserves the alpha mask, replaces RGB with the tint color — silhouette stays crisp)
- Tint comes from an existing `OmniTheme` token, so the button stays in-palette without introducing a new color

**Press reaction**:
- AnimatedScale to `OmniTheme.pressedScale` (0.9) on finger-down; settles back on release / cancel
- Subtle white `ColorFilter` highlight (~10% white) on the logo while pressed
- `HapticFeedback.lightImpact()` fires on `onTapUp`, guarded by `!kIsWeb`
- Reduced-motion users get the scale applied instantly without animation

**Hit target & accessibility**:
- 8px horizontal + 4px vertical transparent `Padding` around the visible circle brings the gesture bounds to 72×64 — well above the 44×44pt minimum
- Explicit `ConstrainedBox(minWidth: 44, minHeight: 44)` + `HitTestBehavior.opaque` keep the guarantee even if `tileSize` is later reduced
- `Semantics(button: true, label: 'Open menu')` wraps the whole control; the ring is decorative and the screen reader only hears the parent's label

| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `onTap` | `VoidCallback` | required | Fires on tap (after the gesture is released) |
| `size` | `double` | `55` | Logo artwork side length in logical pixels |
| `tileSize` | `double` | `55` | Outer circle diameter; matches `kToolbarHeight` (56) exactly so the AppBar toolbar height stays unchanged |

**Constraints**:
- Body-centered "TRAIN" title in the home `Column` is unaffected — the button is in the AppBar `title:` slot and its visible circle (56px) matches `kToolbarHeight` (56) exactly
- The control is a presentation-only widget: no repository or service access; only local `_isPressed` state

### `AnimatedZenHalo`

**File**: `lib/widgets/logo/animated_zen_halo.dart`

Animated brand mark with slow rotation (8000ms) and breathing pulse (3000ms). Used on the splash screen.

### `ZenHaloPainter`

**File**: `lib/widgets/logo/zen_halo_painter.dart`

`CustomPainter` for the Enso arc (zen circle). Stroke reveal animation at 1200ms.

---

## Picker Dialogs

### `ExercisePickerDialog`

**File**: `lib/widgets/pickers/exercise_picker_dialog.dart`

Modal dialog for searching and selecting exercises. Receives `sessionModality` to rank exercises by relevance.

**Key features**:
- Real-time search with `TextField`
- Exercises ranked by `getExercisesRankedForModality()` (relevance score)
- Filter by discipline or muscle group
- "New Exercise" button → opens `ExerciseEditorScreen` with picker/session modality prefilled via `contextModality`
- Returns selected `Exercise` on tap

### `MetricChooserDialog`

**File**: `lib/widgets/pickers/metric_chooser_dialog.dart`

Modal dialog for choosing a tracking method. Shown in Free Training mode and routine creation.

**Key features**:
- Displays only capabilities the selected exercise supports
- Each capability shown as tappable tile with icon and label
- Returns chosen metric string (e.g., `'time'`, `'reps'`, `'hold'`, `'rounds'`)

### `ModalityPickerDialog`

**File**: `lib/widgets/pickers/modality_picker_dialog.dart`

Modal dialog for selecting a modality for an exercise being added to a null-modality (Free Training or Routine) session.

**Key features**:
- Shows all five modalities plus a "General" option
- Returns `(true, String? modality)` record when the user picks an option:
  - Specific modality: `(true, 'cardio_endurance')` etc.
  - "General": `(true, null)`
- Returns `null` when the user cancels (so callers can distinguish cancel from "General")
- Callers use `showDialog<(bool, String?)>` and check for `null` before destructuring

---

## Session Metric Widgets

### `DominantMetricWidget`

**File**: `lib/widgets/session/set_metric_widget.dart`

Unified large-metric display widget used across all effort kinds. Renders exactly **one** large metric value.

| Prop | Type | Description |
|------|------|-------------|
| `displayText` | `String` | The value to show (e.g., "10", "03:00", "Round 1\n03:00") |
| `isMultiline` | `bool` | Multi-line rendering for round display |
| `onTap` | `VoidCallback?` | Tap handler (edit reps, toggle timer) |

The following files are **stub redirects** to `DominantMetricWidget`, kept for import compatibility:
- `lib/widgets/session/drill_metric_widget.dart`
- `lib/widgets/session/round_metric_widget.dart`
- `lib/widgets/session/timed_metric_widget.dart`

### `InlineMetricEditor`

**File**: `lib/widgets/session/inline_metric_editor.dart`

Touch-optimized value input for workout environments. Tap the number to open a numeric-entry modal (the crown scrub control is present in the codebase but not rendered — see `MetricCrownWidget`).

| Prop | Type | Description |
|------|------|-------------|
| `metricType` | `String` | `reps`, `weight`, `duration`, `rpe`, `extra-weight` |
| `currentValue` | `dynamic` | Value to display |
| `unitLabel` | `String` | Label below value (e.g., "REPS", "LBS") |
| `emphasisTier` | `MetricEmphasisTier?` | Optional value emphasis: `dominant`, `secondary`, `muted`; default keeps legacy displayLarge styling |
| `isReadOnly` | `bool` | When true: disables tap-to-edit popup. Used for live timer displays. |
| `onTap` | `VoidCallback?` | When provided, tapping the number calls this instead of opening the generic popup (e.g. timer toggle, duration dialog). |
| `onValueChanged` | `Function(dynamic)` | Immediate callback on value change |

**Interaction model**:
- Number tap is the sole value-change mechanism.
  - `onTap` provided → delegates to `onTap`.
  - `onTap` null and `!isReadOnly` → opens `showMetricEditPopup`.
  - `isReadOnly: true` → no interactive affordance.
- The crown scrub control (`MetricCrownWidget`) is dormant — it remains in the codebase at `lib/widgets/session/metric_crown_widget.dart` and can be re-enabled in the row without rebuilding the widget.

**Visual**: Value size and styling unchanged. The crown is not rendered. When `isReadOnly` and `emphasisTier` are both set, the emphasis tier wins and the value is not dimmed.

**Session context (live timed/round/drill)**: In `WorkoutSessionScreen` detail view, the `InlineMetricEditor` for live timer-based efforts (`timed`, `round`, `drill`) uses `onTap` wired to `showDurationEntryDialog` so tapping the time value opens the h/m/s editor. When the effort is finished (`isTimedFinished`, `isFinished`, `isDrillFinished`), `isReadOnly: true` is set so the value cannot be edited from live mode (use edit mode for corrections). Play/pause control is a separate Start button — not a tap on the value display. Timed and drill timers render at the dominant tier; the play/pause status label sits on a line below the value.

---

### `MetricCrownWidget`

**File**: `lib/widgets/session/metric_crown_widget.dart`

**Status: dormant.** The widget is fully implemented and constructible but is not rendered by `InlineMetricEditor` in the default interaction path. It can be re-enabled by adding it to the `InlineMetricEditor` row without any other changes.

A rotatable thumb-wheel (crown) control painted as a thick vertical wheel edge-on.

| Prop | Type | Description |
|------|------|-------------|
| `metricType` | `String` | Metric type (forwarded to `MetricStepCalc`) |
| `currentValue` | `dynamic` | Current metric value; read on each drag tick |
| `onValueChanged` | `Function(dynamic)` | Fires on each 10px drag step |

**Behavior**: drag fires `onValueChanged` via `MetricStepCalc.apply`. Crown rotates `2π / 120px` radians per pixel. Rotation accumulates for the widget's lifetime but stops immediately on drag release (no momentum). No `AnimationController` or `Timer`.

**Style**: `44×60` touch target; `CustomPaint` centred inside; all colours from `OmniTheme.colors.textMuted`/`textSecondary` with opacity overlays.

**Drag step sensitivity** (from `MetricStepCalc.apply`):
| Metric | Increment per 10px | Range |
|--------|-------------------|-------|
| `reps` | ±1 | 0–999 |
| `weight` | ±0.5 | 0.0–999.0 |
| `duration` | ±5 sec | 0–3600 |
| `rpe` | ±1 | 1–10 |
| `extra-weight` | ±0.5 | -100.0–200.0 |

---

### `showMetricEditPopup`

**File**: `lib/widgets/session/metric_crown_widget.dart` (top-level function)

Opens an `AlertDialog` for exact numeric entry of a metric value.

```dart
Future<void> showMetricEditPopup(
  BuildContext context, {
  required String metricType,
  required dynamic currentValue,
  required String unitLabel,
  required Function(dynamic) onValueChanged,
})
```

- Pre-fills field with formatted current value; selects all text on open.
- Confirm ("Ok"): parses + clamps → `onValueChanged` → closes.
- Barrier tap (outside dialog): closes without calling `onValueChanged`. There is NO Cancel button.
- Empty or unparseable text → treated as dismiss (no value change).
- Keyboard: `signed: true` for `weight`/`extra-weight`; `signed: false` for all other metric types (e.g., `reps`).
- Ok button has explicit `shape: RoundedRectangleBorder(borderRadius: OmniTheme.buttonUtilityRadius)`.

---

### `showDurationEntryDialog`

**File**: `lib/widgets/session/duration_entry_dialog.dart` (top-level function)

Shared h/m/s duration-entry dialog. Used by `WorkoutSessionScreen` (both live and edit modes) and `RoutineSetupScreen` (round effort duration targets).

```dart
Future<int?> showDurationEntryDialog(
  BuildContext context, {
  String title = 'Edit Duration',
  String subtitle = '',
  required int initialSecs,
})
```

- Returns confirmed duration in whole seconds (`h*3600 + m*60 + s`), or `null` if dismissed.
- Three `TextField` instances for hours, minutes, seconds. Pre-filled from `initialSecs`.
- Single "Ok" `FilledButton`. No Cancel button. Barrier tap dismisses without applying.
- `TextEditingController`s are deferred-disposed (300 ms after dialog close) to avoid use-after-dispose errors.

**Usage**: Wire to `onTap` on `InlineMetricEditor` when `metricType == 'duration'`.

---

### `MetricStepCalc`

**File**: `lib/widgets/session/metric_crown_widget.dart` (static class)

Shared utility for value-adjustment math and popup parsing. Used by both `MetricCrownWidget` and `showMetricEditPopup`.

- `MetricStepCalc.apply(metricType, currentValue, deltaY)` — drag step math (identical to previous `InlineMetricEditor._calculateNewValue`).
- `MetricStepCalc.parseAndClamp(metricType, text)` — parse popup input, clamp to metric range, return typed result (`int` for reps, `double` for others). Returns `null` if unparseable.

---

## Presentation Models

### `UiSetData`

**File**: `lib/widgets/models/ui_set_data.dart`

Mutable presentation-layer data class for set tracking. **Not a persistence model.**

| Field | Type | Description |
|-------|------|-------------|
| `id` | `String` | Unique identifier |
| `exerciseId` | `String` | Parent exercise |
| `reps` | `int` | Mutable — current reps value |
| `weight` | `double` | Mutable — current weight value |
| `duration` | `int` | Mutable — current duration in seconds |
| `timestamp` | `DateTime` | When created |

Used by `WorkoutSessionScreen` and `RoutineSetupScreen` for ephemeral UI state.

---

## Nutrition Widgets

Nutrition-feature widgets live under `lib/features/nutrition/widgets/`. They are
feature-scoped (only `NutritionScreen` uses them) but follow the catalog
conventions: pure presentation, theme-reactive, no repository access, state
injected via constructor.

### `LogFoodRow`

**File**: `lib/features/nutrition/widgets/log_food_row.dart`

A single food-library row that doubles as the "log a food as consumed"
affordance on the nutrition page. Layout, left to right:

```
[ ☑/☐ checkbox ]  [ name (up to 2 lines)  +  2×2 macro grid ]  [ amount input × + portion label ]
```

The right-hand column is a `Column` of two rows: the top row holds
the amount `TextField` and an `×` glyph to its right (indicating the
field is a **multiplier** against the food's portion); the bottom row
holds the portion label (e.g. `100 g`, `1 egg`) in `labelSmall` font.

The amount field is a multiplier. The default is `1` for both count
and grams foods (a multiplier of `1` always means "one full portion").
The widget translates the typed multiplier to a raw amount
(`multiplier * referenceAmount`) before calling
`NutritionState.logConsumedFoodAt`; the data layer's "raw amount in
the food's own unit" contract is preserved. A typed `0.5` on a
per-100 g food ⇒ 50 g of macros persisted; a typed `1.5` on a
per-1-egg food ⇒ 1.5 eggs persisted.

The 2×2 macro grid (`_MacroGrid` private helper) is rendered directly
beneath the food name:

```
┌─────────────┬─────────────┐
│ Protein     │ Calories    │
├─────────────┼─────────────┤
│ Carbs       │ Fat         │
└─────────────┴─────────────┘
```

All four cells always render — zero macros show as `0P` / `0C` /
`0F` / `0 cal` rather than being hidden, so the row's vertical
rhythm stays consistent and screen readers can read the values
uniformly. Cell widths are fixed (`_MacroGrid._cellWidth = 56`) so
the columns line up across rows on the same screen.

The food name wraps to 2 lines (with an ellipsis fallback on a third)
so longer names stay readable now that the inline "per …" label has
been removed.

The checkbox is the primary "mark consumed" toggle; tapping it logs
the food at the current multiplier (or unlogs it). Editing the amount
input re-logs the food at the new multiplier via the day-uniqueness
contract on `NutritionState.logConsumedFoodAt`.

| Prop | Type | Description |
|------|------|-------------|
| `food` | `Food` | The library food to render and toggle. |
| `nutritionState` | `NutritionState` | Day-log state (read for `isFoodLoggedToday`; mutate via `logConsumedFoodAt` / `unlogFoodToday`). |
| `foodLibraryState` | `FoodLibraryState` | Symmetric constructor parameter; not mutated by the row. |

**Validation**: the multiplier must be `> 0`. Both count and grams
foods accept any positive decimal — `0.5` on a per-1-egg food means
"half an egg" and is perfectly valid (a previous iteration rejected
fractional counts; that check was removed for the multiplier
contract). While the input is invalid, the checkbox tap is a no-op
and an inline error renders below the input.

**Pre-fill**: on a fresh row, the field shows `1`. If the food is
already logged today, the field pre-fills with the existing
snapshot's raw `amountConsumed` (per the "leave historical logs
alone" decision) — a previously-logged 75 g grams-food still shows
`75` in the field, not `0.75`.

The widget rebuilds via `ListenableBuilder(listenable: nutritionState)`
so the checkbox updates the moment a log is written.

---

### `FoodThumbnail`

**File**: `lib/features/nutrition/widgets/food_thumbnail.dart`
(platform image renderer split into
`food_thumbnail_io.dart` / `food_thumbnail_stub.dart` via
conditional import — same pattern as `ProfileAvatarImage` in
`lib/features/profile/widgets/`).

A 40×40 rounded thumbnail for a food item, with a placeholder
when no image is set. Mirrors the contract of `ProfileAvatarImage`:
the image is loaded from a local file path on native and falls
back to a placeholder on web or when the file is missing.

Used as the leading slot on each catalog row in the **Library**
tab of `AddFoodScreen` (key `food_catalog_thumb_<id>`). The slot
is always present (placeholder when no image) so the trailing
Add / Remove button column does not reflow when an image is
added or removed. The same widget is also used inside the
`FoodForm`'s image picker tile.

| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `imagePath` | `String?` | required | Local file path to a food photo. `null` / empty / unreadable path falls back to the placeholder. |
| `size` | `double` | `40` | Diameter in logical pixels. |
| `radius` | `double` | `8` | Corner radius — matches the `OmniTheme.buttonUtilityRadius` token. |

**Behavior**:
- Always renders a fixed-size slot. The slot is filled with the
  image (`Image.file` on native with an `errorBuilder` fallback)
  or a placeholder (`Icons.restaurant_outlined` tinted with
  `OmniTheme.colors.textMuted` on a `surface` background).
- Pure presentation — no repository / state access, no business
  logic. The `imagePath` is a plain `String?` read at build time.
- The `kIsWeb` short-circuit keeps `dart:io` out of the web build.

### `FoodForm`

**File**: `lib/features/nutrition/widgets/food_form.dart`

Shared form widget used by both the **+ New Item** flow on
`AddFoodScreen` and the **Edit Food** screen
(`EditFoodScreen`). Parameterized by an optional `Food?` initial
value: `null` → create mode, non-null → edit mode.

| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `initial` | `Food?` | required | Pre-fill the form with this food's values when non-null. |
| `foodLibraryState` | `FoodLibraryState` | required | Source for the categories dropdown (re-reads `activeFoodGroups` on every notification). |
| `onSave` | `Future<bool> Function(FoodDraft draft)` | required | Save callback. Returns `true` to pop, `false` to surface a snackbar. |
| `saveLabel` | `String` | `'Save'` | Primary CTA label. |
| `showNotesField` | `bool` | `false` | When true, renders a "Notes (optional)" multi-line field. Edit mode only. |

**Form fields (top to bottom)**:
1. Image picker tile (`FoodFormImageTile`, key `food_form_image_tile`) — square 96×96 with × (clear) and edit (change) overlays; opens a Camera / Gallery bottom sheet on tap; web is a no-op with a snackbar.
2. Name (`food_form_name`) — `TextFormField` with `TextCapitalization.words`.
3. Category (`food_form_group`) — `DropdownButtonFormField<String?>` of the active groups + an "Ungrouped" `null` entry.
4. Unit type (`food_form_unit_type`) — `DropdownButtonFormField<FoodUnitType>` of `count` / `grams`. Swapping units pre-fills sensible defaults for the reference amount + label.
5. Reference amount (`food_form_reference_amount`) + Reference label (`food_form_reference_label`).
6. Macros (per the reference above) — `Protein (g)` (required), `Carbs (g)` (required), `Fiber (g)` (optional, blank = unset), `Fat (g)` (required), `Sodium (mg)` (optional, blank = unset). All integer-only.
7. Notes (`food_form_notes`) — when `showNotesField: true`.
8. Save button (`food_form_save`) — full-width primary CTA, `FilledButton` with the explicit `shape:` + `OmniTheme.buttonBorderRadius` contract.

**Behavior**:
- The form owns validation, the image picker, and the
  translation from controllers to a typed `FoodDraft`. The caller
  hands the draft to `FoodLibraryState.createCustomFood` (create)
  or `FoodLibraryState.updateCustomFood` (edit) — never to the
  repository directly.
- Fiber is exposed alongside carbs in the macro list, matching
  the `Food.fiber` field on the model. The existing
  `calculateNetCarbs(food)` helper handles the net-carb math.
- All colors come from `OmniTheme.colors` /
  `ThemeData.colorScheme`. No hardcoded colors.

---

### `_CategoriesTab` (private to `AddFoodScreen`)

**File**: `lib/features/nutrition/add_food_screen.dart` (private
`_CategoriesTab`, `_CategoryRow`, `_UngroupedRow`, `_DeleteCategoryDialog`)

The third tab of `AddFoodScreen`. Manages the food groups that
organize the user's library. Layout (top to bottom):

- A scrollable list of `_CategoryRow` widgets, one per active
  `FoodGroup` (alphabetical, case-insensitive).
- A trailing read-only `_UngroupedRow` (foods with `groupId == null`).
- A "+ New Category" `OutlinedButton.icon` (key `new_category_button`)
  that calls `FoodLibraryState.createFoodGroup('New Category')`.

The list rebuilds via `ListenableBuilder(listenable: foodLibraryState)`
so add / rename / archive operations reflect immediately.

### `_CategoryRow` (private to `_CategoriesTab`)

| Param | Type | Purpose |
|---|---|---|
| `group` | `FoodGroup` | The group to render |
| `controller` | `TextEditingController` | Stable per-group controller (held by `_CategoriesTabState._controllers`); preserves in-progress rename text across rebuilds |
| `foodCount` | `int` | Number of foods in this group; rendered in the `suffixText` |
| `onRename(String)` | `Future<void> Function(String)` | Calls `FoodLibraryState.renameFoodGroup(id, newName)` |
| `onDelete()` | `Future<void> Function()` | Opens the confirm dialog (or silent-deletes when `foodCount == 0`) |

The `TextField` is keyed `category_name_<group.id>` and commits the
rename on `onEditingComplete` (IME action / unfocus) and on
`onSubmitted` (Enter). The trash `IconButton` is keyed
`category_delete_<group.id>`. Both use `OmniTheme.colors` and
`theme.colorScheme` — no hardcoded colors.

### `_UngroupedRow` (private to `_CategoriesTab`)

A read-only, single-row summary of foods with `groupId == null`.
Renders an `Icons.label_off_outlined` icon, the label "Ungrouped"
(italic, muted), and the food count. No `TextField`, no trash
affordance — the row is purely informational.

### `_DeleteCategoryDialog`

Confirmation dialog for deleting a non-empty category. Title
"Delete category?"; body shows the count of foods to be moved and a
`DropdownButtonFormField` (key `delete_category_destination`) for
the destination group. Options: "Ungrouped" (the default, value
`null`) plus every other active group. Actions: `TextButton("Cancel")`
returns the private `_cancelledSentinel`; `FilledButton("Delete")`
(red `theme.colorScheme.error`, key `delete_category_confirm`)
returns the picked destination id (which may be `null` for
Ungrouped). The caller uses the sentinel to distinguish cancel from
"Ungrouped".

---

## Composition Pattern

```
OmniGradientBackground              ← Full-screen cosmic backdrop
  └── OmniSurface                   ← Dark navy card with border + deep shadow
       └── Content                  ← Text, icons, interactive elements

GestureDetector (press tracking)
  └── AnimatedScale (press feedback)
       └── EnergyTile (gradient + shadows)
            └── EnergyCore (icon circle) + Label
```

---

## Related Documentation

- [Design System](design_system.md) — Design tokens, color system, typography, animation rules
- [Modality-Based Exercise UI](modality_based_exercise_ui.md) — How metric widgets are used in the workout screen

---

**Document Version**: 1.3
**Last Updated**: June 8, 2026
