# Feature: Weight Increment Defaults

## Overview
Update all editable weight-style metrics so the default adjustment increment is 0.5 in the displayed unit system. This should apply to both standard weight and extra-weight interactions in workout logging flows, without changing reps, duration, or RPE behavior.

## Requirements
- All weight increment interactions default to 0.5
- Applies to both kg and lbs display modes
- Applies to both weight and extra-weight editors
- Session logging and routine setup stay consistent
- No database or schema changes are required
- No other metric increments are changed

## Acceptance Criteria
- [x] Swiping or dragging weight values changes by 0.5 at a time
- [x] Swiping or dragging extra-weight values changes by 0.5 at a time
- [x] The behavior is the same when the preferred unit is kg
- [x] The behavior is the same when the preferred unit is lbs
- [x] Reps, duration, and RPE increments remain unchanged
- [x] Relevant regression coverage is added or updated

## Scenarios
- User logs a strength set in the session screen and load adjusts in 0.5 steps
- User logs an extra-weight value for timed or drill efforts and it adjusts in 0.5 steps
- User opens routine setup and sees the same 0.5 behavior there because the shared inline metric editor is reused
- Switching preferred weight unit between kg and lbs does not revert the step size to 2.5

## Iteration 1
### Analysis
This is a fast-track UI behavior fix with no schema change, no repository change, and no new state methods. Investigation shows the current root cause is a hardcoded 2.5 increment in the shared inline metric editor used by workout session and routine setup flows.

Verified current evidence:
- [lib/widgets/session/inline_metric_editor.dart](lib/widgets/session/inline_metric_editor.dart) uses 2.5 for both weight and extra-weight drag increments
- Shared usage means one targeted fix should propagate to session and routine screens

### DB Changes
- None

### Backend Changes
- None expected

### Frontend Changes
1. [x] Update the shared weight increment constant in [lib/widgets/session/inline_metric_editor.dart](lib/widgets/session/inline_metric_editor.dart) from 2.5 to 0.5 for weight
2. [x] Update the extra-weight increment in the same shared editor from 2.5 to 0.5
3. [x] Keep duration, reps, and RPE increments unchanged
4. [x] Confirm no secondary editor or duplicate weight-step logic exists elsewhere in the UI
5. [x] Add or update a regression test covering the 0.5 step behavior

### Implementation Steps
1. [x] Reproduce the current 2.5-step behavior in the session flow
2. [x] Change the shared increment values in the inline metric editor
3. [x] Verify the session screen reflects 0.5 changes for weight and extra-weight
4. [x] Verify the routine setup screen reflects the same behavior
5. [x] Run the relevant widget and regression tests

Red-to-green evidence:
- Added interaction tests for weight and extra-weight drag increments
- Red run verified before the fix: expected 10.5/0.5, actual 12.5/2.5
- Green verification after the fix: targeted tests passed and full suite passed

## Progress
- [x] Root cause documented
- [x] Shared increment updated
- [x] Session flow verified
- [x] Routine flow verified
- [x] Regression tests verified

### Phase 2 Complete ✓
Implementation done. All Phase 0 tests green. Ready for Code Reviewer.

## Feedback
[None yet - implementation complete]
