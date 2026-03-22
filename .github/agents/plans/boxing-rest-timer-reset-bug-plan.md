# Feature: DB-Backed Per-Set Rest Tracking

## Overview
Replace the purely in-memory rest timer (Stopwatch + Timer.periodic inside
`workout_session_screen.dart`) with a wall-clock–persisted `EntryRest` record that is saved to
the repository for every set/round/entry across ALL exercise types (set, round, timed, drill,
and any future custom kinds).  The UI display is driven by `now - rest_start_ms`; no `Stopwatch`
or per-screen `Timer.periodic` for rest is needed.

## Requirements
- Rest is tracked granularly: per exercise effort × per session × per set/round/entry
- Works for every effort kind (`set`, `round`, `timed`, `drill`, and future kinds)
- Rest start (`rest_start_ms`) is persisted the moment a set is logged
- Rest end (`rest_end_ms`) is persisted when the next set/round is actively begun
- Rest survives app backgrounding and navigation (wall-clock based, no Stopwatch)
- Historical rest data is available to future analytics and summary screens
- Edit mode is unaffected (no new rests created or mutated during edit)
- The existing rest overlay still shows the elapsed rest duration for the current set

## Codebase State (pre-implementation)
### What already exists
- `EffortObservation.restDurationMs` field + `rest_duration_ms` column  (legacy, unused)
- `app_effort_observation.rest_duration_ms` column in SQLite schema and db_helper.dart
- `EffortObservation` model already serialises the field

### What is missing
- A unified `EntryRest` record that works for ALL effort kinds
  (`EffortObservation.restDurationMs` only covers `set`-kind efforts; rounds and timed use
  `RoundInstance` / `TimedInstance` which have no rest field at all)
- Repository CRUD methods for rest records
- WorkoutState in-memory cache + `recordRestStart` / `recordRestEnd` / `getRestElapsedSeconds`
- UI wired to state instead of the private `_restStopwatch` / `_restTimer`

---

## Iteration 1
### Phase 1: Data Layer (@dba)

#### 1. Add `app_entry_rest` table to `scripts/sqlite_schema.sql`
```sql
-- ENTRY REST RECORDS
-- ==================
-- Tracks the actual recovery time between consecutive sets/rounds for any effort kind.
-- Created when a set is logged (rest_start_ms); closed when the next set/round begins
-- (rest_end_ms). rest_end_ms is NULL while the athlete is still resting.
-- Works uniformly for effort kinds: set, round, timed, drill, and any future kinds.
-- On DELETE CASCADE ensures cleanup when the parent effort is deleted.
CREATE TABLE app_entry_rest (
  id                TEXT    NOT NULL PRIMARY KEY,
  effort_id         TEXT    NOT NULL,
  entry_index       INTEGER NOT NULL,   -- 0-based index of the set/round this rest PRECEDES
  rest_start_ms     INTEGER NOT NULL,   -- wall-clock epoch ms when previous set was logged
  rest_end_ms       INTEGER,            -- wall-clock epoch ms when this set/round began; NULL = still resting
  created_at_ms     INTEGER NOT NULL,
  updated_at_ms     INTEGER NOT NULL,
  FOREIGN KEY(effort_id) REFERENCES app_segment_effort(id) ON DELETE CASCADE
);
CREATE UNIQUE INDEX IF NOT EXISTS UX_entry_rest_effort_index
  ON app_entry_rest(effort_id, entry_index);
```

Also add it to `lib/data/datasources/db_helper.dart` inside the CREATE TABLE block list,
and add a migration line in `lib/data/datasources/migrations.dart` for existing DBs:
```sql
CREATE TABLE IF NOT EXISTS app_entry_rest ( ... same DDL ... );
```

#### 2. Add `EntryRest` model to `lib/data/models/models.dart`
```dart
class EntryRest {
  final String id;          // 'rest-{effortId}-{entryIndex}'
  final String effortId;
  final int entryIndex;     // 0-based; rest that precedes this set/round
  final int restStartMs;    // wall-clock when previous set was logged
  final int? restEndMs;     // wall-clock when this set/round was started; null = still resting
  final int createdAtMs;
  final int updatedAtMs;

  const EntryRest({ ... });

  /// Elapsed rest in seconds. Live value if restEndMs is null.
  int elapsedSeconds(int nowMs) =>
      ((( restEndMs ?? nowMs) - restStartMs) / 1000).round().clamp(0, 99999);

  factory EntryRest.fromMap(Map<String, dynamic> m) { ... }
  Map<String, dynamic> toMap() { ... }
  EntryRest copyWith({ ... }) { ... }
}
```

#### 3. Add repository methods to `lib/data/repositories/workout_repository.dart`
```dart
// Entry Rest
Future<List<EntryRest>> getEntryRests(String effortId);
Future<String> createEntryRest(EntryRest rest);
Future<void> updateEntryRest(EntryRest rest);
Future<void> deleteEntryRestsForEffort(String effortId);
```

#### 4. Implement in `lib/data/repositories/mock_workout_repository.dart`
- Add `final Map<String, EntryRest> _entryRests = {};`
- Implement the 4 methods using the map (same pattern as `_observations`)
- `deleteEffort()` already calls `deleteObservationsForEffort`; add `deleteEntryRestsForEffort` call there too

#### 5. Implement in `lib/data/repositories/hive_workout_repository.dart`
- Add `late Box<Map> _entryRestsBox;`
- Open the box: `_entryRestsBox = await Hive.openBox<Map>('entry_rests');`
- Implement the 4 methods (same scan-by-effortId pattern as `_observationsBox`)
- Add `deleteEntryRestsForEffort` call inside `deleteEffort()`

#### 6. Update `lib/core/models/session_edit_snapshot.dart`
Do **not** snapshot rest records — rests are never structurally mutated during edit mode
(no new rests are created; add/remove set operations don't touch rests). Document this with
a comment in the class.

---

### Phase 2: State Layer (@developer — WorkoutState)

File: `lib/state/workout/workout_state.dart`

#### 1. Add in-memory cache field
```dart
final Map<String, List<EntryRest>> _entryRests = {};
```

#### 2. Load rest records in `loadSessionData()` (and `loadHistoricalSession()`)
Inside the per-effort loop, after loading observations/rounds/timed:
```dart
_entryRests[effort.id] = await _repository.getEntryRests(effort.id);
```
Also clear `_entryRests.clear()` in the `_clearState` / clear block at the top of both load methods.

#### 3. Expose accessor
```dart
List<EntryRest> getEntryRests(String effortId) =>
    List.unmodifiable(_entryRests[effortId] ?? []);
```

#### 4. Add `recordRestStart(String effortId, int entryIndex)`
```dart
Future<void> recordRestStart(String effortId, int entryIndex) async {
  final now = DateTime.now().millisecondsSinceEpoch;
  final rest = EntryRest(
    id: 'rest-$effortId-$entryIndex',
    effortId: effortId,
    entryIndex: entryIndex,
    restStartMs: now,
    restEndMs: null,
    createdAtMs: now,
    updatedAtMs: now,
  );
  await _repository.createEntryRest(rest);
  _entryRests.putIfAbsent(effortId, () => []).add(rest);
  notifyListeners();
}
```

#### 5. Add `recordRestEnd(String effortId, int entryIndex)`
```dart
Future<void> recordRestEnd(String effortId, int entryIndex) async {
  final list = _entryRests[effortId];
  if (list == null) return;
  final idx = list.indexWhere((r) => r.entryIndex == entryIndex);
  if (idx == -1) return;
  final now = DateTime.now().millisecondsSinceEpoch;
  final updated = list[idx].copyWith(restEndMs: now, updatedAtMs: now);
  await _repository.updateEntryRest(updated);
  list[idx] = updated;
  notifyListeners();
}
```

#### 6. Add `getRestElapsedSeconds(String effortId, int entryIndex)`
```dart
int getRestElapsedSeconds(String effortId, int entryIndex) {
  final list = _entryRests[effortId];
  if (list == null) return 0;
  try {
    final rest = list.firstWhere((r) => r.entryIndex == entryIndex);
    final now = DateTime.now().millisecondsSinceEpoch;
    return rest.elapsedSeconds(now);
  } catch (_) {
    return 0;
  }
}
```

#### 7. Add `hasRestRecord(String effortId, int entryIndex)`
```dart
bool hasRestRecord(String effortId, int entryIndex) {
  final list = _entryRests[effortId];
  if (list == null) return false;
  return list.any((r) => r.entryIndex == entryIndex);
}
```

---

### Phase 3: UI Layer (@developer — workout_session_screen.dart)

#### Remove all local rest state and the Stopwatch
Remove these fields:
```dart
Timer? _restTimer;          // line ~89
Stopwatch? _restStopwatch;  // line ~90
int _restElapsedSeconds = 0; // line ~91
String _restFormatted = '00:00'; // line ~92
```

Remove `_startRestTimer()` method entirely.

Remove `_restTimer?.cancel()` and `_restStopwatch?.stop()` from `dispose()` and `_cancelAllTimers()`.

#### Replace `_startRestTimer()` call in `_logSet()`
Where `_startRestTimer()` is currently called (line ~515), replace with:
```dart
// entryIndex of the NEXT set = _currentSet (since _currentSet hasn't advanced yet)
final nextEntryIndex = _currentSet; // 0-based, equals current 1-based set number
unawaited(widget.workoutState.recordRestStart(effortId, nextEntryIndex));
```

**Important**: the `_loggedSetKeys.contains(logKey)` guard above already prevents
double-logging; it also prevents duplicate `recordRestStart` calls when navigating back.

#### Close rest when a round/timed/drill entry is started
In `_toggleEffortTimer`, inside the `effortKind == 'round'` branch, `case RoundState.notStarted:`:
```dart
// Record rest end: the athlete has started this round
unawaited(widget.workoutState.recordRestEnd(effortId, entryIndex));
```

In the `timed/drill` branch, `case TimedState.notStarted:` (start fresh):
```dart
unawaited(widget.workoutState.recordRestEnd(effortId, entryIndex));
```

For **set**-kind: rest ends at the start of the NEXT `_logSet` call. At the very top
of `_logSet()`, before the early-return guard, add:
```dart
// Close rest for this set if it's not already closed
final currentEntryIndex = _currentSet - 1;
if (widget.workoutState.hasRestRecord(effortId, currentEntryIndex)) {
  unawaited(widget.workoutState.recordRestEnd(effortId, currentEntryIndex));
}
```

#### Update the rest overlay condition and display (both overlay instances)
Replace:
```dart
_restElapsedSeconds > 0
```
with:
```dart
widget.workoutState.hasRestRecord(exercise['id'] as String, _currentSet - 1)
```
(use `_exercises[_currentExerciseIndex]['id']` in the second overlay)

Replace the formatted string display:
```dart
_restFormatted
```
with a helper call:
```dart
_formatRestElapsed(exercise['id'] as String, _currentSet - 1)
```

Add a private helper method:
```dart
String _formatRestElapsed(String effortId, int entryIndex) {
  final secs = widget.workoutState.getRestElapsedSeconds(effortId, entryIndex);
  final mm = (secs ~/ 60).toString().padLeft(2, '0');
  final ss = (secs % 60).toString().padLeft(2, '0');
  return '$mm:$ss';
}
```

The rest overlay now refreshes on every `_ticker` tick (already 1 s), which drives
`setState` → widget rebuild → `getRestElapsedSeconds` called inline. No separate
`Timer.periodic` for rest is needed.

---

### Acceptance Criteria
- [ ] Rest is persisted to the repository at the moment a set/round is logged
- [ ] Navigating away and back to the app restores the displayed rest elapsed correctly (wall-clock)
- [ ] New boxing round: advancing to the next round shows 00:00 immediately, then counts up
- [ ] Regular set exercises: rest overlay appears and counts up after logging a set
- [ ] Timed/drill exercises: rest overlay appears after logging an entry
- [ ] Rest ends (stops incrementing) when the next round/timed timer is tapped to start
- [ ] Rest data is associated with the correct effort + entry index in the repository
- [ ] `deleteEffort()` in both MockWorkoutRepository and HiveWorkoutRepository removes rest records
- [ ] Edit mode is unaffected (no rests created/broken during edit sessions)
- [ ] No compile errors; existing tests pass

### Files Affected
- `scripts/sqlite_schema.sql` (new table DDL + query notes)
- `lib/data/datasources/db_helper.dart` (add to CREATE TABLE block)
- `lib/data/datasources/migrations.dart` (CREATE TABLE IF NOT EXISTS migration)
- `lib/data/models/models.dart` (add `EntryRest` class)
- `lib/data/repositories/workout_repository.dart` (add 4 abstract methods)
- `lib/data/repositories/mock_workout_repository.dart` (implement, wire into deleteEffort)
- `lib/data/repositories/hive_workout_repository.dart` (implement, wire into deleteEffort, open box)
- `lib/state/workout/workout_state.dart` (cache field, load, recordRestStart/End, getRestElapsedSeconds, hasRestRecord)
- `lib/features/session/workout_session_screen.dart` (remove Stopwatch/Timer, wire to WorkoutState)
- `lib/core/models/session_edit_snapshot.dart` (add comment explaining why rests are not snapshotted)

### Notes
- `EffortObservation.restDurationMs` already exists and is stored in the DB, but it only covers
  `set`-kind efforts and is currently never populated. `EntryRest` supersedes it for all
  effort kinds. The column can remain unused for now (no migration needed to remove it).
- The `_ticker` (1 s period, already exists) is sufficient to drive rest overlay rebuilds.
  No additional `Timer.periodic` is required.
- `unawaited()` pattern already used throughout the screen for fire-and-forget async calls —
  use same pattern for `recordRestStart` / `recordRestEnd`.
- The `_loggedSetKeys` guard already prevents duplicate logging; it also guards `recordRestStart`
  for free — no additional deduplication needed there.
- For the FIRST set of an exercise (entry_index = 0), no rest record is created — the overlay
  correctly stays hidden because `hasRestRecord(.., 0)` returns false.

## Progress
- [x] Bug hotfix: reset `_restElapsedSeconds`/`_restFormatted` in `_startRestTimer()` (shipped)
- [x] Phase 1: Data layer — EntryRest model, schema, repository interface + implementations
- [x] Phase 2: State layer — WorkoutState cache, recordRestStart/End, geters, hasRestRecord
- [x] Phase 3: UI layer — remove Stopwatch, wire to WorkoutState, update overlays

## Feedback
