# Navigation & Screen Map

## Overview

OmniTrain uses **imperative navigation** (`Navigator.push` / `Navigator.pop`). There is no named-route system or declarative router (no GoRouter, no AutoRoute). All dependencies are passed via constructor injection — no Provider, Riverpod, or Bloc.

---

## App Entry Point

**File**: `lib/main.dart`

```
main()
  → _createRepository() → HiveWorkoutRepository
  → repository.initialize()
  → Creates: WorkoutState, HomeState, RoutineState, CalendarState, PeriodState, ProfileState, SettingsState, RoutineSessionService, SessionSummaryService
  → runApp(MyApp(...))   // All dependencies injected via constructor
```

**File**: `lib/app.dart`

`MyApp` is a `StatelessWidget` that:
- Builds the "abyssal neon dark" theme via `buildTheme()`
- Sets `MaterialApp.home` → `HomeScreen` (splash screen is commented out)
- Passes all dependencies to `HomeScreen` via constructor

---

## Complete Screen Flow

```
HomeScreen
  │
  ├── Modality Tile (1 of 5) ──→ SessionOverviewScreen (creates session)
  │                                  │
  │                                  ├── Add Exercise → ExercisePickerDialog
  │                                  │                    └── [ModalityPickerDialog] (if null modality: pick modality or General)
  │                                  │                         └── [MetricChooserDialog] (if General picked)
  │                                  │                         └── → WorkoutSessionScreen (auto-navigate, focused on new exercise)
  │                                  │
  │                                  └── Start Workout → WorkoutSessionScreen
  │                                                        │
  │                                                        ├── finish → **pushReplacement** → SessionSummaryScreen
  │                                                        │   (back after finish pops to caller; cannot resume active session)
  │                                                        │                       │
  │                                                        ├── back → SessionSummaryScreen
  │                                                        │                       │
  │                                                        │                       ├── Edit Session → SessionOverviewScreen (push)
  │                                                        │                       ├── Save as Routine → bottom sheet
  │                                                        │                       ├── Discard → popUntil(isFirst)
  │                                                        │                       └── Done → popUntil(isFirst)
  │                                                        │
  │                                                        └── Add Exercise → ExercisePickerDialog
  │                                                              └── [ModalityPickerDialog] (if null modality: pick modality or General)
  │                                                                    └── [MetricChooserDialog] (if General picked)
  │                                                              └── [ExerciseEditorScreen] (create custom)
  │
  ├── My Routines Tile ──→ (if routine session active) → WorkoutSessionScreen
  │                     ──→ (else) → MyRoutinesScreen
  │                                    │
  │                                    ├── Tap routine card → start session → WorkoutSessionScreen
  │                                    ├── FAB (+) → RoutineSetupScreen (new)
  │                                    └── ⋮ menu → Edit → RoutineSetupScreen (existing)
  │                                               → Delete → confirmation dialog
  │
  ├── Free Training Tile ──→ SessionOverviewScreen (modality = null)
  │                            └── (same flow as modality tiles above)
  │
    └── Maintenance Sheet
      ├── Profile ──→ ProfileScreen
      ├── Stats ──→ MaintenancePlaceholderScreen
      └── Settings ──→ SettingsScreen
```

---

## Screen Inventory

| Screen | File | Purpose |
|--------|------|---------|
| `HomeScreen` | `lib/features/home/home_screen.dart` | 3×2 tile grid + maintenance sheet |
| `SessionOverviewScreen` | `lib/features/session/session_overview_screen.dart` | Exercise list for current session, add/remove exercises |
| `WorkoutSessionScreen` | `lib/features/session/workout_session_screen.dart` | Core workout tracking (list view + detail view) |
| `SessionSummaryScreen` | `lib/features/session/session_summary_screen.dart` | Post-workout summary, PRs, save-as-routine |
| `MyRoutinesScreen` | `lib/features/routine/my_routines_screen.dart` | List of saved routines |
| `RoutineSetupScreen` | `lib/features/routine/routine_setup_screen.dart` | Create/edit routines (dual view) |
| `ExerciseEditorScreen` | `lib/features/exercise/exercise_editor_screen.dart` | Create custom exercises |
| `ProfileScreen` | `lib/features/profile/profile_screen.dart` | Identity, avatar, and body measurement tracking |
| `SettingsScreen` | `lib/features/settings/settings_screen.dart` | App Appearance — theme selector |
| `MaintenancePlaceholderScreen` | `lib/features/home/maintenance_placeholder_screen.dart` | Placeholder for non-implemented maintenance routes (Stats) |
| `OmniSplashScreen` | `lib/features/splash/omni_splash_screen.dart` | Brand splash (currently disabled) |

### Empty / Placeholder Directories
- `lib/features/workout/` — contains only `.gitkeep`. All workout UI lives in `lib/features/session/`.

---

## Dependency Injection Pattern

All state and service objects are created in `main.dart` and passed through the widget tree via constructors. There is no DI framework.

```
main.dart
  → WorkoutState(repository)
  → HomeState(repository)          ← now receives repository for hint persistence
  → RoutineState(repository)
  → CalendarState(repository)
  → PeriodState(repository)
  → ProfileState(repository)
  → SettingsState()               ← uses SharedPreferences, not WorkoutRepository
  → RoutineSessionService(repository)
  → SessionSummaryService(repository)
  → MyApp(workoutState, homeState, routineState, routineSessionService, sessionSummaryService, calendarState, periodState, profileState, settingsState)
    → HomeScreen(workoutState, homeState, routineState, routineSessionService, sessionSummaryService, calendarState, periodState, profileState, settingsState)
      → (passes relevant subset to child screens)
```

### Key Injection Rules
- State classes depend only on `WorkoutRepository` interface (never concrete implementations)
- Services depend only on `WorkoutRepository` interface
- Screens receive state/service objects via constructor parameters
- No global singletons except `AppState` (currently minimal, not used in practice)

---

## Dialog Inventory

| Dialog | File | Purpose |
|--------|------|---------|
| `ExercisePickerDialog` | `lib/widgets/pickers/exercise_picker_dialog.dart` | Search and select exercises (modality-ranked) |
| `MetricChooserDialog` | `lib/widgets/pickers/metric_chooser_dialog.dart` | Choose tracking method for an exercise (Free Training / General fallback) |
| `ModalityPickerDialog` | `lib/widgets/pickers/modality_picker_dialog.dart` | Pick a modality for an exercise added to a null-modality session; returns `(bool, String?)` record or `null` (cancelled) |

---

## Active Session Resume Logic

When the user returns to the home screen with an active session:
- **Modality tiles**: If the active session's modality matches the tile, tapping resumes the session (navigates to `WorkoutSessionScreen`)
- **My Routines tile**: If the active session has `intent == 'routine'`, tapping navigates directly to `WorkoutSessionScreen`

When tapping a different modality tile while a session is active:
- A confirmation dialog appears: "Start New Session? Current session will be saved."
- Confirming ends the current session and creates a new one

---

## Related Documentation

- [App Philosophy](app_philosophy.md) — Home screen tile layout and UX constraints
- [Modality Tracking](modality_tracking.md) — Session creation and modality resolution
- [Session Summary](session_summary.md) — Post-workout summary screen

---

**Document Version**: 1.3
**Last Updated**: March 22, 2026
