# Feature: Log-food thumbnail contrast and state dimming

## Overview
Inset the image inside the existing log-food thumbnail toggle while preserving the 40 dp visible container and 48 dp tap target. Dim the unlogged thumbnail content and animate the dimming in lockstep with the existing outline transition. Image precedence and all other toggle behavior remain unchanged.

## Requirements
- Preserve the existing thumbnail container, tap target, row height, border, badge, and press feedback dimensions/behavior.
- Render all thumbnail sources inside a consistent inset area using cover cropping and no distortion.
- Add an animated unlogged dimming overlay; logged content has no overlay.
- Use existing theme and animation tokens; no data or repository changes.

## Acceptance Criteria
- [ ] Outer thumbnail, tap target, and row dimensions remain unchanged.
- [ ] A consistent app-surface ring separates outline and image on all sides.
- [ ] Inset content fills its area with cover cropping and no distortion.
- [ ] Shipped, user-picked, and placeholder sources receive identical inset treatment.
- [ ] Unlogged content is dimmer; logged content has no overlay.
- [ ] Overlay transition uses the existing duration and curve and completes with border transition.
- [ ] Existing outline, badge, and press behavior remain unchanged.
- [ ] Existing image precedence tests continue to pass.

## Scenarios
### S-001: Inset all thumbnail sources
- Trigger: A log-food row renders with any thumbnail source.
- Precondition: The row has a shipped photo, user photo, or placeholder.
- Flow: The fixed-size toggle renders its content inside a uniform inset.
- Expected outcome: The outer footprint is unchanged, and a surface-colored ring is visible on every side.
- Edge case of: none

### S-002: Dim unlogged thumbnail
- Trigger: A food is unlogged or toggled.
- Precondition: The thumbnail is rendered in the log-food list.
- Flow: Unlogged content shows a dim overlay; logging removes it; unlogging restores it with the same animation tokens as the outline.
- Expected outcome: Logged content is full strength and unlogged content remains identifiable but visibly dimmer.
- Edge case of: none

## Iteration 1
### DB Changes
None.
### Backend Changes
None.
### Frontend Changes
Update `_ThumbToggle` in `log_food_row.dart`; add focused widget tests covering geometry, inset, overlay, animation tokens, and source consistency.
### Implementation Steps
1. Add red tests for the fixed outer/tap dimensions, inset geometry, and state overlay.
2. Implement the inset surface ring and animated dimming layer.
3. Run targeted and full tests, analyze, and review documentation impact.

## Progress
- [x] Phase 0: plan and requirements
- [x] Phase 2: add failing behavior tests
- [x] Phase 2: implement inset and dimming
- [x] Phase 2: verify tests and analysis
- [x] Phase 3: review acceptance criteria and architecture

## Feedback

### Phase 0 Complete ✓

### Phase 2 Complete ✓

### Phase 3 Complete ✓
