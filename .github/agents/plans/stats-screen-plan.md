# Feature: Stats Screen

## Overview
Replace the `MaintenancePlaceholderScreen` backing the Stats tile in the maintenance sheet with a real, read-only `StatsScreen` that shows all-time aggregate stats, a 30-day activity bar chart, and the current training streak.

## Requirements
- Total Sessions card (all-time count of completed TrainingSessions)
- Total Training Time card (all-time sum of session durations, "Xh Ym" format)
- Current Streak card (same logic as CalendarState._computeStreak — reuse via CalendarState, not re-implementation)
- 30-day bar chart: session count per calendar day for last 30 days, using fl_chart (already a project dependency)
- Flame indicator on streak ≥ 3
- Empty state when zero completed sessions
- Theme-aware: OmniGradientBackground, OmniSurface, OmniTheme.colorsForTheme(settingsState.appTheme)
- No interactive elements, no filtering, no drill-down — read-only scroll

## Acceptance Criteria
- [ ] Stats tile in the maintenance sheet navigates to StatsScreen, not the placeholder
- [ ] Screen displays total sessions logged (all time)
- [ ] Screen displays total training time (all time, "Xh Ym")
- [ ] Screen displays current streak (consecutive training days, same logic as CalendarState)
- [ ] Screen displays a bar chart of sessions per day for the last 30 days
- [ ] Chart bars use the theme primary accent color
- [ ] Days with no session show as zero-height bars (no gaps in the x-axis)
- [ ] Screen respects the active theme (no hardcoded colors)
- [ ] Screen matches visual language: gradient background, OmniSurface cards, same typography
- [ ] If zero completed sessions, show meaningful empty state — no broken chart
- [ ] No new dependencies introduced (fl_chart already in pubspec.yaml)

## Scenarios
N/A (no new DI components required)

---

## Iteration 1

### DB Changes
None. All required data is accessible via existing repository methods:
- `repository.getAllSessions()` — yields all TrainingSessions; filter endedAtMs != null for "completed"
- `repository.getSessionsByDateRange(fromMs, toMs)` — used for 30-day chart window

### Backend Changes
None. No new repository methods, no new state classes, no schema changes.

### Frontend Changes

#### New file: `lib/features/stats/stats_screen.dart`
- `StatsScreen` is a `StatefulWidget`
- Constructor: `WorkoutRepository repository, SettingsState settingsState`
- `initState()` triggers `_loadData()` via `WidgetsBinding.instance.addPostFrameCallback`
- `_loadData()`:
  1. `getAllSessions()` → filter `s.endedAtMs != null` → compute totalCount and totalDurationMs
  2. `getSessionsByDateRange(30-days-ago, now)` → build `Map<int dayIndex, int count>` for the chart (dayIndex = 0..29, 0 = 30 days ago, 29 = today)
  3. Instantiate `CalendarState(repository)` and call `await calendarState.init()` → read `calendarState.streakDays`
  4. `setState(...)` with all results
- Build method:
  - Scaffold + OmniGradientBackground + SafeArea + ListView
  - AppBar title: "Stats"
  - Section 1: **Aggregate Stats card** (OmniSurface) — 2×2 grid of _StatPill widgets (Total Sessions, Total Time, Streak, [filler or 3-item row])
    - Specifically: three items (Sessions / Time / Streak) → layout as a Row of 3 Expanded _StatPill, matching the `_SummaryCard` rolling-session pattern in SessionSummaryScreen
  - Streak row includes flame icon (🔥 or `Icons.local_fire_department`) when streak ≥ 3, colored primary
  - Section 2: **30-Day Activity** card (OmniSurface) — subtitle "Last 30 days", BarChart via fl_chart
    - BarChart config: barGroups from `List.generate(30, ...)`, each group has one BarChartRod
    - Bar width relative to chart width (not hardcoded px)
    - Y-axis: `maxY = max(1, maxCount)`, no decimals, `interval = max(1, (maxCount / 4).ceil())`
    - X-axis: labels only on days 0, 6, 13, 20, 27 (weekly) — showing abbreviated date (e.g. "Mar 7")
    - Bar color: `themeColors.primary`
    - Grid lines: subdued using `themeColors.divider`
    - Touch interaction: disabled (read-only)
    - Chart height: 180
  - Empty state card: shown when `_totalSessions == 0` → replaces both sections with a single OmniSurface card containing centered icon + text

#### Modified file: `lib/features/home/home_screen.dart`
- Add import for `StatsScreen` and `WorkoutRepository`
- In `_buildMaintenanceGrid()`, replace the Stats `_MaintenanceItem` `onTap` from `_openPlaceholder(...)` to:
  ```dart
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => StatsScreen(
      repository: widget.workoutState.repository,
      settingsState: widget.settingsState,
    ),
  ))
  ```

### Implementation Steps

#### Phase 1: New screen (@developer)
1. [ ] Create `lib/features/stats/stats_screen.dart` with `StatsScreen` StatefulWidget
2. [ ] Implement `_loadData()`: getAllSessions, 30-day range query, CalendarState streak
3. [ ] Implement `_buildAggregateCard()` — 3-pill row (Sessions, Total Time, Streak) using `_StatPill` local private widget
4. [ ] Implement `_buildActivityChart()` using `BarChart` from fl_chart, zero-height bars for empty days
5. [ ] Implement `_buildEmptyState()` for zero sessions
6. [ ] Implement local `_formatDuration(int ms)` → "Xh Ym" (no sub-minute precision for all-time totals)
7. [ ] Add flame icon next to streak value when streak ≥ 3

#### Phase 2: Navigation wiring (@developer)
8. [ ] In `home_screen.dart`, add import for `StatsScreen`
9. [ ] Replace Stats tile `_openPlaceholder` call with `Navigator.of(context).push(...)` to `StatsScreen`

## Progress
- [x] Create stats_screen.dart
- [x] Load aggregate stats from repository
- [x] Load 30-day chart data
- [x] Compute streak via CalendarState
- [x] Build aggregate stats card (3 pills)
- [x] Build 30-day bar chart with fl_chart
- [x] Build empty state card
- [x] Wire Stats tile in home_screen.dart
- [x] Fix arch: WorkoutState delegates (getAllSessions, getSessionsByDateRange) — no direct repo in feature
- [x] Fix date drift: anchor _thirtyDaysAgo/_today in setState
- [x] Fix bar width: LayoutBuilder → (slotWidth * 0.65).clamp(3, 16)
- [x] Fix header Row overflow: Flexible + TextOverflow.ellipsis on date label
- [x] Extract _formatDuration → OmniDateUtils.formatDurationHoursMins
- [x] Remove dead MaintenancePlaceholderScreen tests from screen_widget_test.dart
- [x] Add 3 StatsScreen render tests (title, empty state, aggregate+chart)
- [x] Add 9 formatDurationHoursMins unit tests
- [x] Full test suite: 468 passed, 8 pre-existing failures, 0 regressions

## Phase Status: Complete ✓

## Feedback
<!-- Leave empty until a specialist or reviewer adds notes -->

---

**STOP — wait for explicit user approval before sending this handoff.**

Once approved:

@developer — Please proceed with all steps above (Phase 1 + Phase 2). No DB changes required.
