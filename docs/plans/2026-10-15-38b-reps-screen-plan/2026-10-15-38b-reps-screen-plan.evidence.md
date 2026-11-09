# Evidence — plan 38b (reps screen: `ValueStepperRow`)

Lead-run checks, per phase. Counts are as the lead pasted them; this file
records them, it does not re-run anything (docs-only phase).

## Baseline (before P1, 38a tree)

- `flutter analyze`: 182 issues, 0 errors.
- `flutter test` (full suite): `+4788 ~1` — all passed.

## Phase P1 — `MetricStepping` + `ValueStepperRow`

- Builder run: 9 min.
- Lead-verified: 21 new tests green (`test/metric_stepping_test.dart`,
  `test/value_stepper_row_test.dart`); contracts green
  (`test/ui_standards_contract_test.dart`,
  `test/palette_legibility_contract_test.dart`); `flutter analyze` 182.

## Phase P2 — session screen wiring

- Builder run: 6 min.
- Lead-verified: full suite `+4817 ~1` — all passed; `flutter analyze` 182.
- 8 new screen tests in `test/reps_screen_test.dart`.
- Migrations: bare `Icons.add` / `Icons.remove` finders moved to
  `find.byKey(const Key('set-count-add'))` / `find.byKey(const
  Key('set-count-remove'))` in `test/session_toolbar_rework_test.dart`,
  `test/watch_session_edit_restore_late_entry_test.dart` and
  `test/unsaved_changes_dialog_test.dart`, because the new rows show the same
  icons and the bare finders became ambiguous.

## Fix round 1

- S-4255 / S-4255b added (layout guards, rest strip up / down);
  `test/reps_screen_test.dart` now carries 10 tests.

## Layout probe (lead, throwaway, 390 x 844, test font — wider than the device font)

Rest strip down:

- reps buttons top 260, bottom 308
- weight buttons 348–396
- sets stepper 440–488
- `Log Set` 752–808

Rest strip up:

- chip 686–738
- sets stepper 423–471 (the weight row sits 8 dp higher because the wide test
  font scales the number)

## iOS simulator (iPhone 17, real font), live session

- Both rows show minus on the left and plus on the right; a tap steps (weight
  +2.5 per tap, reps −1).
- A 2.5 s hold on weight plus moved 5.0 to 42.5 and stored once.
- `Log Set` showed `9×42.5` on the logged line, with the rest chip up and the
  sets stepper reachable.
- Navigating back to the logged set dimmed all four buttons and showed
  `LOGGED`.

Not looked at on the device: the session editor and pounds (covered by tests
only — `test/reps_screen_test.dart` `S-4252: edit mode steps a logged set
without storing it`, `S-4251: with pounds saved the weight row steps 5 lb`).
