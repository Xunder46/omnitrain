# Plan 256 — Daily Nutrition has a search that finds a food and logs it in one step

Review item 23 (owner list: "Finding a food. A food must be added to 'Foods I Eat' before logging, and the daily list has no search. Suggested: search on the daily screen that can add and log in one step.").
Phone only. No wire, watch, storage or schema change. Uses what exists: the catalog cache, `addCatalogFoodToLibrary`, the viewed-day log (plan 247).

## Goal and acceptance

The Foods I Eat list on Daily Nutrition gets a search box on top (above the empty state too).

- Empty box: the screen is exactly as before.
- Typing filters "Foods I Eat" by name (case-insensitive substring, spaces trimmed), keeping the category headings, so a long list narrows to the foods you eat that match.
- Below those, a section **From the catalog** lists the bundled and shared catalog foods that match and are NOT already in Foods I Eat (at most 20, alphabetical), each with its calories per serving and an **Add & log** button.
- **Add & log** puts the food into Foods I Eat and logs it on the day the screen shows (today or an earlier day, plan 247) with its normal first portion (a grams food: its reference amount, for example 100 g; a count food: 1). It clears the search, shows `Added to Foods I Eat and logged` and the ring updates. Tap the amount on the new row afterwards to change it.
- No match in either list: `No foods match "x"` with `Try a different search.`
- A new user with an empty Foods I Eat list can use the search straight away (the box is above the "Pick the foods you eat" prompt).
- Removed-food rows (plan 247) are hidden while a search is typed.

Acceptance: S-25601..S-25610 green, the "fails without" ones red at the base commit; `flutter analyze` not above 178 issues, 0 errors; no new red in the full suite against the base failing set; Docs delta applied.

## What the user sees

- Open Daily Nutrition, type `che` in Search: your Cheese row and, under "From the catalog", Cheddar, Cream cheese ... each with an `Add & log` button. Tap it on Cheddar: it is in Foods I Eat, logged for the day, the search is cleared.
- To SEE it: open Daily Nutrition and type any food name you have not added yet.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-25601 | `_FoodLibraryBrowseSection` becomes a `StatefulWidget` (state `_FoodLibraryBrowseSectionState`) holding the search text; `initState` posts a frame callback that calls `foodLibraryState.loadCatalogFoods()` when `catalogFoods` is empty (the same as `AddFoodScreen.initState`). | `nutrition_screen.dart:399-497`, `add_food_screen.dart:85-98` |
| D-25602 | The search box: `TextField` key `nutrition_search_field`, hint `Search foods`, `Icons.search` prefix, dense outlined, a clear `IconButton` (key `nutrition_search_clear`, tooltip `Clear`) while the text is non-empty, `onChanged` -> `setState`. It is the first child of the section, also above the empty state. | `add_food_screen.dart:481-499` (the same look) |
| D-25603 | With a non-empty trimmed query: library rows = `foods` whose lower-cased name contains the lower-cased query, sectioned with the same `foodsIEatSections(...)` call and rendered with the same `_GroupBlock`; the removed-foods block is not shown; the catalog list = `foodLibraryState.catalogFoods` where `!archived`, the name contains the query and `!foodLibraryState.isInLibrary(id)`, sorted by lower-cased name, first 20. | `foods_i_eat_order.dart`, `food_library_state.dart:77,574` |
| D-25604 | New private widget `_CatalogMatchRow` (name, caption `${calculateCalories(food)} cal per ${foodUnitCaption(food)}` for a grams food with its reference amount, or `${calculateCalories(food)} cal each` for a count food, and the button). The button is an `OmniUtilityButton` (key `nutrition_search_add_<catalogId>`, label `Add & log`, `Icons.add`). | `food_helpers.dart`, `omni_utility_button.dart` |
| D-25605 | Add & log: `final libraryId = await foodLibraryState.addCatalogFoodToLibrary(catalogId);` read the library food (`foodLibraryState.foods` by that id), `await nutritionState.logConsumedFoodViewed(food, amount)` where `amount` = `food.unitType == FoodUnitType.grams ? food.referenceAmount : 1.0`; on a null result or an exception show `OmniMessage.error(context, 'Could not add the food. Try again.')` and leave the search as it is; on success clear the search and show `OmniMessage.show(context, 'Added to Foods I Eat and logged')`. A second tap while one is running is ignored (`_adding`). | `food_library_state.dart:923`, `nutrition_state.dart` (`logConsumedFoodViewed`, plan 247) |
| D-25606 | Everything else (the arrows, the ring, the removed-foods block with an empty query, the empty state) is unchanged. | — |

## Scenarios

Fixtures. The screen harness of `test/nutrition_day_switcher_screen_test.dart` (plan 247: `_freshRepo`, `_buildState`, the `NutritionScreen` pump, clock `DateTime(2026, 11, 18, 10)`, surface 600x1200, Mock repository, `clearConsumedFoodsForTest()`). Library: Egg (`f-egg`, count, ref 1, 6P/1C/5F) and Rice (`f-rice`, grams, ref 100, 10/10/10). Catalog (written with `repo.createCatalogFood(Food(... isCatalog: true ...))` before the screen loads it): Cheddar (`c-cheddar`, grams, ref 100 `g`, 25P/1C/33F), Cream cheese (`c-cream`, grams, ref 100 `g`, 6P/4C/34F), Egg noodles (`c-noodle`, grams, 100 `g`, 14P/71C/4F), and Egg (`c-egg`, count, the catalog twin of the library egg: the library egg is a copy of it via `catalogId: 'c-egg'`, so it counts as in the library). If the catalog cache must be loaded explicitly for the test, call `foodLibraryState.loadCatalogFoods()` before pumping.

| ID | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-25601 | open the screen, no query | no `From the catalog` text; the library rows as before | control |
| S-25602 | type `ric` | the Rice row is shown, the Egg row is not; no catalog match, no `From the catalog` section | no filter |
| S-25603 | type `CHE` (upper case, with spaces around) | catalog rows Cheddar and Cream cheese under `From the catalog`, alphabetical, each with its `Add & log` button; no library row (Egg does not contain `che`) | no catalog section |
| S-25604 | type `egg` | the library Egg row; the catalog shows `Egg noodles` only (the catalog Egg is already in the library) | an in-library catalog food would be offered twice |
| S-25605 | type `zzz` | `No foods match "zzz"` and no rows | no empty state |
| S-25606 | type `che`, tap `nutrition_search_add_c-cheddar` | the food is in `foodLibraryState.foods` (name Cheddar, `catalogId c-cheddar`); one row for it in today's log with amount 100 and the day's calories updated; the search field is empty; the snack bar text `Added to Foods I Eat and logged` shows | nothing happens |
| S-25607 | go to yesterday with the arrow, type `che`, tap Add & log | the row is logged on YESTERDAY (`getConsumedFoodsForDate(yesterday)`), not today | logs on today |
| S-25608 | an empty library (no foods), type `che`, Add & log | the search box is visible above the `Pick the foods you eat` prompt before typing; after Add & log the prompt is gone and the new food's row shows | a new user could not search |
| S-25609 | type `che` then tap the clear button | the field is empty and the list is the full one again | no clear |
| S-25610 | a count catalog food (`c-egg2`: count, ref 1) added with Add & log | logged with amount 1.0 | grams rule applied to a count food |

## Input-reality checklist

1. Writers: library foods are written by `addCatalogFoodToLibrary` (this flow), the food form and the picker; rows by `logConsumedFoodViewed` (plan 247). Units: grams or count multiplier.
2. Lifecycle: a catalog food the user already added is excluded by `isInLibrary` (durable `catalogId` link first, then value identity); a library food removed later reappears in the catalog list; deleting a food leaves logged rows as before.
3. Settings: none.
4. Time: the day is the viewed day; switching day keeps the search text (the section keeps its state) (accepted).
5. Cost: filtering is local and per keystroke over at most a few hundred names; the catalog loads once when the cache is empty.
6. Words: new copy `Search foods`, `From the catalog`, `Add & log`, `<N> cal per g`/`each`, `Added to Foods I Eat and logged`, `No foods match "x"`, `Could not add the food. Try again.` (owner to read).
7. Competition: the search box and the day arrows both change what the list shows; a result tapped on one day and the arrows moved before the write lands logs on the day the write started on (the viewed-day methods re-check as in plan 247).

## Phases

1. **P1 builder-app**, scope `lib/features/nutrition/nutrition_screen.dart`: D-25601..D-25606 (exact code in the brief). No full suite.
2. **P2 builder-app** (after P1), scope `test/nutrition_search_screen_test.dart` (new): S-25601..S-25610.
3. **P3 lead**: readers, full suite, analyze, mutation pass, docs, reviewer.

## Readers

`test/nutrition_day_switcher_screen_test.dart`, `nutrition_log_from_library_test`, `nutrition_test`, `picker_polish_test`, `row_caption_and_primer_test`, `daily_targets_display_test`, `first_run_path_test`, `header_standardization_test`, `screen_widget_test` (nutrition groups), `nutrition_target_button_test`, `my_foods_unification_test`, `food_group_membership_test`, `screen_overflow_contract_test`, `ui_standards_contract_test`, `docs_indexing_contract_test`.

## Mutation list (lead)

(a) the library filter removed (S-25602); (b) case-sensitive match (S-25603); (c) the query not trimmed (S-25603); (d) in-library catalog foods offered (S-25604); (e) the 20-row cap removed (add an S-25611 if a seed has more than 20: the lead may skip); (f) Add & log skips `addCatalogFoodToLibrary` (S-25606); (g) logs on today instead of the viewed day (S-25607); (h) the search not cleared after success (S-25606); (i) the search box hidden in the empty state (S-25608); (j) count foods logged with the reference amount (S-25610); (k) a failure shows no message (needs a failing repo: skip if costly); (l) the removed-foods block shown while searching.

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| `docs/nutrition.md` | ADDED | - | ### Search | S-25603, S-25606 |
| `docs/widget_catalog/nutrition_widgets.md` | ADDED | - | `nutrition_search_field` | S-25603 |

The keeper (the lead) adds `### Search` under the `NutritionScreen` section of `docs/nutrition.md` (after `### Earlier days`, at most 10 lines: the box, the filter, From the catalog, Add & log on the viewed day with its first portion, the empty state, each citing its test) and one sentence naming the keys in the widget catalog's nutrition section.

## As built

Added after the mutation pass and the review: S-25610b (a count catalog food with reference amount 2 logs 1.0, one serving), S-25611 (the 20-row cap: 25 matches show 20), S-25612 (removed-food rows are hidden while searching). The Docs delta row for the widget catalog is applied as a `_CatalogMatchRow` entry (the search keys are named there). Input-reality item 7 reads: the log call lands on the day the screen shows when the log starts (plan 247 captures the viewed day at its start); a day change while the catalog add is in flight logs on the new day (nothing is lost).

## Open items

1. (owner) Add & log uses the food's first portion (grams: its reference amount, for example 100 g; count: 1), not a typed amount: change it on the new row afterwards.
2. (owner) The catalog list shows at most 20 matches; a longer match list is cut (type more letters).
4. If the log fails after the library add succeeded, the food is already in Foods I Eat (visible under its heading while the search stays) and the message reads `Could not add the food. Try again.` (the copy of D-25605).
3. (owner) Foods you created yourself and not yet added to Foods I Eat are in the catalog list (they are catalog foods since plan D-2).
