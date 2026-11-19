# Evidence — plan 246 (summary compares like with like)

Run date: 2026-11-18. Machine: Windows. Checks run by the crew (P1–P3 builders and the lead's verify pass before docs); the full suite is run by the lead after this phase and its numbers are added by the lead here.

## New tests

- `test/summary_comparison_basis_test.dart` (new), group `Summary comparison basis (plan 246)`: 9 tests, all pass — `S-24601 routine current compares with the same routine, not a free session`, `S-24602 routine current with only a free session before it has no figure and no basis`, `S-24603 routine current with only a different routine before it has no figure and no basis`, `S-24604 free null-modality current compares with the last free null-modality session, not a routine session`, `S-24605 type match excludes other modalities and routine sessions`, `S-24606 a group the like session lacks gets no figure, a group it has gets the delta`, `S-24607 unfinished and started-after-current sessions are skipped`, `S-24608 blank title falls back to this routine`, `S-24608 null title falls back to this routine`.
- `test/summary_comparison_caption_screen_test.dart` (new): 4 tests, all pass — `S-24611 a routine summary says it compares with the last run of that routine`, `S-24612 no like session means no line`, `S-24613 a free session says it compares with the last session of its type`, `S-24614 a like session with no group shows no line`.
- 238 tests green across the comparison, services and summary test files before the last screen test was added.
- The four existing tests of `compareGroupsToPreviousSession` in `test/services_test.dart` (group `compareGroupsToPreviousSession`) were updated to read `result.deltas` and are green.

## Mutation pass

10 hand-applied mutants, all killed: routine filter; modality filter; routine sessions let through a type match; finished check removed; before-current check removed; a group missing in the like session read as 0; blank-title fallback removed; caption shown without a figure; caption wording swapped; routine label ignoring the title.

Two survivors in the first pass were closed: the first aimed at the wrong method; the second by the added screen test `S-24614 a like session with no group shows no line`.

## Analyze

`flutter analyze`: 178 issues (baseline 181), 0 errors.

## Files changed

- `lib/core/models/session_summary.dart` — `ComparisonBasis`, `GroupComparison` added next to `GroupDelta`.
- `lib/core/services/session_summary_service.dart` — `compareGroupsToPreviousSession` returns `GroupComparison`, like-session filter (same routine, else no routine and same modality), `basis` label rule, hidden-figure rule.
- `lib/features/session/session_summary_screen.dart` — `_comparisonBasis` field and the `summary_comparison_basis` caption line above the group cards.
- `test/summary_comparison_basis_test.dart` (new), `test/summary_comparison_caption_screen_test.dart` (new), `test/services_test.dart` (four calls updated).
- Docs: `docs/data_models.md`, `docs/state_management/services_and_utils.md`, `docs/README.md`, `docs/session_summary.md` (Docs delta table rows and the `## Comparison basis` section).

## Full suite

Run by the lead after this phase; numbers to be added by the lead.
