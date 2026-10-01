# Session Summary Completed Rounds Only - Copilot Prompt Pack

## Context
- Problem statement: On the Session Summary screen, the first stats card currently counts all round instances for round-based efforts, including not-started rounds. The user expectation is to show only completed rounds.
- Scope boundaries: Fix only round counting semantics used by Session Summary totals and round exercise summaries. Do not change round lifecycle state machine, timer behavior, or non-round metrics.
- Constraints:
  - Preserve existing Session Summary UI layout and labels.
  - Keep current data model fields unless a rename is strictly needed.
  - Avoid regressions for set, timed, and drill summary metrics.
- Assumptions:
  - The first card value for rounds is sourced from SessionSummary.totalRounds in lib/state/workout/workout_state.dart.
  - Completed means RoundState.finished.
  - Current bug is caused by rounds.length usage in computeSessionSummary.

## Phase 1 - Confirm Counting Contract
### Intent
Establish a single, explicit counting rule for round completion so implementation and tests use the same definition.

### Copilot Prompt
Inspect round counting in lib/state/workout/workout_state.dart, especially computeSessionSummary(). Confirm where totalRounds and ExerciseSummary.totalRounds are calculated. Document the exact rule to apply: count only round instances whose state is RoundState.finished. Ensure the rule is consistently applied to both per-exercise and overall totals used by Session Summary.

### Acceptance Criteria
- [ ] A single completion rule is identified and documented in code comments or nearby logic notes.
- [ ] The rule explicitly excludes RoundState.notStarted, RoundState.active, and RoundState.paused from completed-round totals.
- [ ] No UI file changes are required in this phase.

## Phase 2 - Implement Completed-Only Round Aggregation
### Intent
Change summary aggregation logic so Session Summary top-card rounds and exercise round totals reflect completed rounds only.

### Copilot Prompt
Update computeSessionSummary() in lib/state/workout/workout_state.dart:
- In the round effort branch, replace raw rounds.length counting with a completed-round counter that includes only RoundState.finished.
- Set both ExerciseSummary.totalRounds and SessionSummary.totalRounds from this completed count.
- Keep existing behavior for set, timed, and drill effort branches unchanged.
- Keep public API shape unchanged unless absolutely necessary.

### Acceptance Criteria
- [ ] For round efforts, summary counts only finished rounds.
- [ ] Round efforts with only not-started rounds report 0 completed rounds.
- [ ] Mixed-state round efforts count finished rounds only.
- [ ] Non-round metrics (totalSets, durations, volume) remain unchanged.

## Phase 3 - Add Regression Tests
### Intent
Prevent future regressions by asserting completed-only round counting at state and UI levels.

### Copilot Prompt
Add or extend tests in test/ to validate round summary semantics:
- Prefer a focused state-level test around WorkoutState.computeSessionSummary() that creates round instances in mixed states and asserts totals.
- Add or extend a widget test for Session Summary first stats card to verify displayed rounds value reflects completed-only count.
- Reuse existing test setup patterns from test/session_finish_timers_test.dart and related session tests.

### Acceptance Criteria
- [ ] At least one test fails before the fix and passes after.
- [ ] State-level assertions verify SessionSummary.totalRounds and per-exercise ExerciseSummary.totalRounds.
- [ ] UI-level assertion verifies first-card rounds text matches completed rounds only.
- [ ] Existing unrelated tests continue passing.

## Phase 4 - Validate and Harden
### Intent
Run targeted verification and ensure no hidden assumptions remain in round summary behavior.

### Copilot Prompt
Run targeted tests for updated files and any impacted summary/session tests. Verify edge cases:
- Session with no round efforts.
- Session with round efforts where all rounds are not started.
- Session with mixed completed and incomplete rounds.
Then perform a quick code review for naming clarity (e.g., comments making completed semantics explicit).

### Acceptance Criteria
- [ ] Targeted test commands complete successfully.
- [ ] Edge-case behavior matches completed-only semantics.
- [ ] Implementation leaves clear intent for future maintainers.

## Validation Checklist
- [ ] All phases are independently executable
- [ ] Prompts reference concrete files/symbols where known
- [ ] Acceptance criteria are observable and testable
- [ ] No phase depends on hidden assumptions
