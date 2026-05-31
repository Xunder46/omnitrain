# OmniTrain Documentation Index

## What This Is

This documentation describes the architecture, features, and conventions of OmniTrain — a universal fitness tracking Flutter app. It is written for **AI pair programming agents and human developers** to understand the codebase quickly and make safe changes.

---

## Quick Start

**OmniTrain** is a Flutter workout logging app that supports any athlete and any sport. Users select a training modality (Cardio, Resistance, Sports, Isometric, or Free Training), add exercises, and track their workout with adaptive UI controls that change based on the modality.

- **Tech stack**: Flutter (Dart), Hive (persistence), ChangeNotifier (state), Constructor DI
- **No** Provider/Riverpod/Bloc — all dependencies are injected manually from `main.dart`
- **Repository pattern**: `WorkoutRepository` interface with `HiveWorkoutRepository` (current) and future `SqliteWorkoutRepository`
- **Navigation**: Imperative (`Navigator.push/pop`) — no named routes or declarative routers

---

## Documentation Map

### Shared Conventions
| Document | Description |
|----------|-------------|
| [Global Conventions](global_conventions.md) | Cross-cutting rules that apply to every task: units and canonical storage, theme tokens, effort-kind analytics, timestamps, and product guardrails |

### Product & Philosophy
| Document | Description |
|----------|-------------|
| [App Philosophy](app_philosophy.md) | Core product goals, UX principles, entity model, MVP boundary, home screen layout |
| [Design System](design_system.md) | Visual identity, color tokens, typography, spacing, animation rules, component patterns, accessibility |

### Feature Documentation
| Document | Description |
|----------|-------------|
| [Modality Tracking](modality_tracking.md) | How exercise capabilities, modalities, and effort kinds work together — the core differentiator |
| [Modality-Based Exercise UI](modality_based_exercise_ui.md) | The adaptive workout session screen — per-modality controls, timer management, swipe gestures |
| [Exercise Info & Notes](exercise_info_and_notes.md) | Workout session detail header sheets: exercise info reference and persistent per-exercise notes |
| [Exercise Ranking](exercise_ranking.md) | How exercises are scored and sorted for the exercise picker |
| [Create New Exercise](create_new_exercise.md) | Modality-aware custom exercise creation and editing |
| [My Routines](my_routines.md) | Reusable workout template system — CRUD, template-to-session conversion, UI |
| [Calendar & Periods](calendar_periods.md) | Month calendar planning, day-session management, and non-overlapping training periods |
| [Session Summary](session_summary.md) | Post-workout analytics — PRs, volume comparison, save-as-routine |
| [Profile & Measurements](profile_and_measurements.md) | Profile identity, avatar flow, body measurement logging, and history chart behavior |
| [Theme & Settings](theme_and_settings.md) | Theme system, measurement/calendar preferences, timer alerts, workout toggles, and Settings screen behavior |
| [Rolling Sessions](rolling_sessions.md) | Rolling/continuous free session format, segment block grouping, isRolling flag, and inline start-sheet guidance |
| [Stats Screen](stats_screen.md) | All-time session aggregates, streak, 30-day activity bar chart, rest averages by modality |

### Release & Operations
| Document | Description |
|----------|-------------|
| [iOS TestFlight Release Checklist](../../../docs/releases/ios-testflight.md) | Release workflow, archive/upload steps, and pre-release checks |
| [May 2026 Plan Review](../../../docs/releases/2026-05-plan-review.md) | Summary of the implementation plans reviewed for Apr 17-May 17, 2026 and the docs they affected |

### Architecture & Technical
| Document | Description |
|----------|-------------|
| [Navigation & Screens](navigation_and_screens.md) | Complete screen map, navigation flow, dependency injection pattern |
| [State Management & Services](state_management.md) | ChangeNotifier classes, service classes, dependency graph |
| [Data Models](data_models.md) | All domain models — sessions, exercises, templates, measurements, relationships |
| [Constants & Configuration](constants_reference.md) | Modalities, capabilities, metrics, effort kinds, intents, design tokens |
| [DB Integration](db_integration.md) | Database setup, schema, seed data, dual-backend strategy |
| [Widget Catalog](widget_catalog.md) | Reusable UI components — layout primitives, tiles, pickers, metric editors |
| [Rest Tracking](rest_tracking.md) | Wall-clock rest tracking architecture, EntryRest model, DB-backed rest records between sets |

---

## Architecture Overview

```
lib/
├── core/
│   ├── constants/        # Modalities, capabilities, metrics, theme tokens
│   ├── errors/           # (placeholder — reserved)
│   ├── models/           # Session summary models, routine manifest
│   ├── services/         # RoutineSessionService, SessionSummaryService
│   └── utils/            # ObservationGrouper, ExerciseHelpers, TimerAlertService
├── data/
│   ├── datasources/      # DatabaseProvider (SQLite), migrations
│   ├── models/           # 20+ pure Dart model classes
│   └── repositories/     # WorkoutRepository interface + Hive implementation
├── features/
│   ├── exercise/         # ExerciseEditorScreen
│   ├── home/             # HomeScreen, maintenance sheet routes
│   ├── profile/          # ProfileScreen + profile feature widgets
│   ├── routine/          # MyRoutinesScreen, RoutineSetupScreen
│   ├── session/          # SessionOverviewScreen, WorkoutSessionScreen, SessionSummaryScreen
│   ├── splash/           # OmniSplashScreen (disabled)
│   └── workout/          # (empty — reserved)
├── mock/                 # SeedData for development
├── state/
│   ├── home/             # HomeState (maintenance hint)
│   ├── calendar/         # CalendarState (month/day session management)
│   ├── period/           # PeriodState (training period lifecycle + overlap guards)
│   ├── profile/          # ProfileState (profile + measurement flows)
│   ├── routine/          # RoutineState (template CRUD)
│   ├── settings/         # SettingsState (theme, unit, and preference state)
│   └── workout/          # WorkoutState (session lifecycle)
├── widgets/
│   ├── buttons/          # (empty — reserved)
│   ├── cards/            # EnergyTile, EnergyCore, MaintenanceTile
│   ├── layout/           # OmniGradientBackground, OmniSurface, NoiseOverlay
│   ├── logo/             # AnimatedZenHalo, ZenHaloPainter
│   ├── models/           # UiSetData (presentation model)
│   ├── pickers/          # ExercisePickerDialog, MetricChooserDialog, ModalityPickerDialog
│   └── session/          # InlineMetricEditor, DominantMetricWidget
├── app.dart              # MyApp, theme construction
└── main.dart             # Entry point, DI setup
```

---

## Key Concepts for New Contributors

### 1. Modality → Effort Kind → UI Controls
The entire app adapts based on modality:
- `resistance_lifting` → effort kind `set` → reps + weight editors
- `cardio_endurance` → effort kind `timed` → duration timer + distance
- `sports` → effort kind `round` → round counter + countdown timer
- `isometric_stretching` → effort kind `drill` → hold timer + extra weight

### 2. Capabilities Are Flags, Not Joins
Exercises have capability flags (`time`, `reps`, `load`, `hold`, `rounds`, `distance`, `sets`) that determine which modalities they can serve. This means:
- Barbell Squat (`[reps, sets, load, time]`) can be tracked by reps in resistance OR by time in cardio
- No duplicate exercises needed for different modalities

### 3. Repository Pattern Is Law
All data access goes through `WorkoutRepository` interface. State classes never import concrete repository implementations. This enables swapping between Hive (web/current) and SQLite (native/future) with zero code changes.

### 4. Immediate Persistence
Every metric change is persisted immediately via the repository — no "save" button, no unsaved state. If the app crashes mid-workout, data is preserved.

### 5. Round Efforts Are Special
Round efforts (`effortKind == 'round'`) use `RoundInstance` records with wall-clock timestamps, not observation rows. This makes them background-resilient (timer survives app suspension). They follow a strict state machine: `notStarted → active ⇄ paused → finished` (terminal).

### 6. Profile Is Live In Maintenance
The maintenance sheet no longer routes Profile to a placeholder. It now pushes `ProfileScreen`, which is backed by `ProfileState` and repository APIs for `UserProfile` and `BodyMeasurementEntry`.

Profile measurement rules implemented in code:
- Primary rows: bodyweight, height
- Additional rows (always visible): body fat %, lean mass, waist, chest, hips, thigh, arm
- Save-time timestamping for logs (no date input UI)
- Chart-based history sheet with point selection and "Log New Entry" stacking behavior
- Avatar path persistence is native-first; web degrades safely to fallback icon

---

## Agent-Specific Notes

### For the Conductor Agent
- Always reference the relevant feature docs before planning changes
- Hand off database changes to the DBA agent, UI changes to the Developer agent
- After implementation, hand off to the Code Reviewer agent

### For the Developer Agent
- Never import concrete repository classes — only the interface
- All buttons must have explicit `shape:` overrides (no Material 3 default StadiumBorder)
- Check `WorkoutConstants` before hardcoding any numeric values
- Round efforts use `WorkoutState.startRound/pauseRound/etc.` — never `updateEntryValue`

### For the DBA Agent
- Every schema change must update the `WorkoutRepository` interface first
- Then implement in `HiveWorkoutRepository` (in-memory boxes)
- Update `scripts/sqlite_schema.sql` and `scripts/sqlite_seed.sql` for future SQLite
- Models in `lib/data/models/models.dart` must be pure Dart (no Flutter imports)

### For the Designer Agent
- All design tokens live in `OmniTheme` — see [Design System](design_system.md)
- The Splash Screen Litmus Test: if it slows down starting a workout, it doesn't belong
- Aesthetic is "spacecraft interior" — precision instruments, not cosmic wallpaper

### For the Code Reviewer Agent
- Check the review checklist in your agent file
- Verify buttons have `shape:` overrides
- Verify state classes only use repository interface
- Look for hardcoded colors (should use `theme.colorScheme`)

---

**Last Updated**: May 22, 2026
