# Home Screen & Nutrition Card Widgets

> Part of the [Widget Catalog](../widget_catalog.md). Return to the index for the complete widget list and the widget → page lookup table.
>
> Scope note: the "Home Screen Footer" section below also covers the nutrition
> cards that the footer gauge links into (`CalorieRing`, `CalorieRingCard`,
> `WaterTrackerControl`, `MacroDonutChart`). They are grouped here because the
> catalog has always organised them under the home-screen footer heading. The
> remaining nutrition components live in
> [Nutrition Widgets](nutrition_widgets.md).

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

Small tile used inside the home screen's maintenance bottom sheet (the Hub
sheet) for system features (Calendar, Stats, Exercise Library, Profile,
Settings — five tiles in a 2-column grid; the last row leaves one tile
alone, by design). Simpler styling than `EnergyTile`.

| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `title` | `String` | required | Tile label (e.g., "Calendar") |
| `icon` | `IconData` | required | Tile icon |
| `onTap` | `VoidCallback` | required | Tap handler |
| `activeTheme` | `AppTheme` | `abyssalNeon` | Active theme for surface fill, border, text |

**Behavior**:
- Press scale: `OmniTheme.pressedScale` (0.96) with `OmniTheme.animationDuration` animation.
- Outer chrome: `OmniTheme.surfaceBorderRadius` rounded corners, `themeColors.surface` fill, `themeColors.surfaceBorder` hairline, `OmniTheme.deepShadow` lift. No rim highlight, no inner shadow, no accent fill — distinguishable from `EnergyTile` at a glance.
- Inner padding: 18 px on every side; an `Icon` (42 px) + 16 px gap + `Text` (`bodyLarge`, weight w600, `OmniTheme.titleLetterSpacing`, height 1.1) inside a centered `Column`.
- Large-text-scale resilience: the title `Text` is wrapped in `Flexible` with `maxLines: 2` and `overflow: TextOverflow.ellipsis`, so when the system text scale is large enough that the natural Column height would overflow the grid cell (tile aspect ratio 1.1, fixed by the parent `SliverGridDelegate`), the title truncates with ellipsis instead of overflowing. The grid delegate owns the outer tile size; this only affects internal flex distribution. See `hub-sheet-gap-and-logo-clip-plan.md` for the layout that depends on this resilience.
- Hit target: the entire tile body is the tap region; press state is local (`_isPressed`).
- Presentation-only: no repository, service, or state access.

### Removed tile implementations

> **Corrected 2026-07-26 (docs audit).** This page carried entries for
> `OmnitrainCategoryTile`, `WorkoutCategoryCard`, and `ModalityTileWidget`,
> described as "legacy/alternative implementations" and "deprecated stub,
> returns `SizedBox.shrink()`". **All three classes and their files have since
> been deleted** — `lib/widgets/cards/` now contains only `energy_tile.dart`,
> `energy_core.dart`, and `maintenance_tile.dart`. There is nothing left to
> "check code for current usage" on. `EnergyTile` is the only home tile
> implementation.

---

---

## Home Screen Footer

### `NutritionSummaryCard`

**File**: `lib/features/home/widgets/nutrition_summary_card.dart`

Self-contained gauge card on the home screen (Iteration 5 / S-100..S-106 — supersedes the Phase 4.1 `NutritionStripBar` full-bleed bottom strip). Sits BELOW the training-tile grid with top gap = 2 × `standardGridSpacing` and is INSET from the screen edges (16 px horizontal padding, matching the tile grid's side margin) — NOT a full-bleed rectangle. The card chrome matches the training-tile visual family: 20 px `OmniTheme.surfaceBorderRadius`, `OmniTheme.surfaceBorder` hairline border, `OmniTheme.deepShadow` lift. Pure presentation — no state access, no business logic, no math. All colors come from `OmniTheme.colors`; per-macro calorie math lives on `NutritionState` (D-4 getters) and is passed in.

| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `consumedCalories` | `int` | required | Today's consumed calories (already rounded by the caller) |
| `targetCalories` | `int?` | required | Today's calorie target, or `null` for "no goal" |
| `proteinKcal` | `int` | required | Protein calorie contribution (D-4: `protein × 4`) |
| `carbsKcal` | `int` | required | Net-carbs calorie contribution (`carbs - fiber`, then × 4 — matches the donut chart's percentage calculation) |
| `fatKcal` | `int` | required | Fat calorie contribution (D-4: `fat × 9`) |
| `onTap` | `VoidCallback` | required | Tap handler — the card is always tappable (S-104). The ENTIRE card body is one tap target; the chevron is a visual cue only. |

**Behavior (S-100..S-106)**:
- **Geometry**: the card is a `Column` of three regions inside a `Material` + `InkWell` + `Ink` with rounded-corner `BoxDecoration` chrome. The three regions:
  1. **Headline row** (`Key('nutrition_card_headline')`): small `Icons.local_dining_outlined` (18 px, `textDominant`) + 8-px gap + the headline `Text` `"{consumed} / {target} Cal"` (comma-grouped thousands) — the LARGEST, BRIGHTEST text on the card (`theme.textTheme.headlineSmall` + `FontWeight.w800` + `textDominant`) + 8-px gap + `Icons.chevron_right` (22 px, `textDominant`) at the right edge. The headline is the only element that earns white emphasis.
  2. **Gauge row** (`Key('nutrition_card_gauge')`): a `Stack` of two layers — the `track` (full-width `divider`-colored pill, 12 px tall, `Key('nutrition_card_gauge_track')`) and the `fill` (a clipped `Row` of three macro `Container`s with `Key('nutrition_card_gauge_segment_0'..'2')`). The fill width = `clamp(consumed / target, 0, 1) × trackWidth` (S-102); the segments are sized as a share of CONSUMED calories (S-103), so they live INSIDE the fill, not across the full bar.
  3. **Caption row** (`Key('nutrition_card_caption')`): a `spaceBetween` `Row` of three `(colorMarker, "M N%")` groups with keys `nutrition_card_caption_protein` / `_carbs` / `_fat`. The caption percentages are the macro's share of CONSUMED calories (S-103). The empty state renders DASHES (`—`), NOT `0%` (S-104).
- **Tap target** (S-101): the ENTIRE card is wrapped in a single `InkWell(onTap: onTap)`. Tapping ANY region of the card (headline text, gauge track, fill, caption row, chevron) fires `onTap`. The empty state is still tappable.
- **Empty state** is split across two orthogonal axes — the gauge needs a **goal** (`consumed / target`) while the caption needs **data to split** (P/C/F kcal share of consumed).
  - **Both axes empty** (S-104 / S-201): `consumedCalories <= 0`. Headline renders `"0 / {target ?? "—"} Cal"` in `textDominant`. Gauge fill is not rendered. Caption row renders DASHES (`—`) for each macro, NOT `0%`. We do not imply a real split when there is no data.
  - **Gauge-only empty** (S-200): no target configured (`targetCalories == null`) but food has been logged. Headline renders `"{consumed} / — Cal"`. Gauge fill is hidden (no goal to fill against). Caption row renders the **real** macro percentages (`P 42%`, `C 33%`, `F 25%`) so the user gets actionable feedback. The track still renders at full width so the card layout stays stable.
  - **Caption-empty even with data** (S-202): `consumed > 0` but `proteinKcal + carbsKcal + fatKcal == 0` (a calorie-only entry). Caption row still renders DASHES — we do not show a fake `P 0% / C 0% / F 0%` split when there is no macro data.
- **Over-budget state** (S-105): when `consumedCalories > targetCalories > 0`:
  - Headline text color switches to `Theme.of(context).colorScheme.error` (the theme's restrained warning tone — no celebration, no alarm).
  - Gauge fill clamps to 100% of the track width (no overflow past `trackWidth`).
  - Caption percentages still render with real values (the data is real, not absent).
- The widget never picks a color of its own — `OmniTheme.colors.stripMacros.{protein,carbs,fat}` for the macro markers and fill segments (a MUTED palette tuned per theme — terracotta / steel-blue / amber; deliberately NOT the saturated `macroChart` palette), `OmniTheme.colors.divider` for the gauge track, `OmniTheme.colors.surface` for the card fill, `OmniTheme.surfaceBorder` + `OmniTheme.surfaceBorderWidth` for the hairline border, and `OmniTheme.deepShadow` for the raised shadow.
- The card's outer `Padding(EdgeInsets.symmetric(horizontal: 16))` provides the screen-edge inset (matching the tile grid's side margin). The home screen owns the top gap (2 × `standardGridSpacing`) and the bottom safe-area clearance.

<!-- REMOVED 2026-07-26 (docs audit): a second `NutritionSummaryCard` section
     documented `lib/features/nutrition/widgets/nutrition_summary_card.dart`
     ("Daily Targets" goal-line card). That file does not exist in the source
     tree and no code references it; the surviving `NutritionSummaryCard` is
     the home gauge card documented above. Section deleted as stale. -->

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

`OmniSurface` wrapper around `CalorieRing` for the top of `NutritionScreen`.
The "Today" section title and the small edit-targets icon button live
in an `OmniCardHeader` *above* the card (rendered by `NutritionScreen`,
not by this widget) — see `.github/agents/plans/unified-card-and-header-plan.md`
Phase 3. The card body itself renders the chart, the sodium chip, and the water tracker in an `OmniSurface` so its chrome matches every other outlined card in the app (radius 20, 1 px `surfaceBorder`, `deepShadow`).

Reads consumed + target data from the injected `NutritionState` and
rebuilds on every notification. Owns the **focus state** that drives
the macro-donut tap-to-focus interaction.

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
- Edit control (`OutlinedButton.icon`, `Key('nutrition_target_button')`)
  lives in the `OmniCardHeader` actions slot above the card (rendered by
  `NutritionScreen`). PR 3 / Item 5 of the 2026-07-27 feedback pack
  replaced the previous icon-only `Icons.tune` `IconButton` with this
  labelled utility variant. The label reflects the saved-target state:
  "Set target" when no target is saved, "Change target" when a target
  is already saved. The button has an explicit `shape:` override
  (`OmniTheme.buttonUtilityRadius` = 8) and uses
  `theme.colorScheme.primary` for the border + label colour, per the
  utility-button design-system rule. The button is **not** part of the
  focus state — tapping it navigates to the targets editor as before.
- `ListenableBuilder` over `nutritionState` — every `notifyListeners()`
  (target load/save, consumed-food load, water increment / decrement,
  log/delete) rebuilds the ring, the donut, the sodium chip, and the
  water tracker. The focus survives a rebuild as long as the focused
  section still has non-zero grams (S-013); it clears if the section
  disappears (S-014), but does not flicker because the fallback is a no-op.
- **Bottom row** is a single `Row(spaceBetween)` with the sodium chip on
  the left and the `WaterTrackerControl` on the right. The two are
  siblings so they horizontally mirror each other. Both rebuild via the
  same `ListenableBuilder`, so each tap on either persists immediately
  and the ring reflects the new totals on the next frame.
- Pure presentation — no repository access, no business logic. The
  water tracker's increment / decrement is wired to
  `nutritionState.incrementWaterForDate(todayMs)` /
  `nutritionState.decrementWaterForDate(todayMs)`.
- Card chrome is `OmniSurface` with symmetric 16 dp padding (A20); no
  call-site may re-declare border, radius, or shadow.

### `WaterTrackerControl`

**File**: `lib/features/nutrition/widgets/water_tracker_control.dart`

Compact, tap-only +/− stepper for the day's water volume. Lives in
the bottom-right of `CalorieRingCard`, horizontally opposite the
sodium chip in the bottom-left. The on-screen glass count is
derived from the stored ml (`volumeMl ~/ kWaterGlassMl`); the icon +
literal `250 ml` annotation carries the unit so the user can decode
the per-glass amount at a glance. Water has no goal — the widget
carries no progress bar, target, or percentage.

Composition (left-to-right):
1. **Glass icon + `250 ml` annotation** stacked vertically. The icon
   (`Icons.local_drink_outlined`) sits on top and reads as a tumbler /
   glass with water; the literal `250 ml` caption sits beneath it so
   the per-glass amount is decoded at a glance. Muted-text color via
   `OmniTheme.colors.textMuted`. The annotation is sourced from
   `kWaterGlassMl` so a future per-glass change propagates here
   automatically. Vertical stacking keeps the row's total width tight
   (~22 dp narrower than the horizontal layout) so the control fits
   alongside the sodium chip on the same card row without crowding.
2. **Minus `IconButton`** — disabled (`onPressed: null`) at 0 glasses.
   `Icons.remove`. Disabled state uses `themeColors.textDisabled`; the
   active state uses `theme.colorScheme.primary`.
4. **Glass count** — tabular-figures `Text` showing the integer count.
   `Key('water_tracker_count')`.
5. **Plus `IconButton`** — enabled. `Icons.add`. `theme.colorScheme.primary`.

| Prop | Type | Description |
|---|---|---|
| `glasses` | `int` | Current glass count for the day. Always `>= 0`. The widget does not accept a typed amount — the count is the only signal the parent can pass in. |
| `onIncrement` | `VoidCallback` | Tap handler for the plus button. The widget does not invoke the state directly; the parent screen owns the persistence wiring. |
| `onDecrement` | `VoidCallback` | Tap handler for the minus button. The widget also passes `null` to the `IconButton.onPressed` (disabled state) when `glasses <= 0` so the visual and the no-op agree. |

**Behavior**:
- Pure presentation: no repository access, no business logic, no
  keyboard / text-entry field. The widget never reads or writes
  ml; the count is the only input.
- All buttons follow the explicit `shape:` + `OmniTheme.buttonIconRadius`
  (10) contract — Material 3's default `StadiumBorder` is never used.
  Both `IconButton`s are 36×36 with `visualDensity: compact` and
  `padding: EdgeInsets.zero` so the control fits the calorie-ring
  card's bottom row without crowding the sodium chip.
- Colors are theme-derived: `theme.colorScheme.primary` for active
  state, `themeColors.textDisabled` for the disabled minus, and
  `themeColors.textMuted` for the icon and `250 ml` label.
- The glass count uses tabular figures (`FontFeature.tabularFigures()`)
  so the value does not reflow as the count grows from 1 to 2 to 3
  digits.
- The widget is rebuilt by its parent's `ListenableBuilder` —
  no internal state. Every state change (increment, decrement, load,
  day rollover) flows through `NutritionState` and the
  `ListenableBuilder` rebuilds the row with the new `glasses` value.

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

**Iteration 3 polish** added:

- **In-band labels** at each section's mid-angle, on the band's
  mid-radius, drawn upright (not rotated). Format is
  `"<initial> <N>g"` with initials:
  - **N**  — Net Carbs
  - **Fb** — Fiber (disambiguated from Fat's single-letter F)
  - **F**  — Fat
  - **P**  — Protein
  Example: a 22 g net carbs section renders `"N 22g"`. The label
  color is picked per section via
  `ThemeData.estimateBrightnessForColor`: light section colors
  (e.g. protein's near-white, fat's amber) get the theme's
  `macroChart.chartLabelDark` slot; dark section colors
  (e.g. net carbs' blue, fiber's green) get the theme's
  `textDominant` slot. No hardcoded colors. Labels inherit the
  section's focus opacity (S-018) — when a section is unfocused
  and at 0.4 opacity, its label also fades to 0.4.
- **Fit test** (S-017): a section's label is hidden when the
  painted text width exceeds the section's arc length at
  mid-radius minus an 8 px breathing pad. A single 1 g Fiber
  slice next to three 200 g macros therefore renders no label
  in the Fiber slot, while the other three sections keep theirs.
- **Even gaps** (S-015): every inter-section gap (including the
  wrap-around seam at 12 o'clock) is exactly `gapDegrees` wide.
  The cursor in `computeMacroSections` now advances by
  `sweep + gap` per boundary (not `sweep + gap/2`), so the
  leftover half-gap that previously piled up at 12 o'clock is
  gone. Verified for n = 1..4 sections.

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
  share the full 360°; the gap between every adjacent pair of
  sections (including the wrap-around seam at 12 o'clock) is exactly
  `gapDegrees` wide — no wide notch at the seam (S-015, Iteration 3
  polish). The first section's leading edge is offset by `gap/2`
  from 12 o'clock so the seam is centered at 12 o'clock rather than
  on the section's leading edge; the cursor in `computeMacroSections`
  advances by `sweep + gap` per boundary so the gap math closes the
  circle exactly for any n = 1..4 sections.
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
- In-band labels are drawn at each section's mid-angle, on the
  band's mid-radius, upright (no rotation). The label text is the
  documented initial + grams (e.g. `"N 22g"`, `"Fb 8g"`, `"F 30g"`,
  `"P 100g"`); the label color is picked per section via a luminance
  check (`ThemeData.estimateBrightnessForColor`): light section
  colors get `OmniTheme.colors.macroChart.chartLabelDark`; dark
  section colors get `OmniTheme.colors.textDominant`. No hardcoded
  colors. A section's label is hidden when the painted text width
  exceeds the section's arc length at mid-radius minus an 8 px pad
  (S-017). Label alpha inherits the section's `sectionOpacities`
  value, so labels fade to 0.4 alongside their section when a focus
  is active (S-018). The label-decision math is factored into the
  pure top-level `computeMacroLabels(...)` function (returns a
  `List<MacroLabel>`) so it can be unit-tested without a widget tree.
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
| `foods.isEmpty` | Centered muted "Your Foods I Eat list is empty. Tap the pencil to add foods." text |
| Data | One header per sorted `FoodGroup` (alphabetical, case-insensitive) followed by its sorted foods, then a trailing "Ungrouped" section for any foods with `groupId == null` |

| Prop | Type | Description |
|---|---|---|
| `foodLibraryState` | `FoodLibraryState` | Source of groups + foods cache. Required. |

**Behavior**:
- Renders one `LogFoodRow` per food. The `LogFoodRow` is the actual
  logging affordance (thumbnail toggle + amount input + single-line
  macros); this section is responsible for the grouped list layout +
  the per-row hairline dividers (S-006) only.
- **`_GroupBlock` dividers (S-006)**: between rows within a group, a
  1 px hairline divider (`OmniTheme.colors.divider`) is rendered. No
  divider is rendered above the first row, and no divider is rendered
  after the last row (so the existing 16 px bottom padding on the group
  block provides the gap to the next group). The per-divider key is
  `Key('group_<groupName>_divider_<i>')` where `<i>` is the row index
  that follows the divider (so `divider_1` sits between row 0 and row 1
  in a group; for a 3-row group the dividers are `_divider_1` and
  `_divider_2`, never `_divider_3`). Tests can assert presence by index
  and absence of the post-last-row index in one test each.
- Computes calories per food with `calculateCalories(food)` from
  `lib/core/utils/food_helpers.dart`; calories are never stored on
  the `Food` model.
- Excludes archived groups and archived foods (the default
  `includeArchived: false` is used by `loadFoodGroups()` /
  `loadFoods()`).
- Theme tokens only — colors come from `OmniTheme.colors` and the
  active `ThemeData`; no hardcoded colors.

---

> **Doc freshness** — Last reconciled against source: 2026-07-26. This page is one part of the [Widget Catalog](../widget_catalog.md); see that index for the full component list. This doc is derived from source, not hand-maintained. Source of truth: the `lib/` tree. If you find a claim here that disagrees with `lib/`, `lib/` wins.
