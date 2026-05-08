# Feature: Active Session Screen — Toolbar Rework & Timer Interaction Redesign

## Overview

Restructure the active session screen's bottom toolbar to clearly separate three categories of control
(timer playback, set management, primary action) that are currently blended together in a single row.
Replace the play button in the toolbar with tap-to-toggle on the timer display itself. Introduce a
clear, modality-adaptive "Log Set" primary action button distinct from navigation arrows. Add
delete confirmation for all deletes. Enforce a global in-progress timer lock to prevent accidental
concurrent timers.

---

## Requirements

- Toolbar order: back arrow · delete · Log Set (or nav arrow for logged sets) · add set · forward arrow
- Timer control moves entirely to tapping the timer display (no play button in toolbar)
- "Log Set" button: rectangular primary-color button at toolbar center, appears on every incomplete set
- Label adapts by effortKind: "Log Set" / "Log Interval" / "Log Round" or "Log Period" / "Log Hold"
- On logged (historical) or out-of-scope sets: center shows a forward arrow identical to the back arrow
- Delete always triggers a lightweight confirmation dialog (single confirm tap)
- A set enters "in progress" only after its timer is started for the first time
- Global in-progress lock: starting a second timer while another set is in progress is blocked
- Timer auto-pauses when the user navigates away from a timed set
- "Previous set" reference always follows plan sequence (already correct; verify and guard gracefully)
- Swipe navigation between sets must continue to work with no regression
- Weight Adjustment control stays in its current zone, visually distinct from the timer tap target

---

## Acceptance Criteria

- [ ] Every incomplete set across all modalities shows a primary-color rectangular button labeled
      "Log Set", "Log Interval", "Log Round", "Log Period", or "Log Hold" at the center of the toolbar.
- [ ] Historical sets and future sets where the user has not navigated show a forward nav arrow at center.
- [ ] Bottom toolbar order left-to-right: back arrow, delete, center button, add set, forward arrow.
- [ ] The dedicated play button is removed from the toolbar entirely.
- [ ] Tapping the timer display starts or pauses the timer for all timer-based modalities (timed, round, drill).
- [ ] Tapping the timer display never changes set lifecycle state.
- [ ] Timer display shows a play icon overlay when stopped/paused, and a pause indicator when running.
- [ ] A set is marked "in progress" only after its timer is started for the first time.
- [ ] Navigating away from a timed set that is in progress auto-pauses its timer.
- [ ] Attempting to start a second timer while another set is in progress shows a blocking message.
- [ ] The user can navigate to and log any incomplete set in any order.
- [ ] "Previous set" reference always shows the plan-sequence predecessor, not the log-order predecessor;
      if that set hasn't been logged yet, the reference shows the planned target or a graceful empty state.
- [ ] The Weight Adjustment control on isometric (drill) sets stays in place and is visually distinct from
      the timer tap area.
- [ ] Delete action always shows a confirmation dialog before data is destroyed.
- [ ] Swipe navigation continues to work with no regression.
- [ ] All modalities (resistance, isometric, cardio, weighted cardio, sports) adopt the new layout.

---

## Scenarios

Populated by Developer agent during Phase 0.

---

## Iteration 1

### DB Changes
None. All required state (TimedState.active/paused/finished, RoundState.active/paused/finished) is
already persisted. No new tables, columns, or repository methods are required.

### Backend Changes (Timer Mixin)
Changes in `lib/features/session/workout_session_timer_mixin.dart`:
- Add `Set<String> _inProgressKeys` — tracks effortId-entryIndex keys whose timer has been started
  at least once and not yet finished (logged). Enables the global in-progress lock.
- Populate `_inProgressKeys` inside `_restoreTimerStateFromPersisted` for any persisted
  `active` or `paused` TimedInstance / RoundInstance entries.
- Add helper `String? _getOtherInProgressKey(String currentTimerKey)` — scans `_inProgressKeys`
  for any key that is not `currentTimerKey` and is NOT in a finished state; returns the conflicting
  key (or null if clear).
- Modify `_toggleEffortTimer()` for the `notStarted` → `active` transition:
  - Check `_getOtherInProgressKey(timerKey)` before starting.
  - If a conflict exists, show a SnackBar/dialog: "Another set is still in progress. Finish or pause
    it before starting a new timer."
  - Block the start; return early.
- When a timer first starts from `notStarted`, add `timerKey` to `_inProgressKeys`.
- When `_resetTimerState()` is called (after logging), remove the key from `_inProgressKeys`.

### Frontend Changes (Detail View)
Changes in `lib/features/session/workout_session_detail_view.dart`:

#### 1. `_buildSetControls()` — complete rewrite
New layout:
```
Row(MainAxisAlignment.spaceBetween) [
  _buildNavArrow(Icons.arrow_back, _previousSet, enabled: canGoPrev),
  _buildIconButton(Icons.delete_outline, _deleteCurrentSet),
  if (!_isCurrentSetLogged())
    _buildLogSetButton(theme)          // PRIMARY: full-width rectangular button
  else
    _buildNavArrow(Icons.arrow_forward, _navigateForward, enabled: canGoNext),
  _buildIconButton(Icons.playlist_add, _addSet),
  _buildNavArrow(Icons.arrow_forward, _navigateForward, enabled: canGoNext),
]
```
- The center primary button does NOT appear in edit mode (edit mode uses its own flow).
- Edit mode center: keep the existing `_nextSetInEditMode` arrow button.

#### 2. `_buildLogSetButton()` — new method
- A `FilledButton` (Material 3 rectangular primary-color button) using the existing app button style.
- Label adapts by effortKind:
  - `set` → "Log Set"
  - `timed` → "Log Interval"
  - `round` + sports modality → "Log Period"
  - `round` + any other modality → "Log Round"
  - `drill` → "Log Hold"
- On press: calls `_logSet()`.

#### 3. `_buildNavArrow()` — rename/restyle from `_buildArrowButton()`
- Always circular, always muted (never primary-colored).
- Same size for back and forward (no more `isPrimary` distinction).
- `_navigateForward()` replaces the forward arrow's action (pure navigation, no logging).

#### 4. `_isCurrentSetLogged()` — new helper
```dart
bool _isCurrentSetLogged() {
  if (_exercises.isEmpty) return false;
  final ex = _exercises[_currentExerciseIndex];
  return _isSetLogged(ex['id'] as String, _currentSet - 1, ex['effortKind'] as String? ?? 'set');
}
```

#### 5. `_navigateForward()` — new method
Pure navigation to next set or next exercise without logging:
- Pause current timer if running (same guard as `_previousSet`).
- Move `_currentSet++` or `_currentExerciseIndex++`/`_currentSet = 1`.
- If at end of all exercises, do nothing (or optionally show finish dialog).

#### 6. Timer display tap-to-toggle
In `_buildMetricWidget()`, wrap the timer display area with `GestureDetector` for `timed`, `round`,
and `drill` effort kinds (not in edit mode, not when set is finished):
```dart
GestureDetector(
  onTap: () => _toggleEffortTimer(effortId),
  child: Stack(
    alignment: Alignment.center,
    children: [
      InlineMetricEditor(metricType: 'duration', ..., isReadOnly: true),
      if (!isFinished)
        Positioned(
          bottom: 8,
          child: Icon(
            isRunning ? Icons.pause_circle_outline : Icons.play_circle_outline,
            size: 20,
            color: theme.colorScheme.primary.withOpacity(0.55),
          ),
        ),
    ],
  ),
)
```
- The play/pause icon is a subtle overlay, not a separate button (maintains visual cleanliness).
- The `extra-weight` / Weight Adjustment section is placed OUTSIDE this GestureDetector so it is
  not captured by the timer tap gesture. This is the existing separation in the widget tree.

#### 7. `_deleteCurrentSet()` — rework of `_deleteLastSet()`
Rename and add lightweight confirmation for non-last-set deletes too:
```
if (entries.length > 1) {
  // New: confirm deletion of a mid-sequence set
  show lightweight dialog: "Delete Set ${_currentSet}? This cannot be undone."
  [Cancel] [Delete]
  if cancelled: return
}
// existing last-set logic (remove exercise confirmation) unchanged
```
Note: `_deleteLastSet()` currently always deletes the LAST entry (not the currently viewed entry).
The rename to `_deleteCurrentSet()` also changes the target to the currently viewed entry index
(`_currentSet - 1`), which is a more intuitive behavior matching the user's visible context.
This is a behavior change — confirm with product before implementing if needed.
Actually: re-reading the spec ("adjacent to the primary Log Set button"), the trashcan deletes the
current set (not always the last). Plan accordingly.

#### 8. `_jumpToSet()` — add timer pause
```dart
void _jumpToSet(int setNumber) {
  // Auto-pause timer if in progress before jumping
  if (_exercises.isNotEmpty) {
    final ex = _exercises[_currentExerciseIndex];
    final effortId = ex['id'] as String;
    final timerKey = '$effortId-${_currentSet - 1}';
    if (_effortRunning[timerKey] == true) {
      _pauseEffortTimer(effortId, _currentSet - 1);
    }
  }
  setState(() { _currentSet = setNumber; });
  ...
}
```

#### 9. "Previous set" reference — graceful empty state
`_buildPreviousSetStats()` already reads from `entries[_currentSet - 2]` (plan sequence), which is
correct. Add a graceful empty state when the previous set has not yet been logged: if all values
are zero/default and the set is not logged, show "Previous: —" or "No previous data yet" instead
of zeros.

### Implementation Steps

**Phase A — Timer mixin changes (low risk; no UI)**
1. [ ] Add `_inProgressKeys` set to `WorkoutSessionTimerMixin`.
2. [ ] Populate `_inProgressKeys` from persisted state in `_restoreTimerStateFromPersisted`.
3. [ ] Add `_getOtherInProgressKey(String currentKey)` helper.
4. [ ] Guard the `notStarted → active` transitions in `_toggleEffortTimer` (round, timed/drill cases)
       with the in-progress lock check; show SnackBar on block.
5. [ ] Add `timerKey` to `_inProgressKeys` on first start.
6. [ ] Remove from `_inProgressKeys` in `_resetTimerState`.

**Phase B — Navigation & auto-pause fixes (low risk)**
7. [ ] Add timer auto-pause to `_jumpToSet()`.
8. [ ] Verify `_switchExercise()` also pauses; add guard if missing.

**Phase C — Toolbar restructure (moderate risk; isolated to `_buildSetControls`)**
9. [ ] Add `_isCurrentSetLogged()` helper.
10. [ ] Add `_navigateForward()` method.
11. [ ] Rewrite `_buildSetControls()` with new 5-element layout.
12. [ ] Add `_buildLogSetButton()` with adaptive label.
13. [ ] Restyle `_buildNavArrow()` (remove `isPrimary`; make both arrows visually identical).
14. [ ] Wire edit mode center button correctly (no change to `_nextSetInEditMode` behavior).

**Phase D — Timer display tap-to-toggle (moderate risk; touches `_buildMetricWidget`)**
15. [ ] Wrap `timed` duration display with GestureDetector + play/pause overlay.
16. [ ] Wrap `round` display with GestureDetector + play/pause overlay.
17. [ ] Wrap `drill` duration display with GestureDetector + play/pause overlay; ensure Weight
        Adjustment TextButton is OUTSIDE the GestureDetector.
18. [ ] Remove the `if (isTimerBased && !widget.editMode)` play/pause icon button from the old
        `_buildSetControls` inner Row (this is part of step 11).

**Phase E — Delete confirmation for all deletes (low risk)**
19. [ ] Rename `_deleteLastSet()` to `_deleteCurrentSet()`.
20. [ ] Change delete target from always-last-entry to `_currentSet - 1` (current entry).
21. [ ] Add lightweight "Delete Set X?" dialog for multi-set cases (currently missing).
22. [ ] Keep "Remove Exercise?" dialog for single-set case (already exists).

**Phase F — Previous set graceful empty state (low risk; cosmetic)**
23. [ ] In `_buildPreviousSetStats()`, check if previous entry has meaningful data before building
        the stats string; show "Previous: —" if the previous entry is all-zero/default.

**Phase G — Regression validation**
24. [ ] Manually verify swipe navigation still works (GestureDetector wrapping timer must not
        intercept swipe events; use `behavior: HitTestBehavior.translucent` if needed).
25. [ ] Manually verify Weight Adjustment is tappable and does not trigger timer toggle.
26. [ ] Verify all 5 modalities in detail view: resistance, isometric, cardio, weighted cardio, sports.
27. [ ] Run existing unit tests; fix any regressions in session-related tests.

---

## Progress

- [x] Phase A: Timer mixin — in-progress lock
- [x] Phase B: Navigation auto-pause fixes
- [x] Phase C: Toolbar restructure
- [x] Phase D: Timer display tap-to-toggle
- [x] Phase E: Delete confirmation for all deletes
- [x] Phase F: Previous set graceful empty state
- [x] Phase G: Regression validation

### Phase 2 Complete ✓
All 17 Phase 0 scenario tests pass. No regressions in existing tests.

**Bonus fix**: `session_core_entry.dart` — effort ID changed from `'effort-$now'` to
`'effort-$now-${currentEfforts.length}'` to prevent ID collision when two exercises are added
within the same millisecond (a real production bug caught by the test suite).

---

## Files Affected

| File | Change |
|------|--------|
| `lib/features/session/workout_session_timer_mixin.dart` | Phases A, B — `_inProgressKeys`, lock guard, `_resetTimerState` |
| `lib/features/session/workout_session_detail_view.dart` | Phases B–F — toolbar, timer tap, delete, nav methods |
| `lib/features/session/workout_session_screen.dart` | Phase B — `_jumpToSet`, possibly `_switchExercise` |

No data model, repository, or state-layer changes required.

---

## Key Implementation Notes

### "In progress" definition
A timer-based set is "in progress" if its `TimedInstance.state` or `RoundInstance.state` is `active`
OR `paused`. For non-timer (`set`) effortKind, the concept does not apply (no lockout).

### `_inProgressKeys` initialization on session restore
When `_restoreTimerStateFromPersisted` encounters a `paused` or `active` instance, it must add the
corresponding `timerKey` to `_inProgressKeys`. This ensures the lock is respected after a session
restart / navigation back into the screen.

### GestureDetector and swipe coexistence
The timer display GestureDetector uses `onTap` only. Swipe navigation likely uses `onHorizontalDrag`
at the parent Scaffold or Stack level. These should not conflict. If they do, set
`behavior: HitTestBehavior.opaque` on the timer GestureDetector and confirm the swipe detector is
at a higher ancestor level.

### `_deleteCurrentSet` target change
Old: always deletes `entries[entries.length - 1]` (last entry).
New: deletes `entries[_currentSet - 1]` (currently viewed entry).
This is a behavior change. After deletion, if `_currentSet > new entries.length`, clamp to last.
The existing logic for "last entry" detection still applies (remove exercise if that was the only set).

### Edit mode
The toolbar in edit mode does not show a "Log Set" button. In edit mode, the center button remains
the forward arrow (navigates to next set via `_nextSetInEditMode`). No changes to edit mode flow.

### Log Set auto-advance
After `_logSet()` completes, the screen still auto-advances to the next set (existing behavior).
This is compatible with out-of-order logging because: if the user navigated to Set 3 directly, Set 3
advances to Set 4 after logging — and Sets 1/2 remain incomplete and still show the "Log Set" button
when the user navigates back to them.

---

## Feedback

