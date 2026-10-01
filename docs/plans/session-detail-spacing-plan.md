# Feature: Active Session Detail Spacing Adjustments

## Overview

Apply a narrowly scoped layout refinement to the active session detail screen so the weight adjustment control and bottom control row sit lower. The change must be localized so no unrelated elements on the page shift.

## Requirements

- Move the weight adjustment control lower without shifting the timer, header, or other unrelated content.
- Move the bottom control row lower without shifting the rest of the page layout.
- Preserve current behavior for timed, drill, round, and set interactions.
- Preserve existing button sizes, timer logic, rest overlay behavior, and state transitions.

## Acceptance Criteria

- [ ] The weight adjustment button renders lower than it does now without moving the timer block.
- [ ] The bottom control row renders lower than it does now without changing header, metric, set progress, previous stats, or indicator positions.
- [ ] No timer, logging, rest timer, or navigation behavior changes.
- [ ] The affected files pass analyzer/error checks after the spacing update.

## Scenarios

### S-001: Weight adjustment spacing remains localized
- Trigger: The active session detail view renders an effort entry with a weight adjustment control.
- Precondition: The current entry exposes the weight adjustment UI.
- Flow: Open the active session detail view and render the metric block for the current entry.
- Expected outcome: The weight adjustment control renders lower than before while the timer and metric block remain anchored.
- Edge case of: none

### S-002: Bottom control row spacing remains localized
- Trigger: The active session detail view renders the bottom set controls.
- Precondition: The session contains at least one exercise entry and the detail view is visible.
- Flow: Open the active session detail view and render the bottom navigation/logging control row.
- Expected outcome: The control row renders lower than before without changing the header, metric stack, progress label, previous stats, or set indicator positions.
- Edge case of: none

## Iteration 1
### DB Changes
None.

### Backend Changes
None.

### Frontend Changes
- Adjust the spacing that precedes the weight adjustment section in `lib/features/session/workout_session_detail_view.dart` so that control sits lower while the timer block stays anchored.
- Adjust the lower control row placement in `lib/features/session/workout_session_list_view.dart` by changing only the padding or margin local to the control row, not the surrounding scroll content.

### Implementation Steps
1. [x] Re-read the current `_buildWeightAdjustmentSection()` block in `lib/features/session/workout_session_detail_view.dart` to confirm the latest edits before patching.
2. [x] Increase only the local top spacing inside `_buildWeightAdjustmentSection()` so the weight adjustment control moves downward independently.
3. [x] Lower the bottom set-controls row in `lib/features/session/workout_session_list_view.dart` by adjusting its local container or padding rather than moving the surrounding content stack.
4. [x] Validate with file-level analyzer checks for the touched files.

## Progress
- [x] Developer implementation complete.
- [x] Validation complete.

### Phase 2 Complete ✓
Implementation done. File-level validation clean. Ready for Code Reviewer.

## Iteration 2
### DB Changes
None.

### Backend Changes
None.

### Frontend Changes
- Increase the bottom control row button size in `lib/features/session/workout_session_detail_view.dart` by enlarging the primary CTA height and the circular nav button diameter.
- Increase the timer control play/pause icon size in the timed, round, and drill status rows in `lib/features/session/workout_session_detail_view.dart`.

### Implementation Steps
1. [x] Re-read the current bottom control button builders and timer status icon blocks before patching.
2. [x] Increase the primary bottom button height and corner radius.
3. [x] Increase the circular nav button size to match the taller control row.
4. [x] Increase the play/pause icon size in timed, round, and drill timer controls.
5. [x] Validate with file-level analyzer checks for the touched file.

### S-003: Bottom control buttons render larger
- Trigger: The active session detail view renders the bottom set controls.
- Precondition: The detail view is visible with the bottom control row enabled.
- Flow: Open the session detail view and render the back button, central action button, and forward button.
- Expected outcome: The bottom row buttons render with a larger visual footprint while preserving their existing behavior.
- Edge case of: S-002

### S-004: Timer control icon renders larger
- Trigger: A timed, round, or drill entry renders its timer status control.
- Precondition: The effort type includes the play/pause status icon.
- Flow: Open the detail view on a timed, round, or drill entry and render the timer status row.
- Expected outcome: The play/pause icon renders larger while the timer behavior and labels remain unchanged.
- Edge case of: none

## Progress
- [x] Developer implementation complete.
- [x] Validation complete.

### Phase 2 Complete ✓
Implementation done. File-level validation clean. Ready for Code Reviewer.

## Iteration 3
### DB Changes
None.

### Backend Changes
None.

### Frontend Changes
- Update `_buildSetControls()` in `lib/features/session/workout_session_detail_view.dart` so the `Log Set` button is never rendered when `isLogged` is true.
- Keep control row in logged/edit states as back/forward arrows only.

### Implementation Steps
1. [x] Re-read the current `_buildSetControls()` block before patching.
2. [x] Gate `Log Set` rendering to unlogged live sets only.
3. [x] Validate with file-level analyzer checks for the touched file.

### S-005: Logged set never shows Log Set button
- Trigger: The detail view renders controls for a set where `isLogged` is true.
- Precondition: Current set is already logged.
- Flow: Render `_buildSetControls()` in live mode and edit mode.
- Expected outcome: The row shows navigation arrows only; `Log Set` is absent.
- Edge case of: S-002

## Iteration 4
### DB Changes
None.

### Backend Changes
None.

### Frontend Changes
- Update center control behavior in `lib/features/session/workout_session_detail_view.dart`:
	- Show `LOGGED` label for logged entries.
	- Show `Start` button for timer entries (`timed`, `round`, `drill`) that are `notStarted`.
	- Keep `Log Set` for resistance (`set`) entries that are not logged.

### Implementation Steps
1. [x] Re-read `_buildSetControls()` and timer state helpers.
2. [x] Add center control state selection for logged/timer-not-started/default cases.
3. [x] Add helper widgets for `LOGGED` label and `Start` button, preserving existing row geometry.
4. [x] Validate with file-level analyzer checks for the touched file.

### S-006: Logged entries show LOGGED status
- Trigger: Center controls are rendered for an already logged entry.
- Precondition: `_isSetLogged(...) == true` and not in edit mode.
- Flow: Render active session detail controls.
- Expected outcome: Center slot displays `LOGGED` text label instead of an action button.
- Edge case of: S-005

### S-007: Not-started timer entries show Start action
- Trigger: Center controls are rendered for timer-based entries.
- Precondition: Effort kind is `timed`, `round`, or `drill`; entry state is `notStarted`; not logged.
- Flow: Render active session detail controls.
- Expected outcome: Center slot shows `Start` button that starts the timer via existing timer toggle behavior.
- Edge case of: none

## Progress
- [x] Developer implementation complete.
- [x] Validation complete.

### Phase 2 Complete ✓
Implementation done. File-level validation clean. Ready for Code Reviewer.

## Feedback
