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

A single food-library row that doubles as the "log a food as consumed"
affordance on the nutrition page. Layout, left to right:

```
[ thumb toggle ]  [ name (1 line) + "<cal> cal · <P>P · <C>C · <F>F" ]  [ amount input + unit label ]
```

**Iteration 1 (thumbnail toggle)** replaced the leading `Checkbox`
with a tappable food thumbnail. The thumb IS the log/unlog toggle
(S-001): tapping it logs the food at the current amount (or unlogs).
Foods with `imagePath` show the image; foods without show the muted
placeholder from `FoodThumbnail` (S-002 — the common case on web
where the image picker is a no-op). The visible thumb is 40×40 and
the tap target is padded to **48×48** (design-system gym-glove rule).
The thumb's `Semantics(checked: isLogged, label: "Log <name>" /
"Unlog <name>", button: true)` wrapper exposes the toggle to screen
readers and tests via `flagsCollection.isChecked` (S-005).

**Selected state** (S-003): 2 px primary border + a 16×16 check badge
in the top-right corner filled with `primary`. The transition is
animated via `AnimatedContainer` (border) and `AnimatedOpacity`
(badge) at `OmniTheme.animationDuration` (180 ms) and
`OmniTheme.animationCurve` (`easeInOut`). **Unselected state**
(S-004): 1 px hairline `divider` border, no badge. **Press feedback**
(S-003 / S-004): an `AnimatedScale` shrinks the visible thumb to
0.96× its size while pressed.

The amount input behavior is unchanged from prior iterations — the
typed value is the food's own-unit amount for grams foods and a
multiplier for count foods. Editing the amount on a logged row
auto-commits the new amount to the day log (debounced ~250 ms).
Validation: amount must be `> 0`; an invalid amount makes the thumb
tap a no-op and renders an inline error.

**Pre-fill priority (food-last-amount-plan, June 2026)** — when the
food is not logged today, the amount input is pre-filled in this
order: (1) `food.lastAmountConsumed` (the user's last saved portion
for this food, in its own unit) — null when the food has never been
logged; (2) `food.referenceAmount` for grams-type (e.g. 100 g); (3)
`1.0` for count-type (the default multiplier). When the food IS
logged today, the existing `findLoggedTodayForFood` lookup wins and
the pre-fill is the day's `amountConsumed` value (today's value
overrides any remembered yesterday's value).

**Iteration 1 (single-line macros — S-007)** replaced the 2×2 macro
grid with a single `Text` line in the format
`"<cal> cal · <P>P · <C>C · <F>F"` (e.g. `"90 cal · 0P · 0C · 10F"`)
for format parity with `AddFoodScreen` rows. The line is one `Text`
widget with `maxLines: 1` and `TextOverflow.ellipsis`.

| Prop | Type | Description |
|------|------|-------------|
| `food` | `Food` | The library food to render and toggle. |
| `nutritionState` | `NutritionState` | Day-log state (read for `isFoodLoggedToday`; mutate via `logConsumedFoodAt` / `unlogFoodToday`). |
| `foodLibraryState` | `FoodLibraryState` | Symmetric constructor parameter; not mutated by the row. |

**Stable keys (for tests)**:
- `Key('log_food_thumb_<food.id>')` — mounted on the `Semantics`
  wrapper of the thumb toggle (not the inner `GestureDetector`).
  Tests look up the toggle's checked state via
  `tester.getSemantics(find.byKey(...)).getSemanticsData().flagsCollection.isChecked`
  (returns `CheckedState.isTrue` when logged, `CheckedState.isFalse`
  when not). The key is on `Semantics` (not `GestureDetector`) so
  that semantics-tree lookups find the correct node carrying the
  `checked` / `label` properties.
- `Key('log_food_amount_<food.id>')` — mounted on the amount input.

**Row separation (S-006)**: hairline dividers (`divider` color,
1 px) render between rows in a group, never after the last row.
Implemented in `_GroupBlock` (the private widget in
`nutrition_screen.dart` that renders each food group). The
per-divider key is `Key('group_<groupName>_divider_<i>')` where
`<i>` is the row index that follows the divider.

The widget rebuilds via `ListenableBuilder(listenable: nutritionState)`
so the thumb's checked state and the amount input's pre-fill update
the moment a log is written.

---

### `FoodThumbnail`

**File**: `lib/features/nutrition/widgets/food_thumbnail.dart`
(platform image renderer split into
`food_thumbnail_io.dart` / `food_thumbnail_stub.dart` via
conditional import — same pattern as `ProfileAvatarImage` in
`lib/features/profile/widgets/`).

A 40×40 rounded thumbnail for a food item, with a placeholder
when no image is set. Mirrors the contract of `ProfileAvatarImage`:
the image is loaded from a local file path on native and falls
back to a placeholder on web or when the file is missing.

Used as the leading slot on each catalog row in the **Library**
tab of `AddFoodScreen` (key `food_catalog_thumb_<id>`). The slot
is always present (placeholder when no image) so the trailing
Add / Remove button column does not reflow when an image is
added or removed. The same widget is also used inside the
`FoodForm`'s image picker tile.

| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `imagePath` | `String?` | required | Local file path to a food photo. `null` / empty / unreadable path falls back to the placeholder. |
| `size` | `double` | `40` | Diameter in logical pixels. |
| `radius` | `double` | `8` | Corner radius — matches the `OmniTheme.buttonUtilityRadius` token. |

**Behavior**:
- Always renders a fixed-size slot. The slot is filled with the
  image (`Image.file` on native with an `errorBuilder` fallback)
  or a placeholder (`Icons.restaurant_outlined` tinted with
  `OmniTheme.colors.textMuted` on a `surface` background).
- Pure presentation — no repository / state access, no business
  logic. The `imagePath` is a plain `String?` read at build time.
- The `kIsWeb` short-circuit keeps `dart:io` out of the web build.

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
1. Image picker tile (`FoodFormImageTile`, key `food_form_image_tile`) — square 96×96 with × (clear) and edit (change) overlays; opens a Camera / Gallery bottom sheet on tap; web is a no-op with a snackbar.
2. Name (`food_form_name`) — `TextFormField` with `TextCapitalization.words`.
3. Group (`food_form_group`) — `DropdownButtonFormField<String?>` of the active groups + an "Ungrouped" `null` entry.
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

| Param | Type | Purpose |
|---|---|---|
| `group` | `FoodGroup` | The group to render |
| `controller` | `TextEditingController` | Stable per-group controller (held by `_CategoriesTabState._controllers`); preserves in-progress rename text across rebuilds |
| `foodCount` | `int` | Number of foods in this group; rendered in the `suffixText` |
| `onRename(String)` | `Future<void> Function(String)` | Calls `FoodLibraryState.renameFoodGroup(id, newName)` |
| `onDelete()` | `Future<void> Function()` | Opens the confirm dialog (or silent-deletes when `foodCount == 0`) |

The `TextField` is keyed `group_name_<group.id>` and commits the
rename on `onEditingComplete` (IME action / unfocus) and on
`onSubmitted` (Enter). The trash `IconButton` is keyed
`group_delete_<group.id>`. Both use `OmniTheme.colors` and
`theme.colorScheme` — no hardcoded colors.

### `_UngroupedRow` (private to `_CategoriesTab`)

A read-only, single-row summary of foods with `groupId == null`.
Renders an `Icons.label_off_outlined` icon, the label "Ungrouped"
(italic, muted), and the food count. No `TextField`, no trash
affordance — the row is purely informational.

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
