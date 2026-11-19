# Review: 77a library-edit-own-copy · P1–P4 · d86bf17f..working tree
Verdict: APPROVE WITH FIXES
Counts: blocker 1 · major 1 · minor 2 · tests: 5589 passed / 2 skipped / 8 failed (all 8 are `test/mix_layer_screen_test.dart`, which the brief records as failing on the untouched base commit d86bf17f)
Diff vs Predicted Files: conforms — exactly the P1–P4 scope files (4 lib, 6 test, 5 docs); the two new test files appear as intent-to-add as the brief says.

## Findings

1. [Blocker] `lib/features/nutrition/add_food_screen.dart:1443-1447` — the in-list outline deviates from decision D-5 on both numbers: D-5 says a "1.5 px outline" with "row radius = the surface radius token already used by neighbouring cards" (`OmniTheme.surfaceBorderRadius`, 20.0, `omni_theme.dart:471`), but the code draws `width: 2` with `BorderRadius.circular(OmniTheme.buttonBorderRadius)` (12.0, the button token). A user sees the row outline corner much tighter than the neighbouring cards it sits among. Fix: use `OmniTheme.surfaceBorderRadius` and width 1.5 — or the owner ratifies 2 px / button radius, in which case D-5, `test/library_row_toggle_test.dart` S-12712 (`expect(border.top.width, equals(2))`, ~line 213) and the two docs sentences that say "2 px" (`docs/nutrition.md` Library-row paragraph, `docs/state_management/nutrition_state.md` AddFoodScreen Library-tab bullet) must say so. Guard: S-12712 (already asserts the width; extend it to assert the radius token).
2. [Major] `lib/state/food_library_state.dart:1017-1025` — `editLibraryFood` evaluates the image-delete rule and the preserved fields on the `libraryCopy` argument, which `EditFoodScreen._save` (`edit_food_screen.dart:67-79`) always builds from the same stale `widget.food` snapshot captured at push time. Two photo changes in one editor session orphan a managed file: pick A writes `imagePath = A` (deleting the stale path), pick B passes the stale snapshot again, so `previousPath` is the pre-session path — the file A is never deleted; and when the stale path equals the catalog row's path, the `previousPath != catalogPath` guard skips the delete of the copy's current managed file entirely. The same staleness feeds `lastAmountConsumed`/`isArchived` back on every autosave; I found no in-app concurrent writer while the editor is open (the editor is a full-screen route; logging happens elsewhere), so that half is theoretical. Fix: inside `editLibraryFood`, take `previousPath` and the preserved fields from the cache's current row (`_foods[libraryCopy.id]`) instead of the argument. Guard: an S-12706 extension that calls `editLibraryFood` twice with the same stale snapshot and different `imagePath`s, asserting the intermediate managed file is deleted.
3. [Minor] `lib/features/nutrition/edit_food_screen.dart:81-95` — `_onReset` is not serialised against the form's blur auto-save: tapping the Reset button (outside the form's `Focus`) unfocuses the form, `FoodForm._onFocusChange` (`food_form.dart:346-351`) fires `_onSave()` unawaited, and the confirm dialog opens while that save is in flight. From code only: the blur save starts at dialog-open time and its `editLibraryFood` write completes long before a human can tap Confirm, so `resetLibraryFood` is the last write and wins; the form's `dispose` path (`food_form.dart:315-341`) saves nothing, so no write happens after pop. The residual risk is a slow repository write landing after the reset write, which would write the pre-reset values back. Fix: have `_onReset` flush any in-flight form save (or set the form's `_saving` guard) before calling `resetLibraryFood`. Guard: a test that starts a save and taps Reset in the same frame asserts the shipped values win.
4. [Minor] `docs/plans/...-plan.md` Assumption Log — empty after a four-phase change whose own Open questions record de-facto assumptions (Q4 Reset placement outside the scroll, Q5's reading of L-3 as "save path unchanged"). Per the project check an empty log after a complex phase is a finding. Fix: the owner rules on Q5 (the reading is implemented: an in-list user-created food's row tap removes, the pencil edits) and Q4, and records the rulings as ratified entries.

## Answers to the brief's five questions

1. **Stale-snapshot autosaves** — yes, the image rule can orphan (finding 2). `lastAmountConsumed`/`isArchived` are carried from the stale snapshot by `copyWith`, but no concurrent writer was found; `resetLibraryFood` is safe (it reads the fresh cache row, `food_library_state.dart:1093-1131`).
2. **`_CatalogRowState` async safety** — safe. `_onToggle` is synchronous and only dispatches. `_onAdd` captures `messenger`/`theme` before its await and guards `mounted` in `finally` (`add_food_screen.dart:1487-1505`). `_onRemove` captures both before the dialog await and guards `!mounted` after it (`:1511-1546`). `_openEdit` has no await. Removal is complete: `_removeTrailingSize` is gone, no dead constant remains, and the class doc no longer says "trashcan" or "square red" (the only `delete_outline`/`colorScheme.error` hits left in the file are My Foods :1113/:1123 and Groups :1910/:2047, which the plan leaves untouched).
3. **Reset vs blur auto-save** — see finding 3: no mutual exclusion in code, but the ordering (blur save fires at dialog open, completes first; dispose saves nothing) means the reset wins in every ordering a user can produce except a pathologically slow repository write.
4. **Other `EditFoodScreen.push` callers** — only two in `lib/`: `add_food_screen.dart:1150` (`_UserFoodRowState`, My Foods) and `:1452` (`_CatalogRowState`). The My Foods call passes `widget.food` only when `isCatalog` is true (user-created; else the legacy shim), and My Foods rows are library copies (`isCatalog == false`) or user-created catalog rows — a bundled catalog row never reaches it. No lib path edits a bundled food through the old catalog-write behaviour.
5. **Tests pass for the right reason** — no vacuous assertion found. The state tests assert specific non-default values (protein 99 vs shipped 3.4, name 'My almond' vs 'Almond butter', `isSeedEntryTouched` false, file `existsSync` false/true), S-12712 asserts the concrete border colour and width, S-12715 asserts exact rendered strings, and the S-12716 source guard asserts whole statements (`onTap: () => _onToggle(context),`) inside the `_CatalogRowState` slice, so it cannot pass on the old code.

## Assumption Log rulings
Log is empty — see finding 4 (owner to rule on Q4/Q5; no code change implied beyond the D-5 numbers in finding 1).

## Scenario coverage
- S-12701 → `test/food_library_copy_edit_test.dart` · Mock + Hive `editLibraryFood changes only the library copy (S-12701)`
- S-12702 → same file · `lastAmountConsumed and catalogId survive an edit (S-12702)`
- S-12703 → same file · `canResetLibraryFood lifecycle (S-12703)` (+ `S-12703b` changed copy of a user-created food)
- S-12704 → same file · `resetLibraryFood restores the shipped values (S-12704)`
- S-12705 → same file · `updateCatalogFood still propagates to the copy (S-12705)`
- S-12706 → same file · `image delete rules on edit (S-12706)` (weakened by finding 2's stale-snapshot gap)
- S-12707 → same file · `foodServingLabel table (S-12707)` (body moved verbatim; 'per 100g' → '100 100g' matches the old `_unitLabel`)
- S-12708 → same file · `edited copy keeps identity fields (S-12708)`
- S-12709 → same file · `ghost catalogId cannot reset (S-12709)`
- S-12710 → `test/library_row_toggle_test.dart` · `S-12710: row tap adds a not-in-list food to the library`
- S-12711 → same file · `S-12711: in-list row tap asks before removing…`
- S-12712 → same file · `S-12712: the in-list row carries the primary outline…`
- S-12713 → same file · `S-12713: pencil on an in-list bundled food edits the copy…`
- S-12714 → same file · `S-12714: the pencil does not toggle the row`
- S-12715 → same file · `S-12715: the row macro line reads the copy after an edit`
- S-12716 → same file · `S-12716: source guard on _CatalogRowState`
- S-12717 → same file · `S-12717: a user-created (non-bundled) in-list food has no Reset button`
- S-12719/S-12720 (lead-added) → same file · routing tests for both save paths
- No scenario is MISSING.

## Lead's disposition (2026-10-25)
1. Blocker (outline numbers): ratified as code (2 px, button radius); D-5 and the docs corrected (A-1). Not a defect of behaviour.
2. Major (stale snapshot): fixed by the lead, S-12706b added, mutation-checked (A-4).
3. Minor (Reset vs blur save): accepted risk (A-5). Owner device check ODC-2 covers it.
4. Minor (empty Assumption Log): filled (A-1..A-5); A-2 is the one the owner may want to overrule.
