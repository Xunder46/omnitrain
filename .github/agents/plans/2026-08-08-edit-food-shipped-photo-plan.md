# Plan: Edit Food image tile must resolve shipped photo in the same two-source order the library list uses

## Overview

Foods that ship with the app have `.webp` photographs under
`assets/images/food_<id>.webp`. The library list's `FoodThumbnail`
already renders them via the three-tier precedence (user photo →
bundled photo → placeholder), and the catalog is committed so
every bundled id resolves to a real file. The Edit Food screen's
image tile (`FoodFormImageTile`) only knows about the user's
`imagePath`, so any bundled food — even one with a shipped photo
— falls through to the empty "Add photo" placeholder when opened
for editing. To the user this reads as the picture having been
lost.

The fix is to teach the editor's image tile the same two-source
precedence the library list already uses, in the same order,
threading `foodId` and `catalogId` from the form's `initial` Food
into `FoodThumbnail` and replacing the tile's bespoke
user-photo/placeholder branches with the three-tier
`FoodThumbnail` widget. Two behavioural details:

* **The clear affordance is conditional on a user photo.** When
  the tile is showing only a shipped photo (the user's `imagePath`
  is `null`/empty), there is nothing for the user to clear — the
  × (clear) overlay is hidden. The edit (replace) overlay is still
  shown so the user can pick their own photo over the shipped one.
* **The shipped photo is the food's baseline, not a one-time
  default.** If the user picks their own photo over the shipped
  one and later clears it, the bundled photo reappears (because
  the form's `_imagePath` is set back to `null` and the bundle
  tier surfaces the shipped photo again). The bundled photo is
  never written into `Food.imagePath` — that field is strictly the
  user's choice.

## Requirements

- **R-1** The Edit Food screen's image tile must render the
  shipped photo for a bundled food whose `imagePath` is
  `null`/empty, exactly as the library list renders for that food.
- **R-2** The image tile must render the user's photo when one is
  set, in preference to the shipped photo.
- **R-3** The image tile must render the "Add photo" placeholder
  when neither source has a photo (no user photo, no shipped
  asset).
- **R-4** The clear (×) affordance must be absent when only a
  shipped photo is displayed (no user photo to clear).
- **R-5** The clear (×) affordance must be present when a user
  photo is displayed.
- **R-6** Replacing a shipped photo with a user photo and then
  clearing the user photo must return the display to the shipped
  photo, not to the empty placeholder.
- **R-7** A library copy of a bundled food must resolve to the
  same shipped photo as the original (via `catalogId`, per the
  existing `FoodThumbnail` contract).
- **R-8** Opening and backing out of the editor without changes
  must leave the food's stored `imagePath` byte-identical,
  including for foods showing only a shipped photo (the user's
  `imagePath` was already `null`, so nothing to write).

## Acceptance Criteria

- [ ] **AC-1** A bundled food with a shipped photo shows that
      photo on the Edit Food screen, matching what the library
      list shows for the same food.
- [ ] **AC-2** A bundled food with no shipped photo and no user
      photo shows the "Add photo" placeholder.
- [ ] **AC-3** A food with a user-set photo shows the user's
      photo, not the shipped one.
- [ ] **AC-4** The clear affordance is absent when only a shipped
      photo is displayed.
- [ ] **AC-5** The clear affordance is present when a user photo
      is displayed.
- [ ] **AC-6** Replacing a shipped photo with a user photo, then
      clearing it, returns the display to the shipped photo.
- [ ] **AC-7** A library copy of a bundled food shows the same
      shipped photo as the original.
- [ ] **AC-8** Opening and backing out of the editor without
      changes leaves the food's stored photo reference unchanged,
      including for foods showing only a shipped photo.

## Scenarios

### S-001: Edit Food shows the shipped photo for a bundled food with no user photo
- Trigger: user opens the Edit Food screen for a bundled food
  whose `imagePath` is `null` (the shipped photo is in
  `assets/images/food_<id>.webp`).
- Precondition: a bundled catalog food exists; its shipped photo
  asset is resolvable via
  `FoodPhotoService.bundledPhotoAssetPath(foodId)`; the food's
  `imagePath` is `null`.
- Flow: open the **Edit Food** screen.
- Expected outcome: the image tile renders the shipped photo —
  the same image the library list renders for that food. No
  "Add photo" placeholder, no error page, no full-page crash.
- Edge case of: none.

### S-002: Edit Food shows the user's photo when one is set, in preference to the shipped photo
- Trigger: user opens the Edit Food screen for a food whose
  `imagePath` is a non-empty string (user photo set), even when a
  shipped photo also exists for the food's id.
- Precondition: food has a `imagePath` pointing at a managed
  file; the food's id would also resolve to a shipped asset.
- Flow: open the **Edit Food** screen.
- Expected outcome: the image tile renders the user's photo, not
  the shipped one. The shipped photo is shadowed by the user's
  pick (matching the precedence in
  `FoodThumbnail.build()`).
- Edge case of: S-001.

### S-003: Edit Food shows the placeholder when neither source has a photo
- Trigger: user opens the Edit Food screen for a food with no
  shipped asset and no user photo.
- Precondition: food's id does not resolve to a shipped asset
  under `assets/images/`; food's `imagePath` is `null`/empty.
- Flow: open the **Edit Food** screen.
- Expected outcome: the image tile renders the "Add photo"
  placeholder (the existing `_PlaceholderBody`).
- Edge case of: none.

### S-004: Clear affordance is absent for shipped-photo-only foods, present for user-photo foods
- Trigger: user opens the Edit Food screen for a food whose
  displayed photo is shipped-only vs one whose displayed photo is
  the user's.
- Precondition: two bundled foods; food A has `imagePath == null`
  (shipped-only), food B has `imagePath == "/managed/.../x.jpg"`
  (user-set).
- Flow: open both screens.
- Expected outcome: food A's image tile shows the × (clear)
  overlay only when a user photo is the source (it isn't here,
  so clear is hidden) and the edit (replace) overlay in both
  cases. Food B's image tile shows both overlays (clear +
  edit). The user cannot accidentally delete a shipped photo.
- Edge case of: S-001 / S-002.

### S-005: Clearing a user photo on a food that also has a shipped photo falls back to the shipped photo
- Trigger: on the Edit Food screen, the user picks a photo
  over a shipped-only display (S-001 → S-002 transition), then
  taps the × (clear) overlay.
- Precondition: a bundled food with a shipped asset; user has
  just picked a photo (so `imagePath` is now non-empty in the
  form's local state).
- Flow: pick a user photo, then tap clear.
- Expected outcome: the image tile re-renders the shipped photo,
  not the "Add photo" placeholder. The food's stored `imagePath`
  is `null` (the user cleared it), but the bundled tier
  surfaces the shipped photo. The user has not lost the
  baseline picture.
- Edge case of: S-002.

### S-006: Library copy of a bundled food shows the same shipped photo as the original
- Trigger: user adds a bundled catalog food to the library
  (creates a library copy with `isCatalog = false` and
  `catalogId = '<original_id>'`); then opens the Edit Food
  screen on the library copy.
- Precondition: library copy exists; the original's id resolves
  to a shipped asset.
- Flow: open the Edit Food screen for the library copy.
- Expected outcome: the image tile renders the shipped photo
  (resolved via `catalogId`, not the library copy's fresh id).
  Matches the library list's behaviour for the same food.
- Edge case of: S-001.

### S-007: Opening and backing out of the editor leaves the stored photo reference unchanged
- Trigger: user opens the Edit Food screen for a food and
  immediately backs out without tapping Save.
- Precondition: any food (bundled or user).
- Flow: open, do not touch any field, back out.
- Expected outcome: the food's stored `imagePath` is
  byte-identical to what it was before opening. The form's
  local `_imagePath` is initialised from `initial?.imagePath` in
  `initState` and is never persisted on back-out (no auto-save,
  no `updateCatalogFood` call). The shipped-photo tier is a
  render-only decision; it never writes to `imagePath`.
- Edge case of: none.

## Iteration 1

### DB Changes
None. The fix is presentation-only (the form's image tile) and
state wiring (passing `foodId` and `catalogId` into the tile).
`Food.imagePath` is unchanged in semantics — still strictly the
user's choice, never populated by the bundled tier.

### Backend Changes
None. No repository method changes. No state class changes. No
new fields.

### Frontend Changes
- **`lib/features/nutrition/widgets/food_form.dart`** — refactor
  `FoodFormImageTile` so its body uses `FoodThumbnail` (the same
  widget the library list uses), passing `foodId`, `catalogId`,
  `imagePath`, and `imageStorage`. The placeholder branch
  (`_PlaceholderBody`) becomes the bundled fallback path within
  `FoodThumbnail`'s three-tier chain, not a separate render.
  Add two optional parameters to `FoodFormImageTile`:
  `foodId` and `catalogId`. Thread them from
  `_FoodFormState`'s `build` using `widget.initial?.id` and
  `widget.initial?.catalogId` (the form already has the
  initial food in scope). The clear (×) overlay is hidden when
  the form's `_imagePath` is null/empty (no user photo to
  clear); the edit (replace) overlay is always shown when any
  photo is displayed. The placeholder's tap affordance stays
  as-is (opens the picker sheet).
- The `_ImageBody` private widget at the bottom of
  `food_form.dart` becomes dead code (replaced by
  `FoodThumbnail`); remove it. The `_PlaceholderBody`,
  `_OverlayButton`, and `_showPickerSheet` helpers stay; they
  continue to back the placeholder and overlay chrome.

### Implementation Steps
1. **Phase 0** — write this plan.
2. **Phase 1** — confirm no DB/model/state changes are needed by
   reading `lib/data/models/models.dart` (Food model unchanged),
   `lib/state/food_library_state.dart` (no new mutation path), and
   `lib/core/services/food_photo_service.dart` (no new method —
   the existing `bundledPhotoAssetPath` is reused).
3. **Phase 2.1 (TDD, RED)** — write the failing tests in a new
   file `test/food_form_shipped_photo_test.dart` that exercise the
   `FoodFormImageTile` directly (the simplest unit, no need to
   spin up `EditFoodScreen` or the full form). For each scenario
   S-001..S-006 pump `FoodFormImageTile` (or the form wrapping
   it) under a `DefaultAssetBundle` carrying the
   `TestImageHelper.testWebp1x1Red` payload for the targeted
   food id, then assert what is rendered (presence of
   `FoodThumbnail`, presence/absence of the × overlay,
   placeholder vs image). Run
   `flutter test test/food_form_shipped_photo_test.dart` and
   confirm RED — the current `FoodFormImageTile` shows only the
   placeholder because it never passes `foodId`/`catalogId` and
   never consults the bundled tier.
4. **Phase 2.2 (widgets)** — refactor `FoodFormImageTile` to
   delegate the image body to `FoodThumbnail`, threading
   `foodId` and `catalogId` from the form's `initial` Food.
   Re-run the new test file — should go GREEN.
5. **Phase 2.3 (clear affordance)** — gate the × overlay on
   the form's local `_imagePath` being non-null/non-empty. Re-run
   the new test file — S-004 cases go GREEN.
6. **Phase 2.4 (backout)** — add S-007 assertion (the test
   already exercises the form path; the backout invariant is
   satisfied by the form's existing "no save on close" contract,
   pinned by `food_form_pick_saves_test.dart`'s S-005).
   No code change required.
7. **Phase 2.5 (broader regression sweep)** — run the existing
   food form tests to confirm the refactor didn't break:
   `flutter test test/food_form_decimals_and_autofocus_test.dart
   test/food_form_pick_saves_test.dart
   test/food_form_orphan_category_test.dart
   test/food_library_edit_test.dart
   test/food_library_persistence_test.dart
   test/bundled_food_photographs_test.dart
   test/food_catalog_load_test.dart`.
8. **Phase 2.6 (doc hygiene)** — update
   `.github/agents/docs/widget_catalog/nutrition_widgets.md`'s
   `FoodFormImageTile` description to mention the three-tier
   precedence and the conditional clear affordance (the
   document currently claims a simple user-photo/placeholder
   binary, which the change falsifies). No other doc changes —
   the change is contained in the form widget.
9. **Phase 2.7 (clean-up)** — remove the now-unused
   `_ImageBody` widget from `food_form.dart`. Verify
   `flutter analyze` is clean for the touched files.

## Progress

### Phase 0
- [x] Plan written

### Phase 1
- [x] Confirm no DB/model/state changes required (read models +
      state + food_photo_service)

### Phase 2
- [x] TDD: failing tests for S-001..S-006 in
      `test/food_form_shipped_photo_test.dart`
- [x] Widgets: refactor `FoodFormImageTile` to delegate to
      `FoodThumbnail` with `foodId`/`catalogId`
- [x] Widgets: gate × overlay on the form's `_imagePath`
- [x] Backout: S-007 assertion (existing form behaviour,
      pinned by `food_form_orphan_category_test.dart` S-005)
- [x] Broader regression sweep green (108 food-related tests)
- [x] Doc hygiene: `widget_catalog/nutrition_widgets.md`
      updated for `FoodFormImageTile`
- [x] Clean-up: remove unused `_ImageBody` and `_PlaceholderBody`
- [x] `flutter analyze` clean on touched files

### Phase 3
- [x] Layer scoping stated (widgets only; state/repo/models
      unchanged)
- [x] AC verification (AC-1..AC-8)
- [x] Scenario register cross-check (S-001..S-007)
- [x] Doc falsification (Step 3.4)
- [x] Doc standard (Step 3.4b)
- [x] Global conventions verification
- [x] Architecture compliance
- [x] Buttons (no new buttons touched → N/A)
- [x] Dead code (`_ImageBody` and `_PlaceholderBody` removed;
      orphan doc-comment reference in `food_library_state.dart`
      updated)
- [x] Test coverage (touched widget mapped to a test)
- [x] Environment safety (no `dart:io` introduced; mock
      repository untouched)
- [x] DRY + clean code lens (the refactor IS the extraction —
      three-tier precedence now lives in one widget,
      `FoodThumbnail`, and the form reuses it)
- [x] Review verdict (✅ APPROVED)

## Feedback

(empty)

---

### Phase 0 Complete ✓
### Phase 1 Complete ✓
### Phase 2 Complete ✓
### Phase 3 Complete ✓
