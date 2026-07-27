# Routine, Profile & Brand Widgets

> Part of the [Widget Catalog](../widget_catalog.md). Return to the index for the complete widget list and the widget → page lookup table.

---

## Routine Primitives

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

Small history visualization for a single body measurement on the Profile screen. Renders one of three branches based on the entry count read from `ProfileState.getMeasurementHistory`:

- **0 entries** — centered muted text `"No history yet"` at the sparkline's full height.
- **1 entry** — the same full chart frame as the 2+ branch (Y-axis line, X-axis line, Y-axis scale labels, X-axis date strip) with **a single horizontal line** crossing **a single filled dot** at the entry's value. Both Y-axis labels show the same value (since `minV == maxV`); both X-axis labels show the same date (since `minMs == maxMs`). The line and dot both render at the chart's visual centre via the existing `xForTimestamp` / `yForValue` fallbacks (`timeRange == 0` → data-area mid; `range == 0` → `xAxisLineY / 2`). Replaces the legacy `Divider`-only hairline so the chart frame stays visually stable across the 0/1/2+ branch transitions.
- **2+ entries** — a compact chart inside a **60 dp** container:
  - **Axes**: a vertical Y-axis line on the **left** (boundary between the y-axis label column and the data area) and a horizontal X-axis line at the **bottom** of the chart area (boundary between the data area and the x-axis date strip). Both are 1 dp `theme.dividerColor` strokes drawn by the painter inside the same `CustomPaint` as the data line + dots.
  - **Y-axis scale**: a max value label at top-LEFT and a min value label at bottom-LEFT of the chart area, in a 38 dp wide LEFT column to the left of the Y-axis line. Right-aligned so the rendered text visually anchors to the line. Rendered in `labelSmall` + `textMuted` + 9 pt. Format is the raw numeric value via `toStringAsFixed(1)` — the unit is intentionally **dropped** (the header above names the measurement and the value column shows the unit), so the LEFT column fits at the same font size as the X-axis labels. `overflow: TextOverflow.ellipsis` clips gracefully for edge cases.
  - **X-axis scale**: a first date label at bottom-left and a last date label at bottom-right via `ChartAxisHelper.formatDateLabel` (`MMM d`, e.g. `Jun 17`). The labels live in the bottom 22 dp of the container; the data + axes live in the top 38 dp.
  - **Line + dots**: `theme.colorScheme.primary` 1.5 dp stroke line through the points with a 2 dp filled dot at **every** entry. X positioning is **time-based** (each entry's `recordedAtMs` is mapped linearly across the chart width) so two entries months apart sit at the chart's leftmost and rightmost x positions while many entries clustered in time sit close together. Falls back to chart mid when all timestamps are equal.

The whole sparkline area is wrapped in an `InkWell` whose `onTap` opens the existing `MeasurementHistoryChartSheet` for the measurement.

| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `definition` | `ProfileMeasurementDefinition` | required | Which measurement to read history for (e.g. `ProfileMeasurements.bodyweight`). Drives the entry-fetch and the title-key. |
| `profileState` | `ProfileState` | required | Source of the measurement history (`getMeasurementHistory`). |
| `settingsState` | `SettingsState` | required | Injected for symmetry with the surrounding surface chrome. No longer used internally (A18 dropped the unit suffix from the y-axis labels). Reserved for future hooks. |
| `onTap` | `VoidCallback?` | `null` | Tapping anywhere inside the sparkline area fires this callback. The host wires it to `_showMeasurementHistory(definition)`. |

**Behavior**:
- Sized at **60 dp tall** (A19; was 56 dp intermediate A18, 38 dp with axes but smaller, 40 dp in A17, 60 dp pre-A17). The chart now **fills** the entire 60 dp card row — the user wants the chart to use the available vertical space rather than sit with breathing room. The host card padding (`EdgeInsets.symmetric(horizontal: 18, vertical: 14)`) wraps the sparkline; total card height stays 88 dp (60 dp chart + 28 dp padding).
- **Refresh model**: the entry list is loaded asynchronously in `initState` via `profileState.getMeasurementHistory(definition.type)`; the widget subscribes to `profileState` (added in `initState`, removed in `dispose`) and re-fetches on every `notifyListeners`; `didUpdateWidget` also reloads when the `definition.type` changes. The listener is the only reliable way to refresh the chart after a new measurement is added via the log sheet — `didUpdateWidget` does not fire when the parent rebuilds with the same `definition` (the common case after a save).
- Keys (for testability): `Key('measurement_sparkline')` on the container `SizedBox`; `Key('measurement_sparkline_tap')` on the `InkWell` gesture area; `Key('measurement_sparkline_y_max')` / `Key('measurement_sparkline_y_min')` on the y-axis value `Positioned`s (LEFT column); `Key('measurement_sparkline_x_first')` / `Key('measurement_sparkline_x_last')` on the x-axis date label `Positioned`s (BOTTOM strip).
- Presentation-only: no repository access of its own (delegates to the injected `ProfileState`), no service access, no business logic. All chart math is local; the painter is a small private class inside the same file. Scale math delegates to the canonical `ChartAxisHelper` and `UnitFormatter` owners (per `docs/global_conventions.md` "Reuse the canonical owner").
- Host layout (per A16, Phase 4 refinement, updated by A17): the per-measurement card body is a 3-section row `[chart rectangle | current value | + button]`. The chart rectangle occupies the available width (`Expanded`), the value column is a fixed 90 dp wide text centred horizontally (`textAlign: TextAlign.center`, `maxLines: 1`, `overflow: TextOverflow.ellipsis`), and the `+` button is the standard 60 × 60 dp outlined `OutlinedButton`. The `OmniCardHeader` is **title-only — no actions cluster** and **uppercased** (A17: `definitions[index].label.toUpperCase()`, so the rendered eyebrow reads e.g. `BODY WEIGHT` not `Body Weight`). Tapping the chart rectangle opens the existing history sheet; tapping the `+` button opens the existing log sheet. Only the titles (`MEASUREMENTS` / `ADDITIONAL` section eyebrows) were extracted into the header in Phase 4; the card body's column structure stays intact.

---

---

## Logo & Brand

### `HomeLogoButton`

**File**: `lib/widgets/common/home_logo_button.dart`

Circular menu/avatar control for the home-screen AppBar that hosts the brand logo. Tapping opens the Hub sheet (Calendar / Stats / Profile / Nutrition / Settings).

**Visual chrome** (rendered in this order, back to front):
- 56×56 circular surface with a subtle ~6% white overlay (`Color(0x0FFFFFFF)`, matching the `OmniTheme.colors.surfaceBorder` token value) so the button has presence on the dark navy header
- 1px `surfaceBorder` ring (~6% white) reinforcing the circle edge — stays monochrome
- `OmniTheme.softShadow` for a low-elevation drop that gives the button its 3D feel against the dark header
- Brand logo artwork (`assets/icon/omnitrain_logo.png`) centered inside, sized to fill the circle (default 55×55 in a 55×55 circle)

**Theme tint** (logo recolor):
- The brand logo's own aqua-cyan matches the **Abyssal Neon** primary (`0xFF2DE2E6`), so on Abyssal Neon the logo is rendered untouched
- On every other theme the logo is recolored to that theme's `OmniTheme.colors.primary` via a `ColorFiltered` with `BlendMode.srcATop` (preserves the alpha mask, replaces RGB with the tint color — silhouette stays crisp)
- Tint comes from an existing `OmniTheme` token, so the button stays in-palette without introducing a new color

**Press reaction**:
- AnimatedScale to `OmniTheme.pressedScale` (0.9) on finger-down; settles back on release / cancel
- Subtle white `ColorFilter` highlight (~10% white) on the logo while pressed
- `HapticFeedback.lightImpact()` fires on `onTapUp`, guarded by `!kIsWeb`
- Reduced-motion users get the scale applied instantly without animation

**Hit target & accessibility**:
- 8px horizontal + 4px vertical transparent `Padding` around the visible circle brings the gesture bounds to 72×64 — well above the 44×44pt minimum
- Explicit `ConstrainedBox(minWidth: 44, minHeight: 44)` + `HitTestBehavior.opaque` keep the guarantee even if `tileSize` is later reduced
- `Semantics(button: true, label: 'Open menu')` wraps the whole control; the ring is decorative and the screen reader only hears the parent's label

| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `onTap` | `VoidCallback` | required | Fires on tap (after the gesture is released) |
| `size` | `double` | `55` | Logo artwork side length in logical pixels |
| `tileSize` | `double` | `55` | Outer circle diameter; matches `kToolbarHeight` (56) exactly so the AppBar toolbar height stays unchanged |

**Constraints**:
- Body-centered "TRAIN" title in the home `Column` is unaffected — the button is in the AppBar `title:` slot and its visible circle (56px) matches `kToolbarHeight` (56) exactly
- The control is a presentation-only widget: no repository or service access; only local `_isPressed` state

### `AnimatedZenHalo`

**File**: `lib/widgets/logo/animated_zen_halo.dart`

Animated brand mark with slow rotation (8000ms) and breathing pulse (3000ms). Used on the splash screen.

### `ZenHaloPainter`

**File**: `lib/widgets/logo/zen_halo_painter.dart`

`CustomPainter` for the Enso arc (zen circle). Stroke reveal animation at 1200ms.

---

> **Doc freshness** — Last reconciled against source: 2026-07-26. This page is one part of the [Widget Catalog](../widget_catalog.md); see that index for the full component list. This doc is derived from source, not hand-maintained. Source of truth: the `lib/` tree. If you find a claim here that disagrees with `lib/`, `lib/` wins.
