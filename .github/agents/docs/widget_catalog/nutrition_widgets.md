# Nutrition Widgets

> Part of the [Widget Catalog](../widget_catalog.md). Return to the index for the complete widget list and the widget → page lookup table.

---

## Nutrition Primitives

### `NutritionPrimerSheet`

**File**: `lib/features/nutrition/widgets/nutrition_primer_sheet.dart`

One-shot orientation sheet for the Daily Nutrition page. The page inverts the usual food-logging model and packs several unfamiliar ideas onto one screen (curate a "Foods I Eat" list once from the global library, check foods off daily with adjustable per-food portions, watch the day roll up into a calories/macros ring + water + sodium), so a brief primer helps a first-time user understand the model. The sheet is single-pane (no carousel, no `PageView`, no Next/Back navigation, no pointers anchored to on-screen widgets) and presents exactly three labeled blocks:

1. **YOUR LIST, BUILT ONCE** — describes the curated "Foods I Eat" list and the pencil edit control on the page.
2. **CHECK TO LOG, SET THE AMOUNT** — describes daily check-off logging and the per-food portion amount.
3. **TODAY AND OVER TIME** — describes the rollup: calories vs target, protein/carb/fat split, water, sodium.

The sheet does NOT cover target editing, group management, or water-stepper instructions — those are discoverable and out of scope.

| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `onDismiss` | `VoidCallback?` | `null` | Optional callback fired on dismiss (e.g. for the host to mark the seen state or push the next screen). If `null`, dismissal just closes the sheet. |

**Behavior**:
- Rendered inside `showModalBottomSheet(isScrollControlled: true, ...)` — the host screen owns the show/dismiss lifecycle.
- Single `FilledButton` "Got it" CTA, full width, height `OmniTheme.buttonPrimaryHeight`, `shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(OmniTheme.buttonBorderRadius))` — no Material 3 `StadiumBorder`. Color from `theme.colorScheme.primary`.
- The three blocks use a section header `OmniCardHeader` (or the canonical D-1 typography) per the global section-header contract.
- The "Got it" CTA fires `Navigator.of(context).pop()` and then `onDismiss?.call()`. The seen-state mutation lives in the host screen (`HomeScreen._openNutritionScreen` calls `nutritionPrimerState.markSeen()` AFTER the sheet pops), NOT inside the sheet — the sheet is presentation-only.
- The header "?" control on `NutritionScreen` uses the same widget but passes an `onDismiss` that does NOT call `markSeen()` — the seen state is preserved across reopens.

**Auto-show contract**:
- The home strip's first-ever tap opens this sheet over the home screen via `showModalBottomSheet`. On dismiss, the host calls `NutritionPrimerState.markSeen()` and then pushes `NutritionScreen`.
- The header "?" on `NutritionScreen` opens the same sheet at any time. The seen state is NOT mutated.

**Test keys** (used by `test/nutrition_primer_test.dart`):
- `nutrition_primer_block_curate`, `nutrition_primer_block_check`, `nutrition_primer_block_rollup` — the three labeled blocks.
- `nutrition_primer_dismiss` — the "Got it" CTA.
- `nutrition_primer_help` — the "?" icon button in the nutrition page header.

---

---

## Nutrition Widgets

Nutrition-feature widgets live under `lib/features/nutrition/widgets/`. They are
feature-scoped (only `NutritionScreen` uses them) but follow the catalog
conventions: pure presentation, theme-reactive, no repository access, state
injected via constructor.

### `LogFoodRow`

**File**: `lib/features/nutrition/widgets/log_food_row.dart`

One row per food in the "Foods I Eat" list, and the actual logging affordance: the thumbnail is
the toggle that logs or unlogs the food for today, alongside an amount input and a single-line
macro summary.

**An unsaved amount edit is not a log.** Typing in the amount field updates the in-memory
controller only; the food row is written when the user explicitly commits. This keeps a
half-typed number from being persisted as a real entry.

The row's selected and unselected states are visually distinct without relying on colour alone.

### `FoodThumbnail`

**File**: `lib/features/nutrition/widgets/food_thumbnail.dart`

Square food image with a placeholder fallback. Platform-conditional: the native implementation
reads from the managed image directory, the web stub renders the placeholder.

### `FoodForm`

**File**: `lib/features/nutrition/widgets/food_form.dart`

Shared form widget used by both the **+ New Item** flow on
`AddFoodScreen` and the **Edit Food** screen
(`EditFoodScreen`). Parameterized by an optional `Food?` initial
value: `null` → create mode, non-null → edit mode.

| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `initial` | `Food?` | required | Pre-fill the form with this food's values when non-null. |
| `foodLibraryState` | `FoodLibraryState` | required | Source for the categories dropdown (re-reads `activeFoodGroups` on every notification). |
| `onSave` | `Future<bool> Function(FoodDraft draft)` | required | Save callback. Returns `true` to pop, `false` to surface a snackbar. |
| `saveLabel` | `String` | `'Save'` | Primary CTA label. |
| `showNotesField` | `bool` | `false` | When true, renders a "Notes (optional)" multi-line field. Edit mode only. |
| `onImageSave` | `Future<bool> Function(FoodDraft draft)?` | `null` | Optional partial-save callback fired after a successful photo pick **or** after the × (clear) overlay clears the photo in **edit mode** (`initial != null`). Wired by `EditFoodScreen` to `FoodLibraryState.updateCatalogFood` so the new or cleared `imagePath` lands in the data layer immediately, even on screens that have no Save button. The draft is built from `initial` with only `imagePath` swapped, so concurrent edits to the form's text controllers (a half-typed name, for example) are preserved. **Not fired in create mode** — the image is just stored locally until the user saves the whole food. |

**Form fields (top to bottom)**:
1. Image picker tile (`FoodFormImageTile`, key `food_form_image_tile`) — square 96×96 tile. The displayed photo follows the same three-tier precedence as the library list's `FoodThumbnail`: user-picked `imagePath`, then `FoodPhotoService.bundledPhotoAssetPath` resolved via `foodId`/`catalogId`, then placeholder. The × (clear) overlay is gated on a user-set photo (the shipped photo is the food's baseline, not the user's), and the edit overlay is shown whenever any photo is rendered. Overlay gating and picker behaviour are verified by `test/food_form_shipped_photo_test.dart` (S-001..S-006).
2. Name (`food_form_name`) — `TextFormField` with `TextCapitalization.words`.
3. Group (`food_form_group`) — `DropdownButtonFormField<String?>` of the active groups + an "Ungrouped" `null` entry. When the food's stored `groupId` points at a category that is not in the active list (deleted, or a default category that was never created because of a name collision at first launch), the form synthesises an extra item carrying the stored `groupId` and the group's resolved name from the full group cache (suffixed " (archived)") or the raw id (suffixed " (no longer available)") rendered with `OmniTheme.colors.textMuted`. See `test/food_form_orphan_category_test.dart` (S-001 / S-002).
4. Unit type (`food_form_unit_type`) — `DropdownButtonFormField<FoodUnitType>` of `count` / `grams`. Swapping units pre-fills sensible defaults for the reference amount + label.
5. Reference amount (`food_form_reference_amount`) + Reference label (`food_form_reference_label`).
6. Macros (per the reference above) — `Protein (g)` (required), `Carbs (g)` (required), `Fiber (g)` (optional, blank = unset), `Fat (g)` (required), `Sodium (mg)` (optional, blank = unset). All accept **decimal** input (e.g. `0.5`, `1.25`) via the `^\d*\.?\d*$` regex filter, mirroring the reference-amount field. Macros are stored as `double` on `Food` / `FoodDraft` so fractional grams persist (S-001).
7. Notes (`food_form_notes`) — when `showNotesField: true`.

**Save CTA**: the form does **not** render an inline save button. The host screen owns the primary bottom CTA via the shared `OmniBottomCTA` (see `.github/agents/plans/primary-bottom-cta-anchor-width-plan.md`). The host wires the CTA's `onPressed` to `FoodFormController.submit`, which routes through the form's validation + save pipeline — the same pipeline the inline button used to trigger.

**Behavior**:
- The form owns validation, the image picker, and the
  translation from controllers to a typed `FoodDraft`. The caller
  hands the draft to `FoodLibraryState.createCustomFood` (create)
  or `FoodLibraryState.updateCustomFood` / `updateCatalogFood`
  (edit) — never to the repository directly.
- "Save on upload" (edit mode): when `onImageSave` is provided
  and `initial != null`, the photo pick handler persists the new
  `imagePath` to the data layer immediately (D-7 cleanup of the
  previous managed file is the state method's responsibility —
  the form does not call the service directly). On hosts that
  have no Save button (`EditFoodScreen` with
  `autoSaveOnBlur: true`), this is the **only** path that writes
  the picked photo to the data layer before the user navigates
  away, so without it the photo would not persist.
- "Save on clear" (edit mode): symmetric to "Save on upload".
  Tapping the × (clear) overlay invokes `clearImage()` which
  sets `_imagePath = null` locally and fires `onImageSave` with
  a partial draft (`imagePath: null`). The state method's
  `previousPath != draft.imagePath` branch handles D-7 cleanup
  of the previous managed file. **Not fired in create mode**
  (no source food to partial-save against).
- Fiber is exposed alongside carbs in the macro list, matching
  the `Food.fiber` field on the model. The existing
  `calculateNetCarbs(food)` helper handles the net-carb math.
- **Auto-select on focus** (S-004..S-006): every `TextFormField`
  on the form (name, reference amount, reference label, all five
  macros, notes) has a per-field `FocusNode` wired to a
  `_selectAllOnFocus` handler. Tapping a pre-filled field
  highlights the entire value via
  `controller.selection = TextSelection(baseOffset: 0,
  extentOffset: controller.text.length)`, so the user can
  retype a value without first clearing it. Empty fields are a
  no-op (no select-all across an empty range). The handler is
  separate from the form-level `FocusNode` that drives
  `autoSaveOnBlur`; the two co-exist without conflict.
- All colors come from `OmniTheme.colors` /
  `ThemeData.colorScheme`. No hardcoded colors.

**Test seam**: `handlePickedImage(XFile)` and `clearImage()` are
both `@visibleForTesting` on the form's state. Production callers
go through the OS picker via `_pickImage(ImageSource)` and the
× overlay via the `FoodFormImageTile.onClear` callback; tests
invoke the seams directly to bypass the platform channel and
overlay tap.

---

### `_CategoriesTab` (private to `AddFoodScreen`)

**File**: `lib/features/nutrition/add_food_screen.dart` (private
`_CategoriesTab`, `_GroupRow`, `_UngroupedRow`, `_DeleteGroupDialog`)

The third tab of `AddFoodScreen`. Manages the food groups that
organize the user's library. Layout (top to bottom):

- A scrollable list of `_GroupRow` widgets, one per active
  `FoodGroup` (alphabetical, case-insensitive).
- A trailing read-only `_UngroupedRow` (foods with `groupId == null`).
- A "+ New Group" `OutlinedButton.icon` (key `new_group_button`)
  that calls `FoodLibraryState.createFoodGroup('New Group')`.

The list rebuilds via `ListenableBuilder(listenable: foodLibraryState)`
so add / rename / archive operations reflect immediately.

### `_GroupRow` (private to `_CategoriesTab`)

**File**: `lib/features/nutrition/add_food_screen.dart`

One editable food group: inline rename plus delete.

### `_UngroupedRow` (private to `_CategoriesTab`)

**File**: `lib/features/nutrition/add_food_screen.dart`

The synthetic "Ungrouped" bucket. Informational only — it cannot be renamed or deleted, because it
is not a stored `FoodGroup` but the absence of one.

### `_DeleteGroupDialog`

Confirmation dialog for deleting a non-empty group. Title
"Delete group?"; body shows the count of foods to be moved and a
`DropdownButtonFormField` (key `delete_group_destination`) for
the destination group. Options: "Ungrouped" (the default, value
`null`) plus every other active group. Actions: `TextButton("Cancel")`
returns the private `_cancelledSentinel`; `FilledButton("Delete")`
(red `theme.colorScheme.error`, key `delete_group_confirm`)
returns the picked destination id (which may be `null` for
Ungrouped). The caller uses the sentinel to distinguish cancel from
"Ungrouped".

---

> **Doc freshness** — Last reconciled against source: 2026-07-26. This page is one part of the [Widget Catalog](../widget_catalog.md); see that index for the full component list. This doc is derived from source, not hand-maintained. Source of truth: the `lib/` tree. If you find a claim here that disagrees with `lib/`, `lib/` wins.
