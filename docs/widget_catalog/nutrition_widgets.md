# Nutrition Widgets

> Part of the [Widget Catalog](../widget_catalog.md). Return to the index for the complete widget list and the widget → page lookup table.

---

## Nutrition Primitives

### `NutritionPrimerSheet`

**File**: `lib/features/nutrition/widgets/nutrition_primer_sheet.dart`

One-shot orientation sheet for the Daily Nutrition page. The page inverts the usual food-logging model and packs several unfamiliar ideas onto one screen (curate a "Foods I Eat" list once from the global library, check foods off daily with adjustable per-food portions, watch the day roll up into a calories/macros ring + water + sodium), so a brief primer helps a first-time user understand the model. The sheet is single-pane (no carousel, no `PageView`, no Next/Back navigation, no pointers anchored to on-screen widgets) and presents exactly three labeled blocks:

1. **YOUR LIST, BUILT ONCE** — describes the curated "Foods I Eat" list and the Choose foods button and the pencil on the page.
2. **TAP TO LOG, SET THE AMOUNT** — describes logging by tapping a food's picture and the per-food portion amount.
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

**Auto-show contract** (plan 77d): the home strip's tap pushes
`NutritionScreen` at once; the first time it opens (primer unseen) the
screen itself raises this sheet over the screen it explains, and on dismiss
marks the primer seen; the header "?" reopens the same sheet at any time
without touching the seen state. The sheet content scrolls when a small
phone or large text leaves less room than it needs
(`test/screen_overflow_contract_test.dart`, Nutrition cases). Pinned by
`test/row_caption_and_primer_test.dart` (`S-13013`) and
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

Shared form widget used by both the header **+ New Food** flow on
`AddFoodScreen` and the **Edit Food** screen
(`EditFoodScreen`). Parameterized by an optional `Food?` initial
value: `null` → create mode, non-null → edit mode.

The form is parameterized by an optional `Food?` initial value
(`null` → create mode, non-null → edit mode), the `FoodLibraryState`
that sources the categories dropdown (re-reading `activeFoodGroups` on
every notification), a `saveLabel` for the host's CTA, an optional
`showNotesField` flag (edit mode), a required `onSave` callback, and an
optional `onImageChanged` callback (`ValueChanged<String?>` — the
form-local photo path, `null` after the × overlay clears it). The serving
control and the label-like macro block below are stated in full; the
remaining fields' keys and defaults are the file's own.

**Serving control.** One single-choice `SegmentedButton` (key
`food_form_basis`) asks what the nutrition numbers are per: `100 g`,
`100 ml`, `1 serving`, plus `As saved: <amount> <label>` only for a food
whose stored serving the first three cannot express. Under `100 g` /
`100 ml`, a link (key `food_form_package_link`) toggles a package row
with a numeric amount (key `food_form_package_amount`, g or ml only);
under `1 serving`, a label field (key `food_form_serving_label`) pairs
with the chips `food_form_serving_chip_<word>` for slice, scoop, bar,
piece and cup, which fill the field. The heading
`food_form_per_heading` is `servingHeading(choice)` and follows typing;
in edit mode a note `food_form_per_note` reads `Check these numbers are
per <X>` while the serving differs from the one the food was opened
with, and is absent when they match or on a New Food.

The choice maps to the stored fields through the pure-Dart mapper
`lib/core/utils/food_serving.dart` (`servingChoiceFrom`,
`storedServingFrom`, `servingHeading`); the form never compares box text:

| Choice | `unitType` | `referenceAmount` | `referenceLabel` |
|---|---|---|---|
| `100 g` | `grams` | `100` | `g` |
| `100 ml` | `grams` | `100` | `ml` |
| Package serving (e.g. `30 g`, `250 ml`) | `grams` | the typed amount | `g` / `ml` |
| `1 serving` (e.g. slice) | `count` | `1` | the typed label, trimmed |
| `As saved` | the stored triple, unchanged | | |

Verified by `test/food_serving_test.dart` (group `food_serving`:
`S-92b.1 round trip over every shipped catalog triple`, `S-92b.1 round
trip over the odd stored servings`, `S-92b.1 stored serving loads as the
matching choice`, `S-92b.1 odd stored servings load as As saved`,
`S-92b.1 each choice stores its triple`, `S-92b.1 heading strings`) and by
`test/food_form_serving_test.dart` (group `FoodForm serving (S-92b)`:
`S-92b.2 New Food defaults to 100 g and saves grams / 100 / g`,
`S-92b.3 100 ml saves grams / 100 / ml`, `S-92b.4 1 serving requires a
label and the chips fill it`, `S-92b.5 package serving sets the amount,
and Back restores 100 g`, `S-92b.6 an edited food opens on its stored
serving and saves both ways`, `S-92b.7 a package-stored food opens with
its amount and keeps it on save`, `S-92b.8 As saved round trips and
restores the opened triple`, `S-92b.9 the check line appears off the
opened serving and hides again`, `S-92b.11 a millilitre food opens on
100 ml and saves it unchanged`, `S-92b.12 a padded serving label saves
trimmed`, `S-92b.13 package amount 0 and . are rejected`, `S-92b.14 the
package row survives a parent rebuild`, `S-92b.15 chips are hidden off
the serving segment`, `S-92b.16 both edit hosts render the same serving
control`, `S-92b.18 switching segments keeps the typed label and amount`,
`S-92b.19 the note is hidden while the package row reproduces the opened
serving`). A save whose serving differs from the stored one clears the
library copy's remembered log amount, and one that leaves it equal keeps
it — see [nutrition_state.md](../state_management/nutrition_state.md)
and `test/food_library_copy_edit_test.dart` (`S-92b.10 a serving-changing
edit clears the remembered amount`, `S-92b.10 a name-only edit keeps the
remembered amount`, `S-92b.10 a reset after a serving-changing edit
clears the remembered amount`).

The form owns validation, the image picker, and the translation from
controllers to a typed `FoodDraft`. The caller hands the draft to
`FoodLibraryState.createCustomFood` (create) or
`FoodLibraryState.updateCustomFood` / `updateCatalogFood` (edit) —
never to the repository directly. One more edit host exists: when the
screen is given a library copy of a bundled catalog food
(`isCatalog == false`), `EditFoodScreen` hands the draft to
`FoodLibraryState.editLibraryFood`, which changes only the copy
(verified by `test/library_row_toggle_test.dart`, group
`Library row toggle (plan 77a S-12710..S-12717)` · `S-12719: the Edit
screen routes a bundled copy's save through editLibraryFood`).

**Label-like macro block.** The five macro boxes run top to bottom in the
order a package prints them — Fat (g), Carbs (g), Fiber (g), Protein (g),
Sodium (mg) — with the keys `food_form_fat`, `food_form_carbs`,
`food_form_fiber`, `food_form_protein` and `food_form_sodium`; create and
edit share one order, and the photo tile `food_form_image_tile` sits below
the name field rather than at the top of the list. A new food opens with
all five boxes empty and a faint `0` hint; the hint and
`FloatingLabelBehavior.always` belong to the macro boxes only. An edit
prefills through `formatGrams`, so a stored `31.0` reads `31`, and a
never-recorded fiber or sodium stays empty so an unchanged save keeps it
unrecorded. The blank-save contract follows from that: a blank Protein,
Carbs or Fat saves `0`, a blank Fiber or Sodium saves "not recorded"
(`null`), and a lone `.` surfaces `Must be a number` without saving — the
macro validator never requires a value, and amount fields keep `Required`
for their own positive check. Calories are derived, never stored: the line
under Sodium (key `food_form_calories`, `= <N> cal`) computes from the
parsed boxes through `caloriesFromMacros` in
`lib/core/utils/food_helpers.dart`, the same function `calculateCalories`
delegates to, so the line and every stored food's `<cal> cal` agree. Macros
are stored as `double` on `Food` / `FoodDraft` so fractional grams persist;
fiber is exposed alongside carbs, matching `Food.fiber`, and
`calculateNetCarbs(food)` owns the net-carb math.

Verified by `test/food_form_label_test.dart` (top-level `testWidgets`, no
group): `S-92c.2: the macros run top to bottom in package order`,
`S-92c.3: a new food starts with five blank boxes and a faint 0`,
`S-92c.4: a name-only food saves blanks as 0.0 and null`,
`S-92c.5: edit prefills with formatGrams and keeps a null fiber empty`,
`S-92c.6: a lone dot blocks Save with "Must be a number"`,
`S-92c.14: a stored 0.0 fiber opens as 0 and stays 0.0`,
`S-92c.14: an unrecorded fiber and sodium open empty and save null`,
`S-92c.14: typing then clearing sodium saves null`,
`S-92c.16: the always-on label and faint 0 are macro-only`,
`S-92c.1: the calories line follows the macros`,
`S-92c.13: fractional macros agree on the line and the row`,
`S-92c.7: the photo tile sits below the name, above Category`; the formula
itself by `test/food_library_state_test.dart` (group `Food Helper
Functions`: `S-92c.9 caloriesFromMacros computes whole-number macros`,
`S-92c.9 caloriesFromMacros rounds half away from zero`,
`S-92c.9 caloriesFromMacros matches calculateCalories`).

**Duplicate-name note.** While the live name text matches an existing food,
`FoodLibraryState.nameExistsInLibrary(name, excluding: initial)` shows a
quiet note (key `food_form_duplicate_note`) under the name, above the photo
tile and the Category dropdown. It never blocks Save and never changes
validation. The predicate is name-only — trimmed and case-folded — and skips
the food being edited plus its `catalogId` twin in either direction, so
editing a copy of a bundled food notes only a rename. Verified by
`test/food_form_label_test.dart` (`S-92c.8: an existing catalog name shows
the note, Save works`, `S-92c.8: editing a user-created food notes only a
rename`, `S-92c.8: editing a library copy of a bundled food shows none`,
`S-92c.10: padded and differently-cased names still match`,
`S-92c.11: clearing the name hides the note`, `S-92c.12: two rows with the
same name show one note`) and by `test/food_library_state_test.dart` (group
`nameExistsInLibrary`: `S-92c.9 returns true for a catalog food`,
`S-92c.9 returns true for a library-only food`, `S-92c.9 returns false for
an archived food`, `S-92c.9 returns false for the excluded library row
itself`, `S-92c.9 returns false for the excluded catalog row itself`,
`S-92c.9 excluding a library copy ignores its catalog twin`,
`S-92c.9 excluding a catalog row ignores its library copies`,
`S-92c.9 a legacy row with no catalogId is a separate food (D-92c.13)`,
`S-92c.9 returns false for a blank name`, `S-92c.9 ignores case and
surrounding spaces`).

**Save CTA**: the form does **not** render an inline save button. Every host
owns a primary bottom CTA through the shared `OmniBottomCTA` (see
`docs/plans/primary-bottom-cta-anchor-width-plan.md`) and wires its `onPressed` to
`FoodFormController.submit`, so the validation + save pipeline stays in one
place. `_NewFoodFormScreen`, `_LegacyLibraryEditScreen` and `EditFoodScreen`
all follow that wiring: each renders a bottom `Save` with key `food_form_save`
(New Food's CTA reads `Save`, not `Create` — `test/nutrition_test.dart`, group
`AddFoodScreen — + New Item (S-004 / S-005)` · "the New Food bottom bar says
Save, not Create (S-92a.10)"), and `EditFoodScreen` pairs it with the
unsaved-changes guard below.

**Contracts that outlive the file's internals**:

- `onSave` returns `true` to pop, `false` to surface feedback.
- Nothing about the photo writes until Save: the save draft carries
  `imagePath`, and the state method that applies it (`updateCatalogFood`,
  `editLibraryFood`, `updateCustomFood`) owns the D-7 delete of the replaced
  managed file — the form never calls the service directly. A pick only
  copies the picked file into the managed directory and moves the form's
  local path; a clear only nulls that path. Verified by
  `test/food_photo_clear_legacy_edit_test.dart` (`clearing a legacy library
  food's photo waits for the Save tap`) and `test/food_form_pick_saves_test.dart`
  (groups `FoodForm: a picked photo waits for Save (S-92a.5)` and `FoodForm: a
  cleared photo waits for Save (S-92a.6)`).
- `onImageChanged` reports that form-local path, because a pick or a clear is
  neither a rendered field nor an `EditableText` and is therefore invisible to
  the probe's field walk. All three hosts mark a `FoodFormUnsavedProbe` with
  it; the probe compares the reported path with the one the screen opened
  with, so New Food (which starts from no photo) is dirty after a pick and
  clean again after pick-then-clear, while the two edit screens start from the
  stored `imagePath`. Verified by `test/nutrition_test.dart`, group
  `AddFoodScreen — New Food form unsaved guard (S-2902)` ·
  "a picked photo counts as unsaved work (S-2902)" and "picking then
  clearing the photo is clean again (S-2902)", and by
  `test/food_photo_clear_legacy_edit_test.dart`.
- **Select-all on focus is per-field, not form-wide** (S-004..S-006):
  the numeric entry fields each carry a per-field `FocusNode` wired
  to the shared `bindSelectAllOnFocus` helper, so tapping a
  pre-filled field highlights the entire value and the user can
  retype without first clearing it; empty fields are a no-op. The
  free-text name field and the multi-line notes field are
  intentionally NOT wired — they keep default cursor-placement
  behaviour.
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
overlay tap. Neither seam saves — both move the form-local path
and report it through `onImageChanged`.

---

### `FoodFormUnsavedProbe`

**File**: `lib/features/nutrition/widgets/food_form_unsaved_probe.dart`

The unsaved-work probe every `FoodForm` host shares: `EditFoodScreen`,
`_NewFoodFormScreen` and the legacy library edit shim each build one with
the form's `GlobalKey` and mark it from `FoodForm.onImageChanged`, so the
three guards cannot drift apart. A plain class, not a widget. It reads the
form's rendered `FormField`s for its baseline and reports a later difference
as unsaved work; `initialImagePath` is the stored photo a pick or a clear is
compared against. The blank-form and edited-form outcomes are verified by
`test/nutrition_test.dart` (groups `AddFoodScreen — New Food form unsaved
guard (S-2902)` and `AddFoodScreen — legacy edit shim unsaved guard
(S-2902)`) and by `test/edit_food_save_test.dart` (`S-92a.3: back with edits
asks; Discard drops them and Keep editing stays`, `S-92a.4: back on an
untouched form closes with no dialog`).

---

### `_CatalogRow` (private to `AddFoodScreen`)

**File**: `lib/features/nutrition/add_food_screen.dart` (private
`_CatalogRow`, `_CatalogRowState`)

One row of the Library tab, one per catalog food. The whole row is the
toggle: a food not in the user's library is added by tapping the row (the
trailing `Add` button, key `add_catalog_food_<id>`, does the same); a food
in the library is removed by tapping the row, which asks
`Remove <name> from Foods I Eat?` first (keys `food-remove-cancel` /
`food-remove-confirm`) and unlogs the food for today on confirm. An in-list
row shows the user's copy with a primary-colour outline (key
`library_row_outline_<id>`), a pencil `IconButton` (key
`edit_catalog_food_<id>`, tooltip `Edit food`) that opens `EditFoodScreen`
with the library copy for a bundled food and with the catalog row itself
for a user-created food, and a check (key `remove_catalog_food_<id>`)
where the red trash button used to be. The row's text is two lines:
`<cal> cal per <serving>` and `<P>P · <C>C · <F>F`, the serving built by
`foodServingLabel` in `lib/core/utils/food_helpers.dart`. Verified by
`test/library_row_toggle_test.dart` (group `Library row toggle (plan 77a
S-12710..S-12717)`: `S-12710: row tap adds a not-in-list food to the
library`, `S-12711: in-list row tap asks before removing; Cancel keeps,
Confirm removes and unlogs today`, `S-12712: the in-list row carries the
primary outline; the not-in-list row has none`, `S-12713: pencil on an
in-list bundled food edits the copy; reset restores the shipped values`,
`S-12714: the pencil does not toggle the row`, `S-12715: the row macro
line reads the copy after an edit`, `S-12716` source guard on
`_CatalogRowState`, `S-12717: a user-created (non-bundled) in-list food
has no Reset button`) and by `test/screen_widget_test.dart` (`Library row
tap adds the food; its pencil opens EditFoodScreen (S-001)`).

---

### `_LibrarySectionHeader` (private to `AddFoodScreen`)

The category heading in the Library list (key `library_section_<title>`): the
category name in the section-title style, with no divider between it and its
first food. Shown only while the search box is empty. Covered by
`test/library_grouping_test.dart` (`S-12820`, `S-12825`).

### `_YoursTag` and `_UserFoodRow` (private to `AddFoodScreen`)

`_YoursTag` is the small primary-colour `Yours` label after a food's name. A
`_CatalogRow` shows it (key `yours_tag_<foodId>`) when the food is not bundled;
`_UserFoodRow`, now used only for older library-only custom foods, always shows
it and keeps its red delete button (`delete_user_food_<id>`). Both rows appear in
the one Library list. Covered by `test/library_merge_test.dart` (`S-12811`,
`S-12812`).

### `_GroupsTab` (private to `AddFoodScreen`)

**File**: `lib/features/nutrition/add_food_screen.dart` (private
`_GroupsTab`, `_GroupRow`, `_UngroupedRow`, `_DeleteGroupDialog`)

The second tab of `AddFoodScreen`. Manages the food categories that
organize the user's library. Layout (top to bottom):

- A scrollable list of `_GroupRow` widgets, one per active
  `FoodGroup` (alphabetical, case-insensitive).
- A trailing read-only `_UngroupedRow` (foods with `groupId == null`).
- No bottom button: the host's header "+" (`OmniHeaderAddButton`, read
  aloud `New Category`, key `new_group_button`) calls
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
