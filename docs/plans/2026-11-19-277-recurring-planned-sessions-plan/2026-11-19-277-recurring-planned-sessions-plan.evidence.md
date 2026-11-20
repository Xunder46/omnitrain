# Plan 277 evidence — Recurring planned sessions

Counts and mutation proof below were reported by the crew for this plan; the
docs keeper folded them into this file without re-running the suite (brief
277 P4).

## P1 — `RecurrenceRule`

Files changed:

- `lib/core/utils/recurrence_rule.dart` — new `RecurrenceRule` value type with
  `tryParse`/`encode`, `dates(DateTime first)`, `summary` and `describe`.

Tests:

- `test/recurrence_rule_test.dart` — 12 tests (S-27701..S-27710, S-27725b).

## P2 — series state

Files changed:

- `lib/state/calendar/calendar_state.dart` — `createRecurringPlannedSessions`,
  `updateSeriesFrom`, `deleteSeriesFrom`.
- `lib/data/models/models.dart` — `recurrenceRule` doc comment swap.
- `scripts/sqlite_schema.sql` — comment swap.

Tests:

- `test/recurring_planned_sessions_state_test.dart` — 20 tests, 10 per
  harness (Mock and Hive; S-27711..S-27716, S-27727, S-27729, S-27730,
  S-27711b).

## P3a — series actions and the three-choice dialog

Files changed:

- `lib/widgets/dialogs/confirmation_dialog.dart` — `ConfirmationDialog.showThreeChoice`.
- `lib/features/calendar/day_session_list_screen.dart` — `_deletePlanned` and
  `_editPlanned` series branches, `_PlannedSessionFormResult.rule`, `_addPlanned`
  consuming `rule`.

Tests:

- `test/confirmation_dialog_three_choice_test.dart` — 8 tests (P3a).
- `test/recurring_planned_sessions_day_list_test.dart` — 9 tests
  (S-27722, S-27723, S-27728).

## P3b — the Repeat sheet

Files changed:

- `lib/features/calendar/day_session_list_screen.dart` — Repeat state +
  switch, `Every` row, weekday chips, `Ends` row, summary line, series-row
  read-only line, `_submit`, `_editPlanned` Repeat-on path.

Tests:

- `test/recurring_planned_sessions_sheet_test.dart` — 10 tests
  (S-27717..S-27721, S-27724, S-27725, S-27726, S-27726b, S-27718b).

## Mutation proof (lead)

40 one-line mutants, all killed except two named equivalent/cosmetic
survivors:

1. `until` kept when the end mode is a count (encode drops it) — equivalent,
   not a behaviour change.
2. the dialog's overflow spacing line — cosmetic.
