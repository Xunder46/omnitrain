# Feature: Stats feeling trend — fixed line color + per-point feeling colors

## Overview

The HOW DID IT FEEL trend on the Stats screen currently paints its connecting line in the same color as the **latest session's** feeling rating. When that rating maps to a color close to the theme background (e.g., feeling=5 resolves to `Theme.of(context).primaryColor`, which on some themes is the same hue family as the chart background or as a horizontal gridline), the entire line vanishes. The fix decouples the two visuals: the line gets one fixed, always-legible color drawn from `themeColors.primary` (the same single-color convention every other chart on the screen already uses), and each individual point is painted in its own session's feeling color via the shared `feelingColor(feeling, context)` helper — the same source the post-session survey tile and the day-session-list border already use. A halo ring on every point guarantees visibility even when the feeling color is close to the background or sits exactly on a horizontal gridline, so a flat trend (all sessions rated the same) still reads as a set of distinct points.

Classification: **TRIVIAL** — no schema change, no new state, no new data, no new screens. Single-chart coloring fix.

## Requirements

- The connecting line on the HOW DID IT FEEL chart must render in a single fixed color that does not change when any session's rating changes. The color must come from `themeColors.primary` (the existing single-line convention used by every other chart on the screen).
- Each point on the trend must be colored by its own session's feeling, sourced from `feelingColor(feeling, context)` — the same shared helper the survey tile and history-row accent already use.
- Each point must carry a halo stroke (`themeColors.surface`) so it remains visible when its feeling color is close to the chart background or sits exactly on a horizontal gridline.
- The line's glow shadow must follow the new fixed line color (not the latest feeling color).
- No multicolored / per-segment / gradient line. The line is one fixed color; only the points carry rating color.
- No averaging, smoothing, or aggregated value of any kind. No feeling scalar anywhere.
- Window logic, empty state, capture, and history-row accent are unchanged.

## Acceptance Criteria

- [ ] The connecting line renders in `themeColors.primary` (one fixed color, never `feelingColor(...)`); the line color is identical regardless of which rating is the most recent point.
- [ ] Each point is colored by `feelingColor(feeling, context)` for its own session's value; a window containing ratings 2, 4, and 5 produces three points with three distinct feeling colors.
- [ ] When the latest rating is 5 (the value that previously produced an invisible line because `feelingColor(5)` returned `Theme.of(context).primaryColor`), the line is fully visible — it is now `themeColors.primary` itself and contrasts against the chart background.
- [ ] When every session in the window has the same rating, every point is individually rendered with its halo stroke and is distinguishable from the horizontal gridline at that value (no disappearing-into-gridline).
- [ ] The line carries no gradient, no per-segment coloring, no averaged value, no feeling scalar.
- [ ] The existing test that asserted `bar.color == Colors.green` when the latest feeling is 4 (and `painter.color == Colors.green` for dots) is rewritten to assert the fixed line color and the per-point feeling color.

## Scenarios

### S-001: Fixed line color is invariant under the latest rating (regression guard)
- Trigger: Two windows with the **same** series shape but different latest ratings render the feeling chart with the **same** line color.
- Precondition: Two sets of sessions — series A ending with rating 2 (orange) and series B ending with rating 5 (theme.primary). Same theme.
- Flow: Render the Stats screen for each series; inspect `LineChartData.lineBarsData.first.color` on the feeling chart (minY=1, maxY=5).
- Expected outcome: `seriesA.lineColor == seriesB.lineColor == themeColors.primary`. The line color does not change with the latest rating.
- Edge case of: none

### S-002: Per-point feeling color matches the shared `feelingColor` source for each value
- Trigger: A window with mixed ratings — e.g., 2, 4, 5 — renders three points, each in its own feeling color.
- Precondition: Three sessions with feelings 2 (orange), 4 (green), 5 (theme.primary).
- Flow: Render the Stats screen; for each of the three indices in `bar.spots`, call `bar.dotData.getDotPainter(spot, i, bar, i)` and read the returned `FlDotCirclePainter.color`.
- Expected outcome: `painter[0].color == Colors.orange`, `painter[1].color == Colors.green`, `painter[2].color == themeColors.primary`. Each point's color equals `feelingColor(rating, context)`.
- Edge case of: none

### S-003: Flat-series visibility — every point is rendered and individually distinguishable
- Trigger: A window where every session is rated 4 (the color that previously caused the line to be drawn in green; the dots in green on a green-adjacent background can read as merged into a gridline).
- Precondition: Five sessions, all rated 4.
- Flow: Render the Stats screen; inspect `bar.spots.length` and the per-index dot painters.
- Expected outcome: `bar.spots.length == 5`. All five `FlDotCirclePainter` instances are present. Each carries a halo stroke (`strokeColor == themeColors.surface`, `strokeWidth > 0`). The line color is `themeColors.primary`, not green, so the connecting line is visible even though every dot is green.
- Edge case of: none

## Iteration 1

### DB Changes
None.

### Backend Changes
None. The `sessionFeeling` field on `TrainingSession` is unchanged; the `FeelingTrendPoint` model is unchanged; the aggregator in `StatsProgressService.computeFeelingTrend` is unchanged. This is a pure-presentation fix to `StatsScreen._buildFeelingCard`.

### Frontend Changes

**`lib/features/stats/stats_screen.dart`** — In `_buildFeelingCard`:

- Replace `final lineColor = feelingColor(trend.last.feeling, context);` with `final lineColor = themeColors.primary;`.
- In the `lineBarsData.first` block:
  - Keep `color: lineColor` and the matching `shadow: Shadow(color: lineColor.withValues(alpha: 0.55), blurRadius: 6)` — both now follow the fixed theme primary.
  - Replace the constant `FlDotCirclePainter(radius: 8, color: lineColor, strokeWidth: 2, strokeColor: themeColors.surface)` with a per-index lookup: `color: feelingColor(trend[i].feeling.toInt(), context)` (mapping `spot.y.round()` back to the session's feeling), `strokeColor: themeColors.surface`, `strokeWidth: 2`. This preserves the halo that already existed so each point is visible against gridlines and on close-to-background feeling colors.
- Update the comment block above the line color choice so it documents the new rule (line = fixed theme primary; points = per-session feeling color via the shared helper; halo = surface).

### Implementation Steps

1. Write the three failing tests in `test/screen_widget_test.dart` (S-001, S-002, S-003).
2. Rewrite the existing buggy assertion (the `feeling line is visible` test that pinned the line color to `Colors.green`) so it asserts the fixed line color and the per-point feeling color.
3. Apply the three-source edit in `_buildFeelingCard` (`lineColor`, per-point dot color, updated comment).
4. Run the full test suite — all Phase 0 scenario tests pass, no previously passing tests are now failing.
5. Update `docs/stats_screen.md` — replace the "Chart" bullet that currently says "the line color picked from `feelingColor(latestFeeling, context)`" with a sentence that documents the fixed line color and per-point feeling color, and add a deliberate-non-feature bullet noting that the line must not take its color from any session's rating.

## Progress

- [x] Phase 0 — Plan written
- [x] Phase 1 — Data layer (N/A — no model/repo/seed changes)
- [x] Phase 2 — TDD tests written (red, confirmed against buggy code)
- [x] Phase 2 — Implementation applied (green)
- [x] Phase 2 — Existing buggy test rewritten
- [x] Phase 2 — `flutter test` green (only the two pre-existing baseline failures remain; my changes add zero new failures and the four feeling-trend tests all pass)
- [x] Phase 2 — `stats_screen.md` updated
- [x] Phase 3 — Code review complete

### Phase 0 Complete ✓

### Phase 1 Complete ✓ (no-op — pure-presentation fix)

### Phase 2 Complete ✓

### Phase 3 Complete ✓

## Feedback

### Phase 0 Complete ✓