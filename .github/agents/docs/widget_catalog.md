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

### `OmniSurface`

**File**: `lib/widgets/layout/omni_surface.dart`

Base container for all cards and panels. Dark navy with border + shadow.

| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `child` | `Widget` | required | Content |
| `padding` | `EdgeInsets?` | `null` | Optional inner padding |
| `showShadow` | `bool` | `true` | Deep shadow toggle |

Uses `OmniTheme.surfaceColor`, `surfaceBorderRadius`, `surfaceBorderColor`, `surfaceBorderWidth`, `deepShadow`.

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

Touch-optimized scrollable value input for workout environments. Swipe up/down to adjust values without a keyboard.

| Prop | Type | Description |
|------|------|-------------|
| `metricType` | `String` | `reps`, `weight`, `duration`, `rpe`, `extra-weight` |
| `currentValue` | `dynamic` | Value to display |
| `unitLabel` | `String` | Label below value (e.g., "REPS", "LBS") |
| `onValueChanged` | `Function(dynamic)` | Immediate callback on value change |

**Sensitivity**:
| Metric | Increment per 10px | Range |
|--------|-------------------|-------|
| `reps` | ±1 | 0–999 |
| `weight` | ±2.5 | 0.0–999.0 |
| `duration` | ±5 sec | 0–3600 |
| `rpe` | ±1 | 1–10 |
| `extra-weight` | ±2.5 | -100.0–200.0 |

**Visual**: 72pt value, 12pt unit label, drag-responsive (updates during drag).

**Session context (timer tap-to-toggle)**: In `WorkoutSessionScreen` detail view, the `InlineMetricEditor` for timer-based efforts (`timed`, `round`, `drill`) is wrapped in a `GestureDetector` with `onTap: _toggleEffortTimer`. A subtle play/pause icon overlay (20pt, 55% opacity) is positioned below the value, visible only when the timer is not finished. The GestureDetector uses `HitTestBehavior.opaque` to consume taps. On `timed` and `drill`, the Weight Adjustment control is placed outside the GestureDetector so it remains tappable.

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
