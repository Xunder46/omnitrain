# Feature: resistance-rest-timer-bug

## Overview
Fix the resistance-modality (set-based) rest timer flow so rest consistently appears, keeps running between logged sets, and closes only when the next set is actually logged.

## Requirements
- Rest timer behavior for set-based efforts must match the modality UX contract in workout session docs.
- Logging a real resistance set (reps > 0) must always start a rest window for the next entry.
- Logging the next real set must close the previous rest window before creating the next one.
- Skipped set entries (reps <= 0) must not create or reset rest windows.
- Rest display must remain stable when navigating between sets/exercises and when reopening the session.
- Behavior must remain repository-agnostic and work with current Mock/Hive and future SQLite implementations via existing abstractions.
- Edit mode must not create/reset/close rest windows.

## Iteration 1

## Analysis
**Architectural flaw identified and fixed**: Rest tracking was failing for resistance modality because `_isSetLogged()` used inconsistent criteria:
- **Resistance (set)**: Checked `reps > 0`, which returned true as soon as reps were entered (not on Log Set)
- **Timed/Round**: Checked `state == finished`, only true after explicit workflow completion

This caused resistance sets to be marked "already logged" before the Log Set button was pressed, skipping rest creation entirely.

## Root Cause
In `_updateMetricValue()`, when a user enters reps, it immediately:
1. Persists the value to observations
2. Calls `_loadExercises()` 
3. During reload, `_isSetLogged()` returns true for reps > 0
4. Populates `_loggedSetKeys` with that entry
5. When user clicks "Log Set", it's already in `_loggedSetKeys`, so rest creation is skipped

## Solution
Changed `_isSetLogged()` for set efforts to check **if rest records already exist** instead of just checking reps > 0. This ensures only actual Log Set completions count as "logged".

## Questions (if any)
1. Should the rest overlay be visible after the final set of the final exercise, or only while there is a next actionable entry?
2. For resistance skips (`reps <= 0`), should the existing open rest continue unchanged (current behavior) or should skip explicitly close rest?

## Implementation Plan

### Phase 1: Data Layer (@dba)
1. [ ] No schema changes expected; verify existing `EntryRest` table/serialization paths remain sufficient for resistance flow.
2. [ ] No repository interface additions expected; confirm `getEntryRests`, `createEntryRest`, and `updateEntryRest` semantics are unchanged.
3. [ ] Validate both `MockWorkoutRepository` and `HiveWorkoutRepository` preserve rest ordering/identity for repeated set logs.

### Phase 2: Logic/UI (@developer)
1. [ ] Reproduce bug in `WorkoutSessionScreen` using a resistance session with at least 3 sets and mixed real/skip logs.
2. [ ] Audit `_logSet()` set-kind path to ensure deterministic ordering for:
   - closing prior open rest,
   - persisting current set,
   - starting next rest.
3. [ ] Replace fire-and-forget race-prone rest transitions in set flow with a deterministic sequence (or guarded single-transition helper) so start/end writes cannot conflict.
4. [ ] Verify `_getRestDisplayEntryIndex`, `_hasRestToDisplay`, and `_formatRestElapsedForDisplay` correctly resolve set-kind rest when moving previous/next and crossing exercise boundaries.
5. [ ] Ensure resistance-specific skip behavior does not suppress valid rest display after subsequent real logs.
6. [ ] Preserve modality-agnostic logic so round/timed/drill behavior remains unchanged.
7. [ ] Keep edit mode isolated: no rest mutations when `editMode == true`.

### Phase 3: Testing (@developer)
1. [ ] Add widget test: resistance set log starts rest overlay and elapsed value increments on tick.
2. [ ] Add widget test: logging next resistance set closes prior open rest and starts a new rest for next entry.
3. [ ] Add widget test: skipped resistance set (`reps == 0`) does not create a new rest window.
4. [ ] Add regression test: navigate previous/next around logged sets and ensure rest does not reset unexpectedly.
5. [ ] Add regression test: reload/reopen session state and verify rest elapsed derives from persisted wall-clock timestamps.

### Acceptance Criteria
- [ ] In resistance modality, logging a real set always triggers rest for the next set.
- [ ] Rest display does not disappear or freeze unexpectedly when navigating between sets.
- [ ] Logging the next real set closes the prior open rest and continues with a new rest window.
- [ ] Skipped sets do not create duplicate or reset rest records.
- [ ] Existing round/timed/drill rest behavior remains unchanged.
- [ ] Works on web with current repositories and remains compatible with future SQLite implementation.
- [ ] Edit mode behavior is unchanged.
- [ ] All relevant tests pass.

### Files Affected
- lib/features/session/workout_session_screen.dart
- lib/state/workout/workout_state.dart
- test/session_finish_timers_test.dart
- test/data_tracking_fixes_test.dart
- test/widget_test.dart

### Notes
- Align with modality guidance in `docs/modality_tracking.md` and `docs/modality_based_exercise_ui.md`.
- Keep repository abstractions unchanged unless a verified gap is found during reproduction.
- Prioritize deterministic state transitions over additional UI timers.

## Progress
- [x] Identify architectural flaw in `_isSetLogged()` inconsistency
- [x] Fix logged detection for set efforts (use rest existence, not reps value)
- [x] Implement deterministic rest start/end sequencing
- [x] Add regression tests for resistance rest creation workflow
- [x] Add test asserting rest only created after Log Set (not on reps entry)
- [ ] Validate no regression for round/timed/drill flows (pending local flutter test run)

## Feedback

---

@developer - Please proceed with Iteration 1 (Logic/UI + tests). No DBA schema changes are expected unless reproduction reveals a repository persistence defect.
