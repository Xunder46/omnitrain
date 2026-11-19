# Evidence — plan 38c (count-up screens)

Status: filled by Phase D (docs keeper, 2026-10-15). All counts below are lead-run gateway outputs as handed to this phase; the docs keeper transcribed them, not re-ran them (docs-only phase, no test run required).

## Baselines (Phase 0, lead)

- `flutter analyze`: 182 issues (0 errors).
- Full suite `flutter test`: `+4822 ~1` — all passed.

## P1 — screen change + new test file

- `test/count_up_screen_test.dart`: 18 tests passing (S-4260 both, S-4261, S-4262, S-4263, S-4264, S-4265 both, S-4266, S-4267 both, S-4268, S-4269 both, S-4270).

## P2a / P2b — reader migrations

- P2a: `+34` across `test/timed_emphasis_redesign_test.dart` and `test/session_toolbar_rework_test.dart`.
- P2b: `test/logger_shell_screen_test.dart` `+28`; `test/screen_widget_test.dart` `+240`.

## Fix rounds (lead)

- Fix 1: added 3 layout tests → `count_up_screen_test.dart` at 21 tests (S-4271, S-4271b, S-4271c).
- Fix 2: migrated `test/exercise_detail_emphasis_tier_test.dart` S-106 and added S-106b.
- Fix 3: added 4 tests (S-4276, S-4277, S-4278, S-4279) → `count_up_screen_test.dart` at 25 tests.
- Review fix (lead): S-4260 third test on a load-carrying exercise (`exercise-barbell-squat` forced to `timed`) → 26 tests.

## Full suite after fix 2

- `flutter test`: `+4841 ~1` — all passed.
- `flutter analyze`: 182 (0 errors).

## Prover (mutation round)

- 21 single-line mutations on `lib/features/session/workout_session_detail_view.dart`.
- 17 red at once; the 4 unproven ones were closed by fix 3 and then red — 21 of 21 proven.

## Simulator (lead, iPhone 17)

- Hold screen: digits; weight row at 5.0 KG after two plus taps; `Log Hold` while running; after logging the buttons dim, `LOGGED` shows, the logged line reads `0:07`, rest chip present.
- Interval screen: digits only, `Start`, no weight control.

## Layout probe (390 x 844, test font)

- Hold: weight buttons 373–421, sets stepper 465–513, rest chip 686–738, primary button 752–808.
- Interval: sets stepper 377–425.

## Final (lead)

- `flutter test`: `+4846 ~1` — all passed. `flutter analyze`: 182 (0 errors). Invariant grep clean.
