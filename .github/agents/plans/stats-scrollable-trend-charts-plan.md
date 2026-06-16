# Feature: Stats Screen — Scrollable Trend Charts

## Overview

The existing on-card charts on `StatsScreen` become horizontally
**scrollable in place**: full history at a fixed per-point width, with a
**pinned y-axis**, opening scrolled to the newest point. No tap-to-expand,
no modal. On-card point tooltips are kept.

The nutrition card's 10-day cap is removed in favour of the same full-history
treatment; skip-empty / round-once / ascending sort are preserved.

## Requirements

- Each stats chart renders full history at a fixed per-point width inside a
  horizontal scroll view; opens scrolled to the newest point.
- Y-axis labels stay pinned and align to the plot's min/max while the plot
  scrolls.
- Charts whose points fit the card width do not scroll (plot clamps to
  viewport).
- Multi-line charts (cardio pace+distance, nutrition macros) scroll together
  on a shared x-domain.
- On-card `lineTouchData` tooltips preserved (tap a point → value).
  No GestureDetector / modal.
- Nutrition aggregation stays in `StatsProgressService` (repository-only);
  identical on Hive (web) and future Sqlite; no platform code in shared
  files.

## Acceptance Criteria

- [ ] All five stats charts render inside a horizontal scroll view at fixed
      per-point width.
- [ ] Pinned y-axis labels align with the scrolling plot's min/max.
- [ ] Charts open scrolled to the newest point.
- [ ] Sparse charts (points fit viewport) fill the width and do not scroll.
- [ ] Multi-line charts scroll as one on a shared x-domain.
- [ ] Tapping a point still shows its tooltip; single-point → single-point
      fallback; no-data → not rendered.
- [ ] Nutrition chart shows full history (no 10-day cap), skip-empty,
      round-once, ascending.
- [ ] No modal, no tap-to-expand, no new sheet widget.
- [ ] Repository interface unchanged; no platform-specific code in shared
      files.

## Scenarios

### S-001: Many points → scroll
- Trigger: User views a chart with more points than fit the card width.
- Precondition: e.g., a top lift with many training days.
- Flow: Chart renders at `points × perPointWidth`; opens scrolled to the
  right (newest); user drags left for older.
- Expected outcome: Smooth horizontal scroll; pinned y-axis stays put;
  vertical page scroll unaffected.
- Edge case of: none

### S-002: Few points → fill width
- Trigger: Chart with few points.
- Precondition: `points × perPointWidth ≤ viewport`.
- Flow: Plot clamps to viewport width; no scroll.
- Expected outcome: Chart fills the card cleanly; pinned axis still
  rendered.
- Edge case of: S-001

### S-003: Nutrition full history
- Trigger: User views the nutrition card (calories or macros).
- Precondition: Logged days beyond the most recent window exist.
- Flow: `computeNutritionTrend(days: null)` aggregates all logged days;
  chart scrolls through full history, opening at newest.
- Expected outcome: More than ~10 days available; horizontal scroll
  engaged.
- Edge case of: S-001

### S-004: Multi-line scroll
- Trigger: User views cardio pace+distance or nutrition macros.
- Precondition: Series share a date domain.
- Flow: All series scroll together; pinned y-axis; legend unchanged.
- Expected outcome: Lines stay aligned across the shared x-domain while
  scrolling.
- Edge case of: S-001

### S-005: Single point
- Trigger: Metric has exactly 1 point.
- Flow: Single-point fallback (unchanged); no scroll view.
- Expected outcome: Same inline single-point card as today.
- Edge case of: S-001

### S-006: Point tooltip
- Trigger: User taps a plotted point.
- Flow: `lineTouchData` tooltip shows the value (preserved behavior).
- Expected outcome: Tooltip appears; no modal.
- Edge case of: none

## Iteration 1

### DB Changes (@dba — optional, small)
- `lib/mock/seed_data.dart`: extend the nutrition consumed-food seed (from
  `stats-nutrition-trend-card-plan.md`) to ~30–45 now-relative days (with
  gaps) so the nutrition chart actually scrolls on web/QA. Seeded workout
  history already spans enough training days for strength/cardio. No
  schema/model/repo changes.

### Backend Changes (@developer)
- `lib/core/services/stats_progress_service.dart`:
  - `computeNutritionTrend({int? days})` — `null` = full history
    (`getConsumedFoodsInRange(0, now)`); the nutrition card calls it with
    `null`. Same per-day aggregation (skip-empty, round-once, ascending).
  - `kNutritionTrendDays` is no longer the data-window cap; it becomes a
    soft "default visible window" hint and is not enforced in the service.

### Frontend Changes (@developer)
- NEW `lib/features/stats/widgets/scrollable_trend_chart.dart`: a wrapper
  that renders [pinned y-axis label column] + [`SingleChildScrollView(horizontal)`
  → `SizedBox(width: plotWidth)` → `LineChart` with `leftTitles` hidden].
  Uses a `ScrollController` to jump to `maxScrollExtent` post-layout
  (newest-first view). `plotWidth = max(viewportWidth, points × perPointWidth)`.
- `lib/features/stats/stats_screen.dart`:
  - Replace `_buildInsetChart`'s fixed-width rendering with the
    scrollable wrapper across all chart builders (`_buildTrendChart`,
    cardio pace, cardio duration, nutrition calories, nutrition macros).
  - Compute y bounds/interval once via `ChartAxisHelper`; feed the same
    min/max to both the pinned label column and the plot.
  - Keep `lineTouchData` tooltips. Nutrition card loads full-history trend
    (`days: null`).

- `.github/agents/docs/stats_screen.md`: document scrollable charts, pinned
  axis, newest-first initial scroll, and nutrition full-history.

### Implementation Steps
1. (@developer) Add `computeNutritionTrend({int? days})` to
   `StatsProgressService`; expose it as a top-level method (and keep
   populating `StatsProgressData.nutritionTrend` so the screen does not
   have to make a second call).
2. (@developer) Build `ScrollableTrendChart` wrapper (pinned axis +
   horizontal scroll + newest-first jump + width clamp).
3. (@developer) Route all stats chart builders through the wrapper; share
   min/max with the pinned column; keep tooltips.
4. (@dba, optional) Extend nutrition seed to ~30–45 days so the chart
   scrolls on web/QA.
5. (@developer) Tests: `computeNutritionTrend(days: null)` (no cap,
   grouped/sorted/skip-empty); widget smoke (chart wrapped in horizontal
   scrollable; pinned labels render; sparse data fills width, no scroll).
6. (@developer) Update `stats_screen.md`. Run on web; verify scroll,
   pinned axis, newest-first, multi-line, sparse, single-point, tooltip.

### Files Affected
- `lib/core/services/stats_progress_service.dart` (@developer)
- `lib/features/stats/widgets/scrollable_trend_chart.dart` (@developer, NEW)
- `lib/features/stats/stats_screen.dart` (@developer)
- `lib/mock/seed_data.dart` (@dba, optional seed-span extension)
- `test/stats_progress_test.dart` (@developer)
- `.github/agents/docs/stats_screen.md` (@developer)

### Notes
- Supersedes the modal plan; revises the nutrition card's 10-day window
  to full-history scrollable (keep skip-empty, round-once, ascending; the
  visible-by-default window is whatever fits the card).
- fl_chart has no native pinned axis — static label column + scrollable
  plot sharing min/max is the supported pattern.
- Newest-first: prefer a `ScrollController` jump to `maxScrollExtent`
  after layout over `reverse: true` (which also flips content direction).
- Nested scrolling: a horizontal `SingleChildScrollView` inside the
  vertical `ListView` is fine; opposite axes don't conflict.
- `global_conventions.md` applies (ms timestamps, canonical storage,
  local-midnight `dateMs`).

---

## Progress

### Phase 0
- [x] Plan file created at `.github/agents/plans/stats-scrollable-trend-charts-plan.md`
- [x] Read `docs/global_conventions.md`, `docs/stats_screen.md`, `docs/navigation_and_screens.md`

### Phase 1
- [x] Extended `lib/mock/seed_data.dart` with older nutrition rows spanning the last 45 days (15 new meal entries across 15 logged days with 2 intentional gaps)
- [x] Updated `MockWorkoutRepository.initialize()` already wires the seeds (no change needed)

### Phase 2
- [x] Red tests written against S-003 (`days: null returns all logged days`), window-bound (`days: N still applies the cap`), full-history skip-empty/round-once, and empty-repo paths
- [x] `StatsProgressService.computeNutritionTrend({int? days})` — `null` = full history (`getConsumedFoodsInRange(0, now)`); `days: kNutritionTrendDays` for the screen's existing default
- [x] `ScrollableTrendChart` widget at `lib/features/stats/widgets/scrollable_trend_chart.dart` (pinned y-axis + horizontal scroll + newest-first jump + width clamp)
- [x] All 5 chart builders route through the wrapper: `_buildTrendChart`, `_buildCardioPaceChart`, `_buildCardioDurationChart`, `_buildCaloriesChart`, `_buildMacrosChart`
- [x] `flutter test test/stats_progress_test.dart` — 35/35 pass
- [x] `flutter test test/stats_progress_test.dart test/db_seed_test.dart test/food_library_edit_test.dart` — 47/47 pass
- [x] `flutter analyze` clean
- [x] `flutter build web` clean
- [x] `stats_screen.md` updated (Scrollable Charts section, NUTRITION reframed as full-history, version 2.2)
- [x] `navigation_and_screens.md` updated (StatsScreen description)

### Phase 3
- [x] Acceptance criteria verified (9/9)
- [x] Global conventions verified (PASS on all 6)
- [x] Architecture compliance verified
- [x] Environment safety verified
- [x] Doc hygiene verified

### Phase 0 Complete ✓
### Phase 1 Complete ✓
### Phase 2 Complete ✓
### Phase 3 Complete ✓
