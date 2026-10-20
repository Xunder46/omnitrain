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
- Single `FilledButton` "Got it" CTA, full width, sized from the shared
  button tokens (`OmniTheme.buttonPrimaryHeight`,
  `OmniTheme.buttonBorderRadius`) with an explicit shape — no Material 3
  `StadiumBorder`. Color from `theme.colorScheme.primary`.
- The three blocks use a section header `OmniCardHeader` (or the canonical D-1 typography) per the global section-header contract.
- The "Got it" CTA fires `Navigator.of(context).pop()` and then `onDismiss?.call()`. The seen-state mutation lives in the host screen (`HomeScreen._openNutritionScreen` calls `nutritionPrimerState.markSeen()` AFTER the sheet pops), NOT inside the sheet — the sheet is presentation-only.
- The header "?" control on `NutritionScreen` uses the same widget but passes an `onDismiss` that does NOT call `markSeen()` — the seen state is preserved across reopens.

**Auto-show contract**: the home strip's first-ever tap opens this sheet
over the home screen, and on dismiss the host marks the primer seen and
pushes `NutritionScreen`; the header "?" on `NutritionScreen` reopens the
same sheet at any time without touching the seen state. Pinned by
`test/nutrition_primer_test.dart` (groups 'S-001: first nutrition strip
tap shows the primer', 'S-003: header "?" reopens the primer regardless
of seen state', 'S-005: primer never gates access', 'S-006: wrong-pattern
guard — persisted value, not in-memory').

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

**Amount edits auto-commit on a logged row.** Editing the amount on a food already
logged today writes the new amount to the day log automatically (debounced; see
`_scheduleAutoCommit` in `lib/features/nutrition/widgets/log_food_row.dart`) — the
user does not re-tap the thumb. The thumb tap is the explicit commit only for the
first log of an unlogged food.

The row's selected and unselected states are visually distinct without relying on colour alone.

Calories are derived from the macros, never stored on `Food` — `calculateCalories` in
`lib/core/utils/food_helpers.dart` is the owner of that derivation.

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

The form is parameterized by an optional `Food?` initial value
(`null` → create mode, non-null → edit mode), the `FoodLibraryState`
that sources the categories dropdown (re-reading `activeFoodGroups` on
every notification), a `saveLabel` for the host's CTA, an optional
`showNotesField` flag (edit mode), a required `onSave` callback, an
optional `onImageSave` partial-save callback, and an optional
`onImageChanged` callback (`ValueChanged<bool>?` — `true` after a
photo is picked, `false` after it is cleared). Its field set, per-field
keys and defaults are the file's own — read them in
`lib/features/nutrition/widgets/food_form.dart` rather than here; this
page does not restate the control list.

The form owns validation, the image picker, and the translation from
controllers to a typed `FoodDraft`. The caller hands the draft to
`FoodLibraryState.createCustomFood` (create) or
`FoodLibraryState.updateCustomFood` / `updateCatalogFood` (edit) —
never to the repository directly. Macro and amount fields accept
decimal entry, and macros are stored as `double` on `Food` /
`FoodDraft` so fractional grams persist. Fiber is exposed alongside
carbs, matching the `Food.fiber` field on the model;
`calculateNetCarbs(food)` in `lib/core/utils/food_helpers.dart` handles
the net-carb math.

**Save CTA**: the form does **not** render an inline save button. Hosts that show
a primary bottom CTA own it via the shared `OmniBottomCTA` (see
`docs/plans/primary-bottom-cta-anchor-width-plan.md`) and wire its `onPressed` to
`FoodFormController.submit`. `EditFoodScreen` is the exception: it has **no**
save button at all — it passes `autoSaveOnBlur: true, skipPopOnSave: true`, so
edits persist when focus leaves the form (see
`lib/features/nutrition/edit_food_screen.dart`).

**Contracts that outlive the file's internals**:

- `onSave` returns `true` to pop, `false` to surface feedback.
- `onImageSave` (edit mode only) is fired after a successful photo
  pick **or** after the × (clear) overlay empties the photo. The
  draft is built from `initial` with only `imagePath` swapped, so
  concurrent edits to the form's text controllers (a half-typed name,
  for example) are preserved, and the state method owns D-7 cleanup
  of the previous managed file — the form does not call the service
  directly. On hosts that have no Save button (`EditFoodScreen` with
  `autoSaveOnBlur: true`), this is the **only** path that writes the
  picked photo to the data layer before the user navigates away, so
  without it the photo would not persist. **Not fired in create
  mode** — the image is just stored locally until the user saves the
  whole food.
- `onImageChanged` is the create-mode guard signal: the host marks
  picked/cleared photo state as unsaved work so the unsaved-changes
  guard can fire. `AddFoodScreen` wires it to its unsaved-work probe;
  the legacy edit-mode shim leaves it unwired (edit mode has
  `onImageSave` instead). Verified by `test/nutrition_test.dart`,
  group `AddFoodScreen — New Food form unsaved guard (S-2902)` ·
  "a picked photo counts as unsaved work (S-2902)" and "picking then
  clearing the photo is clean again (S-2902)".
- **Select-all on focus is per-field, not form-wide** (S-004..S-006):
  the numeric entry fields each carry a per-field `FocusNode` wired
  to the shared `bindSelectAllOnFocus` helper, so tapping a
  pre-filled field highlights the entire value and the user can
  retype without first clearing it; empty fields are a no-op. The
  free-text name field and the multi-line notes field are
  intentionally NOT wired — they keep default cursor-placement
  behaviour. The handler is separate from the form-level `FocusNode`
  that drives `autoSaveOnBlur`; the two co-exist without conflict.
- All colors come from `OmniTheme.colors` /
  `ThemeData.colorScheme`. No hardcoded colors.

The photo tile's three-tier photo precedence (user-picked
`imagePath`, then the bundled photo resolved from the food's id, then
placeholder) and the clear-overlay gating (the shipped photo is the
food's baseline, not the user's) are the shipped-photo rules verified
by `test/food_form_shipped_photo_test.dart` (S-001..S-006). The group
dropdown's orphan-category handling is verified by
`test/food_form_orphan_category_test.dart` (group 'FoodForm: orphan
category (S-001 / S-002)'). Decimal entry and per-field select-all
are verified by `test/food_form_decimals_and_autofocus_test.dart`
(groups 'FoodForm: decimal macros (S-001/S-002/S-003)' and 'FoodForm:
auto-select on focus (S-004/S-005/S-006)').

**Test seam**: `handlePickedImage(XFile)` and `clearImage()` are
both `@visibleForTesting` on the form's state. Production callers
go through the OS picker via `_pickImage(ImageSource)` and the
× overlay via the `FoodFormImageTile.onClear` callback; tests
invoke the seams directly to bypass the platform channel and
overlay tap.

---

### `_GroupsTab` (private to `AddFoodScreen`)

**File**: `lib/features/nutrition/add_food_screen.dart` (private
`_GroupsTab`, `_GroupRow`, `_UngroupedRow`, `_DeleteGroupDialog`)

The third tab of `AddFoodScreen`. Manages the food categories that
organize the user's library. Layout (top to bottom):

- A scrollable list of `_GroupRow` widgets, one per active
  `FoodGroup` (alphabetical, case-insensitive).
- A trailing read-only `_UngroupedRow` (foods with `groupId == null`).
- A "+ New Category" bottom button (the shared `OmniBottomCTA`,
  key `new_group_button`) that calls
  `FoodLibraryState.createFoodGroup('New Category')`.

The list rebuilds via `ListenableBuilder(listenable: foodLibraryState)`
so add / rename / archive operations reflect immediately.

### `_GroupRow` (private to `_GroupsTab`)

**File**: `lib/features/nutrition/add_food_screen.dart`

One editable food group: inline rename plus delete.

### `_UngroupedRow` (private to `_GroupsTab`)

**File**: `lib/features/nutrition/add_food_screen.dart`

The synthetic "Uncategorized" bucket. Informational only — it cannot be renamed or deleted, because it
is not a stored `FoodGroup` but the absence of one.

### `_DeleteGroupDialog`

Confirmation dialog for deleting a non-empty group: it asks where the
affected foods should move (Uncategorized by default, or another
active group) and returns the picked destination, distinguishing
cancel from an Uncategorized pick via a private sentinel. Cancel leaves
the category and its foods unchanged and does not throw. Verified by
`test/nutrition_test.dart` (group 'AddFoodScreen — Groups tab', tests
'trash icon on a non-empty group shows the confirm dialog' and 'Cancel on a
non-empty category closes the dialog without throwing and keeps the category
and its foods (S-2910)').

---

> **Doc freshness** — Last reconciled against source: 2026-07-26. This page is one part of the [Widget Catalog](../widget_catalog.md); see that index for the full component list. This doc is derived from source, not hand-maintained. Source of truth: the `lib/` tree. If you find a claim here that disagrees with `lib/`, `lib/` wins.
