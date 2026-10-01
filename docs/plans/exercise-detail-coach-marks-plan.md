# Feature: Exercise Detail Coach Marks

## Overview
One-time coach mark overlays pointing at the notes and info header icons in the
exercise detail view, to teach users about these two actions on first use.

## Requirements
- Notes coach mark fires on first open of exercise detail view
- Info coach mark fires on first open after notes hint is already seen (never both simultaneously)
- Tapping anywhere dismisses the active coach mark
- Each dismissal immediately persists the flag via `WorkoutRepository.setPreferenceBool`
- Coach marks match the app's dark, minimal visual language
- No third-party libraries — Flutter overlay-based implementation
- The highlighted icon gently pulses to draw the eye
- Keys: `'hint_seen_exercise_notes'` and `'hint_seen_exercise_info'`
- Follow exact same pattern as `hint_seen_maintenance` in `HomeState` / `WorkoutState`

## Acceptance Criteria
- [ ] On first open of any exercise detail view, coach mark appears on notes icon
- [ ] On subsequent first open (after notes seen), coach mark appears on info icon
- [ ] Tapping coach mark or anywhere on screen dismisses it and persists flag
- [ ] Neither coach mark re-appears after dismissal (even across restarts)
- [ ] Both persisted independently — dismissing one never dismisses the other
- [ ] Never shown simultaneously — notes first, info second on next open
- [ ] Visual: dark semi-transparent backdrop, primary accent glow/pulse on icon, minmal label
- [ ] `flutter analyze` produces zero new errors
- [ ] Existing `exercise_notes_sheet_test.dart` still passes

## Analysis
No data layer changes are needed. `getPreferenceBool` / `setPreferenceBool` already
exist on `WorkoutRepository` and are implemented in both `HiveWorkoutRepository` and
`MockWorkoutRepository`.

The exercise detail view is entirely within `WorkoutSessionScreen` (in
`_WorkoutSessionScreenState`). The detail header actions — notes icon and info icon —
are rendered by `_buildExerciseHeaderActions`. Entry to detail mode is serialised
through a single method: `_focusExerciseDetail`. This is the correct injection point.

The maintenance hint pattern (`HomeState`) is the exact model to follow:
`WorkoutState` gets 2 new boolean fields, an `initExerciseHints()` async method,
getter properties, and `mark*Seen()` async methods. The screen loads these, then
after transitioning to detail, schedules the appropriate coach mark via
`WidgetsBinding.instance.addPostFrameCallback`.

## Scenarios
N/A (covered by acceptance criteria above)

## Iteration 1

### DB Changes
None.

### Backend Changes
Add to `lib/state/workout/workout_state.dart`:
1. `bool _exerciseNotesHintSeen = false;`
2. `bool _exerciseInfoHintSeen = false;`
3. `bool get shouldShowExerciseNotesHint => !_exerciseNotesHintSeen;`
4. `bool get shouldShowExerciseInfoHint => !_exerciseInfoHintSeen;`
5. `Future<void> initExerciseHints()` — reads both flags from repository:
   ```dart
   Future<void> initExerciseHints() async {
     _exerciseNotesHintSeen = await _repository.getPreferenceBool('hint_seen_exercise_notes');
     _exerciseInfoHintSeen = await _repository.getPreferenceBool('hint_seen_exercise_info');
     notifyListeners();
   }
   ```
6. `Future<void> markExerciseNotesHintSeen()` — sets flag, notifies, persists:
   ```dart
   Future<void> markExerciseNotesHintSeen() async {
     if (_exerciseNotesHintSeen) return;
     _exerciseNotesHintSeen = true;
     notifyListeners();
     await _repository.setPreferenceBool('hint_seen_exercise_notes', true);
   }
   ```
7. `Future<void> markExerciseInfoHintSeen()` — same pattern for info.

### Frontend Changes
Modify `lib/features/session/workout_session_screen.dart`:

**State variables (add near top of `_WorkoutSessionScreenState`):**
```dart
// GlobalKeys for coach mark position anchors
final GlobalKey _notesIconKey = GlobalKey();
final GlobalKey _infoIconKey = GlobalKey();
// Tracks whether initExerciseHints() has been awaited in this session
bool _exerciseHintsLoaded = false;
// Active coach mark overlay entry (at most one at a time)
OverlayEntry? _coachMarkEntry;
```

**dispose() — remove active overlay entry:**
```dart
_coachMarkEntry?.remove();
_coachMarkEntry = null;
```

**`_buildExerciseHeaderActions` — wrap each icon button in a keyed SizedBox:**
- Wrap the info `IconButton` in `SizedBox(key: _infoIconKey, child: IconButton(...))`
- Wrap the notes `IconButton` in `SizedBox(key: _notesIconKey, child: IconButton(...))`
- **Do not remove** `key: const Key('exercise-info-button')` and
  `key: const Key('exercise-note-button')` — tests depend on them.

**`_focusExerciseDetail` — schedule hint after detail transitions:**
After the `setState(...)` call, append:
```dart
if (!_exerciseHintsLoaded) {
  await widget.workoutState.initExerciseHints();
  _exerciseHintsLoaded = true;
}
WidgetsBinding.instance.addPostFrameCallback((_) {
  if (!mounted) return;
  _maybeShowExerciseCoachMark();
});
```

**New method `_maybeShowExerciseCoachMark()`:**
```dart
void _maybeShowExerciseCoachMark() {
  if (_coachMarkEntry != null) return; // already showing
  final theme = Theme.of(context);
  final primary = theme.colorScheme.primary;
  if (widget.workoutState.shouldShowExerciseNotesHint) {
    _showExerciseCoachMark(
      targetKey: _notesIconKey,
      label: 'Add notes for this exercise',
      primaryColor: primary,
      onDismiss: () => unawaited(widget.workoutState.markExerciseNotesHintSeen()),
    );
  } else if (widget.workoutState.shouldShowExerciseInfoHint) {
    _showExerciseCoachMark(
      targetKey: _infoIconKey,
      label: 'View exercise info',
      primaryColor: primary,
      onDismiss: () => unawaited(widget.workoutState.markExerciseInfoHintSeen()),
    );
  }
}
```

**New method `_showExerciseCoachMark()`:**
Inserts an `OverlayEntry` containing `_ExerciseCoachMarkOverlay`.
The overlay uses `RenderBox.localToGlobal(Offset.zero)` on `targetKey` to compute
the icon center, then renders:
- Full-screen `GestureDetector` background (dark 60% opacity)
- A circular pulsing glow at the icon center (primary color)
- Small `Container` label box below the icon

**New private widget `_ExerciseCoachMarkOverlay` (StatefulWidget):**
- `AnimationController` for a gentle pulse (scale 1.0 → 1.35 → 1.0, 900ms, looping)
- Full screen `Stack`:
  1. Dark backdrop `GestureDetector` covering whole screen (dismisses on tap)
  2. `Positioned` circular animated glow at icon center
  3. `Positioned` label `Container` just below the icon

### Implementation Steps
1. [ ] Add `_exerciseNotesHintSeen`, `_exerciseInfoHintSeen`, flags, getters, `initExerciseHints()`, `markExerciseNotesHintSeen()`, `markExerciseInfoHintSeen()` to `lib/state/workout/workout_state.dart`
2. [ ] Add `_notesIconKey`, `_infoIconKey`, `_exerciseHintsLoaded`, `_coachMarkEntry` to `_WorkoutSessionScreenState`
3. [ ] Wrap info `IconButton` in keyed `SizedBox` in `_buildExerciseHeaderActions`
4. [ ] Wrap notes `IconButton` (the one inside `Stack`) in keyed `SizedBox`
5. [ ] Extend `_focusExerciseDetail`: after `setState`, await `initExerciseHints` once, then schedule `_maybeShowExerciseCoachMark` via postFrameCallback
6. [ ] Implement `_maybeShowExerciseCoachMark()` and `_showExerciseCoachMark()`
7. [ ] Add `_ExerciseCoachMarkOverlay` StatefulWidget at bottom of session screen file
8. [ ] Add `_coachMarkEntry?.remove()` to `dispose()`
9. [ ] Run `flutter analyze` — fix any issues
10. [ ] Run `flutter test test/exercise_notes_sheet_test.dart` — must pass

### Files Affected
- `lib/state/workout/workout_state.dart`
- `lib/features/session/workout_session_screen.dart`

### Notes
- Tests reference `const Key('exercise-note-button')` — these must remain unchanged.
  The `GlobalKey`s go on `SizedBox` wrappers, not the `IconButton`s themselves.
- The `_exerciseHintsLoaded` flag prevents redundant repository reads when navigating
  between exercises in the same session.
- `_maybeShowExerciseCoachMark` guards `_coachMarkEntry != null` so tapping back and
  immediately forward can never stack two overlays.
- `_coachMarkEntry` is cleaned up in `dispose()` in case the screen leaves widget
  tree while an overlay is visible.
- EditMode sessions open to detail directly via `initialFocusId`; coach marks fire
  there just as well since `_focusExerciseDetail` is always the transition point.

## Progress
- [x] Step 1: Add hint state to WorkoutState
- [x] Step 2–4: Add screen state variables and icon key wrappers
- [x] Step 5–8: Add coach mark trigger logic and overlay widget
- [x] Step 9–10: Verify and test — flutter analyze: 0 errors; flutter test: 476/476 passed

## Feedback
[No feedback yet]
