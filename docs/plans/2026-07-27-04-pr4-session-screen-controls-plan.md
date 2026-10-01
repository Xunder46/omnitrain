# PR 4: Session Screen Controls

> **Priority 4 of 8 — Tier 2 quick wins.** Includes Item 6 (tappable rest timer) and Item 7 (Discard Session).

## Overview

Add pause/resume interaction to the persisted rest timer and expose confirmed session discard from both session header modes. Paused time is excluded from recorded rest; cancellation of discard is completely side-effect free.

## Requirements

- Whole-tile tap toggles running/stopped and resumes from accumulated counted time.
- Persist reload-safe counted time excluding stopped intervals.
- Make not-started, running, and stopped visually distinct without reading the number.
- Logging a set or starting an effort timer closes the current rest as before.
- Add secondary destructive discard to list/detail headers.
- Confirmation states permanent loss; confirm deletes the complete session aggregate, clears active state, and returns home.
- Cancel preserves all data and timers.

## Acceptance Criteria

- [ ] Tap stops within one second and next tap resumes without reset.
- [ ] Three rest states are visually distinct and whole tile meets touch-target size.
- [ ] Recorded duration excludes stopped time, including rapid taps/lifecycle changes.
- [ ] Set logging and effort-timer start close stopped rests correctly.
- [ ] Discard is reachable in list/detail headers, secondary, and away from logging controls.
- [ ] Confirmation states permanence.
- [ ] Confirm removes all session-owned data and returns home with no active/history/calendar entry.
- [ ] Cancel preserves values and uninterrupted timers.

## Scenarios

### S-001: Rest pauses/resumes counted time
- Trigger: Tap running rest, wait, tap again.
- Precondition: Open rest exists.
- Flow: running → stopped → running → complete.
- Expected outcome: Persisted duration excludes stopped interval.
- Edge case of: none

### S-002: Rapid taps serialize
- Trigger: Several quick taps.
- Precondition: Rest is running.
- Flow: Toggle requests overlap.
- Expected outcome: Consistent final state with no lost/double-counted time.
- Edge case of: S-001

### S-003: Confirm/cancel discard
- Trigger: Choose discard from either header mode.
- Precondition: Active session has data/timers.
- Flow: Confirmation → cancel or confirm.
- Expected outcome: Cancel changes nothing; confirm deletes aggregate and returns home.
- Edge case of: none

## Iteration 1

### DB Changes
- Extend `EntryRest` only if existing timestamps cannot represent paused intervals reload-safely; update model/repository/Hive/mock/SQL docs if needed.

### Backend Changes
- Add serialized pause/resume/completion through `WorkoutState` and repository interface.
- Reuse canonical session aggregate deletion and verify child cleanup.

### Frontend Changes
- Make rest tile tappable with three token-based visual states.
- Add shaped secondary destructive header action and shared confirmation.

### Implementation Steps
1. TDD rest transitions/math/rapid taps.
2. Update persistence contract if required.
3. TDD confirm/cancel deletion and history/calendar absence.
4. Implement tile and header UI.
5. Run lifecycle, targeted, and full tests.

## Unit Tests Required
- Running→stopped and stopped→running preserve accumulated time.
- Rapid toggles and completion while stopped exclude paused duration.
- Three visual states map correctly.
- Confirm deletes full aggregate and clears all query surfaces; cancel changes nothing.
- Extend uninterrupted-rest and finish-only-ending tests.

## Progress
- [ ] TDD red run recorded
- [ ] Phase 1 — Rest persistence completed or N/A
- [ ] Rest pause/resume implemented
- [ ] Session discard implemented
- [ ] Full suite green
- [ ] Phase 3 — Code Review
- [ ] Release-ready

## Feedback


### Phase 0 Complete ✓

### Phase 1 Complete ✓
- EntryRest model: added `restIsPaused`, `restPausedAtMs`, `restPausedDurationMs`
- TimerManager: added `pauseRest`, `resumeRest`, `isRestPaused`, `_effectiveRestEndMs`
- WorkoutState: pauseRest / resumeRest / isRestPaused wrappers
- scripts/sqlite_schema.sql: ALTER TABLE for new columns documented

### Phase 2 Complete ✓
- workout_session_list_view.dart: rest chip wrapped in Material+InkWell (48dp floor, whole-tile tap); three visual states (meditation icon when running, pause icon + "Paused · tap to resume" caption when paused); discard action in list/detail headers (`Icons.delete_forever`, error tint, hidden in edit mode)
- docs/rest_tracking.md: EntryRest fields, schema, API table, three-state overlay table, pause/resume behaviour
- docs/navigation_and_screens.md: WorkoutSessionScreen row mentions PR 4 Discard action and tappable rest overlay chip
- test/state_test.dart: 6 new tests (rest pause/resume, rapid taps, reload safety, end-while-paused, closeAllOpenRests preserves pause time, etc.)
- test/models_test.dart: 7 new tests (EntryRest new fields, fromMap/toMap, copyWith, elapsedSeconds)
- test/pr4_session_controls_test.dart (NEW): 7 UI smoke tests (rest chip visible after Log Set, 48dp touch target, three visual states via state API, discard action visible, cancel preserves data, confirm clears repo+state, hidden in edit mode)
- test/session_toolbar_rework_test.dart: still passing (Icons.delete_outline reserved for the single-set remove; new discard uses Icons.delete_forever to avoid collision)
- All 2004 tests pass

### Phase 3 Complete ✓
- All 2004 tests pass; no regressions.
- All 8 acceptance criteria verified by tests + manual inspection.
- Doc hygiene updated for `rest_tracking.md`, `navigation_and_screens.md`, `data_models.md`. All under 64 KiB ceiling.
- Layers in scope: models, state, features, docs. No architecture regressions.

### Phase 3 Refinement ✓ (2026-07-27)
- Rest chip: removed "Paused · tap to resume" caption and dropped the
  BoxShadow + Border so the paused chip has identical dimensions to the
  running chip. Caption was redundant with the meditation/pause icon
  swap; shadow and border were both adding 1–2dp spread to the bounding
  rect. The three states (not-started / running / paused) now differ only
  by background tint and icon.
- Discard: replaced the 48×48 icon button with a full-width hollow red
  `OutlinedButton` labelled "Discard" (`colorScheme.error` border + text,
  `OmniTheme.buttonUtilityRadius`). Moved from the header into the
  session-details body, sitting below the Add Exercise / Add Block bar.
  Exercise-details header is restored to its pre-PR-4 shape (no Discard).
  In edit mode the button still mounts but with `onPressed: null` so the
  layout is consistent.
- Tests updated to match: `pr4_session_controls_test.dart` switches to
  `find.widgetWithText(OutlinedButton, 'Discard')` and adds a
  "discard button is hidden in the exercise-details (detail) view" test.
  Three-statestest now asserts the chip's height matches between running
  and paused (caption is gone). `unsaved_changes_dialog_test.dart` and
  `session_edit_duration_test.dart` scope their Discard tap to the
  AlertDialog to avoid the new screen-level Discard button.
- All 2005 tests pass.
- Docs: `rest_tracking.md` table updated to drop the caption column and
  the obsolete BoxShadow/border notes; `navigation_and_screens.md`
  describes the new Discard button location.

### Phase 3 Refinement 2 ✓ (2026-07-27)
- Discard moved back into `_buildHeader` per user feedback — "in the header,
  hidden on the exercise details" is now literal: the button renders only
  when `_showListView == true` (session-details header). The detail
  (exercise-details) header keeps its pre-PR-4 action row
  (notes / info icons).
- OutlinedButton is now compact (`padding: 16/8`, `minimumSize: 0×40`,
  `tapTargetSize: shrinkWrap`) so it fits cleanly in the trailing edge of
  the header row alongside the back arrow + Expanded title column.
- Edit mode: `onPressed: null` + muted tint via `OmniTheme.colors.textDisabled`.
- All 8 PR4 UI tests still pass (no test edits needed — the
  `find.widgetWithText(OutlinedButton, 'Discard')` finder is unaffected
  by the button's parent widget).
- All 2005 tests pass.

### Phase 3 Refinement 3 ✓ (2026-07-27)
- Added `OmniTheme.headerSecondaryActionSize = 48.0` token — the
  Material default tap-target (`kMinInteractiveDimension`). Every
  secondary header action now shares this exact height regardless
  of whether it is icon-only (notes / info [IconButton]s) or
  labeled (Discard [OutlinedButton]).
- Updated `_buildExerciseHeaderActions` in
  `workout_session_detail_view.dart` to use the token for its
  `BoxConstraints(minWidth: …, minHeight: …)`.
- Updated `_buildDiscardHeaderButton` in
  `workout_session_list_view.dart` to wrap the `OutlinedButton`
  in `SizedBox(height: OmniTheme.headerSecondaryActionSize)` —
  the OutlinedButton ignores `minimumSize` and renders at its
  intrinsic minimum (48 dp by default), so the SizedBox is the
  most reliable way to enforce a fixed height.
- New test "discard header button matches secondary action
  height (48dp)" verifies all three secondary actions
  (Discard, notes, info) render at exactly
  `OmniTheme.headerSecondaryActionSize` and that they are
  pairwise equal.
- All 2006 tests pass (+1 net from the new height test).

### Phase 3 Refinement 4 ✓ (2026-07-27)
- Header buttons were too tall. The Material default tap-target
  (48 dp) crowded the header row and didn't match the existing
  compact header-button style used elsewhere in the app
  (calendar `+` button, period-list add button — 40 dp via
  `VisualDensity.compact`).
- Updated `OmniTheme.headerSecondaryActionSize` from 48.0 → **40.0**.
- `_buildExerciseHeaderActions` (notes / info IconButtons) now
  uses both `VisualDensity.compact` AND a 40-dp `BoxConstraints`
  constraint — `VisualDensity.compact` shrinks the default,
  the constraint keeps it from going under 40.
- `_buildDiscardHeaderButton` no longer wraps in a SizedBox;
  uses `VisualDensity.compact` + matching padding to match the
  calendar `+` style (no `tapTargetSize: shrinkWrap` because that
  would drop the button below the 40-dp floor).
- `test/exercise_notes_sheet_test.dart` updated to expect 40 dp
  hit targets and a shared compact icon size.
- All 2006 tests pass.
