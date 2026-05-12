# Feature: Keyboard Dismissal & Text Capitalization Defaults — App-Wide

## Overview
Two coordinated UX improvements to text entry across the entire app:
1. **Keyboard dismissal** — tap-outside-to-dismiss for all text inputs; a styled "Done" toolbar above the numeric keyboard for set-logging inputs.
2. **Capitalization defaults** — word-case for name/label fields, sentence-case for prose/note fields, none for email/password/numeric fields.
Both are implemented centrally so future screens inherit the behavior automatically.

---

## Requirements

### Keyboard Dismissal
- Tapping any non-interactive area while a text input is focused unfocuses the input (dismisses keyboard).
- Applies to all text inputs across all screens, modals, and bottom sheets.
- Scrolling does NOT dismiss the keyboard — only an explicit tap on empty/non-interactive space.
- Tapping another interactive element while a keyboard is open: keyboard dismisses AND the element activates in one tap.
- Multi-line fields (session notes): Return key inserts a newline; does NOT dismiss.
- A "Done" button bar appears above the keyboard for numeric set-logging inputs (weight, reps, time, distance). Bar is themed to match the app's dark instrument-panel aesthetic.
- The Done bar does NOT appear for free-text inputs.

### Capitalization Defaults
- **Word-case** (`TextCapitalization.words`): custom exercise name, custom system name, period name, profile display name, routine name.
- **Sentence-case** (`TextCapitalization.sentences`): session note, any other free-prose fields.
- **None** (`TextCapitalization.none`): email, password, numeric keyboard fields (already handled by keyboard type; confirm no wrong capitalization is set).

---

## Acceptance Criteria
- [ ] Tapping empty space while any text input is focused dismisses the keyboard, no per-screen wiring required.
- [ ] Tapping a button/list item while a keyboard is open dismisses the keyboard AND activates the element in a single tap.
- [ ] Scrolling a `ListView` or `ScrollView` while a text input is focused does NOT dismiss the keyboard.
- [ ] Pressing Return in the session note field inserts a newline (keyboard stays open).
- [ ] A styled "Done" bar appears above the keyboard for every `TextInputType.number` / `TextInputType.numberWithOptions` field in the app.
- [ ] Tapping Done dismisses the keyboard; the field value is committed (unchanged from what the user typed).
- [ ] The Done bar is styled with the app's dark surface color and primary accent for the button text — not system gray.
- [ ] Done bar does NOT appear for free-text fields (notes, names, search).
- [ ] Every name/label field has `TextCapitalization.words` set.
- [ ] Every note/prose field has `TextCapitalization.sentences` set.
- [ ] No auto-capitalization on email, password, or numeric keyboard fields.
- [ ] All existing tests pass after changes.
- [ ] New widget tests cover the three behaviors described below.

---

## Iteration 1

### Analysis

**Global tap-outside-to-dismiss** — The standard Flutter pattern is to wrap `MaterialApp`'s `builder` with a `GestureDetector` (behavior: `HitTestBehavior.translucent`) that calls `FocusManager.instance.primaryFocus?.unfocus()` on tap. Because it sits at the widget tree root and uses `translucent` hit testing, all child events still propagate normally — buttons fire, lists scroll, keyboards stay up during scroll. This is a single-line change to `app.dart`.

**"Done" toolbar** — `InlineMetricEditor` (the drag-swipe editor for weight/reps in the live session view) does NOT use a keyboard, so it needs no Done bar. The keyboard-based numeric fields that need a Done bar are:
- `workout_session_edit_mode.dart` — the shared h/m/s duration dialog (`TextInputType.number` × 3)
- `routine_setup_screen.dart` — numeric target fields (`TextInputType.number`)
- `profile_screen.dart` — body-weight field (`TextInputType.numberWithOptions`)
- Any other field with `keyboardType: TextInputType.number` or `.numberWithOptions`

Implementation: create a reusable `NumericFieldWithDoneBar` wrapper widget in `lib/widgets/inputs/`. The wrapper inserts an `OverlayEntry` when its internal `FocusNode` gains focus and removes it when focus is lost. The overlay is positioned at `MediaQuery.viewInsets.bottom` so it rides the keyboard edge. Done button calls `primaryFocus?.unfocus()`.

**Capitalization** — Per-field `textCapitalization` property on each `TextField`. No central wrapper needed; these are targeted edits to the ~10 affected screens.

---

### Phase 1: Global tap-outside-to-dismiss (@developer)

1. [ ] In `lib/app.dart`, add `builder` parameter to `MaterialApp`:
   ```dart
   builder: (context, child) => GestureDetector(
     behavior: HitTestBehavior.translucent,
     onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
     child: child!,
   ),
   ```
   This one change gives tap-outside-to-dismiss to every text input in the app.

---

### Phase 2: "Done" accessory bar for numeric keyboards (@developer)

2. [ ] Create `lib/widgets/inputs/numeric_field_with_done_bar.dart`
   - Stateful widget that accepts the same core parameters as `TextField` (controller, focusNode, keyboardType, decoration, onChanged, textAlign, etc.) plus its own params.
   - Internally manages an `OverlayEntry` that shows a styled Done bar.
   - Done bar design: `Container` using `Theme.of(context).colorScheme.surface` as background with a top border using the theme's `divider` color. "Done" button uses `TextButton` with `Theme.of(context).colorScheme.primary` foreground text, aligned to the trailing edge. Height: 44px.
   - The overlay entry is inserted to `Overlay.of(context)` on `focusNode.hasFocus` and removed on focus loss.
   - Overlay is positioned using `Positioned(left: 0, right: 0, bottom: MediaQuery.of(context).viewInsets.bottom)`.
   - Done tap: `FocusManager.instance.primaryFocus?.unfocus()`.

3. [ ] Replace numeric `TextField` usages with `NumericFieldWithDoneBar` in:
   - `lib/features/session/workout_session_edit_mode.dart` — all three duration fields (h/m/s)
   - `lib/features/routine/routine_setup_screen.dart` — line ~969 numeric target field
   - `lib/features/profile/profile_screen.dart` — line ~579 body-weight field
   - Any other file found via `grep keyboardType.*number` audit

---

### Phase 3: Capitalization defaults (@developer)

4. [ ] Add `textCapitalization: TextCapitalization.words` to the following fields:
   - `lib/features/exercise/exercise_editor_screen.dart` — exercise name field (line ~296), system name field (line ~313)
   - `lib/features/period/create_period_screen.dart` — period name field (line ~105), period label/description field if present (line ~253)
   - `lib/features/profile/profile_screen.dart` — display name field (line ~312)
   - `lib/features/routine/routine_setup_screen.dart` — routine name fields (lines ~223, ~252)
   - `lib/widgets/pickers/exercise_picker_dialog.dart` — search field: this is a search field, use `TextCapitalization.none` (search should not auto-cap)

5. [ ] Add `textCapitalization: TextCapitalization.sentences` to:
   - `lib/features/session/session_summary_screen.dart` — note field (lines ~443, ~844)
   - `lib/features/session/workout_session_global_timer.dart` — note field (line ~454)
   - `lib/features/calendar/day_session_list_screen.dart` — session note fields (lines ~983, ~991) — audit: confirm both are note-type fields before applying

6. [ ] Confirm no auto-capitalization on numeric fields: verify all `TextField` widgets with `TextInputType.number` or `.numberWithOptions` do NOT have `textCapitalization` set to anything other than `TextCapitalization.none` (the default for numeric keyboards is already none, but make it explicit in `NumericFieldWithDoneBar`'s constructor).

---

### Phase 4: Tests (@developer)

7. [ ] Create `test/keyboard_dismissal_test.dart` with widget tests covering:
   - **Tap-outside dismisses keyboard**: pump a screen with a `TextField`, tap the field to focus it, then tap a non-interactive area, verify `FocusManager.instance.primaryFocus` is null.
   - **Tap interactive element while keyboard is open**: tap a field to open keyboard, then tap a button — verify button's `onPressed` was called AND keyboard is dismissed.
   - **Scroll does not dismiss keyboard**: pump a `ListView` containing a `TextField`, focus the field, trigger a scroll, verify focus is still active.
   - **Return key in multiline inserts newline**: pump a multiline `TextField`, enter text, send `Enter` key event, verify text contains `\n` and focus is retained.

8. [ ] Create `test/numeric_done_bar_test.dart` with widget tests covering:
   - **Done bar appears for numeric input**: pump a `NumericFieldWithDoneBar`, tap to focus, verify a widget matching "Done" label is visible in the tree.
   - **Done bar absent for text input**: pump a plain `TextField` (not `NumericFieldWithDoneBar`), tap to focus, verify no "Done" bar widget is in the tree.
   - **Done bar tap dismisses keyboard**: tap the Done button, verify the field's `FocusNode.hasFocus` becomes false.
   - **Done bar tap preserves field value**: type a value, tap Done, verify the controller's text is unchanged.

9. [ ] Create `test/capitalization_defaults_test.dart` with widget tests covering:
   - **Exercise name field is word-case**: pump `ExerciseEditorScreen` (or the relevant widget), find the exercise name `TextField`, verify `textCapitalization == TextCapitalization.words`.
   - **Period name field is word-case**: same pattern for `CreatePeriodScreen`.
   - **Profile display name is word-case**: same for `ProfileScreen` name dialog.
   - **Session note is sentence-case**: pump `SessionSummaryScreen` or the note widget, find the note `TextField`, verify `textCapitalization == TextCapitalization.sentences`.
   - **Numeric field has no capitalization**: find a `NumericFieldWithDoneBar` instance, verify `textCapitalization == TextCapitalization.none`.
   - **User can override auto-capitalized char**: simulate typing a lowercase character after a capital-triggering event; verify the field does not force-revert it (platform behavior — verify the field does not set `readOnly: true` or similar override).

---

### Files Affected

| File | Change |
|------|--------|
| `lib/app.dart` | Add `builder` with global `GestureDetector` |
| `lib/widgets/inputs/numeric_field_with_done_bar.dart` | **NEW** — done-bar wrapper widget |
| `lib/features/session/workout_session_edit_mode.dart` | Replace 3× numeric `TextField` with `NumericFieldWithDoneBar` |
| `lib/features/routine/routine_setup_screen.dart` | Replace numeric `TextField`; add capitalization to name fields |
| `lib/features/profile/profile_screen.dart` | Replace numeric `TextField`; add capitalization to name field |
| `lib/features/exercise/exercise_editor_screen.dart` | Add `TextCapitalization.words` to name/system fields |
| `lib/features/period/create_period_screen.dart` | Add `TextCapitalization.words` to name field |
| `lib/features/session/session_summary_screen.dart` | Add `TextCapitalization.sentences` to note fields |
| `lib/features/session/workout_session_global_timer.dart` | Add `TextCapitalization.sentences` to note field |
| `lib/features/calendar/day_session_list_screen.dart` | Audit and add appropriate capitalization |
| `lib/widgets/pickers/exercise_picker_dialog.dart` | Confirm `TextCapitalization.none` on search field |
| `test/keyboard_dismissal_test.dart` | **NEW** |
| `test/numeric_done_bar_test.dart` | **NEW** |
| `test/capitalization_defaults_test.dart` | **NEW** |

---

### Notes

- The global `GestureDetector` in `MaterialApp.builder` does not interfere with scroll behavior. Flutter's gesture arena naturally disambiguates scroll drags from taps — the `onTap` callback only fires on a clean tap-up with no movement, so scrolling is unaffected.
- `InlineMetricEditor` uses a drag gesture, not a keyboard. It does not need a Done bar.
- On web (`kIsWeb`), the numeric keyboard doesn't appear (browser handles text input). The `NumericFieldWithDoneBar` overlay can be conditionally suppressed on web using `kIsWeb` to avoid a floating Done button that's unnecessary on desktop browsers.
- The exercise picker's search field (`exercise_picker_dialog.dart`) should use `TextCapitalization.none` — search queries should not be auto-capitalized.
- `day_session_list_screen.dart` has two `TextField` widgets at lines 983 and 991. Developer should audit what these are before assigning capitalization (likely session title + session note).
- For the Done bar's overlay positioning: use `WidgetsBinding.instance.addPostFrameCallback` to calculate the final position after the keyboard insets settle, or use `AnimatedPadding` driven by `MediaQuery.viewInsets.bottom` for a smooth ride-with-keyboard animation.

---

## Progress
- [ ] Phase 1: Global tap-outside-to-dismiss (`app.dart`)
- [ ] Phase 2a: Create `NumericFieldWithDoneBar` widget
- [ ] Phase 2b: Replace numeric TextFields in session, routine, profile
- [ ] Phase 3: Add capitalization to all affected screens
- [ ] Phase 4: Write keyboard_dismissal_test.dart
- [ ] Phase 4: Write numeric_done_bar_test.dart
- [ ] Phase 4: Write capitalization_defaults_test.dart
- [ ] Run all existing tests, confirm no regressions

## Feedback
<!-- Leave empty until a specialist or reviewer adds notes -->
