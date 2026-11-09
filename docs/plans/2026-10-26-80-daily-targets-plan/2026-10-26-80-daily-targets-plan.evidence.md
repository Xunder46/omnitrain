# Evidence — plan 80 (Daily Targets)

Checks the lead observed on the working tree (base 346f7ca0 + P1..P4):

| Phase | Scope | Check observed |
|---|---|---|
| P1 | `macro_targets.dart` helper + the Daily Targets screen | `flutter analyze`: 0 errors |
| P3 | Fuel row (`FuelSummary`, `computeFuelSummary`, `FuelSection`) | `flutter analyze`: 0 errors |
| P4 | Donut focus (`MacroFocusContent.targetGrams`) + home card captions | `flutter analyze`: 0 errors |
| P2a | Screen tests (`macro_targets_test.dart`, `daily_targets_screen_test.dart`, the `nutrition_test.dart` flips) | full `flutter test`: `+5683 ~2: All tests passed!` (before the fix rounds; the lead re-runs after) |
| P2b | Display tests (`daily_targets_display_test.dart`, `home_nutrition_summary_card_test.dart` group `NutritionSummaryCard — macro targets (plan 80)`, `fuel_row_screen_test.dart` group `Fuel row — carbs and fat (plan 80)`) | same full-suite line |
| Fix rounds 1–4 | mutants and labels (rounds 1–2 tests-only, one per surviving mutant) | the 11 non-equivalent survivors each killed; `S-14043 the four figures are labelled` green |

Mutation pass (lead, scripted): 54 mutants, 40 killed on the first pass, 14
survived. 3 are equivalent: a boundary `calories <= 0` vs `< 0` in
`defaultMacroTargets` (both give zeros), a redundant `!informational` in
`MacroFocusContent`, a redundant `>= 0` in `_targetGrams` that the card
re-checks. The other 11 were each killed after tests-only fix rounds 1 and 2.

Simulator look (iPhone 17, screen at phone width):

- Daily Targets: typing Protein 180 moves Calories to `2123`.
- Donut focus: `Carbs 25 of 200 g`.
- Home card: `P 1/180 g · C 25/200 g · F 0/67 g`.
- Stats Fuel row: two rows (Calories, Protein over Carbs, Fat).

(owner) To do by hand: the device look (a real device, not the simulator), and
confirming the default 30/40/30 split is what they want.
