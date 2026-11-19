# Plan 248 — A planned session starts from a Start button on today's plans only; tapping the row opens edit

Review item 10 (owner direction: "Tapping a plan starts a workout at once, future dates included. A Start button similar to the Routines list on today's plans only; tapping the row opens edit").
Phone only. No wire, watch, storage or schema change.

## Goal and acceptance

Today every planned row on the day list (`DaySessionListScreen`) starts a workout the moment the row is tapped, on today and on future dates. After this change:

- A planned row of TODAY shows a play button (the same glyph as the Routines list) before the bin. Only that button starts the workout. Starting works exactly as before: a running workout gets the "Start New Session?" prompt first, an empty routine still keeps the running workout and shows the error.
- Tapping the planned row itself (today or a future date) opens the edit sheet (`Edit Session`). It starts nothing. The pencil button is gone: the row tap is the way to edit, as on the Routines list (a three-button cluster squeezed a long title to 46 dp at 320 dp wide; measured).
- A planned row on a FUTURE date shows the bin only (no play button): a future plan cannot be started from here.
- A PAST day is unchanged: read-only, no play, no bin, the row tap does nothing.
- Completed and in-progress rows are unchanged.

Acceptance: S-24801..S-24806 green, the "fails without" ones red at the base commit; the five existing tests that start a plan by tapping its row now tap the play button and stay green; `flutter analyze` not above 178 issues, 0 errors; no new red in the full suite against the base failing set (`.work/windows-base-failing-tests.txt`); Docs delta applied.

## What the user sees

- Open today in the calendar: each planned row ends with a play arrow and a bin. Tap the arrow: the workout starts. Tap the row name: the edit sheet opens.
- Open a day next week: planned rows end with the bin; tapping a row opens the edit sheet; nothing starts.
- To SEE it: plan a session on today and on tomorrow, open each day from the calendar.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-24801 | `_SessionRow` gets an optional `onStart`. When set it renders a play `IconButton` (tooltip `Start session`, key `day-session-start`, `Icons.play_arrow`, size 24, colour `OmniTheme.colors.primary`) as the FIRST child of the trailing cluster, before the bin. The pencil button and the `onEdit` parameter are removed (the row tap opens edit, D-24803); the cluster is built when `onStart` or `onDelete` is set. | `day_session_list_screen.dart:503-523`; `my_routines_screen.dart:430-444` (the Routines play button) |
| D-24802 | In the planned loop the row passes `onStart` only when `OmniDateUtils.isToday(widget.date)` (and the row is editable, which a today row always is). A future date passes `onStart: null`; a past date passes nothing, as now. | `day_session_list_screen.dart:169-190`; `date_utils.dart:95` |
| D-24803 | The planned row's `onTap` becomes `_editPlanned` (same as the pencil) when editable; the pencil button is removed; the start logic `_tapPlanned` is unchanged and renamed `_startPlanned`, called only from `onStart`. Completed-row tap (summary) is unchanged. | `day_session_list_screen.dart:176-178,253-340` |
| D-24804 | Layout: the trailing cluster is at most two 48 dp slots (play, bin), the same width as the old pencil + bin cluster. Probe (lead, 700 dp tall, a 58-character title): with three buttons the title column was 46 dp wide at 320 dp (and 116 dp at 390 dp), which is why the pencil goes; two buttons leave the old width. | lead probe `.work/item10/probe.txt` |

## Scenarios

Fixtures. Clock: the real clock (`OmniDateUtils.isToday` reads `DateTime.now()`), so build the dates from `DateTime.now()`: `today = DateTime.now()`, `tomorrow = DateTime(y, m, d + 1)`, `yesterday = DateTime(y, m, d - 1)`. Mock repository, `CalendarState`, `WorkoutState`, `RoutineState`, as in `test/planned_routine_calendar_modality_test.dart` (copy its `_pumpDay`-style setup, its seeding of a routine plan `Plan Today 124` and the free plan). One planned session per fixture date, free modality (no routine) unless stated, title `Plan A`. `tester.binding.setSurfaceSize(const Size(600, 1200))`.

Level A (new `test/day_planned_start_button_test.dart`, `testWidgets`, Mock repository only):

| ID | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-24801 | plan on today, no running workout; pump the day | `find.byTooltip('Start session')` finds one widget, and it sits left of the `Delete session` bin (dx smaller) and no `Edit session` tooltip exists; tap it: `workoutState.hasActiveSession` true and a `WorkoutSessionScreen` is on screen | no button exists |
| S-24802 | same fixture; tap the row text `Plan A` | the sheet title `Edit Session` shows; `workoutState.hasActiveSession` false; `repo` holds no active session; no `WorkoutSessionScreen` | tapping the row starts the workout |
| S-24803 | plan on tomorrow; pump the day for tomorrow | no `Start session` tooltip; `Delete session` found once, `Edit session` none; tap the row text: `Edit Session` sheet, `hasActiveSession` false | a future row starts on tap |
| S-24804 | plan on yesterday; pump yesterday | no `Start session`, no `Delete session`; tap the row text: nothing happens (`hasActiveSession` false, no sheet) | guards the unchanged past-day rule against a build that shows Start on every planned row |
| S-24805 | plan on today; a running workout exists; tap `Start session` | the `Start New Session?` prompt shows (`day-session-new-start-confirm` found); `Cancel` keeps the running workout; row tap on the same fixture opens `Edit Session` and shows NO prompt | the prompt used to come from the row tap |
| S-24806 | plan on today; tap the bin | the `Delete` confirmation opens (`day-session-delete-confirm`); cancel it: the row is still there, no workout started (`hasActiveSession` false) and the play button is still there; the bin does not open the edit sheet | guards the two buttons against overlapping hit areas |

Existing tests changed (tap the play button instead of the row): `test/empty_routine_cannot_cost_the_running_workout_test.dart` (S-24002, S-24004: `tester.tap(find.text('Plan Empty 240'))` and `find.text('Plan Today 230')`), `test/start_new_really_discards_screen_test.dart` (S-23004, S-23005: `find.text('Plan Today 230')`), `test/planned_routine_calendar_modality_test.dart` (`find.text('Plan Today 124')`). The replacement is `tester.tap(find.byTooltip('Start session'))` (one planned row in each fixture).

Found by the full run and the review, fixed in the same change: `test/routine_session_modality_test.dart` S-12203 (tap `Start session` instead of the row text) and `test/screen_widget_test.dart` "edit planned session opens shared form" (tap the row text `Planned Test`: the pencil it tapped is gone).

## Input-reality checklist

1. Writers: planned sessions are written by `CalendarState.createPlannedSession` / `updatePlannedSession` (the form on this screen) and by `completePlannedSession` when a workout saved from this screen ends. Nothing in this change writes.
2. Lifecycle: a planned row whose workout was saved becomes completed and leaves the PLANNED group (existing); a deleted routine leaves the row as `Custom Routine`, which still starts a free session (existing).
3. Settings: none read.
4. Time: today is decided when the row list builds; a screen left open across midnight keeps the play button on a day that is now past until the next rebuild, and tapping it starts the session as the row tap used to (accepted).
5. Cost: none (no new read).
6. Words: new tooltip `Start session`; the row tap now opens `Edit Session` (existing sheet title).
7. Competition: two buttons in one trailing cluster (S-24806); the title wraps first on a narrow screen (D-24804).

## Phases

1. **P1 builder-app**, scope `lib/features/calendar/day_session_list_screen.dart`, `test/empty_routine_cannot_cost_the_running_workout_test.dart`, `test/start_new_really_discards_screen_test.dart`, `test/planned_routine_calendar_modality_test.dart`: D-24801..D-24803 (exact code in the brief) and the three existing-test taps. Runs those three test files. No full suite.
2. **P2 builder-app** (after P1), scope `test/day_planned_start_button_test.dart` (new): S-24801..S-24806.
3. **P3 lead**: layout probe (D-24804), readers set, full suite against the base failing set, analyze, mutation pass, `crew-docs-keeper`, reviewer.

## Readers

Tests that build `DaySessionListScreen` or tap a planned row: `screen_widget_test` (group `DaySessionListScreen`), `ui_standards_widget_test` (group `Mock S-2605b DaySessionListScreen headers`), `header_standardization_test`, `past_session_keeps_running_workout_screen_test`, `watch_session_summary_integration_test`, `routine_session_modality_test`, `session_summary_effort_row_test`, `calendar_*` tests, `screen_overflow_contract_test`, `ui_standards_contract_test`, `docs_indexing_contract_test`.

## Mutation list (lead)

(a) Start shown on a future date (S-24803); (b) Start shown on a past day (S-24804); (c) row tap starts the workout again (S-24802); (d) row tap does nothing on today (S-24802); (e) Start button calls the edit sheet (S-24801); (f) bin calls the start path (S-24806); (g) Start button removed (S-24801); (h) past-day row tap opens edit (S-24804).

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| `docs/calendar_periods.md` | MODIFIED | Today and future days allow adding, editing, deleting, and starting a | Today and future days allow adding, editing and deleting a planned session, and today also allows starting a | S-24801, S-24803 |
| `docs/calendar_periods.md` | MODIFIED | tapping a planned entry starts the workout via the routine build flow or the free/modality flow | tapping a planned entry opens its edit sheet; the play button on a planned entry of today starts the workout via the routine build flow or the free/modality flow | S-24801, S-24802 |
| `docs/calendar_periods.md` | MODIFIED | 5. Planned-session tap starts workout using correct modality/routine path. | 5. Planned-session play button (today only) starts workout using correct modality/routine path; the row tap opens edit. | S-24801, S-24802 |
| `docs/navigation_and_screens.md` | MODIFIED | and `WorkoutSessionScreen` to resume/continue one. | and `WorkoutSessionScreen` to resume/continue one or, from the play button on a planned row of today, to start it. | S-24801 |

Stale-term sweep (lead): `grep -rIn -i "tapping a planned\|Planned-session tap\|planned entry starts" docs` outside plans, history, releases: the three `calendar_periods.md` hits are rows 2 and 3 above; nothing else.

## Open items

1. (owner) A plan on a future date cannot be started from the calendar; it starts only once its day is today.
2. (owner) A past plan still cannot be started, moved or deleted (item 9, deferred).
4. (owner) The pencil button is gone from planned rows (tap the row to edit, as on the Routines list). Bringing it back costs title width on a narrow phone.
3. A screen left open across midnight keeps yesterday's play button until it rebuilds (accepted, D-24802).
