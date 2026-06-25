# Calendar Bugs Fix — Historical Summary Screen

## Overview

Fix three related bugs in the historical-session summary flow on
`SessionSummaryScreen`:

1. The embedded calendar grid renders the **current month**, not the
   session's month, when viewing a historical session.
2. The "Open Calendar" button on a historical-session summary **pushes a
   fresh `CalendarScreen`** on top, instead of behaving like the system
   back button when the user originally navigated from the calendar.
3. Discarding a historical session from the summary screen **pops to the
   home hub** (the first route), instead of returning to the calendar or
   day details that originated the navigation.

The fixes preserve the existing active-session post-workout summary flow
(workout finish → save or discard → home).

## Requirements

- The summary's calendar widget MUST display the calendar month and grid
  matching the loaded session's `startedAtMs`.
- The summary's "Open Calendar" button MUST behave like the system back
  button when the screen was opened from the calendar/day-list flow.
  In the post-workout active-session flow it MUST keep pushing a new
  `CalendarScreen` (current behavior).
- Discarding a historical session from the summary MUST return the user
  to the screen they came from (calendar or day list), and MUST refresh
  the calendar state so the deleted session disappears from the grid.
- The existing post-workout flow (workout finish → save / discard →
  home) MUST be unchanged.

## Acceptance Criteria

- [ ] Historical session summary shows the calendar grid for the
      session's start month, not the current month.
- [ ] Historical session summary's calendar header label uses the
      session's start month and year.
- [ ] Historical session summary's "today" cell indicator uses the
      session's day, not the current day.
- [ ] "Open Calendar" on a historical summary opened from the calendar
      pops back to the previous screen (one `Navigator.pop`), instead of
      pushing a new `CalendarScreen`.
- [ ] "Open Calendar" on a post-workout summary (active-session flow)
      still pushes a fresh `CalendarScreen`.
- [ ] Discarding a historical session from the summary returns to the
      originating calendar or day list, and the deleted session no
      longer appears in the calendar grid.
- [ ] Discarding a session from the post-workout summary still returns
      to the home hub (first route).
- [ ] Phase 0.5 TDD: red tests are written and confirmed to fail
      against the unfixed code before implementation begins.

## Scenarios

### S-001: Historical session summary calendar shows the session's month
- Trigger: User taps a past day on the calendar and the only entry on
  that day is a completed session.
- Precondition: A historical `TrainingSession` exists with
  `startedAtMs` in a month different from the current month (e.g.
  March 2025 while today is June 2026).
- Flow: Tapping the day pushes `SessionSummaryScreen` with the
  historical session loaded.
- Expected outcome: The summary's calendar header label is
  "March 2025" and the calendar grid renders the March 2025 layout
  (e.g. 31 cells for March, weekday-leading blanks matching March 1
  2025's weekday).
- Edge case of: none.

### S-002: Historical session summary "Open Calendar" behaves like back
- Trigger: From the historical summary reached via the calendar, the
  user taps the "Open Calendar" button in the calendar card header.
- Precondition: Summary was pushed from `CalendarScreen` (or
  `DaySessionListScreen` reached from the calendar); the back stack
  contains the originating calendar route.
- Flow: User taps "Open Calendar".
- Expected outcome: A single `Navigator.pop` returns to the previous
  screen (calendar or day list). No fresh `CalendarScreen` is pushed on
  top.
- Edge case of: none.

### S-003: Post-workout "Open Calendar" still pushes a fresh calendar
- Trigger: From the post-workout summary reached after finishing a
  workout, the user taps the "Open Calendar" button.
- Precondition: Summary was pushed via `pushReplacement` from
  `WorkoutSessionScreen` after the workout was finished; the only route
  behind the summary is the home hub.
- Flow: User taps "Open Calendar".
- Expected outcome: A fresh `CalendarScreen` is pushed on top of the
  summary, identical to the current behavior.
- Edge case of: none.

### S-004: Discarding a historical session returns to calendar
- Trigger: From the historical summary opened via the calendar, the
  user opens the overflow menu and taps "Discard", then confirms.
- Precondition: Summary is on top of a `CalendarScreen` (or
  `DaySessionListScreen` reached from it). The historical session
  exists in the repository.
- Flow: User taps Discard, confirms the dialog, the session is
  deleted, the calendar state is refreshed.
- Expected outcome: The summary is dismissed and the user lands on the
  originating calendar (or day list). The calendar grid no longer
  shows the deleted session.
- Edge case of: none.

### S-005: Discarding from post-workout summary still goes to home
- Trigger: From the post-workout summary reached after finishing a
  workout, the user opens the overflow menu and taps "Discard", then
  confirms.
- Precondition: Summary is on top of the home hub (post-workout flow,
  reached via `pushReplacement`).
- Flow: User taps Discard, confirms, the session is deleted.
- Expected outcome: `popUntil(isFirst)` returns to the home hub,
  identical to the current behavior.
- Edge case of: none.

## Iteration 1

### DB Changes

No DB changes. `TrainingSession` model already carries `startedAtMs`.

### Backend Changes

None (Dart-only state holders).

### Frontend Changes

#### `lib/features/session/session_summary_screen.dart`
- Add an optional `bool openedFromCalendar` to `SessionSummaryScreen`.
- Derive a `_viewMonth` `DateTime` from
  `widget.workoutState.currentSession?.startedAtMs ?? DateTime.now()`
  instead of `DateTime.now()` in:
  - `_loadCalendarData()` (load window for the displayed month).
  - `_buildCalendarHeader()` (month label).
  - `_buildCalendarCard()` and `_buildCalendarGrid()` (grid layout,
    leading-blank math, "today" indicator).
- Replace `_openCalendarScreen()` with a branched implementation:
  - If `openedFromCalendar == true`: call `Navigator.pop()`.
  - Otherwise: keep the current `OmniNavigator.push(CalendarScreen(...))`.
- Replace `_discardSession()` with a branched implementation:
  - If `openedFromCalendar == true`: keep the existing
    `widget.workoutState.discardCurrentSession()` (deletes the session
    from the repository — the user wants to remove the historical
    record), refresh the calendar state via
    `widget.calendarState.refresh()` so the deleted session disappears
    from the grid, then `Navigator.pop()` to return to the originating
    calendar or day list.
  - Otherwise: keep the existing delete + `popUntil(isFirst)`.
- Update the discard dialog body text to reflect the difference
  (calendar/day list vs. home) so the messaging stays accurate.

#### `lib/features/calendar/calendar_screen.dart`
- Pass `openedFromCalendar: true` when pushing `SessionSummaryScreen`
  from `_openSessionSummary`.

#### `lib/features/calendar/day_session_list_screen.dart`
- Pass `openedFromCalendar: true` when pushing `SessionSummaryScreen`
  from `_tapCompleted`.

#### `lib/features/session/workout_session_finish.dart`
- Pass `openedFromCalendar: false` (or omit — default `false`) when
  pushing `SessionSummaryScreen` after a workout finishes. This keeps
  the post-workout behavior identical to the current implementation.

### Implementation Steps

1. Phase 0.5 — Write failing tests in `test/screen_widget_test.dart`
   (or a new `test/session_summary_calendar_test.dart`) for S-001,
   S-002, S-004. Confirm tests fail against the current code.
2. Add the `openedFromCalendar` constructor parameter and the
   `DateTime _viewMonth` derived from `currentSession.startedAtMs`.
3. Wire the three entry-point sites to pass the new flag.
4. Implement the branched `_openCalendarScreen()` and
   `_discardSession()`.
5. Re-run the failing tests; confirm they pass.
6. Run `flutter analyze` and the full test suite; fix any regressions.
7. Update `docs/navigation_and_screens.md` and
   `docs/calendar_periods.md` to reflect the new flag and behavior.

## Progress

- [x] Plan file written
- [x] Phase 0.5 red tests written (TDD)
- [x] Phase 1 data layer complete (N/A here — no schema changes)
- [x] Phase 2 logic/UI complete
- [x] All new tests green (`flutter test test/calendar_summary_screen_bugs_test.dart` — 5/5 pass)
- [x] All existing related tests still pass — 472/472 in the combined sweep
      (`calendar_summary_screen_bugs_test`, `session_finish_timers_test`,
      `capitalization_defaults_test`, `screen_widget_test`,
      `interaction_flow_test`, `state_test`)
- [x] `flutter analyze` clean for modified files (no new warnings; only
      pre-existing `withOpacity` info-level deprecations remain)
- [x] Docs updated (`navigation_and_screens.md`, `calendar_periods.md`,
      `session_summary.md`)
- [x] Phase 3 code review complete

### Phase 0 Complete ✓

### Phase 1 Complete ✓ (N/A — no schema changes)

### Phase 2 Complete ✓

### Phase 3 Complete ✓
- [ ] Phase 0.5 red tests written (TDD)
- [ ] Phase 1 data layer complete (N/A here — no schema changes)
- [ ] Phase 2 logic/UI complete
- [ ] All tests green (`flutter test`)
- [ ] `flutter analyze` clean
- [ ] Docs updated (`navigation_and_screens.md`, `calendar_periods.md`)
- [ ] Phase 3 code review complete

## Feedback

(empty)
