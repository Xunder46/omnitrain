# Feature: Targeted Typography & Control-Styling Corrections

## Overview

A focused, scoped correction pass addressing four confirmed issues surfaced during TestFlight on-device review. Three direct fixes and one bounded sweep. No redesign. No layout changes to timed/cardio screens. The metric brightness convention (bright = editable, grey = read-only) is a hard constraint and must not be touched.

## Requirements

- Fix 1: Remove `FittedBox(fit: BoxFit.scaleDown)` wrapper from "New Exercise" button label in `ExercisePickerDialog`
- Fix 2: Apply muted/secondary type style to `DropdownButtonFormField` value text and menu items in the picker's Discipline and Muscle filters
- Fix 3: Restyle the "Weight adjustment" `TextButton` in `workout_session_detail_view.dart` as a clearly interactive `OutlinedButton` with an expand/collapse icon
- Fix 4: Bounded sweep — identify and restyle other interactive accent-text controls lacking a button affordance; flag ambiguous candidates

## Acceptance Criteria

- [x] "New Exercise" button label renders at its intended prominent primary-action size with no shrink-to-fit wrapper
- [x] The picker's Discipline and Muscle dropdown value text and menu-item text use an intentional, muted, quieter type role consistent with the sheet's secondary chips; floating field labels stay caption-level
- [x] Picker prominence order reads title → primary action → search → filters/values at chip level; no filter value competes with the title or out-shouts the action
- [x] "Weight adjustment" is presented as a clearly interactive secondary `OutlinedButton` with a disclosure/expand icon, lower in emphasis than the screen's primary action
- [x] The weight value's brightness (and the bright-editable / grey-read-only metric convention generally) is preserved unchanged across all screens
- [x] The bounded sweep restyles only genuinely interactive accent-text controls lacking a clear affordance; static labels, primary actions, and metric values are left alone; ambiguous candidates are flagged in the audit report rather than changed
- [ ] All fixes verified across all six themes on at least one device
- [x] A widget test guards against re-wrapping the "New Exercise" label in shrink-to-fit
- [x] A widget test asserts the picker action label's type role is more prominent than the dropdown value role
- [x] A widget test asserts "Weight adjustment" renders as an `OutlinedButton` (or equivalent interactive button-type widget) with an expand/collapse icon, not as plain `TextButton`
- [x] Existing picker search/selection tests and weight-value editability/brightness tests pass unchanged; only tests tied to the old styling are updated
- [x] An audit report (in the plan's Bounded Sweep Audit section) lists every element changed and every ambiguous candidate flagged but not changed
- [x] No changes to metric brightness convention, time-based screen layout, color system, navigation, or business logic

## Scenarios

### S-001: New Exercise button keeps intended prominence
- Trigger: User opens Exercise Picker dialog.
- Precondition: Session screen opens picker successfully.
- Flow: Dialog renders title, primary action, search, and filters; user observes action row.
- Expected outcome: "New Exercise" label is plain `Text` inside `OutlinedButton.icon` with no shrink-to-fit wrapper.
- Edge case of: none
- Test coverage: `test/screen_widget_test.dart` (`New Exercise label is not wrapped in shrink-to-fit FittedBox`)

### S-002: Filter dropdown values render in muted secondary role
- Trigger: User opens Exercise Picker dialog.
- Precondition: Discipline and Muscle dropdowns are visible with "All" default values.
- Flow: Dialog renders both dropdown selected values and menu item text role.
- Expected outcome: Dropdown values and menu items use bodySmall/muted style and do not compete with title/action hierarchy.
- Edge case of: none
- Test coverage: `test/screen_widget_test.dart` (`New Exercise label type role is more prominent than dropdown value text`)

### S-003: Weight adjustment toggle has explicit affordance
- Trigger: User opens timed exercise detail in workout session.
- Precondition: Timed exercise exists in session and detail view is opened.
- Flow: User views weight adjustment control, then taps it to expand/collapse.
- Expected outcome: Control renders as `OutlinedButton` with disclosure icon (`expand_more` collapsed, `expand_less` expanded), not as plain `TextButton`.
- Edge case of: none
- Test coverage: `test/screen_widget_test.dart` (`weight adjustment renders as OutlinedButton with expand icon, not plain TextButton`)

### S-004: Weight-adjust visibility remains effort-kind dependent
- Trigger: User opens exercise detail for non-timed loaded exercise.
- Precondition: Session contains loaded set exercise.
- Flow: Detail view renders metadata controls.
- Expected outcome: Weight adjustment control remains hidden where timed-only behavior does not apply.
- Edge case of: S-003
- Test coverage: `test/screen_widget_test.dart` (`loaded set exercise does not show weight adjustment link`)

### S-005: Bounded sweep excludes dialog dismiss actions and ambiguous toolbar pattern
- Trigger: Developer performs style-affordance sweep for accent-text interactive controls.
- Precondition: Existing dialog action TextButtons and keyboard done bar controls exist.
- Flow: Inspect each candidate; classify against affordance and accent-text criteria.
- Expected outcome: Only true ambiguity is flagged (`Done` in keyboard done bar), dialog cancel/close actions remain unchanged, audit report is complete.
- Edge case of: none
- Test coverage: Manual audit in Bounded Sweep Audit Report (no behavior change intended)

---

## Iteration 1

### Phase 1: Developer — Fix 1 (New Exercise label, exercise_picker_dialog.dart)

**File:** `lib/widgets/pickers/exercise_picker_dialog.dart`

**Current code (lines ~248–260):**
```dart
SizedBox(
  width: double.infinity,
  child: OutlinedButton.icon(
    onPressed: _openCreateExercise,
    icon: const Icon(Icons.add),
    label: const FittedBox(
      fit: BoxFit.scaleDown,
      child: Text('New Exercise'),
    ),
    ...
  ),
),
```

**Change:** Replace `FittedBox(fit: BoxFit.scaleDown, child: Text('New Exercise'))` with `Text('New Exercise')` directly. The button is full-width with a short label; no overflow risk exists, so shrink-to-fit adds no value and actively suppresses the intended prominence.

**Implementation steps:**
1. [ ] In `exercise_picker_dialog.dart`, in the `OutlinedButton.icon` for "New Exercise", replace the `FittedBox` wrapper with a plain `Text('New Exercise')`
2. [ ] Confirm the `OutlinedButton` uses `foregroundColor: theme.colorScheme.primary` (accent-coloured, primary action role in this sheet) — this is correct and must be preserved

---

### Phase 2: Developer — Fix 2 (Dropdown value text, exercise_picker_dialog.dart)

**File:** `lib/widgets/pickers/exercise_picker_dialog.dart`

**Current code (lines ~313–395):** Both `DropdownButtonFormField<String>` for Discipline and Muscle have `DropdownMenuItem` items with `Text(...)` using the default text style, which resolves to `bodyMedium` or similar — a prominent size that competes with the sheet title.

**Change:** Apply `style: theme.textTheme.bodySmall?.copyWith(color: OmniTheme.textSecondary)` to:
1. The `Text` widgets inside each `DropdownMenuItem` (including the `'All'` item)
2. The `style` property on each `DropdownButtonFormField` itself (controls the displayed selected-value text)

The floating `labelText` ('Discipline', 'Muscle') uses `InputDecoration.labelStyle` — leave it alone; it already renders at a small caption scale via Material's default `InputDecorator` treatment.

**Implementation steps:**
1. [ ] In the Discipline `DropdownButtonFormField`, set `style: theme.textTheme.bodySmall?.copyWith(color: OmniTheme.textSecondary)` on the widget (controls the displayed value)
2. [ ] In each `DropdownMenuItem` for Discipline (the `'All'` item and the mapped items), wrap `Text(...)` with `style: theme.textTheme.bodySmall?.copyWith(color: OmniTheme.textSecondary)`
3. [ ] Repeat for the Muscle `DropdownButtonFormField`
4. [ ] Verify the field labels ('Discipline', 'Muscle') are unchanged
5. [ ] Verify the prominence order in the sheet: "Select Exercise" (headlineSmall) > "New Exercise" (OutlinedButton, primary accent) > search field > filters at bodySmall/muted

---

### Phase 3: Developer — Fix 3 (Weight adjustment control, workout_session_detail_view.dart)

**File:** `lib/features/session/workout_session_detail_view.dart`

**Current code (lines ~104–131):** `_buildWeightAdjustmentSection` renders a `TextButton` with `Text('Weight adjustment', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.primary))`. This reads as bare accent-coloured text with no button affordance and no collapse indicator.

**Change:** Replace the `TextButton` with an `OutlinedButton.icon` that:
- Uses `icon: Icon(isExpanded ? Icons.expand_less : Icons.expand_more)` for the disclosure affordance
- Uses `label: Text('Weight adjustment')` 
- Uses `OutlinedButton.styleFrom(foregroundColor: OmniTheme.textSecondary, side: BorderSide(color: OmniTheme.textSecondary.withValues(alpha: 0.4)))` — clearly interactive (outlined), but secondary in emphasis (muted foreground, not accent primary), so it does not compete with the primary CTA
- Preserves all existing `onPressed` logic (toggle `_weightAdjustExpanded[key]`)
- Preserves `padding`, `minimumSize`, and `tapTargetSize` constraints from the current `ButtonStyle`

The `InlineMetricEditor` below the toggle is unchanged — the metric value's brightness is the intentional editability affordance and must not be touched.

**Implementation steps:**
1. [ ] In `_buildWeightAdjustmentSection`, replace the `TextButton(...)` block with an `OutlinedButton.icon(...)` as described above
2. [ ] Ensure the `isExpanded` variable (already computed) drives the icon: `Icons.expand_less` when expanded, `Icons.expand_more` when collapsed
3. [ ] Keep `_weightAdjustExpanded[key]` toggle logic identical
4. [ ] Do NOT change the `InlineMetricEditor` block

---

### Phase 4: Developer — Fix 4 (Bounded sweep)

**Scope:** Search all files under `lib/` for `TextButton` or `InkWell` or `GestureDetector` usage where the child is `Text(...)` styled with `colorScheme.primary` or `theme.colorScheme.primary` or a named accent colour, and the widget is interactive (has an `onPressed`/`onTap` that is not a dialog Cancel action).

**Pre-analysis (from codebase review):**

The following TextButton instances were reviewed. Each is classified below. Note: dialog Cancel/Close TextButtons are a standard Material pattern and are explicitly NOT in scope (they already have a well-understood affordance — they are paired with a FilledButton primary action and read as secondary dismiss actions).

| Location | Widget | Text | Classification |
|---|---|---|---|
| `workout_session_detail_view.dart` line 104 | `TextButton` | "Weight adjustment" | **FIX 3 — changed to OutlinedButton.icon** |
| `workout_session_finish.dart` line 16 | `TextButton` | "Continue" (in Workout Complete dialog) | Dialog cancel pattern — NOT in scope |
| `workout_session_finish.dart` line 108 | `TextButton` | "Cancel" | Dialog cancel pattern — NOT in scope |
| `workout_session_screen.dart` line 798 | `TextButton` | "Cancel" (dialog) | Dialog cancel pattern — NOT in scope |
| `workout_session_screen.dart` line 856 | `TextButton` | "Cancel" (dialog) | Dialog cancel pattern — NOT in scope |
| `workout_session_screen.dart` line 1173 | `TextButton` | "Cancel" | Dialog cancel pattern — NOT in scope |
| `workout_session_screen.dart` line 1238 | `TextButton` | "Cancel" | Dialog cancel pattern — NOT in scope |
| `workout_session_edit_mode.dart` line 92 | `TextButton` | "Cancel" (dialog) | Dialog cancel pattern — NOT in scope |
| `session_summary_screen.dart` lines 220, 233 | `TextButton` | (review) | Needs inspection |
| `session_overview_screen.dart` line 282 | `TextButton` | "Cancel" (dialog) | Dialog cancel pattern — NOT in scope |
| `home_screen.dart` lines 304, 386 | `TextButton` | "Cancel" (dialog) | Dialog cancel pattern — NOT in scope |
| `metric_chooser_dialog.dart` lines 41, 106 | `TextButton` | (review) | Needs inspection |
| `numeric_field_with_done_bar.dart` line 110 | `TextButton` | (review) | Needs inspection |
| `exercise_picker_dialog.dart` line 420 | `TextButton.icon` | "Clear Filters" | `foregroundColor: OmniTheme.textSecondary` — already uses muted, NOT primary accent — no change needed |
| `onboarding_screen.dart` line 120 | `TextButton` | (review) | Needs inspection |

**Developer must inspect the four "Needs inspection" cases and produce the audit report table before making any changes.** For each, determine:
- Is it interactive (onPressed is not just Navigator.pop)?
- Is it styled with the accent/primary color?
- Is there no other button affordance (no border, no fill)?
- Could a user mistake it for a static label or heading?

If all four are true: restyle to `OutlinedButton` or `OutlinedButton.icon` with muted secondary styling (same pattern as Fix 3).
If ambiguous: flag in the audit report, do NOT change.

**Implementation steps:**
1. [ ] Inspect `session_summary_screen.dart` TextButtons (~lines 220, 233) — classify and act or flag
2. [ ] Inspect `metric_chooser_dialog.dart` TextButtons (~lines 41, 106) — classify and act or flag
3. [ ] Inspect `numeric_field_with_done_bar.dart` TextButton (~line 110) — classify and act or flag
4. [ ] Inspect `onboarding_screen.dart` TextButton (~line 120) — classify and act or flag
5. [ ] Produce the Bounded Sweep Audit table in this plan (update the section below)

---

### Phase 5: Developer — Tests

**New tests to add** (in `test/screen_widget_test.dart`, in the `ExercisePickerDialog` group and the weight adjustment group):

#### Test A — "New Exercise" label is not wrapped in FittedBox
```
testWidgets('New Exercise label is not wrapped in shrink-to-fit', (tester) async {
  // Pump ExercisePickerDialog
  // Find the OutlinedButton whose child tree contains Text('New Exercise')
  // Assert: no FittedBox ancestor exists between the OutlinedButton and the Text
  expect(
    find.ancestor(
      of: find.text('New Exercise'),
      matching: find.byType(FittedBox),
    ),
    findsNothing,
  );
});
```

#### Test B — Picker action label type role is more prominent than dropdown value
```
testWidgets('New Exercise label style is more prominent than dropdown value text', (tester) async {
  // Pump ExercisePickerDialog
  // Find the Text('New Exercise') widget and its fontSize
  // Find the Text('All') widget in the first DropdownButtonFormField and its fontSize
  // Assert: New Exercise fontSize > All fontSize
  // (or compare textTheme role names if accessible)
});
```

#### Test C — Weight adjustment renders as OutlinedButton with icon, not plain TextButton
```
testWidgets('Weight adjustment renders as OutlinedButton with expand icon', (tester) async {
  // Pump WorkoutSessionScreen with a timed exercise (as in the existing weight adjustment test)
  // Navigate to the detail view
  // Assert: find.byType(OutlinedButton) with text 'Weight adjustment' findsOneWidget
  // Assert: find.widgetWithText(TextButton, 'Weight adjustment') findsNothing
  // Assert: find.descendant(of: OutlinedButton finder, matching: find.byIcon(Icons.expand_more)) findsOneWidget
});
```

**Existing tests to update:**
- `screen_widget_test.dart` line 3461: `find.widgetWithText(TextButton, 'Weight adjustment')` → update to find an `OutlinedButton` (or use `find.widgetWithText(OutlinedButton, 'Weight adjustment')`)
- `screen_widget_test.dart` line 3517: `expect(find.text('Weight adjustment'), findsNothing)` — this assertion checks visibility/absence of the text itself, which remains valid regardless of button type; verify it still passes unchanged

---

## Bounded Sweep Audit Report

_To be filled in by Developer during Phase 4 execution._

| File | Line | Widget | Text / Label | Verdict | Action |
|---|---|---|---|---|---|
| `workout_session_detail_view.dart` | 104 | TextButton | "Weight adjustment" | Interactive accent-text expander, no affordance | **Restyled** (Fix 3) |
| `exercise_picker_dialog.dart` | 420 | TextButton.icon | "Clear Filters" | Muted colour (textSecondary), not accent | No change |
| `session_summary_screen.dart` | ~220 | TextButton | "Cancel" (in Discard dialog) | Dialog cancel pattern — paired with "Discard" confirm in AlertDialog | No change |
| `session_summary_screen.dart` | ~233 | TextButton | "Discard" (in Discard dialog) | Dialog confirm pattern — AlertDialog action, not accent-text control | No change |
| `metric_chooser_dialog.dart` | ~41 | TextButton | "Close" (no-capabilities dialog) | Dialog dismiss pattern — only action in AlertDialog with no primary CTA | No change |
| `metric_chooser_dialog.dart` | ~106 | TextButton | "Cancel" (metric chooser dialog) | Dialog cancel pattern — paired with tappable capability options | No change |
| `numeric_field_with_done_bar.dart` | ~110 | TextButton | "Done" | Interactive, primary accent (`colorScheme.primary`). **Ambiguous**: standard iOS/platform keyboard-done-bar convention. Well-understood affordance in toolbar context. | **Flagged** — no change |
| `onboarding_screen.dart` | ~120 | TextButton | "Skip" | Styled with `textMuted` foreground (NOT primary accent) | No change |

---

## Files Affected

- `lib/widgets/pickers/exercise_picker_dialog.dart` — Fix 1, Fix 2
- `lib/features/session/workout_session_detail_view.dart` — Fix 3
- Possibly: `lib/features/session/session_summary_screen.dart` — Fix 4 (TBD)
- Possibly: `lib/widgets/pickers/metric_chooser_dialog.dart` — Fix 4 (TBD)
- Possibly: `lib/widgets/inputs/numeric_field_with_done_bar.dart` — Fix 4 (TBD)
- Possibly: `lib/features/onboarding/onboarding_screen.dart` — Fix 4 (TBD)
- `test/screen_widget_test.dart` — new tests A, B, C; update existing weight-adjustment test at line 3461

## NOT Affected

- `lib/core/constants/omni_theme.dart` — no color or token changes
- `lib/data/`, `lib/state/`, `lib/core/navigation/` — no business logic
- Any timed/cardio screen layout
- Metric brightness / `InlineMetricEditor` styling

## Notes

- The "New Exercise" button in the picker is an `OutlinedButton`, not a `FilledButton`. This is correct — it's primary in this sheet's context, but secondary in the app's global hierarchy. Do not change it to a FilledButton.
- Fix 3 uses muted (`OmniTheme.textSecondary`) foreground for the "Weight adjustment" `OutlinedButton`. This is deliberately NOT the primary accent — it sits below the primary CTA visually. The expand icon is the disclosure affordance.
- The `InlineMetricEditor` below the weight adjustment toggle must remain completely unchanged, including all brightness/color styling of its metric values.
- When updating the existing test at line 3461, use `find.widgetWithText(OutlinedButton, 'Weight adjustment')` or a more specific finder as appropriate for the new widget type.
- All dialog Cancel/Close `TextButton`s across the codebase follow the standard Material pattern (paired with a FilledButton primary). These are NOT ambiguous accent-text controls — they are a well-understood affordance in dialog context. Do not restyle them.

## Progress

- [x] Fix 1: Remove FittedBox from "New Exercise" label
- [x] Fix 2: Apply muted style to dropdown value text and menu items
- [x] Fix 3: Restyle "Weight adjustment" as OutlinedButton.icon
- [x] Fix 4: Complete bounded sweep — inspect 4 TBD candidates, produce audit table
- [x] Test A: New widget test — no FittedBox guard
- [x] Test B: New widget test — type role prominence hierarchy
- [x] Test C: New widget test — weight adjustment is OutlinedButton with icon
- [x] Update existing weight adjustment test (line 3461) to find OutlinedButton
- [ ] Verify all six themes on device
- [x] Confirm existing picker search/selection tests pass unchanged
- [x] Confirm weight-value editability/brightness tests pass unchanged

## Feedback

### Reviewer Findings (Iteration 1)

#### CRITICAL
- Acceptance criterion "All fixes verified across all six themes on at least one device" is still incomplete. The Progress checklist remains unchecked and no evidence artifact (run log, screenshots, or QA note) is attached. This blocks plan completion even though widget tests pass.

#### WARNING
- `## Scenarios` is still a placeholder (`_Populated during implementation._`) and was not retrofilled with scenario-to-test mappings.
- Handoff summary with explicit `Doc Updates` statuses for reviewer-required docs is not present in this feature artifact set, so doc-hygiene verification could not be completed.

#### Required follow-up
1. Complete and record six-theme on-device verification (at least one device).
2. Populate the `## Scenarios` register with implemented scenarios and mapped tests.
3. Add a handoff summary section with explicit doc status entries (updated/not-needed) for reviewer checklist docs.

### Follow-up Resolution (Iteration 2)

- Completed: `## Scenarios` register populated with scenario-to-test mapping.
- Completed: Handoff summary with explicit doc-update status added below.
- Pending: Six-theme on-device verification evidence (manual QA/device run artifact still required).

## Phase Status

**Blocked** — pending manual six-theme on-device verification evidence.

## Developer Handoff Summary

## Developer Work Complete ✓ (except pending manual device verification)

### Phase 0 — TDD
- Scenarios confirmed: 5
- Tests written/updated for this feature: 4 new + 1 updated assertion
- All Phase 0 scenario tests: PASS in `test/screen_widget_test.dart` (129 passed, 0 failed in latest run)

### Implementation
- State classes created/updated: none
- Screens implemented: `lib/features/session/workout_session_detail_view.dart` (weight adjustment control affordance)
- Widgets implemented/updated: `lib/widgets/pickers/exercise_picker_dialog.dart` (button label + dropdown type role)
- Navigation updated: no

### Doc Updates
- `docs/navigation_and_screens.md`: no update required (no route/screen-constructor changes)
- `docs/state_management.md`: no update required (no new state class/method/service changes)
- `docs/widget_catalog.md`: no update required (no new reusable widget introduced)

### Files Changed
- `lib/widgets/pickers/exercise_picker_dialog.dart`
- `lib/features/session/workout_session_detail_view.dart`
- `test/screen_widget_test.dart`
- `.github/agents/plans/typography-control-styling-plan.md`

### Tested On
- [ ] Web (Chrome) with HiveWorkoutRepository
- [ ] All six themes on at least one device (pending manual verification artifact)
- [x] All Phase 0 scenario tests green
- [x] No regressions in existing tests within `test/screen_widget_test.dart`
