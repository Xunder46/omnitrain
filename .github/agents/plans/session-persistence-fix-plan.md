# Feature: Session Persistence Fix — Silent State Restore

## Overview
Session persistence was planned in `active-session-persistence-plan.md` but the UI layer was never
implemented. When users close the app (OS kill) and reopen it, unfinished sessions are lost because
HomeScreen never checks for dangling sessions on cold start.

**Design**: On cold start, silently restore the session into memory with no dialog or confirmation.
The home screen tile lights up as active (same as if the user just started a session), and the user
taps it to return to their workout. No interruption, no decision required.

See `active-session-persistence-plan.md` → Iteration 2 for the full authoritative plan.

## Requirements
- On cold app start, detect in-progress sessions persisted in Hive
- Silently call `loadHistoricalSession()` — **no dialog, no modal, no confirmation**
- Home screen tile becomes active; user taps it to return to their workout
- Warm resume (app backgrounded, not killed) does NOT trigger the restore
- Multiple dangling sessions → keep most recent, silently clean up older ones
- Malformed session records in Hive are gracefully skipped (no crash)

## Acceptance Criteria
- [ ] `getInProgressSessions()` exists on `WorkoutRepository` interface; returns sessions where `endedAtMs == null` sorted by `startedAtMs` desc
- [ ] `HiveWorkoutRepository.getInProgressSessions()` filters and parses; malformed records are caught and skipped
- [ ] `MockWorkoutRepository.getInProgressSessions()` filters correctly for tests
- [ ] `WorkoutState.checkForInProgressSession()` returns most recent session, deletes older dangling sessions
- [ ] `HomeScreen._resumeCheckDone` flag prevents duplicate restore calls on warm resume
- [ ] Post-frame callback in `HomeScreen.initState` short-circuits when `hasActiveSession == true`
- [ ] On cold start with unfinished session: `workoutState.loadHistoricalSession()` is called silently; no dialog shown
- [ ] After restore, `workoutState.hasActiveSession == true`; the matching home screen tile appears active
- [ ] No modal/dialog code in HomeScreen (any previously added modal code is removed)
- [ ] Cold start with no sessions: nothing happens, home screen is clean
- [ ] All unit tests pass; new widget test confirms silent restore behavior

## Scenarios

### S-001: Cold start — one unfinished session
- Precondition: User starts Cardio session, logs 2 sets, OS kills app
- Trigger: User reopens app
- Flow: `initState` post-frame callback finds session → calls `loadHistoricalSession()` silently
- Expected: Home screen tile for Cardio appears active; no dialog
- Outcome: User taps tile → navigates to WorkoutSessionScreen with session fully restored

### S-002: Cold start — no unfinished sessions
- Precondition: User finished and saved last session normally
- Trigger: User reopens app
- Flow: `checkForInProgressSession()` returns null; callback returns early
- Expected: Normal home screen, no tiles active
- Outcome: User starts a new session as usual

### S-003: Multiple dangling sessions
- Precondition: 3 sessions with `endedAtMs == null` in Hive (e.g., crash loop)
- Trigger: Cold start
- Flow: `checkForInProgressSession()` returns most recent, deletes the 2 older ones
- Expected: Most recent session restored; older orphans cleaned up

### S-004: Warm resume (app backgrounded)
- Precondition: Active Cardio session in memory; user switches apps and comes back
- Trigger: App brought to foreground (no kill)
- Flow: `hasActiveSession == true` → post-frame callback returns immediately (no repo query)
- Expected: No change to state; session continues normally

### S-005: Corrupted Hive record
- Precondition: One session has unparseable data in Hive
- Trigger: Cold start / `getInProgressSessions()` parse loop
- Flow: Try/catch inside parse loop skips the bad record, logs warning
- Expected: No crash; valid sessions still discovered

## Implementation Plan

### Phase 1: Data Layer (@dba)

**`lib/data/repositories/workout_repository.dart`**
- Add `Future<List<TrainingSession>> getInProgressSessions()` to abstract interface

**`lib/data/repositories/hive_workout_repository.dart`**
- Implement: filter `_sessionsBox.values` where `ended_at_ms == null`
- Sort by `started_at_ms` descending
- Wrap each record parse in try/catch; skip and log malformed records
- Wrap outer scan in try/catch; return `[]` on unexpected error

**`lib/data/repositories/mock_workout_repository.dart`**
- Implement: filter `_sessions.values` where `endedAtMs == null`
- Sort by `startedAtMs` descending

### Phase 2: State Layer (@dba or @developer)

**`lib/state/workout/workout_state.dart`**
- Add `Future<TrainingSession?> checkForInProgressSession()`:
  - Calls `_repository.getInProgressSessions()`
  - If list has > 1: delete all but index 0 via `_repository.deleteSession()`
  - Returns `sessions.first` or null if empty
  - Full try/catch; returns null on error

### Phase 3: UI Layer (@developer)

**`lib/features/home/home_screen.dart`**
- Add `bool _resumeCheckDone = false` field to `_HomeScreenState`
- Add silent-restore post-frame callback in `initState`:

```dart
WidgetsBinding.instance.addPostFrameCallback((_) async {
  if (!mounted || _resumeCheckDone) return;
  _resumeCheckDone = true;
  if (widget.workoutState.hasActiveSession) return;
  final session = await widget.workoutState.checkForInProgressSession();
  if (session == null || !mounted) return;
  await widget.workoutState.loadHistoricalSession(session.id);
  // No navigation — tile on home screen now shows as active
});
```

- **Remove** any previously added modal code:
  - `_showResumeSessionModal()`
  - `_showDiscardConfirmation()`
  - `_ResumeSessionDialog` widget class
  - `_countEffortsForSession()`, `_getModalityLabel()`, `_formatStartTime()`
  - Any `intl`/`DateFormat` import added solely for the modal

### Phase 4: Tests (@developer)

**`test/screen_widget_test.dart`**
- Remove/update test `'does not show unfinished-session launch modal copy'`
- Add test: cold start with one in-progress session → after pumpAndSettle, tile is active + no dialog shown

**`test/session_resume_test.dart`** (if it exists — verify or create)
- `checkForInProgressSession()` returns null when no sessions
- `checkForInProgressSession()` returns null when all sessions have `endedAtMs` set
- `checkForInProgressSession()` returns most recent in-progress session
- `checkForInProgressSession()` deletes older sessions when multiple exist
- Malformed record in `getInProgressSessions()` does not crash
- `deleteSessionById()` removes session without touching in-memory state (if that method is kept)

## Files Affected
- `lib/data/repositories/workout_repository.dart` — add interface method
- `lib/data/repositories/hive_workout_repository.dart` — implement `getInProgressSessions()`
- `lib/data/repositories/mock_workout_repository.dart` — implement `getInProgressSessions()`
- `lib/state/workout/workout_state.dart` — add `checkForInProgressSession()`
- `lib/features/home/home_screen.dart` — add `_resumeCheckDone` + silent-restore callback; remove all modal code
- `test/screen_widget_test.dart` — update cold-start test
- `test/session_resume_test.dart` — verify/add state-layer tests

## Notes
- No model changes — `TrainingSession` already has all fields needed
- No timer changes — wall-clock timestamps already survive kills
- `loadHistoricalSession` already restores complete state: segments, efforts, observations, rest timers, round/timed instances
- Architecture stays clean: no direct repository access from feature layer; all goes through state

## Progress
- [ ] Phase 1: Data layer — repository methods
- [ ] Phase 2: State layer — `checkForInProgressSession()`
- [ ] Phase 3: UI layer — silent restore, remove modal code
- [ ] Phase 4: Tests

## Feedback
[Leave empty until a specialist or reviewer adds notes]

---

**Next recommended handoff: @dba**

Phases 1 and 2 (data + state). Once `getInProgressSessions()` and `checkForInProgressSession()` are
confirmed working, @developer handles Phase 3 (HomeScreen silent restore + remove old modal code) and Phase 4 (tests).
