# Feature: remove-auto-finish-prompt

## Overview
Remove the automatic finish prompt triggered after logging the last planned set so logging flow is never interrupted. Finishing must remain an explicit user action through the existing Finish Workout button.

## Requirements
- Logging any set, including the final planned set, must never show a finish prompt.
- Do not change Finish Workout button behavior, finish flow, save flow, summary flow, or discard flow.
- Behavior must be consistent across modalities (resistance, cardio, rounds, isometric) and across routine-started and free sessions.
- Re-logging or editing the last set must not show any finish prompt.
- Update tests that currently assert the old auto-prompt behavior.

## Acceptance Criteria
- [x] Logging the final set of a session produces no dialog, bottom sheet, or prompt of any kind.
- [x] Finish Workout button remains the only way to finish a session and behaves exactly as before.
- [x] Behavior is identical across all modalities and for both routine-started and free sessions.
- [x] Re-logging or editing the last set produces no prompt.
- [x] Existing finish-via-button tests pass unchanged.
- [x] `test/session_finish_timers_test.dart` does not depend on the removed auto-prompt behavior.

## Scenarios
### S-001: Log final planned set (no interruption)
- Trigger: User logs the last planned set for the current exercise/session.
- Precondition: Session is active and at least one remaining planned set existed before the action.
- Flow: User logs set -> state updates -> UI remains on logging flow.
- Expected outcome: No finish prompt appears; session remains active.
- Edge case of: none

### S-002: Re-log or edit last set (no interruption)
- Trigger: User re-logs or edits the last logged/planned set.
- Precondition: Session is active and last set already exists.
- Flow: User updates set entry -> state updates -> UI remains in session.
- Expected outcome: No finish prompt appears; session remains active.
- Edge case of: S-001

### S-003: Finish explicitly via button (unchanged)
- Trigger: User presses Finish Workout button.
- Precondition: Session is active.
- Flow: Existing finish action executes.
- Expected outcome: Finish behavior, persistence, and summary navigation remain unchanged.
- Edge case of: none

## Iteration 1
### DB Changes
1. [x] No schema, migration, or repository interface changes.

### Backend Changes
1. [x] Remove/disable the auto-finish-prompt trigger path invoked after logging the final planned set.
2. [x] Ensure set logging completion path always returns to normal active-session state without finish prompt side effects.
3. [x] Preserve existing explicit finish entry points exclusively behind Finish Workout action.

### Frontend Changes
1. [x] Remove any dialog/bottom-sheet invocation tied to "last set logged" events.
2. [x] Keep all existing Finish Workout UI affordances unchanged.

### Implementation Steps
1. [x] Locate where session screen/state detects "last planned set logged" and currently triggers finish prompt.
2. [x] Delete or short-circuit only the prompt invocation, keeping set logging and progression intact.
3. [x] Verify no prompt path remains for re-log/edit flows of final set.
4. [x] Update or replace tests asserting old auto-prompt behavior to assert no prompt.
5. [x] Add a test validating last-set logging advances state without any finish dialog.
6. [x] Run finish-flow regression tests to confirm Finish Workout behavior remains unchanged.
7. [x] Validate `test/session_finish_timers_test.dart` remains independent of auto-prompt behavior.

## Progress
- [x] Remove auto prompt trigger on final set log
- [x] Keep finish flow button-only and unchanged
- [x] Update/invert outdated prompt assertions
- [x] Add no-prompt regression test for last-set logging
- [x] Confirm finish-via-button tests still pass
- [x] Confirm `session_finish_timers_test.dart` has no auto-prompt dependency

## Test Log
- Red (before implementation): `test/interaction_flow_test.dart` new tests failed because `Workout Complete` dialog appeared.
- Green (after implementation):
	- `test/interaction_flow_test.dart` (targeted new tests): 6 passed
	- `test/session_finish_timers_test.dart`: 7 passed
	- `test/interaction_flow_test.dart` (full file): 56 passed

## Scenario Coverage Map
- S-001 (log final planned set, no interruption):
	- `test/interaction_flow_test.dart` — `logging final set does not show finish prompt and keeps session active`
	- `test/interaction_flow_test.dart` — `logging final interval does not show finish prompt`
	- `test/interaction_flow_test.dart` — `logging final round in sports modality does not show finish prompt`
	- `test/interaction_flow_test.dart` — `routine-started drill session logging final hold does not show finish prompt`
- S-002 (re-log/edit last set, no interruption):
	- `test/interaction_flow_test.dart` — `re-visiting already-logged final set does not show finish prompt`
	- `test/interaction_flow_test.dart` — `editing last set in edit mode does not show finish prompt`
- S-003 (explicit finish via button unchanged):
	- `test/session_finish_timers_test.dart` — `Finish workout finalizes active timed entries and session`
	- `test/session_finish_timers_test.dart` — `Finish workout finalizes active round and sets endedAtMs`

## Handoff Summary — Developer, June 5, 2026

### Implementation
- Removed automatic completion prompt invocation from the final-entry logging path in `WorkoutSessionScreen`.
- Kept explicit finish flow unchanged (`Finish Workout` button -> existing confirmation -> existing finish sequence).

### Doc Updates
- `docs/navigation_and_screens.md` — no update required (no route/screen/dependency changes)
- `docs/state_management.md` — no update required (no state API changes)
- `docs/widget_catalog.md` — no update required (no widget API changes)
- `docs/data_models.md` — no update required (no model/schema changes)
- `docs/db_integration.md` — no update required (no repository interface/storage changes)

### Global Conventions Check
- Units + canonical storage: N/A (no unit handling changes)
- Theme tokens only: N/A (no styling changes)
- Effort-kind drives analytics: N/A (no analytics/progress logic changes)
- Timestamps are source data: N/A (no timestamp-source behavior changes)
- Reuse the canonical owner: PASS (existing `WorkoutState`/repository pathways retained)
- Instrument panel, not influencer: PASS (removed logging interruption, preserved explicit finish intent)

### Tested On
- [x] Free session (set/timed) no-prompt logging path
- [x] Sports modality (round) no-prompt logging path
- [x] Isometric routine-started session (drill) no-prompt logging path
- [x] Finish-via-button regression suite unchanged and green

### Phase 2 Complete ✓
Implementation done. All Phase 0 tests green. Ready for Code Reviewer.

## Feedback
### Code Reviewer - June 5, 2026

Implementation is functionally correct for the core prompt-removal path, but this review cannot approve yet due checklist gaps.

Required follow-up before approval:
1. Add scenario-mapped test coverage for S-002 (re-log and edit of last set) so the scenario register has explicit passing tests, not only code-path inference.
2. Add coverage (or explicit evidence) for acceptance-criteria parity across all modalities and session origins (routine-started + free sessions). Current tests assert set + timed only.
3. Add a handoff summary section with a complete `Doc Updates` block that explicitly states status for:
	- `docs/navigation_and_screens.md`
	- `docs/state_management.md`
	- `docs/widget_catalog.md`
	- `docs/data_models.md`
	- `docs/db_integration.md`

Once these are addressed, re-run reviewer checks for scenario register mapping and doc hygiene.

Resolution: Addressed in this iteration via scenario-mapped tests, parity coverage, and the `Handoff Summary` + `Doc Updates` sections above.
