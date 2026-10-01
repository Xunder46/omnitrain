# PR 8: Exercise Library

> **Priority 8 of 8 — Tier 4 new feature.** Item 12 only; depends on PR 7.

## Overview

Add a maintenance-sheet Exercise Library that reuses PR 7's details, supports full-catalog browsing plus custom-only filtering, and safely manages custom exercises. Referenced removals disappear from future selection but remain resolvable for history and analytics.

## Requirements

- Add library to the actual wired maintenance sheet, not home grid.
- Full catalog with picker-equivalent search/filter/order and custom-only filter.
- Consistent custom markers.
- Reuse read-only details with no add-to-workout action.
- Custom details offer edit/confirmed remove; built-ins offer copy only.
- Copy creates a distinct prefilled custom exercise without mutating built-in.
- Referenced removal preserves historical names/values/stats/PRs while excluding future selection.
- Unreferenced custom removal may delete completely.
- Custom rename updates picker, routines, and past workout display.
- Enforce built-in immutability below UI.

## Acceptance Criteria

- [ ] Library reachable from wired maintenance sheet and absent from home grid.
- [ ] Full catalog/search/filter and exact custom-only filter work.
- [ ] Custom markers and shared details render.
- [ ] Custom has edit/remove; built-in has copy only.
- [ ] Copy creates new custom and leaves original unchanged.
- [ ] Remove confirms first.
- [ ] Referenced removal preserves history, logged values, stats, and PRs.
- [ ] Removed exercises disappear from workout/routine selectors.
- [ ] Unreferenced removal deletes completely.
- [ ] Rename propagates to picker/routines/history.
- [ ] No library add-to-workout action exists.
- [ ] Built-ins cannot be edited/removed through any path.

## Scenarios

### S-001: Browse/filter catalog
- Trigger: Open library.
- Precondition: Built-in/custom exercises exist.
- Flow: Search/filter → custom-only → details.
- Expected outcome: Picker-equivalent results and no session action.
- Edge case of: none

### S-002: Copy built-in safely
- Trigger: Choose Make a copy.
- Precondition: Built-in is read-only.
- Flow: Prefilled editor → save.
- Expected outcome: New custom created; original unchanged.
- Edge case of: none

### S-003: Remove referenced custom safely
- Trigger: Confirm remove.
- Precondition: Session/routine references exist.
- Flow: Retire from selection → query history/analytics/selectors.
- Expected outcome: History/analytics unchanged; selectors exclude it.
- Edge case of: none

### S-004: Remove unused custom completely
- Trigger: Confirm remove.
- Precondition: No references.
- Flow: Delete aggregate.
- Expected outcome: Record/links gone everywhere.
- Edge case of: S-003

### S-005: Rename custom; protect built-in
- Trigger: Rename custom or attempt built-in mutation.
- Precondition: Exercise appears across contexts.
- Flow: Save rename; invoke mutation paths.
- Expected outcome: Custom name resolves everywhere; built-in mutations rejected.
- Edge case of: none

## Iteration 1

### DB Changes
- **No schema change.** Two fields already exist on `Exercise`:
  - `ownerUserId` (`String?`) — PR 7 establishes this as the canonical
    custom marker via `Exercise.isCustomExercise`
    (`ownerUserId != null`).
  - `isArchived` (`bool`) — already present, already round-tripped,
    already filtered out of `getExercises()` and
    `getExercisesRankedForModality()` in both Hive and Mock.
- The contract this PR commits to:
  - **Referenced removal** (session/routine template references exist)
    → flip `isArchived = true`. History remains resolvable.
  - **Unreferenced removal** (zero references anywhere) → hard-delete
    via `deleteExercise`. No residue.
- "References" means rows where `exerciseId` matches, across:
  - `app_segment_effort.exercise_id`
  - `app_template_effort.exercise_id`
  - (the existing `Exercise` round-trip already preserves the id; rename
    updates the canonical `Exercise.name` and propagates because history
    is read by id and joins on the live `Exercise.name`.)

### Backend Changes
- New **`ExerciseLibraryService`** (`lib/core/services/exercise_library_service.dart`)
  exposes:
  - `Future<List<Exercise>> listExercises({String? search, String? disciplineId, bool customOnly})`
  - `Future<RemovalPlan> planRemoval(String exerciseId)`
  - `Future<void> removeExercise(String exerciseId)` — picks the right
    path based on reference check; idempotent for already-archived.
  - `Future<Exercise> copyAsCustom(Exercise source)` — creates a
    distinct prefilled custom exercise.
  - `Future<Exercise> renameCustom(Exercise updated)` — guarded against
    built-in mutation.
  - All entry points throw `BuiltInExerciseImmutableError` for built-in
    mutation. The picker / library code MUST NOT depend on this guard
    alone — every call site also branches on `isCustomExercise` first.
- New **`ExerciseLibraryState`** (`lib/state/exercise/exercise_library_state.dart`)
  — `ChangeNotifier` that:
  - caches the full library list (custom + bundled, deduped by id)
  - holds the active search/discipline/custom-only filter
  - exposes `deleteExercise`, `copyAsCustom`, `renameCustom`,
    `editCustom` (delegate to `WorkoutState.updateCustomExercise`).
- `WorkoutState` gains one new method:
  - `Future<bool> isExerciseReferenced(String exerciseId)` — scans
    sessions + routine templates. Single source of truth for the
    referenced check.
- **No changes** to `WorkoutRepository` interface — the existing
  `createExercise` / `updateExercise` / `deleteExercise` /
  `getExercises` / `getExerciseById` / `getSegmentEfforts` /
  `getTemplateEfforts` cover everything the service needs.

### Frontend Changes
- New screen: `lib/features/exercise/exercise_library_screen.dart`
  (`ExerciseLibraryScreen`) — full-screen picker with:
  - Search field (reuses the picker's debounced pattern).
  - Custom-only toggle (`SwitchListTile`, key
    `exercise_library_custom_only_toggle`).
  - List rows share the visual language of the picker (`ListTile`
    with title + chips + custom marker).
  - Per-row tap → `ExerciseDetailViewScreen(showAddAction: false)`.
  - Per-row details still uses the info button
    (same `exercise_row_details_button` key).
- New screen: `lib/features/exercise/exercise_library_detail_screen.dart`
  (`ExerciseLibraryDetailScreen`) — read-only details + shaped
  management actions:
  - Built-in: a single `OutlinedButton.icon` "Make a copy"
    (key `exercise_library_copy_button`).
  - Custom: an `OutlinedButton.icon` "Edit"
    (key `exercise_library_edit_button`) + a destructive
    `OutlinedButton.icon` "Remove"
    (key `exercise_library_remove_button`, `colorScheme.error` border
    + text).
  - All three actions use `RoundedRectangleBorder(
    BorderRadius.circular(OmniTheme.buttonUtilityRadius))` — utility
    radius. Colors from `theme.colorScheme`.
- `HomeScreen._buildMaintenanceGrid` gains a fifth item —
  `Exercise Library` — pushed via `OmniNavigator.push` with a
  constructor-injected `ExerciseLibraryState`. Order is Calendar /
  Stats / Library / Profile / Settings per the design intent (Library
  sits next to Stats because both are reference surfaces).
- The picker continues to use its immediate-add row contract; the
  library never exposes an Add-to-Workout action (Plan acceptance
  criterion).

### Implementation Steps
1. **TDD (red)**: write tests for `ExerciseLibraryService` and
   `ExerciseLibraryState` covering S-001..S-005.
2. Implement `WorkoutState.isExerciseReferenced` + new service +
   state (green).
3. TDD the new screens (red → green).
4. Wire the maintenance-sheet destination.
5. Run full suite + invariant fixtures.
6. Doc hygiene: `navigation_and_screens.md` (new inventory rows,
   maintenance-sheet branch, custom-only contract note),
   `state_management.md` index entry, `widget_catalog.md` if a
   reusable widget emerges.

## Unit Tests Required
- Exact custom-only filter.
- Referenced removal preserves display/values/stats/PRs.
- Unreferenced removal deletes fully.
- Removed excluded from selectors but historically resolvable.
- Copy leaves original unchanged; rename propagates.
- Built-in mutation blocked at UI/state/repository.
- Ownership/availability model round trips and new screen/flow tests.

## Progress
- [x] TDD red run recorded
- [x] Phase 1 — Ownership/removal contract implemented
- [x] Library state/service implemented
- [x] Library UI implemented
- [x] Documentation refreshed
- [x] Full suite green (2088 / 2088, 5 pre-existing skipped)
- [x] Phase 3 — Code Review (✅ APPROVED with suggestions)
- [ ] Release-ready

## Feedback


### Phase 0 Complete ✓
### Phase 1 Complete ✓
### Phase 2 Complete ✓
### Phase 3 Complete ✓
