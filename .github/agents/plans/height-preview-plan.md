# Height Preview in Settings - Plan

## Overview
Add a live height preview to the settings screen's units preview line, displayed alongside the existing weight and distance previews. The height value will be passed from the profile state and will update live when the user changes height units.

## Requirements
- Display user's height in the settings units preview line
- Height shown in the currently active unit (cm or ft/in)
- Live update when user changes height unit
- Show placeholder if height is not set

## Acceptance Criteria
- [ ] Settings units line displays height next to weight/distance indicators
- [ ] Height is shown in the active unit (cm or ft/in)
- [ ] Changing the active unit updates the displayed height live

## Scenarios

### S-001: Height preview displays when height is set
- Trigger: User opens settings screen with height recorded in profile
- Precondition: User has height value in their profile
- Flow: Settings screen loads → height preview shows user's height in preferred unit
- Expected outcome: Height displays (e.g., "180 cm" or "5' 11\"") next to weight/distance

### S-002: Height preview shows placeholder when height not set
- Trigger: User opens settings screen without height recorded
- Precondition: No height value in profile
- Expected outcome: Height shows "—" placeholder

### S-003: Height preview updates live when unit changes
- Trigger: User toggles height unit between cm and ft/in
- Precondition: Height is set
- Expected outcome: Preview updates immediately (e.g., "180 cm" → "5' 11\"")

## Iteration 1

### Frontend Changes
1. Modify `SettingsScreen` constructor to accept optional `double? userHeightCm` parameter
2. Add height preview `_PreviewValue` to the preview row in `_MeasurementsSection`
3. Update `hub_sheet.dart` to pass user's height from `profileState.latestMeasurements['height']?.value`

### Implementation Steps
1. Add `userHeightCm` parameter to `SettingsScreen` constructor
2. Add third `_PreviewValue` widget for height in preview row
3. Use `UnitFormatter.formatHeight()` with the height value
4. Handle null height (show "—")
5. Update hub_sheet.dart to pass height value
6. Update tests

## Progress
- [x] Create plan file
- [x] Add userHeightCm parameter to SettingsScreen
- [x] Add height preview to preview row
- [x] Update hub_sheet.dart to pass height
- [x] Write/update widget tests
- [x] Code review

## Feedback

### Phase 0 Complete ✓
### Phase 1 Complete ✓ (no data layer changes needed)
### Phase 2 Complete ✓
### Phase 3 Complete ✓
