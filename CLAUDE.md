# OmniTrain Agent Brief

OmniTrain is a Flutter/Dart strength-and-fitness training app (iOS/Android focused) built around a dense instrument-panel UX: fast logging, clear status, restrained motion, and functional controls. Primary action is logging work (especially logging a set). Everything else is secondary.

## Core Product and Architecture

- Modality-driven workout logging across: cardio_endurance, resistance_lifting, sports, isometric_stretching, and free training (null modality).
- Core differentiator: exercises carry capability flags (time, hold, reps, sets, load, distance, rounds). UI behavior and effort tracking derive from capabilities + modality config, not join-heavy per-modality exercise duplication.
- Effort kinds are explicit and drive rendering/analytics: set, timed, round, drill.
- Repository pattern is non-negotiable: state/services/features must depend on `WorkoutRepository` interface only, never concrete storage classes.

## Environment Contract

- Single codebase must stay environment-safe for web and native.
- Runtime today is Hive-backed via `HiveWorkoutRepository` (see `lib/main.dart` and `lib/data/repositories/hive_workout_repository.dart`).
- `MockWorkoutRepository` exists as a web-compatible in-memory implementation for testing/dev compatibility.
- SQLite parity is maintained through schema + migrations assets (`scripts/sqlite_schema.sql`, `scripts/sqlite_seed.sql`, `lib/data/datasources/`) and is the native-target persistence direction.

## Authoritative Rules and Docs

- Start with `.github/agents/docs/global_conventions.md` (authoritative cross-cutting rules).
- Then use `.github/agents/docs/README.md` for the index and relevant feature/architecture docs:
  - `app_philosophy.md`
  - `modality_tracking.md`
  - `modality_based_exercise_ui.md`
  - `state_management.md`
  - `data_models.md`
  - `db_integration.md`
  - `design_system.md`
  - `constants_reference.md`
  - `navigation_and_screens.md`
  - `widget_catalog.md`

## Tech Stack and Design Tokens

- Flutter + Dart
- Material 3 theming (`useMaterial3: true`)
- Hive local persistence
- ChangeNotifier state + constructor DI from `lib/main.dart`
- Core tokens/constants in `lib/core/constants/` (notably `omni_theme.dart`, `modality_config.dart`, `modality.dart`, `metric_ids.dart`, `workout_constants.dart`)

## Codebase Orientation

- `lib/main.dart`, `lib/app.dart`: app entrypoint, DI wiring, theme/app shell.
- `lib/data/`: domain models, repository interface, repository implementations, datasource/migration assets.
- `lib/state/`: ChangeNotifier state boundary (Workout, Routine, Settings, Calendar, Profile, etc.).
- `lib/features/`: screen-level features (home, session, exercise, routine, profile, settings, stats, onboarding).
- `lib/widgets/`: reusable presentation widgets.
- `lib/core/`: shared constants, services, and utilities.
- `.github/agents/docs/`: architecture and behavior source of truth.
- `test/`: layer and feature tests; update alongside behavior changes.

## Working Rules for Claude Code

- Keep edits minimal and architecture-consistent.
- Verify affected tests.
- Never bypass repository interfaces from state/features.
- Follow conventions/tokens from docs and constants; do not invent parallel patterns.