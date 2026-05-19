# Feature: theme-system-overhaul

## Overview
Pre-TestFlight theme cleanup and contrast hardening for OmniTrain. This pass removes three deprecated palettes from the shipped selector and enforces strict color-role discipline so the five retained themes remain legible, premium, and consistent with the dark athletic aesthetic.

## Requirements
- Remove the deprecated themes from the shipped code path:
  - `circuitGreen`
  - `arcticCore`
  - `titaniumRose`
- Retain only:
  - `abyssalNeon`
  - `forgeEmber`
  - `obsidianVolt`
  - `voidPulse`
  - `crimsonDojo`
- Delete removed-theme enum entries, token cases, and display-name cases from the theme system.
- Ensure persisted invalid/legacy theme names safely fall back to `AppTheme.abyssalNeon`.
- Shorten the Settings theme selector automatically to five options at runtime.
- Enforce color-role discipline on the exercise picker:
  - primary CTA = filled accent + white text
  - New Exercise = outlined accent only
  - search field resting border = subtle surface border only
  - Recommended label = secondary text, not accent
  - metadata chips/tags = ghost treatment using surface border + muted text
  - exercise name = primary text
  - exercise subtitle = secondary text
- Keep modality accent colors unchanged.
- Make no layout or navigation changes.

## Acceptance Criteria
- [x] `AppTheme` contains only the five retained themes.
- [x] Removed themes no longer appear in `OmniTheme.colorsForTheme()` or `OmniTheme.displayNameForTheme()`.
- [x] Settings theme selector shows only the five retained themes at runtime.
- [x] No screen or widget references removed themes after cleanup.
- [x] Exercise picker tags use ghost styling with no accent fill.
- [x] Exercise picker `Recommended` label uses secondary text color, not accent.
- [x] Exercise picker search field resting state uses the theme surface-border token; accent appears only on focus/active state.
- [x] `New Exercise` remains outlined with accent border + accent text and no fill.
- [x] `Finish Workout` CTA uses the primary accent fill with white text on all retained themes.
- [x] `Obsidian Volt` primary is shifted away from pure neon yellow toward a warmer amber-volt tone and is visually calmer than `#EAE000`.
- [x] `Crimson Dojo` CTA fill resolves to the primary `#E53935`, not the darker secondary `#B71C1C`.
- [x] No modality color constants are changed.
- [x] No new screens, components, or layout changes are introduced.

## Scenarios
- User opens Settings → Appearance and sees exactly five themes.
- User previously saved a removed theme and relaunches the app → fallback resolves safely to Abyssal Neon without crash.
- User opens exercise picker during a session and the screen emphasizes exercise content, not metadata chips.
- User finishes a workout in Crimson Dojo and the CTA remains clearly legible against the dark background.
- User switches to Obsidian Volt and sees a controlled amber-electric accent instead of a harsh neon-lime yellow.

## Analysis
This is a fast-track Developer task: no schema changes, no new repository methods, and no new user flows. The root issue is not the presence of multiple themes alone but accent overuse inside the exercise picker. The current implementation already isolates most theme behavior in the theme token source and in a few UI surfaces, so the safest change is a targeted token cleanup plus widget-level role reassignment.

## Questions (if any)
1. No open product questions. Requirements are explicit.

## Iteration 1
### DB Changes
- None.

### Backend Changes
- None beyond theme-token cleanup in existing UI/theme constants.

### Frontend Changes (@developer)
1. [x] Update [lib/core/constants/omni_theme.dart](lib/core/constants/omni_theme.dart):
   - remove `circuitGreen`, `arcticCore`, and `titaniumRose` from `AppTheme`
   - remove their switch cases from `colorsForTheme()`
   - remove their labels from `displayNameForTheme()`
   - adjust `obsidianVolt.primary` away from `#EAE000` to a warmer amber-volt candidate and keep `crimsonDojo.primary` at `#E53935`
2. [x] Confirm [lib/state/settings/settings_state.dart](lib/state/settings/settings_state.dart) already falls back safely when a removed persisted theme name is encountered; keep this behavior intact.
3. [x] Update [lib/features/settings/settings_screen.dart](lib/features/settings/settings_screen.dart) only as needed so the option grid renders the shortened `AppTheme.values` list with no stale references.
4. [x] Refine [lib/widgets/pickers/exercise_picker_dialog.dart](lib/widgets/pickers/exercise_picker_dialog.dart):
   - keep `New Exercise` as outlined accent treatment
   - move `Recommended` header to `OmniTheme.textSecondary`/theme secondary text
   - change discipline and muscle chips to ghost styling using transparent or surface-level background, `surfaceBorder`, and `textMuted`
   - ensure exercise title remains dominant and subtitle remains secondary
   - ensure the search field border is subdued at rest and only accents on focus
5. [x] Verify [lib/features/session/workout_session_screen.dart](lib/features/session/workout_session_screen.dart) continues using the primary accent fill for the `Finish Workout` CTA across all remaining themes, especially Crimson Dojo.
6. [x] Run analysis and focused widget tests or app smoke validation to prove the selector and picker still compile and render correctly after enum removal.

### Implementation Steps
1. [x] Remove the three deprecated theme enum values and token/display-name cases.
2. [x] Update the Obsidian Volt accent to a warmer amber-volt value and visually confirm it is less aggressive.
3. [x] Audit the exercise picker for every accent usage and remap each one to its correct role.
4. [x] Leave modality colors and layout structure untouched.
5. [x] Verify no remaining code references the removed themes.
6. [x] Run targeted verification before marking complete.

## Progress
- [x] Remove deprecated themes from the enum and theme token switches
- [x] Shorten the settings selector to five runtime options
- [x] Apply exercise picker color-role discipline
- [x] Verify Finish Workout CTA contrast on retained themes
- [x] Validate persisted-theme fallback behavior
- [x] Run analysis/tests and resolve any regressions

Phase Status: Complete

## Files Affected
- lib/core/constants/omni_theme.dart
- lib/widgets/pickers/exercise_picker_dialog.dart
- lib/features/session/workout_session_screen.dart
- lib/features/settings/settings_screen.dart
- lib/state/settings/settings_state.dart
- test/ (targeted verification if needed)

## Notes
- Scope is intentionally narrow: tokens and color-role assignments only.
- No modality accent constants should be touched.
- Because this is a polish/contrast pass with no data work, it should go directly to Developer.

## Feedback
### Phase 2 Complete ✓
Implementation done. Focused theme and UI tests green. Ready for Code Reviewer.

### Post-completion polish ✓
Picker sheet surface and CTA theming aligned. Void Pulse background depth adjusted.
Remaining picker CTA fill cases completed for Forge & Ember, Obsidian Volt, and Crimson Dojo. Crimson surface lifted for legibility.

### Theme context fix (persistent CTA) ✓
**Root cause identified**: `WorkoutSessionScreen.build()` had no local `Theme`/`filledButtonTheme` anchor, so all `FilledButton` instances (including "Finish Workout" and any dialogs opened from the session screen) inherited `colorScheme.primary` from `MaterialApp.theme` context alone — no explicit break-glass if that inheritance were disrupted.

**Fix**: Wrapped the session screen's entire content output in `Theme(data: sessionTheme, child: ...)` where `sessionTheme.filledButtonTheme.style.backgroundColor = WidgetStatePropertyAll(themeColors.primary)`. Theme colors are sourced from `widget.settingsState?.appTheme ?? OmniTheme.activeTheme`. This anchors ALL `FilledButton` instances in the session screen AND any dialogs it opens to the correct accent token, regardless of any upstream overlay context reset.

**Investigation note**: `ExercisePickerDialog` has no `FilledButton` in its widget tree. All prior `filledButtonTheme` additions to the picker's local `Theme` wrapper were visually inert. The break was in the session screen's own context — not the picker.

**Crimson Dojo surface**: Further lifted from `#2C1210` → `#3A1A16` for improved ghost tag legibility.

### CTA root-cause re-investigation (April 2026) — No regression found ✓
A new report claimed `buildTheme()` in `main.dart` was the root cause (mis-spelled; function lives in `lib/app.dart`).

**Conductor verification result**: No change required.
- `buildTheme()` already derives `primary = OmniTheme.colorsForTheme(theme).primary` unconditionally for every theme; `colorScheme.primary` is explicitly set to that value with no conditional branches, no hardcodes, and no default fall-through.
- `buildTheme()` contains **no** `FilledButtonThemeData` or `ButtonThemeData` override; Material3 `FilledButton` naturally inherits `colorScheme.primary`.
- The `theme:` parameter is always explicitly passed as `activeTheme` at the single call site in `app.dart`.
- `showDialog(context: this.context)` inside `_showFinishSessionDialog()` uses the `WorkoutSessionScreen` element context, which resolves `MaterialApp.theme` (correct `colorScheme.primary`) — the dialog `FilledButton` gets the right accent without any additional override.
- `WorkoutSessionScreen – Finish Workout button theme context` widget test passes for all non-default themes (forgeEmber, obsidianVolt, crimsonDojo).

The previously added `filledButtonTheme` override in `WorkoutSessionScreen.build()` is a valid belt-and-suspenders safeguard for buttons rendered within the session content tree; it is not causing any regression and should remain.

No code changes were made in this investigation pass.

### Picker overlay obscuration fix (April 2026) ✓
**Verified root cause**: the Exercise Picker opened with the framework default modal barrier opacity of roughly 0.54, allowing the underlying session CTA area to show through in a degraded state.

**Fix applied**: all Exercise Picker `showDialog<Exercise>()` launch points now set `barrierColor: Colors.black.withOpacity(0.78)`, which fully obscures the underlying session screen without moving or modifying the session CTA.

**Verification evidence**:
- New widget regression test confirms the active `AnimatedModalBarrier` opacity is `>= 0.7` when the picker opens from `WorkoutSessionScreen`.
- Focused widget verification is green for the session CTA theme context and picker overlay path.
