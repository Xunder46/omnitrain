# Feature: rolling-session-calendar-duration-fix

## Overview
Fix a consistency bug where the calendar's monthly "Total Time" stat and the day
session list's per-session duration label both use wall-clock duration for rolling
sessions, inflating values by hours of idle time. The stats screen and session
summary builder already exclude rolling sessions from duration totals; this plan
brings the calendar into alignment.

## Requirements
- Calendar monthly Total Time excludes rolling sessions from the sum.
- Day session list per-session label shows only the start time (no duration
  suffix) for rolling completed sessions.
- Session count and modality breakdown are unaffected.
- Stats screen and session summary screen are untouched.
- The existing "—" zero-state placeholder is preserved.

## Acceptance Criteria
- [ ] Monthly Total Time on the calendar reflects only non-rolling completed sessions.
- [ ] A month containing only rolling sessions shows the zero-state placeholder.
- [ ] Day session list shows "HH:MM AM/PM" only (no duration) for rolling completed sessions.
- [ ] Day session list shows "HH:MM AM/PM · Xh Ym" as before for non-rolling sessions.
- [ ] Session count and modality breakdown still include rolling sessions.
- [ ] Stats screen and session summary screen behavior is unchanged.
- [ ] No visual or layout regressions for non-rolling cases on either surface.

## Scenarios

### Rolling session inflation
A rolling session that stayed open 8 hours of wall-clock time is NOT counted in
monthly Total Time, so the total equals only the sum of non-rolling sessions.

### All-rolling month
A month with only rolling completed sessions → Total Time shows "—".

### Mix month
Month with 1 non-rolling (1 h) + 1 rolling (8 h wall-clock) → Total Time = 1 h.

### Day list — rolling label
Completed rolling session started at 3:45 PM → subtitle line reads "3:45 PM"
with no duration suffix.

### Day list — non-rolling label
Completed non-rolling session started at 3:45 PM, 1 h 12 m duration →
"3:45 PM · 1h 12m" (unchanged).

---

## Iteration 1

### Analysis
Two surfaces need patching, both are pure logic fixes with no schema or model
changes:

1. **`CalendarState.totalTrainingMs`** (lib/state/calendar/calendar_state.dart)
   Add `&& !e.session!.isRolling` to the guard in the existing getter — mirrors
   the identical pattern already in stats_screen.dart lines 69-76.

2. **`_SessionRow._formatTimeDuration`** (lib/features/calendar/day_session_list_screen.dart)
   After computing `durationMs`, check `session.isRolling`; if true, return
   `timeStr` only (skip the duration suffix).

No DBA phase required — `TrainingSession.isRolling` already exists, is
persisted, and is available in the CalendarEntry via `e.session!.isRolling`.

### DB Changes
_None._

### Backend Changes

#### File: lib/state/calendar/calendar_state.dart
- In `totalTrainingMs` getter, add `&& !(e.session!.isRolling)` to the
  existing condition block:

  **Before:**
  ```dart
  if (e.isCompleted &&
      e.session != null &&
      e.session!.endedAtMs != null) {
    total += e.session!.endedAtMs! - e.session!.startedAtMs;
  }
  ```

  **After:**
  ```dart
  // Rolling sessions intentionally have no duration concept; exclude them
  // to stay aligned with session-summary and stats-screen logic.
  if (e.isCompleted &&
      e.session != null &&
      e.session!.endedAtMs != null &&
      !e.session!.isRolling) {
    total += e.session!.endedAtMs! - e.session!.startedAtMs;
  }
  ```

### Frontend Changes

#### File: lib/features/calendar/day_session_list_screen.dart
- In `_SessionRow._formatTimeDuration`, after building `timeStr`, add an early
  return for rolling sessions before computing the duration suffix:

  **Before (inside `_formatTimeDuration`):**
  ```dart
  final durationMs = session.endedAtMs! - session.startedAtMs;
  final totalMinutes = (durationMs / 60000).round();
  ...
  return '$timeStr · $durationStr';
  ```

  **After:**
  ```dart
  // Rolling sessions have no meaningful duration; show start time only.
  if (session.isRolling) return timeStr;

  final durationMs = session.endedAtMs! - session.startedAtMs;
  ...
  ```

### Implementation Steps

1. [ ] Edit `CalendarState.totalTrainingMs` — add `&& !e.session!.isRolling` guard.
2. [ ] Edit `_SessionRow._formatTimeDuration` — add early return for `session.isRolling`.
3. [ ] Update test `'totalTrainingMs sums durations of all completed sessions this month'`
       to explicitly assert non-rolling behavior (seed one extra rolling session and
       confirm the total is unchanged).
4. [ ] Add new CalendarState unit test: mixed month (1 h non-rolling + 8 h rolling) →
       totalTrainingMs == 3_600_000.
5. [ ] Add new CalendarState unit test: all-rolling month → totalTrainingMs == 0.
6. [ ] Add new CalendarState unit test: session count includes rolling sessions even
       though duration is excluded (completedSessionCount == 2, totalTrainingMs == 3_600_000
       for mixed month).
7. [ ] Add new widget test in DaySessionListScreen group: rolling completed session
       renders time only, non-rolling renders time + duration.

## Files Affected
- `lib/state/calendar/calendar_state.dart` — `totalTrainingMs` getter (1-line change)
- `lib/features/calendar/day_session_list_screen.dart` — `_formatTimeDuration` (~3 lines)
- `test/edge_case_test.dart` — update existing test + 3 new CalendarState unit tests
- `test/screen_widget_test.dart` — 1 new widget test for rolling label in DaySessionListScreen

## Notes
- This is a pure logic fix; no new state, no schema changes, no new UI components.
- Pattern to follow for `totalTrainingMs` is verbatim from stats_screen.dart lines 69-76.
- Pattern to follow for `_formatTimeDuration` is "early return if isRolling" — same
  as session_summary_builder.dart line 143 (`totalDurationMs: session.isRolling ? 0 : durationMs`).
- `_seedCompletedSession` helper in edge_case_test.dart does NOT currently accept
  `isRolling`; the new tests will need to construct `TrainingSession` directly with
  `isRolling: true`, or the helper should be extended with an optional `isRolling`
  parameter — whichever is more consistent with existing test style.

## Progress
- [x] Edit CalendarState.totalTrainingMs
- [x] Edit _SessionRow._formatTimeDuration
- [x] Update existing totalTrainingMs unit test
- [x] Add mixed-month unit test
- [x] Add all-rolling unit test
- [x] Add session-count guard unit test
- [x] Add widget test for rolling label

## Phase 1 Complete ✓
