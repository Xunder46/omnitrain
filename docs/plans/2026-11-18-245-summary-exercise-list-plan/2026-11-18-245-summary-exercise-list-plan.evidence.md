# Plan 245 — evidence

Docs-keeper run (2026-11-18). Numbers below are the lead's observed results; the keeper ran no tests and no commands.

## What ran and what was observed

- New tests: 16 (10 in `test/summary_exercise_rows_test.dart`, group `Summary exercise rows (plan 245)`; 6 in `test/summary_exercise_list_screen_test.dart`), all pass.
- The 13 summary test files pass: 157 tests.
- 14 hand-applied mutants, all killed: skipped check, zero-rep check, weight and extra-weight comparisons, timed and round zero filters, empty-row filter, hard-coded unit, dropped drill kind, empty-section guard, section placement, Open Calendar handler, hard-coded unit label on the screen, bypassed formatter.
- Full suite: 7029 passed, 1074 failed — the identical set of failing tests as the base commit (1075 there; all Windows environment failures), so no new red.
- `flutter analyze`: 178 issues (baseline 181), 0 errors.

## Removed tests

- `test/calendar_summary_screen_bugs_test.dart` group `S-001 — historical summary calendar shows the session month`: the summary month grid and month label no longer exist; the file carries a deletion comment pointing at S-24511..S-24514.
- `test/summary_rest_days_elapsed_test.dart` `S-23902` and `S-23903`: the `N workout days / M rest days` totals line is gone. `S-23901` stays.

## Files changed

- `docs/session_summary.md` — overview sentence, hierarchy list, Screen Layout table, "What is not rendered" list, new `## Exercise list` section, entry-points table rows (post-workout and historical).
- `docs/calendar_periods.md` — historical-summary numbered item 1: no calendar grid on the summary; item 2 (Open Calendar pops back) unchanged.
- `docs/design_system.md` — Session Summary header row: `EXERCISES` replaces the month label.
- `docs/navigation_and_screens.md` — `SessionSummaryScreen` row: the summary shows an exercise list and no calendar grid.
- `docs/plans/2026-11-18-245-summary-exercise-list-plan/2026-11-18-245-summary-exercise-list-plan.evidence.md` — this file.
