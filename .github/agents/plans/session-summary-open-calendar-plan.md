# Feature: session-summary-open-calendar

## Overview
Add an Open Calendar action in the Session Summary calendar header that navigates users to the full Calendar screen from Session Summary.

## Requirements
- Add a visible Open Calendar button in the Session Summary calendar card header.
- Tapping Open Calendar must navigate to CalendarScreen.
- Navigation must work whether Session Summary is opened from finishing a workout or from calendar/history flows.
- Preserve existing Session Summary layout style and responsive behavior.
- Keep architecture environment-agnostic (works the same with HiveWorkoutRepository now and future SqliteWorkoutRepository).

## Iteration 1

### DB Changes (@dba)
1. [ ] No schema changes required.
2. [ ] No repository interface changes required.
3. [ ] No seed data updates required.

### Backend Changes (@developer)
1. [ ] Extend SessionSummaryScreen API to support calendar navigation dependencies or callback injection without introducing repository leakage into UI.
2. [ ] Choose one navigation contract and apply consistently:
3. [ ] Option A (preferred): inject an onOpenCalendar callback into SessionSummaryScreen and let parent flows provide navigation behavior.
4. [ ] Option B: inject required calendar dependencies into SessionSummaryScreen (CalendarState, PeriodState, RoutineSessionService) and build CalendarScreen route internally.
5. [ ] Update all SessionSummaryScreen call sites to satisfy the selected contract:
6. [ ] From WorkoutSessionScreen finish flow.
7. [ ] From CalendarScreen completed-session flow.
8. [ ] From DaySessionListScreen completed-session flow.

### Frontend Changes (@developer)
1. [ ] Update calendar card header in [lib/features/session/session_summary_screen.dart](lib/features/session/session_summary_screen.dart#L1074) from title-only to title + action row.
2. [ ] Add Open Calendar button style aligned with existing utility button patterns in app theme (compact, accessible tap target, no overflow on narrow widths).
3. [ ] Wire button onPressed to selected navigation contract.
4. [ ] Keep existing monthly mini-grid and workout/rest day summary intact.
5. [ ] Ensure Open Calendar control is available in loading and loaded states where the calendar card is visible.

### Implementation Steps
1. [ ] Add/adjust imports in [lib/features/session/session_summary_screen.dart](lib/features/session/session_summary_screen.dart) for calendar navigation path chosen.
2. [ ] Refactor _buildCalendarCard to render a header row with month label on the left and Open Calendar action on the right.
3. [ ] Implement navigation callback or route push to CalendarScreen with required dependencies.
4. [ ] Update SessionSummaryScreen constructor and all invocations in:
5. [ ] [lib/features/session/workout_session_screen.dart](lib/features/session/workout_session_screen.dart#L1707)
6. [ ] [lib/features/calendar/calendar_screen.dart](lib/features/calendar/calendar_screen.dart#L164)
7. [ ] [lib/features/calendar/day_session_list_screen.dart](lib/features/calendar/day_session_list_screen.dart#L178)
8. [ ] Add/extend widget tests to verify button visibility and tap navigation behavior (target: [test/session_finish_timers_test.dart](test/session_finish_timers_test.dart)).
9. [ ] Run flutter test for touched tests and confirm no regressions in existing session finish/navigation behavior.

### Acceptance Criteria
- [ ] Session Summary calendar header displays an Open Calendar button.
- [ ] Tapping Open Calendar opens CalendarScreen.
- [ ] No missing dependency/runtime errors occur in any SessionSummaryScreen entry path.
- [ ] Existing calendar mini-grid and workout/rest day text remain unchanged.
- [ ] Existing finish-workout navigation behavior remains valid (back does not return to active workout session).
- [ ] Tests cover the new action at least for one session summary entry flow.

### Files Affected
- [lib/features/session/session_summary_screen.dart](lib/features/session/session_summary_screen.dart)
- [lib/features/session/workout_session_screen.dart](lib/features/session/workout_session_screen.dart)
- [lib/features/calendar/calendar_screen.dart](lib/features/calendar/calendar_screen.dart)
- [lib/features/calendar/day_session_list_screen.dart](lib/features/calendar/day_session_list_screen.dart)
- [test/session_finish_timers_test.dart](test/session_finish_timers_test.dart)

### Notes
- The docs referenced by conductor mode (for example docs/app_philosophy.md and docs/navigation_and_screens.md) are not present in this workspace, so this plan is grounded in live code inspection.
- Prefer callback-based navigation to reduce coupling and avoid threading extra state through unrelated constructors.

## Progress
- [x] Finalize navigation contract (callback vs dependency injection)
- [x] Implement Session Summary header action
- [x] Wire all SessionSummaryScreen entry points
- [x] Add/adjust widget test for Open Calendar navigation
- [ ] Verify no regression in finish-flow navigation

## Feedback
- 2026-03-22: Per product request, Calendar and Open Calendar buttons on Session Summary are temporarily hidden in UI using a feature flag (`_showCalendarActions = false`) in `session_summary_screen.dart`. Navigation plumbing remains in place for quick re-enable.

---

@developer - Please proceed with Phase 2 (Logic/UI) above. No data-layer work is required for this iteration.
