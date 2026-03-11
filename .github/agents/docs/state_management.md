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
| `createNewSession({modality, title, intent, routineTemplateId})` | Creates session + segment |
| `loadSessionData()` | Loads exercises, efforts, observations for current session |
| `endSession()` | Marks session as ended (`endedAtMs`) |
| `clearSession()` | Removes session reference from state (doesn't delete data) |
| `discardCurrentSession()` | Deletes session and all related data |
| `updateSessionNote(note)` | Updates session note |

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
| `updateEntryValue(effortId, entryIndex, metricKey, value)` | Persists metric value immediately |
| `deleteLastEntry(effortId)` | Removes last set |

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

#### Routine Session Support

| Method | Purpose |
|--------|---------|
| `populateSessionFromManifest(manifest)` | Loads exercises from `RoutineSessionManifest` |
| `computeSessionSummary()` | Returns `SessionSummary` |
| `buildTemplateDraftExercises()` | Returns `List<SessionTemplateExercise>` for save-as-routine |

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

### `HomeState`

**File**: `lib/state/home/home_state.dart`
**Depends on**: nothing

Minimal state tracking a single boolean for UI purposes.

| Field | Type | Purpose |
|-------|------|---------|
| `_maintenanceHintSeen` | `bool` | Whether the maintenance sheet hint animation has been shown |

| Method | Purpose |
|--------|---------|
| `shouldShowMaintenanceHint` | Getter — returns `!_maintenanceHintSeen` |
| `markMaintenanceHintSeen()` | Sets flag to `true`, notifies listeners |

Not persisted — resets on app restart.

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
| `compareToPreviousSession(session, volume)` | `VolumeComparison` | Finds previous session, computes volume delta |
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
  ├─ RoutineSessionService
  └─ SessionSummaryService

HomeState (standalone, no dependencies)
AppState (standalone, singleton, minimal)
```

All five injectable objects are created in `main.dart` and passed to `MyApp` via constructor.

---

## Related Documentation

- [Navigation & Screens](navigation_and_screens.md) — How state objects flow to screens
- [Data Models](data_models.md) — The models that state classes manage
- [My Routines](my_routines.md) — RoutineState + RoutineSessionService details
- [Modality Tracking](modality_tracking.md) — WorkoutState modality logic

---

**Document Version**: 1.0
**Last Updated**: February 28, 2026
