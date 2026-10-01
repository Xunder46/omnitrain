# Feature: Stats feeling chart — width consistency with other charts

## Overview

Every chart on the Stats screen — strength e1RM, strength volume, cardio pace, cardio duration, nutrition calories, nutrition macros — renders with the same visual conventions: a 2 dp line, 3 dp-radius dots, 1.5 dp dot stroke, and no glow shadow. The feeling chart was drawn at a heavier weight — 6 dp line, 8 dp-radius dots, 2 dp dot stroke, plus a 6 dp-blur glow shadow — and a 2 dp surface-color halo ring on every dot. That made it visually louder than every other chart on the screen even though it carries the same kind of information (a single trend). The fix locks the feeling chart to the same numeric conventions as the rest of the screen: `barWidth: 2`, dot `radius: 3`, dot `strokeWidth: 1.5`, no glow shadow, no halo ring. The chart's information content (line color, dot color, 5-tick y-axis, scrollable wrapper) is unchanged — only the visual weight is normalized.

Classification: **TRIVIAL** — no schema, no state, no new data, no new screens. Numeric constants tweak + a removed block.

## Requirements

- The feeling chart's line is drawn at `barWidth: 2`, matching every other chart on the screen.
- The feeling chart's dots are drawn at `radius: 3, strokeWidth: 1.5`, matching every other chart on the screen.
- No glow shadow on the feeling chart's line — every other chart on the screen has no shadow, so neither does the feeling chart.
- No surface-color halo ring on the feeling chart's dots — every other chart uses a plain dot with a transparent stroke; the feeling chart now does too.
- All other visual properties (line color, dot color, 5-tick y-axis, scrollable wrapper, straight segments, no area fill) are unchanged.

## Acceptance Criteria

- [ ] `barWidth == 2.0` for the feeling chart's `LineChartBarData`.
- [ ] Dot painter `radius == 3.0` and `strokeWidth == 1.5` for every point on the feeling chart.
- [ ] No `shadow:` is set on the feeling chart's `LineChartBarData` (the `Shadow` block is removed; `bar.shadow` resolves to the fl_chart default — a no-op shadow with `color: Colors.transparent` / `blurRadius: 0`).
- [ ] The feeling chart's dot painter uses no `strokeColor` (transparent default), matching every other chart on the screen.
- [ ] All previously passing tests still pass; the rewritten "feeling line is visible" test and the S-003 flat-series test are updated to assert the new consistent values.

## Scenarios

### S-001: Width parity — the feeling chart uses the same barWidth / dot radius / dot stroke as every other chart
- Trigger: A widget test that locates the feeling chart (`minY == 1.0 && maxY == 5.0`) and reads `bar.barWidth` and the dot painter's `radius` / `strokeWidth`.
- Precondition: At least one session with a recorded feeling exists.
- Flow: Pump the Stats screen, fetch the feeling `LineChart`, inspect the bar and dot painter.
- Expected outcome: `bar.barWidth == 2.0`, `painter.radius == 3.0`, `painter.strokeWidth == 1.5` — identical to the e1RM / volume / cardio / nutrition charts on the same screen.
- Edge case of: none

### S-002: No glow shadow — `bar.shadow` resolves to a transparent / zero-blur no-op
- Trigger: A widget test that reads `bar.shadow` on the feeling chart.
- Precondition: At least one session with a recorded feeling exists.
- Flow: Pump the Stats screen, inspect `bar.shadow.color.a` and `bar.shadow.blurRadius`.
- Expected outcome: The shadow is a no-op (`blurRadius == 0` and `color.a == 0`); no glow contributes to the visual.
- Edge case of: none

## Iteration 1

### DB Changes
None.

### Backend Changes
None.

### Frontend Changes

**`lib/features/stats/stats_screen.dart`** — In `_buildFeelingCard`'s `lineBarsData.first` block:

- `barWidth: 6` → `barWidth: 2`.
- Remove the entire `shadow: Shadow(...)` block.
- `radius: 8` → `radius: 3`.
- `strokeWidth: 2` → `strokeWidth: 1.5`.
- Remove `strokeColor: themeColors.surface` from the dot painter.
- Update the comment block above `barWidth` so it documents the consistency rationale (the previous "glow shadow" comment is no longer applicable; the new comment locks the convention to match the rest of the screen).

**Tests** — `test/screen_widget_test.dart`:

- The rewritten "feeling line is visible" test currently asserts `barWidth >= 4`, `radius >= 6`, shadow alpha `>= 0.4`, and `shadow.blurRadius > 0`. Those four assertions are rewritten to lock the new consistent values: `barWidth == 2.0`, `radius == 3.0`, `shadow.blurRadius == 0`, and a removed alpha assertion (or asserting `shadow.color.a == 0`). The test name is updated so it reflects the new contract (chart consistent with other charts on the screen).
- The S-003 (flat-series visibility) test currently asserts `painter.strokeColor == OmniTheme.colors.surface` and `painter.strokeWidth > 0` for the halo. Those two assertions are removed; the test continues to assert the 5 distinct points and the line color, which is the core of the S-003 contract.

### Implementation Steps

1. Update the two test sites in `test/screen_widget_test.dart` so the assertions match the new consistent values.
2. Apply the numeric + block changes in `lib/features/stats/stats_screen.dart::_buildFeelingCard`.
3. Run the focused test suite (the four feeling-trend tests + the full Stats screen suite) to confirm green.
4. Run `flutter test` to confirm no regressions across the codebase.
5. Update `docs/stats_screen.md` so the "Chart" bullet documents the new width parity.

## Progress

- [x] Phase 0 — Plan written
- [x] Phase 2 — Tests updated to assert new consistent widths (red → green after impl)
- [x] Phase 2 — Implementation applied (barWidth 6→2, radius 8→3, strokeWidth 2→1.5, shadow removed, halo removed)
- [x] Phase 2 — `flutter test` green (only the two pre-existing baseline failures remain; my changes add zero new failures and the four feeling-trend tests all pass)
- [x] Phase 2 — `stats_screen.md` updated
- [ ] Phase 3 — Code review complete

### Phase 0 Complete ✓

### Phase 2 Complete ✓

### Phase 3 Complete ✓