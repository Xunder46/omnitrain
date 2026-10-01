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

## Scenarios
(Populated by Developer agent during Phase 0)

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

## Progress (Iteration 1 — Abandoned)
- [x] Phase 1: Repository — `getInProgressSessions()` in interface + both implementations
- [x] Phase 2: State — `checkForInProgressSession()` + `deleteSessionById()` on `WorkoutState`
- [ ] Phase 3: UI — **Replaced by Iteration 2 (silent restore, no dialog)**
- [ ] Phase 4: Tests — **Updated by Iteration 2**

---

## Iteration 2 — Silent State Restore (No Dialog)

### Design Change
**Previous approach (Iteration 1)**: Show an "Unfinished Session" modal on cold start asking the user to Continue or Discard.

**New approach**: On cold start, silently restore the session into memory with no dialog. The home screen tile lights up as active (same as if the user had just started a session), and the user can tap it to return to the workout. No interruption, no decision required.

**Rationale**: App-state restoration should be invisible. If the OS killed the app, it should just come back to life. The user didn't explicitly end the session — the session should just be there.

### What Changes in Iteration 2

**Removed entirely**:
- `_showResumeSessionModal()` method and all dialog/confirmation UI
- `_ResumeSessionDialog` widget
- `_countEffortsForSession()` / `countSetsForSession()` (was only used for the dialog)
- `deleteSessionById()` on `WorkoutState` (was only used by the Discard flow — if still present from Iteration 1, remove or keep as unused; session deletion is handled by existing `clearSession()`)
- Any import of `intl` / `DateFormat` added solely for the modal

**What stays the same**:
- `getInProgressSessions()` repository method (still needed for the check)
- `checkForInProgressSession()` on `WorkoutState` (still needed; still cleans up older dangling sessions)
- `_resumeCheckDone` guard flag (still needed to prevent repeat loads on warm resume)

**HomeScreen post-frame callback (new implementation)**:
```dart
WidgetsBinding.instance.addPostFrameCallback((_) async {
  if (!mounted || _resumeCheckDone) return;
  _resumeCheckDone = true;
  // Warm resume: in-memory session already exists — nothing to do
  if (widget.workoutState.hasActiveSession) return;
  final session = await widget.workoutState.checkForInProgressSession();
  if (session == null || !mounted) return;
  // Silent restore — no dialog, just reload session state
  await widget.workoutState.loadHistoricalSession(session.id);
  // No navigation: home screen tile now shows as active; user taps to continue
});
```

### Implementation Steps

#### Phase 1: Data Layer (unchanged — verify it exists)
1. [ ] Confirm `getInProgressSessions()` is on `WorkoutRepository` interface
2. [ ] Confirm `HiveWorkoutRepository` implements it (with try/catch for malformed records)
3. [ ] Confirm `MockWorkoutRepository` implements it

If any of the above are missing, implement as specified in Iteration 1 DB Changes above.

#### Phase 2: State Layer (unchanged — verify it exists)
4. [ ] Confirm `WorkoutState.checkForInProgressSession()` exists and returns most recent session, deletes older ones
5. [ ] Confirm `WorkoutState.loadHistoricalSession(String id)` is already public (it is — no change needed)

#### Phase 3: UI Layer (new — replaces Iteration 1 Phase 3)
6. [ ] Add `_resumeCheckDone = false` field to `_HomeScreenState`
7. [ ] Add the silent-restore post-frame callback to `initState` (see code above)
8. [ ] **Remove** `_showResumeSessionModal`, `_showDiscardConfirmation`, `_countEffortsForSession`, `_getModalityLabel`, `_formatStartTime` if they were added in Iteration 1
9. [ ] **Remove** any `_ResumeSessionDialog` widget class if it was added

#### Phase 4: Tests
10. [ ] New test: cold start with one unfinished session → `workoutState.hasActiveSession` is true after `initState` + settle
11. [ ] New test: cold start with no sessions → `workoutState.hasActiveSession` remains false
12. [ ] New test: warm resume (session already in memory) → `checkForInProgressSession` is NOT called
13. [ ] Update `test/screen_widget_test.dart` — remove any test expecting the "Unfinished Session" dialog; replace with test confirming the tile becomes active after cold start
14. [ ] Verify `test/session_resume_test.dart` state-layer tests still pass

### Files Affected
- `lib/data/repositories/workout_repository.dart` — verify interface method (add if missing)
- `lib/data/repositories/hive_workout_repository.dart` — verify implementation (add if missing)
- `lib/data/repositories/mock_workout_repository.dart` — verify implementation (add if missing)
- `lib/state/workout/workout_state.dart` — verify `checkForInProgressSession()` (add if missing); remove dialog-only helpers if present
- `lib/features/home/home_screen.dart` — add `_resumeCheckDone` + silent-restore callback; remove all modal code
- `test/screen_widget_test.dart` — update dialog-related assertions
- `test/session_resume_test.dart` — verify existing state-layer tests still pass

### Notes
- No auto-navigation on cold start — home screen tile becomes active, user taps it to go back in
- `loadHistoricalSession` is already the correct method: it restores segments, efforts, observations, rest timers, round/timed instances, and sets `hasActiveSession = true`
- Timer state (rest timers, round/timed elapsed) is already wall-clock based and will resume from correct timestamps without any extra logic
- Architecture is cleaner: no dialog, no count query, no date formatting in HomeScreen

## Progress (Iteration 2)
- [ ] Phase 1: Data layer — verify/add repository methods
- [ ] Phase 2: State layer — verify/add `checkForInProgressSession()`
- [ ] Phase 3: UI layer — silent restore callback, remove modal code
- [ ] Phase 4: Tests — update and verify

## Feedback
[Leave empty until a specialist or reviewer adds notes]
