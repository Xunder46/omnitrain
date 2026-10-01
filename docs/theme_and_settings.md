# Theme & Settings — Feature Documentation

## Overview

OmniTrain's Settings screen is fully implemented. It owns persisted preferences for:

- calendar display (`Start of Week`)
- measurement units (`Weight`, `Distance`, `Height`)
- timer alert behavior (`Effort Timer Sound`, `Rest Ping`, `Rest Ping Sound`)
- notification permission copy that covers both rest reminders and effort-expiry alerts
- workout follow-up (`Effort Rating`, the automatic post-workout effort-rating prompt; copy verified by `test/screen_widget_test.dart`, `settings screen keeps the streamlined section layout`)
- appearance (`AppTheme` selection)

All settings apply immediately. There is no save button and no staged draft state.

---

## Theme System

**File**: `lib/core/constants/omni_theme.dart`

> **Flagged, not owned here (documentation standard §5).** The `AppTheme` enum
> block and the token-field table below are copied implementation content
> (§3.5/§3.4). They predate this document's conformance pass and are left as
> they are rather than silently rewritten: bringing them into conformance is a
> follow-up, and until then the class and
> [Design System](design_system.md) are the owners.

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

`SettingsState` is a `ChangeNotifier` backed by `WorkoutRepository` preference
storage. It owns the preference set, the default each preference falls back to,
and the key each is stored under — read them off the class. Each setter
normalises what it is handed before persisting, so a value that is not one of
its own is stored as the default rather than kept as given. Both the sound
vocabulary and the rest-ping interval options are the state's own closed sets
(`validSoundIds`, `restPingIntervalOptions`). The defaults, the keys, the
normalisation and the fallbacks are pinned by `test/settings_state_test.dart`.

**The Effort Rating toggle still stores under `show_feeling_survey`.** The key
was published before the feature was named for the rating it feeds, and
renaming it would silently reset the choice of every user who has ever answered
the prompt. `test/settings_state_test.dart` pins the persisted key.

**The Effort Rating toggle is also the wrist's.** `showFeelingSurvey` travels as
`preferences_down`'s `effortRatingPrompt`, which `watch/sync_protocol/PROTOCOL.md`
defines as whether a session ended on the wrist asks for the rating. The phone
never pushes it: a change reaches the wrist with the answer to the wrist's next
sync request. Verified by `test/watch_transport_test.dart` (`S-253`).

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
