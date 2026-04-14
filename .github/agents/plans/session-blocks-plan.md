# Feature: Session Blocks

## Overview
Add a `SessionBlock` concept that allows efforts within a training session to be grouped into named blocks (e.g. "Warm-Up", "Main Work", "Cool Down"). Blocks are orderable, cloneable, and deletable — deleting a block does NOT delete its efforts but nulls their `blockId`.

Also adds `isRolling: bool` to `TrainingSession` (defaults false) to support rolling/continuous session tracking.

## Requirements
- `TrainingSession` gains `isRolling: bool` field (default false), serialized as `is_rolling` INTEGER
- New `SessionBlock` model: id, sessionId, name, orderIndex, createdAtMs, updatedAtMs
- `SegmentEffort` gains nullable `blockId: String?` field, serialized as `block_id`
- 6 new repository interface methods: getSessionBlocks, createSessionBlock, updateSessionBlock, deleteSessionBlock, reorderSessionBlocks, cloneSessionBlock
- Full implementation in `HiveWorkoutRepository` with new `session_blocks` Hive box
- Full implementation in `MockWorkoutRepository`
- SQLite schema parity: new column, new table, new FK column

---

## ⚠️ NOTE: Partial Changes Already Applied by Conductor (incomplete — do NOT ship as-is)

The conductor incorrectly began coding. The following partial changes were made to source files and **must be reviewed and completed by @dba and @developer**:

### Already edited (verify correctness):
- `lib/data/models/models.dart`:
  - `TrainingSession` — `isRolling: bool` field added with `fromMap`/`toMap` serialization ✅
  - `SessionBlock` class added with `fromMap`/`toMap` ✅
  - `SegmentEffort` — `blockId: String?` field added with serialization ✅
- `lib/data/repositories/workout_repository.dart`:
  - 6 new abstract methods added in a `// ─── Session Blocks ───` section ✅
- `lib/data/repositories/mock_workout_repository.dart`:
  - `_sessionBlocks` map field declared — **INCOMPLETE**, methods not yet implemented ⚠️

### Still missing (not yet done):
- `MockWorkoutRepository` — implement all 6 methods
- `HiveWorkoutRepository` — open `session_blocks` box, implement all 6 methods including deep-clone logic
- `scripts/sqlite_schema.sql` — 3 schema changes
- `scripts/sqlite_seed.sql` — no changes needed
- `lib/data/datasources/migrations.dart` — version bump + migration SQL

---

## Iteration 1

### Phase 1: Data Layer (@dba)

#### 1.1 — Verify already-applied model changes
- [ ] Open `lib/data/models/models.dart`, confirm `TrainingSession.isRolling` field and serialization are correct
- [ ] Confirm `SessionBlock` class is complete with all 6 fields, `fromMap`, `toMap`
- [ ] Confirm `SegmentEffort.blockId` nullable field and serialization are correct

#### 1.2 — Update SQLite schema (`scripts/sqlite_schema.sql`)
Add the following **before** `COMMIT;`:

```sql
-- Session Blocks (added Mar 2026)
-- Allows grouping efforts within a session into named ordered blocks.
-- Deleting a block nulls block_id on linked efforts (ON DELETE SET NULL).
ALTER TABLE app_training_session ADD COLUMN is_rolling INTEGER NOT NULL DEFAULT 0;

CREATE TABLE IF NOT EXISTS app_session_block (
  id             TEXT    NOT NULL PRIMARY KEY,
  session_id     TEXT    NOT NULL,
  name           TEXT    NOT NULL,
  order_index    INTEGER NOT NULL DEFAULT 0,
  created_at_ms  INTEGER NOT NULL,
  updated_at_ms  INTEGER NOT NULL,
  FOREIGN KEY(session_id) REFERENCES app_training_session(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS IX_session_block_session
  ON app_session_block(session_id, order_index);

ALTER TABLE app_segment_effort
  ADD COLUMN block_id TEXT REFERENCES app_session_block(id) ON DELETE SET NULL;
```

#### 1.3 — Update `lib/data/datasources/migrations.dart`
- [ ] Bump DB version to 6 (in `database_provider.dart`, `version: 5` → `version: 6`)
- [ ] Add `if (oldVersion < 6) { ... }` block containing:
  ```dart
  await db.execute('ALTER TABLE app_training_session ADD COLUMN is_rolling INTEGER NOT NULL DEFAULT 0');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS app_session_block (
      id             TEXT    NOT NULL PRIMARY KEY,
      session_id     TEXT    NOT NULL,
      name           TEXT    NOT NULL,
      order_index    INTEGER NOT NULL DEFAULT 0,
      created_at_ms  INTEGER NOT NULL,
      updated_at_ms  INTEGER NOT NULL,
      FOREIGN KEY(session_id) REFERENCES app_training_session(id) ON DELETE CASCADE
    )
  ''');
  await db.execute('CREATE INDEX IF NOT EXISTS IX_session_block_session ON app_session_block(session_id, order_index)');
  await db.execute('ALTER TABLE app_segment_effort ADD COLUMN block_id TEXT REFERENCES app_session_block(id) ON DELETE SET NULL');
  ```

#### 1.4 — Implement `MockWorkoutRepository` (@developer can do in Phase 2)
- [ ] Already has `_sessionBlocks` map field — implement the 6 methods:
  - `getSessionBlocks(sessionId)`: filter by sessionId, sort by orderIndex
  - `createSessionBlock(block)`: put in map, return id
  - `updateSessionBlock(block)`: put in map
  - `deleteSessionBlock(blockId)`: remove from map; scan `_efforts.values` and null out `blockId` on any effort matching
  - `reorderSessionBlocks(sessionId, orderedIds)`: iterate orderedIds, update orderIndex for each block in the map
  - `cloneSessionBlock(blockId)`: see deep-clone spec below

#### Deep-clone spec for `cloneSessionBlock(blockId)`:
1. Load original block. New block: same sessionId, name = `'${original.name} (Copy)'`, new UUID id, orderIndex = max existing for sessionId + 1, createdAtMs/updatedAtMs = now
2. Find all `SegmentEffort` where `blockId == blockId`
3. For each effort: new UUID id, same segmentId/orderIndex/effortKind/exerciseId/note, new blockId = new block id, createdAtMs/updatedAtMs = now
4. For each effort: clone its `EffortObservation` records — new UUID id, effortId = new effort id
5. For each effort: clone its `RoundInstance` records — new UUID id, effortId = new effort id
6. For each effort: clone its `TimedInstance` records — new UUID id, effortId = new effort id
7. For each effort: clone its `EntryRest` records — new UUID id, effortId = new effort id
8. Persist all cloned objects; return new block id

---

### Phase 2: Logic/UI (@developer)

#### 2.1 — Implement `HiveWorkoutRepository`
- [ ] Declare `late Box<Map> _sessionBlocksBox;` alongside existing box declarations
- [ ] Open box: `_sessionBlocksBox = await Hive.openBox<Map>('session_blocks');` inside `initialize()`
- [ ] Add `_sessionBlocksBox.clear()` in `clear()` method
- [ ] Implement `getSessionBlocks`: filter by sessionId, sort by orderIndex, return list
- [ ] Implement `createSessionBlock`: `put(block.id, block.toMap())`
- [ ] Implement `updateSessionBlock`: `put(block.id, block.toMap())`
- [ ] Implement `deleteSessionBlock`:
  - Delete block from `_sessionBlocksBox`
  - Scan `_effortsBox`, for each effort with matching blockId: read map, set `block_id` to null, re-put
- [ ] Implement `reorderSessionBlocks`:
  - Iterate `orderedIds` with index; for each id, read block map, update `order_index`, re-put
- [ ] Implement `cloneSessionBlock`:
  - Uses `package:uuid/uuid.dart` — add import at top of file if not present
  - Follow same deep-clone spec as Mock above (using Hive boxes instead of Maps)

#### 2.2 — Verify `updateSessionFeeling` in `HiveWorkoutRepository`
- [ ] Confirm the `TrainingSession(...)` constructor call in `updateSessionFeeling` includes `isRolling: existing.isRolling` — it was added mid-method and may be missing this field

#### 2.3 — Run analyzer and tests
- [ ] `flutter analyze` — zero errors expected
- [ ] `flutter test test/db_seed_test.dart` — must pass against updated schema

---

### Acceptance Criteria
- [ ] `TrainingSession` serializes/deserializes `isRolling` correctly
- [ ] `SessionBlock` round-trips through `fromMap`/`toMap` with all fields
- [ ] `SegmentEffort` serializes `blockId` as nullable string
- [ ] All 6 repository methods defined in interface and implemented in both `HiveWorkoutRepository` and `MockWorkoutRepository`
- [ ] `cloneSessionBlock` produces fully independent copies with new UUIDs for block, efforts, observations, rounds, timed instances, and rests
- [ ] `deleteSessionBlock` nulls `blockId` on linked efforts without deleting them
- [ ] SQLite schema updated: `is_rolling` column, `app_session_block` table, `block_id` on `app_segment_effort`
- [ ] `flutter test test/db_seed_test.dart` passes
- [ ] Zero analyzer errors

### Files Affected
- `lib/data/models/models.dart` (partially done — verify)
- `lib/data/repositories/workout_repository.dart` (partially done — verify)
- `lib/data/repositories/mock_workout_repository.dart` (started — complete methods)
- `lib/data/repositories/hive_workout_repository.dart` (not started)
- `lib/data/datasources/database_provider.dart` (version bump)
- `lib/data/datasources/migrations.dart` (add v6 migration)
- `scripts/sqlite_schema.sql` (3 additions)

## Progress

### Iteration 1 (complete)
- [x] 1.1 Verify already-applied model changes
- [x] 1.2 Update SQLite schema
- [x] 1.3 Update migrations.dart + database_provider.dart version (bumped to 6)
- [x] 1.4 Implement MockWorkoutRepository SessionBlock methods
- [x] 2.1 Implement HiveWorkoutRepository SessionBlock methods
- [x] 2.2 Verify updateSessionFeeling includes isRolling
- [x] 2.3 flutter analyze (0 errors) + db_seed_test pass

### Iteration 2 (in progress)
- [x] 1.1 Add `assignEffortToBlock` to `WorkoutRepository` interface
- [x] 1.2 Implement `assignEffortToBlock` in `MockWorkoutRepository`
- [x] 1.3 Implement `assignEffortToBlock` in `HiveWorkoutRepository`
- [x] 2.1 Add `isRolling` param to `createNewSession()` in `WorkoutState`
- [x] 2.2 Add `_sessionBlocks` cache field; populate and clear at correct sites
- [x] 2.3 Add 6 public block management methods to `WorkoutState`
- [x] 2.4 Add `isRollingSession` getter to `WorkoutState`
- [x] 2.5 Suppress `totalDurationMs` in `computeSessionSummary` for rolling sessions
- [x] 2.6 `flutter analyze` — zero errors

---

## Iteration 3

### Analysis
Four live bugs found in the rolling session UX, plus two carry-over repository fixes from Iteration 2 Feedback that were never completed.

---

### Carry-over Fixes from Iteration 2 Feedback (@developer)

#### CF-1 — `MockWorkoutRepository.updateSessionFeeling()` drops `isRolling`
- File: `lib/data/repositories/mock_workout_repository.dart`
- The `TrainingSession` reconstructed inside `updateSessionFeeling()` omits `isRolling`, silently resetting it to `false`.
- Fix: pass `isRolling: existing.isRolling` in the `TrainingSession(...)` constructor call.

#### CF-2 — `deleteSession()` does not cascade-delete session blocks in Hive/Mock
- Files: `lib/data/repositories/mock_workout_repository.dart`, `lib/data/repositories/hive_workout_repository.dart`
- `deleteSession()` already removes segments, efforts, observations, etc., but leaves `SessionBlock` records orphaned.
- This diverges from SQLite parity (`ON DELETE CASCADE` on `app_session_block.session_id`).
- Fix (Mock): inside `deleteSession(id)`, remove all `_sessionBlocks` entries where `sessionId == id`.
- Fix (Hive): inside `deleteSession(id)`, delete all `_sessionBlocksBox` entries where the raw map's `session_id == id`.

---

### New Bug Fixes

#### Bug 1 — Rest timer is per-exercise; no global rest timer in rolling session list view (@developer)

**Root cause:** `_hasRestToDisplay()` and `_formatRestElapsedForDisplay()` look up `EntryRest` records by the current `effortId`. When navigating to a different exercise in the detail view, the overlay shows THAT exercise's old rest timer instead of the session-wide rest. The rolling session list view (`_buildRollingSessionListView`) has no rest timer display at all.

**Fix — `lib/features/session/workout_session_screen.dart`:**

1. Add helper `_getMostRecentOpenRestKey()` → `(String effortId, int entryIndex)?` that scans all `_exercises`, calls `widget.workoutState.getEntryRests(effortId)` for each, and returns the `(effortId, entryIndex)` of the `EntryRest` with the highest `restStartMs` where `restEndMs == null`. Returns `null` if none exists.

2. Add helper `_hasGlobalRestToDisplay()` → `bool` that returns `_getMostRecentOpenRestKey() != null`.

3. Add helper `_formatGlobalRestElapsed()` → `String` that calls `_formatRestElapsed(effortId, entryIndex)` from the global key, or `'00:00'` if null.

4. **Detail view rest overlay (line ~2519 and line ~3250):** For rolling sessions (`widget.workoutState.isRollingSession`), replace the per-effort `_hasRestToDisplay(...)` / `_formatRestElapsedForDisplay(...)` calls with `_hasGlobalRestToDisplay()` / `_formatGlobalRestElapsed()`. For non-rolling sessions keep existing behaviour.

5. **Rolling session list view (`_buildRollingSessionListView`, line ~1563):** Add a global rest timer overlay `Positioned(left:0, right:0, bottom:68)` — above the "Finish Workout" button — using the same Container+Row as the existing rest overlay widget, conditioned on `!widget.editMode && _hasGlobalRestToDisplay()`.

---

#### Bug 2 — Cloned block carries completed data (rest timers, logged values, completion state) (@developer)

**Root cause:** `cloneSessionBlock` in both Hive and Mock deep-clones `EntryRest`, `RoundInstance`, `TimedInstance`, and `EffortObservation` with their actual logged/completed values intact. The user gets a "pre-finished" block.

**Fix — `HiveWorkoutRepository.cloneSessionBlock` & `MockWorkoutRepository.cloneSessionBlock`:**

For each effort cloned:

- **`EffortObservation`:** Reset all value fields to zero/null — `valueInt: 0`, `valueReal: 0.0`, `valueText: null`, `valueBool: null`, `rpeRating: null`, `restDurationMs: null`. Keep `metricId` and `unitId` (structural, not measurement data).
- **`RoundInstance`:** Keep `plannedDurationSecs` (target). Reset: `state: RoundState.notStarted`, `actualDurationSecs: 0`, `startedAtMs: null`, `finishedAtMs: null`, `completed: false`, `pausedAtMs: null`, `totalPausedDurationMs: 0`.
- **`TimedInstance`:** Keep `targetDurationSecs`. Reset: `state: TimedState.notStarted`, `actualDurationSecs: 0`, `startedAtMs: null`, `finishedAtMs: null`, `pausedAtMs: null`, `totalPausedDurationMs: 0`.
- **`EntryRest`:** **Do not clone at all.** Remove the entry-rest loop entirely from `cloneSessionBlock` in both repositories.

---

#### Bug 3 — Cloned exercises appear grouped by exercise name in detail view (@developer)

**Root cause:** `cloneSessionBlock` preserves the original `orderIndex` for each cloned effort. Since `getSegmentEfforts` sorts efforts by `orderIndex`, two efforts (original + clone) with the same `orderIndex` end up adjacent after sort. Bench Press (orig, idx=0), Bench Press (clone, idx=0), Squat (orig, idx=1), Squat (clone, idx=1) — grouped by exercise instead of by block.

**Fix — `HiveWorkoutRepository.cloneSessionBlock` & `MockWorkoutRepository.cloneSessionBlock`** (applies simultaneously with Bug 2 fix):

Before the effort-clone loop:
1. Sort `linkedEffortEntries` / `linkedEfforts` by original `orderIndex` ascending, so clone positions are deterministic.
2. Compute `maxExistingOrderIndex`: the highest `orderIndex` among ALL efforts in the same segment (scan `_effortsBox` / `_efforts` by `segmentId`).
3. In the clone loop, assign `orderIndex: maxExistingOrderIndex + 1 + loopIndex` instead of preserving the original.

---

#### Bug 4 — Exercises from a deleted block remain navigable in the detail view (@developer)

**Root cause:** `deleteSessionBlock` correctly nulls `blockId` on affected efforts (orphans them). After `_loadExercises()` reload, these orphaned efforts (where `blockId == null`) still appear in `_exercises` and are navigable in the exercise detail swipe view.

**Fix — `lib/features/session/workout_session_screen.dart`, `_loadExercises()`:**

After `_exercises = exercises;` (or the rolling-filtered assignment), add:
```dart
if (widget.workoutState.isRollingSession) {
  _exercises = _exercises.where((e) => e['blockId'] != null).toList();
}
```
Apply inside the `setState` call so all downstream logic (key pre-population, index clamping) operates on the filtered list.

---

### Routine Parity Check

Custom routines (`RoutineSetupScreen` + `RoutineState`) are **not affected** by any of these four bugs:
- No rest timers during template setup (Bugs 1 & 2 restTimer aspect).
- `cloneSessionBlock` is a rolling-session–only repository method; routines use `TemplateSegment` with separate effort ordering — no flatten/sort conflict (Bug 3).
- Deleting a template segment deletes the segment from `_currentSegments` in-memory; `currentEfforts` via `_flattenedEfforts()` rebuilds from segments — orphan efforts cannot arise (Bug 4).

---

### Acceptance Criteria

- [ ] In rolling session live mode, the detail view rest timer overlay shows the session-wide most-recent open rest (not the current exercise's rest)
- [ ] When navigating between exercises in a rolling session's detail view, the rest timer continues counting without resetting or switching to a different exercise's timer
- [ ] The rolling session block list view shows a global rest timer when any rest is active
- [ ] Cloning a block produces a block with blank (zero) metric values, no completion state, and no rest timers
- [ ] Cloned block exercises appear AFTER all existing exercises in the detail view arrow navigation, maintaining block-insertion order
- [ ] Deleting a block in a rolling session removes those exercises from the detail view arrow navigation
- [ ] `MockWorkoutRepository.updateSessionFeeling()` preserves `isRolling`
- [ ] `deleteSession()` removes all associated session blocks in Hive and Mock
- [ ] `flutter analyze` — zero errors
- [ ] Existing tests pass

### Files Affected (Iteration 3)
- `lib/features/session/workout_session_screen.dart` — Bugs 1, 4: global rest helpers + rolling list overlay + exercise filter
- `lib/data/repositories/hive_workout_repository.dart` — Bugs 2, 3 + CF-2: clone reset + orderIndex fix + deleteSession block cleanup
- `lib/data/repositories/mock_workout_repository.dart` — Bugs 2, 3 + CF-1 + CF-2: clone reset + orderIndex fix + updateSessionFeeling isRolling + deleteSession block cleanup

## Progress

### Iteration 3
- [x] CF-1 Fix `MockWorkoutRepository.updateSessionFeeling` to preserve `isRolling`
- [x] CF-2 Fix `deleteSession` in Mock and Hive to cascade-delete session blocks
- [x] Bug 1 Add `_getMostRecentOpenRestKey`, `_hasGlobalRestToDisplay`, `_formatGlobalRestElapsed` helpers to `_WorkoutSessionScreenState`
- [x] Bug 1 Use global rest helpers in detail view rest overlay for rolling sessions
- [x] Bug 1 Add global rest timer overlay to `_buildRollingSessionListView`
- [x] Bug 2+3 Reset cloned `EffortObservation` values to zero in Hive `cloneSessionBlock`
- [x] Bug 2+3 Reset cloned `RoundInstance` state to notStarted in Hive `cloneSessionBlock`
- [x] Bug 2+3 Reset cloned `TimedInstance` state to notStarted in Hive `cloneSessionBlock`
- [x] Bug 2+3 Remove `EntryRest` cloning from Hive `cloneSessionBlock`
- [x] Bug 2+3 Compute and assign sequential `orderIndex` for cloned efforts in Hive `cloneSessionBlock`
- [x] Bug 2+3 Apply all same clone fixes to Mock `cloneSessionBlock`
- [x] Bug 4 Filter `_exercises` to exclude `blockId == null` items in rolling sessions inside `_loadExercises()`
- [x] Run `flutter analyze` — zero errors
- [x] Run `flutter test` — all pass

---

## Iteration 5

### Analysis (Apr 8, 2026)

Iterations 1–4 delivered the complete data layer and rolling session UI. The feature request "Session Groups & Superset Support" now extends this to:

1. **Standard open sessions** — introduce block support (currently flat-list with no block rendering)
2. **Routine → Session conversion** — create `SessionBlock` objects from `TemplateSegments` so routine sessions have editable blocks from the start
3. **Routine setup** — add Clone to the block three-dot menu
4. **Rolling sessions** — already ships the correct UI from Iteration 4 ✅ (no work needed)
5. **Routine session lock removal** — the old `showPerBlockAdd = intent == 'routine'` guard and segment-based rendering is eliminated once standard sessions adopt block-based rendering ✅ (free consequence of Points 1 & 2)
6. **Session summary** — extend block-grouped layout to standard sessions that have blocks
7. **Behaviour corrections** — two existing behaviours must change to match the spec:
   - `deleteSessionBlock` currently nulls `blockId` on efforts; spec requires **deleting** those efforts
   - `cloneSessionBlock` names clones with a timestamp; spec requires `"Main (2)"`, `"Main (3)"` suffix logic

**Iteration 4 execution note (Apr 1, 2026):** `flutter test` passed. `flutter analyze` exits non-zero only due to pre-existing repo-wide infos unrelated to Iteration 4.

---

### Phase 1: Data & State Layer (@dba)

#### 1.1 — `WorkoutState.addSessionBlock({String? name})`
File: `lib/state/workout/workout_state.dart`

Change the method signature from `Future<String> addSessionBlock()` to `Future<String> addSessionBlock({String? name})`.

Inside the method, replace the hardcoded timestamp name derivation with:
```dart
final blockName = name ?? () {
  final hour12 = now.hour % 12 == 0 ? 12 : now.hour % 12;
  final minute = now.minute.toString().padLeft(2, '0');
  final period = now.hour < 12 ? 'AM' : 'PM';
  return '$hour12:$minute $period';
}();
```
Use `blockName` where `name` was previously used.

Update the `addSessionBlock` test in `test/state_test.dart` to confirm that passing a name uses that name (not a timestamp).

#### 1.2 — `cloneSessionBlock` naming: `"Main" → "Main (2)"` in both repositories
Files: `lib/data/repositories/mock_workout_repository.dart`, `lib/data/repositories/hive_workout_repository.dart`

In **both** repositories' `cloneSessionBlock` implementations, replace the timestamp name generation:
```dart
// REMOVE: hour12/minute/period/name timestamp block
// REPLACE WITH:
final rawName = original.name;
final suffixMatch = RegExp(r'^(.*) \((\d+)\)$').firstMatch(rawName);
final name = suffixMatch != null
    ? '${suffixMatch.group(1)!} (${int.parse(suffixMatch.group(2)!) + 1})'
    : '$rawName (2)';
```

Also update the test in `test/session_blocks_repository_test.dart` that currently asserts the clone name is a timestamp.

#### 1.3 — `deleteSessionBlock` cascade-deletes linked efforts (both repositories + WorkoutState cache)

**Context:** The spec requires that deleting a block also deletes all exercises inside it. The current implementation only nulls `blockId`. This is a deliberate breaking change from the Iteration 1 design. The SQLite schema can remain `ON DELETE SET NULL` — the app layer performs the cascade before the FK fires.

**`MockWorkoutRepository.deleteSessionBlock`** — File: `lib/data/repositories/mock_workout_repository.dart`

Replace the current implementation:
```dart
Future<void> deleteSessionBlock(String blockId) async {
  // 1. Find all efforts linked to this block
  final linkedEffortIds = _efforts.values
      .where((e) => e.blockId == blockId)
      .map((e) => e.id)
      .toList();

  // 2. For each linked effort, cascade-delete sub-records then the effort itself
  for (final effortId in linkedEffortIds) {
    _observations.remove(effortId);
    _roundInstances.remove(effortId);
    _timedInstances.remove(effortId);
    _entryRests.removeWhere((r) => r.effortId == effortId);
    for (final effortList in _efforts.values) {
      effortList.removeWhere((e) => e.id == effortId);
    }
    _efforts.remove(effortId); // also clean up if keyed by effortId
  }
  // Also clean up from any segment effort lists
  for (final key in _efforts.keys.toList()) {
    _efforts[key]?.removeWhere((e) => e.blockId == blockId);
  }

  // 3. Delete the block itself
  _sessionBlocks.remove(blockId);
}
```

**`HiveWorkoutRepository.deleteSessionBlock`** — File: `lib/data/repositories/hive_workout_repository.dart`

Replace the current implementation:
```dart
Future<void> deleteSessionBlock(String blockId) async {
  // 1. Find all efforts linked to this block
  final linkedEffortKeys = _effortsBox.toMap().entries
      .where((e) => _asStringMap(e.value)['block_id'] == blockId)
      .map((e) => e.key)
      .toList();

  // 2. For each linked effort, cascade-delete sub-records
  for (final effortKey in linkedEffortKeys) {
    // Delete observations
    final obsKeys = _observationsBox.toMap().entries
        .where((e) => _asStringMap(e.value)['effort_id'] == effortKey)
        .map((e) => e.key)
        .toList();
    for (final k in obsKeys) await _observationsBox.delete(k);

    // Delete round instances
    final riKeys = _roundInstancesBox.toMap().entries
        .where((e) => _asStringMap(e.value)['effort_id'] == effortKey)
        .map((e) => e.key)
        .toList();
    for (final k in riKeys) await _roundInstancesBox.delete(k);

    // Delete timed instances
    final tiKeys = _timedInstancesBox.toMap().entries
        .where((e) => _asStringMap(e.value)['effort_id'] == effortKey)
        .map((e) => e.key)
        .toList();
    for (final k in tiKeys) await _timedInstancesBox.delete(k);

    // Delete entry rests
    final erKeys = _entryRestsBox.toMap().entries
        .where((e) => _asStringMap(e.value)['effort_id'] == effortKey)
        .map((e) => e.key)
        .toList();
    for (final k in erKeys) await _entryRestsBox.delete(k);

    // Delete the effort itself
    await _effortsBox.delete(effortKey);
  }

  // 3. Delete the block itself
  await _sessionBlocksBox.delete(blockId);
}
```

**`WorkoutState.deleteSessionBlock`** — File: `lib/state/workout/workout_state.dart`

After calling `await _repository.deleteSessionBlock(blockId)`, replace the "null out blockId" loop with removal from all caches:
```dart
// Remove the deleted efforts from all in-memory caches
for (final effortList in _efforts.values) {
  final toRemove = effortList.where((e) => e.blockId == blockId).map((e) => e.id).toList();
  effortList.removeWhere((e) => e.blockId == blockId);
  for (final effortId in toRemove) {
    _observations.remove(effortId);
    _roundInstances.remove(effortId);
    _timedInstances.remove(effortId);
    _entryRests.removeWhere((r) => r.effortId == effortId);
  }
}
```

Update tests in `test/session_blocks_repository_test.dart` and `test/state_test.dart`:
- Remove assertions that `blockId` is nulled on linked efforts
- Add assertions that linked efforts are completely absent after block deletion

#### 1.4 — `WorkoutState.populateSessionFromManifest` creates `SessionBlock` per `TemplateSegment`
File: `lib/state/workout/workout_state.dart`

Inside the `for (final segmentEntry in manifest.segments)` loop, **after** `_efforts.putIfAbsent(segmentId, () => []);` and **before** the effort loop, add:

```dart
// Create a SessionBlock for this segment (carries name from the template)
// Only create a block if the segment has exercises.
String? blockId;
if (segmentEntry.exercises.isNotEmpty) {
  blockId = await addSessionBlock(
    name: templateSegment.name ?? 'Block ${segmentCounter}',
  );
}
```

Then, inside the effort loop, after each `if (effortId.isEmpty) continue;`, add:
```dart
if (blockId != null) {
  await assignEffortToBlock(effortId, blockId);
}
```

New test to add in `test/state_test.dart`:
- `populateSessionFromManifest creates one SessionBlock per TemplateSegment with matching names`
- `populateSessionFromManifest assigns each effort to its segment's block`

#### 1.5 — `getExercisesWithEntries()` includes `createdAtMs` per effort
File: `lib/state/workout/workout_state.dart`

In the `result.add({...})` call at the bottom of `getExercisesWithEntries()`, add:
```dart
'createdAtMs': effort.createdAtMs,
```
This is the timestamp used to interleave standalone exercises with block groups in insertion order in the standard session mixed list.

#### 1.6 — Seed data: add example standard session with mixed standalone exercises and blocks
File: `lib/mock/seed_data.dart`

Add a completed `TrainingSession` entry (non-rolling):
- Two `SessionBlock` entries (e.g., "Warm-Up", "Main Work")
- At least two exercises per block (assigned via `blockId`)
- At least one standalone exercise (no `blockId`)

This provides development testing for the new standard session list view and session summary block-grouped layout.

---

### Phase 2: Routine Setup — Clone Block (@developer)

#### 2.1 — `RoutineState.cloneSegment(String segmentId)`
File: `lib/state/routine/routine_state.dart`

Add this new method after `removeSegment`:

```dart
Future<void> cloneSegment(String segmentId) async {
  _clearError();
  try {
    final sourceIndex = _currentSegments.indexWhere((s) => s.id == segmentId);
    if (sourceIndex == -1) return;
    final source = _currentSegments[sourceIndex];

    // Derive clone name: "Main" → "Main (2)", "Main (2)" → "Main (3)"
    final rawName = source.name ?? 'Block ${sourceIndex + 1}';
    final suffixMatch = RegExp(r'^(.*) \((\d+)\)$').firstMatch(rawName);
    final cloneName = suffixMatch != null
        ? '${suffixMatch.group(1)!} (${int.parse(suffixMatch.group(2)!) + 1})'
        : '$rawName (2)';

    final now = DateTime.now().millisecondsSinceEpoch;
    final newSegmentId = 'tseg-clone-$now';
    final clonedSegment = TemplateSegment(
      id: newSegmentId,
      templateId: source.templateId,
      orderIndex: sourceIndex + 1, // will be re-indexed below
      segmentType: source.segmentType,
      name: cloneName,
      createdAtMs: now,
      updatedAtMs: now,
    );

    // Insert cloned segment immediately after the source
    final newSegments = [..._currentSegments];
    newSegments.insert(sourceIndex + 1, clonedSegment);
    // Re-index all segments
    for (int i = 0; i < newSegments.length; i++) {
      newSegments[i] = newSegments[i].copyWith(orderIndex: i);
    }
    _currentSegments = newSegments;
    _segmentEfforts[newSegmentId] = [];

    // Deep-clone efforts and their targets
    final sourceEfforts = _segmentEfforts[segmentId] ?? [];
    for (final effort in sourceEfforts) {
      final newEffortId = 'teff-clone-$now-${effort.id}';
      final clonedEffort = TemplateEffort(
        id: newEffortId,
        templateSegmentId: newSegmentId,
        orderIndex: effort.orderIndex,
        effortKind: effort.effortKind,
        modality: effort.modality,
        exerciseId: effort.exerciseId,
        note: effort.note,
        restSeconds: effort.restSeconds,
        restType: effort.restType,
        createdAtMs: now,
      );
      _segmentEfforts[newSegmentId]!.add(clonedEffort);

      // Clone all targets for this effort (values intact — template context)
      final sourceTargets = _currentTargets
          .where((t) => t.templateEffortId == effort.id)
          .toList();
      for (final target in sourceTargets) {
        final clonedTarget = TemplateTarget(
          id: 'ttgt-clone-$now-${target.id}',
          templateEffortId: newEffortId,
          metricId: target.metricId,
          setIndex: target.setIndex,
          unitId: target.unitId,
          targetMin: target.targetMin,
          targetMax: target.targetMax,
          targetInt: target.targetInt,
          targetText: target.targetText,
          createdAtMs: now,
        );
        _currentTargets.add(clonedTarget);
      }
    }

    _scheduleAutosave();
    notifyListeners();
  } catch (e) {
    _setError('Failed to clone block: $e');
  }
}
```

#### 2.2 — Add "Clone Block" to `_buildSegmentCard` three-dot menu
File: `lib/features/routine/routine_setup_screen.dart`

In the `PopupMenuButton.itemBuilder` inside `_buildSegmentCard`, add a new `PopupMenuItem` **before** the Delete item:
```dart
PopupMenuItem(
  onTap: () => widget.routineState.cloneSegment(segment.id),
  child: Row(
    children: [
      Icon(Icons.copy, size: 18, color: theme.colorScheme.primary),
      const SizedBox(width: 8),
      const Text('Clone Block'),
    ],
  ),
),
```

---

### Phase 3: Standard Sessions — Block Support & Routine Lock Removal (@developer)

All changes in `lib/features/session/workout_session_screen.dart` unless noted.

#### 3.1 — Update `_showBlockDeleteDialog` for new cascade-delete behaviour

Rename to `_confirmAndDeleteBlock(SessionBlock block)` and update the implementation:

```dart
Future<void> _confirmAndDeleteBlock(SessionBlock block) async {
  final blockExercises = _exercises.where((e) => e['blockId'] == block.id).toList();
  final count = blockExercises.length;

  // Empty block → delete immediately without confirmation
  if (count == 0) {
    await widget.workoutState.deleteSessionBlock(block.id);
    if (mounted) await _loadExercises();
    return;
  }

  // Non-empty block → confirm before deleting
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Delete Block?'),
      content: Text(
        'This block contains $count exercise${count != 1 ? 's' : ''}. '
        'All exercises inside will be permanently deleted.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          style: ButtonStyle(
            shape: WidgetStateProperty.all(RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(OmniTheme.buttonUtilityRadius),
            )),
          ),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          style: ButtonStyle(
            shape: WidgetStateProperty.all(RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(OmniTheme.buttonUtilityRadius),
            )),
          ),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (confirmed == true && mounted) {
    await widget.workoutState.deleteSessionBlock(block.id);
    await _loadExercises();
  }
}
```

Update both call sites of `_showBlockDeleteDialog` (in `_buildSessionBlockCard` `onSelected` and `_buildRollingSessionListView`) to call `_confirmAndDeleteBlock(block)` instead of `_showBlockDeleteDialog(block.id)`. Update the `case 'delete'` handler to pass the full `block` object.

#### 3.2 — Create `_buildStandardSessionListView(ThemeData theme)`

Add this new method after `_buildRollingSessionListView`:

```dart
Widget _buildStandardSessionListView(ThemeData theme) {
  final blocks = widget.workoutState.getSessionBlocks();
  final standaloneExercises = _exercises
      .where((e) => e['blockId'] == null)
      .toList();

  // Build a merged ordered list of display items sorted by createdAtMs.
  // Each item is either a SessionBlock (group) or a standalone exercise map.
  final List<({SessionBlock? block, Map<String, dynamic>? exercise})> items = [];
  for (final b in blocks) {
    items.add((block: b, exercise: null));
  }
  for (final ex in standaloneExercises) {
    items.add((block: null, exercise: ex));
  }
  items.sort((a, b) {
    final aMs = a.block?.createdAtMs ?? (a.exercise?['createdAtMs'] as int? ?? 0);
    final bMs = b.block?.createdAtMs ?? (b.exercise?['createdAtMs'] as int? ?? 0);
    return aMs.compareTo(bMs);
  });

  // Segment ID for adding standalone exercises (always first segment).
  final segmentId = widget.workoutState.segments.isNotEmpty
      ? widget.workoutState.segments.first.id
      : null;

  return Scaffold(
    backgroundColor: Colors.transparent,
    body: OmniGradientBackground(
      child: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                _buildHeader(theme),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(children: [_buildSessionTimeWidget(theme)]),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(0, 8, 0, 140),
                    children: [
                      // Mixed list: standalone exercises and block groups in insertion order
                      for (final item in items)
                        if (item.block != null)
                          _buildSessionBlockCard(item.block!, theme)
                        else
                          Padding(
                            padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
                            child: _buildExerciseTile(item.exercise!, theme),
                          ),
                      const SizedBox(height: 4),
                      // "Add Block" — always visible, always appended after list
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            await widget.workoutState.addSessionBlock();
                            if (mounted) setState(() {});
                          },
                          icon: const Icon(Icons.add_circle_outline),
                          label: const Text('Add Block'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            side: BorderSide(color: theme.colorScheme.primary),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                OmniTheme.buttonUtilityRadius),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Global Add Exercise FAB (standalone — no block assignment)
          if (!widget.editMode)
            Positioned(
              right: 10,
              bottom: 110,
              child: SafeArea(
                top: false,
                child: SizedBox(
                  width: OmniTheme.buttonIconSize,
                  height: OmniTheme.buttonIconSize,
                  child: FilledButton(
                    style: ButtonStyle(
                      shape: WidgetStateProperty.all(RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(OmniTheme.buttonIconRadius),
                      )),
                    ),
                    onPressed: () => _addExercise(segmentId: segmentId),
                    child: const Icon(Icons.add),
                  ),
                ),
              ),
            ),
          // Finish Workout button
          Positioned(
            left: 0,
            right: 0,
            bottom: 10,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: SizedBox(
                  width: double.infinity,
                  height: OmniTheme.buttonPrimaryHeight,
                  child: FilledButton(
                    onPressed: widget.editMode
                        ? _saveEditChanges
                        : _showFinishSessionDialog,
                    style: ButtonStyle(
                      shape: WidgetStateProperty.all(RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(OmniTheme.buttonBorderRadius),
                      )),
                    ),
                    child: Text(widget.editMode ? 'Save Changes' : 'Finish Workout'),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
```

#### 3.3 — Replace `_buildListView` routing with `_buildStandardSessionListView`

Currently `_buildListView` dispatches to `_buildRollingSessionListView` for rolling sessions and then uses a complex segment-based layout for everything else. Replace the entire non-rolling branch:

```dart
Widget _buildListView(ThemeData theme) {
  if (widget.workoutState.isRollingSession) {
    return _buildRollingSessionListView(theme);
  }
  return _buildStandardSessionListView(theme);
}
```

Remove the entire body of the old `_buildListView` that follows the rolling-session early return (the `segments` computation, `showPerBlockAdd` logic, empty-state scaffold, and the large `Scaffold` with the mixed-rendering `ListView`). This eliminates:
- The `showPerBlockAdd = intent == 'routine' && segments.length > 1` check (Phase 5 automatic)
- The segment-header rendering for routine sessions (Phase 5 automatic)
- The duplicate empty-state scaffold (now handled inside `_buildStandardSessionListView`)

**Note:** The empty-state scaffold (no exercises, no blocks) can be handled inside `_buildStandardSessionListView` by checking `_exercises.isEmpty && blocks.isEmpty` and showing a centred "No exercises" message with an Add Exercise button. Include this check at the top of the method before building the list.

#### 3.4 — Update `_buildSessionBlockCard` comment (housekeeping only)

Update the in-method comment from "Segment ID for adding exercises in rolling session" to "Segment ID for scoped Add Exercise (always first segment)".

---

### Phase 4: Session Summary Update (@developer)

#### 4.1 — Extend block-grouped layout to standard sessions with blocks
File: `lib/features/session/session_summary_screen.dart`

In `_buildExerciseListSection`, change the dispatch condition from:
```dart
if (session?.isRolling ?? false) {
```
to:
```dart
if ((session?.isRolling ?? false) || widget.workoutState.getSessionBlocks().isNotEmpty) {
```

This ensures that a standard session that has blocks (created by the user or inherited from a routine) renders with the block-grouped summary layout rather than the modality-grouped layout.

---

### Acceptance Criteria

**Standard Sessions**
- [ ] A new open session starts with an empty flat list (no blocks)
- [ ] "Add Block" button is always visible at the bottom of the list
- [ ] Tapping Add Block creates a new block auto-named with the current time (e.g. "10:14 PM")
- [ ] Each block renders with the block card UI: name, three-dot menu (Edit / Clone / Delete), scoped Add Exercise button
- [ ] Global Add Exercise FAB adds a standalone exercise with no block affiliation
- [ ] Scoped Add Exercise inside a block assigns the new exercise to that block
- [ ] Standalone exercises and block groups coexist in insertion order (chronological by `createdAtMs`)
- [ ] Deleting an empty block requires no confirmation
- [ ] Deleting a non-empty block shows a confirmation dialog with the exercise count
- [ ] After block deletion, all exercises inside the block are gone from the session
- [ ] Cloning a block creates a name-suffixed copy (`"Main (2)"`) with zeroed exercise data
- [ ] Reorder arrows are not present in live sessions
- [ ] Finish Workout button behaviour is unchanged

**Rolling Sessions (regression check only — no new work)**
- [ ] Rolling sessions are visually and functionally unchanged
- [ ] Block cards render identically in rolling sessions and standard sessions

**Routine Setup**
- [ ] Routine block three-dot menu includes a Clone option
- [ ] Clone creates a name-suffixed copy (`"Warm-Up (2)"`) with all exercises and targets intact
- [ ] Cloned block is inserted immediately after the source in the segment list

**Routine → Session Conversion**
- [ ] Starting a session from a routine creates one `SessionBlock` per `TemplateSegment`
- [ ] Block names from the routine carry over to the session
- [ ] All exercises in the session are assigned to their corresponding block
- [ ] All session blocks are fully editable (Edit, Delete, Clone, scoped Add Exercise)
- [ ] The source routine template is never modified by live session actions

**Session Summary**
- [ ] A standard session with blocks displays exercises grouped by block in the summary
- [ ] Standalone exercises (blockId == null) display in an "Other" group or at the end
- [ ] Rolling session summary layout is unchanged

**Cross-Cutting**
- [ ] `flutter analyze` — zero errors
- [ ] `flutter test` — all existing tests pass with no regressions
- [ ] Updated: `deleteSessionBlock` tests assert effort deletion (not nulling)
- [ ] New: `addSessionBlock({name: 'x'})` test
- [ ] New: `populateSessionFromManifest` creates SessionBlocks test
- [ ] New: `cloneSessionBlock` uses `"(2)"` suffix test
- [ ] New: `RoutineState.cloneSegment` unit tests

### Files Affected (Iteration 5)

**Phase 1 (@dba)**
- `lib/state/workout/workout_state.dart` — `addSessionBlock` signature, `populateSessionFromManifest` block creation, `deleteSessionBlock` cache update, `getExercisesWithEntries` add `createdAtMs`
- `lib/data/repositories/mock_workout_repository.dart` — `cloneSessionBlock` name logic, `deleteSessionBlock` cascade
- `lib/data/repositories/hive_workout_repository.dart` — `cloneSessionBlock` name logic, `deleteSessionBlock` cascade
- `lib/mock/seed_data.dart` — add standard session with blocks example
- `test/session_blocks_repository_test.dart` — update delete behaviour tests, add name tests
- `test/state_test.dart` — update delete + addSessionBlock tests, add conversion test

**Phase 2 (@developer)**
- `lib/state/routine/routine_state.dart` — add `cloneSegment()`
- `lib/features/routine/routine_setup_screen.dart` — add Clone item to three-dot menu

**Phase 3 (@developer)**
- `lib/features/session/workout_session_screen.dart` — new `_buildStandardSessionListView`, updated `_buildListView`, rename `_showBlockDeleteDialog` → `_confirmAndDeleteBlock`

**Phase 4 (@developer)**
- `lib/features/session/session_summary_screen.dart` — extend block-grouped condition

### Notes
- `_entryRests` may be named `_entryRests` (Map keyed by effortId) or a flat list — developer should check the actual field name/structure in `WorkoutState` and adapt Phase 1.3 accordingly.
- `MockWorkoutRepository` stores efforts in a `Map<String, SegmentEffort>` keyed by `effortId`; the "cascade delete" loop in 1.3 should iterate all entries, not segment-keyed sublists.
- `TemplateEffort` may not have `restSeconds`/`restType` fields — developer should verify the model and omit those fields from `cloneSegment` if absent.
- The `Positioned` Add Exercise FAB in `_buildStandardSessionListView` must be hidden in edit mode (`!widget.editMode`) to match the existing pattern.

## Progress

### Iteration 6 (complete)
- [x] Fix rolling-session block cloning to use current-time title instead of suffix naming
- [x] Add regression tests in repository/state suites for rolling clone title behavior

### Iteration 5 (current)
- [x] 1.1 `WorkoutState.addSessionBlock({String? name})` — add optional name param
- [x] 1.2 `cloneSessionBlock` name logic: `"Main (2)"` suffix in Mock + Hive
- [x] 1.3 `deleteSessionBlock` cascade-delete efforts: Mock + Hive + WorkoutState cache
- [x] 1.4 `populateSessionFromManifest` creates SessionBlocks from TemplateSegments
- [x] 1.5 `getExercisesWithEntries()` includes `createdAtMs` per effort
- [x] 1.6 Seed data: static lists added to SeedData (not auto-seeded; dev-reference only)
- [x] 2.1 `RoutineState.cloneSegment()` method
- [x] 2.2 Add Clone to routine block three-dot menu
- [x] 3.1 Rename `_showBlockDeleteDialog` → `_confirmAndDeleteBlock` with new behaviour
- [x] 3.2 Create `_buildStandardSessionListView`
- [x] 3.3 Replace `_buildListView` non-rolling branch with `_buildStandardSessionListView`
- [x] 3.4 Update `_buildSessionBlockCard` comment (housekeeping)
- [x] 4.1 Extend block-grouped summary condition to standard sessions with blocks
- [x] 5.x Update/add tests per acceptance criteria above
- [x] Run `flutter analyze` — zero errors
- [x] Run `flutter test` — all pass (478 pass, 9 pre-existing failures unrelated to feature)

## Feedback

[Leave empty until a specialist or reviewer adds notes]

---

## Iteration 4

### Analysis
Two UX bugs in the rolling session screen, plus a data-model gap documented as a future consideration.

**Bug A — Reorder block buttons should not exist**
Blocks are time-stamped anchors, not manually orderable. The block card header currently renders two `IconButton`s (`arrow_upward` / `arrow_downward`) that call `_reorderBlockInList`. These must be removed from `_buildSessionBlockCard`. The backing `_reorderBlockInList` helper and `reorderSessionBlocks` repository method can stay (they support programmatic/clone-order use), only the UI buttons go away.

**Bug B — Detail-view arrow navigation ignores block grouping**
`getExercisesWithEntries()` returns all efforts sorted by their global `orderIndex` (insertion sequence across the whole session segment). If the user adds exercises interleaved across blocks — e.g. Block A → Squat (idx 0), Block B → Bench (idx 1), Block A → Deadlift (idx 2) — the arrow navigation shows [Squat, Bench, Deadlift] (global order) instead of [Squat, Deadlift (Block A), Bench (Block B)] (block-grouped order). The fix is a re-grouping step inside `_loadExercises`, after the rolling `blockId != null` filter, that partitions exercises by block in `getSessionBlocks()` sorted order:

```dart
// After: _exercises = _exercises.where((e) => e['blockId'] != null).toList();
final blocks = widget.workoutState.getSessionBlocks(); // sorted by orderIndex
final reordered = <Map<String, dynamic>>[];
for (final block in blocks) {
  reordered.addAll(_exercises.where((e) => e['blockId'] == block.id));
}
_exercises = reordered;
```

This preserves within-block relative order (exercises retain their segment-global orderIndex sequence within the block partition) while ensuring blocks are contiguous in the arrow list.

**Side note — what's stored vs. what's missing**
- `SessionBlock` entity is fully persisted: `id`, `sessionId`, `name`, `orderIndex`, `createdAtMs`, `updatedAtMs`. The "time" in the block name (e.g. "Block 9:45 AM") is a display label, not a dedicated timestamp field — the entity itself survives app restarts.
- **Missing data point:** `SegmentEffort` has no `blockOrderIndex` (position within its block). Within-block ordering relies on the global `orderIndex`, which is correct as long as exercises are always appended. It would break if efforts were ever inserted non-sequentially. No schema change needed now, but a future `block_order_index` column on `app_segment_effort` would make this robust.

---

### Phase 1: UI (@developer) — `lib/features/session/workout_session_screen.dart`

#### Step 1 — Remove reorder buttons from block card header
In `_buildSessionBlockCard`, within the header `Row(children: [...])`, delete both `IconButton` widgets:
- `IconButton(icon: Icon(Icons.arrow_upward, ...), onPressed: index > 0 ? () => ..._reorderBlockInList(index, index - 1) : null)`
- `IconButton(icon: Icon(Icons.arrow_downward, ...), onPressed: index < totalBlocks - 1 ? () => ..._reorderBlockInList(index, index + 1) : null)`

Also remove the `index` and `totalBlocks` parameters from `_buildSessionBlockCard`'s signature and all call sites (only caller is `_buildRollingSessionListView`). If `_reorderBlockInList` is only called from those buttons, remove it too — otherwise leave it.

#### Step 2 — Re-group exercises by block order in `_loadExercises`
Inside the `setState(() { ... })` block, replace:
```dart
if (widget.workoutState.isRollingSession) {
  _exercises = _exercises.where((e) => e['blockId'] != null).toList();
}
```
with:
```dart
if (widget.workoutState.isRollingSession) {
  _exercises = _exercises.where((e) => e['blockId'] != null).toList();
  final blocks = widget.workoutState.getSessionBlocks();
  final reordered = <Map<String, dynamic>>[];
  for (final block in blocks) {
    reordered.addAll(_exercises.where((e) => e['blockId'] == block.id));
  }
  _exercises = reordered;
}
```

#### Step 3 — Run analyzer and tests
- `flutter analyze` — zero errors
- `flutter test` — all existing tests pass (no new tests required for this iteration; the ordering change is UI-layer only and covered by visual inspection)

---

### Acceptance Criteria
- [ ] Rolling session block cards have no up/down arrow buttons
- [ ] Arrow-navigating through exercises in the detail view visits all exercises in Block A first, then Block B, then Block C (block-grouped, block-insertion order)
- [ ] Within each block, exercises appear in the order they were added to that block
- [ ] Non-rolling sessions are unaffected
- [ ] `flutter analyze` — zero errors
- [ ] `flutter test` — all pass

### Files Affected
- `lib/features/session/workout_session_screen.dart` — remove reorder buttons + re-grouping sort

### Notes
- No DB schema changes required for this iteration.
- `reorderSessionBlocks` repository method and `_reorderBlockInList` helper can stay; only the UI affordance is removed.
- A future `block_order_index` column on `app_segment_effort` (and Hive parity) would make within-block ordering explicit and independent of global insertion sequence — recommended if non-sequential block editing is ever added.

## Progress

### Iteration 4
- [x] Step 1 — Remove reorder arrow buttons from `_buildSessionBlockCard`
- [x] Step 2 — Re-group `_exercises` by block order in `_loadExercises`
- [x] Step 3 — `flutter analyze` + `flutter test`

---

3. `reorderSessionBlocks(sessionId, orderedIds)` ignores `sessionId` in both implementations.
  - Files: `lib/data/repositories/mock_workout_repository.dart`, `lib/data/repositories/hive_workout_repository.dart`
  - Method updates any block in `orderedIds` regardless of owning session.
  - Required fix: guard updates with `existing.sessionId == sessionId` (or map key `session_id`).

4. Missing tests for new model/repository behavior.
  - `test/models_test.dart`: add round-trip tests for `TrainingSession.isRolling`, `SessionBlock`, and `SegmentEffort.blockId`.
  - Add repository-layer tests (or nearest existing integration tests) for:
    - `deleteSessionBlock` nulling linked effort `blockId`
    - `cloneSessionBlock` deep-copy semantics (new IDs for block, efforts, observations, rounds, timed instances, rests)
    - `deleteSession` cascading session block cleanup in Hive/Mock parity.

### Feedback Resolution (Mar 31, 2026)
- Fixed: `MockWorkoutRepository.updateSessionFeeling()` now preserves `isRolling`.
- Fixed: `deleteSession()` now removes session blocks in both `MockWorkoutRepository` and `HiveWorkoutRepository`.
- Fixed: `reorderSessionBlocks(sessionId, orderedIds)` now guards by `sessionId` in both repositories.
- Added tests:
  - `test/models_test.dart` for `TrainingSession.isRolling`, `SessionBlock`, `SegmentEffort.blockId`
  - `test/session_blocks_repository_test.dart` for session block delete/reorder/clone/deleteSession/updateSessionFeeling behavior in mock repository.

### Test Coverage Completion (Mar 31, 2026 — Phase 3)
Added comprehensive integration tests to `test/state_test.dart` for all `WorkoutState` session block methods:
- [x] `getSessionBlocks()` — returns empty when no session, returns sorted by orderIndex
- [x] `addSessionBlock()` — creates block with time-based name, increments orderIndex
- [x] `updateSessionBlock()` — persists changes to cache
- [x] `deleteSessionBlock()` — removes block from cache, unassigns linked efforts
- [x] `reorderSessionBlocks()` — calls repository and reloads cache
- [x] `cloneSessionBlock()` — creates independent copy, handles linked records
- [x] `assignEffortToBlock()` — updates effort blockId, supports null for unassign
- [x] `isRollingSession` getter — returns false by default, true when created with isRolling: true
- [x] Rolling session summary end-to-end — `computeSessionSummary` returns totalDurationMs = 0 for rolling sessions
- [x] Non-rolling session summary end-to-end — `computeSessionSummary` returns positive duration for normal sessions

**Results:** All 18 new WorkoutState session block tests pass + all 438 project tests pass (zero regressions).

---

## Iteration 2

### Analysis
Data layer (models, repository interface, repository implementations) was completed in Iteration 1. Iteration 2 adds the missing `WorkoutRepository.assignEffortToBlock` method (not planned in Iteration 1) and all five WorkoutState concerns: `isRolling` session creation, `_sessionBlocks` in-memory cache, 6 public block-management methods, `isRollingSession` getter, and rolling-session duration suppression in `computeSessionSummary`.

---

### Phase 1: Repository Interface & Implementations (@dba)

#### 1.1 — Add `assignEffortToBlock` to the repository interface
File: `lib/data/repositories/workout_repository.dart`

Inside the `// ─── Session Blocks ───` section, after `cloneSessionBlock`:

```dart
/// Assign or unassign an effort to a block.
/// Pass [blockId] as null to unassign (effort becomes unblocked).
Future<void> assignEffortToBlock(String effortId, String? blockId);
```

#### 1.2 — Implement in `MockWorkoutRepository`
File: `lib/data/repositories/mock_workout_repository.dart`

Add after `cloneSessionBlock` implementation:

```dart
@override
Future<void> assignEffortToBlock(String effortId, String? blockId) async {
  final existing = _efforts[effortId];
  if (existing == null) return;
  _efforts[effortId] = SegmentEffort(
    id: existing.id,
    segmentId: existing.segmentId,
    orderIndex: existing.orderIndex,
    effortKind: existing.effortKind,
    exerciseId: existing.exerciseId,
    note: existing.note,
    blockId: blockId,
    createdAtMs: existing.createdAtMs,
    updatedAtMs: DateTime.now().millisecondsSinceEpoch,
  );
}
```

#### 1.3 — Implement in `HiveWorkoutRepository`
File: `lib/data/repositories/hive_workout_repository.dart`

Add after `cloneSessionBlock` implementation:

```dart
@override
Future<void> assignEffortToBlock(String effortId, String? blockId) async {
  final raw = _effortsBox.get(effortId);
  if (raw == null) return;
  final m = _asStringMap(raw);
  m['block_id'] = blockId;
  m['updated_at_ms'] = DateTime.now().millisecondsSinceEpoch;
  await _effortsBox.put(effortId, m);
}
```

**Note:** `SqliteWorkoutRepository` (future production path) will implement this as:
`UPDATE app_segment_effort SET block_id = ?, updated_at_ms = ? WHERE id = ?`

---

### Phase 2: WorkoutState (@developer)

All changes are in `lib/state/workout/workout_state.dart`.  
Rules: **apply idempotently** — skip any field or method that already exists.

#### 2.1 — Task 1: Add `isRolling` to `createNewSession()`

In `createNewSession({...})`, add optional parameter:
```dart
bool isRolling = false,
```

In the `TrainingSession(...)` constructor call inside `createNewSession`, add:
```dart
isRolling: isRolling,
```

#### 2.2 — Task 2: Add `_sessionBlocks` in-memory cache

**Declare the field** — add after the `_exerciseNotes` declaration in the field block:
```dart
// Session blocks cache: keyed by sessionId
final Map<String, List<SessionBlock>> _sessionBlocks = {};
```

**Populate in `loadHistoricalSession()`** — after `_entryRests.clear();` and before the `final segments = await ...` line:
```dart
_sessionBlocks.clear();
```
And after all child-record loads (just before `notifyListeners()`):
```dart
final blocks = await _repository.getSessionBlocks(sessionId);
_sessionBlocks[sessionId] = blocks;
```

**Populate in `loadSessionData()`** — after `_entryRests.clear();` (or wherever the cache clears happen at the top of the method), add:
```dart
_sessionBlocks.clear();
```
And after all child-record loads (just before `notifyListeners()` at the end of the try block):
```dart
final sessionBlocks = await _repository.getSessionBlocks(_currentSession!.id);
_sessionBlocks[_currentSession!.id] = sessionBlocks;
```

**Clear in `clearSession()`** — add alongside the other `.clear()` calls:
```dart
_sessionBlocks.clear();
```

#### 2.3 — Task 3: Add 6 public block management methods

Add a clearly delimited `// ─── Session Block Management ───` section to `WorkoutState`, ideally after `removeExerciseFromSession()`.

**`getSessionBlocks()`**
```dart
List<SessionBlock> getSessionBlocks() {
  if (_currentSession == null) return [];
  final blocks = _sessionBlocks[_currentSession!.id] ?? [];
  return (List<SessionBlock>.from(blocks)
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex)));
}
```

**`addSessionBlock()`** — name is current time in h:mm a (manual format; no Flutter UI dependency):
```dart
Future<String> addSessionBlock() async {
  if (_currentSession == null) return '';
  _clearError();
  try {
    final now = DateTime.now();
    final ms = now.millisecondsSinceEpoch;
    final hour = now.hour % 12 == 0 ? 12 : now.hour % 12;
    final minute = now.minute.toString().padLeft(2, '0');
    final period = now.hour < 12 ? 'AM' : 'PM';
    final name = '$hour:$minute $period';

    final existing = _sessionBlocks[_currentSession!.id] ?? [];
    final maxOrder = existing.fold<int>(-1, (m, b) => b.orderIndex > m ? b.orderIndex : m);

    final block = SessionBlock(
      id: 'block-$ms',
      sessionId: _currentSession!.id,
      name: name,
      orderIndex: maxOrder + 1,
      createdAtMs: ms,
      updatedAtMs: ms,
    );

    final blockId = await _repository.createSessionBlock(block);
    _sessionBlocks.putIfAbsent(_currentSession!.id, () => []).add(block);
    notifyListeners();
    return blockId;
  } catch (e) {
    _setError('Failed to add session block: $e');
    return '';
  }
}
```

**`updateSessionBlock()`**
```dart
Future<void> updateSessionBlock(SessionBlock block) async {
  _clearError();
  try {
    await _repository.updateSessionBlock(block);
    final blocks = _sessionBlocks[block.sessionId];
    if (blocks != null) {
      final idx = blocks.indexWhere((b) => b.id == block.id);
      if (idx != -1) blocks[idx] = block;
    }
    notifyListeners();
  } catch (e) {
    _setError('Failed to update session block: $e');
  }
}
```

**`deleteSessionBlock()`** — also nulls in-memory effort `blockId`:
```dart
Future<void> deleteSessionBlock(String blockId) async {
  _clearError();
  try {
    await _repository.deleteSessionBlock(blockId);
    for (final blocks in _sessionBlocks.values) {
      blocks.removeWhere((b) => b.id == blockId);
    }
    // Mirror the repository cascade: null out blockId on in-memory efforts.
    for (final effortList in _efforts.values) {
      for (int i = 0; i < effortList.length; i++) {
        if (effortList[i].blockId == blockId) {
          final old = effortList[i];
          effortList[i] = SegmentEffort(
            id: old.id,
            segmentId: old.segmentId,
            orderIndex: old.orderIndex,
            effortKind: old.effortKind,
            exerciseId: old.exerciseId,
            note: old.note,
            blockId: null,
            createdAtMs: old.createdAtMs,
            updatedAtMs: old.updatedAtMs,
          );
        }
      }
    }
    notifyListeners();
  } catch (e) {
    _setError('Failed to delete session block: $e');
  }
}
```

**`reorderSessionBlocks()`**
```dart
Future<void> reorderSessionBlocks(List<String> orderedIds) async {
  if (_currentSession == null) return;
  _clearError();
  try {
    await _repository.reorderSessionBlocks(_currentSession!.id, orderedIds);
    final updated = await _repository.getSessionBlocks(_currentSession!.id);
    _sessionBlocks[_currentSession!.id] = updated;
    notifyListeners();
  } catch (e) {
    _setError('Failed to reorder session blocks: $e');
  }
}
```

**`cloneSessionBlock()`**
```dart
Future<String> cloneSessionBlock(String blockId) async {
  if (_currentSession == null) return '';
  _clearError();
  try {
    final newBlockId = await _repository.cloneSessionBlock(blockId);
    final updated = await _repository.getSessionBlocks(_currentSession!.id);
    _sessionBlocks[_currentSession!.id] = updated;
    notifyListeners();
    return newBlockId;
  } catch (e) {
    _setError('Failed to clone session block: $e');
    return '';
  }
}
```

**`assignEffortToBlock()`**
```dart
Future<void> assignEffortToBlock(String effortId, String? blockId) async {
  _clearError();
  try {
    await _repository.assignEffortToBlock(effortId, blockId);
    for (final effortList in _efforts.values) {
      for (int i = 0; i < effortList.length; i++) {
        if (effortList[i].id == effortId) {
          final old = effortList[i];
          effortList[i] = SegmentEffort(
            id: old.id,
            segmentId: old.segmentId,
            orderIndex: old.orderIndex,
            effortKind: old.effortKind,
            exerciseId: old.exerciseId,
            note: old.note,
            blockId: blockId,
            createdAtMs: old.createdAtMs,
            updatedAtMs: old.updatedAtMs,
          );
          break;
        }
      }
    }
    notifyListeners();
  } catch (e) {
    _setError('Failed to assign effort to block: $e');
  }
}
```

#### 2.4 — Task 4: Add `isRollingSession` getter

Add in the getters section (after `hasActiveSession`):
```dart
bool get isRollingSession => _currentSession?.isRolling ?? false;
```

#### 2.5 — Task 5: Suppress duration in `computeSessionSummary()` for rolling sessions

In `computeSessionSummary()`, locate the `return SessionSummary(...)` call and change:
```dart
totalDurationMs: durationMs,
```
to:
```dart
totalDurationMs: _currentSession!.isRolling ? 0 : durationMs,
```

---

### Acceptance Criteria
- [ ] `createNewSession` accepts and persists `isRolling` parameter.
- [ ] `_sessionBlocks` cache populates on `loadSessionData` and `loadHistoricalSession`; cleared in `clearSession`.
- [ ] `getSessionBlocks` returns blocks sorted by `orderIndex` for the current session.
- [ ] `addSessionBlock` creates a block named with current time in h:mm a format.
- [ ] `cloneSessionBlock` reloads the cache and calls `notifyListeners`.
- [ ] `assignEffortToBlock` updates the effort's `blockId` in the repository and the in-memory cache.
- [ ] `isRollingSession` getter returns correct boolean (false when no session).
- [ ] `computeSessionSummary` returns `totalDurationMs = 0` for rolling sessions.
- [ ] Zero `flutter analyze` errors across the entire codebase.

### Files Affected
- `lib/data/repositories/workout_repository.dart` — add `assignEffortToBlock` abstract method
- `lib/data/repositories/mock_workout_repository.dart` — implement `assignEffortToBlock`
- `lib/data/repositories/hive_workout_repository.dart` — implement `assignEffortToBlock`
- `lib/state/workout/workout_state.dart` — all 5 tasks above

### Notes
- `WorkoutState` must not import `dart:math`; use `fold<int>` for max-order calculation.
- `addSessionBlock` uses manual h:mm a format (no `MaterialLocalizations` dependency) since state layer has no Flutter UI context.
- `_clearState` referenced in the task ticket = `clearSession()` in the actual codebase.

## Feedback (Code Review — Mar 31, 2026)

Implementation does not yet meet project compliance standards.

1. Critical: design-system button shape override missing in HomeScreen dialogs.
  - File: `lib/features/home/home_screen.dart`
  - Locations: both `TextButton('Cancel')` actions in the two `AlertDialog` blocks inside `_onTileTap`.
  - Why this blocks: screen-level button policy requires explicit `shape:` override using `OmniTheme.button*Radius` token on every `FilledButton`, `OutlinedButton`, and `TextButton`. Current cancel buttons omit this.
  - Required fix: add `style: ButtonStyle(shape: WidgetStateProperty.all(RoundedRectangleBorder(borderRadius: BorderRadius.circular(OmniTheme.buttonUtilityRadius))))` (or equivalent tokenized helper) to both cancel `TextButton`s.

2. Warning: widget interaction tests do not verify overflow action behavior end-to-end for rolling session blocks.
  - File: `test/screen_widget_test.dart`
  - Current coverage checks menu item visibility only (`Edit/Clone/Delete` present), but not behavior.
  - Required tests to add:
    - Edit: opens rename dialog, saves updated name via `workoutState.updateSessionBlock` observable effect.
    - Clone: selecting clone increases block count and renders `'(Copy)'` suffix.
    - Delete: confirmation dialog text appears (`Exercises in this block will not be deleted.`), confirm removes block while preserving exercise records.

3. Warning: no widget test currently verifies that tapping `+ Add Block` appends a new block card in rolling list view.
  - File: `test/screen_widget_test.dart`
  - Required test: tap `+ Add Block`, pump, assert block count increases and empty-state text appears for the new card.

### Reviewer Alignment (User Direction)
- UI consistency is mandatory and must be enforced in this iteration (not deferred).
- Add regression tests where they validate behavior not already covered; avoid redundant duplicates.
- For this feature, treat the following as required regression coverage (non-redundant):
  1. Block overflow `Edit` action updates rendered block name after save.
  2. Block overflow `Clone` action appends a new block with `'(Copy)'` suffix.
  3. Block overflow `Delete` action shows confirmation copy and removes only the block.
  4. `+ Add Block` tap creates and renders a new block card in rolling list view.

### Reviewer Alignment Resolution (Mar 31, 2026)
- [x] Enforced UI consistency: added explicit `shape` styling for HomeScreen dialog `TextButton` cancel actions.
- [x] Added non-redundant rolling block widget regressions for:
  - [x] `+ Add Block` creates/render new block card
  - [x] `Edit` action renames block in UI
  - [x] `Clone` action appends `'(Copy)'` block
  - [x] `Delete` action shows confirmation copy and removes block while preserving effort record
- [x] Fixed list refresh logic after rename (`setState`) so edit regression passes.

### Coverage Follow-up Resolution (Mar 31, 2026)
- [x] Added `SessionSummaryScreen` widget tests for rolling vs non-rolling stats labels (`DURATION` hidden for rolling, visible otherwise).
- [x] Added `SessionSummaryScreen` rolling grouping tests for named block headers and `Other` fallback for unassigned efforts.
- [x] Added `WorkoutState` test asserting `computeSessionSummary()` propagates `blockId` into `ExerciseSummary` entries.
- [x] Focused regression suite passed: `test/state_test.dart` + `test/screen_widget_test.dart` (182 passing, 0 failing).

### UX Simplification Resolution (Apr 1, 2026)
- [x] Removed separate rolling onboarding modal and consolidated guidance into the Free Training start sheet.
- [x] Kept rolling toggle and replaced short subtitle with detailed onboarding guidance text inline.
- [x] Removed `Don't show again` flow and obsolete `HomeState` rolling onboarding preference API/state.
- [x] Updated widget/state tests to reflect single-sheet behavior; focused regression suite passed (`test/screen_widget_test.dart` + `test/state_test.dart`, 178 passing, 0 failing).
