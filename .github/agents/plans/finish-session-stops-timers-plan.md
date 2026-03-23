# Feature: finish-session-stops-timers

## Overview
Fix session completion semantics so finishing a workout always terminates all active timers and timer-driven state. The current behavior can leave timed entries or rounds effectively still active when the user navigates back, which conflicts with the expectation that Finish Session is terminal for that session.

## Requirements
- Finish Session must stop every active timer path, not only round timers.
- Finish Session must persist active timer-based efforts into terminal states before leaving the session screen.
- Back-navigation from the summary must not allow a finished session to continue counting time.
- The behavior must remain repository-agnostic and work with current web/hive and future sqlite implementations via existing WorkoutRepository APIs.
- No regression to edit mode behavior in WorkoutSessionScreen.

## Iteration 1

### DB Changes (@dba)
1. [ ] No schema changes required.
2. [ ] No repository interface additions required.

### Backend Changes (@developer)
1. [ ] Add a unified session-finalization helper in WorkoutSessionScreen that:
   - Cancels all local UI timers (`_effortTimers`, `_restTimer`, session `_ticker`).
   - Iterates all effort kinds and forces active/paused entries to terminal state via WorkoutState methods.
2. [ ] Extend current pre-finish persistence logic (currently round-focused) to include timed/drill instances:
   - Round: call `endRoundEarly` for `active`/`paused` rounds not already finished.
   - Timed/Drill: call `finishTimedEntry` for `active`/`paused` timed instances not already finished.
3. [ ] Ensure finish flow calls `workoutState.endSession()` at the proper point so session `endedAtMs` is set before navigation settles.
4. [ ] Add a defensive guard in the screen timer tick/update path to no-op when session has `endedAtMs != null`.

### Frontend Changes (@developer)
1. [ ] Update `WorkoutSessionScreen` finish action to use a single deterministic sequence:
   - Freeze UI timers.
   - Persist all active timer-based effort states.
   - End session.
   - Navigate to summary.
2. [ ] Update back-navigation behavior from summary/session flow so returning cannot resume active timer display for a finished session.
3. [ ] Ensure the Finish Session CTA semantics are explicit and consistent with current copy: finishing closes tracking, not pausing.

### Implementation Steps
1. [ ] Audit current `_finishSession()` and `_persistActiveRoundTimers()` in `WorkoutSessionScreen`.
2. [ ] Replace/expand round-only shutdown helper with all-effort shutdown helper (round + timed/drill + rest/session local timers).
3. [ ] Wire all finish entry points (dialog finish buttons and any direct finish paths) to the same shutdown helper.
4. [ ] Call `workoutState.endSession()` exactly once in finish sequence and handle failure path with user-visible error feedback.
5. [ ] Add guard conditions in `_tick()` and `_onEffortTick()` to prevent updates for ended sessions.
6. [ ] Verify edit mode (`editMode == true`) remains unaffected.
7. [ ] Add/adjust widget tests for:
   - Active timed entry + Finish Session -> summary opens, timed entry finished.
   - Active round + Finish Session -> summary opens, round finished/end-early persisted.
   - Press back after finish -> no running timers, no continued elapsed growth.
8. [ ] Run regression smoke tests for skip/log/previous-set flows to ensure no timer lifecycle regressions.

### Acceptance Criteria
- [ ] When user taps Finish Session, all active round/timed/drill timers are stopped and persisted to terminal state.
- [ ] Session receives `endedAtMs` immediately as part of finish flow.
- [ ] Returning/back navigation after finish never shows timer progression for the finished session.
- [ ] Behavior is identical on web (HiveWorkoutRepository) and compatible with future sqlite implementation through existing abstract methods.
- [ ] Edit mode retains existing unsaved-changes behavior and does not run active timers.

### Files Affected
- lib/features/session/workout_session_screen.dart
- lib/state/workout/workout_state.dart
- test/widget_test.dart
- test/session_finish_timers_test.dart

### Notes
- Follow modality timer lifecycle rules documented in modality_based_exercise_ui and modality_tracking.
- Use WorkoutState safety-net methods (`_persistActiveRounds`, `_persistActiveTimedEntries`) as backend consistency guards, but keep UI finish flow deterministic so users see immediate stop behavior.

## Progress
- [x] Confirm root cause and map all finish entry points
- [x] Implement unified timer/session finalization flow
- [x] Add ended-session tick guards
- [x] Add regression tests for finish/back behavior
- [ ] Validate web flow manually and via tests

## Feedback
<!-- Leave empty until a specialist or reviewer adds notes -->

---

@developer - Please proceed with Iteration 1 (Logic/UI) above. No DBA changes are required for this fix.
