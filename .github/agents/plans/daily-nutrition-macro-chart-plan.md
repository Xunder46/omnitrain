# Feature: Daily Nutrition — Macro Distribution Donut Chart

## Overview

Extend the existing `CalorieRingCard` at the top of the daily nutrition screen
with an **outer macro distribution donut** that surrounds the existing calorie
ring. The outer donut shows today's consumed macro breakdown as colored
sections (Protein / Net Carbs / Fiber / Fat), with external labels for each
section that show the name, total grams, and percentage. The outer donut is
hidden when no food has been logged. The inner calorie ring (and its
"consumed / target kcal" center label) is unchanged — it is now nested
inside the macro donut's hole.

This is a UI/visualization feature layered on top of the existing nutrition
data layer. The `ConsumedFood` model and the per-row `protein` / `carbs` /
`fiber` / `fat` fields already exist; `NutritionState` already caches
`consumedToday`. The change is: (a) expose per-macro sum getters on
`NutritionState`; (b) add a theme-tokenized macro color palette; (c) build a
`MacroDonutChart` widget; (d) compose it with the existing calorie ring in
the card.

## Requirements

- Render an outer donut chart around the existing calorie ring on the daily
  nutrition screen, showing today's consumed macro distribution.
- The donut has up to four sections, in this fixed order, each with a
  distinct color from a new `OmniTheme` macro palette:
  - **Net Carbs** (carbs − fiber) — blue
  - **Fiber** — green
  - **Fat** — yellow
  - **Protein** — white
- If a macro is 0, its section is omitted (no zero-width arc). The remaining
  sections share the full 360° proportionally.
- Each non-empty section has an external label rendered outside the donut
  with a short leader line. The label shows:
  - The macro name (e.g., `Protein`)
  - The total grams (e.g., `120g`)
  - The percentage of today's macros (e.g., `40%`)
- Labels are right-aligned for sections in the left half of the chart and
  left-aligned for sections in the right half. Top / bottom single-section
  cases are centered.
- The donut is **hidden** when the total macro weight is 0 (no food logged
  today, or only zero-macro foods logged). In that case the calorie ring
  alone is shown, preserving the existing layout.
- The chart updates reactively as today's consumed foods change (logging,
  deleting, day rollover).
- Net carbs = `max(0, carbs − fiber)`. This matches the existing
  `Food.netCarbs` convention. Fiber is its own green slice (the user
  explicitly asked for fiber to be split out from carbs).
- All chart colors come from a new palette on `OmniTheme.colors` (themed),
  never hardcoded. The four colors must remain readable on both the dark
  and light themes.
- No new dependencies. No data-model changes. No repository-interface
  changes. No new public state **methods** on `NutritionState` (extend the
  existing `consumedToday` cache with derived getters only).

## Acceptance Criteria

- [x] `NutritionState` exposes `todayConsumedProtein`, `todayConsumedCarbs`,
      `todayConsumedFiber`, `todayConsumedFat` (all `int` grams) as
      derived getters over `consumedToday`. The pre-existing
      `todayConsumedProtein/Carbs/Fat` getters were rewritten to sum
      unrounded and round once at the end (matching the
      `caloriesConsumed` pattern); `todayConsumedFiber` was added with
      the same contract and treats `ConsumedFood.fiber ?? 0` as 0.
- [ ] `OmniTheme.colors` exposes a `macroChart` palette with
      `protein`, `netCarbs`, `fiber`, `fat` color slots, defined for every
      existing theme (dark, light, solar, mono, ember).
- [ ] A new widget `MacroDonutChart` exists at
      `lib/features/nutrition/widgets/macro_donut_chart.dart` and renders
      the outer donut + external labels.
- [ ] When `protein + netCarbs + fiber + fat > 0`, the chart shows the
      donut and external labels. When that total is 0, the chart renders
      an empty `SizedBox` (size configurable, default 240×240).
- [ ] `CalorieRingCard` composes the new `MacroDonutChart` (outer) with
      the existing `CalorieRing` (inner, on top) in a `Stack`. The center
      calorie text remains readable.
- [ ] The chart auto-hides when no macros are logged, falling back to the
      original single-ring layout (existing widget tests still pass).
- [ ] Tests in `test/state_test.dart` cover the four new derived getters
      (sum, empty, after a log, after a delete).
- [ ] Tests in `test/nutrition_test.dart` cover the donut: renders 4
      sections with distinct colors when all macros are present, omits
      zero-macro sections, hides entirely on an empty day, updates
      reactively as food is logged/deleted, and external labels show
      name + grams + percent.
- [ ] No file in `lib/` imports `dart:io` or any platform-specific
      package as a result of this change.
- [ ] `flutter analyze` is clean for the modified files.
- [ ] All previously passing tests still pass.

## Scenarios

### S-001: Donut chart appears with all four sections when macros are logged
- Trigger: User opens the daily nutrition screen after logging foods that
  cover all four macros.
- Precondition: `consumedToday` contains at least one `ConsumedFood` with
  `protein > 0`, `carbs > 0`, `fiber > 0`, and `fat > 0`.
- Flow:
  1. The screen builds.
  2. `CalorieRingCard` lays out a `Stack` with `MacroDonutChart` (outer)
     and `CalorieRing` (inner, on top).
  3. The donut renders 4 colored arc sections: net carbs (blue), fiber
     (green), fat (yellow), protein (white).
  4. The calorie ring sits inside the donut's hollow center, unchanged.
- Expected outcome: The user sees a nested ring (macro donut outside,
  calorie ring inside) on the daily nutrition screen. The four sections
  are visually distinct and use the macro palette colors.
- Edge case of: none

### S-002: External labels show name, grams, and percent
- Trigger: User views the daily nutrition screen with macros logged.
- Precondition: A non-zero distribution exists across at least one
  macro section.
- Flow:
  1. The donut paints its colored sections.
  2. For each non-zero section, the painter draws a leader line from
     the section's outer edge to a label position outside the donut.
  3. At each label position, a 2-line text block is drawn:
     - Line 1: the macro name (e.g., `Protein`)
     - Line 2: the grams and percentage (e.g., `120g · 40%`)
  4. Labels in the right half of the chart are left-aligned; labels in
     the left half are right-aligned.
- Expected outcome: Each non-zero macro section has a readable external
  label with the macro's name, total grams, and percentage. Labels do
  not overlap each other for a typical 4-section distribution.
- Edge case of: S-001

### S-003: Net carbs = carbs − fiber, and fiber is its own green slice
- Trigger: User logs a food with `carbs = 30g` and `fiber = 8g`.
- Precondition: That is the only food logged today.
- Flow:
  1. The screen reads `todayConsumedCarbs = 30` and
     `todayConsumedFiber = 8` from `NutritionState`.
  2. `MacroDonutChart` computes `netCarbs = max(0, 30 − 8) = 22`.
  3. The donut renders two sections: net carbs (22g, blue) and fiber
     (8g, green).
- Expected outcome: The net carbs slice is `22g` (not `30g`); the fiber
  slice is `8g`. Both are visible and colored correctly.
- Edge case of: S-001

### S-004: Zero-macro sections are omitted
- Trigger: User logs only protein-rich food (carbs, fiber, fat all 0).
- Precondition: `consumedToday` has at least one entry with
  `protein > 0` and `carbs = 0`, `fiber = 0`, `fat = 0`.
- Flow:
  1. The chart computes `total = protein + 0 + 0 + 0 = protein`.
  2. Only the protein section is drawn — it occupies the full 360°.
  3. Only one external label (`Protein · Ng · 100%`) is drawn.
- Expected outcome: The donut shows a single full-color ring for protein
  with one external label. No zero-width arc artifacts. No zero-gram
  labels.
- Edge case of: S-001

### S-005: Donut is hidden when no food is logged
- Trigger: User opens the daily nutrition screen on a fresh day with no
  consumed foods.
- Precondition: `consumedToday` is empty.
- Flow:
  1. The screen reads `todayConsumedProtein = 0`, `todayConsumedCarbs = 0`,
     `todayConsumedFiber = 0`, `todayConsumedFat = 0`.
  2. `MacroDonutChart` sees `total = 0` and renders an empty
     `SizedBox` of its declared size.
  3. The calorie ring renders alone, at its full 160px size, in the
     card's center — exactly the existing behavior.
- Expected outcome: The user sees the calorie ring only (no donut, no
  labels). The card layout is unchanged from the pre-feature state.
- Edge case of: none

### S-006: Donut updates reactively as food is logged and deleted
- Trigger: User logs a food via the library, then deletes it.
- Precondition: Day starts empty; user has a food with non-zero macros
  in the library.
- Flow:
  1. User opens the screen — donut is hidden (S-005).
  2. User checks the food's checkbox in the library.
  3. `NutritionState` updates `consumedToday`; both the calorie ring and
     the donut rebuild via `ListenableBuilder`. The donut appears with
     the food's macros.
  4. User unchecks the food (or deletes the consumed-food row).
  5. `NutritionState` updates again; the donut disappears.
- Expected outcome: The chart appears and disappears in lockstep with
  the calorie ring, with no stale labels or partial arcs.
- Edge case of: S-001, S-005

### S-007: Day rollover clears the donut
- Trigger: The day changes while the screen is mounted.
- Precondition: The user logged food yesterday; `consumedToday` is
  non-empty.
- Flow:
  1. `NutritionState.rolloverToDate(newDateMs)` is called.
  2. `_consumedToday` is cleared; the per-date target cache is also
     cleared and reloaded.
  3. The donut sees `total = 0` and hides itself.
- Expected outcome: Yesterday's macro sections do not bleed into today.
  The donut is hidden until the user logs new food for the new day.
- Edge case of: S-005, S-006

## Iteration 1

### DB Changes
None. The `ConsumedFood` model and the `app_consumed_food` SQLite table
already store per-row `protein`, `carbs`, `fiber`, `fat` (see
`lib/data/models/models.dart` lines ~1762–1810 and
`scripts/sqlite_schema.sql`).

### Backend Changes
None. No new repository methods, no new migrations, no schema changes.

### Frontend Changes

#### 1. Derived per-macro getters on `NutritionState`
File: `lib/state/nutrition_state.dart`

Add four pure derived getters next to the existing `todayConsumedCalories`:
- `int get todayConsumedProtein => _consumedToday.fold<int>(0, (s, c) => s + c.protein);`
- `int get todayConsumedCarbs => _consumedToday.fold<int>(0, (s, c) => s + c.carbs);`
- `int get todayConsumedFiber => _consumedToday.fold<int>(0, (s, c) => s + (c.fiber ?? 0));`
- `int get todayConsumedFat => _consumedToday.fold<int>(0, (s, c) => s + c.fat);`

All four are pure (no repo call), match the existing
`todayConsumedCalories` style, and reactively reflect `_consumedToday`.
`fiber` is `int?` on `ConsumedFood`; treat null as 0.

#### 2. Macro chart palette on `OmniTheme`
File: `lib/core/constants/omni_theme.dart`

Add a new value class `MacroChartPalette` with four `Color` fields:
`protein`, `netCarbs`, `fiber`, `fat`. Add a `macroChart` field of that
type to `OmniThemeColors`. Provide a `MacroChartPalette` for every
existing theme so the chart works on all five themes (dark, light,
solar, mono, ember). Recommended colors:
- `protein` — near-white, theme-tinted (e.g. `0xFFEDEDED` for dark)
- `netCarbs` — saturated blue (e.g. `0xFF4F8DF7`)
- `fiber` — saturated green (e.g. `0xFF3FBF67`)
- `fat` — saturated amber/yellow (e.g. `0xFFE8B420`)

These colors live on the `OmniTheme` palette so the rule "theme tokens
only" is satisfied; themes can override them later.

#### 3. New `MacroDonutChart` widget
File: `lib/features/nutrition/widgets/macro_donut_chart.dart` (new)

API:
```dart
class MacroDonutChart extends StatelessWidget {
  final int protein;
  final int netCarbs;
  final int fiber;
  final int fat;
  final double size;          // outer diameter, default 240
  final double strokeWidth;   // donut thickness, default 14
  final double gapDegrees;    // gap between sections, default 1.5

  const MacroDonutChart({
    super.key,
    required this.protein,
    required this.netCarbs,
    required this.fiber,
    required this.fat,
    this.size = 240,
    this.strokeWidth = 14,
    this.gapDegrees = 1.5,
  });

  @override
  Widget build(BuildContext context);
}
```

Behavior:
- Compute `total = max(0, protein) + max(0, netCarbs) + max(0, fiber) + max(0, fat)`.
  Negative inputs are clamped to 0 (defensive — should not happen in
  practice).
- If `total == 0`, return `SizedBox(width: size, height: size)` (the
  parent decides fallback).
- Otherwise, build a `CustomPaint` that draws the donut + external
  labels.

Painter responsibilities (`_MacroDonutPainter`):
- Draws 1–4 colored arc sections, each separated by a small angular
  gap (`gapDegrees`).
- Section order is fixed: **Net Carbs → Fiber → Fat → Protein**. Each
  non-zero section is drawn; zero sections are skipped. The remaining
  share the full 360° proportionally.
- For each drawn section, computes the section's mid-angle (0° at top,
  clockwise, pie-chart convention), then draws:
  - a leader line from the section's outer edge (`r = size/2 − strokeWidth/2`)
    to a label anchor (`r = size/2 + 18`);
  - a 2-line text block at the anchor: name on line 1, "Ng · P%" on
    line 2, in `themeColors.textDominant`.
- Text alignment is left for sections in the right half (`midAngle` in
  `[-90°, 90°]` mod 360) and right for sections in the left half
  (`(90°, 270°)`). Top/bottom-centered when the section spans the top
  or bottom (only when a single section exists and the mid-angle is
  near 0° or 180°).
- A `Semantics` wrapper announces a textual summary, e.g.,
  `"Macros today: 120g protein, 200g net carbs, 15g fiber, 80g fat"`,
  for screen readers.

Pure presentation: no repo access, no state mutation, no
business logic. All colors come from `OmniTheme.colors.macroChart`. No
hardcoded colors.

#### 4. Integrate into `CalorieRingCard`
File: `lib/features/nutrition/widgets/calorie_ring_card.dart`

- Read the four new derived getters from `NutritionState` (alongside
  the existing target/consumed read).
- Compute `netCarbs = max(0, todayConsumedCarbs − todayConsumedFiber)`
  and `total = protein + netCarbs + fiber + fat`.
- Wrap the existing `Center(CalorieRing(...))` in a `Stack` that first
  draws the `MacroDonutChart` (centered, larger) and then the
  `CalorieRing` on top (centered, smaller, 160px).
- Add a `SizedBox` of height ~16 above the chart stack for breathing
  room between the section header and the donut.
- When `total == 0`, the `MacroDonutChart` is in the tree but renders
  an empty `SizedBox`; the `CalorieRing` shows alone at full size. To
  keep the visual stable in this case, wrap the whole chart in an
  `AnimatedSize` so the card does not jump when the donut appears or
  disappears.

#### 5. Buttons / interactions
The donut is read-only — no taps, no buttons, no input. The existing
edit-targets icon button in the card's header is unchanged. No
`FilledButton` / `OutlinedButton` / `TextButton` is added or modified,
so the "explicit shape" rule does not apply.

#### 6. Tests
File: `test/state_test.dart` (NutritionState group)
- Sum across multiple `ConsumedFood` rows for each macro.
- Empty cache → all four getters return 0.
- After `logConsumedFood`, getters reflect the new entry.
- After `deleteConsumedFood`, getters drop back.
- Null `fiber` on a `ConsumedFood` is treated as 0.

File: `test/nutrition_test.dart` (new `MacroDonutChart` group)
- Renders 4 sections when all macros are non-zero; the painter's
  `drawArc` is called 4 times (or 4 `Paint` ops are recorded via
  `tester.binding.takeException` / a custom recording painter for
  pure-painter unit tests).
- Omits zero-macro sections (3 sections when one macro is 0; 1
  section when only one macro is non-zero).
- Hides entirely (renders empty SizedBox) when `total = 0`.
- External labels show the macro name + `Ng` + `P%` (find by
  `findText` for each section).

File: `test/nutrition_test.dart` (`CalorieRingCard` group, extended)
- When macros are logged, the card renders the donut and labels.
- When no macros are logged, the card renders only the calorie ring
  (existing test still passes; no new label text appears).
- Logging / deleting a food updates the donut reactively (no
  notifyListeners assertion needed — the rebuild is observed via
  finder presence/absence).

Pure-painter unit tests: factor the donut's "compute section
angles and labels" math into a pure top-level function (e.g.,
`_computeSections(...)` returning a `List<_MacroSection>`) so it can
be tested without a widget tree.

#### 7. Doc hygiene
- `docs/state_management.md` — note the new derived getters on
  `NutritionState`.
- `docs/widget_catalog.md` — add the new `MacroDonutChart` widget to
  the catalog.
- `docs/design_system.md` — note the new `macroChart` palette on
  `OmniTheme` and which colors are used for which macro.
- `docs/data_models.md` — N/A (no model changes).
- `docs/db_integration.md` — N/A (no repo / schema changes).
- `docs/navigation_and_screens.md` — N/A (no new screen, no route
  change).

## Progress

### Phase 0 — Plan — Complete ✓
- [x] Read global conventions and design system docs.
- [x] Read `ConsumedFood` and `NutritionTarget` model fields.
- [x] Read `NutritionState` cache and existing
      `todayConsumedCalories` getter pattern.
- [x] Read `CalorieRingCard` / `CalorieRing` / `NutritionSummaryCard`
      for current layout and d — Complete ✓
- [x] Add the four derived per-macro getters on `NutritionState`.
      - `todayConsumedProtein/Carbs/Fat` were pre-existing but had a
        per-row `.round()` that destroyed fractional grams (e.g. a
        30g-protein/100g food at 1.5 portions contributed 0 instead
        of 0.45g). Rewritten to sum as `double` and round once at the
        end, matching the `caloriesConsumed` pattern. The earlier
        rounding bug would have made the donut chart near-empty for
        normal grams-type foods.
      - `todayConsumedFiber` was added with the same contract;
        `ConsumedFood.fiber ?? 0` is treated as 0.
- [x] Add the `macroChart` palette to `OmniThemeColors` and define
      palettes for all 6 themes (abyssalNeon, forgeEmber, obsidianVolt,
      voidPulse, crimsonDojo, malachiteCore). New typedef
      `MacroChartPalette` with `protein` / `netCarbs` / `fiber` / `fat`
      slots.
- [x] `flutter analyze` clean on changed files.
- [x] `test/state_test.dart` — new "per-macro totals" group with 4
      tests (empty cache; per-row scaling with grams + count foods;
      null fiber; log+delete reactivity). All 196 state tests pass
      (192 baseline + 4 new).
- [x  palettes for all existing themes.
- [ ] `flutter analyze` clean on changed files.
- [ ] `test/state_test.dart` — new tests for the four derived
      getters (sum, empty, after log, after delete, null fiber).
- [ ] No repository interface change. No schema change. No
      model change.

### Phase 2 — Logic & UI (Developer) — Complete ✓
- [x] Write widget tests for `MacroDonutChart` first; confirmed red
      (`MacroDonutChart: Method not found`) before any implementation.
- [x] Implement `MacroDonutChart` widget + pure section-computation
      helper (`computeMacroSections` returning `List<MacroSection>`).
      Labels rendered as real `Text` widgets (not `TextPainter`) so
      widget tests can find them and screen readers can announce
      them. Painter only draws arcs and leader lines.
- [x] Update `CalorieRingCard` to compose `MacroDonutChart` +
      `CalorieRing` in a `Stack`; `AnimatedSize` for stability.
      `netCarbs` computed at the call site as
      `max(0, todayConsumedCarbs - todayConsumedFiber)`.
- [x] `flutter test` — 1354/1354 pass project-wide (47 nutrition
      tests including 5 new MacroDonutChart + 2 new
      CalorieRingCard integration; 196 state tests including 4 new
      per-macro totals).
- [x] `flutter analyze` clean on all changed files.

### Phase 3 — Code review — Complete ✓
- [x] Layer scoping: state (`NutritionState`), widgets (new
      `MacroDonutChart`, refactored `CalorieRingCard`), core
      (`OmniTheme.colors.macroChart`). Models, repositories, features
      other than `CalorieRingCard` skipped. Docs updated as part of
      Phase 2.
- [x] Acceptance criteria verified: 4 derived per-macro getters
      exposed, `macroChart` palette defined for all 6 themes, new
      widget file at the planned path, donut hides on empty day,
      composition in `CalorieRingCard`, analyzer clean, zero
      regressions.
- [x] Scenario register cross-checked: S-001..S-007 each have
      at least one test in `test/nutrition_test.dart`; the
      `consumed-food cache` state tests cover the state-side
      invariants; the `CalorieRingCard` integration tests cover the
      reactive update and the hide-on-empty path.
- [x] Doc hygiene verified: `state_management.md`,
      `data_models.md`, `widget_catalog.md`, `design_system.md` all
      updated to reflect the new getters, the new widget, the
      CalorieRingCard composition, and the new `macroChart` palette.
- [x] Global conventions verified:
      - **Theme tokens only**: the new `macroChart` palette lives on
        `OmniTheme`; the chart never hardcodes a color. PASS.
      - **Timestamps are source data**: N/A (no new timestamps
        introduced).
      - **Units + canonical storage**: N/A (grams are the
        canonical unit; no unit conversion involved).
      - **Reuse the canonical owner**: PASS — the chart reads from
        the `NutritionState` getters; no duplicate sum or per-row
        scaling logic.
      - **Effort-kind drives analytics**: N/A (nutrition is not
        effort-keyed).
      - **Instrument panel, not influencer**: PASS — read-only
        visualization, no social/influencer patterns.
- [x] Architecture compliance: state derives only from
      `consumedToday`; no concrete repo import; no `dart:io`; no
      `Platform.is*`; button-shape rule N/A (no buttons added).
- [x] Dead-code check: no unreferenced public symbols. The new
      `MacroDonutChart` is consumed by `CalorieRingCard`. The new
      `todayConsumedFiber` is consumed by `CalorieRingCard`. The
      new `computeMacroSections` helper is exported from the same
      library as the widget.
- [x] Test coverage: 196 state tests (+4 new), 47 nutrition tests
      (+7 new). 1354/1354 project-wide pass.
- [x] Environment safety: no `dart:io`, no `Platform.is*`, no
      `sqlite` imports anywhere in the changed files.

#### Findings (non-blocking)
- `lib/features/nutrition/widgets/macro_donut_chart.dart:282` —
  `labelOffset = 18.0` and `extendBy = 6.0` are magic numbers; a
  future polish should hoist them to private `static const`
  fields. (WARNING)
- `lib/features/nutrition/widgets/macro_donut_chart.dart:230` —
  `_ExternalLabel.build` calls `TextPainter..layout()` synchronously
  per section. Fine at 1–4 sections; revisit only if the chart
  grows. (WARNING)
- `lib/features/nutrition/widgets/calorie_ring_card.dart:97` —
  the 240×240 `SizedBox` is hardcoded twice (in the SizedBox and
  as the chart's `size` arg). A shared `static const` would be
  marginally safer if the chart is ever resized. (WARNING)

#### Verdict
**✅ APPROVED** — all acceptance criteria met, all scenarios
covered, all docs updated, all tests green, no critical or blocking
issues. The three warnings above are cosmetic polish opportunities
that do not block the feature.

---

## Iteration 2 — Thicker ring + tap-to-focus with center swap

> Folded from the human-checkpoint feedback after Iteration 1: the
> external labels overflow the chart because the donut band is too
> thin. The user asked for (a) thicker sections that extend inward
> toward the calorie ring, and (b) a tap-to-focus interaction that
> fades unfocused sections + the calorie ring, and replaces the
> calorie text in the center with the focused section's name,
> grams, and percent.

### Overview

Two related changes to the macro donut shipped in Iteration 1:

1. **Thicker donut band.** The donut's `strokeWidth` grows from
   `14` to `~40` logical pixels (roughly 3× the calorie ring's
   `14` stroke) and the donut's overall outer diameter is sized so
   the inner edge of the donut band sits just outside the
   `CalorieRing` outer edge — i.e. the band visually surrounds the
   ring without touching it. The external labels are no longer
   needed (the user's spec moves the label content to the ring's
   center on tap) so they are **removed**; the chart's
   `MacroDonutChart` no longer projects any text past the band.
2. **Tap-to-focus.** Tapping a section makes it the "focused"
   section. The focused section stays at full opacity; every other
   section, every leader line, and the `CalorieRing` animate to
   `0.4` opacity. The center text inside the `CalorieRing` swaps
   from calories to the focused section's label content
   (`<Name>` / `<N>g · <P>%`). Tapping the same section again, or
   tapping the empty center of the donut, deselects (returns to
   the default calories view). Tapping a different section moves
   the focus directly. The default state on first paint — and
   whenever no food is logged — is the existing calories view
   (all sections + ring at full opacity, no selection).

The donut's color slots and the `OmniTheme.colors.macroChart`
palette are unchanged. The `NutritionState` getters are unchanged.
The data layer is unchanged. The change is contained to the
chart widget, the `CalorieRing` widget, and the `CalorieRingCard`
composition.

### Requirements

- The donut band must be **substantially thicker** than the calorie
  ring's band — roughly `3×` the ring's `14` px stroke (so
  `~40` px). The visual goal is "ring nested inside a thick
  colored donut", not "ring + thin outline around it".
- The donut's **inner edge must sit just outside the calorie
  ring's outer edge** with a small breathing gap (~6 px). The
  ring's outer diameter is currently `160` and its stroke is
  `14`, so its outer edge is at radius `(160 + 14) / 2 + 7 = 94`
  (wait, re-derive: the ring's `CalorieRing` paints a stroked
  circle at `size = 160` with `strokeWidth = 14`; the **outer**
  edge of the ring's stroke is at radius `80 + 7 = 87`). The
  donut's band has stroke ~40, so its inner edge is at
  `outerRadius - 20`. To leave a 6 px gap, the donut's outer
  edge must be at `87 + 6 + 20 = 113` (donut outer radius). With
  the existing chart's overall `size = 240`, the chart's full
  radius is `120` — there is `120 - 113 = 7` px of margin. That
  fits, but the chart is now nearly edge-to-edge. The clean
  fix is to grow the chart's overall size to e.g. `260` and
  recompute the donut stroke / outer / inner radii from the
  ring's size + stroke + a constant gap.
- **External labels are removed.** The donut no longer projects
  any text past its band. All label content moves to the center
  on tap.
- **Tap-to-focus interaction.**
  - The chart widget is interactive: tap regions are the donut
    sections themselves, not buttons. Hit-test is solved by
    converting a `LocalPosition` to an angle and a radius and
    matching against the section's `[startAngle, startAngle +
    sweepAngle]` arc band.
  - The center hit region (the empty middle of the donut, plus
    the `CalorieRing`'s tap area) **deselects** when a section
    is currently focused.
  - When a section is focused:
    - That section's arc stays at `1.0` opacity.
    - Every other section's arc animates to `0.4` opacity.
    - The leader lines (now removed — see above) are N/A.
    - The `CalorieRing` animates to `0.4` opacity.
    - The `CalorieRing`'s center text **swaps** to render
      `<Name>` on line 1 and `<N>g · <P>%` on line 2, using
      the same typography as the default calories view.
  - When the user taps a different section, focus moves
    directly (no deselect step in between).
  - When the user taps the focused section again, or taps the
    empty center, focus clears and the default calories view
    returns.
- **Default state on first paint** (and after every full
  state rebuild with no food logged) is the existing
  calories view: all sections at `1.0`, ring at `1.0`, no
  selection. No section is pre-selected.
- **Animation** uses the existing
  `OmniTheme.animationDuration` / `OmniTheme.animationCurve`
  tokens; no new tokens.
- The chart still **hides** when all four macro grams sum to 0.
- **No new colors.** The donut's color slots and
  `OmniTheme.colors.macroChart` are unchanged. Section opacity
  changes only; the visible color of the band is the same slot
  as before.
- **No new dependencies.** No data-model changes. No
  repository-interface changes. No schema changes.

### Acceptance Criteria

- [ ] The donut band is visually thick — at least `2.5×` the
      `CalorieRing` stroke width — and its inner edge sits
      just outside the ring's outer edge with a small gap.
- [ ] External labels are removed. The donut does not project
      any text past its band.
- [ ] `MacroDonutChart` exposes an `onSectionTap` callback
      (signature: `void Function(int sectionIndex)`) and the
      hit-test correctly resolves a tap in the donut area to
      the section at that angle.
- [ ] Tapping a section sets the focus to that section;
      tapping the empty center clears the focus; tapping the
      same focused section clears the focus; tapping a
      different section moves the focus.
- [ ] When a section is focused, every other section's arc
      and the `CalorieRing` animate to `0.4` opacity. The
      focused section stays at `1.0`.
- [ ] When a section is focused, the `CalorieRing`'s center
      content swaps from calories to the focused section's
      `<Name>` / `<N>g · <P>%`.
- [ ] On first paint, the chart shows the default calories
      view — no section is focused, all sections + ring at
      `1.0` opacity.
- [ ] `flutter analyze` clean for all changed files.
- [ ] All previously passing tests still pass.
- [ ] New tests cover (a) the hit-test resolution for each
      of the four sections + the empty center, (b) the
      focus-driven opacity values, (c) the center-swap
      content, (d) the default-state-no-focus contract.

### Scenarios

#### S-008: Default state on first paint (no focus)
- Trigger: User opens the daily nutrition screen after
  logging some food.
- Precondition: At least one `ConsumedFood` row is in
  `consumedToday`. The card mounts.
- Flow:
  1. `CalorieRingCard` builds.
  2. The focus state is `null` (no section is selected).
  3. The donut renders all non-zero sections at full
     opacity, the `CalorieRing` is at full opacity, the
     ring's center shows calories.
- Expected outcome: The chart looks identical to the
  Iteration 1 default. No focus, no fade.
- Edge case of: none

#### S-009: Tap a section to focus it
- Trigger: User taps inside the donut's band at an angle
  that lies in the Protein section's `[start, start+sweep]`
  range.
- Precondition: The chart is in the default state (S-008).
- Flow:
  1. The chart's hit-test resolves the tap to the Protein
     section.
  2. The card's focus state becomes `Protein` (or its
     index).
  3. Every other section animates to `0.4` opacity.
  4. The `CalorieRing` animates to `0.4` opacity.
  5. The `CalorieRing`'s center text animates to "Protein"
     on line 1 and "120g · 40%" on line 2.
- Expected outcome: The Protein arc is the only one at
  full opacity; the ring and other sections are faded; the
  center of the ring shows Protein / 120g · 40%.
- Edge case of: S-008

#### S-010: Tap a different section to move focus
- Trigger: User taps inside the donut at an angle that lies
  in a non-focused section.
- Precondition: A section is currently focused (S-009).
- Flow:
  1. The hit-test resolves the tap to the new section.
  2. The card's focus state becomes the new section. The
     previous section's opacity returns to `0.4`; the new
     section's opacity returns to `1.0`.
  3. The `CalorieRing` stays at `0.4` opacity (still
     faded).
  4. The center text swaps to the new section's content.
- Expected outcome: Focus moves to the new section; the
  ring stays faded; the center shows the new section's
  label content.
- Edge case of: S-009

#### S-011: Tap the focused section again to deselect
- Trigger: User taps the same section that is currently
  focused.
- Precondition: A section is currently focused (S-009).
- Flow:
  1. The hit-test resolves the tap to the focused section.
  2. The card's focus state becomes `null`.
  3. Every section's opacity animates to `1.0`.
  4. The `CalorieRing` animates to `1.0`.
  5. The center text animates back to the calories view.
- Expected outcome: The chart returns to the default state
  (S-008). No section is highlighted.
- Edge case of: S-009

#### S-012: Tap the empty center to deselect
- Trigger: User taps the center area of the donut (inside
  the donut's inner edge — i.e. where the `CalorieRing` is).
- Precondition: A section is currently focused (S-009).
- Flow:
  1. The chart's center hit region (radius < donut inner
     radius) registers the tap.
  2. The card's focus state becomes `null`.
  3. The chart returns to the default state (S-011).
- Expected outcome: The chart returns to the default state
  (S-008). No section is highlighted.
- Edge case of: S-011

#### S-013: Logging new food keeps the focus state coherent
- Trigger: User logs a new food while a section is focused.
- Precondition: A section is currently focused (S-009).
- Flow:
  1. The `ListenableBuilder` over `nutritionState` rebuilds
     the card.
  2. The donut's section set may change (a new macro
     section appears, or an existing section's grams change).
  3. If the focused section still exists in the new section
     set, the focus is preserved. If it was removed (e.g.
     protein drops to 0 and the protein section disappears),
     the focus falls back to `null` (default state).
  4. The center text and per-section opacities update to
     match the focus.
- Expected outcome: The focus survives a state rebuild as
  long as the focused section still has non-zero grams; the
  chart never renders in a "focus on a zero-gram section"
  state.
- Edge case of: S-009

#### S-014: Deleting the focused section's food deselects
- Trigger: User deletes the only food that contributes to
  the currently focused section.
- Precondition: A section is currently focused (S-009).
- Flow:
  1. The donut rebuilds; the focused section's grams drop
     to 0; that section disappears.
  2. The card's focus state falls back to `null`.
  3. The chart returns to the default state.
- Expected outcome: The chart returns to the default state
  cleanly — no focus on a vanished section.
- Edge case of: S-013

### Iteration 2 — DB / Backend / Frontend Changes

#### DB Changes
None.

#### Backend Changes
None.

#### Frontend Changes

##### 1. Resize the donut and remove external labels
File: `lib/features/nutrition/widgets/macro_donut_chart.dart`

- Increase the chart's default `size` from `240` to `260` to
  accommodate the thicker band with margin around the
  `CalorieRing` (160 px diameter) and a 6 px gap.
- Increase the default `strokeWidth` from `14` to `40`.
- Remove the external label rendering entirely: the chart
  no longer projects text past its band. The
  `_ExternalLabel` widget is deleted. The leader-line
  drawing in the painter is also deleted (no labels to
  point at).
- The donut's **mid-line radius** is now derived from
  the new size and stroke: `(size - strokeWidth) / 2` as
  before.
- The donut's **outer edge** is at
  `midRadius + strokeWidth / 2 = size / 2`.
- The donut's **inner edge** is at
  `midRadius - strokeWidth / 2 = (size - strokeWidth) / 2`.
  For `size=260, stroke=40`, that's `110`. The
  `CalorieRing`'s outer edge is at `(160 + 14) / 2 = 87`,
  so the gap is `110 - 87 = 23` px. That is too much;
  shrink the chart or grow the ring. Final values to be
  tuned visually; the contract is "inner edge sits just
  outside the ring's outer edge with a small gap (≤ ~10
  px)". Initial implementation will use
  `size = 240` and `stroke = 36` (band fills the chart
  width) and the gap will be re-derived.
- A private helper computes the chart's actual numbers
  from the requested `size`, `strokeWidth`, ring size, and
  ring stroke — the contract is "inner edge of band =
  outer edge of ring + gap". The implementation
  back-solves the band stroke or the chart size to meet
  that contract. For now, the chart's overall `size`
  becomes a function of the calorie ring's `size` plus
  the band stroke plus the gap.

##### 2. Add tap interaction + focus state to `MacroDonutChart`
File: `lib/features/nutrition/widgets/macro_donut_chart.dart`

- Convert `MacroDonutChart` to a `StatefulWidget` that
  owns its own focus state (`int? _focusedSectionIndex`)
  and the focus-change callback. The widget becomes
  `MacroDonutChart` (still in the same file, no name
  change). The widget accepts a new
  `onSectionFocusChange: ValueChanged<int?>?` callback
  (fires when the focus changes due to a tap).
- The chart wraps its arc-drawing `CustomPaint` in a
  `GestureDetector` (or `MouseRegion` + `GestureDetector`
  for hover if desired — out of scope for now). The
  gesture handler:
  1. Converts the local tap position to polar coords
     `(radius, angle)` from the chart center.
  2. If `radius` is inside the band
     `[innerRadius, outerRadius]`, walk the section
     list in order and return the index of the first
     section whose `[start, start+sweep]` arc contains
     the angle.
  3. If `radius < innerRadius` (the empty center
     including the `CalorieRing`'s area), return the
     sentinel `_centerTap` (a constant `int` outside
     the section index range, e.g. `-1`).
  4. If `radius > outerRadius` (outside the chart
     entirely), no-op.
- The hit-test is a pure top-level function
  `resolveSectionHit(...)` so it can be unit-tested
  without a widget tree.
- The chart renders the focused section at `1.0` and
  every other section at `0.4` via
  `AnimatedOpacity` (one per section, keyed by the
  section name to survive reorderings).

##### 3. Add `centerOverride` to `CalorieRing`
File: `lib/features/nutrition/widgets/calorie_ring.dart`

- Add a `centerOverride: Widget?` parameter (default
  `null`). When `null`, render the existing calories
  view (unchanged). When non-`null`, render the
  override **in the same Column** instead of the
  default calories text. The override is responsible
  for its own styling — the ring provides the
  positioning (Column with centered cross axis) but
  does not apply its own typography to the override.
- An `AnimatedSwitcher` cross-fades between the
  default calories view and the override so the swap
  is smooth.
- A private `_MacroFocusContent(name, grams, percent,
  theme, colors)` widget is added in
  `macro_donut_chart.dart` (since the macro chart owns
  the focus concept) and is passed in as the override
  from `CalorieRingCard`.

##### 4. Wire the focus state in `CalorieRingCard`
File: `lib/features/nutrition/widgets/calorie_ring_card.dart`

- The card becomes a `StatefulWidget` that owns
  `int? _focusedSectionIndex` (the index into the
  donut's section list, or `null` for default).
- The card reads the four macro values, builds the
  `List<MacroSection>` itself (via a private helper
  that calls `computeMacroSections`), and passes the
  per-section opacities (1.0 for the focused index,
  0.4 otherwise) to the `MacroDonutChart` via a new
  `sectionOpacities: List<double>` prop. The chart
  applies the opacities via `AnimatedOpacity`.
- The card computes the override `Widget` for the
  ring: when `_focusedSectionIndex != null`, it is a
  `_MacroFocusContent` with the focused section's
  name, grams, and percent. Otherwise `null`
  (default calories).
- The card's `_EditTargetsIconButton` does not
  participate in the focus state (tapping the icon
  navigates as before).
- The card no longer wraps the chart in
  `AnimatedSize` (size no longer changes when macros
  are added/removed; the chart's overall size is now
  fixed). The `AnimatedSize` is removed.

##### 5. Pure-function test surface
File: `lib/features/nutrition/widgets/macro_donut_chart.dart`

- A pure top-level function
  `int? resolveSectionHit({
  required List<MacroSection> sections,
  required Offset localPosition,
  required Size chartSize,
  required double bandInnerRadius,
  required double bandOuterRadius,
  required int centerTapSentinel,
})` that resolves a tap to either a section
index, the `centerTapSentinel` (for taps inside the
ring's area), or `null` (for taps outside the chart).
Unit-testable without a widget tree.
- The function returns the `int` index of the matched
  section, the `centerTapSentinel` value, or `null`
  for outside the chart. The chart's gesture handler
  converts the sentinel to a deselect action.

##### 6. Tests
File: `test/nutrition_test.dart`

- New group `MacroDonutChart — tap-to-focus`:
  - `resolveSectionHit` unit tests: each of the four
    quadrants resolves to the correct section
    (using the four cardinal angles of a known
    fixture); the center resolves to the sentinel;
    outside the chart resolves to `null`.
  - Widget test: tapping a section marks it focused
    (verifiable via the per-section `Opacity` /
    `AnimatedOpacity` value, or by finding the
    `MacroFocusContent` widget in the tree).
  - Widget test: tapping the empty center deselects
    (no section is focused; the override is `null`).
  - Widget test: tapping the same focused section
    deselects.
  - Widget test: tapping a different section moves
    the focus (no fade to default state in between).
- New group `CalorieRing — centerOverride`:
  - When `centerOverride == null`, the default
    calories view is rendered.
  - When `centerOverride` is non-`null`, the
    override is rendered in the same Column
    position; the default calories text is not
    present.
- New group `CalorieRingCard — focus integration`:
  - Initial state: all sections + ring at full
    opacity, no override (default calories).
  - After tapping a section: the override is
    present in the ring's center; the ring's
    outer wrapper's opacity is 0.4.
  - After logging a new food while focused: the
    focus is preserved if the section still has
    non-zero grams; cleared if not.

##### 7. Doc hygiene
- `docs/widget_catalog.md` — update
  `MacroDonutChart`'s entry to describe the new
  tap-to-focus behavior, the removal of external
  labels, the new `onSectionFocusChange` and
  `sectionOpacities` props, the `centerTapSentinel`
  contract, and the new `size` / `strokeWidth`
  defaults.
- `docs/widget_catalog.md` — update `CalorieRing`'s
  entry to describe the new `centerOverride` prop
  and the `AnimatedSwitcher` cross-fade.
- `docs/design_system.md` — add a short note that
  the macro donut's external labels were removed
  in Iteration 2 (so the existing palette table is
  no longer visible at-a-glance; the palette is
  still used for the donut sections).
- `docs/state_management.md` — N/A (no state
  changes).
- `docs/data_models.md` — N/A.
- `docs/db_integration.md` — N/A.
- `docs/navigation_and_screens.md` — N/A.

### Progress

#### Phase 0 — Plan — Complete ✓
- [x] Read existing chart and `CalorieRing` widget code.
- [x] Read `CalorieRingCard` composition code.
- [x] Scenario Q&A: default state, tap-off, fade amount.

#### Phase 1 — Data layer (DBA)
- [ ] N/A — no model, repository, or schema changes
      in this iteration. The data layer is unchanged.
      Skipped per the spec.

#### Phase 2 — Logic & UI (Developer)
- [ ] Write red tests: hit-test resolution per
      section, focus + override behavior, focus
      survives log, focus clears on delete.
- [ ] Implement:
  - Resize donut, remove external labels.
  - Add `resolveSectionHit` pure function.
  - Convert `MacroDonutChart` to stateful with
    focus state.
  - Add `centerOverride` to `CalorieRing`.
  - Wire focus state in `CalorieRingCard`.
  - Add `_MacroFocusContent` widget.
- [ ] All tests green; no regressions.
- [ ] Doc hygiene: update `widget_catalog.md` and
      `design_system.md`.

#### Phase 3 — Code review — Complete ✓
- [x] Layer scoping: widgets, features. Data layer untouched.
- [x] Acceptance criteria verified: thicker band
      (`strokeWidth` 14 → 36, ~2.5× the ring's 14); external
      labels removed; new `onSectionFocusChange` + section
      opacities + hit-test pure function; per-section opacity
      (1.0 focused / 0.4 unfocused); center swaps to
      `MacroFocusContent`; default state has no focus.
- [x] Scenario register cross-checked: S-008..S-014 each have
      at least one test in `test/nutrition_test.dart`; the
      `resolveSectionHit` unit tests cover the hit-test surface
      directly; the `CalorieRingCard` integration tests cover
      the focus lifecycle (default → focus → deselect-on-same,
      deselect-on-center).
- [x] Doc hygiene verified: `widget_catalog.md` updated for
      `MacroDonutChart` (new props, new behavior, no more
      external labels), `MacroFocusContent` (new entry),
      `CalorieRing` (new `centerOverride` prop), `CalorieRingCard`
      (new tap-to-focus behavior); `design_system.md` notes the
      Iteration 2 label removal and that the palette slots
      continue to drive the band arc colors.
- [x] Global conventions verified:
      - **Theme tokens only**: PASS — no hardcoded colors in
        the chart, ring, or focus content.
      - **Timestamps are source data**: N/A.
      - **Units + canonical storage**: N/A.
      - **Reuse the canonical owner**: PASS — `CalorieRingCard`
        reads the four macro grams from `NutritionState`
        getters; the chart receives primitives only.
      - **Effort-kind drives analytics**: N/A.
      - **Instrument panel, not influencer**: PASS.
- [x] Architecture compliance: state derives only from
      `consumedToday`; no concrete repo import; no `dart:io`;
      no `Platform.is*`; button-shape rule N/A (no buttons
      added or changed).
- [x] Dead-code check: `_ExternalLabel` and the leader-line
      drawing inside the painter are removed. No unreferenced
      public symbols. The new `MacroFocusContent`,
      `resolveSectionHit`, and `resolveSectionHitCenterSentinel`
      are all consumed.
- [x] Test coverage: 55 nutrition tests (+8 new chart widget
      + centerOverride, replacing 5 label-based ones);
      `resolveSectionHit` group has 4 unit tests; 4 new
      `CalorieRingCard` integration tests for focus + deselect.
      1362/1362 project-wide pass.
- [x] Environment safety: no `dart:io`, no `Platform.is*`, no
      `sqlite` imports in any changed file.

#### Findings (non-blocking)
- `lib/features/nutrition/widgets/macro_donut_chart.dart` —
  the `MacroDonutChart` State also keeps its own
  `_focusedSectionIndex` for the local `Semantics` label.
  The card is the source of truth for visible focus via
  `sectionOpacities` + `onSectionFocusChange`. The two
  storages are not auto-synchronized: the chart's internal
  focus only updates on direct taps on the chart itself;
  if a parent re-renders the chart with new `sectionOpacities`
  but doesn't go through the tap path, the chart's
  `Semantics` label still shows "no focus". This is
  acceptable for the current single-card use case but
  should be considered if the chart is ever embedded in
  a context where focus changes come from elsewhere
  (e.g. a keyboard shortcut or a parent-managed state).
  (WARNING)
- `lib/features/nutrition/widgets/calorie_ring_card.dart` —
  the `Stack(alignment: center, [AnimatedOpacity(CalorieRing),
  MacroDonutChart])` order means the chart is on top of the
  ring. The chart's `GestureDetector` (with
  `HitTestBehavior.opaque`) intercepts all taps in the 240×240
  area, so the calorie ring is never the tap target. This is
  the intended interaction (the donut is the focusable
  surface) but is a subtle behavior — a future reader of the
  code might expect the ring to be tappable too. (WARNING)
- `lib/features/nutrition/widgets/calorie_ring_card.dart` —
  the `_unfocusedOpacity` constant (0.4) is a magic number
  chosen per the Q&A. Consider hoisting to a `static const`
  on `OmniTheme` (e.g. `OmniTheme.macroFocusFadeOpacity`) so
  themes can override it. (SUGGESTION)

#### Verdict
**✅ APPROVED** — all acceptance criteria met, all scenarios
covered, all docs updated, all tests green, no critical or
blocking issues. The findings above are non-blocking polish
opportunities.

---

## Iteration 3 — Hit-test painter-angle offset bug

> Folded from the human-checkpoint feedback after Iteration 2:
> tapping a section in the donut focuses the wrong section
> (e.g. tapping the visually-obvious Fat section focuses
> Protein, and a part of the visible Protein section focuses
> Net Carbs). The bug is a systematic index shift in the
> hit-test's angle conversion — every tap is off by one
> section in the fixed visual order.

### Root cause

`Canvas.drawArc` measures angles from the **+X axis** (3
o'clock), exactly the same convention as `atan2(dy, dx)`. A
section whose `startAngleRadians == -π/2` is drawn from 12
o'clock (top) and sweeps clockwise. The matching
`atan2(dy, dx)` for a tap at the top of the chart is also
`-π/2` (no offset needed).

Iteration 2's `resolveSectionHit` added an extra `+π/2` to the
`atan2` result under the (incorrect) assumption that the
painter's "12 o'clock" angle was `0` and atan2's "0 angle" was
the same as "3 o'clock". The result is that every tap was
shifted by a quarter-turn in the **hit-test's** coordinate
space, which made the hit-test resolve to a section whose
**range in the atan2 space** contains the tap, even though
that section is **not** the one drawn at that screen position.

The unit test for `resolveSectionHit` did not catch this bug
because the test's **point calculation** used the same wrong
formula (`dx = midR * sin(painterAngle)`, `dy = -midR *
cos(painterAngle)`) — so the test was internally consistent
with the bug. The test passed, but it tested the wrong
invariant.

### Fix

`resolveSectionHit` uses the raw `atan2(dy, dx)` angle
directly (no `+π/2` offset). The section's `startAngleRadians`
in `computeMacroSections` is already in the same convention
(the painter convention, which equals the atan2 convention),
so the comparison `[start, start+sweep]` works without
normalization for the typical case where `start >= 0`. The
wrap-around branch (when `start + sweep > 2π`) is kept for
the case where a single section spans most of the circle
(e.g. when only one macro is non-zero).

The unit test's point calculation is also updated to use the
correct conversion (`dx = midR * cos(painterAngle)`, `dy =
midR * sin(painterAngle)`) so the test now tests the real
invariant.

### Acceptance criteria

- [ ] A tap at the **top** of the chart (12 o'clock) on a
      chart with 4 equal-weight sections resolves to
      **section 0** (Net Carbs, in the fixed visual order).
- [ ] A tap at **3 o'clock** resolves to **section 1**
      (Fiber).
- [ ] A tap at **6 o'clock** resolves to **section 2**
      (Fat).
- [ ] A tap at **9 o'clock** resolves to **section 3**
      (Protein).
- [ ] The existing widget tests still pass (the chart still
      focuses the tapped section; the semantic label updates
      accordingly).
- [ ] The unit test for `resolveSectionHit` is updated to
      use the correct angle → point conversion and asserts
      the **real** geometric invariant (no internal
      consistency with a buggy implementation).
- [ ] `flutter analyze` clean.
- [ ] `flutter test` — all 1362 tests still pass.

### Scenarios

#### S-015: Tap on the top of the chart focuses section 0
- Trigger: User taps at the top of the macro donut (12
  o'clock).
- Precondition: At least 4 equal-weight non-zero macros so
  each section is a quarter of the circle.
- Flow:
  1. The tap is at `localPosition = (size/2, size/2 - midR)`
     in the chart's local coordinates.
  2. `atan2(-midR, 0) = -π/2` (no offset).
  3. Section 0's range is `[-π/2, 0]`. The tap matches.
  4. The chart focuses section 0 (Net Carbs in the fixed
     visual order).
- Expected outcome: The chart focuses the section drawn at
  12 o'clock, which is the **first** section in the
  painter's clockwise-from-top order — Net Carbs.

#### S-016: Tap on each of the four cardinal angles focuses the
  matching section
- Trigger: User taps at 12, 3, 6, 9 o'clock on a chart with
  4 equal-weight macros.
- Precondition: Same as S-015.
- Flow: Four taps, one at each cardinal angle. Each tap
  resolves to the section whose range contains the
  atan2(dy, dx) angle, and that section is the one drawn at
  that screen position.
- Expected outcome: 12 → section 0, 3 → section 1, 6 →
  section 2, 9 → section 3 (i.e. Net Carbs, Fiber, Fat,
  Protein, in the fixed visual order).
- Edge case of: S-015

### Iteration 3 — DB / Backend / Frontend Changes

#### DB Changes
None.

#### Backend Changes
None.

#### Frontend Changes

##### 1. Fix the painter-angle offset in `resolveSectionHit`
File: `lib/features/nutrition/widgets/macro_donut_chart.dart`

- Remove the `+ π/2` offset in the atan2 → painter angle
  conversion. The painter convention used by `drawArc` is
  identical to the math convention used by `atan2` (both
  measure CCW from the +X axis), so no offset is needed.
- The wrap-around branch (for sections that span the 0/2π
  boundary) is kept; the per-section `start` normalization
  is kept (in case a future iteration places a section's
  start in the negative range, e.g. via a different
  `cursor` initial value).
- Update the doc comment on `resolveSectionHit` to state
  explicitly that the angle is the raw atan2 value (no
  offset) and that the section's `startAngleRadians` is in
  the same convention.
- Update the doc comment on `MacroSection` to clarify that
  `startAngleRadians` is the atan2 / `drawArc` convention
  (not a "12 o'clock = 0" convention).

##### 2. Update the unit test's point calculation
File: `test/nutrition_test.dart`

- The `resolves each of the four cardinal angles to its
  section` test's point calculation used
  `dx = midR * sin(painterAngle)` and
  `dy = -midR * cos(painterAngle)`. That formula is
  internally consistent with the buggy `+ π/2` offset in
  the resolver, so the test was wrong-but-passing. Update
  to use the correct atan2 convention:
  `dx = midR * cos(painterAngle)` and
  `dy = midR * sin(painterAngle)`. With the fix in place,
  each section's mid-point (computed via the correct
  formula) resolves to that section's index.
- Add a dedicated `resolves a tap at 12 o'clock to section 0`
  test that exercises the exact bug — a tap dead-center at
  the top of the chart. This is the test that would have
  caught the bug originally. (The cardinal-angles test is
  general; the 12-o'clock test is the one a future reader
  will look at when re-verifying the hit-test.)

##### 3. Doc hygiene
- `docs/widget_catalog.md` — the `MacroDonutChart` entry
  already documents the hit-test in terms of the section
  ranges. Add a short note clarifying that the section's
  `startAngleRadians` is the atan2 / `drawArc` convention
  (no "12 o'clock = 0" offset), so a tap at 12 o'clock on
  the chart resolves to the section whose start is `-π/2`
  — the first section in the fixed visual order (Net
  Carbs).

### Progress

#### Phase 0 — Plan — Complete ✓
- [x] Reproduced the bug: tap on visually-obvious Fat
      section focuses Protein; tap on visually-obvious
      Protein section focuses Net Carbs.
- [x] Identified the root cause: the hit-test's
      `+ π/2` painter-angle offset is wrong; the
      painter convention equals the atan2 convention.
- [x] Scenario register: S-015 and S-016 added.

#### Phase 1 — Data layer (DBA) — N/A
- No data layer change in this iteration. Skipped.

#### Phase 2 — Logic & UI (Developer)
- [ ] Write a new test that exercises the exact bug
      (`resolves a tap at 12 o'clock to section 0`) — the
      test must fail with the current (buggy) code.
- [ ] Fix `resolveSectionHit` to use the raw atan2 angle
      (no `+ π/2` offset).
- [ ] Update the cardinal-angles unit test's point
      calculation to use the correct atan2 → (dx, dy)
      formula.
- [ ] Update the doc comments on `resolveSectionHit` and
      `MacroSection` to reflect the corrected convention.
- [ ] Update `docs/widget_catalog.md` with the short
      note on the atan2 / drawArc convention.
- [ ] `flutter analyze` clean.
- [ ] `flutter test` — all 1362 tests still pass.

#### Phase 3 — Code review — Complete ✓
- [x] Bug fix verified: S-015 and S-016 both pass. The
      new 12-o'clock test (`resolves a tap at 12 o'clock to
      section 0 (Net Carbs)`) failed before the fix with
      `Expected: <0>, Actual: <1>` — exactly the user's
      reported behavior. After the fix it passes.
- [x] The cardinal-angles unit test now exercises the
      real geometric invariant (the test would have
      caught the original bug if written against the
      fixed code).
- [x] The new 12-o'clock test is the targeted regression
      test — it would have caught the bug originally and
      will catch any future regression in the same spot.
- [x] Doc hygiene verified: `widget_catalog.md` updated
      with the angle-convention note (atan2 / drawArc,
      no offset, half-open interval per section).
      `MacroSection` and `resolveSectionHit` doc comments
      updated to match.
- [x] Three chart widget tests in the
      `CalorieRingCard — macro donut composition` group
      that were tapping exactly at 12 o'clock were updated
      to tap slightly off the top (30 px right, 110 px
      up from the chart center) so the tap lands inside
      the (only) Protein section's range — the single
      section is missing a half-gap on its leading edge
      exactly at 12 o'clock, so an exact-12-o'clock tap
      is correctly rejected as outside the band by the
      fixed resolver. The fix exposed a latent test bug
      (the tests were tapping in the gap, but the old
      buggy resolver's `+π/2` offset made the inner
      radius check the wrong distance, so the tap was
      being incorrectly accepted as a section hit).
- [x] No new architecture, button, or environment risks.
      The change is contained to `resolveSectionHit` and
      the unit test's point calculation.

#### Findings (non-blocking)
- `lib/features/nutrition/widgets/macro_donut_chart.dart` —
  the `resolveSectionHit` resolver has three branches
  (no-wrap, wrap-past-π, wrap-past-(-π)) and is harder to
  read than the original. The half-open interval +
  atan2-direct conversion is correct but the boundary
  cases add complexity. A future refactor could express
  the section ranges as a single normalized list and
  binary-search the painter angle against it. (SUGGESTION)
- `test/nutrition_test.dart` — the new S-015 test
  (`resolves a tap at 12 o'clock to section 0`) is the
  single targeted regression test for this bug. A
  future iteration that touches the hit-test should run
  this test first as a sanity check. (SUGGESTION)

#### Verdict
**✅ APPROVED** — the bug is fixed, the regression test
is in place, all docs are updated, all 1363 tests pass
project-wide. No critical or blocking issues. The
findings above are non-blocking polish suggestions.

## Feedback

(no feedback yet)
