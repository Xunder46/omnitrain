# Feature: Fix Failing Unit Tests (9 failures)

## Overview
9 unit tests are failing across 4 test files. Root cause investigation identified two distinct causes.

## Root Cause 1 — TEMP debug line in `initState` (8 tests)

**File:** `lib/features/session/workout_session_screen.dart`, line 141

```dart
// TEMP: reset coach mark flags for testing — remove when done
unawaited(widget.workoutState.resetExerciseHintsForTesting());
```

This line in `initState()` unconditionally resets the `_exerciseInfoHintSeen` and `_exerciseNotesHintSeen` flags to `false` and overwrites the persisted repository values. As a result:

1. `exercise_notes_sheet_test.dart` seeds the prefs as `true` to prevent the coach overlay — but the `resetExerciseHintsForTesting()` call overwrites those seeds back to `false` immediately when the widget mounts.
2. Any test that navigates to the exercise detail view then gets the `_ExerciseCoachMarkOverlay` inserted, which uses `GestureDetector(behavior: HitTestBehavior.opaque)` as a full-screen backdrop. This absorbs **all pointer events**, making every button in the session screen unreachable by `tester.tap()`.

**Affected tests (8):**
- `exercise_notes_sheet_test.dart`: "Exercise notes indicator updates after save and clear"
- `unsaved_changes_dialog_test.dart`: "Unsaved dialog close icon dismisses and keeps editing"
- `unsaved_changes_dialog_test.dart`: "Unsaved dialog discard rolls back structural changes"
- `unsaved_changes_dialog_test.dart`: "Unsaved dialog save keeps structural changes"
- `unsaved_changes_dialog_test.dart`: "Unsaved dialog renders without overflow in constrained width"
- `widget_test.dart`: "Resistance logs create deterministic rest transitions"
- `widget_test.dart`: "Resistance shows Rest overlay after logging set"
- `widget_test.dart`: "Resistance rest only appears after Log Set, not just from entering reps"

**Fix:** Remove the two-line TEMP block (comment + `unawaited(...)` call) from `initState`.

---

## Root Cause 2 — Test uses `editMode: true` but expects add-button only shown in non-edit mode (1 test)

**File:** `test/interaction_flow_test.dart`, line 195

The test `'shows add exercise icon button when session is empty'` opens `WorkoutSessionScreen` with `editMode: true` and then asserts `find.byIcon(Icons.add)` finds widgets.

In `_buildStandardSessionListView`, the `Icons.add` button is wrapped in:
```dart
if (!widget.editMode)
  Positioned(... child: FilledButton(..., child: const Icon(Icons.add)))
```

In edit mode the add button is intentionally hidden (editing an existing session doesn't allow adding exercises via that FAB). The test intent — "empty list view shows 'No exercises' + an Icons.add button" — is testing a **live-session** concern, not an edit-mode concern.

**Fix:** Remove `editMode: true` from the test's `pumpWidget` call so the screen runs in live (non-edit) mode, matching the test's stated intent. Since `editMode` defaults to `false`, simply omit it.

---

## Acceptance Criteria
- [ ] All 9 previously failing tests pass
- [ ] No new test failures introduced
- [ ] The coach mark feature still works in the running app (overlay fires for first-time users, not for tests/returning users)

## Files Affected
- `lib/features/session/workout_session_screen.dart` — remove 2 lines from `initState`
- `test/interaction_flow_test.dart` — remove `editMode: true` from one test's `pumpWidget` call

## Progress
- [x] Remove TEMP reset block from `workout_session_screen.dart` `initState`
- [x] Remove `editMode: true` from `interaction_flow_test.dart` empty-session test
- [x] Add coach mark preference seeding to `widget_test.dart` _setupSession helper
- [x] Add coach mark preference seeding to `unsaved_changes_dialog_test.dart` setupEditSession helper
- [x] Add coach mark preference seeding to `interaction_flow_test.dart` setupSession helper
- [x] Run all tests and confirm 0 failures

**Phase Complete ✓**
Implementation done. All 9 previously failing tests now pass (487 passed, 0 failed). Test suites ready for code review.

