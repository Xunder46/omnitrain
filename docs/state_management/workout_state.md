# Workout Session State

> Part of [State Management & Services](../state_management.md). Return to the index for the full class list and dependency graph.

---

### `WorkoutState` (Facade)

**File**: `lib/state/workout/workout_state.dart`
**Depends on**: `WorkoutRepository`

Thin `ChangeNotifier` facade. Constructs and holds `TimerManager`, `ExerciseLibrary`, and `SessionCore`, then delegates every public getter and method to the appropriate sub-holder. No business logic lives here.

**Construction order** (cross-references require this sequence):
```dart
_timerManager    = TimerManager(_repository, notify: notifyListeners);
_exerciseLibrary = ExerciseLibrary(_repository, notify: notifyListeners);
_sessionCore     = SessionCore(
  _repository,
  notify: notifyListeners,
  timerManager: _timerManager,
  exerciseLibrary: _exerciseLibrary,
  lateEntryRecovery: watchLateEntryRecovery,
);
```

The constructor also takes an optional `watchLateEntryRecovery`, the watch
graph's `WatchLateEntryRecovery` handle, which the session core's restore calls
on Discard so a wrist entry that arrived while the screen was open is not lost.
It is null when the platform has no watch, and a null handle leaves the restore
behaving exactly as it did before. Because the handle comes from the watch
graph, `lib/main.dart` builds `WorkoutState` after `createWatchSync` and builds
`ExerciseLibraryState` after both. Verified by
`test/watch_session_edit_restore_late_entry_test.dart` (`S-1401` to `S-1410`,
`S-1414`).

Each sub-holder receives `notify: () => notifyListeners()` so all `notifyListeners()` calls still fire once from the single `ChangeNotifier` that consumers subscribe to. No consumer screen or test changes are required.

**`notify` callback pattern**: Sub-holders are plain Dart objects (not ChangeNotifiers). They call the injected `notify` callback in place of `notifyListeners()`. This preserves the single-listener model and avoids the double-dispatch overhead of chaining multiple ChangeNotifiers.

#### Active Session Persistence Helpers

`WorkoutState` includes cold-start lifecycle helpers that are intentionally facade-level (not in `SessionCore`):

| Method | Purpose |
|--------|---------|
| `checkForInProgressSession()` | Reads repository `getInProgressSessions()`, returns most recent dangling session, and best-effort deletes older duplicates |
| `deleteSessionById(String id)` | Deletes a session by id without mutating current in-memory session |
| `countSetsForSession(String sessionId)` | Read-only aggregate count of `EffortObservation` rows across all session segments/efforts for resume dialog display |

These methods keep feature screens on the state boundary and avoid direct repository access from `features/`.

---

---

### `SessionCore`

**Files** (split for maintainability):
- `session_core.dart` — core fields, getters, query methods (~211 lines)
- `session_core_io.dart` — I/O operations (load, save, update) (~281 lines)
- `session_core_entry.dart` — entry/exercise CRUD (~394 lines)
- `session_core_lifecycle.dart` — session lifecycle management (~292 lines)

**Depends on**: `WorkoutRepository`, `TimerManager`, `ExerciseLibrary`

Handles all session lifecycle and CRUD concerns (Cluster A of the original `WorkoutState`). Calls `timerManager.addRound` / `addTimedEntry` when creating timer-based entries; calls `exerciseLibrary.clearNoteCache()` from `clearSession()`.

#### Key State Fields

| Field | Type | Purpose |
|-------|------|---------|
| `_currentSession` | `TrainingSession?` | Active session |
| `_segments` | `List<SessionSegment>` | Session segments (usually one) |
| `_efforts` | `Map<String, List<SegmentEffort>>` | Efforts keyed by segment ID |
| `_observations` | `Map<String, List<EffortObservation>>` | Observations keyed by effort ID |
| `_sessionBlocks` | `Map<String, List<SessionBlock>>` | Blocks keyed by session ID |
| `_exerciseCache` | `Map<String, Exercise>` | Cache of exercise definitions for active session |
| `_currentModalityConfig` | `ModalityConfig?` | Active modality config |
| `_isLoading` | `bool` | Loading state |
| `_error` | `String?` | Last error message |

#### Session Lifecycle Methods

| Method | Purpose |
|--------|---------|
| `createNewSession({modality, title, intent, routineTemplateId, isRolling})` | Creates session + segment; `isRolling` (bool, default `false`) sets `TrainingSession.isRolling` |
| `loadSessionData()` | Loads exercises, efforts, observations for current session |
| `refreshEfforts(effortIds)` | Re-reads only the named efforts' observations, instances and entry rests from the repository — a refresh, not a reload, so a running timer survives. Used by the watch merge (`docs/watch_session_sync.md`, D-17); verified by `test/watch_session_merge_test.dart`'s S-16 |
| `loadHistoricalSession(session)` | Loads a previously completed session for review/edit mode; sets `_currentModalityConfig` correctly from `session.modality` |
| `endSession()` | Marks session as ended: `endedAtMs` is `max(startedAtMs, now)`, so a stored end never precedes its start (D-153; `S-155 writer table — every phone-owned writer leaves an ordered window endSession clamps a start that lies ahead of the phone clock` in `test/session_window_never_inverted_test.dart`); idempotent — no-op if session already has `endedAtMs`. After a successful save, delegates to the injected `HealthSyncService` (no-op when not injected or when the health write toggle is off) |
| `clearSession()` | Removes session reference from state (doesn't delete data) |
| `discardCurrentSession()` | Deletes session and all related data |
| `updateSessionNote(note)` | Updates session note |
| `updateSessionEndTime(durationSecs)` | Edit-mode only — sets `endedAtMs = max(startedAtMs, startedAtMs + durationSecs × 1000)` (D-153); no-op if `durationSecs ≤ 0` (`S-155 writer table — every phone-owned writer leaves an ordered window updateSessionEndTime with a zero or negative duration writes nothing` in `test/session_window_never_inverted_test.dart`) |
| `updateSessionFeeling(sessionId, rating)` | Persists the 1-5 session effort rating (1 Very easy … 5 Max effort) to `TrainingSession.sessionFeeling` for any session id; updates `_currentSession` in-place when it is that session |
| `isRollingSession` | Getter — returns `true` when the active session has `isRolling == true`; returns `false` when no session is loaded |

#### Exercise Management

| Method | Purpose |
|--------|---------|
| `addExerciseToSession(exercise, {chosenMetric})` | Hydrates the cached exercise via `_repository.getExerciseById(exercise.id)` so the session cache carries the canonical capabilities (matching how the exercise browser presents them), then creates the effort with the correct `effortKind`. The caller's `Exercise` is used as a fallback only if the repository doesn't know the id. |
| `removeExerciseFromSession(effortId)` | Deletes effort + observations + rounds |
| `getExercisesRankedForModality(modality, {...})` | Returns exercises sorted by relevance |
| `createCustomExercise(name, {modality, ...})` | Creates new exercise in repository with persisted modality key |
| `updateCustomExercise(exercise, {...})` | Updates existing exercise metadata + capability/muscle-group associations via repository interface |

#### Observation Management

| Method | Purpose |
|--------|---------|
| `addEntry(effortId, {previousValues})` | Creates a new set/interval/round/drill. The optional `previousValues` map carries forward metrics from the prior entry into the new observation rows / round instance — see the per-effort-kind table below. A distance is never carried forward: a new timed entry starts at 0 m with no source (D-702). Keys not present fall back to the app-wide defaults in `lib/core/constants/effort_defaults.dart` and `workout_constants.dart`. The carry-forward is read-only on the prior entry — `previousValues` only seeds the new entry's defaults, it does not mutate prior observations. The `_addSet` caller in `workout_session_screen.dart` populates `previousValues` from the prior entry in `getExercisesWithEntries()` so each new set/interval/round/drill pre-fills with the prior values (June 2026, exercise-set-last-value-plan). Verified by `test/row_invariants_guard_test.dart` (`S-1304`) |

| `updateEntryValue(effortId, entryIndex, metricKey, value)` | Persists metric value immediately; preserves all existing fields — `rpeRating`, `restDurationMs`, and, for every metric but distance, `valueSource`. A distance row's source is instead derived from the value written: `entered` for a positive value that has none, none for a zero (clearing it), and an existing source kept otherwise. The row it writes is the one entry *k* owns ([Entry Identity](../data_models.md#entry-identity), D-324), so an edit lands on the entry the user chose; a set's missing extra weight is created with that set's own number, and a hold's or a timed entry's missing predecessors are filled first. Verified by `test/entry_identity_test.dart` (`S-853`, `S-857`, `S-863`, `S-864`); the distance-source derivation by `test/distance_source_test.dart` (`S-804` (a)) and `test/row_invariants_guard_test.dart` (`S-883` steps 2a, 2b) |
| `deleteLastEntry(effortId)` | Removes last set |
| `deleteEntry(effortId, entryIndex)` | Removes exactly the rows entry *k* owns and nothing else — for a set, the *k*-th group; for a timed or hold entry, delegated to `deleteTimedEntry`. No row is renamed (D-326). Verified by `test/entry_identity_test.dart` (`S-851`, `S-852`, `S-860`) |
| `markSetSkipped(effortId, entryIndex)` | Marks set as explicitly skipped with `valueInt: 0, valueBool: true`; survives reload via `_isSetLogged` check. Addresses entry *k* by the same rule as `updateEntryValue`. Verified by `test/entry_identity_test.dart` (`S-854`) |
| `setEntryDistance(effortId, entryIndex, metres)` | Records a distance with source `entered` (zero removes it); an existing row keeps its id and `createdAtMs`, and earlier unpaired entries are filled first, numbered upward. A new row is numbered above every row the effort holds, so it never overwrites a stored one. Verified by `test/distance_source_test.dart` (`S-805`–`S-807`), `test/entry_identity_test.dart` (`S-845`, `S-856`, `S-864`) and `test/row_invariants_guard_test.dart` (`S-883`) |
| `confirmEntryDistance(effortId, entryIndex)` | Re-records the metres an entry already holds, keeping them exactly, and flips the source to `entered`. Verified by `test/distance_source_test.dart` (`S-806`) |

| `getEffortDistanceEntries(effortId)` | The effort's distance entries, each with its own row or none (D-328). Only a `timed` effort has any: a distance belongs to a timed entry, so any other effort kind returns an empty list (D-703). The Summary builds its DISTANCE rows from this and the distance writes address the same list, so a row on screen and the row an edit lands on are the same entry. Verified by `test/entry_identity_summary_test.dart` (`S-858`) and `test/session_summary_distance_test.dart` (`S-1303`) |

Both distance writes report failures through the same error channel as the
other observation methods, and the entry-pairing rule they share with the
Summary and Stats lives in [Distance Source & Pairing](../distance_source.md).
`updateEntryValue` writes a distance too, addressing the same entries.

#### Routine Session Support

| Method | Purpose |
|--------|--------|
| `populateSessionFromManifest(manifest)` | Loads exercises from `RoutineSessionManifest` |
| `computeSessionSummary()` | Returns `SessionSummary`; counts `RoundState.finished` rounds (both natural completion and early-end logged rounds; not-started/active/paused are excluded) |
| `buildTemplateDraftExercises()` | Returns `List<SessionTemplateExercise>` for save-as-routine. Each target reads the entry's own row through `EntryRows`; a `timed`/`drill` template carries no distance target (`S-1311`–`S-1315` in `test/state_test.dart`) |

---

---

### `SessionBlockManager`

**File**: `lib/state/workout/session_block_manager.dart`
**Depends on**: `WorkoutRepository`, `TimerManager`

Encapsulates all session block CRUD and block-effort assignment logic. Extracted from `SessionCore` to keep each sub-holder within its size target.

| Method | Purpose |
|--------|--------|
| `getSessionBlocks()` | Returns blocks for the current session sorted by `orderIndex` |
| `addSessionBlock({String? name})` | Creates a new `SessionBlock`; if `name` is omitted, names the block with current wall-clock time (`"3:45 PM"`) — the mechanism behind time-stamped blocks in rolling sessions |
| `updateSessionBlock(block)` | Persists changes to an existing block |
| `deleteSessionBlock(blockId)` | Deletes a block and mirrors the cascade to in-memory effort/observation maps |
| `reorderSessionBlocks(orderedIds)` | Reorders blocks for the current session |
| `cloneSessionBlock(blockId)` | Deep-clones a block and all linked records via the repository |
| `assignEffortToBlock(effortId, blockId)` | Assigns or unassigns an effort to a block |

---

---

### `SessionSummaryBuilder`

**File**: `lib/state/workout/session_summary_builder.dart`
**Depends on**: `WorkoutRepository`, `TimerManager`

Extracted from `SessionCore` to isolate session summary computation. Called by `SessionCore.computeSessionSummary()`.

| Method | Purpose |
|--------|--------|
| `computeSessionSummary(session, segments, efforts, observations, exerciseCache)` | Aggregates all session metrics into a `SessionSummary` model; counts finished rounds; sums durations |

---

---

### `TimerManager`

**File**: `lib/state/workout/timer_manager.dart`
**Depends on**: `WorkoutRepository`

Handles all round, timed-entry, and rest state machines (Cluster B of the original `WorkoutState`). Notifies listeners via the injected `notify` callback.

#### Key State Fields

| Field | Type | Purpose |
|-------|------|---------|
| `_roundInstances` | `Map<String, List<RoundInstance>>` | Round instances keyed by effort ID |
| `_timedInstances` | `Map<String, List<TimedInstance>>` | Timed instances keyed by effort ID |
| `_entryRests` | `Map<String, List<EntryRest>>` | Rest records keyed by effort ID |

#### Round Management (round effortKind only)

| Method | Transition | Purpose |
|--------|-----------|---------|
| `addRound(effortId, {plannedDurationSecs})` | — | Creates new `RoundInstance` |
| `startRound(effortId, roundIndex)` | notStarted → active | Starts timer |
| `pauseRound(effortId, roundIndex)` | active → paused | Stamps `pausedAtMs` |
| `resumeRound(effortId, roundIndex)` | paused → active | Folds pause into `totalPausedDurationMs` |
| `endRoundEarly(effortId, roundIndex)` | active/paused → finished | Derives elapsed from timestamps |
| `completeRound(effortId, roundIndex)` | active → finished | Natural countdown completion |
| `updateRoundPlannedDuration(effortId, roundIndex, secs)` | — | Adjusts target duration |
| `deleteRound(effortId, roundIndex)` | — | Removes round instance |
| `getRoundsForEffort(effortId)` | — | Returns all rounds for an effort |

#### Timed Management (timed / drill effortKind)

| Method | Transition | Purpose |
|--------|-----------|---------|
| `addTimedEntry(effortId, {targetDurationSecs})` | — | Creates new `TimedInstance`; `targetDurationSecs` used as elapsed offset on first start. Its id never repeats one an existing instance already holds — an add that lands on the same millisecond as a held id takes the next free one instead (D-338). Verified by `test/distance_source_import_test.dart` (`S-880`) |
| `startTimedEntry(effortId, entryIndex)` | notStarted → active | Back-dates `startedAtMs` by any pre-set `targetDurationSecs` offset; clears target after first start so entry is open-ended |
| `pauseTimedEntry(effortId, entryIndex)` | active → paused | Stamps `pausedAtMs` |
| `resumeTimedEntry(effortId, entryIndex)` | paused → active | Folds pause duration into `totalPausedDurationMs`; clears `pausedAtMs` |
| `finishTimedEntry(effortId, entryIndex)` | active/paused → finished | Derives `actualDurationSecs` from timestamps; folds final pause if paused |
| `deleteTimedEntry(effortId, entryIndex)` | — | Removes the instance and its own rows — the *k*-th row of each companion metric, found before the instance goes (D-326) — and re-indexes subsequent entries. Verified by `test/entry_identity_test.dart` (`S-855`, `S-860`) |
| `getTimedInstancesForEffort(effortId)` | — | Returns unmodifiable list of timed instances for an effort |

#### Rest Tracking Methods

| Method | Signature | Purpose |
|--------|-----------|--------|
| `recordRestStart` | `(effortId, entryIndex) → Future<void>` | Creates an `EntryRest` record with `restStartMs = now`; called after a set/round is logged |
| `recordRestEnd` | `(effortId, entryIndex) → Future<void>` | Sets `restEndMs = now` on the open rest record; called when the athlete starts the next entry |
| `persistOpenRests` | `(closeAtMs) → Future<void>` | Closes every open `EntryRest` across all efforts at `closeAtMs`; called by `endSession()` |
| `getRestElapsedSeconds` | `(effortId, entryIndex) → int` | Returns live elapsed seconds for the rest overlay display |
| `hasRestRecord` | `(effortId, entryIndex) → bool` | Returns `true` if a rest record exists for this entry; drives overlay visibility |
| `getEntryRests` | `(effortId) → List<EntryRest>` | Returns unmodifiable list of rest records for an effort |

See [Rest Tracking](../rest_tracking.md) for full architecture details.

---

---

### `ExerciseLibrary`

**File**: `lib/state/workout/exercise_library.dart`
**Depends on**: `WorkoutRepository`

Handles the exercise catalog, exercise notes, and coach-mark hint flags (Cluster C of the original `WorkoutState`). Exposes `clearNoteCache()` called by `SessionCore.clearSession()`.

#### Key State Fields

| Field | Type | Purpose |
|-------|------|---------|
| `_allExercises` | `List<Exercise>` | Full exercise catalog |
| `_muscleGroups` | `List<String>` | Available muscle groups |
| `_disciplines` | `List<String>` | Available disciplines |
| `_exerciseNotes` | `Map<String, ExerciseNote>` | Notes keyed by exercise ID |
| `_exerciseNoteLoadInFlight` | `Set<String>` | Guards concurrent note loads |
| `_exerciseNoteSaveInFlight` | `List<Future<void>>` | Queued save operations |
| `_exerciseNotesHintSeen` | `bool` | Coach-mark hint flag |
| `_exerciseInfoHintSeen` | `bool` | Coach-mark hint flag |

#### Key Methods

| Method | Purpose |
|--------|---------|
| `loadAllExercises()` | Loads full exercise catalog |
| `loadMuscleGroups()` / `loadDisciplines()` | Loads filter options |
| `searchExercises(query)` | Filters exercises by name |
| `getExercisesRankedForModality(modality, {...})` | Returns exercises sorted by relevance score |
| `createCustomExercise(name, {...})` | Creates exercise in repository and caches it |
| `updateCustomExercise(exercise, {...})` | Updates exercise and refreshes cache |
| `loadExerciseNote(exerciseId)` | Loads note with in-flight guard |
| `saveExerciseNote(exerciseId, note, {sessionId})` | Saves note with debounce queue |
| `getExerciseNote(exerciseId)` | Returns cached note or null |
| `hasExerciseNote(exerciseId)` | Checks if a note exists |
| `clearNoteCache()` | Clears note state; called by `SessionCore.clearSession()` |
| `initExerciseHints()` | Loads hint flags from repository |
| `markExerciseNotesHintSeen()` / `markExerciseInfoHintSeen()` | Persists hint flags |

---

> **Doc freshness** — Last reconciled against source: 2026-07-26. This page is one part of [State Management & Services](../state_management.md); see that index for the full class list. This doc is derived from source, not hand-maintained. Source of truth: the `lib/` tree. If you find a claim here that disagrees with `lib/`, `lib/` wins.
