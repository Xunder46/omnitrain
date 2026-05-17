# Feature: Routine Exercise Detail Screen UI Parity with Live Session

## Overview
The exercise detail screen shown during routine creation/editing (`_buildDetailView` in `RoutineSetupScreen`) is out of date. Its set-management controls are in a bottom bar that does not match the live session's exercise detail UI. The source of truth for UI/UX is `WorkoutSessionScreen`'s detail view (`workout_session_detail_view.dart`).

## Requirements
- The routine exercise detail view must visually and structurally match the live session detail view.
- Set add/remove controls must move inline, flanking the "Set X of Y" label.
- The bottom bar must become navigation-only (back/forward arrows only), matching session edit-mode behavior.
- No new state methods, no schema changes, no repository changes.

## Acceptance Criteria
- [ ] `_buildSetProgress` in `RoutineSetupScreen` renders `[-] Set X of Y [+]` inline, matching the session's `_buildSetProgress` layout.
- [ ] The `_buildSetControls` bottom bar shows only `[← Prev] [→ Next]` arrows, with no add/delete buttons.
- [ ] Add-set behaviour is preserved: tapping `+` calls `_addSet`, respects max cap, advances to new set.
- [ ] Remove-set behaviour is preserved: tapping `-` calls `_deleteCurrentSet` (or equivalent), respects min of 1.
- [ ] All four effort kinds (set, timed, round, drill) display correctly with the new layout.
- [ ] No regression in existing routine set-count widget/state tests.

## Scenarios

### S-001: Add set from inline control
- Trigger: User is on detail view of a routine exercise; taps `+` next to "Set 1 of 2".
- Expected: Set count increases, view advances to new set, inline counter updates.

### S-002: Remove set from inline control
- Trigger: User taps `-` next to "Set 2 of 2".
- Expected: Set count decreases, current set index clamps to valid range.

### S-003: Remove set when only 1 set remains
- Trigger: User taps `-` on "Set 1 of 1".
- Expected: Nothing happens (min guard), button appears disabled.

### S-004: Navigation arrows still work
- Trigger: User taps `←` or `→` in bottom bar.
- Expected: Set navigation advances/retreats as before.

### S-005: All effort kinds
- Trigger: Detail view for timed / round / drill / set exercises.
- Expected: Inline controls render correctly for each label variant ("Interval", "Round", "Hold", "Set").

## Iteration 1

### Analysis
`_buildDetailView` in `lib/features/routine/routine_setup_screen.dart` uses:
1. `_buildSetProgress` — currently returns plain `Text("Set X of Y")`, no inline controls.
2. A `Positioned` bottom overlay containing `_buildSetControls` — which renders
   `[← Prev] | [+ Add Set icon] [🗑️ Delete Last Set icon] | [→ Next]`.

The live session's `workout_session_detail_view.dart` uses:
1. `_buildSetProgress` — renders `[-] Set X of Y [+]` inline row (remove left, add right).
2. `_buildSetControls` — renders `[← Back] | [Log Set CTA] | [→ Next]`; in edit mode renders `[← Back] | [→ Next]` only.

Since routines set targets (not log), the analog of "edit mode" is correct: nav arrows only at the bottom.

### DB Changes
- None.

### Backend Changes
- None. Existing `addSetForEffort` and `removeLastSetForEffort` on `RoutineState` are reused.
- The remove action in the inline control should remove the **last** set (not "current" set), consistent with existing `_deleteLastSet` behaviour. If current set is removed implicitly, clamp `_currentSet` to `setCount - 1`.

### Frontend Changes (all in `lib/features/routine/routine_setup_screen.dart`)

**1. Update `_buildSetProgress` (inside the extension on `_RoutineSetupScreenState`)**

Replace the current plain-`Text` implementation with the session-parity inline row:
```
Row(
  mainAxisAlignment: MainAxisAlignment.center,
  children: [
    // Minus — remove last set (low prominence)
    InkWell(
      onTap: setCount > 1 ? () => _deleteLastSet(effort) : null,
      customBorder: CircleBorder(),
      child: Container(
        constraints: BoxConstraints(minWidth: 50, minHeight: 50),
        alignment: Alignment.center,
        child: Icon(Icons.remove, size: 24,
          color: setCount > 1
            ? theme.colorScheme.onSurface.withAlpha((0.35 * 255).round())
            : theme.colorScheme.onSurface.withAlpha((0.15 * 255).round())),
      ),
    ),
    // Label
    Text(label, style: ...),
    // Plus — add set (primary colour)
    InkWell(
      onTap: canAddSet ? () => _addSet(effort) : null,
      customBorder: CircleBorder(),
      child: Container(
        constraints: BoxConstraints(minWidth: 50, minHeight: 50),
        alignment: Alignment.center,
        child: Icon(Icons.add, size: 24,
          color: canAddSet
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurface.withAlpha((0.2 * 255).round())),
      ),
    ),
  ],
)
```

The signature of `_buildSetProgress` needs updating to accept `effort` and `canAddSet`:
```dart
Widget _buildSetProgress(
  int totalEntries,
  TemplateEffort effort,
  bool canAddSet,
  ThemeData theme,
)
```

Update the call site inside `_buildDetailView` to pass `effort` and `canAddSet`.

**2. Update `_buildSetControls` (inside the extension on `_RoutineSetupScreenState`)**

Replace the current three-section row (prev | add+delete | next) with navigation-only arrows matching session edit mode:
```dart
Widget _buildSetControls(int totalEntries, TemplateEffort effort) {
  return Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      _buildArrowButton(
        icon: Icons.arrow_back,
        label: 'Previous Set',
        isEnabled: _currentSet > 1,
        onPressed: _currentSet > 1 ? _previousSet : null,
      ),
      _buildArrowButton(
        icon: Icons.arrow_forward,
        label: 'Next Set',
        isEnabled: _currentSet < totalEntries,
        onPressed: _currentSet < totalEntries ? _nextSet : null,
      ),
    ],
  );
}
```

The `effort` parameter may still be kept in the signature for forward compatibility but is no longer used inside `_buildSetControls`.

**3. `_deleteCurrentSet` vs `_deleteLastSet`**

The session screen has `_deleteCurrentSet` (removes the currently displayed set). The routine screen has `_deleteLastSet` (always removes the last set). To keep parity with session behaviour, rename and refactor `_deleteLastSet` to remove the **current** set's slot if it is the last, otherwise keep removing the last. This is a minor behaviour change worth aligning. If the current set is not the last, disable the `-` button (simpler, safer). **Decision:** disable `-` unless `_currentSet == setCount` (i.e. only allow removing the last set), which is consistent with the existing implementation and prevents accidental mid-set deletion. This is documented as a known deviation from the session's `_deleteCurrentSet` until a future iteration.

### Implementation Steps
1. [ ] Update `_buildSetProgress` signature and body to render `[-] label [+]` inline.
2. [ ] Update the call site in `_buildDetailView` (pass `effort` and `canAddSet`).
3. [ ] Replace body of `_buildSetControls` with navigation-only arrows.
4. [ ] Verify `_addSet` / `_deleteLastSet` wiring is correct from the new inline controls.
5. [ ] Run existing routine-related tests to confirm no regressions.
6. [ ] Manually verify on simulator all four effort kinds display correctly.

### Files Affected
- `lib/features/routine/routine_setup_screen.dart` — all changes

### Notes
- No new dependencies, no state changes, no repository changes.
- Tests covering set-count discoverability (`screen_widget_test.dart`) should still pass; the add-set affordance is now inline in the set progress row rather than in a separate bottom widget.
- If tests assert on the bottom-bar icons (`Icons.playlist_add`, `Icons.delete_outline`), those assertions will need to be updated to the new inline location.

## Progress
- [x] Update `_buildSetProgress` — inline `[-] label [+]`
- [x] Update call site in `_buildDetailView`
- [x] Replace `_buildSetControls` body — navigation only
- [x] Remove dead `_buildIconButton` helper
- [x] Run routine/widget tests — 773/773 green
- [x] All effort kinds display correctly (label variants: Set/Interval/Round/Hold)

## Feedback

