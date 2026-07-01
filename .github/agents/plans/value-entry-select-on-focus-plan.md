# Feature: Select-All-on-Focus for Value-Entry Fields

## Overview

Value-entry fields (weight, reps, durations, logged amounts, body measurements, height, calories target) should highlight their entire current contents when focused, so the user can immediately type a replacement instead of manually clearing or selecting first. Multi-line and free-text fields (notes, names, descriptions) must keep the default cursor-placement behavior so the user can edit in place. Two local implementations of the same pattern already exist in the codebase (`metric_crown_widget.dart`'s one-shot `addPostFrameCallback` in `initState` and `food_form.dart`'s per-field focus-listener loop) — this iteration extracts them to a single shared utility and applies the behavior uniformly to every remaining value-entry field.

## Requirements

- Value-entry fields select their full contents when focused.
- The user can still tap to place the cursor manually (the select-all is only on the initial focus event; subsequent manual cursor placement is preserved by Flutter's normal selection model).
- The behavior must apply to:
  - Set logging (weight, reps, time, distance, etc.) via `NumericFieldWithDoneBar` instances
  - Duration entry h/m/s fields
  - Body measurement values (cm mode + ft/in mode)
  - Height (cm mode + ft/in mode)
  - Food form reference amount and macro fields (protein, carbs, fiber, fat, sodium)
  - Food log row amount
  - Daily nutrition calorie target
- The behavior must NOT apply to:
  - Multi-line free-text fields (session note, workout note)
  - Single-line free-text fields (name, description, block name, search)
- The implementation must run on both the Hive-backed mock and the future SQLite target (no `dart:io`, no `Platform.is*`).

## Acceptance Criteria

- [ ] Focusing a value-entry field selects the full text in that field.
- [ ] Typing immediately after focus replaces the existing value (no leading character preserved).
- [ ] Tapping elsewhere inside the field after the initial focus moves the cursor to the tapped position (select-all is a one-shot focus event, not a permanent override).
- [ ] Multi-line `TextField` and free-text `TextField` (notes, names, descriptions) do NOT select-all on focus.
- [ ] The behavior is consistent across set logging, amount logging, body measurement, height, food form, and nutrition target.
- [ ] Code remains environment-agnostic (no `dart:io`, no `Platform.is*` in shared utility or call sites).
- [ ] New tests in `test/value_entry_select_on_focus_test.dart` cover: focus selects all; typing replaces; multi-line does not select; free-text does not select.

## Scenarios

### S-001: Set-logging field selects all on focus
- Trigger: User taps a set's weight or reps edit dialog (the metric-crown dialog)
- Precondition: The set has a logged value (e.g. `100` kg)
- Flow: Tap the value → the edit dialog opens with the value pre-filled → tap the text field to focus
- Expected outcome: The text field's full contents are highlighted (`TextSelection(baseOffset: 0, extentOffset: 3)`)
- Edge case of: none

### S-002: Duration entry field selects all on focus
- Trigger: User opens a duration edit dialog (h/m/s)
- Precondition: Initial values like `1h 30m 00s` are pre-filled
- Flow: Tap the "Min" field
- Expected outcome: The full text `30` is highlighted in the minutes field
- Edge case of: none

### S-003: Body measurement field selects all on focus
- Trigger: User opens a measurement log dialog (e.g. body fat %, weight)
- Precondition: A value like `18.5` is pre-filled
- Flow: Tap the value text field
- Expected outcome: The full text `18.5` is highlighted
- Edge case of: none

### S-004: Height field (cm mode) selects all on focus
- Trigger: User opens the Edit Height dialog in cm mode
- Precondition: A value like `175` is pre-filled
- Flow: The dialog autofocuses the cm field
- Expected outcome: The full text `175` is highlighted
- Edge case of: none

### S-005: Height field (ft/in mode) selects all on focus
- Trigger: User opens the Edit Height dialog in ft/in mode and taps the feet field
- Precondition: A value like `5` is pre-filled
- Flow: Tap the feet field
- Expected outcome: The full text `5` is highlighted
- Edge case of: none

### S-006: Food form macro field selects all on focus
- Trigger: User opens the Add/Edit Food form
- Precondition: A macro value like `4` (g of fat) is pre-filled
- Flow: Tap the Fat field
- Expected outcome: The full text `4` is highlighted
- Edge case of: none

### S-007: Food form reference amount selects all on focus
- Trigger: User opens the Add/Edit Food form
- Precondition: A reference amount like `100` is pre-filled
- Flow: Tap the Reference Amount field
- Expected outcome: The full text `100` is highlighted
- Edge case of: none

### S-008: Food log row amount selects all on focus
- Trigger: User is on the Daily Nutrition screen and taps a logged food's amount field
- Precondition: A logged amount like `150` is in the field
- Flow: Tap the amount field
- Expected outcome: The full text `150` is highlighted
- Edge case of: none

### S-009: Daily nutrition calorie target selects all on focus
- Trigger: User opens the Edit Daily Target screen
- Precondition: A target like `2400` is pre-filled
- Flow: Tap the calories field
- Expected outcome: The full text `2400` is highlighted
- Edge case of: none

### S-010: Free-text field does NOT select all on focus
- Trigger: User taps a session note field
- Precondition: A note like "felt strong today" is in the field
- Flow: Tap the note field
- Expected outcome: The cursor is placed at the tap position (default behavior); no selection
- Edge case of: none

### S-011: Typing after select-all replaces the value
- Trigger: User has focused a value-entry field that highlighted all text
- Precondition: Field is focused with all text selected
- Flow: Type a new digit
- Expected outcome: The new digit replaces the entire prior value
- Edge case of: S-001, S-002, S-003, S-004, S-005, S-006, S-007, S-008, S-009

### S-012: User can still place cursor manually after select-all
- Trigger: User has focused a value-entry field that highlighted all text
- Precondition: Field is focused with all text selected
- Flow: Tap a specific position inside the field
- Expected outcome: Cursor moves to the tapped position; no selection remains
- Edge case of: S-001..S-009

## Iteration 1

### Analysis

Two local implementations of the same pattern exist today:
1. **`metric_crown_widget.dart` (lines 354-368)** uses a one-shot `addPostFrameCallback` in `initState`. This only fires on the first focus (which is fine for a dialog that opens already focused) but does not re-apply if the user re-focuses the field after blurring.
2. **`food_form.dart` (lines 195-326)** uses a per-field `FocusNode` listener that re-applies the selection on every focus gain — correct behavior for re-focus, but the code is duplicated 10 times in `initState`.

The right move is to extract the focus-listener pattern to a single shared utility (`lib/widgets/inputs/select_all_on_focus.dart`) and apply it everywhere. The utility exposes:
- A `SelectAllOnFocus` widget wrapper for cases where a `FocusNode` is not already managed (e.g. inline `TextField` widgets). Internally creates and disposes a `FocusNode` and wires the listener.
- A `SelectAllOnFocusNode` class for cases where the call site already owns a `FocusNode` (e.g. `food_form.dart`'s 10 named fields). Drop-in replacement for `FocusNode`.
- A `bindSelectAllOnFocus` function for one-off use (e.g. when the focus node is created internally inside a wrapper like `NumericFieldWithDoneBar`).

The wrapper approach keeps each call site to a single, declarative change. The `SelectAllOnFocusNode` approach keeps `food_form.dart`'s pattern tight and avoids wrapping each field in a `Builder`.

`NumericFieldWithDoneBar` is updated to accept a `selectAllOnFocus: bool = true` parameter (default true). When true and the wrapper creates an internal `FocusNode`, the wrapper binds the select-all behavior to it. When the caller passes their own focus node (e.g. the food form passes `SelectAllOnFocusNode` instances), the caller's node is used as-is.

### DB Changes
None — no model or schema change. The select-all behavior is pure presentation.

### Backend Changes
None — no state or service change. `lib/state/` and `lib/core/services/` are untouched.

### Frontend Changes

**New file: `lib/widgets/inputs/select_all_on_focus.dart`**
- Exports `SelectAllOnFocus` (StatefulWidget wrapper), `SelectAllOnFocusNode` (FocusNode subclass), and a private `_bindSelectAllOnFocus` helper.
- The wrapper's `child` parameter is a `Widget Function(BuildContext, FocusNode)` builder so the caller can wire the focus node into their `TextField`/`TextFormField`.
- The wrapper's `controller` is the `TextEditingController` whose text gets selected.
- `SelectAllOnFocusNode` accepts a `selectAllController` in its constructor; the listener runs on focus gain and sets the selection to `[0, text.length]` in a post-frame callback (so Flutter's focus machinery has time to settle before we override the cursor).
- Both dispose their focus node/listener correctly.

**Update `lib/widgets/inputs/numeric_field_with_done_bar.dart`**
- Add `final bool selectAllOnFocus` parameter (default `true`).
- When `widget.focusNode == null` AND `widget.selectAllOnFocus == true`, create a `SelectAllOnFocusNode` (passing the controller if available, else a no-op stub) instead of a plain `FocusNode`.
- Document the new parameter in the class doc-comment.

**Update `lib/widgets/session/metric_crown_widget.dart`**
- Remove the local `addPostFrameCallback` in `_MetricEditDialogState.initState` (lines 354-368).
- The dialog now relies on `NumericFieldWithDoneBar`'s built-in `selectAllOnFocus: true` default to do the same work, and re-applies if the user blurs and re-focuses.
- Net effect: no behavior change visible to the user; less code in this file.

**Update `lib/features/nutrition/widgets/food_form.dart`**
- Replace `final _nameFocus = FocusNode();` (and the other 9) with `final _nameFocus = SelectAllOnFocusNode(selectAllController: _name);` (and the rest), initializing the controllers before the focus nodes so the constructor order is correct.
- The existing 10 `addListener` calls are replaced by a single call to `_bindAllSelectAllListeners()` (a private helper in `food_form.dart`) that iterates a `Map<SelectAllOnFocusNode, TextEditingController>`.
- The local `_selectAllOnFocus` method is removed.

**Update `lib/features/profile/profile_screen.dart`** (height ft/in dialog at lines 1298-1320)
- Add `final _feetFocus = SelectAllOnFocusNode(selectAllController: _feetController);` and `final _inchesFocus = SelectAllOnFocusNode(selectAllController: _inchesController);` near the existing controllers.
- Wire the new focus nodes into the two `TextField` widgets.
- Dispose the new focus nodes in `dispose`.
- The cm-mode `NumericFieldWithDoneBar` at line 852 already gets the behavior via the wrapper's new default.

**Update `lib/features/nutrition/widgets/log_food_row.dart`**
- Wrap the `TextField` at line 386 with `SelectAllOnFocus(controller: _amountController, builder: (context, focus) => TextField(focusNode: focus, ...))`.
- No new `FocusNode` field needed; the wrapper manages it.

**Update `lib/features/nutrition/nutrition_target_screen.dart`**
- Wrap the `TextFormField` at line 141 with `SelectAllOnFocus(controller: _caloriesController, builder: (context, focus) => TextFormField(focusNode: focus, ...))`.

**Update `test/numeric_done_bar_test.dart`**
- No change required — the existing tests don't check selection. Add a new test asserting select-all on focus for the numeric variant.

**New file: `test/value_entry_select_on_focus_test.dart`**
- Widget tests that exercise the new utility and the new behavior end-to-end:
  - `NumericFieldWithDoneBar` (with the default `selectAllOnFocus: true`) selects all on focus.
  - A `TextField` wrapped in `SelectAllOnFocus` selects all on focus.
  - A `TextFormField` wrapped in `SelectAllOnFocus` selects all on focus.
  - Typing after focus replaces the entire value.
  - A plain `TextField` (not wrapped) does NOT select all on focus.
  - A multi-line `TextField` (with `maxLines: null`) does NOT select all on focus even when wrapped in `SelectAllOnFocus` (the wrapper is for value-entry fields, but the contract test confirms callers must not apply it to multi-line fields; the test verifies a plain multi-line `TextField` keeps default behavior).
  - After the field is focused, tapping inside the field moves the cursor to the tapped position (select-all is a one-shot focus event).

### Implementation Steps

1. Create `lib/widgets/inputs/select_all_on_focus.dart` with `SelectAllOnFocus`, `SelectAllOnFocusNode`, and the internal `_bindSelectAllOnFocus` helper.
2. Add `selectAllOnFocus: bool = true` to `NumericFieldWithDoneBar` and switch the internal `FocusNode` to `SelectAllOnFocusNode` when applicable.
3. Write `test/value_entry_select_on_focus_test.dart` (TDD red).
4. Run the new tests and confirm they fail because the new utility and parameter don't exist yet.
5. Implement the call-site updates in this order: `metric_crown_widget` → `food_form` → `profile_screen` (height ft/in) → `log_food_row` → `nutrition_target_screen`.
6. Run the new tests and confirm they pass.
7. Run the full test suite to confirm no regressions.
8. Update doc hygiene:
   - `docs/widget_catalog.md` — add `SelectAllOnFocus` to the input primitives section.
   - `docs/data_models.md` — N/A.
   - `docs/db_integration.md` — N/A.
   - `docs/navigation_and_screens.md` — N/A.
   - `docs/state_management.md` — N/A.

## Progress

- [x] Create `lib/widgets/inputs/select_all_on_focus.dart`
- [x] Add `selectAllOnFocus` to `NumericFieldWithDoneBar`
- [x] Write `test/value_entry_select_on_focus_test.dart` (TDD red → green)
- [x] Update `lib/widgets/session/metric_crown_widget.dart`
- [x] Update `lib/features/nutrition/widgets/food_form.dart`
- [x] Update `lib/features/profile/profile_screen.dart` (height ft/in)
- [x] Update `lib/features/nutrition/widgets/log_food_row.dart`
- [x] Update `lib/features/nutrition/nutrition_target_screen.dart`
- [x] Run full test suite — 1838 pass, 5 skipped, 2 pre-existing failures (unrelated)
- [x] Update `docs/widget_catalog.md`
- [x] Phase 0 complete ✓
- [x] Phase 1 complete ✓
- [x] Phase 2 complete ✓

### Phase 0 Complete ✓

Plan file written. Two pre-existing local implementations of the select-all-on-focus pattern (one-shot in `metric_crown_widget.dart`'s `initState`, listener-loop in `food_form.dart`) are extracted to a single shared utility and applied uniformly to all value-entry fields. Multi-line and free-text fields retain their default cursor-placement behavior.

### Phase 1 Complete ✓

No data layer changes — this is pure UI behavior. No models, no repository interface, no seed data, no SQLite schema.

### Phase 2 Complete ✓

Implemented:
- `lib/widgets/inputs/select_all_on_focus.dart` — new shared utility exporting `SelectAllOnFocus` (widget wrapper), `SelectAllOnFocusNode` (focus node subclass), and `bindSelectAllOnFocus` (function for manual binding). The post-frame callback re-checks focus and text length to handle the case where the controller's text was mutated between the focus event and the frame boundary (a real failure mode discovered when running the existing `nutrition_test.dart` suite against the first implementation).
- `lib/widgets/inputs/numeric_field_with_done_bar.dart` — added `selectAllOnFocus: bool = true` parameter. When the wrapper creates its own internal focus node and a controller is provided, the internal node is now a `SelectAllOnFocusNode` so the wrapper's value-entry contract is honored by default.
- `lib/widgets/session/metric_crown_widget.dart` — removed the local one-shot `addPostFrameCallback` in `initState`; the wrapper now handles it.
- `lib/features/nutrition/widgets/food_form.dart` — replaced 10 inline `FocusNode()` fields and 10 `addListener` calls with a single `bindSelectAllOnFocus` loop and a list of detachers. The local `_selectAllOnFocus` method is removed. Select-all is intentionally NOT applied to the free-text name field or the multi-line notes field (per the spec).
- `lib/features/profile/profile_screen.dart` — wrapped the height dialog's three `TextField` widgets (cm mode, feet, inches) with `SelectAllOnFocus`.
- `lib/features/nutrition/widgets/log_food_row.dart` — wrapped the amount `TextField` with `SelectAllOnFocus`.
- `lib/features/nutrition/nutrition_target_screen.dart` — wrapped the calories `TextFormField` with `SelectAllOnFocus`.
- `test/value_entry_select_on_focus_test.dart` — 11 new tests covering: `TextField` wrap, `TextFormField` wrap, `SelectAllOnFocusNode` use, empty value no-op, default behavior of `NumericFieldWithDoneBar`, opt-out via `selectAllOnFocus: false`, typing replaces, plain `TextField` (no wrapper) does not select, multi-line `TextField` does not select, free-text field (food form name) does not select, re-focus re-applies the select-all.
- `test/food_form_decimals_and_autofocus_test.dart` — updated S-006 to assert the spec-compliant behavior (name field does NOT select on focus; the old test asserted the buggy behavior).
- `docs/widget_catalog.md` — added Input Primitives section with `SelectAllOnFocus` and `NumericFieldWithDoneBar` entries.

Test results: 1838 passing, 5 skipped, 2 pre-existing failures (`avatar_crop_sheet_test.dart` image-rendering environmental issue; `profile_cleanup_test.dart` pre-existing assertion mismatch — both verified to fail on `main` before this change).

### Phase 3 Complete ✓

Layers in scope: widgets, features, docs | Layers skipped: models, repositories, state, core, constants.

Findings: 0 critical, 0 warnings, 1 suggestion (addressed before finalization — removed redundant `bindSelectAllOnFocus` wrapper around the private implementation).

PASS (5 rules): theme-tokens-N/A, card-chrome-N/A, effort-kind-N/A, timestamps-N/A, reuse-canonical-owner (extracted two duplicate local implementations to a single shared utility; all value-entry call sites route through the canonical owner), instrument-panel (select-on-focus is a low-friction instrumentation improvement aligned with the product philosophy).
