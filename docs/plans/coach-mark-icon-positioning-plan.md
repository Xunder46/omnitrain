# Feature: Coach-mark glow anchor alignment with icon glyph

## Overview
The first-time coach-mark overlay on the exercise-detail screen (`WorkoutSessionScreen` detail mode) points at the info (`Icons.info_outline`) and notes (`Icons.edit_note`) header icons. The pulsing glow's centre currently anchors to the wrapping `SizedBox` that contains the `IconButton`, not to the visible icon glyph. Because `IconButton` lays out its child inside an internal `Padding(...)/SizedBox(30×30)/Align(center)` chain, the inner glyph does not sit at the geometric centre of the IconButton — the asymmetric user-supplied `padding` (`EdgeInsets.fromLTRB(0,0,5,0)` for info, `EdgeInsets.fromLTRB(5,0,0,0)` for notes) pushes the 30×30 glyph box to one corner of the 44×44 IconButton, so the glow ring is offset from the icon by several pixels. Re-anchor the coach mark on the actual `Icon` widget so its centre coincides with the visual icon glyph.

## Requirements
- Coach-mark glow centre coincides with the visual icon glyph for **both** the info icon and the notes icon.
- Existing tests that search by `const Key('exercise-info-button')` and `const Key('exercise-note-button')` keep passing unchanged (those keys stay on the `IconButton`).
- Internal `GlobalKey _infoIconKey` / `GlobalKey _notesIconKey` continue to be used by `_showExerciseCoachMark`; only their placement changes.
- No new state, no schema change, no repository change, no doc change.

## Acceptance Criteria
- [ ] `flutter analyze` produces zero new errors.
- [ ] `flutter test test/exercise_notes_sheet_test.dart` still passes.
- [ ] `flutter test test/screen_widget_test.dart` still passes.
- [ ] A new interaction test asserts the coach-mark overlay's glow centre lies within 2 px of the icon glyph's visual centre for both info and notes icons.

## Scenarios

> TRIVIAL feature — scenario register omitted; covered by acceptance criteria.

## Iteration 1

### DB Changes
None.

### Backend Changes
None. (`shouldShowExerciseInfoHint` / `markExerciseInfoHintSeen` etc. in `lib/state/workout/exercise_library.dart` are untouched.)

### Frontend Changes
`lib/features/session/workout_session_detail_view.dart` — in `_buildExerciseHeaderActions`:

- Move `key: _infoIconKey` off the outer wrapping `SizedBox` and onto the `Icon` widget (inside the `IconButton`'s `icon:` argument). The outer `SizedBox` wrapper is no longer needed for the key, but keeping a `SizedBox` shrink-wrapping the `IconButton` is harmless and avoids touching the test-facing layout — drop the key from it but keep the wrapper.
- Same change for the notes icon: move `key: _notesIconKey` off the outer `SizedBox` wrapper (still kept) onto the inner `Icon` widget.
- Keep `key: const Key('exercise-info-button')` and `key: const Key('exercise-note-button')` on the `IconButton`s — they are referenced by existing tests.

### Implementation Steps
1. [ ] Edit `_buildExerciseHeaderActions` to move `_infoIconKey`/`_notesIconKey` onto `Icon` widgets.
2. [ ] Run `flutter analyze`.
3. [ ] Run targeted `flutter test` for affected test files.
4. [ ] Run full `flutter test`.

### Files Affected
- `lib/features/session/workout_session_detail_view.dart`

## Progress
- [x] Step 1: move GlobalKeys onto Icon widgets
- [x] Step 2: `flutter analyze` — no new warnings
- [x] Step 3: targeted tests green (2/2 positioning tests pass)
- [x] Step 4: full test suite green (222 screen_widget tests + 9 notes/info-sheet tests + 39 in_session_pr tests + 31 catalog_refresh tests all pass)

## Phase 1 Complete ✓
## Phase 2 Complete ✓
## Phase 3 Complete ✓

## Feedback
[No feedback yet]_dev/