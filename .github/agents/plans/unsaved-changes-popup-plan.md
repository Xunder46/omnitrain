# Feature: unsaved-changes-popup

## Overview
Fix the unsaved-edits confirmation popup so actions do not stack or overflow horizontally, and replace the current "Keep editing" CTA with a compact top-right close (X) action that keeps editing behavior.

## Requirements
- Popup actions must fit reliably across common widths without button overlap/stacking artifacts.
- "Keep editing" must be represented as a top-right close icon button (X).
- "Discard" and "Save" actions must remain clear, tappable, and visually stable.
- Dialog behavior must be unchanged functionally:
  - Close/X dismisses dialog and returns to editing.
  - Discard performs existing discard path.
  - Save performs existing save path.
- Works consistently on web and native form factors with existing repository pattern.

## Iteration 1

### DB Changes (@dba)
1. [ ] No schema changes required.
2. [ ] No repository changes required.

### Backend Changes (@developer)
1. [ ] Verify dialog action callbacks map to existing state methods without behavioral changes.
2. [ ] Keep close/X path equivalent to prior "Keep editing" dismiss semantics.
3. [ ] Ensure no new side effects in save/discard flow ordering.

### Frontend Changes (@developer)
1. [ ] Refactor unsaved-edits popup layout to avoid horizontal overflow at narrow widths.
2. [ ] Replace text CTA "Keep editing" with top-right icon close control (X).
3. [ ] Keep primary actions in footer row with robust responsive behavior:
   - Use layout that avoids overlap and preserves minimum tap targets.
   - Preserve visual priority between Discard and Save.
4. [ ] Confirm spacing/alignment consistency with existing dialog styling.
5. [ ] Ensure accessibility labels/tooltips for close icon and action buttons.

### Implementation Steps
1. [ ] Locate unsaved-edits dialog/popup widget and all invocation points.
2. [ ] Remove "Keep editing" action button from the footer action group.
3. [ ] Add top-right close icon button in dialog header/chrome that triggers `Navigator.pop` (or equivalent existing dismiss callback).
4. [ ] Update action row layout to handle tight widths (responsive row/wrap/flexible strategy) while keeping Discard and Save readable.
5. [ ] Validate no clipping/overlap for at least small-phone and desktop dialog widths.
6. [ ] Add or update widget tests for:
   - X close dismisses dialog and preserves edits.
   - Discard callback invoked correctly.
   - Save callback invoked correctly.
   - Buttons remain visible and non-overlapping in constrained width scenario.
7. [ ] Run existing widget tests related to workout/session edit flow for regressions.

### Acceptance Criteria
- [ ] Unsaved-edits popup never shows stacked/overlapping action buttons at expected app widths.
- [ ] "Keep editing" text button is removed.
- [ ] A top-right X close button exists and dismisses to editing state.
- [ ] Discard and Save remain present, functional, and visually stable.
- [ ] Accessibility labels exist for the icon close control.
- [ ] Web behavior is validated; implementation remains platform-agnostic.

### Files Affected
- lib/features/session/workout_session_screen.dart
- lib/widgets/** (if dialog is extracted/shared)
- test/widget_test.dart
- test/** (dialog-specific widget tests)

### Notes
- Keep implementation minimal and focused on layout/controls only; do not change business semantics.
- If dialog is reused in multiple flows, ensure all flows inherit the same fixed layout.

## Progress
- [x] Confirm dialog source location and current layout constraints
- [x] Implement close icon and action row layout fix
- [x] Add constrained-width widget test coverage
- [ ] Run regression tests for edit/save/discard flow

## Feedback
<!-- Leave empty until a specialist or reviewer adds notes -->

---

@developer - Please proceed with Iteration 1 (Logic/UI) above. No DBA changes are required for this fix.
