# Plan 254 — The food form has a Calories box you can overwrite on its own

Review item 17, second half (owner: "an optional calories field that overrides the sum, it is still autocomputed but can be edited alone without affecting anything"). Plan 253 made a food and a logged row able to hold a calories number; this plan lets the user type it.
Phone only. No wire, watch or schema change.

## Goal and acceptance

The food form (new food, edit food, edit a catalog food, the "make my own copy of a default food" path) shows a **Calories (kcal)** box under Sodium instead of the read-only `= N cal` line.

- The box follows the macros: until the user types in it, it shows the macro sum (protein x 4 + carbs x 4 + fat x 9, rounded) and updates live as Fat, Carbs and Protein change.
- Typing a number in it overwrites the calories for this food and nothing else: the macros do not move, and later macro edits no longer change the box.
- When the number differs from the macro sum a quiet line under the box says `Macros give 16 cal` with a `Use macros` button that puts the macro sum back and returns the food to "computed".
- Saving stores the typed number as the food's calories override (plan 253); a number equal to the macro sum, or a blank box, stores no override (the food stays "computed"). Editing a food that has an override opens with that number in the box.
- Every way a form saves reaches the stored food: new custom or catalog food, edit of a custom food, edit of a catalog food (and its linked library copies), a default food saved as the user's own copy.
- Nothing else changes: macros, sodium, the donut, the serving choice.

Acceptance: S-25401..S-25412 green, the "fails without" ones red at the base commit; the existing form tests that read the old `= N cal` line are rewritten to read the box; `flutter analyze` not above 178 issues, 0 errors; no new red in the full suite against the base failing set; Docs delta applied.

## What the user sees

- New Food: type Fat 0, Carbs 3.6, Protein 0.5: the Calories box reads 16. Type 43 in it: it stays 43 when you change Carbs; a line under it says `Macros give 16 cal` and `Use macros`. Save: the food shows 43 kcal per 100 ml in the list, the logging row and the day ring.
- Edit a food with no number typed: the box reads the macro sum and follows the macros as before.
- To SEE it: add a food, type a calories number different from the macro sum, log it, watch the day ring.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-25401 | `FoodDraft` gets `final double? caloriesOverride` (optional named, default null: every existing construction compiles). | `food_draft.dart` |
| D-25402 | `FoodLibraryState` carries it through EVERY site that turns a draft or named fields into a `Food`: `createCatalogFood` (`Food(...)`), `updateCatalogFood` (`existing.copyWith(..., caloriesOverride: draft.caloriesOverride)`, so null clears) and its propagation to linked library copies (the same `copyWith` list), `createOwnCopyOfDefault` (the `FoodDraft(...)` it builds), `createCustomFood` and `updateCustomFood` (new named parameter `double? caloriesOverride`, passed into their `Food(...)`), `createCustomFoodFromDraft`. | `food_library_state.dart:976-1180,1276-1440` |
| D-25403 | The two screens that call the named update pass `caloriesOverride: draft.caloriesOverride` (`edit_food_screen.dart` `_save`, `add_food_screen.dart` `_persist`). | `edit_food_screen.dart:158-172`, `add_food_screen.dart:290-312` |
| D-25404 | `FoodForm`: a `_calories` controller and a `_caloriesEdited` flag. Auto mode (`_caloriesEdited` false): `_syncCalories()` writes the macro sum into the box on init and after every macro change (the macro boxes' `onChanged` already rebuilds: it calls `_syncCalories()` first). An edit mode food with an override opens `_caloriesEdited` true with its number. A user edit of the box (`onChanged`) sets `_caloriesEdited` true and never refills (a blank box stays blank: hint shows the macro sum, saves no override). `Use macros` sets `_caloriesEdited` false and refills. The draft's `caloriesOverride` is null unless `_caloriesEdited` and the box parses to a number whose rounded value differs from the macro sum. | `food_form.dart:196-376,465-497,876-890` |
| D-25405 | The old `Text('= N cal', key: food_form_calories)` line is replaced: new keys `food_form_calories_field` (the box, `TextFormField`, label `Calories (kcal)`, decimal keyboard, `DecimalInputFormatter`, select-all on focus, validator `Must be a number` like the macro boxes), `food_form_calories` (the quiet `Macros give N cal` line, shown only while overriding), `food_form_calories_reset` (the `Use macros` text button, shown with it). The unsaved-work probe needs no change (the box is a keyed `FormField`). | `food_form_unsaved_probe.dart` |
| D-25406 | Out of this plan: the bundled catalog numbers (plan 255), the watch (reads the stored food), any "last calories" memory. | — |

## Scenarios

Fixtures. A `FoodLibraryState` over Mock (and Hive for the stored ones) built as `test/food_library_state_test.dart` builds it; a `FoodDraft` helper with Beer's numbers (protein 0.5, carbs 3.6, fat 0, grams, reference 100 `ml`) and `caloriesOverride: 43`; the form pumped as `test/food_form_label_test.dart` pumps it (copy its `_pump...` helper; surface 600x1200).

Level A (state, plain `test()`, Mock and Hive twins):

| ID | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-25401 | `createCatalogFood(draft with 43)`; read the catalog food and the stored row | `caloriesOverride == 43` | the draft drops it |
| S-25402 | `createCustomFood(..., caloriesOverride: 43)` and `createCustomFoodFromDraft(draft)` | both stored with 43 | no parameter |
| S-25403 | `updateCustomFood(id, ..., caloriesOverride: 43)` on a food with none; then again with `caloriesOverride: null` | 43, then null (cleared) | the rebuild drops or keeps it |
| S-25404 | `updateCatalogFood(existing, draft with 43)`; then a draft with null | the catalog food holds 43 then null; a LINKED library copy (added with `addCatalogFoodToLibrary`) holds the same each time | the propagation forgets it |
| S-25405 | `createOwnCopyOfDefault(source, draft with 43, addToList: true)` | the new food (and its library row) holds 43 | the copy path builds a new draft without it |

Level B (form widget, Mock):

| ID | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-25406 | open a blank New Food form; type Fat `10` | the Calories box reads `90`; add Carbs `10`: `130`; no `food_form_calories_reset` | the box does not exist |
| S-25407 | type `43` in the box, then change Carbs | the box stays `43`; `food_form_calories` reads `Macros give N cal` with the current macro sum; `food_form_calories_reset` is shown | the macros would overwrite it |
| S-25408 | after S-25407 tap `Use macros` | the box shows the macro sum again; the note and button are gone; changing a macro moves the box again | no reset |
| S-25409 | fill the form with Beer's macros, type `43`, submit through the controller; capture the draft | `draft.caloriesOverride == 43`; protein/carbs/fat unchanged | the draft has no field |
| S-25410 | fill the form with macros summing to 90 and leave the box untouched; and a second form where the user types `90`; and a third where the box is cleared | all three drafts have `caloriesOverride == null` | an equal or blank value would store a pointless override |
| S-25411 | open EDIT on a food with `caloriesOverride: 43` | the box reads `43`; the note reads `Macros give 16 cal` | the edit form ignores the stored number |
| S-25412 | type `abc`-like input (a lone `.`): submit | validation error `Must be a number`; nothing saved | the box has no validator |

Existing tests that read the old line and must change: `test/food_form_label_test.dart` (the 7 uses of `food_form_calories`: lines about 386-420 and 671-695): they now read the box text through `food_form_calories_field`.

## Input-reality checklist

1. Writers: a `Food` is written by the form through `FoodLibraryState` (this plan carries the field through every path), the catalog loader and refresh (they do not know the field yet: plan 255; a refresh of a user-touched catalog food is skipped by the seed-touched marker, so a user's override survives).
2. Lifecycle: editing a food later changes only future rows; a default food saved as the user's copy keeps the number the user typed on the copy; clearing returns the food to computed.
3. Settings: none.
4. Time: none.
5. Cost: none.
6. Words: new copy `Calories (kcal)`, `Macros give N cal`, `Use macros`, `Must be a number` (existing) (owner to read).
7. Competition: the box and the macro boxes share the form: macros auto-fill the box only while untouched (S-25407); the serving choice does not touch it (the number is per the chosen serving, like the macros).

## Phases

1. **P1 builder-app**, scope `lib/core/models/food_draft.dart`, `lib/state/food_library_state.dart`, `lib/features/nutrition/edit_food_screen.dart`, `lib/features/nutrition/add_food_screen.dart`: D-25401..D-25403 (exact code in the brief). No full suite.
2. **P2 builder-app** (after P1), scope `lib/features/nutrition/widgets/food_form.dart`: D-25404, D-25405 (exact code in the brief).
3. **P3 builder-app** (after P2), scope `test/calories_field_state_test.dart` (new): S-25401..S-25405.
4. **P4 builder-app** (after P2, may run beside P3), scope `test/calories_field_form_test.dart` (new), `test/food_form_label_test.dart`: S-25406..S-25412 and the rewritten old reads.
5. **P5 lead**: readers, full suite, analyze, mutation pass, docs, reviewer.

## Readers

Tests that build `FoodDraft(`, call `updateCustomFood`/`createCustomFood`/`createCatalogFood`, pump `FoodForm` or the add/edit screens: `test/food_group_membership_test.dart`, `food_library_edit_test.dart`, `food_library_own_copy_test.dart`, `food_library_state_delete_guard_test.dart`, `food_library_state_test.dart`, `image_persistence_round_trip_test.dart`, `library_grouping_test.dart`, `library_merge_test.dart`, `library_row_toggle_test.dart`, `my_foods_unification_test.dart`, `picker_polish_test.dart`, `screen_widget_test.dart`, `food_form_label_test.dart`, `first_run_path_test.dart`, `header_standardization_test.dart`, `decimal_comma_input_test.dart`, `screen_overflow_contract_test.dart`.

## Mutation list (lead)

(a) `createCatalogFood` drops it (S-25401); (b) `createCustomFood` drops it (S-25402); (c) `updateCustomFood` drops it (S-25403); (d) `updateCatalogFood` drops it (S-25404); (e) the propagation to the linked copy drops it (S-25404); (f) `createOwnCopyOfDefault` drops it (S-25405); (g) the form never sends it (S-25409); (h) the macros keep overwriting an edited box (S-25407); (i) an equal value is stored as an override (S-25410); (j) `Use macros` does not reset (S-25408); (k) the edit form ignores the stored number (S-25411); (l) a blank box stores 0 (S-25410).

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| `docs/nutrition.md` | MODIFIED | The form that sets it follows in a later plan. | The food form's Calories (kcal) box sets it: it follows the macros until the user types a number of their own (a number equal to the macro sum, or a blank box, stores none), and a quiet `Macros give N cal` line with a `Use macros` button brings it back. | S-25406, S-25409 |
| `docs/widget_catalog/nutrition_widgets.md` | MODIFIED | Calories are derived, never stored: the line | Calories come from the macros unless the user types their own (plan 254): the Calories (kcal) box (key `food_form_calories_field`) | S-25406, S-25407 |

Stale-term sweep (lead): `grep -rIn "= N cal\|food_form_calories\|derived calories" docs` outside plans, history, releases: only `docs/widget_catalog/nutrition_widgets.md` (lines ~198-203). The lead rewrites that whole sentence (it also claims `calculateCalories` delegates to `caloriesFromMacros`, which plan 253 already made false) in one multi-line edit.

## As built

Added after the mutation pass and the review: S-25413 (a typed 0 is a real override: water), S-25414 (`FoodLibraryState.createFood(Food)` kept dropping the override: fixed with one line and a test), S-25415 (focusing the auto-filled box must not make a new food form look dirty). The unsaved-work probe (`food_form_unsaved_probe.dart`) was changed beyond the plan's D-25405 ("needs no change"): its controller listener now counts only a change of the TEXT as typing, because the select-all that runs when a box with text gets focus is a selection change and made an untouched New Food form show the "Unsaved changes" dialog. The `!_caloriesEdited` check in `_caloriesOverrideForSave` is redundant (an untouched box equals the macro sum, which stores no override) and its mutant stays alive.

## Open items

1. (owner) Typing a number that rounds to the macro sum (16.4 when the macros give 16) stores no override and shows no note; an override cannot equal the rounded macro sum.
2. (owner) The number is per the chosen serving, like the macros (the form does not convert it when the serving choice changes).
3. Plan 255: the bundled beer and wine numbers.
