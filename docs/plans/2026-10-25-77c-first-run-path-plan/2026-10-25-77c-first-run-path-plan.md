# Feature: 77c — first-run path: the home card says what it is, the empty list leads to the picker, day one is quieter

> Status: seeded by the lead 2026-10-25 (owner away). One track: phone app. Follows 77b2 (`9cb77038`). Series: `docs/plans/2026-10-25-77-nutrition-setup-path-series.md`.
> Base: `9cb77038` on `claude_develop`. Never create or switch branches; git belongs to the governor.
> Baseline: `flutter analyze` 180 issues, 0 errors.

## Overview

| What you see | Now | After 77c |
|---|---|---|
| Home screen nutrition card | fork icon, "0 / 2,000 Cal", chevron — nothing says what it is | fork icon, the word "Nutrition", then the figure and chevron |
| Daily Nutrition with no foods yet | "Your Foods I Eat list is empty. Tap the pencil to add foods." | "Pick the foods you eat", a one-line hint and a filled "Choose foods" button that opens the picker (the Library, now grouped by category) |
| Calorie card on a day with no sodium | "Na 0 mg" | The sodium chip is not shown until something with sodium is logged (the water control keeps its place on the right) |

## Decision Ledger

- **D-1** `_Headline` (`lib/features/home/widgets/nutrition_summary_card.dart` ~l.262-290) gets a label `Text('Nutrition')` (key `nutrition_card_title`, `labelLarge`, `OmniTheme.colors.textSecondary`, maxLines 1) between the icon and the figure. The figure sits in an `Expanded` + `FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerRight)` so it shrinks instead of ellipsizing; its key `nutrition_card_headline_text` and text are unchanged. The card gets no extra height (the short-viewport test stays valid).
- **D-2** `_FoodLibraryBrowseSection` (`lib/features/nutrition/nutrition_screen.dart` ~l.286-325) gets a required `VoidCallback onChooseFoods`; when `foods.isEmpty` it shows `OmniEmptyState(icon: Icons.restaurant_menu_outlined, title: 'Pick the foods you eat', hint: 'Choose them from the library, then tick them off each day.', action: FilledButton(key: Key('foods_i_eat_choose_button'), ... child: Text('Choose foods')))` and the button calls `onChooseFoods` (the screen passes `_openManageLibrary`). The pencil in the header stays. The old strings `Your Foods I Eat list is empty.` / `Tap the pencil to add foods.` disappear. Button shape per the design system (`OmniTheme.buttonBorderRadius`).
- **D-3** `calorie_ring_card.dart` ~l.268-272: the `_SodiumTotalChip` is built only when `widget.nutritionState.todayConsumedSodium > 0`, otherwise `const SizedBox.shrink()` (the row stays `spaceBetween`, so water stays on the right). The test `renders "Na 0 mg" when nothing is logged` (nutrition_test.dart ~l.389) is inverted.
- **D-4** Out of scope: an inline picker on the Daily Nutrition screen (the button goes straight to the grouped Library); hiding the water control; primer timing (77d).

## Scenarios (ids `S-1291x`; grep: unused)

- **S-12910** Home card shows `find.byKey(Key('nutrition_card_title'))` with text `Nutrition` and the unchanged `nutrition_card_headline_text` (`0 / 2,000 Cal` for target 2000, consumed 0); at 320 wide and 2.0x text the headline still renders without an exception (FittedBox) and `home_short_viewport_test` stays green.
- **S-12911** Daily Nutrition with an empty library: `Pick the foods you eat` and `foods_i_eat_choose_button` found; the old two strings absent; tapping the button opens `AddFoodScreen` (find `Manage Food Library`).
- **S-12912** With foods in the list the empty state is absent and the button is not found.
- **S-12913** Sodium chip: absent when `todayConsumedSodium == 0`; present (`Na <n> mg`) after logging a food with sodium; water control (`water_tracker_label`) present in both cases and still right of the card's centre.
- **S-12914** Source guard: `nutrition_summary_card.dart` contains `nutrition_card_title` and `'Nutrition'`; `nutrition_screen.dart` contains `foods_i_eat_choose_button` and no `Tap the pencil`.

## Phases
- **P1** `crew-builder-app`: exact code, three lib files (lead gives it).
- **P2** `crew-builder-app`: new `test/first_run_path_test.dart` and the existing tests these changes move (the lead lists them after P1).
- Then docs (lead), mutation pass, lead review, commit.

## Owner device check
- (owner) ODC-1 Fresh install: the home card reads "Nutrition"; open it: "Pick the foods you eat" with a Choose foods button, no "Na 0 mg".

## Assumption Log
- **A-1** (lead, owner may overrule) The label is the single word "Nutrition", inline, so the card does not grow.
- **A-2** (lead, owner may overrule) The empty-state "picker" is a button into the (now category-grouped) Library, not an inline list.
- **A-3** (lead, owner may overrule) Only the sodium chip is hidden on an empty day; the water control stays (water is not food).
