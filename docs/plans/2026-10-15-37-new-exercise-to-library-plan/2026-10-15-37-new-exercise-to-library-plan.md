# Plan 37 — Move "New Exercise" from the exercise picker to the Exercise Library

Status: SEEDED by the lead. Base commit `cbc7a8f` (branch `claude_develop`, tree clean at seed time). Not authorised to commit: the owner commits; never push.
Owner request (2026-10-15): "+ New Exercise" belongs on the Exercise Library screen, not on the exercise picker; it frees room on the picker. Owner leaves the how to the lead.

## Goal and acceptance

- A1. The exercise picker (`Select Exercise`) no longer shows the full-width `New Exercise` button or the gap under it: the search field is the first thing on the screen. Everything else on the picker is unchanged (search, Discipline / Muscle filters, Recommended and Others lists, row tap picks, info control opens details).
- A2. The Exercise Library screen has a way to create an exercise: a `+` icon button in the screen header (`OmniBackHeader.actions`), tooltip `New Exercise`, key `exercise_library_new_button`. Tapping it opens the same editor (`ExerciseEditorScreen`) in create mode. No session modality is prefilled (the library has no session): the user picks the modality first, as the modality-first form already requires.
- A3. When the editor returns a created exercise, the library does what the picker did: reloads the list, forgets that exercise's cached muscle links, puts the new exercise's name in the search field so the row is visible. Cancelling (back) changes nothing.
- A4. The editor itself, its parameters (`contextModality` stays as an optional parameter, now with no caller), edit mode from `ExerciseLibraryDetailScreen`, Copy and Remove are unchanged.
- A6 (owner, added 2026-10-15 mid-unit). When the picker's list is empty (a search or filters that match nothing), its `No exercises found` state also offers a `New Exercise` button (key `exercise_picker_new_button`, in `OmniEmptyState.action`). It opens the editor as the picker did before: modality prefilled from the session (`contextModality: widget.sessionModality`); on a created exercise the picker puts its name in the search field so it shows and can be tapped. Nothing else about the picker's empty state changes. With any result in the list the button is not shown.
- A5. No data-model, repository, state-class, wire or Swift change. `flutter analyze` not above the plan's baseline (record it at Phase 0 start: run it once, write the count in Progress); `flutter test` not below its current pass count minus the tests this plan removes (list them in Progress).

## Decision Ledger

- D-1 Placement (technical decision, precedent): header `+` action, the same slot Calendar / Stats / Routine setup use (`OmniBackHeader.actions`, `lib/widgets/layout/omni_back_header.dart:26-31`). It costs no list room in the library. Every `IconButton` carries a `tooltip:` (`test/ui_standards_contract_test.dart`). Colour: the header's existing action convention (read how `lib/features/calendar/calendar_screen.dart:93-` and `lib/features/stats/stats_screen.dart:256-` build theirs and copy it; no new colour literal).
- D-2 Picker: delete the `New Exercise` `SizedBox`/`OutlinedButton.icon` block and the `SizedBox(height: 16)` after it (`lib/features/exercise/exercise_picker_screen.dart:202-224`), the method `_openCreateExercise` (`:170-184`) and the import of `exercise_editor_screen.dart` (`:9`) if nothing else in the file uses it. `OmniNavigator` stays (used at `:692`). `sessionModality` stays (ranking).
- D-3 Library: add `_openCreateExercise` next to `_openManagementDetails` (`lib/features/exercise/exercise_library_screen.dart:289`): `OmniNavigator.push<Exercise>(context, (_) => ExerciseEditorScreen(workoutState: widget.workoutState))`; when the result is null return; else remove the exercise id from `_exerciseMuscleLinksCache`, set `_searchController.text = created.name` (the existing listener debounces into `setSearchText`), `await widget.exerciseLibraryState.reload()` and `_warmCache`. Guard every use of `context`/`setState` after an await with `mounted`. Add the import. Update the file's header comment (differences from the picker) to say the library is where exercises are created.
- D-4 SUPERSEDED by A6/D-6: the empty-search button now lives in the picker. Still not in this plan: reaching the library from inside a running session. The only route to the library stays the maintenance sheet tile.
- D-6 Phase P2 (picker only): restore the old `_openCreateExercise` (modality from `widget.sessionModality`, search text := created name, `_exerciseMuscleLinksCache.remove`, `await _searchExercises()`) and re-add the editor import; the empty branch becomes `OmniEmptyState(icon: Icons.search_off, title: 'No exercises found', hint: 'Try adjusting your filters', action: OutlinedButton.icon(key: const Key('exercise_picker_new_button'), onPressed: _openCreateExercise, icon: const Icon(Icons.add), label: const Text('New Exercise'), style: <same primary-coloured outline style the removed button had>))`.
- D-5 Tests are migrated, not loosened: the picker tests that asserted the button become guards that it is gone (see scenarios).

## Readers of what this plan changes

- `test/screen_widget_test.dart`: `:7397` `shows New Exercise button` (picker) — becomes the absence guard S-4101; `:7556` `New Exercise label is not wrapped in shrink-to-fit FittedBox` and `:7578` `New Exercise label type role is more prominent than dropdown value text` — both look for the picker's button text. The first is deleted; the second keeps its dropdown-value assertions (the `All` text size) and drops the `New Exercise` half (rename it to say what it still proves). `:3510` (`ExerciseEditorScreen` title) and `test/header_standardization_test.dart:389` are the editor's own title: untouched.
- `test/pr8_exercise_library_test.dart` group `ExerciseLibraryScreen` (`:392-`): add the new scenarios; `test/muscle_filter_picker_test.dart:510` builds `ExerciseLibraryScreen` — re-read, expect no change.
- Contract tests: `test/ui_standards_contract_test.dart` (tooltip, colour literals, header rules), `test/docs_indexing_contract_test.dart`, `test/navigation_contract_enforcement_test.dart` (the editor is pushed through `OmniNavigator`). Run them; a red one means fix the new code, never the allowlist.
- Docs: `docs/create_new_exercise.md` (Entry Points, `contextModality` sentence at `:21-23`), `docs/navigation_and_screens.md:190` (entry points), `docs/widget_catalog/session_widgets.md` (grep `New Exercise`), `docs/README.md` (grep), the library doc if one exists (`grep -rn "Exercise Library" docs/*.md`).

## Core scenarios (exact fixtures)

Fixture: Mock repository as `_freshRepo()` in `test/screen_widget_test.dart` for the picker; `_freshRepo()` / `_buildState(repo)` of `test/pr8_exercise_library_test.dart` for the library.

- S-4101 (picker, `test/screen_widget_test.dart`) `ExercisePickerScreen(workoutState)` at 800x1200: `find.text('New Exercise')` finds nothing and `find.byIcon(Icons.add)` finds nothing; the search field (`Search exercises...`) is the first child of the body column (its top is within 24 px of the header bottom). Fails today: the button is there.
- S-4102 (library, `test/pr8_exercise_library_test.dart`) `ExerciseLibraryScreen` shows `find.byKey(Key('exercise_library_new_button'))` once, with tooltip `New Exercise`. Fails today: no such key.
- S-4103 Tapping it pushes `ExerciseEditorScreen` in create mode (`find.byType(ExerciseEditorScreen)`; the header title reads `New Exercise`, not `Edit Exercise`) with no modality chip selected (the form's `MODALITY` section has none selected).
- S-4104 Saving a custom exercise named `Zercher Squat 4104` in that editor (choose a modality, a capability, a name, save): back on the library the search field reads `Zercher Squat 4104`, the list shows that row with the `Custom` marker (`exercise_row_custom_marker`), and `ExerciseLibraryState.exercises` contains it. If the full save flow is too heavy for a widget test under FakeAsync, drive the editor with a real save in a plain `test()` at the state layer plus a widget test that pops the editor route with an `Exercise` created through `WorkoutState`: the architect picks and states which.
- S-4105 Backing out of the editor without saving leaves the search field empty and the list as before.
- S-4106 Guard that the editor from the library does not pass a session modality: `ExerciseEditorScreen.contextModality` is null on the pushed widget.
- S-4108 (picker) search `zzzznotanexercise`: `exercise_picker_new_button` shown once; with the default list (results) it is absent (S-4101 stays green: no `New Exercise` text when exercises are listed).
- S-4109 Tapping it opens `ExerciseEditorScreen` whose `contextModality` equals the picker's `sessionModality` (picker built with a modality).
- S-4110 Saving a new exercise there (as S-4104 does) returns to the picker with the search field reading its name and the row listed.
- S-4107 Existing guards stay green: `ExerciseLibraryDetailScreen` `S-9: Edit opens the full editor and saves through it`; picker row-tap returns the exercise; picker with `sessionModality` still shows Recommended / Others.

Why they fail without the change: S-4101 the button exists; S-4102-S-4106 there is no create path in the library.

## Phase outline

- Phase 0 (lead): baselines (`flutter analyze` count; the full-suite pass count from the last run if cheap, otherwise run it once before Phase P1 starts).
- Phase P1 — `crew-builder-app`; scope `lib/features/exercise/exercise_picker_screen.dart,lib/features/exercise/exercise_library_screen.dart,test/screen_widget_test.dart,test/pr8_exercise_library_test.dart`: D-2, D-3, D-1 and S-4101..S-4107, red first. Read the callers named in D-1 for the action's look.
- Phase P2 — `crew-builder-app`; scope `lib/features/exercise/exercise_picker_screen.dart,test/screen_widget_test.dart`: D-6, S-4108..S-4110, red first.
- Phase D — `crew-docs-keeper`; scope `docs/create_new_exercise.md,docs/navigation_and_screens.md,docs/widget_catalog/session_widgets.md,docs/README.md` (+ any other doc the grep finds) + the plan's evidence file. Runs after P1 verified.
- After D: prover (guards S-4101..S-4106), lead mutations, reviewer. The lead looks at the screens on the iOS simulator at phone width (picker: no gap above search; library: header `+`; the editor opening from it; save and return).

## Code pointers (current lines)

- `lib/features/exercise/exercise_picker_screen.dart`: imports `:1-13` (editor import `:9`), `_openCreateExercise :170-184`, body column `:196-224` (button block `:202-223`, spacer `:224`), search field `:227`, details push `:692`.
- `lib/features/exercise/exercise_library_screen.dart`: header `:104` (`appBar: const OmniBackHeader(title: 'Exercise Library')` — `const` must go once `actions` carries a closure), `_openManagementDetails :289-302`, `_warmCache :304`, cache map `:47`, search listener `:52,77`.
- `lib/features/exercise/exercise_editor_screen.dart`: `contextModality :18,24,75`, title `:398`, pops the created `Exercise`.
- `lib/features/exercise/exercise_library_detail_screen.dart:118` (edit path, untouched).

## Progress / Assumption Log / Feedback / Open questions

### Progress
- Seeded 2026-10-15. Baselines: analyze 182; full suite before P1 not run (base), after P1 `+4745 ~1` (lead-run).
- P1 built by crew-builder-app (12m 37s), lead-verified: diff clean, analyze 182, full suite `+4745 ~1` all passed.
- 2026-10-15: owner asked for the empty-search button (A6) mid-unit; Phase P2 added (picker + screen_widget_test only).

### Assumption Log
- (none yet)

### Feedback
- (none yet)

### Open questions
- (none; D-4 is an owner follow-up, reported not built)
