# Feature: Data Tracking Fixes

## Overview
Four targeted fixes for user data that is either silently lost or never persisted:
1. `updateEntryValue` drops `rpeRating` and `restDurationMs` fields when overwriting an observation
2. `HomeState._maintenanceHintSeen` resets every app relaunch
3. Skipped sets have no persisted "skipped" marker — indistinguishable from un-attempted sets after reload
4. `perceivedSessionRpe` is modelled and stored in the DB but has no UI write path

No new tables or schema changes are required. All fixes use existing fields and the existing Hive `meta` box.

---

## Iteration 1

### DB / Repository Changes

**Fix 2 only needs new repo methods** — store hint flags in the existing Hive `meta` box.

1. [ ] Add two methods to `lib/data/repositories/workout_repository.dart` abstract class:
   ```dart
   Future<bool> getPreferenceBool(String key, {bool defaultValue = false});
   Future<void> setPreferenceBool(String key, bool value);
   ```
2. [ ] Implement in `lib/data/repositories/hive_workout_repository.dart` using `_metaBox`:
   - `getPreferenceBool`: `return _metaBox.get(key, defaultValue: defaultValue) as bool? ?? defaultValue;`
   - `setPreferenceBool`: `await _metaBox.put(key, value);`
3. [ ] Implement in `lib/data/repositories/mock_workout_repository.dart` using an in-memory `Map<String, bool> _prefs = {}`:
   - `getPreferenceBool`: `return _prefs[key] ?? defaultValue;`
   - `setPreferenceBool`: `_prefs[key] = value;`

No migrations or seed changes needed — `_metaBox` is already open.

---

### Backend / State Changes

#### Fix 1 — `updateEntryValue` drops observation fields (2-line fix)

File: `lib/state/workout/workout_state.dart` → `updateEntryValue()` (~line 742–757)

The `newObs` construction copies `valueInt`, `valueReal`, `valueText`, `valueBool` from `oldObs` but hard-drops `rpeRating` and `restDurationMs`.

Change:
```dart
final newObs = EffortObservation(
  id: oldObs.id,
  effortId: oldObs.effortId,
  metricId: oldObs.metricId,
  unitId: oldObs.unitId,
  valueInt: (value is int) ? value : oldObs.valueInt,
  valueReal: (value is double) ? value : oldObs.valueReal,
  valueText: (value is String) ? value : oldObs.valueText,
  valueBool: (value is bool) ? value : oldObs.valueBool,
  rpeRating: oldObs.rpeRating,           // ADD THIS
  restDurationMs: oldObs.restDurationMs, // ADD THIS
  createdAtMs: oldObs.createdAtMs,
  updatedAtMs: DateTime.now().millisecondsSinceEpoch,
);
```

#### Fix 2 — Persist maintenance hint flag

File: `lib/state/home/home_state.dart`

- Inject `WorkoutRepository` into `HomeState` constructor (same pattern as all other states)
- On `init()`, read `getPreferenceBool('hint_seen_maintenance')` and set `_maintenanceHintSeen`
- In `markMaintenanceHintSeen()`, also call `await _repository.setPreferenceBool('hint_seen_maintenance', true)`

Steps:
1. [ ] Add `WorkoutRepository _repository` field and constructor param to `HomeState`
2. [ ] Add `Future<void> init()` method that reads the flag from repo on startup
3. [ ] Update `markMaintenanceHintSeen()` to also persist through the repo
4. [ ] In `lib/main.dart`, pass `repository` to `HomeState(repository)` and `await homeState.init()` after repository initialization

#### Fix 3 — Persist skipped-set intent

The existing `EffortObservation` model already has a `valueBool` field. When a set is explicitly skipped, it currently writes nothing extra (zero-reps obs may exist from pre-fill but is set to 0). We will use `valueBool = true` on the reps observation as the explicit "skipped" marker.

Files: `lib/state/workout/workout_state.dart` and `lib/features/session/workout_session_screen.dart`

**WorkoutState additions:**
1. [ ] Add method `Future<void> markSetSkipped(String effortId, int entryIndex)`:
   - Finds the reps observation for `entryIndex`
   - Creates a new obs with `valueInt: 0, valueBool: true` (explicitly skipped)
   - Calls `_repository.updateObservation(newObs)` and updates cache

**Screen changes in `_skipSet()`:**
2. [ ] After marking `_skippedSets`, call `widget.workoutState.markSetSkipped(effortId, _currentSet - 1)` (fire-and-forget is fine, it's already an async state method)

**Restore skip state on reload (`_loadExercises`):**
3. [ ] In the pre-populate `_loggedSetKeys` loop, also restore `_skippedSets`: when `effortKind == 'set'` and `reps == 0` and `valueBool == true` on the obs, add that index to `_skippedSets[effortId]`
4. [ ] Update `_isSetLogged` to treat `valueBool == true` (skipped) as logged (so rest timer / skip logic is consistent on reload)

#### Fix 4 — Perceived session RPE save path

The `TrainingSession.perceivedSessionRpe` field exists in model and is carried through all `updateSession` copies, but there is no UI entry point to set it.

Files: `lib/state/workout/workout_state.dart` and `lib/features/session/session_summary_screen.dart`

**WorkoutState:**
1. [ ] Add `Future<void> updateSessionRpe(String sessionId, double rpe)` (mirrors `updateSessionFeeling`):
   - Clamp `rpe` to `1.0–10.0`
   - Build updated session with `perceivedSessionRpe: rpe`, call `updateSession`, update `_currentSession`

**Session Summary Screen:**
2. [ ] Extend `_showFeelingSheet()` to include an RPE picker step, OR add a separate RPE row visible below the feeling selector on the summary screen
   - Recommended: add a simple 1–10 horizontal number row directly below the feeling card on the summary screen (non-blocking, always visible, not in a sheet)
   - Wire to `widget.workoutState.updateSessionRpe(session.id, selectedRpe)`
   - Show current value from `session.perceivedSessionRpe` as the initial selection
   - Label it: "Effort (RPE)" to distinguish from session feeling

---

### Implementation Steps (in order)

1. [ ] Fix 1: Add `rpeRating` and `restDurationMs` to `newObs` in `updateEntryValue` — `workout_state.dart`
2. [ ] Fix 2a: Add preference methods to `WorkoutRepository` abstract class
3. [ ] Fix 2b: Implement in `HiveWorkoutRepository` and `MockWorkoutRepository`
4. [ ] Fix 2c: Update `HomeState` to accept repository, add `init()`, persist flag
5. [ ] Fix 2d: Wire `HomeState(repository)` and `homeState.init()` in `main.dart`
6. [ ] Fix 3a: Add `markSetSkipped()` to `WorkoutState`
7. [ ] Fix 3b: Call `markSetSkipped()` from `_skipSet()` in workout_session_screen.dart
8. [ ] Fix 3c: Restore `_skippedSets` on load from `valueBool == true` on reps obs
9. [ ] Fix 3d: Update `_isSetLogged` to treat `valueBool == true` as logged
10. [ ] Fix 4a: Add `updateSessionRpe()` to `WorkoutState`
11. [ ] Fix 4b: Add RPE picker UI to session summary screen, wire to `updateSessionRpe`

---

## Progress
- [x] Fix 1: Preserve rpeRating/restDurationMs in updateEntryValue
- [x] Fix 2: Persist HomeState maintenance hint flag
- [x] Fix 3: Persist skipped-set marker using valueBool on reps observation
- [x] Fix 4: Add perceivedSessionRpe save path in summary screen

## Feedback
### Code Reviewer Findings (March 22, 2026)

Implementation does not fully satisfy Fix 3 intent and introduces a behavioral regression.

1. **Skipped-set marker is never cleared after a real log**
    - Files: `lib/state/workout/workout_state.dart`, `lib/features/session/workout_session_screen.dart`, `lib/core/utils/observation_grouper.dart`
    - Problem: `markSetSkipped()` sets reps observation `valueBool = true`, but later logging reps/weight does not reset it to `false`.
    - Impact: A set can remain permanently marked skipped in persistence/UI even after the user logs actual reps, and set-dot visuals can continue to render as skipped.
    - Required fix:
       - Clear skip marker when a set is logged with actual reps (or when user edits reps away from skipped state).
       - Ensure `_skippedSets` in screen state is reconciled/removed when the user logs that set.
       - Align restore logic to the original rule: treat skipped only when `reps == 0 && valueBool == true`.

2. **Test coverage gap for new persistence paths**
    - Add targeted tests for:
       - skip -> reload -> shown skipped,
       - skip -> later log reps -> skip cleared,
       - maintenance hint persists across HomeState init,
       - session RPE persists and rehydrates.

### Follow-up Resolution (March 22, 2026)

- Cleared stale skip marker in `updateEntryValue()` when reps are logged (`reps > 0`), so skipped state is removed from persistence on real logs.
- Reconciled `_skippedSets` UI state in `_logSet()` when a real set is logged.
- Tightened restore/logged skip rule to require `reps == 0 && skipped == true`.
- Added regression tests in `test/data_tracking_fixes_test.dart` covering all four persistence scenarios listed above.

---

@developer — All four fixes are self-contained code changes with no DB schema migrations needed. Please work through Implementation Steps 1–11 in order. Fix 1 is the quickest and most critical (silent data loss). Fix 2 requires wiring the repo into HomeState but follows the exact same pattern as every other State class in this codebase.
