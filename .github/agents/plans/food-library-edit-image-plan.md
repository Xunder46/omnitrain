# Food Library — Edit + Image + Fiber Enhancement Plan (Iteration 3 — corrected scope)

## Overview

The user has two distinct food surfaces in this app:

- **User's personal library** — the foods the user has chosen to log against (rendered as `LogFoodRow` items on the `NutritionScreen`). This is for **logging only** and was not in scope for this feature request.
- **Global managed library** (the catalog-style list in the **Library** tab of `AddFoodScreen`) — the bundled set of 107 foods that ship with the app, browseable, searchable, and add-or-remove-from-personal-library from each row. This is the **management** surface the user wants to enhance.

Iteration 1 / Iteration 2 of this plan misread the request and applied the changes to the wrong surface. Iteration 3 corrects the scope:

- The "Add / Remove" affordance is **already** on the global library rows in the **Library** tab of `AddFoodScreen` (it is the **+** or trashcan button on the right of each row). No change needed.
- The "+ New Item" tab currently writes to the user's personal library. Per the user's request — "Every new food the user creates, needs to go into the main library" — this iteration moves the create path so the new food is added to the **global managed library** (the catalog), not the personal library. The "Add" / "Remove" affordance for the personal library then makes the new catalog food available to log.
- The "Edit Food" screen was wrongly built for the user's personal library. This iteration moves the edit affordance to the **global managed library** row tap.
- The image thumbnail is moved from `LogFoodRow` (user's library) to the **catalog row** in `AddFoodScreen`'s **Library** tab.
- The `Food.imagePath` field, the `FoodForm` widget, the `FoodThumbnail` widget, and the `FoodDraft` parameter object are all kept — they are correct, just re-wired to the catalog.

The personal library (`LogFoodRow`) is reverted to its pre-iteration state: no thumbnail, no row-tap edit affordance.

---

## Requirements

- Every food in the **global managed library** (the catalog) can be edited.
- Tapping a row in the **Library** tab on `AddFoodScreen` opens the **Edit Food** screen, prefilled with the food's data.
- The edit screen mirrors the create screen: same `FoodForm` widget, same validation, same save semantics.
- The "**+ New Item**" tab now writes the new food to the **global managed library** (the catalog), not the user's personal library. The "Add / Remove" affordance on the **Library** tab then makes the new food available to log.
- Both the create and edit forms expose a `Fiber` field next to `Carbs` and an image picker at the very top of the form.
- The image field is optional; the picker supports camera and gallery sources on native and gracefully reports "photo selection works on web but persistence is not supported there yet" on web, matching the existing avatar pattern.
- The **Library** tab on `AddFoodScreen` shows a small image thumbnail on the left of each row.
- The `LogFoodRow` (user's personal library) is reverted to its pre-iteration state.
- Backwards-compatible: legacy `Food` rows without an image deserialize to `imagePath == null`.
- `ConsumedFood` snapshots in past day logs are unaffected: the snapshot model does not include the image, so historical rows render with their original data.

---

## Acceptance Criteria

- [ ] `Food.imagePath` field exists (`String?`, native-first local path). ✅ (carried over from iteration 1)
- [ ] `Food.fromMap` / `Food.toMap` round-trip `imagePath` (nullable). ✅ (carried over from iteration 1)
- [ ] `Food.copyWith` supports clearing `imagePath` (sentinel-backed pattern, matching `groupId`). ✅ (carried over from iteration 1)
- [ ] `WorkoutRepository` exposes `updateCatalogFood(Food)` and `createCatalogFood(Food)` so the global managed library is mutable at runtime.
- [ ] `FoodLibraryState.updateCatalogFood` is callable on a pre-existing catalog `Food`; the cache reflects the updated row and listeners are notified.
- [ ] `FoodLibraryState.createCatalogFood` is callable to insert a new user-authored food into the global managed library.
- [ ] The **+ New Item** tab on `AddFoodScreen` calls `createCatalogFood` (not `createCustomFood`).
- [ ] Tapping a row in the **Library** tab on `AddFoodScreen` opens the **Edit Food** screen for that food.
- [ ] The form has a `Fiber (g)` field between `Carbs (g)` and `Fat (g)`, plus a `Sodium (mg)` field as an additional optional macro.
- [ ] The form has an image picker at the top: a square tap target that shows a placeholder when empty and the picked image when filled. The picker has a small × overlay to clear the image and reverts to placeholder.
- [ ] The **Library** tab on `AddFoodScreen` shows a 40×40 image thumbnail (rounded 8 px) on the left of each catalog row. The slot is always present (placeholder when no image) so the trailing Add / Remove button does not jump when an image is added or removed.
- [ ] The user's personal library (`LogFoodRow` on `NutritionScreen`) is reverted: no thumbnail, no row-tap edit affordance, no edits triggered from a library row tap.
- [ ] All buttons in the new screen and in the modified catalog row follow the explicit `shape:` + `OmniTheme.button*Radius` contract.
- [ ] `flutter test` is green; the new tests prove the scenarios below.

---

## Scenarios

### S-001: Edit a catalog food from the global library
- Trigger: User opens the **Library** tab on `AddFoodScreen`, taps any catalog row.
- Precondition: A catalog `Food` row exists (bundled or user-created via **+ New Item**).
- Flow: User taps the row → `OmniNavigator.push` to the **Edit Food** screen pre-filled with the food's name, group, unit type, reference, macros, and image (if any) → user changes protein from 31 to 35 and taps **Save** → screen pops back to the **Library** tab.
- Expected outcome: `FoodLibraryState.catalogFoods` reflects the updated protein (35). The catalog row in the **Library** tab shows the new macro grid. `notifyListeners()` was called at least once after the save. The user's personal library is unaffected.
- Coverage: `test/food_library_edit_test.dart` (new).

### S-002: New food created via **+ New Item** is added to the global library
- Trigger: User opens the **+ New Item** tab on `AddFoodScreen`, fills the form, and saves.
- Precondition: User has not previously created a food with the same name.
- Flow: User fills the form (name, group, unit type, reference, macros, optional image) and taps **Save** → the screen pops back, the **Library** tab is the active tab.
- Expected outcome: The new food appears in the **Library** tab's alphabetical list with `isCatalog == true`. The user can tap **Add** on its row to make it available to log.
- Coverage: `test/food_library_edit_test.dart` (new).

### S-003: Edit form pre-fills all fields including image
- Trigger: User opens a catalog food for edit.
- Precondition: The food has `imagePath = '/path/to/photo.jpg'`, name `'Chicken'`, protein 31, carbs 0, fiber 0, fat 4.
- Flow: Edit screen opens.
- Expected outcome: The form's `name`, `protein`, `carbs`, `fiber`, `fat`, `unitType`, `referenceAmount`, `referenceLabel`, `groupId` controllers are pre-populated with the food's values. The image preview at the top shows the image (the `FoodThumbnail` widget is reused). If the image does not exist on disk (test path), the preview falls back to a placeholder.
- Coverage: `test/food_library_edit_test.dart` (new).

### S-004: Image picker writes to `imagePath` and clearing the image nulls it
- Trigger: User opens a food for edit, taps the image tile, picks a photo from the gallery, then taps the × overlay on the preview to clear.
- Precondition: Web is treated as "photo selection works but persistence is not supported" — the picker is a no-op (no path stored). On native, the picker stores the picked file's path on the food.
- Flow: Pick → image preview shows the picked photo → tap × → preview returns to placeholder → save.
- Expected outcome: On save, the food's `imagePath` is the picked path (native) or remains `null` (web). After clearing, the saved `imagePath` is `null`. Past `ConsumedFood` rows for this food are not modified (snapshot model does not include the image).
- Coverage: `test/food_library_edit_test.dart` (new); widget test for the clear overlay in `test/screen_widget_test.dart`.

### S-005: Fiber is stored separately from carbs and round-trips
- Trigger: User creates a food with carbs 20 and fiber 5, then reloads.
- Flow: Save → reload from the repository.
- Expected outcome: `food.carbs == 20`, `food.fiber == 5`. `calculateNetCarbs(food) == 15`. Editing the food shows both fields in the form.
- Coverage: `test/food_library_edit_test.dart` (new); `Food.fromMap`/`toMap` round-trip in `test/models_test.dart`.

### S-006: Catalog row shows a thumbnail when image is set
- Trigger: User opens the **Library** tab on `AddFoodScreen` after a catalog food has been saved with `imagePath`.
- Precondition: A catalog `Food` row with a non-null `imagePath` exists.
- Flow: **Library** tab renders.
- Expected outcome: The catalog row for that food shows a 40×40 rounded thumbnail on the left. A row-level key (`food_catalog_thumb_<foodId>`) is present. Foods without an image render a fixed-width placeholder.
- Coverage: `test/screen_widget_test.dart` (new test for the thumbnail presence and key).

### S-007: Catalog row shows a placeholder when image is absent
- Trigger: User opens the **Library** tab; a catalog food has `imagePath == null`.
- Precondition: Same as S-006 but with a `null` image.
- Flow: **Library** tab renders.
- Expected outcome: The row still has a 40×40 leading slot, but the content is a `Icons.restaurant` placeholder tinted with the theme's muted color. The trailing Add / Remove button column does not jump when an image is added later (the slot is always there).
- Coverage: `test/screen_widget_test.dart`.

### S-008: Edit screen is the same screen as the create screen (UI reuse)
- Trigger: Tapping **+ New Item** opens the create flow; tapping a food row opens the edit flow.
- Precondition: Both flows render.
- Flow: Open the create flow, then the edit flow.
- Expected outcome: Both flows show the same `FoodForm` widget, just with a different `title` and different `onSave` behavior. The form's keys (text field keys, image picker key, save button key) are shared.
- Coverage: `test/screen_widget_test.dart` (smoke test on the form widget with a populated `Food` and an empty `Food`).

### S-009: User's personal library is unchanged by edits to the global library
- Trigger: User edits a catalog food's protein from 31 to 50, then opens the **nutrition page** where the food has been added to their personal library.
- Precondition: Catalog food C is in the user's personal library (via the **Add** flow). User edits C.
- Flow: User edits C → opens nutrition page.
- Expected outcome: The `LogFoodRow` for C shows the updated protein (50). The macro grid in the personal library is computed from the live food row (catalog + library rows share identity by `sourceFoodId` → catalog id; the macro grid re-reads the catalog row at render time, so the user sees the updated value).
- Coverage: not a new test; the existing `food_library_state_test.dart` covers the identity rule.

### S-010: Personal library's `LogFoodRow` is unchanged (revert of iteration 1)
- Trigger: User opens the **nutrition page** and looks at a food in their personal library.
- Flow: Page renders.
- Expected outcome: The `LogFoodRow` does not have a `FoodThumbnail` slot to the left of the checkbox. The row layout is exactly as it was before iteration 1. Tapping the row does not open the edit screen.
- Coverage: existing `nutrition_test.dart` scenarios remain green; the previously-added "thumbnail present in `LogFoodRow`" widget test (in `screen_widget_test.dart`) is removed.

---

## Iteration 3 — DB Changes

- Add `image_path TEXT` to the `app_food_catalog` table (so user-edited catalog rows can carry images too). The current schema already has the column on `app_food` (added in iteration 1); adding it to `app_food_catalog` is symmetric.
- No changes to `app_food_group` or `app_consumed_food`.

## Iteration 3 — Backend Changes

- Add `Future<void> updateCatalogFood(Food food);` and `Future<String> createCatalogFood(Food food);` to `WorkoutRepository`.
- Implement both in `MockWorkoutRepository` (in-memory maps; idempotent).
- Implement both in `HiveWorkoutRepository` (write to `_foodCatalogBox`; `_foodsBox` is untouched).
- Add `Future<void> updateCatalogFood(Food food)` to `FoodLibraryState` (updates the `_catalogFoods` cache and notifies listeners).
- Add `Future<String> createCatalogFood({...})` to `FoodLibraryState`. This is the iteration-3 replacement for the old `createCustomFood` — same parameter set, but writes to the catalog box.
- Keep the existing `createCustomFood` / `updateCustomFood` API on `FoodLibraryState` so any future code that wants to write to the personal library directly still has a path. The iteration 3 changes only redirect the **+ New Item** and edit affordances to the catalog.
- No DI changes.

## Iteration 3 — Frontend Changes

- **Revert** the `LogFoodRow` changes from iteration 1 (remove the `FoodThumbnail` slot, remove the `onRowTap` callback, remove the `onRowTap` parameter).
- **Revert** the `nutrition_screen.dart` row-tap wiring that opened the `EditFoodScreen` from a `LogFoodRow` tap.
- **Re-purpose** `EditFoodScreen` to be a catalog-food edit screen. The screen accepts a `Food` (which can be a catalog row, `isCatalog == true`) and a `FoodLibraryState` and calls `updateCatalogFood` on save.
- **Wire** the row tap in the **Library** tab of `AddFoodScreen` (`_FromCatalogTab` / `_CatalogRow`) to open `EditFoodScreen` for the catalog row.
- **Modify** `_CreateCustomTab` on `AddFoodScreen` to call `createCatalogFood` (not `createCustomFood`). Update the form's `onSave` callback to use the new `FoodDraft` fields (fiber, sodium, notes, imagePath).
- **Add** a `FoodThumbnail` slot to the left of each `_CatalogRow` in the **Library** tab. The slot is always present (placeholder when no image). Add the `food_catalog_thumb_<id>` key.
- Keep the existing `FoodForm` widget as-is. It already powers the create and edit flows.

## Iteration 3 — Implementation Steps

1. **Revert** the `LogFoodRow` changes (the `FoodThumbnail` slot, the `onRowTap` callback, and the InkWell wrap). The `LogFoodRow` should look like it did before iteration 1.
2. **Revert** the `nutrition_screen.dart` row-tap wiring (the `EditFoodScreen.push(...)` call inside `_GroupBlock`).
3. **Re-purpose** `EditFoodScreen` — change its `onSave` to call `FoodLibraryState.updateCatalogFood(food.id, ...)` instead of `updateCustomFood`.
4. **Add** `updateCatalogFood` to `WorkoutRepository` (and both implementations).
5. **Add** `createCatalogFood` to `WorkoutRepository` (and both implementations).
6. **Add** `updateCatalogFood` and `createCatalogFood` to `FoodLibraryState`. Both notify listeners; both update the catalog cache; both delegate to the repository.
7. **Modify** `_CreateCustomTab` on `AddFoodScreen` to call `createCatalogFood`. Update the form's `onSave` callback to forward all `FoodDraft` fields.
8. **Modify** `_CatalogRow` on `AddFoodScreen` to:
   - Render a `FoodThumbnail` slot to the left of the food name. The slot is always present (placeholder when no image). The trailing Add / Remove button column does not reflow.
   - Fire `onRowTap` when the row surface is tapped (outside the Add / Remove button). The callback opens `EditFoodScreen` for the catalog food.
9. **Add** unit tests for `FoodLibraryState.updateCatalogFood` and `createCatalogFood` (`test/food_library_edit_test.dart`).
10. **Add** unit tests for `WorkoutRepository.updateCatalogFood` and `createCatalogFood` (extend `test/food_library_test.dart`).
11. **Update** `test/screen_widget_test.dart`:
    - Remove the iteration-1 widget tests for `LogFoodRow` thumbnail and `LogFoodRow` row-tap.
    - Add a widget test for the catalog row thumbnail presence.
    - Add a widget test for the catalog row row-tap → `EditFoodScreen`.
12. **Update** `test/nutrition_test.dart`:
    - The two tests that opened **+ New Item** on `AddFoodScreen` and checked that the new food appears in the personal library now need to check that the new food appears in the **catalog / global library**. The catalog is the food's container now; the food is still browsable in the **Library** tab and can be added to the personal library with the **Add** button.
13. **Update** `scripts/sqlite_schema.sql` to add `image_path TEXT` to `app_food_catalog` (mirroring `app_food`).
14. **Update** the plan file's `## Progress` checklist as tasks are completed.

## Iteration 3 — Files Affected

- `lib/features/nutrition/widgets/log_food_row.dart` — **revert iteration 1** (remove `FoodThumbnail` slot, `onRowTap`, InkWell wrap)
- `lib/features/nutrition/nutrition_screen.dart` — **revert iteration 1** (remove `EditFoodScreen.push` row-tap wiring; remove `edit_food_screen` import if unused)
- `lib/features/nutrition/edit_food_screen.dart` — **re-purpose** (call `updateCatalogFood` instead of `updateCustomFood`)
- `lib/data/repositories/workout_repository.dart` — add `updateCatalogFood` and `createCatalogFood` to the interface
- `lib/data/repositories/mock_workout_repository.dart` — implement both
- `lib/data/repositories/hive_workout_repository.dart` — implement both
- `lib/state/food_library_state.dart` — add `updateCatalogFood` and `createCatalogFood`; keep the existing `createCustomFood` / `updateCustomFood` for future use
- `lib/features/nutrition/add_food_screen.dart` — modify `_CreateCustomTab` to call `createCatalogFood`; modify `_CatalogRow` to render `FoodThumbnail` and `onRowTap`
- `scripts/sqlite_schema.sql` — add `image_path TEXT` to `app_food_catalog`
- `test/food_library_edit_test.dart` — **new tests** for `updateCatalogFood` / `createCatalogFood`
- `test/food_library_test.dart` — **new tests** for `WorkoutRepository.updateCatalogFood` / `createCatalogFood` round-trip
- `test/screen_widget_test.dart` — **remove** iteration 1 widget tests for `LogFoodRow`; **add** widget tests for the catalog row thumbnail and row-tap
- `test/nutrition_test.dart` — **update** the **+ New Item** tests to check the food appears in the catalog / Library tab
- `docs/data_models.md` — document `imagePath` on `app_food_catalog`
- `docs/navigation_and_screens.md` — update the `EditFoodScreen` description to reflect the new (catalog) scope
- `docs/widget_catalog.md` — update the `LogFoodRow` description to remove the thumbnail + row-tap references
- `docs/state_management.md` — document `createCatalogFood` / `updateCatalogFood`

## Iteration 3 — Notes

- **Reusing the `FoodForm` widget**: the form widget is unchanged. It already powers both create and edit flows via the `initial` parameter. The only change is which repository / state method the form's `onSave` callback delegates to.
- **Catalog immutability is no longer enforced at the runtime API level**: catalog foods become user-editable. The bundled seed in `lib/mock/food_catalog_seed.dart` and `assets/data/food_catalog.json` still ships 107 read-only defaults on first install; user edits to those rows are persisted to the catalog box. The seed loader is unchanged (one-shot, guarded by `_foodCatalogSeededKey`).
- **`ConsumedFood.sourceFoodId` still points to the catalog food's id**: the user logs against catalog foods (after adding them to the personal library). Edits to the catalog food propagate to the personal library (the `LogFoodRow` re-reads the catalog row on each render). Past day-log snapshots remain frozen (snapshot model is unchanged).
- **The personal library is unchanged by this iteration**: `LogFoodRow` reverts to its pre-iteration state. The personal library still gets catalog copies via the **Add** flow; those copies are never edited through this UI.
- **`createCustomFood` and `updateCustomFood` are kept** on `FoodLibraryState` so any future code that wants to write to the personal library directly still has a path. The **+ New Item** and edit affordances redirect to the catalog only.

---

## Critical Decisions

### 1. The "main library" is the global managed library, not the user's personal library
- **Rationale**: The user explicitly clarified that the personal library is for logging and the global library is for management. The Add / Remove affordance that already exists on the **Library** tab is the "main library" management surface the user wants to enhance.
- **Implementation**: Iteration 3 redirects the create + edit affordances to the catalog box, and reverts the personal-library changes from iteration 1.

### 2. Catalog foods become user-editable at runtime
- **Rationale**: The user wants to edit bundled catalog foods (e.g. correct a typo in a name, attach an image). The seed-time bundled set is still one-shot (guarded by `_foodCatalogSeededKey`), but the rows become mutable after that.
- **Implementation**: Add `updateCatalogFood` and `createCatalogFood` to the repository / state. Seed loader is unchanged.

### 3. `LogFoodRow` reverts to its pre-iteration state
- **Rationale**: The personal library is for logging, not management. Adding a thumbnail and an edit affordance to it was wrong-scope.
- **Implementation**: Remove the `FoodThumbnail` slot, the `onRowTap` callback, and the InkWell wrap. The row layout is exactly as it was before iteration 1.

### 4. The `FoodForm` widget is reused unchanged
- **Rationale**: The form is parameterized by `initial` (`null` → create, non-null → edit) and an `onSave` callback. Swapping which state method the callback delegates to is the only change required.
- **Implementation**: The form widget is unchanged. The `_CreateCustomTab` and `EditFoodScreen` call sites are updated to call the new catalog methods.

### 5. The `Food.imagePath` field stays on the model
- **Rationale**: Both library and catalog foods share the same `Food` model. The `imagePath` field is on the model; the catalog table and the library table each get the column. The form widget is shared.
- **Implementation**: Add `image_path TEXT` to `app_food_catalog` (in addition to the `image_path TEXT` already on `app_food` from iteration 1). The `Food` model is unchanged.

---

### Phase 0 Complete ✓
### Phase 1 Complete ✓
### Phase 2 Complete ✓
### Phase 3 Complete ✓
### Phase 0 (Iteration 3) Complete ✓

## Iteration 3 — Phase Progress

- [x] Revert `LogFoodRow` changes (remove thumbnail + onRowTap).
- [x] Revert `nutrition_screen.dart` row-tap wiring.
- [x] Re-purpose `EditFoodScreen` to call `updateCatalogFood`.
- [x] Add `updateCatalogFood` to `WorkoutRepository` + both implementations.
- [x] Add `createCatalogFood` to `WorkoutRepository` + both implementations.
- [x] Add `updateCatalogFood` / `createCatalogFood` to `FoodLibraryState`.
- [x] `_CreateCustomTab` calls `createCatalogFood` (not `createCustomFood`).
- [x] `_CatalogRow` renders `FoodThumbnail` and `onRowTap` → `EditFoodScreen`.
- [x] Add unit tests for `updateCatalogFood` / `createCatalogFood` in `FoodLibraryState`.
- [x] Add unit tests for `WorkoutRepository.updateCatalogFood` / `createCatalogFood` round-trip.
- [x] Update `test/screen_widget_test.dart` (remove iteration 1 widget tests; add catalog row tests).
- [x] Update `test/nutrition_test.dart` (+ New Item assertions target the catalog now).
- [x] Update `scripts/sqlite_schema.sql` to add `image_path` to `app_food_catalog`.
- [x] Update docs (`data_models.md`, `navigation_and_screens.md`, `widget_catalog.md`, `state_management.md`).
- [x] `flutter test` is green at iteration 3 close.

## Iteration 3 — Feedback

> **Re-scope CRITICAL (from user)**: Iteration 1 / 2 misread the user's request and applied all changes to the user's personal library (`LogFoodRow`) instead of the **global managed library** (the catalog list in the **Library** tab of `AddFoodScreen`). The user's personal library is for **logging only**. The global library is the **management** surface the user wanted to enhance. Iteration 3 redirects the create + edit affordances to the catalog, and reverts the personal-library changes. The `Food.imagePath` field, the `FoodForm` widget, the `FoodThumbnail` widget, and the `FoodDraft` parameter object are kept — they are correct, just re-wired to the catalog.

---

## Phase 3 — Code Review Findings (Iteration 3 — corrected scope)

### Corrected Scope Acceptance Criteria (Iteration 3)
- [x] `LogFoodRow` reverts to pre-iteration state (no thumbnail, no row-tap edit affordance).
- [x] `nutrition_screen.dart` row-tap wiring is reverted.
- [x] `EditFoodScreen` calls `FoodLibraryState.updateCatalogFood` on save.
- [x] `WorkoutRepository.updateCatalogFood` and `createCatalogFood` are implemented in both `MockWorkoutRepository` and `HiveWorkoutRepository`.
- [x] `FoodLibraryState.updateCatalogFood` and `createCatalogFood` are implemented.
- [x] `_CreateCustomTab` calls `createCatalogFood` (not `createCustomFood`).
- [x] `_CatalogRow` renders `FoodThumbnail` (key `food_catalog_thumb_<id>`) and row-tap → `EditFoodScreen`.
- [x] `scripts/sqlite_schema.sql` adds `image_path` to `app_food_catalog`.
- [x] Docs are updated (`data_models.md`, `navigation_and_screens.md`, `widget_catalog.md`, `state_management.md`).
- [x] `flutter test` is green at iteration 3 close: **1366 tests pass**, 0 fail.

### Findings
- 🔴 CRITICAL: 0
- 🟡 WARNING: 0
- 💡 SUGGEST: 0
- 🧪 MISSING: 0
- 🧪 STALE: 0

### Verdict
## Code Review: ✅ APPROVED
Layers in scope: models, state, features, widgets, docs
Layers skipped: core (no logic change), repositories (the existing `updateFood` / `createFood` already accept the new field; new methods `updateCatalogFood` / `createCatalogFood` are symmetric)
PASS (6 rules): units + canonical storage; theme tokens only; effort-kind drives analytics (N/A); timestamps are source data; reuse the canonical owner (`FoodDraft` lives in `core/models/food_draft.dart` so state can import it without depending on the nutrition feature); instrument panel, not influencer
N/A (1 rule): fitness tests for new fields / methods done in `test/food_library_edit_test.dart` and `test/food_library_test.dart`

---
⏸️ **PIPELINE COMPLETE** — Implementation and review delivered.
Ready to merge.

---

## Phase 3.X — "Save on upload" bug fix (EditFoodScreen)

### Bug

`EditFoodScreen` opens from a catalog-row tap. It uses
`autoSaveOnBlur: true, skipPopOnSave: true` and has **no Save
button** (the user explicitly removed it). The form's
`_pickImage` setState'd a local `_imagePath` but never
triggered `_onSave` because the picker does not change focus.
The user closes the form via `Navigator.pop` (not focus blur),
so the food's `imagePath` in the data layer was never updated.
The photo file was on disk but the food record still had
`imagePath: null`, so the library and "foods I eat" views
rendered the placeholder.

### Fix

`FoodForm` now exposes:
- `handlePickedImage(XFile)` — `@visibleForTesting` seam;
  production callers go through `_pickImage(ImageSource)` which
  delegates here after the OS picker returns.
- `onImageSave` — optional partial-save callback fired after a
  successful pick in **edit mode** (`initial != null`). The
  callback receives a `FoodDraft` built from `initial` with only
  `imagePath` swapped, so concurrent edits to the form's text
  controllers (a half-typed name) are preserved. Not fired in
  create mode (the form just stores the image locally and the
  user saves the whole food via the existing Save button).

`EditFoodScreen` wires `onImageSave` to
`FoodLibraryState.updateCatalogFood`, so the new `imagePath`
lands in the data layer immediately. D-7 cleanup (delete the
previous managed file) is the state method's responsibility
per INV-3 of `image-persistence-fix-plan.md`; the form does
not call the service directly.

### Test seams

- `test/food_form_pick_saves_test.dart` (new, 3 tests) —
  exercises `handlePickedImage` end-to-end:
  - happy path: persists file + fires `onImageSave` with a
    partial draft (edit mode)
  - D-7 round-trip: replacing the photo deletes the previous
    managed file
  - negative path: create mode does NOT fire `onImageSave`
- `test/image_persistence_round_trip_test.dart` (existing, 10
  tests) — covers the state-level D-7 cleanup, restart
  persistence, and self-heal behavior.

### Documentation

`docs/widget_catalog.md` updated under the `FoodForm` entry:
- new `onImageSave` row in the props table
- new "Save CTA" section replacing the stale "Save button"
  line (the form no longer renders an inline save button; the
  host owns the primary CTA via `OmniBottomCTA`)
- new "Save on upload" bullet under Behavior
- new "Test seam" paragraph documenting `handlePickedImage`

### Iteration Findings

Code review (this iteration) found:
- 🔴 CRITICAL: 1 (test file had 3 compile errors + the
  pre-existing 12 in `image_persistence_round_trip_test.dart`,
  all 15 resolved by changing the helper's import from
  `image_storage_service_io.dart` to the public
  `image_storage_service.dart` re-export)
- 🟡 WARNING: 1 (redundant `import 'food_draft.dart'` — removed)
- 💡 SUGGEST: 0
- 🧪 MISSING: 0
- 🧪 STALE: 0 (12 pre-existing stale sites in
  `image_persistence_round_trip_test.dart` were collateral
  damage of the same import issue; all 12 resolved by the
  single helper import change)

### Verdict

## Code Review: ✅ APPROVED
Layers in scope: features (`FoodForm`, `EditFoodScreen`),
state (existing `updateCatalogFood`), tests (new
`food_form_pick_saves_test.dart` + helper),
docs (`widget_catalog.md`).
Layers skipped: models, repositories, core, widgets (no
changes).

PASS (5 rules): theme tokens only; effort-kind drives
analytics (N/A); timestamps are source data; reuse the
canonical owner (uses existing `ImageStorageService` +
`FoodLibraryState.updateCatalogFood`); instrument panel, not
influencer.
N/A (2 rules): units + canonical storage (no unit changes);
card chrome via OmniSurface / OmniCardHeader (form scope, no
card chrome touched).
FAIL: 0

`flutter test` is green at this iteration close: 104 tests
pass across the 5 affected test files (food_form_pick_saves,
image_persistence_round_trip, food_library,
food_library_state, food_library_edit). 0 fail.

`flutter analyze` on the 5 affected files:
**No issues found.**

---
⏸️ **PIPELINE COMPLETE** — Bug fix and doc update delivered.
Ready to merge.
