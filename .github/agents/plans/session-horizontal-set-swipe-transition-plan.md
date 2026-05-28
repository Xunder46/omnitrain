# Feature: Session Detail — Horizontal Set Swipe Direction and Slide Transition

## Overview
In the live workout session detail view, horizontal set navigation is inverted and changes sets instantly. Swiping right currently advances and swiping left goes back, which conflicts with the natural left-to-advance / right-to-go-back convention. The same set changes also need a brief horizontal slide so swipe and arrow navigation feel consistent and give clear feedback.

## Requirements
- Swap the horizontal swipe mapping so leftward swipe advances and rightward swipe goes back.
- Keep the existing forward/back actions themselves unchanged.
- Add a brief horizontal slide for every set change triggered by swipe or previous/next arrows.
- Make the outgoing set slide in the direction of travel and the incoming set slide from the opposite side.
- Keep vertical exercise swipes unchanged and unanimated.
- Keep vertical value-adjust drags unchanged.
- Do not change set boundary behavior beyond the corrected direction.

## Scenarios
### S-001: Left swipe advances set
- Trigger: User swipes left on the live session detail view.
- Precondition: Current exercise has at least two sets or entries to navigate between.
- Flow: The swipe is recognized as the forward action.
- Expected outcome: The next set becomes current and the content slides horizontally.
- Edge case of: none

### S-002: Right swipe goes back
- Trigger: User swipes right on the live session detail view.
- Precondition: Current set is not the first navigable set.
- Flow: The swipe is recognized as the back action.
- Expected outcome: The previous set becomes current and the content slides horizontally.
- Edge case of: none

### S-003: Arrow navigation matches swipe motion
- Trigger: User taps the previous or next set arrows.
- Precondition: Session detail view is open.
- Flow: The same set-navigation action as the corresponding swipe is invoked.
- Expected outcome: The set changes with the same horizontal transition as the matching swipe.
- Edge case of: none

### S-004: Vertical value drag remains isolated
- Trigger: User drags vertically on a value editor.
- Precondition: A draggable metric editor is visible.
- Flow: The value adjusts via the existing vertical gesture handling.
- Expected outcome: The value changes, and no set navigation or horizontal slide occurs.
- Edge case of: none

### S-005: Vertical exercise swipe remains unchanged
- Trigger: User swipes vertically between exercises.
- Precondition: Multiple exercises are available in the session.
- Flow: The existing vertical gesture handler switches exercises.
- Expected outcome: Exercise navigation behaves exactly as before, without new animation.
- Edge case of: none

### S-006: Horizontal transition lands on the correct set
- Trigger: User changes sets by swipe or arrow.
- Precondition: The detail view is open on a multi-set exercise.
- Flow: The set content is animated to the next or previous set.
- Expected outcome: After the transition completes, the newly current set's content is shown.
- Edge case of: none

## Iteration 1
### DB Changes
None.

### Backend Changes
None.

### Frontend Changes
- `lib/features/session/workout_session_detail_view.dart`
- `test/session_toolbar_rework_test.dart`

### Implementation Steps
1. [x] Swap the horizontal drag mapping so leftward swipes call the forward/advance action and rightward swipes call the back action.
2. [x] Add a brief horizontal `AnimatedSwitcher` transition around the set-specific detail content keyed by the current exercise/set.
3. [x] Make the outgoing and incoming motion direction depend on whether the navigation is forward or backward.
4. [x] Keep vertical exercise swipes and vertical drag value editors unchanged.
5. [x] Update the existing arrow/swipe coverage to reflect the corrected direction.
6. [x] Add interaction coverage proving the arrow actions and swipes produce the same set navigation.
7. [x] Add coverage proving vertical metric drags still adjust values and do not change sets.
8. [x] Add coverage proving vertical exercise swipes remain unchanged.
9. [x] Add coverage proving the transition settles on the correct current set content.
10. [x] Run the narrow session widget tests for validation.

## Progress
- [x] Swap horizontal swipe direction
- [x] Add horizontal set slide transition
- [x] Preserve vertical drag behavior
- [x] Add/update swipe and arrow tests
- [x] Add transition completion coverage
- [x] Run focused validation

### Phase 2 Complete ✓
Implementation done. Focused session swipe/transition tests are green.

## Doc Updates
- .github/agents/docs/navigation_and_screens.md: no update required (no new screen, route, or constructor dependency changes)
- .github/agents/docs/state_management.md: no update required (no new state class/method API changes)
- .github/agents/docs/widget_catalog.md: no update required (no reusable widget API changes)
- .github/agents/docs/data_models.md: no update required (no model or schema changes)
- .github/agents/docs/db_integration.md: no update required (no DB or repository changes)

## Feedback
None.
