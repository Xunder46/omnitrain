# Theme & Settings — Feature Documentation

## Overview

OmniTrain supports **multiple app themes** selectable at runtime from the Settings screen. The selected theme is persisted across sessions and applied reactively to all screens without a restart. All theme tokens, including gradient colors, surface colors, and primary accent, are sourced from a single centralised resolver.

---

## Available Themes

| Enum Value | Display Name | Primary Accent | Character |
|------------|-------------|----------------|-----------|
| `AppTheme.abyssalNeon` | Abyssal Neon | `#2DE2E6` (Neon Cyan) | Deep navy gradient, electric cyan accents |
| `AppTheme.forgeEmber` | Forge & Ember | `#FF6B35` (Ember Orange) | Dark amber-black gradient, molten orange accents |
| `AppTheme.obsidianVolt` | Obsidian Volt | `#EAE000` (Electric Yellow) | Near-black gradient, volt yellow accents || `AppTheme.circuitGreen` | Circuit Green | `#00E676` (Circuit Green) | Deep forest-black gradient, vivid green accents |
---

## Token System: `OmniTheme`

**File**: `lib/core/constants/omni_theme.dart`

### `AppTheme` Enum

```dart
enum AppTheme { abyssalNeon, forgeEmber, obsidianVolt, circuitGreen }
```

### Color Token Record

`OmniTheme.colorsForTheme(AppTheme theme)` returns a typed record with these fields:

| Token Field | Role |
|-------------|------|
| `backgroundTop` | Top color of the full-screen gradient |
| `backgroundBottom` | Bottom color of the full-screen gradient |
| `surface` | Card / panel / sheet background |
| `primary` | Interactive elements, accents, active states |
| `secondary` | Supporting accents |
| `textMuted` | Tertiary / placeholder text |
| `divider` | Separator lines |
| `surfaceBorder` | Subtle surface boundary color |

### Exact Color Values

#### `abyssalNeon`
| Token | Value |
|-------|-------|
| backgroundTop | `Color(0xFF0F1F33)` |
| backgroundBottom | `Color(0xFF060B14)` |
| surface | `Color(0xFF0E223A)` |
| primary | `Color(0xFF2DE2E6)` |
| secondary | `Color(0xFF1B9AAA)` |
| textMuted | `Color(0xFF9BA4B5)` |
| divider | `Color(0xFF1F2937)` |
| surfaceBorder | `Color(0x0FFFFFFF)` |

#### `forgeEmber`
| Token | Value |
|-------|-------|
| backgroundTop | `Color(0xFF1C1008)` |
| backgroundBottom | `Color(0xFF0A0603)` |
| surface | `Color(0xFF211407)` |
| primary | `Color(0xFFFF6B35)` |
| secondary | `Color(0xFFCC4A1A)` |
| textMuted | `Color(0xFFA07060)` |
| divider | `Color(0xFF2A1C10)` |
| surfaceBorder | `Color(0x0DFFFFFF)` |

#### `obsidianVolt`
| Token | Value |
|-------|-------|
| backgroundTop | `Color(0xFF111111)` |
| backgroundBottom | `Color(0xFF050505)` |
| surface | `Color(0xFF161616)` |
| primary | `Color(0xFFEAE000)` |
| secondary | `Color(0xFFB8B000)` |
| textMuted | `Color(0xFF666666)` |
| divider | `Color(0xFF1F1F1F)` |
| surfaceBorder | `Color(0x12FFFFFF)` |

#### `circuitGreen`
| Token | Value |
|-------|-------|
| backgroundTop | `Color(0xFF071210)` |
| backgroundBottom | `Color(0xFF030806)` |
| surface | `Color(0xFF091714)` |
| primary | `Color(0xFF00E676)` |
| secondary | `Color(0xFF00A854)` |
| textMuted | `Color(0xFF4A7A5A)` |
| divider | `Color(0xFF102018)` |
| surfaceBorder | `Color(0x0DFFFFFF)` |

### Helper Methods

| Method | Signature | Purpose |
|--------|-----------|---------|
| `colorsForTheme` | `(AppTheme) → OmniThemeColors` | Returns token record for a given theme |
| `displayNameForTheme` | `(AppTheme) → String` | Returns user-facing display name |
| `activeTheme` | `static AppTheme get` | Low-refactor global accessor for widgets not receiving SettingsState via constructor |

---

## SettingsState

**File**: `lib/state/settings/settings_state.dart`
**Depends on**: `SharedPreferences`

A `ChangeNotifier` that owns the persisted app theme selection.

### State Fields

| Field | Type | Default |
|-------|------|---------|
| `_appTheme` | `AppTheme` | `AppTheme.abyssalNeon` |

### Public API

| Member | Signature | Purpose |
|--------|-----------|---------|
| `appTheme` | `AppTheme get` | Currently selected theme |
| `setAppTheme` | `(AppTheme) → Future<void>` | Persists selection by `enum.name` and calls `notifyListeners()` |
| `_loadFromPrefs` | private | Reads `'app_theme'` key from SharedPreferences on init; falls back to `abyssalNeon` if missing/invalid |

### Persistence

- Key: `'app_theme'`
- Storage: `SharedPreferences`
- Value format: `AppTheme.name` string (e.g. `'forgeEmber'`)
- Fallback on invalid/missing key: `AppTheme.abyssalNeon`

---

## Dependency Injection

`SettingsState` is created in `main.dart` before `runApp()` and threaded through the constructor chain:

```
main.dart
  → SettingsState()   (initialized with await settingsState._loadFromPrefs())
  → MyApp(settingsState, ...)
    → HomeScreen(settingsState, ...)
      → WorkoutSessionScreen(settingsState, ...)   (for OmniTheme.activeTheme fallback)
      → SessionOverviewScreen(settingsState, ...)
      → SessionSummaryScreen(settingsState, ...)
      → SettingsScreen(settingsState)
```

`OmniTheme.activeTheme` is set from `settingsState.appTheme` at the top-level `ListenableBuilder` so that widgets deep in the tree that do not receive `settingsState` have a low-refactor path to the active token values.

---

## Reactive MaterialApp Rebuild

`MyApp` wraps its `MaterialApp` in a `ListenableBuilder` (or `AnimatedBuilder`) listening to `settingsState`:

```dart
ListenableBuilder(
  listenable: settingsState,
  builder: (context, _) {
    OmniTheme.activeTheme = settingsState.appTheme;  // sync global accessor
    return MaterialApp(
      theme: buildTheme(appTheme: settingsState.appTheme),
      ...
    );
  },
)
```

This causes `MaterialApp` to rebuild immediately when the user selects a new theme — no restart or delay.

---

## `buildTheme` in `app.dart`

**File**: `lib/app.dart`

Signature: `ThemeData buildTheme({AppTheme appTheme = AppTheme.abyssalNeon})`

- Derives `colorScheme.primary` from `OmniTheme.colorsForTheme(appTheme).primary`
- All other theme values unchanged from the original Abyssal Neon theme

---

## `OmniGradientBackground`

**File**: `lib/widgets/layout/omni_gradient_background.dart`

Now reads active theme gradient tokens instead of hardcoded values:

- Gradient uses `themeColors.backgroundTop` → `themeColors.backgroundBottom`
- Radial highlight and noise overlay behavior is **unchanged**
- `themeColors` is resolved from `OmniTheme.colorsForTheme(OmniTheme.activeTheme)`

---

## Settings Screen

**File**: `lib/features/settings/settings_screen.dart`

Accessible via: `HomeScreen` → Maintenance sheet → Settings

### Appearance Section

Displays a segmented theme selector with all three `AppTheme.values`:

- Each option shows a **10 px circular color swatch** (using that theme's `primary` color) to the left of the theme display name
- Selected option: surfaced styling with primary-accent border
- Unselected: transparent with muted border
- Tapping an option calls `settingsState.setAppTheme(theme)` — **no save button**; applies instantly

### Interaction Rules

- Theme changes apply immediately and persist
- The selector uses the same animated-container interaction pattern as other settings UI
- No other settings categories are implemented yet beyond Appearance

---

## Token Usage Rules (Updated)

1. **All feature screens and widgets must not hardcode hex color values**. Use `OmniTheme.colorsForTheme(OmniTheme.activeTheme)` or receive theme colors via constructor/argument.
2. `modality_colors.dart` is **not** affected by theme selection — modality accents are intentionally fixed regardless of theme.
3. `OmniSurface` resolves surface/border colors from the active theme token path so glass-panel surfaces automatically adapt.
4. Maintenance sheet background, drag handle, and `MaintenanceTile` fill/icon colors all react to the active theme.

---

## Screen-Level Theme Wiring Summary

| Screen | How It Gets Theme Colors |
|--------|--------------------------|
| `HomeScreen` maintenance sheet | `OmniTheme.colorsForTheme(settingsState.appTheme)` |
| `SessionOverviewScreen` | Receives `settingsState` via constructor |
| `SessionSummaryScreen` | Receives `settingsState` via constructor (feeling sheet uses active tokens) |
| `WorkoutSessionScreen` | Receives `settingsState`; falls back to `OmniTheme.activeTheme` when null (edit-mode entry path) |
| `SettingsScreen` | Receives `settingsState` directly |

---

## Related Documentation

- [Design System](design_system.md) — Visual identity, color token roles, and design rules
- [Navigation & Screens](navigation_and_screens.md) — SettingsScreen navigation path
- [State Management](state_management.md) — SettingsState in the dependency graph

---

**Document Version**: 1.0
**Last Updated**: March 22, 2026
