# Theme & Settings — Feature Documentation

## Overview

OmniTrain's Settings screen is fully implemented. It owns persisted preferences for:

- calendar display (`Start of Week`)
- measurement units (`Weight`, `Distance`, `Height`)
- timer alert behavior (`Effort Timer Sound`, `Rest Ping`, `Rest Ping Sound`)
- notification permission copy that covers both rest reminders and effort-expiry alerts
- workout follow-up (`Effort Rating` — "Ask how hard the workout was after finishing")
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

Six themes: Abyssal Neon, Forge & Ember, Obsidian Volt, Void Pulse, Crimson Dojo, and Malachite
Core. Their palettes and the reasoning behind each are in [Design System](design_system.md); the
values themselves live only in `lib/core/constants/omni_theme.dart`.

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
| `preferredHeightUnit` | `String` | `cm` | `preferred_height_unit` |
| `startOfWeek` | `String` | `monday` | `preferred_start_of_week` |
| `showFeelingSurvey` | `bool` | `true` | `show_feeling_survey` (backs the "Effort Rating" toggle; key kept from the feeling survey so every user's choice carried over) |
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
| `setPreferredHeightUnit(unit)` | Normalizes to `cm` or `ftin` (feet/inches) |
| `setStartOfWeek(value)` | Normalizes to `monday` or `sunday` |
| `setShowFeelingSurvey(value)` | Enables/disables the automatic post-workout effort rating prompt |
| `setEffortTimerSound(soundId)` | Persists the effort-timer alert sound |
| `setRestPingInterval(seconds)` | Persists periodic rest reminders |
| `setRestPingSound(soundId)` | Persists the rest-ping sound |

---

## Settings Screen

**File**: `lib/features/settings/settings_screen.dart`

Entry path: `HomeScreen` → Maintenance sheet → `SettingsScreen`

The screen's section labels are rendered by `OmniCardHeader`. The label set and
order are pinned by the Settings section test in `test/header_standardization_test.dart` rather than
enumerated here — the list is presentation, and prose enumeration of it drifts.

### Sections

The screen groups preferences, sound and alert behaviour, workout follow-up, appearance, and the
platform-health sync toggles. Two
rules matter beyond the row list:

- **Height is stored canonically in centimetres regardless of the display unit.** Switching the
  unit toggle never rewrites a saved height; only the input shape and the rendered form change.
  This is the general units rule from [Global Conventions](global_conventions.md) applied to the
  one measurement with a compound display form.
- **Sound choices preview immediately on tap** through `TimerAlertService.playPreview`, and audio
  playback no-ops safely on web rather than throwing.

### Version Footer

The footer reports the installed app version and build, resolved once at startup from
`package_info_plus` and threaded in as `AppVersionInfo`. The string is built by
`AppVersionInfo.formatVersionLine()` so the screen and its tests share one formatter.

**No version literal is baked into `lib/features/settings/`.** A version bump is picked up from
`pubspec.yaml` with zero source changes. A placeholder exists only in the startup catch block so
the footer stays renderable if the platform lookup fails; it never reaches a widget under normal
operation.

### Removed Surface

The Settings screen does not include account-management rows such as sign-in, export-data, or account-removal actions.

The platform-health toggles are the one settings area that can fail to take effect: an OS permission
denial is persisted as its own toggle state (rather than silently reading as off) so the row can
point the user at system settings. The gate each pipeline reads is owned by `SettingsState`; see
[State Management](state_management.md).

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


---

> **Doc freshness** — Last reconciled against source: 2026-06-29. This doc is derived from source, not hand-maintained. Source of truth: the `lib/` tree as it exists on the reconciliation date. If you find a claim here that disagrees with `lib/`, `lib/` wins — please flag the drift in a fresh chat with the Coordinator agent.
