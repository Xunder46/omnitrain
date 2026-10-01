# Feature: Open Hub sheet by tapping the home-screen logo

## Overview
Make tapping the home-screen logo open the Hub sheet. The logo currently does nothing; wire it so a tap opens the Hub the same way the existing peek handle does.

## Requirements
- Tapping the logo opens the Hub sheet to its current size.
- The peek handle still works and is unchanged.
- The Hub sheet still closes by dragging down.

## Acceptance Criteria
- [x] Tapping the logo opens the Hub sheet to its current size.
- [x] The peek handle still works and is unchanged.
- [x] The Hub sheet still closes by dragging down.

## Scenarios

### S-001: Tap logo to open Hub sheet
- Trigger: User taps the OmniTrain logo in the AppBar on the Home screen.
- Precondition: Home screen is visible, Hub sheet is closed (at minimum extent).
- Flow: 
  1. User taps the logo.
  2. Logo tap handler is invoked.
  3. Hub sheet opens to maximum extent (0.9).
- Expected outcome: Hub sheet is fully open, same as when opened by dragging the peek handle.
- Edge case of: none

### S-002: Tap logo when Hub sheet is already open
- Trigger: User taps the OmniTrain logo in the AppBar on the Home screen.
- Precondition: Home screen is visible, Hub sheet is already open (at maximum extent).
- Flow: 
  1. User taps the logo.
  2. Logo tap handler is invoked.
  3. Hub sheet extent is set to maximum (no change).
- Expected outcome: Hub sheet remains open, no adverse effects.
- Edge case of: S-001

### S-003: Peek handle still works
- Trigger: User drags the peek handle on the Hub sheet.
- Precondition: Hub sheet is closed.
- Flow: 
  1. User drags peek handle upward.
  2. Hub sheet opens proportionally to drag.
- Expected outcome: Hub sheet opens as before, same behavior.
- Edge case of: none

## Implementation Plan

### Phase 1: Logic/UI (@developer)
1. [x] Add `_openHubSheet` method to `_HomeScreenState` that calls `_snapSheet(_maxSheetExtent)` to properly animate the sheet.
2. [x] Wrap the logo Image.asset in the AppBar with a GestureDetector that calls `_openHubSheet` on tap.
3. [x] Ensure no visual changes to the logo (use GestureDetector without feedback).
4. [x] Verify the peek handle functionality is unchanged (no modifications to `_buildMaintenanceSheet` or related sheet logic).
5. [x] Test on web with MockWorkoutRepository.

### Acceptance Criteria
- [x] Works on web with MockWorkoutRepository
- [x] No platform-specific code in shared files
- [x] Repository interface is environment-agnostic
- [x] Tapping the logo opens the Hub sheet
- [x] Peek handle still works and is unchanged
- [x] Hub sheet still closes by dragging down

### Files Affected
- lib/features/home/home_screen.dart

### Notes
- The Hub sheet is controlled by `_sheetController` and `_sheetExtent` in HomeScreen.
- Opening the sheet is achieved by setting the extent to `_maxSheetExtent` (0.9).
- This change only adds a new way to open the sheet; it does not alter the sheet's behavior or appearance.
- Must ensure the logo remains visually identical (no splash, no highlight).