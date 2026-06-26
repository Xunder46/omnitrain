# Exercise Set Last Value Plan

## Overview

Logging resistance work currently requires re-typing the same reps and weight for every set, even when the user does the same load across all sets of an exercise. The same friction applies to round duration in martial-arts/sports sessions and to extra-weight in drill (isometric) holds. The infrastructure for "carry forward the previous set's values into the new set" already exists for the cardio/timed extra-weight case (`workout_session_screen.dart:_addSet` → `WorkoutState.addEntry(..., previousValues: ...)` → `SessionCore.addEntry`'s `previousValues` map), but only that one metric family uses it today. This plan extends the carry-forward to every other user-tunable value, so a "3×10 @ 60 kg" exercise becomes a single input per set instead of three.

The carry-forward is **per-effort, per-session, in-memory only**. When the user adds a new set within the same session, the new set's pre-fill is the LAST set's values; when the user adds a fresh exercise, the first set falls back to the existing app-wide defaults (`reps=10`, `weight=0.0`, `extra-weight=0.0`) — there is no cross-session memory at the storage layer (deliberately scoped out: this is a friction reduction, not a per-exercise preference system).

Depends on the same `previousValues` machinery that already drives the timed-extra-weight carry-forward (June 2025 / S-003). No schema change, no new repository method, no new state owner.

## Requirements

- Extend `_addSet` in `workout_session_screen.dart` to populate `previousValues` for every metric that the current effort kind tracks:
  - **`set` effort**: `reps` (int), `weight` (double), and `extra-weight` (double, only when the exercise lacks `load` capability).
  - **`round` effort**: `round-duration` (int seconds).
  - **`drill` effort**: `extra-weight` (double).
  - **`timed` effort**: keep the existing `extra-weight` carry-forward unchanged.
- The values to carry forward are read from the `getExercisesWithEntries()` summary view's `entries.last` map, matching the existing `_addSet` lookups.
- The carry-forward is **read-only on the previous set** — the new set's `previousValues` must not mutate the prior `EffortObservation` rows. The state layer's `addEntry` already constructs fresh `EffortObservation` rows from the `previousValues` map (see `session_core_entry.dart`), so this is satisfied by passing a new map.
- The pre-fill is always editable; the user can override the carried-forward value before logging. No schema or UI change.
- When the user adds the first set of a fresh exercise (no prior entries), no `previousValues` is passed → the existing `addEntry` defaults (`reps=10`, `weight=0.0`, `extra-weight=0.0`) apply. This preserves the existing "fresh exercise" contract.
- Carry-forward is a same-session-only memory. When the session ends (or the user navigates away and back), the new exercise's first set again uses the app-wide defaults. No cross-session memory.

## Acceptance Criteria

- [ ] Adding a second set within the same exercise in the same session pre-fills reps from the previous set.
- [ ] Adding a second set within the same exercise in the same session pre-fills weight from the previous set.
- [ ] Editing the reps/weight on the new set before logging does not mutate the prior set's stored values.
- [ ] Adding a round within the same round-effort pre-fills `round-duration` from the previous round.
- [ ] Adding a drill (isometric) within the same drill-effort pre-fills `extra-weight` from the previous drill.
- [ ] Adding the FIRST set of a fresh exercise uses the existing app-wide defaults (`reps=10`, `weight=0.0`).
- [ ] The existing timed-effort extra-weight carry-forward (S-003, pre-feature) keeps working unchanged.

## Scenarios

### S-001: Second set of a resistance exercise pre-fills reps/weight from the first set
- Trigger: User is in a resistance_lifting session with Barbell Squat. They logged set 1 at `10 reps × 60 kg`. They tap "+ Add Set".
- Precondition: Set 1 is logged (EffortObservation rows exist with the values).
- Flow: Tap "+ Add Set" → new set's reps = 10, weight = 60.
- Expected outcome: New set's reps and weight fields pre-fill from the previous set; user can confirm-and-go or override.
- Edge case of: none.

### S-002: First set of a fresh exercise uses the app-wide default
- Trigger: User is in a resistance_lifting session. They add a brand-new exercise (e.g., Dumbbell Bench Press).
- Precondition: The exercise has no prior sets in this session (and no per-exercise default at the storage layer).
- Flow: Add exercise → first set's reps = 10, weight = 0.0.
- Expected outcome: First set uses the existing `addEntry` defaults; no carry-forward because there is nothing to carry.
- Edge case of: S-001.

### S-003: Editing the pre-filled reps/weight does not mutate the prior set
- Trigger: User has set 1 at `10 reps × 60 kg`. They add set 2 (pre-fill 10, 60). They change set 2's reps to 8 BEFORE logging.
- Precondition: Set 2 not yet logged.
- Flow: Edit reps to 8 → tap "Log Set" → check set 1's stored value.
- Expected outcome: Set 1's stored reps is still 10; the new set's stored reps is 8. The carry-forward is read-only on the prior set.
- Edge case of: S-001.

### S-004: Adding a second round pre-fills round-duration from the first round
- Trigger: User is in a sports session with Boxing (3-min rounds). They log round 1 (planned 180s). They tap "+ Add Round".
- Precondition: Round 1's `plannedDurationSecs` is 180.
- Flow: Tap "+ Add Round" → new round's planned duration = 180.
- Expected outcome: New round pre-fills with the previous round's planned duration.

### S-005: Adding a second drill pre-fills extra-weight from the first drill
- Trigger: User is in an isometric session with Wall Sit (load capability, so extra-weight applies). They log drill 1 at `extra-weight = 10 kg`. They tap "+ Add Hold".
- Precondition: Drill 1's `extra-weight` is 10.
- Flow: Tap "+ Add Hold" → new drill's extra-weight = 10.
- Expected outcome: New drill pre-fills with the previous drill's extra-weight.

### S-006: Existing timed-effort extra-weight carry-forward (S-003 regression guard)
- Trigger: User is in a cardio_endurance session. They log interval 1 at `extra-weight = 15 kg`. They tap "+ Add Interval".
- Precondition: The pre-feature `previousValues: {'extra-weight': lastWeight}` path is in place.
- Flow: Tap "+ Add Interval" → new interval's extra-weight = 15.
- Expected outcome: The existing S-003 behavior continues to work. No regression.

## Iteration 1

### DB Changes

None. The `previousValues` map on `WorkoutState.addEntry` and `SessionCore.addEntry` already round-trips every supported metric; the only change is which keys the **caller** populates. No SQL migration, no new model field, no new repository method.

### Backend Changes

1. **`workout_session_screen.dart` (`_addSet`)**:
   - Extend the `previousValues` builder to cover every effort kind:
     - `set` (current gap): pull `reps` and `weight` from `entries.last`. Also `extra-weight` when the exercise lacks `load` capability (parity with the existing `addEntry` factory, which creates the `extra-weight` observation in that case).
     - `round` (current gap): pull `round-duration` (int) from `entries.last['round-duration']`.
     - `drill` (current gap): pull `extra-weight` from `entries.last['extra-weight']`.
     - `timed` (already in place): keep the `extra-weight` carry-forward.
   - All reads from `entries.last` are nullable-safe — pass the key in the `previousValues` map only when the prior value is non-null, so the state layer's fallback defaults stay intact.

No changes to `WorkoutState`, `SessionCore.addEntry`, `EffortObservation`, or `Exercise`.

### Frontend Changes

None new. `LogFoodRow`-style edits are not in scope. The `_addSet` change is a one-method edit; the pre-fill is rendered by the existing `InlineMetricEditor` widgets, which already read the new observation row's `valueInt`/`valueReal` on the same frame the row is created.

### Implementation Steps

1. Add state tests for the carry-forward contract in `test/state_test.dart` (WorkoutState group): for each effort kind (`set`, `round`, `drill`, `timed`), assert that `addEntry(..., previousValues: ...)` propagates the expected keys into the resulting observations (storage-level contract). This is already partially covered by the existing S-003 test for timed; add parallels for the new keys.
2. Add a widget-level integration test for `_addSet`'s `previousValues` builder in `test/interaction_flow_test.dart` (or extend an existing workout-session test): drive the actual call path and assert the new set's `entries.last` mirrors the prior set.
3. Edit `lib/features/session/workout_session_screen.dart:_addSet` to build the full `previousValues` map for each effort kind. Cap the edit at the function body; do not touch unrelated methods.
4. Update `docs/state_management.md` to document the `WorkoutState.addEntry(previousValues: ...)` extended contract (every effort kind's carry-forward keys).
5. Update `docs/widget_catalog.md` / `docs/navigation_and_screens.md` if any inline-metric-editor pre-fill behavior is observed by tests (likely N/A — the widget already reads the freshly-created observation).

## Progress

- [x] Phase 0 — Plan authored
- [x] Phase 0.5 — Red tests written (state-level + widget-level)
- [x] Red run confirmed:
  - `test/state_test.dart`: new "exercise previousValues carry-forward" group passes (state layer already accepts the keys via `previousValues`).
  - `test/exercise_set_last_value_test.dart` S-001 fails: after tapping "+ Add Set", the new set's reps shows `10` (default) instead of `8` (carried forward).
  - `test/exercise_set_last_value_test.dart` S-003 fails: weight is `0.0` instead of `60.0`.
- [x] Phase 1 — Data layer
  - [x] N/A — no schema or repository change
  - [x] Doc hygiene: `state_management.md` carry-forward contract expanded
  - [x] Bonus: added `capabilities` to the `getExercisesWithEntries` summary view (so the screen can decide whether to carry forward `extra-weight` for no-load set exercises without an extra repository lookup).
- [x] Phase 2 — Logic & UI
  - [x] Extend `_addSet` `previousValues` builder for `set` / `round` / `drill` / `timed`
  - [x] Re-read from `workoutState.getExercisesWithEntries()` (source of truth) instead of the stale cached `_exercises` list — fixes a latent bug where `updateEntryValue` followed by `_addSet` carried forward the cached defaults instead of the user's typed values.
  - [x] Re-run integration test → green (S-001 + S-003 pass)
  - [x] Re-run state tests → green (216/216 pass)
  - [x] Run broader session-related test suites → 66/66 pass
- [x] Phase 3 — Code review
  - [x] Layer scoping: state (screen), features (screen test), docs in scope; models, repositories, core, widgets, mock skipped
  - [x] Acceptance criteria verified (5/5): S-001 / S-002 / S-003 / S-004 / S-005 / S-006 all green
  - [x] Scenario register cross-checked (S-001..S-006, all have ≥1 test)
  - [x] Doc hygiene table reviewed (state_management updated; widget_catalog/navigation_and_screens/data_models/db_integration N/A — no changes in scope)
  - [x] Global conventions verified (PASS / N/A — no `dart:io`, no `Platform.is*`, no hardcoded colors, no model or repository changes)
  - [x] Architecture compliance verified (state via repo interface only; features use state methods; no business logic in widgets)
  - [x] Buttons N/A (no buttons added)
  - [x] Dead code: none
  - [x] Test coverage: 7 new tests (5 state + 2 widget integration); all 216+66 tests pass
  - [x] Environment safety: confirmed
  - [x] DRY + clean code: `_buildPreviousValues` extracted as pure helper; reads from source-of-truth (state) instead of stale cached list

### Phase 0 Complete ✓
### Phase 1 Complete ✓
### Phase 2 Complete ✓
### Phase 3 Complete ✓
