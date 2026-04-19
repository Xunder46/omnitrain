# Feature: Settings Account Removal

## Overview
Remove the non-functional Account section from the Settings screen before TestFlight. This is a removal-only cleanup pass: eliminate the Sign In and Export Data rows, remove the now-empty Account card/header, and keep the Version value visible as a low-emphasis footer at the bottom of the screen.

Fast-track note: this change introduces no new user-facing flow, no schema changes, and no new state methods. It can go directly to @developer without a DBA phase.

## Requirements
- Remove the Sign In row entirely from Settings, including its subtitle, icon, chevron, tap handler, and any navigation or snackbar target tied only to that row.
- Remove the Export Data row entirely from Settings, including its subtitle, icon, trailing icon, tap handler, and any dead references tied only to that row.
- Remove the Account section container and the ACCOUNT header once the rows are deleted.
- Relocate the Version display so it remains visible at the bottom of Settings as plain, low-emphasis footer text.
- Leave Measurements, Training, and Appearance sections unchanged in behavior and ordering.
- Remove or update tests that explicitly assert the old Account section, Sign In row, Export Data row, or Account snackbar behavior.
- Clean up any dead imports, icon references, constants, or handlers left behind by the removed rows.

## Acceptance Criteria
- [ ] The Sign In row no longer appears anywhere in Settings.
- [ ] The Export Data row no longer appears anywhere in Settings.
- [ ] The Account section card and ACCOUNT header are fully removed.
- [ ] The Version text remains visible as a plain footer element below the Appearance section, outside any card and without tappable-row affordances.
- [ ] Settings shows exactly three retained section cards in order: Measurements, Training, Appearance; then the Version footer.
- [ ] Measurements behavior is unchanged.
- [ ] Training behavior is unchanged, with Equipment and Modality Defaults still present.
- [ ] Appearance behavior is unchanged.
- [ ] No dead handlers, orphan references, or unused imports remain for Sign In or Export Data.
- [ ] Widget tests no longer reference the removed Account structure and verify the new footer placement.
- [ ] Relevant tests pass after the cleanup.

## Scenarios
- Open Settings and confirm the visible cards are Measurements, Training, and Appearance only.
- Scroll to the bottom of Settings and confirm the version number is visible as small footer text, not in a card and not interactive.
- Tap Equipment and confirm its existing placeholder snackbar still appears.
- Tap Modality Defaults and confirm its existing placeholder snackbar still appears.
- Confirm there is no Sign In or Export Data entry anywhere on the screen.

## Iteration 1
### Analysis
Current implementation places an ACCOUNT placeholder section in [lib/features/settings/settings_screen.dart](lib/features/settings/settings_screen.dart) containing Sign In, Export Data, and Version. Existing tests in [test/screen_widget_test.dart](test/screen_widget_test.dart) and [test/interaction_flow_test.dart](test/interaction_flow_test.dart) explicitly assert the Account section and Sign In snackbar behavior.

### DB Changes
- None required.
- No repository, persistence, or schema work is expected for this pass.

### Backend Changes
- None required.

### Frontend Changes (@developer)
1. [ ] Update [lib/features/settings/settings_screen.dart](lib/features/settings/settings_screen.dart) to remove the entire ACCOUNT placeholder section.
2. [ ] Delete the Sign In row definition and its placeholder snackbar usage.
3. [ ] Delete the Export Data row definition and its placeholder snackbar usage.
4. [ ] Re-home the version value as small, muted footer text at the bottom of the Settings list after the Appearance section.
5. [ ] Keep existing spacing visually balanced without adding new cards or sections.
6. [ ] Remove any no-longer-used icon references or local helpers only if they become unused after the row deletions.

### Test/Validation Steps (@developer)
1. [ ] Update [test/screen_widget_test.dart](test/screen_widget_test.dart) so it verifies the retained section order and the presence of the footer-style version text instead of ACCOUNT.
2. [ ] Update or remove the Account-specific portion of [test/interaction_flow_test.dart](test/interaction_flow_test.dart), preserving checks for still-supported Settings interactions only.
3. [ ] Run the focused widget test files covering Settings.
4. [ ] Run the broader relevant regression test set if the focused tests expose shared layout issues.

### Implementation Steps
1. [ ] Remove obsolete Account UI from the Settings list.
2. [ ] Add the non-interactive version footer below the retained sections.
3. [ ] Clean test expectations for removed rows/section.
4. [ ] Verify no analyzer warnings or unused imports remain.
5. [ ] Verify the Settings screen still scrolls and renders correctly on the retained sections.

## Progress
- [x] Remove Account section UI from Settings screen.
- [x] Relocate version text to footer.
- [x] Clean obsolete handlers/references.
- [x] Update Account-related widget tests.
- [x] Run relevant verification tests.

### Phase 2 Complete ✓
Implementation done. All Phase 0 tests green. Ready for Code Reviewer.

## Feedback
### Code Review Follow-up — April 19, 2026
The remaining review items were addressed:
- Settings footer copy now uses a plain, low-emphasis version label.
- Tests no longer reference the removed Account rows or section.
- The outdated drag-details test construction was updated to the current Flutter API.
- Navigation docs now reflect the post-removal Settings screen.
