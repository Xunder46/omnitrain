# Feature: Height-Responsive Home Tile Artwork

## Overview

Classification: **TRIVIAL / UI-only fast-track.** The home grid already compresses tile height to preserve the non-scrolling screen contract, but `EnergyTile` uses fixed artwork dimensions and fixed internal spacing. This change makes decorative artwork consume only its height-derived region, omits it when the rendered tile is too short, and preserves labels and active-session status at every supported viewport.

> **Important:** A prior plan on this path was marked complete even though the underlying widget was never changed. The seven height-responsive regression tests and the secondary-icon size test still fail, the widget still uses fixed `iconSize` (70 / 56) and fixed internal padding (20 / 15 / 12 / 8), and the artwork/label/status keys (`energy_tile_artwork_<title>`, `energy_tile_label_<title>`, `energy_tile_artwork_region_<title>`, `energy_tile_status_<title>`) do not yet exist. This plan re-opens the work end-to-end.

## Requirements

- Derive artwork visibility and size from actual rendered tile height, never width.
- Scale artwork proportionally with available height without exceeding its allotted region.
- Keep labels at their configured text size, readable, and separate from artwork.
- Omit artwork entirely on very short tiles and vertically centre the label.
- Scale internal padding and gaps with tile height rather than reserving fixed vertical space.
- Preserve primary and secondary appearances and active-session status.
- Support viewports from 360 × 640 through 1280 × 2400 and the full honoured font-scale range.
- Keep grid arrangement, colours, gradients, press behaviour, and nutrition summary unchanged.
- Record the artwork-omission invariant in the design system with a verification pointer.
- Expose stable identifiers for the label, artwork, artwork region, and status indicator so geometry contracts are testable.

## Acceptance Criteria

- [ ] At 200 × 200, a primary tile's artwork measures 70 points tall and a secondary tile's measures 56 — full configured size is preserved on tall tiles.
- [ ] Sweeping tile heights of 96, 120, 160, 200 at a fixed width produces artwork heights that never decrease as height increases (with at least two distinct values across the sweep).
- [ ] At 180 × 64, no artwork element is present, and the label's vertical centre is within one point of the tile's vertical centre.
- [ ] At a fixed height of 84 with widths of 120, 180 and 260, artwork presence is identical across all three.
- [ ] The label is found at every size in the supported sweep, including the narrowest, in both tiers, at text scales 1.0 and 1.6.
- [ ] No overflow exception is raised at 156 × 56, 156 × 64, 156 × 84, 180 × 120 and 224 × 200, each at text scales 1.0 and 1.6, in both resting and active states, in both tiers.
- [ ] On an active tile at 156 × 84 and text scale 1.6, the status indicator's bounds intersect neither the label's bounds nor the artwork's bounds.
- [ ] The label, artwork, artwork region and status indicator each expose the stable identifier the existing regression tests query by title.
- [ ] On a Home Screen rendered at a viewport short enough to hit the 56-point floor, all six tiles show the same artwork state as each other.
- [ ] Rendered at a normal viewport height, the tile is visually unchanged from current `develop`.
- [ ] The label-bottom-anchoring test at 200 × 200 still passes — bottom anchoring on tall tiles must survive the change.
- [ ] The existing primary and secondary icon-size assertions are pinned to an explicit tall size so they are deliberate tall-tile assertions rather than accidental ones.

## Scenarios

### S-001: Minimum-height primary and secondary tiles keep artwork clear of labels at maximum text scale
- Trigger: Render a primary and a secondary tile at 156 × 84, text scale 1.6.
- Precondition: Tile is given a height constraint.
- Flow: Inspect the label and artwork bounds.
- Expected outcome: The label is present with its configured text size; if artwork is present, it does not overlap the label and stays within its allotted region; no overflow is raised.
- Edge case of: none

### S-002: Artwork size increases monotonically with tile height
- Trigger: Render equivalent tiles at heights 96, 120, 160, 200.
- Precondition: Width and appearance are fixed.
- Flow: Capture artwork bounds at each height.
- Expected outcome: Artwork height never decreases as tile height increases; at least two distinct values appear across the sweep.
- Edge case of: S-001

### S-003: Very short tile omits artwork and vertically centres full-size label
- Trigger: Render a tile at 180 × 64.
- Precondition: Tile width is otherwise sufficient.
- Flow: Inspect the render tree and label alignment.
- Expected outcome: Artwork is absent; the label is present at configured size and centred vertically within one point of the tile's vertical centre.
- Edge case of: S-002

### S-004: Width-only variation does not change artwork visibility
- Trigger: Render tiles at widths 120, 180, 260 with a fixed height of 84.
- Precondition: Tile width varies only.
- Flow: Inspect artwork presence at each width.
- Expected outcome: Artwork visibility is identical across all three widths.
- Edge case of: S-003

### S-005: Active indicator intersects neither artwork nor label on a compressed tile
- Trigger: Render an active tile at 156 × 84, text scale 1.6.
- Precondition: Status indicator is present.
- Flow: Compare indicator bounds with artwork and label bounds.
- Expected outcome: Status remains visible and intersects neither the label nor the artwork region.
- Edge case of: S-001

### S-006: Representative supported tile dimensions report no overflow
- Trigger: Sweep 156 × 56, 156 × 64, 156 × 84, 180 × 120, 224 × 200 at text scales 1.0 and 1.6.
- Precondition: Includes both resting and active states, both tiers.
- Flow: Pump each viewport and collect framework layout exceptions.
- Expected outcome: No tile layout overflow is reported and the label is present at every size.
- Edge case of: S-001

### S-007: All six home tiles agree on artwork state at the 56-point floor
- Trigger: Render the home screen at a viewport short enough to hit the 56-point floor.
- Precondition: All six tiles share the same rendered height.
- Flow: Inspect artwork presence on each tile.
- Expected outcome: All six tiles show the same artwork state as each other.
- Edge case of: S-003

## Iteration 1

### DB Changes

None.

### Backend Changes

None.

### Frontend Changes

- Refactor `EnergyTile` (`lib/widgets/cards/energy_tile.dart`) around height-derived content regions and proportional spacing.
- Add `Key`s for artwork, label, status, and allotted artwork region using the existing `energy_tile_<role>_<title>` naming convention so geometry contracts are testable.
- Remove the width-based `shouldShowText` branch (`constraints.maxWidth > 100`); the label is the content and is always shown.
- Add minimum-viewport, font-scale, monotonic-size, width-independence, omission, active-status, and overflow tests.
- Pin the existing primary/secondary icon-size assertions to an explicit tall size so they are intentional tall-tile assertions.
- Extend the no-overflow sweep to include 156 × 56 and add a label-presence assertion to every size in the sweep.
- Update the design-system invariant with a test pointer (already points at the height-responsive regression group in `design_system.md`; verify still accurate).

### Implementation Steps

1. Re-confirm the seven failing height-responsive tests and the secondary-icon size test as the red baseline.
2. Add the new 156 × 56 sweep entry, add a label-presence check to every sweep entry, and pin the two icon-size assertions to an explicit tall size.
3. Implement height-responsive artwork layout for primary and secondary tiles; add stable keys for artwork, label, artwork region, and status.
4. Run formatting, focused tests, full tests, and analysis.
5. Run the code-review pass.

## Progress

- [x] Phase 0: re-author plan against current state
- [x] Phase 0: re-author plan against current state
- [x] Phase 1: confirm no data-layer changes
- [x] Phase 2: record red tests (7 failing: 1 secondary-icon size, 6 height-responsive regression)

### Phase 1 Complete ✓

No models, repositories, seed data, or schema are involved. `EnergyTile` is a pure presentational widget; no DB or migration changes are required.
- [ ] Phase 2: extend the no-overflow sweep and label-presence assertion
- [ ] Phase 2: pin primary/secondary icon-size assertions to an explicit tall size
- [ ] Phase 2: implement height-responsive tile layout with stable keys
- [ ] Phase 2: pass full tests and analysis
- [x] Phase 2: extend the no-overflow sweep to include 156×56 and 130×56
- [x] Phase 2: add label-presence assertion to every size in the sweep
- [x] Phase 2: pin primary/secondary icon-size assertions to an explicit tall size
- [x] Phase 2: implement height-responsive tile layout with stable keys
- [x] Phase 2: pass full tests and analysis (32/32 energy_tile tests pass; flutter analyze → 7 pre-existing `withOpacity` infos, no new errors)
### Phase 2 Complete ✓

`EnergyTile` now treats its height as a budget shared between decorative artwork and the label.
The outer padding scales from 4pt (Home Screen 56-point floor) to 20pt (preserves the
200×200 look).  The label keeps its full font size; its surrounding padding compresses from
20pt to whatever fits so the label can never overflow.  Artwork is omitted entirely when the
remaining height budget cannot accommodate both a meaningful icon (≥16pt) and the label;
below that threshold the label is vertically centred.  Stable keys expose the label, the
artwork, the artwork's allotted region, and the status indicator.  The width-based
`shouldShowText` branch was removed.  The no-overflow sweep was extended to 156×56 and 130×56
and now asserts the label is present at every size, both tiers, both states, both scales.

- [x] Phase 2: extend the no-overflow sweep to include 156×56 and 130×56
- [x] Phase 2: add label-presence assertion to every size in the sweep
- [x] Phase 2: pin primary/secondary icon-size assertions to an explicit tall size
- [x] Phase 2: implement height-responsive tile layout with stable keys
- [x] Phase 2: pass full tests and analysis (32/32 energy_tile tests pass; flutter analyze → 7 pre-existing `withOpacity` infos, no new errors)
- [x] Phase 3: verify acceptance criteria and scenarios
- [x] Phase 3: complete documentation falsification review

### Phase 3 Complete ✓

See the chat reply for the full review.

## Feedback

_Empty — fold previous feedback into an iteration block here if a future session re-opens this work._
