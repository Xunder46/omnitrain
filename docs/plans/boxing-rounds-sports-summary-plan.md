# Feature: Boxing Rounds Sports Summary Visibility Fix

## Overview
Investigate and fix a bug where boxing/sports exercises can appear in-session with `0 rounds` and then fail to produce a Sports card on Session Summary because no completed rounds are counted. Preserve product rule: Sports card appears only when at least one round is actually logged.

## Requirements
- Keep current product rule: Sports summary card renders only when at least one round is logged.
- Ensure boxing/sports round interactions persist correctly as completed round data.
- Ensure Session Summary reflects logged rounds from persisted `RoundInstance` records.
- Fix applies correctly to new sessions going forward.
- Avoid broad behavioral changes to summary card visibility for empty/incomplete sports efforts.

## Acceptance Criteria
- [ ] In a new Sports/boxing session, if user starts and completes/logs at least one round, Session Summary shows the Sports card.
- [ ] In a new Sports/boxing session with zero completed rounds, Session Summary does not show the Sports card.
- [ ] A round that reaches `RoundState.finished` contributes to session round totals and summary group metrics.
- [ ] Round completion via both natural countdown completion and early end+log path is counted consistently.
- [ ] No regression for non-sports groups (strength/cardio/isometric) summary visibility.
- [ ] Existing summary rule remains unchanged: no Sports card when no logged rounds.

## Scenarios
- New boxing session, add Heavy Bag Rounds, complete one round -> Sports card appears with at least 1 round.
- New boxing session, add Speed Bag/Heavy Bag Rounds but never start round timers and finish session -> Sports card absent.
- New boxing session, start then end round early and log -> Sports card appears if round is persisted as finished.
- Mixed session with both strength and sports, only strength logged -> strength card only.
- Mixed session with strength logged and one completed sports round -> both strength and sports cards appear.

## Iteration 1
### DB Changes
1. [ ] No schema changes required.
2. [ ] No repository interface changes expected.

### Backend Changes
1. [ ] Audit round lifecycle persistence in workout state and screen flow to verify where a round transitions to `finished`.
2. [ ] Confirm summary totals derive from completed `RoundInstance` records only and identify mismatch points.
3. [ ] Patch round logging flow so first logged boxing round reliably reaches persisted `finished` state before session end.
4. [ ] Ensure `computeSessionSummary()` and summary service consume the same round completion source of truth.

### Frontend Changes
1. [ ] Verify UI flow in workout session screen does not allow advancing/finishing without persisting legitimate completed rounds when user performed one.
2. [ ] Keep existing Sports-card gating unchanged (only render when `totalRounds > 0` or equivalent logged-round metric > 0, aligned with current product rule).

### Implementation Steps
1. [ ] Reproduce using a deterministic test or scripted state setup for boxing rounds showing `0 rounds` in list and missing Sports card.
2. [ ] Trace `RoundState.notStarted -> active -> paused/finished` transitions for first round in a new sports effort.
3. [ ] Validate `_logSet` and `_toggleEffortTimer` ordering for round efforts and eliminate race/order issues that can leave round uncounted.
4. [ ] Add targeted unit/widget tests for round completion counting and Sports-card visibility contract.
5. [ ] Run targeted summary + workout session tests and confirm green.

## Progress
- [x] Confirmed reproduction path for missing Sports card with boxing rounds.
- [x] Isolated root cause in round completion persistence or summary aggregation wiring.
- [x] Implemented fix in round flow and/or summary aggregation.
- [x] Added regression tests for Sports card visibility rule.
- [x] Verified no regressions in other modality summary cards.

### Phase 2 Complete ✓
Implementation done. All Phase 0 tests green. Ready for Code Reviewer.

## Feedback
<!-- Leave empty until a specialist or reviewer adds notes -->
