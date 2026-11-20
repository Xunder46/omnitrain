# Calendar & Periods - Feature Documentation

## Overview

The **Calendar & Periods** feature provides day-level training planning and historical visibility inside a month calendar.

It combines:
1. **Calendar month grid** with per-day session indicators for both planned and completed sessions.
2. **Day session list** with date-aware editing rules and start/summary navigation.
3. **Training periods** (named date ranges) with overlap validation and calendar highlighting.

This feature is intentionally scoped for MVP planning workflows:
- Simple CRUD for planned sessions and periods, plus repeating series of planned sessions.
- Reuse of existing workout execution and summary screens.

---

## Behaviour Rules

### Session Indicators

Each day renders an indicator per session: filled for completed, outlined for planned, coloured by
modality through `ModalityColorUtils`. Indicator count is capped, with the remainder shown as an
overflow count, so a heavy day never overruns its cell.

A planned routine is coloured by the routine's **current** Focus Modality, resolved on each month load (a routine plan stores no modality itself; changing the routine's Focus changes the planned day's colour the next time the calendar loads). A routine with no Focus, or one that no longer exists, stays Free Training coloured. A finished session is coloured by its own recorded modality, not by this rule; a routine session records the routine's Focus when it starts, and plan 122's one-time back-fill gave past routine sessions the routine's Focus as it was on that update (a routine with no Focus, or one since deleted, stays Free Training) (tests S-12203, S-12207). In the day list the card's second line reads `<Focus> · Planned` for a routine with a Focus and just `Planned` otherwise (tests S-12401, S-12405, S-12411 in `test/planned_routine_calendar_modality_test.dart`).

### Monthly Stats Strip

A strip below the grid reports four figures for the **displayed month**: completed session count,
total training time, the streak slot, and a per-modality breakdown. The streak slot's label comes
from `CalendarState.isActiveStreak` (`lib/state/calendar/calendar_state.dart`): it reads STREAK
in the current month when the streak is live (a session today or yesterday), otherwise BEST RUN (the longest
consecutive-day run within the displayed month's data). A multi-day streak renders with a flame
prefix. Values render as an em dash rather than a zero
when the month has no data, and the strip stays blank while the month is loading rather than
flashing placeholder values. A live streak shows even before the month's first session. Verified
by `test/calendar_streak_state_test.dart` (groups `S-17403 to S-17405 a live streak, a lapsed
one, none`, `S-17406 a live streak before the first session of the month`, `S-17401 two sessions
on one day count as one day`, `S-17402 the streak across a clock change`) and
`test/calendar_streak_screen_test.dart` (group `S-17406 and S-17407 the Calendar strip`).

### Day Routing

Routing behavior is date-sensitive:
- **Past day + exactly 1 entry**:
  - If real completed `TrainingSession` -> `SessionSummaryScreen`
  - Otherwise -> `DaySessionListScreen`
- **Past day + multiple entries** -> `DaySessionListScreen`
- **Today/Future** -> `DaySessionListScreen`

### Day Session List

`DaySessionListScreen` groups entries into Completed first, then Planned, then In Progress.
The three group labels are shared `OmniCardHeader`s (`COMPLETED`, `PLANNED`,
`IN PROGRESS`), not screen-local header widgets. Verified by
`test/ui_standards_widget_test.dart` (group `Mock S-2605b DaySessionListScreen
headers`: `a completed, a planned and an open session give three uppercase
OmniCardHeaders`, `no header renders when the day is empty`).

An empty day is the shared empty state (`OmniEmptyState`): a past day shows
`No sessions on this day.`; a today or future day shows `No sessions planned
yet.` with hint `Add one with the button below.` Verified by
`test/screen_widget_test.dart` (group `DaySessionListScreen`: `empty day
renders the shared OmniEmptyState (S-2802)`).

In the planned-session form, `Add Session` stays off in Routine mode until a routine is chosen, so a plan
never saves as Free Training by accident (plan 262, `test/add_session_needs_routine_test.dart`).

**Past days are read-only, except deleting a missed plan.** Today and future days allow adding, editing and deleting a planned session, and today also allows starting a
planned session; a past day keeps its missed plans visible and lets you delete one (the bin, with the usual confirmation; plan 272, `test/day_planned_start_button_test.dart` `S-27201`), but not edit, move, mark done or start it. Tapping a completed entry opens its summary;
tapping a planned entry opens its edit sheet; the play button on a planned entry of today starts the workout via the routine build flow or the free/modality flow
depending on whether it is routine-linked.

When a workout is saved from the summary, the originating `PlannedSession` is marked completed and
linked via `linkedSessionId`. A routine workout started anywhere else (the Routines list, Home) completes the unstarted plan for the same routine on the day it started when it is finished (`completePlanFor`: the first created when there are several; free-training plans are not matched). Verified by `test/plan_completes_on_routine_finish_test.dart` (`S-25101` to `S-25111`).

**Effort tint.** A completed session row's left border carries its session effort rating on the
theme's one-color intensity ramp (`feelingColor(rating, themeColors)`), so a week reads as an
intensity map; the ramp means "more", never good/bad. Unrated sessions keep the standard border.
Ratings recorded before the effort rating replaced the feeling survey are shown the same way (see
[Session Summary](session_summary.md)). Verified by `test/screen_widget_test.dart` (`effort tint:
ratings 1, 3 and 5 on one day draw ramp steps 1, 3 and 5, each visibly different`, `completed
session cards show time, duration, and feeling border`, `completed session cards without a feeling
keep the standard border`); a rating changed on a calendar-opened summary re-tints the row on
return (`test/session_summary_effort_row_test.dart`, `S-5: day list → …`).

#### Historical-session summary behavior

Opening a finished session while a workout is running does not end that workout: the running workout is put back when the summary closes (plan 229, `test/past_session_keeps_running_workout_test.dart`, `test/past_session_keeps_running_workout_screen_test.dart`).

When a `SessionSummaryScreen` is opened from the calendar flow (either
from the day-list row tap on a completed entry, or from a single-entry
past-day cell on the month grid), the screen is constructed with
`openedFromCalendar: true` and the originating `CalendarState`. This
unlocks four pieces of historical-aware behavior:

1. The summary shows no calendar grid; the summary screen instead lists each
   exercise with the work logged in it (S-24514 in
   `test/summary_exercise_list_screen_test.dart`; see
   [Session Summary](session_summary.md)).
2. The summary has no "Open Calendar" button; the system Back returns
   to the day list (and a subsequent back to the calendar).
3. The overflow-menu "Discard" action permanently deletes the
   historical session from the repository and pops back to the
   originating day list (calendar state is refreshed so the deleted
   indicator disappears from the grid). The confirmation dialog copy
   reflects the destructive + "return to previous screen" semantics.
4. The automatic post-workout effort-rating prompt is never shown (the
   rating can still be added or changed from the EFFORT row, and a
   change refreshes the originating calendar). Verified by
   `test/session_summary_effort_row_test.dart` (`S-4/S-5: Historical
   session — add and change rating (opened from calendar)`, `S-5: day
   list → …`).

### Repeating planned sessions

A plan repeats as **one row per date**:
`CalendarState.createRecurringPlannedSessions` writes one normal planned
session per date the rule yields, and no date is created after one year from
the planned day. Verified by `test/recurring_planned_sessions_state_test.dart`
(group `Mock: recurring planned-session series state` ·
`S-27711 createRecurringPlannedSessions writes 4 rows with the rule text and
reloads the month once`) and `test/recurrence_rule_test.dart` (group
`RecurrenceRule` · `S-27707 the one-year cap beats a large count`, where a
daily rule from 2026-11-19 yields 366 dates ending 2027-11-19).

The rule lives in `lib/core/utils/recurrence_rule.dart`
(`RecurrenceRule`, `RecurrenceUnit`, `RecurrenceEnd`). `recurrenceRule` holds
the JSON text, and it is the same on every row of a series, even a series of
one (`test/recurrence_rule_test.dart` · `S-27710 encode/tryParse round trip is
lossless and forgeries are null`;
`test/recurring_planned_sessions_state_test.dart` ·
`S-27712 a rule that yields one date creates one row that still carries the
rule text`). Week intervals are Monday-based
(`test/recurrence_rule_test.dart` · `S-27704 weekly every 2 Thu and Mon skips
week 1 and the pre-first Monday`); a month step keeps the planned day clamped
to the month's last day (`S-27705 monthly from the 31st clamps each step from
the first date`); dates stay local midnights across clock-change days
(`S-27709 dates keep local midnight across clock-change days`).

The planned-session sheet (today or a future day) has a `Repeat` switch. With
it on, the sheet reveals the `Every` interval and unit row (`Days`, `Weeks`,
`Months`), weekday chips only for `Weeks` — the planned day's chip is ticked
and cannot be un-ticked — and the `Ends` toggle between `After` a session
count and `On date`, plus a one-line summary that follows the settings
(`test/recurring_planned_sessions_sheet_test.dart`, groups
`S-27717: sheet, Repeat off` ·
`S-27717: Repeat off hides the settings and stores one plain row`;
`S-27718: sheet, Repeat on` ·
`S-27718: the settings rows appear, chips follow the unit, the Ends toggle is
one-of`; `S-27719: the summary line follows the settings` ·
`S-27719: the summary text changes with the interval, the count and the end
mode`). The interval choices and the `After` session-count bounds live in the
sheet's form state (`lib/features/calendar/day_session_list_screen.dart`).
A fresh ON starts at `Every 1 Weeks` with `After` at its default count
(`test/recurring_planned_sessions_sheet_test.dart` ·
`S-27726: Every-3-days then off stores one plain row; ON again shows the
defaults`, which reads the dropdowns and the count field of a fresh ON). The
`On date` picker runs from the day after the planned day to one year after it,
and `Add Session` is off while no end date is chosen
(`S-27721: the picker runs from the planned day + 1 to one year on, and a
picked day enables Add Session`). Turning Repeat off drops the settings: the
sheet stores one plain row with no rule text, and turning it on again in the
same sheet shows the clean defaults
(`S-27726: Every-3-days then off stores one plain row; ON again shows the
defaults`; `S-27726b: stale Every-3-Months/extra-weekday/On-date settings are
dropped in the SAME sheet when the switch goes OFF then ON`). The sheet
scrolls to `Add Session` above the keyboard inset on a 390x844 surface
(`S-27720: no overflow with the keyboard up and a scroll reaches
Add Session`).

Editing or deleting a row of a series asks `Just this one` /
`This and all after it` / `Cancel` through the shared three-choice dialog
(`ConfirmationDialog.showThreeChoice`, keys `day-session-series-*`;
`test/confirmation_dialog_three_choice_test.dart` ·
`P3a: the three actions render in the order cancel, first, second`,
`P3a: the cancel action returns ThreeChoice.cancel`,
`P3a: the first action ("Just this one") returns ThreeChoice.first`,
`P3a: the second action ("This and all after it") returns
ThreeChoice.second`). `Just this one` touches only that row's day;
`This and all after it` reaches every row from it on, including the first;
`Cancel` writes nothing (`test/recurring_planned_sessions_day_list_test.dart`,
groups `S-27722: delete on a series row; a non-series row` ·
`S-27722: "Just this one" removes only the tapped day's row; three rows of
the series remain`, `S-27723: edit then Save Changes on a series row; a
non-series row` · `S-27723: Cancel writes nothing`;
`test/recurring_planned_sessions_state_test.dart` ·
`S-27729 the series scope includes the first row itself`). Completed rows and
past days are never changed by a series edit or delete, except that the row
you delete is removed even when it is a missed plan on a past day
(`test/recurring_planned_sessions_state_test.dart` ·
`S-27713 deleteSeriesFrom keeps the completed row, the earlier row and the
past-day row`, `S-27714 updateSeriesFrom copies title and modality to rows
2..4 only, untouched fields stay put`,
`S-27730 deleting a missed plan from a series removes it and the later
upcoming rows, not past rows after it`). A row outside any series is handled
alone, and a non-series row saves with no dialog
(`test/recurring_planned_sessions_state_test.dart` ·
`S-27711b a row outside any series is handled alone`;
`test/recurring_planned_sessions_day_list_test.dart` ·
`S-27723: a non-series row saves with NO dialog`). Turning Repeat on for an
existing plain row keeps that row as the first of the series and creates only
the later dates (`test/recurring_planned_sessions_sheet_test.dart` ·
`S-27724: the kept row is the first of the series and only the later dates
are created`); a new plan with Repeat on creates one row per date sharing one
series id (`S-27718b: daily After 3 titled Tmp creates three rows sharing one
rule`). The edit sheet of a series row shows a read-only `Repeats …` line
instead of the switch and its settings
(`S-27725: a series row shows the read-only line and no switch`). One day can
hold an ordinary plan and a series row side by side
(`test/recurring_planned_sessions_day_list_test.dart`, group
`S-27728: one day holding an ordinary plan and a series row` ·
`S-27728: both rows render and the day counts two entries`). Completing one
occurrence keeps its rule text and leaves the others planned, and deleting a
routine still cascade-deletes every occurrence of its series
(`test/recurring_planned_sessions_state_test.dart` ·
`S-27715 completing one occurrence keeps its rule text and leaves the others
planned`, `S-27716 the routine delete cascade removes every occurrence and
leaves an unrelated row`).

### Periods

The Training periods list opens from the Calendar header's Training periods
action (label `Training periods`, key `calendar_training_periods_button`). It
goes to another place, so it is not a header "+"; how it looks is in
[Design System](design_system.md), "Header actions". Returning from the list
refreshes the calendar. Verified by `test/header_standardization_test.dart`
(group `OmniBackHeader presence – CalendarScreen` · `S-9155`, `S-9156`,
"S-9156: returning from the Training periods list refreshes the calendar").

Period capabilities:
- List name + date range
- Create and edit
- Delete
- Optional modality focus tags
- Optional notes
- Curated color palette (stored as `colorHex`)

Calendar highlights days covered by periods with a semi-transparent background.

Changing month keeps the previous month's grid on screen until the new one has loaded (no spinner
flash after the first load). Swiping the grid left shows the next month and right the previous one;
a `Today` icon in the header (key `calendar_today_button`) appears while another month is showing and
returns to the current one; and a screen reader hears each day as its number and session count, such as
`16, 2 sessions` (plan 261, `test/calendar_navigation_polish_test.dart`).

The period you are in today is named in a small line under the month title (key
`calendar_period_name`) while the month on screen overlaps it; with no such period
there is no line. The list screen's title is also `Training periods`, and the period
form's Start and End dates read like `Nov 16` (with the year, `Nov 16, 2025`, when it
is not this year), never `16/11/2025` (plan 260, `test/period_polish_test.dart`).

An empty periods list is the shared empty state (`OmniEmptyState`, title
`No training periods yet.`, hint `Add one with the button below.`). Verified
by `test/screen_widget_test.dart` (group `PeriodListScreen`: `empty list
renders the shared OmniEmptyState (S-2802)`).

Create Period — in new and edit mode alike — warns about unsaved changes:
leaving the form with edits open a two-button dialog (keep editing / discard),
so typed values cannot be lost silently. Verified by
`test/screen_widget_test.dart` (group `CreatePeriodScreen unsaved changes
guard (S-2901)`: `typed name + system back shows the Unsaved changes dialog`,
`Discard pops and persists nothing`, `edit mode: an untouched stored period pops with no dialog`,
`edit mode: Discard leaves the stored period unchanged`).

---

## Data Model

### PlannedSession

**Model**: `PlannedSession` in `lib/data/models/models.dart`

Key fields:
- `id`
- `scheduledDateMs` (start-of-day local in memory; stored as that wall-clock time read as UTC, so a time-zone change keeps the day)
- `modality` (nullable)
- `routineTemplateId` (nullable)
- `isCompleted`
- `linkedSessionId` (nullable)
- `recurrenceRule` (nullable JSON text; the series rule)

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
  (`startDateMs` and `endDateMs` are stored the same way: as the wall-clock time read as UTC, the end at 23:59:59.999, so a time-zone change keeps the dates; plan 236, `test/plans_and_periods_survive_zone_change_test.dart`)
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
- Resolves each planned routine's Focus Modality from its template (one `getTemplates()` read per load, none when no routine is planned)
- Groups entries by day for month grid
- Exposes period list for highlights
- Handles planned session CRUD and the recurring-series actions
- Handles `completePlannedSession(plannedSessionId, linkedSessionId)`
- Handles `completePlanFor(session)`: called by `WorkoutState` when Finish stores a session's end (`onSessionEnded`), it links the first-created unstarted plan for the session's routine on the day the session started, if any
- Computes monthly stats and current streak from loaded data

#### Monthly Stats Getters (derived from `_entriesByDay`)

| Getter | Type | Description |
|--------|------|-------------|
| `completedSessionCount` | `int` | Count of entries where `isCompleted == true` |
| `totalTrainingMs` | `int` | Sum of `endedAtMs − startedAtMs` for completed entries with a real session |
| `modalityBreakdown` | `Map<String?, int>` | Completed session count grouped by modality key (null = Free Training) |
| `streakDays` | `int` | The live streak, else the displayed month's longest run (see below) |

#### Streak Calculation (`_computeStreak`)

Called concurrently with `_loadPeriods()` at the end of each `_loadMonth()`:

1. Fetches every completed session up to today via `repository.getSessionsByDateRange` (no lookback limit, plan 273).
2. Builds a `Set<int>` of local start-of-day timestamps, so two sessions on one day count once.
3. Anchors on **today** if today has a session, else on **yesterday** if yesterday has one.
4. Walks backwards one calendar day at a time, never 24 h, so a clock change cannot hide a day.
5. Stores the result in `_streakDays` (0 on error; with no anchor day, the displayed month's longest run).

> The streak is not capped: it runs back as far as the consecutive days go (`test/calendar_streak_state_test.dart` `S-27203`).

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
3. Day list is grouped: Completed first, Planned second, In Progress third.
4. Past days are read-only in the day list, apart from deleting a missed plan.
5. Planned-session play button (today only) starts workout using correct modality/routine path; the row tap opens edit.
6. Completed-session tap opens summary.
7. Period overlap is rejected before save.
8. Period colors are curated presets and used as calendar highlights.
9. Planned-session add/edit form uses the same shared mode selector and field-swap behavior.

---

## Invariants

**A planned session repeats only through the `recurrenceRule` JSON text it carries.** Every row of a series stores the same rule text on `PlannedSession` (`lib/data/models/models.dart`), and only `RecurrenceRule` (`lib/core/utils/recurrence_rule.dart`) parses it — no other code branches on the field. Verified by `test/recurrence_rule_test.dart` (group `RecurrenceRule` · `S-27710 encode/tryParse round trip is lossless and forgeries are null`) and `test/recurring_planned_sessions_state_test.dart` (group `Mock: recurring planned-session series state` · `S-27711 createRecurringPlannedSessions writes 4 rows with the rule text and reloads the month once`).

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
