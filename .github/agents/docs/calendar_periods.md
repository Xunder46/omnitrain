# Calendar & Periods - Feature Documentation

## Overview

The **Calendar & Periods** feature provides day-level training planning and historical visibility inside a month calendar.

It combines:
1. **Calendar month grid** with per-day session indicators for both planned and completed sessions.
2. **Day session list** with date-aware editing rules and start/summary navigation.
3. **Training periods** (named date ranges) with overlap validation and calendar highlighting.

This feature is intentionally scoped for MVP planning workflows:
- No recurrence behavior yet (model extension point exists).
- Simple CRUD for planned sessions and periods.
- Reuse of existing workout execution and summary screens.

---

## User Workflows

### 1. Open Calendar

```
HomeScreen -> Maintenance sheet -> Calendar
  -> CalendarScreen
```

The existing maintenance-menu Calendar entry is reused (no duplicate navigation entry).

### 2. Month View + Session Indicators

Each day can render indicators for all sessions on that date:
- **Completed session**: filled circle
- **Planned session**: outlined circle
- **Color**: resolved from modality via `ModalityColorUtils` (delegates to `ModalityColors.forModality`)

Rendering rules:
- Up to 2 circles visible.
- Overflow shown as `+N` where `N = total - 2`.

### 3. Monthly Stats Strip

A compact stats strip sits below the calendar grid and fills the remaining vertical space, keeping the entire screen non-scrollable. It shows four stats for the **currently displayed month**:

| Stat | Description |
|------|-------------|
| **SESSIONS** | Count of completed sessions in the month; `—` if none |
| **TIME** | Sum of `endedAtMs − startedAtMs` for completed sessions, formatted as `Xh Ym`, `Xm`, or `Xs`; `—` if zero |
| **STREAK** | Consecutive-day streak ending today (or yesterday if no session today), computed from up to 90 days of history (not just the current month); 🔥 shown for streaks ≥ 3 |
| **Modality dots** | One colored dot + count per modality with ≥1 completed session, sorted by count descending; uses `ModalityColorUtils.colorForModality` |

Layout rules:
- Divider separates grid from strip.
- Strip fills all remaining vertical space below the grid via `Expanded`.
- While the month is loading, the strip area shows `SizedBox.shrink()` to avoid flashing `—` values.
- No scroll — grid uses `shrinkWrap: true` / `NeverScrollableScrollPhysics` so total height is bounded.

### 3. Tap a Day

Routing behavior is date-sensitive:
- **Past day + exactly 1 entry**:
  - If real completed `TrainingSession` -> `SessionSummaryScreen`
  - Otherwise -> `DaySessionListScreen`
- **Past day + multiple entries** -> `DaySessionListScreen`
- **Today/Future** -> `DaySessionListScreen`

### 4. Day Session List

`DaySessionListScreen` groups entries into:
1. **Completed**
2. **Planned**

Behavior by date:
- **Past day**: read-only
- **Today/Future**:
  - Add planned session
  - Edit planned session
  - Delete planned session
  - Tap planned session to start workout

Tap behavior:
- Tap completed entry -> opens `SessionSummaryScreen`
- Tap planned entry -> starts workout:
  - Routine-linked planned session -> routine build flow
  - Modality-only planned session -> free/modality workout flow

When workout is saved from summary, the originating `PlannedSession` is marked completed and linked via `linkedSessionId`.

### 5. Periods

From `CalendarScreen` app bar:
```
Periods button -> PeriodListScreen -> Create/Edit Period
```

Period capabilities:
- List name + date range
- Create and edit
- Delete
- Optional modality focus tags
- Optional notes
- Curated color palette (stored as `colorHex`)

Calendar highlights days covered by periods with a semi-transparent background.

---

## Data Model

### PlannedSession

**Model**: `PlannedSession` in `lib/data/models/models.dart`

Key fields:
- `id`
- `scheduledDateMs` (start-of-day local)
- `modality` (nullable)
- `routineTemplateId` (nullable)
- `isCompleted`
- `linkedSessionId` (nullable)
- `recurrenceRule` (nullable placeholder)

Notes:
- Planned records are lightweight scheduling entities.
- They are distinct from full `TrainingSession` payloads.

### TrainingPeriod

**Model**: `TrainingPeriod` in `lib/data/models/models.dart`

Key fields:
- `id`
- `name`
- `startDateMs`
- `endDateMs`
- `focusModalities`
- `notes`
- `colorHex` (nullable)

Validation rule (non-overlap):
`new.start <= existing.end && new.end >= existing.start`

---

## Repository Contracts

**Interface**: `WorkoutRepository` (`lib/data/repositories/workout_repository.dart`)

Planned sessions:
- `getPlannedSessions()`
- `getPlannedSessionsForDateRange(fromMs, toMs)`
- `createPlannedSession(session)`
- `updatePlannedSession(session)`
- `deletePlannedSession(id)`
- `getPlannedSessionsByTemplateId(templateId)`
- `deletePlannedSessionsByTemplateId(templateId)`

Periods:
- `getPeriods()`
- `getPeriodById(id)`
- `createPeriod(period)`
- `updatePeriod(period)`
- `deletePeriod(id)`
- `hasPeriodOverlap(startMs, endMs, {excludeId})`

Implemented in:
- `HiveWorkoutRepository`
- `MockWorkoutRepository`

---

## State Management

### CalendarState

**File**: `lib/state/calendar/calendar_state.dart`

Responsibilities:
- Maintains displayed month (`year`, `month`)
- Loads completed + planned sessions for month range
- Groups entries by day for month grid
- Exposes period list for highlights
- Handles planned session CRUD
- Handles `completePlannedSession(plannedSessionId, linkedSessionId)`
- Computes monthly stats and current streak from loaded data

#### Monthly Stats Getters (derived from `_entriesByDay`)

| Getter | Type | Description |
|--------|------|-------------|
| `completedSessionCount` | `int` | Count of entries where `isCompleted == true` |
| `totalTrainingMs` | `int` | Sum of `endedAtMs − startedAtMs` for completed entries with a real session |
| `modalityBreakdown` | `Map<String?, int>` | Completed session count grouped by modality key (null = Free Training) |
| `streakDays` | `int` | Current consecutive-day streak (see below) |

#### Streak Calculation (`_computeStreak`)

Called concurrently with `_loadPeriods()` at the end of each `_loadMonth()`:

1. Fetches sessions for the last 90 days via `repository.getSessionsByDateRange`.
2. Builds a `Set<int>` of UTC-midnight timestamps for days that have a completed session.
3. Anchors on **today** if today has a session, else on **yesterday** if yesterday has one.
4. Walks backwards day-by-day counting consecutive days present in the set.
5. Stores the result in `_streakDays` (defaults to 0 on error or no anchor day).

> The 90-day window caps the displayed streak at 90. Increase the window if longer streaks are needed.

### PeriodState

**File**: `lib/state/period/period_state.dart`

Responsibilities:
- Period list loading
- Create/update/delete period
- Form validation:
  - Name required
  - Max length 50
  - `start <= end`
  - No overlap (with optional `excludeId`)

### RoutineState Integration

`RoutineState.deleteRoutine()` cascade-deletes planned sessions for that template via repository.

`MyRoutinesScreen` warns users when routine deletion would remove planned sessions.

---

## Screen Map

- `lib/features/calendar/calendar_screen.dart`
- `lib/features/calendar/day_session_list_screen.dart`
- `lib/features/period/period_list_screen.dart`
- `lib/features/period/create_period_screen.dart`

Supporting flows:
- `lib/features/session/workout_session_screen.dart`
- `lib/features/session/session_summary_screen.dart`
- `lib/features/routine/my_routines_screen.dart`

---

## UX Rules Snapshot

1. Calendar indicators include both planned and historical sessions.
2. Indicator style communicates state (filled vs outlined).
3. Day list is grouped: Completed first, Planned second.
4. Past days are read-only in day list.
5. Planned-session tap starts workout using correct modality/routine path.
6. Completed-session tap opens summary.
7. Period overlap is rejected before save.
8. Period colors are curated presets and used as calendar highlights.

---

## Current Limitations

1. Recurrence is not implemented; `recurrenceRule` is placeholder-only.
2. End-to-end smoke test checklist should be run after major calendar/period changes.

---

## Related Documentation

- [State Management & Services](state_management.md)
- [Navigation & Screens](navigation_and_screens.md)
- [Data Models](data_models.md)
- [My Routines](my_routines.md)
- [Session Summary](session_summary.md)

---

**Document Version**: 1.0
**Last Updated**: March 10, 2026
