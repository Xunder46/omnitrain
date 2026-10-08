# Rest Tracking — Architecture & Feature Documentation

## Overview

OmniTrain uses **wall-clock-persisted rest records** to track recovery time between sets and rounds across all exercise types. Rest data survives app backgrounding and session reloads because it is derived from epoch timestamps rather than an in-memory `Stopwatch`.

---

## The rule: rest is a count-up

Rest is a count-up from the moment a set is logged to the moment the next set starts. There is no
preset rest length, no rest countdown and no end-of-rest alarm on any device
([Global Conventions](global_conventions.md), "Rest rule: rest is a count-up";
`docs/plans/2026-10-08-18b-watch-rest-count-up-plan`, D-160). A routine's stored `restSeconds` is a
prescription read at routine setup, never a timer (D-168). The one allowed rest cue is the rest ping:
a repeating nudge at each multiple of the Rest Ping interval while a rest is open, on the device that
holds the rest, and it reaches the phone and the watch from that one setting — a haptic tap and no
sound on the wrist, and never a countdown ([Theme and Settings](theme_and_settings.md); Dart
`test/watch_rest_ping_test.dart`, `S-241 an interval of 30 polled every second from 0 to 100 taps at 30,
60 and 90 and nowhere else`; Swift `WatchRestPingTests.testS241AnIntervalTapsAtItsMultiplesAndNowhereElse`).
Every rest record on the wire carries no length, and the shared contract refuses one
(`test/sync_protocol_fixtures_test.dart`,
`S-165 the wire refuses a rest length` — `a rest carries no planned length, a round keeps one, and a
rest with one is refused`). `test/rest_is_count_up_contract_test.dart` fails if a scanned tree
reintroduces a preset rest length or a rest countdown.

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
  → closeAllOpenRestsInMemory(effortId)        // closes every open rest IN-MEMORY immediately
  → closeAllOpenRests(effortId) async          // persists the close to repository asynchronously

Session ends via endSession()
  → persistOpenRests(endedAtMs)                 // closes any still-open rest at session end
```

For the **first set** of an exercise (`entryIndex == 0`), no rest record is created — the overlay correctly stays hidden because `hasRestRecord(effortId, 0)` returns `false`.

### Rest Record Lifecycle — Synchronous Close on Effort Start

When a timed, round, or drill effort timer starts, `closeAllOpenRests(effortId)` is called to close all open rest records for that effort. This prevents a rest window opened for a previously-skipped entry from continuing to tick in the background.

**Critical invariant**: The rest close happens in **two phases**:

1. **Synchronous in-memory close** (`_closeAllOpenRestsInMemory`): All open `EntryRest` records for the effort have their `restEndMs` set to the current wall-clock instant. The in-memory cache in `TimerManager._entryRests` is updated immediately. This happens **before the timer UI starts rendering**.

2. **Asynchronous repository persist** (`closeAllOpenRests`): After the in-memory close, the updated rest records are persisted to the repository asynchronously. This may lag behind UI rendering on high-latency devices, but queries to `hasRestRecord()` and `getRestElapsedSeconds()` see the closed state immediately from the in-memory cache.

**Why two phases?** On real devices with network/IO latency, the repository persist can lag by hundreds of milliseconds. Without the in-memory close, the rest overlay would display stale elapsed time (rest time + new timer time) in that window, creating a confusing visual flicker. The two-phase approach ensures the UI is always consistent with in-memory state, even when the repository is still catching up.

**Testing**: Scenario S-2 in the rest-timer-timed-overlap-bug plan verifies this behaviour by simulating a 500ms async persist delay and confirming that `hasRestRecord()` returns `false` and `getRestElapsedSeconds()` returns `0` immediately, while the repository persist is still in-flight.

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

The rest overlay chip is hosted by the `RestTimerStrip` widget
(`lib/features/session/rest_timer_strip.dart`), which docks the chip
into a reserved horizontal strip directly above the primary bottom
action button on every session surface — the rolling list view,
the standard list view, and the detail view. The strip replaces
the previous floating overlay, which sat at a fixed pixel offset
above the bottom edge of the screen and landed on top of
interactive controls on small viewports (covering the Add
Exercise / Add Block bar on the list view and the weight-adjustment
controls on the detail view for the entire rest period).

Every workout surface routes visibility through a **single shared
helper** — `_shouldShowRestOverlay()` in
`workout_session_global_timer.dart` — and passes the result as a
`visible:` flag to the strip. The invariant is that the surfaces
can never disagree about whether a rest timer is counting,
because none of them owns the decision. A cross-effort rest
(open for exercise A while a timer runs on exercise B) is hidden
everywhere while that timer is active, and edit mode hides the
chip outright.

Verified by:

- `test/unified_rest_overlay_test.dart` (`Unified rest overlay rule`)
  — visibility contract is unchanged.
- `test/rest_timer_docked_strip_test.dart` (`Docked strip — no
  overlap with interactive controls`, `… height collapse + scroll
  stability`, `… cross-surface parity`, `… viewport overflow
  sweep`) — the docked placement satisfies the no-overlap,
  scroll-stability, and cross-surface-parity invariants.

The chip itself is unchanged from the previous floating
implementation: it is tappable across its whole tile, distinguishes
its states without requiring the user to read the number, and
keeps an identical bounding rect across running and paused
states. The strip's empty area around the chip absorbs taps via
a transparent `GestureDetector`, so a tap that lands on the
padding around the chip does not reach the scrollable beneath;
the chip's own tap-to-pause/resume handler is unaffected.

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

## The Wrist's Rest

The watch runs its own rest, and it is a count-up with nothing to configure. The shipped wrist
screen is `watch/watchos/Sources/WatchSessionEngine/WatchRestView.swift`; the Dart file
`lib/watch/logging/watch_rest_screen.dart` is its twin, mounted by no runtime harness
(`docs/state_management/watch_surface.md`). Verified by `test/watch_rest_surface_test.dart` (`S-161
the rest elapsed counts up and survives the screen turning off`, `S-162 Next ends the rest at the
tap instant`, `S-163 logging ends a running rest first`), its Swift twin
`WatchRestSurfaceTests.testS161TheRestElapsedCountsUpAndSurvivesARelaunch`, and the logging path
that starts the rest with no length (`test/watch_logging_timers_test.dart`, `S-160 a logged set
starts a rest with no planned length`).

A rest is device-local, so the wrist's rest does not yet reach the phone's history: the phone
records rest from its own open rest window, and no rest row is imported from the wrist.

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
