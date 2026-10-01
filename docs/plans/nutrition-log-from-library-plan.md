# Feature: Log a Food as Consumed from the Library

## Overview

From the food library on the nutrition page, the user marks a food as consumed
and sets the amount **in the food's own unit** (a count for count-type foods,
grams for grams-type foods). The contribution to today's totals equals the
food's stored per-reference macros scaled by `amount / referenceAmount` (e.g.
3 of a "per 1 egg" food contributes 3×; 150 g of a "per 100 g" food contributes
1.5×).

The per-row affordance is a **checkbox on the left** to toggle the food in
or out of today's log, plus an **amount input on the right** that holds the
amount in the food's own unit. The food's preset reference label
("per 100 g" / "per 1 egg") is rendered as a small caption **beneath** the
amount input. The deletion affordance is **out of scope** for this iteration
— it will be redesigned in a follow-up.

When a food is logged, a frozen `ConsumedFood` snapshot is persisted that
captures the food's name, unit type, reference, macros, and the daily targets
in effect that day. The logged entry must not read live from the library or
current targets afterwards. The calorie ring and totals update live as foods
are logged or amounts change.

> **2026-06-10 revision**: The amount field is the **entered unit value**,
> not a multiplier — for a per-100 g food, `150` means "150 g" (1.5× the
> reference); for a per-1-egg food, `3` means "3 eggs" (3× the reference).
> The reference label moves from the middle of the row to a small caption
> beneath the amount input. Editing the amount on an already-logged row
> auto-commits the new amount to the day log (debounced) so the ring and
> totals update live without requiring a checkbox re-tap.

The data layer is already in place (model, repository, mock + hive, SQLite
schema — all from the prior `nutrition-data-audit` and `nutrition-page-calories-ring`
plans). This plan ships the **state wiring + UI affordance** to expose that
capability to the user.

## Requirements

- R-1. Every food row in the food library card on the nutrition page has:
  - a **checkbox** on the left indicating whether the food is in today's
    log (checked = logged today, unchecked = not logged today);
  - the existing food name + macro string in the middle;
  - an **amount input** on the right (numeric `TextField`) holding the
    amount in the food's own unit (integer for count foods, decimal for
    grams);
  - the food's **reference label** ("per 100 g" / "per 1 egg") rendered
    as a small caption **beneath** the amount input (not in the middle
    of the row).
  The checkbox is the primary "mark consumed" affordance; tapping it
  logs the food at the current amount (or unlogs it). Editing the
  amount on a logged row auto-commits the new amount to the day log
  (see R-5).
- R-2. The amount input's default value is `1` for count foods and `100`
  for grams foods. When the user first taps the checkbox, the food is
  logged at the current amount input value.
- R-3. The amount is the **entered unit value** (not a multiplier). The
  contribution to today's totals is
  `(per-reference macros) × (amount / referenceAmount)`. Examples:
  - 150 g of a per-100 g food (31P / 0C / 3F = 151 kcal):
    `151 × (150 / 100) = 151 × 1.5 = 226.5`.
  - 3 of a per-1-egg food (6P / 1C / 5F = 73 kcal):
    `73 × (3 / 1) = 73 × 3 = 219`.
  Same scaling applies to protein/carbs/fat (grams).
- R-4. On log, a `ConsumedFood` snapshot is built that freezes:
  - food name, unit type, reference amount, reference label, protein,
    carbs, fiber, fat, sodium;
  - group id + name (snapshotted via lookup; nullable if the group is
    gone);
  - today's daily target values (calories/protein/carbs/fat);
  - the consumed amount.
  The snapshot is persisted via `repository.createConsumedFood` (on
  initial log) or `repository.updateConsumedFood` (on amount change).
- R-5. **Live auto-commit on amount edit.** After logging or updating,
  the `NutritionState.consumedToday` cache is updated and
  `notifyListeners()` fires so the `CalorieRingCard` and the totals
  rebuild without an explicit reload. The amount field is **debounced**
  (~250 ms after the last keystroke) before the row is re-committed to
  the repository, so the user can type freely without hammering the
  repository on every keystroke. While the food is logged today,
  editing the amount auto-commits via
  `NutritionState.logConsumedFoodAt` (which is the day-uniqueness
  update path) — the user does NOT need to re-tap the checkbox.
- R-6. A food can have **at most one** `ConsumedFood` row per day
  (uniqueness by `(sourceFoodId, dateMs)`). The state layer enforces
  this: toggling the checkbox on a food that is already logged updates
  the existing row; toggling it off deletes the row. Editing the amount
  updates the existing row in place.
- R-7. The `CalorieRingCard` rebuilds live (consumed value updates
  without an explicit reload call).
- R-8. The consumed-food entry is **frozen**: editing the source food's
  macros, archiving/deleting the source food, renaming the source group,
  or changing today's daily targets must not alter an already-logged
  entry (the snapshot pattern is enforced by `ConsumedFood` reading only
  its own fields, not the live `Food`).
- R-9. Amount input validation: must be `> 0` and finite. Both
  count and grams foods accept any positive value (whole numbers
  and decimals). The row's checkbox stays enabled but logging is a
  no-op (with an inline error) while the input is empty, non-numeric,
  zero, or negative.
- R-10. UI uses the existing `OmniTheme` button tokens (icon-only
  affordances sized to `buttonIconSize × buttonIconSize`); every
  `FilledButton`/`OutlinedButton`/`TextButton` has an explicit `shape:`
  override (no Material 3 StadiumBorder default). The checkbox is a
  stock Flutter `Checkbox` (themed via `theme.colorScheme`).
- R-11. **No deletion affordance** in this iteration. Removing a food
  from today's log is done by unchecking the row's checkbox. A
  dedicated delete UI is a follow-up.

## Acceptance Criteria
auto-commits
      the new amount (debounced) to the existing
      `ConsumedFood.amountConsumed`; the row's checkbox remains
      checked; the ring/totals update live without a checkbox
      re-tap. The amount field is the **entered unit value** (not
      a multiplier); the reference label renders as a small caption
      **beneath** the amount input per-100 g macros to
      today's totals.
- [ ] AC-2. Tapping the checkbox on a count-type food (per 1 egg) with
      `amount = 3` contributes `3×` the food's per-1-egg macros to
      today's totals.
- [ ] AC-3. After logging, `nutritionState.consumedToday` contains the
      new snapshot and `nutritionState.todayConsumedCalories` reflects
      the scaled total.
- [ ] AC-4. The `CalorieRingCard` rebuilds (consumed value updates)
      without an explicit reload call.
- [ ] AC-5. Changing the amount input on a logged row updates the
      existing `ConsumedFood.amountConsumed`; the row's checkbox
      remains checked; the ring/totals update live.
- [ ] AC-6. Unchecking a logged row removes the `ConsumedFood` row
      from the cache and the repository; the ring/totals update live.
- [ ] AC-7. After logging, editing the source food's protein (via the
      repository) leaves the existing `ConsumedFood.protein`
      unchanged.
- [ ] AC-8. After logging, archiving/removing the source food leaves
      the existing `ConsumedFood` row unchanged (snapshot preserved).
- [ ] AC-9. After logging, updating today's daily target values leaves
      the existing `ConsumedFood.targetCalories` (etc.) unchanged.
- [ ] AC-10. A food can have at most one `ConsumedFood` row per day;
      re-toggling the checkbox on an already-logged row updates
      (not duplicates) the existing row.
      fractional values (e.g. `0.5`) are accepted for both count
      and grams foods; logging is blocked only while the input is
      empty, non-numeric, zero, or negativend negative values; logging
      is blocked while the input is invalid (inline error).
- [ ] AC-12. Every button-shaped widget in the consume flow has an
      explicit `shape:` override; icon affordances sized to
      `buttonIconSize`; checkbox themed via `theme.colorScheme` /
      `OmniTheme.colors` only; no hardcoded colors.

## Scenarios

### S-001: Mark grams-type food consumed at 150 g
- Trigger: User taps the checkbox on `Chicken Breast` (per 100 g,
  31P / 0C / 3F = 151 kcal) and types `150` in the amount input.
  The amount is the **entered unit value** (grams), not a multiplier:
  150 in the field means 150 g consumed, which scales 1.5× against
  the per-100 g reference.
- Precondition: `Chicken Breast` exists in the library with
  `unitType = grams`, `referenceAmount = 100.0`,
  `referenceLabel = "per 100 g"`. No existing logs for today.
- Flow:
  1. The row renders with the checkbox unchecked, the amount input
     pre-filled to `100` (default for grams), and the reference label
     "per 100 g" rendered as a small caption **beneath** the input.
  2. User clears the amount, types `150`.
  3. User taps the checkbox.
- Expected outcome:
  - A `ConsumedFood` snapshot is persisted with
    `name = "Chicken Breast"`, `unitType = grams`,
    `referenceAmount = 100.0`, `referenceLabel = "per 100 g"`,
    `protein = 31`, `carbs = 0`, `fat = 3`,
    `amountConsumed = 150.0`.
  - `consumedToday.length == 1`.
  - `todayConsumedCalories == (31*4 + 0*4 + 3*9) * (150 / 100) == 226`
    (151 × 1.5).
  - The checkbox is now checked; the ring shows the new consumed
    value.
- Edge case of: none.

### S-002: Mark count-type food consumed at 3
- Trigger: User taps the checkbox on `Egg` (per 1 egg, 6P / 1C / 5F
  = 69 kcal) and types `3` in the amount input.
- Precondition: `Egg` exists with `unitType = count`,
  `referenceAmount = 1.0`, `referenceLabel = "per 1 egg"`.
- Flow:
  1. The row renders with the checkbox unchecked, the amount input
     pre-filled to `1` (default for count), and the reference label
     "per 1 egg" visible.
  2. User types `3`.
  3. User taps the checkbox.
- Expected outcome:
  - `ConsumedFood` persisted with `unitType = count`,
    `referenceAmount = 1.0`, `referenceLabel = "per 1 egg"`,
    `protein = 6`, `carbs = 1`, `fat = 5`,
    `amountConsumed = 3.0`.
  - `consumedToday.length == 1`.
  - `todayConsumedCalories == (6*4 + 1*4 + 5*9) * 3 == 207`.
  - The checkbox is checked; the ring shows the new consumed value.
- Edge case of: none.

### S-003: Totals equal sum of scaled snapshots across multiple foods
- Trigger: User logs `Chicken Breast` at 150 g **and** `Egg` at 3 on
  the same day.
- Precondition: Both foods exist; today has no prior logs.
- Flow:
  1. Log `Chicken Breast` at 150 g via its checkbox.
  2. Log `Egg` at 3 via its checkbox.
- Expected outcome:
  - `consumedToday.length == 2`.
  - `todayConsumedCalories == 226 + 207 == 433`.
  - `todayConsumedProtein == (31 * 1.5).round() + (6 * 3).round()
    == 47 + 18 == 65` (rounded; per the existing
    `ConsumedFood.caloriesConsumed` rounding style).
  - `todayConsumedCarbs == 0 + 3 == 3`.
  - `todayConsumedFat == (3 * 1.5).round() + (5 * 3).round()
    == 5 + 15 == 20`.
  - Both row checkboxes are checked; the ring and totals reflect the
    **sum**.
- Edge case of: S-001, S-002.

### S-004: Logged entry is frozen — editing the source food does not change it
- Trigger: User logs `Chicken Breast` at 150 g, then the user edits
  the source food to have `protein = 50` (instead of 31).
- Precondition: `Chicken Breast` is logged. The test edits via the
  repository directly to simulate any UI edit.
- Flow:
  1. Log `Chicken Breast` at 150 g via
     `NutritionState.logConsumedFood(food, 150)`.
  2. Update the food in the repository: `protein = 50`.
  3. Reload today's consumed foods from the repository.
- Expected outcome:
  - The `ConsumedFood` snapshot still has `protein == 31` and
    `caloriesConsumed == 226`. The snapshot is not recomputed from
    the live food.
  - The live `Food.protein` is now `50`, but `ConsumedFood` is
    frozen.
- Edge case of: S-001.

### S-005: Logged entry is frozen — removing the source food does not change it
- Trigger: User logs `Chicken Breast` at 150 g, then the user removes
  the source food from the library.
- Precondition: `Chicken Breast` is logged.
- Flow:
  1. Log via state.
  2. Call `repository.removeFood(chickenId)`.
  3. Reload today's consumed foods from the repository.
- Expected outcome:
  - The `ConsumedFood` row remains (its snapshot is intact).
  - `sourceFoodId` is the original id; the dangling reference is
    expected and supported (the snapshot has all values it needs).
  - `name`, `protein`, `carbs`, `fat`, `unitType`,
    `referenceAmount`, `referenceLabel`, `amountConsumed`,
    `groupNameSnapshot` are all unchanged.
- Edge case of: S-004.

### S-006: Logged entry is frozen — changing today's target does not change it
- Trigger: User logs `Chicken Breast` at 150 g, then the user changes
  today's daily target to `calories = 3000`.
- Precondition: `Chicken Breast` is logged.
- Flow:
  1. Log via state.
  2. Save a new `NutritionTarget(calories: 3000)` via
     `NutritionState.saveNutritionTarget`.
  3. Reload today's consumed foods.
- Expected outcome:
  - The `ConsumedFood` row's `targetCalories` is the value at log
    time (not `3000`).
  - `ConsumedFood.caloriesConsumed` is unchanged.
  - The state's current `nutritionTarget` is `3000`, but the
    snapshot is not rewritten.
- Edge case of: S-004.

### S-007: Amount edit on a logged row auto-commits the new snapshot
- Trigger: User logs `Chicken Breast` at 150 g, then changes the
  amount to `200` g on the same row. **The user does not re-tap
  the checkbox** — the edit auto-commits (debounced) to the day log.
- Precondition: `Chicken Breast` is logged at 150 g.
- Flow:
  1. Log via state (checkbox tap).
  2. Edit the amount input to `200`; do not re-tap the checkbox.
  3. Wait for the auto-commit debounce window to elapse.
  4. Inspect the `ConsumedFood` row.
- Expected outcome:
  - The existing `ConsumedFood.amountConsumed == 200.0`; the row's
    `id`, `sourceFoodId`, `loggedAtMs` are unchanged.
  - The `ConsumedFood.protein`, `carbs`, `fat`, `unitType`,
    `referenceAmount`, `referenceLabel`, and target values are
    unchanged (snapshot is still frozen).
  - The ring's consumed value updates to
    `(31*4 + 0*4 + 3*9) × (200 / 100) == 302`.
  - The row's checkbox remains checked; no checkbox interaction was
    required.
- Edge case of: S-001.

### S-008: Uncheck removes the log; re-check creates a new one
- Trigger: User logs `Chicken Breast` at 150 g, unchecks the row,
  then re-checks the row (still at 150 g).
- Precondition: `Chicken Breast` is logged at 150 g.
- Flow:
  1. Log via state.
  2. Uncheck the row.
  3. Re-check the row.
- Expected outcome:
  - After uncheck: `consumedToday` no longer contains the entry;
    `todayConsumedCalories == 0`; the checkbox is unchecked.
  - After re-check: a new `ConsumedFood` row exists in the
    repository (a fresh `id` is assigned; the old row was deleted,
    not resurrected). `consumedToday.length == 1`;
    `todayConsumedCalories == 226`.
  - Per R-6, the day-uniqueness contract means there is **never
    more than one row per `(sourceFoodId, dateMs)`** in
    `consumedToday`.
- Edge case of: S-001.

### S-009: Amount input rejects 0 and negative values; fractional values are accepted for both unit types
- Trigger: User opens a row, types `0` or `-5`, then taps the
  checkbox.
- Precondition: A library food exists.
- Flow:
  1. Type `0`.
  2. Tap the checkbox.
  3. Inspect `consumedToday`.
  4. Type `0.5` (grams food) → checkbox tap → row logs at 0.5.
  5. Type `0.5` (count food) → checkbox tap → row logs at 0.5.
     The amount is a multiplier against the food's reference; 0.5
     of a per-1-egg food means "half an egg" and is valid.
- Expected outcome:
  - For `0` or negative (either unit type): the checkbox tap is a
    no-op; an inline error renders next to the input;
    `consumedToday` does not gain a new entry.
  - For `0.5` on a grams food: the row logs at amount = 0.5.
  - For `0.5` on a count food: the row logs at amount = 0.5 (the
    field shows `0.5`; the validator does NOT reject fractional
    counts).
- Edge case of: none.

> **Spec change (2026-06-08)**: Earlier drafts of this plan stated
> that count foods required a whole number ≥ 1. The user clarified
> that the amount is a multiplier against the food's reference and
> that fractional counts (e.g. "0.5 eggs") are valid. The validator
> in [log_food_row.dart] was relaxed to accept any positive value for
> both unit types; the only invalid inputs are empty, non-numeric,
> zero, and negative.

## Iteration 1

(Original delivery — checkbox + amount input wired to `NutritionState`.)

## Iteration 2

### User feedback received (2026-06-10)

> "I tried it out and the multiplier feature doesn't really make sense. The
> way food amounts are logged should derive from the way the food is set up,
> if it's grams/ml, that should be the entered amount, not the multiplier,
> and if it's single units setting, that should be the multiplier. Remove
> the x multiplier sign and have the reference label (setting on the food
> item) appear beneath the input field. Add logic so that the daily
> nutrition totals also auto update if the amount field is updated, not
> only when the checkbox is checked."

Three changes:

1. **Semantic clarification** — the amount field is the **entered unit
   value**, not a multiplier. For a per-100 g food, `150` in the field
   means "150 g consumed" (1.5× the reference). For a per-1-egg food,
   `3` means "3 eggs" (3× the reference). The scaling math is
   unchanged (`amount / referenceAmount`); the only change is the
   framing of the UI: the input is "amount in own unit", not
   "multiplier".
2. **Reference label moved** — the food's reference label (e.g.
   "per 100 g" / "per 1 egg") renders as a small caption **beneath**
   the amount input (a `helperText`), not in the middle of the row.
3. **Auto-commit on amount edit** — when the user edits the amount
   field AND the food is already logged today, the new amount
   auto-commits to the day log (debounced ~250 ms). The user does not
   need to re-tap the checkbox; the ring and totals update live.

### DB Changes

None. The data layer is unchanged; the same `logConsumedFoodAt`
update path is used for both the checkbox-tap and the
auto-commit-on-edit flows.

### Backend Changes

- I2-B-1. `LogFoodRow` (frontend widget) gets a `_commitDebounce`
  timer (250 ms) that fires `_autoCommitIfLogged` whenever the
  amount controller's text changes. `_autoCommitIfLogged`:
  - Validates the current input (same `_validateAmount` path used
    by the checkbox toggle).
  - If the food is already logged today AND the input is valid,
    calls `nutritionState.logConsumedFoodAt(food, amount)` to
    auto-commit the new amount.
  - If the input is invalid, no auto-commit; the inline error
    renders via the existing `_amountError` state.
  - Cancels any pending debounce on dispose to avoid late fires.

No state or repository changes — `logConsumedFoodAt` is already
the right call for the day-uniqueness update path.

### Frontend Changes

- I2-F-1. `LogFoodRow` (`lib/features/nutrition/widgets/log_food_row.dart`):
  - **Remove** the inline `_formatReferenceLabel` `Text` widget
    that previously sat between the macros and the amount input.
  - **Add** the reference label as a `helperText` on the amount
    `InputDecoration` so it renders as a small caption **beneath**
    the input field. The label is the food's own `referenceLabel`
    (e.g. "per 100 g" / "per 1 egg"); no `×` multiplier prefix.
  - **Update** `_onAmountChanged` to also trigger
    `_autoCommitIfLogged` (debounced). On every keystroke, restart
    the 250 ms timer; when it fires, validate + commit.
  - **Remove** the obsolete "× multiplier" framing from the widget
    doc comments.

### Implementation Steps

1. Update the `LogFoodRow` build to move the reference label into
   `InputDecoration.helperText` and add the debounced auto-commit
   in `_onAmountChanged`.
2. Add a regression test for the auto-commit behavior (S-007
   updated): typing a new amount on a logged row without re-tapping
   the checkbox results in the snapshot being updated and the
   ring/totals reflecting the new value.
3. Add a regression test that the reference label renders beneath
   the input (as helperText), not in the middle of the row.
4. Run `flutter test`; all green.
5. Update `docs/widget_catalog.md` to reflect the new layout.

### Progress

- [x] Iteration 1: shipped
- [x] Iteration 2 user feedback received
- [ ] Iteration 2: TDD — write red tests for auto-commit + label
      layout
- [ ] Iteration 2: `LogFoodRow` — move reference label to
      `InputDecoration.helperText`
- [ ] Iteration 2: `LogFoodRow` — debounced auto-commit on
      amount edit
- [ ] Iteration 2: `flutter test` green
- [ ] Iteration 2: doc hygiene


### DB Changes

No new tables, no new columns, no new model fields. The data layer was
delivered in the prior `nutrition-data-audit-plan` and
`nutrition-page-calories-ring-plan` iterations and is sufficient for this
feature:

- `ConsumedFood` model: complete with frozen-snapshot fields, round-trip
  via `fromMap`/`toMap`, and `caloriesConsumed` computed getter.
- `WorkoutRepository` interface: `getConsumedFoodsForDate`,
  `createConsumedFood`, `deleteConsumedFood`,
  `getConsumedFoodsInRange` are all declared and implemented in both
  `MockWorkoutRepository` (in-memory `_consumedFoods` map) and
  `HiveWorkoutRepository` (box `consumed_foods`), with the SQLite
  schema already in place (`app_consumed_food` table, indices on
  `date_ms` and `logged_at_ms`).
- `NutritionState.logConsumedFood(food, amount)` and
  `NutritionState.deleteConsumedFood(id)` already exist; they build the
  frozen snapshot, persist it, refresh the cache, and notify listeners.
  This plan extends the state surface with a few small additions (see
  Backend Changes) — **no model or schema changes**.

### Backend Changes

State-surface additions to `NutritionState`
(`lib/state/nutrition_state.dart`):

- B-1. `ConsumedFood? findLoggedTodayForFood(String foodId)` — looks
  up an existing `ConsumedFood` row in the cache (and, if not in
  cache, the repository) by `sourceFoodId == foodId` for today's
  `dateMs`. Returns the row or `null`. Used by the UI to determine
  whether a row's checkbox should be checked on first paint, and to
  enforce the "one row per `(sourceFoodId, dateMs)`" invariant
  (R-6).
- B-2. `bool isFoodLoggedToday(String foodId)` — pure / cache-only
  helper that returns `true` when the cache contains a
  `ConsumedFood` with `sourceFoodId == foodId` for today. Used by
  the row's checkbox `value:` binding so the checkbox never has to
  read the repository directly.
- B-3. `Future<String?> logConsumedFoodAt(Food food, double amount)`
  — composes the existing snapshot-builder with the day-uniqueness
  invariant: if a row for `(sourceFoodId, todayMs)` already exists
  in the cache, **update** its `amountConsumed` and `updatedAtMs`
  via the new `updateConsumedFood` repository method, keep the same
  id, and notify. Otherwise create a new row via the existing
  `createConsumedFood` path. Returns the row id. This is the
  single entry point the UI calls when the user toggles the
  checkbox ON or edits the amount. The existing
  `logConsumedFood` is kept on the public surface for backwards
  compatibility with the test suite and prior callers; it delegates
  to `logConsumedFoodAt`.
- B-4. `Future<bool> unlogFoodToday(String foodId)` — looks up the
  existing row for `(sourceFoodId, todayMs)` and deletes it via the
  repository; refreshes the cache; notifies. Returns `true` if a
  row was removed, `false` otherwise. This is the single entry
  point the UI calls when the user toggles the checkbox OFF.
- B-5. New derived getters on `NutritionState` (pure / cached-only,
  no repo call):
  - `int get todayConsumedProtein` — sum of
    `(protein * amountConsumed.round())` across `consumedToday`.
  - `int get todayConsumedCarbs` — sum of
    `(carbs * amountConsumed.round())`.
  - `int get todayConsumedFat` — sum of
    `(fat * amountConsumed.round())`.
  - `List<ConsumedFood> get consumedTodaySorted` —
    `consumedToday` sorted by `loggedAtMs` ascending. Returns a
    new list (the cache stays in insertion order; this getter is
    for presentation and for deterministic tests).
- B-6. `Future<ConsumedFood?> refreshConsumedToday()` — re-runs
  `loadConsumedToday` and returns the resulting list. Kept as a
  named alias for clarity at the call site that follows an
  external edit (e.g. test fixtures mutating the repository
  directly).

Repository-interface additions to `WorkoutRepository`
(`lib/data/repositories/workout_repository.dart`):

- B-7. `Future<void> updateConsumedFood(ConsumedFood entry)` —
  persists changes to a single `ConsumedFood` row by `id`. Throws
  if the id is not present (callers must guard). Used by
  `logConsumedFoodAt` to amend an existing row's `amountConsumed`.
- B-8. `Future<ConsumedFood?> getConsumedFoodById(String id)` —
  returns the snapshot for an id, or `null` if not found. Used
  by `findLoggedTodayForFood` as a cache-miss fallback.

Both methods are added in both `MockWorkoutRepository`
(in-memory map operations) and `HiveWorkoutRepository`
(read-modify-write on the `consumed_foods` box). The SQLite
schema's `app_consumed_food` table already supports
UPDATE/SELECT-by-id with no change.

### Frontend Changes

The per-row UI on the food library card becomes a
`LogFoodRow` widget. The existing `_FoodRow` is replaced with this
new widget (the per-row "remove from library" delete affordance
is **removed**; deletion will be redesigned in a follow-up — the
existing hard-delete `removeFood` API stays available via
`FoodLibraryState` but is no longer surfaced in this UI).

Widget additions to `lib/features/nutrition/`:

- F-1. **`LogFoodRow`** (new file
  `lib/features/nutrition/widgets/log_food_row.dart`) — a single
  library-food row, now a stateful widget because it owns the
  `TextEditingController` for the amount input. Constructor:
  - `required Food food` (the library food)
  - `required NutritionState nutritionState`
  - `required FoodLibraryState foodLibraryState` (still needed
    for the Food's name/macros rendering, even though the row no
    longer mutates the library)
  - Renders, left to right:
    - a stock `Checkbox` (`value: nutritionState.isFoodLoggedToday(food.id)`,
      `onChanged: (v) => _toggle(v)`). The checkbox is themed via
      `theme.colorScheme` — no hardcoded colors.
    - the food name (flex)
    - the macro string (existing
      `"$cal cal · ${food.protein}P · ${food.carbs}C · ${food.fat}F"`)
    - a **reference label** text widget, e.g. `per 100 g` /
      `per 1 egg` — pulled from `food.referenceLabel` with a
      leading "per " if the label is not already prefixed (e.g.
      `"g"` → `"per 100 g"`, `"egg"` → `"per 1 egg"`).
    - an amount `TextField` (numeric keyboard, ~64 dp wide)
      prefilled with the default for the food's unit type
      (count: `1`; grams: `100`). Editing the field commits on
      focus loss or on submit; while the input is invalid, the
      checkbox tap is a no-op and an inline error renders.
  - The widget rebuilds via `ListenableBuilder(listenable: nutritionState)`
    so the checkbox updates the moment a log is written.

- F-2. **`_FoodLibraryBrowseSection`** in `nutrition_screen.dart`
  is updated to render `LogFoodRow` instead of `_FoodRow`. The
  section is now a `StatefulWidget` only insofar as the
  `LogFoodRow` instances own their controllers; the section
  itself stays stateless and rebuilds on
  `FoodLibraryState` / `NutritionState` notifications.

- F-3. **`NutritionScreen`** — no structural change beyond
  swapping the row widget. The calorie ring card, the food
  library card, the targets card, and the bottom "Manage Food Library"
  CTA all stay. The "Consumed Today" list (out of scope for
  this iteration) is removed; a follow-up will redesign the
  deletion affordance and re-introduce it.

- F-4. **No new buttons.** The checkbox is a stock Flutter
  `Checkbox`; the amount input is a stock `TextField`. The
  existing bottom "Manage Food Library" CTA keeps its explicit
  `RoundedRectangleBorder` shape.

### Implementation Steps

1. (Phase 0.5 TDD) Write the failing tests for the scenarios in
   the `## Scenarios` section. Map:
   - State / model behavior → extend
     `test/food_library_test.dart` (or a new group in
     `test/state_test.dart`) with a new group
     `NutritionState — log from library`. Cover S-001..S-009.
   - Snapshot preservation (S-004, S-005, S-006) → tests in
     the same file, asserting the `ConsumedFood` row's fields
     are unchanged after the source mutation.
   - Derived totals (S-001..S-003) → assertions on
     `nutritionState.todayConsumedCalories` /
     `todayConsumedProtein` / `todayConsumedCarbs` /
     `todayConsumedFat`.
   - Day-uniqueness (S-008) → test that re-toggling the
     checkbox on an already-logged row updates (not
     duplicates) the existing row.
   - Widget rendering (S-001, S-002) → tests in
     `test/screen_widget_test.dart` (or extend
     `test/nutrition_test.dart`) that pump the
     `NutritionScreen` and verify:
     - the checkbox is present on each food row,
     - typing an amount and tapping the checkbox results in
       the new snapshot being persisted and the ring's
       consumed value updating.
   - Edge cases (S-009) → unit tests in
     `test/edge_case_test.dart` for the validation branch
     and the day-uniqueness branch.
2. (Phase 2.2 State) Implement B-1..B-8 in `NutritionState` and
   the repository (interface + mock + hive). Run the red tests,
   watch them go green.
3. (Phase 2.3 Features) Implement F-1..F-4. Wire `LogFoodRow`
   into the existing `_FoodLibraryBrowseSection`. Re-run
   tests; fix anything red.
4. (Phase 2.6 Tests green) `flutter test` passes. Pre-existing
   tests in `food_library_test.dart`, `nutrition_test.dart`,
   `nutrition_data_audit_test.dart` continue to pass.
5. (Phase 2.7 Doc hygiene) Update:
   - `docs/state_management.md` — note the new
     `logConsumedFoodAt`, `unlogFoodToday`,
     `findLoggedTodayForFood`, `isFoodLoggedToday`, the
     derived macro totals on `NutritionState`, plus the
     new repository methods `updateConsumedFood` and
     `getConsumedFoodById`.
   - `docs/navigation_and_screens.md` — note the new
     `LogFoodRow` widget in the `NutritionScreen` row.
   - `docs/widget_catalog.md` — add `LogFoodRow` to the
     catalog.
   - `docs/data_models.md` — N/A (no model change).
   - `docs/db_integration.md` — note the new
     `updateConsumedFood` / `getConsumedFoodById`
     repository methods in the day-log section.

## Progress

- [ ] Phase 0 complete (this plan)
- [ ] Phase 1: DB layer audit
- [ ] Phase 1: Repository additions (`updateConsumedFood`,
      `getConsumedFoodById`) in interface, mock, and hive
- [ ] Phase 2.0.5: TDD — red tests for S-001..S-009 written
      and confirmed failing
- [ ] Phase 2.1: `NutritionState` state additions
      (`logConsumedFoodAt`, `unlogFoodToday`,
      `findLoggedTodayForFood`, `isFoodLoggedToday`, derived
      macro totals, `refreshConsumedToday`)
- [ ] Phase 2.2: `LogFoodRow` widget
- [ ] Phase 2.3: Wire `LogFoodRow` into
      `_FoodLibraryBrowseSection`; remove the now-orphan
      `_FoodRow` delete affordance
- [ ] Phase 2.4: Button-shape compliance pass (no new
      buttons, but verify the existing "Manage Food Library" CTA and
      any existing icon buttons on the screen still have
      explicit `shape:` overrides)
- [ ] Phase 2.5: `flutter test` green
- [ ] Phase 2.6: Doc hygiene (state_management,
      navigation, widget_catalog, db_integration)
- [ ] Phase 3: Code review against acceptance criteria,
      scenarios, global conventions, architecture compliance

## Feedback

(Iteration 1 feedback folded into Iteration 2 above; the user
requested three changes: semantic clarification of the amount
field, moving the reference label beneath the input, and
auto-commit on amount edit.)

### Phase 0 Complete ✓ (Iteration 1)

### Phase 1 Complete ✓ (Iteration 1)

### Phase 2 Complete ✓ (Iteration 1)

### Phase 3 Complete ✓ (Iteration 1)


