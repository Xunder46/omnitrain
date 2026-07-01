# Session Exercise Capabilities Hydration Plan

## Overview

Exercises displayed inside a workout session were losing their capability flags
(bilateral, etc.) because `SessionCore.addExerciseToSession` cached the incoming
`Exercise` as-is, trusting that the caller had already merged capabilities. In
practice the caller may have an `Exercise` whose `capabilities` list is empty
(e.g., from a future code path, a routine manifest constructed against a
stale repository snapshot, or any code path that builds an `Exercise` without
going through `getExercisesRankedForModality` / `getExercises`). Once cached
without flags, `loadSessionData()` short-circuits the repository re-read
(because the cache already has the id), so the empty capability list
persists for the lifetime of the session — meaning the exercise info sheet's
`isBilateral` check is false for a bilateral-flagged exercise like Dumbbell
Curl, and the bilateral logging note never appears.

The fix routes the cache write through `_repository.getExerciseById(...)`, the
same hydration the exercise browser uses, so the cached exercise is always
the canonical version with capabilities merged in.

## Requirements

- `SessionCore.getExercise(id)` must return an `Exercise` whose `capabilities`
  contains the same flags that the exercise browser (picker) would show for
  that id.
- The fix must hold even when the caller of `addExerciseToSession` passes an
  `Exercise` with `capabilities` empty (or wrong): the cache must reflect the
  repository's canonical capability list.
- The fix must not change capability storage (the separate store stays), the
  capability merge logic (no new `copyWith` semantics), or the wording of the
  bilateral note.
- Existing behavior must be preserved: routine manifests, picker flow,
  historical session load, and resumed-session load must all continue to work
  (and now be defensively correct).

## Acceptance Criteria

- AC-1: `addExerciseToSession` with an `Exercise` whose `capabilities` is empty
  results in `_exerciseCache[exercise.id].capabilities` equal to the
  repository's canonical list for that id (i.e., `bilateral` for
  `exercise-dumbbell-curl`).
- AC-2: Opening the exercise info sheet for a bilateral-flagged exercise
  (e.g., Dumbbell Curl) inside a session renders the `LOGGING NOTE` section
  AND the bilateral body text ("Log both sides as a single combined set…").
- AC-3: A non-bilateral exercise (e.g., Barbell Bench Press) inside a session
  does NOT render the `LOGGING NOTE` section.
- AC-4: The exercise info sheet for an exercise with `bilateral` capability
  but no image/steps shows `LOGGING NOTE` and does NOT show
  "No information available yet".
- AC-5: S-001 is updated (or has a companion) that goes through the real
  session hydration path (`loadSessionData` after `addExerciseToSession`)
  using an exercise whose capabilities are NOT set by the test body — so a
  future regression to `addExerciseToSession`'s caching is caught.

## Scenarios

### S-001: addExerciseToSession hydrates capabilities from the repository
- Trigger: `WorkoutState.addExerciseToSession(exerciseWithEmptyCaps)` where
  `exerciseWithEmptyCaps.id` matches a seeded exercise (e.g.,
  `exercise-dumbbell-curl`).
- Precondition: `MockWorkoutRepository.initialize()` has been called; the
  exercise exists in the repo with `['reps', 'sets', 'load', 'bilateral',
  'time']` in its capability store.
- Flow: build an `Exercise(id: 'exercise-dumbbell-curl', capabilities: const
  [])`, call `addExerciseToSession(...)`, then read
  `workoutState.getExercise('exercise-dumbbell-curl')`.
- Expected outcome: the returned `Exercise.capabilities` contains
  `ExerciseCapability.bilateral` and the other seeded flags — not an empty
  list.
- Edge case of: none.

### S-002: bilateral info sheet through real session hydration path
- Trigger: open the info sheet on a bilateral-flagged exercise after a full
  session pump.
- Precondition: a session with one seeded bilateral exercise has been added
  via `addExerciseToSession` using an exercise fetched from
  `repository.getExercisesRankedForModality(...)` (the same call the picker
  makes); the test does NOT pre-populate capabilities by hand.
- Flow: pump `WorkoutSessionScreen`, tap the exercise tile to enter detail
  mode, tap the `exercise-info-button`.
- Expected outcome: `LOGGING NOTE` is rendered exactly once and the bilateral
  body copy ("Log both sides as a single combined set…") is present.
- Edge case of: none.

### S-003: non-bilateral exercise shows no bilateral note (regression guard)
- Trigger: open the info sheet on a non-bilateral exercise inside a session.
- Precondition: a seeded non-bilateral exercise (e.g., bench press) has been
  added via the real session path; capabilities come from the repository, not
  the test.
- Flow: pump session, tap tile, tap `exercise-info-button`.
- Expected outcome: `LOGGING NOTE` is NOT rendered.
- Edge case of: S-002.

### S-004: bilateral + no steps/image shows note, hides empty-state (regression guard)
- Trigger: open the info sheet on a bilateral-flagged exercise that has no
  image asset and no `howToSteps`.
- Precondition: the exercise is fetched from the repository and added via the
  real session path; capabilities are NOT injected by the test.
- Flow: pump session, tap tile, tap `exercise-info-button`.
- Expected outcome: `LOGGING NOTE` is rendered; "No information available yet"
  is NOT rendered.
- Edge case of: S-002.

### S-005: bilateral exercise from `getExercisesRankedForModality` keeps caps across `loadSessionData`
- Trigger: simulate the picker → session path by feeding an exercise from
  `getExercisesRankedForModality` into `addExerciseToSession`, then call
  `loadSessionData()` (which the screen's `_loadExercises` calls).
- Precondition: a resistance session exists; the chosen exercise is bilateral.
- Flow: add exercise, call `loadSessionData`, then
  `workoutState.getExercise(exercise.id)`.
- Expected outcome: the cached exercise's `capabilities` still contains
  `bilateral` after `loadSessionData` (i.e., the cache write in
  `addExerciseToSession` is not clobbered by the `loadSessionData` skip path,
  and `loadSessionData`'s own re-read path is also correct).
- Edge case of: S-002.

## Iteration 1

### DB Changes
- None. Capability storage (the separate `_exerciseCapabilities` box / map)
  is unchanged.

### Backend Changes
- None. No model, repository interface, or seed data change.

### Frontend Changes
- `lib/state/workout/session_core_entry.dart`: in `addExerciseToSession`,
  replace the direct `_exerciseCache[exercise.id] = exercise;` write with a
  hydration pass:
  ```dart
  // Hydrate through the repository so the cached exercise carries the
  // canonical capabilities (matches how the exercise browser presents them).
  final hydrated = (await _repository.getExerciseById(exercise.id)) ?? exercise;
  _exerciseCache[exercise.id] = hydrated;
  ```
  This is the only code change. `getExerciseById` already merges
  capabilities from the separate store in both the Hive and Mock
  implementations; the `?? exercise` fallback keeps the behavior safe if the
  exercise is brand-new and not yet in the repo (which should not happen in
  practice, but preserves current behavior).

### Implementation Steps
1. Edit `session_core_entry.dart` per the snippet above (Phase 1 → Phase 2
   boundary; minimal state change).
2. Add test S-001 in a new test file or an existing capability-focused file
   (decision: extend `test/exercise_info_sheet_bilateral_test.dart` so the
   hydration test and the info-sheet tests live together).
3. Add test S-005 in the same file to guard the `loadSessionData` ↔ cache
   interaction.
4. Update existing S-001 (or add a companion S-002-b) so that the exercise
   is sourced from `repository.getExercisesRankedForModality(...)` — i.e.,
   the same code path the picker uses — and then the test pumps through
   `_loadExercises` (which already calls `loadSessionData`). The existing
   `getExercises().firstWhere` form can be replaced with the ranked call so a
   regression that drops capabilities at any point in the picker → cache →
   session chain is caught.
5. Run `flutter test test/exercise_info_sheet_bilateral_test.dart` — all
   tests must pass.
6. Run the full suite `flutter test` — no previously passing test should now
   fail.

## Progress

- [x] Phase 0 plan written
- [x] Phase 0 Complete ✓
- [x] Phase 1: data-layer edits (none required; plan acknowledges this)
- [x] Phase 1 Complete ✓
- [x] Phase 2: state edit + tests
- [x] Phase 2 Complete ✓
- [x] Phase 3: code review
- [x] Phase 3 Complete ✓

### Phase 3 Complete ✓
Code review verdict: ✅ APPROVED.

Layers in scope: state, tests, docs
Layers skipped: models, repositories, core, widgets, features

Doc hygiene:
| Doc | Status |
|---|---|
| state_management.md | ✅ updated (one-line clarification of hydration behavior) |
| data_models.md | ✅ still accurate ("capabilities (populated at query time, not stored on model)") |
| db_integration.md | N/A (no repo/seed changes) |
| widget_catalog.md | N/A (no widget changes) |
| navigation_and_screens.md | N/A (no route changes) |

Conventions:
PASS (3 rules): reuse canonical owner (uses `_repository.getExerciseById`,
the same hydration the exercise browser uses); repository interface only
(`_repository` is typed `WorkoutRepository`); effort-kind drives analytics
(N/A — no analytics change, only capability propagation).
N/A (4 rules): units + canonical storage, theme tokens, OmniSurface cards,
timestamps as source data.
FAIL: none.

Findings: none.

Test gaps: none — every scenario in the register maps to ≥1 test.

Critical: 0 | Warnings: 0 | Suggestions: 0.

### Phase 2 Complete ✓
- TDD red phase: `test/exercise_info_sheet_bilateral_test.dart` S-006 and S-007
  failed with the unpatched code (cached capabilities were `[]`, the
  bilateral note didn't render).
- State edit: `lib/state/workout/session_core_entry.dart`
  `addExerciseToSession` now hydrates through `_repository.getExerciseById`
  before writing to `_exerciseCache`; the caller's Exercise is preserved as
  a fallback if the repository doesn't know the id.
- Test update: S-001 in the same file now sources the exercise from
  `getExercisesRankedForModality` (the real picker path) instead of
  `getExercises`, so a regression anywhere in the picker → cache → session
  chain is caught.
- New tests: S-006 (cache hydration unit-style) and S-007 (full
  widget test with no caps injected by the test body).
- Green phase: 306 tests pass in the combined run
  (`test/state_test.dart` + `test/models_test.dart` +
  `test/exercise_info_sheet_bilateral_test.dart`). Pre-existing
  `avatar_crop_sheet_test` and a flaky `round_auto_expiry_test` S-BUG-003 are
  unrelated and confirmed to fail on `git stash` of these changes too.

### Phase 0 Complete ✓
Plan written and reconciled with source. No data-layer edits needed (capability storage is unchanged; the merge logic at `getExerciseById` and `getExercisesRankedForModality` is already correct in both `MockWorkoutRepository` and `HiveWorkoutRepository`). The fix is purely in the state layer's `addExerciseToSession` cache write.

### Phase 1 Complete ✓
Confirmed: no model, repository interface, seed data, or SQL schema changes. The capability store (`_exerciseCapabilities` map / `exercise_capabilities` Hive box) is unchanged. `_getCapabilities` and `getExerciseById` already merge capabilities in both implementations. Only the state-layer cache write in `session_core_entry.dart` needs to change.

## Feedback

(fold prior-session blockers here if any)