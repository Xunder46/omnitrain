# Feature: Active Session Persistence & Resume

## Overview
Make active workout sessions durable across app lifecycle events (OS kill, force quit, cold start). Sessions are already being written through to Hive on every mutation — the data survival gap is solved. The missing pieces are: (1) a repository query to detect in-progress sessions at launch, (2) state methods to expose that check and to resume without loading unnecessarily, and (3) a modal on the home screen that fires on cold start when a dangling session is found.

## Requirements
- A session started by the user is persisted to local storage before the session screen is shown (ALREADY TRUE — `createNewSession` calls `_repository.createSession` before navigation)
- Every mutation writes through to storage immediately (ALREADY TRUE — all `SessionCore` mutations call through to the repository)
- Rest timer state is stored as a wall-clock `restStartMs` timestamp (ALREADY TRUE — `EntryRest.restStartMs` is already persisted; `RoundInstance` / `TimedInstance` use wall-clock timestamps)
- On cold start, if an in-progress session exists in storage, a modal appears over the home screen
- The modal shows: session modality/name, start time, and number of sets logged
- Continue → loads session into memory, navigates to `WorkoutSessionScreen`
- Discard → one confirmation tap → deletes session record → home screen is clean
- Warm resume (app merely backgrounded) does NOT trigger the modal — existing in-memory state carries through
- Malformed session records are cleaned up silently without crashing
- Sessions never auto-expire — they persist until acted on
- Multiple in-progress sessions: surface only the most recent, delete older ones

## Acceptance Criteria
- [ ] `getInProgressSessions()` exists on `WorkoutRepository` interface and returns all sessions where `endedAtMs == null`, sorted by `startedAtMs` desc
- [ ] `HiveWorkoutRepository` implements `getInProgressSessions()` correctly
- [ ] `MockWorkoutRepository` implements `getInProgressSessions()` correctly
- [ ] `WorkoutState.checkForInProgressSession()` returns the most recent dangling session (or null), and deletes all older ones
- [ ] `WorkoutState.deleteSessionById(String id)` deletes a session without requiring it to be loaded into memory first
- [ ] `HomeScreen.initState` registers a post-frame callback that, when `workoutState.hasActiveSession` is false, calls `checkForInProgressSession()` and shows the resume modal if a session is found
- [ ] The resume modal visually matches the existing "Start New Session?" `AlertDialog` pattern (title, content, Cancel/Continue actions)
- [ ] The modal displays: session modality or title, formatted start time, and set count
- [ ] Continue: calls `workoutState.loadHistoricalSession(sessionId)` then pushes `WorkoutSessionScreen`
- [ ] Discard: single confirmation tap → calls `workoutState.deleteSessionById(id)` → modal dismissed
- [ ] Modal does not appear on warm resume (`workoutState.hasActiveSession == true` suppresses the check)
- [ ] Corrupted/unreadable session record in Hive is caught, logged, and skipped (no crash, no modal)
- [ ] All new paths covered by unit tests
- [ ] Resume dialog back-dismiss (`result == null`) preserves session and does not trigger delete
- [ ] Resume modal displays true sets logged (observation count), not effort/exercise count
- [ ] Home feature does not directly access repository for resume modal metrics (state boundary preserved)
- [ ] Malformed Hive session record path is covered by an automated test
- [ ] Resume dialog has widget and interaction coverage for Continue, Discard, and back-dismiss behavior

## Scenarios
### S-001: Cold start with one in-progress session
- Trigger: App launches to `HomeScreen` after process kill.
- Precondition: Exactly one stored session has `endedAtMs == null`; in-memory state has no active session.
- Flow: `HomeScreen.initState` post-frame callback calls `checkForInProgressSession()`, then shows resume modal.
- Expected outcome: Modal appears with session label, formatted start time, and sets logged count.
- Edge case of: none

### S-002: Continue from resume modal
- Trigger: User taps `Continue` in resume modal.
- Precondition: Resume modal is visible for a valid session id.
- Flow: `loadHistoricalSession(sessionId)` completes, then navigation pushes `WorkoutSessionScreen`.
- Expected outcome: Session is restored in memory and user lands on `WorkoutSessionScreen`.
- Edge case of: S-001

### S-003: Discard from resume modal
- Trigger: User taps `Discard`, then taps `Confirm Discard`.
- Precondition: Resume modal is visible for a valid session id.
- Flow: First tap arms confirmation state; second tap pops `false`; caller deletes session by id.
- Expected outcome: Session record is removed from storage; modal dismissed; home remains clean.
- Edge case of: S-001

### S-004: Back-dismiss resume modal preserves session
- Trigger: System back action dismisses resume modal.
- Precondition: Resume modal is visible.
- Flow: Dialog returns `null`; caller branches only on explicit `true`/`false`.
- Expected outcome: No delete is executed and session remains in storage.
- Edge case of: S-001

### S-005: Multiple dangling in-progress sessions
- Trigger: Cold start calls `checkForInProgressSession()`.
- Precondition: More than one stored session has `endedAtMs == null`.
- Flow: Repository returns sorted list desc by `startedAtMs`; state keeps first and best-effort deletes older ones.
- Expected outcome: Most recent session is returned; older dangling sessions are removed.
- Edge case of: S-001

### S-006: Malformed session record in Hive
- Trigger: `getInProgressSessions()` iterates sessions.
- Precondition: At least one row/map is not parseable by `TrainingSession.fromMap`.
- Flow: Parse throws in try/catch; record is skipped and processing continues.
- Expected outcome: No crash; malformed record excluded from results; valid records still returned.
- Edge case of: S-001

---

## Iteration 1

### Analysis
The data layer already provides full write-through persistence. `createNewSession`, `createEffort`, `createObservation`, `updateObservation`, `deleteObservation`, `updateSession` — all write to the Hive repository immediately. `EntryRest.restStartMs` and `RoundInstance`/`TimedInstance` wall-clock timestamps mean timer state survives a kill without any changes. `loadHistoricalSession` (already exposed on `WorkoutState`) already loads the complete session state including entry rests, round instances, timed instances, observations, exercise cache, and session blocks. **The implementation is smaller than it looks.**

### DB Changes
- New method `getInProgressSessions()` on `WorkoutRepository` interface
  - Returns `List<TrainingSession>` where `endedAtMs == null`
  - Sorted by `startedAtMs` descending (most recent first)
  - Wraps `_asStringMap` parse in try/catch; malformed records are skipped and logged
- Implement in `HiveWorkoutRepository`: filter `_sessionsBox.values` for `ended_at_ms == null`
- Implement in `MockWorkoutRepository`: filter `_sessions.values` for `endedAtMs == null`

### Backend / State Changes

#### `WorkoutState` additions (lib/state/workout/workout_state.dart)

1. `Future<TrainingSession?> checkForInProgressSession()`:
   - Calls `_repository.getInProgressSessions()`
   - If list has > 1 entry: delete all but the most recent (`_repository.deleteSession` for each older one)
   - Returns the most recent, or null if list is empty
   - Wraps everything in try/catch; on exception returns null (graceful degradation)

2. `Future<void> deleteSessionById(String id)`:
   - Calls `_repository.deleteSession(id)` directly
   - Does NOT touch `_currentSession` (no in-memory side effects)
   - Wraps in try/catch; logs on failure

Note: `resumeInProgressSession` is not needed — `loadHistoricalSession(sessionId)` already does the full restore and is already public on `WorkoutState`. It will set `hasActiveSession = true` once efforts are loaded.

### Frontend Changes

#### HomeScreen (lib/features/home/home_screen.dart)

Add `_resumeCheckDone` bool flag to `_HomeScreenState` (prevents the check running more than once per warm session).

In `initState`, after the existing `addPostFrameCallback`:
```dart
WidgetsBinding.instance.addPostFrameCallback((_) async {
  if (!mounted || _resumeCheckDone) return;
  _resumeCheckDone = true;
  // Only run on cold start: warm resume already has in-memory session
  if (widget.workoutState.hasActiveSession) return;
  final session = await widget.workoutState.checkForInProgressSession();
  if (session == null || !mounted) return;
  _showResumeSessionModal(context, session);
});
```

#### `_showResumeSessionModal` method on `_HomeScreenState`:

Shows an `AlertDialog` (matching the existing "Start New Session?" pattern) with:
- **Title**: `'Unfinished Session'`
- **Content**: rows showing:
  - Session name/modality (use `session.title ?? _modalityLabel(session.modality)`)
  - Start time formatted as `'Started [day] at [HH:mm]'` using `DateFormat`
  - Set count from a direct repo query: `_countSets(session)` (counts all observations in the session at display time — see below)
- **Actions**:
  - `TextButton('Discard')` → shows one-tap inline confirmation (change button label to `'Confirm Discard'` on first tap, execute on second) OR use a nested `showDialog` for the confirmation step
  - `FilledButton('Continue')` → calls `workoutState.loadHistoricalSession(session.id)` then pushes `WorkoutSessionScreen`

For set count at display time: call `_repository.getSessionSegments(session.id)` then `_repository.getSegmentEfforts(segmentId)` for each, sum the effort counts. This is a read-only scan and does not touch `WorkoutState`.

Alternatively, to keep the modal self-contained: use a `FutureBuilder` inside the dialog content to load and display the set count asynchronously while showing a placeholder.

#### Style note:
Reuse the same `ButtonStyle` with `RoundedRectangleBorder(borderRadius: BorderRadius.circular(OmniTheme.buttonUtilityRadius))` that already appears in the existing conflict dialog.

### Implementation Steps

#### Phase 1: Data Layer (@dba)
1. [ ] Add `Future<List<TrainingSession>> getInProgressSessions()` to `WorkoutRepository` (lib/data/repositories/workout_repository.dart)
2. [ ] Implement in `HiveWorkoutRepository` — filter `_sessionsBox.values`, parse with try/catch to swallow malformed records, return sorted by `startedAtMs` desc
3. [ ] Implement in `MockWorkoutRepository` — filter `_sessions.values` for `endedAtMs == null`, return sorted by `startedAtMs` desc

#### Phase 2: State Layer (@developer)
4. [ ] Add `checkForInProgressSession()` to `WorkoutState` (delegates to `_sessionCore` or uses `_repository` directly — recommend directly on `WorkoutState` since it is lifecycle/startup logic, not session-lifecycle logic)
5. [ ] Add `deleteSessionById(String id)` to `WorkoutState`
6. [ ] Expose `WorkoutRepository get repository` is already public — the modal can use `widget.workoutState.repository` to fetch set count data without adding new state methods

#### Phase 3: UI (@developer)
7. [ ] Add `_resumeCheckDone` bool to `_HomeScreenState`
8. [ ] Add post-frame callback in `initState` for resume check (after existing hint animation callback)
9. [ ] Implement `_showResumeSessionModal(BuildContext context, TrainingSession session)` on `_HomeScreenState`
   - Uses `FutureBuilder` or async builder for set count
   - Discard: single confirmation tap pattern
   - Continue: `await widget.workoutState.loadHistoricalSession(session.id)` then `Navigator.push` to `WorkoutSessionScreen`

#### Phase 4: Tests (@developer)
10. [ ] New test: `checkForInProgressSession()` returns null when no sessions exist
11. [ ] New test: `checkForInProgressSession()` returns null when all sessions have `endedAtMs` set
12. [ ] New test: `checkForInProgressSession()` returns the most recent in-progress session when one exists
13. [ ] New test: `checkForInProgressSession()` returns most recent and deletes older ones when multiple in-progress sessions exist
14. [ ] New test: `getInProgressSessions()` on `MockWorkoutRepository` returns correct filtered list
15. [ ] New test: `deleteSessionById` removes session without affecting in-memory state
16. [ ] New test: malformed session record in `getInProgressSessions()` does not crash (via mock that injects a bad record)
17. [ ] Existing test review: any test covering app startup should confirm resume check path; any test covering session start should confirm session exists in storage before navigation

### Files Affected
- `lib/data/repositories/workout_repository.dart` — add `getInProgressSessions()`
- `lib/data/repositories/hive_workout_repository.dart` — implement `getInProgressSessions()`
- `lib/data/repositories/mock_workout_repository.dart` — implement `getInProgressSessions()`
- `lib/state/workout/workout_state.dart` — add `checkForInProgressSession()`, `deleteSessionById()`
- `lib/features/home/home_screen.dart` — add resume check in `initState`, implement `_showResumeSessionModal()`
- `test/` — new test file `session_resume_test.dart`

### Notes
- **No model changes** — `TrainingSession` already has all fields needed (`endedAtMs`, `modality`, `title`, `startedAtMs`, `isRolling`)
- **No timer changes** — `EntryRest.restStartMs`, `RoundInstance` start/end timestamps, `TimedInstance` wall-clock fields already survive a kill
- **Write-through is already complete** — no changes needed to `SessionCore` mutation methods
- **`loadHistoricalSession` reuse** — this method is already fully equipped for resume: loads segments, efforts, observations, round instances, timed instances, entry rests, exercise cache, and session blocks
- **Warm resume guard** — `workoutState.hasActiveSession` being true means in-memory state is intact; the post-frame callback short-circuits immediately
- **Set count query** — accessing `workoutState.repository` directly for the display-only count is acceptable since it is read-only and scoped to the modal display; alternatively, a new `countSetsForSession(String sessionId)` can be added to the repository interface if developer prefers a cleaner API

---

## Iteration 2

### Analysis
Code review identified one merge-blocking defect and four quality gaps. Scope is to implement all feedback items: preserve session on back-dismiss, compute true set counts, enforce feature-to-state boundary, add malformed-record test coverage, and add widget/interaction tests for resume dialog flows. No schema or model migration is required.

### DB Changes
- None

### Backend / State Changes
1. Update `WorkoutState` with a read-only method for resume modal metric lookup (recommended: `Future<int> countSetsForSession(String sessionId)`) so UI does not call repository directly.
2. Implement set counting as total `EffortObservation` rows across all efforts in all session segments.
3. Keep method side-effect free: no mutation of active in-memory session.

### Frontend Changes
1. Fix resume dialog result handling in home screen:
   - `result == true` → continue
   - `result == false` → discard/delete
   - `result == null` (system back-dismiss) → no-op, preserve session
2. Replace effort/exercise metric copy with sets logged copy and use state method above.
3. Remove direct repository access from home feature for modal metric lookup.

### Test Changes
1. Add repository-focused malformed-record test for Hive `getInProgressSessions()` that verifies bad records are skipped without crash.
2. Add widget/render test for resume dialog content and action visibility.
3. Add interaction tests for:
   - Continue flow resumes and navigates.
   - Discard flow deletes and dismisses.
   - Back-dismiss leaves session intact (regression test for critical bug).
4. Add or update unit tests for `WorkoutState.countSetsForSession` set counting behavior.

### Implementation Steps

#### Phase 1: State & Boundary (@developer)
1. [ ] Add `countSetsForSession(String sessionId)` to `WorkoutState`.
2. [ ] Implement counting using repository reads inside state only.
3. [ ] Ensure implementation handles empty segments/efforts and returns `0` safely.

#### Phase 2: UI Regression Fixes (@developer)
4. [ ] Update home resume dialog result branching to explicit `true/false/null` handling.
5. [ ] Replace modal metric label/value to true sets logged.
6. [ ] Refactor home modal metric retrieval to call `WorkoutState` method (no direct repository in feature).

#### Phase 3: Automated Tests (@developer)
7. [ ] Add malformed Hive record test for in-progress session query.
8. [ ] Add resume dialog widget test coverage.
9. [ ] Add resume dialog interaction tests for Continue, Discard, and back-dismiss.
10. [ ] Add unit tests for `countSetsForSession` correctness across multi-segment sessions.

### Files Affected
- `lib/state/workout/workout_state.dart`
- `lib/features/home/home_screen.dart`
- `lib/data/repositories/hive_workout_repository.dart` (tests only if helper exposure needed)
- `test/session_resume_test.dart`
- `test/screen_widget_test.dart`
- `test/interaction_flow_test.dart`

### Notes
- Fast-track to Developer-only is **not** applicable because this pass includes user-visible metric semantics and adds a new state method.
- Keep repository interface unchanged unless tests prove state cannot compute set counts via existing reads.
- Preserve existing dialog visual style and action ordering.

## Progress
- [x] Iteration 2 Phase 1: Add set counting method in state boundary
- [x] Iteration 2 Phase 2: Fix dialog branching and metric semantics
- [x] Iteration 2 Phase 3: Add malformed-record + widget + interaction tests

## Feedback
(No pending feedback. Add new reviewer notes here.)
