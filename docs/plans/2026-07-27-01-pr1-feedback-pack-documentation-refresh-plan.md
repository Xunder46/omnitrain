# PR 1: Feedback Pack Documentation Refresh

> **Priority 1 of 8 — documentation prerequisite.** Ship before every other 2026-07-27 feedback-pack plan and before the pending 2026-07-13 plan set.

## Overview

Recheck the agent-facing documentation against `lib/` before implementing this feedback pack. Record the current startup, gesture, routine, session-entry, rest, nutrition, exercise-ownership, and maintenance-sheet behavior without implementing Items 2–12.

## Requirements

- Source wins over older docs and plans.
- Correct affected current-state documentation and clearly separate current behavior from desired behavior in later plans.
- Preserve the 64 KiB indexing ceiling and all inbound links.
- Explicitly document unresolved custom-exercise identity and the wired maintenance-sheet implementation.
- Modify no application source.

## Acceptance Criteria

- [x] Affected docs match current `lib/` behavior.
- [x] Startup docs distinguish preparing, succeeded, and genuinely failed states.
- [x] Session and routine docs record the gestures PR 2 removes.
- [x] Routine/card/session-entry behavior is accurately documented before PRs 5–6.
- [x] Exercise ownership is verified or explicitly unresolved.
- [x] The feedback-pack shipping order is discoverable.
- [x] Doc indexing/link tests pass and `git diff -- lib` is empty.

## Scenarios

### S-001: Downstream agent finds current and desired contracts
- Trigger: An agent begins PR 2–8.
- Precondition: PR 1 landed.
- Flow: Read global conventions, feature doc, and ordered plan.
- Expected outcome: Stale documentation does not preserve behavior being removed.
- Edge case of: none

## Iteration 1

### DB Changes
None.

### Backend Changes
None.

### Frontend Changes
None.

### Implementation Steps
1. Recheck source areas named above.
2. Update only applicable current-state docs and index entries.
3. Run documentation integrity checks and verify `lib/` is untouched.

## Unit Tests Required
- Run `test/docs_indexing_contract_test.dart` and existing source/doc consistency checks.

## Progress
- [x] Source claims re-audited
- [x] Affected docs refreshed
- [x] Documentation checks green
- [x] Phase 1 — Data Layer (N/A)
- [x] Phase 2 — Logic & UI (N/A)
- [x] Phase 3 — Code Review
- [x] Release-ready

## Feedback


### Phase 0 Complete ✓
