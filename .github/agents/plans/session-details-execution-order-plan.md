# Feature: Session Details Exercise Execution Order Fix

## Overview
WorkoutSessionScreen currently renders non-rolling session exercises in an order that can diverge from performed order. Non-rolling session details must render exercises chronologically by execution order, with createdAtMs as deterministic tie-breaker.

## Requirements
- Non-rolling WorkoutSessionScreen renders exercises in ascending execution order.
- If execution order is equal, createdAtMs ascending breaks ties.
- No modality group headers are rendered on non-rolling WorkoutSessionScreen.
- Rolling session rendering remains unchanged.
- SessionSummaryScreen rendering remains unchanged.

## Scenarios
### S-001: Non-rolling mixed exercise ordering
- Trigger: Open non-rolling WorkoutSessionScreen with mixed effort kinds.
- Precondition: Session has at least three exercises with differing execution order metadata.
- Flow: Load screen list view and inspect visual exercise tile order.
- Expected outcome: Tiles are rendered in ascending execution order regardless of effort kind/modality.
- Edge case of: none

### S-002: Tie-break when execution order duplicates
- Trigger: Open non-rolling WorkoutSessionScreen where two exercises share the same execution order.
- Precondition: Session has duplicate execution-order values and distinct createdAtMs values.
- Flow: Load list and compare relative order of duplicate-execution items.
- Expected outcome: Duplicate-execution items are ordered by createdAtMs ascending.
- Edge case of: S-001

### S-003: Non-rolling list has no modality headers
- Trigger: Open non-rolling WorkoutSessionScreen with mixed effort kinds.
- Precondition: Session contains set, timed, and round efforts.
- Flow: Inspect list view labels.
- Expected outcome: Strength/Cardio/Sports/Intervals group headers do not appear.
- Edge case of: S-001

### S-004: Rolling list unchanged
- Trigger: Open rolling WorkoutSessionScreen.
- Precondition: Existing rolling behavior and tests.
- Flow: Render block list UI.
- Expected outcome: Existing rolling block rendering remains unchanged.
- Edge case of: none

### S-005: Session summary unchanged
- Trigger: Open SessionSummaryScreen for non-rolling/rolling sessions.
- Precondition: Existing summary behavior and tests.
- Flow: Render summary list/group cards.
- Expected outcome: Existing summary grouping remains unchanged.
- Edge case of: none

## Red Test Run (Phase 0)
- Added test: `non-rolling session displays exercises by execution order with createdAt tie-break`
- Added test: `non-rolling session does not render modality group headers`
- Run: `test/screen_widget_test.dart` (targeted)
- Result: 1 passed, 1 failed
- Failing expectation confirms current ordering bug in non-rolling WorkoutSessionScreen.

## Progress
- [x] Phase 0.1 Codebase analysis complete
- [x] Phase 0.3 Scenario register written
- [x] Phase 0.4 Tests added and red run recorded
- [x] Implement non-rolling ordering fix in WorkoutSessionScreen path
- [x] Verify targeted tests green
- [x] Run broader regression tests for unchanged rolling/summary paths
- [x] Update doc hygiene files (or record no-update required)

## Doc Hygiene
- .github/agents/docs/navigation_and_screens.md: no update required (no new screen/route/dependency changes)
- .github/agents/docs/state_management.md: no update required (no new state class/method contracts)
- .github/agents/docs/widget_catalog.md: no update required (no reusable widget API changes)

## Follow-up Fix
- Reported issue: cloned superset blocks still progressed as grouped all-first-exercise then all-second-exercise in detail mode.
- Cause: non-rolling detail progression used `_exercises` ordering that could still group by local order index collisions after cloning.
- Resolution: non-rolling `_exercises` are now sorted by `createdAtMs` (chronological insertion), with deterministic tie-breakers (`executionOrder`, then `id`).
- Validation: targeted widget tests updated for clone-like order-index collisions and now pass.

## Phase Status
- Phase 0: Complete
- Phase 2: Complete

### Phase 2 Complete ✓
Implementation done. All Phase 0 tests green. Ready for Code Reviewer.

## Feedback
- Non-rolling ordering implementation currently sorts by `createdAtMs` first and only then `executionOrder`, but the stated requirement/Scenario S-001 expects ascending `executionOrder` with `createdAtMs` only as tie-breaker.
- Update sort comparator in `WorkoutSessionScreen` non-rolling paths to apply `executionOrder` primary ordering and `createdAtMs` tie-break, then re-validate affected widget tests.
- Re-run and record targeted test evidence for S-001 and S-002 after comparator correction.

- Resolved: non-rolling comparators now sort by `executionOrder` first, then `createdAtMs`, then id; targeted widget tests re-run and passing.

- User-direction update (April 14, 2026): non-rolling ordering was reverted to chronology-first (`createdAtMs`, then `executionOrder`, then id) to preserve performed insertion flow in session detail/list paths.
- User-direction update (April 14, 2026, latest): non-rolling detail traversal must follow the exact visible list order; with blocks present, traversal is anchored by block placement in list view and exercises stay grouped under their block.
