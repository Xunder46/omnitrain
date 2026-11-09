# Plan — 133: "Yours" after the macros, and editing a default food makes a food of your own

**Status**: 133a and 133b built, reviewed (1 fix round) and verified by the lead; uncommitted. Evidence: `2026-11-08-133-yours-tag-and-edit-default-plan.evidence.md`; review: `...review.md`.
**Binding conventions**: `docs/global_conventions.md`, `docs/design_system.md` ("Shared pieces and rules per job").
**Base commit**: `fcd727b3afc81a5deb3d1c75712c298809256f61` (branch `claude_develop`; the owner's tree is on that branch, no switch made).
**Evidence**: observed counts are in Progress below.

## Overview

Owner feedback on the nutrition Library (2026-11-08), three points. The owner decided:

1. The calorie ring stays as it is (no change).
2. The **Yours** label moves after the macros so it stops cutting the food name. → **133a** (done).
3. The edit pencil shows on every Library row. Editing a **default** food no longer edits a hidden personal copy: on Save the app
   asks, then creates a new food of the user's own (tagged Yours) and copies the photo too. Owner-approved defaults: if the default
   was in Foods I Eat the new food takes its place there (today's log carries over); if it was not in the list the new food is
   created in the Library only (the user taps Add as for any new food); **Reset to original** goes away; the confirmation uses the
   app's standard confirmation dialog. → **133b**.

The two parts are two PRs (scope budget): 133a is ~40 lines; 133b removes a whole feature (copy-edit and Reset) and adds the copy
flow, so it is split again below into **133b1 (state)** and **133b2 (screens + tests + docs)**.

## Goal and acceptance

133a: on a Library row of a food the user created, the Yours tag sits at the end of the macros line; the name line holds only the name.
Acceptance: S-13301.

133b: acceptance S-13310..S-13320.

## Decision Ledger

| ID | Decision | Backing |
|---|---|---|
| D-13301 | The tag is placed by one private `_MacroLine(text, tagKey)` used by `_CatalogRow` and `_UserFoodRow`; the macros text is `Flexible` so the macros shorten first and the tag never clips | `add_food_screen.dart` `_MacroLine`; S-13301 |
| D-13310 | A **default food** = a Library row that is a bundled catalog row (`isBundledCatalogFood(food.id)`), or the user's copy of one (`catalogId` names a bundled row). Editing any default food saves as a new food of the user's own | `food_library_state.dart:1698` `isBundledCatalogFood` |
| D-13311 | The pencil shows on every `_CatalogRow` (drop the `inList \|\| isYours` condition). A not-in-list default opens the form on the catalog row; an in-list default opens it on the user's copy (so earlier edits show) | `add_food_screen.dart` `_CatalogRowState.build` (`if (inList \|\| isYours)`) and `_openEdit` (`if (bundled && copy == null) return;`) |
| D-13312 | Save on a default food: nothing changed (`FoodFormUnsavedProbe.isDirty` false) → pop, no dialog. Otherwise ask with `ConfirmationDialog.showTwoChoice`, `isDestructive: false`, title `Save as your own food?`, body `<name> is a default food and stays as it is. Saving creates a new food of your own, with its photo copied.`, `Cancel` / `Create copy`, keys `food-copy-cancel` / `food-copy-confirm` (same shape as `food-remove-*`, `food-reset-*`). The words are owner-visible copy: listed in the report | `edit_food_screen.dart` `_onReset` (shape to copy); `confirmation_dialog.dart:33` |
| D-13313 | Confirm creates a **catalog food the user created** through `createCatalogFood` (new id, `isCatalog: true`, no seed-touched marker, never matched as the default's copy). The default's catalog row and its seed marker are untouched | `food_library_state.dart:1276` `createCatalogFood` |
| D-13314 | If the default is in Foods I Eat (`libraryIdFor(catalogId) != null`): carry the day over in this order — read today's amount (`findLoggedTodayForFood(libraryId)`), `unlogFoodToday`, `removeFood(libraryId)`, `createCatalogFood`, `addCatalogFoodToLibrary(newId)`, `logConsumedFoodAt(newLibraryFood, amount)` when it was logged. The default then shows **Add** again. If not in the list: only `createCatalogFood` (not added) | `nutrition_state.dart:532` `logConsumedFoodAt`, `:638` `unlogFoodToday`; precedent for a screen-level two-state helper: `widgets/delete_created_food.dart` |
| D-13315 | Photo: `draft.imagePath` is a managed basename or null (`food_form.dart:handlePickedImage` persists on pick). Non-null → copy that file to a fresh managed file (new basename, same bytes). Null → the default's shipped photo (`FoodPhotoService.bundledPhotoAssetPath(catalogId ?? id)`, a `.webp` asset) is loaded with `rootBundle` and written with `persistImageBytes(bytes, extension: '.webp')`. No shipped asset, no storage service (web stub throws `UnsupportedError`) or any failure → the new food has no photo and the save still succeeds. The replaced library copy's own managed file is deleted afterwards (never the new copy's) | `image_storage_service_io.dart` `persistImageBytes`, `deleteIfManaged`, `resolveOrRelink`; `food_thumbnail.dart` three-tier rule |
| D-13316 | After the swap the user's food is user-created: editing it again goes through `updateCatalogFood` with no dialog (unchanged path) | `edit_food_screen.dart` `_save` |
| D-13317 | **Reset to original** is removed: `food_reset_original`, `_onReset`, `FoodLibraryState.canResetLibraryFood`, `resetLibraryFood` and `editLibraryFood` are deleted with their tests. Library copies the user already edited stay as they are (they are ordinary rows); opening one now offers the copy flow | `edit_food_screen.dart:140`, `food_library_state.dart:1107,1158,1192` |
| D-13318 | New state API: `FoodLibraryState.createOwnCopyOfDefault(Food source, FoodDraft draft, {required bool addToList})` returns the new library id (or the catalog id when not added); it owns D-13313 and D-13315 and the in-list add/remove, but not the log carry (FoodLibraryState has no NutritionState) | decision of the lead |
| D-13319 | The log carry lives in a screen-level helper `saveDefaultAsOwnFood(context, ...)` in `lib/features/nutrition/widgets/save_default_as_own_food.dart` next to `delete_created_food.dart`: it shows the D-13312 dialog, then does the D-13314 sequence | `widgets/delete_created_food.dart` |
| D-13320 | The question is asked from the Save button BEFORE the form's save runs (`EditFoodScreen._onSavePressed` -> `confirmSaveAsOwnFood` -> `_formController.submit()`), not inside `_save`: `FoodForm._onSave` shows `Could not save food` whenever `onSave` returns false (`food_form.dart:488`), so a Cancel inside `_save` would show an error. The controller is the form's only save trigger (`food_form.dart:259`). `saveDefaultAsOwnFood` has no dialog and no snackbar of its own (the form reports a false) | `food_form.dart:454-501` |
| D-13321 | A failed swap puts today's amount back: `saveDefaultAsOwnFood` re-logs it on whichever row is in the list (the old copy if still there, else the new food) in its `catch`, so a storage error cannot lose today's log. The dialog body names the default's own name (`food.name`), not the edited name | decision of the lead (review of the architect's code) |

## Scenarios

| ID | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-13301 | created food `Mine 77 food` in the Library (`_seedCreatedFood`) | the tag's row holds the macros text and not the name; tag x >= macros right edge; name bottom <= tag top | the old row put the tag after the name (observed red on the HEAD source) |
| S-13310 | Library, `chicken_breast` NOT in the list | pencil `edit_catalog_food_chicken_breast` exists; tapping it opens `Edit Food` pre-filled with the shipped name; the row is not toggled | pencil was hidden for a bundled not-in-list row |
| S-13311 | open edit on `chicken_breast`, change protein, tap Save | dialog `Save as your own food?` with the D-13312 body; `Cancel` writes nothing (catalog and library unchanged, screen still open); unchanged form + Save pops with no dialog | no dialog existed; Save wrote the copy path |
| S-13312 | as above, confirm, not in the list | a catalog food with the edited values, `isCatalog`, not bundled, tagged Yours; `chicken_breast` row still shows **Add** and its values/seed marker unchanged; the new food is NOT in Foods I Eat; screen popped | edit of a not-in-list default was impossible |
| S-13313 | `chicken_breast` added, logged today at 150 g, edit protein, confirm | the old copy row is gone; the new food is in Foods I Eat and logged today at 150 (its amount, new macros in `todayConsumedProtein`); `chicken_breast` row shows **Add**; `isFoodLoggedToday(oldCopyId)` false | the old path edited the copy in place and kept one row |
| S-13314 | photo, three cases through `createOwnCopyOfDefault` with a temp-dir `ImageStorageService`: (a) draft `imagePath` null and the default has a shipped photo; (b) draft carries a managed file; (c) draft null and no shipped asset | (a) new `imagePath` is a managed basename whose bytes equal the asset bytes; (b) new basename differs from the old and bytes equal, the old copy's file is gone and the default's own file (if any) survives; (c) `imagePath` null and no throw | no copy existed (the old path shared the file with the copy) |
| S-13315 | S-13312 result, tap its pencil, change, Save | no dialog; `updateCatalogFood` path; row updated | n/a guard for D-13316 (passes before and after: say so in evidence; prover shows it red by sending the user-created food into the dialog branch) |
| S-13316 | Edit screen for a default food that had been edited as a copy (seed a library copy whose name differs from the catalog) | no `Reset to original` button, no `food_reset_original` key; the secondary footer slot is empty | the button existed |
| S-13317 | `createOwnCopyOfDefault` on Mock AND Hive repositories (rows really stored), `addToList` true and false | stored rows match: new catalog row, library row only when added, old copy removed, default catalog row byte-equal | state API did not exist |
| S-13318 | the source guard `S-12716` on `_CatalogRowState` and `S-12818` on `add_food_screen.dart` rewritten for the new rule | guards name the pencil on every row and the copy flow | they pin the old `inList \|\| isYours` and `bundled && copy == null` lines |
| S-13319 | default in list, logged today, edit + Cancel on the dialog | nothing changed: copy still there, log still at old amount | n/a guard (ordering: log is touched only after confirm) |
| S-13320 | Mock-only widget test of the full flow in `library_row_toggle_test.dart` style | the Library row order after the swap: default (Add) and the new food (Yours, in list) both listed, alphabetical | the old path left one row and no second food existed |

## Input-reality checklist (seed answers)

1. Writers: library rows are written by `createCatalogFood`/`addCatalogFoodToLibrary`/`removeFood` (`food_library_state.dart`), logs by
   `NutritionState.logConsumedFoodAt`/`unlogFoodToday`; the wrist reads the library through the foods frame
   (`watch_reference_sync.dart`), which re-sends on the next sync; a wrist-logged entry for today is a `ConsumedFood` keyed by the
   copy's id and is found by the same `findLoggedTodayForFood`. Past days are frozen snapshots.
2. Lifecycle: an archived copy is ignored by `libraryIdFor`; a copy the user edited before this change is an ordinary row that now
   takes the copy flow; a default logged more than once today cannot exist (day-uniqueness).
3. Settings: none change the answer (no unit or week setting is read). Volume/energy units are not involved.
4. Time: the carry reads today at the start and logs "today" at the end; a midnight crossing in those milliseconds would move the
   entry to the new day. Accepted (no test); stated in the Assumption Log.
5. Cost: one pass over the cached foods per save; no extra repository reads beyond the writes.
6. Words: old wording found by grep (see Docs sweep): Reset to original, editLibraryFood, canResetLibraryFood, resetLibraryFood, "pencil on an in-list row", "never edited directly".
7. Competition: a default and the food made from it have the same name; both are listed alphabetically; the Yours tag tells them apart (S-13320).

## Feature invariants

- INV-133-A: the copy flow is state-owned: `createOwnCopyOfDefault` performs the whole in-list swap (create catalog row → remove the replaced copy row → delete the replaced copy's managed file → add the new catalog row); the screen helper never reorders these or calls the repository.
- INV-133-B: the new copy never shares a managed basename with the source (io `copyManagedFileToNewBasename`), and the replaced copy's own managed file is deleted only after its row is removed (`deleteIfManaged` INV-5 no-ops on a missing file).
- INV-133-C: no Save of a default ever mutates the bundled catalog row, its seed-touched marker or a library copy in place (D-13313); every already-edited library copy stays an ordinary row (D-13317) that the user can still edit and delete, saving through `updateCatalogFood`/`updateCustomFood` as today (D-13316).
- INV-133-D: the dialog always precedes every write/log touch (S-13319); an untouched default form pops with no dialog and no writes (D-13312); the log carry's read happens before `unlogFoodToday` so a Cancel cannot lose the amount.
- INV-133-E: a photo-resolution failure inside `createOwnCopyOfDefault` never fails the save — the new food simply has no photo (D-13315 third leg); a state-layer failure never leaves a half-swapped library (the image resolution runs BEFORE `createCatalogFood`).
- INV-133-F: `FoodThumbnail` keeps its three-tier rule and the row's `FoodThumbnail(catalogId: inList ? widget.food.id : widget.food.catalogId)` — the new food's thumbnail renders from its own fresh managed basename.

## Existing-functionality impact

| Touched surface | What already reads it (search result) | Effect | Guarded by |
|---|---|---|---|
| `FoodLibraryState.editLibraryFood` / `canResetLibraryFood` / `resetLibraryFood` deleted | `grep '.editLibraryFood(\|.resetLibraryFood(\|canResetLibraryFood(' lib/` → only `edit_food_screen.dart:132,152,174` (`_save`, `_onReset`, `canReset`) besides the definitions | the screen's default branch is replaced by the copy flow; its `else` leg (a non-catalog food) routes to `updateCustomFood` with the exact arg list copied from `_LegacyLibraryEditScreen._persist` (add_food_screen.dart, shim) so legacy rows and tests that pump EditFoodScreen on a non-catalog row keep working | D-13317, S-13315, S-13316 |
| `ImageStorageService` (io + web stub) gains a method | readers of the service: `FoodThumbnail`/`FoodForm`/profile widgets call only the existing methods | append-only; no existing method changes; the stub throws `UnsupportedError` like the rest | D-13315, S-13314 |
| `add_food_screen.dart` `_CatalogRowState` pencil + `_openEdit` | `test/screen_widget_test.dart` S-001 ("its pencil opens EditFoodScreen"), `test/nutrition_test.dart` row groups, `test/library_row_toggle_test.dart` S-12713/S-12716/S-12719, `docs/widget_catalog/nutrition_widgets.md` `_CatalogRow` | pencil on every row; a not-in-list default opens on its bundled row; a copy's pencil still opens the copy. `S-12818`'s source guard does not pin the pencil (checked: it pins tabs/CTA only) | D-13311, S-13318 |
| `edit_food_screen.dart` footer secondary slot | `test/omni_bottom_cta_secondary_test.dart` cites `Reset to original` in a comment (line 5); `docs/design_system.md:410`, `docs/widget_catalog/layout_and_inputs.md:122` | the slot shows `Delete food` for a user-created food, nothing for a default (D-13317); `OmniBottomCTA`'s own contract unchanged | S-13316, D-13317 |
| `FoodLibraryState.isDefaultFood` (new reader: `edit_food_screen._save`) | new method; the `_save` router is its only production reader | n/a — guarded by its own tests + the copy-flow suite | D-13310, S-13315 |
| `libraryIdFor` identity/legacy fallback unchanged | `isInLibrary`, row toggle, S-12812b | the swap keeps `addCatalogFoodToLibrary(newId)` writing `catalogId == newId`, so the durable lookup finds the new row; the old copy is removed BEFORE the add (would otherwise reuse it, `food_library_state.dart` `addCatalogFoodToLibrary` reuse rule) | S-13317, S-13313 |

## Edge scenarios

| ID | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-13321 | `chicken_breast` in the list, NOT logged today; edit + confirm | no unlog, no log call (neither fired); the new food is in the list and unlogged; the old copy row is gone | n/a guard (leg is optional); prover: red against a mutant that unlogs unconditionally (unlogFoodToday of a not-logged id is a no-op, so the state-based check cannot tell — the Mock spy does) |
| S-13322 | run the S-13312 flow TWICE on the same `chicken_breast` | two user-created foods, both Yours, both listed alphabetically; editing either of them afterwards goes through `updateCatalogFood` with no dialog (D-13310: `isDefaultFood` false for `catalogId`-suffixed ids) | n/a repeat-guard because the first copy is user-created (passes before and after: say so in evidence) |
| S-13323 | pick branch: draft carries a managed basename whose file was deleted before Save; temp-dir service | the copy dialog confirms → `copyManagedFileToNewBasename` `readAsBytes` throws → caught → new food created with `imagePath: null`, save succeeds; the old copy's own file (if any) untouched | n/a new behavior (the old path shared the file) |
| S-13324 | asset branch: shipped photo, service throws on `persistImageBytes` (its `managedDirectoryPath` pointed at a deleted temp dir) | new food created, `imagePath: null`, no throw; old copy row still swapped (the image leg runs before any state write, so nothing else was touched) | n/a new behavior |
| S-13325 | copy the file AFTER the state swap started is impossible: assert instead that `removeFood(oldLibraryId)` happened BEFORE `addCatalogFoodToLibrary(newId)` (Mock spy order) | order recorded: remove→delete-file→add precedes; if the add happens first it would GRAFT the new catalog food onto the still-existing old copy (`libraryIdFor` finds it) and the new row would never enter the list | the old code had no swap at all |
| S-13326 | a default whose library copy is ARCHIVED (`isArchived: true`): pencil on the bundled catalog row, edit, confirm | `libraryIdFor` skips archived rows (existing rule) → treated as not-in-list: new catalog food created, not added; the archived copy row untouched | n/a (checklist 2: archived = removed from list) |
| S-13327 | `chicken_breast` in the list, logged today at 150; the repository's `createCatalogFood` throws (Mock subclass); edit + Confirm | the screen shows `Could not save food` once and stays open; the old copy row is still in the list; `isFoodLoggedToday(oldCopyId)` is true at 150 | the sequence unlogs first; without the restore the log is lost |
| S-13328 | edit + Save + Cancel on the dialog | no `Could not save food` snackbar (find.text findsNothing), the screen stays open, nothing written | a Cancel inside `_save` returns false and the form shows the error |

## Phases

- **133a (done, lead-written)**: `add_food_screen.dart` `_MacroLine`; `test/library_merge_test.dart` S-13301; two doc sentences.
- **133b1 (crew-builder-app, serial)**: D-13318, D-13315, D-13317 state half: add `createOwnCopyOfDefault` and an image-service
  method to copy a managed file (`image_storage_service_io.dart` + `_stub.dart`); delete `editLibraryFood`, `canResetLibraryFood`,
  `resetLibraryFood`; delete `test/food_library_copy_edit_test.dart` and replace it with `test/food_library_own_copy_test.dart`
  (S-13314, S-13317 under Mock and Hive). Exact-text brief for the state method.
- **133b2a (crew-builder-app, after 133b1)**: D-13311, D-13312, D-13314, D-13316, D-13319: the helper, `EditFoodScreen`, the pencil in
  `_CatalogRow`. Exact replacement code in the brief.
- **133b2b (crew-builder-app, separate run, after 133b2a)**: tests S-13310, S-13311, S-13312, S-13313, S-13315, S-13316, S-13318, S-13319,
  S-13320 in a new `test/edit_default_food_test.dart` plus the rewrites of `test/library_row_toggle_test.dart`, `test/edit_food_save_test.dart`,
  `test/library_merge_test.dart` (S-12816 mentions Reset), `test/omni_bottom_cta_secondary_test.dart` (one Reset reference).
- **133b3 (crew-docs-keeper)**: the Docs delta below; then the lead runs `plan-lint.py after`.

## Phases (expanded)

All four phases run serially: 133b2a compiles only against 133b1's `createOwnCopyOfDefault`/`isDefaultFood`/`copyManagedFileToNewBasename`; 133b2b's assertions pin 133b2a's behavior; 133b3 cites 133b2b's rewritten test names. No parallel runs.

### 133b1 (crew-builder-app, serial)

Write scope: `lib/state/food_library_state.dart`, `lib/core/services/image_storage_service_io.dart`, `lib/core/services/image_storage_service_stub.dart`, `test/food_library_state_test.dart`, `test/food_library_own_copy_test.dart` (new). The deletion of `test/food_library_copy_edit_test.dart` is a Governor action.

1. [ ] Add `copyManagedFileToNewBasename(String reference)` to `lib/core/services/image_storage_service_io.dart` `ImageStorageService`, inserted after `persistImageBytes` — code below.
2. [ ] Add the stub twin to `lib/core/services/image_storage_service_stub.dart` `ImageStorageService`, inserted after `persistImageBytes` — code below.
3. [ ] Add `bool isDefaultFood(Food food)` to `FoodLibraryState` (`lib/state/food_library_state.dart`), placed next to `isBundledCatalogFood` — code below.
4. [ ] Add `createOwnCopyOfDefault` + private `_copyImagePathFor` to `FoodLibraryState`, placed after `createCatalogFood`; add imports `../core/services/food_photo_service.dart` and `package:flutter/services.dart show rootBundle;` (the file currently imports neither) — code below.
5. [ ] Delete `editLibraryFood`, `canResetLibraryFood`, `resetLibraryFood` and the `_servingChanged` helper (its only remaining caller) from `FoodLibraryState`.
6. [ ] Create `test/food_library_own_copy_test.dart` with the Mock and Hive groups and the fixtures below; port the surviving `S-12718: libraryFoodFor returns the copy, null before add` test from the deleted `test/food_library_copy_edit_test.dart` into `test/food_library_state_test.dart` (same test name, Hive harness: `HiveWorkoutRepository` with the `_PathProviderChannel` mock copied from the deleted file's fixture, seeded in `setUp`, closed in `tearDown`).

Exact code (133b1):

```dart
// image_storage_service_io.dart — insert after persistImageBytes --------
  /// Copies the managed file named by [reference] to a fresh
  /// `<uuid><ext>` file under the managed directory and returns
  /// that new basename (NOT an absolute path — D-1). Used by
  /// `FoodLibraryState.createOwnCopyOfDefault` when a new food is
  /// made from a default food's photo (plan 133 D-13315): the new
  /// food never shares a managed basename with the source, so
  /// replacing or deleting one cannot remove the other's bytes.
  ///
  /// [reference] may be a basename (the modern contract, D-1) or a
  /// legacy absolute path. The source file is never modified or
  /// deleted. The destination keeps the source file's extension.
  Future<String> copyManagedFileToNewBasename(String reference) async {
    final resolved = _isBasename(reference)
        ? p.join(_managedDir, reference)
        : reference;
    final extension = p.extension(resolved);
    final bytes = await File(resolved).readAsBytes();
    // `persistImageBytes` owns the write and its D-6 cleanup.
    return persistImageBytes(
      bytes,
      extension: extension.isEmpty ? _defaultExtension : extension,
    );
  }

// image_storage_service_stub.dart — insert after persistImageBytes -----
  /// Mirror of `ImageStorageService.copyManagedFileToNewBasename`
  /// in the IO variant. Always throws on web (D-8).
  Future<String> copyManagedFileToNewBasename(String reference) async =>
      _unsupported();

// food_library_state.dart — next to isBundledCatalogFood ---------------
  /// True when [food] is a **default food** (plan 133 D-13310): a
  /// bundled catalog row, or the user's library copy of one
  /// (`catalogId` names a bundled row).
  bool isDefaultFood(Food food) {
    if (isBundledCatalogFood(food.id)) return true;
    final catalogId = food.catalogId;
    return catalogId != null && isBundledCatalogFood(catalogId);
  }

// food_library_state.dart — after createCatalogFood --------------------
  /// Creates a food of the user's own from a **default food** (a
  /// bundled catalog row or the copy of one) and applies the
  /// editor's draft to it (plan 133 D-13313..D-13315). The bundled
  /// catalog row and its seed-touched marker are untouched; the new
  /// food is a plain user-created catalog food and is never matched
  /// as the default's copy.
  ///
  /// Owns the whole in-list swap so no reader sees an intermediate
  /// state (INV-133-A):
  ///
  ///   1. resolve the photo for the new copy (D-13315) — before any
  ///      state write, so a photo failure writes nothing;
  ///   2. `createCatalogFood` with the resolved path;
  ///   3. when the default IS in the list: remove the replaced copy
  ///      row FIRST (addCatalogFoodToLibrary reuses the existing row
  ///      for a catalog id, so the new row must not find the old
  ///      copy there), delete its managed photograph, then
  ///      addCatalogFoodToLibrary with the new id.
  ///
  /// Returns the new library row id when the new food was added to
  /// the list, else the new catalog id.
  Future<String> createOwnCopyOfDefault(
    Food source,
    FoodDraft draft, {
    required bool addToList,
  }) async {
    if (!isDefaultFood(source)) {
      throw StateError(
        'createOwnCopyOfDefault: source must be a default food '
        '(got id ${source.id}, catalogId ${source.catalogId})',
      );
    }
    final imagePath = await _copyImagePathFor(source, draft);
    final newId = await createCatalogFood(
      FoodDraft(
        name: draft.name,
        groupId: draft.groupId,
        unitType: draft.unitType,
        referenceAmount: draft.referenceAmount,
        referenceLabel: draft.referenceLabel,
        protein: draft.protein,
        carbs: draft.carbs,
        fiber: draft.fiber,
        fat: draft.fat,
        sodium: draft.sodium,
        notes: draft.notes,
        imagePath: imagePath,
      ),
    );
    if (addToList) {
      final oldLibraryId = libraryIdFor(source.catalogId ?? source.id);
      if (oldLibraryId != null) {
        final replacedPath = _foods[oldLibraryId]?.imagePath;
        await removeFood(oldLibraryId);
        await _imageStorage?.deleteIfManaged(replacedPath);
      }
      await addCatalogFoodToLibrary(newId);
      return libraryIdFor(newId)!;
    }
    return newId;
  }

  /// D-13315: the photo for the new copy. A picked photo already
  /// lives under the managed directory and is copied to a fresh
  /// basename; an untouched photo re-encodes the default's shipped
  /// `.webp` asset through the managed directory. No service
  /// injected (as in tests) or any failure → the new food has no
  /// photo and the save still succeeds (INV-133-E).
  Future<String?> _copyImagePathFor(Food source, FoodDraft draft) async {
    final svc = _imageStorage;
    final draftPath = draft.imagePath;
    if (svc == null) return draftPath;
    if (draftPath != null) {
      try {
        return await svc.copyManagedFileToNewBasename(draftPath);
      } catch (_) {
        return null;
      }
    }
    final assetPath = FoodPhotoService.bundledPhotoAssetPath(
      source.catalogId ?? source.id,
    );
    try {
      final data = await rootBundle.load(assetPath);
      return await svc.persistImageBytes(
        data.buffer.asUint8List(),
        extension: '.webp',
      );
    } catch (_) {
      return null;
    }
  }
```

Test fixtures (133b1, `test/food_library_own_copy_test.dart`):

- Mock group `FoodLibraryState create own copy (Mock)` (Mock `FoodLibraryState(repo)`, the `test/food_library_copy_edit_test.dart` style), Hive group `FoodLibraryState create own copy (Hive)` (HiveWorkoutRepository with the `_PathProviderChannel` mock, seeded in `setUp`, closed after); Mock-first.
- State tests (Mock + Hive): `createOwnCopyOfDefault not in list adds nothing (S-13317)` — seed `chicken_breast` catalog, not in the list; expect the returned id IS the new catalog id, a new catalog row with the draft's values + `isCatalog: true`, no library row, `isSeedEntryTouched(SeedEntryType.foodCatalog, 'chicken_breast')` false. `createOwnCopyOfDefault in list swaps the row (S-13317)` — add + edit the copy, run `addToList: true`; expect the returned id == the new library row id, the old row id is gone, the new library row's `catalogId` names the NEW catalog row, the bundled catalog row unchanged byte-equal. `createOwnCopyOfDefault (source not a default) throws (D-13310)` — a copy of a user-created catalog food → `throwsStateError`.
- Photo tests (Mock-only, `TestImageStorage.create()` from `test/helpers/test_image_storage.dart`, run async I/O under `tester.runAsync`): S-13314(a) null draft + shipped asset → the new path is a managed basename whose bytes equal the asset bytes; S-13314(b) draft carries a managed basename → new basename differs, bytes equal, after the in-list swap the replaced copy's file is gone and the default's own file survives; S-13314(c) null draft, no shipped asset (`FoodPhotoService.bundledPhotoAssetPath` nice-to-have path missing) → `imagePath: null`, no throw.
- Prove-red: every fixture above is red at the base commit (`createOwnCopyOfDefault` does not exist; the old path has no copy flow at all).

Done criteria (133b1): `flutter test test/food_library_own_copy_test.dart` all green; `flutter test test/food_library_state_test.dart test/food_library_state_delete_guard_test.dart test/food_library_persistence_test.dart test/food_orphan_category_integration_test.dart` all green (regression readers of `FoodLibraryState` — are they intact when the three methods and `_servingChanged` are gone); `flutter analyze` reports ONLY the deleted-method errors in `lib/features/nutrition/edit_food_screen.dart` (editLibraryFood/canResetLibraryFood/resetLibraryFood lines) plus the three test files being rewritten in 133b2b — no other new issue vs. baseline 181; NOT run: the doc-index contract (its citations are fixed in 133b3), the full suite, and never `flutter test` alone (whole-tree compile needs 133b2a).

### 133b2a (crew-builder-app, after 133b1)

Write scope: `lib/features/nutrition/edit_food_screen.dart`, `lib/features/nutrition/add_food_screen.dart`, `lib/features/nutrition/widgets/save_default_as_own_food.dart` (new).

1. [ ] Create `lib/features/nutrition/widgets/save_default_as_own_food.dart` with `saveDefaultAsOwnFood` (exact code below, mirrors `confirmAndDeleteCreatedFood`).
2. [ ] `edit_food_screen.dart` `_save` — exact code below.
3. [ ] `edit_food_screen.dart` — replace the footer `canReset` and the `secondaryLabel` ternary, delete `Future<void> _onReset()`, and update the class doc comment (exact code below).
4. [ ] `add_food_screen.dart` `_CatalogRowState.build` — drop the pencil's `if (inList || isYours)` wrapper, replace the comment above it (exact code below).
5. [ ] `add_food_screen.dart` `_CatalogRowState._openEdit` — exact code below.
6. [ ] `add_food_screen.dart` `_UserFoodRowState._openEdit` — pass `nutritionState: widget.nutritionState` in the `isCatalog` branch (exact code below).

Exact code (133b2a):

```dart
// lib/features/nutrition/widgets/save_default_as_own_food.dart (new) --
import 'package:flutter/material.dart';

import '../../../core/models/food_draft.dart';
import '../../../data/models/models.dart';
import '../../../state/food_library_state.dart';
import '../../../state/nutrition_state.dart';
import '../../../widgets/dialogs/confirmation_dialog.dart';
import '../../../widgets/feedback/omni_message.dart';

/// Asks, then saves a **default food** (a bundled catalog food or the
/// user's copy of one) as a food of the user's own (plan 133
/// D-13312..D-13315).
///
/// The bundled catalog row and its seed marker are never written.
/// When the default is in the user's list, today's log moves to the
/// new food: the amount is read first (INV-133-D), the D-13314
/// sequence runs (unlog, swap), then the carried amount is re-logged
/// on the new library row. Returns true when a confirmed save
/// succeeded; false on Cancel or an error (an error shows a
/// snackbar).
Future<bool> saveDefaultAsOwnFood(
  BuildContext context, {
  required Food food,
  required FoodDraft draft,
  required FoodLibraryState foodLibraryState,
  required NutritionState nutritionState,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final theme = Theme.of(context);
  final confirmed = await ConfirmationDialog.showTwoChoice(
    context: context,
    title: 'Save as your own food?',
    body: Text(
      '${food.name} is a default food and stays as it is. Saving '
      'creates a new food of your own, with its photo copied.',
    ),
    dismissLabel: 'Cancel',
    confirmLabel: 'Create copy',
    dismissKey: const Key('food-copy-cancel'),
    confirmKey: const Key('food-copy-confirm'),
    isDestructive: false,
  );
  if (!confirmed) return false;
  try {
    final oldLibraryId = foodLibraryState.libraryIdFor(
      food.catalogId ?? food.id,
    );
    final amountConsumed = oldLibraryId == null
        ? null
        : nutritionState.findLoggedTodayForFood(oldLibraryId)?.amountConsumed;
    if (oldLibraryId != null && amountConsumed != null) {
      await nutritionState.unlogFoodToday(oldLibraryId);
    }
    final newId = await foodLibraryState.createOwnCopyOfDefault(
      food,
      draft,
      addToList: oldLibraryId != null,
    );
    if (oldLibraryId != null && amountConsumed != null) {
      final newLibraryFood = foodLibraryState.foods.firstWhere(
        (f) => f.id == newId,
      );
      await nutritionState.logConsumedFoodAt(newLibraryFood, amountConsumed);
    }
    return true;
  } catch (_) {
    OmniMessage.errorOn(messenger, theme, 'Could not save food');
    return false;
  }
}

// edit_food_screen.dart _save (replacement is whole-method) ------------
  Future<bool> _save(FoodDraft draft) async {
    final nutrition = widget.nutritionState;
    try {
      // A default food is never written in place (D-13312): an
      // untouched form pops, anything else asks, and a confirmed save
      // creates a food of the user's own through the copy flow
      // (D-13313..D-13315). Without a NutritionState the carry is
      // impossible, so the save cannot run.
      if (widget.foodLibraryState.isDefaultFood(widget.food)) {
        if (!_probe.isDirty) return true;
        if (nutrition == null) return false;
        return await saveDefaultAsOwnFood(
          context,
          food: widget.food,
          draft: draft,
          foodLibraryState: widget.foodLibraryState,
          nutritionState: nutrition,
        );
      }
      if (widget.food.isCatalog) {
        await widget.foodLibraryState.updateCatalogFood(widget.food, draft);
      } else {
        // A non-catalog row here is a legacy library-only custom
        // (the shim's `_persist` carries the exact argument list).
        await widget.foodLibraryState.updateCustomFood(
          id: widget.food.id,
          name: draft.name,
          groupId: draft.groupId,
          unitType: draft.unitType,
          referenceAmount: draft.referenceAmount,
          referenceLabel: draft.referenceLabel,
          protein: draft.protein,
          carbs: draft.carbs,
          fiber: draft.fiber,
          fat: draft.fat,
          sodium: draft.sodium,
          notes: draft.notes,
          imagePath: draft.imagePath,
        );
      }
      return true;
    } catch (_) {
      return false;
    }
  }

// edit_food_screen.dart footer (replacement) --------------------------
    final canDelete =
        widget.food.isCatalog &&
        widget.nutritionState != null &&
        !widget.foodLibraryState.isBundledCatalogFood(widget.food.id);
...
        bottomNavigationBar: OmniBottomCTA(
          label: 'Save',
          buttonKey: const Key('food_form_save'),
          onPressed: _formController.submit,
          // Delete sits above Save in the shared footer, so it shares
          // the height, margins and radius.
          secondaryLabel: canDelete ? 'Delete food' : null,
          secondaryButtonKey: const Key('food_delete_created'),
          onSecondaryPressed: _onDeleteCreated,
          isSecondaryDestructive: true,
        ),

// edit_food_screen.dart class doc comment (replacement) ---------------
/// Edit Food screen — opened from the pencil on a **Library** row
/// (every row offers the pencil, D-13311). Pre-fills the shared [FoodForm]
/// with the given [Food] and carries the same bottom **Save** CTA and
/// unsaved-changes guard as the New Food screen: nothing is written until
/// Save, and leaving with edits asks first.
///
/// What Save does depends on the food:
///   * a **default food** (a bundled catalog row or the user's copy of
///     one, D-13310) — an untouched form pops with nothing written;
///     anything else asks `Save as your own food?` and, on confirm,
///     saves a food of the user's own through [saveDefaultAsOwnFood]
///     (D-13313..D-13315); the default itself is never written.
///   * a **catalog row the user created** saves through
///     [FoodLibraryState.updateCatalogFood] as before.
///
/// Past [ConsumedFood] snapshots stay frozen.
///
/// A food the user created also shows a **Delete food** button (given a
/// `nutritionState`).
///
/// Pure presentation: no repository access; all colors come from
/// [OmniTheme.colors] / `ThemeData.colorScheme`.

// add_food_screen.dart _CatalogRowState.build (pencil block replacement)
            // The pencil on every Library row (D-13311): a bundled food
            // opens the Edit Food screen on the user's copy when it is in
            // the list, else on the bundled catalog row itself; a food the
            // user created opens its catalog row.
            IconButton(
              key: Key('edit_catalog_food_${widget.food.id}'),
              icon: const Icon(Icons.edit_outlined, size: 20),
              color: theme.colorScheme.primary,
              tooltip: 'Edit food',
              onPressed: _busy ? null : () => _openEdit(context),
            ),

// add_food_screen.dart _CatalogRowState._openEdit (replacement) -------
  /// Open the Edit Food screen. A bundled food opens on the user's copy
  /// when one exists in the list (so earlier edits are visible) and on
  /// the bundled catalog row itself when it is not; saving a default
  /// food asks and then creates a food of the user's own (D-13311,
  /// D-13312). A food the user created edits its catalog row, in the
  /// list or not.
  void _openEdit(BuildContext context) {
    final copy = widget.foodLibraryState.libraryFoodFor(widget.food.id);
    final bundled = widget.foodLibraryState.isBundledCatalogFood(
      widget.food.id,
    );
    final edited = bundled && copy != null ? copy : widget.food;
    EditFoodScreen.push(
      context,
      food: edited,
      foodLibraryState: widget.foodLibraryState,
      nutritionState: widget.nutritionState,
    );
  }

// add_food_screen.dart _UserFoodRowState._openEdit (isCatalog branch) -
    if (widget.food.isCatalog) {
      EditFoodScreen.push(
        context,
        food: widget.food,
        foodLibraryState: widget.foodLibraryState,
        nutritionState: widget.nutritionState,
      );
    } else {
      ... // shim branch unchanged
```

Note: the doc-comment `[saveDefaultAsOwnFood]` link needs the import BEFORE the comment compiles — the import is part of item 3. The `ConfirmationDialog` import STAYS (the unsaved-changes dialog uses `showUnsavedChanges`).

Done criteria (133b2a): `flutter analyze` reports only the test-file issues being rewritten in 133b2b (production files compile); `flutter test test/screen_widget_test.dart test/food_photo_clear_legacy_edit_test.dart test/food_form_pick_saves_test.dart test/food_library_edit_test.dart` all green — these prove the untouched read paths (S-001 pencil flow, the legacy shim, the pick flow, the updateCatalogFood propagation) survive.

### 133b2b (crew-builder-app, separate run, after 133b2a)

Write scope: `test/edit_default_food_test.dart` (new), `test/library_row_toggle_test.dart`, `test/edit_food_save_test.dart`, `test/library_merge_test.dart`, `test/omni_bottom_cta_secondary_test.dart`.

1. [ ] Create `test/edit_default_food_test.dart` (Mock-only widget group, the `_freshRepo` harness copied from `test/library_row_toggle_test.dart`; every copy-flow test passes a `NutritionState` so the dialog path is reachable) — one test per S-13310..S-13316, S-13318, S-13319, S-13320 (fixtures below).
2. [ ] `test/library_row_toggle_test.dart`: rewrite the S-12713 pencil test as the copy-flow test; rewrite the S-12716 source guard for the new rule; replace the S-12719 routing test (its old `find.text('Reset to original')` behavior is covered by the copy flow) with a pinned-dialog test on the untouched form (D-13312).
3. [ ] `test/edit_food_save_test.dart`: rewrite S-92a.3's inline `_editLibraryFood` calls and the S-92a.7 routing test (the pin on `editLibraryFood` disappears with the helper) — rewrite the whole copy-flow fixture per the new tests.
4. [ ] `test/library_merge_test.dart`: rewrite the S-12812b footer-slot test (Reset keys) and the S-12816 Reset dialog half; keep the S-12818 source guard and the S-12810..S-12815 rows exactly.
5. [ ] `test/omni_bottom_cta_secondary_test.dart`: the comment on line 5 changes to `Delete food`.
6. [ ] The deleted `test/food_library_copy_edit_test.dart` test-name citations in the docs (rows below) — the rewrite of each doc row happens in 133b3, but splice the mock/Hive `_freshRepo` reuse by this file (they share ONE test file's naming) into `test/food_library_own_copy_test.dart` when 133b1 lands (J the name is already the plan there).

Exact scenario fixtures (133b2b):

- S-13310 `pencil on a not-in-list bundled row opens the bundled row`: `pumpLibraryTab` with `chicken_breast` NOT in the list; expect `find.byKey(Key('edit_catalog_food_chicken_breast'))` EXISTS; tap → the Edit Food screen title reads `Edit Food`, the form shows the bundled name; the tag row is still untagged (no log happened).
- S-13311 `the copy-dialog text`: as S-13310; tap the pencil; `enterText` on the name field 'Grandma edit'; tap `food_form_save`; expect a dialog with the title. `Save as your own food?` and the exact body `Grandma edit is a default food and stays as it is. Saving creates a new food of your own, with its photo copied.`; the dialog's Cancel key is `food-copy-cancel`, Confirm is `food-copy-confirm`; tap Cancel → no write: `state.catalogFoods` has no `Edit Food`-added row and the row is still not-in-list... wait, correct that: the copy flow is NOT permitted yet (the dialog's Cancel leg) → `state.catalogFoods` still shows 0 user-created catalog rows beyond the bundled one + and the edit screen is STILL OPEN with the typed name (not popped) — assert `find.text('Edit Food')` findsOneWidget; unchanged form + Save pops with NO dialog (D-13312 pop leg).
- S-13312 `confirm creates the food of the user's own (not-in-list)`: as S-13311 but Confirm → the new catalog row exists (named `Grandma edit`, Mock roster by `CatalogFoodsForTest` or `state.catalogFoods`), `isCatalog: true`, `isDefaultFood(newRow)` false, NOT in the list (the Library row renders the OLD bundled chicken), the screen popped, `isSeedEntryTouched(SeedEntryType.foodCatalog, 'chicken_breast')` false.
- S-13313 `log carry when in list and logged`: add `chicken_breast` to the list, log today via `nutrition.logConsumedFoodAt(copy, 150)`, edit, Confirm → the old copy row is gone (`state.libraryFoodFor('chicken_breast')` is null), the new food is in the list, `nutrition.todayConsumedProtein` reflects the NEW macros at the carried 150 amount, `isFoodLoggedToday(oldCopyId)` false, `isFoodLoggedToday(newLibraryId)` true, the bundled row shows the `Add` button again.
- S-13315 `a food of the user's own saves without a dialog`: after the S-13312 flow, open the pencil on the new food, edit again, Save → no dialog, the catalog row updated in the Mock (an unlogged: the row's `updatedAtMs` advanced).
- S-13316 `no Reset to original button`: on an edited copy's editor (seed a library copy whose name differs from the catalog like `edit_food_save_test.dart::_seedEditedLibraryCopy` but through `addCatalogFoodToLibrary` + `updateFood` or the copy flow), expect `food_reset_original` findsNothing, `find.text('Reset to original')` findsNothing, and the secondary footer slot is EMPTY for a default (a user-created catalog food still shows `Delete food` there).
- S-13318 `source guards`: `edit_food_screen.dart` `contains('isDefaultFood')` and `isNot(contains('editLibraryFood'))`; `save_default_as_own_food.dart` `contains('saveDefaultAsOwnFood')`; `add_food_screen.dart` `isNot(contains('if (inList || isYours'))`.
- S-13319 `Cancel on the dialog preserves everything`: the S-13313 fixture + Cancel instead of Confirm → all rows unchanged, `isFoodLoggedToday(oldCopyId)` true (the log was never touched).
- S-13320 `the row order after the swap (alphabetically)`: after the S-13312 confirm, the Library rows contain BOTH the bundled `chicken_breast` (Add) and the new food (Yours, in list) in the alphabetical order the Library list renders — assert the found order by index.

Predicted files (133b2b): the five test files only.

Done criteria (133b2b): `flutter test test/edit_default_food_test.dart test/library_row_toggle_test.dart test/edit_food_save_test.dart test/library_merge_test.dart test/omni_bottom_cta_secondary_test.dart` all green; `flutter analyze` back to the 181-issue baseline; `flutter test test/screen_widget_test.dart test/nutrition_test.dart` still green (S-001 and the row groups untouched).

### 133b3 (crew-docs-keeper)

Write scope: the seven docs of the completed table; then the lead runs `plan-lint.py after`.

1. [ ] `docs/nutrition.md` — rows 1, 2 and the ADDITIONAL-delta rows (see the completed table).
2. [ ] `docs/state_management/nutrition_state.md` — remove the method table rows + the heading; update the pencil bullet; move the `libraryFoodFor` citation.
3. [ ] `docs/data_models.md` — the bundled-catalog bullet + its citation tail.
4. [ ] `docs/design_system.md` — the bottom-CTA wording.
5. [ ] `docs/widget_catalog/layout_and_inputs.md` — the `OmniBottomCTA` sentence.
6. [ ] `docs/widget_catalog/nutrition_widgets.md` — the `editLibraryFood`-named paragraph, the delete-pool sentence, the `_CatalogRow` paragraph and its citations.
7. [ ] `docs/navigation_and_screens.md` — the `EditFoodScreen` row + its citation tail.
8. [ ] Run `flutter test test/docs_indexing_contract_test.dart test/ui_standards_contract_test.dart` (green = the doc/test-name citation graph survived the rewrites).

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| `docs/nutrition.md` | MODIFIED | `**Reset to original**; the two never appear together` | `Save as your own food?` first | D-13312, S-13311 |
| `docs/nutrition.md` | MODIFIED | `saves through `FoodLibraryState.editLibraryFood`` | `FoodLibraryState.createOwnCopyOfDefault` — a new catalog food of the user's | D-13318, S-13317 |
| `docs/nutrition.md` | REMOVED | `a `Reset to original` button (key` | - | D-13317, S-13316 |
| `docs/nutrition.md` | MODIFIED | `are state methods too (`editLibraryFood`,` | `createOwnCopyOfDefault` is a state method; the copy flow's log | D-13319, S-13313 |
| `docs/state_management/nutrition_state.md` | REMOVED | `##### Edit your copy / Reset to original (plan 77a)` | - | D-13317 |
| `docs/state_management/nutrition_state.md` | REMOVED | `editLibraryFood(Food libraryCopy, FoodDraft draft)` | - | D-13317 |
| `docs/state_management/nutrition_state.md` | REMOVED | `canResetLibraryFood(Food libraryCopy)` | - | D-13317 |
| `docs/state_management/nutrition_state.md` | REMOVED | `resetLibraryFood(String libraryId)` | - | D-13317 |
| `docs/state_management/nutrition_state.md` | MODIFIED | `the pencil on an in-list row opens `EditFoodScreen`` | the pencil on every Library row opens `EditFoodScreen` | D-13311, S-13310 |
| `docs/data_models.md` | MODIFIED | `editing changes the user's library copy (`FoodLibraryState.editLibraryFood`)` | editing a default food creates a new food of the user's own (`FoodLibraryState.createOwnCopyOfDefault`) | D-13313, S-13312 |
| `docs/design_system.md` | MODIFIED | `Reset to original on the food editor)` | that belongs with the primary one but must not compete with it (Delete food | D-13317 |
| `docs/widget_catalog/layout_and_inputs.md` | MODIFIED | `The food editor uses it for **Delete food** and **Reset to original**.` | The food editor uses it for **Delete food**. | D-13317 |
| `docs/widget_catalog/nutrition_widgets.md` | MODIFIED | `` `FoodLibraryState.editLibraryFood`, which changes only the copy `` | `FoodLibraryState.createOwnCopyOfDefault`, which makes a | D-13318 |
| `docs/navigation_and_screens.md` | MODIFIED | `A library copy of a bundled catalog food saves through `FoodLibraryState.editLibraryFood`` | A default food saves, after a confirmation, as a new food of the user's own through `FoodLibraryState.createOwnCopyOfDefault` | D-13312, S-13311 |
| `docs/nutrition.md` | MODIFIED | `**Reset to original** and **Delete food** keep their own confirmation and pop` | `**Delete food** keeps its own confirmation and pops directly` | D-13312, S-13311 |
| `docs/nutrition.md` | REMOVED | `resetLibraryFood restores the` | - | D-13317 |
| `docs/nutrition.md` | REMOVED | `Edit screen routes a bundled copy's save through editLibraryFood` | - | D-13317 |
| `docs/nutrition.md` | MODIFIED | `S-12713: pencil on an in-list bundled` | `S-12713: the pencil on an in-list bundled food opens its | D-13311, S-13318 |
| `docs/nutrition.md` | REMOVED | `test/food_library_copy_edit_test.dart` (group `FoodLibraryState edit own copy` | - | D-13317 |
| `docs/state_management/nutrition_state.md` | REMOVED | `S-12719: the Edit screen routes a bundled copy's save through editLibraryFood` | - | D-13317 |
| `docs/state_management/nutrition_state.md` | MODIFIED | `EditFoodScreen` calls `editLibraryFood(copy, draft)` | `EditFoodScreen` saves a default through the screen helper `saveDefaultAsOwnFood` | D-13319, S-13313 |
| `docs/state_management/nutrition_state.md` | MODIFIED | Verified by `test/food_library_copy_edit_test.dart` (`libraryFoodFor returns the copy` | Verified by `test/food_library_state_test.dart` (group `FoodLibraryState libraryFoodFor (Hive)` | D-13318 |
| `docs/data_models.md` | REMOVED | `updateCatalogFood still propagates to the copy (S-12705)` | - | D-13316 |
| `docs/widget_catalog/nutrition_widgets.md` | MODIFIED | `screen routes a bundled copy's save through editLibraryFood` | `Edit a default food (plan 133)` | D-13318 |
| `docs/widget_catalog/nutrition_widgets.md` | MODIFIED | `editLibraryFood`, `updateCustomFood`) owns the D-7 delete | `createOwnCopyOfDefault`, `updateCustomFood`) owns the D-7 delete | D-13315 |
| `docs/widget_catalog/nutrition_widgets.md` | REMOVED | `in-list bundled food edits the copy; reset restores the shipped values` | - | D-13317 |

The architect completes the table from this sweep (every hit is a row; test names in the docs that cite deleted tests are REMOVED
rows): `grep -rIn "Reset to original\|resetLibraryFood\|canResetLibraryFood\|editLibraryFood\|food_reset_original\|pencil on an in-list\|in-list bundled\|never edited directly" docs | grep -v "docs/plans\|docs/history\|docs/releases"`.
Known hits not yet in rows: `docs/nutrition.md` lines near 242, 334-348, 473-476; `docs/widget_catalog/nutrition_widgets.md` near 256 and 351.
Sweep completion (architect run): every hit is now a row above — `docs/nutrition.md` 167, 244, 307, 328-348, 475-476; `docs/state_management/nutrition_state.md` 144, 148-151, 184; `docs/data_models.md` 415; `docs/design_system.md` 410; `docs/widget_catalog/layout_and_inputs.md` 122; `docs/widget_catalog/nutrition_widgets.md` 171, 174, 256, 351; `docs/navigation_and_screens.md` 184; `docs/global_conventions.md` no hits.

## Code pointers (CURRENT lines)

- `add_food_screen.dart` `_CatalogRowState.build`: `if (inList || isYours)` guards the pencil; `_openEdit`: `if (bundled && copy == null) return;` then `final edited = bundled ? copy! : widget.food;`.
- `edit_food_screen.dart:127` `_save`: `if (widget.food.isCatalog) { await ...updateCatalogFood(...) } else { await ...editLibraryFood(...) }`; `:172` `canReset`; `:221-230` footer secondary slot (Reset or Delete).
- `food_library_state.dart:971` `addCatalogFoodToLibrary`, `:1276` `createCatalogFood`, `:576` `removeFood`, `:640` `libraryIdFor`, `:1247` `libraryFoodFor`.
- `widgets/delete_created_food.dart` `confirmAndDeleteCreatedFood` (shape of a screen-level helper that touches both states).
- Test helpers to copy: `library_row_toggle_test.dart` (pump the Library tab on Mock), `library_merge_test.dart` `pumpLibraryTab`, `_freshRepo`, `_seedCreatedFood`.
- (architect) `nutrition_state.dart:506` `findLoggedTodayForFood`, `:516` `isFoodLoggedToday`, `:532` `logConsumedFoodAt(Food, double)`, `:633` `unlogFoodToday` (returns bool, `deleteConsumedFood` underneath); `ConsumedFood.amountConsumed` is the carried field.
- (architect) `lib/core/services/food_photo_service.dart:24` `FoodPhotoService.bundledPhotoAssetPath(String foodId)` → `assets/images/food_<id>.webp`, no existence check; `food_library_state.dart:96` `List<Food> get foods`, `:135` `imageStorageOrNull`.
- (architect) `image_storage_service_io.dart` `_isBasename` is private static; `deleteIfManaged(String?)` no-ops on a missing file (INV-5); `persistImageBytes(bytes, {extension})` asserts a leading dot and owns the D-6 cleanup.
- (architect) `test/food_photo_clear_legacy_edit_test.dart` pumps the Library tab and opens the legacy shim editor on a legacy custom row — it does NOT open `EditFoodScreen` and does not touch the copy flow (no rewrite needed).
- (architect) `test/library_row_toggle_test.dart:444` guard asserts `edit_food_screen.dart` CONTAINS `editLibraryFood` — the S-12716 rewrite flips it to `isNot(contains('editLibraryFood'))` (red at base, green after 133b2a).

## Progress

- [x] 133a built by the lead. Red without the change (the HEAD source restored `cmp`-identical afterwards): S-13301 failed at `test/library_merge_test.dart:170`. Green with it: `flutter test test/library_merge_test.dart` `+12: All tests passed!`. `test/ui_standards_contract_test.dart` + `test/docs_indexing_contract_test.dart`: `+54: All tests passed!`. `flutter analyze`: 181 issues (same as the last baseline). Invariant grep: nothing.
- [x] 133b1, 133b2a, 133b2b, 133b3 built by the crew; review fix round 1 done. Full suite `+7081 ~2: All tests passed!`, analyze 181, 14 mutants killed (evidence file).
- [ ] (owner) Look at the Library on a phone: Yours after the macros on a long food name; pencil on a default food; the Save-as-your-own dialog wording; the new food and its photo.
- [x] Architect plan written (this run, 2026-11-08-133): invariants, impact table, S-13321..S-13326, four expanded phases with exact code, docs delta completed from the sweep. 133b1..133b3 remain unchecked below.

## Assumption Log

- Unchanged form + Save on a default food pops with no dialog and creates nothing (owner not asked: lowest-surprise reading of "saves a copy").
- A default edited before this change keeps its edits as an ordinary row; its Reset is gone with no replacement.
- Midnight crossing during the carry is not handled (D-13314, checklist 4).
- On web the photo is not copied (the image service is a stub there).
- (architect) The copy flow's unlog step runs BEFORE the state swap (D-13314 order); a throw between unlog and re-log loses today's entry for the default — accepted, same family as the midnight-crossing note above.
- (architect) The not-in-list branch of the pencil opens `EditFoodScreen` on the bundled catalog row, whose Save runs the `updateCatalogFood` leg for a user-created food but the copy flow for a bundled one — the dialog decides, the row type does not.
- (architect) `saveDefaultAsOwnFood` uses `foods.firstWhere` to fetch the new library row; a missing row would throw into the helper's catch and show the snackbar, leaving a created-but-not-listed catalog row. Accepted (it cannot happen: the state just inserted the row).
- (architect) `test/food_form_pick_saves_test.dart` / `test/food_photo_clear_legacy_edit_test.dart` exercise the pick/clear paths, which don't route through the copy flow; the sweep that could have proved their independence more deeply was out of scope for this run (grep coverage listed in Open questions).

## Open questions

1. `docs/global_conventions.md` — not re-read this run; the plan keeps the seeded conventions references and adds no new convention. If a required section heading is missing, `plan-lint.py after` will flag it (Governor action: run it and report).
2. Scope budget: `.github/copilot/pr-scope-budget.md` not read this run; the four seeded sub-phases are kept and each phase's write scope is ≤ 6 files, inside the seeded split. If a phase busts a phase-size budget, the part-A/part-B split is already stated (133b2a and 133b2b are separate runs).
3. `firstOrNull` from `package:collection` was avoided in the exact code; `foods.firstWhere` is used instead — plain core.
4. The `foods`/`catalogFoods` getters return COPIES (`values.toList()`); `logConsumedFoodAt(newLibraryFood, …)` gets the copy — fine for ConsumedFood construction (it reads fields only).
5. Is there an `EditFoodScreen` reader that pumps it on a bundled copy WITHOUT a NutritionState besides `test/library_row_toggle_test.dart:434` (S-12719)? `grep` found pumpWidget hosts in `test/library_row_toggle_test.dart` and `test/edit_food_save_test.dart`; both are rewritten in 133b2b. `test/screen_widget_test.dart` pumps `AddFoodScreen`, never `EditFoodScreen` directly (not checked beyond the S-001 name cited in `docs/widget_catalog/nutrition_widgets.md`).

## Feedback

(empty)

## Architect notes

- Every production-code claim in this expansion was re-verified against the files on disk this run (base commit `fcd727b`): the seeded Code-pointer line numbers match the current files (`edit_food_screen.dart:132/152/174`, the `if (inList || isYours)` and `if (bundled && copy == null) return;` lines).
- The `else` leg of the new `_save` routes to `updateCustomFood` with the shim's exact argument list: deleting `editLibraryFood` would otherwise break the legacy shim contract (`_LegacyLibraryEditScreen._persist` is the reference).
- `createCatalogFood(FoodDraft draft)` builds its own row (no `catalogId` field on the draft, fresh id inside the state), so the copy flow needs no source-row mutation — the new catalog row is created from the draft alone.
- `addCatalogFoodToLibrary` reuses the existing library row for a catalog id (`libraryIdFor` on add), which is why the replaced copy row MUST be removed before the add (S-13325).
- Widget tests that drive `FoodForm.onSave(draft)` directly (S-12719 style) bypass the typed-field probe, so `_probe.isDirty` is false and the D-13312 pop leg would swallow the dialog; the rewritten tests instead type into the name field and tap `food_form_save`.
- `_servingChanged` (state, ~782) is deleted WITH `editLibraryFood` (its only remaining caller); `_servingTripleChanged` (~791) stays — other call sites.
