# Feature: Open Tracking on First Unlogged Set

## Overview
When entering the focused, single-exercise tracking view in a live workout, the screen should open on the first set/entry that is not yet logged (the next actionable set). Current behavior is inconsistent by entry path: list-tap opens at set 1, while initial-focus paths (for example from overview/detail wrappers) restore to the last set.

## Analysis
This is a launch-critical UX fix on the highest-frequency action path (logging entries). Scope is intentionally narrow: only the initial set position when opening exercise detail. Logging, manual navigation, and exercise list behavior remain unchanged.

Primary control points identified:
- `lib/features/session/workout_session_screen.dart`
  - `_loadExercises()` currently sets `initialDetailSet = entries.length` for `initialFocusId` path.
  - `_focusExerciseDetail(..., {int setNumber = 1})` is called from list-tap and add/switch paths with default set 1.
  - `_isSetLogged(effortId, entryIndex, effortKind)` already defines logged state per modality and should be reused.
- Entry paths to align:
  - Tap exercise in list view (`_focusExerciseDetail(idx)`)
  - Open with `initialFocusId` from overview/wrapper flows (`SessionOverviewScreen`, `ExerciseDetailScreen`)

## Questions
None.

## Requirements
- Land on first unlogged set when entering focused tracking view.
- If all sets are logged, land on last set.
- If none are logged, land on first set.
- Behavior must be identical regardless of entry path into tracking detail view.
- Use each effort kind's existing logged definition (no new logged semantics):
  - `set` via rest-next-entry logic
  - `timed`/`drill` via `TimedState.finished`
  - `round` via `RoundState.finished`
- Do not change logging flow, manual prev/next navigation, or list view behavior.

## Acceptance Criteria
- [x] Opening an exercise with sets 1-2 of 4 logged lands on set 3.
- [x] Opening an exercise with no logged sets lands on set 1.
- [x] Opening an exercise with all sets logged lands on set 4 (last set).
- [x] The landing result is identical for list-tap entry and `initialFocusId` entry.
- [x] Rule holds for `set`, `timed`, `round`, and `drill` efforts using existing logged definitions.

## Scenarios
- Resistance (`set`): 2/4 logged -> opens `Set 3 of 4`.
- Timed (`timed`): finished states `[finished, notStarted, notStarted]` -> opens `Interval 2 of 3`.
- Round (`round`): finished states `[finished, finished, notStarted]` -> opens `Round/Period 3 of 3`.
- Drill (`drill`): all finished -> opens `Hold N of N` (last).
- Single-set effort:
  - not logged -> opens set 1
  - logged -> still opens set 1 (last == first)

## Iteration 1
### DB Changes
None.

### Backend Changes
None. No model/schema/repository/state API changes.

### Frontend Changes
- `lib/features/session/workout_session_screen.dart`
- Tests in session screen coverage files (likely `test/session_toolbar_rework_test.dart` and/or `test/widget_test.dart`; add targeted file if cleaner).

### Implementation Steps
1. [ ] Add a local helper in `WorkoutSessionScreen` that computes initial set number for a given exercise index (or effort id) using existing `_isSetLogged(...)` and current `entries`.
2. [ ] Helper algorithm:
   - If entries empty: return 1
   - Find first index where `_isSetLogged(...) == false`
   - If found: return `index + 1`
   - Else (all logged): return `entries.length`
3. [ ] Update `initialFocusId` path in `_loadExercises()` to use the helper instead of `entries.length`.
4. [ ] Update list-tap entry path (`_focusExerciseDetail(idx)` call site) to pass computed set number from same helper, so behavior matches initial-focus path.
5. [ ] Keep `_focusExerciseDetail` API stable; only change the setNumber passed by callers and ensure bounds safety (`1..entries.length`, with fallback 1).
6. [ ] Confirm no behavior changes to post-open manual navigation (`_jumpToSet`, `_switchExercise`, prev/next, log advancement).
7. [ ] Add unit/widget tests for set-selection logic outcomes:
   - some logged -> first unlogged
   - none logged -> first
   - all logged -> last
   - single-set (logged and unlogged)
8. [ ] Add modality-specific coverage (one test each for `set`, `timed`, `round`, `drill`) validating first-unlogged landing with each modality's existing logged definition.
9. [ ] Add/adjust entry-path parity tests to assert equal landing for:
   - list-tap entry
   - `initialFocusId` entry
10. [ ] Update/remove any tests that assert old behavior (always set 1 or always last via focus path).
11. [ ] Run focused tests for touched files plus any updated session-screen suite.

## Progress
- [x] Add first-unlogged initial-set helper in workout session screen
- [x] Wire helper into list-tap entry path
- [x] Wire helper into `initialFocusId` entry path
- [x] Keep navigation/logging behavior unchanged after initial open
- [x] Add core set-selection tests (some/none/all/single)
- [x] Add modality-specific first-unlogged tests (`set`, `timed`, `round`, `drill`)
- [x] Add entry-path parity tests (list tap vs initial focus)
- [x] Update obsolete tests encoding old opening behavior
- [x] Run focused test validation

## Phase 0 Validation
- Red run before implementation: `flutter test test/session_toolbar_rework_test.dart` -> 19 passed, 6 failed (new first-unlogged expectations)
- Green run after implementation: `flutter test test/session_toolbar_rework_test.dart` -> 25 passed, 0 failed

### Phase 2 Complete ✓
Implementation done. All Phase 0 scenario tests green. Ready for Code Reviewer.

## Feedback
None.

## Doc Updates
- `.github/agents/docs/navigation_and_screens.md`: updated DI rule note to remove obsolete `AppState` singleton reference.
- `.github/agents/docs/state_management.md`: removed obsolete `AppState` section and dependency graph reference.
- `.github/agents/docs/widget_catalog.md`: no update required (no reusable widget API changes).
- `.github/agents/docs/data_models.md`: no update required (no model/schema changes).
- `.github/agents/docs/db_integration.md`: no update required (no DB/repository changes).

## Global Conventions Check
- Units + canonical storage: N/A (no unit conversion or persistence logic changed).
- Theme tokens only: N/A (no styling or theme token changes).
- Effort-kind drives analytics: PASS (landing logic reuses existing effort-kind-specific logged checks via `_isSetLogged`).
- Timestamps are source data: PASS (timed/round logged state still derives from persisted instance states).
- Reuse the canonical owner: PASS (shared `_isSetLogged` and existing screen/state ownership reused; no duplicated logging semantics).
- Instrument panel, not influencer: PASS (change removes navigation friction on primary logging flow without adding non-instrument behavior).
