# Feature: 77d — Foods I Eat row says what the amount box counts and how to log; the primer shows on the screen it explains

> Status: seeded by the lead 2026-10-25 (owner away). One track: phone app. Follows 77c (`56c74bb8`). Series: `docs/plans/2026-10-25-77-nutrition-setup-path-series.md`.
> Base: `56c74bb8` on `claude_develop`. Never create or switch branches; git belongs to the governor.
> Baseline: `flutter analyze` 180 issues, 0 errors.

## Overview

| What you see | Now | After 77d |
|---|---|---|
| Caption under a Foods I Eat amount box | The reference serving ("100 ml", "1 medium"; "100 100 g" on older data), which reads like the box counts 100-ml units | Only the unit the box counts: "ml", "g", "medium" |
| Unlogged food's thumbnail | Empty ring in the corner | The ring holds a small "+" (the thumbnail is still the log button) |
| First visit to nutrition | The primer sheet opens over the home screen, before you have seen the Daily Nutrition screen | The Daily Nutrition screen opens first and the primer sheet rises over it, once |

## Decision Ledger

- **D-1** New `String foodUnitCaption(Food food)` in `lib/core/utils/food_helpers.dart`: the unit alone. Trim the label; drop a leading `per `; drop a leading number with optional space (`^\d+(\.\d+)?\s*`); if nothing is left return the trimmed original label. `LogFoodRow`'s caption (`log_food_row.dart` ~l.419) uses it instead of `foodServingLabel`. `foodServingLabel` stays for Library rows. The box value semantics are unchanged (grams-type: amount in the unit; count-type: number of servings).
- **D-2** `_ThumbToggle` (`log_food_row.dart` ~l.596-620): the unlogged badge shows `Icon(Icons.add, size: 12, color: themeColors.textMuted)` instead of nothing. Logged state unchanged. Typing an amount on an unlogged row still does not log (assumption A-1).
- **D-3** Primer timing: `HomeScreen._openNutritionScreen` (`lib/features/home/home_screen.dart` ~l.343-355) pushes `NutritionScreen` at once (no sheet first) and `_showNutritionPrimer` is deleted with its now-unused import. `_NutritionScreenState` shows the primer itself after its first frame when `widget.nutritionPrimerState.shouldShowPrimer` (mounted-guarded), marking seen on dismiss exactly as the home did (`unawaited(widget.nutritionPrimerState.markSeen())` in the sheet's `onDismiss`); the "?" button still reopens it without marking seen. The two share one method `_showPrimer({required bool markSeen})`.

## Scenarios (ids `S-1301x`; grep: unused)

- **S-13010** `foodUnitCaption` table: `g`→`g`, `ml`→`ml`, `medium`→`medium`, `100 g`→`g`, `per 100g`→`g`, `per 100 ml`→`ml`, `egg white`→`egg white`, ``→``.
- **S-13011** A Foods I Eat row for a 100 ml food shows the caption `ml` (not `100 ml`) and the box shows 100; a count food shows `medium` and box `1`; typing 250 leaves the caption `ml`.
- **S-13012** Unlogged row: the thumbnail badge contains `Icons.add`; after tapping the thumbnail it contains `Icons.check` and not `Icons.add`.
- **S-13013** First visit, primer unseen: tapping the home card shows `Daily Nutrition` (the screen) AND the primer (`nutrition_primer_dismiss`) over it; dismissing marks seen (`shouldShowPrimer` false); a second visit shows no primer. With the primer already seen no sheet appears on entry. The "?" button still opens it without changing the flag.
- **S-13014** Source guard: `home_screen.dart` has no `_showNutritionPrimer`; `nutrition_screen.dart` contains `_showPrimer(markSeen: true)`.

## Phases
- **P1** `crew-builder-app`: exact code (lead gives it): `food_helpers.dart`, `log_food_row.dart`, `home_screen.dart`, `nutrition_screen.dart`.
- **P2** `crew-builder-app`: tests (new `test/row_caption_and_primer_test.dart`) and the existing tests these changes move.
- Then docs (lead), mutation pass, lead review, commit.

## Owner device check
- (owner) ODC-1 Foods I Eat: captions read just the unit; the thumbnail ring of an unlogged food has a "+". First tap on the home card after a fresh install: Daily Nutrition opens and the primer slides up over it.

## Assumption Log
- **A-1** (lead, owner may overrule) Typing an amount on an unlogged food does not log it (that could log by accident); the "+" in the ring is the cue instead.
- **A-2** (lead, owner may overrule) The primer waits for the nutrition screen rather than being cut; it still shows once, with the same text.
