# Theme & Settings — Feature Documentation

## Overview

OmniTrain's Settings screen is fully implemented. It owns persisted preferences for:

- calendar display (`Start of Week`)
- measurement units (`Weight`, `Distance`)
- timer alert behavior (`Effort Timer Sound`, `Rest Ping`, `Rest Ping Sound`)
- workout follow-up (`Feeling Survey`)
- appearance (`AppTheme` selection)

All settings apply immediately. There is no save button and no staged draft state.

---

## Theme System

**File**: `lib/core/constants/omni_theme.dart`

### `AppTheme` Enum

```dart
enum AppTheme {
  abyssalNeon,
  forgeEmber,
  obsidianVolt,
  voidPulse,
  crimsonDojo,
  malachiteCore,
}
```

### Available Themes

| Enum Value | Display Name | Primary Accent | Character |
|------------|--------------|----------------|-----------|
| `AppTheme.abyssalNeon` | Abyssal Neon | `#00B4B8` | Deep navy with cyan instrumentation |
| `AppTheme.forgeEmber` | Forge & Ember | `#FF6B35` | Molten orange, industrial warmth |
| `AppTheme.obsidianVolt` | Obsidian Volt | `#D4A017` | Dark amber-electric contrast |
| `AppTheme.voidPulse` | Void Pulse | `#8B5CF6` | Deep violet, late-night focus |
| `AppTheme.crimsonDojo` | Crimson Dojo | `#E53935` | Combat-sport red, heavier contrast |
| `AppTheme.malachiteCore` | Malachite Core | `#1A9A4A` | Deep mineral green, grounded and earthy |

For full palette values and visual rationale, see [Design System](design_system.md).

### `OmniTheme` Token Resolver

`OmniTheme.colorsForTheme(AppTheme theme)` returns a typed record with these fields:

| Token Field | Purpose |
|-------------|---------|
| `backgroundTop` | Top stop of the app gradient |
| `backgroundBottom` | Bottom stop of the app gradient |
| `surface` | Surface and sheet background |
| `primary` | Primary CTA / active accent |
| `secondary` | Supporting accent |
| `textMuted` | Secondary and metadata text |
| `divider` | Dividers and low-emphasis separators |
| `surfaceBorder` | Subtle surface outline |

### Helper API

| Member | Purpose |
|--------|---------|
| `OmniTheme.colorsForTheme(theme)` | Returns the token record for a theme |
| `OmniTheme.displayNameForTheme(theme)` | Returns the user-facing theme name |
| `OmniTheme.activeTheme` | Global fallback for widgets not passed `SettingsState` |

`MyApp` rebuilds `MaterialApp` through a `ListenableBuilder` watching `SettingsState`, so theme changes propagate immediately without restart.

---

## SettingsState

**File**: `lib/state/settings/settings_state.dart`

`SettingsState` is a `ChangeNotifier` backed by `WorkoutRepository` preference storage.

### Persisted Fields

| Field | Type | Default | Preference Key |
|-------|------|---------|----------------|
| `appTheme` | `AppTheme` | `abyssalNeon` | `app_theme` |
| `preferredWeightUnit` | `String` | `kg` | `preferred_weight_unit` |
| `preferredDistanceUnit` | `String` | `km` | `preferred_distance_unit` |
| `startOfWeek` | `String` | `monday` | `preferred_start_of_week` |
| `showFeelingSurvey` | `bool` | `true` | `show_feeling_survey` |
| `effortTimerSound` | `String` | `boxing_bell` | `effort_timer_sound` |
| `restPingInterval` | `int` | `0` (`Off`) | `rest_ping_interval` |
| `restPingSound` | `String` | `soft_chime` | `rest_ping_sound` |

### Sound Options

Valid sound IDs:

- `boxing_bell`
- `digital_buzzer`
- `soft_chime`
- `double_tap`
- `signal_tone`

Valid rest ping intervals:

- `0` (`Off`)
- `30`
- `45`
- `60`
- `90`
- `120`
- `180`

### Public API

| Method | Purpose |
|--------|---------|
| `initialize()` | Loads all persisted preferences |
| `setAppTheme(theme)` | Persists theme and notifies listeners |
| `setPreferredWeightUnit(unit)` | Normalizes to `kg` or `lbs` |
| `setPreferredDistanceUnit(unit)` | Normalizes to `km` or `miles` |
| `setStartOfWeek(value)` | Normalizes to `monday` or `sunday` |
| `setShowFeelingSurvey(value)` | Enables/disables the post-workout survey |
| `setEffortTimerSound(soundId)` | Persists the effort-timer alert sound |
| `setRestPingInterval(seconds)` | Persists periodic rest reminders |
| `setRestPingSound(soundId)` | Persists the rest-ping sound |

---

## Settings Screen

**File**: `lib/features/settings/settings_screen.dart`

Entry path: `HomeScreen` → Maintenance sheet → `SettingsScreen`

The screen is organized into four surfaced sections plus a low-emphasis version footer.

### 1. Preferences

Rows in the `PREFERENCES` section:

- `Start of Week`: segmented toggle (`Sun` / `Mon`) used by calendar views
- `Weight`: segmented toggle (`kg` / `lbs`) used by weight displays and editors
- `Distance`: segmented toggle (`km` / `mi`) used by cardio and timed exercise displays

Below those rows, a `PREVIEW` card renders example values for both weight and distance using the active unit preferences.

### 2. Sounds & Alerts

Rows in the `SOUNDS & ALERTS` section:

- `Effort Timer Sound`: bottom-sheet picker for the sound played when a timed effort or round expires
- `Rest Ping`: bottom-sheet picker for the periodic interval reminder during an open rest
- `Rest Ping Sound`: bottom-sheet picker for the sound used by the rest ping

Behavior notes:

- tapping a sound option plays an immediate preview through `TimerAlertService.playPreview(...)`
- effort timer completion uses `fireEffortTimerAlert(...)` and adds heavy haptics on native platforms
- rest ping uses `fireRestPingAlert(...)` and adds light haptics on native platforms
- web safely no-ops audio playback and logs debug output instead of throwing

### 3. Workout

Rows in the `WORKOUT` section:

- `Feeling Survey`: toggle for whether the session summary flow asks how the workout felt after finishing

This setting is on by default.

### 4. Appearance

The `APPEARANCE` section renders a two-column theme grid from `AppTheme.values`.

Interaction rules:

- tapping a tile calls `settingsState.setAppTheme(appTheme)` directly
- the selected tile uses surfaced fill plus a primary-colored border
- when the theme count is odd, the grid renders one ghost slot so the last row is visually balanced instead of showing a lone tile

### Version Footer

The screen ends with a centered, low-emphasis footer currently rendered as `Version 1.0.0`.

### Removed Surface

The Settings screen no longer includes account-management rows such as sign-in, export-data, or account-removal actions. The current implementation is limited to preferences, alert behavior, workout follow-up, and appearance.

---

## Theme Wiring Summary

| Surface | Theme Source |
|---------|--------------|
| `MaterialApp` | `buildTheme(appTheme: settingsState.appTheme)` |
| `OmniGradientBackground` | `OmniTheme.colorsForTheme(OmniTheme.activeTheme)` |
| `OmniSurface` | Active theme surface + border tokens |
| Maintenance sheet and tiles | Active theme token resolver |
| Session / summary / settings screens | Constructor-injected `SettingsState` with `OmniTheme.activeTheme` fallback where needed |

---

## Related Documentation

- [Design System](design_system.md) — visual identity, palette intent, and token usage
- [Navigation & Screens](navigation_and_screens.md) — where Settings lives in the app flow
- [State Management](state_management.md) — `SettingsState` in the dependency graph

---

**Document Version**: 2.0
**Last Updated**: May 17, 2026
