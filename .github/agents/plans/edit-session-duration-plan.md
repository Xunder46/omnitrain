# Feature: edit-session-duration

## Overview
Allow users to edit final session duration while in Edit Session mode so they can correct sessions that kept running in the background after they stopped training but forgot to press Finish.

## Requirements
- Edit Session mode must expose session duration as an editable value.
- Editing duration must update the session end timestamp deterministically (`endedAtMs = startedAtMs + editedDuration`).
- Duration edits must participate in existing unsaved-changes behavior (Save / Discard / Keep editing).
- Duration editing must not restart timers or alter per-effort timer lifecycle behavior.
- Solution must remain repository-agnostic (works with current Hive repo on web and future SQLite through existing repository contracts).

## Iteration 1

### Analysis
User flow already supports opening `WorkoutSessionScreen` with `editMode: true` from session summary. Timed and round entries are already editable in edit mode, but session-level duration is currently derived from timestamps and not directly editable. We need a session-level edit control that writes back to `endedAtMs` when the user saves changes.

### Questions (if any)
1. Should editing session duration be allowed to set a value shorter than the sum of all logged effort durations, or should we clamp to at least that computed minimum?
2. Should the UI expose duration only (derived end time), or both explicit end time and duration for advanced correction?

### DB Changes (@dba)
1. [ ] No schema changes required.
2. [ ] No repository interface changes required if we reuse existing session update path.

### Backend Changes (@developer)
1. [ ] Add edit-session state field(s) in `WorkoutSessionScreen` for pending session duration override (seconds/ms) initialized from persisted session timestamps.
2. [ ] Extend edit buffer/snapshot dirty-check logic so session-duration changes are tracked as unsaved edits.
3. [ ] Add/update `WorkoutState` method to persist an edited session end time in edit mode without invoking finish flow side effects.
4. [ ] On Save Changes, write adjusted `endedAtMs` before returning to summary and refresh summary totals from persisted data.
5. [ ] Add guardrails for invalid edits:
   - Duration cannot be negative.
   - `endedAtMs` cannot be earlier than `startedAtMs`.
   - Apply product decision from Question 1 (clamp vs allow below logged effort sum).

### Frontend Changes (@developer)
1. [ ] Add a visible session-level duration editor in edit mode (not live mode), using existing interaction patterns (InlineMetricEditor style).
2. [ ] Ensure displayed session duration reflects pending edit immediately (optimistic local UI) while preserving existing list/detail layout behavior.
3. [ ] Keep timer/status visuals read-only in edit mode (no play/pause behavior introduced by this feature).
4. [ ] Preserve current navigation semantics:
   - Back from edit mode prompts unsaved-changes if duration changed.
   - Save returns to summary with corrected duration shown.

### Implementation Steps
1. [ ] Audit edit-mode initialization and save paths in `WorkoutSessionScreen` (`_computeSessionDuration`, edit snapshot, save handler).
2. [ ] Add session-duration edit control and wire change callback to pending edit state.
3. [ ] Integrate session-duration edits into `_hasUnsavedEditChanges()` and rollback flow.
4. [ ] Implement state-layer persistence method for session `endedAtMs` correction using existing repository update mechanism.
5. [ ] Update summary refresh/navigation flow so corrected duration is visible immediately after save.
6. [ ] Add tests:
   - Edit mode duration change + Save updates displayed session duration in summary.
   - Duration change triggers unsaved-changes dialog when backing out.
   - Discard in edit mode reverts duration to original value.
   - Invalid duration inputs are rejected/clamped per accepted rule.
7. [ ] Run regression checks for finish-session timer finalization and existing timed/round edit behaviors.

### Acceptance Criteria
- [ ] In Edit Session mode, user can change session duration directly.
- [ ] Saving edits persists corrected duration by updating session timestamps.
- [ ] Session summary shows corrected duration after returning from edit flow.
- [ ] Unsaved-changes protection includes session duration edits.
- [ ] No regressions in timer finalization, round/timed entry editing, or web behavior.
- [ ] Architecture remains environment-agnostic (Hive now, SQLite-ready later).

### Files Affected
- lib/features/session/workout_session_screen.dart
- lib/state/workout/workout_state.dart
- lib/features/session/session_summary_screen.dart
- test/unsaved_changes_dialog_test.dart
- test/session_finish_timers_test.dart
- test/session_edit_duration_test.dart

### Notes
- Align with modality-based timer rules in `modality_based_exercise_ui.md` and `modality_tracking.md`: edit mode must remain non-live and should only mutate persisted values on Save.
- Keep finish-flow behavior separate from edit-flow behavior to avoid accidental timer lifecycle coupling.

## Progress
- [x] Confirm product decision for minimum allowed session duration (clamp rule)
      → Allow any positive value; zero/negative are rejected by `updateSessionEndTime`.
- [x] Implement edit-mode session duration UI/state
      → `_pendingDurationSecs`, `_originalDurationSecs`, `_hasDurationChanged()`,
         `_reformatElapsed()`, `_editSessionDuration()` dialog,
         `_buildSessionTimeWidget()` helper, both chip replacements in `_buildListView`.
- [x] Persist edited `endedAtMs` through WorkoutState
      → `WorkoutState.updateSessionEndTime(int durationSecs)` added after `updateSessionNote`.
- [x] Add regression and unsaved-change tests
      → `test/session_edit_duration_test.dart` — 4 unit tests + 5 widget tests.
- [ ] Validate web flow manually and via tests

## Feedback
<!-- Leave empty until a specialist or reviewer adds notes -->

---

@developer - Please proceed with Iteration 1 (Logic/UI) above. No DBA schema work is required unless Question 1 introduces new data constraints.
