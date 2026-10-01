# Feature: Free Rolling Session — Add Exercise Bug Fix

## Overview

A free rolling session (started from Free Training tile with "Rolling Session" toggle) cannot add exercises. Two bugs combine to cause this:

1. **Auto-open suppressed**: The exercise picker never auto-opens on start for rolling sessions, even when the session is brand new with no blocks.
2. **Exercise silently discarded**: When the user taps "Add Exercise" at the session level and selects an exercise, it is created in the repository with `blockId == null`. But `_loadExercises` filters `_exercises` to only those where `blockId != null` for rolling sessions — so the exercise immediately disappears.

## Requirements

- Adding an exercise to an empty free rolling session must work end-to-end.
- The exercise picker should auto-open when a rolling session starts with no blocks (matching the UX expectation).
- Exercises added via the session-level "Add Exercise" button must appear in the rolling session list view.
- The rolling session design intent (exercises grouped in time-stamped blocks) must be preserved.

## Acceptance Criteria

- [ ] Starting a free rolling session auto-opens the exercise picker (same as standard sessions)
- [ ] Selecting an exercise auto-creates a new named block and assigns the exercise to it
- [ ] The exercise appears immediately in the list view under the auto-created block
- [ ] Subsequent "Add Exercise" from the session-level bar also auto-creates a new block each time
- [ ] Exercises added within a block card ("Add Exercise" inside a block) still go to that specific block — no change
- [ ] No regression for standard (non-rolling) sessions

## Analysis

### Bug 1 — Auto-open suppressed

File: `lib/features/session/workout_session_screen.dart`

```dart
bool _shouldAutoOpenPicker() {
  return !widget.editMode &&
      _exercises.isEmpty &&
      !_autoOpenAttempted &&
      !widget.workoutState.isRollingSession;  // <-- blocks auto-open for ALL rolling sessions
}
```

The guard `!widget.workoutState.isRollingSession` was added because rolling sessions are block-based. But a brand-new free rolling session has no blocks — so the user lands on an empty screen with buttons only, and no picker appears.

**Fix**: Relax the guard to only suppress auto-open when the rolling session already has blocks. An empty rolling session should auto-open:

```dart
bool _shouldAutoOpenPicker() {
  final hasBlocks = widget.workoutState.getSessionBlocks().isNotEmpty;
  return !widget.editMode &&
      _exercises.isEmpty &&
      !_autoOpenAttempted &&
      (!widget.workoutState.isRollingSession || !hasBlocks);
}
```

### Bug 2 — Exercise silently discarded

File: `lib/features/session/workout_session_screen.dart`, `_addExercise`

When "Add Exercise" is called without a `blockId` (session-level button or auto-open), the effort is created in the repo with `blockId == null`. Then `_loadExercises` filters it out:

```dart
// In _loadExercises:
if (widget.workoutState.isRollingSession) {
  _exercises = _exercises.where((e) => e['blockId'] != null).toList();
  // exercises with blockId == null are dropped!
}
```

**Fix**: In `_addExercise`, after a successful add, if it's a rolling session and no explicit `blockId` was provided, auto-create a new session block and assign the effort to it:

```dart
// Inside _addExercise, after the existing blockId assignment block:
if (effortId.isNotEmpty && blockId == null && widget.workoutState.isRollingSession) {
  try {
    await widget.workoutState.addSessionBlock(); // creates time-stamped block
    final newBlock = widget.workoutState.getSessionBlocks().last;
    await widget.workoutState.assignEffortToBlock(effortId, newBlock.id);
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to assign exercise to block: $e')),
      );
    }
  }
}
```

This preserves the rolling session design: exercises are always in named time-stamped blocks.

## Implementation Plan

### Phase 1: Logic/UI (@developer)

**File**: `lib/features/session/workout_session_screen.dart`

1. [ ] **Fix `_shouldAutoOpenPicker()`** — relax the rolling session guard to only suppress auto-open when blocks already exist:
   - Add `final hasBlocks = widget.workoutState.getSessionBlocks().isNotEmpty;`
   - Change `!widget.workoutState.isRollingSession` to `(!widget.workoutState.isRollingSession || !hasBlocks)`

2. [ ] **Fix `_addExercise()`** — auto-create a block for rolling sessions when no `blockId` is provided:
   - After the existing `if (effortId.isNotEmpty && blockId != null)` block (line ~1079), add a new block:
   ```dart
   if (effortId.isNotEmpty && blockId == null && widget.workoutState.isRollingSession) {
     try {
       await widget.workoutState.addSessionBlock();
       final newBlock = widget.workoutState.getSessionBlocks().last;
       await widget.workoutState.assignEffortToBlock(effortId, newBlock.id);
     } catch (e) {
       if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text('Failed to assign exercise to block: $e')),
         );
       }
     }
   }
   ```

### No DBA phase needed
- No schema changes
- No new models
- No new repository methods
- All required methods (`addSessionBlock`, `assignEffortToBlock`, `getSessionBlocks`) already exist

## Files Affected

- `lib/features/session/workout_session_screen.dart`
  - `_shouldAutoOpenPicker()` (~line 981)
  - `_addExercise()` (~line 998)

## Notes

- `addSessionBlock()` auto-names the block with current wall-clock time (e.g., "9:15 AM") — this is the rolling session design intent and requires no change.
- The fix does NOT touch `_loadExercises` or the `blockId != null` filter — that filter is correct and intentional.
- The "Add Exercise" button within an existing block card already passes `blockId: block.id`, so it is unaffected by this change.
- For the auto-open fix, using `getSessionBlocks()` (already loaded in state) avoids any async work inside `_shouldAutoOpenPicker`.

## Progress

- [x] Fix `_shouldAutoOpenPicker()` in workout_session_screen.dart
- [x] Fix `_addExercise()` auto-create block in workout_session_screen.dart
- [ ] Manual test: start free rolling session → picker auto-opens → select exercise → exercise appears in block
- [ ] Manual test: add another exercise from session bar → new block auto-created → exercise appears

### Phase 1 Status: Complete

## Feedback

