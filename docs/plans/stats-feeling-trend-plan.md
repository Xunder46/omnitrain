# Feature: Stats screen feeling trend

## Overview

Surface the already-captured post-session feeling as its own trend on the Stats screen, in the same scrollable-trend area and current-state window the Strength / Cardio / NUTRITION sections already use. The trend renders one point per completed session that has a recorded feeling (1–5); sessions without a feeling are omitted, never rendered as zero. The trend is a passive readout — no average-feeling tile, no stat number, no recommendation. It is universal across modalities (a runner or grappler with no lifting sees it identically) and is read against the total cross-modal training-time trend by visual alignment on the same time window.

## Requirements

- Add a "Feeling" trend card to the Stats screen, placed inside the same scrollable trend area as Strength / Cardio / NUTRITION.
- One point per completed session that has a `sessionFeeling` value; sessions without one are skipped (no zero-fill, no synthetic flat line).
- Trend uses the same current-state window resolved by `StatsProgressService.resolveWindow` — change the window → feeling trend moves with the others (lockstep).
- Universal across modalities — never gated on resistance / set / volume data. An all-running or all-grappling dataset renders identically.
- Use the existing visual language for feeling (the same `feelingColor(feeling, context)` palette already used on the day-session-list border tint).
- No stat tile, no summary number, no "average feeling" anywhere on the screen or in any stat grid.
- No rest / deload / recovery suggestion, banner, nudge, or call-to-action of any kind.
- Sessions with no recorded feeling are omitted from the trend, not counted as zero, not rendered as a dip that reads as a real drop.
- When the window contains no feeling data, render an explicit empty state — not an error, not a misleading flat line at zero.
- Do not touch the day-session-list feeling border tint; that stays as-is.

## Acceptance Criteria

- [ ] A feeling trend appears on the Stats screen using the same current-state window as the existing trends; changing the window updates it consistently with the others.
- [ ] The feeling trend renders for a user whose sessions are entirely non-strength (e.g., only runs and rolls) and is not blank or gated for them.
- [ ] The feeling trend can be visually compared, on the same time window, against the total training-time trend.
- [ ] No average-feeling number, feeling tile, or feeling entry appears in any summary/stat grid on the screen.
- [ ] No rest, deload, or recovery suggestion is shown anywhere as a result of this feature.
- [ ] Sessions with no recorded feeling are omitted from the trend, not counted as zero and not rendered as a dip that reads as a real drop.
- [ ] When the selected window contains no feeling data, an explicit empty state is shown — not an error, not a misleading flat line at zero.

## Scenarios

### S-001: Building the feeling series from a window of sessions
- Trigger: User opens Stats with several completed sessions, some with feeling, some without, all inside the recent-training-days window.
- Precondition: 5 completed sessions across the last 14 days; sessions #2 and #4 have `sessionFeeling` set (3 and 5); sessions #1, #3, #5 do not.
- Flow: `StatsScreen._loadData()` → `StatsProgressService.computeProgressData()` → `StatsProgressData.feelingTrend` is built.
- Expected outcome: `feelingTrend` has exactly 2 points, one per session that has a feeling, in chronological order; the sessions without a feeling are omitted entirely (not zero-filled).
- Edge case of: none

### S-002: All-non-strength dataset (universal) still produces a populated feeling series
- Trigger: A user whose only training is cardio (running) and rolls (sports); no set efforts at all.
- Precondition: 3 completed sessions in the window, all cardio_endurance or sports, each with a recorded feeling.
- Flow: Same as S-001.
- Expected outcome: `feelingTrend` has 3 points. No coupling to lifting / set / volume — the series is built independently from `TrainingSession.sessionFeeling`.
- Edge case of: S-001

### S-003: Empty window — explicit empty state, no fabricated points
- Trigger: User opens Stats inside the current window and zero sessions have a recorded feeling.
- Precondition: All completed sessions in the window have `sessionFeeling == null`.
- Flow: Same as S-001.
- Expected outcome: `feelingTrend` is `const []`. The UI renders an explicit empty-state card (e.g., "No feeling logged in this window yet") — not an error, not a flat line at 0.
- Edge case of: S-001

### S-004: Window recomputes the feeling series on the same boundaries as other trends
- Trigger: A user-defined training period covers today and contains sessions with feelings; then the period ends and the user re-opens Stats.
- Precondition: Period-scoped window with N sessions with feelings → resolves period window. Period ends → falls back to recent-training-days window.
- Flow: `resolveWindow(...)` switches between `isPeriodScoped: true` and `isPeriodScoped: false`. `computeProgressData()` re-walks the window both times.
- Expected outcome: `feelingTrend` reflects the same window that `topLifts` / `topCardio` were selected from. Changing the window moves the feeling trend in lockstep with the other trends.
- Edge case of: S-001

### S-005: Guard test — no feeling scalar / tile in the summary stat grid
- Trigger: A regression test that scans the rendered Stats screen for the ALL TIME summary stat row.
- Precondition: The Stats screen renders normally.
- Flow: Render the screen, query the DOM / widget tree under the ALL TIME summary stat grid for any text containing the word "feeling" or any numeric scalar derived from feeling.
- Expected outcome: No "Feeling" label appears in the summary stat grid. No "average feeling" / "X.X / 5" scalar appears anywhere in that region. (This locks the antipattern out so a future change can't accidentally re-introduce it.)
- Edge case of: none

### S-006: Omitted sessions are not rendered as dips
- Trigger: A user with 3 consecutive completed sessions; the middle session has no feeling; the surrounding two have feelings of 3 and 5.
- Precondition: Sessions day-0 (feeling=3), day-1 (no feeling), day-2 (feeling=5), all inside the window.
- Flow: `computeProgressData()` → `feelingTrend`.
- Expected outcome: `feelingTrend` has exactly 2 points at day-0 and day-2; day-1 is omitted. The chart does not interpolate a dip from 3 → 0 → 5.
- Edge case of: S-001

### S-007: Feeling color palette matches the day-session-list border tint
- Trigger: User logs a session with feeling 4; the day-session-list row gets a green left border.
- Precondition: Same `feelingColor(feeling, context)` palette already used elsewhere.
- Flow: Trend chart picks its line color from `feelingColor(latestFeeling, context)` or a stable, theme-derived shade; the palette mapping 1→red, 2→orange, 3→yellow, 4→green, 5→primary is reused.
- Expected outcome: The feeling trend visual language matches the existing session-history border tint, so the same number on both surfaces reads as the same color.
- Edge case of: none

## Iteration 1

### DB Changes
None. The `sessionFeeling` field already exists on `TrainingSession` and is round-trip-safe via `fromMap`/`toMap`. No schema, table, column, or migration changes.

### Backend Changes

**`lib/core/models/stats_progress.dart`** — Add value types:

```
class FeelingTrendPoint {
  final DateTime date;       // local midnight of the session
  final int feeling;         // 1..5
  const FeelingTrendPoint({required this.date, required this.feeling});
}
```

Add `final List<FeelingTrendPoint> feelingTrend;` to `StatsProgressData` (default `const []`).

**`lib/core/services/stats_progress_service.dart`** — Add a pure-Dart aggregator:

- Add `Future<List<FeelingTrendPoint>> computeFeelingTrend()` that:
  - Calls `_repository.getAllSessions()` and filters to completed (`endedAtMs != null`).
  - Filters to sessions whose `startedAtMs` falls within the **same window** that `computeProgressData()` resolves (calls `resolveWindow(...)` directly so the boundary check is identical).
  - Filters to sessions with non-null `sessionFeeling` (1..5).
  - Builds one `FeelingTrendPoint` per qualifying session: `date` = local-midnight `DateTime` derived from `startedAtMs`; `feeling` = `sessionFeeling`.
  - Sorts ascending by date.
  - Returns `const []` when no sessions qualify — no fabricated points, no zero-fill.
- Call `computeFeelingTrend()` from inside `computeProgressData()` and add the result to the returned `StatsProgressData`.

### Frontend Changes

**`lib/features/stats/stats_screen.dart`** — UI:

- Add a "HOW DID IT FEEL" section between the existing Strength / Cardio / NUTRITION sections (after Cardio, before NUTRITION is the natural read order; below NUTRITION is also acceptable — see Implementation Steps for the chosen slot).
- Each section header is an `OmniCardHeader(title: 'HOW DID IT FEEL', actions: [_buildWindowChip(...)])` — same window chip as the other sections, so the user reads the window as part of the chip.
- The trend chart:
  - Uses the existing `ScrollableTrendChart` wrapper.
  - Y-axis is the 1..5 feeling scale; the `unitLabel` reads "feeling".
  - One point per `FeelingTrendPoint`; the chart line is colored by `feelingColor(latestFeeling, context)` for visual consistency with the day-session-list border tint. (When the series is empty, the empty-state path is taken instead — no chart, no flat line.)
  - Sits inside the same scrollable container as the other charts.
- Empty state (when `feelingTrend.isEmpty` and the window is not "no sessions at all" — i.e., sessions exist but none have a feeling logged): an `OmniSurface` card with the text "No feeling logged in this window yet" — same visual treatment as the Strength / Cardio empty states. The current global "No sessions yet" empty-state card remains the no-sessions branch.
- **No stat tile.** The ALL TIME row of three pills (Sessions / Time / Streak) is unchanged. No "feeling" pill is added; no scalar is added to any grid.
- The feeling section does NOT add itself when `_totalSessions == 0` (same upstream guard as the other sections).
- No new state, no new repository calls — the service does the work and returns the trend inside `StatsProgressData`.

### Implementation Steps

**`lib/core/models/stats_progress.dart`**
1. [ ] Add `FeelingTrendPoint` class with `date` (local midnight) and `feeling` (int 1..5) — const constructor.
2. [ ] Add `final List<FeelingTrendPoint> feelingTrend;` to `StatsProgressData`. Default `const []`; update `StatsProgressData.empty` to keep `feelingTrend` empty.

**`lib/core/services/stats_progress_service.dart`**
3. [ ] Implement `Future<List<FeelingTrendPoint>> computeFeelingTrend()`:
   - `final allSessions = await _repository.getAllSessions();`
   - `final completed = allSessions.where((s) => s.endedAtMs != null).toList();`
   - `final periods = await _repository.getPeriods();`
   - `final window = resolveWindow(periods: periods, completedSessions: completed);`
   - For each completed session inside the window with non-null `sessionFeeling` in 1..5, build a `FeelingTrendPoint` from `startedAtMs`'s local-midnight.
   - Sort ascending by date; return.
4. [ ] Update `computeProgressData()` to call `computeFeelingTrend()` and pass the result to the returned `StatsProgressData`.

**`lib/features/stats/stats_screen.dart`**
5. [ ] In the main `ListView` body, after `_buildCardioSection(...)`, add `_buildFeelingSection(context, themeColors)` BEFORE the NUTRITION section.
6. [ ] Implement `_buildFeelingSection(...)`:
   - Render `OmniCardHeader(title: 'HOW DID IT FEEL', actions: [_buildWindowChip(context, themeColors, data.window)])`.
   - If `feelingTrend.isEmpty` AND `_totalSessions > 0` → render `_buildSectionEmptyState(..., 'No feeling logged in this window yet')`.
   - Otherwise render an `OmniSurface` containing the feeling chart, mirroring the structure of the other scrollable trend cards on the screen.
7. [ ] Implement `_buildFeelingChart(OmniThemeColors themeColors, List<FeelingTrendPoint> trend)`:
   - Use `ScrollableTrendChart` with `bounds = ChartAxisHelper.computeBounds([1.0, 2.0, 3.0, 4.0, 5.0])` (the full 1..5 range, so the chart never auto-scales below the semantic floor / above the semantic ceiling — feeling is ordinal, not continuous).
   - `unitLabel: 'feeling'`.
   - Line color = `feelingColor(trend.last.feeling, context)` (matches the session-border tint).
   - Spots: one `FlSpot(i.toDouble(), trend[i].feeling.toDouble())` per point.
   - `minY: 1.0`, `maxY: 5.0` (do NOT call `ChartAxisHelper.computeBounds` with the actual values — the feeling scale is fixed; otherwise a run of all-3s would clamp to a 3.0–3.0 flat line that reads as zero context).
8. [ ] Ensure the new section respects the existing "no sessions at all" guard: the global empty state still renders instead of the HOW DID IT FEEL card when `_totalSessions == 0`.

**`test/stats_progress_test.dart`**
9. [ ] Add unit tests for `computeFeelingTrend()`:
   - S-001: window of sessions, mix of feeling and no-feeling → exactly the feeling sessions, in chronological order.
   - S-002: all-non-strength dataset (only running / rolling sessions) → populated series, no gating.
   - S-003: window with zero feeling data → empty list, no crash, no fabricated points.
   - S-004: window recomputes on the same boundaries (seed a period covering today with feeling sessions, then verify `feelingTrend` reflects the period; remove the period and verify it reflects the recent-training-days fallback).
   - S-006: omitted sessions are skipped (no zero-fill interpolation between two points).

**`test/screen_widget_test.dart`** (and / or a new dedicated widget test)
10. [ ] Add a widget test (S-005) that pumps `StatsScreen` against a repository with sessions having `sessionFeeling` values and asserts that the rendered ALL TIME row does NOT contain the word "feeling" anywhere — locking out the antipattern of a feeling scalar in the summary stat grid.
11. [ ] Add a widget test asserting that the feeling trend chart is rendered inside an `OmniSurface` (so a future "tile" refactor that swaps the chart for a pill trips this guard).
12. [ ] Add a widget test asserting that for an all-non-strength dataset (only cardio sessions with feelings), the feeling trend renders and is not blank or gated.
13. [ ] Add a widget test asserting the empty state: when zero sessions in the window have a feeling, the empty card with "No feeling logged in this window yet" renders — no chart, no flat line.

**Verify**
14. [ ] Re-run all stats_progress + screen_widget + stats-related tests. The existing feeling-tint test for the day-session-list screen must remain unchanged and green.

## Progress

- [x] Phase 0 complete (this plan)
- [x] Phase 1 complete (data layer)
- [x] Phase 0.5 complete (TDD red→green tests)
- [x] Phase 2 complete (logic & UI)
- [x] Phase 3 complete (code review)
- [x] Iteration 2 complete (axis-label tweak)
- [x] Iteration 3 complete (line visibility + tapped-tile color)
- [x] Iteration 4 complete (kill the in-card labels; make the line definitively visible)
- [x] Iteration 5 complete (line glow + assert-mixed-case test labels)
- [x] Iteration 6 complete (modal title casing mismatch — re-evaluated by user)

### Iteration 6 (TRIVIAL — fast-track)

**Fast-track rationale.** Two `SessionSummaryScreen` widget tests were failing on the user's machine because the test assertions expected the modal title in upper case (`'HOW DID IT FEEL?'`) while the source rendered mixed case (`'How did it feel?'`). The user explicitly told the Developer to leave the source label alone ("don't change any stupid labels, the after session survey should stay 'How did it feel?', you only needed to fix the stats and unit tests") — so the fix is the opposite of the obvious one: tests are updated to match the source, not the other way around. No source label change.

#### Changes

**Test files (4 files, 12 assertions)** — all `'HOW DID IT FEEL?'` (uppercase) → `'How did it feel?'` (mixed case), matching `_FeelingSheetContent.build()`'s existing `'How did it feel?'` title:

- `test/screen_widget_test.dart` — 7 assertions in the `SessionSummaryScreen` group (`shows feeling modal on mount…`, `feeling modal is non-dismissible…`, `selecting tile 3 dismisses…`, `does not show feeling modal when session feeling already exists`).
- `test/header_standardization_test.dart` — 3 conditional dismissal blocks (`PopupMenuButton is present inside OmniBackHeader`, `overflow menu items are accessible after tapping menu`, `S-…` sheet-gating helper). The comments immediately above each conditional are also updated so the comments match the actual string.
- `test/session_finish_timers_test.dart` — 2 conditional dismissal blocks (`Finish workout finalizes active round and sets endedAtMs`, `Session summary shows Open Calendar button`). The narrative comments are updated in lockstep.
- `test/interaction_flow_test.dart` — 1 assertion in the SessionSummaryScreen flow that asserted `'HOW DID IT FEEL?'` was `findsNothing` after dismissal (the test was already lenient because `findNothing` matches absence, but the string was still inconsistent — corrected for consistency).

**`lib/features/session/session_summary_screen.dart`** — **unchanged.** The modal title remains `'How did it feel?'`. The Developer initially flipped the source to uppercase; the user then reverted that request, and the source is now exactly as it was before iteration 6.

### Iteration 5 (TRIVIAL — fast-track)

**Fast-track rationale.** Direct user feedback: the HOW DID IT FEEL trend line on the Stats screen was still hard to read on the device. Two assumptions from iteration 4 turned out to be too conservative: a bare 5dp stroke can wash out when it crosses a horizontal gridline, and a single 7dp dot pair can disappear next to a stronger gridline tick. This iteration adds a soft glow shadow in the line color so the line and the dots read against any background without introducing a second color into the visual language (the survey-tile fill / history-row border palette contract still holds — the shadow uses `lineColor.withValues(alpha: 0.55)`).

#### Changes

**`lib/features/stats/stats_screen.dart`** — `_buildFeelingCard`:
- `barWidth: 5` → `barWidth: 6`. A 5dp stroke was the iteration 4 floor; bumping to 6dp gives the line a clear edge against the 1dp gridlines without making it feel chunky on a 120dp-tall chart.
- Dot `radius: 7` → `radius: 8`. Single-pixel margin over the line so each data point reads as a distinct marker, not as a slightly thicker point on the line.
- **Added** `shadow: Shadow(color: lineColor.withValues(alpha: 0.55), blurRadius: 6)` on the `LineChartBarData`. The soft glow in the same color as the line is what makes it definitively visible — the bare stroke alone can still read thin when it crosses a horizontal gridline of the same approximate value, especially on the dark theme. The shadow color is pinned to `lineColor` (the same `feelingColor(latestFeeling, context)` the rest of the visual language uses) so no new vocabulary is introduced: the chart line, the glow, the dot fill, the survey-tile fill, and the history-row left border all share the same palette.

**`test/screen_widget_test.dart`** — `feeling line is visible…` test (the iteration 4 guard):
- Added two new assertions: `bar.shadow.color.a >= 0.4` (the shadow must actually contribute contrast, not be the default transparent) and `bar.shadow.blurRadius > 0` (the shadow must actually blur, not be a sharp duplicate of the stroke). These lock the shadow in so a future "simplify the bar" change can't quietly drop the glow and leave a flat 6dp stroke that's vulnerable to gridline bleed-through.

**Result.** 398 tests pass across `test/screen_widget_test.dart`, `test/stats_progress_test.dart`, `test/header_standardization_test.dart`, `test/session_finish_timers_test.dart`, and `test/interaction_flow_test.dart`. The two previously-failing `SessionSummaryScreen` tests (`shows feeling modal on mount with five numbered tiles`, `feeling modal is non-dismissible and blocks summary controls`) now pass against the unchanged `'How did it feel?'` source label. The Stats screen HOW DID IT FEEL chart is locked in with a 6dp line, 8dp dots, and a soft glow shadow in the line color — visible against any theme background, and the line color stays the same `feelingColor(latestFeeling, context)` palette shared by the post-workout survey tile and the day-session-list border.

### Iteration 4 (TRIVIAL — fast-track)

**Fast-track rationale.** Two surgical changes driven by direct user feedback: remove the in-card "Post-session feeling" title and the "1 = Rough · 5 = Great" caption (the user called them "stupid labels that shouldn't be there"), and make the line definitively visible by removing the curve, dropping the area-fill wash, and bumping line + dot weight. No schema, no new state, no new behavior.

#### Changes

**`lib/features/stats/stats_screen.dart`** — `_buildFeelingCard`:
- **Removed** the in-card title row (`● Post-session feeling`) and the caption (`1 = Rough · 5 = Great`). The `HOW DID IT FEEL` section header above the card is the title; the y-axis tick labels (1, 2, 3, 4, 5) already explain the scale.
- `isCurved: true` (with `curveSmoothness: 0.3`) → `isCurved: false`. Curved segments with sparse data can pull control points off-grid and render the line as a smear; straight segments read unambiguously on a 120dp-tall chart.
- `barWidth: 3.5` → `barWidth: 5`. A 3.5dp stroke was still too thin to read against the dark theme.
- Dot `radius: 5`, `strokeWidth: 1.5` → `radius: 7`, `strokeWidth: 2`. Larger dots compensate for the absence of the area fill.
- **Removed** `belowBarData` (was `BarAreaData(show: true, color: lineColor.withAlpha(40))`). The tinted region under the line was washing the line out on the dark theme — the user could see the chart's grid lines but not the line itself. Dropping the fill lets the line sit clean against the chart background.
- Restructured the card body: `OmniSurface(child: Column(children: [Row(...), ScrollableTrendChart(...)]))` → `OmniSurface(child: ScrollableTrendChart(...))`. The card now holds only the chart.

**`test/screen_widget_test.dart`**:
- Updated `feeling trend chart renders inside an OmniSurface` and `all-non-strength dataset` tests to check for the chart's presence via `find.byType(LineChart)` under `find.byType(OmniSurface)` (the previous signature check looked for the now-removed "Post-session feeling" text).
- Updated `feeling line is visible…` test:
  - Tightened thresholds: `barWidth >= 4.0`, `radius >= 6.0`.
  - Added new assertions: `bar.isCurved == false` (no smear), `bar.belowBarData.show == false` (no area fill wash).
- New test `feeling card has no in-card title` asserts that `find.text('Post-session feeling')` and `find.text('1 = Rough · 5 = Great')` both `findNothing`, while the HOW DID IT FEEL section header and the chart are still rendered.

### Iteration 3 (TRIVIAL — fast-track)

**Fast-track rationale.** Two visual tweaks: bump `barWidth` / dot radius so the line actually reads on a phone, and document that the line color is already the same palette as the post-workout survey tile's **selected** color (so the chart line and the survey-tile fill are the same vocabulary). No schema, no new state, no new behavior.

#### Changes

**`lib/features/stats/stats_screen.dart`** — `_buildFeelingCard`:
- `barWidth: 2` → `barWidth: 3.5`. A 2dp stroke was too thin on a 120dp-tall trend card.
- Dot `radius: 3` → `radius: 5`. Same reason — a 3dp dot disappeared on a 120dp chart next to a thicker line.
- `belowBarData.color: lineColor.withAlpha(25)` → `lineColor.withAlpha(40)`. A 10% alpha wash was effectively invisible; bumping to ~16% gives the area a faint tint without competing with the line for attention.
- Card padding restored to `(16, 16, 12, 16)` (was `(0, 16, 12, 16)` after a stray edit). The 0dp left padding clipped the card's content against its rounded border.
- Card title row restored to a dot indicator + `"Post-session feeling"`.
- Comment block above `lineColor =` now spells out the visual-language contract: the chart line color = `feelingColor(feeling, context)` = the post-workout survey tile's selected fill/border = the day-session-list left-border tint. Three surfaces, one palette.

**`test/screen_widget_test.dart`** — New guard test (`feeling line is visible (barWidth >= 3, dot radius >= 4) and its color matches feelingColor(latestFeeling)…`):
- Asserts the feeling chart's `barWidth >= 3.0` (visibility).
- Asserts the `FlDotCirclePainter.radius >= 4.0` (visibility, probed by calling `getDotPainter(...)` with the first spot and casting to `FlDotCirclePainter`).
- Asserts `bar.color == Colors.green` for a latest feeling of 4 — i.e. the chart line uses the same palette as `feelingColor(4)`, which is the same color the post-workout survey tile turns when the user taps the "4" tile.
- Asserts the dot painter's `color == Colors.green` (dots share the line color, not the theme primary).

### Iteration 2 (TRIVIAL — fast-track)

**Fast-track rationale.** The change is a single bounds tweak + a single copy change. No schema, no new state, no new behavior. No scenario Q&A, no exhaustive analysis.

#### Changes

**`lib/features/stats/stats_screen.dart`** — `_buildFeelingCard`:
- `ChartAxisBounds(min: 0.5, max: 5.5, interval: 1)` → `ChartAxisBounds(min: 1, max: 5, interval: 1)`. The 0.5..5.5 range produced 6 ticks (0.5, 1.5, 2.5, 3.5, 4.5, 5.5); the new range produces exactly the 5 integer ticks the spec demands (1, 2, 3, 4, 5).
- `unitLabel: 'feeling'` → `unitLabel: ''`. The "feeling" suffix on the y-axis labels is dropped; bare integers read cleanly.

**`test/screen_widget_test.dart`** — New guard test:
- Asserts `LineChart.data.minY == 1.0 && maxY == 5.0` on the feeling chart.
- Asserts the pinned-axis labels (Text widgets inside `ScrollableTrendChart`, excluding the inner `LineChart`'s own titles) include exactly "1", "2", "3", "4", "5" and never include the word "feeling".

**`docs/stats_screen.md`** — Updated HOW DID IT FEEL section to describe the 5-tick pinned y-axis and the bare-integer labels (was: "fixed 1..5 semantic range").

### Phase 3 Complete ✓
Code review executed. Doc hygiene updates applied to `docs/stats_screen.md` (HOW DID IT FEEL section, value-types line, "What Is Windowed" table). 267 tests pass across `test/stats_progress_test.dart` and `test/screen_widget_test.dart`. Pre-existing avatar_crop failures are unrelated to this feature (zero references to feeling/stats in that file).

### Phase 0 Complete ✓
Plan written; iteration 1 scope frozen.

### Phase 1 Complete ✓
`FeelingTrendPoint` value type added; `StatsProgressData.feelingTrend` field added (default `const []`); `StatsProgressService.computeFeelingTrend({required StatsWindow window})` implemented; `computeProgressData()` wires the trend into the returned data. No DB or repository interface changes — purely additive.

### Phase 0.5 Complete ✓
Seven new unit tests in `test/stats_progress_test.dart` (S-001..S-006 + 2 defensive guards: out-of-range values, in-progress sessions). Six new widget tests in `test/screen_widget_test.dart` (S-005 ALL TIME guard, HOW DID IT FEEL chart in OmniSurface, all-non-strength universality, empty-window explicit state, no-sessions global guard, no-dip interpolation guard). All 13 new tests pass.

### Phase 2 Complete ✓
`lib/features/stats/stats_screen.dart` now renders the HOW DID IT FEEL section between Cardio and NUTRITION using the same `OmniCardHeader` + `_buildWindowChip` pattern as the other sections. The chart sits inside a `ScrollableTrendChart` with a fixed 0.5..5.5 y-axis (feeling is ordinal; never auto-scaled), line color picked from `feelingColor(latestFeeling, context)` for visual parity with the session-history border tint, `LineTouchData.enabled = false` consistent with the other Stats charts. Empty-state card ("No feeling logged in this window yet") renders when `feelingTrend.isEmpty` and `_totalSessions > 0`. The no-sessions global empty-state card still wins when `_totalSessions == 0`. Analyzer: clean on all touched files.

## Feedback