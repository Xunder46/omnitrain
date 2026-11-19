# Plan 265 — Nutrition polish: keep scroll and amounts, one carb label, readable amount error

Review item 35 (owner list: "Nutrition: returning from Daily Targets resets the scroll; carb slice switches between 'Net Carbs' and 'Carbs'; cramped amount error; water has no goal"). Owner 2026-11-19: no optional water goal.
Phone only. No wire, watch, storage or schema change.

## Goal and acceptance

- Coming back from Daily Targets keeps the scroll position and any amount typed in a food row. Cause: the reload set `isLoading`, and the screen swapped its whole scroll view for a spinner.
- The ring's carbs slice reads `Carbs` with total carbs (fibre included) whether or not a carbs target exists (it read `Net Carbs` and net grams without one).
- A food row's amount error shows under the row at full width (it was squeezed into the 73 dp amount box); the box turns red.

Acceptance: S-26501, S-26502 green and red without the change; the updated S-14035 calories-only test green; `flutter analyze` not above 178 issues, 0 errors; no new red against the Windows base failing set; Docs delta applied.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-26501 | `NutritionScreen` shows the loading spinner only until its content has been shown once (`_hasShownContent`). | `nutrition_screen.dart` |
| D-26502 | The carbs slice always names `Carbs` and counts total carbs; its percent of calories is unchanged (net-based). The target form `<grams> of <target> g` is unchanged. | `calorie_ring_card.dart` |
| D-26503 | `LogFoodRow` renders `_amountError` as a full-width `Text` under the row (live region, key `log_food_amount_error_<id>`); the field's `errorText` is gone and its border turns the error colour. | `log_food_row.dart` |

## Scenarios

S-26501 type an amount, reload the target slowly: no spinner, same scroll position, same text. S-26502 amount `0`: the message sits below the box, wider than 250 dp, the box has no `errorText`. S-14035 (updated) calories-only target: the slice names `Carbs` and shows `180 g`.

## Input-reality checklist

1. Writers: none. 2. Lifecycle: the day arrows and first load unchanged. 3. Settings: none. 4. Time: none. 5. Cost: none. 6. Words: `Carbs` where `Net Carbs` showed. 7. Competition: a reload mid-typing keeps the field's controller.

## Docs delta

`docs/nutrition.md`: one paragraph after the NutritionScreen section.

## Open items

1. (owner) Defaults taken: `Carbs`/total in both states (matches what the target means); the percent shown with it is still the share of calories from net carbs, as with a target today.
2. (owner) The optional water goal is not built (owner decision).
