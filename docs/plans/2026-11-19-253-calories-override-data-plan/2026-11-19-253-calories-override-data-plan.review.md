# Review: plan 253 (a food can carry its own calories number: data and math) · P1+P2 · 8e1b2838..working tree
Verdict: APPROVE WITH FIXES
Counts: blocker 0 · major 1 · minor 5 · tests: 15 passed / 0 failed (`test/calories_override_test.dart`, lead's run per brief; full suite not re-run per brief) · analyze 178, 0 errors (baseline, per brief)
Diff vs Predicted Files: outside: `test/food_catalog_load_test.dart` (1 line, finding 5)

## Findings

1. [Major] `docs/data_models.md:420,463` — "`calories`: computed as `(protein * 4 + carbs * 4 + fat * 9).round()`" and the consumed-formula sentence are now false for a food or row carrying `calories_override`: a maintainer reading the model doc would conclude a stored calories number cannot exist. The plan's Docs delta pre-decided `data_models.md` is not touched (size band), but the sentence is false as of this change. Fix (smallest, next time the doc is edited or in plan 254): add "unless the food carries `calories_override` (plan 253)" to both sentences. Guard: the paragraph `docs/nutrition.md:570-577` states the true behaviour.
2. [Minor] `lib/core/utils/food_helpers.dart:19-25` — `calculateCalories`'s doc comment still claims "Formula: protein * 4 + carbs * 4 + fat * 9 … Delegates to [caloriesFromMacros] so there is one formula (D-92c.1)", but the body now returns `food.calories` and delegates to nothing; the diff added the plan-253 sentence but left the false delegation claim. Fix: drop or reword the "Formula"/"Delegates" sentences.
3. [Minor] `lib/core/utils/food_helpers.dart:8-10` — `caloriesFromMacros`'s doc: "The food form's live calories line calls this directly, so the line and every stored food render the same number." Now false whenever a food carries an override (form line shows the macro sum, the stored food shows 43). Plan 254 owns the form; until then the sentence should say "every stored food without a `caloriesOverride`". Fix: one-line qualification.
4. [Minor] `lib/data/models/models.dart:1972-1973` — banner comment "Calories are computed (not stored): protein * 4 + carbs * 4 + fat * 9" is made false by this diff and was not touched. Fix: "…unless the food carries a `caloriesOverride` (plan 253)".
5. [Minor] `test/food_catalog_load_test.dart:270` — outside the plan's predicted files: `withSkin.fat!` → `withSkin.fat` on a non-nullable field, no behaviour change, and the plan says nothing about it. If this was an analyze-baseline cleanup to reach 178/0 errors, note it in the plan; otherwise revert.
6. [Minor] `test/calories_override_test.dart` (S-25306 group) — no test asserts a row keeps its frozen override across an amount edit. Verified by reading that `logConsumedFoodAt` (`lib/state/nutrition_state.dart:607-616`), `logConsumedFoodOnDay`'s same-day update (`:664-669`) and `setLoggedAmountViewed` (`:891-916`) all rebuild via `ConsumedFood.copyWith(amountConsumed:)`, whose `??` preserves the override — but a mutation that replaced `copyWith` with a field-by-field rebuild would not be killed by any existing test. Fix: in the stored S-25306 group, after the freeze asserts, `await state.logConsumedFoodAt(beer, 500)` and expect the row's `caloriesConsumed` 215 and `caloriesOverride` 43.

No Blockers. The override reaches every calorie surface that matters today: `Food.calories` (`models.dart:2085-2090`), `calculateCalories` (`food_helpers.dart:27-29`, which the watch payload reads at `watch_reference_sync.dart:892`), `ConsumedFood.caloriesConsumed` (`models.dart:2322-2326`), and all day-level sums read `caloriesConsumed` (`nutrition_state.dart:107`, `nutrition_day_totals.dart:26`, `stats_progress_service.dart:2089`). The watch (Swift `WatchFoodCatalog.calories(at:)` and the phone mirror `watch_food_catalog.dart:62`) has no macro math — it only multiplies the payload's `caloriesPerServing`. The remaining macro-sum sites are intended macro-based (`calorie_ring_card.dart:155-157` donut, `macro_targets.dart:63` targets, `nutrition_state.dart:1068-1098` macro gram sums) or are the food form's live line (`food_form.dart:649`), which plan 254 owns.

Q2 answer: every `Food` construction that must carry an override forward does — `Food.copyWith` uses the sentinel (`models.dart:2198-2201`), catalog propagation builds via `copyWith` (`food_library_state.dart:826-845, 851-870, 930-936`), the snapshot builder copies it (`nutrition_state.dart:520-521`) and `foodFromConsumedSnapshot` copies it back (`food_helpers.dart:128`). The draft/named-field rebuilders (`food_library_state.dart:462, 1077, 1293, 1397`) take a `FoodDraft` or named fields that have no override parameter yet, so they cannot drop what they never receive; `FoodLibraryState.createFood(Food food)` (`:462-485`) is the one state API that takes a full `Food` and rebuilds it field-by-field, silently dropping `caloriesOverride` — it has no callers in `lib` today and no writer can set an override until plan 254, so no user-visible failure now, but plan 254 must add the pass-through there. `catalog_refresh_service.dart` only rewrites bundled catalog rows gated by the seed-touched marker (`:228-241`), so it cannot drop a user's override. Hive legacy/int reads are safe: `(m['calories_override'] as num?)?.toDouble()` (`models.dart:2127, 2345`).

Q3 answer: no path needs to clear a row's override. Removing the override from a food affects only future rows by the frozen-snapshot contract, and the amount-edit paths preserve the row's value (see finding 6). `ConsumedFood.copyWith`'s `??` is therefore correct; `Food.copyWith`'s sentinel is what the clearing path (plan 254's form) will use, and S-25303 proves it.

## Assumption Log rulings
No assumption log in the plan; none in the diff. The plan is small (one field, one formula swap) — no entries needed.

## Scenario coverage
S-25301 → test/calories_override_test.dart · `S-25301 the override replaces the macro sum; without it the sum stands`
S-25302 → test/calories_override_test.dart · `S-25302 a stored override survives the roundtrip` + `S-25302 a map with no calories_override key reads as no override (old rows)`
S-25303 → test/calories_override_test.dart · `S-25303 an explicit null clears it; no argument keeps it; a new number replaces it`
S-25304 → test/calories_override_test.dart · `S-25304 250 ml of the 43-kcal beer is 108 (107.5 rounds once); without the override 41`
S-25305 → test/calories_override_test.dart · `S-25305 a frozen override survives the roundtrip` + `S-25305 a map with no calories_override key reads as no override`
S-25306 → test/calories_override_test.dart · Mock and Hive twins · `S-25306 logging the beer freezes the override into the row, and editing the library food later never changes the day`
S-25307 → test/calories_override_test.dart · `S-25307 the day totals add 108 + 340 = 448, and every macro total equals the macro-only math`
S-25308 → test/calories_override_test.dart · `S-25308 calculateCalories returns the override, not the macro sum` + `S-25308 the foods_down payload carries the override as caloriesPerServing`
S-25309 → test/calories_override_test.dart · Mock and Hive twins · `S-25309 the day whose row holds the override totals 108`
S-25310 (extra, not in the plan; documented in `docs/nutrition.md`) → test/calories_override_test.dart · `S-25310 the display food of a logged row keeps its frozen override`

All 15 tests assert behaviour with concrete numbers (43 / 16 / 108 / 41 / 448 / 381 / 340 / 170), not presence. The two assertions the brief asks about would fail on the corresponding mutation: if the log-time snapshot did not copy the override, S-25306's first expect reads 41, not 108; if the Stats series used macros, S-25309's trend row reads 41, not 108.

## Docs delta
docs/nutrition.md ADDED `caloriesOverride` -> applied (paragraph at :570-577; names `Food.calories`, `calculateCalories`, `caloriesPerServing`, `ConsumedFood.caloriesConsumed` and `test/calories_override_test.dart` `S-25301` to `S-25310`, all of which exist; every behaviour claim above was verified in code this run)
docs/data_models.md (not named by the table, deliberately per plan) -> sentences at :420 and :463 now incomplete for overridden foods -> finding 1

## Lead dispositions

1. Major (`docs/data_models.md` two sentences false for an override): FIXED in place (two clauses added; the file stays in the size band, no new lines).
2. Minor `calculateCalories` doc claimed a delegation that is gone: FIXED (reworded).
3. Minor `caloriesFromMacros` doc said every stored food renders the same number: FIXED (qualified, "without an override").
4. Minor banner comment above `Food` ("Calories are computed (not stored)"): FIXED.
5. Minor `test/food_catalog_load_test.dart:270`: not this plan's change; already modified before the unit started (the owner's), left unstaged.
6. Minor (no test that an amount edit keeps the frozen override): FIXED by S-25306b.
Note: the review's side finding that `FoodLibraryState.createFood(Food)` would drop an override (no caller today) is recorded as open item 3 of the plan for plan 254.
