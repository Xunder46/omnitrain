# Feature: Exercise Info & Notes Sheets

## Overview
Two additive bottom-sheet capabilities in WorkoutSessionScreen detail mode:
- Exercise Info: read-only sheet with exercise image and ordered how-to cues
- Exercise Notes: editable, auto-saving, per-exercise persistent notes with header indicator

No full-screen navigation changes; all interactions remain in the session experience.

## Requirements
- Maintain repository abstraction compatibility for web and native paths
- Ensure note-dependent header UI never renders before note cache load on any detail-entry path
- Keep save-order guarantees for rapid, overlapping note edits
- Preserve existing behavior for info/notes sheets except for correctness fixes
- Keep implementation platform-agnostic in shared layers

## Iteration 5

### DB Changes
- None required

### Backend Changes
- Confirm no model/schema/repository-interface changes are needed
- Add required method-level lifecycle documentation in state layer

### Frontend Changes
- Fix initial-focus detail sequencing so note load is awaited before detail render
- Preserve existing sheet UX while ensuring indicator correctness on first detail paint

### Implementation Steps
1. [ ] In [lib/features/session/workout_session_screen.dart](lib/features/session/workout_session_screen.dart), remove early `_showListView = false` transition inside `_loadExercises()` for `initialFocusId` restore.
2. [ ] Route initial-focus restore exclusively through awaited `_focusExerciseDetail(index)`.
3. [ ] Verify no other unawaited detail-entry path can render note-dependent header UI before `loadExerciseNote(exerciseId)` completes.
4. [ ] In [test/workout_state_note_serialization_test.dart](test/workout_state_note_serialization_test.dart), instantiate delayed repository with non-zero load latency for cache-skip timing coverage.
5. [ ] Assert first load reflects latency and second load is cache-fast (with CI-tolerant bounds).
6. [ ] In [lib/state/workout/workout_state.dart](lib/state/workout/workout_state.dart), add one doc line on `saveExerciseNote()` stating queue entries are session-scoped and cleared by `clearSession()`.
7. [ ] Run verification commands and focused tests listed below.

### Acceptance Criteria
- [ ] Initial-focus restore does not enter detail mode until note load is complete.
- [ ] No detail-entry path renders note-dependent header UI before cache hydration.
- [ ] Cache-skip timing test is meaningful and would fail without skip behavior.
- [ ] `saveExerciseNote()` method doc includes session lifecycle cleanup note.
- [ ] `flutter analyze` completes with zero errors.
- [ ] `flutter test test/workout_state_note_serialization_test.dart` passes.
- [ ] `flutter test test/exercise_notes_sheet_test.dart` passes.

### Files Affected
- lib/features/session/workout_session_screen.dart
- test/workout_state_note_serialization_test.dart
- lib/state/workout/workout_state.dart

## Progress
- [x] Iteration 5 Phase 1: confirm no data-layer changes are needed
- [x] Iteration 5 Phase 2A: fix initial-focus detail-entry sequencing
- [x] Iteration 5 Phase 2B: strengthen cache-skip timing test
- [x] Iteration 5 Phase 2C: add saveExerciseNote() lifecycle doc note
- [x] Iteration 5 Verification: flutter analyze (no errors; existing info-level lints remain)
- [x] Iteration 5 Verification: workout_state_note_serialization_test.dart
- [x] Iteration 5 Verification: exercise_notes_sheet_test.dart

## Feedback
[No new feedback yet]

---

@developer - Please proceed with Iteration 5 implementation.
