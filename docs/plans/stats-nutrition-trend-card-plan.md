# Feature: Stats Screen — Nutrition Trend Card

## Overview

Add a new card at the very bottom of `StatsScreen` (under the Cardio section) that
visualises the user's last 10 days of nutrition logging. The card carries a
segmented pill toggle (`Calories` | `Macros`) over a trend computed from
`ConsumedFood` rows: a single kcal/day line in the Calories view, and a
three-line (protein / carbs / fat) chart in the Macros view. Days with no
logged food are skipped, matching the existing strength/cardio trend
behavior. The trend computation lives in `StatsProgressService` and depends
only on the `WorkoutRepository` interface.

## Requirements

- Card sits at the very bottom of the has-sessions stats list (after Cardio).
- Segmented pill toggle: `Calories` | `Macros`. Default = Calories. Toggle
  state is local widget state (not persisted).
- Window = last 10 days: today + 9 prior, anchored at load time.
- Days with no logged food are skipped; only logged days are plotted, sorted
  ascending by date — matches existing strength/cardio/rest-time trend
  behavior.
- Calories line color = `themeColors.primary` (matches existing trend lines).
- Macros line colors come from `OmniTheme.colors.macroChart`:
  - protein → `macroChart.protein`
  - carbs → `macroChart.netCarbs` (this is the strip's carbs/blue slot)
  - fat → `macroChart.fat`
- Carbs line plots **total** carbs grams (not net carbs), matching the
  home strip's blue semantics. The token is named `netCarbs` because the
  donut uses that slot, but the line value here is total carbs.
- Per-day macro grams aggregate as
  `Σ (macro × amountConsumed / referenceAmount)`, accumulated as double
  and rounded once per day (mirrors the `NutritionState` rounding
  contract). Per-day calories = `Σ ConsumedFood.caloriesConsumed` (per-row,
  already rounded), matching the calorie ring.
- If 0 days in the window have logged food → card hidden entirely.
- If exactly 1 day has logged food → inline single-point fallback (no
  chart), mirroring the lift/cardio single-point pattern.
- Computation lives in `StatsProgressService` (pure-Dart, repository-only),
  so it is identical on Hive (web) and future Sqlite.
- Both views share the same plotted-day set (any logged food makes the day
  present for all series) — toggling never changes the x-domain.
- Window is anchored at load time (like the activity chart) so a midnight
  rebuild does not shift points.

## Acceptance Criteria

- [ ] Card renders at the bottom of the stats list when ≥1 day in the last
      10 has logged food.
- [ ] Card is hidden when 0 days in the window have logged food.
- [ ] Default view is Calories: one line in `themeColors.primary`.
- [ ] Macros view shows exactly three lines (protein/carbs/fat) in the
      `macroChart` palette colors, with a legend.
- [ ] Empty days are skipped (not zero-filled); only logged days plot,
      sorted ascending by date.
- [ ] ≥2 logged days → `LineChart`; exactly 1 logged day → inline
      single-point card.
- [ ] Toggle is a segmented pill control; switching views does not
      re-query the repository (both series computed once on load).
- [ ] Trend computation is in `StatsProgressService` and depends only on
      the `WorkoutRepository` interface (no concrete impl, no platform
      code).
- [ ] `seed_data.dart` includes consumed-food logs spanning the last 10
      days so the card renders on the web/QA build.
- [ ] Repository interface unchanged; no platform-specific code in
      shared files.
- [ ] `test/stats_progress_test.dart` covers nutrition aggregation: per-day
      grouping, skip-empty, window bounds, ascending sort, round-once.

## Scenarios

### S-001: Calories view (default)
- Trigger: User opens Stats; ≥2 days in the last 10 have logged food.
- Precondition: Completed sessions exist (screen is in has-sessions
  branch); consumed-food rows exist within the window.
- Flow: Screen loads → service computes the trend → card renders with
  the Calories pill selected → single line plots kcal/day across logged
  days, ascending.
- Expected outcome: One primary-colored line; y-axis kcal via
  `ChartAxisHelper`; date labels at sampled indices; tooltip shows
  `"<n> kcal"`.
- Edge case of: none

### S-002: Macros view
- Trigger: User taps the `Macros` pill.
- Precondition: Same data as S-001.
- Flow: View switches to the three-line chart over the same logged days.
- Expected outcome: Three lines — protein (`macroChart.protein`), carbs
  (`macroChart.netCarbs`, total carbs grams), fat (`macroChart.fat`) —
  plus a legend; tooltip shows grams per series.
- Edge case of: none

### S-003: Toggle between views
- Trigger: User taps a pill.
- Precondition: Card visible.
- Flow: Selected pill state flips (local widget state); the chart area
  swaps; no repository call.
- Expected outcome: Instant view swap; both series already in memory;
  default on entry is Calories.
- Edge case of: none

### S-004: Single logged day in window
- Trigger: Exactly 1 day in the last 10 has logged food.
- Precondition: Has-sessions branch.
- Flow: Service returns a one-point trend → card shows inline
  single-point card(s) instead of a chart, in whichever view is
  selected.
- Expected outcome: Calories view →
  `"<n> kcal — 1 day, log more to see a trend"`; Macros view → per-macro
  single-point summary. No line chart.
- Edge case of: S-001 / S-002

### S-005: No food logged in window
- Trigger: 0 days in the last 10 have logged food.
- Precondition: Has-sessions branch.
- Flow: Service returns an empty trend → card omitted from the list.
- Expected outcome: No nutrition card rendered; rest of the stats screen
  unchanged.
- Edge case of: S-001

### S-006: No sessions at all
- Trigger: `_totalSessions == 0`.
- Precondition: none.
- Flow: Screen shows only the existing global empty-state card.
- Expected outcome: Nutrition card not shown (current screen behavior
  preserved); nutrition trend is not loaded.
- Edge case of: S-005

## Iteration 1

### DB Changes (@dba)
- `lib/mock/seed_data.dart`: add a `static final List<ConsumedFood>
  sampleConsumedFoods` collection of 8–10 `ConsumedFood` seed rows that
  span the last 10 days using `DateTime.now()`-relative `dateMs`
  (local midnight per day), matching the existing now-relative seeding
  convention. Skip 1–2 days intentionally so QA can verify the
  "skip empty days" behavior (S-001).
- Vary macros across days so all three macro lines and the calorie line
  show visible movement. Reuse bundled-catalog macro values
  (`FoodCatalogSeed`) where possible to keep the seed self-consistent.
- Follow `docs/global_conventions.md`: ms timestamps, `dateMs` = local
  midnight, frozen-snapshot fields populated (name, unitType,
  referenceAmount/Label, protein/carbs/fat, amountConsumed, target*
  fields, created/updated ms). Pass entries to
  `MockWorkoutRepository.createConsumedFood` in `initialize()` so both
  Hive and Mock surfaces see the rows.

### Backend Changes (@developer)
- `lib/core/models/stats_progress.dart`: add
  `NutritionTrendPoint { DateTime date; int calories; int protein; int
  carbs; int fat; }`.
- `lib/core/services/stats_progress_service.dart`:
  - Add `static const int kNutritionTrendDays = 10;`.
  - Add a `nutritionTrend` field on `StatsProgressData` (default empty
    list) so the same service call that powers the existing screen also
    returns the nutrition trend (no double-walk of the repo).
  - Add `Future<List<NutritionTrendPoint>> _computeNutritionTrend()`:
    anchor `today` + `nineDaysAgo`; call
    `getConsumedFoodsInRange(fromMs, toMs)`; group rows by `dateMs`; per
    day sum calories (`Σ ConsumedFood.caloriesConsumed`) and macro grams
    (`Σ (macro × amountConsumed / referenceAmount)`, round once);
    drop days with no rows; sort ascending by date.

### Frontend Changes (@developer)
- `lib/features/stats/stats_screen.dart`:
  - Load the trend in `_loadData()` (parallel with existing calls); store
    on state as `List<NutritionTrendPoint>`.
  - Add a `_NutritionView { calories, macros }` local enum + `setState`
    toggle; default `calories`.
  - Build the card inline (matching the existing lift/cardio
    `_build*` private-method pattern): `OmniSurface` with a `NUTRITION`
    section label, segmented pill toggle, and the chart area.
  - Calories chart: single `LineChartBarData` in `themeColors.primary`;
    reuse `_buildInsetChart`, `ChartAxisHelper` bounds/interval/labels,
    tooltip, dot, grid.
  - Macros chart: three `LineChartBarData` (protein/carbs/fat) in the
    `macroChart` colors; add a legend via `_buildLegendItem`.
  - Single-point fallback (S-004) reusing the existing single-point card
    style; hide the whole card when the trend is empty (S-005).
  - Insert after the Cardio section in the has-sessions branch only
    (S-006 keeps current empty-state behavior).
- `docs/stats_screen.md`: document the new NUTRITION
  section, the 10-day window, skip-empty behavior, color tokens, and
  visibility rules.

### Implementation Steps
1. (@dba) Add 8–10 days of `ConsumedFood` seed logs (now-relative, 1–2
   gaps, varied macros) to `seed_data.dart`. Wire into
   `MockWorkoutRepository.initialize()`.
2. (@developer) Add `NutritionTrendPoint` to `stats_progress.dart` and
   a `nutritionTrend` field to `StatsProgressData`.
3. (@developer) Add `kNutritionTrendDays` +
   `_computeNutritionTrend` to `StatsProgressService`; fold into
   `StatsProgressData`.
4. (@developer) Read `nutritionTrend` in `StatsScreen._loadData()` and
   hold it in state.
5. (@developer) Add the segmented pill toggle + `_NutritionView` state
   (default Calories).
6. (@developer) Build the Calories line chart (primary color).
7. (@developer) Build the Macros 3-line chart + legend (macroChart
   colors; carbs = total carbs).
8. (@developer) Single-point fallback + hide-when-empty; place card at
   the bottom of the has-sessions list.
9. (@developer) Extend `test/stats_progress_test.dart` with nutrition
   aggregation cases (grouping, skip-empty, window bound, ascending
   sort, round-once).
10. (@developer) Update `stats_screen.md`. Run on web and verify both
    views, toggle, single-point, and hidden states.

### Files Affected
- `lib/mock/seed_data.dart` (@dba)
- `lib/data/repositories/mock_workout_repository.dart` (@dba —
  wire seeds via `initialize()`)
- `lib/core/models/stats_progress.dart` (@developer)
- `lib/core/services/stats_progress_service.dart` (@developer)
- `lib/features/stats/stats_screen.dart` (@developer)
- `test/stats_progress_test.dart` (@developer)
- `docs/stats_screen.md` (@developer)

### Notes
- No DBA work beyond seed: the range query, the `ConsumedFood` model,
  and the repository interface already exist and are
  environment-agnostic.
- Keep the carbs **value** = total carbs even though the **color** token
  is named `netCarbs` (that slot is the strip's carbs/blue). Call this
  out in code comments to prevent a future "net carbs" regression.
- Both views share the same plotted-day set (any logged food makes the
  day present for all series), so toggling never changes the x-domain.
- Window is anchored at load (like the activity chart) so a
  midnight/theme rebuild does not shift points.
- Calorie line color is intentionally `themeColors.primary` (the user
  specified macro colors only); flag at review if a distinct calorie
  color is preferred.
- TDD is non-negotiable: tests against the **scenarios** go in first and
  must fail before the implementation goes in.

---

## Progress

### Phase 0
- [x] Read `docs/global_conventions.md`, `docs/stats_screen.md`,
      `docs/navigation_and_screens.md`
- [x] Plan file created with Overview, Requirements, Acceptance
      Criteria, Scenarios (S-001..S-006), Iteration 1

### Phase 1
- [x] 13 `ConsumedFood` seed rows spanning the last 10 days added to
      `lib/mock/seed_data.dart` (days 0, 1, 3, 4, 5, 7, 8 logged;
      days 2, 6, 9 intentionally empty to verify skip-empty)
- [x] `MockWorkoutRepository.initialize()` loads the seed rows
- [x] No schema / model / repository-interface changes

### Phase 2
- [x] Red tests written against the scenarios (`S-001`..`S-005`,
      window bound, skip-empty, round-once, total carbs)
- [x] `NutritionTrendPoint` value type + `nutritionTrend` field
      added to `StatsProgressData`
- [x] `kNutritionTrendDays` + `_computeNutritionTrend` added to
      `StatsProgressService` (pure-Dart, repository-only)
- [x] `StatsScreen` loads `nutritionTrend` in `_loadData` (parallel
      with existing calls — no extra round-trip)
- [x] `_NutritionView` enum + segmented pill toggle wired in
- [x] Calories chart (single line, `themeColors.primary`)
- [x] Macros chart (3 lines + legend, `macroChart` colors)
- [x] Single-point fallback for 1-day case (Calories & Macros)
- [x] Card hidden when trend is empty (S-005)
- [x] `flutter test test/stats_progress_test.dart` — 31/31 pass
- [x] `flutter test test/food_library_edit_test.dart
      test/food_library_persistence_test.dart` — 45/45 pass
- [x] `flutter analyze` — no new issues
- [x] `flutter build web` — builds clean
- [x] `stats_screen.md` updated (NUTRITION section, constants,
      core files, version 2.1)
- [x] `navigation_and_screens.md` updated (StatsScreen description)

### Phase 3
- [x] Acceptance criteria verified (11/11)
- [x] Global conventions verified (PASS on all 6)
- [x] Architecture compliance verified
- [x] Buttons checked (explicit `shape:`, `OmniTheme.buttonUtilityRadius`)
- [x] Environment safety verified
- [x] Doc hygiene verified

### Phase 0 Complete ✓
### Phase 1 Complete ✓
### Phase 2 Complete ✓
### Phase 3 Complete ✓

