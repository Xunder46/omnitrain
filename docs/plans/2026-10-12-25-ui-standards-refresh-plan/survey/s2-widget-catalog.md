# S2 · Widget catalog vs the widgets that exist (read-only)

Scout sheet, 2026-10-12. Sources read this run: `docs/widget_catalog.md` + all five part pages,
`lib/widgets/**` (glob, 30 files), `lib/features/**/widgets/` (glob, 29 files), targeted greps as cited.

## Item 1 · Catalog names vs source (STALE-DOC)

Checked 41 names in the index lookup table plus 17 widgets named in the index notes and part pages
(58 total). 56 exist at the stated path with the stated role (verified by class-declaration grep this
run). 2 misses:

### F1 · STALE-DOC · `_ResumeSessionDialog` no longer exists
- Where the doc says it: `docs/widget_catalog.md` (index, "Note on resume dialog"):
  "The cold-start `Unfinished Session` dialog is implemented as a private, screen-local widget in
  `HomeScreen` (`_ResumeSessionDialog`)."
- Where the code does it: `lib/features/home/home_screen.dart:138-141` and `:176-183` — the cold-start
  resume is now silent restoration, no dialog:
  ```dart
  if (!_resumeCheckDone) {
    widget.workoutState.checkForInProgressSession();
    _resumeCheckDone = true;
  }
  ```
  and in a post-frame callback: `final session = await widget.workoutState.checkForInProgressSession();
  if (session != null && mounted) { await widget.workoutState.loadHistoricalSession(session.id); }`
- What a user would see: returning to the app with an unfinished session no longer asks anything; the
  session is silently reloaded.
- Guard: none found: searched `ResumeSessionDialog`, `Unfinished Session`, `resume dialog` in `lib/`.
- Unsure: whether a test still references the old dialog (did not search `test/`).

### F2 · STALE-DOC · `_CategoriesTab` renamed `_GroupsTab`
- Where the doc says it: `docs/widget_catalog/nutrition_widgets.md` ("### `_CategoriesTab` (private to
  `AddFoodScreen`)" and "File: `lib/features/nutrition/add_food_screen.dart` (private
  `_CategoriesTab`, `_GroupRow`, `_UngroupedRow`, `_DeleteGroupDialog`)").
- Where the code does it: `lib/features/nutrition/add_food_screen.dart:1302`
  `class _GroupsTab extends StatefulWidget {`. `_GroupRow` (:1562), `_UngroupedRow` (:1625),
  `_DeleteGroupDialog` (:1669) all exist as documented.
- What a user would see: nothing (private class name only).
- Guard: none found: searched `class _CategoriesTab` in `lib/`.
- Unsure: whether the "+ New Group" button details in that entry still match `_GroupsTab`'s build
  (did not read the whole tab body).

## Item 2 · Public classes in `lib/widgets/**` no catalog file mentions (UNDOCUMENTED, kind NO-RULE)

Method: class-declaration grep over `lib/widgets/**`, then grep of each name in `docs/widget_catalog/`.
Names already listed in the index's "Not yet catalogued" table (`InteractiveLogo`,
`ScrollableTrendChart`, `FoodThumbnailImage`) are excluded — the catalog does mention them.

### UNDOCUMENTED · `ConfirmationDialog` + `UnsavedChangesAction`
- File: `lib/widgets/dialogs/confirmation_dialog.dart:19` (`class ConfirmationDialog {`),
  `:5` (`enum UnsavedChangesAction { keepEditing, discard, save }`)
- Role from code: shared two-/three-choice confirmation and unsaved-changes dialog factory
  (`showTwoChoice`, `showUnsavedChanges`, `twoChoice`); 22 call sites across `lib/features`
  (grep `ConfirmationDialog\.` → 22 matches in 15 files).
- Not in any `docs/widget_catalog/*.md` file. It IS described in `docs/design_system.md:356`
  ("enforced by the shared `ConfirmationDialog` component"), so the gap is catalog-only.

### UNDOCUMENTED · `OverheadPressIcon`
- File: `lib/widgets/icons/overhead_press_icon.dart:28`
- Role from code: "Minimalist geometric stick figure performing an overhead barbell press" — tile
  artwork builder for the resistance home tile (`lib/core/constants/home_tiles.dart:61`).
- Not found anywhere in `docs/` (grep `OverheadPressIcon` in `docs/` → 0 matches). The index's
  Directory Structure block lists `icons/` but names no widget.

### UNDOCUMENTED · `chart_primitives.dart` top-level helpers
- File: `lib/widgets/chart/chart_primitives.dart:8` (`kChartBottomAxisReservedSize`), `:13`
  (`buildLegendItem`), `:37` (`buildSinglePointCard`)
- Role from code: shared chart chrome — reserved bottom-axis height, one legend swatch+label row, and
  the single-history-point card used by Stats and nutrition-trend charts.
- Not in any `docs/widget_catalog/*.md` file; mentioned only in `docs/plans/**` (D-533).

### UNDOCUMENTED · `buildEdgeAwareDateLabel` + `kEdgeLabelHorizontalShift`
- File: `lib/widgets/chart/edge_aware_date_label.dart:12` (const), `:29` (function)
- Role from code: bottom-axis date label with a horizontal inset on the first/last x positions so the
  labels clear the pinned y-axis and the card border; used by the stats charts and the profile
  measurement history sheet.
- Not in any `docs/widget_catalog/*.md` file; mentioned only in `docs/plans/unify-chart-scrolling-popup-plan.md:361`.

Grouping by folder: `dialogs/` 1 (ConfirmationDialog), `icons/` 1 (OverheadPressIcon), `chart/` 2 files
(4 public symbols). All other `lib/widgets/` public classes are catalogued.

## Item 3 · Two or more widgets doing the same user-visible job (INCONSISTENT)

### F3 · INCONSISTENT · Outlined card chrome: `OmniSurface` vs raw `Card()`
- Where the doc says it: `docs/widget_catalog/layout_and_inputs.md` (`OmniSurface`): "No call-site may
  re-declare border, radius, or shadow for an outlined card."
- Where the code does it: `lib/features/session/workout_session_list_view.dart:161` and
  `lib/features/routine/routine_setup_screen.dart:354` and `:1113` — raw `Card(` with
  `elevation: 2`, `borderRadius: BorderRadius.circular(12)`, `color: …surface.withOpacity(0.7)`.
- What a user would see: session-block and routine-segment cards have a different corner radius,
  elevation and translucency than every card that goes through `OmniSurface`.
- Guard: none found: searched `Card\(` in `lib/features` (4 matches, one is a comment).
- Unsure: whether `routine_setup_screen.dart:1113` is user-visible or a dead path (did not read context).

### F4 · INCONSISTENT · Text-entry dialogs: no shared widget, five ad-hoc `AlertDialog` forms
- Where the doc says it: nothing — the catalog has no text-entry-dialog entry (searched
  `AlertDialog` in `docs/widget_catalog/`; only `showMetricEditPopup` and `showDurationEntryDialog`
  are documented, both session-scoped).
- Where the code does it (raw `AlertDialog` with a `TextField`, outside `lib/widgets`):
  - `lib/features/session/workout_session_screen.dart:1615` ("Rename Block")
  - `lib/features/profile/profile_screen.dart:644` ("Edit Name") and `:1291` ("Edit Height")
  - `lib/features/routine/routine_setup_screen.dart:832` ("Edit Block")
  - `lib/features/exercise/exercise_library_detail_screen.dart:309` ("Rename exercise")
- What a user would see: five rename/value dialogs that look similar but are built independently;
  button shapes and capitalisation are re-declared per site.
- Guard: none found: searched `AlertDialog\(` in `lib/` (raw sites listed above; the shared
  `ConfirmationDialog` sites are 22 and consistent).
- Unsure: whether `add_food_screen.dart:961` ("Cannot Delete", info-only) belongs in the same family.

### F5 · INCONSISTENT · Feedback `SnackBar`s: `PRToast` is shared, error/info toasts are per-screen
- Where the doc says it: `docs/widget_catalog/session_widgets.md` documents `PRToast` only for the PR
  celebration; no doc covers error/info snackbars.
- Where the code does it: raw `SnackBar(` outside `lib/widgets` — 30+ sites, e.g.
  `lib/features/session/workout_session_screen.dart:1550,1560,1583`,
  `lib/features/nutrition/add_food_screen.dart:152,306,768,1034,1240,1269,1481,1516`,
  `lib/features/routine/routine_setup_screen.dart:959,968,1000,1034,1041`,
  `lib/features/exercise/exercise_library_detail_screen.dart:95,100,124,146`,
  `lib/features/profile/profile_screen.dart:760,1013,1099`,
  `lib/features/session/session_summary_screen.dart:418`, `lib/features/calendar/day_session_list_screen.dart:287,306`.
- What a user would see: error and confirmation messages appear as plain default-shaped snackbars
  whose styling is whatever each screen passed, while the PR toast has its own bespoke treatment.
- Guard: none found: searched `SnackBar\(` in `lib/`.
- Unsure: whether any theme-level `snackBarTheme` normalises them (did not read `app.dart`/theme).

### F6 · INCONSISTENT · Bottom sheets: shared sheet widgets exist, but hosts open raw `showModalBottomSheet` with no shared chrome
- Where the doc says it: nothing — no catalog entry defines a shared bottom-sheet container.
- Where the code does it: 15 raw `showModalBottomSheet(` call sites outside the three shared sheet
  widgets (`EffortRatingSheet`, `NutritionPrimerSheet`, `StatsPrimerSheet`), e.g.
  `lib/features/session/workout_session_global_timer.dart:126,304`,
  `lib/features/settings/settings_screen.dart:448,462`,
  `lib/features/calendar/day_session_list_screen.dart:315,339`,
  `lib/features/home/home_screen.dart:361,408,810`,
  `lib/features/profile/profile_screen.dart:493,724,742`,
  `lib/features/session/session_summary_screen.dart:481`, `lib/features/nutrition/nutrition_screen.dart:112`,
  `lib/features/stats/stats_screen.dart:349`, `lib/features/nutrition/widgets/food_form.dart:1099`.
- What a user would see: sheets whose corner shape, background and drag behaviour are decided
  per screen.
- Guard: none found: searched `showModalBottomSheet` in `lib/`.
- Unsure: whether a theme-level `bottomSheetTheme` normalises the chrome (did not read the theme).

Counts for the record: raw `showDialog(` outside `lib/widgets` — 2 (`workout_session_edit_mode.dart:145`
delegates to `ConfirmationDialog.showUnsavedChanges`; `session_summary_screen.dart:364,391` — the
latter two wrap shared widgets, not checked). Raw `AlertDialog(` outside `lib/widgets` — 6 sites
(F4 + add_food 961). Raw `showModalBottomSheet(` — 15 sites (F6). Raw `SnackBar(` — 30+ sites (F5).

## Item 4 · Visual values / control inventories repeated in the catalog (DOC-OFF-STANDARD)

`docs/documentation_standard.md` forbids visual values and control inventories in docs (per
`.work/2026-10-12-25-ui-standards/common.md`). Up to 5 quotes, cap reached:

### F7 · DOC-OFF-STANDARD · Column-cap numbers in `layout_and_inputs.md`
- Where the doc says it: `docs/widget_catalog/layout_and_inputs.md:41,44,46`:
  "- **Phone-class widths** (≤ 500 dp, includes every phone and a" / "- **Tablet-class widths** (> 500 dp …"
  "`OmniTheme.kColumnMaxWidth` (480) dp, with equal empty margins on"; also `:25` "Optional radial white
  highlight (10% opacity)".
- What a user would see: n/a (doc-only).
- Guard: none found: searched `480|500 dp` in `docs/widget_catalog/`.
- Unsure: nothing.

### F8 · DOC-OFF-STANDARD · Animation durations in `feature_primitives.md`
- Where the doc says it: `docs/widget_catalog/feature_primitives.md:136` "Animated brand mark with slow
  rotation (8000ms) and breathing pulse (3000ms)"; `:142` "Stroke reveal animation at 1200ms".
- What a user would see: n/a (doc-only).
- Guard: none found.
- Unsure: nothing.

### F9 · DOC-OFF-STANDARD · Crop-sheet geometry in `feature_primitives.md`
- Where the doc says it: `docs/widget_catalog/feature_primitives.md:59` "`min(screenW - 32, 360)`";
  `:62` "`InteractiveViewer` (`minScale: 1.0`, `maxScale: 4.0`)"; `:78` "`RepaintBoundary.toImage(pixelRatio: 3.0)`".
- What a user would see: n/a (doc-only).
- Guard: none found.
- Unsure: nothing.

### F10 · DOC-OFF-STANDARD · Tile size and input regex in `nutrition_widgets.md`
- Where the doc says it: `docs/widget_catalog/nutrition_widgets.md:95` "square 96×96 tile"; `:100`
  "via the `^\d*\.?\d*$` regex filter".
- What a user would see: n/a (doc-only).
- Guard: none found.
- Unsure: nothing.

### F11 · DOC-OFF-STANDARD · Dispose delay in `session_widgets.md`
- Where the doc says it: `docs/widget_catalog/session_widgets.md:114` "`TextEditingController`s are
  deferred-disposed (300 ms after dialog close)".
- What a user would see: n/a (doc-only).
- Guard: none found.
- Unsure: nothing.

Control inventories also present (not quoted, cap reached): the `FoodForm` field list
(`nutrition_widgets.md:95-101`, a 7-step top-to-bottom control inventory) and the primer-sheet block
lists (`nutrition_widgets.md`, `stats` note in the index).

## Not checked
- `test/` coverage for F1 (whether a test still drives the removed resume dialog).
- Whether `routine_setup_screen.dart:1113` raw `Card()` is reachable.
- Theme-level `snackBarTheme` / `bottomSheetTheme` normalisation (F5/F6).
