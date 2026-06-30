# Feature: Unified Rest Overlay Rule Across All Workout Surfaces

## Overview
Today the per-set rest indicator uses two different visibility rules depending on which
workout surface you're looking at:

- The **detail (per-exercise) view** hides the rest overlay chip when an effort timer is
  currently running on the displayed entry (`!(_effortRunning['$effortId-$entryIndex'] ?? false)`).
- The **list (session-detail) view** shows the rest chip whenever any open rest exists in
  the session, with no check on whether an effort is actively running.

So when a user starts a timer on a set whose rest is still open, the detail view correctly
hides the chip but the list view keeps displaying a counting timer — two surfaces
contradicting each other.

This plan establishes one shared rule across both surfaces: **show the rest overlay chip
iff a rest period is open AND no effort is actively running for the entry that rest
precedes**. The new screen-level helper `_shouldShowRestOverlay` is the single source of
truth; both `Positioned(...child: _buildRestOverlayChip(...))` call sites collapse to
`!widget.editMode && _shouldShowRestOverlay()`.

## Root Cause
- `lib/features/session/workout_session_list_view.dart:372` and `:498` (rolling + standard
  list views) gate the rest chip on `_hasGlobalRestToDisplay()` alone — they don't check
  `_effortRunning`.
- `lib/features/session/workout_session_list_view.dart:767` (detail view) additionally
  gates on `!(_effortRunning['${exercise['id']}-${_currentSet - 1}'] ?? false)`.

Three sites, two rules. Whenever an effort is running the list view keeps showing a
rest chip while the detail view hides it.

## Requirements
1. A user is "resting" iff a rest record is open AND no effort is currently active
   anywhere in the session (session-wide check, not per-entry).
2. Both surfaces (list view, detail view) derive the chip's shown/hidden state and its
   elapsed time from the same source — `_getMostRecentOpenRestKey()` +
   `_formatGlobalRestElapsed()` — so they can never disagree.
3. Starting any effort type — logging a set, starting a timed/drill timer, starting a
   round — ends the open rest in the data layer for that effort (existing behavior
   preserved) so no screen displays a counting timer once any effort is running.

## Acceptance Criteria
- [ ] The list view (both standard and rolling) hides the rest chip whenever ANY
      effort timer is running in the session — not only when the entry the most-recent
      open rest precedes is running. (Session-wide check.)
- [ ] The detail view hides the rest chip under the same session-wide rule — never
      shows the chip while any effort timer is running anywhere in the session.
- [ ] All three rest-chip `Positioned(...)` call sites use the same shared helper
      (`_shouldShowRestOverlay`) — only differ in stack nesting, never in visibility rule.
- [ ] Both surfaces render the chip's elapsed text from the same helper
      (`_formatGlobalRestElapsed`) — single source of truth.
- [ ] For the same session state, the detail-view chip and the list-view chip both
      shown or both hidden, with the same elapsed value.
- [ ] Logging a set ends the most-recent open rest for that effort (no open rest for
      the just-logged entry remains after `Log Set`).
- [ ] Starting a timed/drill effort calls `closeAllOpenRests` so no open rest remains
      for that effort after the timer starts.
- [ ] Starting a round calls `closeAllOpenRests` so no open rest remains for that
      effort after the round timer starts.
- [ ] Normal rest between sets (open rest, no effort running) still displays and counts
      on both surfaces identically.
- [ ] Cross-effort scenario: a rest open for exercise A is also hidden on every
      surface while a timer is running on exercise B (unified session-wide rule).
- [ ] `docs/rest_tracking.md` reflects the unified session-wide rule.

## Scenarios

### S-001: Rest chip hides on list view when any effort is running
- Trigger: User logs set 1, navigates to list view (rest open for entryIndex=1),
  navigates back to detail, taps Start on the timed entry, returns to list view.
- Precondition: Non-rolling session with one time-capable exercise, one set logged
  (rest open), no timer has been started.
- Flow: Log set 1 → open rest for entryIndex=1 → switch to list view → chip visible →
  switch back to detail → tap Start → `closeAllOpenRests` fires → switch to list view.
- Expected outcome: The list view does NOT render the rest overlay chip.
- Edge case of: none.

### S-002: Rest chip hides on detail view when any effort is running
- Trigger: User starts a round from the detail view after the prior round logged and
  opened a rest.
- Precondition: Round-capable exercise, one round logged → rest open for entryIndex=1.
- Flow: Detail view open on round 0 → log round 0 (manual Log Round) → rest opens for
  entryIndex=1 → chip visible → tap Start on round 1.
- Expected outcome: Detail view does NOT render the rest overlay chip.
- Edge case of: none.

### S-002b: Cross-effort scenario — list and detail agree when a different effort is running
- Trigger: User logs exercise A's set 1 (rest opens for A/entryIndex=1), navigates to
  exercise B and starts B's round timer.
- Precondition: Session with two exercises (A is a set-kind exercise, B is a
  round-capable exercise). A's rest is open; B has no open rest.
- Flow: Log A's set 1 → open rest for A/entryIndex=1 → switch to B's detail view →
  tap Start on B's round.
- Expected outcome: Both list view and detail view must hide the rest chip while B's
  timer is running. (Under the OLD per-entry rule the list view would still render
  the chip for A's open rest.)
- Edge case of: S-004.

### S-003: Both surfaces render the same chip with the same elapsed (no effort running)
- Trigger: After logging a set, before starting any timer, on both views.
- Precondition: Open rest for some entry, no effort timer running.
- Flow: Capture elapsed text in list view → switch to detail view → capture again.
- Expected outcome: Both views show the rest chip; the elapsed text is the same in both
  views (within one-second tick granularity).
- Edge case of: none.

### S-004: Both surfaces hide the chip identically when the entry's effort is running
- Trigger: User starts a timer on the entry that owns the most-recent open rest.
- Precondition: Open rest + timer running for the same effortId/entryIndex.
- Flow: After timer start, check list view chip + check detail view chip.
- Expected outcome: Neither view renders the rest chip.
- Edge case of: S-001 (the list-view-only failure mode).

### S-005: Logging a set closes the open rest (state)
- Trigger: `WorkoutState` layer (via screen `_logSet`).
- Precondition: An open rest exists for `(effortId, entryIndex)`.
- Flow: Log a set → `_logSet` calls `recordRestEnd` for the most-recent open rest.
- Expected outcome: After tapping Log Set, the rest record for the just-logged entry
  has `restEndMs != null`. Any new rest opened by the same `_logSet` is for the
  *next* entry — it does not undo the close on the just-logged entry.
- Edge case of: none.

### S-006: Starting a timed effort closes the open rest (state)
- Trigger: User taps Start on a notStarted timed (or drill) instance.
- Precondition: Open rest exists for `(effortId, entryIndex)`.
- Flow: Timer toggle → `closeAllOpenRests(effortId)` → all open rests for the effort
  close.
- Expected outcome: `getEntryRests(effortId).where((r) => r.restEndMs == null)` is empty
  after the toggle.
- Edge case of: none.

### S-007: Starting a round closes the open rest (state)
- Trigger: User taps Start on a notStarted round instance.
- Precondition: Open rest exists for `(effortId, entryIndex)`.
- Flow: Round toggle → `closeAllOpenRests(effortId)` → all open rests for the effort
  close.
- Expected outcome: `getEntryRests(effortId).where((r) => r.restEndMs == null)` is empty
  after the toggle.
- Edge case of: none.

## Iteration 1

### DB Changes
None — the `EntryRest` model and `closeAllOpenRests` / `recordRestEnd` repository contract
are unchanged. The plan is purely a UI-rule refactor; existing data writes already close
the right records at the right moment.

### Backend Changes
None — `WorkoutState` public surface is unchanged. No new method, no removed method.

### Frontend Changes

#### `lib/features/session/workout_session_global_timer.dart`
- Add a single screen-level helper on the `_SessionGlobalTimerExt` extension:
  ```dart
  /// Shared rest-overlay visibility rule for every [WorkoutSessionScreen]
  /// surface. The chip is visible iff a rest period is open AND no effort
  /// is currently active *anywhere in the session* (session-wide check).
  /// Both the list view and the detail view must call this helper so the
  /// two surfaces always agree.
  bool _shouldShowRestOverlay() {
    if (widget.editMode) return false;
    if (_getMostRecentOpenRestKey() == null) return false;
    // Session-wide "any effort active" check.
    for (final entry in _effortRunning.entries) {
      if (entry.value == true) return false;
    }
    return true;
  }
  ```
- Keep the existing `_hasGlobalRestToDisplay()` for callers that genuinely only need
  the data-layer signal (e.g., `_checkRestPings`, `_scheduleActiveRestNotifications`).
  These are correct as-is and are not part of the bug.

#### `lib/features/session/workout_session_list_view.dart`
- Replace the three rest-chip `Positioned(...)` gates (rolling list `:372`, standard
  list `:498`, detail view `:767`) from:
  ```dart
  if (!widget.editMode && _hasGlobalRestToDisplay())
  ```
  or
  ```dart
  if (!widget.editMode &&
      _hasGlobalRestToDisplay() &&
      !(_effortRunning['${exercise['id']}-${_currentSet - 1}'] ?? false))
  ```
  with
  ```dart
  if (_shouldShowRestOverlay())
  ```
  This collapses both forms into one. The `widget.editMode` guard moves inside
  `_shouldShowRestOverlay`.
- All three sites continue to call `_formatGlobalRestElapsed()` so the elapsed value
  stays in lock-step.
- The detail view's per-entry check (`$effortId-$_currentSet - 1`) is replaced by
  the session-wide check. In practice this is a strictness improvement: the chip
  is now also hidden when a different exercise's timer is running (cross-effort
  rest scenario, see S-002b). The existing test suite already exercises the
  "no-timer-running" case only, so no test should regress.

### Implementation Steps

1. **Phase 1 — TDD**: Add the scenario tests (S-001..S-007) as failing tests against the
   current code. Confirm they fail before implementation, then fix the code, then
   confirm green.
2. **Phase 2 — Implement helper**: Add `_shouldShowRestOverlay()` to
   `workout_session_global_timer.dart`.
3. **Phase 3 — Replace call sites**: Edit `workout_session_list_view.dart` to call the
   helper in all three `Positioned(...)` gates.
4. **Phase 4 — Verify review-flagged test**: Confirm the existing "vertical position"
   tests in `test/screen_widget_test.dart` (the `pumpSessionWithOpenRest`-based group)
   still pass — they should because the helper preserves chip visibility whenever the
   same `_hasGlobalRestToDisplay() && no-effort-running` condition is met (and no
   timer is running in those tests).
5. **Phase 5 — Doc hygiene**: Update `docs/rest_tracking.md` → "WorkoutSessionScreen
   Integration" section to document the unified `_shouldShowRestOverlay()` rule.
6. **Phase 6 — Run**: `flutter test` → all green.

## Progress

### Phase 0
- [x] Author plan file
- [x] ### Phase 0 Complete ✓

### Phase 1 (Data Layer)
- [x] N/A (no model / repo / state changes)
- [x] ### Phase 1 Complete ✓

### Phase 2 (Logic & UI) — TDD
- [x] Add S-001..S-007 + S-002b scenario tests (red run: S-002b failed on current code)
- [x] Confirm red run captured: `S-002b: cross-effort — list view hides the chip for A's open rest while B's timer is running` failed before the fix
- [x] Implement `_shouldShowRestOverlay` helper in `workout_session_global_timer.dart`
- [x] Replace 3 call sites in `workout_session_list_view.dart`
- [x] Run `flutter test test/unified_rest_overlay_test.dart` → all 8 green
- [x] Run `flutter test test/unified_rest_overlay_test.dart test/round_auto_expiry_test.dart test/screen_widget_test.dart` → all 231 green
- [x] Full suite regression: only pre-existing failures in `avatar_crop_sheet_test.dart` and `profile_cleanup_test.dart` (verified via `git stash`-then-run on main)
- [x] ### Phase 2 Complete ✓

### Phase 3 (Code Review)
- [x] Doc hygiene table verified (`rest_tracking.md` updated, others N/A)
- [x] Global conventions verification (PASS on Rule 6 "Reuse the canonical owner" — helper composes existing primitives; N/A for the visual/unit/architecture rules because no UI chrome, units, analytics, navigation, or storage surface changed)
- [x] Architecture compliance (features + private extensions only; no model/repo/state/IO surface; no concrete repo import in scope; state injected via constructor as before)
- [x] Buttons spot-check (no new buttons added; no existing button touched)
- [x] Dead code check (no new unreferenced state/service/widget)
- [x] Test coverage (8 new tests in `test/unified_rest_overlay_test.dart` cover every scenario; pre-existing rest/screen/state tests still pass)
- [x] Environment safety (no `dart:io`, no `Platform.is*`, no SQLite, no concrete repo import)
- [x] ### Phase 3 Complete ✓

## Feedback
