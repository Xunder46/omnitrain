# Routine, Profile & Brand Widgets

> Part of the [Widget Catalog](../widget_catalog.md). Return to the index for the complete widget list and the widget → page lookup table.

---

## Routine Primitives

### `_RoutineCard` (private to `MyRoutinesScreen`)

**File**: `lib/features/routine/my_routines_screen.dart`

One row per saved routine. The row body and the start control are **separate, non-overlapping tap
targets with different destinations**: the body opens the editor, the start control creates the
session. This split is the point of the widget — a single tap target that both edits and starts is
what it replaced. The start control's tap region is larger than its visible glyph, and no point in
a row is unresponsive.

### `DemoRoutineBadge`

**File**: `lib/features/routine/widgets/demo_routine_badge.dart`

Subtle "Demo" pill rendered next to built-in demo routines on the
`MyRoutinesScreen` list row. Sourced from `OmniTheme` typography tokens
+ `Theme.colorScheme.primary`; never hardcodes colors. Pass
`compact: true` to use the reduced horizontal padding when nested next
to a title that already has generous spacing.

The chip is purely informational — the versioned catalog refresh
pipeline (`SeedEntryType.routineTemplate`) is the source of truth for
"is this a demo"; delete / edit behaviour is identical for demo and
user routines.

**Use site**: `lib/features/routine/my_routines_screen.dart` (the row
title when `routine.isBuiltInDemo`).

---

---

## Profile Primitives

### `AvatarCropSheet`

**File**: `lib/features/profile/widgets/avatar_crop_sheet.dart`

Full-screen avatar crop step pushed between the photo picker and the
avatar save in `ProfileScreen`. Square viewport with a circular dim
scrim overlay matching the avatar's `ClipOval` display, so the user
can pinch-zoom and drag the picked photo to frame the subject
before committing.

| Prop | Type | Description |
|---|---|---|
| `imageBytes` | `Uint8List` | Encoded image bytes (JPEG, PNG, HEIC — anything `Image.memory` decodes). Read once at construction. |

**Behavior**:
- Square viewport via `AspectRatio(aspectRatio: 1.0)` capped at
  `min(screenW - 32, 360)`. Wrapped in a `RepaintBoundary` whose
  `key` is `@visibleForTesting` so tests can drive the capture
  pipeline.
- `InteractiveViewer` (`minScale: 1.0`, `maxScale: 4.0`) lets the
  user pan / zoom inside the square. A `TransformationController`
  is exposed via `@visibleForTesting` so tests can drive a
  deliberately off-center / zoomed crop.
- A circular dim scrim (`CustomPainter` using `Path.fillType =
  evenOdd`) shows what the avatar will look like inside the
  circle. `IgnorePointer`d so it never blocks the
  `InteractiveViewer` underneath.
- Bottom CTA row: `OutlinedButton` Cancel + `FilledButton` Use
  Photo, both with explicit `shape:` overrides using
  `OmniTheme.buttonBorderRadius` per the global convention. Use
  Photo is full-width with the standard
  `OmniTheme.buttonPrimaryHeight` height; Cancel is full-width
  with the same height. The Use Photo button shows a
  `CircularProgressIndicator` while the capture is in flight
  (`_isSaving = true`) and is disabled to prevent double-tap.
- On Use Photo: `RepaintBoundary.toImage(pixelRatio: 3.0)` →
  `image.toByteData(format: ui.ImageByteFormat.png)` →
  `Navigator.pop(context, bytes)`. Cancel pops with `null`.
- Capture pipeline runs in the test zone's fake async clock;
  tests wrap the tap in `tester.runAsync` + `pumpAndSettle` to
  let the render pipeline complete the frame.
- No new dependencies. The crop step is built from
  `InteractiveViewer`, `RepaintBoundary`, and `Image.memory` —
  all in Flutter's core widget set. No plugin channel, no
  platform code. The `ImageByteFormat.png` encoder is built
  into Flutter; no new image-encoding dependency is added.
- Pure presentation — no repository access, no business logic.
  The picker → crop → save wiring is owned by `ProfileScreen`.
- Pushed via `OmniNavigator.push(..., fullscreenDialog: true)` —
  **not** a raw `MaterialPageRoute`. The `OmniRoute` wraps the
  page in `OmniGradientBackground` and exposes `opaque => true`,
  which is what prevents the underlying ProfileScreen from
  bleeding through during the slide-up transition. (A raw
  `MaterialPageRoute` would expose a transparent Scaffold behind
  it during the transition — see the navigation contract in
  `docs/navigation_and_screens.md`.)

---

---

## Profile Widgets

### `MeasurementSparkline`

**File**: `lib/features/profile/widgets/measurement_sparkline.dart`

Compact trend preview inside each profile measurement card. Renders a single-value fallback when
only one entry exists and a line-with-dots chart otherwise.

X positioning is **time-based** (each entry's `recordedAtMs` is mapped linearly across the chart width) so two entries months apart sit at the chart's leftmost and rightmost x positions while many entries clustered in time sit close together. Falls back to chart mid when all timestamps are equal.

The y-axis scale and the drawn line are converted to the active display unit: a
`unit-kg` measurement goes through `UnitFormatter.convertWeight`, so the quick
chart matches the history sheet; other measurements plot as stored. It takes the
`SettingsState` for this reason. See [Profile & Measurements](../profile_and_measurements.md).

Tapping the chart opens the measurement's history sheet; the `+` control opens the log sheet.

## Logo & Brand

### `HomeLogoButton`

**File**: `lib/widgets/common/home_logo_button.dart`

The home-screen logo, which doubles as the maintenance-sheet opener. Its transparent padding
extends the gesture bounds beyond the visible circle so the target clears the platform minimum
without enlarging the mark itself.

### `AnimatedZenHalo`

**File**: `lib/widgets/logo/animated_zen_halo.dart`

Animated brand mark with slow rotation (8000ms) and breathing pulse (3000ms). Used on the splash screen.

### `ZenHaloPainter`

**File**: `lib/widgets/logo/zen_halo_painter.dart`

`CustomPainter` for the Enso arc (zen circle). Stroke reveal animation at 1200ms.

---

> **Doc freshness** — Last reconciled against source: 2026-07-26. This page is one part of the [Widget Catalog](../widget_catalog.md); see that index for the full component list. This doc is derived from source, not hand-maintained. Source of truth: the `lib/` tree. If you find a claim here that disagrees with `lib/`, `lib/` wins.
