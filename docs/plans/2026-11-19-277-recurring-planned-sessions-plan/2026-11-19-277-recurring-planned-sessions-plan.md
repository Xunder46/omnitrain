# Plan 277 — Recurring planned sessions

Owner list item 1 (2026-11-19): "Add a Recurring checkbox toggle which expands the sheet and reveals the settings for making a session repeat conditionally. Some settings show or hide depending on selections."
Phone only. No wire change, no storage-schema change (the unused `recurrenceRule` text slot is used), no watch code.
Base commit: see `.work/2026-11-19-277-recurring/base.txt` (`8ec6f4216f0c4e31d65324e8d6317536fe73972e`). Analyze baseline: 176 issues, 0 errors.

## Goal and acceptance

In the calendar's New Planned Session sheet (today or a future day) a `Repeat` switch appears. Off: the sheet is exactly as today. On: the sheet grows and shows the repeat settings; a settings row shows or hides by what is chosen above it:

- `Every` [N] [days | weeks | months] (N from 1 to 12, default 1, default unit weeks).
- Only when the unit is weeks: weekday chips Mon..Sun. The weekday of the day being planned is ticked and cannot be un-ticked (the planned day is always the first session); the others are optional.
- `Ends`: `After` [N times] or `On date`. Default `After 8 times`. `After` shows a count field (2 to 366); `On date` shows a date picker row (a date after the planned day, at most one year after it). No `Never`.
- A one-line summary under the settings in plain words, for example `Every 2 weeks on Mon, Thu · 8 sessions · until 14 Jan`, and the number of sessions that will be created.

`Add Session` then creates one normal planned session on each date (same modality or routine, title and note on all). Nothing is created beyond one year after the planned day: the last date is never later than the same calendar date one year on (daily from 2026-11-19 gives at most 366 sessions).

Editing or deleting a session that belongs to a series asks `Just this one` or `This and all after it` (completed sessions and past days are never changed). Editing a session that is not in a series also shows the `Repeat` switch; turning it on keeps that session as the first of a new series and creates the later ones.

Acceptance: S-27701..S-27729 green, each guard red without the change; `flutter analyze` at most 176 issues, 0 errors; `test/ui_standards_contract_test.dart` and `test/docs_indexing_contract_test.dart` green; no new red in the full suite against `.work/2026-11-19-277-recurring/base.txt`'s failing set; Docs delta applied.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-27701 | A series is stored as ordinary `PlannedSession` rows, one per date, all carrying the same `recurrenceRule` string. No new field, repository method, box or SQL column. Completing, skipping (a past day stays as a missed plan), deleting, the routine-delete cascade, the watch `planned_down` window and Export all keep working unchanged. | `lib/data/models/models.dart` `PlannedSession.recurrenceRule`, `lib/state/calendar/calendar_state.dart` `completePlannedSession`/`completePlanFor` (both already copy `recurrenceRule`) |
| D-27702 | `recurrenceRule` holds a small JSON text: `{"v":1,"series":"<uuid>","unit":"day\|week\|month","every":N,"weekdays":[1..7],"end":"count\|date","count":N,"until":"YYYY-MM-DD"}`. Parsing is forgiving: a null, empty or unreadable value means "not in a series". | new `lib/core/utils/recurrence_rule.dart` `RecurrenceRule` |
| D-27703 | The date list comes from one pure function `RecurrenceRule.dates(DateTime first)`: returns `DateTime(y, m, d)` local midnights, first element is `first`, stops at the end rule or at `DateTime(first.year + 1, first.month, first.day)` inclusive, whichever is earlier. Weeks are Monday-based: week 0 is the week of `first`; a date counts when its week number is a multiple of `every` and its weekday is ticked. Months: the same day of month as `first`, clamped to the month's last day, each computed from `first` (never from the previous result). Dates are built with `DateTime(y, m, d + k)`, never `add(Duration(days: k))` (a clock-change day would drift). | `lib/core/utils/date_utils.dart` `OmniDateUtils.startOfDayMs`; plan 235/236 wall-clock storage in `PlannedSession.toMap` |
| D-27704 | `CalendarState.createRecurringPlannedSessions({first, rule, modality, routineTemplateId, title, note})` writes the rows one by one through `repository.createPlannedSession` and reloads the month once at the end. `updatePlannedSession`/`deletePlannedSession` stay as they are for single rows. | `calendar_state.dart` `createPlannedSession` (one reload per create today) |
| D-27705 | New `CalendarState.updateSeriesFrom(PlannedSession edited)` and `deleteSeriesFrom(PlannedSession from)`: apply to every row with the same series id, `scheduledDateMs >= from.scheduledDateMs`, `isCompleted == false`, `linkedSessionId == null` and a day that is today or later. They read `repository.getPlannedSessions()` once. Edits copy modality, routine, title and note only; dates and `recurrenceRule` are untouched. | `calendar_state.dart` `completePlannedSession` (reads `getPlannedSessions()` the same way), `OmniDateUtils.isPastDay` |
| D-27706 | Choosing `Just this one` on an edit keeps the row in the series (same `recurrenceRule`). On a delete it removes that row only. | `day_session_list_screen.dart` `_editPlanned`, `_deletePlanned` |
| D-27707 | The series choice is the shared `ConfirmationDialog`; it only has two-choice and unsaved-changes helpers today, so add one shared three-choice helper there (`Just this one` / `This and all after it` / `Cancel`) with the same visual rules, never a screen-local dialog. | `lib/widgets/dialogs/confirmation_dialog.dart` `showTwoChoice`; `docs/design_system.md` "Shared pieces and rules per job" |
| D-27708 | The `Repeat` switch and its settings live in `_PlannedSessionForm` (same file) and return one extra field `RecurrenceRule? rule` in `_PlannedSessionFormResult`. The sheet scrolls (`SingleChildScrollView`) so the expanded form fits a 390x844 phone with the keyboard up. Turning `Repeat` off hides the settings and drops them. | `day_session_list_screen.dart` `_PlannedSessionForm`, `_PlannedSessionFormResult` |
| D-27709 | When editing a session that already is in a series, the sheet shows a read-only line with the summary (`Repeats every 2 weeks on Mon, Thu until 14 Jan`) instead of the switch. Changing the pattern means deleting the following sessions and adding a new series. | owner-confirm default |
| D-27710 | No change to the watch, the watch wire, `scripts/sqlite_schema.sql` structure or Hive boxes. Update only the comment texts that say recurrence is reserved/not implemented. | `models.dart` doc of `PlannedSession`, `scripts/sqlite_schema.sql` `recurrence_rule` comment, `test/db_seed_test.dart` still green |
| D-27711 | Editing a non-series row with Repeat on keeps that row as the first of the series: `_editPlanned` writes the updated row in place via `updatePlannedSession` (rule text stamped) and then creates only the LATER dates, so `createRecurringPlannedSessions` takes an optional `skipFirst` (default `false`) and skips the first date when set. Without it the planned day would get two rows. | S-27724; extends D-27704 |
| D-27712 | Weekday numbers in the rule are Dart weekdays (1=Mon .. 7=Sun, the numbers `DateTime.weekday` gives, verified `lib/core/utils/date_utils.dart:126`). The sheet's chips use the Monday-based label list, the same shape as `calendar_screen.dart` `_mondayLabels`. The Settings week-start never enters a stored rule (Input-reality 3). | `calendar_screen.dart` `_mondayLabels`; Input-reality 3 |

## Scenarios (converted to one table; ids and wording kept, fails-without added)

Fixtures are local dates; first date Thu 2026-11-19 unless said. All derived with a throwaway script (arithmetic re-derived by the architect by hand: 2026-11-19 is a Thursday; 2027 is not a leap year).

| S-n | fixture | expect | fails without |
|---|---|---|---|
| S-27701 | Daily, every 1, `After 3`, from 2026-11-19 | 2026-11-19, 11-20, 11-21 | no function — without `RecurrenceRule.dates` nothing computes repeat dates. |
| S-27702 | Weekly, every 1, ticked Thu (locked) and Mon, `After 4`, from 2026-11-19 | 11-19 Thu, 11-23 Mon, 11-26 Thu, 11-30 Mon | no rule: the weekday ticks cannot become dates. |
| S-27703 | Weekly, every 2, Thu, `After 3`, from 2026-11-19 | 11-19, 12-03, 12-17 | the every-N interval filter does not exist. |
| S-27704 | Weekly, every 2, Thu and Mon, from 2026-11-19 | 11-19, 11-30, 12-03 (the Monday 11-16 before the first date is not created; week 1, 11-23..11-29, is skipped) | without the Monday-based week-0 anchor the pre-first Monday and week 1 would be included. |
| S-27705 | Monthly from 2027-01-31, `After 4` | 01-31, 02-28, 03-31, 04-30 (each from the 31st, not from the previous clamp) | without clamping each step from `first` the chain drifts (02-28 → 03-28 → 04-28). |
| S-27706 | `On date` 2026-11-21 from 11-19 daily | 3 dates; an `until` before the first date still gives the first date alone | without the until bound and the guaranteed first element the first row is dropped. |
| S-27707 | One-year cap: daily from 2026-11-19, `After 500`; monthly from 2026-11-19, `After 24` | exactly 366 dates, last 2027-11-19; 13 dates (2027-11-19 included) | without the cap 500 rows would be written, past one year. |
| S-27708 | The first date's weekday not in the caller's list (weekly rule, first Thu, ticks Mon only) | the first date is always included (the rule adds it) | without the forced first element the planned day itself would get no row. |
| S-27709 | Dates across the clock-change days 2026-10-25 and 2027-03-28 | exact local midnights, consecutive days (guard on the construction, see D-27703; if the test zone cannot be set, a source-text guard on `RecurrenceRule.dates` asserting `DateTime(` with a day offset and no `Duration(days`) | `Duration(days:)` arithmetic drifts an hour per crossing. |
| S-27710 | Rule text round trip: encode then decode; decode null, `''`, `'{'`, `'{"v":2}'` and a map without `series` | encode then decode equals; every unreadable value decodes to "not a series" without throwing | unforgiving parsing would throw on every legacy row (all existing rows are null). |
| S-27711 | `createRecurringPlannedSessions` with S-27702's rule, run on the Mock and Hive harness | 4 rows, same series id, same modality or routine, title and note, `isCompleted false`, `scheduledDateMs` equal to `startOfDayMs` of each date; one `notifyListeners`-driven month reload (count reloads with a listener) | without the state method the sheet has no writer; a per-row reload would fire 4 month reads instead of 1. |
| S-27712 | A rule that yields one date (`until` equal to the first date) | one row created that still carries the rule text (a series of one) | without carrying the text the row silently leaves the series. |
| S-27713 | `deleteSeriesFrom` on the 2nd of 4 rows; row 3 completed (linked session); a 5th row on a past day | rows 2 and 4 removed, row 1 kept, the completed row 3 stays, the past-day row stays | without the completed/past-day filters a series delete would erase history. |
| S-27714 | `updateSeriesFrom` changing the title on the 2nd of 4 rows | rows 2..4 change title only; dates, ids and `recurrenceRule` untouched; a completed row untouched | without the field-copy discipline a rebuild drops the rule text or shifts dates. |
| S-27715 | Completing one occurrence (`completePlannedSession`) | its `recurrenceRule` kept, the others still planned | the copy at `calendar_state.dart:310` must survive; dropping it silently ends the series. |
| S-27716 | Routine delete cascade removes every occurrence (`deletePlannedSessionsByTemplateId`) — fixture: a routine with 3 occurrences | every occurrence removed — unchanged behaviour, guarded | the cascade must not special-case series rows. |
| S-27717 | Sheet, Repeat off | the settings rows are not in the tree and `Add Session` returns `rule == null` | without the off-branch every add would carry a rule. |
| S-27718 | Sheet, Repeat on (planned day is a Thursday) | `Every`, unit and `Ends` rows appear; weekday chips absent for days and months, present for weeks; the Thu chip is ticked and a tap on it does not un-tick; `After` shows the count field, `On date` the date row, never both | no conditional show/hide exists in the sheet today. |
| S-27719 | Sheet summary line and session count change when the unit, interval, weekdays or end change | the numbers of S-27702 (4 sessions) | without the reactive summary the user confirms numbers they cannot see. |
| S-27720 | Sheet at 390x844 with the keyboard inset, Repeat on, `After` focused | no overflow exception (probe measured, not assumed) | the expanded form does not fit without scrolling. |
| S-27721 | `On date` picker offered 2027-11-20 (past one year) and 2026-11-18 (before the planned day) | both refused | without the bound the rule could receive dates beyond the cap or before the series. |
| S-27722 | Day list: delete on a series row; a non-series row | the three-choice dialog: `Just this one` removes one, `This and all after it` removes the tail, `Cancel` nothing; the non-series row still shows today's two-choice dialog (`day-session-delete-confirm`) | without the branch a series delete removes one row and leaves an orphaned tail — or everything, with no choice. |
| S-27723 | Day list: edit then `Save Changes` on a series row; a non-series row | the same dialog applies the chosen scope; the non-series row saves with no dialog | without the branch a one-row edit silently diverges from the tail. |
| S-27724 | Edit a non-series row with Repeat turned on | the row is kept and the later dates are created with the rule; the kept row gets the rule text | without the skip-first path (D-27711) the planned day would be created twice. |
| S-27725 | Edit sheet of a series row | the read-only summary line and no switch | without it the user could change the pattern of one row only (D-27709 forbids). |
| S-27726 | Sheet: Repeat on (`Every 3 days`), then Repeat off, then `Add Session` | one ordinary row, `rule == null`, no later dates | without dropping the settings on off a stale rule would be attached. |
| S-27727 | A series (S-27702's 4 rows) read back through the harness after a simulated time-zone change (the technique of `test/plans_and_periods_survive_zone_change_test.dart`) | the same 4 calendar days, rule text unchanged | the wall-clock key contract (plan 236) must hold for series rows too. |
| S-27728 | A day that already carries an ordinary plan, plus a series row on the same day | both rows render in the day list (and two indicators on the month cell), no conflict rule | competition: several plans on one day must keep working. |
| S-27729 | `updateSeriesFrom`/`deleteSeriesFrom` called with `from` = the first row of a 4-row series | the scope includes row 1 itself (the `>=` comparison) | without the inclusive boundary editing row 1 would change only rows 2..4. |
| S-27730 | A missed plan (past day) of a series, deleted with `This and all after it`, with later past rows and future rows | the pointed-at row and the future rows go; later past rows stay | the past-day filter would also hide the row the user pointed at |
| S-27711b | A row outside any series passed to `updateSeriesFrom`/`deleteSeriesFrom` | only that row changes | a series call on a plain row would touch others |
| S-27718b | Add Session with Repeat on (days, After 3) | three rows sharing one series id | the sheet would not create the series |
| S-27725b | `RecurrenceRule.describe` | states the whole series in words | the read-only line would be wrong |
| S-27726b | Repeat on, changed, off, on again in the same sheet | defaults again | stale settings would leak into the next ON |
| S-27724b | The later-dates write fails after the plan was stamped | `Could not save. Try again.` shows | silent series of one |

Each scenario above states why it fails without the change in the architect's table (every scenario needs a fixture a real writer could produce: rows are produced by `createRecurringPlannedSessions`, never hand-built with an unreadable rule).

## Feature invariants

- `recurrenceRule` text is written only by `createRecurringPlannedSessions` and the Repeat-on edit path, always through `RecurrenceRule.encode` (D-27702, D-27711).
- No reader branches on the rule text except the series actions, the sheet's read-only line and `RecurrenceRule.tryParse` (D-27701, D-27709).
- A series action never touches a completed row, a linked row or a past day (D-27705).
- One series create / edit / delete = at most one month reload (D-27704, D-27705).
- Repeat dates are pure local midnights built with `DateTime(y, m, d + k)`; no `Duration` day arithmetic, no DST dependence (D-27703).
- Nothing is stored beyond one year after the planned day; `count` ≤ 366, `every` ≤ 12 (Goal).

## Existing-functionality impact

| Touched surface | Existing readers (search run this run) | Effect | Guarded by |
|---|---|---|---|
| `PlannedSession.recurrenceRule` gains non-null values | grep `recurrenceRule` and `recurrence_rule` over `lib/` and `test/`: `models.dart` (field, `fromMap`/`toMap`), `calendar_state.dart:310` (`completePlannedSession` copy), `day_session_list_screen.dart:374` (`_editPlanned` copy), `test/plans_and_periods_survive_zone_change_test.dart:143` | every existing copy keeps the text unchanged; nothing else branches | S-27715, S-27727; existing S-23602 stays green |
| Calendar month load and entries | `calendar_screen.dart` `_MonthGrid`/`_SessionIndicators` (via `CalendarState.entriesByDay`), `day_session_list_screen.dart` `_plannedEntries` (via `entriesForDay`) | series rows are ordinary entries; dots and rows behave as today | S-27728; existing suite |
| Watch `planned_down` window | `watch_reference_sync.dart:221` reads `getPlannedSessions()`, filters by date/`linkedSessionId`; the envelope has no rule field | series rows travel as plain rows | D-27710; existing `test/watch_reference_sync_test.dart` |
| Routine delete cascade | `routine_state.dart:281` `deletePlannedSessionsByTemplateId` | removes every occurrence | S-27716 |
| `ConfirmationDialog` file | `test/ui_standards_contract_test.dart` scans it as an allowed `AlertDialog` owner; `showTwoChoice`/`twoChoice` have 22+ call sites across `lib/features` | a new sibling helper; no existing signature changes | S-27722 dialog part; `test/ui_standards_contract_test.dart` |
| `scripts/sqlite_schema.sql` | `test/db_seed_test.dart` reads and executes the file | comment-only edit; execution identical | Done run of `test/db_seed_test.dart` |
| Export | plan 278a copies the rule text as it is | out of this plan's scope | 278a plan |

## Input-reality checklist

1. Writers: `recurrenceRule` is written only by `createRecurringPlannedSessions` and the Repeat-on edit; read by `RecurrenceRule.tryParse`. Existing rows have `null`. The Export (plan 278a) copies the text as it is.
2. Lifecycle: completed occurrences keep the rule and are skipped by series edits and deletes; a past, unstarted occurrence is a missed plan and is never changed by a series action; a deleted occurrence is gone (no tombstone, the series simply has a gap); a routine delete removes all occurrences.
3. Settings: week start (Settings) does not change the series (weeks are Monday-based inside the rule); the weekday chip labels follow the locale used elsewhere in the sheet. Nothing in Settings changes a stored series.
4. Time: planning today is allowed (the first date is today); a clock-change day and month ends are in S-27705/S-27709; Dec to Jan year change is S-27707's monthly case; time zone change while a series exists is covered by the stored wall-clock key (plan 236), guarded by re-running `test/plans_and_periods_survive_zone_change_test.dart` with a series.
5. Cost: up to 366 sequential `createPlannedSession` calls and one month reload (D-27704); the series edit/delete read `getPlannedSessions()` once and write only the changed rows, then one reload. No per-row reload.
6. Words: stale terms to sweep in `docs/`: `recurrence`, `Recurring`, `reserved`, `Simple CRUD for planned sessions` (see Docs delta).
7. Competition: several plans on one day are already allowed; a series can put a second plan on a day that has one (no conflict rule; the day list shows both).

## Phases (serial; all `crew-builder-app`; write scope per phase)

- **P1 rule** (scope `lib/core/utils/recurrence_rule.dart`, `test/recurrence_rule_test.dart`): D-27702, D-27703; S-27701..S-27710.
- **P2 state** (scope `lib/state/calendar/calendar_state.dart`, `lib/data/models/models.dart` (doc comment only), `scripts/sqlite_schema.sql` (comment only), `test/recurring_planned_sessions_state_test.dart`): D-27704..D-27706, D-27710; S-27711..S-27716. Runs under Mock and Hive.
- **P3 dialog + sheet** (scope `lib/widgets/dialogs/confirmation_dialog.dart`, `lib/features/calendar/day_session_list_screen.dart`, `test/recurring_planned_sessions_sheet_test.dart`, `test/confirmation_dialog_three_choice_test.dart`): D-27707..D-27709; S-27717..S-27725. Split into 3a (dialog + series delete/edit wiring, S-27722..S-27725) and 3b (sheet UI, S-27717..S-27721) if the architect counts more than 8 items.
- **P4 docs** (`crew-docs-keeper`): the Docs delta table.

## Expanded phases

The architect counts more than 8 items for P3, so it splits exactly as seeded: **P3a** and **P3b**. The sheet's `rule` field and `_addPlanned` consumption sit in P3a items 4–5 so the day-list wiring stays one pass; P3b owns the form. All phases run serially: P2 imports P1's `RecurrenceRule`; P3a and P3b both edit `day_session_list_screen.dart`; P4 needs the shipped behaviour. No phase runs in parallel with another.

### P1 rule — `crew-builder-app`

Write scope: `lib/core/utils/recurrence_rule.dart`, `test/recurrence_rule_test.dart`. Predicted files: the same two.
Tests added: `test/recurrence_rule_test.dart` — plain `test()`, group `RecurrenceRule`, S-27701..S-27710 (no widget, no harness).
Done: `.github/copilot/scripts/macos/gateway.sh test -- test/recurrence_rule_test.dart` green; analyze count not raised above the 176 baseline.

1. [ ] Create `RecurrenceRule` (fields `series`, `unit`, `every`, `weekdays`, `end`, `count`, `until`; static `tryParse(String?)` forgiving per D-27702; instance `encode()` with a stable key order) — `lib/core/utils/recurrence_rule.dart` · `RecurrenceRule`
2. [ ] `dates(DateTime first)` pure function per D-27703 (Monday weeks, month clamp always from `first`, `DateTime(y, m, d + k)`, one-year cap inclusive, first element always present) — `lib/core/utils/recurrence_rule.dart` · `dates`
3. [ ] `summary(DateTime first, int count)` one-line summary (`Every 2 weeks on Mon, Thu · 4 sessions`; appends `· until 14 Jan` only when the end mode is a date; day-first date text from `OmniDateUtils.shortMonthName`) — `lib/core/utils/recurrence_rule.dart` · `summary`
4. [ ] S-27701..S-27707 date arithmetic tests (the exact dates of the table) — `test/recurrence_rule_test.dart` · group `dates`
5. [ ] S-27708, S-27709 guards (first element always present; DST guard on the construction, source-text variant per the scenario) — `test/recurrence_rule_test.dart` · group `dates`
6. [ ] S-27710 round-trip and forgery decode tests — `test/recurrence_rule_test.dart` · group `tryParse/encode`

Guard proof: `prove-red` at the base commit fails as a load error (the test imports a file absent at base), so each guard is proven by a mutation the lead applies to the new file, one at a time, then reverted:
- M1 `dates` drops the guaranteed first element → S-27701, S-27708 red.
- M2 `dates` week filter `weekIndex % every == 0` → `== 1` → S-27703, S-27704 red.
- M3 `dates` month k computed from the previous emitted date instead of `first` → S-27705 red.
- M4 `dates` cap `first.year + 1` → `first.year + 2` → S-27707 red.
- M5 `dates` builds with `.add(const Duration(days: k))` → S-27709 red (or its source-text guard red by design).
- M6 `tryParse` accepts `v != 1` → S-27710 red.
- M7 `dates` until comparison made exclusive of the until day → S-27706 red (3 dates → 2).

### P2 state — `crew-builder-app`

Write scope: `lib/state/calendar/calendar_state.dart`, `lib/data/models/models.dart` (doc comment only), `scripts/sqlite_schema.sql` (comment only), `test/recurring_planned_sessions_state_test.dart`. Predicted files: the same four.
Tests added: `test/recurring_planned_sessions_state_test.dart` — plain `test()` over `harnessFactories` (Mock and Hive, the shape of `test/plan_completes_on_routine_finish_test.dart`), S-27711..S-27716, S-27727.
Done: `.github/copilot/scripts/macos/gateway.sh test -- test/recurring_planned_sessions_state_test.dart test/db_seed_test.dart test/plans_and_periods_survive_zone_change_test.dart` green.

1. [ ] `createRecurringPlannedSessions({required DateTime first, required RecurrenceRule rule, String? modality, String? routineTemplateId, String? title, String? note, bool skipFirst = false})`: one series id, one row per `rule.dates(first)` (first skipped when `skipFirst`), `scheduledDateMs: OmniDateUtils.startOfDayMs(date)`, one `_loadMonth()` at the end — `lib/state/calendar/calendar_state.dart` · `createRecurringPlannedSessions`
2. [ ] `updateSeriesFrom(PlannedSession edited)`: one `getPlannedSessions()` read, filter per D-27705 (same series id, `>=` date, `isCompleted == false`, `linkedSessionId == null`, today-or-later), rebuild each row copying modality/routine/title/note only, one `_loadMonth()` — `lib/state/calendar/calendar_state.dart` · `updateSeriesFrom`
3. [ ] `deleteSeriesFrom(PlannedSession from)`: same filter, `deletePlannedSession` per row, one `_loadMonth()` — `lib/state/calendar/calendar_state.dart` · `deleteSeriesFrom`
4. [ ] Doc comment swap: "Recurrence is NOT yet implemented… always set it to null" → the field doc describes the series rule text and its reader (wording per D-27702) — `lib/data/models/models.dart` · `PlannedSession` doc
5. [ ] Comment swap on the `recurrence_rule` column (`RESERVED: NULL until recurrence is built` → series rule text) — `scripts/sqlite_schema.sql` · `app_planned_session.recurrence_rule`
6. [ ] S-27711..S-27713 state tests over `harnessFactories` (rows and fields; one reload — a spy counts `getPlannedSessionsForDateRange` calls: one per series create, not one per row; series delete keeps completed and past-day rows) — `test/recurring_planned_sessions_state_test.dart`
7. [ ] S-27714..S-27716, S-27727 state tests (series edit field discipline, completion keeps the rule, cascade removes occurrences, zone-change read-back) — `test/recurring_planned_sessions_state_test.dart`

Guard proof: base compile fails as above; mutations:
- M8 `createRecurringPlannedSessions` moves `_loadMonth()` inside the loop → S-27711 reload count red.
- M9 `deleteSeriesFrom` drops the `isCompleted == false` filter → S-27713 red (the completed row is deleted).
- M10 `deleteSeriesFrom`/`updateSeriesFrom` change `>=` to `>` → S-27713 (row 2 kept) and S-27729 red.
- M11 `updateSeriesFrom` drops `recurrenceRule` from the rebuilt row → S-27714 red.
- M12 `completePlannedSession` drops the existing `recurrenceRule: ps.recurrenceRule` copy (`calendar_state.dart:310`) → S-27715 red.
- M13 `createRecurringPlannedSessions` stamps a different `series` id per row → S-27711 red.

### P3a dialog + day-list series wiring — `crew-builder-app`

Write scope: `lib/widgets/dialogs/confirmation_dialog.dart`, `lib/features/calendar/day_session_list_screen.dart`, `test/confirmation_dialog_three_choice_test.dart`, `test/recurring_planned_sessions_day_list_test.dart`. Predicted files: the same four.
Tests added: `test/confirmation_dialog_three_choice_test.dart` (widget test of the dialog alone), `test/recurring_planned_sessions_day_list_test.dart` (widget tests, Mock-first; series rows seeded through `createRecurringPlannedSessions`, never hand-built), S-27722, S-27723, S-27728.
Done: `.github/copilot/scripts/macos/gateway.sh test -- test/confirmation_dialog_three_choice_test.dart test/recurring_planned_sessions_day_list_test.dart test/ui_standards_contract_test.dart` green.

1. [ ] `showThreeChoice({title, body, three label/key pairs, isDestructive})` returning an enum result (Cancel on barrier and system back), reusing `_dialogActionStyle`/`_dialogActionShape` — `lib/widgets/dialogs/confirmation_dialog.dart` · `showThreeChoice`
2. [ ] `_deletePlanned` branch: a row whose rule parses → three-choice (`Just this one` / `This and all after it` / `Cancel`, keys `day-session-series-delete-one`, `day-session-series-delete-after`, `day-session-delete-cancel`) → `deletePlannedSession` or `deleteSeriesFrom`; non-series rows keep today's two-choice dialog — `lib/features/calendar/day_session_list_screen.dart` · `_deletePlanned`
3. [ ] `_editPlanned` branch: a series row asks the same three-choice before saving; `Just this one` → `updatePlannedSession`, `This and all after it` → `updateSeriesFrom` — `lib/features/calendar/day_session_list_screen.dart` · `_editPlanned`
4. [ ] `_PlannedSessionFormResult` gains `final RecurrenceRule? rule;` — `lib/features/calendar/day_session_list_screen.dart` · `_PlannedSessionFormResult`
5. [ ] `_addPlanned` consumes `result.rule`: null → `createPlannedSession` as today; non-null → `createRecurringPlannedSessions` — `lib/features/calendar/day_session_list_screen.dart` · `_addPlanned`
6. [ ] Dialog tests: the three actions render in order, each returns its value, barrier and back coalesce to Cancel, the action styles reuse the shared helper — `test/confirmation_dialog_three_choice_test.dart`
7. [ ] Day-list tests S-27722, S-27723, S-27728 — `test/recurring_planned_sessions_day_list_test.dart`

Guard proof: mutations:
- M14 `_deletePlanned` routes series rows to `showTwoChoice` (drop the branch) → S-27722 red.
- M15 `_editPlanned` drops the series branch (always `updatePlannedSession`) → S-27723 red.
- M16 `_addPlanned` ignores `result.rule` (always `createPlannedSession`) → S-27728's series setup fails to appear (and P3b's S-27717 flow red).

### P3b sheet UI — `crew-builder-app`

Write scope: `lib/features/calendar/day_session_list_screen.dart`, `test/recurring_planned_sessions_sheet_test.dart`. Predicted files: the same two.
Tests added: `test/recurring_planned_sessions_sheet_test.dart` — widget tests, Mock-first, S-27717..S-27721, S-27724, S-27725, S-27726.
Done: `.github/copilot/scripts/macos/gateway.sh test -- test/recurring_planned_sessions_sheet_test.dart test/ui_standards_contract_test.dart` green.

1. [ ] `_PlannedSessionFormState` repeat state (`_repeatOn`, `_every`, `_unit`, `_weekdays`, `_endMode`, `_count`, `_until`) and the `Repeat` switch row that shows/hides the settings block — `lib/features/calendar/day_session_list_screen.dart` · `_PlannedSessionFormState`
2. [ ] `Every` row: count 1..12, unit selector days/weeks/months (default 1, weeks) — `_PlannedSessionFormState.build`
3. [ ] Weekday chips Mon..Sun (D-27712 labels), shown only for weeks; the planned day's chip ticked and its tap ignored — `_PlannedSessionFormState.build`
4. [ ] `Ends` row: `After` count 2..366 (default 8) / `On date` picker bounded to (planned day, planned day + 1 year]; exactly one field visible — `_PlannedSessionFormState.build`
5. [ ] Summary line + session count from `RecurrenceRule.summary`, updated on every settings change (S-27719) — `_PlannedSessionFormState.build`
6. [ ] Edit sheet of a series row: read-only summary line instead of the switch (D-27709) — `_PlannedSessionFormState.build`
7. [ ] `_submit` returns `rule` (null when off; the settings dropped on off, S-27726); the form body wrapped in `SingleChildScrollView` (D-27708) — `_PlannedSessionFormState._submit`, `build`
8. [ ] `_editPlanned` Repeat-on path for a non-series row: `updatePlannedSession` with the rule stamped, then `createRecurringPlannedSessions(..., skipFirst: true)` (D-27711) — `lib/features/calendar/day_session_list_screen.dart` · `_editPlanned`

Guard proof: mutations:
- M17 `_submit` returns `rule: null` always → S-27717, S-27724 red.
- M18 the locked chip's handler un-ticks (drop the guard) → S-27718 red.
- M19 the form's `SingleChildScrollView` replaced by a bare `Column` → S-27720 red (overflow exception).
- M20 a series row's edit sheet shows the switch instead of the read-only line → S-27725 red.
- M21 the Repeat-off branch keeps the settings in the tree → S-27717, S-27726 red.

### P4 docs — `crew-docs-keeper`

Write scope: `docs/calendar_periods.md`, `docs/widget_catalog.md`, `docs/design_system.md`. Predicted files: the same three.
Tests: `test/docs_indexing_contract_test.dart` and `test/ui_standards_contract_test.dart` stay green (file sizes, symbol names).
Done: `.github/copilot/scripts/macos/gateway.sh test -- test/docs_indexing_contract_test.dart test/ui_standards_contract_test.dart` green; the Docs delta table applied row by row.

Items = the rows of the Docs delta table below, in order.

## Docs delta (seed rows; the architect completes the table from the stale-term sweep)

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| `docs/calendar_periods.md` | REMOVED | `No recurrence behavior yet (model extension point exists).` | `-` | D-27701 |
| `docs/calendar_periods.md` | MODIFIED | `- `recurrenceRule` (nullable placeholder)` | `nullable JSON text; the series rule` | D-27702 |
| `docs/calendar_periods.md` | MODIFIED | `**`recurrenceRule` is a placeholder field that is never read.**` | `A planned session repeats` | D-27702, S-27710 |
| `docs/calendar_periods.md` | ADDED | - | `Repeating planned sessions` | D-27703, S-27718, S-27722 |
| `docs/widget_catalog.md` | MODIFIED | `Shared two-choice confirmation dialog factory (`showTwoChoice`, `twoChoice`)` | `showThreeChoice` | D-27707 |
| `docs/calendar_periods.md` | MODIFIED | `Simple CRUD for planned sessions and periods.` | `Simple CRUD for planned sessions and periods, plus repeating series of planned sessions` | D-27704, D-27705 |
| `docs/calendar_periods.md` | ADDED | - | `Handles planned session CRUD and the recurring-series actions` | D-27704, D-27705 |
| `docs/design_system.md` | MODIFIED | `Both `ConfirmationDialog` shapes build their action buttons` | `Every `ConfirmationDialog` shape builds its action buttons` | D-27707 |

Stale-term sweep run this run over `docs/` (excluding `docs/plans`, `docs/history`, `docs/releases`), case-insensitive `recurrence|recurring|reserved` and `Simple CRUD for planned sessions`: the in-scope hits are `docs/calendar_periods.md:13`, `:14`, `:177`, `:241`, `:318-319` and `docs/design_system.md:388` — all covered by the rows above. `docs/widget_catalog.md:138` is the seeded row. Every other hit lives under the excluded folders (`docs/plans/*` old plan records). The `models.dart` doc comment and the `sqlite_schema.sql` comment are code-side texts, handled by P2 items 4–5 (D-27710).

## Shared contracts and their readers

- `RecurrenceRule` (new, `lib/core/utils/recurrence_rule.dart`): read by `CalendarState.createRecurringPlannedSessions`/`updateSeriesFrom`/`deleteSeriesFrom`, `day_session_list_screen.dart` `_deletePlanned`/`_editPlanned`/`_addPlanned`/`_PlannedSessionFormState`, and the P1–P3 test files. Nothing else parses rule text (grep `recurrenceRule` over `lib/` this run: only `models.dart`, `calendar_state.dart:310`, `day_session_list_screen.dart:374`).
- `_PlannedSessionFormResult.rule` (new field): read only in the same file (`_addPlanned`, `_editPlanned`); the class is private, so no other reader can exist.
- `ConfirmationDialog.showThreeChoice` (new): read by `_deletePlanned`, `_editPlanned` and its own test; the `showTwoChoice`/`twoChoice` call sites are untouched (grep listed 22+ sites across `lib/features`; none change).
- `recurrenceRule` field contract: unchanged shape, new non-null values. Readers verified this run: `models.dart` maps, `calendar_state.dart:310`, `day_session_list_screen.dart:374`, `test/plans_and_periods_survive_zone_change_test.dart:143`. Watch, seed (`lib/mock/seed_data.dart` `samplePlannedSessions` is empty and must stay empty) and `scripts/sqlite_schema.sql` structure unchanged.

## Progress

- [x] P1.1 `RecurrenceRule` value + `tryParse`/`encode`
- [x] P1.2 `dates(DateTime first)`
- [x] P1.3 `summary(DateTime first, int count)`
- [x] P1.4 date arithmetic tests S-27701..S-27707
- [x] P1.5 first-element + DST guards S-27708, S-27709
- [x] P1.6 round-trip guards S-27710
- [x] P2.1 `createRecurringPlannedSessions`
- [x] P2.2 `updateSeriesFrom`
- [x] P2.3 `deleteSeriesFrom`
- [x] P2.4 `models.dart` doc comment swap
- [x] P2.5 `sqlite_schema.sql` comment swap
- [x] P2.6 state tests S-27711..S-27713
- [x] P2.7 state tests S-27714..S-27716, S-27727
- [x] P3a.1 `showThreeChoice`
- [x] P3a.2 `_deletePlanned` series branch
- [x] P3a.3 `_editPlanned` series branch
- [x] P3a.4 `_PlannedSessionFormResult.rule`
- [x] P3a.5 `_addPlanned` consumes `rule`
- [x] P3a.6 dialog tests
- [x] P3a.7 day-list tests S-27722, S-27723, S-27728
- [x] P3b.1 repeat state + switch
- [x] P3b.2 `Every` row
- [x] P3b.3 weekday chips
- [x] P3b.4 `Ends` row
- [x] P3b.5 summary line
- [x] P3b.6 series-row read-only line
- [x] P3b.7 `_submit` + scroll wrap
- [x] P3b.8 `_editPlanned` Repeat-on path
- [x] P3b tests S-27717..S-27721, S-27724..S-27726
- [x] P4 docs delta rows 1..8

## Assumption Log

| ID | Assumption | Resolution |
|---|---|---|

(empty — none yet)

## Feedback

None yet. Review findings will land in `2026-11-19-277-recurring-planned-sessions-plan.review.md`; evidence in `2026-11-19-277-recurring-planned-sessions-plan.evidence.md` (both paths reserved beside this plan).

## Open questions (architect)

1. **Shell denied for a throwaway script** — the sandbox allows only `gateway.sh`, so the seeded "derived with a throwaway script" arithmetic was re-derived by hand instead (2026-11-19 is a Thursday: 323rd day of 2026, offset 322 ≡ 0 mod 7 from Thursday 2026-01-01; 2027 is not a leap year, so the daily cap from 2026-11-19 is 366 dates ending 2027-11-19). Every date in the table was checked by hand, not by script.
2. **S-27711's "one reload"** — `_loadMonth()` calls `notifyListeners()` twice per call (start and finally, `calendar_state.dart:160`/`:222`). The scenario's assertion is interpreted as one `_loadMonth` cycle per series create (a spy counts `getPlannedSessionsForDateRange` batches: one per create, not one per row), not one `notifyListeners`.
3. **The Goal's example summary line** shows both `8 sessions` and `until 14 Jan`; `Ends` is one-of (`After` or `On date`). Resolved (P1.3): the line always shows the session count and appends `· until <date>` only when the end mode is a date. Say if the owner wants a different composition.
4. **D-27711 and D-27712 are new decisions** appended after the seeded ledger; D-27704's seeded signature gains only an optional named parameter (`skipFirst`), which the seeded text does not contradict but the owner should confirm.
5. **New scenarios S-27726..S-27729** are appended after the seeded 25 (kept ≤ 30 for the PR scope budget's soft signal); the seeded rows are otherwise word-for-word. The seeded acceptance sentence's range was widened from S-27701..S-27725 to S-27701..S-27729 to cover them.
6. **PR scope budget check** (`.github/copilot/pr-scope-budget.md`): 4 implementation phases (P1, P2, P3a, P3b) plus a docs phase — the "more than 3 phases" soft signal fires (the seed itself already carries it); 12 decisions ≤ 20; 29 scenarios ≤ 30; one track (phone only); the plan is far under the 800-line hard limit. One soft signal only → no split proposed; do not add scenarios or decisions to this plan without re-checking.
7. `docs/design_system.md:382` cites `test/widgets/confirmation_dialog_alignment_test.dart`; no such path was found this run (dialog tests sit at the `test/` root). Not caused by this change; left alone.

## Open items for the owner

1. Defaults taken, say if you want different: a series cannot change its pattern after creation (D-27709); weeks are Monday-based; the planned day is always the first session and its weekday cannot be un-ticked.
2. No way to see the whole series at once; each occurrence is an ordinary planned session. A `Repeats` badge on the day list rows is NOT in this plan.
