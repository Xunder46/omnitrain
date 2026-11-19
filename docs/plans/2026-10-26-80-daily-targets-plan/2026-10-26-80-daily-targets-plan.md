# Feature: 80 — Daily Targets: protein, carbs and fat targets beside the calorie target

> Status: BUILT, PROVED AND REVIEWED 2026-10-26 (uncommitted on claude_develop; reviewer APPROVE, 3 minors: labels on all four Fuel figures ratified by lead, fractional gram rounding on reopen accepted, non-finite numbers fixed in fix-5). Base commit: `.work/2026-10-26-80/base.txt` (346f7ca0). Team: the crew (lead-seeded; no architect run, the seed carries exact code, see the Assumption Log). Owner request (chat, 2026-10-26): add protein/carbs/fat targets, keep the calorie target, prefill default macro targets once calories are set, and let a manual macro change auto-adjust calories. Binding conventions: `docs/global_conventions.md`; `.github/copilot/pr-scope-budget.md`.

## What the owner sees

| Moment | Today | After |
|---|---|---|
| Nutrition page, tap Set target / Change target | a screen titled "Daily Calorie Target" with one Calories box and copy saying macros are "informational" | the screen is titled **Daily Targets**: the big Calories box, then three boxes in a row: Protein (g), Carbs (g), Fat (g), then a line "Macros add up to N Cal" and one short help paragraph |
| Type 2000 in Calories | nothing else | the three boxes fill with a default split (30 % protein, 40 % carbs, 30 % fat of the calories): 150 / 200 / 67 g. The line reads "Macros add up to 2003 Cal" |
| Change a macro box (say Protein to 180) | n/a | Calories updates to what the macros add up to (2123). The other two boxes keep their numbers |
| Change Calories after you typed a macro | n/a | boxes you typed in keep your numbers; boxes still on the default re-split the new calories |
| Clear a macro box | n/a | no target for that macro (it stays empty and is not refilled) |
| Calories and macros disagree | n/a | allowed. Save is never blocked by a mismatch |
| Reopen with a saved calories-only target | a Calories box | the Calories box and the default split shown in the macro boxes (saved only if you tap Save) |
| Reopen with saved macros | n/a | your numbers |
| Home card captions | "P 42%  C 33%  F 25%" (share of what you ate) | for each macro that has a target: "P 80/150 g"; a macro without a target keeps its share, "C 33%". Never both for one macro. With a target and nothing logged yet: "P 0/150 g" |
| Nutrition page: tap a donut slice | "Protein / 80 g · 25%" | with a target: "Protein / 80 of 150 g". Tapping the carbs slice shows "Carbs / 180 of 250 g" (TOTAL carbs, fibre included). Fibre slice and macros without a target are unchanged |
| Stats, Fuel row | Calories and Protein (with "of N target") | a second line adds Carbs and Fat in the same form ("of 250 g target") |
| Watch | no nutrition target on the wrist | unchanged (scouted: the wire carries no target) |

Consequence the owner must know (not new code): the Protein Consistency signal on Stats already compares against a protein target when one exists (`protein_consistency_signal.dart`, `proteinTargetsByDay`). Once users save the default 30 % protein split, that signal judges them against that number instead of their own usual level.

(owner) Open Nutrition, Set target, type 2000, see 150/200/67; edit Protein to 180, see Calories 2123; Save; look at the home card captions, tap each donut slice, open Stats and look at the Fuel row.

## Decision Ledger

- D-1 Carbs target means TOTAL carbs (fibre included), as the owner decided. `NutritionTarget.carbs` stores total grams. The donut keeps drawing a Net Carbs slice plus a Fibre slice; when a carbs target exists, the Net Carbs slice's focus text names "Carbs" and shows `todayConsumedCarbs` (total) of the target. The no-target text and every share percentage stay net-carbs based (unchanged). The trend's carbs series is already total (`NutritionTrendPoint.carbs`, `stats_progress.dart:112-117`), and so is the new Fuel average.
- D-2 Macro inputs are grams, whole-number display, optional. Empty = 0 = no target (`NutritionTarget` has non-nullable doubles, default 0.0, `models.dart:1820-1836`; no model change).
- D-3 Default split constants: protein 30 %, carbs 40 %, fat 30 % of calories; grams = protein `calories*30/400`, carbs `calories*40/400`, fat `calories*30/900`, each `.round()`. Calories per gram 4/4/9. Helpers live in `lib/core/utils/macro_targets.dart` (new): `MacroTargets`, `defaultMacroTargets(double)`, `impliedCalories(...)`.
- D-4 Screen behaviour (exact code in the P1 brief): a macro box the user typed in (or one loaded from a stored target) is "manual". Typing Calories re-fills only the non-manual boxes (cleared when calories is empty or 0). Typing in any macro box marks it manual and sets Calories to `impliedCalories` of all three boxes (empty = 0); if all three boxes are empty Calories is left alone. Setting `controller.text` in code never fires `onChanged`, so there is no feedback loop.
- D-5 Load: stored calories > 0 and all stored macros 0 → fill the boxes with the default split (non-manual). Any stored macro > 0 → show stored grams, all three boxes manual (zero ones empty). Dirty = any of the four texts differs from the snapshot taken after load (so the load-time prefill is not "unsaved").
- D-6 Save writes the four values (macros empty → 0.0). If Calories is empty/0 and the macros add up to more than 0, Calories is saved as the implied value. Validator on all four boxes: empty ok, not a number → 'Please enter a valid number', negative → 'Please enter a non-negative number'. A mismatch never blocks.
- D-7 Screen title `Daily Targets` (loading and loaded). The nutrition page button labels `Set target` / `Change target` and `nutrition_target_button` are unchanged. The class name `NutritionTargetScreen` is unchanged.
- D-8 Donut focus (`calorie_ring_card.dart:168-193`, `macro_donut_chart.dart:672-740`): `MacroFocusContent` gains `targetGrams` (`int?`, default null). With `targetGrams > 0` the detail line is `'$grams of $targetGrams g'` (no percent). Protein and Fat use the section's grams; the `Net Carbs` section with a carbs target > 0 shows name `Carbs` and grams `todayConsumedCarbs`. Target = `nutritionState.nutritionTarget` field `.round()`, only when > 0. Fibre unchanged.
- D-9 Home card (`nutrition_summary_card.dart`, `_CaptionRow`/`_CaptionEntry`, fed by `home_screen.dart:583-596`): `NutritionSummaryCard` gains optional `proteinGrams`, `carbsGrams`, `fatGrams` (int, default 0) and `targetProteinGrams`, `targetCarbsGrams`, `targetFatGrams` (int?, default null). A macro whose target is > 0 prints `'<L> <consumed>/<target> g'` (also when nothing is logged); a macro without a target keeps today's rule. Carbs grams = `todayConsumedCarbs` (total). Card widths 390 and 320 must not overflow.
- D-10 Fuel row: `FuelSummary` gains `carbsAverage`, `fatAverage`, `previousCarbsAverage`, `previousFatAverage`, `targetCarbs`, `targetFat`, `hasCarbsTarget`, `hasFatTarget`; `computeFuelSummary` fills them from `NutritionTrendPoint.carbs/.fat` (total carbs) and the target row it already reads (`stats_progress_service.dart:2054-2078`); `FuelSection` adds a second `Row` of two metrics (carbs, fat) under the calories/protein row with keys `fuel_carbs`, `fuel_carbs_change`, `fuel_carbs_target`, `fuel_fat`, `fuel_fat_change`, `fuel_fat_target`. The training/rest split lines are unchanged.
- D-11 Out of scope: the watch (scouted: no nutrition target on the wire or in `watch/`, `ios/OmniTrain Watch App/`, `lib/watch/`), percent inputs, the trend screen (it already plots all three targets), body-weight based defaults, per-day target history UI, the signals' logic.
- D-12 Docs: `docs/nutrition.md` (lines ~254, 467-475, 523 say calories-only), `docs/signals.md` (~609-613 says target mode is unreachable), `docs/stats_screen.md` (Fuel row), `docs/widget_catalog/nutrition_widgets.md`, `docs/navigation_and_screens.md` (screen title), `docs/data_models.md` (NutritionTarget note), `docs/state_management/nutrition_state.md` only if it says macros are zero.

## Scenarios (exact fixtures; ids S-14001..)

Defaults: 2000 → 150/200/67 (implied 2003); 2400 → 180/240/80 (2400); 1850 → 139/185/62 (1854); 2200 → 165/220/73 (implied 660+880+657 = 2197). Re-derived with a script.

- S-14001 `defaultMacroTargets`: 2000 → (150,200,67); 2400 → (180,240,80); 1850 → (139,185,62); 0 and −5 → (0,0,0).
- S-14002 `impliedCalories`: (150,200,67) = 2003; (180,240,80) = 2400; protein 100 only = 400; fat 10 only = 90; none = 0.
- S-14010 empty target: title `Daily Targets`; keys `calories_field`, `protein_field`, `carbs_field`, `fat_field` all empty; no `implied_calories_readout`. Fails today: no macro fields.
- S-14011 type 2000: boxes 150 / 200 / 67; readout text `Macros add up to 2003 Cal`.
- S-14012 then enter Protein 180: Calories 2123 (720+800+603); carbs 200 and fat 67 unchanged; readout `Macros add up to 2123 Cal`.
- S-14013 then enter Calories 2200: protein stays 180 (manual); carbs 220; fat 73; readout `Macros add up to 2257 Cal` (720+880+657).
- S-14014 from S-14011 clear Fat: Calories 1400, fat empty; then enter Calories 1000: protein 75, carbs 100, fat stays empty.
- S-14015 S-14011 then Save: `nutritionState.nutritionTarget` and `repo.getNutritionTargetForDate(today)` equal calories 2000, protein 150, carbs 200, fat 67 (Mock). Fails today: macros 0.
- S-14016 calories-only still possible: type 2000, clear Protein, Carbs, Fat (each by entering empty text), type Calories 1800, Save → stored (1800, 0, 0, 0).
- S-14017 stored (2000,0,0,0): open → boxes 150/200/67 and Back pops at once (no `nutrition-target-unsaved-keep` dialog).
- S-14018 stored (2000,180,220,70): boxes 180/220/70; enter Calories 2400 → boxes unchanged.
- S-14019 empty screen, enter Protein 100 → Calories 400; clear Calories; Save → stored calories 400, protein 100.
- S-14020 enter Protein `-5`, tap Save → text `Please enter a non-negative number` shown, nothing stored.
- S-14021 type in Fat, tap Back → the unsaved-changes dialog shows (guard still works with four fields).
- S-14022 the existing calories-only tests flip: `nutrition_test.dart` group 57-77 (macro fields now present, readout key now present once a macro has text), 213-219 (macros no longer 0), 1638-1648 and `nutrition_target_button_test.dart:305` (title `Daily Targets`).
- S-14030 home card: targets 150/250/67 g, consumed 80/180/50 g → captions `P 80/150 g`, `C 180/250 g`, `F 50/67 g` and no `%` text in the caption row.
- S-14031 only a protein target (150): consumed 80 g, `proteinKcal 320, carbsKcal 280, fatKcal 450`, `consumedCalories 1050` → `P 80/150 g`, `C 27%`, `F 43%`.
- S-14032 targets set, nothing logged (`consumedCalories 0`, grams 0): `P 0/150 g`; a macro without target shows `—`.
- S-14033 no targets: the existing `P 42%` / `C 33%` / `F 25%` and `—` tests stay green unchanged.
- S-14034 `HomeScreen` passes the six values: via an existing HomeScreen harness if `home_nutrition_summary_card_test.dart` or `first_run_path_test.dart` pumps one with a `NutritionState`, else a source guard asserting each exact argument statement, the rendered `Text`, and the constructor storage.
- S-14035 donut: one consumed food (protein 80, carbs 180, fiber 30, fat 50, reference 100, consumed 100) and target (2000,150,250,67): tapping the Protein slice → texts `Protein` and `80 of 150 g`; Net Carbs slice → `Carbs` and `180 of 250 g` (not 150); Fat → `Fat` and `50 of 67 g`; Fibre → `Fiber` and `30 g`. With target (2000,0,0,0) the focus text is the old `80 g · N%`. No `of target`/`%` text with a target.
- S-14036 `MacroFocusContent`: `targetGrams` null → `80 g · 25%`; `targetGrams` 150 → `80 of 150 g`; `targetGrams` 0 → old form.
- S-14040 service: target (2200,150,250,70), two logged days with known carbs/fat/fibre → `FuelSummary.targetCarbs == 250`, `targetFat == 70`, `carbsAverage` / `fatAverage` are means over logged days of TOTAL carbs (a food with fibre 10 counts all its carbs).
- S-14041 widget: `fuel_carbs` reads `<N> g`, `fuel_carbs_target` reads `of 250 g target`, `fuel_fat_target` reads `of 70 g target`; with carbs/fat targets 0 the target keys are absent and the change compares with the previous window.
- S-14042 the existing calories/protein Fuel assertions stay green.

Readers of the changed contracts (grepped 2026-10-26): `NutritionTargetScreen` is built in one place (`nutrition_screen.dart:83-85`); `FuelSummary(` is built only in `stats_progress_service.dart:2054` (tests go through `computeFuelSummary`); `MacroFocusContent(` only in `calorie_ring_card.dart:177`; `NutritionSummaryCard(` in `home_screen.dart`, `test/home_nutrition_summary_card_test.dart`, `test/first_run_path_test.dart`; `NutritionTarget(` macro seeds in ~30 test files are inputs and stay valid. Tests that pin the old text: `test/nutrition_test.dart` (57-77, 213-219, 1638-1648), `test/nutrition_target_button_test.dart:305`. Pre-existing donut focus test group `nutrition_test.dart:640` uses targets without macros (unchanged behaviour). Watch: nothing reads a nutrition target.

## Phases

- P1 `crew-builder-app` — helper + Daily Targets screen (D-2..D-7; exact code in the brief). Scope: `lib/core/utils/macro_targets.dart` (new), `lib/features/nutrition/nutrition_target_screen.dart`. Parallel with P3.
- P3 `crew-builder-app` — Fuel row (D-10, S-14040..S-14042). Scope: `lib/core/models/fuel_summary.dart`, `lib/core/services/stats_progress_service.dart`, `lib/features/stats/widgets/fuel_section.dart`, `test/fuel_row_screen_test.dart`. Parallel with P1.
- P4 `crew-builder-app` — donut focus + home card (D-8, D-9, S-14030..S-14036). Scope: `lib/features/nutrition/widgets/macro_donut_chart.dart`, `lib/features/nutrition/widgets/calorie_ring_card.dart`, `lib/features/home/widgets/nutrition_summary_card.dart`, `lib/features/home/home_screen.dart`, `test/home_nutrition_summary_card_test.dart`, `test/daily_targets_display_test.dart` (new). Runs after P1 or P3 (writer cap 2).
- P2 `crew-builder-app` — screen tests (S-14001, S-14002, S-14010..S-14022). Scope: `test/macro_targets_test.dart` (new), `test/daily_targets_screen_test.dart` (new), `test/nutrition_test.dart`, `test/nutrition_target_button_test.dart`. After P1.
- P5 lead — analyze, touched tests, full `flutter test`, invariant grep, layout probe at 390x844 and 320 wide, simulator look, mutation pass.
- P6 `crew-docs-keeper` (D-12), then `crew-reviewer`.

## Assumption Log

- No architect run: the seed carries exact code (P1 brief) and four phases of at most 8 items each; recorded in friction as in plans 56/57.
- The default split 30/40/30 is the lead's pick (it makes the owner's own example, "of 150 g target", come out for 2000 kcal). The owner can change the three constants.
- A macro with a target but nothing logged shows `P 0/150 g` on the home card instead of the day-one dash: a target is something the user chose, so showing the goal is more useful than hiding it. Reported to the owner.
- Mixed captions are allowed per macro (some with grams, some with a share) because macro targets are optional.
- Clearing macros one by one lowers Calories each time (D-4); the last cleared leaves Calories at what was left. Accepted: the owner asked that macro edits adjust calories.
