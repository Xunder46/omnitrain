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
- The SQLite **runtime has been retired** — `sqflite` is no longer a dependency, `lib/data/datasources/database_provider.dart` / `db_helper.dart` / `migrations.dart` are deleted, and the SQL files are no longer bundled as app assets. Hive is the persistence engine on every platform.
- `scripts/sqlite_schema.sql` and `scripts/sqlite_seed.sql` remain the **canonical data-model documentation** for the agent pipeline. Keep them in step with `lib/data/models/models.dart`; `test/db_seed_test.dart` executes them against an in-memory database to prove they stay valid SQL. Treat them as the schema contract, not as a live persistence path.

## Authoritative Rules and Docs

> **Doc freshness.** The docs in `.github/agents/docs/` are derived from source, not hand-maintained. If a claim there disagrees with `lib/`, `lib/` wins. Past snapshots / superseded audits live under `.github/agents/docs/history/` and under `docs/releases/` — they are clearly labeled `HISTORY` and must not be treated as current state.
>
> **Audit — 2026-07-26.** A full audit against `lib/` corrected drift across the set: nutrition tracking was still listed as an explicit non-goal, six screens were missing from the inventory, four data models were undocumented, and the SQLite runtime was documented as live after being retired. Two oversized docs were split so the whole set is indexable. Read `.github/agents/docs/docs-audit-2026-07-26.md` for what changed and, more importantly, **what is still unresolved** — including two conflicting hub implementations and the absence of any way to identify a custom exercise.
>
> **Size ceiling.** No file in `.github/agents/docs/` may exceed 64 KiB; larger files are silently skipped by the tools that index them. Enforced by `test/docs_indexing_contract_test.dart`. Split oversized docs into part pages and keep the original path as an index so inbound links keep resolving.

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
  - `state_management.md` — index for `ChangeNotifier` classes, service classes, dependency graph (split into `state_management/`)
  - `data_models.md` — all domain models (sessions, exercises, templates, measurements, etc.)
  - `constants_reference.md` — modalities, capabilities, metrics, effort kinds, intents, design tokens
  - `db_integration.md` — schema/seed SQL as the data-model contract, catalog + data versioning (the SQLite runtime is retired)
  - `widget_catalog.md` — index for reusable UI components (split into `widget_catalog/`)
  - `rest_tracking.md` — wall-clock rest tracking, `EntryRest` model, DB-backed rest records
  - `navigation_and_screens.md` — complete screen map, navigation flow, dependency injection pattern
  - `navigation_contract.md` — the navigation contract (enforced by `test/navigation_contract_enforcement_test.dart`)
  - `design_system.md` — visual identity, color tokens, typography, spacing, animation rules, component patterns
  - `history/route-migration-audit.md` — **HISTORY** original `centralized-route-system` migration audit (superseded by the automated test)
  - `docs-audit-2026-07-26.md` — record of the 2026-07-26 audit: what was corrected, what was added, and what remains unresolved
  - **Nutrition** has no dedicated feature doc yet; its behavior is spread across `navigation_and_screens.md`, `state_management/nutrition_state.md`, `widget_catalog/nutrition_widgets.md`, `data_models.md`, and `db_integration.md`

## Tech Stack and Design Tokens

- Flutter + Dart
- Material 3 theming (`useMaterial3: true`)
- Hive local persistence
- ChangeNotifier state + constructor DI from `lib/main.dart`
- Core tokens/constants in `lib/core/constants/` (notably `omni_theme.dart`, `modality_config.dart`, `modality.dart`, `metric_ids.dart`, `workout_constants.dart`)

## Codebase Orientation

- `lib/main.dart`, `lib/app.dart`: app entrypoint, DI wiring, theme/app shell.
- `lib/data/`: domain models, repository interface, repository implementations, and the food-catalog loader.
- `lib/state/`: ChangeNotifier state boundary (Workout, Routine, Settings, Calendar, Profile, etc.).
- `lib/features/`: screen-level features (home, session, exercise, routine, calendar, period, nutrition, profile, settings, stats, onboarding, splash, startup).
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

> **Doc freshness** — Last reconciled against source: 2026-07-26. This doc is derived from source, not hand-maintained. Source of truth: the `lib/` tree as it exists on the reconciliation date. If you find a claim here that disagrees with `lib/`, `lib/` wins — please flag the drift in a fresh chat with the Coordinator agent.
