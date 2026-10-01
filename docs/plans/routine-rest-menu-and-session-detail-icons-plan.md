# Feature: Routine Rest Menu Removal and Session Detail Icon Size

## Overview
Two small UI corrections in existing surfaces:
- Remove the misleading `Edit Rest` entry from the per-exercise overflow menu in the routine builder, without changing persisted rest data.
- Slightly enlarge the exercise info and notes icons in the live session exercise detail header so they are easier to see and tap.

## Requirements
- In the routine builder overflow menu, hide `Edit Rest` and leave the remaining menu actions unchanged.
- Make the rest edit dialog unreachable from the routine builder UI.
- Do not delete, migrate, or mutate stored `restSeconds` or `restType` values.
- Existing routines with saved rest values must continue to load and save normally.
- Leave rest-ping / rest-notification settings and live-session rest behavior unchanged.
- In the live session exercise detail header, increase the size of the info and notes icons equally.
- Ensure both icon tap targets are at least 44x44.
- Do not move the icons or change their actions.

## Acceptance Criteria
- [ ] The routine-builder per-exercise overflow menu no longer shows `Edit Rest`.
- [ ] `Change Tracking` and `Remove` still appear and still work from the same overflow menu.
- [ ] No routine-builder interaction path opens the `Edit Rest` dialog.
- [ ] A routine with pre-existing `restSeconds` / `restType` values loads and saves without crash, loss, or corruption of those values.
- [ ] Rest-ping / rest-notification settings elsewhere in the app are unaffected.
- [ ] The live session exercise info and notes icons are visibly larger than before and remain equal in size.
- [ ] Each live session icon has a minimum tap target of at least 44x44.
- [ ] Icon positions and on-tap behavior are unchanged.
- [ ] No clipping, overflow, or layout shift occurs on the smallest supported width.

## Scenarios

### S-001: Routine exercise overflow menu without rest editor
- Trigger: User opens the per-exercise overflow menu in `RoutineSetupScreen`.
- Precondition: Routine has at least one exercise card in list view.
- Flow: Open the menu, inspect available actions, choose one of the remaining actions.
- Expected outcome: `Edit Rest` is absent; `Change Tracking` and `Remove` are still present and functional.
- Edge case of: none

### S-002: Existing routine containing saved rest values
- Trigger: User opens an existing routine whose efforts already have `restSeconds` and `restType` set, then saves it again.
- Precondition: Rest data already exists in persisted template data.
- Flow: Load routine for editing, render routine builder, save routine without any rest-edit UI.
- Expected outcome: Screen loads normally, save succeeds, and stored rest values round-trip unchanged.
- Edge case of: S-001

### S-003: Live session header icons remain usable after size bump
- Trigger: User enters the live workout exercise detail view and taps the info and notes icons.
- Precondition: Session detail view is visible.
- Flow: Render header, verify icon size and hit area, tap each icon.
- Expected outcome: Both icons are larger and equal-sized, both remain tappable, and both open their existing destinations.
- Edge case of: none

## Iteration 1
### DB Changes
None.

### Backend Changes
None. No schema, repository, model, or state-method changes are expected.

### Frontend Changes
- [lib/features/routine/routine_setup_screen.dart](/Users/irinakutsenko/Developer/omnitrain/lib/features/routine/routine_setup_screen.dart)
- [lib/features/session/workout_session_detail_view.dart](/Users/irinakutsenko/Developer/omnitrain/lib/features/session/workout_session_detail_view.dart)

### Implementation Steps
1. [ ] In [lib/features/routine/routine_setup_screen.dart](/Users/irinakutsenko/Developer/omnitrain/lib/features/routine/routine_setup_screen.dart), remove the `Edit Rest` popup-menu item from `ExerciseCard` and stop wiring any routine-builder UI path to `onEditRest`.
2. [ ] Keep the `_editRest()` implementation and persisted rest fields intact unless dead-code cleanup is required after the menu removal; do not alter rest persistence behavior.
3. [ ] Confirm the remaining routine-builder overflow actions still invoke the existing `Change Tracking` and `Remove` flows.
4. [ ] In [lib/features/session/workout_session_detail_view.dart](/Users/irinakutsenko/Developer/omnitrain/lib/features/session/workout_session_detail_view.dart), increase both header icon sizes from the current 18 and raise both `IconButton` minimum constraints from the current 36x36 to at least 44x44, keeping both icons identical in size.
5. [ ] Preserve existing icon placement, keys, and handlers for `exercise-info-button` and `exercise-note-button`.
6. [ ] Update or add focused widget coverage in [test/screen_widget_test.dart](/Users/irinakutsenko/Developer/omnitrain/test/screen_widget_test.dart) for the routine-builder overflow menu so it asserts `Edit Rest` is absent, the remaining actions are present, and at least one remaining action is tappable.
7. [ ] Add or extend a routine-state round-trip test in [test/state_test.dart](/Users/irinakutsenko/Developer/omnitrain/test/state_test.dart) to load an effort with pre-existing `restSeconds` / `restType`, save the routine, and confirm those values persist unchanged.
8. [ ] Add or extend focused live-session header tests in [test/exercise_info_sheet_bilateral_test.dart](/Users/irinakutsenko/Developer/omnitrain/test/exercise_info_sheet_bilateral_test.dart) and/or [test/exercise_notes_sheet_test.dart](/Users/irinakutsenko/Developer/omnitrain/test/exercise_notes_sheet_test.dart) to assert the two header icons share the new size, meet the 44x44 minimum tap target, and remain tappable.
9. [ ] Run the narrowest relevant widget/state tests for the touched routine-builder and session-detail surfaces.

## Progress
- [x] Remove misleading `Edit Rest` menu entry from routine builder
- [x] Preserve existing routine rest data round-trip behavior
- [x] Increase live session info icon size and hit target
- [x] Increase live session notes icon size and hit target
- [x] Update routine-builder overflow menu tests
- [x] Update rest-data round-trip test coverage
- [x] Update live session icon size/tapability tests
- [x] Run focused test validation

## Phase 0 Red Test Run
- `flutter test` run completed before implementation.
- New failures were limited to the intended slices:
	- `test/screen_widget_test.dart` routine overflow menu coverage
	- `test/exercise_notes_sheet_test.dart` session detail icon size/hit target coverage
- The rest-data round-trip state test passed red/green-neutral against existing persistence behavior, confirming the implementation risk is UI-only for that slice.

### Phase 2 Complete ✓
Implementation done. All Phase 0 tests green. Ready for Code Reviewer.

## Verification
- `flutter test` — PASS
- Focused tests:
	- `test/screen_widget_test.dart` — PASS
	- `test/state_test.dart` — PASS
	- `test/exercise_notes_sheet_test.dart` — PASS
	- `test/exercise_info_sheet_bilateral_test.dart` — PASS
- `flutter build web` — PASS (existing wasm dry-run warnings from `flutter_timezone_web`, build completed successfully)
- Post-review compliance rerun — PASS
	- Dialog button shapes and routine color-token usage rechecked in `RoutineSetupScreen`
	- Focused feature tests and full suite re-run green

## Doc Updates
- `docs/navigation_and_screens.md` — no update required
- `docs/state_management.md` — no update required
- `docs/widget_catalog.md` — no update required
- `docs/data_models.md` — no update required
- `docs/db_integration.md` — no update required
- `docs/my_routines.md` — updated overflow menu description to remove `Edit Rest`

## Feedback
[No new feedback yet]