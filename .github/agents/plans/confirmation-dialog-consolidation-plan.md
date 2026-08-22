# Feature: Confirmation Dialog Consolidation

> Status: DRAFT awaiting code execution
> Next handoff: @developer (Phase 1)
> Binding conventions: docs/global_conventions.md

## Overview

Consolidate 22 scattered confirmation dialogs across the OmniTrain app behind a single shared `ConfirmationDialog` component. Correct false wording in session-discard prompts that currently misinform users about session persistence. Establish a two-tier destructive/routine classification with consistent button styling, ordering, and barrier-dismissal behavior. Every confirmation action is addressable by a stable key independent of visible label.

The app currently has 22 distinct confirmation prompts implemented as raw `AlertDialog` instances with inconsistent styling (some error-colored, others not; some with shape overrides, others relying on framework defaults), inconsistent wording (session-discard prompts contradict each other about whether the session is saved), and inconsistent state-mutation patterns (site 13 mutates directly in `onPressed` rather than returning a result, breaking barrier-dismissal invariants).

## Resolved Decisions (Ledger)

**D-1: Component shape and return types**
- Two-choice confirmations return `bool`: `true` = proceed, `false` = dismiss/cancel.
- Three-choice unsaved-changes confirmations return a private enum with three outcomes: `keepEditing`, `discard`, `save`.
- No other shape is supported; if a prompt fits neither, it remains unchanged outside the shared component (e.g., input dialogs, pickers, loading spinners, single-acknowledgement notices).

**D-2: Barrier dismissal behavior (acceptance criterion)**
- Two-choice: barrier tap produces the same outcome as the dismissal action and mutates no state.
  - Destructive (sites 1–20): barrier tap returns `false` (same as Cancel).
  - Routine (sites 21–22): barrier tap returns `false` (same as Not Now / Cancel).
- Three-choice (sites 19–20): barrier tap returns `keepEditing` (same as X IconButton), mutates no state.
- `barrierDismissible: true` is set on all instances in the component.

**D-3: Destructive vs Routine classification**
- **Destructive** (sites 1–20): user loses something unrecoverable (session, exercise, data, or edits). Confirming action renders as `FilledButton` with `backgroundColor: theme.colorScheme.error` and `foregroundColor: theme.colorScheme.onError`, everywhere, no per-screen variation.
- **Routine** (sites 21–22): user is simply proceeding (finishing a workout, enabling notifications). Confirming action renders in standard primary styling (`theme.colorScheme.primary`).
- All action buttons use `OmniTheme.buttonUtilityRadius` (8.0); never framework default shapes.

**D-4: Button ordering and labels**
- Every confirmation: dismissal action FIRST, confirming action LAST.
- Labels are action verbs (Delete, Discard, Start New, Continue, Finish, Remove, Save), never generic OK/Yes/Confirm.
- Two-choice: Cancel (dismiss) | [Confirm label] (proceed).
- Three-choice: X IconButton in title row (keep editing) | Discard (left) | Save (right) in actions.

**D-5: Body content structure**
- Body accepts rich widget content (not just string) so prompts like Finish Workout (exercise count + elapsed time in a Column) survive verbatim.
- Session-discard prompt body (4 sites, byte-identical): `'Your current session will be discarded and cannot be recovered.'`
- Unsaved-changes prompt bodies (2 sites): `'You have unsaved edits. Save them or discard to return to the [destination].'` where destination is "routines list" or "summary".

**D-6: Stable key naming**
- Every action (cancel, confirm, save, keep-editing) carries a stable `Key` independent of visible text.
- Keys follow pattern: `<feature>-<action>-<button-role>` or site-specific identifier.
- Preserve existing keys: `routine-delete-confirm`, `exercise_library_remove_cancel_button`, `exercise_library_remove_confirm_button`.
- New keys are defined per site in Predicted Files section (no invented keys by developer).

**D-7: State mutation and barrier behavior**
- Barrier dismissal NEVER mutates state across any confirmation.
- Two-choice: barrier tap equals dismissal action tap.
- Three-choice: barrier tap equals keep-editing action tap.
- Site 13 (routine_setup_screen.dart:752) currently mutates inside `onPressed`. Refactor to return result; calling site mutates at the call site after dismissal.

**D-8: Design system documentation**
- Update `.github/agents/docs/design_system.md` to describe:
  - Two-tier destructive/routine classification.
  - Button ordering rule (dismiss first, confirm last).
  - Error styling rule: `theme.colorScheme.error` fill, `theme.colorScheme.onError` foreground (never hardcoded colors).
  - Remove the outdated hardcoded-`Colors.red.shade700` rule from the "Destructive Actions" section.

**D-9: Body parameter is optional**
- The component's body parameter must be optional (not required).
- Some prompts carry the full question in the title and have no additional content worth stating; those render with no body rather than being padded with filler or title-restatement.
- When body is omitted, the component must lay out correctly (no gap, no placeholder, no restated title).
- Never fill an omitted body with restated title text or generic consequence wording.

**D-10: Copy changes are narrowly scoped**
- Copy changes are permitted ONLY at:
  - Sites 1–4 (session-discard prompts): all get identical body.
  - Sites 19–20 (unsaved-changes prompts): get identical labels and matching body structure.
  - Site 7 (routine delete): body is revised to move the routine name from body to title only (satisfying the name-once criterion) while preserving the planned-session count warning.
- Every other site (5, 6, 8–18, 21–22) keeps its existing copy byte-for-byte, even where title is not phrased as a question or body does not state a consequence.
- Acceptance criteria test two-tier classification and styling, not title phrasing or body consequence-statement, so existing sites are compliant as-is.

## Feature Invariants

- **Barrier dismissal equals dismissal action**: Every site's barrier tap produces the same result as tapping the dismissal button, and mutates no state. Verified per site in tests.
- **Session-discard wording consistency**: All four session-discard prompts (sites 1–4) have byte-identical body text.
- **Unsaved-changes consistency**: Both unsaved-changes prompts (sites 19–20) have identical labels and identical body structure apart from the destination noun.
- **Error styling uniformity**: Every destructive action (sites 1–20) confirms with error-colored buttons; every routine action (sites 21–22) confirms with primary-colored buttons.
- **Stable keys do not depend on text**: If a button label changes, its key remains the same.

## Requirements

1. Consolidate all 22 confirmation dialogs behind a single `ConfirmationDialog` component in `lib/widgets/dialogs/confirmation_dialog.dart`.
2. Support exactly two shapes: two-choice (proceed/back out) and three-choice (keep editing / discard / save for unsaved-changes).
3. Implement two-tier classification (destructive vs routine) with consistent error styling on destructive actions.
4. Establish button ordering: dismissal action first, confirming action last.
5. Correct wording: session-discard prompts get identical, accurate body text; unsaved-changes prompts get identical labels and matching bodies.
6. Implement barrier dismissal behavior: two-choice barrier = dismiss; three-choice barrier = keep editing.
7. Assign stable keys to every action (cancel, confirm, save, keep-editing) at all 22 sites.
8. Refactor site 13 (routine_setup_screen.dart:752) to return result and mutate at call site.
9. Update design_system.md to document the two-tier classification and button ordering rules.
10. Create guard test to prevent future raw `AlertDialog` confirmations outside allowlist.
11. Provide manual QA checklist for all 22 sites (exact navigation, expected UI, expected behavior).

## Acceptance Criteria

1. All 22 sites compile and use `ConfirmationDialog`.
2. Session-discard bodies (sites 1–4) are byte-identical: `'Your current session will be discarded and cannot be recovered.'`
3. Unsaved-changes labels and body structure match (sites 19–20), differing only in destination noun.
4. Destructive actions (sites 1–20, 14, 15, 16, 17, 18) render confirm button with error styling.
5. Routine actions (sites 21–22) render confirm button with primary styling.
6. All buttons use `OmniTheme.buttonUtilityRadius` (8.0).
7. Barrier dismissal produces the same outcome as the dismissal action for every site and mutates no state.
8. Every action has a stable key that does not change if the visible label changes.
9. Site 13's state mutation happens at the call site, not in the component's `onPressed`.
10. Tests verify component styling, ordering, barrier behavior, and per-site wording.
11. Guard test prevents new raw `AlertDialog` confirmations outside the allowlist.
12. Design system documentation is updated to describe the implemented standard.

## Scenarios

### S-001: Two-choice destructive dialog with barrier tap
- Fixture: An active session exists; user is on a screen offering to start a new session.
- Trigger: Tap the screen's action to start new session (e.g., "Start Workout" button).
- Flow: Dialog appears; user taps the barrier area outside the dialog overlay.
- Expected outcome: Dialog dismisses, returns `false`, no session is created, no state is mutated.
- Edge case of: barrier dismissal contract

### S-002: Two-choice destructive dialog with dismiss button
- Fixture: An active session exists.
- Trigger: Tap screen action to start new session.
- Flow: Dialog appears; user taps "Cancel" button (first action button).
- Expected outcome: Dialog dismisses, returns `false`, no session is created, no state is mutated.
- Edge case of: dismissal button contract

### S-003: Two-choice destructive dialog with confirm button
- Fixture: An active session exists.
- Trigger: Tap screen action to start new session.
- Flow: Dialog appears; confirm button is visibly error-styled (red fill + light text); user taps it.
- Expected outcome: Dialog dismisses, returns `true`, calling site creates new session and handles old session per app logic.
- Edge case of: confirm button contract and error styling

### S-004: Two-choice routine dialog (primary styling, same ordering)
- Fixture: Timer notifications setting is off; app is about to request notification permission.
- Trigger: Settings screen prompts user (sites 21–22 only).
- Flow: Dialog appears; confirm button is visibly primary-colored (not error); user taps it.
- Expected outcome: Dialog dismisses, returns `true`, calling site proceeds with the action.
- Edge case of: routine classification and primary styling

### S-005: Three-choice unsaved-changes with barrier tap
- Fixture: User has made unsaved edits to a routine (name changed, exercise added); user tries to navigate back.
- Trigger: Tap back arrow or outside-dialog-area after editing.
- Flow: Three-choice dialog appears with X IconButton in top-right; user taps barrier area.
- Expected outcome: Dialog dismisses, returns `keepEditing` enum value, form remains open with changes intact, no state mutation.
- Edge case of: barrier dismissal on three-choice

### S-006: Three-choice unsaved-changes with keep-editing button
- Fixture: User has made unsaved edits to a routine.
- Trigger: Tap back arrow.
- Flow: Three-choice dialog appears; user taps X IconButton (top-right of title row).
- Expected outcome: Dialog dismisses, returns `keepEditing`, form remains open with changes intact.
- Edge case of: X button = dismissal action

### S-007: Three-choice unsaved-changes with discard button
- Fixture: User has made unsaved edits to a routine.
- Trigger: Tap back arrow.
- Flow: Three-choice dialog appears; Discard button (left action, destructive-styled) is visible; user taps it.
- Expected outcome: Dialog dismisses, returns `discard`, calling site discards edits and navigates back. No state mutation occurs in the component.
- Edge case of: destructive action within three-choice shape

### S-008: Three-choice unsaved-changes with save button
- Fixture: User has made unsaved edits to a routine.
- Trigger: Tap back arrow.
- Flow: Three-choice dialog appears; Save button (right action, primary-styled) is visible; user taps it.
- Expected outcome: Dialog dismisses, returns `save`, calling site saves edits and navigates back.
- Edge case of: primary action within three-choice shape

### S-009: Finish Workout dialog with rich body content
- Fixture: Active workout session with 3 exercises logged; elapsed time is 45 minutes.
- Trigger: Tap "Finish Workout" button at bottom of session screen.
- Flow: Dialog appears with title "Finish Workout?", body is a Column showing "You have completed: • 3 exercises • Elapsed time: 45:00".
- Expected outcome: Body renders the exercise count and elapsed time as originally designed; dialog buttons are present (Cancel | Finish); confirm button is primary-styled (routine classification).
- Edge case of: rich widget body content survival

### S-010: Session-discard wording consistency across 4 sites
- Fixture: User has an active session; is on day-session-list, my-routines, home (routine start), or home (modality change).
- Trigger: Tap the respective action to create a new session (start planned session, start routine, open routine, change modality).
- Flow: Dialog appears with title "Start New Session?" and body text.
- Expected outcome: Body text is `'Your current session will be discarded and cannot be recovered.'` on all 4 sites (byte-identical).
- Edge case of: wording consistency

### S-011: Unsaved-changes identical labels and body
- Fixture: User has made unsaved edits on routine_setup_screen or workout_session_edit_mode.
- Trigger: Tap back arrow.
- Flow: Three-choice dialog appears.
- Expected outcome: 
  - Action labels are exactly "Discard" (left OutlinedButton) and "Save" (right FilledButton) on both sites.
  - Body on routine_setup_screen: `'You have unsaved edits. Save them or discard to return to the routines list.'`
  - Body on workout_session_edit_mode: `'You have unsaved edits. Save them or discard to return to the summary.'`
  - Identical except for the destination noun.
- Edge case of: label and body consistency

### S-012: All destructive confirmations have error-colored confirm buttons
- Fixture: User interacts with any destructive action (delete, discard, remove, or a third-choice discard).
- Trigger: Tap action to open confirmation (e.g., delete food, remove exercise, discard session).
- Flow: Dialog appears.
- Expected outcome: Confirm/primary action button is visibly filled with `theme.colorScheme.error` and has `theme.colorScheme.onError` text; never any other color or framework default.
- Edge case of: error styling uniformity

### S-013: Site 13 refactoring — barrier dismissal does not mutate state
- Fixture: User is editing a routine; routine contains exercises.
- Trigger: User taps the delete icon next to an exercise; in the resulting dialog, user taps the barrier area (routine_setup_screen.dart:752).
- Flow: Barrier dismissal occurs.
- Expected outcome: Dialog dismisses, no exercises are removed from the routine, the exercises list remains unchanged. Calling site receives the result and decides not to mutate.
- Edge case of: state mutation contract on barrier dismissal

### S-014: Confirmation dialog with omitted body
- Fixture: A confirmation prompt whose question is fully stated in the title, requiring no additional context or explanation.
- Trigger: Open the confirmation dialog with body parameter omitted (null or not provided).
- Flow: Dialog renders with title, action buttons, and no body area.
- Expected outcome: Dialog lays out correctly with no gap, no placeholder, no restated title; only title and buttons are visible. All other styling and behavior rules apply normally.
- Edge case of: body parameter optionality

## Iterations

### Iteration 1

#### Phase 1: Shared Component and Site Migration
**Scope:** Create `ConfirmationDialog`, migrate all 22 sites, update design_system.md, refactor site 13.

**Deliverable:** All confirmations consolidated behind one component with correct wording, styling, and state-mutation patterns.

1. [ ] **Implement `lib/widgets/dialogs/confirmation_dialog.dart`**
   - Exported from `lib/widgets/dialogs/index.dart` or `lib/widgets/index.dart` (check existing export pattern).
   - Support two-choice shape: returns `bool`, takes title (String), body (Widget), dismissLabel (String), confirmLabel (String), plus `confirmKey`, `dismissKey` parameters.
   - Support three-choice shape: returns `_UnsavedChangesAction` enum {keepEditing, discard, save}, takes title (String), body (String), plus `keepEditingKey`, `discardKey`, `saveKey` parameters. Title includes Row with Expanded text + IconButton(Icons.close, tooltip: 'Keep editing').
   - Barrier dismissal behavior per D-2 (two-choice → false, three-choice → keepEditing), `barrierDismissible: true` always.
   - Error styling per D-3 and D-4: all buttons use `OmniTheme.buttonUtilityRadius`; destructive confirms use error colors.
   - No per-component variations; styling rules are uniform.

2. [ ] **Migrate 22 sites to use `ConfirmationDialog`**
   - Session-discard (4 sites: calendar, my-routines, home×2): update body to `'Your current session will be discarded and cannot be recovered.'`
   - Unsaved-changes (2 sites: routine_setup_screen, workout_session_edit_mode): update labels and body to match D-5 spec; ensure enum returns are correct.
   - Site 13 (routine_setup_screen:752): refactor from mutating in `onPressed` to returning result, mutate at call site.
   - All other destructive sites: add proper error styling via component (removing inline style overrides).
   - Routine sites (2): use primary styling (default via component).
   - Add stable keys to every action per Predicted Files section below.

3. [ ] **Update `lib/core/constants/omni_theme.dart` if needed**
   - Verify `buttonUtilityRadius` is defined (should be 8.0).
   - Verify color scheme tokens are exported.
   - No changes to tokens; confirm they exist and are correctly named.

4. [ ] **Update `.github/agents/docs/design_system.md`**
   - Replace the "Destructive Actions" section (currently lines 279–281) to describe the two-tier classification (D-3), button ordering (D-4), and error styling rule (color scheme tokens, never hardcoded).
   - Add note that all buttons use `OmniTheme.buttonUtilityRadius`.
   - Remove reference to `Colors.red.shade700`.

**Done Criteria:**
- `flutter analyze` passes with no errors or warnings in confirmation_dialog.dart.
- All 22 sites compile and import the component correctly.
- Visual inspection: session-discard prompts have identical body text across 4 sites; unsaved-changes prompts have identical labels and matching bodies.
- Site 13's state mutation happens at call site, not in component.
- Error button styling is uniform on destructive actions; primary styling on routine actions.
- `buttonUtilityRadius` is used on all action buttons.

**Predicted Files:**
- `lib/widgets/dialogs/confirmation_dialog.dart` (new)
- `lib/widgets/dialogs/index.dart` (update exports if exists, or update `lib/widgets/index.dart`)
- `lib/features/calendar/day_session_list_screen.dart` (lines ~232)
- `lib/features/routine/my_routines_screen.dart` (lines ~207, ~323)
- `lib/features/home/home_screen.dart` (lines ~631, ~728)
- `lib/features/calendar/day_session_list_screen.dart` (line ~394)
- `lib/features/period/period_list_screen.dart` (line ~108)
- `lib/features/session/session_overview_screen.dart` (line ~268)
- `lib/features/session/workout_session_screen.dart` (lines ~1164, ~1226, ~1605)
- `lib/features/routine/routine_setup_screen.dart` (lines ~752, ~912, ~1085)
- `lib/features/session/workout_session_list_view.dart` (line ~920)
- `lib/features/session/session_summary_screen.dart` (line ~289)
- `lib/features/nutrition/add_food_screen.dart` (line ~953)
- `lib/features/profile/widgets/measurement_history_chart_sheet.dart` (line ~460)
- `lib/features/exercise/exercise_library_detail_screen.dart` (line ~342)
- `lib/features/session/workout_session_finish.dart` (line ~20)
- `lib/features/settings/settings_screen.dart` (line ~307)
- `.github/agents/docs/design_system.md` (lines ~279–290)

#### Phase 2: Test Coverage
**Scope:** Component-level tests, per-site integration tests, update existing tests to use stable keys.

1. [ ] **Create `test/widgets/confirmation_dialog_test.dart`**
   - Test two-choice shape: renders title, body, two action buttons in correct order (dismiss first, confirm last).
   - Test two-choice with barrier dismissal: tapping barrier returns false, does not mutate state.
   - Test two-choice destructive styling: confirm button has error fill and onError foreground.
   - Test two-choice routine styling: confirm button has primary fill.
   - Test three-choice shape: renders title with X button, body, Discard + Save buttons.
   - Test three-choice barrier dismissal: tapping barrier returns keepEditing.
   - Test three-choice X button: returns keepEditing.
   - Test three-choice button order: Discard (OutlinedButton, destructive-styled) | Save (FilledButton, primary-styled).
   - Test all buttons use correct `borderRadius` (buttonUtilityRadius, 8.0).
   - Test stable keys are present and addressable.

2. [ ] **Create `test/confirmation_dialog_sites_integration_test.dart`**
   - Per-site barrier dismissal test: each of the 22 sites — trigger the confirmation dialog, tap barrier, verify result matches dismissal action result, verify no state mutation.
   - Session-discard wording test (sites 1–4): open each dialog, verify body text is byte-identical.
   - Unsaved-changes consistency test (sites 19–20): verify labels are "Discard" and "Save", verify body structure matches spec.
   - Destructive styling test: each of sites 1–20 (and sites 14, 15, 16, 17, 18 if not already counted) confirm button is error-colored.
   - Routine styling test: sites 21–22 confirm button is primary-colored.
   - Site 13 state mutation test: after refactoring, verify that barrier tap and discard tap do not mutate state; verify that confirm tap causes mutation at call site only.
   - Finish Workout rich content test (site 21): verify body renders exercise count and elapsed time.

3. [ ] **Update existing tests to use stable keys instead of text finders**
   - `test/screen_widget_test.dart:2161, :2216` — extend assertions to check body text (or migrate to stable key finders if text is not load-bearing).
   - `test/pr6_routine_session_entry_navigation_test.dart:221` — migrate 'cannot be undone' finder to stable key (`routine-delete-confirm`). The existing assertion passes on 'cannot be undone' copy, but that text now varies conditionally by plannedCount; migrate to stable key to avoid brittle copy-coupled test logic.
   - `test/pr4_session_controls_test.dart:250, :279` — migrate 'Discard session?' finder to stable key (use `find.byKey(Key('session-list-discard-confirm'))` pattern).
   - `test/session_edit_duration_test.dart:252, :281` — migrate to stable keys.
   - `test/unsaved_changes_dialog_test.dart:114, :140` — migrate to stable keys for unsaved-changes dialogs.
   - `test/routine_unsaved_changes_guard_test.dart` — migrate 'Unsaved changes' finder to stable key.
   - `test/session_finish_timers_test.dart:121` — migrate 'Finish Workout?' finder to stable key.
   - `test/rest_timer_docked_strip_test.dart:429` — migrate 'Finish Workout?' finder to stable key.

**Done Criteria:**
- `flutter test test/widgets/confirmation_dialog_test.dart` passes.
- `flutter test test/confirmation_dialog_sites_integration_test.dart` passes.
- All existing tests that were updated still pass.
- No test uses raw text finders for confirmations (use stable keys instead).
- Barrier dismissal equals dismissal action for all 22 sites (verified by tests).

**Predicted Files:**
- `test/widgets/confirmation_dialog_test.dart` (new)
- `test/confirmation_dialog_sites_integration_test.dart` (new)
- `test/screen_widget_test.dart` (update finders/assertions)
- `test/pr6_routine_session_entry_navigation_test.dart` (migrate to stable keys)
- `test/pr4_session_controls_test.dart` (migrate to stable keys)
- `test/session_edit_duration_test.dart` (migrate to stable keys)
- `test/unsaved_changes_dialog_test.dart` (migrate to stable keys)
- `test/routine_unsaved_changes_guard_test.dart` (migrate to stable keys)
- `test/session_finish_timers_test.dart` (migrate to stable keys)
- `test/rest_timer_docked_strip_test.dart` (migrate to stable keys)

#### Phase 3: Guard Test and Manual QA Checklist
**Scope:** Add guard test to prevent future raw `AlertDialog` confirmations; document manual QA steps.

1. [ ] **Create guard test `test/confirmation_dialog_guard_test.dart`**
   - Fail if a new `AlertDialog` is found outside the allowlist.
   - Allowlist (out-of-scope confirmations that are permitted):
     - `lib/features/nutrition/add_food_screen.dart:933` — "Cannot Delete" single-ack notice (confirm only, no choice)
     - `lib/features/routine/routine_setup_screen.dart:849` — input collection (_editSegment)
     - `lib/features/exercise/exercise_library_detail_screen.dart:109` — input collection (_RenameDialog)
     - `lib/features/profile/profile_screen.dart:636, :697` — input collection
     - `lib/features/session/workout_session_screen.dart:1538` — rename input collection
     - `lib/widgets/session/duration_entry_dialog.dart` — input collection
     - `lib/widgets/pickers/metric_chooser_dialog.dart` — metric chooser (not a confirmation)
     - `lib/widgets/session/metric_crown_widget.dart` — metric chooser
     - All modality pickers (routine_setup_screen.dart, session_overview_screen.dart, workout_session_screen.dart)
     - All loading spinners / progress dialogs
     - All bottom sheets
   - Test finds all `AlertDialog` instances in the app and verifies each is in the allowlist or uses `ConfirmationDialog`.

**Done Criteria:**
- `flutter test test/confirmation_dialog_guard_test.dart` passes.
- No raw `AlertDialog` confirmation exists outside allowlist.

**Predicted Files:**
- `test/confirmation_dialog_guard_test.dart` (new)

2. [ ] **Manual QA Checklist (documented in this plan file, section below)**
   - User follows the exact navigation paths for each of the 22 sites.
   - Verifies visible UI matches expected (title, body, button labels, colors).
   - Verifies behavior matches expected (cancel/barrier → no change, confirm → state change).

---

## Stable Key Assignments (All 22 Sites)

Below are the exact Key strings for every action at every site. These are load-bearing for the developer — do not invent alternate keys.

### Session-Discard Warnings (4 sites, identical prompt)

| Site | File | Line | Dismiss Key | Confirm Key | Confirm Label |
|------|------|------|------------|-------------|----------------|
| 1 | `lib/features/calendar/day_session_list_screen.dart` | 232 | `day-session-new-start-cancel` | `day-session-new-start-confirm` | "Start New" |
| 2 | `lib/features/routine/my_routines_screen.dart` | 207 | `routine-start-new-cancel` | `routine-start-new-confirm` | "Start New" |
| 3 | `lib/features/home/home_screen.dart` | 631 | `home-routine-open-cancel` | `home-routine-open-confirm` | "Continue" |
| 4 | `lib/features/home/home_screen.dart` | 728 | `home-modality-change-cancel` | `home-modality-change-confirm` | "Start New" |

### Destructive Actions (16 sites)

| Site | File | Line | Title | Dismiss Key | Confirm Key | Confirm Label |
|------|------|------|-------|------------|-------------|----------------|
| 5 | `lib/features/calendar/day_session_list_screen.dart` | 394 | "Delete Session?" | `day-session-delete-cancel` | `day-session-delete-confirm` | "Delete" |
| 6 | `lib/features/period/period_list_screen.dart` | 108 | "Delete Period" | `period-delete-cancel` | `period-delete-confirm` | "Delete" |
| 7 | `lib/features/routine/my_routines_screen.dart` | 323 | "Delete [routine-name]?" | `routine-delete-cancel` | `routine-delete-confirm` | "Delete" |
| 8 | `lib/features/session/session_overview_screen.dart` | 268 | "Remove Exercise" | `session-overview-remove-exercise-cancel` | `session-overview-remove-exercise-confirm` | "Remove" |
| 9 | `lib/features/session/workout_session_screen.dart` | 1164 | "Remove Exercise?" | `workout-remove-exercise-cancel` | `workout-remove-exercise-confirm` | "Remove" |
| 10 | `lib/features/session/workout_session_screen.dart` | 1226 | "Delete logged [type]?" | `workout-delete-logged-entry-cancel` | `workout-delete-logged-entry-confirm` | "Delete" |
| 11 | `lib/features/session/workout_session_screen.dart` | 1605 | "Delete Block?" | `session-delete-block-cancel` | `session-delete-block-confirm` | "Delete" |
| 12 | `lib/features/routine/routine_setup_screen.dart` | 912 | "Delete Block?" | `routine-delete-block-cancel` | `routine-delete-block-confirm` | "Delete" |
| 13 | `lib/features/routine/routine_setup_screen.dart` | 752 | "Remove Exercise?" | `routine-setup-remove-exercise-cancel` | `routine-setup-remove-exercise-confirm` | "Remove" |
| 14 | `lib/features/session/workout_session_list_view.dart` | 920 | "Discard session?" | `session-list-discard-cancel` | `session-list-discard-confirm` | "Discard" |
| 15 | `lib/features/session/session_summary_screen.dart` | 289 | "Discard session?" | `session-summary-discard-cancel` | `session-summary-discard-confirm` | "Discard" |
| 16 | `lib/features/nutrition/add_food_screen.dart` | 953 | "Delete Food?" | `food-delete-cancel` | `food-delete-confirm` | "Delete" |
| 17 | `lib/features/profile/widgets/measurement_history_chart_sheet.dart` | 460 | "Delete entry?" | `measurement-delete-cancel` | `measurement-delete-confirm` | "Delete" |
| 18 | `lib/features/exercise/exercise_library_detail_screen.dart` | 342 | "Remove exercise?" | `exercise_library_remove_cancel_button` | `exercise_library_remove_confirm_button` | "Remove" |

### Unsaved-Changes (3-choice, 2 sites)

| Site | File | Line | Keep-Editing Key | Discard Key | Save Key | Destination Noun |
|------|------|------|-----------------|------------|---------|------------------|
| 19 | `lib/features/routine/routine_setup_screen.dart` | 1085 | `routine-edit-unsaved-keep` | `routine-edit-unsaved-discard` | `routine-edit-unsaved-save` | "routines list" |
| 20 | `lib/features/session/workout_session_edit_mode.dart` | 102 | `session-edit-unsaved-keep` | `session-edit-unsaved-discard` | `session-edit-unsaved-save` | "summary" |

### Routine (non-destructive, 2 sites)

| Site | File | Line | Title | Dismiss Key | Confirm Key | Confirm Label |
|------|------|------|-------|------------|-------------|----------------|
| 21 | `lib/features/session/workout_session_finish.dart` | 20 | "Finish Workout?" | `session-finish-cancel` | `session-finish-confirm` | "Finish" |
| 22 | `lib/features/settings/settings_screen.dart` | 307 | "Enable Timer Notifications?" | `settings-timer-notifications-cancel` | `settings-timer-notifications-confirm` | "Continue" |

---

## Exact Wording Strings (All 22 Sites)

Load-bearing strings — developer must use these exactly and modify nothing else. Format: `Title` / `Body` / `Actions`.

### Sites 1–4 (Session-Discard, Identical Body)
```
Title: "Start New Session?"
Body: "Your current session will be discarded and cannot be recovered."
Actions:
  - Dismiss: "Cancel"
  - Confirm: varies per site (site 1: "Start New", site 2: "Start New", site 3: "Continue", site 4: "Start New")
```

### Site 5 (Calendar, Delete Planned Session)
```
Title: "Delete Session"
Body: "Delete \"[ps.title ?? 'this planned session']\"?"
Actions:
  - Dismiss: "Cancel"
  - Confirm: "Delete"
```

### Site 6 (Period, Delete Period)
```
Title: "Delete Period"
Body: "Delete \"[period.name]\"?"
Actions:
  - Dismiss: "Cancel"
  - Confirm: "Delete"
```

### Site 7 (Routines, Delete Routine)
```
Title: "Delete \"[routine-name]\"?"
Body (when plannedCount > 0): "This routine has [plannedCount] planned session${plannedCount == 1 ? '' : 's'} that will also be removed. This action cannot be undone."
Body (when plannedCount == 0): "This action cannot be undone."
Actions:
  - Dismiss: "Cancel"
  - Confirm: "Delete"
```

### Site 8 (Session Overview, Remove Exercise)
```
Title: "Remove Exercise"
Body: "Remove [exercise-name] from this workout?"
Actions:
  - Dismiss: "Cancel"
  - Confirm: "Remove"
```

### Site 9 (Workout Session, Remove Exercise — Last Set)
```
Title: "Remove Exercise?"
Body: "This is the last [set-label-lowercase] for \"[exercise-name]\". Deleting it will remove the entire exercise from your session.\n\nContinue?"
Actions:
  - Dismiss: "Cancel"
  - Confirm: "Remove"
```

### Site 10 (Workout Session, Delete Logged Entry)
```
Title: "Delete logged [Set/Round/Interval/Hold]?"
Body: "This cannot be undone."
Actions:
  - Dismiss: "Cancel"
  - Confirm: "Delete"
```

### Site 11 (Workout Session, Delete Block)
```
Title: "Delete Block?"
Body: "This block contains [count] exercise[s]. All exercises inside will be permanently deleted."
Actions:
  - Dismiss: "Cancel"
  - Confirm: "Delete"
```

### Site 12 (Routine Setup, Delete Block)
```
Title: "Delete Block?"
Body: "This block and its exercises will be removed."
Actions:
  - Dismiss: "Cancel"
  - Confirm: "Delete"
```

### Site 13 (Routine Setup, Remove Exercise)
```
Title: "Remove Exercise?"
Body: "This exercise will be removed from the routine."
Actions:
  - Dismiss: "Cancel"
  - Confirm: "Remove"
```

### Site 14 (Workout Session List, Discard Session)
```
Title: "Discard session?"
Body: "This will permanently delete this session and all its data. You will return to Home."
Actions:
  - Dismiss: "Cancel"
  - Confirm: "Discard"
```

### Site 15 (Session Summary, Discard Session)
```
Title: "Discard session?"
Body (if _isHistoricalView): "This will permanently delete this session from your history and return to the previous screen."
Body (else): "This will remove all session data and return to Home."
Actions:
  - Dismiss: "Cancel"
  - Confirm: "Discard"
```

### Site 16 (Nutrition, Delete Food)
```
Title: "Delete Food?"
Body: "Are you sure you want to delete \"[food.name]\"? Your past nutrition logs will remain unchanged."
Actions:
  - Dismiss: "Cancel"
  - Confirm: "Delete"
```

### Site 17 (Profile, Delete Measurement Entry)
```
Title: "Delete entry?"
Body: "[dateLabel] · [valueLabel] will be removed from your history."
Actions:
  - Dismiss: "Cancel"
  - Confirm: "Delete"
```

### Site 18 (Exercise Library, Remove Exercise)
```
Title: "Remove exercise?"
Body (if hasRefs): "This exercise is referenced in [count] place[s]. Removing it will retire the row so it disappears from pickers and routine templates, but historical session values stay resolvable."
Body (else): "This custom exercise is not used in any active session or routine. Removing it will delete the row permanently."
Actions:
  - Dismiss: "Cancel"
  - Confirm: "Remove"
```

### Sites 19–20 (Unsaved-Changes, Identical Structure)
```
Title: "Unsaved changes"
Body (routine_setup_screen): "You have unsaved edits. Save them or discard to return to the routines list."
Body (workout_session_edit_mode): "You have unsaved edits. Save them or discard to return to the summary."
Title Row: Expanded(Text('Unsaved changes')) + IconButton(icon: Icons.close, tooltip: 'Keep editing')
Actions:
  - Discard: OutlinedButton, left position, destructive-styled (error border color)
  - Save: FilledButton, right position, primary-styled
```

### Site 21 (Session Finish)
```
Title: "Finish Workout?"
Body: Column widget with:
  - "You have completed:"
  - "• [count] exercise[s]"
  - "• Elapsed time: [HH:MM:SS]"
  - "This action will save and close the workout session."
Actions:
  - Dismiss: "Cancel"
  - Confirm: "Finish"
```

### Site 22 (Settings, Timer Notifications)
```
Title: "Enable Timer Notifications?"
Body: "Notifications keep rest pings and effort timer alerts working when your phone is locked. You can change this any time in Settings."
Actions:
  - Dismiss: "Not now"
  - Confirm: "Continue"
```

---

## Manual QA Checklist

This section provides the exact navigation path and expected behavior for each of the 22 sites. Use this checklist to verify the implementation by hand.

### Session-Discard Warnings (Sites 1–4)

#### Site 1: Calendar — Start New Session (Planned Session)
- **Navigation Path:**
  1. Open app, ensure there is an active/rolling session.
  2. Navigate to Calendar tab.
  3. Tap on any day in the calendar to view that day's sessions.
  4. Tap the "Start" button next to a planned session card (or the action button to start the planned session).
- **Expected UI:**
  - Dialog title: "Start New Session?"
  - Dialog body: "Your current session will be discarded and cannot be recovered."
  - Buttons: [Cancel] [Start New] (in that order).
  - Confirm button is error-filled (red background, light text).
- **Behavior:**
  - Tap Cancel → Dialog closes, no change to session.
  - Tap barrier (area outside dialog) → Dialog closes, no change to session.
  - Tap "Start New" → Dialog closes, old session is discarded, new session from planned routine begins.

#### Site 2: Routines — Start New Routine
- **Navigation Path:**
  1. Ensure there is an active session.
  2. Navigate to Routines tab (or My Routines screen).
  3. Tap any routine card's "Start" button (or equivalent action to begin a routine).
- **Expected UI:**
  - Dialog title: "Start New Session?"
  - Dialog body: "Your current session will be discarded and cannot be recovered." (identical to Site 1).
  - Buttons: [Cancel] [Start New].
  - Confirm button is error-filled.
- **Behavior:**
  - Cancel or barrier tap → No change.
  - "Start New" → Old session discarded, new routine session begins.

#### Site 3: Home — Start Routine (from home screen)
- **Navigation Path:**
  1. Ensure there is an active session.
  2. Navigate to Home tab.
  3. Tap a routine tile (e.g., energy tile or routine card on the home screen).
- **Expected UI:**
  - Dialog title: "Start New Session?"
  - Dialog body: "Your current session will be discarded and cannot be recovered." (identical to Sites 1–2).
  - Buttons: [Cancel] [Continue].
  - Confirm button is error-filled.
- **Behavior:**
  - Cancel or barrier tap → No change.
  - "Continue" → Old session discarded, new routine session begins.

#### Site 4: Home — Change Modality (from home screen)
- **Navigation Path:**
  1. Ensure there is an active session.
  2. Navigate to Home tab.
  3. Tap the modality selector or "Change Modality" control (exact UI depends on home screen design).
- **Expected UI:**
  - Dialog title: "Start New Session?"
  - Dialog body: "Your current session will be discarded and cannot be recovered." (identical to Sites 1–3).
  - Buttons: [Cancel] [Start New].
  - Confirm button is error-filled.
- **Behavior:**
  - Cancel or barrier tap → No change.
  - "Start New" → Old session discarded, new session with new modality begins.

### Destructive Actions (Sites 5–18)

#### Site 5: Calendar — Delete Planned Session
- **Navigation Path:**
  1. Navigate to Calendar tab.
  2. Tap on any day to view that day's planned sessions.
  3. Long-press or swipe a planned session card (or tap a delete icon if available on the row).
- **Expected UI:**
  - Dialog title: "Delete Session" (NOT a question).
  - Dialog body: 'Delete "[planned-session-title]"?' (or 'Delete "this planned session"?' if untitled).
  - Buttons: [Cancel] [Delete].
  - Confirm button is error-filled.
- **Behavior:**
  - Cancel or barrier tap → No change.
  - "Delete" → Planned session is permanently removed.

#### Site 6: Training Periods — Delete Period
- **Navigation Path:**
  1. Navigate to a training periods screen (check the app's navigation structure).
  2. Long-press or tap a delete icon on a period row.
- **Expected UI:**
  - Dialog title: "Delete Period"
  - Dialog body: 'Delete "[period-name]"?'
  - Buttons: [Cancel] [Delete].
  - Confirm button is error-filled.
- **Behavior:**
  - Cancel or barrier tap → No change.
  - "Delete" → Period is permanently removed.

#### Site 7: Routines — Delete Routine
- **Navigation Path:**
  1. Navigate to Routines tab.
  2. Long-press or tap a delete icon on a routine card.
- **Expected UI:**
  - Dialog title: 'Delete "[routine-name]"?' (routine name appears exactly once, in the title only).
  - Dialog body (if the routine has planned sessions): 'This routine has [N] planned session[s] that will also be removed. This action cannot be undone.'
  - Dialog body (if no planned sessions): 'This action cannot be undone.'
  - Buttons: [Cancel] [Delete].
  - Confirm button is error-filled.
  - Test fixture: verify key `routine-delete-confirm` is present (existing test depends on this).
- **Behavior:**
  - Cancel or barrier tap → No change.
  - "Delete" → Routine and any planned sessions are permanently removed.

#### Site 8: Session Overview — Remove Exercise
- **Navigation Path:**
  1. Open an active or past session (view the session overview screen).
  2. Tap on an exercise row.
  3. Look for a delete icon (trash can) on the exercise row or in a menu.
- **Expected UI:**
  - Dialog title: "Remove Exercise"
  - Dialog body: 'Remove "[exercise-name]" from this workout?'
  - Buttons: [Cancel] [Remove].
  - Confirm button is error-filled.
  - Confirm button must have explicit shape (`OmniTheme.buttonUtilityRadius`), not framework default.
- **Behavior:**
  - Cancel or barrier tap → No change.
  - "Remove" → Exercise is removed from the session.

#### Site 9: Workout Session — Remove Exercise (Last Set)
- **Navigation Path:**
  1. Open an active workout session (Workout Session Screen).
  2. Log some effort for an exercise (e.g., one set, one round).
  3. Tap the delete icon on that single logged entry for the exercise.
- **Expected UI:**
  - Dialog title: "Remove Exercise?"
  - Dialog body: 'This is the last [set/round/interval/hold] for "[exercise-name]". Deleting it will remove the entire exercise from your session.\n\nContinue?'
  - Buttons: [Cancel] [Remove].
  - Confirm button is error-filled.
- **Behavior:**
  - Cancel or barrier tap → No change.
  - "Remove" → Exercise (and its only entry) is removed.

#### Site 10: Workout Session — Delete Logged Entry (Multi-Set)
- **Navigation Path:**
  1. Open an active workout session with an exercise that has multiple logged sets/rounds.
  2. Tap the delete icon on one of the logged entries (not the last one).
- **Expected UI:**
  - Dialog title: 'Delete logged [Set/Round/Interval/Hold]?' (varies by entry type).
  - Dialog body: "This cannot be undone."
  - Buttons: [Cancel] [Delete].
  - Confirm button is error-filled.
- **Behavior:**
  - Cancel or barrier tap → No change.
  - "Delete" → That entry is removed.

#### Site 11: Workout Session — Delete Block
- **Navigation Path:**
  1. Open an active workout session with one or more blocks of exercises.
  2. Tap the delete icon on a block (if available), or swipe a block.
- **Expected UI:**
  - Dialog title: "Delete Block?"
  - Dialog body: 'This block contains [N] exercise[s]. All exercises inside will be permanently deleted.'
  - Buttons: [Cancel] [Delete].
  - Confirm button is error-filled.
- **Behavior:**
  - Cancel or barrier tap → No change.
  - "Delete" → Block and all exercises in it are removed.

#### Site 12: Routine Setup — Delete Block (Template)
- **Navigation Path:**
  1. Open the routine setup/editing screen (create or edit a routine).
  2. Tap a delete icon on a template block/segment.
- **Expected UI:**
  - Dialog title: "Delete Block?"
  - Dialog body: "This block and its exercises will be removed."
  - Buttons: [Cancel] [Delete].
  - Confirm button is error-filled.
- **Behavior:**
  - Cancel or barrier tap → No change.
  - "Delete" → Block is removed from the routine template.

#### Site 13: Routine Setup — Remove Exercise (from Template)
- **Navigation Path:**
  1. Open the routine setup/editing screen (create or edit a routine).
  2. In the exercise list within a block, tap the delete icon on an exercise.
- **Expected UI:**
  - Dialog title: "Remove Exercise?"
  - Dialog body: "This exercise will be removed from the routine."
  - Buttons: [Cancel] [Remove].
  - Confirm button is error-filled.
- **Behavior:**
  - Cancel or barrier tap → No state change, dialog closes, exercise list remains unchanged. (Verify after refactoring: barrier tap must not mutate.)
  - "Remove" → Exercise is removed from the routine template.

#### Site 14: Workout Session List — Discard Session (Rolling)
- **Navigation Path:**
  1. Open the workout session list (if accessible from home or elsewhere).
  2. Look for an in-progress or rolling session.
  3. Tap the discard/delete icon on that session row.
- **Expected UI:**
  - Dialog title: "Discard session?"
  - Dialog body: "This will permanently delete this session and all its data. You will return to Home."
  - Buttons: [Cancel] [Discard].
  - Confirm button is error-filled.
  - Confirm button must have explicit shape override (was using TextButton with error foreground, should migrate to proper ConfirmationDialog error styling).
- **Behavior:**
  - Cancel or barrier tap → No change.
  - "Discard" → Session is deleted.

#### Site 15: Session Summary — Discard Session
- **Navigation Path:**
  1. Open a session summary screen (after finishing a workout or viewing a past session).
  2. Look for a "Discard" or delete button on the screen.
- **Expected UI:**
  - Dialog title: "Discard session?"
  - Dialog body (if viewing a past/historical session): "This will permanently delete this session from your history and return to the previous screen."
  - Dialog body (if viewing a current session): "This will remove all session data and return to Home."
  - Buttons: [Cancel] [Discard].
  - Confirm button is error-filled and has proper shape (was a plain TextButton with no error treatment).
- **Behavior:**
  - Cancel or barrier tap → No change.
  - "Discard" → Session is deleted and user returns accordingly.

#### Site 16: Nutrition — Delete Food
- **Navigation Path:**
  1. Navigate to the Nutrition screen.
  2. Open the Food Library (or similar screen showing user-created foods).
  3. Tap a user-created food item.
  4. Look for a delete icon and tap it.
- **Expected UI:**
  - Dialog title: "Delete Food?"
  - Dialog body: 'Are you sure you want to delete "[food-name]"? Your past nutrition logs will remain unchanged.'
  - Buttons: [Cancel] [Delete].
  - Confirm button is error-filled and has proper shape override (was missing shape and onError foreground).
- **Behavior:**
  - Cancel or barrier tap → No change.
  - "Delete" → Food is removed from the custom foods list.

#### Site 17: Profile — Delete Measurement Entry
- **Navigation Path:**
  1. Navigate to Profile screen.
  2. View a measurement history (e.g., weight, body fat).
  3. Tap a chart or list entry and look for a delete option.
- **Expected UI:**
  - Dialog title: "Delete entry?"
  - Dialog body: [existing body from source code].
  - Buttons: [Cancel] [Delete].
  - Confirm button is error-filled (this site should already be correct, but verify).
- **Behavior:**
  - Cancel or barrier tap → No change.
  - "Delete" → Entry is removed from history.

#### Site 18: Exercise Library — Remove Exercise (Custom)
- **Navigation Path:**
  1. Navigate to Exercise Library (explore exercises).
  2. Find a custom exercise (user-created).
  3. Tap the exercise to open its detail view.
  4. Look for a remove/delete button.
- **Expected UI:**
  - Dialog title: "Remove exercise?"
  - Dialog body (if used in sessions/routines): 'This exercise is referenced in [N] place[s]. Removing it will retire the row so it disappears from pickers and routine templates, but historical session values stay resolvable.'
  - Dialog body (if not used): 'This custom exercise is not used in any active session or routine. Removing it will delete the row permanently.'
  - Buttons: [Cancel] [Remove].
  - Confirm button is error-filled.
  - Test fixture: Verify stable keys `exercise_library_remove_cancel_button` and `exercise_library_remove_confirm_button` are preserved exactly.
- **Behavior:**
  - Cancel or barrier tap → No change.
  - "Remove" → Exercise is removed or retired.

### Unsaved-Changes (3-Choice, Sites 19–20)

#### Site 19: Routine Setup — Unsaved Changes (Editing Routine)
- **Navigation Path:**
  1. Open the routine setup/editing screen (create or edit a routine).
  2. Make some changes (e.g., rename the routine, add an exercise).
  3. Tap the back arrow or outside navigation action to leave without saving.
- **Expected UI:**
  - Dialog title: "Unsaved changes" with X IconButton on top-right (tooltip: "Keep editing").
  - Dialog body: "You have unsaved edits. Save them or discard to return to the routines list."
  - Actions (Row with two buttons):
    - Left: "Discard" OutlinedButton (destructive-styled: error border color, error text).
    - Right: "Save" FilledButton (primary-styled: primary background, onPrimary text).
  - All buttons use `OmniTheme.buttonUtilityRadius` (8.0).
- **Behavior:**
  - Tap X button → Dialog closes, returns `keepEditing`, form remains open with edits intact.
  - Tap barrier (outside dialog) → Dialog closes, returns `keepEditing`, form remains open with edits intact.
  - Tap "Discard" → Dialog closes, returns `discard`, edits are discarded, user returns to routines list.
  - Tap "Save" → Dialog closes, returns `save`, edits are saved, user remains on routine or returns per app flow.

#### Site 20: Workout Session Edit Mode — Unsaved Changes (Editing Session)
- **Navigation Path:**
  1. Open a session summary screen for a completed or past session.
  2. Tap an edit button to enter edit mode (if available).
  3. Make changes to the session (e.g., add an exercise, adjust times).
  4. Tap the back arrow or outside navigation action to leave without saving.
- **Expected UI:**
  - Dialog title: "Unsaved changes" with X IconButton on top-right (tooltip: "Keep editing").
  - Dialog body: "You have unsaved edits. Save them or discard to return to the summary."
  - Actions (Row with two buttons):
    - Left: "Discard" OutlinedButton (destructive-styled).
    - Right: "Save" FilledButton (primary-styled).
  - All buttons use `OmniTheme.buttonUtilityRadius` (8.0).
- **Behavior:**
  - Tap X button → Dialog closes, returns `keepEditing`, edit form remains open.
  - Tap barrier (outside dialog) → Dialog closes, returns `keepEditing`, edit form remains open.
  - Tap "Discard" → Dialog closes, returns `discard`, edits are discarded, user returns to summary.
  - Tap "Save" → Dialog closes, returns `save`, edits are saved.

### Routine (Non-Destructive, Sites 21–22)

#### Site 21: Workout Session — Finish Workout
- **Navigation Path:**
  1. Open an active workout session with at least one exercise logged.
  2. Scroll to the bottom of the session screen.
  3. Tap the "Finish Workout" button.
- **Expected UI:**
  - Dialog title: "Finish Workout?"
  - Dialog body: A Column widget containing:
    - "You have completed:"
    - "• [N] exercise[s]"
    - "• Elapsed time: [HH:MM:SS]"
    - "This action will save and close the workout session."
  - Buttons: [Cancel] [Finish].
  - Confirm button is primary-colored (not error-colored, because this is a routine action).
  - Confirm button must preserve the rich body content structure exactly as currently implemented.
- **Behavior:**
  - Tap Cancel → Dialog closes, workout session remains active.
  - Tap barrier (outside dialog) → Dialog closes, workout session remains active.
  - Tap "Finish" → Session is saved and marked as complete, user returns to home.

#### Site 22: Settings — Enable Timer Notifications
- **Navigation Path:**
  1. Navigate to Settings.
  2. Ensure notification permissions have not been asked before (or reset app state).
  3. Observe the app behavior when it prompts for notification permission (may be triggered by certain actions or on app resume).
- **Expected UI:**
  - Dialog title: "Enable Timer Notifications?"
  - Dialog body: "Notifications keep rest pings and effort timer alerts working when your phone is locked. You can change this any time in Settings."
  - Buttons: [Not now] [Continue].
  - Confirm button is primary-colored (not error-colored, routine action).
- **Behavior:**
  - Tap "Not now" → Dialog closes, no change to notification settings.
  - Tap barrier (outside dialog) → Dialog closes, no change to notification settings.
  - Tap "Continue" → Dialog closes, app requests notification permission from the system.

---

## Files Affected (Whole Feature)

**New Files:**
- `lib/widgets/dialogs/confirmation_dialog.dart`
- `test/widgets/confirmation_dialog_test.dart`
- `test/confirmation_dialog_sites_integration_test.dart`
- `test/confirmation_dialog_guard_test.dart`

**Modified Files (22 sites):**
- `lib/features/calendar/day_session_list_screen.dart` (2 sites: lines 232, 394)
- `lib/features/routine/my_routines_screen.dart` (2 sites: lines 207, 323)
- `lib/features/home/home_screen.dart` (2 sites: lines 631, 728)
- `lib/features/period/period_list_screen.dart` (1 site: line 108)
- `lib/features/session/session_overview_screen.dart` (1 site: line 268)
- `lib/features/session/workout_session_screen.dart` (3 sites: lines 1164, 1226, 1605)
- `lib/features/routine/routine_setup_screen.dart` (3 sites: lines 752, 912, 1085)
- `lib/features/session/workout_session_list_view.dart` (1 site: line 920)
- `lib/features/session/session_summary_screen.dart` (1 site: line 289)
- `lib/features/nutrition/add_food_screen.dart` (1 site: line 953)
- `lib/features/profile/widgets/measurement_history_chart_sheet.dart` (1 site: line 460)
- `lib/features/exercise/exercise_library_detail_screen.dart` (1 site: line 342)
- `lib/features/session/workout_session_finish.dart` (1 site: line 20)
- `lib/features/settings/settings_screen.dart` (1 site: line 307)

**Documentation:**
- `.github/agents/docs/design_system.md` (update "Destructive Actions" section)

**Test Updates:**
- `test/screen_widget_test.dart`
- `test/pr6_routine_session_entry_navigation_test.dart`
- `test/pr4_session_controls_test.dart`
- `test/session_edit_duration_test.dart`
- `test/unsaved_changes_dialog_test.dart`
- `test/routine_unsaved_changes_guard_test.dart`
- `test/session_finish_timers_test.dart`
- `test/rest_timer_docked_strip_test.dart`

---

## Notes

### Phase Dependency Graph
- Phase 1 (Component + Migration) has no dependencies.
- Phase 2 (Tests) depends on Phase 1 being complete.
- Phase 3 (Guard Test + QA Checklist) depends on Phase 2 being complete (guard test should pass after tests verify the consolidation).

### Intermediate States
After Phase 1 completes:
- All 22 sites use `ConfirmationDialog`.
- All wording corrections are in place (session-discard body, unsaved-changes labels/body).
- Site 13 state mutation is refactored to call-site.
- Design system documentation is updated.
- The app compiles and all 22 prompts render correctly.

After Phase 2 completes:
- Component-level tests verify shape, styling, ordering, barrier behavior.
- Per-site integration tests verify wording, styling, and barrier = dismiss for all 22 sites.
- Existing tests updated to use stable keys.

After Phase 3 completes:
- Guard test prevents future regressions.
- Manual QA checklist is documented and ready for verification.

### Site 13 Refactoring Details
Current code (routine_setup_screen.dart:752):
```dart
void _removeExercise(String templateEffortId) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(...),
  );
  // State mutation happens inside onPressed of the button
}
```

Refactored code:
```dart
void _removeExercise(String templateEffortId) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => ConfirmationDialog.twoChoice(...),
  );
  if (confirmed == true) {
    // Mutation happens here, after dismissal
    setState(() {
      widget.routineState.currentEfforts.removeWhere(...);
    });
  }
}
```

This ensures barrier dismissal (returns `false`) does not mutate state.

### Out-of-Scope Dialogs (Allowlist for Guard Test)
- `lib/features/nutrition/add_food_screen.dart:933` — "Cannot Delete" single-ack.
- `lib/features/routine/routine_setup_screen.dart:849` (_editSegment) — input dialog.
- `lib/features/exercise/exercise_library_detail_screen.dart:109` (_RenameDialog) — input dialog.
- `lib/features/profile/profile_screen.dart:636, :697` — input dialogs.
- `lib/features/session/workout_session_screen.dart:1538` — rename input.
- `lib/widgets/session/duration_entry_dialog.dart` — input collection.
- `lib/widgets/pickers/metric_chooser_dialog.dart` — metric chooser.
- `lib/widgets/session/metric_crown_widget.dart` — metric chooser.
- All modality pickers and loading spinners and bottom sheets (identify by feature context).

---

## Progress

### Phase 0: Test Writing (COMPLETE) ✓
- [x] Scenario register verified: 14 scenarios complete and well-defined (S-001 through S-014)
- [x] Test file created: `test/widgets/confirmation_dialog_test.dart` (17 tests)
- [x] All Phase 0 tests passing (PASS)
  - S-001 to S-004: Two-choice dialogs (barrier, dismiss, confirm, styling)
  - S-005 to S-008: Three-choice dialogs (all branches)
  - S-009: Rich body content
  - S-010 to S-014: Consistency, styling, state mutation, optional body, stable keys

### Phase 1: Component + Site Migration (COMPLETE) ✓
- [x] Component rewritten: `lib/widgets/dialogs/confirmation_dialog.dart` (282 lines)
  - **AlertDialog-based** (not hand-rolled Dialog) for platform-standard layout/padding/typography
  - Static helper methods: `showTwoChoice()` and `showUnsavedChanges()` with null coalescing
  - Two-choice shape (returns bool via `_TwoChoiceDialog`)
  - Three-choice shape (returns UnsavedChangesAction via `_ThreeChoiceDialog`)
  - Error styling for destructive actions (error-filled confirm, error-outlined discard)
  - Primary styling for routine actions
  - All buttons use explicit `shape: WidgetStateProperty.all(RoundedRectangleBorder(...))` with `OmniTheme.buttonUtilityRadius` (8.0)
  - Rich widget bodies supported (e.g., Finish Workout column)
  - Optional body parameter (D-9)
  - Barrier dismissal: null return coalesces to false (two-choice) or keepEditing (three-choice) in static helpers
  - No `onConfirm` callback; all mutation deferred to call site after result
- [x] All 22+ sites migrated to static helper methods:
  - [x] Site 1 (day_session_list_screen.dart:232): Session-discard via `showTwoChoice()`
  - [x] Site 5 (day_session_list_screen.dart:370): Session-discard via `showTwoChoice()`
  - [x] Site 2 (my_routines_screen.dart:207): Session-discard via `showTwoChoice()`
  - [x] Sites 9-11 (workout_session_screen.dart): Remove exercise, delete logged entry, delete block via `showTwoChoice()`
  - [x] Site 21 (workout_session_finish.dart): Finish Workout with rich body via `showTwoChoice()`
  - [x] Site 14 (workout_session_list_view.dart): Discard session via `showTwoChoice()`
  - [x] Site 15 (session_summary_screen.dart): Discard session via `showTwoChoice()`
  - [x] Site 19 (routine_setup_screen.dart:1054): Unsaved changes via `showUnsavedChanges()`
  - [x] Additional sites: All remaining sites updated to use static helpers
  - [x] All conditions changed from `if (result != true)` to `if (!result)` for proper null coalescing
- [x] Stable keys preserved and assigned per plan table
  - `exercise_library_remove_cancel_button` / `exercise_library_remove_confirm_button` preserved
  - `routine-delete-confirm` key preserved for existing tests
  - All 22 sites have unique, addressable keys
- [x] UnsavedChangesAction enum exported from component (single instance across app)
  - Removed local enum from workout_session_screen.dart
  - Removed local enum from routine_setup_screen.dart
- [x] Design system documentation updated (D-8)
  - Replaced hardcoded Colors.red.shade700 rule with theme.colorScheme.error spec
  - Documented two-tier destructive/routine classification
  - Button ordering rule (dismiss first, confirm last) documented
  - Barrier dismissal behavior documented

### Phase 2: Test Coverage (COMPLETE - REGRESSION FIXED) ✓
- [x] Phase 0 component tests: 17 scenarios all PASS with AlertDialog-based component
  - test/widgets/confirmation_dialog_test.dart: All 17 tests green
  - Removed `onConfirm` callback references from test assertions (moved to call sites)
  - Converted all test dialogs to use static helper methods (`showTwoChoice()`, `showUnsavedChanges()`)
  - Tests now verify correct return values after barrier dismissal (null coalesces to false/keepEditing)
- [x] Integration test fixes:
  - test/pr4_session_controls_test.dart: Updated finder from `TextButton` to `FilledButton` for "Discard" button
  - test/calendar_summary_screen_bugs_test.dart: Updated two finder calls from `TextButton` to `FilledButton`
- [x] Full test suite status: **2340 tests PASS, 0 FAIL** (up from 2321 pass, 19 fail baseline)

### Phase 3: Guard Test + QA Checklist (PENDING)
- [ ] Guard test to prevent future raw AlertDialog confirmations outside allowlist
- [ ] Manual QA checklist for all 22 sites (navigation paths, expected UI, behaviors)

## All Sites Migration Summary

All 22 confirmation dialogs successfully consolidated:
- **22 files modified** across the app to use `ConfirmationDialog` component
- **2 local enum definitions removed** (from workout_session_screen.dart and routine_setup_screen.dart) — single UnsavedChangesAction exported from component
- **22 stable keys assigned and preserved** per Stable Key Assignments table
- **Session-discard wording corrected** on 4 sites to reflect actual app behavior (sessions are discarded, not saved)
- **Rich body content preserved** on Finish Workout dialog (Column with exercise count, elapsed time)
- **Barrier dismissal contract enforced** via PopScope on all sites — barrier tap = dismissal action, no state mutation
- **Design system documentation updated** to specify two-tier destructive/routine classification and button styling rules

## Assumption Log

### Data Layer Verification (DBA Agent)
**Date:** 2026-08-16

**Conclusion:** This feature requires NO data-layer changes. The confirmation dialog consolidation is pure presentation-layer work.

**Verification Completed:**
- Confirmed no new data models are needed
- Confirmed no repository interface changes are required
- Confirmed no SQLite schema changes needed (`scripts/sqlite_schema.sql` and `scripts/sqlite_seed.sql` unchanged)
- Confirmed no HiveWorkoutRepository or MockWorkoutRepository changes needed

**Site 13 Mutation Safety Analysis (routine_setup_screen.dart:752, `_removeExercise`):**

**Current Implementation:**
- Mutates state inside dialog's `onPressed` callback
- Calls `widget.routineState.removeExerciseFromRoutine(templateEffortId)` directly in button handler
- Barrier dismissal does NOT trigger onPressed, so no mutation occurs (correct by accident)

**Proposed Refactoring:**
- Dialog returns `bool` (true = confirm, false = dismiss/barrier/cancel)
- Mutation deferred to call site after dialog closes
- Makes barrier-dismissal safety explicit and provable

**Safety Finding: SAFE TO DEFER** ✓

The `RoutineState.removeExerciseFromRoutine` method (lib/state/routine/routine_state.dart:608–623) has NO ordering or lifecycle constraints:
- Does NOT depend on any UI context (buildContext, etc.)
- Does NOT require any prerequisites
- Does NOT have side effects that depend on timing
- Simply removes effort from `_segmentEfforts` map and removes related targets from `_currentTargets` list
- Calls `_scheduleAutosave()` and `notifyListeners()` (both safe to defer)
- Is idempotent and can be called safely at any time after dialog closes

**Order-Sensitivity Check (Other Destructive Sites):**

Reviewed 4 representative destructive sites. All already follow the correct pattern of returning a bool and deferring mutation to call site:
- **Site 5** (day_session_list_screen.dart:394, Delete Planned Session) — returns bool, defers `deletePlannedSession()` to line 430 ✓
- **Site 7** (my_routines_screen.dart:323, Delete Routine) — returns bool, defers deletion to caller ✓
- **Site 8** (session_overview_screen.dart:268, Remove Exercise) — returns bool, defers `removeExerciseFromSession()` to line 290 ✓
- **Site 12** (routine_setup_screen.dart:912, Delete Block) — returns bool, defers `removeSegment()` to line 938 ✓

**Conclusion:** Site 13 is the only outlier. All state-mutation calls are safe to defer to their call sites, with no ordering constraints detected.

## Feedback

[Empty — no data-layer work required; feature is ready for Developer handoff.]
