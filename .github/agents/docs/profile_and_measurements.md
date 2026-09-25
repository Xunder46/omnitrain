# Profile & Measurements

## Overview

The Profile feature is now an implemented maintenance route, not a placeholder.

Primary capabilities:
- Local single-user profile (`local-user`) with display name and avatar path
- Identity-area editable height (compact value rendered under the display name, edited via a single tap; not charted)
- Charted measurements: body weight, body fat %, waist, lean mass (read-only, computed), hips, thigh, chest, arm
- Lean mass is computed from latest body weight × (1 − body fat %/100); the manual log path is removed but historical entries are preserved
- Measurement logging with save-time timestamps
- Chart-based measurement history (full history, scrollable)

---

## Entry Points

- `HomeScreen` maintenance sheet:
  - Profile tile pushes `ProfileScreen`
  - Stats tile pushes `StatsScreen` (all-time aggregates, scrollable strength + cardio trends, Recent PRs, NUTRITION card — see [Stats Screen](stats_screen.md))
  - Settings tile pushes `SettingsScreen` (preferences, sounds & alerts, Effort Rating toggle, theme grid, version footer — see [Theme & Settings](theme_and_settings.md))
- `ProfileScreen` depends on `ProfileState` via constructor injection

---

## Core Files

- `lib/features/profile/profile_screen.dart`
- `lib/features/profile/widgets/measurement_history_chart_sheet.dart`
- `lib/features/profile/widgets/profile_avatar_image_io.dart`
- `lib/features/profile/widgets/profile_avatar_image_stub.dart`
- `lib/features/profile/widgets/avatar_crop_sheet.dart`
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
- `updateHeight(double cmCanonical)` writes a `BodyMeasurementEntry(type='height', unitId='unit-cm')` through the same `logMeasurement` path the chart card used to use. The Settings height preview keeps working unchanged because it reads the same `type='height'` entries.
- `logMeasurement()` writes `BodyMeasurementEntry` with UUID and defaults `recordedAtMs` to save time when omitted
- `deleteMeasurementEntry()` updates latest measurement cache immediately after delete

Convenience getters (all are pure derivations of `_latestMeasurements` — no extra state):
- `latestHeightCm` → `double?` (canonical cm)
- `latestBodyWeightKg` → `double?` (canonical kg)
- `latestBodyFatPct` → `double?`
- `computedLeanMassKg` → `double?` derived as `latestBodyWeightKg × (1 - latestBodyFatPct / 100)`; `null` when either input is missing. Lean mass is no longer a stored value.

---

## UI Behavior

### Identity Section

A compact horizontal header — avatar on the left, name and height stacked beside it — sitting
directly on the gradient with no card chrome, so it collapses to roughly the avatar's height and
leaves the space below for the measurement cards. Name and height are each their own tap target,
opening their respective editors.

### Measurement Sections

- Rows for a measurement type can arrive from two sources: the in-app log sheet, and the platform
  health store when the user enables `Read body weight`. An imported row is an ordinary
  `BodyMeasurementEntry` in canonical kilograms, distinguished by a deterministic id derived from
  the platform sample — so re-reading the same sample upserts rather than duplicating. Nothing
  downstream may assume a user typed the value.
- Single charted column sourced from `ProfileMeasurements.additional`, top-to-bottom:
  Body Weight, Body Fat %, Waist, Lean Mass, Hips, Thigh, Chest, Arm
- Each row has:
  - measurement label (uppercased via `OmniCardHeader`)
  - current value or em dash (key `measurement_value`)
  - outlined add button (except Lean Mass — see below)
- Row tap (chart area) opens chart history sheet
- Add button opens log sheet
- **Lean Mass** is a read-only computed row with no manual entry path. Its value derives from
  `ProfileState.computedLeanMassKg` (body weight × (1 − body fat %)), and reads as an em dash when
  either input is missing rather than showing a misleading number.
  - Pre-existing `lean_mass` `BodyMeasurementEntry` rows are preserved in the repository but are not used as the display source

### Logging Sheet

- Single numeric input (used by all charted measurements except Lean Mass — see the computed-row contract above; the charted measurements retain their manual log path)
- No note input
- No date input
- Save captures timestamp at button press time
- **Height input shape** lives in the identity-area editor dialog (no longer a bottom sheet). It branches on the active height unit:
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

- Renders inside the shared `ScrollableTrendChart` wrapper (pinned
  y-axis column on the left, horizontally scrollable plot on the
  right — same primitive used by the stats screen).
- Loads the **full** history (no `take(10)` cap). The chart shows
  the 8 most recent days by default and older days are reachable
  by horizontal scroll.
- Opens scrolled to the most recent entry (the `ScrollController`
  jumps to `maxScrollExtent` on first layout). Data is never
  reversed; the scroll position is what brings the latest day
  into view.
- Y-axis label column is pinned (does not scroll with the plot)
  and renders whole numbers via `ChartAxisHelper.computeBounds`
  (no unit suffix — the value is already in the strip below).
- Tapping the chart is a no-op (no fl_chart tooltip popup). The
  only remaining touch affordance is **long-press to delete**,
  served by a single chart-area `GestureDetector`; the dialog
  targets the most recent entry (the strip is locked to it, so
  the user can never lose track of what they're about to delete).
- Below-chart value strip shows the most recent entry by
  default. There is no tap-to-select affordance — the strip
  stays anchored to the newest day for the lifetime of the
  sheet so the user always knows which entry long-press will
  remove.
- Hint text: `Long-press to delete`.
- "Log New Entry" opens log sheet on top of chart sheet (without
  dismissing chart), then reloads chart data.
- **Height chart** y-axis plots in the active unit:
  - `cm` mode — canonical cm passthrough; strip label reads
    `180 cm`.
  - `ftin` mode — total whole inches; strip label reads in the
    natural compound form (e.g. `5 ft 11 in`). Stored heights
    are never rewritten when the unit toggle flips, so a
    pre-existing height displays correctly under either unit
    without migration.

---

## Avatar Crop Step

After the user picks a photo from the camera or gallery, a square
crop step with a circular preview overlay appears before the
avatar is saved. The crop step exists because the avatar displays
as a circle (`ClipOval`) and an off-center subject in the raw pick
gets clipped badly — the user has no control over framing without
this step.

**Where it sits in the flow.** `ProfileScreen._pickAvatar` calls
`ImagePicker.pickImage(source: ...)`. On native, the picked bytes
are routed through `AvatarCropSheet` (full-screen dialog, pushed
via `OmniNavigator.push(..., fullscreenDialog: true)`); the
sheet's confirm writes the cropped region via
`ImageStorageService.persistImageBytes` and then
`ProfileState.updateAvatarPath(basename)`. On web the existing
`kIsWeb` early-return shows the existing snackbar; the crop step
is not reached (web persistence is intentionally out of scope).

The `OmniNavigator.push` route is mandatory — see the navigation
contract in `docs/navigation_and_screens.md`. `OmniRoute` wraps
the destination in `OmniGradientBackground` and exposes
`opaque => true`, which is what prevents the underlying screen
from bleeding through during the slide-up transition. A raw
`MaterialPageRoute` does not have either property, and the avatar
crop step's `Scaffold` is transparent — using `MaterialPageRoute`
causes the ProfileScreen below to be visible mid-transition.

**Crop UI.** The viewport is square with a circular dim scrim showing what the avatar will look
like once clipped, and the user can pinch-zoom and drag to reposition within it.

**Output shape.** The stored avatar is a **square** image; the circular scrim is a preview aid
only. Keeping the persisted file square means the existing `ClipOval` display still applies at
render time and avoids introducing a transparent-margin avatar format nothing else in the app
renders.

**Cancel** pops with `null`; the picker temp file lives outside
the managed dir and is never copied in. The existing avatar
is untouched.

**No new dependencies.** The crop step is built from
`InteractiveViewer`, `RepaintBoundary`, and `Image.memory` —
all in Flutter's core widget set. No plugin channel, no platform
code.

**Persistence integration.** The cropped PNG bytes are
persisted via `ImageStorageService.persistImageBytes(bytes,
extension: '.png')` which writes them to
`<managedDir>/<uuid-v4>.png` and returns the basename. The
existing `ProfileState.updateAvatarPath(basename)` then takes over
the rest of the flow (delete previous file via D-7, save new
profile row, notify listeners).

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


---

> **Doc freshness** — Last reconciled against source: 2026-06-29. This doc is derived from source, not hand-maintained. Source of truth: the `lib/` tree as it exists on the reconciliation date. If you find a claim here that disagrees with `lib/`, `lib/` wins — please flag the drift in a fresh chat with the Coordinator agent.
