# Plan 216 — evidence

Base commit `82db7759` on `claude_develop` (other sessions' `docs/plans/2026-11-15-208-fuel-burned-per-day-plan/` and `test/stats_gallery_render_test.dart` are outside this plan's scopes).

## What was built

- P1 (builder, 5.8 min): `InstrumentList` adds `_noComparisonNote` under the caption while no row has a `previousValue`; new `test/stats_no_comparison_note_test.dart` (S-21601..S-21603).
- Lead: S-21604 (two sections, one note) and S-21605 (a ten-day window names ten days) added after the mutation pass; after the review the copy was reworded to `Nothing to compare yet. Change shows once an exercise was also trained in the 4 weeks before.` and the note's gate now looks at every section; docs (`stats_screen.md`, `widget_catalog.md`).

## Lead verification

- Mutation pass, five mutants: never shows, shows when any row is new, note under every header, span hard-coded: killed (the last two only after S-21604/S-21605); the `rows.isNotEmpty` guard: equivalent (a section is built only with a row). Re-run after the wording change: killed again.
- Review (crew-reviewer): APPROVE WITH FIXES. Major: the first copy ("the 4 weeks before also hold training") was false when the earlier period held only other exercises or another measure (reworded). Minor: the note's gate looked at the first section only (fixed).

## Final runs

Full suite on the final code (lead, 900 s cap): `+7790 ~4: All tests passed!`, 0 failures. `flutter analyze`: 181 issues (baseline 181), 0 errors. `plan-lint after`: clean.

## Not done / residual

- Every row still reads `new`; the note explains why but does not replace the chips.
- An earlier value that is the zero fallback makes the chips compare against zero and hides the note (existing behaviour).
- The totals for a thin first month still live only on Records & Trends.
- (owner) A history with all sessions inside the last 4 weeks: read the new line.
