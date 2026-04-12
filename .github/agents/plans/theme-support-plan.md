# Feature: theme-support

## Overview
Add user-selectable app themes to OmniTrain with two new palettes (Forge & Ember, Obsidian Volt), persist the selected theme, and apply it reactively across app-level `ThemeData`, gradient backgrounds, and settings UI. The implementation must be constrained to theming concerns only and must not alter navigation, workout/session logic, data models unrelated to theme, or modality accent-color constants.

## Requirements
- Extend or add `AppTheme` enum in `lib/core/constants/omni_theme.dart` with:
  - `abyssalNeon`
  - `forgeEmber`
  - `obsidianVolt`
- Add theme token source in `OmniTheme` via `colorsForTheme(AppTheme theme)` (record/map/object acceptable) with exact raw values:
  - abyssalNeon
    - backgroundTop: `Color(0xFF0F1F33)`
    - backgroundBottom: `Color(0xFF060B14)`
    - surface: `Color(0xFF0E223A)`
    - primary: `Color(0xFF2DE2E6)`
    - secondary: `Color(0xFF1B9AAA)`
    - textMuted: `Color(0xFF9BA4B5)`
    - divider: `Color(0xFF1F2937)`
    - surfaceBorder: `Color(0x0FFFFFFF)`
  - forgeEmber
    - backgroundTop: `Color(0xFF1C1008)`
    - backgroundBottom: `Color(0xFF0A0603)`
    - surface: `Color(0xFF211407)`
    - primary: `Color(0xFFFF6B35)`
    - secondary: `Color(0xFFCC4A1A)`
    - textMuted: `Color(0xFFA07060)`
    - divider: `Color(0xFF2A1C10)`
    - surfaceBorder: `Color(0x0DFFFFFF)`
  - obsidianVolt
    - backgroundTop: `Color(0xFF111111)`
    - backgroundBottom: `Color(0xFF050505)`
    - surface: `Color(0xFF161616)`
    - primary: `Color(0xFFEAE000)`
    - secondary: `Color(0xFFB8B000)`
    - textMuted: `Color(0xFF666666)`
    - divider: `Color(0xFF1F1F1F)`
    - surfaceBorder: `Color(0x12FFFFFF)`
- Add theme display names:
  - `Abyssal Neon`
  - `Forge & Ember`
  - `Obsidian Volt`
- Add a `SettingsState` with persisted theme selection (`SharedPreferences`) alongside existing unit-preference pattern.
- Ensure saved theme is loaded during state init and falls back to `AppTheme.abyssalNeon`.
- Update app theme builder to accept `AppTheme`, deriving `colorScheme.primary` from the selected Omni theme tokens.
- Make `MaterialApp` rebuild reactively on theme change via `ListenableBuilder`/`AnimatedBuilder` around `settingsState`.
- Update `OmniGradientBackground` to use active theme gradient colors while keeping radial highlight and noise behavior unchanged.
- Add theme selector inside Settings Appearance section using existing segmented animated-container interaction style.
- Selector requirements:
  - Render all themes from `AppTheme.values`
  - Immediate apply and persist on tap
  - No save button
  - 10 px swatch circle left of label using each theme primary color
- Ensure no hardcoded hex colors are introduced in feature screens/widgets; use `OmniTheme` token accessors.
- Do not modify `modality_colors.dart`.
- If `OmniSurface` reads theme constants from `OmniTheme`, ensure it resolves active theme surface values.

## Iteration 1

### DB Changes
1. [ ] No database or repository schema changes required.
2. [ ] No SQLite/Hive migration required.

### Backend Changes (@developer)
1. [ ] Add `AppTheme` enum in `lib/core/constants/omni_theme.dart` if missing; otherwise append missing enum members without removing existing values.
2. [ ] Introduce `OmniTheme.colorsForTheme(AppTheme theme)` token resolver using exact provided color values.
3. [ ] Introduce `OmniTheme.displayNameForTheme(AppTheme theme)` with required labels.
4. [ ] Add active-theme bridge for low-refactor path (`OmniTheme.activeTheme`) only if constructor-injection into all relevant widgets is too invasive.
5. [ ] Create `lib/state/settings/settings_state.dart` as a `ChangeNotifier` with:
   - persisted `_themeKey = 'app_theme'`
   - `_appTheme` default `AppTheme.abyssalNeon`
   - getter `appTheme`
   - `setAppTheme(AppTheme theme)` persisting by enum `.name` and notifying listeners
   - `_loadFromPrefs()` to restore theme by name with safe fallback
6. [ ] Keep any existing unit preference logic intact; if unit preference currently lives elsewhere, preserve behavior while introducing theme persistence in a compatible state location.
7. [ ] Thread `SettingsState` through constructor chain from `main.dart` -> `MyApp` (and onward if needed) using existing dependency-injection style.
8. [ ] Update `buildTheme` signature in `lib/app.dart` to accept optional `AppTheme` defaulting to abyssal neon and derive `colorScheme.primary` from `OmniTheme.colorsForTheme(theme)`.
9. [ ] Keep all non-theme behavior in `buildTheme` unchanged unless strictly required to source values from the selected token set.

### Frontend Changes (@developer)
1. [ ] Wrap `MaterialApp` in a reactive builder listening to `settingsState` so runtime theme changes repaint app chrome immediately.
2. [ ] Update `lib/widgets/layout/omni_gradient_background.dart` to read active gradient tokens from selected theme:
   - preserve radial highlight logic
   - preserve noise overlay logic
3. [ ] Update any tokenized surfaces/components that currently reference fixed `OmniTheme.surfaceColor`/`surfaceBorderColor` so they reflect active theme values when sourced from OmniTheme.
4. [ ] Implement Settings screen/theme selector UX:
   - If dedicated settings screen exists, add content inside existing Appearance placeholder section only.
   - If no settings screen exists (current codebase has a maintenance placeholder), create a minimal `SettingsScreen` with existing section structure and insert the Appearance theme segmented control without unrelated feature expansion.
5. [ ] Build segmented toggle row from `AppTheme.values` using existing animation pattern from settings UI conventions:
   - selected: surfaced styling with primary border
   - unselected: transparent/muted border
6. [ ] Add 10 px primary-color swatch to each option label using theme token primary color.
7. [ ] Ensure tapping an option calls `settingsState.setAppTheme(theme)` and applies immediately.
8. [ ] Keep navigation and workout logic untouched; only route-level changes permitted are those required to reach the existing settings UI if currently placeholder-based.
9. [ ] Request Designer review after implementation to validate selector visual polish against design system.

### Implementation Steps
1. [ ] Add/extend theme enum and token utilities in `omni_theme.dart`.
2. [ ] Implement `SettingsState` with shared-preference persistence and initialization load.
3. [ ] Instantiate and initialize `SettingsState` in `main.dart`.
4. [ ] Inject `SettingsState` into `MyApp` and any settings feature entry point.
5. [ ] Refactor `buildTheme({AppTheme theme = AppTheme.abyssalNeon})` and use selected primary token.
6. [ ] Add app-level reactive rebuild around `MaterialApp` for live theme switching.
7. [ ] Wire active theme access for `OmniGradientBackground` (and `OmniSurface` if required by existing static-token usage).
8. [ ] Add theme selector UI to Settings Appearance section with swatches and immediate persistence.
9. [ ] Run static analysis and targeted widget/app smoke test to verify:
   - all AppTheme switch statements are exhaustive
   - selected theme persists across restart
   - gradient and primary color update on selection
   - no modifications in modality color constants

## Progress
- [x] Create/extend `AppTheme` enum
- [x] Add `OmniTheme.colorsForTheme` token source
- [x] Add `OmniTheme.displayNameForTheme`
- [x] Implement `SettingsState` theme persistence/load
- [x] Inject `SettingsState` through app constructor chain
- [x] Update `buildTheme` to accept active `AppTheme`
- [x] Make `MaterialApp` rebuild on settings changes
- [x] Update `OmniGradientBackground` to active gradient tokens
- [x] Ensure `OmniSurface` uses active surface token path
- [x] Add Appearance theme segmented selector UI with swatches
- [x] Verify no hardcoded hex in feature UI code
- [x] Verify `modality_colors.dart` unchanged
- [x] Add or update tests for settings/theme persistence and reactive application
- [x] Maintenance sheet background uses `OmniTheme.colorsForTheme(theme).surface` — no hardcoded hex
- [x] Sheet drag handle uses `primary.withOpacity(0.4)` from active theme
- [x] `MaintenanceTile` fill and icon colors respond to active theme
- [x] All `MaintenanceTile` call sites pass `activeTheme: settingsState.appTheme`
- [x] `SessionOverviewScreen` scaffold and AppBar backgrounds use `themeColors.backgroundTop`
- [x] `SessionOverviewScreen` exercise rows use `themeColors.surface` + `themeColors.surfaceBorder` (Container replaces Card)
- [x] `SessionOverviewScreen` "Exercises" section label uses `themeColors.textMuted`
- [x] `SettingsState` injected via constructor into `SessionOverviewScreen`
- [x] No call sites updated for `SessionOverviewScreen` (screen has no active navigation entry points yet)
- [x] `SessionSummaryScreen` feeling bottom sheet uses active theme tokens (surface/text/borders/handle)
- [x] `WorkoutSessionScreen` edit/list theme fallback uses `OmniTheme.activeTheme` when `settingsState` is null
- [x] Settings Appearance theme selector uses a 2-column by 4-row mini-tile grid layout
- [x] Settings AppBar title bar colors follow active theme tokens (no static white)

## Acceptance Criteria
- [ ] `AppTheme` compiles with exhaustive switch handling for all three themes.
- [ ] Selected theme persists and reloads with fallback to `abyssalNeon` when invalid/missing.
- [ ] `buildTheme` reads selected theme primary token into `colorScheme.primary`.
- [ ] `MaterialApp` updates theme immediately when selection changes.
- [ ] `OmniGradientBackground` reflects selected theme top/bottom gradient.
- [ ] Settings Appearance UI renders exactly three options from `AppTheme.values` with 10 px primary swatches.
- [ ] Theme changes apply instantly with no save button.
- [ ] No hardcoded hex values are added in settings/theme widgets; tokens come from `OmniTheme`.
- [ ] `modality_colors.dart` remains unchanged.
- [ ] Non-theming app logic remains unaffected.

## Files Affected
- lib/core/constants/omni_theme.dart
- lib/state/settings/settings_state.dart
- lib/main.dart
- lib/app.dart
- lib/widgets/layout/omni_gradient_background.dart
- lib/widgets/layout/omni_surface.dart (if token source is static and must be made theme-aware)
- lib/features/settings/settings_screen.dart (if existing)
- lib/features/home/home_screen.dart (only if required to route to existing/new settings screen)
- test/ (theme settings + persistence tests)

## Notes
- The repository currently has no `lib/state/settings/settings_state.dart`; implementation should add it while preserving existing constructor injection patterns.
- The current home maintenance tile routes Settings to a placeholder screen; if required for this feature, add minimal routing to the settings UI without broad navigation refactors.
- `docs/app_philosophy.md` was not found in the current workspace snapshot; align with existing architecture patterns observed in `main.dart`/`app.dart` and existing feature/state layering.

## Feedback
### Review Outcome: Addressed

Previously reported blockers were addressed in a follow-up implementation pass:

1. State-layer storage coupling removed by routing theme persistence through repository preference methods.
2. Dedicated tests added for settings theme persistence and reactive app theme updates.
3. Progress checklist updated after adding validation coverage.
