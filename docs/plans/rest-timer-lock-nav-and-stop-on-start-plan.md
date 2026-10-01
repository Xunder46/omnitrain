# Feature: Rest Timer Stops When Interval Starts + Nav Arrow Lock

## Overview
Bug: For Cardio (`timed`), Sports (`round`), and Isometric (`drill`) effort kinds, when the user
completes an interval, a rest timer opens. If the user skips forward to another interval (without
starting it), then starts that interval, the rest timer visually hides (because `_effortRunning`
flips true) but the underlying `EntryRest` record is never closed — it keeps ticking in the
background. When the user navigates back (pausing the skipped interval's timer), the rest timer
reappears with an inflated elapsed time.

Additionally, the navigation arrows (and set-dot indicators) are not locked while an interval
timer is actively running, letting users jump between sets mid-timer.

## Root Cause
In `_toggleEffortTimer` (timer mixin), both the `TimedState.notStarted` and
`RoundState.notStarted` cases call:
```dart
unawaited(widget.workoutState.recordRestEnd(effortId, entryIndex));
```
`recordRestEnd` closes only the rest record whose `entryIndex` matches the current interval.
But when the user skipped over a previous interval, the open `EntryRest` was created for that
**previous** interval's index, so `recordRestEnd` finds nothing and silently no-ops. The rest
record remains open indefinitely.

## Requirements
1. When an interval timer starts, ALL open `EntryRest` records for that exercise are closed
   (regardless of `entryIndex`).
2. Navigation arrows (back/forward) are **disabled** while the exercise timer is actively
   running (`_effortRunning[key] == true`).
3. Set-dot indicator taps are also **disabled** while the exercise timer is running.
4. When the timer is paused (not running), arrows and dots are re-enabled and the rest timer
   (if still open) is visible and counting.

## Acceptance Criteria
- [ ] Completing interval 1 → rest timer opens ✓
- [ ] Skipping to interval 3 then **starting** it → rest timer is fully closed (elapsed resets on next rest)
- [ ] Navigating back from a running interval 3 → NOT possible (arrows locked)
- [ ] Pausing interval 3 → arrows become enabled; any open rest timer visible if still open
- [ ] Back/forward arrows are visually dimmed when timer is running
- [ ] Set-dot indicators do not respond to taps when timer is running
- [ ] Applies to `timed`, `round`, and `drill` effort kinds (Cardio, Sports, Isometric)
- [ ] No regression for `set` effort kind (no timer, arrows remain always enabled)
- [ ] `closeAllOpenRests` is a no-op when there are no open rests

## Implementation Plan

### Phase 1: State layer — close ALL open rests on timer start

#### 1. `lib/state/workout/timer_manager.dart`
Add after `recordRestEnd`:
```dart
Future<void> closeAllOpenRests(String effortId) async {
  _clearError();
  try {
    final list = _entryRests[effortId];
    if (list == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    for (var i = 0; i < list.length; i++) {
      final rest = list[i];
      if (rest.restEndMs != null) continue;
      final closed = rest.copyWith(restEndMs: now, updatedAtMs: now);
      await _repository.updateEntryRest(closed);
      list[i] = closed;
    }
    _notify();
  } catch (e) {
    _setError('Failed to close all open rests: $e');
  }
}
```

#### 2. `lib/state/workout/workout_state.dart`
Add delegation after `recordRestEnd`:
```dart
Future<void> closeAllOpenRests(String effortId) =>
    _timerManager.closeAllOpenRests(effortId);
```

### Phase 2: Timer mixin — use closeAllOpenRests when starting

#### 3. `lib/features/session/workout_session_timer_mixin.dart`
In `_toggleEffortTimer`, for **both** `notStarted` cases, replace:
```dart
unawaited(widget.workoutState.recordRestEnd(effortId, entryIndex));
```
with:
```dart
unawaited(widget.workoutState.closeAllOpenRests(effortId));
```
Applies to `TimedState.notStarted` AND `RoundState.notStarted`.

### Phase 3: Detail view — lock nav when timer is running

#### 4. `lib/features/session/workout_session_detail_view.dart`

**In `_buildSetControls`** — add `isTimerRunning` flag after `entryIndex`:
```dart
final isTimerRunning = _effortRunning['$effortId-$entryIndex'] ?? false;
```
Change `backArrow`:
```dart
isEnabled: !isTimerRunning && (_currentSet > 1 || _currentExerciseIndex > 0),
onPressed: isTimerRunning || !(_currentSet > 1 || _currentExerciseIndex > 0)
    ? null
    : _previousSet,
```
Change `forwardArrow`:
```dart
isEnabled: !isTimerRunning,
onPressed: isTimerRunning ? null : (widget.editMode ? _nextSetInEditMode : _nextSet),
```

**In `_buildSetIndicator`** — add at top of method:
```dart
final effortId = _exercises[_currentExerciseIndex]['id'] as String;
final isTimerRunning = _effortRunning['$effortId-${_currentSet - 1}'] ?? false;
```
Change `GestureDetector.onTap`:
```dart
onTap: isTimerRunning ? null : () => _jumpToSet(index + 1),
```

## Files Affected
- `lib/state/workout/timer_manager.dart` (add `closeAllOpenRests`)
- `lib/state/workout/workout_state.dart` (delegate `closeAllOpenRests`)
- `lib/features/session/workout_session_timer_mixin.dart` (use `closeAllOpenRests` on start)
- `lib/features/session/workout_session_detail_view.dart` (lock arrows + dots)

## Progress
- [x] Add `closeAllOpenRests` to `timer_manager.dart`
- [x] Expose `closeAllOpenRests` in `workout_state.dart`
- [x] Replace `recordRestEnd` with `closeAllOpenRests` in timer mixin (timed case)
- [x] Replace `recordRestEnd` with `closeAllOpenRests` in timer mixin (round case)
- [x] Add `isTimerRunning` guard to back/forward arrows in `_buildSetControls`
- [x] Add `isTimerRunning` guard to dot indicator taps in `_buildSetIndicator`
- [x] Verify no regression for `set` effort kind (no timer, `isTimerRunning` is always false)

## Status: Complete

## Feedback
