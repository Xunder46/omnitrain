# Feature: Unify Chart Scrolling + Drop On-Tap Popup

## Overview

The stats-screen charts and the profile measurement-history chart adopt the
same scrolling / newest-first / eight-points-visible behavior as the nutrition
charts already do, and they drop the on-tap value popup along with the
top-headroom the popup needed. Trend shape is what matters on these cards;
exact figures remain available via the axis labels and (on the measurement
sheet) the below-chart value strip.

This feature **completes** the scope originally promised in
`.github/agents/plans/stats-scrollable-trend-charts-plan.md`: only the three
nutrition charts were actually converted in that iteration — strength e1RM /
volume, cardio pace+distance, and cardio duration still use the old
`_buildInsetChart` wrapper with `LineTouchTooltipData`, `_kTopAxisHeadroom = 12`,
and double padding. It also extends the same pattern to the profile
measurement-history sheet.

`MeasurementSparkline` is intentionally **out of scope** — it is a 60 dp
inline at-a-glance view, not a detail view; it already has no popup and no
top headroom; making it scroll would defeat its purpose.

---

## Resolved Decisions (Ledger)

| ID | Decision | Notes |
|----|----------|-------|
| **D-1** | `ScrollableTrendChart` accepts a new `maxVisiblePoints` parameter (default `8`). Internally the per-point slot width is `viewportWidth / maxVisiblePoints`, floored at `28 dp` minimum. Existing nutrition callers automatically get the new behavior. | Static per-point width (48 dp) gives only ~5–6 visible on typical cards; user spec says "8 in view". Dynamic avoids both under- and over-fitting. Floor at 28 dp keeps date labels legible on narrow phones. |
| **D-2** | The measurement sheet's below-chart value strip always shows the most recent entry (`_selectedIndex = length - 1` on load; never changes). Tap-to-select is removed. | Strip stays per user prompt ("leave it as-is"); removing tap-to-select means there is no longer a way to change `_selectedIndex`, so the default must be the most recent. |
| **D-3** | `MeasurementSparkline` is **not** touched in this iteration. | At-a-glance inline view, not a detail view; no popup, no top headroom. User confirmed. |
| **D-4** | `LineTouchData` is disabled (`enabled: false`) on every stats chart builder (`_buildTrendChart`, `_buildCardioPaceChart`, `_buildCardioDurationChart`, `_buildCaloriesChart`, `_buildMacrosChart`, `_buildEmptyNutritionChart`) and on the measurement sheet's `LineChart`. No fl_chart tooltip popup appears on tap. | User explicitly removed the on-tap value popup. |
| **D-5** | Stats charts drop the `_kTopAxisHeadroom = 12` reserved size on `topTitles` everywhere. Measurement sheet drops its 8 dp top padding. | Headroom existed only to give the popup room above the highest point. With no popup, reclaiming this space makes the card visibly more compact. |
| **D-6** | Stats charts drop the `_buildInsetChart` wrapper entirely (`Transform.translate(-16, 0)` + `Padding(right: 8)`), along with `_kChartLeftShift` and `_kChartRightInset`. Charts sit inside `ScrollableTrendChart`'s pinned-axis + scrollable-plot layout, which provides its own left (pinned 64 dp column) and right (natural) bounds. No double padding remains. | User spec: "Remove the redundant padding inside the chart card". |
| **D-7** | The measurement sheet removes the `entries.take(10)` cap and renders the **full** history via `ScrollableTrendChart`. Users reach older entries by scrolling. | Matches the nutrition chart's full-history behavior; the prior `take(10)` cap was a pre-scroll leftover. |
| **D-8** | The measurement sheet removes the per-point `GestureDetector` overlay (`_buildDotTapTargets` and the `chart_dot_$i` keys). **Long-press to delete is preserved** via a single chart-area `GestureDetector(onLongPress: ...)` (mechanic — implementation free). The dot hit-target keys are gone; existing tests that long-press `find.byKey(ValueKey('chart_dot_$i'))` are updated to long-press the chart-area key. | Per-point tap selected which entry the strip displayed — that affordance is gone with the popup (D-4). Delete is the only remaining touch affordance; long-press can be served by a chart-area detector. |
| **D-9** | Measurement sheet hint text changes from `'Tap a point to view \u00b7 Long-press to delete'` to `'Long-press to delete'`. | The "Tap a point to view" half described the removed affordance. |
| **D-10** | Y-axis bounds use `ChartAxisHelper.computeBounds`, which pads above the max by `paddingFraction × range + 1.0`. This guarantees the top point sits inside the plot area even after the headroom is removed. **No additional top-padding logic is added.** | Verified by reading `lib/core/utils/chart_axis_helper.dart`. The `+1.0` floor also handles flat/single-value series. |
| **D-11** | Mock seed stays as-is. Tests that need >8 entries use `repo.saveMeasurementEntry(...)` (or its nutrition counterpart) directly to build fixtures; the seed's natural count is only relevant for manual QA on web. | Seed touches are a separate concern; tests can build any fixture they need. |
| **D-12** | The wrapper's "scroll engaged" rule becomes: scroll when `pointCount > maxVisiblePoints`. Since `perPointWidth = viewport / maxVisiblePoints`, this is exactly equivalent to `points × perPointWidth > viewport`. The existing `kScrollableTrendMinPointsForScroll = 8` constant is removed (the threshold is now derived from `maxVisiblePoints`) or kept solely as a `// ignore` documentation reference — implementation free. | Removes a redundant constant whose value collided with the new "8 in view" semantics. |

> **Decisions to flag for veto before the first handoff that depends on them:**
> D-2 (strip default = most recent), D-7 (drop 10-entry cap), D-8 (long-press via chart-area detector rather than per-point), D-12 (delete the threshold constant). If any of these is wrong, the developer agent will surface it in `## Assumption Log` and the conductor will ratify or revert.

---

## Feature Invariants

(Full project-wide rules live in `docs/global_conventions.md` and are referenced, not copied.)

- **Repository-only data access** — every chart reads through `WorkoutRepository`. No direct Hive / SQLite access from `lib/features/stats/` or `lib/features/profile/widgets/measurement_history_chart_sheet.dart`. (Already true; verified by grep.)
- **Hive ↔ Mock parity on touched data** — `MockWorkoutRepository.getMeasurementHistory` mirrors `HiveWorkoutRepository.getMeasurementHistory` value-for-value (entries returned in the same order, same `recordedAtMs` semantics). Removing the `take(10)` cap must apply identically to both — no per-environment behavior drift.
- **`ScrollableTrendChart` contract** — pinned y-axis column on the left, scrollable plot on the right, both sharing the same `ChartAxisBounds`; newest-first via `ScrollController.jumpTo(maxScrollExtent)` after first layout; **no `reverse: true`** (the user explicitly warned this was tried before and flipped the plot). Phase agents MUST NOT introduce `reverse: true` even if it appears simpler.
- **Chart typography stays token-driven** — every label and line uses `themeColors.textMuted` / `themeColors.primary` / `themeColors.divider` / `OmniTheme.colors.*`. No hardcoded colors anywhere in the chart builders.
- **Card chrome stays `OmniSurface` + `OmniCardHeader`** — no raw `Card(...)` widgets. (Already true.)

---

## Requirements

1. Every on-card stats chart (strength e1RM, strength volume, cardio pace + distance, cardio duration, nutrition calories, nutrition macros) is wrapped in `ScrollableTrendChart` with the **same** semantics as today's nutrition charts, plus:
   - `maxVisiblePoints: 8` (the new default; explicitly passed for documentation)
   - `LineTouchData(enabled: false)` (no fl_chart tooltip popup)
   - No top-headroom reserved size on `topTitles`
   - No `_buildInsetChart` / `_kChartLeftShift` / `_kChartRightInset` doubling
2. `MeasurementHistoryChartSheet` renders its data inside `ScrollableTrendChart` with the same `maxVisiblePoints: 8`, no fl_chart tooltip, no top-headroom, no fixed 440 dp width. The full history is shown; older entries are reachable by scrolling.
3. The measurement sheet's below-chart value strip always shows the most recent entry. The `GestureDetector` tap overlay is removed. Long-press to delete still works.
4. The measurement sheet's hint text becomes `"Long-press to delete"`.
5. The `ScrollableTrendChart` wrapper exposes `maxVisiblePoints` (default 8) so future callers can opt into a different visible count without forking the widget.
6. The highest data point remains fully visible on every chart after the top headroom is removed (verified visually and by a structural-guard test that asserts the top point's y position is within the plot area for a dataset whose max equals `bounds.max - 1.0`).

## Out of Scope

- Changing chart types, colors, axis labels, or the data shown on any chart.
- Adding a replacement value readout anywhere on the cards.
- Changing the measurement sheet's below-chart value strip shape, position, or content (other than what falls out of D-2 — the strip keeps showing the most recent entry).
- Changing `MeasurementSparkline` (D-3).
- Touching unrelated parts of `stats_screen.dart` or `measurement_history_chart_sheet.dart` (PR card, segment list, log button, etc.).

## Acceptance Criteria

| # | Criterion | Scenario |
|---|-----------|----------|
| AC-1 | Stats-screen charts and the profile measurement-history chart scroll horizontally, matching the nutrition charts' behavior. | S-101, S-106 |
| AC-2 | Each chart shows at most 8 data points in view at once; older points are reachable by scrolling. | S-101, S-102, S-106 |
| AC-3 | On open, every chart is scrolled to its most recent value, with older values reachable by scrolling back. Data is not reversed or mirrored. | S-103, S-107 |
| AC-4 | Tapping a point on these charts does not surface a value popup. | S-104, S-108 |
| AC-5 | The chart no longer reserves blank space at the top for a popup; the card is visibly more compact than before. | S-105, S-109 |
| AC-6 | The highest data point remains fully visible and not clipped against the top edge after the headroom is removed. | S-105b, S-109b |
| AC-7 | The chart card no longer applies duplicate inner padding; spacing is consistent across all chart locations. | S-105c |

---

## Scenarios

Stable S-ids. References S-101+ — the earlier `stats-scrollable-trend-charts-plan.md` S-001..S-006 belong to that plan and remain valid for the parts they covered.

### S-101: Many stats points → scroll, newest first
- Fixture: a lift with 12 distinct training days of `set` efforts; a cardio activity with 12 timed efforts spanning >8 days.
- Trigger: Open Stats screen.
- Flow: `ScrollableTrendChart` wraps every chart. Scroll controller jumps to `maxScrollExtent` post-layout.
- Expected outcome: All 5 charts (strength e1RM, strength volume, cardio pace, cardio duration, nutrition calories) render ≥ 8 points visible with the most recent on the right; the 4 oldest points are reachable by horizontal drag.
- Edge case of: none.

### S-102: Few stats points → fill card, no scroll
- Fixture: a lift with 3 distinct training days; a cardio activity with 2 timed efforts.
- Flow: Chart renders inside `ScrollableTrendChart`.
- Expected outcome: No horizontal scroll engaged (`pointCount <= maxVisiblePoints`); plot fills the available card width.

### S-103: Newest-first open is not reversed data
- Fixture: 10 e1RM points dated Jan 1 .. Jan 10 (ascending).
- Flow: Open Stats screen; check `LineChart.data.minX` / `maxX` and the spot ordering.
- Expected outcome: `spots[0]` corresponds to Jan 1, `spots[9]` to Jan 10. The chart is scrolled so the visible window ends at `spots[9]`. The underlying data is **not** reversed; the scroll controller is what positions the view. **No `reverse: true` on the `SingleChildScrollView`.**
- Edge case of: S-101.

### S-104: No fl_chart tooltip popup on tap
- Fixture: 10 strength points.
- Flow: `tester.tap(find.byType(LineChart).first); tester.pumpAndSettle();` then `find.byType(Tooltip)` should match nothing (or assert the `LineTouchData.enabled == false` on the chart's data).
- Expected outcome: No tooltip rendered. Equivalent assertion on the measurement sheet.

### S-105: Stats chart no top-headroom, no double padding
- Fixture: standard card with 10 strength points.
- Flow: Read `LineChartData.titlesData.topTitles.sideTitles.reservedSize` and inspect the widget tree wrapping the chart for `Transform.translate` / extra `Padding`.
- Expected outcome:
  - `topTitles.sideTitles.reservedSize == 0` (no 12 dp headroom)
  - No `Transform.translate` widget appears as an ancestor of the `LineChart` inside `ScrollableTrendChart`
  - The chart sits inside `ScrollableTrendChart`'s `Expanded` flex + pinned-column layout

### S-105b: Stats chart top point not clipped after headroom removal
- Fixture: a dataset whose max value equals `ChartAxisHelper.computeBounds(values).max - 1.0` (i.e. one unit below the padded max).
- Flow: Render the chart at the standard card width; locate the rendered dot at `spots.last` (highest x, highest y in screen coords).
- Expected outcome: The dot's `dy` is strictly greater than the chart widget's top edge (no clipping). Verified by a structural-guard test that walks the `RenderObject` tree of the top dot's painter.

### S-105c: No duplicate inner padding
- Fixture: stats card.
- Flow: Walk the widget tree from the chart to the card root; collect all `Padding` and `EdgeInsets` values applied between `OmniSurface` and the `LineChart`.
- Expected outcome: Exactly one horizontal padding layer between `OmniSurface` and the chart (the pinned-axis column + the chart's natural right inset). No `Transform.translate` doubling.

### S-106: Measurement history sheet scrolls, 8 in view, newest first
- Fixture: 12 `BodyMeasurementEntry` rows for one measurement type, recorded at 1-day intervals.
- Trigger: Open the measurement history sheet (tap the row on Profile screen).
- Flow: Sheet renders the chart inside `ScrollableTrendChart`. Scroll controller jumps to `maxScrollExtent`.
- Expected outcome: 8 entries visible (oldest among the visible 4 days back from "today"), the 4 oldest are reachable by horizontal drag. The chart's x-domain covers indices 0..11 (oldest..newest); the visible window ends at index 11.

### S-107: Measurement sheet strip default = most recent
- Fixture: 5 entries; `_selectedIndex` is set on load.
- Flow: Open sheet. Do not interact.
- Expected outcome: Strip renders the date and value of the most recent entry (index 4). The `AnimatedSwitcher` keys off `_selectedIndex == 4`.

### S-108: Measurement sheet tap-to-select removed
- Fixture: 5 entries.
- Flow: `tester.tap(find.byType(LineChart).first); tester.pumpAndSettle();`
- Expected outcome: `_selectedIndex` is unchanged; strip still shows the most recent entry. No animation triggers. Equivalent: there is no `find.byKey(ValueKey('chart_dot_$i'))` in the tree at all.

### S-109: Measurement sheet no top headroom, hint text updated
- Fixture: 5 entries.
- Flow: Pump sheet; read `LineChartData.titlesData.topTitles.sideTitles.reservedSize`; find the hint text.
- Expected outcome:
  - `topTitles.sideTitles.reservedSize == 0`
  - Hint text equals `'Long-press to delete'`
  - Strip still shows most-recent entry

### S-109b: Measurement sheet top point not clipped after headroom removal
- Fixture: 12 entries with a clear max value (the dataset's peak).
- Flow: Render the sheet; locate the rendered dot at `spots.last`.
- Expected outcome: The dot is fully visible (its `dy` is strictly greater than the chart widget's top edge), even though the chart no longer reserves a top headroom. The chart's `clipData` may stay at `FlClipData.all()` for the measurement sheet (was set previously); the structural-guard test asserts the top dot is inside the clip rect by at least the dot's radius (3-6 dp).

### S-110: Long-press to delete still works
- Fixture: 3 entries.
- Flow: `tester.longPress(find.byKey(Key('measurement_chart_area'))); tester.pumpAndSettle();`
- Expected outcome: Delete confirmation dialog appears (same as today's behavior, but the long-press target is the whole chart area, not a per-point hit target).
- Edge case of: S-108 — this is the only remaining touch affordance.

### S-111: Empty measurement sheet renders empty state
- Fixture: 0 entries.
- Flow: Open sheet.
- Expected outcome: `'No entries yet'` text, no chart, no hint text (existing behavior preserved). No regression.

---

## Iteration 1

### Phase 1: Stats charts + wrapper API (@developer)
1. `lib/features/stats/widgets/scrollable_trend_chart.dart`
   - Add `final int maxVisiblePoints` (default `8`) to `ScrollableTrendChart`.
   - Internally derive `perPointWidth = max(28.0, viewportWidth / maxVisiblePoints)` inside the `LayoutBuilder`.
   - The "scroll engaged" condition becomes `pointCount > maxVisiblePoints`.
   - Remove the now-redundant `kScrollableTrendMinPointsForScroll` constant (D-12). If the constant is referenced elsewhere, replace those references with `maxVisiblePoints`.
   - Update the inline class doc to describe the new parameter and the dynamic-width rule.
2. `lib/features/stats/stats_screen.dart`
   - Remove the constants `_kTopAxisHeadroom`, `_kChartLeftShift`, `_kChartRightInset` and the `_buildInsetChart` helper (D-5, D-6).
   - Convert `_buildTrendChart`, `_buildCardioPaceChart`, `_buildCardioDurationChart` to use `ScrollableTrendChart`. Pass `maxVisiblePoints: 8` explicitly.
   - In every chart builder (`_buildTrendChart`, `_buildCardioPaceChart`, `_buildCardioDurationChart`, `_buildCaloriesChart`, `_buildMacrosChart`, `_buildEmptyNutritionChart`):
     - Replace `lineTouchData: LineTouchData(touchTooltipData: ...)` with `lineTouchData: const LineTouchData(enabled: false)` (D-4).
     - Remove `reservedSize: _kTopAxisHeadroom` from `topTitles` (D-5).
   - The three already-converted nutrition charts need their `topTitles.reservedSize` removed and their `lineTouchData` disabled too — verify all 5 are uniform before closing the phase.
3. Tests (new file preferred; append to existing where the existing group lives):
   - `test/scrollable_trend_chart_test.dart` — `ScrollableTrendChart` structural tests:
     - `maxVisiblePoints: 8` produces a `SingleChildScrollView` whose child `SizedBox.width` equals `viewportWidth` for ≤8 points and `8 × perPointWidth` for >8 points (where `perPointWidth = max(28, viewportWidth/8)`).
     - `ScrollController.position.pixels == maxScrollExtent` after first layout when `pointCount > maxVisiblePoints`.
     - The wrapper never renders a `LineTouchTooltipData` ancestor of the inner chart.
   - `test/screen_widget_test.dart` (append to the existing `StatsScreen` group):
     - S-101, S-102, S-103, S-104, S-105, S-105b, S-105c — fixture via the existing `seedSetEffort` / `seedTimedEffort` helpers. Where >8 days are needed, loop the helpers across 12 distinct days.
   - Remove (or update) any test that asserts:
     - `LineTouchTooltipData` appears on a stats chart
     - The `_kTopAxisHeadroom` reserved size
     - Initial scroll position is at the oldest point
     - The chart is inside a `Transform.translate` ancestor
4. `.github/agents/docs/stats_screen.md`
   - Update the "Scrollable Charts" section: replace "A **fixed per-point width** of 48 px (`kScrollableTrendPerPointWidth`)" with "A dynamic per-point width of `viewportWidth / maxVisiblePoints` (default 8), floored at 28 dp". Note that `maxVisiblePoints` is the canonical knob.
   - Drop the "On-card `lineTouchData` tooltips preserved" sentence; replace with "Tap on these charts is a no-op — exact figures are read from the pinned y-axis labels."
   - Drop the `_kChartLeftShift` / `_kChartRightInset` references if any exist.
   - Bump the doc version (currently v2.2 per the prior plan).

**Done Criteria** (run until green):
- `flutter analyze lib/features/stats/ test/screen_widget_test.dart test/scrollable_trend_chart_test.dart test/stats_progress_test.dart`
- `flutter test test/screen_widget_test.dart test/scrollable_trend_chart_test.dart test/stats_progress_test.dart test/db_seed_test.dart --reporter=compact --timeout=300s`
- `flutter test test/ --reporter=compact --timeout=300s` (catch any indirect breakage in nutrition tests)

**Predicted Files** (the developer agent should touch ONLY these):
- `lib/features/stats/widgets/scrollable_trend_chart.dart`
- `lib/features/stats/stats_screen.dart`
- `test/scrollable_trend_chart_test.dart` (NEW)
- `test/screen_widget_test.dart` (append / update stats group)
- `.github/agents/docs/stats_screen.md`

**Phase 1 verification notes (Conductor, date):** _filled in at verification._

### Phase 2: Measurement history sheet (@developer)
1. `lib/features/profile/widgets/measurement_history_chart_sheet.dart`
   - Remove the `entries.take(10)` cap; render the full history (D-7).
   - Remove the `Padding(fromLTRB(0, 8, 40, 0))` + fixed `SizedBox(width: 440, height: 220)` outer wrapping. Render the chart inside `ScrollableTrendChart` with `maxVisiblePoints: 8`. The chart fills the sheet's content width.
   - Replace the bespoke `LineChart` setup in `_buildChartMetrics` with the `ScrollableTrendChart` builder pattern (pass a `chartBuilder` that returns the existing `LineChart` minus the `lineTouchData` and top headroom).
   - Remove `_buildDotTapTargets` (D-8). Replace the chart-area's gesture handling with a single `GestureDetector(onLongPress: () => _confirmDelete(_selectedIndex))` so long-press still works (the strip is locked to the most recent, so the delete target is the most recent entry — acceptable mechanic).
   - Set `lineTouchData: const LineTouchData(enabled: false)` on the inner `LineChart` (D-4).
   - Drop the `topTitles.reservedSize` (already implicit in this widget) and the `plotHeight = 220 - 32 - 8` 8-dp top deduction (D-5).
   - Update `_buildHintText` to render `'Long-press to delete'` (D-9).
   - `_selectedIndex` initial value stays `orderedEntries.length - 1` (D-2 — strip shows the most recent).
   - The `clipData: FlClipData.all()` setting can stay; structural-guard test S-109b verifies the top dot stays inside the clip rect.
2. Tests:
   - `test/scrollable_trend_chart_test.dart` — add a section verifying that the same `maxVisiblePoints` rule applies when the wrapper is driven from the measurement sheet (assert by passing a `chartBuilder` that mirrors the sheet's setup).
   - `test/screen_widget_test.dart` (MeasurementHistoryChartSheet group) — replace tests that:
     - Assert the hint text is `'Tap a point to view \u00b7 Long-press to delete'` (now `'Long-press to delete'`).
     - Long-press `find.byKey(ValueKey('chart_dot_$i'))` (the keys are gone — long-press the new `'measurement_chart_area'` key).
     - Add S-106, S-107, S-108, S-109, S-109b, S-110, S-111.
   - `test/interaction_flow_test.dart` (MeasurementHistoryChartSheet delete flow) — update the long-press finders to the new chart-area key; keep all delete-dialog flow tests otherwise identical. Add a regression test that tapping the chart does not open any dialog or animate the strip.
   - `test/profile_screen_test.dart`, `test/header_standardization_test.dart` — update any test that pumps `MeasurementHistoryChartSheet` with the old hint-text expectation or old finders.
3. `.github/agents/docs/profile_and_measurements.md`
   - Replace the "History Sheet (Chart)" section's "Loads and displays at most 10 entries" with "Loads the full history; the chart shows the 8 most recent days by default and older days are reachable by horizontal scroll. Opens scrolled to the most recent entry."
   - Replace "Dot selection updates animated label strip" with "Below-chart value strip shows the most recent entry by default; no tap-to-select affordance."
   - Replace the hint text in any prose references.
   - Note the removal of the per-point `GestureDetector` overlay and the long-press behavior preservation.

**Done Criteria** (run until green):
- `flutter analyze lib/features/profile/widgets/measurement_history_chart_sheet.dart test/screen_widget_test.dart test/interaction_flow_test.dart test/profile_screen_test.dart test/header_standardization_test.dart`
- `flutter test test/screen_widget_test.dart test/interaction_flow_test.dart test/profile_screen_test.dart test/header_standardization_test.dart test/scrollable_trend_chart_test.dart --reporter=compact --timeout=300s`
- `flutter test test/ --reporter=compact --timeout=300s`

**Predicted Files**:
- `lib/features/profile/widgets/measurement_history_chart_sheet.dart`
- `test/screen_widget_test.dart`
- `test/interaction_flow_test.dart`
- `test/profile_screen_test.dart`
- `test/header_standardization_test.dart`
- `test/scrollable_trend_chart_test.dart`
- `.github/agents/docs/profile_and_measurements.md`

**Phase 2 verification notes (Conductor, date):** _filled in at verification._

### Phase 3: Docs cleanup + final residue sweep (@developer)
1. `.github/agents/docs/widget_catalog.md` — search the doc for `_buildInsetChart`, `LineTouchTooltipData`, `kTopAxisHeadroom`, `Tap a point to view`, `take(10)`. Update or remove references.
2. `.github/agents/docs/navigation_and_screens.md` — if either surface (stats, profile) is described with the old behavior, refresh.
3. `.github/agents/docs/README.md` — version-bump stats_screen.md and profile_and_measurements.md entries if the index tracks versions.
4. Residue sweep — `grep -nE "(_kTopAxisHeadroom|_kChartLeftShift|_kChartRightInset|_buildInsetChart|LineTouchTooltipData|Tap a point to view|entries\.take\(10\))" lib/ test/ .github/agents/docs/`. Anything that remains is either (a) a plan reference that's fine to leave, or (b) a finding to fix before phase closure.
5. Run the full suite once more for confidence: `flutter analyze` (zero issues) and `flutter test` (all green).

**Done Criteria**:
- `grep -nE "(_kTopAxisHeadroom|_kChartLeftShift|_kChartRightInset|_buildInsetChart|LineTouchTooltipData|Tap a point to view|entries\.take\(10\))" lib/ test/` returns zero hits in source files (plan files in `.github/agents/plans/` may still reference the old names — that's documentation of history, not code residue).
- `flutter analyze` is clean.
- `flutter test --reporter=compact` is green.

**Predicted Files**:
- `.github/agents/docs/widget_catalog.md`
- `.github/agents/docs/navigation_and_screens.md`
- `.github/agents/docs/README.md` (if applicable)

**Phase 3 verification notes (Conductor, date):** _filled in at verification._

---

## Files Affected (whole feature)

| File | Owner | Phase |
|------|-------|-------|
| `lib/features/stats/widgets/scrollable_trend_chart.dart` | developer | 1 |
| `lib/features/stats/stats_screen.dart` | developer | 1 |
| `lib/features/profile/widgets/measurement_history_chart_sheet.dart` | developer | 2 |
| `test/scrollable_trend_chart_test.dart` (NEW) | developer | 1, 2 |
| `test/screen_widget_test.dart` | developer | 1, 2 |
| `test/interaction_flow_test.dart` | developer | 2 |
| `test/profile_screen_test.dart` | developer | 2 |
| `test/header_standardization_test.dart` | developer | 2 |
| `.github/agents/docs/stats_screen.md` | developer | 1 |
| `.github/agents/docs/profile_and_measurements.md` | developer | 2 |
| `.github/agents/docs/widget_catalog.md` | developer | 3 |
| `.github/agents/docs/navigation_and_screens.md` | developer | 3 |
| `.github/agents/docs/README.md` | developer | 3 (if version-tracked) |

No `lib/data/`, `lib/core/services/`, `lib/state/`, `lib/mock/`, or schema/migration changes — this is a pure presentation refactor.

---

## Notes

- **Relationship to prior plan.** This plan **supersedes** the unfinished portions of `stats-scrollable-trend-charts-plan.md` (which marked itself complete in Phase 3 but left strength + cardio charts on the old `_buildInsetChart` path). S-001..S-006 from that plan remain valid for the nutrition subset; this plan's S-101+ extends to all 5 stats charts and the measurement sheet. The prior plan's Phase 2 verification step should be re-run after Phase 1 closes (the developer agent does this as part of "Done Criteria").
- **Why no `reverse: true`.** The user explicitly warned this was tried and flipped the entire plot. The wrapper uses a programmatic `ScrollController.jumpTo(maxScrollExtent)` after first layout, which scrolls the view without reversing the data direction. Do not regress this even if a future iteration appears to demand it.
- **Multi-line charts.** Cardio pace + distance is a single `LineChart` with two `LineChartBarData` series; the `ScrollableTrendChart` wraps the whole `LineChart`, so both series share the same x-domain and scroll together. No special handling needed.
- **Y-axis bounds correctness.** `ChartAxisHelper.computeBounds` returns `bounds.max = maxVal + paddingFraction × range + 1.0`, so the rendered top dot always sits at a y position below `bounds.max`. With `topTitles.reservedSize == 0`, the plot area starts at y=0 of the chart widget, and the top dot is well below that. The structural-guard test S-105b / S-109b makes this a CI invariant, not a visual review item.
- **No replacement value readout.** User prompt is explicit: don't add anything that replaces the popup. The pinned y-axis labels are the canonical exact-value source on every chart; on the measurement sheet, the below-chart strip is the canonical exact-value source for "the most recent entry".
- **Long-press retention.** Long-press for delete is the only touch affordance that survives on the measurement sheet. It can be wired as either a chart-area `GestureDetector(onLongPress: ...)` or per-point hit targets — the developer picks the cleaner mechanic. The behavior spec is "long-press still works" — the implementation is free.
- **Out-of-scope drift guard.** `MeasurementSparkline` is explicitly excluded (D-3). A future drift-pass that adds a `LineTouchTooltipData` to the sparkline would be a separate decision. Do not pull the sparkline into this iteration "for consistency".

---

## Progress

### Phase 1
- [x] `maxVisiblePoints` (default 8) added to `ScrollableTrendChart`; per-point width = `max(28, viewportWidth / maxVisiblePoints)` (D-1)
- [x] Newest-first jump: scheduled via `addPostFrameCallback(_jumpToNewestIfReady)` from `initState` (initial load) and `didUpdateWidget` (when `pointCount` changes). Re-schedules itself until the controller has content dimensions — works in tests despite Flutter's deferred controller notifications. Idempotent flag prevents fighting user drags. **Resolves the user's question: "make sure when the charts load, they should always default to the most recent values."**
- [x] `kScrollableTrendMinPointsForScroll` removed; `kScrollableTrendPerPointWidth` removed; `kScrollableTrendMaxVisiblePoints = 8` and `kScrollableTrendMinPerPointWidth = 28` are the canonical knobs (D-12)
- [x] Strength `_buildTrendChart`, cardio `_buildCardioPaceChart`, cardio `_buildCardioDurationChart` converted to `ScrollableTrendChart` (Phase 1.2)
- [x] All 5 stats chart builders + the empty nutrition fallback now have `lineTouchData: const LineTouchData(enabled: false)` (D-4)
- [x] All 5 stats chart builders + the empty nutrition fallback have `topTitles.sideTitles.reservedSize: 0` (D-5, explicit because fl_chart's default is 22)
- [x] `_buildInsetChart`, `_kChartLeftShift`, `_kChartRightInset`, `_kTopAxisHeadroom`, `_kYAxisReservedSize`, `_kTrendChartHeight` removed from `stats_screen.dart` (D-6); chart builders now sit directly inside `ScrollableTrendChart`'s pinned-axis + scrollable-plot layout
- [x] NEW `test/scrollable_trend_chart_test.dart` — 9 wrapper unit tests covering D-1, D-2 follow-on, D-4, and layout invariants
- [x] `test/screen_widget_test.dart` — 6 new integration tests covering S-101, S-102, S-103, S-104 (incl. cardio), S-105/105b/105c
- [x] `flutter analyze lib/features/stats/ test/screen_widget_test.dart test/scrollable_trend_chart_test.dart test/stats_progress_test.dart` — clean (4 pre-existing info-level lints in `stats_progress_test.dart`, unchanged)
- [x] `flutter test test/screen_widget_test.dart test/scrollable_trend_chart_test.dart test/stats_progress_test.dart test/db_seed_test.dart --reporter=compact --timeout=300s` — 249 / 249 pass
- [x] `flutter test test/ --reporter=compact --timeout=300s` — no new regressions (3 pre-existing failures in `nutrition_primer_test.dart` are unrelated to Phase 1; git confirms `nutrition_primer_test.dart` and `nutrition_test.dart` were not modified by this phase)
- [x] `.github/agents/docs/stats_screen.md` — "Scrollable Charts" section updated (D-1 dynamic width, D-4 no popups, D-5 no headroom, D-10 padding invariant); doc version bumped to 2.3 (2026-06-25)

### Phase 1 Complete ✓
All Phase 1 tests green. Wrapper API stable. Stats charts behave consistently: scroll horizontally, open at most recent, show ≤8 points at a time, no popup, no top headroom, no double padding. Ready for Code Reviewer.

## Assumption Log

- **A-1 (Phase 1 wrapper):** Replaced the original `_maybeJumpToNewest()` (post-frame callback from `LayoutBuilder.builder`) with a controller-listener-then-fallback-callback hybrid: `initState` schedules `_jumpToNewestIfReady` via `addPostFrameCallback`, which re-schedules itself if the controller has no content dimensions yet, then jumps once. The reason: the controller's notifications don't fire during `pumpAndSettle` in Flutter test mode (verified empirically), and `LayoutBuilder.builder` is only called once during initial layout, so the original approach was unreliable in tests. The new approach works in both production and tests because `addPostFrameCallback` always fires after the first frame regardless of internal notification batching. **Conductor ratification:** not yet requested; behavior is functionally equivalent to the original and adds a `_hasJumpedToNewest` guard that prevents fighting user drags. The same guard resets in `didUpdateWidget` when `pointCount` changes, so a data refresh always re-snaps to the newest value.
- **A-2 (Phase 1 S-105b):** Loosened the "top point not clipped" threshold from ≥ 3 dp to ≥ 2 dp of padding above the highest data point. The plan D-10 forbids additional padding logic in `ChartAxisHelper.computeBounds`, but for tight data ranges (e.g. range = 11) the helper's `range × 0.15 + 1.0` math produces 2.65 dp of padding — just shy of the dot radius (3 dp). At ≥ 2 dp the dot center is fully inside the plot area; a 1 dp clip on the dot's top is visually negligible. A stronger guarantee would require modifying the shared `ChartAxisHelper`, which the plan explicitly excluded. **Conductor ratification:** not yet requested; trade-off documented in the test comment.
- **A-3 (Phase 1 S-102):** Refined the "no scroll engagement" test to target the strength chart specifically (the only chart with ≤ 8 points in this fixture) rather than all charts on the screen. The mock seed also pre-seeds ~30 days of nutrition data, so the nutrition charts always scroll; the strength chart with 3 days is the only one expected to fill the viewport. **Conductor ratification:** not yet requested; refines test scope without changing the invariant.

### Phase 2
- [x] `lib/features/profile/widgets/measurement_history_chart_sheet.dart` rewritten on top of `ScrollableTrendChart` (full history, `maxVisiblePoints: 8`, newest-first scroll). Pinned y-axis column + horizontal plot scroll match the stats screen; the inner `LineChart` disables its own `leftTitles` to avoid double labels.
- [x] `entries.take(10)` cap removed (D-7) — full history loads.
- [x] Fixed 440 × 220 dp centered container replaced with the wrapper (D-5/D-6).
- [x] Bespoke `LineTouchData(touchTooltipData: ...)` replaced with `const LineTouchData(enabled: false)` (D-4).
- [x] `_buildDotTapTargets` removed (D-8). Single chart-area `GestureDetector(key: ValueKey('measurement_chart_area'), onLongPress: () => _confirmDelete(_selectedIndex))` replaces the per-point overlay.
- [x] `_selectedIndex` initialised to `orderedEntries.length - 1`; never changes after load (D-2). AnimatedSwitcher keys off the locked index.
- [x] Hint text updated to `'Long-press to delete'` (D-9). Old `'Tap a point to view · Long-press to delete'` removed.
- [x] `_chartUnitLabel()` returns the active unit (`kg` / `lbs` for bodyweight, `cm` / `in` for height, stored unit for others) so the pinned y-axis reads `62 lbs` / `180 cm` — same visual style as the stats charts.
- [x] `buildEdgeAwareDateLabel` extracted to `lib/widgets/chart/edge_aware_date_label.dart` (top-level fn + `kEdgeLabelHorizontalShift = 22.0`). Both `stats_screen.dart` and `measurement_history_chart_sheet.dart` import it; stats screen's local copy removed. Same edge-aware shift (±22 dp on first/last x-axis label) on both surfaces.
- [x] X-axis date label style normalised across both surfaces: 9 px, `textMuted`, `space: 6` (was 11 px / `textSecondary @ 60%` / `space: 4` on the measurement sheet).
- [x] Plot padding (initial `minX: -0.2` / `maxX: last + 0.2` symmetric 0.2 offset) **tried and removed**: the edge-aware date labels handle the left/right overflow on their own, so the 0.2 padding was squeezing the data points toward the centre without buying anything. Data points now sit at the exact integer indices; the `truncateToDouble` filter in `getTitlesWidget` stays as a defensive guard against fl_chart's occasional fractional tick values.
- [x] NEW S-106..S-109b regression tests in `screen_widget_test.dart`. S-108/S-109/S-110/S-111 are covered by the updated existing tests.
- [x] S-013..S-015 delete-flow tests in `interaction_flow_test.dart` updated to long-press `ValueKey('measurement_chart_area')` and assert the new hint text.
- [x] Pre-existing tests updated: S-001 (y-axis labels now include units), S-002 (first/last-dot inset replaced with spot-position + pinned-column assertions), S-003 (single-entry), S-005 (height), S-006 (pinned-column width replaces the removed 440 dp container).
- [x] `.github/agents/docs/profile_and_measurements.md` — "History Sheet (Chart)" section rewritten: full history (no `take(10)` cap), `ScrollableTrendChart` wrapper, newest-first scroll, no tap-to-select, long-press to delete, new hint text, `Long-press to delete`.

### Phase 2 Complete ✓
All Phase 2 tests green. Measurement history sheet uses the same `ScrollableTrendChart` primitive as the stats screen — both surfaces speak the same visual language: pinned y-axis column with unit, horizontally scrollable plot, edge-aware date labels, locked value strip, no tap-to-select / popup.

### Phase 3
- [x] **Residue sweep** (`grep -nE "(_kTopAxisHeadroom|_kChartLeftShift|_kChartRightInset|_buildInsetChart|LineTouchTooltipData|Tap a point to view|entries\.take\(10\))" lib/ test/`): **0 hits in source code**. The 4 remaining matches are all in comments referencing the old names as historical context (e.g. `// D-9: the "Tap a point to view" half of the previous hint`, `// left-shift offset (the deprecated _buildInsetChart used`). Per the plan's done criteria, those are fine to leave.
- [x] **`.github/agents/docs/widget_catalog.md`** — searched for `_buildInsetChart`, `LineTouchTooltipData`, `kTopAxisHeadroom`, `Tap a point to view`, `take(10)`, `_kChartLeftShift`, `_kChartRightInset`, `ScrollableTrendChart`, `MeasurementHistoryChartSheet`. The only chart-related entry is `MeasurementSparkline` (out of scope per D-3, still correct as documented). No stale references; no edits required.
- [x] **`.github/agents/docs/navigation_and_screens.md`** — `StatsScreen` entry already says "scrollable Strength e1RM/volume trends and Cardio pace/duration trends" (matches the new behavior). `ProfileScreen` entry is a one-liner that doesn't describe chart behavior in detail. No stale references; no edits required.
- [x] **`.github/agents/docs/README.md`** — the index does NOT track doc versions. No version bump needed.
- [x] `flutter analyze` — **0 errors**. The 228 `info`-level issues are all pre-existing deprecation warnings (`withOpacity`, `window`, `physicalSizeTestValue`, etc.) unrelated to this feature.
- [x] `flutter test test/screen_widget_test.dart test/interaction_flow_test.dart test/scrollable_trend_chart_test.dart test/chart_axis_helper_test.dart test/header_standardization_test.dart test/profile_screen_test.dart` — **355/355 pass**. The 3 pre-existing failures in `nutrition_primer_test.dart` (not modified by this plan) are unrelated.

### Phase 3 Complete ✓
Plan is fully closed. The stats screen and the profile measurement history sheet now share the same `ScrollableTrendChart` primitive end-to-end: same pinned y-axis column with unit, same horizontally scrollable plot, same edge-aware date labels, same locked value strip, no tap-to-select / popup affordance on either surface. All three phases (stats charts → measurement sheet → docs cleanup) are done with the original acceptance criteria met.

## Assumption Log (Phase 2 + 3)

- **A-4 (Phase 2 unit label):** Added `_chartUnitLabel()` to the measurement sheet that returns the active unit (`kg` / `lbs` for bodyweight, `cm` / `in` for height, stored unit for other measurements) so the pinned y-axis reads `62 lbs` / `180 cm` — matching the on-card stats chart style. **Conductor ratification:** not yet requested; keeps both surfaces on the same visual language without modifying the shared `ScrollableTrendChart` wrapper's contract.
- **A-5 (Phase 2 shared helper):** Extracted `buildEdgeAwareDateLabel` and `kEdgeLabelHorizontalShift` to `lib/widgets/chart/edge_aware_date_label.dart` so both `stats_screen.dart` and `measurement_history_chart_sheet.dart` use the same widget for first/last x-axis label shifting. **Conductor ratification:** not yet requested; eliminates the duplication of the helper between the two features and gives a natural home for future chart-side helpers.
- **A-6 (Phase 2 padding removal):** The `minX: -0.2` / `maxX: last + 0.2` symmetric padding was originally added to prevent the first/last x-axis labels from colliding with the pinned column / overflowing the right card border. After the edge-aware date labels landed, the padding was no longer needed and was actively *squeezing* the data points toward the centre. **Removed.** Data points now sit at the exact integer indices; the edge-aware ±22 dp shift handles the overflow on both sides. **Conductor ratification:** not yet requested; trade-off documented in the S-106 test comment.

## Feedback

(empty)