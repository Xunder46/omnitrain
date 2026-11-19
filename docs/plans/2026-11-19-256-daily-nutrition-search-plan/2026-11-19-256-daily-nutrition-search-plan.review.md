# Review: plan 256 (Daily Nutrition search with "Add & log") · all phases · cbdd199d..working tree

Verdict: APPROVE WITH FIXES

Counts: blocker 0 · major 2 · minor 3 · tests: targeted run `flutter test test/ui_standards_contract_test.dart test/docs_indexing_contract_test.dart test/nutrition_search_screen_test.dart test/food_catalog_load_test.dart` = 115 passed / 11 failed; all 13 plan-256 tests green; every one of the 11 failures names only files this diff does not touch (docs/plans over-ceiling files, lib/app.dart raw colours, add_food_screen/profile_screen dialogs, omni_message/pr_toast SnackBars) or is a Windows `Illegal character in path` crash inside `docs_indexing_contract_test.dart` itself (`_Uri.file`) — pre-existing, none attributable to plan 256. Full suite not run (brief forbids it).

Diff vs Predicted Files: outside: `test/food_catalog_load_test.dart` (1 line, see finding 5)

## Findings

1. [Major] `docs/widget_catalog/nutrition_widgets.md` — the plan's Docs delta row "ADDED `nutrition_search_field`" is NOT applied. Grep over `docs/` finds `nutrition_search_field` only in `docs/nutrition.md` and the plan; the widget catalog's nutrition section does not name it. A maintainer building against the widget catalog never learns the search box and its two contract keys (`nutrition_search_field`, `nutrition_search_clear`) exist. Fix: one sentence in the nutrition section naming the keys, as the plan's keeper instruction says. Guard: the marker check the governor already runs.
2. [Major] Goal sentence "Removed-food rows (plan 247) are hidden while a search is typed" has no test in `test/nutrition_search_screen_test.dart`: no test seeds a consumed row whose library food is gone and then types a query, so no assertion in the file can fail if the removed-foods block were rendered during a search (plan mutation (l)). The brief says all 13 mutations were killed; no test this run can see how (l) was killed, so treat it as unproven here. Fix: one test seeding a removed-food row (log, delete the library food), typing a query, asserting the removed block is absent. Guard: that test.
3. [Minor] `lib/features/nutrition/nutrition_screen.dart` `_addAndLog` — failure after the library add succeeded (the log write throws, or a grams food with `referenceAmount <= 0` makes `logConsumedFoodViewed` return null): the food IS in Foods I Eat, the row disappears from `From the catalog` (the cache notify rebuilds the `isInLibrary` filter), and the user sees `Could not add the food. Try again.` with no row to retry on. Recovery exists (the new row is visible under its heading in the results, where it can be logged normally), so the state is consistent; the message is just misleading about what failed. Smallest fix: reword the failure copy to name the partial result, or leave as planned (D-25605 specifies this copy) and accept. Guard: a mock-repo test whose log write throws asserting the library add survived.
4. [Minor] `lib/features/nutrition/nutrition_screen.dart` `_addAndLog` — if the day arrows are tapped while `addCatalogFoodToLibrary` is in flight, `logConsumedFoodViewed` captures `_pastViewMs` at ITS start (`nutrition_state.dart:871-879`), so the row lands on the newly shown day, not the day the tap started on. The plan's Input-reality item 7 sentence ("logs on the day the write started on") holds only under the reading "the write = the log call". The row always lands on a day the screen is showing, so nothing is lost; record the wording choice or no change. Guard: none suitable without a fake clock in the section.
5. [Minor] `test/food_catalog_load_test.dart:270` — a one-line change outside the plan's Predicted Files (`byId['chicken_thigh']!.fat!` → `...!.fat`). `Food.fat` is a non-nullable `double` (`lib/data/models/models.dart:1852`), so the dropped `!` removes an unnecessary-null-assertion info; the plan does not say why. If this is the analyze-baseline bookkeeping, note it in the plan; otherwise revert.

Not findings, checked: the transient cold-cache window (typed query before `loadCatalogFoods` finishes) can briefly show `No foods match "x"` for a catalog food; the post-frame load notifies (`loadCatalogFoods` notifies in its `finally`, `food_library_state.dart:891-906`) and the section's `ListenableBuilder` rebuilds, so it self-corrects — the same accepted pattern as `AddFoodScreen.initState`. `loadFoods` does NOT load the catalog (`food_library_state.dart:415-439` has no `loadCatalogFoods` call), so the screen's own load call is needed, not redundant. `isInLibrary` edge cases (`food_library_state.dart:575-623`): a user-edited library copy stays hidden via the durable `catalogId` link; a legacy row without `catalogId` hides only while its value identity matches; an archived library row is deliberately skipped, so the catalog food is offered again after removal (documented intent). `mounted`, `messenger`/`theme`-before-await and the `_adding` double-tap guard in `_addAndLog` are all real; the buttons also disable via `busy`.

## Docs delta

`docs/nutrition.md` ADDED `### Search` -> applied — sits after `### Earlier days`, before `### AddFoodScreen`; every sentence cites a test that exists in `test/nutrition_search_screen_test.dart` (S-25602..S-25608, S-25610) and states what those tests assert
`docs/widget_catalog/nutrition_widgets.md` ADDED `nutrition_search_field` -> MISSING (finding 1)

Doc edits the table does not name: none needed — grep over `docs` (excluding `docs/plans`) for the old wording finds no sentence that is now false: no "no search on Daily Nutrition" claim outside plans, and `docs/watch-app-setup-and-qa.md:768` ("open Nutrition and tap Choose foods") and the `Choose foods` button descriptions in `docs/nutrition.md:96` / `docs/widget_catalog/nutrition_widgets.md:15` remain true (the button is unchanged).

## Assumption Log rulings

The plan carries no Assumption Log section and no entries; for a one-screen, no-storage-change plan that is acceptable.

## Scenario coverage

S-25601 -> test/nutrition_search_screen_test.dart · S-25601
S-25602 -> test/nutrition_search_screen_test.dart · S-25602
S-25603 -> test/nutrition_search_screen_test.dart · S-25603
S-25604 -> test/nutrition_search_screen_test.dart · S-25604
S-25605 -> test/nutrition_search_screen_test.dart · S-25605
S-25606 -> test/nutrition_search_screen_test.dart · S-25606 (asserts the repo row, amount 100, cleared field, message)
S-25607 -> test/nutrition_search_screen_test.dart · S-25607 (asserts yesterday has the row and today does not)
S-25608 -> test/nutrition_search_screen_test.dart · S-25608
S-25609 -> test/nutrition_search_screen_test.dart · S-25609
S-25610 -> test/nutrition_search_screen_test.dart · S-25610 (+ S-25610b: count food with reference 2 logs 1; + S-25611: the 20-row cap, first 20 alphabetically)
Removed-foods hidden while searching -> MISSING (finding 2)
Failure message path -> MISSING (plan itself allowed skipping mutation (k); recorded, not counted against the scenarios)

## Lead dispositions

1. Major (the widget catalog entry was missing): FIXED (a `_CatalogMatchRow` entry naming the keys).
2. Major (no test for "removed-food rows are hidden while searching"): FIXED by S-25612, mutant killed.
3. Minor (a failed log after a successful library add): accepted, recorded as open item 4; the food is visible and loggable under its heading.
4. Minor (a day change during the add): recorded in the plan (input-reality item 7 reworded).
5. Minor `test/food_catalog_load_test.dart:270`: not this plan's change; already modified before the unit started (the owner's), left unstaged.
