# Feature: 77a — Library rows toggle with an outline, edits change only your copy, Reset to original

> Status: seeded by the lead 2026-10-25. One track: phone app (`lib/`). Part of `docs/plans/2026-10-25-77-nutrition-setup-path-series.md` (owner decisions O-1, O-3; defaults L-1..L-3).
> Base: `d86bf17f` on `claude_develop`. Never create or switch branches; git belongs to the governor.
> Binding: `docs/global_conventions.md`; `docs/design_system.md` ("Shared pieces and rules per job"); `.github/copilot/pr-scope-budget.md`.
> Baseline: `flutter analyze` 180 issues, 0 errors (2026-10-25).
> Evidence: `2026-10-25-77a-library-edit-own-copy-plan.evidence.md` (beside this plan). Review: `2026-10-25-77a-library-edit-own-copy-plan.review.md` (reserved path; the reviewer writes it).

## Overview

| What you do | Now | After 77a |
|---|---|---|
| Tap a food row in Library | Opens the ten-field editor for the shipped catalog entry | A food not in your list is added; a food in your list asks "Remove from your library?" (same dialog as today) |
| See that a food is in your list | The "Add" button turns into a red trash can | The row gets a primary-colour outline and a check; there is no red button |
| Edit a bundled food | Changes the shipped entry for the whole install, no undo | A small pencil on the row (only on foods in your list) opens the editor; saving changes only your copy |
| Undo an edit | Not possible | "Reset to original" at the bottom of the editor (only when your copy differs from the shipped food); asks first |
| Read a Library row | "48 cal · 3P · 5C · 2F" | "48 cal per 100 ml · 3P · 5C · 2F" |
| Foods you created | Edit changes them | Unchanged (L-3) |

## Decision Ledger

- **D-1** New `FoodLibraryState.editLibraryFood(Food libraryCopy, FoodDraft draft)`: applies the draft to the library row only (`_repository.updateFood`, cache, notify). It does NOT call `updateCatalogFood`, `markSeedEntryTouched` or `_propagateCatalogEditToLinkedFoods`. `lastAmountConsumed`, `id`, `catalogId`, `createdAtMs` are kept. Image handling mirrors `updateCatalogFood` (`food_library_state.dart` ~l.930-950): when `draft.imagePath` differs and the previous path is a managed file belonging to this copy, delete it; never delete a path the catalog row still holds (`_catalogFoods[catalogId]?.imagePath`).
- **D-1b** New `Food? FoodLibraryState.libraryFoodFor(String catalogFoodId)`: the user's library copy for a catalog id (the row `libraryIdFor` points at), else null. An in-list Library row shows the COPY's name, macros, serving and photo (so an edit is visible there); a not-in-list row shows the catalog food.
- **D-2** New `FoodLibraryState.canResetLibraryFood(Food libraryCopy) → bool`: true only when `libraryCopy.catalogId` names a catalog row that `isBundledCatalogFood` AND any of name, groupId, unitType, referenceAmount, referenceLabel, protein, carbs, fiber, fat, sodium, notes, imagePath differs from that catalog row. New `resetLibraryFood(String libraryId)` copies exactly those fields from the catalog row into the copy, keeping `id`, `catalogId`, `lastAmountConsumed`, `createdAtMs`; `updatedAtMs` = now. Image: same rule as D-1.
- **D-3** `EditFoodScreen` gets its own copy-or-catalog decision from the food it is given: a library row (`isCatalog == false`) with a bundled twin saves through `editLibraryFood`; a user-created catalog row (`isCatalog == true`, not bundled) keeps `updateCatalogFood` (L-3). The legacy library-only custom path (`_LegacyLibraryEditScreen`, `updateCustomFood`) is untouched. Both `onSave` and `onImageSave` use the same branch.
- **D-4** Reset UI: a secondary `OutlinedButton` "Reset to original" (key `food_reset_original`) under the form in `EditFoodScreen`, built only when `canResetLibraryFood(currentFood)`; tap asks via `ConfirmationDialog.showTwoChoice` (title "Reset to original?", keys `food-reset-cancel` / `food-reset-confirm`), then `resetLibraryFood` and pops. Shared pieces per `design_system.md`; no new colour values.
- **D-5** `_CatalogRow` (`add_food_screen.dart` l.1315-1500): the row `InkWell.onTap` becomes the toggle: not in list → `_onAdd`; in list → `_onRemove` (keeps its confirm dialog and the unlog-today step, L-2). The trailing `Add` button stays (key `add_catalog_food_<id>`); the red remove button is replaced by a non-red check indicator (key `remove_catalog_food_<id>` kept on the tappable check so existing keys resolve) and the row gets a primary-colour outline (`theme.colorScheme.primary`, 2 px like the Foods I Eat thumbnail toggle, button radius `OmniTheme.buttonBorderRadius`; ratified by the lead after the first review, which read this line as 1.5 px / surface radius). A pencil `IconButton` (key `edit_catalog_food_<id>`, `Icons.edit_outlined`, tooltip "Edit food", 48 px tap target) shows only when in list (L-1) and opens `EditFoodScreen.push` with the LIBRARY copy (`libraryIdFor(food.id)` → the copy) for a bundled food, and with the catalog row itself (`widget.food`) for a user-created food (so D-3's `updateCatalogFood` path and its propagation stay as today).
- **D-6** Serving unit: move `LogFoodRow._unitLabel` (`log_food_row.dart` ~l.421-443, quoted by the scout) into `lib/core/utils/food_helpers.dart` as `String foodServingLabel(Food food)` (same behaviour, same output "100 ml"); `LogFoodRow` calls it. `_CatalogRow`'s macro line becomes `'$cal cal per ${foodServingLabel(food)} · ${P}P · ${C}C · ${F}F'`. `_UserFoodRow` (My Foods) is NOT changed (the tab goes in 77b).
- **D-7** Past `ConsumedFood` snapshots are untouched (they freeze at log time). The watch `foods_down` list is built from library rows, so an edited copy now reaches the wrist as the user's values; no watch change.
- **D-8** Existing installs where the catalog row was already edited under the old behaviour keep that edit (catalog row + tombstone untouched); no migration (series rule: no legacy handling).
- **D-9** Waiting readers / concurrent paths: none new (all calls are awaited UI actions; `_busy` guard in the row already serialises add/remove).

## Scenarios (ids `S-1270x`; grep 2026-10-25: unused)

State (`test/food_library_copy_edit_test.dart`, new; Mock repo, plus the same S-12701/S-12703 in a Hive group using the harness of `test/food_library_persistence_test.dart`):
- **S-12701** Edit a bundled food's copy: bundled `almond_butter` added to the library, `editLibraryFood(copy, draft with protein 99, name "My almond")` → the library row has protein 99 / name "My almond"; `getCatalogFoodById('almond_butter')` still has the shipped values; `isSeedEntryTouched(foodCatalog,'almond_butter')` is false. Fails without the change: today the only edit path rewrites the catalog row.
- **S-12702** `lastAmountConsumed` (fixture 250) and `catalogId` survive an edit.
- **S-12703** `canResetLibraryFood`: false for an untouched copy; true after S-12701's edit; false after `resetLibraryFood`; false for a user-created food (non-bundled twin) and for a legacy library-only row.
- **S-12704** `resetLibraryFood` restores every listed field (name, protein, imagePath) to the catalog values and keeps the amount (250) and `id`.
- **S-12705** Editing a user-created catalog food still goes through `updateCatalogFood` and still propagates to its copy (the existing food_library_edit_test.dart guards stay green).
- **S-12706** Image: edit that clears a managed image the catalog row does not hold deletes the file; edit when the copy's path equals the catalog row's path deletes nothing.
- **S-12707** `foodServingLabel`: `Food(referenceAmount 100, label 'ml')` → "100 ml"; `'per 100g'` legacy label → "100 g"-style output identical to the old `_unitLabel` (table of 4 inputs copied from the old behaviour).

Screen (`test/library_row_toggle_test.dart`, new, Mock-first):
- **S-12710** Library, food not in list: row tap adds it (row now shows the check key, `remove_catalog_food_<id>` present, `add_catalog_food_<id>` absent); no `Icons.delete_outline` in the row; no pencil before add.
- **S-12711** In-list row tap shows the remove dialog; Cancel keeps the food; Confirm removes it and, if logged today, unlogs it.
- **S-12712** The in-list row has the primary outline (find the `DecoratedBox`/`Container` border colour == `colorScheme.primary`); the not-in-list row has none.
- **S-12713** Pencil on an in-list bundled food opens `EditFoodScreen` with the library copy (`food.isCatalog == false`); saving changes only the copy (catalog row unchanged); Reset button absent before an edit, present after, and tapping it + confirm restores the shipped values.
- **S-12714** The pencil does not toggle the row (tapping it leaves the food in the list).
- **S-12715** Row text for a bundled food reads "<cal> cal per 100 ml · ..." (exact string from the fixture).
- **S-12716** Source guard on `add_food_screen.dart` `_CatalogRowState`: the statements `onTap: () => _onToggle(context)` (the exact name the builder chooses; builder states it) and the rendered `Icons.edit_outlined` exist; `Icons.delete_outline` and `colorScheme.error` do not appear between the class start and `_UserFoodRow`. The guard asserts the whole statement including brace, not a substring.

Existing tests that encode the old behaviour (grep 2026-10-25; the builder lists each changed assertion): `test/nutrition_test.dart` (59 matches of delete/pencil/My Foods strings; the Library-tab Add/Remove groups), `test/my_foods_unification_test.dart`, `test/screen_widget_test.dart` (`Icons.delete_outline`, row-tap-opens-editor), `test/food_library_edit_test.dart` (22: catalog-edit-propagates stays for user-created foods), `test/food_photo_clear_legacy_edit_test.dart`, `test/header_standardization_test.dart` (only if it taps the Library row), `test/food_library_test.dart`, `test/food_group_membership_test.dart`.

## Phases (serial; one concern each)

- **P1** `crew-builder-app`, state + helper (6 items): D-1, D-2, D-6 helper only, tests S-12701..S-12707. Scope: `lib/state/food_library_state.dart`, `lib/core/utils/food_helpers.dart`, `lib/features/nutrition/widgets/log_food_row.dart` (call site only), `test/food_library_copy_edit_test.dart`. Never runs the full suite.
- **P2** `crew-builder-app`, production UI as exact code from the lead's brief (D-3, D-4, D-5, D-6 row line). Scope: `lib/features/nutrition/edit_food_screen.dart`, `lib/features/nutrition/add_food_screen.dart`. Tests it breaks are fixed in P3.
- **P3** `crew-builder-app`, tests (separate run, copies a named helper block): S-12710..S-12716 in `test/library_row_toggle_test.dart`; fixes the old assertions listed above.
- **P4** `crew-docs-keeper`: `docs/nutrition.md`, `docs/widget_catalog/nutrition_widgets.md`, `docs/state_management/nutrition_state.md`, `docs/navigation_and_screens.md` (the EditFoodScreen row), `docs/data_models.md` only if a field line is stale.
- Then lead: verify, look at the screen at 390x844 on the simulator, prove (mutations), review, fix rounds ≤ 3.

## Owner device checks

- (owner) ODC-1 Library, add a food: row gets the outline and check; tap the row again: asks before removing.
- (owner) ODC-2 Add Almond Butter, tap its pencil, change the calories, save; reopen: "Reset to original" is there; reset: values return.

## Feature invariants

- Only `WorkoutRepository` persists; `HiveWorkoutRepository` and `MockWorkoutRepository` give identical output (S-12701/S-12703 run in both).
- Theme tokens only: outline and check colours from `theme.colorScheme.primary`; no new colour values (D-4, D-5).
- Shared pieces: the reset ask routes through `ConfirmationDialog.showTwoChoice`; no hand-built dialog.
- No `notifyListeners()` during build: `editLibraryFood`/`resetLibraryFood` are awaited UI actions that notify after writes.
- Widget tests run Mock-first; any Hive use is seeded in `setUp`, never inside `testWidgets` (hanging constraint).
- Existing keys `add_catalog_food_<id>` / `remove_catalog_food_<id>` keep resolving (D-5).

## Existing-functionality impact

Searches run 2026-10-25 over `lib/` and `test/` (counts are matches):

| Touched surface | What already reads it (search result) | Effect | Guarded by |
|---|---|---|---|
| `updateCatalogFood(` | 40 matches / 16 files. Lib call sites: `food_library_state.dart:930` (def), `:969` (repo), `edit_food_screen.dart:91,106`, `add_food_screen.dart:438` (`_LegacyLibraryEditScreen._persist`), `catalog_refresh_service.dart:163`; repo iface `workout_repository.dart:586`, `hive:2360`, `mock:1525`. | Only the two `edit_food_screen.dart` calls re-branch (D-3); state method and legacy shim untouched. | S-12705, D-3 |
| `EditFoodScreen.push(` | Lib only: `add_food_screen.dart:1151` (`_UserFoodRowState`, My Foods), `:1418` (`_CatalogRowState`, Library). No `test/` caller. | `:1418` passes the library copy (D-5); `:1151` untouched (77b). | S-12713 |
| `_CatalogRow` | `add_food_screen.dart:530` (doc), `:634` (built in `_FromCatalogTab`), `:1311-1330` (class). | Row rebuilt (D-5, D-6); construction site unchanged. | S-12710..S-12716 |
| `delete_outline` | In scope: `add_food_screen.dart:37` (doc), `:1460` (remove button). `:1124`, `:1885` are My Foods / Groups — untouched. Tests: `nutrition_test.dart:1877,3202,3229` (Library rows); session/set matches unrelated. | `:1460` icon replaced by the check (D-5). | S-12710, S-12716 |
| `remove_catalog_food_` | Lib: `add_food_screen.dart:1450`. Test: `nutrition_test.dart` ×10 (1867–3408). | Key moves onto the tappable check (D-5); assertions re-verified in P3. | S-12710, S-12711 |
| `add_catalog_food_` | Lib: `add_food_screen.dart:1430`. Test: `nutrition_test.dart` ×8 (1841–3341). | Button stays (D-5). | S-12710 |
| `_unitLabel` | `log_food_row.dart:421` (call), `:438` (def). `watch_logging_state.dart:417,545` is `_unitLabelFor` — unrelated. No test matches. | Body moves to `foodServingLabel`; `LogFoodRow` calls it (D-6). | S-12707 |
| `isCatalog` in `food_form.dart` | 0 matches. | `FoodForm` never branches on it; D-3's decision lives in `EditFoodScreen`. | D-3 |

## Edge scenarios

- **S-12708** (state, `test/food_library_copy_edit_test.dart`): after `editLibraryFood`, the copy keeps `isCatalog == false` and its `catalogId`, and `updatedAtMs` > the fixture's 1000. Fails without the change: no edit path exists that writes the copy without rewriting the catalog row.
- **S-12709** (state): `canResetLibraryFood` is false when the copy's `catalogId` names a catalog row that is no longer loaded (fixture: copy with `catalogId: 'ghost_food'`); `resetLibraryFood` on it throws like `updateCatalogFood`'s phantom guard (`food_library_state.dart:936-939`) and the UI never reaches it because the button is gated on `canReset`.
- **S-12717** (screen, `test/library_row_toggle_test.dart`): an in-list user-created catalog food shows the pencil; tapping it opens the editor and saving still goes through `updateCatalogFood` (L-3); the Reset button is absent for it (`canResetLibraryFood` false, S-12703).

## Phase detail

Serial: P1 → P2 → P3 → P4. P2 needs P1's state methods; P3 tests what P2 builds; P4 records the landed behaviour. No parallel phases.

### P1 — state + helper (`crew-builder-app`)
1. [ ] Add `editLibraryFood(Food libraryCopy, FoodDraft draft)` per D-1 — `lib/state/food_library_state.dart` · new method beside `updateCatalogFood` (:930)
2. [ ] Add `canResetLibraryFood` + `resetLibraryFood` per D-2 — `lib/state/food_library_state.dart`
3. [ ] Add `String foodServingLabel(Food food)` (body moved verbatim from `LogFoodRow._unitLabel`, `log_food_row.dart:438`) — `lib/core/utils/food_helpers.dart`
4. [ ] Call `foodServingLabel` from `LogFoodRow` and delete `_unitLabel` — `lib/features/nutrition/widgets/log_food_row.dart:421,438`
5. [ ] Write S-12701..S-12707, S-12708, S-12709 Mock group — `test/food_library_copy_edit_test.dart`
7. [ ] Add `libraryFoodFor` per D-1b + S-12718 (copy returned for an added food, null before add, the edited values after `editLibraryFood`) — `lib/state/food_library_state.dart`, test file
6. [ ] Add the Hive group for S-12701/S-12703 using the harness of `test/food_library_persistence_test.dart` — same file
- **Done Criteria**: `flutter test test/food_library_copy_edit_test.dart test/food_library_edit_test.dart test/food_library_state_test.dart` green (never the full suite); `flutter analyze` = 180 issues, 0 errors.
- **Predicted Files**: the four scope files and nothing else.
- **Write scope**: `--scope lib/state/food_library_state.dart,lib/core/utils/food_helpers.dart,lib/features/nutrition/widgets/log_food_row.dart,test/food_library_copy_edit_test.dart`

### P2 — production UI (`crew-builder-app`; the lead gives the exact code — this phase lists pointers only)
1. [ ] Re-branch `onSave`/`onImageSave` per D-3 — `lib/features/nutrition/edit_food_screen.dart:91,106` · `_EditFoodScreenState.build`
2. [ ] Reset footer per D-4, placement per Open question Q4 — `edit_food_screen.dart` · `_EditFoodScreenState.build`
3. [ ] Correct the stale doc comment claiming an `OmniBottomCTA` Save — `edit_food_screen.dart:20-27`
4. [ ] Row `onTap` → toggle per D-5 — `add_food_screen.dart:1338` · `_CatalogRowState.build`
5. [ ] Replace `_buildRemoveButton` with the check indicator per D-5 — `add_food_screen.dart:1452-1467`
6. [ ] Add the pencil `IconButton` per D-5 (`_openEdit` passes `libraryIdFor(food.id)`'s copy) — `add_food_screen.dart` · `_CatalogRowState`
7. [ ] Primary outline on the in-list row per D-5 — `add_food_screen.dart` · `_CatalogRowState.build`
8. [ ] Macro line per D-6 — `add_food_screen.dart:1345` · `_CatalogRowState.build`
- **Done Criteria**: `flutter analyze` = 180 issues, 0 errors; `flutter test test/food_library_copy_edit_test.dart` still green. Screen tests are expected red here and fixed in P3.
- **Predicted Files**: the two scope files and nothing else.
- **Write scope**: `--scope lib/features/nutrition/edit_food_screen.dart,lib/features/nutrition/add_food_screen.dart`

### P3 — screen tests (`crew-builder-app`, separate run)
1. [ ] Write S-12710..S-12716, S-12717 Mock-first — `test/library_row_toggle_test.dart`
2. [ ] Fix the Library-tab assertions in `test/nutrition_test.dart` (Add/Remove groups; `delete_outline` at :1877, :3202, :3229)
3. [ ] Update `test/screen_widget_test.dart:9646` (S-001 row tap now toggles) and the direct-`EditFoodScreen` tests at :9291, :9360, :9520 if the footer shifts layout
4. [ ] Sweep `test/food_library_test.dart`, `test/food_group_membership_test.dart`, `test/header_standardization_test.dart`, `test/my_foods_unification_test.dart` for Library-row assertions; fix only what 77a changed
- **Done Criteria**: those five files green; `flutter analyze` = 180 issues, 0 errors.
- **Predicted Files**: the six scope test files and nothing else.
- **Write scope**: `--scope test/library_row_toggle_test.dart,test/nutrition_test.dart,test/screen_widget_test.dart,test/food_library_test.dart,test/food_group_membership_test.dart,test/header_standardization_test.dart,test/my_foods_unification_test.dart`

### P4 — docs (`crew-docs-keeper`)
1. [ ] Update the Library-row and edit behaviour text — `docs/nutrition.md`
2. [ ] Update the `_CatalogRow` / `EditFoodScreen` widget entries — `docs/widget_catalog/nutrition_widgets.md`
3. [ ] Update the state-method list (`editLibraryFood`, `canResetLibraryFood`, `resetLibraryFood`) — `docs/state_management/nutrition_state.md`
4. [ ] Update the `EditFoodScreen` row — `docs/navigation_and_screens.md`
5. [ ] Fix a `Food` field line only if stale — `docs/data_models.md`
- **Done Criteria**: docs under 52 KB per file; every behaviour sentence names an existing test.
- **Predicted Files**: the five docs files and nothing else.
- **Write scope**: `--scope docs/nutrition.md,docs/widget_catalog/nutrition_widgets.md,docs/state_management/nutrition_state.md,docs/navigation_and_screens.md,docs/data_models.md`

## Progress

| Item | Result |
|---|---|
| P1.1 `editLibraryFood` | pending |
| P1.2 `canResetLibraryFood` + `resetLibraryFood` | pending |
| P1.3 `foodServingLabel` | pending |
| P1.4 `LogFoodRow` call site | pending |
| P1.5 Mock group S-12701..S-12709 | pending |
| P1.6 Hive group | pending |
| P2.1..P2.8 UI | pending |
| P3.1..P3.4 tests | pending |
| P4.1..P4.5 docs | pending |

## Assumption Log

- **A-1** (lead) Outline is 2 px with the button radius, not 1.5 px with the surface radius: it matches the thumbnail toggle on the same screen family and looked right at 402 pt on the iPhone 17 simulator. Technical, not product.
- **A-2** (lead, owner may overrule) Because the Library row tap is the toggle for every food (owner O-3), tapping an in-list food the user CREATED also asks to remove it; its pencil edits it (save path as before, L-3).
- **A-3** (lead) The Reset button sits pinned under the scrolling form and is decided when the editor opens, so it appears the next time the editor is opened after an edit.
- **A-4** (lead) Review finding 2 (stale snapshot: second photo change in one editor session orphaned a file) was fixed by the lead in `editLibraryFood` (reads the cached row) with S-12706b; fix round 4 would have broken the 3-round cap and the change is ~6 lines. Mutation check: reverting it fails S-12706b.
- **A-5** (lead) Review finding 3 (Reset vs the form's blur auto-save) is not changed: from code the reset write is the last write in every ordering a user can produce; only a pathologically slow repository write could reorder. Recorded as a known risk.

## Feedback

See `2026-10-25-77a-library-edit-own-copy-plan.review.md` once the reviewer writes it.

## Open questions

1. **Q1 (image source)** — `lib/features/nutrition/widgets/food_thumbnail.dart:107-127`: tier 1 renders `imagePath` whenever non-empty; tier 2 resolves the bundled asset with `final resolutionKey = catalogId ?? foodId!`. So a copy with its own `imagePath` displays that photo, and a copy with `imagePath == null` falls back to the shipped photo through `catalogId`. D-1/D-2's image rules are consistent with this. `FoodFormImageTile` (`food_form.dart:950-1034`) delegates to `FoodThumbnail` with the same precedence.
2. **Q2 (draft identity)** — `FoodDraft` (`lib/core/models/food_draft.dart:19-45`) carries NO `id` and NO `catalogId`; its fields are name, groupId, unitType, referenceAmount, referenceLabel, protein, carbs, fiber, fat, sodium, notes, imagePath. Identity comes from the `existing` Food argument, so D-1's `(Food libraryCopy, FoodDraft draft)` signature works. `FoodForm` never checks `isCatalog` (0 matches in `food_form.dart`; the `catalogId` hits at :573, :984, :999, :1034 belong to `FoodFormImageTile`).
3. **Q3 (tests opening the editor)** — no `test/` file calls `EditFoodScreen.push(`. Library-row-tap-expects-editor: `test/screen_widget_test.dart:9646` (S-001, taps 'Chicken breast, skinless', expects 'Edit Food' at :9688) — the only one; P3 rewrites it. Direct `EditFoodScreen` constructions affected by D-3/D-4: `screen_widget_test.dart:9291, :9360, :9520`. My Foods legacy-path tests expecting 'Edit Food' but untouched by 77a: `nutrition_test.dart:3073,3093,3117,3134`, `screen_widget_test.dart:9860`, `food_photo_clear_legacy_edit_test.dart:126`.
4. **Q4 (Reset placement)** — `EditFoodScreen.build` body is exactly `FoodForm(...)` (`edit_food_screen.dart:76-110`); `FoodForm` renders its own scrollable field column and no inline save button (`food_form.dart:747-753`), and no bottom CTA exists on the screen (the doc comment at `edit_food_screen.dart:20-27` claiming an `OmniBottomCTA` with key `food_form_save` is stale — no such widget in the build method). Proposal: `body: Column(children: [Expanded(FoodForm(...)), if (canReset) SafeArea(child: Padding(... OutlinedButton(key: Key('food_reset_original')) ...))])` — the button sits pinned below the scrolling form, outside its scroll, with no CTA to conflict with. `canResetLibraryFood` is evaluated on the `Food` passed at push time, which already satisfies S-12713 (absent before an edit, present after a save + reopen).
5. **D-5 vs L-3 interpretation** — D-5 makes the row tap a toggle for every Library row, so an in-list user-created food's row tap removes it instead of opening the editor; its edit entry point becomes the pencil (D-5), which per D-3 still saves through `updateCatalogFood`. L-3's "edit behaviour unchanged" is read as "the save path is unchanged", not "the row tap still opens the editor". Flagging in case the owner meant the latter.
6. `add_food_screen.dart:1311-1338` doc comment says the remove button is "a square red FilledButton" but it is 88×40 (`_addTrailingWidth`); P2's rewrite should fix that comment with the code.
