# Feature: Measurement History Chart Readability

## Overview

Fix two readability regressions on the `MeasurementHistoryChartSheet` chart
(fl_chart `LineChart`) — restore vertical-axis value labels so a user can
estimate any data point's value from the chart alone, and inset the data line
horizontally so the first/last dots don't sit flush against the chart's left
and right edges. Both fixes are scoped to the history popup chart only; the
inline `MeasurementSparkline` on the profile cards and the larger scrollable
chart rework are out of scope.

---

## Phase Match Classification

**TRIVIAL** — focused readability fix on a single widget's chart configuration;
no schema change, no new state, no new user-facing screen. No mid-flight Q&A.
Iteration is one block.

---

## Analysis

### Affected files
- `lib/features/profile/widgets/measurement_history_chart_sheet.dart` — the only source file affected.

### Current state (verified)

The chart is built by `_buildChartMetrics()` (around lines 380–530 of the file).
The relevant configuration that locks in the broken behaviour:

- `gridData: FlGridData(show: false)` (line 442) — all grid lines hidden.
- `leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false))` (line 445) — no Y-axis labels.
- `rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false))` (line 446) — no right labels.
- Outer Padding wraps the chart at `fromLTRB(16, 8, 16, 0)` — only 16 dp on each side. With `leftTitles.reservedSize` defaulted to 0 (because `showTitles: false`), the chart's plot area extends edge-to-edge inside the `LineChart` widget, so the first and last dots at `minX=0` / `maxX=N-1` sit flush against the chart's visual bounds.

Inline comments at lines 139–142 and 438–440 narrate the prior A20 decision ("hidden entirely per A20", "Horizontal grid lines hidden per A20"). Those comments need to be rewritten to describe the new behaviour.

### Existing utilities to reuse

- `ChartAxisHelper.computeBounds(values)` (`lib/core/utils/chart_axis_helper.dart`) — padded axis bounds with a nice interval. Already used by `stats_screen.dart` and `scrollable_trend_chart.dart`. Floor of `+1.0` on the padded range keeps flat / single-value series readable.
- `ChartAxisHelper.readableIntervalForHeight(bounds, chartHeight)` — adjusts the interval so the visible number of Y-axis ticks stays within a spacing budget. Mirrors the established stats-screen pattern.
- `ChartAxisHelper.formatYAxisValue(value, unit, decimals: 0)` — formats with optional unit. The popup chart shows the unit in the selected-point label strip below the chart, so we pass an empty unit for the axis labels to avoid duplication. The `ProfileMeasurements.formatValue` helper already strips trailing `.0`s and can be used for the raw numeric string.

### Out of scope (deferred)

- Horizontal scrolling / paging / windowing — separate planned rework.
- `MeasurementSparkline` (inline mini-chart on profile cards) — already has Y-axis labels and proper horizontal insets; out of scope.
- Date axis, selected-point label, colors, log-entry button — unchanged.

---

## Requirements

- Restore vertical-axis value labels on the popup chart.
  - The lowest and highest plotted values are both labeled.
  - Labels are bare numeric values (no unit suffix); the unit is already in the selected-point label strip below the chart and the chart title.
  - Subtle horizontal grid lines return at the labeled tick positions to anchor the labels visually.
- Add internal horizontal breathing room to the data line so the first and last dots are visibly inset from the chart's left and right edges.
  - First dot's x position is strictly greater than the chart's left edge.
  - Last dot's x position is strictly less than the chart's right edge.
- Bottom date axis is unchanged — same dates, same positions, same formatting.
- Selected-point label strip still shows date · value unit.
- Fix applies to every measurement type that opens this popup (body weight, height, body fat %, lean mass, and the five circumferences).
- No horizontal scrolling, paging, or point-windowing introduced.

---

## Acceptance Criteria

- [ ] Opening any measurement's history popup shows value labels on the vertical axis; the lowest and highest plotted values are both labeled.
- [ ] A user can estimate a data point's value from the axis labels alone, without tapping the point.
- [ ] Subtle horizontal grid lines render at each labeled Y-axis tick.
- [ ] The first and last data points are visibly inset from the left and right edges of the chart; neither dot renders touching or clipped by the chart's bounds.
- [ ] The bottom date axis is unchanged — same dates, same positions, same formatting.
- [ ] The selected-point label beneath the chart still shows the date and the value with its unit.
- [ ] The fix is visible for every measurement type that opens this popup, not only body weight.
- [ ] No horizontal scrolling or point-windowing behaviour is introduced.
- [ ] All `OmniTheme` / `theme.colorScheme` colour and shape rules are preserved (no hardcoded colours; the chart's primary line + dot palette is unchanged).

---

## Scenarios

### S-001: Y-axis labels render the min and max plotted values
- Trigger: User opens any measurement's history popup with ≥2 entries.
- Precondition: At least two `BodyMeasurementEntry` records exist for that measurement type in the repository.
- Flow: User taps a measurement row on ProfileScreen → `MeasurementHistoryChartSheet` renders → chart appears.
- Expected outcome: At least two Y-axis labels render containing the minimum and maximum plotted values as bare numeric strings (e.g. `74.0` and `82.0`). No unit suffix is appended.
- Edge case of: none.

### S-002: First and last plotted points are inset from the chart's horizontal bounds
- Trigger: Same as S-001.
- Precondition: ≥2 entries spanning a non-trivial time range.
- Flow: Chart renders.
- Expected outcome: The position of the first plotted dot inside the chart is strictly greater than the chart's left visual edge; the position of the last plotted dot is strictly less than the chart's right visual edge. Neither dot sits on the chart's outer edge.
- Edge case of: none.

### S-003: Single-entry case still centers the dot and shows a Y-axis label
- Trigger: User opens a measurement's history popup with exactly one entry.
- Precondition: One `BodyMeasurementEntry` exists.
- Flow: Chart renders.
- Expected outcome: The single dot is horizontally centered in the chart's plot area (not touching either edge). A Y-axis label renders at that entry's value (the min and max are the same value).
- Edge case of: S-001, S-002.

### S-004: Bottom date axis and selected-point label are unchanged
- Trigger: User opens the history popup for any measurement type.
- Precondition: ≥2 entries.
- Flow: Chart renders.
- Expected outcome: Bottom date labels (X-axis) render at the same positions and with the same `MMM d` formatting as before. The selected-point label strip beneath the chart still shows `date · value unit` (e.g. `Jun 14 · 80 kg`).
- Edge case of: none.

### S-005: Fix applies to every measurement type
- Trigger: User opens the history popup for body weight, height, body fat %, lean mass, waist, chest, hips, thigh, or arm.
- Precondition: ≥2 entries exist for that measurement type.
- Flow: Each popup renders in turn.
- Expected outcome: Y-axis labels render for every measurement type. First/last dots are inset for every measurement type. The unit conversion path (kg ↔ lbs) for the `unit-kg` types is preserved through the existing `UnitFormatter.convertWeight` wiring.
- Edge case of: S-001, S-002.

---

## Iteration 1

### DB Changes
None.

### Backend Changes
None.

### Frontend Changes

#### 1. Restore Y-axis labels and grid lines

In `lib/features/profile/widgets/measurement_history_chart_sheet.dart`,
inside `_buildChartMetrics(theme)`:

- Replace `gridData: FlGridData(show: false)` with a subtle horizontal grid:
  - `show: true`
  - `drawVerticalLine: false`
  - `drawHorizontalLine: true`
  - `horizontalInterval` derived from `ChartAxisHelper.readableIntervalForHeight(bounds, plotHeight)`
  - `getDrawingHorizontalLine: (_) => FlLine(color: theme.colorScheme.onSurface.withOpacity(0.08), strokeWidth: 1)`
- Replace `leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false))` with:
  - `showTitles: true`
  - `reservedSize: 36`
  - `interval` matching the grid interval
  - `getTitlesWidget` using `SideTitleWidget(meta: meta, space: 4, child: Text(ChartAxisHelper.formatYAxisValue(value, ''), style: ...))` — pass an empty unit string so the axis labels are bare numbers.
- Compute the bounds via `ChartAxisHelper.computeBounds(values)` and pass them through `_ChartMetrics` so the grid interval, label interval, and `minY`/`maxY` all share the same source of truth.
- Keep `topTitles` and `rightTitles` hidden but set `reservedSize: 14` on `rightTitles` to add the right-side breathing room for the data line.

#### 2. Add internal horizontal breathing room

Two coordinated changes so the chart's plot area shrinks symmetrically:

- The Y-axis labels reserve 36 dp on the left (from step 1).
- The empty `rightTitles` reserves 14 dp on the right (from step 1).

Together these 36 + 14 = 50 dp of horizontal inset push the plot area 50 dp narrower than the `LineChart` widget. The first dot at `minX=0` and the last dot at `maxX=N-1` are now inset from the `LineChart` widget's left/right edges by those reserved sizes.

#### 3. Update the gesture-detector overlay to match the new plot area

The `_buildDotTapTargets(chartMetrics)` overlay currently assumes the plot area fills the `LineChart` widget. It must now subtract the reserved title space on both sides so its tap targets line up with the rendered dots:

- Extend `_ChartMetrics` with `leftReserved` and `rightReserved` fields.
- In `_buildDotTapTargets`:
  - `plotLeft = chartMetrics.leftReserved`
  - `plotWidth = max(0.0, constraints.maxWidth - chartMetrics.leftReserved - chartMetrics.rightReserved)`
  - Single-entry case: `x = plotLeft + plotWidth / 2`
  - Multi-entry case: `x = plotLeft + (i / (_entries.length - 1)) * plotWidth`

#### 4. Update inline comments

- Lines 139–142 ("Vertical axis values hidden entirely per A20") — rewrite to describe the restored labels and the breathing-room inset.
- Lines 438–440 ("Horizontal grid lines hidden per A20") — rewrite to describe the restored grid lines.

#### 5. No changes to the outer `Padding(fromLTRB(16, 8, 16, 0))`

The outer padding is fine — the breathing room comes from the inner title `reservedSize` adjustments, which shrink the plot area symmetrically inside the `LineChart` widget without affecting the overall chart footprint.

### Implementation Steps

1. **Phase 0.5 — TDD**: add the new widget tests to `test/screen_widget_test.dart` (red), run them to confirm they fail.
2. Update `_buildChartMetrics` to restore Y-axis labels + grid lines and add the right-side reserved size.
3. Extend `_ChartMetrics` with `leftReserved` and `rightReserved`; pass the values through.
4. Update `_buildDotTapTargets` to subtract the reserved sizes.
5. Rewrite the two stale A20 comments.
6. Re-run the full test suite; confirm new tests pass and no previously passing tests regress.
7. Run `flutter analyze lib/ test/` to catch any new analyzer warnings.

### Files affected

- `lib/features/profile/widgets/measurement_history_chart_sheet.dart` (modified)
- `test/screen_widget_test.dart` (modified — new tests appended to the existing `MeasurementHistoryChartSheet` group)
- No other production files affected.

---

## Progress

- [x] Phase 0 — Plan ✓
- [x] Phase 0.5 — TDD: write failing widget tests for Y-axis labels and horizontal inset
- [x] Phase 1 — Data layer (skipped — no schema, no repository changes)
- [x] Phase 2 — Logic & UI: restore Y-axis labels + grid lines + horizontal inset; update gesture overlay; rewrite A20 comments
- [x] Phase 3 — Code review

---

### Phase 0 Complete ✓

### Phase 1 Complete ✓ (skipped — no DB / repository changes for this read-only chart fix)

### Phase 2 Complete ✓

### Phase 3 Complete ✓