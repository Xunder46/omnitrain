# Rest Tracking — Architecture & Feature Documentation

## Overview

OmniTrain uses **wall-clock-persisted rest records** to track recovery time between sets and rounds across all exercise types. Rest data survives app backgrounding and session reloads because it is derived from epoch timestamps rather than an in-memory `Stopwatch`.

---

## Why Wall-Clock Rest Tracking

The original implementation used a `Stopwatch` + `Timer.periodic` inside `WorkoutSessionScreen` to track rest. This had two problems:

1. **No persistence** — rest elapsed reset to zero if the user navigated away or the OS suspended the app.
2. **Effort-kind limited** — the old `EffortObservation.restDurationMs` field only covered `set`-kind efforts. Round and timed efforts had no rest tracking at all.

The replacement architecture stores a per-entry rest record in the repository at the moment a set is logged, and derives elapsed time on-demand from `now - restStartMs`.

---

## `EntryRest` Model

**File**: `lib/data/models/models.dart`

| Field | Type | Description |
|-------|------|-------------|
| `id` | `String` | Deterministic key: `'rest-{effortId}-{entryIndex}'` |
| `effortId` | `String` | Parent `SegmentEffort` id |
| `entryIndex` | `int` | 0-based; identifies the set/round **this rest precedes** |
| `restStartMs` | `int` | Wall-clock epoch ms when the previous set was logged |
| `restEndMs` | `int?` | Wall-clock epoch ms when the next set/round was started; `null` while still resting |
| `createdAtMs` | `int` | Creation timestamp |
| `updatedAtMs` | `int` | Last modified timestamp |

### Computed Helper

```dart
// Returns elapsed rest seconds; live value if restEndMs is null.
int elapsedSeconds(int nowMs) =>
    (((restEndMs ?? nowMs) - restStartMs) / 1000).round().clamp(0, 99999);
```

---

## SQLite Schema

**File**: `scripts/sqlite_schema.sql`

```sql
CREATE TABLE app_entry_rest (
  id                TEXT    NOT NULL PRIMARY KEY,
  effort_id         TEXT    NOT NULL,
  entry_index       INTEGER NOT NULL,
  rest_start_ms     INTEGER NOT NULL,
  rest_end_ms       INTEGER,           -- NULL while athlete is still resting
  created_at_ms     INTEGER NOT NULL,
  updated_at_ms     INTEGER NOT NULL,
  FOREIGN KEY(effort_id) REFERENCES app_segment_effort(id) ON DELETE CASCADE
);
CREATE UNIQUE INDEX IF NOT EXISTS UX_entry_rest_effort_index
    ON app_entry_rest(effort_id, entry_index);
```

The `ON DELETE CASCADE` constraint ensures rest records are removed automatically when their parent effort is deleted.

### Migration

`lib/data/datasources/migrations.dart` contains a `CREATE TABLE IF NOT EXISTS app_entry_rest` migration for existing databases.

---

## Repository Contract

**File**: `lib/data/repositories/workout_repository.dart`

```dart
// Entry Rest
Future<List<EntryRest>> getEntryRests(String effortId);
Future<String>          createEntryRest(EntryRest rest);
Future<void>            updateEntryRest(EntryRest rest);
Future<void>            deleteEntryRestsForEffort(String effortId);
```

`deleteEntryRestsForEffort` is called inside `deleteEffort()` in both `HiveWorkoutRepository` and `MockWorkoutRepository` so cleanup is automatic.

### Hive Implementation

- Box name: `'entry_rests'`
- Key: `rest.id`
- `getEntryRests(effortId)` scans the box and filters by `effortId`

### Mock Implementation

- In-memory `Map<String, EntryRest> _entryRests = {}`
- Follows the same patterns as `_observations`

---

## WorkoutState Integration

**File**: `lib/state/workout/workout_state.dart`

### In-Memory Cache

```dart
final Map<String, List<EntryRest>> _entryRests = {};
```

Populated during `loadSessionData()` and `loadHistoricalSession()` alongside observations and rounds. Cleared in `_clearState()`.

### Public API

| Method | Signature | Purpose |
|--------|-----------|---------|
| `getEntryRests` | `(String effortId) → List<EntryRest>` | Returns unmodifiable list of rest records for an effort |
| `recordRestStart` | `(String effortId, int entryIndex) → Future<void>` | Creates rest record with current epoch time as `restStartMs`; called after a set is logged |
| `recordRestEnd` | `(String effortId, int entryIndex) → Future<void>` | Updates `restEndMs` on the open rest record; called when the athlete starts the next set/round |
| `persistOpenRests` | `(int closeAtMs) → Future<void>` | Closes all still-open rest records at session end using a shared wall-clock timestamp |
| `getRestElapsedSeconds` | `(String effortId, int entryIndex) → int` | Returns live elapsed seconds for display (uses wall-clock `now` when `restEndMs` is null) |
| `hasRestRecord` | `(String effortId, int entryIndex) → bool` | Returns true if a rest record exists for this entry; drives overlay visibility |

### Record Lifecycle

```
_logSet() or round completed
  → recordRestStart(effortId, nextEntryIndex)  // creates open rest record

Next set _logSet() called
  → recordRestEnd(effortId, entryIndex)         // closes rest, stops elapsed growth
  → recordRestStart(effortId, nextEntryIndex)   // opens new rest

Effort timer started (timed / drill / round)
  → recordRestEnd(effortId, entryIndex)         // closes rest on timer start

Session ends via endSession()
  → persistOpenRests(endedAtMs)                 // closes any still-open rest at session end
```

For the **first set** of an exercise (`entryIndex == 0`), no rest record is created — the overlay correctly stays hidden because `hasRestRecord(effortId, 0)` returns `false`.

---

## WorkoutSessionScreen Integration

**File**: `lib/features/session/workout_session_screen.dart`

The old `Stopwatch`-based rest state has been removed:

```dart
// REMOVED:
Timer? _restTimer;
Stopwatch? _restStopwatch;
int _restElapsedSeconds = 0;
String _restFormatted = '00:00';
// _startRestTimer() method removed entirely
```

### Wiring

| Event | Action |
|-------|--------|
| Set logged (`_logSet`) | `unawaited(workoutState.recordRestStart(effortId, nextEntryIndex))` |
| Next set begins (`_logSet`) | `unawaited(workoutState.recordRestEnd(effortId, currentEntryIndex))` |
| Timed/drill timer started | `unawaited(workoutState.recordRestEnd(effortId, entryIndex))` |
| Round started (notStarted → active) | `unawaited(workoutState.recordRestEnd(effortId, entryIndex))` |

All calls use the existing `unawaited()` fire-and-forget pattern used throughout the screen.

### Overlay Display

Rest overlay visibility is driven by `workoutState.hasRestRecord(effortId, entryIndex)`.

Elapsed time is rendered by:

```dart
String _formatRestElapsed(String effortId, int entryIndex) {
  final secs = widget.workoutState.getRestElapsedSeconds(effortId, entryIndex);
  final mm = (secs ~/ 60).toString().padLeft(2, '0');
  final ss = (secs % 60).toString().padLeft(2, '0');
  return '$mm:$ss';
}
```

The overlay refreshes on every `_ticker` tick (1 second, already exists for round timers) — no additional `Timer.periodic` is required.

---

## Effort Kind Coverage

| Effort Kind | Rest Created After | Rest Closed By |
|-------------|-------------------|----------------|
| `set` | Each `_logSet` call | Next `_logSet` call |
| `round` | Each completed/ended round | `_toggleEffortTimer` (next round start) |
| `timed` | Each logged timed entry | Timer start for next entry |
| `drill` | Each logged drill entry | Timer start for next entry |

---

## Resistance Modality `_isSetLogged` Fix

As part of the full rest tracking implementation, the `_isSetLogged()` method was corrected for `set`-kind efforts.

**Previous behavior**: returned `true` as soon as `reps > 0` was entered (before the athlete tapped "Log Set"), which caused `_loggedSetKeys` to be pre-populated and rest creation to be skipped.

**Corrected behavior**: for `set`-kind efforts, `_isSetLogged()` now checks whether a rest record already exists for that entry index. This ensures only actual "Log Set" completions count as logged.

---

## Relationship to Legacy `EffortObservation.restDurationMs`

`EffortObservation.restDurationMs` already exists and is stored in the SQLite schema, but it only applied to `set`-kind efforts and was never populated in the UI. `EntryRest` supersedes it for all effort kinds. The column remains in the schema unused — no migration is needed to remove it.

---

## Edit Mode Behavior

Rest records are **never created or mutated during edit mode** (`WorkoutSessionScreen.editMode == true`). The `session_edit_snapshot.dart` does not snapshot rest records because edit mode does not trigger new set logging.

---

## Related Documentation

- [Modality-Based Exercise UI](modality_based_exercise_ui.md) — Timer architecture and rest overlay UX
- [Data Models](data_models.md) — `EntryRest` model definition
- [DB Integration](db_integration.md) — `app_entry_rest` table and migration

---

**Document Version**: 1.0
**Last Updated**: March 22, 2026
