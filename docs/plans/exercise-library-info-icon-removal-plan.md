# Feature: Remove redundant info icon from exercise library search

> Status: DRAFT awaiting Q&A  
> Next handoff: @developer (Phase 1)  
> Binding conventions: docs/global_conventions.md

## Overview

The exercise library search row includes a trailing info icon (Icons.info_outline, key `exercise_row_details_button`) that opens `ExerciseDetailViewScreen` — the same read-only details surface the user sees when tapping the row itself. This is redundant. Removal is scoped to the library only; the picker's identical icon remains because row-tap selection behavior (pop and exit) makes the info affordance the *only* way to inspect details in that context.

Additionally, a latent defect: `ExerciseDetailViewBody` is a `SingleChildScrollView` with `padding: EdgeInsets.fromLTRB(16, 16, 16, 24)`. When nested inside `ExerciseLibraryDetailScreen`'s outer `SingleChildScrollView` (which carries the same padding), content gets double-padded to 32pt horizontal inset, while the sibling `_ManagementActionBar` gets only 16pt. The fix: eliminate the padding duplication so all siblings align at 16pt.

## Resolved Decisions (Ledger)

**D-1: Scope — info icon removal is library-only.**
- Remove from `lib/features/exercise/exercise_library_screen.dart` (`IconButton` at lines 280–301, method `_openReadOnlyDetails` at lines 306–316, import at line 29).
- Leave `lib/features/exercise/exercise_picker_screen.dart` completely untouched (lines 665–685). In the picker, row-tap pops the exercise and exits; the info icon is the only way to inspect details.
- The class `ExerciseDetailViewScreen` itself is NOT deleted — the picker still uses it.

**D-2: Mechanism for padding alignment — add optional parameter to `ExerciseDetailViewBody`.**
- Add parameter `contentPadding` with default `EdgeInsets.fromLTRB(16, 16, 16, 24)`.
- `ExerciseDetailViewScreen` and picker usage: pass default (or nothing, relying on the default).
- `ExerciseLibraryDetailScreen`: pass `contentPadding: EdgeInsets.zero`.

**D-3: Remove outer padding from `ExerciseLibraryDetailScreen`.**
- `SingleChildScrollView` at line 161 currently carries `padding: EdgeInsets.fromLTRB(16, 16, 16, 24)`.
- Change to `padding: EdgeInsets.zero` — the inner body's `contentPadding` provides the inset.
- Net result: `ExerciseDetailViewBody` content and `_ManagementActionBar` both sit at 16pt inset from the column's edge.

**D-4: Interpretation — "expand the padding" was a misread.**
- User's original request ("expand the padding on the exercise tap screen") was driven by observing misalignment (buttons narrower than content), not by wanting larger insets.
- The confirmed intent: align content and buttons at the same 16pt inset. No padding increase.

## Feature Invariants

- `ExerciseDetailViewScreen` (read-only, used by picker) must render content at exactly 16pt inset — no change to existing behavior or test results.
- `ExerciseLibraryDetailScreen` (tap screen, management surface) must render both metadata content and action buttons at exactly 16pt inset — they must be visually aligned.
- No nested `SingleChildScrollView` side effects (overflow, scroll conflict, layout thrashing) observed during or after the fix.

## Requirements

1. Remove the info icon affordance from exercise library rows only.
2. Remove the dead `_openReadOnlyDetails` method and its import.
3. Eliminate padding duplication in the library detail screen.
4. Align content and action buttons at 16pt inset.
5. Update tests and documentation to reflect the removal.

## Acceptance Criteria

1. Info icon is absent from library exercise rows.
2. Row tap still opens `ExerciseLibraryDetailScreen` without change.
3. Picker exercise rows still have the info icon and still open `ExerciseDetailViewScreen` — pixel-identical rendering.
4. Library detail screen: metadata body and management buttons visually aligned at 16pt padding.
5. All tests pass without modification to test expectations (except removal of icon-tap tests).
6. Header comments updated to remove mention of the removed affordance.

## Scenarios

### S-1: Library row without info icon
- **Fixture**: Exercise library loaded with 3+ exercises (mix of built-in and custom). Exercise picker also loaded with same exercises.
- **Trigger**: User views library screen exercise list, then switches to picker screen.
- **Flow**: 
  1. Library screen: each row displays name, tags, custom marker if applicable.
  2. Picker screen: each row displays name, tags, custom marker if applicable.
  3. Compare row layouts.
- **Expected outcome**: 
  - Library: no trailing icon. Row ends after custom marker (if present) or after name/tag space.
  - Picker: trailing info icon present (Icons.info_outline, 20pt size, 44x44 touch target).
  - Both screens use identical row structure for name/tags; only trailer differs.
- **Edge case of**: none

### S-2: Library row tap opens management screen
- **Fixture**: Exercise library with 1 built-in + 1 custom exercise.
- **Trigger**: User taps an exercise row (anywhere except where the icon was).
- **Flow**:
  1. Tap a row in the middle of the exercise name.
  2. Observe screen transition.
  3. Verify the detail screen opens.
  4. Verify no back behavior has changed.
- **Expected outcome**: Screen pushes `ExerciseLibraryDetailScreen` with the tapped exercise. No icon action. Row tap behavior is unaffected.
- **Edge case of**: none

### S-3: Picker row details icon still works
- **Fixture**: Exercise picker with 3+ exercises.
- **Trigger**: User taps the info icon on a picker row.
- **Flow**:
  1. Tap the trailing info icon (Icons.info_outline) on a row.
  2. Observe screen transition.
  3. Verify content inset (should be 16pt).
  4. Tap back.
  5. Verify picker is still open and row is reachable (no double-pop).
- **Expected outcome**: Icon tap opens `ExerciseDetailViewScreen` with `showAddAction: true` (default). Content renders at 16pt inset. Back pops the detail screen, leaving picker in place. Subsequent row selection via tap works.
- **Edge case of**: none

### S-4: Library tap screen — content and buttons aligned at 16pt
- **Fixture**: Exercise library with 1 custom exercise that has a long description (to ensure scrolling) + muscle groups.
- **Trigger**: User taps the row to open management screen.
- **Flow**:
  1. Tap a library row to open `ExerciseLibraryDetailScreen`.
  2. Visually inspect the metadata body (title, description, discipline, capabilities, muscles).
  3. Scroll down to see the action bar (Edit, Remove buttons or Copy button).
  4. Compare insets of body content and button row.
- **Expected outcome**: 
  - Metadata title and content sections: 16pt left/right inset.
  - Action bar buttons: 16pt left/right inset.
  - Both widgets vertically aligned at the same inset level.
  - No visual misalignment (buttons wider/narrower than content).
- **Edge case of**: none

### S-5: Picker row navigation unchanged
- **Fixture**: Workout session in progress, picker open (user adding an exercise to a set).
- **Trigger**: 
  1. User taps a row to select (not the icon).
  2. Picker pops, exercise is added to session.
- **Flow**: Same as before removal.
- **Expected outcome**: Selection works, picker exits, exercise is added. No change to row-tap behavior.
- **Edge case of**: none

## Iteration 1

### Phase 1: Remove icon, method, and import from library screen (@developer)

1. [ ] Open `lib/features/exercise/exercise_library_screen.dart`.
2. [ ] Remove the `IconButton` widget at lines 280–301 (trailing info icon).
3. [ ] Remove the `_openReadOnlyDetails` method at lines 306–316 (becomes dead code).
4. [ ] Remove the import `import 'exercise_detail_view_screen.dart';` at line 29 (no other references in this file).
5. [ ] Verify no other uses of `ExerciseDetailViewScreen` remain in the file via grep.
6. [ ] Update header comment at lines 13–14 to remove mention of the info-icon affordance and the PR 7 reference that no longer applies.

**Done Criteria** (run until green):
- `flutter analyze lib/features/exercise/exercise_library_screen.dart` — no errors or warnings.
- `flutter test test/exercise_row_density_test.dart` — all tests pass (icon-tap tests will fail until updated; see Phase 2).
- `flutter test test/pr8_exercise_library_test.dart` — all tests pass (same caveat).

**Predicted Files**:
- `lib/features/exercise/exercise_library_screen.dart` (icon, method, import removed; comment updated)

### Phase 2: Add `contentPadding` parameter to `ExerciseDetailViewBody` (@developer)

1. [ ] Open `lib/features/exercise/exercise_detail_view_screen.dart`.
2. [ ] Add optional parameter `final EdgeInsets contentPadding;` to the `ExerciseDetailViewBody` constructor signature (line ~164).
3. [ ] Set default value: `this.contentPadding = const EdgeInsets.fromLTRB(16, 16, 16, 24)`.
4. [ ] Update the `SingleChildScrollView.padding` at line 189 to use `contentPadding` instead of the hardcoded constant.
5. [ ] Verify the constructor is documented (it already is for other parameters; add a brief docstring for `contentPadding`).

**Done Criteria**:
- `flutter analyze lib/features/exercise/exercise_detail_view_screen.dart` — no errors or warnings.
- `flutter test test/pr7_exercise_details_view_test.dart` — all tests pass (no changes to these tests; they use the default).

**Predicted Files**:
- `lib/features/exercise/exercise_detail_view_screen.dart` (parameter added, default applied)

### Phase 3: Update library detail screen to use `contentPadding: EdgeInsets.zero` and remove outer padding (@developer)

1. [ ] Open `lib/features/exercise/exercise_library_detail_screen.dart`.
2. [ ] At line 162, change `SingleChildScrollView` padding from `EdgeInsets.fromLTRB(16, 16, 16, 24)` to `EdgeInsets.zero`.
3. [ ] At line 168 (the `ExerciseDetailViewBody` instantiation), add parameter `contentPadding: EdgeInsets.zero`.
4. [ ] Update header comment at line 4 to remove mention of PR 7 and clarify the layout (one padding source, not nested).

**Done Criteria**:
- `flutter analyze lib/features/exercise/exercise_library_detail_screen.dart` — no errors or warnings.
- `flutter test test/pr8_exercise_library_test.dart` — all tests pass (visual alignment verified; see Phase 4).

**Predicted Files**:
- `lib/features/exercise/exercise_library_detail_screen.dart` (outer padding removed, body parameter added, comment updated)

### Phase 4: Update tests to remove icon-tap expectations and verify alignment (@developer)

Tests to update:

**`test/pr7_exercise_details_view_test.dart`** (lines 153, 208, 279, 478):
- Lines 153, 208: These tap the info icon in the *picker* context (from `test/pr7_exercise_details_view_test.dart` — note the file name). The picker's icon remains unchanged, so these tests stay as-is. **No change needed.**
- Lines 279, 478: These also appear to test icon taps in picker/read-only context. Verify they are not testing the *library* icon. If they test the picker, no change. If they test the library icon, delete those expectations.

**`test/exercise_row_density_test.dart`** (lines 115, 422):
- These test row layout and density. Line 115 and 422 likely find or verify the presence of the info icon.
- Update: Remove assertions that verify `exercise_row_details_button` is present in the library rows.
- Update: Remove any density tests that measure the icon's impact on row height (e.g., multi-line rows with icon).
- Keep: Any picker-related icon tests — the picker is untouched.

**`test/pr8_exercise_library_test.dart`** (line ~479):
- Find all references to `exercise_row_details_button` or icon-tap flows in the library context.
- Remove tests that verify the info icon exists or is tappable.
- Keep: Tests that verify row-tap behavior (opening `ExerciseLibraryDetailScreen`).
- Add: New test verifying content/button alignment at 16pt inset (golden/pixel test or measurement via `Offset` queries, depending on test suite patterns).

1. [ ] Audit `test/pr7_exercise_details_view_test.dart` for icon-tap tests in library context; update if any.
2. [ ] Audit `test/exercise_row_density_test.dart` for icon-presence or density assertions; remove library-icon checks.
3. [ ] Audit `test/pr8_exercise_library_test.dart` for icon-tap tests; remove them.
4. [ ] Add integration test or widget test for alignment: open library detail screen, measure left inset of metadata body and action bar, assert both are 16pt.

**Done Criteria**:
- `flutter test test/pr7_exercise_details_view_test.dart test/exercise_row_density_test.dart test/pr8_exercise_library_test.dart` — all tests pass.
- No lint or analysis warnings.
- New alignment test passes (content and buttons at 16pt).

**Predicted Files**:
- `test/pr7_exercise_details_view_test.dart` (minor updates if library-context icon tests exist; likely no change)
- `test/exercise_row_density_test.dart` (icon-presence checks removed)
- `test/pr8_exercise_library_test.dart` (icon-tap tests removed, alignment test added)

### Phase 5: Final verification and cleanup (@developer)

1. [ ] Run `flutter test` on the full test suite to ensure no regressions.
2. [ ] Verify the picker exercise rows still render the info icon (visual inspection or screenshot test).
3. [ ] Verify the library exercise rows do NOT render the info icon.
4. [ ] Verify library detail screen content and buttons are aligned at 16pt (visual inspection or measurement test).
5. [ ] Verify no dead imports remain in either screen file (grep for `ExerciseDetailViewScreen` in `exercise_library_screen.dart`, confirming it does not appear).
6. [ ] Review the header comments in both screen files to confirm they are up-to-date and no longer mention the removed affordance.

**Done Criteria**:
- `flutter test` passes without failures.
- Visual inspection confirms no regressions (picker icon present, library icon absent, alignment correct).
- No dead code or unused imports remain.
- All header comments are accurate and current.

**Predicted Files**:
- None (verification only)

## Files Affected (whole feature)

- `lib/features/exercise/exercise_library_screen.dart` — icon, method, import removed
- `lib/features/exercise/exercise_detail_view_screen.dart` — `contentPadding` parameter added
- `lib/features/exercise/exercise_library_detail_screen.dart` — outer padding removed, `contentPadding` parameter passed
- `test/exercise_row_density_test.dart` — **NO CHANGE.** Verified picker-only (zero `ExerciseLibraryScreen` references); every `exercise_row_details_button` assertion in it is a picker assertion. Must not be touched.
- `test/pr8_exercise_library_test.dart` — icon-tap tests removed, alignment test added
- `test/pr7_exercise_details_view_test.dart` — likely no change; verify context during Phase 4

## Notes

### Nesting smell acknowledged
The original structure (`SingleChildScrollView` inside `SingleChildScrollView` with duplicate padding) is a code smell. The fix via parameter defaulting is minimal and preserves the existing behavior for read-only consumers. A deeper refactor (moving padding out of `ExerciseDetailViewBody`) was considered but deferred — it would require coordinating three call sites (picker, read-only screen, library detail screen) and risks breaking the picker's scroll offset tracking.

### Padding default choice
`EdgeInsets.fromLTRB(16, 16, 16, 24)` was chosen as the default because:
- Horizontal (16pt) matches `OmniTheme.bottomCTAHorizontalPadding`.
- Top (16pt) provides standard breathing room.
- Bottom (24pt) matches form-spacing conventions and leaves room for the Add button in the read-only screen context.

### Scenario coverage
Scenarios enumerate fixtures comprehensively so test authors can seed exact data:
- S-1: Library + picker comparison (exercises must be identical across both).
- S-2: Library row tap (both built-in and custom).
- S-3: Picker icon tap (requires picker to not exit prematurely; idempotency guard is in `ExerciseDetailViewScreen._onAddPressed`).
- S-4: Alignment verification (long description forces scroll; ensures button bar is visible and measurable).
- S-5: Picker selection flow (orthogonal to info icon).

### Test audit notes
- `test/pr7_exercise_details_view_test.dart` — **confirmed by orchestrator: NO CHANGE.** All four `exercise_row_details_button` taps (lines ~153, ~208, ~279, ~478) build `ExercisePickerScreen`. Out of scope; must still pass unmodified.
- `test/exercise_row_density_test.dart` — **corrected by orchestrator.** Earlier claim that this file covers both picker and library was wrong. `grep -c ExerciseLibraryScreen` returns 0; its `_resolveRow` helper and all icon assertions (lines ~115, ~422) build `ExercisePickerScreen`. Since the picker is out of scope (D-1), this file needs no edit and removing its icon assertions would delete live picker coverage. Leave it alone; it must still pass unmodified.
- `test/pr8_exercise_library_test.dart` — named for PR 8 (Library), directly tests library screen and detail screen. Icon-tap flows are in scope here. Remove those tests.

## Assumption Log

- **A-1**: Fixture construction. Built fixtures explicitly in-test using `_freshRepo()` + `_buildState()` patterns from `pr8_exercise_library_test.dart`. Do not depend on incidental seed-data contents.
- **A-2**: Long-description exercise. Created deterministically (~600 chars via repeated phrase) and pinned surface size with `tester.binding.setSurfaceSize(Size(800, 1200))`.
- **A-3**: Alignment test strategy. Programmatic measurement of render boxes using `closeTo()` assertions (not loose `greaterThanOrEqualTo`). Measure both metadata body and action bar left edges.
- **A-4**: Action bar key. Added `Key('exercise_library_action_bar')` to `_ManagementActionBar` root widget (Container wrapping Row or SizedBox) so test finds it reliably by key.
- **A-5**: S-2 scope. Test asserts existing behavior (row tap already works); no red-first evidence of a bug. Serves as regression guard.
- **A-6**: Test file location. All library scenarios added to `test/pr8_exercise_library_test.dart`.
- **A-7**: Picker scenarios (S-3, S-5) untouched. Coverage verified by picker test files passing unmodified.

## Progress

- [x] **Data Layer Review**: No data-layer changes required. All changes are UI-only (screen files, test files).
- [x] **Phase 0 — Scenario Verification + Tests (MANDATORY)**:
  - [x] Verified scenario register (S-1 through S-5) complete and testable.
  - [x] Wrote Phase 0 tests for S-1 (icon absent), S-2 (row tap regression guard), S-4 (alignment).
  - [x] Added `Key('exercise_library_action_bar')` to `_ManagementActionBar` for reliable test measurement.
  - [x] Baseline: 44 passing across three files; 2349 passing full suite.
  - [x] Phase 0 red-first evidence: S-1 and S-4 fail as designed; S-2 passes (regression guard).
- [x] **Phase 1 — Remove icon, method, and import from library screen**:
  - [x] Removed `IconButton` widget (trailing info icon, lines 274–295).
  - [x] Removed `_openReadOnlyDetails` method (dead code after icon removal).
  - [x] Removed `import 'exercise_detail_view_screen.dart'` (no longer used).
  - [x] Updated header comment to remove mention of info affordance.
  - [x] Verified no dead references remain via grep.
- [x] **Phase 2 — Add `contentPadding` parameter to `ExerciseDetailViewBody`**:
  - [x] Added optional `contentPadding` parameter with default `EdgeInsets.fromLTRB(16, 16, 16, 24)`.
  - [x] Updated `SingleChildScrollView.padding` to use parameter instead of hardcoded constant.
  - [x] Picker and read-only screen usage unchanged (rely on default).
- [x] **Phase 3 — Update library detail screen to use aligned padding**:
  - [x] Kept outer `SingleChildScrollView` padding at `EdgeInsets.fromLTRB(16, 16, 16, 24)`.
  - [x] Passed `contentPadding: EdgeInsets.zero` to `ExerciseDetailViewBody` (eliminates double padding).
  - [x] Updated header comment to clarify single-padding layout.
  - [x] Net result: metadata content and action bar both at 16pt inset.
- [x] **Phase 4 — Tests remain aligned**:
  - [x] No existing library tests to update (icon tap tests were in this file's new tests only).
  - [x] Verified picker-only tests (`pr7_exercise_details_view_test.dart`, `exercise_row_density_test.dart`) unchanged and passing.
- [x] **Phase 5 — Final verification**:
  - [x] Full test suite: **2352 passing, 1 skipped** (all Phase 0 tests now pass).
  - [x] Phase 0 tests all green: S-1 (icon absent), S-2 (row tap works), S-4 (16pt alignment).
  - [x] No regressions: picker icon present and unchanged (verified by unmodified picker tests).
  - [x] Library detail screen: content and buttons visually aligned at 16pt inset.
- [x] **Auto-fix cleanup pass**:
  - [x] Fix 1: Replaced bare `Container` wrappers in `_ManagementActionBar` with direct key attachment on `Row` (custom branch) and `SizedBox` (built-in branch). Key name `exercise_library_action_bar` preserved exactly. Geometry unchanged; S-4 alignment test passes.
  - [x] Fix 2: Ran `dart format` on `exercise_library_detail_screen.dart` to fix indentation (no changes needed after Fix 1 edits).
  - [x] Fix 3: Added doc comment for `contentPadding` field in `ExerciseDetailViewBody` noting the default preserves previous hardcoded padding.
  - [x] Full test suite: **2352 passing, 1 skipped** — all Phase 0 tests including S-4 still pass.
  - [x] `flutter analyze` on both changed files: no issues found.

## Feedback

(No blockers encountered. Implementation complete and verified. All auto-fix changes applied cleanly with zero regression.)
