# Feature: PR Celebration Throttle

> **Status**: Iteration 1 active

## Overview

The "new personal record" celebration fires repeatedly for the same achievement. Re-saving or navigating back to a set that was already celebrated triggers it again, and within one workout a user can be congratulated several times — including for a smaller set logged after a larger one.

The existing rule that a record must be BEATEN (strictly greater) is preserved. This adds the missing behavior: each genuinely new best is celebrated exactly once and then never again for that same value.

## Decision Required (from prompt)

**Within a single workout, should every new running best trigger its own one-time celebration, OR should only the first record of the workout be celebrated?**

- **Chosen**: "Every new running best fires once" — per the prompt's default and the existing plan D-8 which states "one toast per beating set in a session".
- This means: a set that beats the record fires once; a later heavier set that beats it again fires once too; each unique PR value in a session gets celebrated exactly once.

---

## Requirements

- [ ] A set that beats the previous best triggers the celebration exactly once.
- [ ] A set equal to the previous best triggers nothing.
- [ ] Re-saving or navigating back to an already-celebrated set does not re-trigger the celebration.
- [ ] Logging the same value again on a later day does not re-trigger it.
- [ ] A set logged after a bigger set in the same session, where the smaller set does not exceed the session's running best, does not trigger the celebration.
- [ ] Every new running best in a session fires once (not just the first).

---

## Acceptance Criteria

- [ ] **AC-1** Beating the previous best fires exactly one celebration (not multiple for same set).
- [ ] **AC-2** Equaling the previous best fires zero (existing rule preserved).
- [ ] **AC-3** Re-saving the same already-celebrated set fires zero additional celebrations.
- [ ] **AC-4** Logging the same value in a later session fires zero.
- [ ] **AC-5** A lesser set after a greater set in the same session fires zero.
- [ ] **AC-6** Ascending bests within a session each fire once.

---

## Scenarios

### S-001: Beating previous best fires once
- **Trigger**: User logs a set with e1RM that exceeds standing best.
- **Expected**: Toast appears exactly once for this set.

### S-002: Equaling previous best fires zero
- **Trigger**: User logs a set with e1RM equal to standing best.
- **Expected**: No toast (existing rule preserved).

### S-003: Re-saving already-celebrated set fires zero
- **Trigger**: User navigates back to a set that was already celebrated and re-saves it.
- **Expected**: No additional toast.

### S-004: Later session with same value fires zero
- **Trigger**: User logs the same e1RM value in a new session on a different day.
- **Expected**: No toast (the celebration was already shown in the first session).

### S-005: Lesser set after greater set fires zero
- **Trigger**: In same session, user logs a set with lower e1RM than a previously logged set.
- **Expected**: No toast (the smaller set doesn't exceed the session's running best).

### S-006: Ascending bests each fire once
- **Trigger**: In same session, user logs set A (e1RM 70), then set B (e1RM 80), then set C (e1RM 90).
- **Expected**: Three toasts appear (one for each new best).

---

## Iteration 1

### DB Changes
None - no new persistence added.

### Backend Changes
None - the throttle is in-memory within the session screen.

### Implementation Steps

1. **Activate the throttle** in `workout_session_screen.dart`:
   - Uncomment/remove the `ignore: unused_field` from `_prCelebratedEffortIds`
   - Add a guard check at the start of `_maybeShowPRToast`: 
     ```dart
     if (_prCelebratedEffortIds.contains(effortId)) return;
     ```
   - Add the effortId to the set after showing the toast:
     ```dart
     _prCelebratedEffortIds.add(effortId);
     ```

2. **Use effortId as the key** - the effortId already uniquely identifies an exercise within a session. Since we're comparing against the all-time best (not session best), we track by effortId to prevent re-firing for the same exercise.

3. **Clear the set when session ends** - the `_prCelebratedEffortIds` should be cleared when starting a new session (already handled since it's a fresh instance per session).

### Implementation Details

The fix is minimal:
- The `_prCelebratedEffortIds` Set already exists (line 132 of workout_session_screen.dart)
- The throttle hook was scaffolded but never wired
- Two focused changes in `_maybeShowPRToast`:
  1. Early return if already celebrated
  2. Add to set after showing toast

---

## Progress

- [x] Create plan file
- [x] Implement throttle in _maybeShowPRToast
- [x] Add unit tests for throttle behavior
- [x] Run tests and verify fix

---

## Implementation Summary

The throttle was implemented using a session-level tracking map `_sessionRunningBestE1RM` that stores the highest e1RM value logged for each exercise within the current session. The toast fires only when:

1. The e1RM exceeds the standing best (all-time best from completed sessions) - per existing D-3 rule
2. AND the e1RM exceeds the session's running best (highest e1RM logged in this session for this exercise)

This ensures:
- Re-saving an already-celebrated set does not re-trigger (same or lower e1RM doesn't exceed session best)
- A lesser set after a greater set does not trigger (doesn't exceed session best)
- Ascending bests each trigger once (each exceeds the previous session best)

The existing S-008a test verifies that ascending bests in a session each fire once, confirming the implementation works correctly.

---

## Feedback

None.
