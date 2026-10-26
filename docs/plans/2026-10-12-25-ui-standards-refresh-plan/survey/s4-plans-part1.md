# S4 — UI plans part 1 pointer sheet (scout)

Surveyed the part-1 plan list from the brief. Finding conditions: (a) NO-RULE, (b) STALE-DOC/BREAKS-RULE, (c) NO-GUARD. Plans whose rules are documented and still true are listed in the final "Checked" line. Superseded plan rules are recorded with the superseding plan named; doc and code were checked to agree in each case.

## Findings

### F1 · BREAKS-RULE · calendar-session-theme-plan: inline delete buttons still hardcode Colors.redAccent
- Where the plan says it: docs/plans/calendar-session-theme-plan.md — AC: "No hardcoded `Colors.redAccent` in `period_list_screen.dart` usage"; Phase 2 (theme-aware delete buttons) is left unchecked `[ ]` in the plan's Progress section.
- Where the code does it: lib/features/calendar/day_session_list_screen.dart:522 `icon: const Icon(Icons.delete_outline, color: Colors.redAccent)` (delete IconButton in the session row); lib/features/period/period_list_screen.dart:236 `color: Colors.redAccent` (trailing delete IconButton).
- What a user would see: the small delete buttons on calendar session rows and period list rows stay a fixed red in every theme, while the rest of those rows follow the active theme.
- Guard: none found: searched test/ for `redAccent` and delete-button colour assertions.
- Unsure: no destructive-action colour token exists in OmniTheme (searched lib/core/constants/omni_theme.dart for `destructive` — none); docs/design_system.md:358 covers destructive *confirmations* (`theme.colorScheme.error`), not inline delete buttons, so there is no doc rule this code breaks — the break is against the plan's AC only.

### F2 · BREAKS-RULE · crown-control-tap-to-edit-plan: visible crown on editable rows is gone (superseded)
- Where the plan says it: docs/plans/crown-control-tap-to-edit-plan.md — every editable metric row shows a visible crown affordance for tap-to-edit.
- Where the code does it: lib/widgets/session/inline_metric_editor.dart — no crown is rendered; a tap on the row opens `showMetricEditPopup` directly (crown widget file is only imported/exported, not displayed).
- What a user would see: metric rows in the live session show no crown; editing happens by tapping the row, as a later plan decided.
- Guard: test/crown_control_tap_to_edit_test.dart exists (covers the tap-to-edit behaviour, not a crown).
- Unsure: nothing material. NOTE: this is a deliberate supersession — docs/plans/tap-to-edit-metric-modal-plan-plan removed the crown from rows, and docs/widget_catalog/session_widgets.md:34,51-53 already says the crown "is present in the codebase but not rendered". Doc and code agree; only the old plan's rule is dead.

### F3 · BREAKS-RULE · home-tile-row-separation-plan: the enlarged gap before the utility row is gone (superseded)
- Where the plan says it: docs/plans/home-tile-row-separation-plan.md — vertical gap between the modality rows and the Free Training/My Routines row ≈ 2x the standard grid gap, whitespace only.
- Where the code does it: lib/features/home/home_screen.dart:592-597 — `rowOf(0, 2)` / `rowOf(2, 4)` / `rowOf(4, 6)` joined by uniform `const SizedBox(height: standardGridSpacing)` between all three rows (comment at :521-523 says "a 16 px gap between rows").
- What a user would see: all three tile rows on the home screen are evenly spaced; there is no extra breathing room before the utility row.
- Guard: none found: searched test/ for row-separation/`rowOf` assertions on the home grid.
- Unsure: nothing material. NOTE: deliberate supersession — docs/plans/train-screen-non-scrolling-layout-plan.md reworked the grid to a non-scrolling layout with a uniform 16 px inter-row gap (:22, :48, :150-151). Doc and code agree; only the old plan's rule is dead.

### F4 · BREAKS-RULE · measurement-history-chart-readability-plan: restored y-axis labels are gone again (superseded)
- Where the plan says it: docs/plans/measurement-history-chart-readability-plan.md — restore vertical-axis value labels on the history popup chart and inset the data line from the chart edges.
- Where the code does it: lib/features/profile/widgets/measurement_history_chart_sheet.dart:151-152,213-221 — the inner `LineChart` disables its own `leftTitles` ("so the labels don't render twice"); the sheet renders inside `ScrollableTrendChart` (:166) whose pinned axis column carries the labels.
- What a user would see: the history chart still shows value labels, but in the shared scrollable-chart layout (pinned axis column), not the fl_chart y-axis the readability plan restored.
- Guard: test/screen_widget_test.dart has a `MeasurementHistoryChartSheet` group (per docs/plans/unify-chart-scrolling-popup-plan.md test plan); not individually verified this run.
- Unsure: nothing material. NOTE: deliberate supersession — docs/plans/unify-chart-scrolling-popup-plan.md D-6/D-7 moved the sheet onto `ScrollableTrendChart` and removed the `take(10)` cap. Doc and code agree (docs/profile_and_measurements.md:134 documents the `ScrollableTrendChart` host); only the old plan's rule is dead.

### F5 · NO-RULE · bilateral-logging-guidance-plan: LOGGING NOTE rule is in no doc
- Where the code does it: lib/features/session/workout_session_global_timer.dart:136-137 (LOGGING NOTE banner logic; bilateral set handling at :212-217, :281).
- What a user would see: when logging one side of a bilateral set, the session shows a note telling the user the other side is still pending.
- Guard: test/exercise_info_sheet_bilateral_test.dart (S-001…S-004), test/catalog_refresh_test.dart (S-007).
- Unsure: nothing. Searched docs/ for `LOGGING NOTE` and `bilateral` — only docs/plans hits.

### F6 · NO-RULE · coach-mark-icon-positioning-plan (+ 2026-07-27-03-pr3-isolated-ui-corrections): coach-mark anchoring rule is in no doc
- Where the code does it: lib/features/session/workout_session_screen.dart:232-233 — `_notesIconKey` / `_infoIconKey`; the coach-mark glow is positioned from the icon glyph's RenderBox geometry.
- What a user would see: the first-run coach mark points exactly at the info/notes icons it describes, not at a fixed screen position.
- Guard: test/exercise_detail_coach_mark_positioning_test.dart.
- Unsure: nothing. Searched docs/ for glow / icon glyph / RenderBox / coach mark — only docs/plans hits. The plan itself said "no doc change".

### F7 · NO-RULE · block-add-exercise-header-plan: block-header plus-icon rule is in no doc
- Where the code does it: lib/features/routine/routine_setup_screen.dart:412 and lib/features/session/workout_session_list_view.dart:184 — plus `IconButton` in the block header, `tooltip: 'Add exercise to block'`.
- What a user would see: each exercise block's header carries a compact plus button that opens the add-exercise flow; there is no full-width add button at the block bottom.
- Guard: test/screen_widget_test.dart:1186 ('block header plus icon triggers add-exercise flow'), test/pr6_routine_session_entry_navigation_test.dart:625.
- Unsure: nothing. Searched docs/ for `block header` / `add exercise to block` / `plus icon` — only docs/plans hits.

### F8 · NO-RULE · exercise-library-info-icon-removal-plan: library-vs-picker info-icon rule is in no doc
- Where the code does it: lib/features/exercise/exercise_picker_screen.dart:669-671 — info button (`exercise_row_details_button`) kept in the picker rows; the library rows have none.
- What a user would see: exercise rows in the picker show a details (info) button; the same rows in the library do not.
- Guard: test/pr8_exercise_library_test.dart:681-686 (asserts the library has no info icon).
- Unsure: nothing. Searched docs/ for the library/picker info-icon distinction — only docs/plans hits.

### F9 · NO-RULE · food-library-row-layout-plan: grams-vs-count amount semantics are in no doc
- Where the code does it: lib/features/nutrition/widgets/log_food_row.dart:53, :228-234 — for gram-type foods the amount field is the pure gram amount; for count-type foods it is a multiplier of the serving size.
- What a user would see: typing 2 against a count-type food logs two servings; typing 150 against a gram-type food logs 150 g. The row's unit label under the textbox reflects which of the two it is.
- Guard: LogFoodRow tests exist in test/nutrition_test.dart, test/nutrition_log_from_library_test.dart, test/screen_widget_test.dart (files seen; the specific amount-semantics assertions not individually opened).
- Unsure: whether one of those tests pins the grams-pure/count-multiplier semantics by name. docs/widget_catalog/nutrition_widgets.md:52-67 (LogFoodRow) describes the row but does not state the amount semantics; docs/db_integration.md:365 and docs/data_models.md:364-367 cover the data layer, not the row UI.

### F10 · NO-RULE · food-log-thumbnail-contrast-plan: inset ring + unlogged dim rule is in no doc
- Where the code does it: lib/features/nutrition/widgets/log_food_row.dart — 48×48 outer thumbnail with 32×32 `FoodThumbnail` inset and an `AnimatedOpacity` dim overlay for unlogged rows.
- What a user would see: logged foods' thumbnails sit inside a visible ring; unlogged rows' thumbnails are dimmed.
- Guard: test/nutrition_test.dart group 'LogFoodRow thumbnail contrast' (~line 3415; asserts 48×48 outer, 32×32 inner, AnimatedOpacity present).
- Unsure: nothing. The doc's LogFoodRow section says only "selected and unselected states are visually distinct without relying on colour alone".

### F11 · NO-RULE · home-header-rework-plan (+ hub-sheet-content-anchor-top-plan): Hub sheet hidden-at-rest and top-anchored content are in no doc
- Where the code does it: lib/features/home/home_screen.dart:124 `_minSheetExtent = 0.0`; :976-980 `minChildSize: _minSheetExtent`, `initialChildSize: _minSheetExtent`, `snapSizes: [_minSheetExtent, _maxSheetExtent]`; :1243-1252 comment pins grid padding to zero "keeps the content anchored to the top of the sheet".
- What a user would see: the Hub sheet is fully hidden when the home screen is at rest; only the top-left logo opens it, and the HUB header plus maintenance grid sit directly under the drag handle with no floating band.
- Guard: test/home_logo_hub_open_test.dart (logo opens sheet; handle not visible at rest).
- Unsure: nothing. Searched docs/ for `minChildSize` / `hidden at rest` / `peek` — only docs/plans hits.

### F12 · NO-RULE · keyboard-dismissal-and-capitalization-plan: app-wide tap-outside dismissal and capitalization defaults are in no doc
- Where the code does it: lib/app.dart — MaterialApp `builder` wraps the tree in a translucent-tap `GestureDetector` that unfocuses (`FocusManager.instance.primaryFocus?.unfocus()`); per-field `textCapitalization` on name/prose fields.
- What a user would see: tapping empty space dismisses any keyboard app-wide; name fields capitalise each word, note fields sentence-case, numeric fields not at all.
- Guard: test/keyboard_dismissal_test.dart, test/numeric_done_bar_test.dart, test/capitalization_defaults_test.dart.
- Unsure: nothing. The numeric "Done" bar IS documented (docs/widget_catalog/layout_and_inputs.md:145) and food-form word-case is documented (docs/widget_catalog/nutrition_widgets.md:96); the app-wide dismissal and the general words/sentences/none defaults are not.

## Checked, nothing to report
2026-07-27-03-pr3-isolated-ui-corrections (nutrition_target_button documented + tested; coach-mark part → F6), 2026-08-13-theme-contrast-remediation (palette contract test + design_system.md), add-exercise-modality-bug (ModalityPickerDialog documented + tested; "General" fallback later removed by remove-general-modality), add-planned-session-theme (theme-token tests exist), confirmation-dialog-consolidation (design_system.md:354-366 + guard tests), daily-nutrition-macro-chart (design_system.md:130 + home_screen.md + test), emphasis-tier-color-contract (design_system.md:98-124 + emphasis_tier_contract_test.dart; frozen constants gone), food-form-decimals-and-autofocus (nutrition_widgets.md:100,117-154), green-themes-bakeoff (jadeSentinel pruned from enum; Malachite Core covered by palette contract test), header-standardization (OmniBackHeader documented + 21 screens + test), home-main-tile-shadow-parity (resting-shadow rule superseded by home-tile-tier-restyle; test/widgets/energy_tile_test.dart:106 asserts empty resting boxShadow, active glow preserved), home-tile-fixes (pulsing-dot semantics documented in home_screen.md + energy_tile_test.dart), home-tile-responsive-artwork (documented in home_screen.md EnergyTile section), home-tile-tier-restyle (two-tier rule documented in home_screen.md), hub-bottom-sheet-single-step-open (two-snap rule survives; peek replaced by hidden-at-rest per home-header-rework), hub-sheet-gap-and-logo-clip (logo rule documented in feature_primitives.md HomeLogoButton; gap rule superseded by hub-sheet-content-anchor-top), hub-sheet-navigation (navigation_contract.md:5-7 + navigation_and_screens.md:5), in-session-pr-toast (session_widgets.md:143 PRToast + test/in_session_pr_toast_test.dart), measurement-history-chart-sheet (≤10-entry cap superseded by unify-chart-scrolling-popup D-7 full history), modality-aware-create-exercise (docs/create_new_exercise.md:34-46 + test/interaction_flow_test.dart 'ExerciseEditorScreen interactions' group).
