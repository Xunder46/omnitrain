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
| `restIsPaused` | `bool` | PR 4: `true` while the rest window is in the paused state. PR 4 hides the running elapsed count until resumed. |
| `restPausedAtMs` | `int?` | PR 4: wall-clock instant when the rest was paused; `elapsedSeconds` freezes at this value. `null` when not paused. |
| `restPausedDurationMs` | `int` | PR 4: cumulative paused time across all pause/resume cycles for this rest. Subtracted from the running duration so the recorded rest excludes stopped intervals. |
| `createdAtMs` | `int` | Creation timestamp |
| `updatedAtMs` | `int` | Last modified timestamp |

### Computed Helper

```dart
// Returns elapsed rest seconds; paused freezes at restPausedAtMs,
// running reads from nowMs. Subtracts restPausedDurationMs so the
// recorded rest excludes stopped intervals.
int elapsedSeconds(int nowMs) {
  final effectiveEndMs = restEndMs ??
      (restIsPaused ? (restPausedAtMs ?? nowMs) : nowMs);
  return ((effectiveEndMs - restStartMs - restPausedDurationMs) / 1000)
      .round()
      .clamp(0, 99999);
}
```

---

## SQLite Schema

**File**: `scripts/sqlite_schema.sql`

```sql
CREATE TABLE app_entry_rest (
  id                       TEXT    NOT NULL PRIMARY KEY,
  effort_id                TEXT    NOT NULL,
  entry_index              INTEGER NOT NULL,
  rest_start_ms            INTEGER NOT NULL,
  rest_end_ms              INTEGER,           -- NULL while athlete is still resting
  rest_is_paused           INTEGER NOT NULL DEFAULT 0, -- PR 4: 1 = paused, 0 = running
  rest_paused_at_ms        INTEGER,                    -- PR 4: wall-clock pause time
  rest_paused_duration_ms  INTEGER NOT NULL DEFAULT 0, -- PR 4: cumulative paused duration
  created_at_ms            INTEGER NOT NULL,
  updated_at_ms            INTEGER NOT NULL,
  FOREIGN KEY(effort_id) REFERENCES app_segment_effort(id) ON DELETE CASCADE
);
CREATE UNIQUE INDEX IF NOT EXISTS UX_entry_rest_effort_index
    ON app_entry_rest(effort_id, entry_index);

-- PR 4 migration: add pause/resume columns on existing installs.
ALTER TABLE app_entry_rest ADD COLUMN rest_is_paused INTEGER NOT NULL DEFAULT 0;
ALTER TABLE app_entry_rest ADD COLUMN rest_paused_at_ms INTEGER;
ALTER TABLE app_entry_rest ADD COLUMN rest_paused_duration_ms INTEGER NOT NULL DEFAULT 0;
```
```

The `ON DELETE CASCADE` constraint ensures rest records are removed automatically when their parent effort is deleted.

### Migration

`scripts/sqlite_schema.sql` contains the `CREATE TABLE IF NOT EXISTS
app_entry_rest` statement.

> **Corrected 2026-07-26 (docs audit).** This line pointed at
> `lib/data/datasources/migrations.dart`. That file was deleted when the
> SQLite runtime was retired; schema statements now live in
> `scripts/sqlite_schema.sql` itself. See
> [DB Integration](db_integration.md#sqlite-schema-versioning).

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
| `pauseRest` | `(String effortId, int entryIndex) → Future<void>` | PR 4: Sets `restIsPaused = true` and stamps `restPausedAtMs = now`. No-op when the rest is already paused or closed. |
| `resumeRest` | `(String effortId, int entryIndex) → Future<void>` | PR 4: Accumulates the paused interval (`now - restPausedAtMs`) into `restPausedDurationMs` and clears `restIsPaused`. No-op when the rest is already running or closed. |
| `isRestPaused` | `(String effortId, int entryIndex) → bool` | PR 4: Returns the `restIsPaused` flag for the given rest. Drives the overlay chip's running/paused branch. |
| `persistOpenRests` | `(int closeAtMs) → Future<void>` | Closes all still-open rest records at session end using a shared wall-clock timestamp |
| `getRestElapsedSeconds` | `(String effortId, int entryIndex) → int` | Returns live elapsed seconds for display (uses wall-clock `now` when `restEndMs` is null; freezes at `restPausedAtMs` while paused; subtracts `restPausedDurationMs` so the recorded value excludes stopped time) |
| `hasRestRecord` | `(String effortId, int entryIndex) → bool` | Returns true if a rest record exists for this entry; drives overlay visibility |

### Record Lifecycle

```
_logSet() or round completed
  → recordRestStart(effortId, nextEntryIndex)  // creates open rest record

Next set _logSet() called
  → recordRestEnd(effortId, entryIndex)         // closes rest, stops elapsed growth
  → recordRestStart(effortId, nextEntryIndex)   // opens new rest

Effort timer started (timed / drill / round)
  → closeAllOpenRests(effortId)                // closes every open rest for that effort

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
| Timed/drill timer started | `unawaited(workoutState.closeAllOpenRests(effortId))` |
| Round started (notStarted → active) | `unawaited(workoutState.closeAllOpenRests(effortId))` |

All calls use the existing `unawaited()` fire-and-forget pattern used throughout the screen.

### Overlay Display

The rest overlay chip is rendered on **every** surface by `_buildRestOverlayChip`
inside `lib/features/session/workout_session_list_view.dart` (rolling list view,
standard list view, detail view). Visibility is governed by the single helper
`_shouldShowRestOverlay()` defined on `_SessionGlobalTimerExt` in
`lib/features/session/workout_session_global_timer.dart`:

```dart
// Session-wide visibility rule shared by every rest-chip Positioned(...) site.
bool _shouldShowRestOverlay() {
  if (widget.editMode) return false;
  if (_getMostRecentOpenRestKey() == null) return false;
  // Any effort active in the session hides the chip.
  for (final entry in _effortRunning.entries) {
    if (entry.value == true) return false;
  }
  return true;
}
```

Both the **list view** (session-detail) and the **detail view** (per-exercise)
route through this helper, so the two surfaces can never disagree about whether
to show a counting rest timer. Even a cross-effort rest (a rest open for
exercise A's entry while a timer is running on exercise B) is hidden on every
surface while that timer is active.

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

The current chip is **tappable**. PR 4 wraps the chip in `Material` + `InkWell`
whose `onTap` calls `_toggleRestChip`, which dispatches to `workoutState.pauseRest`
or `workoutState.resumeRest` based on the current `isRestPaused` flag. The chip
has a 48-dp touch-target floor (vertical padding 12 + minHeight 48) so the
whole tile is hittable without aiming for a small icon.

Three visually distinct states (PR 4 spec: "Three rest states are visually
distinct without reading the number"):

| State | Background tint | Icon | Extra chrome |
|-------|-----------------|------|--------------|
| **Running** (default, rest just opened) | Primary-tinted | `Icons.self_improvement` (meditation) | (none) |
| **Paused** (after tap) | Muted surface tint | `Icons.pause` | (none) |
| **Not started** (no open rest for the session) | — (chip hidden entirely) | — | — |

`_shouldShowRestOverlay()` (above) hides the chip in the not-started case.
The running/paused branches share the same chip widget; the icon swap is
the sole differentiator (background tint + icon). The chip's bounding
rect is intentionally identical in both states — no shadow, no border —
so the user can read the same timer without layout jumping.

> **Removed 2026-07-27 (PR 4 refinement).** Earlier drafts of PR 4 carried
> a "Paused · tap to resume" caption under the timer in the paused state.
> That caption made the chip 2dp taller than the running chip (because of
> the wrapped `Column`) and the feedback was deemed redundant with the
> icon swap. The chip is now single-line in both states.

Pause/resume behaviour:

- Tap-pause captures the wall-clock instant as `restPausedAtMs` so the
  elapsed display freezes on the next `_ticker` tick (≤ 1s later).
- Tap-resume adds the stopped interval (`now - restPausedAtMs`) to
  `restPausedDurationMs` and clears the paused flag; the displayed
  elapsed count resumes from the frozen value with stopped time
  excluded from the recorded duration.
- Reloading during a paused window restores the exact `restPausedAtMs`
  stamp so the chip continues to display the same frozen count.
- Closing the rest (via `recordRestEnd`/`closeAllOpenRests`/`persistOpenRests`)
  uses `_effectiveRestEndMs` which honours the paused instant — a paused
  rest is closed at `restPausedAtMs`, never at `now`, so the recorded
  duration never includes stopped time.

Logging the next entry or starting an effort timer still closes open rest as described above.

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

`EffortObservation.restDurationMs` remains in the canonical SQL schema documentation, but it only applied to `set`-kind efforts and was never populated in the UI. `EntryRest` supersedes it for all effort kinds. The column is not part of the retired SQLite runtime path; no live persistence migration is needed to remove it.

---

## Edit Mode Behavior

Rest records are **never created or mutated during edit mode** (`WorkoutSessionScreen.editMode == true`). The `session_edit_snapshot.dart` does not snapshot rest records because edit mode does not trigger new set logging.

---

## Related Documentation

- [Modality-Based Exercise UI](modality_based_exercise_ui.md) — Timer architecture and rest overlay UX
- [Data Models](data_models.md) — `EntryRest` model definition
- [DB Integration](db_integration.md) — `app_entry_rest` table and migration

---

**Document Version**: 1.1
**Last Updated**: July 27, 2026


---

> **Doc freshness** — Last reconciled against source: 2026-07-27. This doc is derived from source, not hand-maintained. Source of truth: the `lib/` tree as it exists on the reconciliation date. If you find a claim here that disagrees with `lib/`, `lib/` wins — please flag the drift in a fresh chat with the Coordinator agent.
