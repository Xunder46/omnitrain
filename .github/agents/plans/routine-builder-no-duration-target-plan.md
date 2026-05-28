# Feature: Routine Builder — Remove Duration Editor for Cardio and Isometric Exercises

## Overview
In the routine builder detail view, cardio (`effortKind == 'timed'`) and
isometric/stretching (`effortKind == 'drill'`) efforts currently expose a duration
target editor. That editor is misleading in this context: live cardio and drill
timers are count-up timers that always begin at zero, so any routine-side duration
target is not applied when the routine becomes a session. The routine builder should
stop exposing a duration target for these two effort kinds while preserving set
count controls, drill extra-weight editing, sports round-duration editing, and all
resistance behavior.

## Analysis
This is a narrowly scoped routine-builder UI correction aligned with the product
principle that templates should only expose values that genuinely affect execution.
The control point is `RoutineSetupScreen._buildMetricWidget`, and the main risk is
accidentally removing legitimate editors for `round` or `set` efforts or weakening
routine-to-session creation for timed/drill entries. Repo docs confirm the screen is
the correct ownership boundary and that live timed/drill efforts start from zero,
while round efforts keep a real preset duration.

## Questions
None.

## Requirements
- Remove the duration target editor from routine setup for `timed` cardio efforts.
- Remove the duration target editor from routine setup for `drill` isometric/stretching efforts.
- Keep timed/drill set-count controls unchanged so interval/hold counts still work.
- Keep the drill extra-weight editor unchanged.
- Keep the timed extra-weight editor when the exercise has an extra-weight target.
- Keep sports/round duration editing unchanged.
- Keep resistance reps and weight editors unchanged.
- Confirm routine-to-session creation still succeeds for timed/drill efforts without a duration target.
- Do not change live workout behavior, repository interfaces, model classes, or state APIs.

## Acceptance Criteria
- [ ] In routine setup, a `timed` cardio effort shows no duration editor and still shows interval-count controls.
- [ ] In routine setup, a `drill` isometric effort shows no duration editor, still shows the extra-weight editor, and still shows hold-count controls.
- [ ] In routine setup, a `round` sports effort still shows an editable round-duration value.
- [ ] In routine setup, a `set` resistance effort still shows reps and weight editors.
- [ ] Building or starting a routine containing timed and/or drill efforts succeeds with the expected number of intervals/holds, and those timers start at zero.

## Scenarios
- Timed effort with no extra-weight target renders no metric editor in routine detail view.
- Timed effort with an extra-weight target renders only the extra-weight editor.
- Drill effort renders only the extra-weight editor.
- Round effort remains unchanged and still renders the round-duration editor.
- Set effort remains unchanged and still renders reps and weight editors.
- Routine-to-session conversion preserves timed/drill entry counts without requiring a duration target.

## Iteration 1
### DB Changes
None.

### Backend Changes
None. No schema, repository, model, or state-method changes are expected.

### Frontend Changes
- `lib/features/routine/routine_setup_screen.dart`
- `test/screen_widget_test.dart`

### Implementation Steps
1. [ ] Update the `timed` branch in `RoutineSetupScreen._buildMetricWidget` so it no longer reads or writes `MetricIds.duration`.
2. [ ] Preserve timed extra-weight rendering only when an extra-weight target exists; otherwise render no metric editor for the timed case.
3. [ ] Update the `drill` branch in `RoutineSetupScreen._buildMetricWidget` so it only renders the extra-weight editor and no longer reads or writes `MetricIds.duration`.
4. [ ] Leave the `round`, `set`, and default branches unchanged.
5. [ ] Add widget coverage proving timed and drill efforts no longer render duration editors while their set-progress labels remain intact.
6. [ ] Add or confirm widget coverage proving round duration and resistance reps/weight editors remain intact.
7. [ ] Add or confirm a routine-to-session test proving timed/drill efforts still build correctly with the expected entry counts and zeroed startup timers.
8. [ ] Run focused tests for the touched routine builder and any touched routine-session path.

## Iteration 2
### DB Changes
None.

### Backend Changes
None. The follow-up concern is verification depth, not data-layer scope.

### Frontend Changes
- Reconcile the implementation against the required scenario matrix in `test/screen_widget_test.dart`.
- Reconfirm the routine-session creation path used by timed/drill efforts.

### Implementation Steps
1. [ ] Verify the `RoutineSetupScreen` test group includes explicit coverage for:
   - timed detail view shows no duration editor
   - drill detail view shows no hold-time editor
   - round detail view still renders round-duration editor
   - timed no-extra-weight branch renders no metric editor
   - routine-to-session conversion succeeds for timed and drill efforts
2. [ ] If any of the above tests are missing or regressed, restore them before widening scope.
3. [ ] Ensure the routine-to-session test asserts timed/drill `setCount` and zeroed startup timer state rather than only checking creation success.
4. [ ] Re-run `flutter test test/screen_widget_test.dart` and any narrowly relevant routine/session test if implementation changes touch the conversion path.

## Files Affected
- `lib/features/routine/routine_setup_screen.dart`
- `test/screen_widget_test.dart`

## Notes
- Repo docs currently describe timed/drill routine defaults as copying duration targets. If the implementation already diverged or this feature ships now, the developer should check whether the routine docs need a wording update for accuracy.
- This is a Developer handoff only. No DBA phase is required.
- The cheapest validation path is the routine screen widget test file, followed by the specific routine-session conversion test.

## Progress
- [x] Remove timed duration editor from routine detail rendering
- [x] Remove drill duration editor from routine detail rendering
- [x] Preserve timed extra-weight-only behavior
- [x] Preserve drill extra-weight behavior
- [x] Preserve round duration editor behavior
- [x] Preserve resistance reps and weight behavior
- [x] Add or confirm timed/drill no-duration widget tests
- [x] Add or confirm round and resistance regression coverage
- [x] Add or confirm routine-to-session conversion coverage for timed/drill
- [x] Run focused test validation

### Phase 2 Complete ✓
Implementation matched the plan and the remaining review gaps were resolved on May 27, 2026. Re-verified with focused routine widget tests; prior same-day full `flutter test` and `flutter build web` remained green.

## Doc Updates
- docs/navigation_and_screens.md: no update required
- docs/state_management.md: no update required
- docs/widget_catalog.md: no update required
- .github/agents/docs/my_routines.md: updated routine-builder metric-editor and smart-default descriptions for timed/drill efforts

## Feedback
None.
