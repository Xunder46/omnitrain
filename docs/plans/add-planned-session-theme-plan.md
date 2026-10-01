# Feature: Add Planned Session Theme Parity

## Overview
The Add Planned Session bottom sheet in `DaySessionListScreen` is not fully theme-reactive. Several elements use static `OmniTheme` constants (or implicit defaults) instead of active tokens from the current app theme and Material theme, causing visual mismatch and stale styling when users switch themes.

## Requirements
- The Add Planned Session screen (bottom sheet form) must use active theme tokens for all visual elements
- Theme switching must update this screen immediately without app restart
- Remove hardcoded colors/styles in this screen path (backgrounds, surfaces, text, icon colors, borders, accents)
- Add widget tests that verify token-driven rendering and runtime theme switch re-render

## Acceptance Criteria
- [x] Bottom-sheet container surface/background resolves from active theme tokens (not static constants)
- [x] Header/title text, labels, and close icon resolve from active theme tokens/text theme
- [x] Mode toggle buttons (Free Training / Routine) use active theme tokens for selected/unselected states
- [x] Field borders/labels/icons in dropdowns and text fields are theme-driven
- [x] Existing CTA remains theme-driven and compliant with shared button shape tokens
- [x] Switching app theme causes Add Planned Session form visuals to update on repump/rebuild with no restart
- [x] No hardcoded `Colors.*` or static non-reactive Omni theme constants remain in `_PlannedSessionForm` visual styling
- [x] New widget test verifies active-token rendering for background, text, and icon
- [x] New widget test verifies theme-switch rerender for the same form

## Scenarios

### S-001: Render Uses Active Theme Tokens
- Trigger: User taps "Add Planned Session" on `DaySessionListScreen`.
- Precondition: `OmniTheme.activeTheme` is set to a non-default theme (e.g., `forgeEmber`).
- Flow: Open the bottom sheet and inspect sheet surface, title text style color, close icon color, and primary accent controls.
- Expected outcome: Form visuals are derived from active theme tokens/theme data, not static constants.
- Edge case of: none

### S-002: Runtime Theme Switch Re-renders Form
- Trigger: App theme changes while user is on calendar flow; form is rebuilt/reopened.
- Precondition: Form can be opened from `DaySessionListScreen`; at least two themes are available.
- Flow: Render form with theme A, switch to theme B, rebuild/reopen form, compare token-backed visual properties.
- Expected outcome: Form surface/accent/icon/text token values update to theme B without app restart.
- Edge case of: S-001

### S-003: Mode Toggle Styling Stays Theme-Consistent
- Trigger: User toggles between Free Training and Routine in the form.
- Precondition: Form is open and theme is active.
- Flow: Observe selected/unselected button states before and after mode toggle.
- Expected outcome: Selected/unselected styles use active theme accents/borders/foregrounds and preserve current button shape tokens.
- Edge case of: S-001

## Iteration 1

### DB Changes
None.

### Backend / State Changes
None expected. This is a presentation-layer correction. No repository/state interface updates required.

### Frontend Changes (@developer)
1. Update `_PlannedSessionForm` in `lib/features/calendar/day_session_list_screen.dart` to derive visual tokens per build via:
   - `final theme = Theme.of(context);`
   - `final colors = OmniTheme.colorsForTheme(OmniTheme.activeTheme);`
2. Replace static sheet decoration color usage:
   - `OmniTheme.surfaceColor` -> active token (`colors.surface`) or `theme.colorScheme.surface` (consistent with app pattern).
3. Replace static text/icon color bindings:
   - `OmniTheme.textPrimary` / `OmniTheme.textSecondary` usages inside `_PlannedSessionForm` -> theme/text tokens (`theme.textTheme...`, `theme.colorScheme.onSurface`, or `colors.textMuted` where semantically secondary).
4. Normalize mode-button selected/unselected styling to active-token values:
   - Remove fixed `OmniTheme.zenCoreGlowColor` reliance for selected state.
   - Use active accent/border tokens (`theme.colorScheme.primary`, opacity variants, and themed foregrounds).
5. Ensure dropdown/text field decorations are explicitly theme-aware where needed:
   - Border/label/focus styles should resolve from theme input decoration defaults or explicit theme-based values, not implicit hardcoded colors.
6. Keep existing shape and sizing tokens (`OmniTheme.buttonBorderRadius`, `OmniTheme.buttonPrimaryHeight`) intact (not a redesign).

### Test Changes (@developer)
1. Extend `test/screen_widget_test.dart` under `group('DaySessionListScreen', ...)` with:
   - Test A: open Add Planned Session and assert key widgets use active theme tokens for:
     - Sheet surface/background
     - Header text style color/token source
     - Close icon color/token source
   - Test B: set theme A, render and capture selected token-backed values; switch to theme B (`OmniTheme.activeTheme = ...` and repump), reopen/render, assert values changed to theme B tokens.
2. Prefer concrete widget-property assertions (e.g., `Container.decoration`, `IconButton.color`, text style color) over screenshots.
3. Keep tests deterministic by setting fixed surface size and avoiding timing-sensitive expectations.

### Implementation Steps
1. [x] Refactor `_PlannedSessionForm.build` to resolve active theme/tokens once and reuse locally
2. [x] Replace all static color references inside `_PlannedSessionForm` with active token/theme-derived values
3. [x] Verify selected/unselected session type button visuals are active-theme driven
4. [x] Add widget test: token-backed render expectations for background/text/icon
5. [x] Add widget test: theme switch updates form token usage
6. [x] Run focused widget tests for `DaySessionListScreen` and ensure no regressions in existing tests

## Progress
- [x] Plan drafted for implementation
- [x] Phase 0 scenario register completed
- [x] Red test baseline captured (new tests failed pre-implementation)
- [x] `_PlannedSessionForm` token refactor complete
- [x] Theme-switch behavior validated in widget tests
- [x] S-003 mode-toggle style assertions added
- [x] Focused test run green
- [x] Full `test/screen_widget_test.dart` run green

## Doc Updates
- `docs/navigation_and_screens.md`: no update required (no route graph or constructor dependency change)
- `docs/state_management.md`: no update required (no state/service API change)
- `docs/widget_catalog.md`: no update required (no new reusable widget introduced)
- `docs/data_models.md`: no update required (no model contract change)
- `docs/db_integration.md`: no update required (no repository/schema/data-layer change)

### Phase 2 Complete ✓
Implementation done. All Phase 0 tests green. Ready for Code Reviewer.

## Feedback
<!-- Leave empty until a specialist or reviewer adds notes -->
