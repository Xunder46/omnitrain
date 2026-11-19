# Plan 253 — A food can carry its own calories number (data and math)

Review item 17, first half (owner: "an optional calories field that overrides the sum, still autocomputed but can be edited alone without affecting anything"; "calories stay computed from the macros by default; you can overwrite the calories number alone; macros are not changed by it"). This plan is the DATA and the MATH: a food and a logged row can hold a calories number that replaces the macro sum everywhere calories are shown or added up. The form field that sets it is plan 254; fixing the bundled beer and wine numbers is plan 255.
Phone only. No wire change (the watch reads `caloriesPerServing` from `calculateCalories`, which now honours the override). Storage gains one optional field.

## Goal and acceptance

- `Food` has an optional `caloriesOverride` (kcal per the food's reference amount: per 100 g or per 1 item, like its macros). When it is null (every food today) nothing changes. When set, the food's calories are that number, not `protein x 4 + carbs x 4 + fat x 9`.
- A logged row (`ConsumedFood`) freezes the override with the rest of the snapshot at log time, so editing the food later never changes a past day, and a row's calories are `override x amount / reference amount` (rounded once, as now).
- Everything that adds calories up through those two reads follows: the day's ring total, the trend, the Stats nutrition averages and fuel signals (they sum `caloriesConsumed`), the logging row's calories caption, the watch's food list (`caloriesPerServing`).
- Macros, sodium and the macro donut never change because of the override.
- Old stored rows (no `calories_override` key) read back as no override.

Acceptance: S-25301..S-25309 green, the "fails without" ones red at the base commit; `flutter analyze` not above 178 issues, 0 errors; no new red in the full suite against the base failing set; the schema file stays valid SQL (`test/db_seed_test.dart`) and in step with the models; Docs delta applied.

## What the user sees

Nothing yet: no screen can set the number until plan 254. After 254: a food whose calories you typed (beer, 43 kcal per 100 ml) shows 43 on its row, adds 43 per 100 ml to the day, and keeps adding 43 for the days it was logged on even if you edit the food.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-25301 | `Food` gains `final double? caloriesOverride` (constructor, `fromMap` key `calories_override` via `(m['calories_override'] as num?)?.toDouble()`, `toMap`, `copyWith` with the file's own sentinel `_foodCopyWithUnset` so it can be cleared). `Food.calories` returns `(caloriesOverride ?? macroKcal(...)).round()`. | `models.dart:1975-2205` |
| D-25302 | `ConsumedFood` gains `final double? caloriesOverride` (constructor, `fromMap`/`toMap` key `calories_override`, `copyWith` with `??` like its neighbours). `caloriesConsumed` becomes `((caloriesOverride ?? macroKcal(...)) * (amountConsumed / referenceAmount)).round()`. | `models.dart:2220-2400` |
| D-25303 | The log-time snapshot copies it: `NutritionState` row builder adds `caloriesOverride: food.caloriesOverride`; `foodFromConsumedSnapshot` copies it back; `calculateCalories(Food)` returns `food.calories`. | `nutrition_state.dart:495-530`, `food_helpers.dart:28,119` |
| D-25304 | `scripts/sqlite_schema.sql` gets `calories_override REAL` (nullable, comment: kcal per reference amount, overrides the macro sum, NULL = computed) on `app_food`, `app_food_catalog` and `app_consumed_food`, so every `toMap` key is a column. No migration (the Hive maps are schemaless; a missing key reads as null). | `sqlite_schema.sql:1245-1261,1318-1335,1410-1432`, `test/db_seed_test.dart` |
| D-25305 | Out of this plan: `FoodDraft` and the form (plan 254), the bundled catalog numbers (plan 255), the macro-percent labels (they stay macro based). | — |

## Scenarios

Fixtures. `Food` Beer: `unitType: grams`, `referenceAmount: 100`, `referenceLabel: 'ml'` (use `g` if the type requires), protein 0.5, carbs 3.6, fat 0 (macro sum 16.4 kcal -> 16), `caloriesOverride: 43`. Rice: 10P/10C/10F per 100 g, no override (170 kcal). Mock AND Hive through `harnessFactories` for the stored-roundtrip scenarios; model scenarios are pure.

| ID | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-25301 | `Food` Beer with and without the override | `calories` 43 with it, 16 without; Rice 170 | no field |
| S-25302 | `Food.toMap` then `Food.fromMap` of Beer, and of a map with no `calories_override` key | override 43.0 preserved; the key-less map gives `caloriesOverride == null` and macro-sum calories | no key / back-compat |
| S-25303 | `Food.copyWith(caloriesOverride: null)` on Beer; `copyWith()` with no argument; `copyWith(caloriesOverride: 50)` | null; still 43; 50 | clearing is impossible without the sentinel |
| S-25304 | `ConsumedFood` of Beer, 250 ml (`amountConsumed: 250`, reference 100) with override 43 and without | `caloriesConsumed` 108 (43 x 2.5 = 107.5, rounded once: 108) and 41 (16.4 x 2.5 = 41) | consumed math ignores it |
| S-25305 | `ConsumedFood.toMap` / `fromMap` roundtrip with the override and a key-less map | preserved; null on the key-less map | no key |
| S-25306 | `NutritionState.logConsumedFood(beer, 250)` (Mock and Hive), then `state.todayConsumedCalories` | 108; the stored row holds `caloriesOverride` 43; THEN edit the library food's override to 100 (`repo.updateFood(beer.copyWith(caloriesOverride: 100))`) and re-read the day: still 108 (frozen) | the snapshot would not freeze it |
| S-25307 | the day totals: `NutritionDayTotals.of([beerRow (override 43, 250 ml), riceRow (200 g)])` | calories 108 + 340 = 448; protein/carbs/fat/fiber/sodium sums equal the macro-only math (the override changes calories only) | totals use macros |
| S-25308 | `calculateCalories(beer)` and the watch food payload (`watch_reference_sync.dart`'s `caloriesPerServing` for a food list holding beer: use the existing builder test's harness) | 43 | the watch would still show 16 |
| S-25309 | Stats: `StatsProgressService` nutrition series for a day with the beer row (`stats_progress_service.dart:2089`, `dayCalories`): the day's calories | 108 for the beer row | stats use macros |

## Input-reality checklist

1. Writers: a `Food` is written by the food form (plan 254), the catalog loader, `FoodLibraryState`; a `ConsumedFood` by `NutritionState` (`logConsumedFood*`, past-day edits, the wrist bridge). Only the log-time snapshot sets the row's field. Units: kcal per reference amount.
2. Lifecycle: a food edited or deleted later keeps its rows' frozen override; a row logged before this change has no override and keeps its macro-sum calories; removing the override from a food affects only future rows.
3. Settings: none.
4. Time: a past day never changes (frozen snapshot).
5. Cost: none (one more field in maps).
6. Words: none (no UI in this plan).
7. Competition: the macro donut and percent labels still read macros (an override that disagrees with the macros is the point of the feature); the day target and the ring compare `caloriesConsumed` totals against the calories target.

## Phases

1. **P1 builder-data**, scope `lib/data/models/models.dart`, `lib/core/utils/food_helpers.dart`, `lib/state/nutrition_state.dart`, `scripts/sqlite_schema.sql`: D-25301..D-25304 (exact code in the brief). No full suite.
2. **P2 builder-app** (after P1), scope `test/calories_override_test.dart` (new): S-25301..S-25309.
3. **P3 lead**: readers, full suite, analyze, mutation pass, docs, reviewer.

## Readers

Every test that builds `Food` or `ConsumedFood` positionally or checks their `toMap` keys: `test/models_test.dart`, `test/db_seed_test.dart` (schema vs models), `test/nutrition_*`, `test/watch_nutrition_*`, `test/stats_*nutrition*`, `test/food_*`, `test/state_test.dart`. The new field is optional and named, so no caller breaks; tests that compare whole `toMap()` outputs gain one key (`calories_override: null`): the lead runs the readers after P1 and lists them.

## Mutation list (lead)

(a) `Food.calories` ignores the override (S-25301); (b) `fromMap` ignores the key (S-25302); (c) `toMap` omits it (S-25302); (d) copyWith cannot clear (S-25303); (e) `caloriesConsumed` ignores it (S-25304); (f) the log-time snapshot does not copy it (S-25306); (g) `calculateCalories` uses macros (S-25308); (h) rounding per row instead of once (S-25307).

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| `docs/nutrition.md` | ADDED | - | `caloriesOverride` | S-25301, S-25304, S-25306 |

The lead adds one short paragraph to `docs/nutrition.md` (46.9 KB, below the size band) where it explains how calories are computed: a food or a logged row can hold its own calories number that replaces the macro sum, frozen into each logged row; macros are unaffected; the form to set it follows (plan 254). `docs/data_models.md` (52.9 KB) and `docs/db_integration.md` (52.3 KB) are in the size band and are NOT touched; the schema file carries its own comment.

## As built

Added after the lead's mutation pass and the review: S-25310 (the display food of a logged row keeps its frozen override: the mutant that dropped it in `foodFromConsumedSnapshot` survived) and S-25306b (an amount change keeps the frozen override). Stale sentences the review found were corrected: two in `docs/data_models.md` (edited in place, the file stays in the size band), the banner above `Food` and two helper comments.

## Open items

1. The form field and the pass-through (`FoodDraft`, `FoodLibraryState`) are plan 254: until then nothing can set an override.
2. The bundled catalog's beer and wine numbers are plan 255.
3. `FoodLibraryState.createFood(Food)` rebuilds a food field by field and would drop an override; it has no caller in `lib` today. Plan 254 (the form pass-through) must route every create and update through a path that carries `caloriesOverride`.
