# Feature: Session Details Exercise Execution Order Fix

## Overview
Active-session ordering is currently inferred from timestamps and legacy effort order indices, which is unstable for mixed standalone + block sessions and for cloned blocks. Ordering must be explicit and persisted so users always see the exact sequence they built, both in list view and exercise-detail traversal, including after reload.

## Requirements
- Top-level active-session order must be preserved by explicit recorded position, not inferred from timestamps.
- Top-level items include both blocks and standalone exercises, and must appear exactly in user add order.
- Each block must preserve its own explicit internal exercise order.
- Adding an exercise to an existing block appends to that block only and does not perturb any other top-level item.
- Cloning a block appends the cloned block at the end of top-level order and preserves internal exercise order exactly.
- Ordering must persist across reload/reopen and be deterministic even when createdAt collisions occur.
- No drag-and-drop reorder UI is introduced.
- Rolling-session behavior is out of scope for changes, but must be validated as non-regressed.

## Acceptance Criteria
- [x] Building sequence block A(1,2,3), standalone X, block B(4,5) renders and reloads as A -> X -> B.
- [x] Block A internal order remains 1 -> 2 -> 3 before and after cloning A.
- [x] Each cloned block of A preserves 1 -> 2 -> 3 exactly across repeated clones.
- [x] Cloned block appears as the final top-level item.
- [x] Adding an exercise into earlier block A appends to end of A and does not move X or B.
- [x] Reopen/reload preserves identical two-level order with zero drift.
- [x] Order is independent from system-clock timing and deterministic across repeated identical builds.
- [x] Rolling session list/group behavior remains unchanged.

## Scenarios
### S-101: Mixed top-level ordering persistence
- Trigger: Build active session as A(1,2,3), X, B(4,5).
- Expected outcome: Top-level order remains A -> X -> B before and after reload.

### S-102: Clone preserves intra-block order
- Trigger: Clone block A once.
- Expected outcome: Clone internal order exactly matches source (1,2,3).

### S-103: Repeated clone determinism
- Trigger: Clone the same source block multiple times in succession.
- Expected outcome: Every clone has identical internal order.

### S-104: Append into earlier block
- Trigger: Add new exercise into non-last block A after other items exist.
- Expected outcome: New exercise is last in A; no movement of other blocks/standalone items.

### S-105: Reload invariance
- Trigger: Complete flow add blocks -> clone -> add new exercises -> reload.
- Expected outcome: Two-level order is identical before vs after reload.

### S-106: Timestamp-collision independence
- Trigger: Create multiple items in one operation/tight time window.
- Expected outcome: Stable deterministic order not dependent on createdAt.

## Iteration 1
### Analysis
Current implementation uses order inference instead of persisted ordering:
- Non-rolling list and detail sequence rely on comparator paths based on createdAt/executionOrder in workout session screen state.
- Block rendering collects block members by filter without applying a persisted block-local order.
- Repository clone methods copy original effort.orderIndex values into cloned efforts, which can collide globally and do not define block-local append sequence.
- Mixed top-level ordering is synthesized from block.createdAtMs and effort.createdAtMs, which is not a durable explicit ordering contract.

### Questions (Resolved)
1. Scope: both standard and block/superset active-session flows are affected.
2. Ordering source of truth: explicit persisted add-order at top-level and block-local levels.
3. Deliverable: diagnosis plus implementation handoff plan.

### Phase 1: Data Layer (@dba)
1. [x] Define explicit persisted ordering fields for active-session top-level items (blocks + standalone efforts) and block-internal effort order.
2. [x] Add/update schema contract and model mapping so order is not inferred from timestamps.
3. [x] Update repository interface for creating block/effort records with explicit order assignment and retrieval guarantees.
4. [x] Implement deterministic order writes/reads in HiveWorkoutRepository.
5. [x] Implement deterministic order writes/reads in MockWorkoutRepository.
6. [x] Update cloneSessionBlock to preserve source intra-block sequence exactly and assign deterministic top-level append order for the clone.
7. [x] Validate no order mutation of unrelated items when appending to earlier blocks.

### Phase 2: Logic/UI (@developer)
1. [x] Refactor active-session list ordering to consume persisted top-level order only.
2. [x] Refactor block card member rendering to consume persisted block-local order only.
3. [x] Refactor detail traversal sequence to mirror visible list order derived from persisted ordering.
4. [x] Remove timestamp-based comparator dependence for active-session ordering decisions.
5. [x] Ensure add-to-block appends only inside target block and preserves all external positions.
6. [x] Validate rolling-session rendering path for non-regression.

### Phase 3: Tests (@developer)
1. [x] Add test: clone preserves exact intra-block member order.
2. [x] Add test: repeated clones keep stable identical member order.
3. [x] Add test: add-to-earlier-block appends locally without disturbing top-level order.
4. [x] Add test: mixed top-level block/standalone order persists after reload.
5. [x] Add test: deterministic ordering independent of createdAt collisions.
6. [x] Update existing clone/order tests that currently validate deep-copy without asserting order.
7. [x] Run targeted suites for session screen and repository order behavior.

### Files Affected (Expected)
- lib/data/repositories/workout_repository.dart
- lib/data/repositories/hive_workout_repository.dart
- lib/data/repositories/mock_workout_repository.dart
- lib/state/workout/session_core_entry.dart
- lib/state/workout/session_block_manager.dart
- lib/state/workout/session_summary_builder.dart
- lib/features/session/workout_session_screen.dart
- lib/features/session/workout_session_list_view.dart
- test/session_blocks_repository_test.dart
- test/screen_widget_test.dart

## Progress
- [x] Phase 1 data-contract and repository order persistence design
- [x] Phase 1 repository implementations updated (Hive + Mock)
- [x] Phase 2 active-session ordering path refactor complete
- [x] Phase 3 ordering regression test suite added and green
- [x] Rolling-session non-regression validation complete

## Phase Status
- Phase 1: Complete
- Phase 2: Complete
- Phase 3: Complete

### Phase 1 Complete ✓
Data layer implemented. Models, repository interface, and Hive implementation ready. Developer can proceed with Logic/UI Phase.

### Phase 2 Complete ✓
Logic/UI ordering now consumes persisted canonical order fields end-to-end. Remaining failing widget assertions are legacy-order-contract tests to be updated in Phase 3.

### Phase 3 Complete ✓
Ordering regression coverage added and focused session-order validations are green. Ready for Code Reviewer.

## Doc Hygiene
- docs/navigation_and_screens.md: no update required (no route/screen constructor changes in this iteration)
- docs/state_management.md: no update required (no new state owner/service contract)
- docs/widget_catalog.md: no update required (no reusable widget API changes)
- docs/data_models.md: updated (documented `SessionBlock.topLevelOrderIndex`, `SegmentEffort.topLevelOrderIndex`, and `SegmentEffort.blockOrderIndex` plus ordering contract)
- docs/db_integration.md: updated (documented deterministic ordering contract, Hive behavior, and SQLite v7 migration/versioning notes)

## Iteration 2
### Analysis
Two bugs found after Iteration 1 landed:

**Bug 1 — Active session "Add Block": new block can appear before standalone exercises.**
`session_block_manager.addSessionBlock()` stores the new block in memory with `topLevelOrderIndex = null`. The repository normalizes it correctly via `_nextTopLevelOrderForSession`, but that value is never written back to the in-memory entry. `_blockTopLevelOrder` falls back to `block.orderIndex` (computed from blocks only), which can be ≤ a standalone exercise's `topLevelOrderIndex`, causing the new block to sort before some standalone exercises. `cloneSessionBlock` already does the right thing by reloading from the repository — `addSessionBlock` must do the same.

**Bug 2 — Routine "Clone Block": clone inserts immediately after the source, not at the end.**
`routine_state.cloneSegment()` calls `newSegments.insert(sourceIndex + 1, clonedSegment)`. Should append to end regardless of source position.

### Phase 1: State fix — Active session (@developer)
1. [x] In `lib/state/workout/session_block_manager.dart` `addSessionBlock()`: replace `_sessionBlocks.putIfAbsent(currentSessionId, () => []).add(block)` with `_sessionBlocks[currentSessionId] = await _repository.getSessionBlocks(currentSessionId)` (same reload pattern as `cloneSessionBlock`).

### Phase 2: State fix — Routine (@developer)
2. [x] In `lib/state/routine/routine_state.dart` `cloneSegment()`: change `newSegments.insert(sourceIndex + 1, clonedSegment)` to `newSegments.add(clonedSegment)`. Re-indexing loop below is unchanged.

### Phase 3: Tests (@developer)
3. [x] `test/state_test.dart`: Update `'cloneSegment inserts clone immediately after source'` to assert clone goes to end — expected order after cloning first block when Block B exists: `[Main Block, Block B, Main Block (2)]`.
4. [x] `test/state_test.dart`: Add `'addSessionBlock places new block after all standalone exercises'` — add standalone exercise, call `addSessionBlock`, verify new block's effective `topLevelOrderIndex` is greater than the standalone exercise's.

### Acceptance Criteria
- [x] "Add Block" in a session with standalone exercises always appends after all existing items.
- [x] Cloning a block in any position in a session appends the clone to the end.
- [x] Cloning a block in any position in a routine appends the clone to the end.
- [x] Updated and new tests in `test/state_test.dart` are green.
- [x] All existing ordering regression tests remain green.

### Files Affected (Iteration 2)
- lib/state/workout/session_block_manager.dart
- lib/state/routine/routine_state.dart
- test/state_test.dart

## Progress (Iteration 2)
- [x] Bug 1 fix: `session_block_manager.addSessionBlock` reload after create
- [x] Bug 2 fix: `routine_state.cloneSegment` append to end
- [x] Tests: updated `cloneSegment` test + new `addSessionBlock` ordering test

### Iteration 2 Complete ✓
Implementation done. Add-block and clone-to-end ordering are now deterministic across session and routine flows, with targeted regression suites green.

## Feedback

## Iteration 3
### Analysis
Returning from exercise details to the session list used `_scrollListToBottom()` with `animateTo(..., duration: 300ms)`, which created a visible scroll animation when restoring focus near the end of the list.

### Phase 2: Logic/UI (@developer)
1. [x] In `lib/features/session/workout_session_screen.dart` `_scrollListToBottom()`, replace animated bottom scroll with immediate jump (`jumpTo`) so back navigation restores the final position without visible motion.

### Acceptance Criteria
- [x] Back navigation from exercise details restores the session list at the end immediately.
- [x] No visible scroll animation is shown during that restore.

### Files Affected (Iteration 3)
- lib/features/session/workout_session_screen.dart

## Progress (Iteration 3)
- [x] Logic/UI fix: instant bottom restore on return from detail view

### Iteration 3 Complete ✓
Implementation done. Back navigation now restores bottom position without visible scroll animation.

## Iteration 4
### Analysis
Even with instant `jumpTo(maxScrollExtent)`, returning from detail could still show a subtle final notch as layout settled. UX target is to land near the bottom with controls in the lower half, not pinned to the absolute end.

### Phase 2: Logic/UI (@developer)
1. [x] In `lib/features/session/workout_session_screen.dart`, calibrate `_scrollListToBottom()` to jump to a near-bottom anchor (`maxScrollExtent - viewport * 0.05`) instead of absolute max.
2. [x] Add one follow-up post-frame settle jump using the same anchor formula so late extent changes do not produce visible secondary motion.

### Acceptance Criteria
- [x] Returning from detail lands with bottom actions in the lower half of the viewport.
- [x] No visible notch/secondary scroll appears during restore.

### Files Affected (Iteration 4)
- lib/features/session/workout_session_screen.dart

## Progress (Iteration 4)
- [x] Logic/UI tune: near-bottom anchored restore with post-layout settle

### Iteration 4 Complete ✓
Implementation done. Detail-to-list return now restores to a stable near-bottom anchor without visible notch scrolling.
