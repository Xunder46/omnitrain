# Feature: Home Main Tile Shadow Parity

## Overview
Align the main home menu tile shadow with the HUB menu tile shadow for visual consistency, while preserving the active session tile shadow treatment.

## Requirements
- Inactive main home menu tiles must use the same shadow as HUB tiles.
- Active session tile shadow must remain unchanged.
- No behavior or navigation changes.

## Acceptance Criteria
- [x] Inactive home menu tiles render with HUB-equivalent shadow.
- [x] Active session tile shadow remains unchanged.
- [x] No regressions in tile tap/press behavior.

## Scenarios
N/A — visual parity adjustment only.

## Progress
- [x] Located HUB and main menu tile shadow definitions
- [x] Updated inactive main menu tile shadow to HUB shadow
- [x] Preserved active session tile shadow behavior
- [x] Follow-up: adjusted inactive main menu shadow colors to match each tile palette

### Phase 2 Complete ✓
Implementation done. All Phase 0 tests green. Ready for Code Reviewer.
