# Feature: Crown Control and Tap-to-Edit for Editable Metrics

## Overview

Replace the hidden drag-on-number interaction on the active workout screen's editable
metrics with an explicit crown control and a tap-to-edit popup for exact numeric entry.
This is a pure UI/interaction change. No data models, repository methods, or business
logic change. The existing `onValueChanged` callback paths in `InlineMetricEditor` are
reused unchanged.

## Requirements

- Each editable metric row gets its own crown widget on the right side.
- Dragging on the crown adjusts the value through the existing adjustment path.
- Crown rotates proportionally to drag (~2x travel), stops immediately on release.
- No momentum, no idle/looping animation, no post-release value change.
- Tapping the metric number opens a popup with a free-entry numeric field.
- Popup pre-fills with the current value, selects all text, has confirm and cancel.
- Confirm applies the typed value; cancel leaves the value unchanged.
- Crowns are equal visual weight regardless of emphasis tier (dominant vs secondary).
- Number size and styling are unchanged.
- Behaviour is identical on:
  - Active free sessions (`WorkoutSessionScreen`, live mode)
  - Routine-driven sessions (`WorkoutSessionScreen`, live mode, intent='routine')
  - Routine creation/editing (`RoutineSetupScreen`)

## Acceptance Criteria

- [ ] Each editable metric (reps, weight, extra-weight on load-capable timed/drill) has its own crown on the right side of its row.
- [ ] Crowns are equal visual weight regardless of emphasis tier.
- [ ] Dragging on the crown changes the value via existing `onValueChanged`; dragging the number no longer scrubs.
- [ ] Crown rotates only while dragged (~2x finger travel), stops immediately on release; no idle/looping animation.
- [ ] No momentum: releasing finger stops value changes; a flick does not continue changing the value.
- [ ] Tapping the number opens a popup pre-filled with the current value, selected for overwrite.
- [ ] Popup has explicit Confirm and Cancel; Confirm applies typed value, Cancel leaves value unchanged.
- [ ] Metric number size and styling are unchanged.
- [ ] Works identically on active free session, routine-driven session, and routine creation surfaces — verified per surface in tests.
- [ ] No change to rest timer, navigation, session lifecycle, or business logic.
- [ ] `OmniTheme` tokens only — no hardcoded colors.
- [ ] All new buttons/dialogs have explicit `shape:` overrides (no StadiumBorder).

## Scenarios

Populated by Developer agent during Phase 0.

---

## Iteration 1

### Analysis

**Current state of `InlineMetricEditor`**

`InlineMetricEditor` (`lib/widgets/session/inline_metric_editor.dart`, ~238 lines)
is a `StatefulWidget` backed by a single `GestureDetector`. It handles:
- `onVerticalDragUpdate` — scrub surface (drag on the number itself)
- `onVerticalDragEnd` — reset accumulated delta
- `onTap` — optional pass-through (used for timer toggle on timed/round/drill)

The drag logic accumulates `_accumulatedDelta` and fires `onValueChanged` every 10px.
Value clamping and stepping logic lives in `_calculateNewValue()`.

**Target surfaces**

| Surface | File | Editable metrics |
|---------|------|-----------------|
| Session detail — set | `workout_session_detail_view.dart` | reps (dominant), weight (secondary) |
| Session detail — timed | `workout_session_detail_view.dart` | extra-weight via `_buildWeightAdjustmentSection` |
| Session detail — drill | `workout_session_detail_view.dart` | extra-weight via `_buildWeightAdjustmentSection` |
| Routine setup — set | `routine_setup_screen.dart` | reps (dominant), weight (secondary) |
| Routine setup — timed | `routine_setup_screen.dart` | extra-weight (secondary) |
| Routine setup — drill | `routine_setup_screen.dart` | extra-weight (secondary) |

Round efforts have no user-adjustable numeric metric (duration is set before starting and uses `InlineMetricEditor` in edit mode only, not in live mode). Crown is not required for round/timed timer display — those are read-only (tap to toggle timer, not to edit a value). Crown is only required for editable metrics with a `onValueChanged` that changes a numeric target.

**What changes in `InlineMetricEditor`**

1. Remove `onVerticalDragUpdate` and `onVerticalDragEnd` from the outer `GestureDetector`
   (the number is no longer the scrub surface).
2. The outer `GestureDetector` keeps `onTap` for timer-toggle passthrough.
3. Wrap the number+unit display in a `GestureDetector` with `onTap` calling
   `_showEditPopup()` when the editor is not read-only.
4. Add a `MetricCrownWidget` to the right of the number+unit column.
5. The crown receives the same `onValueChanged` and the metric step/clamp parameters
   (forwarded from `InlineMetricEditor`'s existing `metricType`).

**`MetricCrownWidget`** (new file: `lib/widgets/session/metric_crown_widget.dart`)

A `StatefulWidget` that:
- Paints a custom crown silhouette (thick vertical wheel, edge-on profile, ridges)
  using `CustomPainter`.
- Handles `onVerticalDragUpdate` — fires value changes via `onValueChanged`, and
  accumulates rotation angle: `angle += delta.dy * 2 * (pi / pixelsPerRev)` where
  `pixelsPerRev` is a tuning constant (default 120px).
- Handles `onVerticalDragEnd` — stops rotating (sets `_isDragging = false`), does
  NOT continue changing values.
- Uses `Transform.rotate` on the painted crown to show the accumulated rotation.
- Exposes `metricType` so it can look up increments from the same table already in
  `InlineMetricEditor._calculateNewValue`.

The crown painter draws:
- A rounded-rectangle profile (thick, dark fill, slightly lighter border).
- Horizontal ridges (evenly spaced horizontal lines across the wheel face),
  rotated with the wheel.
- All colours from `OmniTheme` tokens (`textMuted` for the body, `textSecondary`
  for the ridges, consistent regardless of emphasis tier).

**`MetricEditPopup`** (new file: `lib/widgets/session/metric_edit_popup.dart`
OR implemented as a reusable `showDialog`-based function)

An `AlertDialog` with:
- Title: derived from `unitLabel` (e.g., "Edit Reps", "Edit Weight").
- Body: a `TextField` with `keyboardType: TextInputType.numberWithOptions(decimal: true)`,
  pre-filled with the formatted current value, text selected on first focus.
- Confirm action (`FilledButton`): parses input, clamps to metric range, calls
  `onValueChanged`, closes dialog.
- Cancel action (`TextButton`): closes dialog without calling `onValueChanged`.
- Both buttons have explicit `shape: RoundedRectangleBorder(...)` overrides.
- Uses `NumericFieldWithDoneBar` as the field implementation to get the "Done" bar
  on native platforms (web degrades safely).

### DB Changes

None. This is a pure UI change.

### Backend Changes

None. No state classes, repository methods, or models change.

### Frontend Changes

1. New widget: `lib/widgets/session/metric_crown_widget.dart`
2. New helper (or static function in the same file): `showMetricEditPopup(...)` — returns `Future<dynamic>`.
3. Modified widget: `lib/widgets/session/inline_metric_editor.dart`
   - Remove drag-on-number gesture handlers.
   - Add tap-on-number gesture calling `showMetricEditPopup`.
   - Compose `MetricCrownWidget` to the right of the value+unit column (only when not `isReadOnly`).
   - Row layout: `[value+unit column] [SizedBox(width: 8)] [MetricCrownWidget]`
4. Test file: `test/crown_control_tap_to_edit_test.dart` (all new tests).
5. Modified test: `test/interaction_flow_test.dart`
   - Update "weight drag increments by 0.5" — drive the `MetricCrownWidget`, not `InlineMetricEditor` directly.
   - Update "extra-weight drag" similarly.
   - Update "fast weight drag" and "fast extra-weight drag" — use crown's drag update handler.
6. Modified test: `test/resistance_emphasis_redesign_test.dart`
   - Any test that drives `onVerticalDragUpdate` on `InlineMetricEditor` must target the crown widget instead.

### Implementation Steps

#### Phase 1 — `MetricCrownWidget` standalone widget

1. [ ] Create `lib/widgets/session/metric_crown_widget.dart`.
2. [ ] Implement `_CrownPainter extends CustomPainter`:
   - `size`: `width = 28, height = 56` (fixed, not taking available space).
   - Body: `RoundedRectangle` with `rx = 6`, filled with `OmniTheme.colors.textMuted` at 20% opacity, stroked with `OmniTheme.colors.textSecondary` at 30% opacity, stroke width 1.5.
   - Ridges: 6 horizontal lines drawn in the body, evenly spaced (top, middle, bottom cluster), color `OmniTheme.colors.textSecondary` at 40% opacity, stroke width 1.
   - Ridges are painted in the painter's local coordinate space; `Transform.rotate` wraps the whole `CustomPaint` so ridges appear to rotate with the wheel.
3. [ ] Implement `MetricCrownWidget` props: `metricType`, `currentValue`, `onValueChanged`.
4. [ ] Implement drag state: `_isDragging`, `_accumulatedDelta`, `_rotationAngle` (radians).
5. [ ] `onVerticalDragUpdate`: accumulate `details.delta.dy`; fire `onValueChanged` using the same 10px-per-step logic from `InlineMetricEditor._calculateNewValue` (extract this logic to a shared static method `MetricStepCalc.calculate(metricType, currentValue, deltaY)`); update `_rotationAngle += details.delta.dy * _kRotationFactor` where `_kRotationFactor = 2 * pi / 120`.
6. [ ] `onVerticalDragEnd`: reset `_accumulatedDelta = 0`; set `_isDragging = false`; do NOT reset `_rotationAngle` (keeps position until next drag, feels natural); `setState` to stop any pending redraws.
7. [ ] No `AnimationController`, no `Timer`, no looping — crown only moves during active drag.
8. [ ] Widget size: wrap in `SizedBox(width: 44, height: 60)` for touch target compliance; `CustomPaint` centered within.

#### Phase 2 — `showMetricEditPopup` helper

9. [ ] Create (or add to `metric_crown_widget.dart`) a top-level async function `showMetricEditPopup`:
   ```
   Future<dynamic> showMetricEditPopup(
     BuildContext context, {
     required String metricType,
     required dynamic currentValue,
     required String unitLabel,
     required Function(dynamic) onValueChanged,
   })
   ```
10. [ ] Inside, call `showDialog` with an `AlertDialog`.
11. [ ] Title text: `'Edit ${_titleForMetric(metricType)}'` (e.g., "Edit Reps", "Edit Weight").
12. [ ] Field: `NumericFieldWithDoneBar` (import from `lib/widgets/inputs/numeric_field_with_done_bar.dart`), `keyboardType: TextInputType.numberWithOptions(decimal: true)`, controller pre-populated with formatted current value.
13. [ ] On dialog open, schedule `controller.selection = TextSelection(baseOffset: 0, extentOffset: controller.text.length)` via `WidgetsBinding.instance.addPostFrameCallback`.
14. [ ] Confirm `FilledButton`: parse typed text → call `_parseAndClamp(metricType, text)` → call `onValueChanged(result)` → `Navigator.pop(context)`. If text is empty or unparseable, do not call `onValueChanged` and pop (treat as cancel).
15. [ ] Cancel `TextButton`: `Navigator.pop(context)` with no `onValueChanged` call.
16. [ ] Both buttons: `shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(OmniTheme.buttonUtilityRadius))`.
17. [ ] Confirm `FilledButton` style: `shape` override + default filled styling (primary color).
18. [ ] `_parseAndClamp`: parse as `double`, round to `int` for `reps`, clamp to metric range (0–999 reps, 0.0–999.0 weight, -100.0–200.0 extra-weight). Return typed value matching the metric (`int` for reps, `double` for weight/extra-weight). Return `null` if unparseable (then caller does not call `onValueChanged`).

#### Phase 3 — Modify `InlineMetricEditor`

19. [ ] Extract `_calculateNewValue` logic (the step/clamp math) to a top-level or static function `MetricStepCalc.apply(String metricType, dynamic currentValue, double deltaY)` in its own small utility file or at the top of `metric_crown_widget.dart` (developer's choice — just keep it accessible by both widgets without creating a circular import). The function signature matches the existing behaviour exactly.
20. [ ] Remove `onVerticalDragUpdate` and `onVerticalDragEnd` from the outer `GestureDetector` in `InlineMetricEditor.build()`. The outer `GestureDetector` retains `onTap` only.
21. [ ] Wrap the value+unit display (the `Column` or `Row` currently inside the `GestureDetector`) in a separate `GestureDetector` with:
    - `onTap: isReadOnly ? null : () => showMetricEditPopup(context, ...)`.
22. [ ] Add `MetricCrownWidget` to the right of the value+unit column. Layout becomes a `Row`:
    ```
    Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // existing value+unit column (now with its own tap gesture for popup)
        if (!isReadOnly) ...[
          const SizedBox(width: 8),
          MetricCrownWidget(
            metricType: widget.metricType,
            currentValue: widget.currentValue,
            onValueChanged: widget.onValueChanged,
          ),
        ],
      ],
    )
    ```
23. [ ] Keep existing `padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 32)` on the outer container — the crown sits inside this padding, within the row.
24. [ ] Keep `isReadOnly` suppressing both the crown and the tap-to-edit popup (read-only = no editable affordances).
25. [ ] The `emphasisTier` of the crown is always the same neutral styling (`textMuted`/`textSecondary`) regardless of whether the parent editor is dominant or secondary. Do not derive crown colour from `emphasisTier`.

#### Phase 4 — Surface verification (no code changes expected, but must be checked)

26. [ ] Verify `WorkoutSessionScreen` detail view (free session) — `_buildMetricWidget` for `effortKind == 'set'` passes editable `InlineMetricEditor` instances with `isReadOnly: false` (current state); crown and popup will appear automatically.
27. [ ] Verify `WorkoutSessionScreen` detail view (routine session, intent='routine') — same `_buildMetricWidget` path, same result.
28. [ ] Verify `RoutineSetupScreen._buildMetricWidget` for `effortKind == 'set'`, `timed`, `drill` — same `InlineMetricEditor` usage, crown and popup appear automatically.
29. [ ] Verify `_buildWeightAdjustmentSection` (timed and drill weight adjustment) uses `InlineMetricEditor` — crown and popup appear automatically inside the expanded section.
30. [ ] Verify that `timed`, `round`, and `drill` timer display editors (`isReadOnly: true`) do NOT show a crown and do NOT open a popup on tap (read-only guard from step 24 covers this).
31. [ ] Verify edit mode (`editMode: true` in `WorkoutSessionScreen`) — the `InlineMetricEditor` instances in edit mode already use `onTap` for `_showDurationEntryDialog`; the tap-to-edit popup must NOT fire for duration fields in edit mode. Audit: in edit mode, duration editors already pass `onTap: () async { ... }` directly — the existing `onTap` on the outer GestureDetector will fire. The inner value-display tap (step 21) should only wire `showMetricEditPopup` for non-read-only editors that do NOT already have an `onTap` provided. Solution: add a `bool suppressTapToEdit` prop (default `false`) OR check: if `widget.onTap != null`, the number tap calls `widget.onTap` instead of `showMetricEditPopup`. This preserves the edit-mode duration tap behaviour.

    **Decision for step 31**: Add a `tapToEditEnabled` parameter (default `true`, set to `false` by callers that provide their own `onTap` for timer toggle/edit mode). Alternatively, detect via `widget.onTap != null` — if provided, tap the number calls `widget.onTap`; if not provided and `!isReadOnly`, tap calls `showMetricEditPopup`. The developer should pick whichever results in the cleanest code; document the choice in a code comment.

#### Phase 5 — Tests

32. [ ] Create `test/crown_control_tap_to_edit_test.dart`:

    **Crown widget tests:**
    - [ ] T-01: Widget test — `InlineMetricEditor` (reps, not read-only) renders a `MetricCrownWidget` in its subtree.
    - [ ] T-02: Widget test — `InlineMetricEditor` (weight, not read-only) renders a `MetricCrownWidget`.
    - [ ] T-03: Widget test — both reps and weight `InlineMetricEditor` instances in the same widget tree each render exactly one `MetricCrownWidget`; crowns are the same type regardless of emphasis tier.
    - [ ] T-04: Widget test — `InlineMetricEditor` with `isReadOnly: true` does NOT render a `MetricCrownWidget`.
    - [ ] T-05: Widget test — drag on `MetricCrownWidget` (reps) calls `onValueChanged`; drag on the number `Text` does NOT call `onValueChanged` (no vertical drag handler on the number).
    - [ ] T-06: Widget test — drag on `MetricCrownWidget` (weight) calls `onValueChanged`.
    - [ ] T-07: Widget test — `MetricCrownWidget` rotation angle changes during drag and does not change after drag ends (access `_rotationAngle` via state or key).
    - [ ] T-08: Widget test — after drag ends (via `onVerticalDragEnd`), subsequent `pump` calls do NOT produce further value changes (no momentum/post-release change).
    - [ ] T-09: Widget test — rotation magnitude is ~2x drag distance (e.g., drag 60px → rotation ~`60 * 2 * pi / 120` radians = pi radians ± small tolerance).

    **Tap-to-edit popup tests:**
    - [ ] T-10: Widget test — tapping the number Text inside an `InlineMetricEditor` (reps, not read-only, no custom `onTap`) opens a dialog with a `TextField` pre-filled with the current value.
    - [ ] T-11: Widget test — confirming the popup with a valid number calls `onValueChanged` with the parsed value.
    - [ ] T-12: Widget test — cancelling the popup does NOT call `onValueChanged`.
    - [ ] T-13: Widget test — popup dialog has explicit confirm and cancel buttons.

    **Surface verification tests (per-surface, minimal, confirming crown presence):**
    - [ ] T-14: Widget test — `WorkoutSessionScreen` in live mode (free session, `effortKind == 'set'`) detail view renders `MetricCrownWidget` instances.
    - [ ] T-15: Widget test — `WorkoutSessionScreen` in live mode (routine session, intent='routine', `effortKind == 'set'`) detail view renders `MetricCrownWidget` instances.
    - [ ] T-16: Widget test — `RoutineSetupScreen` (`effortKind == 'set'`) exercise detail renders `MetricCrownWidget` instances.

33. [ ] Update `test/interaction_flow_test.dart`:
    - 'weight drag increments by 0.5' — find `MetricCrownWidget` (or its internal `GestureDetector` keyed by a `Key('crown-metric-${metricType}')`) and drive `onVerticalDragUpdate` on it, not on `InlineMetricEditor` directly.
    - 'extra-weight drag increments by 0.5' — same.
    - 'fast weight drag still snaps to 0.5 increments' — drive crown's drag handler.
    - 'fast extra-weight drag still snaps to 0.5 increments' — drive crown's drag handler.

34. [ ] Update `test/resistance_emphasis_redesign_test.dart`:
    - Any test that accesses `GestureDetector.onVerticalDragUpdate` from the `InlineMetricEditor` subtree must be redirected to use the crown's handler. The tests that check emphasis tier colours on `Text` widgets are unaffected (no change to text styling).

## Progress

- [x] T-01 through T-17 new tests (37 total — all passing)
- [x] Update interaction_flow_test drag tests (4 tests → crown target)
- [x] Update resistance_emphasis_redesign_test — no drag-target changes needed (tests unaffected)
- [x] Update session_toolbar_rework_test — 'vertical metric drag' test redirected to crown
- [x] MetricStepCalc extraction (lib/widgets/session/metric_crown_widget.dart)
- [x] MetricCrownWidget with CustomPainter (_CrownPainter, 6 ridges, OmniTheme tokens)
- [x] showMetricEditPopup helper (StatefulWidget dialog with proper controller lifecycle)
- [x] InlineMetricEditor modified (drag removed, tap-to-edit added, crown composed)
- [x] Surface verification: live free session, live routine session, routine setup — all show crowns
- [x] Bug fix: round live-mode InlineMetricEditor missing isReadOnly:true — added to preserve timer-toggle GestureDetector behavior
- [x] docs/widget_catalog.md updated (InlineMetricEditor, MetricCrownWidget, showMetricEditPopup, MetricStepCalc entries)

### Test results (full suite)
- 1055 tests — ALL PASSING
- New tests in crown_control_tap_to_edit_test.dart: 37/37 pass
- Updated tests in interaction_flow_test.dart: 4 drag tests pass
- Updated tests in session_toolbar_rework_test.dart: 1 drag test passes
- resistance_emphasis_redesign_test.dart: 5/5 pass (unchanged)
- widget_test.dart: all pass (round timer pause bug fixed)

### Files changed
- NEW: lib/widgets/session/metric_crown_widget.dart
- NEW: test/crown_control_tap_to_edit_test.dart
- MODIFIED: lib/widgets/session/inline_metric_editor.dart
- MODIFIED: lib/features/session/workout_session_detail_view.dart (round live isReadOnly:true)
- MODIFIED: test/interaction_flow_test.dart
- MODIFIED: test/session_toolbar_rework_test.dart
- MODIFIED: docs/widget_catalog.md

### Phase status: **Complete**

## Files Affected

**New:**
- `lib/widgets/session/metric_crown_widget.dart` — `MetricCrownWidget` + `_CrownPainter` + `MetricStepCalc` static helper + `showMetricEditPopup` function
- `test/crown_control_tap_to_edit_test.dart`

**Modified:**
- `lib/widgets/session/inline_metric_editor.dart` — remove drag, add tap-to-edit, compose crown
- `test/interaction_flow_test.dart` — redirect drag tests to crown widget
- `test/resistance_emphasis_redesign_test.dart` — redirect any drag-target references

**Unchanged (verified, no edit needed):**
- `lib/features/session/workout_session_detail_view.dart` — InlineMetricEditor usages unchanged
- `lib/features/routine/routine_setup_screen.dart` — InlineMetricEditor usages unchanged
- All state files, repository files, and data models

## Feedback

### Code Review (verdict: APPROVE)

Reviewed against acceptance criteria, conventions, correctness, and test quality.
Ran `flutter analyze` and the affected test suites independently to confirm claims.

**Verdict: APPROVE — no blocking issues.**

Verified:
- Value-adjustment math preserved exactly. Diffed `MetricStepCalc.apply` against the
  original `_calculateNewValue` at `HEAD`: identical (only `final`→`const` on the
  increment literal). Bounds/steps unchanged. The dedicated `MetricStepCalc` unit
  tests cover reps/weight/extra-weight stepping and clamping.
- Crown is the sole scrub surface; drag handlers removed from `InlineMetricEditor`.
  Old drag-on-number tests in `interaction_flow_test.dart` / `session_toolbar_rework_test.dart`
  correctly redirected to drive the crown.
- No momentum (T-08), rotation stops on release (T-07), ~2× rotation with tolerance (T-09).
  No `AnimationController`/`Timer`/idle animation in `MetricCrownWidget`.
- Tap-to-edit popup pre-fills + selects, explicit Confirm (`FilledButton`) / Cancel
  (`TextButton`) with explicit `shape:` overrides; confirm applies, cancel no-ops
  (T-10–T-13). Signed/`+`/`-0` parsing + clamping covered.
- `onTap` delegation: number tap calls custom `onTap` when provided (edit-mode duration
  dialog), else generic popup; inner opaque gesture prevents double-fire with outer (T-10b).
- Crown is neutral, equal-weight by construction (no emphasis/color param); T-03.
- Read-only suppression: no crown/popup when `isReadOnly` (T-17). Round live-timer
  `isReadOnly: true` addition is correct and necessary (prevents the new inner
  tap/crown from hijacking the timer toggle); no visual regression since it passes
  `emphasisTier: dominant`, so the dimming branch does not fire.
- All three surfaces mounted with real screens and asserted (T-14 free, T-15 routine
  intent, T-16 routine setup). Duration-editable-in-routine-setup confirmed.
- Full suite: 1055 passing.

**Non-blocking nits (lint only — `flutter analyze`):**
1. `test/crown_control_tap_to_edit_test.dart` — two unused imports
   (`routine_session_service.dart`, `data/models/models.dart`) [warning].
2. `test/crown_control_tap_to_edit_test.dart:551` — local `_navigateToSetDetail`
   has a leading underscore (`no_leading_underscores_for_local_identifiers`) [info].
3. `test/interaction_flow_test.dart:30` and `test/session_toolbar_rework_test.dart:11`
   — unnecessary explicit import of `metric_crown_widget.dart` (re-exported by
   `inline_metric_editor.dart`) [info].

None of these affect behavior or block merge. The `withOpacity` deprecation flagged
mid-run at `workout_session_detail_view.dart:910` is NOT attributable to this change
(the file diff is only the 4-line `isReadOnly` addition) and does not appear in
`flutter analyze`; treat as pre-existing.
