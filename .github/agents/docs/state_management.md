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

### `WorkoutState`

**File**: `lib/state/workout/workout_state.dart`
**Depends on**: `WorkoutRepository`

The primary state manager for active workout sessions. Manages the entire session lifecycle.

#### Key Responsibilities
1. Session CRUD (create, load, end, discard)
2. Exercise management (add, remove from session)
3. Set/entry management (add, log, skip, delete)
4. Observation persistence (reps, weight, duration, distance, RPE, extra weight)
5. Round lifecycle (start, pause, resume, complete, end early)
6. Exercise ranking (delegates to repository)
7. Session summary computation
8. Template draft building (for save-as-routine)

#### Key State Fields

| Field | Type | Purpose |
|-------|------|---------|
| `_currentSession` | `TrainingSession?` | Active session |
| `_currentSegment` | `SessionSegment?` | Active segment (usually one per session) |
| `_exercises` | `List<Map<String, dynamic>>` | Exercises with entries and observations |
| `_exerciseCache` | `Map<String, Exercise>` | Cache of exercise definitions |
| `_allExercises` | `List<Exercise>` | Full exercise list for ranking |
| `_isLoading` | `bool` | Loading state |
| `_currentModalityConfig` | `ModalityConfig?` | Active modality config |

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
| `createCustomExercise(name, {...})` | Creates new exercise in repository |

#### Observation Management

| Method | Purpose |
|--------|---------|
| `addEntry(effortId)` | Creates new set/interval with default observations |
| `updateEntryValue(effortId, entryIndex, metricKey, value)` | Persists metric value immediately; preserves all existing fields including `rpeRating` and `restDurationMs` |
| `deleteLastEntry(effortId)` | Removes last set |
| `markSetSkipped(effortId, entryIndex)` | Marks set as explicitly skipped with `valueInt: 0, valueBool: true`; survives reload via `_isSetLogged` check |

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

#### Rest Tracking Methods

| Method | Signature | Purpose |
|--------|-----------|--------|
| `recordRestStart` | `(effortId, entryIndex) → Future<void>` | Creates an `EntryRest` record with `restStartMs = now`; called after a set/round is logged |
| `recordRestEnd` | `(effortId, entryIndex) → Future<void>` | Sets `restEndMs = now` on the open rest record; called when the athlete starts the next entry |
| `getRestElapsedSeconds` | `(effortId, entryIndex) → int` | Returns live elapsed seconds for the rest overlay display |
| `hasRestRecord` | `(effortId, entryIndex) → bool` | Returns `true` if a rest record exists for this entry; drives overlay visibility |
| `getEntryRests` | `(effortId) → List<EntryRest>` | Returns unmodifiable list of rest records for an effort |

See [Rest Tracking](rest_tracking.md) for full architecture details.

#### Routine Session Support

| Method | Purpose |
|--------|--------|
| `populateSessionFromManifest(manifest)` | Loads exercises from `RoutineSessionManifest` |
| `computeSessionSummary()` | Returns `SessionSummary`; counts `RoundState.finished` rounds (both natural completion and early-end logged rounds; not-started/active/paused are excluded) |
| `buildTemplateDraftExercises()` | Returns `List<SessionTemplateExercise>` for save-as-routine |

#### Session Block Management

Session blocks organize efforts into named, time-stamped groups. They are the primary UI structure for rolling sessions but are present in all session types when content is added via the routine manifest flow.

| Method | Purpose |
|--------|--------|
| `getSessionBlocks()` | Returns blocks for the current session sorted by `orderIndex` |
| `addSessionBlock({String? name})` | Creates a new `SessionBlock` for the current session. If `name` is omitted the block is named with the current wall-clock time in `"h:mm AM/PM"` format (e.g. `"3:45 PM"`) — the mechanism behind time-stamped blocks in rolling sessions |
| `updateSessionBlock(block)` | Persists changes to an existing block |
| `deleteSessionBlock(blockId)` | Deletes a block and mirrors the repository cascade to in-memory effort/observation maps |
| `reorderSessionBlocks(orderedIds)` | Reorders blocks for the current session |
| `cloneSessionBlock(blockId)` | Deep-clones a block and all linked records via the repository |

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

Owns persisted app appearance and measurement preferences. See [Theme & Settings](theme_and_settings.md) for full documentation.

| Field | Type | Default |
|-------|------|--------|
| `_appTheme` | `AppTheme` | `AppTheme.abyssalNeon` |
| `_preferredWeightUnit` | `String` | `'kg'` |
| `_preferredDistanceUnit` | `String` | `'km'` |

| Method | Purpose |
|--------|--------|
| `appTheme` | Getter — current selected theme |
| `preferredWeightUnit` | Getter — current displayed load unit (`kg` or `lbs`) |
| `preferredDistanceUnit` | Getter — current displayed distance unit (`km` or `miles`) |
| `setAppTheme(AppTheme)` | Persists theme by enum name and notifies listeners for immediate UI updates |
| `setPreferredWeightUnit(String)` | Normalizes/persists the display weight unit and notifies listeners |
| `setPreferredDistanceUnit(String)` | Normalizes/persists the display distance unit and notifies listeners |
| `_loadFromPrefs()` | Private — restores theme and unit preferences from repository-backed preference keys on init |

---

### `AppState`

**File**: `lib/state/app_state.dart`
**Depends on**: nothing

Singleton shell class for app-wide initialization. Not a `ChangeNotifier`. Currently minimal:

```dart
class AppState {
  static final AppState _instance = AppState._internal();
  factory AppState() => _instance;

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  Future<void> initialize() async { ... }
  void reset() { ... }
}
```

Not used by any screen in the current codebase.

---

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

### `TimerAlertService`

**File**: `lib/core/utils/timer_alert_service.dart`

Static utility for timer expiration feedback:
- `fireTimerExpiredAlert()` → `HapticFeedback.heavyImpact()` (skipped on web) + `SystemSound.play(SystemSoundType.alert)`

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

SharedPreferences
  └─ SettingsState    ← theme persistence only

AppState (standalone, singleton, minimal)
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

**Document Version**: 1.2
**Last Updated**: March 22, 2026
