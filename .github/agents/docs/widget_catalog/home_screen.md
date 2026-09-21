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

The home-screen modality tile, and the only home tile implementation. Renders one of two visual
tiers — primary for the four modality tiles, secondary for Free Training and My Routines — and an
 active state when the current session matches the tile. Artwork is height-responsive decoration:
 it is constrained to its allotted region and omitted on short tiles when the label needs the space.
 The active state is announced to screen readers via `Semantics`; its pulsing dot is decorative and excluded from semantics.

**File**: `lib/widgets/cards/energy_core.dart`

The circular icon element inside `EnergyTile`. Presentation-only.

### `MaintenanceTile`

**File**: `lib/widgets/cards/maintenance_tile.dart`

Tile used inside the home maintenance sheet. Styled to be distinguishable from `EnergyTile` at a
glance — no accent fill, no rim, no inner shadow — so system destinations never read as training
actions. The title is flex-constrained so a large system text scale truncates rather than
overflowing the fixed grid cell.

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

The home-screen nutrition gauge card. Pure presentation — no state access and no math; per-macro
calorie contributions are computed on `NutritionState` and passed in. The whole card body is one
tap target, not just the chevron.

- **Empty state** is split across two orthogonal axes — the gauge needs a **goal** (`consumed / target`) while the caption needs **data to split** (P/C/F kcal share of consumed).
  - **Both axes empty** (S-104 / S-201): `consumedCalories <= 0`. Headline renders `"0 / {target ?? "—"} Cal"` in `textDominant`. Gauge fill is not rendered. Caption row renders DASHES (`—`) for each macro, NOT `0%`. We do not imply a real split when there is no data.
  - **Gauge-only empty** (S-200): no target configured (`targetCalories == null`) but food has been logged. Headline renders `"{consumed} / — Cal"`. Gauge fill is hidden (no goal to fill against). Caption row renders the **real** macro percentages (`P 42%`, `C 33%`, `F 25%`) so the user gets actionable feedback. The track still renders at full width so the card layout stays stable.
  - **Caption-empty even with data** (S-202): `consumed > 0` but `proteinKcal + carbsKcal + fatKcal == 0` (a calorie-only entry). Caption row still renders DASHES — we do not show a fake `P 0% / C 0% / F 0%` split when there is no macro data.
When consumption exceeds the target the fill clamps rather than overflowing and the headline
switches to the theme's error tone — a restrained warning, not an alarm.

### `CalorieRing`

**File**: `lib/features/nutrition/widgets/calorie_ring.dart`

Donut showing today's consumed calories against the daily target. A `null` or non-positive target
means consumed-only mode with no goal arc. The fill fraction clamps to the track, but the numeric
label always shows the real consumed value so exceeding the target stays visible. Pure
presentation — no `BuildContext` lookups, no repository access, all maths local.

### `CalorieRingCard`

**File**: `lib/features/nutrition/widgets/calorie_ring_card.dart`

`OmniSurface` wrapper composing `MacroDonutChart` around `CalorieRing`, plus the sodium chip and
the water tracker. Owns the tap-to-focus state for the donut: tapping a section focuses it,
tapping it again or tapping the centre clears. When the focused section's grams fall to zero the
focus falls back to none rather than pointing at nothing. Rebuilds on every `NutritionState`
notification, so a log or unlog anywhere propagates here.

### `WaterTrackerControl`

**File**: `lib/features/nutrition/widgets/water_tracker_control.dart`

Tap-only +/− stepper for the day's water. Water has **no goal** — the widget carries no progress
bar, target, or percentage. The glass count is derived from stored millilitres at the display
boundary; the widget never reads or writes ml itself, and the per-glass amount is sourced from
`kWaterGlassMl` so a future change propagates automatically. Decrement is disabled at zero.

### `MacroDonutChart`

**File**: `lib/features/nutrition/widgets/macro_donut_chart.dart`

Interactive donut wrapping the calorie ring. Renders up to four arc sections — net carbs, fiber,
fat, protein — sized proportionally to grams, and hides itself entirely when all four are zero so
the parent can fall back to the calorie ring alone. The chart owns its focus state and announces
it via `Semantics`; the parent drives *visible* focus by passing per-section opacities.

**Why the hit-test uses raw `atan2` with no offset.** `Canvas.drawArc` measures angles from the
+X axis (3 o'clock), and so does `atan2(dy, dx)`. Because the two conventions already agree, a
section drawn from a given start angle is hit-testable against the unmodified atan2 result — no
rotation correction is needed, and adding one would silently break hit-testing. Section ranges are
half-open `[start, start + sweep)`, so a tap exactly on a boundary resolves to the following
section; when only one macro is non-zero its single section wraps past the 0/2π boundary and the
resolver splits the range accordingly.

The section-angle and label-fit maths are factored into pure top-level functions
(`computeMacroSections`, `computeMacroLabels`, `resolveSectionHit`) so they are unit-testable
without a widget tree. Colours come from `OmniTheme.colors.macroChart`.

### `MacroFocusContent`

**File**: `lib/features/nutrition/widgets/macro_donut_chart.dart`

Rendered in the calorie ring's centre when a macro section is focused, showing the macro name with
its colour marker plus grams and percentage. Passed to `CalorieRing` as its centre override by
`CalorieRingCard`.

---

### `FoodLibraryBrowseSection` (private to `NutritionScreen`)

**File**: `lib/features/nutrition/nutrition_screen.dart` (private `_FoodLibraryBrowseSection`,
plus private `_GroupBlock`)

Read-only, grouped list of foods for the "Foods I Eat" card on `NutritionScreen`. Branches on
`FoodLibraryState` into loading, empty, and data states.

The grouping and order are `foodsIEatSections` in `lib/core/utils/foods_i_eat_order.dart` — the
single owner of the rule for both this card and the watch's synced list. Verified by
`test/watch_nutrition_quick_log_test.dart` (S-003).

Rows are `LogFoodRow` (`lib/features/nutrition/widgets/log_food_row.dart`), which owns the logging
affordance; this section owns the grouped list layout only. Archived groups and archived foods are
excluded.

---

> **Doc freshness** — Last reconciled against source: 2026-07-26. This page is one part of the [Widget Catalog](../widget_catalog.md); see that index for the full component list. This doc is derived from source, not hand-maintained. Source of truth: the `lib/` tree. If you find a claim here that disagrees with `lib/`, `lib/` wins.
