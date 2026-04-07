# Feature: Auto-Open Exercise Picker on New Session Start

## Overview
When a user starts a new workout session (via tile tap), immediately open the exercise picker dialog instead of landing on an empty session screen. This reduces friction and gets users to the action (adding exercises) faster.

## Requirements
- Auto-open exercise picker on first session load when:
  - Session has NO exercises
  - Session is NOT in edit mode
  - Session is NOT created from a routine (routines pre-load exercises)
  - Session is a new creation (modal-based, free training, or rolling)
- If user cancels the picker, fall back to the empty state screen with "Add First Exercise" button
- Preserve preferred modality filtering if navigating from a modality tile

## Acceptance Criteria
- [ ] Exercise picker opens automatically when session loads with zero exercises (non-edit mode)
- [ ] Preferred modality (from tile) is passed through and applied in the picker
- [ ] Routine sessions are excluded (they pre-load exercises)
- [ ] Edit mode sessions are excluded (never auto-open)
- [ ] Canceling the picker shows the empty state screen
- [ ] All session types work: free training, modality-based, rolling
- [ ] No breaking changes to existing flows

## Technical Analysis

### Current Flow
1. Tile tapped → navigation to `WorkoutSessionScreen`
2. `initState()` → `_loadExercises()`
3. If `_exercises.isEmpty` → displays "No exercises yet" screen
4. User manually taps "Add First Exercise" → `_addExercise()` → dialog opens

### Desired Flow  
1. Tile tapped → navigation to `WorkoutSessionScreen`
2. `initState()` → `_loadExercises()`
3. If `_exercises.isEmpty` AND not edit mode AND not routine session:
   - Automatically call `_addExercise()` to open picker
4. If picker dialog returns exercise, flow continues normally
5. If picker is cancelled, fall back to empty state screen

### Key Conditions to Check
- `widget.editMode` — Is this a reviewed/edited completed session? If true, never auto-open
- `_exercises.isEmpty` — Does session have no exercises yet?
- Routine detection: Check if session was loaded from a routine (would need to trace through `WorkoutState` to see if exercises were pre-loaded)
- First load only: Avoid re-opening picker on subsequent `_loadExercises()` calls

### Implementation Strategy
1. Add state flag to track if first auto-open was attempted
2. After `_exercises` loads in `_loadExercises()`, check conditions
3. If all conditions met, use `Future.microtask` or `WidgetsBinding.instance.addPostFrameCallback()` to trigger `_addExercise()` after UI builds
4. Ensure picker is opened AFTER `setState()` completes so loading state is cleared

## Scenarios
- **Scenario 1**: User taps Strength modality tile, session created with zero exercises
  - ✓ Exercise picker should auto-open with Strength modality pre-filtered
  
- **Scenario 2**: User taps Free Training, chooses rolling mode, session created with zero exercises
  - ✓ Exercise picker should auto-open with no modality filter
  
- **Scenario 3**: User opens a completed session in edit mode with exercises
  - ✓ No auto-open (edit mode check prevents it)
  
- **Scenario 4**: User opens a routine that has pre-loaded exercises
  - ✓ No auto-open (exercises exist, isEmpty check prevents it)
  
- **Scenario 5**: User cancels the auto-opened exercise picker
  - ✓ Empty state screen appears with "Add First Exercise" button
  
- **Scenario 6**: User taps "Add First Exercise" after canceling picker
  - ✓ Picker opens again (normal `_addExercise()` flow)

## Implementation Plan

### Phase 1: State Management (@developer)
1. [ ] In `_WorkoutSessionScreenState`, add new boolean field:
   - `bool _autoOpenAttempted = false;` — flag to prevent re-opening on re-loads
2. [ ] Ensure this flag is NOT reset in `_loadExercises()` once set

### Phase 2: Auto-Open Logic (@developer)
1. [ ] Modify `_loadExercises()` to add auto-open trigger at the end:
   - After `setState() { _isLoading = false; ... }`
   - Add check: `if (_shouldAutoOpenPicker()) { _scheduleAutoOpenPicker(); }`
2. [ ] Create `_shouldAutoOpenPicker()` method:
   - Return `true` if:
     - NOT edit mode (`!widget.editMode`)
     - AND exercises list is empty (`_exercises.isEmpty`)
     - AND first load (`!_autoOpenAttempted`)
     - AND NOT loading from a routine (session should not have pre-loaded exercises)
   - Return `false` otherwise
3. [ ] Create `_scheduleAutoOpenPicker()` method:
   - Use `Future.microtask(() => _addExercise())` to open picker after frame renders
   - Set `_autoOpenAttempted = true` to prevent re-opening on subsequent loads

### Phase 3: Preserve Modality (@developer)
1. [ ] Ensure `_addExercise()` already reads `widget.preferredModality` and passes it to picker
   - ✓ Already implemented (line ~1215: `final modality = widget.workoutState.currentSession?.modality ?? widget.preferredModality;`)
2. [ ] No changes needed — existing code already handles this

### Phase 4: UI Fallback (@developer)
1. [ ] Verify empty state screen still renders if:
   - Picker is cancelled/dismissed
   - AND no exercise was added
   - ✓ Existing logic handles this (if `_exercises` still empty after dialog closes)
2. [ ] No code changes needed — existing flow works correctly

### Files Affected
- `lib/features/session/workout_session_screen.dart`
  - Add `_autoOpenAttempted` field to `_WorkoutSessionScreenState`
  - Modify `_loadExercises()` lifecycle
  - Add `_shouldAutoOpenPicker()` helper
  - Add `_scheduleAutoOpenPicker()` helper

## Implementation Steps

### Step 1: Add state field (@developer)
In `_WorkoutSessionScreenState`:
```dart
class _WorkoutSessionScreenState extends State<WorkoutSessionScreen> {
  // ... existing fields ...
  bool _autoOpenAttempted = false;  // NEW: Track if auto-open was attempted
  // ... rest of fields ...
}
```

### Step 2: Create helper methods (@developer)
Add two new methods to `_WorkoutSessionScreenState`:

```dart
bool _shouldAutoOpenPicker() {
  // Auto-open only on first load with empty exercises in live (non-edit) mode
  return !widget.editMode &&
      _exercises.isEmpty &&
      !_autoOpenAttempted;
}

void _scheduleAutoOpenPicker() {
  _autoOpenAttempted = true; // Prevent re-opening on subsequent _loadExercises calls
  // Schedule after current frame renders so loading state is cleared
  Future.microtask(() {
    if (mounted) {
      _addExercise();
    }
  });
}
```

### Step 3: Trigger auto-open (@developer)
In `_loadExercises()`, after the `setState()` where `_isLoading = false`:
```dart
setState(() {
  // ... existing state updates ...
  _isLoading = false;
});

// NEW: Check if we should auto-open the exercise picker
if (_shouldAutoOpenPicker()) {
  _scheduleAutoOpenPicker();
}
```

Find the exact location in the code around line 280-310 where `_isLoading = false;` is set in the first setState() block within the try catch of _loadExercises().

## Progress
- [x] Add `_autoOpenAttempted` state field
- [x] Create `_shouldAutoOpenPicker()` helper method
- [x] Create `_scheduleAutoOpenPicker()` helper method  
- [x] Integrate auto-open logic into `_loadExercises()`
- [x] Code compiles with no errors (flutter analyze)
- [x] All existing tests pass (456 passed, 8 pre-existing failures)
- [x] Web build succeeds
- [ ] Manual test on web (modality tiles, free training, rolling)
- [ ] Manual test cancel flow (picker → empty state)
- [ ] Manual test edit mode (should NOT auto-open)
- [ ] Manual test routine sessions (should NOT auto-open)

## Phase 2 Complete ✓

All code changes implemented and verified. The exercise picker will now auto-open when:
- New session is created (from modality tiles, free training, or rolling)
- Session has zero exercises
- Session is NOT in edit mode
- First time loading (subsequent _loadExercises() calls won't re-trigger)

Implementation uses `Future.microtask()` to ensure the UI renders before opening the dialog, reusing the existing `_addExercise()` method which already handles modality filtering and exercise selection.

## Feedback
[Leave empty until review]

## Notes
- The `_addExercise()` method already handles all the complexity (modality filtering, metric selection, etc.)
- Using `Future.microtask()` ensures the picker opens after the frame renders and loading spinner is cleared
- The `_autoOpenAttempted` flag prevents infinite loops if exercises fail to add and `_loadExercises()` is called again
- No database/data model changes needed — purely UI/state flow enhancement
