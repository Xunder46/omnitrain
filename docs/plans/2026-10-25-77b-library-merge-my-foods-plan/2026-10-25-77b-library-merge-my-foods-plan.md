# Feature: 77b — "My Foods" tab merged into Library: "Yours" tag, a "Create new food" button, delete from the editor

> Status: seeded by the lead 2026-10-25 (owner away; owner decisions O-2 and O-3 of `docs/plans/2026-10-25-77-nutrition-setup-path-series.md`). One track: phone app (`lib/`). Follows 77a (`c395f572`).
> Base: `c395f572` on `claude_develop`. Never create or switch branches; git belongs to the governor.
> Binding: `docs/global_conventions.md`; `docs/design_system.md` ("Shared pieces and rules per job"); `.github/copilot/pr-scope-budget.md`.
> Baseline: `flutter analyze` 180 issues, 0 errors (2026-10-25).

## Overview

| What you do | Now | After 77b |
|---|---|---|
| Open Manage Food Library | Three tabs: Library, My Foods, Categories | Two tabs: Library, Categories |
| Look for a food you created | In the My Foods tab (and also in Library, unmarked) | In Library, with a small "Yours" tag next to the name |
| Create a food | "+ New Food" button on My Foods | "+ Create new food" button at the bottom of Library (same form) |
| Delete a food you created | Red trash on its My Foods row | "Delete food" button at the bottom of its editor (asks first; past logs untouched) |
| An old pre-catalog custom food (no catalog twin) | Only in My Foods | In Library too, tagged "Yours", with its old red delete button (legacy rows keep their old row) |

## Decision Ledger

- **D-1** `AddFoodScreen` has two tabs: `TabController(length: 2)`, constants `_libraryTabIndex = 0`, `_groupsTabIndex = 1`, labels `Library` / `Categories` (`add_food_screen.dart` `_AddFoodScreenState`, scout: l.84, 117-122, 174-210). `_MyFoodsTab` and `_myFoodsTabIndex` are deleted; `_FoodIdentity` stays (used by D-2).
- **D-2** The Library tab list = every catalog food (bundled + user-created, as today) PLUS the legacy library-only customs that My Foods surfaced (non-archived, `!isCatalog`, `catalogIdFor(f) == null`), deduped by `_FoodIdentity` with the catalog row winning, sorted together case-insensitively by name, search filtering all of them. Catalog rows render as `_CatalogRow` (77a); legacy rows render as the existing `_UserFoodRow` unchanged (tap edits through `_LegacyLibraryEditScreen`, red delete button as today).
- **D-3** "Yours" tag: a small text label `Yours` (key `yours_tag_<foodId>`, `theme.textTheme.labelSmall`, `theme.colorScheme.primary`) after the name on (a) `_CatalogRow` when `!foodLibraryState.isBundledCatalogFood(widget.food.id)` and (b) every `_UserFoodRow`. Bundled foods never carry it.
- **D-4** Library bottom CTA: `OmniBottomCTA(label: '+ Create new food', buttonKey: const Key('new_food_button'), onPressed: () => _openNewFoodForm(context))` on the Library tab (the `_NewFoodFormScreen` flow is unchanged). The Library list's bottom padding clears it (`OmniTheme.formBottomCTAClearance`).
- **D-5** Delete a created food from its editor. New file `lib/features/nutrition/widgets/delete_created_food.dart` with `Future<bool> confirmAndDeleteCreatedFood(BuildContext context, {required Food food, required FoodLibraryState foodLibraryState, required NutritionState nutritionState})`: asks (title `Delete <name>?`, body "Your past nutrition logs will remain unchanged.", keys `food-delete-cancel` / `food-delete-confirm`), then unlogs today's entry if logged, removes the library copy (`libraryIdFor`), then `deleteCatalogFood` (the sequence of `_UserFoodRowState._onDelete`, catalog branch, `add_food_screen.dart` ~l.1190-1230), and returns true; on a thrown error shows `OmniMessage.errorOn(... 'Could not delete <name>')` and returns false. `EditFoodScreen` gets an optional `NutritionState? nutritionState`; when `food.isCatalog && !isBundledCatalogFood(food.id) && nutritionState != null` it shows, in the same footer slot as Reset to original (never both), an `OutlinedButton` "Delete food" (key `food_delete_created`, `theme.colorScheme.error` text and border, `OmniTheme.buttonBorderRadius`), which calls the helper and pops on true. `EditFoodScreen.push` gets the same optional parameter; `_CatalogRowState._openEdit` passes `widget.nutritionState`.
- **D-6** `_UserFoodRowState._onDelete` and `_openEdit` stay as they are (legacy rows only now).
- **D-7** Out of scope (77b2): grouping Library by category; (77c/77d) everything else.

## Scenarios (ids `S-1281x`; grep 2026-10-25: unused)

Helper/screen (new `test/library_merge_test.dart`, Mock):
- **S-12810** Manage screen shows tabs `Library` and `Categories` and no `My Foods` (find.text), `TabBar` has 2 tabs. Fails today: three tabs.
- **S-12811** A created food (via `createCatalogFood` + `addCatalogFoodToLibrary`) appears in Library once, with `yours_tag_<id>`; a bundled food row (`chicken_breast`) has none.
- **S-12812** A legacy library-only custom (`createCustomFood`, no catalog twin) appears in Library as a row with `delete_user_food_<id>` and a Yours tag; a library COPY of a bundled food is not listed twice (only one row text for 'Chicken breast, skinless').
- **S-12813** Search "mine 77" finds the created food and hides others; clearing restores.
- **S-12814** The Library tab shows `new_food_button` with text `+ Create new food`; tapping it opens the New Food form (find the form field `food_form_name`); the Categories tab still shows `new_group_button`; no CTA text `+ New Food` anywhere.
- **S-12815** Delete from the editor: open the pencil of an in-list created food → `food_delete_created` present → tap → dialog → Cancel keeps the food → again → Confirm → food gone from catalog, library and today's log (log it first), screen popped.
- **S-12816** `food_delete_created` is absent for a bundled food's editor and for a library copy; `food_reset_original` and `food_delete_created` are never both present.
- **S-12817** Helper unit: `confirmAndDeleteCreatedFood` returns false and deletes nothing on Cancel; returns true and removes the catalog row + library copy on Confirm (widget host with a button).
- **S-12818** Source guard on `add_food_screen.dart`: no occurrence of `class _MyFoodsTab`, `_myFoodsTabIndex`, `'My Foods'`, `'+ New Food'`, `No custom foods yet`; whole statements asserted.

Existing tests that encode the old tab (grep 2026-10-25; the builder lists every changed assertion): `test/my_foods_unification_test.dart` (17 matches: rework to the Library tab, keep every behavioural claim that still holds: dedup, legacy rows, delete), `test/nutrition_test.dart` (`My Foods` ×14, `No custom foods yet`, `+ New Food` flows at ~l.2822-3140), `test/screen_widget_test.dart` (`My Foods` ×8, ~l.9860 legacy edit), `test/food_photo_clear_legacy_edit_test.dart` (×4), `test/food_library_test.dart`, `test/food_group_membership_test.dart`, `test/header_standardization_test.dart` (only if they tap the tab).

## Phases (serial)

- **P1** `crew-builder-app`: D-5 helper file + `EditFoodScreen`/`push` change as exact code (lead gives it). Scope: `lib/features/nutrition/widgets/delete_created_food.dart` (new), `lib/features/nutrition/edit_food_screen.dart`.
- **P2** `crew-builder-app`: D-1..D-4, D-6 in `add_food_screen.dart` as exact code (lead gives it). Scope: `lib/features/nutrition/add_food_screen.dart`.
- **P3a** `crew-builder-app`: `test/library_merge_test.dart` S-12810..S-12818.
- **P3b** `crew-builder-app`: rework the old tests listed above (scope = those files).
- **P4** `crew-docs-keeper` (after the last test-adding round). Then the lead: simulator look, mutation pass, `crew-reviewer`, commit.

## Owner device checks

- (owner) ODC-1 Manage Food Library: two tabs; your own food has a "Yours" tag; "+ Create new food" opens the form and the new food shows up tagged.
- (owner) ODC-2 Open a food you created, scroll to the bottom: "Delete food" asks, then removes it (and from Foods I Eat).

## Assumption Log

- **A-1** (lead, owner may overrule) Deleting a created food is offered only from its editor ("Delete food" at the bottom, asks first), not on the Library row, so the row keeps one meaning (tap = add/remove from your list).
- **A-2** (lead, owner may overrule) Older library-only custom foods (from before the catalog) stay in Library with their old red delete button; they are rare and not worth a second row design.
- **A-3** (lead, owner may overrule) The Library button reads "+ Create new food" and sits at the bottom of the Library tab (the owner said "Create new food button inside Library").
- **A-4** (lead) The docs keeper stopped on a search loop; the lead wrote the doc edits. Review minors 1, 2, 4 fixed by the lead; minor 3 (the two Library empty states do not reserve space for the bottom button) accepted: both are centred and short.
