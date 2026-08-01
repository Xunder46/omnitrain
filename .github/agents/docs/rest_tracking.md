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

**File**: `lib/data/models/models.dart` — see [Data Models](data_models.md) for the record's place
in the model graph.

One rest record per `(effortId, entryIndex)` pair, identified by a deterministic id so the same
entry always maps to the same record. The record stores wall-clock instants, not a counter: when
the rest started, when it ended (`null` while still resting), whether it is currently paused, when
it was paused, and how much paused time has accumulated.

Elapsed rest is **derived at read time**, never stored. A paused rest freezes at its pause instant;
a running rest reads from now; accumulated paused time is subtracted so the recorded rest excludes
stopped intervals.

## Schema

The `app_entry_rest` table is defined in `scripts/sqlite_schema.sql`, which
`test/db_seed_test.dart` executes to prove it stays valid SQL. Two constraints matter beyond the
column list: rest records are unique per `(effort_id, entry_index)`, and they cascade on delete
with their parent effort so cleanup is automatic rather than something callers must remember.

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

The old `Stopwatch`-based rest state has been removed from the session screen entirely.

### Wiring

| Event | Action |
|-------|--------|
| Set logged (`_logSet`) | `unawaited(workoutState.recordRestStart(effortId, nextEntryIndex))` |
| Next set begins (`_logSet`) | `unawaited(workoutState.recordRestEnd(effortId, currentEntryIndex))` |
| Timed/drill timer started | `unawaited(workoutState.closeAllOpenRests(effortId))` |
| Round started (notStarted → active) | `unawaited(workoutState.closeAllOpenRests(effortId))` |

All calls use the existing `unawaited()` fire-and-forget pattern used throughout the screen.

### Overlay Display

The rest overlay chip renders on **every** session surface — rolling list view, standard list view,
and detail view — and all of them gate visibility through a **single shared helper**. This is the
invariant: the two surfaces can never disagree about whether a rest timer is counting, because
neither owns the decision. A cross-effort rest (open for exercise A while a timer runs on exercise
B) is hidden everywhere while that timer is active, and edit mode hides the chip outright.

Verified by `test/unified_rest_overlay_test.dart` (`Unified rest overlay rule`).

The chip is tappable across its whole tile, so pausing or resuming rest never requires aiming at a small icon.

The chip distinguishes its states without requiring the user to read the number, and its bounding
rect is identical in every state so the timer never jumps as it changes.

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
