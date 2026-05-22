# Navigation & Screen Map

## Navigation Contract

> **Rule**: All screen-level navigation goes through `OmniNavigator`. `OmniRoute` and `OmniFadeRoute` are the only route types used for screen pushes. Any `MaterialPageRoute` or `PageRouteBuilder` outside `lib/core/navigation/` is a **code-review blocker**.

### Architecture

```
OmniNavigator.push / pushReplacement / pushReplacementFade
    └── OmniRoute<T> / OmniFadeRoute<T>
            └── OmniGradientBackground  ← wraps every pushed page
                    └── Screen widget
```

The app-level `OmniGradientBackground` (in `app.dart` `builder:`) covers static areas (status bar, overscroll, sheet gaps). Each `OmniRoute` also wraps its page in `OmniGradientBackground` and sets `opaque = true`, ensuring the incoming route fully occludes the outgoing one at every animation frame and eliminating transition bleed-through.

### When to use each method

| Method | Use case |
|---|---|
| `OmniNavigator.push(context, (_) => Screen(...))` | Standard forward navigation |
| `OmniNavigator.pushReplacement(context, (_) => Screen(...))` | Replace current route (e.g. session → summary) |
| `OmniNavigator.pushReplacementFade(context, (_) => Screen(...))` | Fade-replace (splash → home) |
| `OmniNavigator.popUntil(context, predicate)` | Pop multiple routes (e.g. back to root) |

See `docs/navigation_contract.md` for the full rationale.

---

## Overview

OmniTrain uses **imperative navigation** via `OmniNavigator` (wrapping Flutter's `Navigator.push` / `Navigator.pop`). There is no named-route system or declarative router (no GoRouter, no AutoRoute). All dependencies are passed via constructor injection — no Provider, Riverpod, or Bloc.

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
- Builds the theme via `buildTheme()`
- Sets `MaterialApp.home` based on the `showOnboarding` flag (read from SQLite preference `onboarding_complete` in `main.dart`):
  - Fresh install (`onboarding_complete` absent or `false`) → `OnboardingScreen`
  - Returning user (`onboarding_complete = true`) → `HomeScreen`
- Passes all dependencies via constructor

```
main.dart → (fresh install, onboarding_complete absent/false) → OnboardingScreen → [Get Started] → HomeScreen
main.dart → (returning user, onboarding_complete = true)       → HomeScreen
```

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
  ├── Free Training Tile ──→ Free Training start sheet
  │                            ├── Rolling Session toggle
  │                            └── Start Session ──→ WorkoutSessionScreen (modality = null)
  │                                                  └── Empty finish discards the session and returns to HomeScreen
  │
    └── Maintenance Sheet
      ├── Calendar ──→ CalendarScreen
      ├── Profile ──→ ProfileScreen
      ├── Stats ──→ StatsScreen
      └── Settings ──→ SettingsScreen
```

---

## Screen Inventory

| Screen | File | Purpose |
|--------|------|---------|
| `HomeScreen` | `lib/features/home/home_screen.dart` | 3×2 tile grid + maintenance sheet |
| `SessionOverviewScreen` | `lib/features/session/session_overview_screen.dart` | Exercise list for current session, add/remove exercises |
| `WorkoutSessionScreen` | `lib/features/session/workout_session_screen.dart` | Core workout tracking (list view + detail view). Split into 4 Dart `part` files: main coordinator, `workout_session_timer_mixin.dart` (timer state/logic), `workout_session_list_view.dart` (list-view builders), `workout_session_detail_view.dart` (detail-view builders). Detail view uses an inline set-progress row (`remove · label · add`) plus a back / start-or-log / forward action row. Timer control lives on the timer display itself, and the session clock stays at `00:00` until the first exercise is added. Removing a logged entry or the last remaining entry confirms before deletion. |
| `SessionSummaryScreen` | `lib/features/session/session_summary_screen.dart` | Post-workout summary, PRs, save-as-routine |
| `MyRoutinesScreen` | `lib/features/routine/my_routines_screen.dart` | List of saved routines |
| `RoutineSetupScreen` | `lib/features/routine/routine_setup_screen.dart` | Create/edit routines (dual view) |
| `ExerciseEditorScreen` | `lib/features/exercise/exercise_editor_screen.dart` | Create/edit custom exercises with modality-aware capability/discipline filtering; accepts optional `contextModality` for session-prefill |
| `ProfileScreen` | `lib/features/profile/profile_screen.dart` | Identity, avatar, and body measurement tracking |
| `SettingsScreen` | `lib/features/settings/settings_screen.dart` | Calendar start-of-week, weight/distance units, timer alert preferences, feeling survey toggle, appearance theme selector, and a low-emphasis version footer |
| `StatsScreen` | `lib/features/stats/stats_screen.dart` | Read-only stats: all-time sessions, total training time, current streak, Strength e1RM/volume trends, Cardio pace/duration trends, and recent PRs |
| `OnboardingScreen` | `lib/features/onboarding/onboarding_screen.dart` | First-launch 3-page swipeable intro. Page 1: app pitch. Page 2: modality tiles with accent colors and one-liners. Page 3: calendar features + Get Started button. Completion sets `onboarding_complete` preference key via `repository.setPreferenceBool` and calls `pushReplacement` to `HomeScreen`. |
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
  → SettingsState(repository)     ← persisted app theme + weight/distance unit preferences via repository preferences
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

Cold-start persistence resume:
- On first frame of `HomeScreen`, when `workoutState.hasActiveSession == false`, state checks storage for in-progress sessions.
- If one exists, an `AlertDialog` titled `Unfinished Session` is shown.
- `Continue` restores the historical session and pushes `WorkoutSessionScreen`.
- `Discard` uses one confirmation tap (`Discard` -> `Confirm Discard`) and deletes by id.
- System back-dismiss returns `null` and preserves the stored session (no delete side effect).
- If multiple dangling sessions exist, only the most recent is surfaced; older ones are cleaned up by state.

When tapping a different modality tile while a session is active:
- A confirmation dialog appears: "Start New Session? Current session will be saved."
- Confirming ends the current session and creates a new one

---

## Related Documentation

- [App Philosophy](app_philosophy.md) — Home screen tile layout and UX constraints
- [Modality Tracking](modality_tracking.md) — Session creation and modality resolution
- [Session Summary](session_summary.md) — Post-workout summary screen

---

**Document Version**: 1.5
**Last Updated**: May 17, 2026
