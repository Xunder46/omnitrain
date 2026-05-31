# State Management & Services

## Overview

OmniTrain uses **ChangeNotifier** classes for state management. There is no Provider, Riverpod, or Bloc — all dependencies are injected via constructors from `main.dart`.

State classes follow strict rules:
- Depend only on `WorkoutRepository` interface (never concrete implementations)
- No Flutter/UI imports
- No direct storage/DB access
- Private state fields with public getters
- Call `notifyListeners()` after state changes

---

## State Classes

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
);
```

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

### `SessionCore`

**Files** (split for maintainability):
- `session_core.dart` — core fields, getters, query methods (~211 lines)
- `session_core_io.dart` — I/O operations (load, save, update) (~281 lines)
- `session_core_entry.dart` — entry/exercise CRUD (~394 lines)
- `session_core_lifecycle.dart` — session lifecycle management (~292 lines)

**Depends on**: `WorkoutRepository`, `TimerManager`, `ExerciseLibrary`

Handles all session lifecycle and CRUD concerns (Cluster A of the original `WorkoutState`). Calls `timerManager.addRound` / `addTimedEntry` when creating timer-based entries; calls `exerciseLibrary.clearNoteCache()` from `clearSession()`.

#### SyncService Integration Surface (forward-looking)

When cloud sync is added, `SyncService` will be injected into `SessionCore` at construction time:

```dart
// SessionCore(_repository, syncService: SyncService?, notify: ..., ...)
//
// After each successful repository write:
// await _repository.createSession(session);
// syncService?.queueCreate(SyncEntity.session, session);
```

The same pattern applies to `TimerManager` for `RoundInstance`/`TimedInstance` records and to `ExerciseLibrary` for exercise and note writes.

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
| `loadHistoricalSession(session)` | Loads a previously completed session for review/edit mode; sets `_currentModalityConfig` correctly from `session.modality` |
| `endSession()` | Marks session as ended (`endedAtMs`); idempotent — no-op if session already has `endedAtMs` |
| `clearSession()` | Removes session reference from state (doesn't delete data) |
| `discardCurrentSession()` | Deletes session and all related data |
| `updateSessionNote(note)` | Updates session note |
| `updateSessionEndTime(durationSecs)` | Edit-mode only — sets `endedAtMs = startedAtMs + durationSecs × 1000`; no-op if `durationSecs ≤ 0` |
| `updateSessionFeeling(feeling)` | Persists a 1-5 feeling score to `TrainingSession.sessionFeeling`; updates `_currentSession` in-place |
| `isRollingSession` | Getter — returns `true` when the active session has `isRolling == true`; returns `false` when no session is loaded |

#### Exercise Management

| Method | Purpose |
|--------|---------|
| `addExerciseToSession(exercise, {chosenMetric})` | Creates effort with correct effortKind |
| `removeExerciseFromSession(effortId)` | Deletes effort + observations + rounds |
| `getExercisesRankedForModality(modality, {...})` | Returns exercises sorted by relevance |
| `createCustomExercise(name, {modality, ...})` | Creates new exercise in repository with persisted modality key |
| `updateCustomExercise(exercise, {...})` | Updates existing exercise metadata + capability/muscle-group associations via repository interface |

#### Observation Management

| Method | Purpose |
|--------|---------|
| `addEntry(effortId)` | Creates new set/interval with default observations |
| `updateEntryValue(effortId, entryIndex, metricKey, value)` | Persists metric value immediately; preserves all existing fields including `rpeRating` and `restDurationMs` |
| `deleteLastEntry(effortId)` | Removes last set |
| `markSetSkipped(effortId, entryIndex)` | Marks set as explicitly skipped with `valueInt: 0, valueBool: true`; survives reload via `_isSetLogged` check |

#### Routine Session Support

| Method | Purpose |
|--------|--------|
| `populateSessionFromManifest(manifest)` | Loads exercises from `RoutineSessionManifest` |
| `computeSessionSummary()` | Returns `SessionSummary`; counts `RoundState.finished` rounds (both natural completion and early-end logged rounds; not-started/active/paused are excluded) |
| `buildTemplateDraftExercises()` | Returns `List<SessionTemplateExercise>` for save-as-routine |

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

### `SessionSummaryBuilder`

**File**: `lib/state/workout/session_summary_builder.dart`
**Depends on**: `WorkoutRepository`, `TimerManager`

Extracted from `SessionCore` to isolate session summary computation. Called by `SessionCore.computeSessionSummary()`.

| Method | Purpose |
|--------|--------|
| `computeSessionSummary(session, segments, efforts, observations, exerciseCache)` | Aggregates all session metrics into a `SessionSummary` model; counts finished rounds; sums durations |

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
| `addTimedEntry(effortId, {targetDurationSecs})` | — | Creates new `TimedInstance`; `targetDurationSecs` used as elapsed offset on first start |
| `startTimedEntry(effortId, entryIndex)` | notStarted → active | Back-dates `startedAtMs` by any pre-set `targetDurationSecs` offset; clears target after first start so entry is open-ended |
| `pauseTimedEntry(effortId, entryIndex)` | active → paused | Stamps `pausedAtMs` |
| `resumeTimedEntry(effortId, entryIndex)` | paused → active | Folds pause duration into `totalPausedDurationMs`; clears `pausedAtMs` |
| `finishTimedEntry(effortId, entryIndex)` | active/paused → finished | Derives `actualDurationSecs` from timestamps; folds final pause if paused |
| `deleteTimedEntry(effortId, entryIndex)` | — | Removes instance and re-indexes subsequent entries |
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

See [Rest Tracking](rest_tracking.md) for full architecture details.

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

### `RoutineState`

**File**: `lib/state/routine/routine_state.dart`
**Depends on**: `WorkoutRepository`

Manages routine template CRUD operations. Does **not** handle session creation (that responsibility was moved to `RoutineSessionService` in Phase 1 refactoring).

#### Key State Fields

| Field | Type | Purpose |
|-------|------|---------|
| `_routines` | `List<WorkoutTemplate>` | All saved routines |
| `_currentTemplate` | `WorkoutTemplate?` | Routine being created/edited |
| `_currentSegment` | `TemplateSegment?` | Active segment (usually one) |
| `_currentEfforts` | `List<TemplateEffort>` | Exercises in current routine |
| `_currentTargets` | `List<TemplateTarget>` | Per-set targets |

#### Key Methods

| Category | Methods |
|----------|---------|
| **CRUD** | `loadRoutines()`, `createNewRoutine(name)`, `updateRoutineName(name)`, `saveRoutine()`, `deleteRoutine(id)`, `loadRoutineForEditing(id)` |
| **Exercises** | `addExerciseToRoutine(exercise, effortKind)`, `removeExerciseFromRoutine(id)`, `reorderExercises(old, new)`, `updateEffortKind(id, kind)` |
| **Targets** | `setTargetValue(...)`, `getEffortTargets(id)`, `addSetForEffort(id, kind)`, `removeLastSetForEffort(id)` |

---

### `CalendarState`

**File**: `lib/state/calendar/calendar_state.dart`
**Depends on**: `WorkoutRepository`

Manages the calendar month view and associated monthly stats. See also [Calendar & Periods](calendar_periods.md) for full feature documentation.

#### Key Responsibilities
- Display month navigation (`goToPrevMonth`, `goToNextMonth`)
- Load completed + planned sessions for the current month range and group by day into `_entriesByDay`
- Compute monthly stats derived from `_entriesByDay` (pure getters — no extra caching)
- Compute the current consecutive-day streak via `_computeStreak()` (up to 90 days of history)
- Load period highlights for calendar background shading

#### Monthly Stats Getters

| Getter | Type | Description |
|--------|------|-------------|
| `completedSessionCount` | `int` | Completed sessions in loaded month |
| `totalTrainingMs` | `int` | Sum of `endedAtMs − startedAtMs` for completed sessions with timing data |
| `modalityBreakdown` | `Map<String?, int>` | Count of completed sessions grouped by modality key |
| `streakDays` | `int` | Current consecutive-day streak (computed independently of displayed month) |

---

### `HomeState`

**File**: `lib/state/home/home_state.dart`
**Depends on**: `WorkoutRepository`

Minimal state tracking a single boolean for UI purposes. Now persists the hint flag via `WorkoutRepository.setPreferenceBool` so it survives app restarts.

| Field | Type | Purpose |
|-------|------|--------|
| `_maintenanceHintSeen` | `bool` | Whether the maintenance sheet hint animation has been shown |

| Method | Purpose |
|--------|--------|
| `init()` | `async` — reads `'hint_seen_maintenance'` from repository preferences on startup |
| `shouldShowMaintenanceHint` | Getter — returns `!_maintenanceHintSeen` |
| `markMaintenanceHintSeen()` | Sets flag to `true`, persists via `repository.setPreferenceBool('hint_seen_maintenance', true)`, notifies listeners |

Persisted — survives app restart via `WorkoutRepository.getPreferenceBool` / `setPreferenceBool` backed by the Hive `meta` box.

---

### `ProfileState`

**File**: `lib/state/profile/profile_state.dart`
**Depends on**: `WorkoutRepository`

Manages profile identity and body-measurement flows used by `ProfileScreen`.

#### Key Responsibilities
1. Load or bootstrap a local profile (`id: 'local-user'`)
2. Persist display name and avatar path changes
3. Load latest measurement values per type
4. Log new measurement entries
5. Read measurement history for chart/list UI
6. Delete measurement entries and refresh latest values

#### Key State Fields

| Field | Type | Purpose |
|-------|------|---------|
| `_profile` | `UserProfile?` | Current local profile |
| `_isLoading` | `bool` | Loading guard for initial profile load |
| `_error` | `String?` | Last profile/measurement error |
| `_latestMeasurements` | `Map<String, BodyMeasurementEntry?>` | Latest entry per measurement type |

#### Key Methods

| Method | Purpose |
|--------|---------|
| `loadProfile()` | Loads profile; creates and saves `local-user` if missing; loads primary latest measurements |
| `loadLatestMeasurements(types, {notify})` | Bulk refresh for selected types |
| `updateDisplayName(name)` | Trims and persists display name (`null` when blank) |
| `updateAvatarPath(path)` | Persists avatar path or clears it |
| `logMeasurement(type, value, unitId, {recordedAtMs})` | Saves new entry; defaults timestamp to save time |
| `getMeasurementHistory(type)` | Repository passthrough for history UI |
| `deleteMeasurementEntry(entryId, measurementType)` | Deletes and refreshes latest value for the type |

---

### `SettingsState`

**File**: `lib/state/settings/settings_state.dart`
**Depends on**: `WorkoutRepository`

Owns persisted app appearance, calendar, timer-alert, and workout follow-up preferences. See [Theme & Settings](theme_and_settings.md) for full documentation.

| Field | Type | Default |
|-------|------|--------|
| `_appTheme` | `AppTheme` | `AppTheme.abyssalNeon` |
| `_preferredWeightUnit` | `String` | `'kg'` |
| `_preferredDistanceUnit` | `String` | `'km'` |
| `_startOfWeek` | `String` | `'monday'` |
| `_showFeelingSurvey` | `bool` | `true` |
| `_effortTimerSound` | `String` | `'boxing_bell'` |
| `_restPingInterval` | `int` | `0` |
| `_restPingSound` | `String` | `'soft_chime'` |
| `_notificationPermissionAsked` | `bool` | `false` |

| Method | Purpose |
|--------|--------|
| `appTheme` | Getter — current selected theme |
| `preferredWeightUnit` | Getter — current displayed load unit (`kg` or `lbs`) |
| `preferredDistanceUnit` | Getter — current displayed distance unit (`km` or `miles`) |
| `startOfWeek` | Getter — current calendar week start (`monday` or `sunday`) |
| `showFeelingSurvey` | Getter — whether to show the post-workout feeling prompt |
| `effortTimerSound` | Getter — selected alert sound for timer completion |
| `restPingInterval` | Getter — periodic rest reminder interval in seconds |
| `restPingSound` | Getter — selected rest-ping sound |
| `notificationPermissionAsked` | Getter — whether notification permission has been contextually requested yet |
| `setAppTheme(AppTheme)` | Persists theme by enum name and notifies listeners for immediate UI updates |
| `setPreferredWeightUnit(String)` | Normalizes/persists the display weight unit and notifies listeners |
| `setPreferredDistanceUnit(String)` | Normalizes/persists the display distance unit and notifies listeners |
| `setStartOfWeek(String)` | Normalizes/persists the calendar week start and notifies listeners |
| `setShowFeelingSurvey(bool)` | Persists the post-workout survey toggle |
| `setEffortTimerSound(String)` | Persists the selected effort-timer alert sound |
| `setRestPingInterval(int)` | Persists the periodic rest reminder interval |
| `setRestPingSound(String)` | Persists the selected rest-ping sound |
| `setNotificationPermissionAsked()` | Persists that notification permission has already been requested in-context |
| `_loadFromPrefs()` | Private — restores theme and unit preferences from repository-backed preference keys on init |

## Service Classes

Services contain business logic that doesn't belong in state classes. They depend only on `WorkoutRepository` — no state classes, no UI.

### `RoutineSessionService`

**File**: `lib/core/services/routine_session_service.dart`
**Depends on**: `WorkoutRepository`

Orchestrates template-to-session conversion.

| Method | Returns | Purpose |
|--------|---------|---------|
| `buildSessionFromTemplate(templateId)` | `RoutineSessionManifest` | Loads template hierarchy and builds a pure-data manifest for session population |

**Flow**:
1. Loads `WorkoutTemplate` → `TemplateSegment` → `TemplateEffort` → `TemplateTarget`
2. Loads all referenced `Exercise` entities
3. Returns `RoutineSessionManifest` (contains template + list of `SessionExerciseEntry`)

**Throws**: `Exception` if template not found or has no exercises

### `SessionSummaryService`

**File**: `lib/core/services/session_summary_service.dart`
**Depends on**: `WorkoutRepository`

Post-workout analytics.

| Method | Returns | Purpose |
|--------|---------|---------|
| `compareGroupsToPreviousSession(session, summary)` | `Map<String, GroupDelta>` | Finds the most recent previous session; computes per-group stats (strength volume, cardio/isometric duration, round counts); returns delta map keyed by `'strength'`, `'cardio'`, `'rounds'`, `'isometric'` |
| `computePRs(exerciseSummaries)` | `List<PRAchievement>` | Checks best weights against historical data |
| `saveRoutineFromDraft(draft, {focusModality})` | `String` (template ID) | Persists a session-to-routine template |

---

## Utility Classes

### `ObservationGrouper`

**File**: `lib/core/utils/observation_grouper.dart`

Groups flat observation lists by effort kind into structured per-set maps. Used by both session display and summary computation.

### `WorkoutSessionTimerMixin` (UI timer state)

**File**: `lib/features/session/workout_session_timer_mixin.dart`

`part of workout_session_screen.dart`. Mixed into `_WorkoutSessionScreenState`. Owns per-effort timer UI state and lifecycle — translating `TimerManager` state into local widget fields (`_effortRunning`, `_timedState`, `_roundState`, etc.).

**Key fields added (toolbar rework)**:
- `_inProgressKeys` (`Set<String>`) — tracks `effortId-entryIndex` keys whose timer has been started at least once and not yet finished. Enforces the global in-progress lock: only one timer can be active at a time.

**Key behaviors**:
- `_restoreTimerStateFromPersisted`: populates `_inProgressKeys` for any persisted `active`/`paused` state on session restore.
- `_toggleEffortTimer` (for `notStarted → active` transition): checks `_getAnotherInProgressKey`; if blocked, shows SnackBar `"Another set is still in progress. Pause or finish it before starting a new timer."` and returns early.
- `_resetTimerState`: removes key from `_inProgressKeys` (called after manual set log/finish flows).
- `_handleEffortTimerExpired` (round flow): removes the current round key from `_inProgressKeys` before calling `completeRound`, so the next round is immediately startable after auto-expiry.

**Auto-pause hooks** (in `workout_session_screen.dart`):
- `_jumpToSet()` — checks if current set's timer is running (`_effortRunning[timerKey] == true`) and calls `_pauseEffortTimer` before navigating to a different set.
- `_switchExercise()` — same auto-pause check before switching to a different exercise.

### `TimerAlertService`

**File**: `lib/core/utils/timer_alert_service.dart`

Audio-backed service for effort timer completion, rest-ping reminders, and settings previews.

Key behavior:

- `initialize()` configures `audio_session` on native platforms and preloads the bundled MP3 assets through `just_audio`
- `fireEffortTimerAlert(soundId)` plays the selected effort-timer sound and adds heavy haptic feedback on native platforms
- `fireRestPingAlert(soundId)` plays the selected rest-ping sound and adds light haptic feedback on native platforms
- `playPreview(soundId)` is used by the Settings sound picker to audition a sound immediately
- web does not attempt playback; it exits safely with debug logging instead

### `RestNotificationService`

**File**: `lib/core/utils/rest_notification_service.dart`

Platform notification scheduler for both rest pings and one-shot effort-timer expiry alerts.

Key behavior:

- `initialize()` configures local notifications plugin initialization and Android sound channels
- `scheduleRestPings(restStartMs, intervalSecs, soundId)` schedules future interval notifications (IDs `100-149`) via timezone-aware `zonedSchedule`
- `scheduleEffortTimerExpiry(fireAtMs, soundId)` schedules a single effort-expiry notification (ID `200`) used by round/timed/drill timer expiry
- scheduling uses `tz.local`, with local timezone set during app bootstrap in `main.dart` before app start
- `cancelRestNotifications()` cancels the reserved ID range and is used on rest-end / finish / dispose paths
- `cancelEffortTimerNotification()` cancels the reserved effort-expiry ID and is used on pause/manual-advance/finish/dispose paths
- foreground session scheduling uses silent notifications (`playSound: false`) and lifecycle backgrounding re-schedules audible notifications to avoid duplicate in-app + OS audio while still alerting when backgrounded/locked
- `requestPermission()` and `hasPermission()` support the Settings permission row flow
- Settings reads permission status only after `notificationPermissionAsked == true`, so the first-time row remains `Not yet asked` until contextual request
- `noop()` provides a safe no-op fallback for tests and non-wired construction paths
- web is fully no-op (all methods return early)

---

## Dependency Graph

```
WorkoutRepository (interface)
  │
  ├─ WorkoutState
  ├─ RoutineState
  ├─ CalendarState
  ├─ PeriodState
  ├─ ProfileState
  ├─ HomeState        ← now depends on WorkoutRepository for preference persistence
  ├─ RoutineSessionService
  └─ SessionSummaryService

WorkoutRepository
  └─ SettingsState    ← preference persistence (theme, units, alerts, calendar, workout toggles)
```

All injectable state/service objects are created in `main.dart` and passed to `MyApp` via constructor.

---

## Related Documentation

- [Navigation & Screens](navigation_and_screens.md) — How state objects flow to screens
- [Data Models](data_models.md) — The models that state classes manage
- [My Routines](my_routines.md) — RoutineState + RoutineSessionService details
- [Modality Tracking](modality_tracking.md) — WorkoutState modality logic
- [Theme & Settings](theme_and_settings.md) — SettingsState, theme tokens, AppTheme enum
- [Rest Tracking](rest_tracking.md) — EntryRest model and wall-clock rest architecture

---

**Document Version**: 1.3
**Last Updated**: May 27, 2026
