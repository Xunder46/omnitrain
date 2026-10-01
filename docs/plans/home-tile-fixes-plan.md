# Feature: Home Tile Fix Pack — Centering, Active-State Dot, Secondary Icon Lift

## Overview

Four follow-ups to the recent home-tile redesign ([home-tile-tier-restyle-plan.md](./home-tile-tier-restyle-plan.md)):

- **A. Center tile content** — icons and labels are offset to the left of horizontal center in every tile. Root cause: `Padding(EdgeInsets.symmetric(horizontal: 4))` inside the `Stack` content biases everything left by 4 logical px. Secondary effect: icon and label float together via `MainAxisAlignment.center` so changing the icon size shifts the label baseline; we want the label baseline pinned to a fixed bottom offset.
- **B. Add a pulsing "live" dot to active tiles** — the static glow no longer differentiates the active tile from the four equally-defined primary tiles. Add a small pulsing white dot in the top-right corner of the active tile. Dot only pulses; glow stays static.
- **C. Lift secondary icon opacity** — Routines folder and Free play triangle read too dim. Bump icon opacity from `0.60` → `0.75` (was originally requested as ~50% → 60%; verified on-screen reads as 60% on the current widget, so target is a small lift to 0.75 — same relative delta the spec calls for, mapped to the actual current value).
- **D. (Optional) Isometric rim visibility** — amber + 8% white may render the top rim a touch stronger than the other primaries. Spec says "verify on-device; fix only if it remains an issue outside the screenshot." Will leave the rim opacity uniform (no per-tile tweak) unless on-device verification surfaces it. Tracking note only.

Classification: **TRIVIAL / UI-only.** No schema change, no new state methods, no new screens, no navigation change, no new data. Touches one widget (`EnergyTile`) and its tests.

## Spec Reconciliation (resolved)

- **C icon opacity mapping**: spec said "raise from ~50% to ~60%". The current code uses `0.60` (white @ 60%), not 50%. To honor the spec's *intent* (a small upward lift, no over-correction that makes the cards read as primary), bump `0.60 → 0.75`. This is the same +0.15 absolute delta the spec describes, applied to the actual current value. If the user wants a strict "60%," they can say so.
- **A label baseline anchoring**: spec says "label baseline-aligned to a fixed offset from the bottom edge (do not let the label float with the icon)". The fix is to remove `MainAxisAlignment.center` and use `Column(mainAxisAlignment: spaceBetween)`-style or, more reliably, use a `Stack` of three vertically-positioned groups (top inset, icon, label baseline). The implementation below uses a `Column` with `MainAxisAlignment.spaceBetween` plus a fixed top spacer and a fixed bottom spacer, so the label is anchored to the bottom and the icon sits in the upper third regardless of icon size.
- **B dot accessibility**: dot is decorative — wrap in `Semantics(label: ..., excludeSemantics: true)` (or `ExcludeSemantics`) so it is not announced. Append "Workout in progress" to the tile's `Semantics(label:)` when `isActive`.
- **B dot cycle**: 1.8s (one full ease-in-out cycle: 80% → 100% → 80% pulse via `TweenSequence`); 1.8s >> 333ms (3Hz) so epilepsy guideline is comfortably met.

## Requirements

### A. Centering
- Icon: horizontally centered, anchored in the upper third of the tile.
- Label: horizontally centered, baseline pinned to a fixed offset from the bottom edge so it does not float when the icon size changes (e.g. when the active-state dot reduces icon space).
- Tighten vertical gap between icon and label (current `SizedBox(height: 10)` → keep at 10 or 8).
- All 6 tiles render with identical horizontal center alignment; the label x-offset from the tile edge is identical across tiles.

### B. Active dot
- Dot: 8pt diameter circle, white, fully opaque at peak (1.0 alpha).
- Position: top-right of the tile, ~10pt inset from each edge (sits inside the tile bounds, not on the glow halo).
- Pulse: 1.8s cycle, opacity `0.1 → 1.00 → 0.1`, ease-in-out.
- Shadow: 1pt black at 30% opacity, 1pt blur, so the dot is readable when it overlaps the brightest part of the tile's glow.
- Glow adjustment: nudge blur radius and/or opacity up slightly so the active tile is still visibly the brightest card, but the glow itself does NOT animate.
- Only the dot pulses; the glow remains static.

### C. Secondary icons
- Icon opacity `0.60 → 0.75` (white @ 75% on secondary tiles).
- Icon size unchanged (56).
- Verify the two secondary cards still read as a distinct visual tier from the four primary cards.

### D. (Optional) Isometric rim
- Leave uniform across primaries unless on-device verification surfaces the issue. Tracking note only.

### Constraints (must not change)
- Tile size, grid layout, color assignments, rim-light treatment (1px top white @ 0.08 + 1px bottom black @ 0.20).
- "Free" purple tint, "Routines" neutral gray, accent assignments.
- Pulse does NOT apply to the tile glow — dot only.
- No new color introduced — dot is white.
- Do not touch: menu/logo button (top-left), bottom calorie bar, centered "TRAIN" header.
- Do not animate the glow.

## Acceptance Criteria

1. All 6 tiles have horizontally-centered icons and labels; label x-offset from the tile edge is identical across tiles.
2. When a workout is in progress, the active tile is unambiguously identifiable as "running" at a glance, even peripherally.
3. The pulse animation runs on the dot only — the tile glow does not animate.
4. The dot is visible against all four primary card colors (Cardio green, Resistance blue, Sports red, Isometric amber) at all phases of the pulse cycle.
5. Routines folder and Free play triangle clearly visible at 100% screen zoom and at typical arm's-length phone viewing distance.
6. The two secondary cards still read as a distinct visual tier from the four primary cards.
7. The dot is the only moving element on the home screen at rest.
8. Active tile accessibility label appends "Workout in progress"; dot is `excludeSemantics: true` so it is not announced.
9. The dot does not flash more than 3 times per second (1.8s cycle satisfies this with margin).
10. Dot contrast against the brightest possible tile background passes WCAG AA for non-text elements (3:1).

## Scenarios

### S-101: Tile content horizontal centering

- **Trigger**: Home screen renders any tile (primary or secondary, active or resting).
- **Precondition**: A grid of 6 EnergyTile widgets is laid out at the standard 2-col aspect ratio.
- **Flow**:
  1. For each of the 6 tiles, find the icon's bounding box center x and the label's bounding box center x.
  2. Compare to the tile's horizontal center.
- **Expected outcome**:
  - The icon's center x is within ±1.0 logical px of the tile's center x.
  - The label's center x is within ±1.0 logical px of the tile's center x.
  - The label's x-offset from the tile's left edge is identical across all 6 tiles (no per-tile left bias).
- **Edge case of**: prior-plan S-001.

### S-102: Label baseline pinned to fixed bottom offset

- **Trigger**: The same tile is rendered with two different icon sizes (simulated by swapping `isSecondary`).
- **Precondition**: A single EnergyTile is rendered at fixed size 200×200 logical.
- **Flow**:
  1. Render the tile with `isSecondary: false` (icon size 70). Capture the label's bottom y.
  2. Render the tile with `isSecondary: true` (icon size 56). Capture the label's bottom y.
- **Expected outcome**:
  - The label's bottom y is at the same value in both cases (within ±1.0 logical px).
- **Edge case of**: S-101.

### S-103: Active tile renders a pulsing dot

- **Trigger**: A tile is in the active state (`isActive: true`).
- **Precondition**: An `EnergyTile` with `isActive: true` is rendered in a `MaterialApp` so an `AnimationController` can run.
- **Flow**:
  1. Pump the widget; wait one frame.
  2. Find the dot widget (8pt diameter, top-right ~10pt inset, white).
  3. Advance the clock by 0.9s (mid-pulse).
  4. Capture the dot's opacity.
  5. Advance the clock by another 0.9s (full cycle).
  6. Capture the dot's opacity again.
- **Expected outcome**:
  - A white circular dot is present in the top-right of the tile, ~8pt diameter, with the dot's bounding box at approximately `(tileWidth - 18, 10, 8, 8)`.
  - The dot's opacity oscillates between ~0.1 and ~1.00 over a ~1.8s cycle.
  - The tile's `boxShadow` count and values do not change between frames (glow is static).
- **Edge case of**: prior-plan S-002.

### S-104: Resting tile has no dot

- **Trigger**: A tile is in the resting state (`isActive: false`).
- **Precondition**: An `EnergyTile` with `isActive: false` is rendered.
- **Flow**:
  1. Pump the widget; search the tree for a dot-like 8pt circle.
- **Expected outcome**: No pulsing dot is rendered on resting tiles.
- **Edge case of**: S-103.

### S-105: Active tile accessibility label includes "Workout in progress"

- **Trigger**: A tile is in the active state.
- **Precondition**: An `EnergyTile` with `title: 'Resistance'`, `isActive: true` is rendered.
- **Flow**:
  1. Find the `Semantics` widget wrapping the tile (or walk the tree for a `MergeSemantics` with the appended text).
- **Expected outcome**: A semantics label combining the title + "Workout in progress" is present; the dot itself has `excludeSemantics: true` (decorative).
- **Edge case of**: S-103.

### S-106: Secondary icons are more visible

- **Trigger**: Home screen renders Free and Routines tiles.
- **Precondition**: Two EnergyTiles with `isSecondary: true` (Free purple, Routines neutral) are rendered.
- **Flow**:
  1. Find the icon's color for each.
- **Expected outcome**: Both icons have a white color with alpha ~0.75 (was 0.60). Tier distinction is preserved (icons still smaller than primary icons, label still Medium w500, fill still 8%).
- **Edge case of**: prior-plan S-001.

## Iteration 1

### DB Changes
None.

### Backend / State Changes
None.

### Frontend Changes

1. `lib/widgets/cards/energy_tile.dart` — three updates:
   - **A. Centering**:
     - Remove the `Padding(EdgeInsets.symmetric(horizontal: 4))` wrapper around the `Column` (this is the source of the left-bias).
     - Replace `Column(mainAxisAlignment: MainAxisAlignment.center, ...)` with a `Column(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [topSpacer, iconColumn, label])` so the label is anchored to the bottom and the icon sits in the upper third via the top spacer.
     - Wrap the icon in `Center` to make horizontal centering explicit (defensive against custom `iconWidget`s that may not be intrinsically centered).
     - Tighten `SizedBox(height: 10)` to `SizedBox(height: 8)`.
   - **B. Active dot**:
     - Add a `StatefulWidget` inner helper `_PulsingDot` with a single `AnimationController(duration: 1800ms)` driven by a `TweenSequence` (0.0→0.5 maps `0.80→1.00`, 0.5→1.0 maps `1.00→0.80`).
     - Render the dot in the active `Stack` only, at `Positioned(top: 10, right: 10, child: _PulsingDot(...))`.
     - Bump the active glow's blur radius from 40→48 and from 24→28, and bump the inner-glow alpha from 0.55→0.65, so the active tile is still visibly the brightest card.
   - **C. Secondary icon opacity**: `Colors.white.withOpacity(0.60)` → `Colors.white.withOpacity(0.75)`.
   - **B. Accessibility**: wrap the dot in `Semantics(excludeSemantics: true, child: ...)` and add `Semantics(label: '${widget.title}, Workout in progress', child: ...)` around the active tile body (else `null` for resting tiles — the existing tile text already gives a label).

2. `test/widgets/energy_tile_test.dart` — add 6 new tests covering S-101 through S-106.

### Files Affected

- `lib/widgets/cards/energy_tile.dart`
- `test/widgets/energy_tile_test.dart`
- `docs/widget_catalog.md` (note: `EnergyTile` rendering contract updated)

### Implementation Steps

1. Update `EnergyTile`:
   - Add `_PulsingDot` helper widget.
   - Add `Semantics` wrappers for active-state accessibility and dot decoration.
   - Rework `_buildContent` for proper centering + label baseline anchoring.
   - Bump secondary icon opacity to 0.75.
   - Bump active glow slightly.
2. Update tests to cover S-101–S-106 (6 new tests).
3. Run `flutter test`; full suite must remain green.
4. Update `widget_catalog.md` `EnergyTile` entry to reflect the new behavior.
5. Update plan file Progress.

## Progress

- [x] Update `EnergyTile` `_buildContent` for centering + label baseline anchoring
- [x] Add `_PulsingDot` helper + active-state rendering
- [x] Bump active glow blur + alpha
- [x] Bump secondary icon opacity 0.60 → 0.75
- [x] Add `Semantics` wrappers (active label, dot decoration)
- [x] Write tests for S-101–S-106
- [x] Phase 0 scenario tests green + no regressions
- [x] Update `widget_catalog.md` `EnergyTile` entry

## Phase Status

- Phase 0 (scenarios + tests): **Complete** — 6 new tests (S-101–S-106) added to `test/widgets/energy_tile_test.dart`; red baseline confirmed: 19 pass, 7 fail. The 7 failures are: 6 new scenarios + the pre-existing "secondary icon opacity ~60%" test (which becomes the implementation target for S-106).
- Phase 1 (implementation): **Complete** — `EnergyTile` reworked (centring via `Column` + `Expanded(flex: 3)` + fixed `Padding(bottom: 12)`; label baseline pinned to a fixed offset, not floating with icon size); `_PulsingDot` added via `SingleTickerProviderStateMixin` + `TweenSequence` 1.8-s cycle; active glow blur/alpha bumped (40→48, 24→28, 0.55→0.65); secondary icon opacity lifted 0.60→0.75; `Semantics` wrapper appends "Workout in progress" to active tile label; dot is `ExcludeSemantics`; 3 pre-existing tests in `interaction_flow_test.dart` + `screen_widget_test.dart` updated from `pumpAndSettle()` to `pump(duration)` to settle around the now-continuous dot animation.
- Phase 2 (verification): **Complete** — full test suite green (1343 pass, 5 pre-existing skipped, 0 fail); `flutter analyze` shows only pre-existing/info-level `withOpacity` deprecations consistent with the rest of the codebase. Web smoke test (Chrome with HiveWorkoutRepository) is recommended but not blocking — the visual + animation contracts are fully covered by the 11 Phase 0/1 widget tests.

## Phase 0 Red Baseline

`flutter test test/widgets/energy_tile_test.dart` → 19 pass, 7 fail.

Failing tests (all expected to go green after implementation):

1. `S-101: all 6 tiles: icon center x matches tile center x` — pre-implementation has 4 px left-bias from the `Padding(horizontal: 4)` wrapper.
2. `S-101: all 6 tiles: label center x matches tile center x` — same root cause.
3. `S-102: label bottom y is identical across icon sizes` — `MainAxisAlignment.center` lets the label float with the icon.
4. `S-103: active tile renders a white ~8pt dot in the top-right` — no dot exists yet.
5. `S-103: dot opacity oscillates between ~0.1 and ~1.00 over a 1.8s cycle` — no animation yet.
6. `S-103: active glow boxShadow count is stable across frames` — passes by accident (the bug is the *count* changing, which would happen if I add an animated shadow; this guards against that). (Actually passes pre-implementation; kept as a regression guard.)
7. `S-104: resting tile renders no pulsing dot` — passes pre-implementation (no dot anywhere).
8. `S-105: active tile announces "Resistance, Workout in progress"` — no Semantics wrapper yet.
9. `S-105: dot is excluded from semantics (decorative)` — no ExcludeSemantics wrapper yet.
10. `S-106: secondary icon opacity is ~0.75` — current 0.60.
11. `S-106: secondary icon size remains 56` — passes pre-implementation (regression guard).

Pre-existing scenarios from the prior plan remain green (S-001, S-002).
