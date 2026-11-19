# Evidence — 77a Library edit own copy

> Implementers write here, not into the plan. Reviewer findings go to `2026-10-25-77a-library-edit-own-copy-plan.review.md`.

## Baselines

- `flutter analyze`: 180 issues, 0 errors (2026-10-25, from the plan header).

## Suite outputs

- P1 `test/food_library_copy_edit_test.dart`: 13 tests green (Mock group 11 + Hive group 2).
- P2/P3 `test/library_row_toggle_test.dart`: 10 tests green.
- `test/nutrition_test.dart`: +90 green; `test/screen_widget_test.dart`: +237 green.
- `flutter analyze` after the change: 180 issues, 0 errors (baseline 180).

## Red → green tables

(empty)

## Fix rounds

1. Two-line row text and outline inset — on the iPhone 17 simulator the one-line
   row text wrapped mid-macros; the row now renders `<cal> cal per <serving>` and
   `<P>P · <C>C · <F>F` on two lines, and the outline is inset.
2. Tests for the Edit screen's save routing (S-12719 / S-12720).
3. Two surviving mutants killed (see mutation pass below).

## Mutation pass (lead)

12 one-line mutations across state, edit screen and row: 10 killed at once,
2 survived — `canResetLibraryFood` without the bundled-catalog check, and the
pencil always opening the copy. Both killed after fix round 3.

## Known limit (recorded, not fixed)

`Food.copyWith` cannot set `fiber`, `sodium` or `notes` back to null (they are
not sentinel-backed), so clearing one of those fields in an edit does not stick.
Pre-existing; `resetLibraryFood` builds the row explicitly and does restore nulls.

## Simulator observations (lead, iPhone 17, 402 pt width)

- Seen: Library rows with outline, check and pencil; the editor opens on the copy.
- NOT seen: typing an edit and Reset on the device (owner check ODC-2).
- Pre-existing, not changed: the Foods I Eat row on this simulator install showed
  the caption "100 100 g" for a food whose stored label is "100 g"-style legacy data.

## Footprints

(empty)

## Assumption detail

(empty)
