# Exercise Ranking / Recommended Sorting — Technical Notes

This document describes how exercises are ranked and sorted for a given session modality in the codebase.

## Purpose

- Provide a concise, technical description of the inputs, algorithm, and outputs for exercise ranking used by the UI.
- Help future implementers port, tune, or convert the ranking algorithm to other repositories (e.g. SQLite implementation).

## Where to look in the code

- Repository entrypoint: `lib/data/repositories/mock_workout_repository.dart` — implements `getExercisesRankedForModality(...)` for the mock data source.
- Public state wrapper: `lib/state/workout/workout_state.dart` — delegates to the repository and exposes `getExercisesRankedForModality` to UI code.
- Modality configuration & scoring helpers: `lib/core/constants/modality_config.dart` — defines `ModalityConfig` and contains the scoring logic (`calculateRelevanceScore`).
- Consumer/UI: `lib/features/exercise/exercise_picker_screen.dart` — previously partitioned the returned list into sections; UI now consumes the repository-sorted list.

## Inputs

- `modality` (String?) — the session modality key (e.g. `cardio_endurance`, `resistance_lifting`, `sports`). When `null` this is Free Training mode.
- Optional filters: `searchText`, `disciplineId`, `muscleGroupIds`.
- Static reference data: disciplines, sport categories, exercise capability mappings.

## High-level flow (repository)

1. Start from all non-archived exercises (apply basic filters: text, discipline, muscle groups).
2. If `modality == null` (Free Training):
   - Return alphabetically sorted exercises (by name).
3. Otherwise (modality present):
   - Resolve `ModalityConfig` for the modality (primary/secondary/anti capabilities, category id, etc.).
   - For each candidate exercise:
     - Attach the exercise capabilities (from seed data / capability map).
     - Resolve the exercise discipline -> category id (if present) for affinity scoring.
     - Compute a numeric relevance score using `ModalityConfig.calculateRelevanceScore(...)`.
   - Sort exercises by: `score DESC`, then `name ASC` (alphabetical tie-breaker).
   - Return the sorted list of `Exercise` objects (capabilities attached).

## Scoring (conceptual)

- The `ModalityConfig` encapsulates what matters for a modality:
  - `primaryCapabilities`: strong positive signals (e.g. `reps` for resistance, `time` for cardio/sports)
  - `secondaryCapabilities`: weaker positive signals
  - `antiCapabilities`: negative signals that reduce relevance
  - `categoryId`: discipline-category affinity increases score when an exercise's discipline belongs to the modality's category

- `calculateRelevanceScore(...)` combines capability matches and category affinity into a single floating point score. Typical components:
  - +X if exercise supports a primary capability
  - +Y for each matching secondary capability
  - -Z for anti-capabilities present
  - +W if discipline.categoryId == modality.categoryId (affinity bonus)

Note: the precise numeric weights live in `ModalityConfig.forModality` / `calculateRelevanceScore` and can be tuned there.

## UI considerations

- The UI (`ExercisePickerScreen`) requests `getExercisesRankedForModality(modality, ...)` and receives a sorted list.
- Previously the dialog partitioned results into "Recommended" (exercises supporting the modality's primary metric) and "Other exercises"; that partitioning has been removed and the list is displayed in the repository's sorted order.

## Files to update when tuning behavior

- `lib/core/constants/modality_config.dart` — adjust primary/secondary/anti capability lists and weights.
- `lib/data/repositories/mock_workout_repository.dart` — port to SQLite: the same input/output contract should be preserved.
- `lib/features/exercise/exercise_picker_screen.dart` — decide whether to reintroduce UI grouping by thresholds or display score badges.

---
Generated: automated documentation added to repository.


---

> **Doc freshness** — Last reconciled against source: 2026-07-26. This doc is derived from source, not hand-maintained. Source of truth: the `lib/` tree as it exists on the reconciliation date. If you find a claim here that disagrees with `lib/`, `lib/` wins — please flag the drift in a fresh chat with the Coordinator agent.
