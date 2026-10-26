# Review: 2026-10-26-80-daily-targets-plan · P1..P5 · 346f7ca0..working tree
Verdict: APPROVE
Counts: blocker 0 · major 0 · minor 3 · tests: 5691 passed / 0 failed / 2 skipped (`All tests passed!`, full `flutter test`, 04:38)
Diff vs Predicted Files: conforms — every lib/test file is inside a phase's scope; docs are the D-12 set (`docs/widget_catalog/nutrition_widgets.md` turned out to hold no ring/donut/summary/target-screen content, so the catalog updates correctly landed in `docs/widget_catalog.md` and `docs/widget_catalog/home_screen.md`).

## Findings

1. [Minor] `lib/features/stats/widgets/fuel_section.dart:103,128` — the diff adds `labelKey`/`label` ("Calories", "Protein") to the two pre-existing metrics, not only the new carbs/fat row D-10 authorises. The owner sees new labels above figures the plan's table described as unchanged. Tested (`S-14043 the four figures are labelled`) and documented (`docs/stats_screen.md` "four figures in two rows, each carrying its own label"), so it reads as a deliberate lead decision — listed for the owner, not a defect. Fix: none needed if the owner ratifies; otherwise drop the two labels.
2. [Minor] `lib/features/nutrition/nutrition_target_screen.dart:83-85` — a stored fractional macro (reachable only by typing a decimal, e.g. protein `150.5`) is shown rounded by `_gramsText` ("150"); reopening and tapping Save without edits then persists 150.0, silently moving the stored target by <1 g. D-5/D-6 do not describe the round-on-reopen. Fix: keep the raw stored text in the box, or accept and document the rounding.
3. [Minor] `lib/features/nutrition/nutrition_target_screen.dart:47-49,140-146` — `_valueOf`/`_validateGrams` accept any `double.tryParse` success, including `1e400` (Infinity) and `NaN`: typing `1e400` in a macro box puts the literal text `Infinity` in the Calories box (`implied.toString()` in `_syncCaloriesFromMacros`) and Save persists infinity/NaN. Pre-existing for the Calories box; the diff extends the hole to the three macro boxes. Fix: reject non-finite values in `_validateGrams` (`!parsed.isFinite`).

## Assumption Log rulings
- No architect run, seed carries exact code — ratify: the screen implements D-4/D-5/D-6 exactly as seeded and the screen group is green.
- Default split 30/40/30 is the lead's pick — ratify: the three constants sit in `lib/core/utils/macro_targets.dart` and the owner can change them.
- `P 0/150 g` with a target and nothing logged — ratify: implemented in `_CaptionEntry` (target form takes precedence over the empty-state dash), tested by S-14032.
- Mixed captions per macro — ratify: tested by S-14031.
- Clearing macros one by one lowers Calories each time — ratify: tested by S-14023.

## Scenario coverage
- S-14001 → `test/macro_targets_test.dart` · group `defaultMacroTargets (S-14001)` (2000/2400/1850/0/−5)
- S-14002 → `test/macro_targets_test.dart` · group `impliedCalories (S-14002)` + round-trip group
- S-14010..S-14021 → `test/daily_targets_screen_test.dart` · one named testWidgets each (S-14010 empty, S-14011 prefill, S-14012 protein 180, S-14013 calories 2200, S-14014 clear fat, S-14015 save, S-14016 calories-only, S-14017 prefill not dirty, S-14018 stored macros manual, S-14019 protein-only save, S-14020 negative blocked, S-14021 unsaved dialog)
- S-14022 → `test/nutrition_test.dart` · flipped group `NutritionTargetScreen — daily targets (plan 80)` + `test/nutrition_target_button_test.dart` · title `Daily Targets`
- S-14030, S-14031, S-14032, S-14034 → `test/home_nutrition_summary_card_test.dart` · group `NutritionSummaryCard — macro targets (plan 80)` (incl. S-14034b and the 390/320 no-overflow test)
- S-14033 → the unchanged no-target caption tests in the same file, green in the full run
- S-14035, S-14036 → `test/daily_targets_display_test.dart` · groups `CalorieRingCard — focus text with macro targets (S-14035)` and `MacroFocusContent — target forms (S-14036)`
- S-14040, S-14041 → `test/fuel_row_screen_test.dart` · group `Fuel row — carbs and fat (plan 80)` (with-target and no-target subgroups)
- S-14042 → the unchanged calories/protein Fuel assertions, green in the full run
- (extra) S-14023..S-14027, S-14043 → covered in `daily_targets_screen_test.dart` and `fuel_row_screen_test.dart`
