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

- Single numeric input, with one shape exception for height (see below)
- No note input
- No date input
- Save captures timestamp at button press time
- **Height input shape** branches on the active height unit:
  - `cm` mode — single `Value (cm)` field; the entered value is stored
    verbatim as canonical cm.
  - `ftin` mode — side-by-side `Feet` and `Inches` fields. Inches are
    bounded to 0–11 as a per-field rule. The pair is converted to
    canonical cm via `UnitFormatter.toCanonicalHeightFeetInches` before
    the entry is persisted with `unitId='unit-cm'`.
  - The physical validation range is the same in either mode: 50–250 cm
    in cm mode, 20–98 total inches (1 ft 8 in – 8 ft 2 in) in ftin mode.
    The error message is stated in the active unit.

### History Sheet (Chart)

- Uses `fl_chart` line chart
- Loads and displays at most 10 entries
- Oldest to newest on X-axis
- Most recent point preselected
- Dot selection updates animated label strip
- "Log New Entry" opens log sheet on top of chart sheet (without dismissing chart), then reloads chart data
- **Height chart** y-axis plots in the active unit:
  - `cm` mode — canonical cm passthrough; selected-point label reads
    `180 cm`.
  - `ftin` mode — total whole inches; selected-point label reads in the
    natural compound form (e.g. `5 ft 11 in`). Stored heights are never
    rewritten when the unit toggle flips, so a pre-existing height
    displays correctly under either unit without migration.

---

## Avatar Platform Notes

- `image_picker` is integrated for avatar actions.
- Native/desktop: avatar path rendering uses `dart:io` implementation (`Image.file`).
- Web: stub implementation safely falls back to icon; no `dart:io` import path is used.
- Current contract is native-first (`avatarPath` local file path). Web persistence is intentionally not solved in this iteration.

---

## Avatar Persistence

Profile avatars and food photos uploaded via the OS photo picker are
stored in a managed directory inside the app's documents storage.
This ensures the images survive app restarts on iOS/Android.

### Storage Contract

- **Managed directory**: `<applicationDocumentsDirectory>/omni_images/`
- **Filename**: `<uuid-v4>.<ext>` where `<ext>` is preserved from the
  picked image (with fallback chain: name → path → `.jpg`)
- **Reference is a basename**: The string stored in
  `UserProfile.avatarPath` and `Food.imagePath` is the basename only
  (e.g. `e8b3…0123.jpg`) — not an absolute path. The reference is
  **location-independent**: it does not encode the documents
  directory's current location and therefore survives the OS
  relocating the app's data during an update or a reinstall.
- **Path is opaque**: The repository stores the path string but never
  reads or writes the image file directly.

### Resolve + Re-link on Load

When loading a profile or food, the state calls
`ImageStorageService.resolveOrRelink(storedReference)`. The service
searches the **current** managed directory first (the common
post-relocation case where the data moved with the directory), then
the literal reference path (legacy absolute paths whose file is
still on disk), then bounded candidate directories (the picker's
temp cache and the application support directory). If a matching
file is reachable anywhere, the service re-links it into the
current managed directory (a one-time copy) and returns the
basename. The state persists the normalized basename back to the
record so subsequent loads hit the fast path.

The reference is **cleared to `null` only when the file is truly,
verifiably absent** from every candidate location — this prevents
the launch-blocker regression where a photo whose file is still on
the device becomes unrecoverable. Pre-fix records whose stored
reference was an absolute path are migrated to the basename on
first load after the fix.

### Delete on Replace/Remove

When the avatar or food photo is replaced or removed:
1. The state captures the previous basename from the loaded record
2. The new value is persisted first
3. The `ImageStorageService.deleteIfManaged(previousBasename)` is
   called to delete the previous managed file. For a basename
   input, the service deletes `<managedDir>/<basename>`
   unconditionally (basenames are by convention managed). For an
   absolute-path input (legacy migration only), the service
   applies the `isManaged` gate so non-managed paths are never
   deleted.

### Web Behavior

On web, the `kIsWeb` early-return in the picker handlers shows a
snackbar: "Photo selection works on web, but avatar/food photo
persistence is not supported there yet." The service is not called.

### Implementation Files

- `lib/core/services/image_storage_service.dart` (conditional export)
- `lib/core/services/image_storage_service_io.dart` (native implementation)
- `lib/core/services/image_storage_service_stub.dart` (web stub)

See also: `docs/db_integration.md` — "Image Storage (managed directory)"

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
