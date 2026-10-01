# Feature: Resistance Framework Extra-Weight Visibility

## Overview
Fix live workout metric rendering so extra-weight is not shown for resistance (`set`) efforts. Resistance must always render exactly reps + weight, while timed, drill, and round frameworks keep their current extra-weight behavior.

## Requirements
- Remove extra-weight control from resistance (`set`) effort rendering entirely.
- Keep resistance reps + weight controls unchanged.
- Keep timed, drill, and round extra-weight controls unchanged, including collapsed-by-default behavior.
- Rendering decision must be based only on `effortKind` (framework), not exercise capabilities.
- Do not change logging, persistence, or set-to-set carry-forward behavior.
- Fix the reported case: hold-type exercise tracked as resistance must show only reps + weight.

## Acceptance Criteria
- [x] A `set` effort shows reps and weight only, with no "Weight adjustment" control for any exercise.
- [x] The same exercise tracked as `drill` still shows the extra-weight control (collapsed by default).
- [x] `timed` and `round` efforts still show extra-weight control exactly as before.
- [x] Extra-weight visibility is determined solely by `effortKind`, not by exercise capabilities.
- [x] Logging, persistence, and carry-forward behavior remain unchanged for all frameworks.
- [x] Existing resistance logging/persistence tests still pass unchanged.

## Scenarios
[Populated by Developer agent during Phase 0]

## Iteration 1
### Analysis
Current `set` UI rendering in `workout_session_detail_view.dart` checks exercise capabilities (`load`) and shows the extra-weight section when the exercise is non-load. This creates two weight-related inputs in resistance for some exercises and violates framework-driven UI behavior.

### Questions (if any)
1. None. Scope is explicit and limited to render gating + tests.

### DB Changes
- None.

### Backend Changes
- None expected for data handling, schema, repository, or state API.
- Validate that no state-layer logic is modified beyond what is required for render behavior tests.

### Frontend Changes
1. Update resistance (`set`) branch in `lib/features/session/workout_session_detail_view.dart` to always omit extra-weight UI.
2. Remove capability-based condition (`hasLoad`/exercise capability checks) from set metric rendering.
3. Keep timed/drill/round branches unchanged.

### Test Changes
1. Add render test in `test/screen_widget_test.dart` proving `set` shows no "Weight adjustment" for:
   - a load-capable exercise tracked as `set`
   - a non-load exercise tracked as `set`
2. Ensure/keep render coverage that `drill`, `timed`, and `round` still render extra-weight control as today.
3. Update/remove any assertion that expects extra-weight to appear for `set` non-load exercises.
4. Re-run resistance logging/persistence tests (notably set-entry persistence paths) to confirm no value-handling regressions.

### Implementation Steps
1. [ ] Remove set-framework extra-weight render block from `workout_session_detail_view.dart`.
2. [ ] Remove now-unused local variables/import dependencies tied to set extra-weight visibility checks.
3. [ ] Add/adjust widget tests for set/no-extra-weight behavior across load-capable and non-load exercises.
4. [ ] Confirm existing timed/drill/round extra-weight widget tests still pass.
5. [ ] Update or delete stale tests in `test/state_test.dart` and/or `test/screen_widget_test.dart` that encode capability-based set extra-weight behavior.
6. [ ] Run targeted tests for session screen + set persistence/logging behavior.

## Progress
- [x] UI render gating updated for `set`
- [x] Capability-based condition removed from `set` path
- [x] New/updated `set` widget tests added
- [x] Timed/drill/round extra-weight tests verified unchanged (all pass)
- [x] Stale bug-encoding tests: none existed that explicitly asserted extra-weight on set; state persistence test retained (data layer unchanged)
- [x] Targeted regression tests passed (374 tests, 0 failures)

## Feedback
[None]
