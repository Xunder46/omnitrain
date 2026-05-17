# Feature: Remove App-Launch Resume Modal

## Overview
Remove the cold-start unfinished-session resume modal entirely. On app launch with an in-progress session, the home screen should show only the existing red highlighted modality tile; tapping that tile resumes the session exactly like normal active-session flow.

## Requirements
- Remove the app-launch resume modal UI and any modal-only helper widgets.
- Remove modal-driving state/controllers/flags introduced for cold-start prompt behavior.
- Remove modal-trigger routing/startup logic (if any remains).
- Remove modal copy strings and modal-specific UI expectations.
- Remove modal-specific unit/widget tests.
- Replace removed modal tests with regressions that assert: no modal appears, tile highlight remains the sole affordance, tile tap resumes.
- Preserve current persistence and cold-start hydration behavior (no behavior changes to write-through persistence and load semantics).
- Keep existing "start new workout while one is in progress" conflict modal unchanged.
- Do not add any replacement UI surface (no banner/prompt/indicator).
- Per scope confirmation: remove modal-specific APIs if now unused, including repository/state helpers introduced for the modal path.

## Acceptance Criteria
- [ ] No app-launch resume modal appears under any condition.
- [ ] Modal-related UI/state/controller/routing/copy artifacts are removed from the codebase.
- [ ] Cold start with an in-progress session renders home with red highlighted modality tile and no modal.
- [ ] Cold start with no in-progress session renders unchanged clean home with no highlighted tile.
- [ ] Tapping highlighted tile after cold start resumes session with existing logged data intact.
- [ ] Session persistence and cold-start hydration behavior remain intact (no regressions in mutation persistence or startup load).
- [ ] Existing "Start New Session?" conflict modal still works unchanged.
- [ ] No replacement UI surface is introduced.

## Scenarios
- Cold start + in-progress session in storage: home renders immediately; highlighted tile visible; no modal; tap resumes.
- Cold start + no in-progress session: home renders normally; no highlighted tile; no modal.
- Mid-session warm usage and in-session flows: unchanged.

## Iteration 1

### Analysis
- Current codebase already appears to have no active resume modal implementation in HomeScreen startup flow; however, modal-specific remnants remain in state and tests.
- Modal-related state helpers currently present in WorkoutState: `checkForInProgressSession`, `deleteSessionById`, `countSetsForSession`, and helper counting logic.
- Repository API `getInProgressSessions` appears dedicated to the removed modal flow and currently has no production caller outside those state/tests.
- Modal test surface still exists in multiple test files and must be removed/replaced.
- `docs/app_philosophy.md` is not present in this workspace snapshot; plan aligns with the stated instrument-panel principle from request context (surface state, avoid interruption).

### DB Changes
- No schema/table/migration changes.

### Backend Changes
- Remove modal-only state methods and internal helpers from WorkoutState.
- Remove modal-only repository contract and implementations if no remaining runtime call sites require them.
- Remove dead comments/docs that reference cold-start resume modal behavior.
- Verify startup hydration path remains intact and independent of modal logic.

### Frontend Changes
- Ensure HomeScreen has no cold-start modal trigger path and no modal copy strings.
- Preserve active-tile highlight semantics and tap-to-resume navigation path.
- Keep unrelated conflict modal flows untouched ("Start New Session?").

### Implementation Steps

#### Phase 1: Data/Repository Cleanup (@developer)
1. [ ] Remove `getInProgressSessions()` from repository interface if confirmed unused outside removed modal flow.
2. [ ] Remove corresponding implementations from Hive and Mock repositories.
3. [ ] Remove/adjust any repository tests that exist solely for modal support.

#### Phase 2: State Cleanup (@developer)
1. [ ] Remove modal-introduced WorkoutState APIs: `checkForInProgressSession`, `deleteSessionById`, `countSetsForSession`, and private counting helper(s).
2. [ ] Remove state comments that reference unfinished-session resume modal behavior.
3. [ ] Confirm no feature/state code paths still call removed methods.

#### Phase 3: UI/Startup Cleanup (@developer)
1. [ ] Remove any remaining startup modal trigger hooks and modal copy references (if present).
2. [ ] Confirm HomeScreen behavior on launch is passive (state is surfaced by tile highlight only).
3. [ ] Confirm unrelated in-progress conflict dialog behavior remains unchanged.

#### Phase 4: Tests (@developer)
1. [ ] Delete modal rendering/action tests in HomeScreen interaction/widget suites.
2. [ ] Remove modal-specific state tests that only validate modal helper APIs.
3. [ ] Add/adjust regression tests to assert:
- [ ] cold-start with in-progress session shows no modal text/actions,
- [ ] corresponding home tile is highlighted as active,
- [ ] tapping highlighted tile navigates/resumes with persisted session data intact,
- [ ] cold-start without in-progress session remains unchanged.
4. [ ] Keep/extend tests that ensure "Start New Session?" conflict modal still appears for modality-switch conflicts.

### Files Affected
- lib/state/workout/workout_state.dart
- lib/data/repositories/workout_repository.dart
- lib/data/repositories/hive_workout_repository.dart
- lib/data/repositories/mock_workout_repository.dart
- lib/features/home/home_screen.dart
- test/interaction_flow_test.dart
- test/screen_widget_test.dart
- test/state_test.dart
- test/session_resume_test.dart

## Progress
- [x] Remove modal-only repository API and impls
- [x] Remove modal-only WorkoutState APIs/helpers
- [x] Remove any remaining startup modal trigger/copy
- [x] Replace modal tests with no-modal + highlighted-tile resume regressions
- [x] Verify unrelated in-progress conflict modal still passes
- [x] Run targeted tests and confirm no regressions

### Phase 2 Complete ✓
Implementation done. All targeted Logic/UI regressions green. Ready for Code Reviewer.

## Feedback
