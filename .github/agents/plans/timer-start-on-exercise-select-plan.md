# Feature: Timer Starts After First Exercise Selection

## Overview
The global session timer (`_elapsedFormatted`) currently starts counting the moment a session is created —
before the user has even picked an exercise. The user wants the clock to stay at `00:00` until they select
their first exercise, then begin counting from zero at that point.

## Requirements
- On the workout session screen, the elapsed timer shows `00:00` and does not advance until the first
  exercise has been confirmed (i.e., after `addExerciseToSession` succeeds).
- When the first exercise is confirmed, `session.startedAtMs` is reset to `now` so that elapsed time
  is calculated correctly even if the user navigates away and comes back.
- All subsequent exercises (2nd, 3rd, …) must NOT reset the timer.
- Behaviour in edit mode (review of completed sessions) is unchanged.
- Sessions created from routines (`populateSessionFromManifest`) are unaffected because exercises are
  pre-populated before the screen renders; the timer guard (`_exercises.isEmpty`) would be false
  immediately after load.

## Acceptance Criteria
- [ ] Timer displays `00:00` on session screen before any exercise is selected
- [ ] Timer begins counting from `00:00` the moment the first exercise is confirmed
- [ ] Navigating away and back to an in-progress session with at least one exercise shows correct elapsed time
- [ ] A new session that already has exercises (loaded from routine) shows elapsed time immediately
- [ ] No regression in edit mode (frozen timer still works)
- [ ] No regression for per-exercise timers (timed/drill efforts)

## Scenarios
N/A – straightforward UI + state fix, no new user flows.

## Iteration 1

### DB Changes
None. `started_at_ms` column already exists in `training_session`.

### Backend Changes
1. Add `resetSessionTimerStart()` to `SessionCoreLifecycleMethods` in
   `lib/state/workout/session_core_lifecycle.dart`:
   - Guard: return early if `_currentSession == null`.
   - Set `startedAtMs = DateTime.now().millisecondsSinceEpoch`.
   - Persist via `_repository.updateSession(updatedSession)`.
   - Update `_currentSession`, call `_notify()`.

2. Expose `resetSessionTimerStart()` as a one-liner proxy on `WorkoutState`
   (`lib/state/workout/workout_state.dart`).

### Frontend Changes
3. `lib/features/session/workout_session_global_timer.dart` — `_tick()`:
   - Add early-return guard: if `_exercises.isEmpty`, set `_elapsedFormatted = '00:00'` and return.
   - Place the guard immediately after the `session.endedAtMs != null` guard.

4. `lib/features/session/workout_session_screen.dart` — `_addExercise()`:
   - Capture `final isFirstExercise = _exercises.isEmpty;` **before** calling
     `workoutState.addExerciseToSession(...)`.
   - After a successful add (`effortId.isNotEmpty`) and before `_loadExercises()`, if `isFirstExercise`
     is `true`, call `await widget.workoutState.resetSessionTimerStart()`.

### Implementation Steps
- [ ] 1. Add `resetSessionTimerStart()` to `session_core_lifecycle.dart`
- [ ] 2. Add proxy to `workout_state.dart`
- [ ] 3. Add `_exercises.isEmpty` guard in `_tick()` (`workout_session_global_timer.dart`)
- [ ] 4. Call `resetSessionTimerStart()` on first exercise add in `_addExercise()` (`workout_session_screen.dart`)
- [ ] 5. Manual smoke-test: open session, verify `00:00`, add exercise, verify timer starts from `00:00`
- [ ] 6. Run `flutter test` to confirm no regressions

## Progress
- [ ] Add resetSessionTimerStart() to session_core_lifecycle.dart
- [ ] Expose proxy on workout_state.dart
- [ ] Guard _tick() when no exercises yet
- [ ] Reset timer on first exercise add in _addExercise()
- [ ] Manual smoke-test
- [ ] Run tests

## Feedback

