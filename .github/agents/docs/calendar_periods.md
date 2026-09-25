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

## Behaviour Rules

### Session Indicators

Each day renders an indicator per session: filled for completed, outlined for planned, coloured by
modality through `ModalityColorUtils`. Indicator count is capped, with the remainder shown as an
overflow count, so a heavy day never overruns its cell.

### Monthly Stats Strip

A strip below the grid reports four figures for the **displayed month**: completed session count,
total training time, the current streak (computed from up to 90 days of history, not just the
displayed month), and a per-modality breakdown. Values render as an em dash rather than a zero
when the month has no data, and the strip stays blank while the month is loading rather than
flashing placeholder values.

### Day Routing

Routing behavior is date-sensitive:
- **Past day + exactly 1 entry**:
  - If real completed `TrainingSession` -> `SessionSummaryScreen`
  - Otherwise -> `DaySessionListScreen`
- **Past day + multiple entries** -> `DaySessionListScreen`
- **Today/Future** -> `DaySessionListScreen`

### Day Session List

`DaySessionListScreen` groups entries into Completed first, then Planned.

**Past days are read-only.** Today and future days allow adding, editing, deleting, and starting a
planned session; a past day allows none of those. Tapping a completed entry opens its summary;
tapping a planned entry starts the workout via the routine build flow or the free/modality flow
depending on whether it is routine-linked.

When a workout is saved from the summary, the originating `PlannedSession` is marked completed and
linked via `linkedSessionId`.

**Effort tint.** A completed session row carries a 4dp left border in its session effort rating's
color — the theme's one-color intensity ramp via `feelingColor(rating, themeColors)`, from the
faintest step (1, Very easy) to the full accent (5, Max effort) — so a week reads as an intensity
map. Unrated sessions keep the standard border with no tint. Ratings recorded before the effort
rating replaced the feeling survey are shown the same way (see [Session Summary](session_summary.md)).

#### Historical-session summary behavior

When a `SessionSummaryScreen` is opened from the calendar flow (either
from the day-list row tap on a completed entry, or from a single-entry
past-day cell on the month grid), the screen is constructed with
`openedFromCalendar: true` and the originating `CalendarState`. This
unlocks three pieces of historical-aware behavior:

1. The embedded calendar card (the monthly grid + "workout days / rest
   days" totals) renders the **session's start month**, not today.
   Highlighting (the "today" border) follows the session's
   day-of-month.
2. The "Open Calendar" header button acts like the system back button:
   one `Navigator.pop()` returns to the day list (and a subsequent back
   to the calendar), instead of stacking a fresh `CalendarScreen` on
   top of the summary.
3. The overflow-menu "Discard" action permanently deletes the
   historical session from the repository and pops back to the
   originating day list (calendar state is refreshed so the deleted
   indicator disappears from the grid). The confirmation dialog copy
   reflects the destructive + "return to previous screen" semantics.

### Periods

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
9. Planned-session add/edit form uses the same shared mode selector and field-swap behavior.

---

## Invariants

**`recurrenceRule` is a placeholder field that is never read.** It exists on `PlannedSession` as a
model extension point; no code branches on it. Do not assume scheduling recurrence works.

---

## Related Documentation

- [State Management & Services](state_management.md)
- [Navigation & Screens](navigation_and_screens.md)
- [Data Models](data_models.md)
- [My Routines](my_routines.md)
- [Session Summary](session_summary.md)

---

**Document Version**: 1.1
**Last Updated**: April 13, 2026


---

> **Doc freshness** — Last reconciled against source: 2026-06-29. This doc is derived from source, not hand-maintained. Source of truth: the `lib/` tree as it exists on the reconciliation date. If you find a claim here that disagrees with `lib/`, `lib/` wins — please flag the drift in a fresh chat with the Coordinator agent.
