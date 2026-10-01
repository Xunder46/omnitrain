# Feature: Calendar Duplicate Session Bug Fix

## Overview
When a user executes a workout that originated from a planned session, the calendar shows two entries for the same day: one for the real `TrainingSession` and one for the now-completed `PlannedSession`. The user sees what looks like "multiple saves" on the calendar, but it's actually a display/filtering bug.

## Root Cause Analysis

In `lib/state/calendar/calendar_state.dart`, `_loadMonth()` builds calendar entries from:

```dart
final entries = <CalendarEntry>[
  ...completedSessions.map(CalendarEntry.fromSession),
  ...plannedSessions.map(CalendarEntry.fromPlannedSession), // ALL planned sessions, including linked ones
];
```

When a planned session is executed:
1. A `TrainingSession` is created and completed → appears in `completedSessions`
2. `completePlannedSession()` marks the `PlannedSession` with `isCompleted: true` + `linkedSessionId: <the real session's id>`
3. BUT the `PlannedSession` still shows up via `getPlannedSessionsForDateRange` → ALSO added to entries

Result: two entries on the calendar for the same day. The `PlannedSession` with a `linkedSessionId` is already represented by its `TrainingSession` — it should be excluded.

## Requirements
- Planned sessions that have been executed (have `linkedSessionId != null`) must not appear as calendar entries, since their `TrainingSession` already appears
- Unexecuted planned sessions (past, today, or future — with `linkedSessionId == null`) must continue to show as before
- No other behavior changes

## Iteration 1

### DB Changes
None. `PlannedSession.linkedSessionId` field already exists in the model and is persisted.

### Backend/State Changes
Filter linked planned sessions out of the calendar entry list inside `_loadMonth()`.

### Frontend Changes
None beyond the state fix.

### Implementation Steps

#### Phase 1: State Fix (@developer)

1. [ ] In `lib/state/calendar/calendar_state.dart`, inside `_loadMonth()`, filter out planned sessions whose `linkedSessionId` is not null before creating entries:

   **Before:**
   ```dart
   final entries = <CalendarEntry>[
     ...completedSessions.map(CalendarEntry.fromSession),
     ...plannedSessions.map(CalendarEntry.fromPlannedSession),
   ];
   ```

   **After:**
   ```dart
   final unlinkedPlannedSessions =
       plannedSessions.where((p) => p.linkedSessionId == null).toList();

   final entries = <CalendarEntry>[
     ...completedSessions.map(CalendarEntry.fromSession),
     ...unlinkedPlannedSessions.map(CalendarEntry.fromPlannedSession),
   ];
   ```

2. [ ] Verify: run the app, create a planned session, start and finish it. Confirm only one dot appears on the calendar for that day.

3. [ ] Verify existing behaviour: a planned session that was never started (with `linkedSessionId == null`) still shows its outline/dot as before.

### Acceptance Criteria
- [ ] Completing a workout from a planned session shows exactly ONE dot/entry on the calendar (the TrainingSession), not two
- [ ] Unlinked planned sessions (not yet executed) still appear on the calendar as before
- [ ] `DaySessionListScreen` still shows the correct set of entries for a day (this reads from `calendarState.entriesForDay`, which is driven by the same `_entriesByDay` map — so it should be automatically correct)
- [ ] No changes to any model, repository, or other state classes required

### Files Affected
- `lib/state/calendar/calendar_state.dart` — `_loadMonth()` method only (~4 lines changed)

### Notes
- The fix is intentionally minimal: one filter predicate, no data model or repo changes
- Do NOT filter on `isCompleted` — a planned session could theoretically be marked complete without a `linkedSessionId` in future workflows; `linkedSessionId != null` is the precise signal that the TrainingSession already exists in the calendar
- The `completePlannedSession()` method always sets both `isCompleted: true` AND `linkedSessionId`, so the filter is safe

## Progress
- [x] Filter linked planned sessions in `_loadMonth()`
- [ ] Verify no duplicate on calendar after completing a planned session
- [ ] Verify unlinked planned sessions still appear

## Feedback
