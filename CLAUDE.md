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

> **Doc freshness.** Every current-state doc in `.github/agents/docs/` was re-derived from source on 2026-06-29 and carries a `Last reconciled against source: 2026-06-29` stamp. The docs are derived from source, not hand-maintained. If a claim here disagrees with `lib/`, `lib/` wins. Past snapshots / superseded audits live under `.github/agents/docs/history/` and under `docs/releases/` — they are clearly labeled `HISTORY` and must not be treated as current state.

- Start with `.github/agents/docs/global_conventions.md` (authoritative cross-cutting rules).
- Then use `.github/agents/docs/README.md` for the index and relevant feature/architecture docs:
  - `app_philosophy.md` — product goals, entity model, home screen layout
  - `modality_tracking.md` — exercise capabilities, modalities, effort kinds
  - `modality_based_exercise_ui.md` — adaptive workout session screen
  - `exercise_info_and_notes.md` — exercise-info sheet and per-exercise notes
  - `exercise_ranking.md` — exercise ranking algorithm
  - `create_new_exercise.md` — modality-first custom exercise editor
  - `my_routines.md` — reusable workout templates (CRUD + template-to-session)
  - `calendar_periods.md` — month calendar, day-session list, training periods
  - `rolling_sessions.md` — rolling/continuous free session format, `isRolling` flag
  - `session_summary.md` — post-workout analytics, per-group deltas, feeling-survey capture
  - `stats_screen.md` — all-time aggregates, scrollable strength + cardio trends, Recent PRs, NUTRITION card
  - `profile_and_measurements.md` — identity, avatar, body measurement logging, history chart
  - `theme_and_settings.md` — theme grid, units, timer alerts, Feeling Survey toggle
  - `state_management.md` — `ChangeNotifier` classes, service classes, dependency graph
  - `data_models.md` — all domain models (sessions, exercises, templates, measurements, etc.)
  - `constants_reference.md` — modalities, capabilities, metrics, effort kinds, intents, design tokens
  - `db_integration.md` — database setup, schema, seed data, dual-backend strategy
  - `widget_catalog.md` — reusable UI components (layout primitives, tiles, pickers, metric editors)
  - `rest_tracking.md` — wall-clock rest tracking, `EntryRest` model, DB-backed rest records
  - `navigation_and_screens.md` — complete screen map, navigation flow, dependency injection pattern
  - `navigation_contract.md` — the navigation contract (enforced by `test/navigation_contract_enforcement_test.dart`)
  - `design_system.md` — visual identity, color tokens, typography, spacing, animation rules, component patterns
  - `history/route-migration-audit.md` — **HISTORY** original `centralized-route-system` migration audit (superseded by the automated test)

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

---

> **Doc freshness** — Last reconciled against source: 2026-06-29. This doc is derived from source, not hand-maintained. Source of truth: the `lib/` tree as it exists on the reconciliation date. If you find a claim here that disagrees with `lib/`, `lib/` wins — please flag the drift in a fresh chat with the Coordinator agent.
