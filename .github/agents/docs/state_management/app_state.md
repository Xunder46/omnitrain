# Routine, Calendar, Home, Profile & Settings State

> Part of [State Management & Services](../state_management.md). Return to the index for the full class list and dependency graph.

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

---

### `CalendarState`

**File**: `lib/state/calendar/calendar_state.dart`
**Depends on**: `WorkoutRepository`

Manages the calendar month view and associated monthly stats. See also [Calendar & Periods](../calendar_periods.md) for full feature documentation.

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
| `loadProfile()` | Loads profile; creates and saves `local-user` if missing; loads latest measurements for the charted column (`ProfileMeasurements.additional`) |
| `loadLatestMeasurements(types, {notify})` | Bulk refresh for selected types |
| `updateDisplayName(name)` | Trims and persists display name (`null` when blank) |
| `updateAvatarPath(path)` | Persists avatar path or clears it |
| `logMeasurement(type, value, unitId, {recordedAtMs})` | Saves new entry; defaults timestamp to save time |
| `getMeasurementHistory(type)` | Repository passthrough for history UI |
| `deleteMeasurementEntry(entryId, measurementType)` | Deletes and refreshes latest value for the type |

---

---

### `SettingsState`

**File**: `lib/state/settings/settings_state.dart`
**Depends on**: `WorkoutRepository`, `PreferencesService`

Owns persisted app appearance, calendar, timer-alert, and workout follow-up preferences. See [Theme & Settings](../theme_and_settings.md) for full documentation.

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

---

### `PeriodState`

**File**: `lib/state/period/period_state.dart`

Owns the training-period lifecycle (create / update / delete) and the
non-overlap guard. Backs `PeriodListScreen` and `CreatePeriodScreen`.
Constructed with a `WorkoutRepository` and injected from `main.dart`.

Added to this doc on 2026-07-26 — it was previously absent from the state
documentation despite being wired into `main.dart` and two screens.

| Member | Type | Description |
|--------|------|-------------|
| `periods` | `List<TrainingPeriod>` | Unmodifiable view of loaded periods |
| `isLoading` | `bool` | True while `load()` is in flight |
| `error` | `String?` | Last load/mutation error, or `null` |
| `load()` | `Future<void>` | Loads all periods from the repository |
| `validate(...)` | `Future<PeriodValidationResult>` | Validates name, date range, and overlap against existing periods |
| `createPeriod({...})` | `Future<bool>` | Validates then persists a new period; returns `false` on validation failure |
| `updatePeriod({...})` | `Future<bool>` | Validates then persists an edit (excludes the edited period from the overlap check) |
| `deletePeriod(String id)` | `Future<void>` | Removes a period |

`PeriodValidationResult` is a small value type carrying `isValid` plus
`nameError` / `dateError` / `overlapError` so the form can render
field-level messages.

See [Calendar & Periods](../calendar_periods.md) for the product behavior.

---

> **Doc freshness** — Last reconciled against source: 2026-07-26. This page is one part of [State Management & Services](../state_management.md); see that index for the full class list. This doc is derived from source, not hand-maintained. Source of truth: the `lib/` tree. If you find a claim here that disagrees with `lib/`, `lib/` wins.
