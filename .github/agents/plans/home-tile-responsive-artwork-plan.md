# Feature: Height-Responsive Home Tile Artwork

## Overview

Classification: **TRIVIAL / UI-only fast-track.** The home grid already compresses tile height to preserve the non-scrolling screen contract, but `EnergyTile` uses fixed artwork dimensions and fixed internal spacing. This change makes decorative artwork consume only its height-derived region, omits it when the rendered tile is too short, and preserves labels and active-session status at every supported viewport.

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

## Acceptance Criteria

- [ ] At 360 × 640 and normal text scale, artwork and labels never intersect across all six tiles.
- [ ] At 360 × 640 and maximum honoured text scale, artwork and labels never intersect across all six tiles.
- [ ] Artwork never exceeds its allotted region.
- [ ] Artwork size changes monotonically with rendered tile height.
- [ ] Below the height threshold, artwork is absent and the label is vertically centred.
- [ ] Labels retain their configured text size at every supported viewport.
- [ ] Width-only changes do not affect artwork visibility.
- [ ] Active-session status intersects neither artwork nor label at 360 × 640.
- [ ] No tile overflow occurs across the supported viewport sweep.
- [ ] Design-system documentation records the omission invariant.

## Scenarios

### S-001: Supported minimum viewport
- Trigger: Render the home screen at 360 × 640.
- Precondition: Normal or maximum honoured system font scale.
- Flow: Render all six tiles and inspect artwork and label bounds.
- Expected outcome: Every label remains present at configured size; artwork and labels do not intersect; no overflow occurs.
- Edge case of: none

### S-002: Height-responsive artwork
- Trigger: Render equivalent tiles across increasing heights.
- Precondition: Tile width and appearance remain fixed.
- Flow: Capture artwork bounds at each height.
- Expected outcome: Artwork height is monotonic with tile height and never exceeds its allotted region.
- Edge case of: S-001

### S-003: Artwork omission
- Trigger: Render a tile below the omission threshold.
- Precondition: Tile width remains otherwise sufficient.
- Flow: Inspect the render tree and label alignment.
- Expected outcome: Artwork is absent and the unchanged label is vertically centred.
- Edge case of: S-002

### S-004: Height-only visibility rule
- Trigger: Change tile width while holding tile height fixed.
- Precondition: Compare primary and secondary appearances.
- Flow: Inspect artwork presence at each width.
- Expected outcome: Visibility is unchanged because rendered height alone controls omission.
- Edge case of: S-003

### S-005: Active-session status separation
- Trigger: Render an active tile at 360 × 640.
- Precondition: Status indicator is present.
- Flow: Compare indicator bounds with artwork and label bounds.
- Expected outcome: Status remains visible and intersects neither content region.
- Edge case of: S-001

### S-006: Supported viewport sweep
- Trigger: Render tiles across representative viewports from the supported minimum to maximum.
- Precondition: Include normal and maximum honoured font scales.
- Flow: Pump each viewport and collect framework layout exceptions.
- Expected outcome: No tile layout overflow is reported.
- Edge case of: S-001

## Iteration 1

### DB Changes

None.

### Backend Changes

None.

### Frontend Changes

- Refactor `EnergyTile` around height-derived content regions and proportional spacing.
- Add stable keys for artwork, label, status, and allotted artwork region so geometry contracts are testable.
- Add minimum-viewport, font-scale, monotonic-size, width-independence, omission, active-status, and overflow tests.
- Update the design-system tile invariant and point to the regression tests.

### Implementation Steps

1. Add scenario-driven widget tests and confirm the pre-fix red baseline.
2. Implement height-responsive artwork layout for primary and secondary tiles.
3. Update the design-system invariant with a test pointer.
4. Run formatting, focused tests, full tests, analysis, and review.

## Progress

- [x] Phase 0: classify and author plan
- [x] Phase 1: confirm no data-layer changes
- [x] Phase 2: record red tests
- [x] Phase 2: implement adaptive tile layout
- [x] Phase 2: update design-system invariant
- [x] Phase 2: pass full tests and analysis
- [x] Phase 3: verify acceptance criteria and scenarios
- [x] Phase 3: complete documentation falsification review

### Phase 1 Complete ✓

No models, repositories, seed data, or schema are involved.

### Phase 2 Implementation Complete ✓

`EnergyTile` now derives the artwork region, internal padding, and content gap from the tile's actual height. Artwork is omitted when the available height cannot fit the configured label plus a 64dp artwork region; the label keeps its full text size and is vertically centred. Stable keys (`energy_tile_label_<title>`, `energy_tile_artwork_<title>`, `energy_tile_artwork_region_<title>`, `energy_tile_status_<title>`) make geometry contracts testable. `flutter test` → 2094 pass / 1 skip / 0 fail; `flutter analyze` → 220 pre-existing `withOpacity` infos, no new errors.

### Phase 3 Review Complete ✓

All acceptance criteria and scenarios verified by the height-responsive artwork regression group; no documentation falsification or prohibited additions detected. Full review delivered in the chat reply.

