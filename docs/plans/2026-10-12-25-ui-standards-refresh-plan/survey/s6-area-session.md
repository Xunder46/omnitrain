# S6 · Area sheet · workout session, exercise, routine (read-only)

Scout sheet. All quotes verbatim from files read this run (2026-10-12).
Docs read: modality_based_exercise_ui.md, exercise_info_and_notes.md, create_new_exercise.md,
exercise_ranking.md, my_routines.md, rest_tracking.md, rolling_sessions.md, session_summary.md,
widget_catalog/session_widgets.md.
Code read: lib/features/{session,exercise,routine}, lib/widgets/session, lib/widgets/pickers.

## Section 1 · STALE-DOC / CONFLICT

Names checked against `lib/`: ~40 (screens, widgets, keys, tokens, doc-quoted identifiers). Mismatches below.

### F1 · STALE-DOC · Picker "Recommended / Other" partitioning exists again
- Where the doc says it: docs/exercise_ranking.md:47-49 — "Previously the dialog partitioned results into 'Recommended' (exercises supporting the modality's primary metric) and 'Other exercises'; that partitioning has been removed and the list is displayed in the repository's sorted order."
- Where the code does it: lib/features/exercise/exercise_picker_screen.dart:486-505 —
  ```
  if (_recommendedExercises.isNotEmpty) {
    listItems.add((headerTitle: 'Recommended', exercise: null));
  ...
  if (_otherExercises.isNotEmpty) {
    listItems.add((headerTitle: 'Other', exercise: null));
  ```
  and `_partitionExercises` at :140-165 splits on `RECOMMENDED_SCORE_THRESHOLD` (lib/core/constants/modality_config.dart:13 `const double RECOMMENDED_SCORE_THRESHOLD = 50.0;`).
- What a user would see: with a session modality set, the picker shows "Recommended" and "Other" section headers; the doc claims the list is one flat sorted list.
- Guard: none found: searched test/ for RECOMMENDED_SCORE_THRESHOLD, "Recommended", "Other" (not run — test dir not searched this run; see Unsure).
- Unsure: whether a test pins the partitioning (test/ not searched).

### F2 · STALE-DOC · ModalityPickerDialog has no "General" option and shows four modalities
- Where the doc says it: docs/widget_catalog/session_widgets.md ("ModalityPickerDialog") — "Shows all five modalities plus a 'General' option" and "Returns `(true, String? modality)` … 'General': `(true, null)`".
- Where the code does it: lib/widgets/pickers/modality_picker_dialog.dart:70-77 —
  ```
  final modalities = [
    ('cardio_endurance', 'Cardio', Icons.favorite),
    ('resistance_lifting', 'Resistance', Icons.fitness_center),
    ('sports', 'Sports', Icons.sports_basketball),
    ('isometric_stretching', 'Isometric', Icons.accessibility),
  ];
  ```
  No null/"General" tuple; Cancel pops with null (`Navigator.pop(context)`, :57).
- What a user would see: the dialog lists four modalities and a Cancel button; there is no "General" choice, so a Free Training add cannot explicitly pick "no modality" from this dialog.
- Guard: none found: searched lib/ for `showModalityPickerDialog` callers destructuring `(true, null)`; routine_setup_screen.dart:783-796 returns early when `pickedModality == null`, consistent with no General option.
- Unsure: whether any caller relies on a General return (searched lib/features + lib/widgets only).

### F3 · STALE-DOC · List view has no FAB
- Where the doc says it: docs/modality_based_exercise_ui.md ("List View") — "FAB button to add new exercise".
- Where the code does it: lib/features/session/workout_session_list_view.dart:278 `Widget _buildAddExerciseAndBlockBar(ThemeData theme, {String? segmentId})` — an inline bar rendered at the end of the list and centred in the empty state (:362, :382, :463, :506, :528). `grep FloatingActionButton` over lib/features matches only a comment in my_routines_screen.dart:68.
- What a user would see: adding an exercise is a bar/button inside the scroll content, not a floating action button.
- Guard: none found: searched lib/features for FloatingActionButton.
- Unsure: nothing.

### F4 · STALE-DOC · InlineMetricEditor is tap-only, not drag-responsive; visual values in doc
- Where the doc says it: docs/modality_based_exercise_ui.md ("InlineMetricEditor") — "Drag-responsive (value updates during drag, not just on release)", "72pt display value", "Unit label in small caps below (12pt, 50% opacity)".
- Where the code does it: lib/widgets/session/inline_metric_editor.dart:15-19 — "When [isReadOnly] is true: no tap or drag affordances are shown."; the only gestures are `onTap` (:218, :234-235); no `onPanUpdate`/`Listener` drag path exists in the file. The widget catalog (session_widgets.md, "InlineMetricEditor") already says "Number tap is the sole value-change mechanism" — the two docs disagree with each other and modality_based_exercise_ui.md is the stale one. The 72pt/12pt figures are also visual values a doc may not hold (documentation_standard.md).
- What a user would see: values change by tapping the number and using the popup/dialog; dragging does nothing.
- Guard: none found: searched lib/widgets/session/inline_metric_editor.dart for drag handlers.
- Unsure: nothing.

### F5 · STALE-DOC · Rolling-session duration comment quoted in the doc is not in the code
- Where the doc says it: docs/rolling_sessions.md ("UI Changes When isRolling Is True") — quotes inline code `// Duration intentionally omitted for rolling sessions (Task 5).`
- Where the code does it: suppression exists but with different code: lib/features/session/session_summary_screen.dart:795 `if (!isRolling) ...[`; lib/features/session/workout_session_list_view.dart:62 `if (widget.workoutState.isRollingSession) {`. `grep "Duration intentionally omitted"` over lib/features: no match.
- What a user would see: behaviour matches (no duration for rolling); only the quoted source line is gone.
- Guard: test/header_standardization_test.dart S-008 is cited by session_summary.md (not re-run this run).
- Unsure: nothing.

### F6 · STALE-DOC · Summary "Header" row: date + modality badge moved into the first card
- Where the doc says it: docs/session_summary.md ("Screen Layout" table) — "Header | Session title, formatted start date and time, modality badge".
- Where the code does it: lib/features/session/session_summary_screen.dart:673-675 — `appBar: OmniBackHeader(title: title ...)` (title only); :756-765 —
  ```
  return OmniCardHeader(
    key: const Key('omni_session_info_header'),
    title: _formatDateTime(startedAt),
    actions: [_buildModalityChip(theme)],
  );
  ```
  with the in-code comment ":768-771 — the date and modality chip live in [_buildSessionInfoHeader] above this card" ("per the Phase 2.2 refinement — chip belongs to the first card, not the page-level header").
- What a user would see: the top app bar shows only the session title; the date and modality chip sit on the first card.
- Guard: none found: searched test/ (not searched this run).
- Unsure: whether a test pins the header split.

### F7 · STALE-DOC (minor) · Info-sheet empty-state condition
- Where the doc says it: docs/exercise_info_and_notes.md — 'empty state: "No information available yet" when no image/steps exist'.
- Where the code does it: lib/features/session/workout_session_global_timer.dart:283-285 — `if (!hasImage && !hasSteps && !isBilateral)` — a bilateral exercise with no image/steps shows the bilateral LOGGING NOTE instead of the empty state.
- What a user would see: a bilateral exercise with no image or steps shows the logging note, never the "No information available yet" text.
- Guard: none found: searched lib/ for "No information available yet" (only this site).
- Unsure: nothing.

## Section 2 · NO-RULE / INCONSISTENT

### F8 · BREAKS-RULE · Raw colours in ModalityPickerDialog and coach-mark overlay
- Where the doc says it: docs/global_conventions.md:10 — "Theme tokens only | Colors, accents, surfaces, borders, and other visual styling must come from `OmniTheme` tokens or `ThemeData.colorScheme` … Never hardcode colors or bypass the selected theme."
- Where the code does it: lib/widgets/pickers/modality_picker_dialog.dart:22 `color: Color(0xFF1a1a1a),` :32 `color: Colors.white,` :110 `color: Colors.white,`; lib/features/session/workout_session_global_timer.dart:694/:744 `const Color(0xBF000000)`, :808 `const Color(0xFF1A1A2E)`, :822 `Colors.white.withOpacity(0.9)`, :834 `Colors.black87`; lib/features/session/session_summary_screen.dart:555 and :1102 `Colors.white.withOpacity(0.06)`. (workout_session_global_timer.dart:190 `Colors.black.withOpacity(0.7)` is a scrim gradient over the info-sheet hero image.)
- What a user would see: the modality dialog and the one-time coach marks keep a fixed dark look regardless of the active theme; the summary's card borders/dividers use a white-based hairline that is not a theme token.
- Guard: none found: searched test/ (not searched this run).
- Unsure: whether a lint or test scans for raw colours.

### F9 · NO-RULE · Empty states are per-screen bespoke, three different shapes
- Where the code does it:
  - lib/features/routine/my_routines_screen.dart:126-160 — circle icon + "No Routines Yet" + "Create your first routine to get started".
  - lib/features/exercise/exercise_picker_screen.dart:436-452 — icon + "No exercises found" + "Try adjusting your filters".
  - lib/features/exercise/exercise_library_screen.dart:307 `class _EmptyState extends StatelessWidget` (private, library-only).
  - lib/features/session/session_overview_screen.dart:163-183 — icon + "No exercises yet" + "Add your first exercise to get started".
  - lib/features/session/workout_session_list_view.dart:425-440 — the session empty state is not text at all: it centres the Add-Exercise-and-Block bar (PR 6 / S-003 + S-004 comment at :417-421).
- What a user would see: every surface invents its own empty-state composition; no doc states a shared empty-state rule or component.
- Guard: none found: searched lib/widgets for a shared EmptyState widget (only the private `_EmptyState` in the library screen).
- Unsure: nothing.

### F10 · NO-RULE · Unsaved-changes guards exist in three surfaces with near-identical copy, written nowhere as an area rule
- Where the code does it:
  - lib/features/session/workout_session_edit_mode.dart:96-113 — `ConfirmationDialog.showUnsavedChanges(title: 'Unsaved changes', body: 'You have unsaved edits. Save them or discard to return to the summary.')`.
  - lib/features/routine/routine_setup_screen.dart:1052-1060 — same dialog, body '…return to the routines list.'; single exit path `_attemptExit` (:1010-1050) used by header back, system back and bottom Cancel (:1063).
  - lib/features/session/workout_session_screen.dart:1316-1345 (delete-current-set), :1352 (delete logged entry), :1680 (delete block), workout_session_list_view.dart:896 (discard session), workout_session_finish.dart:21 (finish), session_overview_screen.dart:271, session_summary_screen.dart:340 (discard), my_routines_screen.dart:213/:305 — all `ConfirmationDialog.showTwoChoice` with `isDestructive` for destructive paths.
- What a user would see: leaving an editor with unsaved work always asks "Unsaved changes" with Keep editing / Discard / Save; every destructive action confirms through the same dialog component. Consistent, but no doc in this area states it as a rule (my_routines.md describes the routine case only).
- Guard: none found for a cross-area rule; my_routines.md cites test/pr6_routine_session_entry_navigation_test.dart for delete-history only.
- Unsure: nothing.

### F11 · NO-RULE · Live session persists every change; edit mode buffers until Save — two saving models, no written rule
- Where the code does it: docs/modality_based_exercise_ui.md does state "Immediate Persistence" for live mode; but the edit-mode buffer rule (lib/features/session/workout_session_screen.dart:1394-1400 "edit mode: buffer changes locally without persisting… saved only when the user clicks 'Save'", buffer at :189-191, flush in workout_session_edit_mode.dart:168+) and the summary note's debounced save (session_summary_screen.dart:248-249 `Timer(const Duration(milliseconds: 600)…)`) vs the exercise note sheet's 500 ms debounce (workout_session_global_timer.dart:432) are nowhere stated as rules. Two debounces for the same job differ (600 ms vs 500 ms).
- What a user would see: in a live workout nothing is ever "unsaved"; in Edit Session changes are held until Save Changes; notes save on a quiet pause whose length differs between the two note fields.
- Guard: none found: searched lib/ for a shared debounce constant (none).
- Unsure: nothing.

### F12 · NO-RULE · Keyboard behaviour: capitalisation per field, no global rule
- Where the code does it: `textCapitalization: TextCapitalization.words` on routine name (routine_setup_screen.dart:238), exercise name (exercise_editor_screen.dart:317), summary note (:577); `TextCapitalization.sentences` on routine description, block name (:858), summary note card (:1201), exercise note sheet (workout_session_global_timer.dart:505); `TextCapitalization.none` on both search fields (exercise_picker_screen.dart:243, exercise_library_screen.dart:110). Search fields use a clear (✕) suffix button; no field shows select-on-focus.
- What a user would see: names capitalise word-wise, prose sentence-wise, searches not at all — consistent per field type but written nowhere.
- Guard: none found.
- Unsure: nothing.

### F13 · NO-RULE · Errors: inline field errors on forms, SnackBar for action failures, full-screen retry for load failure
- Where the code does it: editor validation errors rendered inline (`_modalityError`/`_nameError`/`_capabilityError`, exercise_editor_screen.dart:296-303, :404-410); action failures as SnackBar (my_routines_screen.dart:262/:276, routine_setup_screen.dart:995, workout_session_screen.dart:1559/:1577, workout_session_finish.dart:101); session load failure as a full-screen error with Retry (workout_session_list_view.dart:686-722).
- What a user would see: three error channels with no doc saying which is used when.
- Guard: none found.
- Unsure: nothing.

### F14 · NO-RULE · Locked/unavailable features
- Where the code does it: disabled controls with tooltips rather than explanations — editor modality chips `onSelected: _isModalityReadOnly ? null : …` (exercise_editor_screen.dart:287-290); legacy chips disabled with a `disabledColor` and a 'Legacy capability' error text (:401-419); detail header info/note buttons disabled when `exercise == null` (workout_session_detail_view.dart:44-46); read-only timer values via `isReadOnly: true` (session_widgets.md; inline_metric_editor.dart:115). No "locked feature" explanation pattern exists in this area.
- What a user would see: unavailable controls are simply inert; nothing explains why beyond tooltips.
- Guard: none found.
- Unsure: nothing.

### F15 · NOTICED (fact, not a finding kind) · SessionOverviewScreen is unreachable
- lib/features/session/session_overview_screen.dart:19 defines `SessionOverviewScreen`; `grep "SessionOverviewScreen"` over lib/ matches only its own file. No screen pushes it. It still appears in session_widgets.md as a pusher of ExercisePickerScreen ("Pushed from `SessionOverviewScreen`, …").
- NOTICED: lib/features/session/session_overview_screen.dart:19 — dead screen; widget catalog names it as a live entry point.

## Section 3 · Pattern matrix

| Screen (file) | P1 top bar | P2 card header | P3 empty state | P4 locked | P5 confirm | P6 unsaved guard | P7 entry | P8 bottom action | P9 sheets/modals | P10 tokens | P11 a11y | P12 charts |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| WorkoutSessionScreen list (workout_session_list_view.dart) | custom `_buildHeader` (:977) — IconButton + title, not OmniBackHeader | custom block card | Add-Exercise bar centred (:425-440) | none | ConfirmationDialog.showTwoChoice (:896) | edit-mode only (edit_mode.dart:102) | none (no text fields) | OmniBottomCTA 'Finish Workout'/'Save Changes' (:386-393) | none | tokens; no raw colour seen in this file | ? | none |
| WorkoutSessionScreen detail (workout_session_detail_view.dart) | same custom `_buildHeader` + info/note IconButtons (:20-100) | none | 'No exercises yet' + 'Add First Exercise' FilledButton (list_view:747-763) | buttons disabled when exercise null (:44) | delete-set / remove-exercise confirms (screen:1316/:1352) | edit-mode only | InlineMetricEditor tap→popup/dialog; duration dialog | set-controls row (Previous / centre / Next, :832-878) | info + note bottom sheets (global_timer:126/:304) | tokens | header action min sizes from OmniTheme (:47-50) | none |
| SessionSummaryScreen (session_summary_screen.dart) | OmniBackHeader + PopupMenuButton (:673-694) | OmniCardHeader ×3 (:717/:761/:888) | n/a (always has data) | none | discard confirm (:340) | none (note autosaves) | note TextField, sentences (:1201) | OmniBottomCTA 'Done' (:731) | save-as-routine sheet (:481), EffortRatingSheet | mostly tokens; raw `Colors.white.withOpacity(0.06)` :555/:1102 | ? | calendar grid (custom GridView, :1256) |
| SessionOverviewScreen (session_overview_screen.dart) | OmniBackHeader (:152) | none | icon + 'No exercises yet' (:163-183) | none | remove-exercise confirm (:271) | none | none | Row of buttons (:300+, not OmniBottomCTA) | none | tokens | ? | none |
| MyRoutinesScreen (my_routines_screen.dart) | OmniBackHeader (:64) | none | circle icon + 'No Routines Yet' (:126-160) | none | start-over-session + delete confirms (:213/:305) | n/a (list screen) | none | OmniBottomCTA '+ New Routine' (:74) | none | tokens | ? | none |
| RoutineSetupScreen list (routine_setup_screen.dart) | OmniBackHeader + delete action (:173-190) | custom segment cards | n/a (name field always present) | none | remove-exercise (:755), delete-block (:893), delete-routine (:1002 area) | `_attemptExit` showUnsavedChanges (:1052) | name/description TextFields, words/sentences (:238/:258) | custom Cancel/Save row in gradient stack (:530-586), not OmniBottomCTA | Edit Block dialog (:826), ModalityPickerDialog (:783) | tokens | FittedBox scaleDown on bottom buttons (:570/:583) | none |
| RoutineSetupScreen detail (:605) | OmniBackHeader with 'Exercise n / m' subtitle (:626-631) | none | falls back to list when no efforts (:607-609) | none | same as above | same | InlineMetricEditor + duration dialog | same bottom row | same | tokens | ? | none |
| ExercisePickerScreen (exercise_picker_screen.dart) | OmniBackHeader (:192) | custom `_buildSectionHeader` 'Recommended'/'Other' (:520) | 'No exercises found' + 'Try adjusting your filters' (:436-452) | none | none | none | search TextField, none-capitalisation, clear button (:243) | none (selection pops) | none (full-screen push) | tokens | ListTile titleAlignment.top comment (:546-553) | none |
| ExerciseEditorScreen (exercise_editor_screen.dart) | OmniBackHeader (:257-258) | none | loading spinner (:263) | modality locked in edit (`_isModalityReadOnly`), legacy chips disabled | none (save validates instead) | none (save/cancel without guard) | name words / description sentences (:317/:330) | OmniBottomCTA 'Save exercise' (:479) | none | tokens | ? | none |
| ExerciseLibraryScreen (exercise_library_screen.dart) | OmniBackHeader (:102) | none | private `_EmptyState` (:307) | none | none | none | search TextField + custom-only SwitchListTile (:105/:140) | none | none | tokens | ? | none |
| ExerciseLibraryDetailScreen (exercise_library_detail_screen.dart) | OmniBackHeader 'Custom/Built-in Exercise' (:159) | none | n/a | none | remove confirm via ConfirmationDialog.twoChoice (:370) | none | rename dialog (:283) | in-scroll `_ManagementActionBar` (:200), not bottom-anchored | rename/remove dialogs | tokens | ? | none |
| ExerciseDetailViewScreen (exercise_detail_view_screen.dart) | OmniBackHeader (:113) | none | n/a | none | none | none | none | `_ExerciseDetailAddBar` bottom bar (:324, via bottomNavigationBar :130) | none | tokens | ? | none |
| ExerciseDetailScreen (exercise_detail_screen.dart) | compat shim → WorkoutSessionScreen (:12-45) | — | — | — | — | — | — | — | — | — | — | — |

Cells marked `?`: text-scale overflow / semantics labels (P11) were not audited per screen this run — I checked only the two spots quoted (header action constraints, FittedBox, ListTile alignment). P12: no chart widget is used anywhere in this area (searched lib/features/{session,exercise,routine} for chart imports — none), so "none" is checked, not guessed.

## Open questions for the governor
- test/ was not searched for guards (time box); every "Guard: none found" line means lib/ only.
- `.work/crew/2026-10-12-25-ui-standards/` did not exist; this file was created with the create tool (no shell available to mkdir).
