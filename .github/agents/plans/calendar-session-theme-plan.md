# Feature: Calendar Day Session Theme Adjustment

## Overview
When on the calendar day details screen, the session rows (completed, planned, in-progress) are not adjusting their text colors to the current app theme. Hardcoded colors ignore theme selection.

## Requirements
- Session rows must use theme-aware colors from `OmniTheme.colorsForTheme(OmniTheme.activeTheme)`
- Completed state should use theme primary color
- Planned state should use theme textMuted color
- Delete button color should be theme-aware

## Root Cause
In `lib/features/calendar/day_session_list_screen.dart`, the `_SessionRow` widget:
- Line 490: `final stateColor = entry.isCompleted ? Colors.greenAccent : Colors.white54;`
- Line 534: `color: Colors.redAccent,` (delete button)

These hardcoded colors don't respond to theme changes. The container and surface are theme-aware (using `OmniTheme.surfaceColor` and `OmniTheme.surfaceBorderColor`), but text colors are not.

## Implementation Plan

### Phase 1: Fix _SessionRow Widget in day_session_list_screen.dart (@developer)
1. [ ] Import theme resolver at top of `day_session_list_screen.dart` if not present
2. [ ] In `_SessionRow.build()`, get theme colors: `final themeColors = OmniTheme.colorsForTheme(OmniTheme.activeTheme);`
3. [ ] Replace hardcoded `stateColor` calculation (line ~490):
   - Change `Colors.greenAccent` → `themeColors.primary` (completed state - remains green but theme-dependent)
   - Change `Colors.white54` → `themeColors.textMuted` (planned state)
4. [ ] Replace hardcoded delete button color (line ~534):
   - Keep destructive red color - research/define theme-aware equivalent for each theme (maintain visible delete affordance)
5. [ ] Test on web with MockWorkoutRepository across all app themes
6. [ ] Verify session rows update color when theme changes

### Phase 2: Fix Similar Issue in period_list_screen.dart (@developer)
1. [ ] Check `period_list_screen.dart` line 292 for hardcoded `Colors.redAccent`
2. [ ] Apply same destructive color fix as Phase 1 step 4
3. [ ] Test period list screen across all themes

### Acceptance Criteria
- [ ] Completed session rows show primary color (green in Abyssal Neon, orange in Forge & Ember, yellow in Obsidian Volt, green in Circuit Green)
- [ ] Planned session rows show textMuted color from active theme
- [ ] Delete button maintains distinctive destructive appearance across all themes
- [ ] Works on web with all 4 theme options (Abyssal Neon, Forge & Ember, Obsidian Volt, Circuit Green)
- [ ] No hardcoded `Colors.X` in _SessionRow widget
- [ ] No hardcoded `Colors.redAccent` in period_list_screen.dart usage
- [ ] Theme changes apply immediately to already-displayed sessions
- [ ] Both day_session_list_screen.dart and period_list_screen.dart updated

## Files Affected
- `lib/features/calendar/day_session_list_screen.dart` (_SessionRow widget, line ~490 and ~534)
- `lib/features/period/period_list_screen.dart` (delete button color, line 292)

## Notes
- The `OmniTheme.colorsForTheme()` method already provides theme-aware colors for primary, secondary, and textMuted
- No database changes needed
- The container background already uses `OmniTheme.surfaceColor` (theme-aware), so only text colors need fixing
- **Destructive color handling**: For delete buttons, consider adding a destructive/error color token to `OmniTheme` if not present, or use a consistent pattern (e.g., `Color(0xFFFF4444)` that's visible across all themes)
- The completed state color change from `Colors.greenAccent` to `themeColors.primary` ensures it adapts to each theme's primary accent (which varies by theme)

## Progress
- [x] Phase 1: Fix _SessionRow in day_session_list_screen.dart
- [ ] Phase 2: Fix period_list_screen.dart
- [ ] Test across all themes
- [ ] Verify immediate theme updates work

## Feedback
