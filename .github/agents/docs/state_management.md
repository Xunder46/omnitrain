# State Management & Services

**Scope.** The state layer as a whole: the `ChangeNotifier` classes under
`lib/state/`, the service and utility classes under `lib/core/services/` and
`lib/core/utils/`, and the dependency graph that `lib/main.dart` wires between
them. It also covers the watch's own state classes and services under
`lib/watch/` (`WatchSessionEngine`, `WatchLoggingState`, the sensor layer), which
mirror `lib/state/`'s responsibilities on the wrist and are documented in
[Service & Utility Classes](state_management/services_and_utils.md). Screens and
widgets are documented under
[navigation_and_screens.md](navigation_and_screens.md) and
[widget_catalog.md](widget_catalog.md) instead.

> **This page is an index.** The state documentation was split into four part
> pages on 2026-07-26 so that no single documentation file sits near the
> per-file size ceiling that the tools indexing this folder enforce. Nothing
> was dropped in the split — every section moved verbatim into one of the
> pages below, and the previously-missing `PeriodState` and five
> service/utility classes were added.
>
> Links to `state_management.md` from plans and other docs still resolve here.

## Overview

OmniTrain uses **ChangeNotifier** classes for state management. There is no Provider, Riverpod, or Bloc — all dependencies are injected via constructors from `main.dart`.

State classes follow strict rules:
- Depend only on `WorkoutRepository` interface (never concrete implementations)
- No Flutter/UI imports
- No direct storage/DB access
- Private state fields with public getters
- Call `notifyListeners()` after state changes

---

## Pages

| Page | Covers |
|------|--------|
| [Workout Session State](state_management/workout_state.md) | `WorkoutState` facade + `SessionCore`, `SessionBlockManager`, `SessionSummaryBuilder`, `TimerManager`, `ExerciseLibrary` |
| [Nutrition State](state_management/nutrition_state.md) | `NutritionState`, `FoodLibraryState`, `NutritionPrimerState` |
| [Routine, Calendar, Home, Profile & Settings State](state_management/app_state.md) | `RoutineState`, `CalendarState`, `HomeState`, `ProfileState`, `SettingsState`, `PeriodState` |
| [Service & Utility Classes](state_management/services_and_utils.md) | `CrashReportingService`, `RoutineSessionService`, `SessionSummaryService`, `HealthSyncService` (+ `HealthPlatformService` gateway), `ObservationGrouper`, `TimerAlertService`, `RestNotificationService`, `WorkoutSessionTimerMixin`, plus `CatalogSource` / `BundledCatalogSource`, `DemoRoutinesValidator`, `StartupFailureDiagnosticWriter`, `OmniDateUtils`, `FuzzySearch`, and the watch↔phone surface (`LiveSessionMirrorState`, `WatchSyncOrchestrator`, `WatchNutritionState`, `WatchNutritionLogBridge`, `WatchIncomingRouter`, `WatchSyncRequestHandler`, `WatchReferenceSync`, `WatchTransport` and its channel/factory, the two reconcilers) |

---

## Class → Page Lookup

| Class | Page |
|-------|------|
| `BundledCatalogSource` | [Services & Utilities](state_management/services_and_utils.md) |
| `CalendarState` | [App State](state_management/app_state.md) |
| `CatalogSource` | [Services & Utilities](state_management/services_and_utils.md) |
| `CrashReportingService` | [Services & Utilities](state_management/services_and_utils.md) |
| `DemoRoutinesValidator` | [Services & Utilities](state_management/services_and_utils.md) |
| `ExerciseLibrary` | [Workout Session State](state_management/workout_state.md) |
| `FoodLibraryState` | [Nutrition State](state_management/nutrition_state.md) |
| `FuzzySearch` | [Services & Utilities](state_management/services_and_utils.md) |
| `HealthSyncService` | [Services & Utilities](state_management/services_and_utils.md) |
| `HomeState` | [App State](state_management/app_state.md) |
| `LiveSessionMirrorState` | [Services & Utilities](state_management/services_and_utils.md) |
| `NutritionPrimerState` | [Nutrition State](state_management/nutrition_state.md) |
| `NutritionState` | [Nutrition State](state_management/nutrition_state.md) |
| `ObservationGrouper` | [Services & Utilities](state_management/services_and_utils.md) |
| `OmniDateUtils` | [Services & Utilities](state_management/services_and_utils.md) |
| `PeriodState` | [App State](state_management/app_state.md) |
| `ProfileState` | [App State](state_management/app_state.md) |
| `RestNotificationService` | [Services & Utilities](state_management/services_and_utils.md) |
| `RoutineSessionService` | [Services & Utilities](state_management/services_and_utils.md) |
| `RoutineState` | [App State](state_management/app_state.md) |
| `SessionBlockManager` | [Workout Session State](state_management/workout_state.md) |
| `SessionCore` | [Workout Session State](state_management/workout_state.md) |
| `SyncSessionReconciler` | [Services & Utilities](state_management/services_and_utils.md) |
| `WatchActivityTypes` | [Services & Utilities](state_management/services_and_utils.md) |
| `WatchGpsPolicy` | [Services & Utilities](state_management/services_and_utils.md) |
| `WatchLoggingState` | [Services & Utilities](state_management/services_and_utils.md) |
| `WatchNutritionState` | [Services & Utilities](state_management/services_and_utils.md) |
| `WatchNutritionLogBridge` | [Services & Utilities](state_management/services_and_utils.md) |
| `WatchIncomingRouter` | [Services & Utilities](state_management/services_and_utils.md) |
| `WatchMessageChannel` | [Services & Utilities](state_management/services_and_utils.md) |
| `WatchSyncRequestHandler` | [Services & Utilities](state_management/services_and_utils.md) |
| `createWatchSync` | [Services & Utilities](state_management/services_and_utils.md) |
| `createPlatformWatchTransport` | [Services & Utilities](state_management/services_and_utils.md) |
| `WatchPlatformWorkout` | [Services & Utilities](state_management/services_and_utils.md) |
| `WatchReferenceSync` | [Services & Utilities](state_management/services_and_utils.md) |
| `WatchSensorRecorder` | [Services & Utilities](state_management/services_and_utils.md) |
| `WatchSessionEngine` | [Services & Utilities](state_management/services_and_utils.md) |
| `WatchSessionSensors` | [Services & Utilities](state_management/services_and_utils.md) |
| `WatchSyncOrchestrator` | [Services & Utilities](state_management/services_and_utils.md) |
| `SessionSummaryBuilder` | [Workout Session State](state_management/workout_state.md) |
| `SessionSummaryService` | [Services & Utilities](state_management/services_and_utils.md) |
| `SettingsState` | [App State](state_management/app_state.md) |
| `StartupFailureDiagnosticWriter` | [Services & Utilities](state_management/services_and_utils.md) |
| `TimerAlertService` | [Services & Utilities](state_management/services_and_utils.md) |
| `TimerManager` | [Workout Session State](state_management/workout_state.md) |
| `WorkoutSessionTimerMixin` | [Services & Utilities](state_management/services_and_utils.md) |
| `WorkoutState` | [Workout Session State](state_management/workout_state.md) |

---

## Dependency Graph

Every injectable state/service object is constructed in `main.dart` and passed
to `MyApp` via constructor. Verified against `lib/main.dart` on 2026-07-26.

```
WorkoutRepository (interface, → HiveWorkoutRepository at runtime)
  │
  ├─ WorkoutState(repository)
  ├─ HomeState(repository)
  ├─ RoutineState(repository)
  ├─ CalendarState(repository)
  ├─ PeriodState(repository)
  ├─ ProfileState(repository, …)
  ├─ NutritionState(repository)
  ├─ FoodLibraryState(repository, …)
  ├─ NutritionPrimerState(repository)
  ├─ CatalogRefreshService(repository, …)
  ├─ RoutineSessionService(repository)
  └─ SessionSummaryService(repository)

SettingsState(repository, preferencesService)
  └─ preference persistence (theme, units, alerts, calendar, workout toggles)

Platform-selected services (no repository dependency):
  ├─ createRestNotificationService()
  ├─ createTimerAlertService()
  └─ createPreferencesService()
```

---

## Related Documentation

- [Navigation & Screens](navigation_and_screens.md) — How state objects flow to screens
- [Data Models](data_models.md) — The models that state classes manage
- [My Routines](my_routines.md) — RoutineState + RoutineSessionService details
- [Modality Tracking](modality_tracking.md) — WorkoutState modality logic
- [Theme & Settings](theme_and_settings.md) — SettingsState, theme tokens, AppTheme enum
- [Rest Tracking](rest_tracking.md) — EntryRest model and wall-clock rest architecture
- [Calendar & Periods](calendar_periods.md) — PeriodState product behavior

---

> **Doc freshness** — Last reconciled against source: 2026-07-26. This doc is derived from source, not hand-maintained. Source of truth: the `lib/` tree as it exists on the reconciliation date. If you find a claim here that disagrees with `lib/`, `lib/` wins — please flag the drift in a fresh chat with the Coordinator agent.
