# Plan: Tap-to-Edit Metric Modal (Crown Removal)

## Overview

This is a UI-only simplification for v1 launch. The Phase 5 crown scrub control
is hidden from all user-facing surfaces (not deleted). Tapping a metric number
becomes the only way to change a value: it opens a small numeric-entry modal
(the existing `showMetricEditPopup` / `_MetricEditDialog`), which pre-fills with
the current value and has explicit Confirm / Cancel actions.

The crown widget (`MetricCrownWidget`) and all its scrub logic remain in the
codebase dormant and reintroducible. No value-math, bounds, step increments,
or business logic changes.

Three surfaces must be verified: the **active session screen**
(`WorkoutSessionScreen` live + edit modes), the **routine maker**
(`RoutineSetupScreen`), and the **historical session editor**
(`WorkoutSessionScreen` in `editMode: true` — which is already the "historical
session editor" in the current architecture).

The `weight` metric's `parseAndClamp` currently clamps at `0.0`, but the feature
request says negative load must be accepted for assisted movements. This is
noted as a bounds change that must be made to `parseAndClamp` for `'weight'`.
The drag-step `apply` already clamps weight at 0, which is fine for the crown
(dormant); the modal path uses `parseAndClamp`, which is where the fix belongs.

---

## Analysis of Current State

### What already exists
- `showMetricEditPopup` / `_MetricEditDialog` — a fully working numeric modal,
  living in `lib/widgets/session/metric_crown_widget.dart`. Already handles:
  - Pre-fill with current value (all metric types)
  - Confirm / Cancel actions
  - `MetricStepCalc.parseAndClamp` for parsing + clamping
  - `signed: true, decimal: true` keyboard
- `InlineMetricEditor` — already has tap-to-edit logic (`_onNumberTap`), which
  calls `showMetricEditPopup` when `onTap` is null and `!isReadOnly`.
- Crown is rendered only when `!isReadOnly` via the `if (!widget.isReadOnly)`
  guard in `InlineMetricEditor.build`.

### What must change
1. **Hide crown from render tree** — `InlineMetricEditor` must stop rendering
   `MetricCrownWidget`. The class and its logic stay; only the render condition
   changes. The `isReadOnly` guard currently gates both crown and tap-to-edit;
   a new `showCrown` flag (defaulting `false`) is the cleanest approach, or the
   crown block is simply removed from the row while keeping tap-to-edit active.
2. **Weight modal must accept negative values** — `parseAndClamp` clamps
   `'weight'` to `clamp(0.0, 999.0)`. This must change to allow negative values
   for assisted load (e.g. `-50.0` for a -50 lb machine assist). A reasonable
   lower bound matching the extra-weight range: `-200.0` (or the same `-100.0`
   as extra-weight — see implementation note below). The keyboard already uses
   `signed: true`.
3. **Update widget_catalog.md** — the doc still says the crown is on the right
   of the value; update the `InlineMetricEditor` entry to reflect that the crown
   is dormant and tap-to-edit is the sole interaction path.
4. **Update tests** — Phase 5 tests in `crown_control_tap_to_edit_test.dart`
   assert the crown IS rendered (T-01, T-02, T-03, T-14, T-15, T-16, plus the
   duration-gets-crown group). Those must flip to assert the crown is NOT
   rendered. Tests for value-change via crown drag must be rewritten to drive
   the tap-to-edit modal instead. Value math tests (`MetricStepCalc`) are
   unchanged. `interaction_flow_test.dart` has tests that drive `MetricCrownWidget`
   directly — those must be updated. `session_toolbar_rework_test.dart` has one
   test (`vertical metric drag updates value`) that uses `MetricCrownWidget`;
   that must be updated to drive the modal.

### Bounds decision for negative weight
The feature request says "the weight/load metric ... must permit a minus sign so
negative values can be entered." The existing `extra-weight` range is `-100.0`
to `200.0`. A symmetric or similarly generous bound for `weight` is appropriate:
`-200.0` to `999.0` keeps max headroom for heavy loads and allows full assisted
range. This is a `parseAndClamp` change only (the drag-step clamping is for the
dormant crown and is left as-is to avoid risk).

---

## Files to Change

### 1. `lib/widgets/session/inline_metric_editor.dart`
- Remove the `MetricCrownWidget` from the row in `build`. Specifically, remove
  the `if (!widget.isReadOnly) ...[SizedBox(8), MetricCrownWidget(...)]` block
  from `contentRow`.
- The tap-to-edit `GestureDetector` on the value (the `tappableValue` block)
  stays exactly as-is — no change to `_onNumberTap`.
- The `export` line re-exporting `MetricCrownWidget` stays (keeps it importable
  from tests).
- No prop changes required; the crown rendering is simply not included in the
  widget tree.

### 2. `lib/widgets/session/metric_crown_widget.dart`
- `parseAndClamp`: change `'weight'` case from `clamp(0.0, 999.0)` to
  `clamp(-200.0, 999.0)` so negative assisted-load values are accepted.
- All other code (drag logic, `MetricCrownWidget`, `_CrownPainter`,
  `MetricStepCalc.apply`, `showMetricEditPopup`) is left unchanged.

### 3. `docs/widget_catalog.md`
- Update the `InlineMetricEditor` entry to say the crown is no longer rendered
  in the default interaction path (it remains in the codebase as dormant code).
- Update the interaction model section to describe tap-to-edit as the sole
  user-facing value-change mechanism.

### 4. `test/crown_control_tap_to_edit_test.dart`
Full rewrite of affected test groups. See Test Plan below for exact changes.

### 5. `test/interaction_flow_test.dart`
Update `InlineMetricEditor interactions` group and the session swipe test
that drives `MetricCrownWidget` directly. See Test Plan below.

### 6. `test/session_toolbar_rework_test.dart`
Update `vertical metric drag updates value` test. See Test Plan below.

---

## Files to Create

None. No new source files are needed; the modal already exists.

---

## Implementation Steps

### Step 1 — Bounds fix: allow negative weight in parseAndClamp
File: `lib/widgets/session/metric_crown_widget.dart`

In `MetricStepCalc.parseAndClamp`, change:
```dart
case 'weight':
  return double.parse(parsed.clamp(0.0, 999.0).toStringAsFixed(1));
```
to:
```dart
case 'weight':
  return double.parse(parsed.clamp(-200.0, 999.0).toStringAsFixed(1));
```

This is the only change to value math. The `apply` method's weight clamp at 0
stays (crown is dormant, so this is irrelevant to users but must not be deleted).

### Step 2 — Hide crown from InlineMetricEditor render tree
File: `lib/widgets/session/inline_metric_editor.dart`

Remove the crown block from the row. The `contentRow` currently is:
```dart
final contentRow = Row(
  mainAxisSize: MainAxisSize.min,
  crossAxisAlignment: CrossAxisAlignment.center,
  children: [
    tappableValue,
    if (!widget.isReadOnly) ...[
      const SizedBox(width: 8),
      MetricCrownWidget(
        metricType: widget.metricType,
        currentValue: widget.currentValue,
        onValueChanged: widget.onValueChanged,
      ),
    ],
  ],
);
```

Change to:
```dart
final contentRow = Row(
  mainAxisSize: MainAxisSize.min,
  crossAxisAlignment: CrossAxisAlignment.center,
  children: [
    tappableValue,
    // Crown is dormant (not rendered). MetricCrownWidget and its scrub logic
    // remain in the codebase at lib/widgets/session/metric_crown_widget.dart
    // and can be re-enabled here without rebuilding it.
  ],
);
```

The `export` line, imports, and all other code in the file are unchanged.

### Step 3 — Update widget_catalog.md
File: `docs/widget_catalog.md`

In the `InlineMetricEditor` section:
- Replace the description "Drag the crown (right of value) up/down to adjust;
  tap the number to open a free-entry popup." with "Tap the number to open a
  numeric-entry modal (the crown scrub control is present in the codebase but
  not rendered — see `MetricCrownWidget`)."
- Update the Interaction model bullet:
  - Remove "Crown (right of the value): vertical drag fires `onValueChanged`..."
  - Keep and clarify the Number tap bullet.
  - Note crown is dormant.
- Remove the Sensitivity table (drag increments — irrelevant while crown is not
  rendered; keep a note that it is documented in the MetricCrownWidget entry).
- Update the Visual note to remove "Crown is a 44×60 touch target on the right
  of the value+unit row."

### Step 4 — Update test/crown_control_tap_to_edit_test.dart

#### T-01, T-02, T-03 (Crown presence — currently assert crown IS rendered)
Flip to assert crown is NOT rendered:
- T-01: `expect(find.byType(MetricCrownWidget), findsNothing)` for reps editor.
- T-02: `expect(find.byType(MetricCrownWidget), findsNothing)` for weight editor.
- T-03: Two editors in same tree → `expect(find.byType(MetricCrownWidget), findsNothing)`.
  Remove the `crowns[0].runtimeType == crowns[1].runtimeType` assertion
  (no crowns to compare). Update description to "neither editor renders
  MetricCrownWidget".
- T-04: Already asserts `findsNothing` for `isReadOnly: true` — keep as-is,
  update description to note this is now true for all editors (read-only or not).

#### T-05 (Crown drag on reps calls onValueChanged)
Rewrite as tap-to-edit:
- Remove the drag-on-crown part.
- New T-05: Tapping the number opens the modal; entering a value and confirming
  calls `onValueChanged` with the parsed value. Verify dragging the number text
  does not change the value (no drag handler on it).

#### T-06 (Crown drag on weight calls onValueChanged)
Rewrite as tap-to-edit for weight:
- New T-06: Tapping the weight number opens the modal; entering `10.5` and
  confirming calls `onValueChanged` with `10.5`.

#### T-07, T-08, T-09 (Crown rotation and drag mechanics)
These test `MetricCrownWidget` directly (not through `InlineMetricEditor`). They
remain valid because the widget is still in the codebase. Keep T-07, T-08, T-09
as-is — they test the dormant widget's internal mechanics, which must not break.
Update group description to note these test the dormant crown widget directly.

#### T-10, T-11, T-12, T-13, T-10b (Tap-to-edit popup)
These are already correct and pass. Keep them as-is. T-10 verifies the dialog
opens. T-11 verifies confirm applies value. T-12 verifies cancel leaves value
unchanged. T-13 verifies button types. T-10b verifies custom `onTap` delegates.
No changes needed here.

#### T-14, T-15, T-16 (Surface verification — currently assert crown IS rendered)
Flip to assert crown is NOT rendered on each surface:
- T-14 (WorkoutSessionScreen live mode): `expect(find.byType(MetricCrownWidget), findsNothing)`.
  Additionally add a tap-to-edit assertion: tap the reps value text, verify
  `AlertDialog` appears.
- T-15 (WorkoutSessionScreen routine session): same flip + tap-to-edit check.
- T-16 (RoutineSetupScreen): same flip + tap-to-edit check.

#### T-17 (Live-mode timed editor isReadOnly: true — no crown)
Already asserts `findsNothing`. Keep as-is.

#### Duration editor gets crown group
Flip to assert duration editor (not read-only, no onTap) does NOT render
`MetricCrownWidget`. The drag test ("duration editor drag on crown changes
value") must be rewritten: either drive `MetricCrownWidget` directly (since it
is still instantiable) or replace with a tap-to-edit modal test for duration.
Recommended: replace with a tap-to-edit test: tap duration value, enter `120`,
confirm, verify `onValueChanged(120)` called.

#### Add new tests (negative weight entry)
- New T-W01: `parseAndClamp('weight', '-50.0')` returns `-50.0`.
- New T-W02: `parseAndClamp('weight', '-200.0')` returns `-200.0` (lower bound).
- New T-W03: `parseAndClamp('weight', '-999')` clamps to `-200.0`.
- New T-W04: tap weight editor, enter `-25.5`, confirm → `onValueChanged(-25.5)`.
- New T-NW01: `parseAndClamp('reps', '-5')` returns `0` (non-load metrics clamp
  at 0, negative entry is rejected by clamping).
- New T-NW02: `parseAndClamp('duration', '-10')` returns `0`.
- New T-NW03: tap reps editor, enter `-5`, confirm → `onValueChanged(0)` (the
  value is clamped to 0, not silently dropped).

#### Add new codebase-guard test
- New T-G01: Verify `MetricCrownWidget` class exists in the codebase at runtime
  (confirm it has not been deleted). This is a static existence test:
  `expect(MetricCrownWidget, isNotNull)` — or instantiate and verify type.
  A simple `expect(() => MetricCrownWidget(metricType: 'reps', currentValue: 0,
  onValueChanged: (_) {}), returnsNormally)` confirms it is constructible.

### Step 5 — Update test/interaction_flow_test.dart

#### `InlineMetricEditor interactions` group
- `weight drag increments by 0.5`: currently drags `MetricCrownWidget`.
  Rewrite as tap-to-edit: tap the value text, enter `10.5`, confirm, verify
  `updatedValue == 10.5`.
- `extra-weight drag increments by 0.5`: same pattern.
- `fast weight drag still snaps to 0.5 increments`: drive `MetricCrownWidget`
  directly (it is still in the codebase). Keep as-is but update comment to note
  this tests the dormant crown widget directly, not the inline editor's UI.
- `fast extra-weight drag still snaps to 0.5 increments`: same — keep driving
  the crown directly with a clarifying comment.

#### Session swipe test: `vertical metric drag updates value without set navigation`
This test currently drives `MetricCrownWidget` via `GestureDetector` directly.
Rewrite to use tap-to-edit:
- Navigate to detail view.
- Read `beforeReps` from `InlineMetricEditor`.
- Tap the reps value text to open the modal.
- Enter a higher value (e.g. `beforeReps + 5`).
- Tap Confirm.
- Read `afterReps` and assert `afterReps > beforeReps`.
- Assert still on `Set 1 of 2` (no navigation occurred).

### Step 6 — Update test/session_toolbar_rework_test.dart

#### `vertical metric drag updates value without set navigation`
This test drives `MetricCrownWidget` via its `GestureDetector`. Rewrite to
use tap-to-edit modal, same approach as the interaction_flow_test version above.

---

## Test Plan

### Tests to KEEP unchanged (must still pass)
- All `MetricStepCalc` unit tests (value math is not changing, except weight
  lower bound which adds new tests).
- T-07, T-08, T-09 (crown widget rotation mechanics — widget stays in codebase).
- T-10, T-11, T-12, T-13, T-10b (tap-to-edit popup — already correct).
- T-04, T-17 (read-only = no crown — still true; now universally true).
- All session toolbar rework tests except the metric-drag one.
- All scroll-to-bottom tests.
- All `InlineMetricEditor` size/style tests (none exist currently beyond what
  is covered above).

### Tests to UPDATE (flip crown-presence assertions)
- T-01, T-02, T-03: `findsWidgets` → `findsNothing`.
- T-14, T-15, T-16: `findsWidgets` → `findsNothing`, plus add tap-to-edit check.
- Duration crown group: assert `findsNothing` + replace drag test with modal test.

### Tests to REWRITE (drive modal instead of crown)
- T-05, T-06: Was crown drag → now tap-to-edit modal.
- `interaction_flow_test.dart` weight + extra-weight drag tests (the main
  tester.drag ones).
- `session_toolbar_rework_test.dart` metric drag test.
- `interaction_flow_test.dart` session swipe: vertical drag test.

### New tests to ADD
- T-W01, T-W02, T-W03 (`parseAndClamp` weight negative-value acceptance and
  lower-bound clamping).
- T-W04 (weight modal tap → negative value applied through existing logic).
- T-NW01, T-NW02, T-NW03 (non-load metrics clamp negative entry to 0).
- T-G01 (codebase guard: `MetricCrownWidget` is constructible — not deleted).
- Surface tap-to-edit consistency checks added into T-14, T-15, T-16.

### Tests explicitly NOT to change
- Set/interval/hold/period count editor tests (the `Set X of Y` stepper tests
  in `session_toolbar_rework_test.dart` and `session_detail_set_count` tests).
- Rest timer tests.
- Navigation / swipe mapping tests (except the one metric-drag test).

---

## Important Implementation Notes

1. **Do not delete any code in `metric_crown_widget.dart`**. The entire file
   stays. The only changes are `parseAndClamp` weight bounds and (optionally)
   a doc comment noting the widget is dormant in the default editor config.

2. **The `export` in `inline_metric_editor.dart`** re-exports `MetricCrownWidget`,
   `MetricStepCalc`, and `showMetricEditPopup`. Keep this export intact so tests
   can import from `inline_metric_editor.dart` as before.

3. **The `isReadOnly` prop is unchanged in meaning**. It still suppresses the
   tap-to-edit gesture. The crown is now always absent, making `isReadOnly` on
   live-timer displays relevant only for the tap-to-edit suppression, which
   continues to be the correct behavior.

4. **No changes to `workout_session_detail_view.dart` or
   `routine_setup_screen.dart`** are expected. The `InlineMetricEditor` callers
   do not need to change because the tap-to-edit was already wired
   (`_onNumberTap` calls `showMetricEditPopup` when `onTap` is null). Removing
   the crown from the render only requires changes inside `inline_metric_editor.dart`.

5. **Weight lower bound**: `-200.0` is chosen (matching the generous headroom
   on the high side). The feature request does not specify a lower bound; this
   matches a full-stack assisted machine scenario. If product wants `-100.0`
   (matching extra-weight), that is equally acceptable — developer should confirm
   with product before coding, or default to `-200.0` as a conservative choice.

6. **The `_formatCurrentValue` function in `metric_crown_widget.dart`** formats
   `weight` as `toStringAsFixed(1)`. For negative values this produces e.g.
   `-50.0`, which is correct and already accepted by `double.tryParse`.

7. **`NumericFieldWithDoneBar`** is the input field used by the modal. It
   already uses `TextInputType.numberWithOptions(signed: true, decimal: true)`,
   so the minus key is already available on all platforms. No change needed.

---

## Progress

- [x] Data layer phase: Done (no changes needed). `MetricStepCalc`/`parseAndClamp` is a widget-layer utility in `lib/widgets/session/metric_crown_widget.dart`, not in the data layer. No schema, model, repository, or Hive changes are required for this feature. The negative-weight clamp fix is a UI concern owned by the developer agent.
- [x] Step 1: Update `parseAndClamp` weight lower bound in `metric_crown_widget.dart`
- [x] Step 2: Remove crown from `InlineMetricEditor` render tree
- [x] Step 3: Update `widget_catalog.md` doc
- [x] Step 4: Update `test/crown_control_tap_to_edit_test.dart`
- [x] Step 5: Update `test/interaction_flow_test.dart`
- [x] Step 6: Update `test/session_toolbar_rework_test.dart`
- [x] Verify: all tests pass with `flutter test` (1063 tests passed)

---

## Bugs (Post-Implementation)

Two bugs were discovered after the above implementation was completed.

### Bug B-01: Modal has two buttons ("Cancel" + "Confirm") — should be single "Ok"

**Where**: `_MetricEditDialog` in `lib/widgets/session/metric_crown_widget.dart`

**Current state**: `showMetricEditPopup` renders an `AlertDialog` with two `actions`: a `TextButton` ("Cancel") and a `FilledButton` ("Confirm"). The bug report requires a single "Ok" button (implied: a `FilledButton` that commits the value and closes).

**What changes**:
- Remove the `TextButton` Cancel action entirely.
- Rename the `FilledButton` label from "Confirm" to "Ok".
- A single button that applies the value and closes is the desired UX.
- There is no separate Cancel path; tapping outside the dialog (system back) still dismisses without saving, which is the Flutter default for `showDialog` with `barrierDismissible: true`.

**Impact on tests**: All tests that currently find or tap "Confirm" must be updated to find/tap "Ok". All tests that find or tap "Cancel" must be removed or restructured. Specifically:
- T-11: tap "Confirm" → tap "Ok"
- T-12: tap "Cancel" → test that tapping outside the dialog (or pressing back) leaves value unchanged. Alternatively, test that entering then pressing "Ok" works, and that the dialog closes without saving when `barrierDismissible` closes it.
- T-13: currently asserts both "Confirm" and "Cancel" exist as specific button types → rewrite to assert only "Ok" `FilledButton` exists (no Cancel button).
- All other taps on "Confirm" (T-05, T-06, T-W04, T-NW03, T-14, T-15, T-16, duration tests) → update to "Ok".
- Any `find.text('Cancel')` assertions in tests → update or remove.

### Bug B-02: Tapping timed/round/drill display in live mode starts timer instead of opening editor modal

**Where**: `lib/features/session/workout_session_detail_view.dart`, live-mode branches of `_buildMetricWidget` for effort kinds `'timed'`, `'round'`, and `'drill'`.

**Current state**: The timed display `InlineMetricEditor` is wrapped in a parent `GestureDetector` whose `onTap` fires `_toggleEffortTimer(effortId)`. The `InlineMetricEditor` itself is `isReadOnly: true`, which suppresses its own tap-to-edit gesture. Result: tapping anywhere on the timer display starts/pauses the timer.

**What the user expects**: Tapping the numeric display opens the metric editor modal (the same `showMetricEditPopup` used for reps/weight), allowing the user to manually override the elapsed/remaining time value. The "Start" button in the center controls (`_buildStartTimerButton`) is the dedicated start path and remains unchanged.

**Root cause**: `isReadOnly: true` kills the inner tap-to-edit gesture, and the outer `GestureDetector` intercepts all taps for timer toggle. The fix is:
1. Remove `isReadOnly: true` from the live-mode timed/round/drill `InlineMetricEditor` instances.
2. Remove (or keep but disconnect) the outer `GestureDetector` that fires `_toggleEffortTimer`. The timer start/pause path remains available via the center "Start" / "Log" button control.
3. The `InlineMetricEditor` will then call `showMetricEditPopup` on tap (since `onTap` is null and `isReadOnly` is false), which lets the user override the elapsed seconds.

**Affected code blocks** (all in `workout_session_detail_view.dart`):

- `'timed'` live-mode block (lines ~265-334): Outer `GestureDetector` with key `'timer-gesture-detector'` wraps the `InlineMetricEditor`. Remove outer GestureDetector and set `isReadOnly: false` (default) on the `InlineMetricEditor`. Wire `onValueChanged` to persist `elapsedSecs` via `_updateMetricValue`.
- `'round'` live-mode block (lines ~439-511): Same pattern — outer GestureDetector wraps `InlineMetricEditor`. Remove outer GestureDetector, remove `isReadOnly: true`, wire `onValueChanged` to `'round-duration'` or current elapsed.
- `'drill'` live-mode block (lines ~595-658): Same pattern. Remove outer GestureDetector, remove `isReadOnly: true`, wire `onValueChanged` to `'elapsedSecs'`.

**What stays unchanged**:
- The play/pause icon row below the timer value remains as a visual indicator.
- `_buildStartTimerButton` / `_buildLogSetButton` center controls remain the primary action paths.
- Edit mode (`widget.editMode == true`) already uses `onTap` pointing to `_showDurationEntryDialog` — that path is correct and unchanged.

**Important constraint for round live mode**: The `remaining` countdown value (`effectiveTarget - elapsed`) is read-only feedback; the user editable value is `round-duration` (the target). When the user opens the modal via tap, the value to pre-fill and the key to update is `round-duration`. For `timed` and `drill`, it is `elapsedSecs`.

**Impact on tests**: Tests that currently drive `GestureDetector` with key `'timer-gesture-detector'` to toggle timers will need to find timer control via the "Start" button or the play/pause row instead. The test `T-17` in `crown_control_tap_to_edit_test.dart` currently asserts `isReadOnly: true` suppresses the crown on live timed; that assertion about `findsNothing` for the crown stays valid (crown is still hidden), but the `isReadOnly` setup must be removed from the live-mode path.

---

## Iteration 2: Bug Fix Tasks

### Task B-01-1 — Single "Ok" button in `_MetricEditDialog`
File: `lib/widgets/session/metric_crown_widget.dart`

In `_MetricEditDialogState.build`, in the `actions` list:
- Remove the `TextButton` (Cancel) entirely.
- Change the `FilledButton` child text from `'Confirm'` to `'Ok'`.
- Keep the `FilledButton.onPressed` logic unchanged (parse, clamp, call `onValueChanged`, pop).
- Keep `barrierDismissible` at its default (`true`) so tapping outside still closes without saving.

### Task B-01-2 — Update tests for single "Ok" button
File: `test/crown_control_tap_to_edit_test.dart`

- Anywhere `find.text('Confirm')` is used: change to `find.text('Ok')`.
- T-12 (cancel leaves value unchanged): rewrite to test that dismissing via `barrierDismissible` (tap outside dialog) leaves value unchanged, since there is no Cancel button.
- T-13: remove the Cancel button assertion; assert only a single `FilledButton` with text "Ok" appears.
- Anywhere `find.text('Cancel')` is used: update accordingly.

File: `test/interaction_flow_test.dart`
- Find any `find.text('Confirm')` or `find.text('Cancel')` taps → update to `find.text('Ok')`.

File: `test/session_toolbar_rework_test.dart`
- Find any `find.text('Confirm')` or `find.text('Cancel')` taps → update to `find.text('Ok')`.

### Task B-02-1 — Remove timer-tap-to-start from live timed/round/drill displays
File: `lib/features/session/workout_session_detail_view.dart`

**`'timed'` live-mode block**:
- Remove the outer `GestureDetector` (key `'timer-gesture-detector'`) that wraps the `Column` containing the `InlineMetricEditor` and the play/pause row.
- On the `InlineMetricEditor`:
  - Remove `isReadOnly: true`.
  - Remove `onValueChanged: (_) {}` — replace with real handler: `onValueChanged: (value) => _updateMetricValue(effortId, entryIndex, 'elapsedSecs', value)`.
- Keep the play/pause `Row` (icon + status text) as a visual indicator (not a tap target).
- The `Column` wrapper stays; only the `GestureDetector` is removed.

**`'round'` live-mode block**:
- Remove the outer `GestureDetector` (no explicit key, found at line ~453) that wraps the `Column` containing `InlineMetricEditor` + play/pause row.
- On the `InlineMetricEditor`:
  - Remove `isReadOnly: true`.
  - Change `onValueChanged` to persist `'round-duration'`: `(value) => _updateMetricValue(effortId, entryIndex, 'round-duration', value)`.

**`'drill'` live-mode block**:
- Remove the outer `GestureDetector` (found at line ~599) that wraps the `Column` containing `InlineMetricEditor` + play/pause row.
- On the `InlineMetricEditor`:
  - Remove `isReadOnly: true`.
  - Change `onValueChanged: (_) {}` → `(value) => _updateMetricValue(effortId, entryIndex, 'elapsedSecs', value)`.

### Task B-02-2 — Update tests for timer tap behavior
File: `test/crown_control_tap_to_edit_test.dart`

- T-17 (live-mode timed editor has no crown): this test validates no `MetricCrownWidget` is rendered. Since `isReadOnly: true` is being removed, the test setup must not rely on `isReadOnly: true` to suppress the crown. The crown is suppressed because `MetricCrownWidget` is simply not rendered in `InlineMetricEditor` (that was the prior iteration's work). Verify T-17 still passes without `isReadOnly: true`.
- Add new test: tapping the timer display value in live timed mode opens `AlertDialog` (the metric edit popup). Timer does NOT start from the number tap — no `_toggleEffortTimer` call.

File: `test/interaction_flow_test.dart` / `test/session_toolbar_rework_test.dart`
- Any test that drives `find.byKey(const Key('timer-gesture-detector'))` to toggle a timer: update to use "Start" button instead.

---

## Acceptance Criteria (Iteration 2)

- [ ] `showMetricEditPopup` renders exactly one button labeled "Ok" (a `FilledButton`); no Cancel button is present.
- [ ] Tapping outside the modal (barrier dismiss) closes it without calling `onValueChanged`.
- [ ] Tapping the timer display in live timed/round/drill mode opens the metric editor modal; it does NOT start the timer.
- [ ] The "Start" button in the center controls still starts the timer correctly.
- [ ] All existing tests pass after the button-rename and test updates.
- [ ] No regression on numeric (reps/weight) tap-to-edit modal.

---

## Progress (Iteration 2)

- [x] B-01-1: Remove Cancel button; rename Confirm to Ok in `_MetricEditDialog`
- [x] B-01-2: Update all test files for single-button modal (crown_control_tap_to_edit_test.dart, interaction_flow_test.dart, session_toolbar_rework_test.dart)
- [x] B-02-1: Remove outer GestureDetector timer-tap from timed/round/drill live-mode blocks; remove isReadOnly: true; wire real onValueChanged
- [x] B-02-2: Update tests for timer tap behavior (session_toolbar_rework_test.dart S-009/S-011/S-012/S-013; widget_test.dart timer tests updated to use Start button and state methods)
- [x] Verify: all tests pass with `flutter test` (1063 tests passed)

---

**Feedback**
