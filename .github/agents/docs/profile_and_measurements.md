# Profile & Measurements

## Overview

The Profile feature is now an implemented maintenance route, not a placeholder.

Primary capabilities:
- Local single-user profile (`local-user`) with display name and avatar path
- Primary measurements: bodyweight, height
- Additional measurements: body fat %, lean mass, waist, chest, hips, thigh, arm
- Measurement logging with save-time timestamps
- Chart-based measurement history (last 10 entries)

---

## Entry Points

- `HomeScreen` maintenance sheet:
  - Profile tile pushes `ProfileScreen`
  - Stats/Settings still route to placeholder
- `ProfileScreen` depends on `ProfileState` via constructor injection

---

## Core Files

- `lib/features/profile/profile_screen.dart`
- `lib/features/profile/widgets/measurement_history_chart_sheet.dart`
- `lib/features/profile/widgets/profile_avatar_image_io.dart`
- `lib/features/profile/widgets/profile_avatar_image_stub.dart`
- `lib/state/profile/profile_state.dart`
- `lib/core/constants/profile_measurements.dart`

---

## Data Contract

### Models

- `UserProfile`
- `BodyMeasurementEntry`

Defined in `lib/data/models/models.dart`.

### Repository Surface

`WorkoutRepository` includes profile/measurement APIs:
- `getProfile()`
- `saveProfile(...)`
- `getMeasurementHistory(type)`
- `getLatestMeasurement(type)`
- `saveMeasurementEntry(...)`
- `deleteMeasurementEntry(entryId)`

Both `HiveWorkoutRepository` and `MockWorkoutRepository` implement these methods.

---

## ProfileState Behavior

`ProfileState` is the single state owner for profile flows.

Key behavior:
- `loadProfile()` loads from repository, or creates/saves default `UserProfile(id: 'local-user')`
- `updateDisplayName()` and `updateAvatarPath()` persist immutable profile updates
- `logMeasurement()` writes `BodyMeasurementEntry` with UUID and defaults `recordedAtMs` to save time when omitted
- `deleteMeasurementEntry()` updates latest measurement cache immediately after delete

---

## UI Behavior

### Identity Section

- Uses `OmniGradientBackground` + `OmniSurface`
- Avatar tap opens bottom sheet actions: Take Photo, Choose from Gallery, Remove Photo
- Remove action is disabled when no avatar path exists
- Display name is editable via dialog

### Measurement Sections

- Primary section label: `MEASUREMENTS`
- Additional measurements render directly below primary (no toggle and no extra section label)
- Each row has:
  - measurement label
  - current value or em dash
  - outlined add button
- Row tap opens chart history sheet
- Add button opens log sheet

### Logging Sheet

- Single numeric input
- No note input
- No date input
- Save captures timestamp at button press time

### History Sheet (Chart)

- Uses `fl_chart` line chart
- Loads and displays at most 10 entries
- Oldest to newest on X-axis
- Most recent point preselected
- Dot selection updates animated label strip
- "Log New Entry" opens log sheet on top of chart sheet (without dismissing chart), then reloads chart data

---

## Avatar Platform Notes

- `image_picker` is integrated for avatar actions.
- Native/desktop: avatar path rendering uses `dart:io` implementation (`Image.file`).
- Web: stub implementation safely falls back to icon; no `dart:io` import path is used.
- Current contract is native-first (`avatarPath` local file path). Persisted web avatar replay is intentionally not solved in this iteration.

Recommended follow-up for robust web persistence:
- repository-backed web-safe representation (bytes, object URL, or base64/blob strategy)

---

## Dependency And Platform Notes

- `pubspec.yaml` includes `image_picker`.
- iOS privacy keys were added in `ios/Runner/Info.plist` for camera and photo library access.
- Platform plugin registrants were updated by Flutter tooling.

---

## Testing Coverage

- `test/profile_data_layer_test.dart`
- `test/profile_state_test.dart`
- `test/profile_navigation_test.dart`
- `test/profile_screen_test.dart`

These cover repository sorting/latest behavior, state bootstrapping and mutations, navigation wiring, and UI constraints (no note/date fields).

---

**Document Version**: 1.0
**Last Updated**: March 15, 2026
