# Feature: Round Auto-Expiry Active-Round Lock Fix

## Overview
When a round timer is logged via Log Set, the next round can be started normally. When a round timer expires and is auto-logged, the app still reports an active round running and blocks starting the next round. This plan fixes round auto-expiry state cleanup so the next round is available to start, but does not auto-start. Additionally, the rest timer must start immediately on auto-expiry (same as manual Log Round).

## Requirements
- Auto-expired round logging must clear active-round state the same way manual Log Set does
- After auto-expiry, next round must be startable
- Next round must not auto-start
- Rest timer must start immediately on round auto-expiry (same as manual Log Round)
- Scope is round timers only
- Count-up timed efforts remain explicit manual-log flows
- No UI/copy/settings changes

## Acceptance Criteria
- [x] Auto-expired round logging clears active-round state
- [x] User can start next round immediately after auto-expiry logging
- [x] Next round does not auto-start
- [x] Manual Log Set and auto-expiry are equivalent for round finalization state
- [x] Rest timer starts immediately on round auto-expiry (not deferred to Log Round tap)
- [x] Navigating forward after auto-expiry does not create a duplicate rest record
- [x] Count-up timed efforts still require manual log
- [x] Regression tests for this bug pass

## Scenarios
- Round start -> timer zero -> auto-log -> next round start succeeds without active-round error
- Manual Log Set and auto-expiry round finalization produce equivalent active-round cleanup
- Count-up timed effort flow remains manual-log only

## Iteration 1
### DB Changes
- None

### Backend Changes
- None

### Frontend Changes
- Round timer lifecycle state-finalization parity between manual log and auto-expiry paths in session timer/screen code
- Round active-state cleanup sequencing fix
- Timer/session regression tests

### Implementation Steps
1. [x] Diff manual Log Set round-completion path vs auto-expiry path and identify missing active-state cleanup
2. [x] Extract shared round-finalization helper or invoke existing shared finalization logic from auto-expiry
3. [x] Ensure cleanup executes before next-round availability checks/actions
4. [x] Preserve explicit control: next round becomes startable but does not auto-start
5. [x] Add regression test for auto-expiry then start-next-round success
6. [x] Add parity test for manual vs auto-expiry round state cleanup
7. [x] Add guard test that count-up timed efforts remain manual-log only
8. [x] Run targeted session/timer tests
9. [ ] Validate on connected iOS device; validate Android if device available, else document gap

## Iteration 2
### DB Changes
- None

### Backend Changes
- None

### Frontend Changes
- `WorkoutSessionTimerMixin._handleEffortTimerExpired`: on round expiry, call `recordRestStart(effortId, entryIndex + 1)` and `scheduleRestPings` immediately; add logKey to `_loggedSetKeys` so subsequent "Log Round" tap takes the early-return path without creating a second rest record
- `WorkoutSessionTimerMixin` abstract deps: add `Set<String> get _loggedSetKeys;`
- `_WorkoutSessionScreenState._loggedSetKeys`: add `@override` annotation

### Implementation Steps
1. [x] Add `Set<String> get _loggedSetKeys;` to mixin abstract dependencies
2. [x] Add `@override` to `_loggedSetKeys` field in `_WorkoutSessionScreenState`
3. [x] In `_handleEffortTimerExpired` round branch: add `_loggedSetKeys.add(timerKey)`, `recordRestStart(effortId, entryIndex + 1)`, `scheduleRestPings`
4. [x] Add S-BUG-004 regression test: rest record exists immediately after auto-expiry, not after Log Round tap
5. [x] Run all tests in `round_auto_expiry_test.dart` — 5/5 pass

## Iteration 3
### DB Changes
- None

### Backend Changes
- None

### Frontend Changes
- `WorkoutSessionTimerMixin`: add `Future<void> _logSet();` to abstract dependencies
- `_handleEffortTimerExpired` (round branch): call `unawaited(_logSet())` when `entryIndex == _currentSet - 1` to auto-advance to the next set after auto-expiry
- `_handleEffortTimerExpired` (timed/drill branch): same auto-advance guard — `_logSet()` runs full log flow (starts rest timer, advances) since the logKey is not pre-added to `_loggedSetKeys` for timed/drill
- Guard condition `entryIndex == _currentSet - 1` prevents `_drainStaleInProgressKeys` from accidentally advancing the wrong set when a user navigates forward before the tick fires

### Implementation Steps
1. [x] Add `Future<void> _logSet();` to mixin abstract dependencies
2. [x] Add guarded `unawaited(_logSet())` to round branch of `_handleEffortTimerExpired`
3. [x] Add guarded `unawaited(_logSet())` to timed/drill branch of `_handleEffortTimerExpired`
4. [x] Update S-BUG-001 test: remove forward arrow tap (auto-advance makes it redundant)
5. [x] Update S-BUG-001b test: clarify that drain guard skips auto-advance for stale keys
6. [x] Update S-BUG-004 test: assert "Start" visible immediately after auto-expiry
7. [x] Run `round_auto_expiry_test.dart` (5/5 pass)
8. [x] Run broader suite: `screen_widget_test.dart`, `session_finish_timers_test.dart`, `interaction_flow_test.dart`, `session_detail_set_count_test.dart` (236 pass, 0 fail)

## Progress
- [x] Implement round auto-expiry active-state cleanup parity
- [x] Verify next round startability without auto-start
- [x] Add regression tests for active-round lock bug
- [x] Confirm count-up timed efforts unchanged
- [x] Rest timer starts on auto-expiry (Iteration 2)
- [x] No duplicate rest record on forward navigation after auto-expiry (Iteration 2)
- [x] Auto-advance to next set on round/timed/drill auto-expiry (Iteration 3)
- [x] Manual Log Set/Round already auto-advances (confirmed unchanged)
- [ ] Validate on physical iOS device
- [ ] Validate on physical Android device (or document unavailability)

## Feedback

- Physical iOS device launch was not attempted in this environment; on-device validation remains pending.
- No Android device is available in this environment; Android validation is pending.

## Handoff

### Doc Updates
- docs/navigation_and_screens.md: no update required (no route/screen/constructor dependency changes)
- docs/state_management.md: updated to document round auto-expiry cleanup path in `WorkoutSessionTimerMixin`
- docs/widget_catalog.md: no update required (no new reusable widgets)

### Global Conventions Check
- Units + canonical storage: N/A (no unit conversion/storage logic changed)
- Theme tokens only: N/A (no visual styling changes)
- Effort-kind drives analytics: N/A (no analytics/progress classification changes)
- Timestamps are source data: PASS (timer completion still derives from persisted wall-clock timing)
- Reuse the canonical owner: PASS (fix stays inside `WorkoutSessionTimerMixin` active-round ownership)
- Instrument panel, not influencer: N/A (no UX/copy/interaction style changes)

### Validation
- Targeted tests: `test/round_auto_expiry_test.dart` passing (3/3)
- Physical iOS validation: pending
- Physical Android validation: pending (device unavailable)

