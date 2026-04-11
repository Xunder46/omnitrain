# Stats Screen — Feature Documentation

## Overview

`StatsScreen` is a read-only analytics screen that surfaces aggregate training data for the current user. It is accessible from the maintenance sheet on the home screen. There are no interactive controls or filters in the current release — it is purely a display screen.

---

## Navigation Entry Point

```
HomeScreen
  └── Maintenance sheet (swipe up or tap hint)
        └── Stats → StatsScreen
```

---

## What the Screen Displays

The screen is organized into three sections, each rendered as an `OmniSurface` card:

### ALL TIME
A row of three stat pills:

| Stat | Source |
|------|--------|
| **Sessions** | Count of completed sessions across all time (sessions where `endedAtMs != null`) |
| **Total Time** | Sum of `endedAtMs − startedAtMs` for all completed sessions, formatted as h:mm |
| **Streak** | Current consecutive-day training streak, delegated to `CalendarState.streakDays`; a flame icon appears when streak ≥ 3 days |

### ACTIVITY
A **30-day session activity bar chart** built with `fl_chart`:

- Index 0 = 29 days ago; index 29 = today (window anchored at load time, never re-evaluated on rebuild)
- Bar height = number of completed sessions that day
- Bar color = `themeColors.primary` (current theme accent; not per-modality)
- X-axis labels appear at indices 0, 7, 14, 21, 28 in `"Mon DD"` format (short month name + day)
- Empty days render as zero-height bars

### REST TIME
A **multi-line chart** showing average rest duration (seconds) per day, one line per modality. Only visible when closed rest records exist in the 30-day window.

- Each line uses the modality accent color from `ModalityColors.forModality(modality)`
- Modalities displayed in order: `cardio_endurance`, `resistance_lifting`, `sports`, `isometric_stretching`, Free Training (`null`)
- Null-modality (Free Training) is included if rest records exist for it
- Days with no rest data for a modality are skipped (no gap-fill)

---

## Streak Calculation

Streak is not computed inside `StatsScreen`. A temporary `CalendarState` is created internally using the repository from `WorkoutState`, initialized, and its `streakDays` getter is read. The calculation logic lives in `CalendarState._computeStreak()` (up to 90 days of history). See [Calendar & Periods](calendar_periods.md) for full streak logic.

---

## How the 30-Day Chart Works

- `_dayCounts` is a 30-element `List<int>` initialized to zero, indexed `[0..29]` where 0 = 29 days ago and 29 = today
- Sessions in the 30-day window are iterated; each session contributes +1 to the `dayIndex` computed from `sessionDay.difference(thirtyDaysAgo).inDays`
- Only completed sessions (`endedAtMs != null`) are counted
- The date window is anchored at load time (`_thirtyDaysAgo`, `_today`) so that a midnight rebuild (e.g. triggered by a theme change) does not shift bar indices while `_dayCounts` still represents the original window

---

## Data Loading

All data is loaded in `_loadData()`, called once on first frame via `addPostFrameCallback`. Two repository calls are made in parallel:

```dart
final results = await Future.wait([
  widget.workoutState.getAllSessions(),           // all-time aggregates
  widget.workoutState.getSessionsByDateRange(fromMs, toMs),  // 30-day chart
]);
```

Rest averages are fetched via:
```dart
workoutState.repository.getEntryRestsByModalityInDateRange(fromMs, toMs)
```

The screen shows a `CircularProgressIndicator` while loading and an empty-state message when no completed sessions exist.

---

## What Is Intentionally Not in v1

- No per-modality session count breakdown
- No date range selector or filter controls
- No per-exercise or per-exercise-type stats
- No week / month / year toggle
- All deferred to post-launch iteration

---

## Core Files

| File | Role |
|------|------|
| `lib/features/stats/stats_screen.dart` | Full screen implementation |
| `lib/state/workout/workout_state.dart` | `getAllSessions()`, `getSessionsByDateRange()`, repository access |
| `lib/state/calendar/calendar_state.dart` | `streakDays` getter (created internally by `StatsScreen`) |
| `lib/state/settings/settings_state.dart` | Theme colors for the chart and layout |
| `lib/core/constants/modality_colors.dart` | Per-modality accent colors for the rest time chart |

---

## Related Documentation

- [Calendar & Periods](calendar_periods.md) — streak calculation details
- [State Management & Services](state_management.md)
- [Navigation & Screens](navigation_and_screens.md)

---

**Document Version**: 1.0
**Last Updated**: April 11, 2026
