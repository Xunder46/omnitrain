# OmniTrain Documentation Index

> **Doc freshness:** This index and every doc linked below were re-derived from the `lib/` source tree. The current-state docs in this folder are not hand-maintained — they are derived from source. Past-snapshot / superseded docs live under [`.github/agents/docs/history/`](history/) with a `HISTORY` banner so they cannot be mistaken for current state.
> **When the source disagrees with this index, the source wins.**
>
> **Audit pass — 2026-07-26.** A full audit against `lib/` corrected several
> documents that had drifted. Highlights: nutrition tracking was still listed
> as an explicit non-goal; six screens were missing from the inventory; four
> data models were undocumented; and the two largest docs exceeded the size
> ceiling of the tools that index this folder and have been split. See
> [`docs-audit-2026-07-26.md`](docs-audit-2026-07-26.md) for the full summary
> and the list of things left unresolved.
>
> **Size ceiling:** no file in this folder may exceed **64 KiB** — larger files
> are silently skipped by the indexers that serve these docs to agents.
> Enforced by `test/docs_indexing_contract_test.dart`.

## What This Is

This documentation describes the architecture, features, and conventions of OmniTrain — a universal fitness tracking Flutter app. It is written for **AI pair programming agents and human developers** to understand the codebase quickly and make safe changes.

---

## Quick Start

**OmniTrain** is a Flutter workout logging app that supports any athlete and any sport. Users select a training modality (Cardio, Resistance, Sports, Isometric, or Free Training), add exercises, and track their workout with adaptive UI controls that change based on the modality.

- **Tech stack**: Flutter (Dart), Hive (persistence), ChangeNotifier (state), Constructor DI
- **No** Provider/Riverpod/Bloc — all dependencies are injected manually from `main.dart`
- **Repository pattern**: `WorkoutRepository` interface with `HiveWorkoutRepository` (runtime) and `MockWorkoutRepository` (tests/dev); the SQLite runtime is retired
- **Navigation**: Imperative, but always through `OmniNavigator` (`lib/core/navigation/`) — no named routes or declarative routers, and raw `MaterialPageRoute` / `PageRouteBuilder` outside that module is a build break

Beyond training, the app also ships **nutrition tracking** (daily calorie
target, a food catalog and personal food library, per-day consumed log, water
tracking) and **calendar planning** (month view, planned sessions, and
non-overlapping training periods).

---

## Documentation Map

### Shared Conventions
| Document | Description |
|----------|-------------|
| [Global Conventions](global_conventions.md) | Cross-cutting rules that apply to every task: units and canonical storage, theme tokens, effort-kind analytics, timestamps, and product guardrails |
| [Documentation Standard](documentation_standard.md) | What these documents may and may not contain; the required top-of-document scope block; the rule that behaviour is pointed at, not described |

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
| [Session Summary](session_summary.md) | Post-workout analytics — per-group comparison vs the previous session, inline PRs, feeling-survey capture, save-as-routine. (The earlier standalone "volume comparison" surface was removed; progress is shown as per-group delta chips.) |
| [Profile & Measurements](profile_and_measurements.md) | Profile identity, avatar flow, body measurement logging, and history chart behavior |
| [Theme & Settings](theme_and_settings.md) | Theme system, measurement/calendar preferences, timer alerts, workout toggles, and Settings screen behavior |
| [Rolling Sessions](rolling_sessions.md) | Rolling/continuous free session format, segment block grouping, isRolling flag, and inline start-sheet guidance |
| [Stats Screen](stats_screen.md) | All-time aggregates (Sessions / Time / Streak), scrollable Strength e1RM and volume trends, scrollable Cardio pace + distance (or duration) trends, all-time Recent PRs, and a full-history NUTRITION card with a Calories / Macros segmented toggle. Each section's top-N exercise list is selected from a "current-state window" (active training period or last 14 training days) while the trend charts themselves use the selected exercise's full history. |
| [Stats Best-Load Investigation](stats_best_load_investigation.md) | Investigation finding (2026-08-16), not a feature doc. Traces every computation that produces a per-exercise best/heaviest-load figure and every surface that displays one. Records what the deleted Records section's "Heaviest load" actually computed (one set's `weight × reps`), which mislabeled figures are still live (Recent PRs and the session-summary PR line show an *estimated* 1RM as a bare weight), and why rep records came out uniformly `10` (a persisted default, not a cap). |
| **Nutrition** — no dedicated feature doc yet | ⚠️ Nutrition shipped but never got its own feature document. Until one exists, the behavior is spread across [Navigation & Screens](navigation_and_screens.md) (the four nutrition screens and their flows), [Nutrition State](state_management/nutrition_state.md) (`NutritionState`, `FoodLibraryState`, `NutritionPrimerState`), [Nutrition Widgets](widget_catalog/nutrition_widgets.md) and [Home Screen & Nutrition Cards](widget_catalog/home_screen.md), [Data Models](data_models.md#nutrition-models), and [DB Integration](db_integration.md). |

### Release & Operations
| Document | Description | Status |
|----------|-------------|--------|
| [iOS TestFlight Release Checklist](../../../docs/releases/ios-testflight.md) | Release workflow, archive/upload steps, and pre-release checks | **Current — operational** |
| [May 2026 Plan Review](../../../docs/releases/2026-05-plan-review.md) | Summary of the implementation plans reviewed for Apr 17-May 17, 2026 and the docs they affected | **History snapshot** (frozen window) |
| [PR-Surface Verification — June 27, 2026](../../../docs/releases/2026-06-27-pr-surface-verification.md) | Read-only verification of the personal-record definition divergence across the in-workout toast, Stats screen, and Session Summary. The divergence it documents is real and unresolved. | **History report** (single-purpose) |

### Architecture & Technical
| Document | Description |
|----------|-------------|
| [Navigation & Screens](navigation_and_screens.md) | Complete screen map, navigation flow, dependency injection pattern |
| [State Management & Services](state_management.md) | **Index** — ChangeNotifier classes, service classes, dependency graph. Split into [Workout](state_management/workout_state.md), [Nutrition](state_management/nutrition_state.md), [Routine/Calendar/Home/Profile/Settings](state_management/app_state.md), and [Services & Utilities](state_management/services_and_utils.md) |
| [Data Models](data_models.md) | All domain models — sessions, exercises, templates, measurements, relationships |
| [Constants & Configuration](constants_reference.md) | Modalities, capabilities, metrics, effort kinds, intents, design tokens |
| [DB Integration](db_integration.md) | Database setup, schema, seed data, dual-backend strategy |
| [Widget Catalog](widget_catalog.md) | **Index** — reusable UI components. Split into [Layout & Inputs](widget_catalog/layout_and_inputs.md), [Home & Nutrition Cards](widget_catalog/home_screen.md), [Session/Pickers](widget_catalog/session_widgets.md), [Nutrition Widgets](widget_catalog/nutrition_widgets.md), and [Routine/Profile/Brand](widget_catalog/feature_primitives.md) |
| [Rest Tracking](rest_tracking.md) | Wall-clock rest tracking architecture, EntryRest model, DB-backed rest records between sets |
| [Navigation Contract](navigation_contract.md) | The single source of truth for screen-level navigation. Enforced by `test/navigation_contract_enforcement_test.dart`; raw `MaterialPageRoute` / `PageRouteBuilder` outside `lib/core/navigation/` is a build break. The historical migration audit lives under [history/route-migration-audit.md](history/route-migration-audit.md). |

---

## Architecture Overview

Re-derived from `lib/` on 2026-07-26. The previous version of this tree was
missing the entire `features/nutrition/`, `features/calendar/`,
`features/period/`, `features/stats/`, `features/onboarding/` and
`features/startup/` areas, the `state/nutrition/` classes, and four
`widgets/` subdirectories.

```
lib/
├── core/
│   ├── constants/        # Modalities, capabilities, metrics, theme tokens
│   ├── errors/           # (placeholder — reserved)
│   ├── models/           # Session summary, stats progress, food draft, routine manifest
│   ├── navigation/       # OmniNavigator, OmniRoute — the navigation contract
│   ├── services/         # RoutineSessionService, SessionSummaryService, StatsProgressService,
│   │                     #   CatalogRefreshService, ImageStorageService, CrashReportingService, …
│   └── utils/            # ObservationGrouper, ExerciseHelpers, TimerAlertService,
│                         #   UnitFormatter, FuzzySearch, OmniDateUtils, …
├── data/
│   ├── models/           # 30+ pure Dart model classes (models.dart)
│   └── repositories/     # WorkoutRepository interface + Hive and Mock implementations
├── features/
│   ├── calendar/         # CalendarScreen, DaySessionListScreen
│   ├── exercise/         # ExerciseEditorScreen, ExercisePickerScreen, ExerciseDetailScreen (wrapper)
│   ├── home/             # HomeScreen + widgets/, MaintenancePlaceholderScreen (dead)
│   ├── nutrition/        # NutritionScreen, NutritionTargetScreen, AddFoodScreen,
│   │                     #   EditFoodScreen + widgets/
│   ├── onboarding/       # OnboardingScreen
│   ├── period/           # PeriodListScreen, CreatePeriodScreen
│   ├── profile/          # ProfileScreen + widgets/
│   ├── routine/          # MyRoutinesScreen, RoutineSetupScreen + widgets/
│   ├── session/          # SessionOverviewScreen, WorkoutSessionScreen, SessionSummaryScreen
│   ├── settings/         # SettingsScreen
│   ├── splash/           # OmniSplashScreen (disabled)
│   ├── startup/          # StartupFailureScreen
│   ├── stats/            # StatsScreen + widgets/ (ScrollableTrendChart)
│   └── workout/          # (empty — reserved)
├── mock/                 # SeedData for development
├── state/
│   ├── calendar/         # CalendarState (month/day session management)
│   ├── home/             # HomeState (maintenance hint)
│   ├── nutrition/        # NutritionPrimerState (one-shot primer seen-flag)
│   ├── period/           # PeriodState (training period lifecycle + overlap guards)
│   ├── profile/          # ProfileState (profile + measurement flows)
│   ├── routine/          # RoutineState (template CRUD)
│   ├── settings/         # SettingsState (theme, unit, and preference state)
│   ├── workout/          # WorkoutState (session lifecycle)
│   ├── nutrition_state.dart     # NutritionState (targets, consumed log, water)
│   └── food_library_state.dart  # FoodLibraryState (catalog + groups + personal library)
├── widgets/
│   ├── buttons/          # (empty — reserved)
│   ├── cards/            # EnergyTile, EnergyCore, MaintenanceTile
│   ├── chart/            # Shared chart primitives
│   ├── common/           # InteractiveLogo
│   ├── icons/            # Custom icon widgets
│   ├── inputs/           # SelectAllOnFocus, NumericFieldWithDoneBar
│   ├── layout/           # OmniGradientBackground, OmniSurface, OmniCardHeader, NoiseOverlay
│   ├── logo/             # AnimatedZenHalo, ZenHaloPainter
│   ├── models/           # UiSetData (presentation model)
│   ├── pickers/          # MetricChooserDialog, ModalityPickerDialog
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
All data access goes through the `WorkoutRepository` interface. State classes never import concrete repository implementations. `HiveWorkoutRepository` is the runtime implementation on every platform; `MockWorkoutRepository` provides in-memory test/dev compatibility. The SQLite runtime has been retired.

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
- Update `scripts/sqlite_schema.sql` and `scripts/sqlite_seed.sql` when the canonical data-model contract changes, even though SQLite is not a runtime backend
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
2026-07-26 (full audit against source; see the audit note at the top of this file
and [`docs-audit-2026-07-26.md`](docs-audit-2026-07-26.md))

---

## History

Documents that describe a past snapshot, a superseded design, or a single-purpose report live under [`.github/agents/docs/history/`](history/) with a `HISTORY` banner so they cannot be mistaken for the current state of the product. The history folder is read-only and is not refreshed when the product changes.

Current contents:

- [`history/route-migration-audit.md`](history/route-migration-audit.md) — the original `centralized-route-system` migration audit (May–June 2026). Superseded as the enforcement mechanism by [`test/navigation_contract_enforcement_test.dart`](../../../test/navigation_contract_enforcement_test.dart); the test wins on disagreement.
- [`history/feedback-pack-baseline-2026-07-27.md`](history/feedback-pack-baseline-2026-07-27.md) — the source baseline recorded on 2026-07-27, immediately before the 2026-07-27 feedback pack (PRs 2–8). Frozen as of that date and no longer accurate: PRs 2, 4, 5 and 6 have since shipped.

**Last Updated**: July 27, 2026

---

> **Doc freshness** — Last reconciled against source: 2026-07-27. This doc is derived from source, not hand-maintained. Source of truth: the `lib/` tree as it exists on the reconciliation date. If you find a claim here that disagrees with `lib/`, `lib/` wins — please flag the drift in a fresh chat with the Coordinator agent.
