# Review: plan 254 · calories field in food form · a2c82b3f..working tree
Verdict: APPROVE WITH FIXES
Counts: blocker 0 · major 3 · minor 4 · tests: not re-run here (per brief: the lead ran the full suite; the 43 new/rewritten tests pass; `flutter analyze` at baseline 178, 0 errors)
Diff vs Predicted Files: outside: `test/food_catalog_load_test.dart` (1 line, see finding 7); the plan file itself is expected. All other changed paths match the plan.

## Findings

1. [Major] `lib/features/nutrition/widgets/food_form.dart:366` + `lib/widgets/inputs/select_all_on_focus.dart:156` + `lib/features/nutrition/widgets/food_form_unsaved_probe.dart:88` — focusing the auto-filled Calories box marks an untouched New Food dirty. The box is pre-filled in auto mode (`_syncCalories()` in `initState` writes the macro sum, asserted by the rewritten `S-92c.3` as `'0'`), so it is the only field on a new-food form with non-empty text; `bindSelectAllOnFocus` selects it on focus, the selection assignment notifies the controller, the probe's `_onTyped` listener sets `_typed = true`, and `_attemptExit` (edit_food_screen.dart:111) shows the "Unsaved changes" dialog for a form the user never typed into. On the same form, focusing a macro box does not do this — the boxes are empty and the select-all listener returns early on empty text — so the behaviour is new and asymmetric. (On an edit form the pre-existing macro boxes already behave this way; this diff extends it to the create form.) Fix: smallest change is in the probe — make `_onTyped` set `_typed` only when the controller's text actually changed from the last value it reported (track last text per hooked controller), so selection-only notifications do not count. Guard: a widget test pumping a New Food with a probe, focusing `food_form_calories_field`, asserting `!probe.isDirty`.
2. [Major] Stale doc sentences the plan's stale-term sweep missed — three behaviour sentences are now false:
   - `docs/widget_catalog/nutrition_widgets.md:82` — "Calories are derived from the macros, never stored on `Food`" (LogFoodRow section): false since plan 253 (`Food.caloriesOverride`, `calories_override` column) and plan 254 (the form stores it).
   - `docs/nutrition.md:147` — "a live `= <N> cal` line": the line no longer exists (replaced by the box).
   - `docs/nutrition.md:325` — "a live `= <N> cal` line from `caloriesFromMacros`": same.
   The lead's sweep pattern (`= N cal|food_form_calories|derived calories`) cannot match `= <N> cal` or "derived from the macros, never stored". Fix: rewrite the three sentences (the form box follows the macros and may store an override). Guard: widen the sweep pattern to `= <N> cal|never stored` and re-run it.
3. [Major] `lib/state/food_library_state.dart:461-484` — `createFood(Food)` rebuilds the Food field-by-field and silently drops `caloriesOverride`. It is the one remaining site that turns a Food into a Food without carrying the field (every draft path carries it; `foodFromConsumedSnapshot` at food_helpers.dart:124 and the `ConsumedFood` freeze at nutrition_state.dart:522 do). No production caller in `lib/` today (tests and a debug main only), but any future call with an override-bearing Food loses the number with no error — against the plan's "every path" goal. It also already dropped `catalogId` before this plan (pre-existing, noted here only as the same shape of bug). Fix: one line, `caloriesOverride: food.caloriesOverride,` in the rebuild. Guard: extend `test/calories_field_state_test.dart` with a `state.createFood(food with 43)` case (red today).
4. [Minor] `lib/features/nutrition/widgets/food_form.dart:945-951` + the two new doc sentences — a typed value that ROUNDS to the macro sum is silently discarded. Type `16.4` while the macros give 16: `_caloriesOverrideForSave` returns null (`typed.round() == _macroCalories`), the note does not appear (`overriding` uses the same rounding), save stores no override, and the box reads 16 on reopen. Plan-conformant (D-25404, open item 1 — an override cannot be (rounded-)equal to the sum), but both doc sentences say only "a number equal to the macro sum" (docs/nutrition.md:576, docs/widget_catalog/nutrition_widgets.md:204), which is false for 16.4. Fix: say "equal to the rounded macro sum" in both sentences, or show the `Macros give 16 cal` note whenever the raw typed value differs.
5. [Minor] Missing coverage for the explicit-zero override (brief question 3). Nothing exercises typing `0` into the box while the macros sum above 0 (water: macros 16, calories 0). Code-wise it works (`parseDecimal('0')` → `0.0`, `round() != macro` → override 0 stored; `Food.calories` reads it through `??`, models.dart:2088, so no falsy zero trap), but no test would fail if someone special-cased `typed == 0 → null`. Guard: extend S-25409 with a water case asserting `draft.caloriesOverride == 0.0` and a day total of 0.
6. [Minor] `docs/nutrition.md:573-577` — the new form-behaviour sentence sits inside a paragraph whose tail reads "Verified by `test/calories_override_test.dart` (`S-25301` to `S-25310`)". Those scenarios cover the stored half (getter, map roundtrip, copyWith, frozen rows, day totals), not the box. A maintainer chasing the form behaviour finds no pointer to `test/calories_field_form_test.dart`. Fix: add "and the box by `test/calories_field_form_test.dart` (`S-25406`..`S-25412`)" to the sentence.
7. [Minor] `test/food_catalog_load_test.dart:270` — changed outside the brief's path list (`fat!` → `fat`), not named by the plan (Predicted Files) or the brief. Presumably analyze hygiene after plan 253 made `fat` non-nullable; harmless, but it is an unlisted change — the lead should name it in the plan (or the governor note) so the scope check passes cleanly.

## Assumption Log rulings
- Open item 1 ("an override cannot be exactly equal to the macro sum"): ratified as implemented, with the rounding nuance recorded in finding 4 — the doc wording is the fix, not the code.
- Open item 2 (the number is per the chosen serving): ratified — the serving control never rewrites the macro boxes (no `.text =` on them anywhere in food_form.dart), so the box cannot go stale on a serving change either.
- Plan fact "the unsaved-work probe needs no change (the box is a keyed FormField)" (D-25405, backed by food_form_unsaved_probe.dart): partially wrong — see finding 1; the keyed-FormField part holds, the no-change claim does not.

## Input-reality checklist (checked against code/tests)
1. Writers: the five form paths carry the field (verified in diff); `createFood` does not (finding 3); catalog loader/refresh do not know the field and `updateCatalogFood` marks the row seed-touched (food_library_state.dart:1019) so a refresh skips it; the watch bridge carries no calories at all (no wire change, D-25406 — out of scope by decision).
2. Lifecycle: edits change future rows only; the log freeze carries the override at log time (nutrition_state.dart:522); clearing returns the food to computed (S-25403/S-25404 null branches).
3. Settings: none touched.
4. Time: none.
5. Cost: `_macroCalories` recomputed per build only; negligible.
6. Words: found by grep (not memory) — the three stale sentences in finding 2; `Use macros` / `Macros give` appear nowhere else in docs.
7. Competition: the box and the macro boxes share the form; the macros auto-fill the box only while untouched, asserted by S-25407 (a test that fails if the macros overwrite an edited box).

## Scenario coverage
S-25401 -> test/calories_field_state_test.dart · S-25401 createCatalogFood (Mock+Hive)
S-25402 -> test/calories_field_state_test.dart · S-25402 createCustomFood + FromDraft
S-25403 -> test/calories_field_state_test.dart · S-25403 set then clear
S-25404 -> test/calories_field_state_test.dart · S-25404 catalog + linked copy + clear both
S-25405 -> test/calories_field_state_test.dart · S-25405 own copy of default
S-25406 -> test/calories_field_form_test.dart · S-25406 (box exists and follows; reset absent)
S-25407 -> test/calories_field_form_test.dart · S-25407 (box stays 43; note text; reset shown)
S-25408 -> test/calories_field_form_test.dart · S-25408 (reset restores auto mode)
S-25409 -> test/calories_field_form_test.dart · S-25409 (draft carries 43)
S-25410 -> test/calories_field_form_test.dart · S-25410 (untouched / equal / cleared → null)
S-25411 -> test/calories_field_form_test.dart · S-25411 (edit opens on 43, saves 43)
S-25412 -> test/calories_field_form_test.dart · S-25412 (lone dot rejected, nothing saved)
Rewritten old reads -> test/food_form_label_test.dart · S-92c.1, S-92c.13, the two `faint 0` assertions
No scenario in the plan lacks a test that would fail without the change. Untested scenarios outside the plan's list: finding 1 (probe), finding 5 (typed zero).

## Docs delta
docs/nutrition.md MODIFIED -> applied
docs/widget_catalog/nutrition_widgets.md MODIFIED -> applied
Doc edits the table does NOT name: the three stale sentences in finding 2 (nutrition_widgets.md:82, nutrition.md:147, nutrition.md:325), and the verification pointer in finding 6.

## Lead dispositions

1. Major (focusing the auto-filled box made a new food form look dirty): FIXED in the probe (only a text change counts as typing), S-25415 and mutant p killed.
2. Major (three stale doc sentences the plan's sweep pattern missed): FIXED (`docs/nutrition.md` two, `docs/widget_catalog/nutrition_widgets.md` one); re-swept with `= <N> cal` and `never stored`.
3. Major (`createFood(Food)` dropped the override): FIXED with one line; S-25414, mutant q killed. Its pre-existing drop of `catalogId` is not part of this plan.
4. Minor (a typed value that rounds to the macro sum is discarded silently): documented as "rounds to the macro sum" in both sentences and in the plan's open item 1.
5. Minor (no test for an explicit zero): FIXED by S-25413, mutant r killed.
6. Minor (the doc sentence pointed only at the stored-half tests): FIXED, it now names the form and state tests.
7. Minor `test/food_catalog_load_test.dart:270`: not this plan's change; already modified before the unit started (the owner's), left unstaged.
