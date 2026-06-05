# Widget Catalog

## Overview

Reusable UI components live in `lib/widgets/` and are organized by purpose. All widgets follow these conventions:
- Presentation-only (no repository or service access)
- Local UI state only (e.g., `_isPressed`, animation controllers)
- Design tokens from `OmniTheme` (never hardcoded colors/sizes)

Note on resume dialog:
- The cold-start `Unfinished Session` dialog is implemented as a private, screen-local widget in `HomeScreen` (`_ResumeSessionDialog`).
- It is intentionally not promoted into `lib/widgets/` because it is feature-specific and not reused across screens.

---

## Directory Structure

```
lib/widgets/
├── buttons/              # (empty — reserved for future button components)
├── cards/                # Tile and card components for the home screen
├── layout/               # Foundational layout primitives
├── logo/                 # Brand elements (Zen Halo)
├── models/               # Presentation-layer data classes
├── pickers/              # Selection dialogs
└── session/              # Workout session metric widgets
```

---

## Layout Primitives

### `OmniGradientBackground`

**File**: `lib/widgets/layout/omni_gradient_background.dart`

Full-screen cosmic gradient backdrop used on every screen.

| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `child` | `Widget` | required | Content to overlay |
| `showRadialHighlight` | `bool` | `true` | White radial glow at top-center |

**Layers** (bottom to top):
1. Vertical linear gradient (`backgroundGradientTop` → `backgroundGradientBottom`)
2. Optional radial white highlight (10% opacity)
3. Optional film-grain noise overlay (`NoiseOverlayPainter`) — controlled by `OmniTheme.enableBackgroundNoise`

### `OmniBackHeader`

**File**: `lib/widgets/layout/omni_back_header.dart`

Standardized back-and-title header used by all secondary screens. Implements `PreferredSizeWidget` so it slots directly into `Scaffold.appBar`.

| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `title` | `String` | required | Primary header text |
| `subtitle` | `String?` | `null` | Optional second line below the title in `bodySmall` + `OmniTheme.colors.textSecondary` |
| `onBack` | `VoidCallback?` | `null` | Called on back arrow tap; defaults to `Navigator.of(context).pop()` |
| `actions` | `List<Widget>?` | `null` | Trailing widgets forwarded to `AppBar.actions` |

**Behavior**:
- `preferredSize` is always `Size.fromHeight(kToolbarHeight)` (56 px)
- `backgroundColor` and `surfaceTintColor` are `Colors.transparent`, `elevation: 0` — gradient background shows through
- Back arrow color: `OmniTheme.colors.textDominant` (never inherits from theme's `foregroundColor`)
- `titleTextStyle`: `titleLarge` + `FontWeight.w600` + `OmniTheme.titleLetterSpacing` (0.4) + `OmniTheme.colors.textDominant`
- Screens must set `extendBodyBehindAppBar: true` on their `Scaffold` for the gradient to render behind the transparent header

**Usage notes**:
- Calendar uses `actions: [FilledButton('+')]` for the Periods shortcut
- `SessionSummaryScreen` uses `actions: [PopupMenuButton]` for the Edit/Save/Discard overflow
- `SessionOverviewScreen` and `RoutineSetupScreen` use `subtitle` for contextual secondary text

### `OmniSurface`

**File**: `lib/widgets/layout/omni_surface.dart`

Base container for all cards and panels. Dark navy with border + shadow.

| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `child` | `Widget` | required | Content |
| `padding` | `EdgeInsets?` | `null` | Optional inner padding |
| `showShadow` | `bool` | `true` | Deep shadow toggle |

Uses `OmniTheme.colors.surface`, `surfaceBorderRadius`, `OmniTheme.colors.surfaceBorder`, `surfaceBorderWidth`, `deepShadow`.

### `OmniBottomCTA`

**File**: `lib/widgets/layout/omni_bottom_cta.dart`

Shared full-width bottom call-to-action used by screens with a single persistent footer action.

| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `label` | `String` | required | Button text; a leading `+` triggers the shared add affordance |
| `onPressed` | `VoidCallback?` | required | Tap handler; `null` disables the CTA |
| `isDestructive` | `bool` | `false` | Uses the active theme’s destructive/error colors |

**Behavior**:
- Fixed height: `OmniTheme.buttonPrimaryHeight`
- Fixed radius: `OmniTheme.buttonBorderRadius`
- Footer-safe spacing via `SafeArea(top: false)` with shared padding
- Theme-reactive fade gradient behind the button using `colorScheme.surface`
- Prevents per-screen CTA styling drift by centralizing footer layout and colors

### `NoiseOverlayPainter`

**File**: `lib/widgets/layout/noise_overlay_painter.dart`

`CustomPainter` that renders a subtle film-grain texture over the gradient background. Creates a premium aesthetic without being distracting.

---

## Home Screen Cards

### `EnergyTile`

**File**: `lib/widgets/cards/energy_tile.dart`

Primary home-screen modality tile. `StatefulWidget` with press-scale animation.

| Prop | Type | Description |
|------|------|-------------|
| `title` | `String` | Tile label (e.g., "Cardio / Endurance") |
| `icon` | `IconData` | Tile icon |
| `gradientColors` | `List<Color>` | Background gradient |
| `accentColor` | `Color` | Glow/accent color |
| `onTap` | `VoidCallback` | Tap handler |
| `isActive` | `bool` | Highlights when session matches this modality |

**Behavior**:
- Press scale: `OmniTheme.pressedScale` (0.96) with 180ms animation
- Active state: enhanced glow border + increased opacity
- Responsive: text labels hide below 100px width via `LayoutBuilder`

### `EnergyCore`

**File**: `lib/widgets/cards/energy_core.dart`

Circular icon widget inside `EnergyTile`. Radial gradient background with glow shadow.

| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `icon` | `IconData` | required | Center icon |
| `gradientColors` | `List<Color>` | required | Radial fill |
| `glowColor` | `Color` | required | Outer glow |
| `isActive` | `bool` | `false` | Glow intensity boost |
| `size` | `double` | `OmniTheme.energyCoreSize` | Circle diameter |

### `MaintenanceTile`

**File**: `lib/widgets/cards/maintenance_tile.dart`

Small tile used inside the home screen's maintenance bottom sheet for system features (Profile, Stats, Settings). Simpler styling than `EnergyTile`.

### `OmnitrainCategoryTile` / `WorkoutCategoryCard`

**Files**: `lib/widgets/cards/omnitrain_category_tile.dart`, `lib/widgets/cards/workout_category_card.dart`

Legacy/alternative tile implementations. May be deprecated stubs — check code for current usage.

### `ModalityTileWidget`

**File**: `lib/widgets/cards/modality_tile_widget.dart`

**DEPRECATED.** Returns `SizedBox.shrink()`. Replaced by `EnergyTile`.

---

## Logo & Brand

### `AnimatedZenHalo`

**File**: `lib/widgets/logo/animated_zen_halo.dart`

Animated brand mark with slow rotation (8000ms) and breathing pulse (3000ms). Used on the splash screen.

### `ZenHaloPainter`

**File**: `lib/widgets/logo/zen_halo_painter.dart`

`CustomPainter` for the Enso arc (zen circle). Stroke reveal animation at 1200ms.

---

## Picker Dialogs

### `ExercisePickerDialog`

**File**: `lib/widgets/pickers/exercise_picker_dialog.dart`

Modal dialog for searching and selecting exercises. Receives `sessionModality` to rank exercises by relevance.

**Key features**:
- Real-time search with `TextField`
- Exercises ranked by `getExercisesRankedForModality()` (relevance score)
- Filter by discipline or muscle group
- "New Exercise" button → opens `ExerciseEditorScreen` with picker/session modality prefilled via `contextModality`
- Returns selected `Exercise` on tap

### `MetricChooserDialog`

**File**: `lib/widgets/pickers/metric_chooser_dialog.dart`

Modal dialog for choosing a tracking method. Shown in Free Training mode and routine creation.

**Key features**:
- Displays only capabilities the selected exercise supports
- Each capability shown as tappable tile with icon and label
- Returns chosen metric string (e.g., `'time'`, `'reps'`, `'hold'`, `'rounds'`)

### `ModalityPickerDialog`

**File**: `lib/widgets/pickers/modality_picker_dialog.dart`

Modal dialog for selecting a modality for an exercise being added to a null-modality (Free Training or Routine) session.

**Key features**:
- Shows all five modalities plus a "General" option
- Returns `(true, String? modality)` record when the user picks an option:
  - Specific modality: `(true, 'cardio_endurance')` etc.
  - "General": `(true, null)`
- Returns `null` when the user cancels (so callers can distinguish cancel from "General")
- Callers use `showDialog<(bool, String?)>` and check for `null` before destructuring

---

## Session Metric Widgets

### `DominantMetricWidget`

**File**: `lib/widgets/session/set_metric_widget.dart`

Unified large-metric display widget used across all effort kinds. Renders exactly **one** large metric value.

| Prop | Type | Description |
|------|------|-------------|
| `displayText` | `String` | The value to show (e.g., "10", "03:00", "Round 1\n03:00") |
| `isMultiline` | `bool` | Multi-line rendering for round display |
| `onTap` | `VoidCallback?` | Tap handler (edit reps, toggle timer) |

The following files are **stub redirects** to `DominantMetricWidget`, kept for import compatibility:
- `lib/widgets/session/drill_metric_widget.dart`
- `lib/widgets/session/round_metric_widget.dart`
- `lib/widgets/session/timed_metric_widget.dart`

### `InlineMetricEditor`

**File**: `lib/widgets/session/inline_metric_editor.dart`

Touch-optimized value input for workout environments. Tap the number to open a numeric-entry modal (the crown scrub control is present in the codebase but not rendered — see `MetricCrownWidget`).

| Prop | Type | Description |
|------|------|-------------|
| `metricType` | `String` | `reps`, `weight`, `duration`, `rpe`, `extra-weight` |
| `currentValue` | `dynamic` | Value to display |
| `unitLabel` | `String` | Label below value (e.g., "REPS", "LBS") |
| `emphasisTier` | `MetricEmphasisTier?` | Optional value emphasis: `dominant`, `secondary`, `muted`; default keeps legacy displayLarge styling |
| `isReadOnly` | `bool` | When true: disables tap-to-edit popup. Used for live timer displays. |
| `onTap` | `VoidCallback?` | When provided, tapping the number calls this instead of opening the generic popup (e.g. timer toggle, duration dialog). |
| `onValueChanged` | `Function(dynamic)` | Immediate callback on value change |

**Interaction model**:
- Number tap is the sole value-change mechanism.
  - `onTap` provided → delegates to `onTap`.
  - `onTap` null and `!isReadOnly` → opens `showMetricEditPopup`.
  - `isReadOnly: true` → no interactive affordance.
- The crown scrub control (`MetricCrownWidget`) is dormant — it remains in the codebase at `lib/widgets/session/metric_crown_widget.dart` and can be re-enabled in the row without rebuilding the widget.

**Visual**: Value size and styling unchanged. The crown is not rendered. When `isReadOnly` and `emphasisTier` are both set, the emphasis tier wins and the value is not dimmed.

**Session context (live timed/round/drill)**: In `WorkoutSessionScreen` detail view, the `InlineMetricEditor` for live timer-based efforts (`timed`, `round`, `drill`) uses `onTap` wired to `showDurationEntryDialog` so tapping the time value opens the h/m/s editor. When the effort is finished (`isTimedFinished`, `isFinished`, `isDrillFinished`), `isReadOnly: true` is set so the value cannot be edited from live mode (use edit mode for corrections). Play/pause control is a separate Start button — not a tap on the value display. Timed and drill timers render at the dominant tier; the play/pause status label sits on a line below the value.

---

### `MetricCrownWidget`

**File**: `lib/widgets/session/metric_crown_widget.dart`

**Status: dormant.** The widget is fully implemented and constructible but is not rendered by `InlineMetricEditor` in the default interaction path. It can be re-enabled by adding it to the `InlineMetricEditor` row without any other changes.

A rotatable thumb-wheel (crown) control painted as a thick vertical wheel edge-on.

| Prop | Type | Description |
|------|------|-------------|
| `metricType` | `String` | Metric type (forwarded to `MetricStepCalc`) |
| `currentValue` | `dynamic` | Current metric value; read on each drag tick |
| `onValueChanged` | `Function(dynamic)` | Fires on each 10px drag step |

**Behavior**: drag fires `onValueChanged` via `MetricStepCalc.apply`. Crown rotates `2π / 120px` radians per pixel. Rotation accumulates for the widget's lifetime but stops immediately on drag release (no momentum). No `AnimationController` or `Timer`.

**Style**: `44×60` touch target; `CustomPaint` centred inside; all colours from `OmniTheme.colors.textMuted`/`textSecondary` with opacity overlays.

**Drag step sensitivity** (from `MetricStepCalc.apply`):
| Metric | Increment per 10px | Range |
|--------|-------------------|-------|
| `reps` | ±1 | 0–999 |
| `weight` | ±0.5 | 0.0–999.0 |
| `duration` | ±5 sec | 0–3600 |
| `rpe` | ±1 | 1–10 |
| `extra-weight` | ±0.5 | -100.0–200.0 |

---

### `showMetricEditPopup`

**File**: `lib/widgets/session/metric_crown_widget.dart` (top-level function)

Opens an `AlertDialog` for exact numeric entry of a metric value.

```dart
Future<void> showMetricEditPopup(
  BuildContext context, {
  required String metricType,
  required dynamic currentValue,
  required String unitLabel,
  required Function(dynamic) onValueChanged,
})
```

- Pre-fills field with formatted current value; selects all text on open.
- Confirm ("Ok"): parses + clamps → `onValueChanged` → closes.
- Barrier tap (outside dialog): closes without calling `onValueChanged`. There is NO Cancel button.
- Empty or unparseable text → treated as dismiss (no value change).
- Keyboard: `signed: true` for `weight`/`extra-weight`; `signed: false` for all other metric types (e.g., `reps`).
- Ok button has explicit `shape: RoundedRectangleBorder(borderRadius: OmniTheme.buttonUtilityRadius)`.

---

### `showDurationEntryDialog`

**File**: `lib/widgets/session/duration_entry_dialog.dart` (top-level function)

Shared h/m/s duration-entry dialog. Used by `WorkoutSessionScreen` (both live and edit modes) and `RoutineSetupScreen` (round effort duration targets).

```dart
Future<int?> showDurationEntryDialog(
  BuildContext context, {
  String title = 'Edit Duration',
  String subtitle = '',
  required int initialSecs,
})
```

- Returns confirmed duration in whole seconds (`h*3600 + m*60 + s`), or `null` if dismissed.
- Three `TextField` instances for hours, minutes, seconds. Pre-filled from `initialSecs`.
- Single "Ok" `FilledButton`. No Cancel button. Barrier tap dismisses without applying.
- `TextEditingController`s are deferred-disposed (300 ms after dialog close) to avoid use-after-dispose errors.

**Usage**: Wire to `onTap` on `InlineMetricEditor` when `metricType == 'duration'`.

---

### `MetricStepCalc`

**File**: `lib/widgets/session/metric_crown_widget.dart` (static class)

Shared utility for value-adjustment math and popup parsing. Used by both `MetricCrownWidget` and `showMetricEditPopup`.

- `MetricStepCalc.apply(metricType, currentValue, deltaY)` — drag step math (identical to previous `InlineMetricEditor._calculateNewValue`).
- `MetricStepCalc.parseAndClamp(metricType, text)` — parse popup input, clamp to metric range, return typed result (`int` for reps, `double` for others). Returns `null` if unparseable.

---

## Presentation Models

### `UiSetData`

**File**: `lib/widgets/models/ui_set_data.dart`

Mutable presentation-layer data class for set tracking. **Not a persistence model.**

| Field | Type | Description |
|-------|------|-------------|
| `id` | `String` | Unique identifier |
| `exerciseId` | `String` | Parent exercise |
| `reps` | `int` | Mutable — current reps value |
| `weight` | `double` | Mutable — current weight value |
| `duration` | `int` | Mutable — current duration in seconds |
| `timestamp` | `DateTime` | When created |

Used by `WorkoutSessionScreen` and `RoutineSetupScreen` for ephemeral UI state.

---

## Composition Pattern

```
OmniGradientBackground              ← Full-screen cosmic backdrop
  └── OmniSurface                   ← Dark navy card with border + deep shadow
       └── Content                  ← Text, icons, interactive elements

GestureDetector (press tracking)
  └── AnimatedScale (press feedback)
       └── EnergyTile (gradient + shadows)
            └── EnergyCore (icon circle) + Label
```

---

## Related Documentation

- [Design System](design_system.md) — Design tokens, color system, typography, animation rules
- [Modality-Based Exercise UI](modality_based_exercise_ui.md) — How metric widgets are used in the workout screen

---

**Document Version**: 1.0
**Last Updated**: February 28, 2026
