# Feature: finish-session-stops-timers

## Overview
Fix session completion semantics so finishing a workout always terminates all active timers and timer-driven state. The current behavior can leave timed entries or rounds effectively still active when the user navigates back, which conflicts with the expectation that Finish Session is terminal for that session.

## Requirements
- Finish Session must stop every active timer path, not only round timers.
- Finish Session must persist active timer-based efforts into terminal states before leaving the session screen.
- Back-navigation from the summary must not allow a finished session to continue counting time.
- The behavior must remain repository-agnostic and work with current web/hive and future sqlite implementations via existing WorkoutRepository APIs.
- No regression to edit mode behavior in WorkoutSessionScreen.

## Iteration 1

### DB Changes (@dba)
1. [ ] No schema changes required.
2. [ ] No repository interface additions required.

### Backend Changes (@developer)
1. [ ] Add a unified session-finalization helper in WorkoutSessionScreen that:
   - Cancels all local UI timers (`_effortTimers`, `_restTimer`, session `_ticker`).
   - Iterates all effort kinds and forces active/paused entries to terminal state via WorkoutState methods.
2. [ ] Extend current pre-finish persistence logic (currently round-focused) to include timed/drill instances:
   - Round: call `endRoundEarly` for `active`/`paused` rounds not already finished.
   - Timed/Drill: call `finishTimedEntry` for `active`/`paused` timed instances not already finished.
3. [ ] Ensure finish flow calls `workoutState.endSession()` at the proper point so session `endedAtMs` is set before navigation settles.
4. [ ] Add a defensive guard in the screen timer tick/update path to no-op when session has `endedAtMs != null`.

### Frontend Changes (@developer)
1. [ ] Update `WorkoutSessionScreen` finish action to use a single deterministic sequence:
   - Freeze UI timers.
   - Persist all active timer-based effort states.
   - End session.
   - Navigate to summary.
2. [ ] Update back-navigation behavior from summary/session flow so returning cannot resume active timer display for a finished session.
3. [ ] Ensure the Finish Session CTA semantics are explicit and consistent with current copy: finishing closes tracking, not pausing.

### Implementation Steps
1. [ ] Audit current `_finishSession()` and `_persistActiveRoundTimers()` in `WorkoutSessionScreen`.
2. [ ] Replace/expand round-only shutdown helper with all-effort shutdown helper (round + timed/drill + rest/session local timers).
3. [ ] Wire all finish entry points (dialog finish buttons and any direct finish paths) to the same shutdown helper.
4. [ ] Call `workoutState.endSession()` exactly once in finish sequence and handle failure path with user-visible error feedback.
5. [ ] Add guard conditions in `_tick()` and `_onEffortTick()` to prevent updates for ended sessions.
6. [ ] Verify edit mode (`editMode == true`) remains unaffected.
7. [ ] Add/adjust widget tests for:
   - Active timed entry + Finish Session -> summary opens, timed entry finished.
   - Active round + Finish Session -> summary opens, round finished/end-early persisted.
   - Press back after finish -> no running timers, no continued elapsed growth.
8. [ ] Run regression smoke tests for skip/log/previous-set flows to ensure no timer lifecycle regressions.

### Acceptance Criteria
- [ ] When user taps Finish Session, all active round/timed/drill timers are stopped and persisted to terminal state.
- [ ] Session receives `endedAtMs` immediately as part of finish flow.
- [ ] Returning/back navigation after finish never shows timer progression for the finished session.
- [ ] Behavior is identical on web (HiveWorkoutRepository) and compatible with future sqlite implementation through existing abstract methods.
- [ ] Edit mode retains existing unsaved-changes behavior and does not run active timers.

### Files Affected
- lib/features/session/workout_session_screen.dart
- lib/state/workout/workout_state.dart
- test/widget_test.dart
- test/session_finish_timers_test.dart

### Notes
- Follow modality timer lifecycle rules documented in modality_based_exercise_ui and modality_tracking.
- Use WorkoutState safety-net methods (`_persistActiveRounds`, `_persistActiveTimedEntries`) as backend consistency guards, but keep UI finish flow deterministic so users see immediate stop behavior.

## Progress
- [x] Confirm root cause and map all finish entry points
- [x] Implement unified timer/session finalization flow
- [x] Add ended-session tick guards
- [x] Add regression tests for finish/back behavior
- [x] Validate web flow manually and via tests
- [x] Add round state machine transition matrix tests (state_test.dart — 16 cases pass)
- [x] Add timed state machine transition matrix tests (state_test.dart — 16 cases pass)
- [x] Add explicit scenario tests: terminal guarantee + single/multi-cycle resume for both state machines
- [x] _CountingRepo instrumentation: write counters + listener notification delta assertions

## Feedback
### Code Reviewer - April 26, 2026

Implementation does not currently meet transition-safety coverage expectations for `WorkoutState` round/timed lifecycle APIs.

Required follow-up before approval:
1. Add exhaustive transition matrix tests for `RoundState` and `TimedState` in `test/state_test.dart` (or an approved split test file with test-map update): every `(from, to)` pair, including no-op and illegal transitions.
2. Exercise transitions through public `WorkoutState` methods only (`startRound`, `pauseRound`, `resumeRound`, `completeRound`, `endRoundEarly`, `startTimedEntry`, `pauseTimedEntry`, `resumeTimedEntry`, `finishTimedEntry`). Do not call private validators directly.
3. For allowed transitions, assert state persistence and side effects: in-memory instance changed, repository write occurred, and listeners notified.
4. For illegal transitions, assert silent rejection with no side effects: no state mutation, no repository write, no listener notification, and no thrown exception.
5. Add explicit terminal-state guarantees: once state is `finished`, all public transition attempts out of `finished` must be blocked for both round and timed instances.
6. Add explicit pause/resume repeatability coverage: single `paused -> active` and repeated multi-cycle `active -> paused -> active -> paused -> active` for both state machines.

Current tests in `test/state_test.dart` and `test/edge_case_test.dart` cover happy-path lifecycle and basic pause/resume, but not exhaustive legal/illegal transition matrices or side-effect invariants.

## Remediation Execution Plan (@developer)

### Scope
Add transition-matrix test coverage only. Do not modify production code in `lib/` for this iteration.

### Required Test Groups
1. Add group: `round state machine transition matrix` in `test/state_test.dart`.
2. Add group: `timed state machine transition matrix` in `test/state_test.dart`.

### Transition Matrix (Expected Legality)

#### Round
| From | To | Expected |
|---|---|---|
| notStarted | notStarted | reject |
| notStarted | active | allow |
| notStarted | paused | reject |
| notStarted | finished | reject |
| active | notStarted | reject |
| active | active | reject |
| active | paused | allow |
| active | finished | allow |
| paused | notStarted | reject |
| paused | active | allow |
| paused | paused | reject |
| paused | finished | allow |
| finished | notStarted | reject |
| finished | active | reject |
| finished | paused | reject |
| finished | finished | reject |

#### Timed
| From | To | Expected |
|---|---|---|
| notStarted | notStarted | reject |
| notStarted | active | allow |
| notStarted | paused | reject |
| notStarted | finished | reject |
| active | notStarted | reject |
| active | active | reject |
| active | paused | allow |
| active | finished | allow |
| paused | notStarted | reject |
| paused | active | allow |
| paused | paused | reject |
| paused | finished | allow |
| finished | notStarted | reject |
| finished | active | reject |
| finished | paused | reject |
| finished | finished | reject |

### Side-Effect Assertions Per Test
For each matrix case, assert all of the following:
1. State outcome: target state for allowed transitions, unchanged state for rejected transitions.
2. Persistence outcome: repository write count increments only for allowed transitions.
3. Notification outcome: listener callback count increments only for allowed transitions.
4. Failure mode: rejected transitions must not throw.

### Instrumentation Requirements (Test-Only)
1. Add a local counting repository test double in `test/state_test.dart` by extending `MockWorkoutRepository` and overriding:
   - `updateRoundInstance`
   - `updateTimedInstance`
2. Add integer counters for writes and expose reset helpers.
3. Attach a listener to `WorkoutState` and assert notify count deltas per transition.

### Explicit Scenario Tests
1. Terminal guarantee (round): once finished, attempts through all public round transition methods are rejected.
2. Terminal guarantee (timed): once finished, attempts through all public timed transition methods are rejected.
3. Resume single-cycle (round and timed): paused -> active works once.
4. Resume multi-cycle (round and timed): active -> paused -> active -> paused -> active is repeatable and persists each legal hop.

### Test Design Constraints
1. One transition outcome per test case.
2. Public WorkoutState APIs only.
3. No private validator calls.
4. No real timers, audio, or animations.

### Completion Checklist
1. [x] Run `test/state_test.dart` — 155 tests pass (new matrix groups included).
2. [x] Run `test/edge_case_test.dart` — 37 tests pass, no lifecycle regressions.
3. [x] Pass/fail summary: all new and existing tests green.
4. Tests were not split into a new file — no code-reviewer.agent.md update required.

### Code Reviewer - April 26, 2026 (Follow-up)

Implementation is close, but this iteration still does not fully satisfy the plan's verification and handoff requirements.

Required follow-up before approval:
1. Add the missing widget test for the active round finish path in `test/session_finish_timers_test.dart` (or an approved equivalent mapped widget test): start a `round` effort, finish the workout, assert summary navigation, assert the round is persisted as `RoundState.finished`, and assert the session has `endedAtMs`.
2. Add an explicit handoff summary with a `Doc Updates` section covering the developer-owned docs named in the reviewer checklist. If no doc change is needed for a file, state that explicitly rather than omitting it.
3. Add a short reviewer/developer note for the missing `## Scenarios` register in this plan so future review iterations have a direct scenario-to-test mapping.

Non-blocking adjacent warning:
- `lib/state/app_state.dart` is still unreferenced dead code per the standing reviewer note. Remove it or wire it intentionally in a separate cleanup iteration.

---

## Scenarios

> Note: No scenario register was written before implementation. Tests covering terminal
> guarantee, active-round finish, and active-timed finish exist in
> `test/session_finish_timers_test.dart` and `test/state_test.dart`. A retroactive
> scenario register should be added before the next iteration if this feature is extended.

---

## Handoff Summary — Developer, April 27, 2026

### Phase 0 — TDD
- Scenarios confirmed: retroactive (see `## Scenarios` note above)
- Round finish widget test added: `test/session_finish_timers_test.dart` line 187
- All tests: PASS (155 state_test, 37 edge_case_test, all session_finish_timers_test)

### Implementation
- State classes created/updated: none (test-only iteration)
- Screens implemented: none
- Widgets extracted: none
- Navigation updated: no

### Doc Updates
- docs/navigation_and_screens.md — no change required (no new screens or routes)
- docs/state_management.md — no change required (no new state APIs)
- docs/widget_catalog.md — no change required (no new reusable widgets)
- docs/modality_based_exercise_ui.md — no change required (no UI changes)
- docs/db_integration.md — no change required (no repository interface changes)

### Files Changed
- test/session_finish_timers_test.dart (active round finish widget test added)
- test/state_test.dart (round + timed transition matrix groups added)
- docs/plans/finish-session-stops-timers-plan.md (Progress updated, Scenarios note, Handoff Summary)

### Tested On
- [x] All Phase 0 scenario tests green
- [x] No regressions in existing tests

---

@developer - Please proceed with Iteration 1 (Logic/UI) above. No DBA changes are required for this fix.
