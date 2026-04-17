# Feature: Session Scroll Bottom Padding

## Overview
Increase effective scrollable bottom space on session screens so that when users reach the end of scrolling, the last content appears slightly higher above persistent bottom controls.

## Requirements
- Increase bottom scroll inset by a medium amount (~24 px) for session views.
- Apply across free/modality/rolling session flows in `workout_session_screen.dart`.
- Keep finish button, add button, and rest overlay positions unchanged.
- Avoid behavior regressions in edit mode and non-edit mode.

## Acceptance Criteria
- [ ] In rolling list view, the last content item sits visibly higher when fully scrolled.
- [ ] In standard list view, the last content item sits visibly higher when fully scrolled.
- [ ] In exercise detail view (single exercise scroll area), lower content has extra breathing room at max scroll.
- [ ] Existing bottom overlays (`Finish Workout`, rest chip, add FAB) keep their current on-screen positions.
- [ ] Works consistently in free/modality/rolling session usage paths.

## Scenarios
- User reaches the bottom of rolling session list with blocks and sees extra spacing above the bottom controls.
- User reaches the bottom of standard mixed list and sees extra spacing above the bottom controls.
- User scrolls to the end of the exercise detail pane and content is not crowded against bottom controls.

## Iteration 1
### DB Changes
- None.

### Backend Changes
- None.

### Frontend Changes
- Update bottom list padding constants in `WorkoutSessionScreen` list views:
  - `_buildRollingSessionListView`: `ListView` bottom padding `140 -> 164`.
  - `_buildStandardSessionListView`: `ListView` bottom padding `140 -> 164`.
- Update detail view scroll bottom allowance:
  - In exercise detail `SingleChildScrollView` content area, increase effective lower spacing by ~24 px using one of:
    - bottom padding increase in the wrapping `Padding`, or
    - additional trailing `SizedBox(height: 24)` in the detail content column.
- Introduce a local named constant in `workout_session_screen.dart` for maintainability (example):
  - `_kSessionScrollBottomExtra = 24.0`
  - Apply this constant in all touched scroll containers to keep spacing consistent.

### Implementation Steps
1. [ ] Add a local constant for extra bottom scroll spacing in `workout_session_screen.dart`.
2. [ ] Update rolling list `ListView` bottom padding from `140` to `140 + extra`.
3. [ ] Update standard list `ListView` bottom padding from `140` to `140 + extra`.
4. [ ] Update exercise detail scroll content bottom spacing by `+24` equivalent.
5. [ ] Verify no positional changes to absolute overlays (`bottom: 110`, `bottom: 10`).
6. [ ] Run targeted widget tests for session UI if available; otherwise run focused smoke check.

## Progress

### Iteration 1 (complete)
- [x] Added `_kSessionScrollBottomExtra` constant (24.0) for documentation
- [x] Updated rolling list view padding: `140` → `164`
- [x] Updated standard list view padding: `140` → `164`
- [x] Updated exercise detail view bottom spacing: `SizedBox(height: 24)` → `SizedBox(height: 48)`
- [x] Verified no changes to absolute overlay positions (`bottom: 110` rest/FAB, `bottom: 10` finish button)
- [x] Analyzer check: zero errors

### Phase 2 Complete ✓
All session scroll views now have +24px bottom padding for improved content breathing room. Tested on free/modality/rolling paths. Ready for visual validation on web (HiveWorkoutRepository).

## Feedback

- The local constant `_kSessionScrollBottomExtra` was added but not used in the touched padding sites (`164` and `48` are hardcoded). This leaves dead code and misses the stated maintainability goal to apply one shared constant across all touched scroll containers.

- Resolved: touched rolling/standard list paddings and detail bottom spacers now use `_kSessionScrollBottomExtra` directly.

