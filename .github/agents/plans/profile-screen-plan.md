# Feature: profile-screen

## Overview
Build the Profile feature for OmniTrain end-to-end: add profile and body-measurement domain models, extend the repository surface, introduce ProfileState, create the ProfileScreen UI, and replace the System-sheet Profile placeholder route with the real screen. The feature must follow the existing constructor-injection architecture, use the current Hive-backed runtime storage, and remain compile-safe for MockWorkoutRepository and disabled-but-compiled screens like OmniSplashScreen.

## Requirements
- Add `UserProfile` and `BodyMeasurementEntry` models to `lib/data/models/models.dart` using existing model conventions: pure Dart, immutable fields, `fromMap()`, `toMap()`.
- Support measurement types in two UI tiers:
  - Primary: `bodyweight`, `height`
  - Additional: `body_fat_pct`, `lean_mass`, `waist_cm`, `chest_cm`, `hips_cm`, `thigh_cm`, `arm_cm`
- Hardcode measurement logging to metric units for now:
  - `bodyweight`, `lean_mass` → `unit-kg`
  - `height`, circumference metrics → `unit-cm`
  - `body_fat_pct` → `unit-pct`
- Extend `WorkoutRepository` with profile and measurement-history methods.
- Implement repository support in Hive with boxes:
  - `user_profile`
  - `body_measurements`
- Ensure all `WorkoutRepository` implementations remain compilable after interface expansion.
- Add `ProfileState` as a `ChangeNotifier` depending only on `WorkoutRepository`.
- Wire `ProfileState` through `main.dart` → `MyApp` → `HomeScreen` → maintenance sheet → `ProfileScreen`.
- Replace the System-sheet Profile tile route from `MaintenancePlaceholderScreen` to `ProfileScreen`.
- Build `ProfileScreen` using `OmniGradientBackground` and `OmniSurface`, with identity, primary measurements, additional measurements, and measurement-history flows.
- Use `image_picker` for avatar actions if available; add it if missing.
- All buttons must explicitly set shape using `OmniTheme.buttonBorderRadius` or the appropriate OmniTheme button radius token.
- Minimum touch target for interactive rows/buttons/avatar affordances: 48 dp.
- Avatar loading must be defensive: invalid/missing path falls back to icon.

## Iteration 1

### DB Changes (@dba)
1. [ ] Add `UserProfile` model to `lib/data/models/models.dart` with fields:
   - `id`
   - `displayName`
   - `avatarPath`
   - `createdAtMs`
2. [ ] Add `BodyMeasurementEntry` model to `lib/data/models/models.dart` with fields:
   - `id`
   - `measurementType`
   - `value`
   - `unitId`
   - `recordedAtMs`
   - `note`
3. [ ] Extend `WorkoutRepository` in `lib/data/repositories/workout_repository.dart` with:
   - `getProfile()`
   - `saveProfile(UserProfile profile)`
   - `getMeasurementHistory(String measurementType)`
   - `getLatestMeasurement(String measurementType)`
   - `saveMeasurementEntry(BodyMeasurementEntry entry)`
   - `deleteMeasurementEntry(String entryId)`
4. [ ] Add in-memory implementations for the new repository methods in `lib/data/repositories/mock_workout_repository.dart` so the interface expansion does not break tests or alternate environments.
5. [ ] Add Hive storage support in `lib/data/repositories/hive_workout_repository.dart`:
   - open `user_profile` box during `initialize()`
   - open `body_measurements` box during `initialize()`
   - persist `UserProfile` keyed by profile id
   - persist `BodyMeasurementEntry` keyed by entry id
   - implement per-type filtering and `recordedAtMs` descending sort
6. [ ] Seed or define missing unit IDs required by the feature:
   - verify `unit-kg` already exists
   - add `unit-cm`
   - add `unit-pct`
   - optionally add future-proof imperial IDs later, but do not block this feature on them
7. [ ] Keep current runtime storage environment-agnostic:
   - Hive remains the active implementation in `main.dart`
   - no Flutter imports in models or repository abstractions
   - document any future SQLite parity work separately rather than coupling it to this feature

### Backend Changes (@developer)
1. [ ] Create `lib/state/profile/profile_state.dart` as a `ChangeNotifier` that depends only on `WorkoutRepository`.
2. [ ] Add state fields:
   - `UserProfile? profile`
   - `bool isLoading`
   - `Map<String, BodyMeasurementEntry?> latestMeasurements`
3. [ ] Implement `loadProfile()` to:
   - load an existing profile or create an in-memory default `UserProfile(id: 'local-user', ...)` before persisting if no profile exists
   - fetch latest entries for the primary measurement types on initial load
   - notify listeners around loading/error transitions
4. [ ] Implement `updateDisplayName(String name)` and `updateAvatarPath(String? path)` as profile-updating helpers that preserve immutable model usage.
5. [ ] Implement `logMeasurement(String type, double value, String unitId, {String? note})` to:
   - create a `BodyMeasurementEntry` with UUID id
   - support an explicit recorded date argument if needed by UI; if the requested signature remains unchanged, ensure the UI can still pass the chosen day through a minimal extension without forcing an awkward workaround
   - persist the entry and update `latestMeasurements[type]`
6. [ ] Implement `getMeasurementHistory(String type)` as a repository passthrough.
7. [ ] Add `deleteMeasurementEntry(String entryId, String type)` or equivalent state helper if needed so swipe-to-delete can update local state immediately after repository deletion.
8. [ ] Reuse the repo’s existing UUID pattern (`package:uuid/uuid.dart`) and keep measurement type strings centralized in one feature-local constant/config structure to avoid duplication across state and UI.
9. [ ] Wire `ProfileState` into constructor injection:
   - `lib/main.dart`
   - `lib/app.dart`
   - `lib/features/home/home_screen.dart`
   - `lib/features/splash/omni_splash_screen.dart` (constructor ripple from `HomeScreen`)

### Frontend Changes (@developer)
1. [ ] Create `lib/features/profile/profile_screen.dart` as a scrollable profile surface on top of `OmniGradientBackground`.
2. [ ] Build Section 1: Identity.
   - top avatar affordance with 120 dp circular presentation
   - wrap avatar panel in `OmniSurface`
   - if `avatarPath` is null or unreadable, show person icon using theme/OmniTheme tokens
   - tap avatar opens bottom sheet with `Take Photo`, `Choose from Gallery`, `Remove Photo`
   - ensure destructive/remove action is disabled or hidden when no photo exists
3. [ ] Add avatar image handling with explicit platform-safe behavior.
   - native/mobile-desktop path: load via `File(path)` with try/catch / errorBuilder fallback
   - web path: do not crash on `dart:io` unavailability; degrade gracefully to icon/fallback until a web-safe persisted image format is designed
4. [ ] Add display-name editing.
   - tappable name row
   - show `Add your name` muted placeholder when null/blank
   - use inline editor or simple dialog, whichever matches current screen patterns with less state complexity
5. [ ] Build Section 2: Primary Measurements.
   - uppercase muted section label with letterSpacing 2.0
   - one row each for `bodyweight` and `height`
   - row shows label, prominent current value/unit or muted em dash, and trailing add button
   - tap row opens measurement-history bottom sheet
   - tap add button opens log-entry bottom sheet
6. [ ] Build Section 3: Additional Measurements.
   - shown by default directly below primary measurements
   - no extra section label and no dropdown toggle
   - same row rendering and actions as primary measurements
7. [ ] Build log-entry bottom sheet.
   - numeric input prefilled from latest value if available
   - no note field
   - timestamp defaults to save time (no date picker UI)
   - full-width primary `FilledButton` with explicit shape override
   - validate numeric input before save
8. [ ] Build measurement-history bottom sheet.
   - show last 10 entries for the selected type
   - format date as `Mar 14` using existing date utilities or a tiny local formatter rather than adding `intl` unless there is another clear benefit
   - do not render notes
   - support swipe-to-delete per row and refresh state after delete
   - include `Log new entry` button at the bottom
9. [ ] Replace the System-sheet Profile tile navigation in `lib/features/home/home_screen.dart` to push `ProfileScreen(profileState: ...)` instead of `MaintenancePlaceholderScreen`.
10. [ ] Keep all styling aligned with design-system constraints:
   - `OmniGradientBackground` backdrop
   - `OmniSurface` panels
   - typography and spacing from theme/OmniTheme
   - no hardcoded hex colors in the new screen
   - all interactive elements maintain at least 48 dp touch area
   - every `FilledButton`/`OutlinedButton`/`TextButton` sets explicit `shape`
11. [ ] Add platform/dependency setup for `image_picker`.
   - update `pubspec.yaml`
   - add any required iOS usage-description strings if the package demands them for camera/gallery access
   - verify Android/web builds still run after dependency addition
12. [ ] Request Designer review after implementation to verify section hierarchy, typography, spacing, and avatar/measurement affordance polish against the design system.

## Iteration 2

### DB Changes
1. [x] Remove `note` from `BodyMeasurementEntry` model and serialized storage contract.
2. [x] Remove `note` column from `app_body_measurement_entry` schema definitions in legacy and future SQLite assets.

### Backend Changes (@developer)
1. [ ] Simplify `ProfileState.logMeasurement(...)` usage so the measurement timestamp defaults to `DateTime.now()` at save time for the profile UI flow.
2. [ ] Ensure the profile UI no longer depends on a user-editable date field for measurement logging.
3. [ ] Preserve repository-only data access; no direct storage or platform-specific persistence logic may move into UI widgets.

### Frontend Changes (@developer)
1. [ ] Update the measurement log bottom sheet in `lib/features/profile/profile_screen.dart`:
   - remove the date picker UI entirely
   - save `recordedAtMs` implicitly when the user taps `Save`
2. [ ] Remove the note input from the bodyweight logging flow.
   - Superseded by latest requirement: profile measurement note UI removed for all types
   - Data-layer contract also removes profile measurement notes
3. [ ] Keep the height input exactly as-is; no additional height field work is needed from this feedback.
4. [ ] Document web avatar testing behavior in the screen-level implementation notes:
   - `image_picker_for_web` can open browser file selection on web
   - current absolute-file-path avatar design is native-first and does not provide persistent local file-path replay on web
   - if web avatar testing is required beyond picker selection, plan a follow-up web-safe avatar representation such as bytes, object URL, or base64/blob-backed persistence through the repository interface

### Implementation Steps
1. [ ] Remove the profile measurement date input control from the log-entry sheet.
2. [ ] Change save behavior so measurement timestamps are captured at button press time.
3. [ ] Remove or conditionally hide the bodyweight note field.
   - Superseded: remove all profile measurement notes from UI and data layer
4. [ ] Verify the height flow remains unchanged and still logs correctly.
5. [ ] Smoke-test avatar selection on web to confirm current package behavior and document any persistence limitation.

### Acceptance Criteria
- [ ] Bodyweight logging no longer asks for a note.
- [ ] Profile measurement logging does not expose note fields for any type.
- [ ] Measurement logging no longer renders a date input field.
- [ ] Saved measurement timestamps reflect the actual save time.
- [ ] Height logging remains available and unchanged.
- [ ] Documentation explicitly states the current web avatar testing limitation and the viable follow-up direction.

### Implementation Steps
1. [ ] Add the two new data models to `lib/data/models/models.dart`.
2. [ ] Extend `WorkoutRepository` with profile and body-measurement methods.
3. [ ] Implement new repository methods in both Hive and Mock repositories.
4. [ ] Add missing seed unit definitions required by profile measurements.
5. [ ] Create `ProfileState` with profile loading, identity updates, and measurement CRUD helpers.
6. [ ] Thread `ProfileState` through `main.dart`, `app.dart`, `home_screen.dart`, and `omni_splash_screen.dart`.
7. [ ] Create `ProfileScreen` with identity section, measurement rows, and expansion state.
8. [ ] Implement avatar action sheet and defensive image loading.
9. [ ] Implement log-entry bottom sheet and measurement-history bottom sheet with delete support.
10. [ ] Replace the maintenance-sheet Profile tile route.
11. [ ] Add/update tests:
   - repository tests for measurement history sorting and latest lookup
   - `ProfileState` tests for initial load, logging, and deletion refresh behavior
   - widget/navigation smoke test for Profile tile opening `ProfileScreen`
12. [ ] Smoke-test on web and at least one native target if available.

## Progress
- [x] Add `UserProfile` and `BodyMeasurementEntry` models
- [x] Extend `WorkoutRepository` profile/measurement API
- [x] Implement profile persistence in `HiveWorkoutRepository`
- [x] Implement compile-safe profile persistence in `MockWorkoutRepository`
- [x] Add missing measurement units required by the feature
- [x] Create `ProfileState`
- [x] Inject `ProfileState` through app constructors
- [x] Build `ProfileScreen` identity section
- [x] Build measurement rows and expansion UI
- [x] Build logging and history bottom sheets
- [x] Replace Profile tile navigation target
- [x] Add dependency/platform setup for `image_picker`
- [ ] Add tests and run smoke verification
- [ ] Request Designer review
- [x] Remove profile date input from logging sheet
- [x] Remove bodyweight note input
- [x] Remove height note input
- [x] Remove note UI from all profile measurements/history
- [x] Document web avatar testing limitation/follow-up
- [x] Show additional measurements by default without dropdown or label
- [x] Make profile plus button outlined (ghost) in primary color
- [x] Hide username edit hint after name exists
- [x] Remove profile measurement notes from data layer

## Acceptance Criteria
- [ ] The System-sheet Profile tile opens a real `ProfileScreen`, not `MaintenancePlaceholderScreen`.
- [ ] The app compiles with all `WorkoutRepository` implementations after the interface change.
- [ ] A local single-user profile can be loaded and persisted with id `local-user`.
- [ ] Display name edits persist and immediately reflect in the UI.
- [ ] Avatar removal clears the saved path and falls back to the icon state.
- [ ] Missing or invalid avatar paths do not crash the screen.
- [ ] Primary measurements (`bodyweight`, `height`) load their latest values on first profile load.
- [ ] Additional measurements are visible by default below primary measurements.
- [ ] Logging a measurement stores a timestamped entry and updates the latest-value row immediately.
- [ ] Measurement history returns entries sorted by `recordedAtMs` descending.
- [ ] History bottom sheet shows at most the last 10 entries and supports delete.
- [ ] All new buttons explicitly override shape using OmniTheme button radius tokens.
- [ ] The screen uses `OmniGradientBackground` and `OmniSurface` rather than ad hoc containers.
- [ ] New UI uses theme/OmniTheme colors only; no hardcoded hex values are introduced in the new feature.
- [ ] Web builds do not crash because of avatar/file-path logic; unsupported file-path behavior degrades gracefully.

## Files Affected
- `lib/data/models/models.dart`
- `lib/data/repositories/workout_repository.dart`
- `lib/data/repositories/hive_workout_repository.dart`
- `lib/data/repositories/mock_workout_repository.dart`
- `lib/mock/seed_data.dart`
- `lib/state/profile/profile_state.dart`
- `lib/main.dart`
- `lib/app.dart`
- `lib/features/home/home_screen.dart`
- `lib/features/profile/profile_screen.dart`
- `lib/features/splash/omni_splash_screen.dart`
- `pubspec.yaml`
- `test/` (new profile-focused tests)

## Notes
- Current runtime uses Hive for both web and native via `main.dart`; no active SQLite implementation change is required for this feature.
- There is a requirement conflict between absolute file-path avatars and web support. Implementation should treat native file paths as the primary path, while web must fail safe and show the fallback avatar instead of importing `dart:io` into a web-only code path unsafely.
- User feedback supersedes the earlier date-entry assumption: measurement logging should not expose a date field in the UI; `recordedAtMs` should default to save time.
- Older intermediate constraints about bodyweight/height-only note removal are superseded by full profile note removal.
- Latest feedback supersedes earlier scope: profile screen should not render note UI anywhere (log sheets or history), and profile measurement note fields are removed from the data layer contract.
- Latest feedback also supersedes the earlier expansion pattern: additional measurements are always visible below primary measurements with a subtle gap, no dropdown toggle, and no additional section label.
- `unit-cm` and `unit-pct` are not currently present in seeded units and must be added or measurement rows will persist dangling unit IDs.
- `HomeScreen` constructor changes also ripple into `OmniSplashScreen`, even though the splash screen is currently disabled.
- Web photo testing is partially possible today through the web picker plugin, but the current native-first `avatarPath` contract is not a robust persisted-web-avatar design. A follow-up should route web avatar data through the repository as a web-safe representation instead of a local file path.

## Iteration 3

### Analysis
This iteration adds per-measurement validation ranges to the save flow and entry deletion (with confirmation) from the history chart sheet. **No database schema changes are needed.** `deleteMeasurementEntry` already exists in the `WorkoutRepository` interface, all three repository implementations, and `ProfileState`. This is a pure UI + constants task.

Three files change:
- `lib/core/constants/profile_measurements.dart` — new validation-range lookup
- `lib/features/profile/profile_screen.dart` — wire range validation into `_MeasurementLogSheetState._save()`
- `lib/features/profile/widgets/measurement_history_chart_sheet.dart` — long-press delete, confirmation dialog, helper text

### Phase 1: Validation Range Constants (@developer)
1. [ ] Add a private `_ValidationRange` value type to `profile_measurements.dart`:
   ```
   class _ValidationRange {
     final double min;
     final double max;
     const _ValidationRange(this.min, this.max);
   }
   ```
2. [ ] Add two static const maps to `ProfileMeasurements`:
   - `_kgRanges`: keyed by measurement type, values for kg/cm/% units
   - `_lbsRanges`: keyed by `bodyweight` and `lean_mass` only, for lbs display values
3. [ ] Populate ranges exactly per the spec table:
   - `bodyweight` → kg: 20–300, lbs: 40–600
   - `height` → cm: 50–250
   - `body_fat_pct` → %: 1–100
   - `lean_mass` → kg: 20–200, lbs: 40–440
   - `waist_cm` → cm: 30–200
   - `chest_cm` → cm: 30–200
   - `hips_cm` → cm: 30–200
   - `thigh_cm` → cm: 20–100
   - `arm_cm` → cm: 15–80
4. [ ] Add static method `ProfileMeasurements.validationRangeFor(String type, SettingsState settings)` that returns `_ValidationRange`:
   - For `unit-kg` types (`bodyweight`, `lean_mass`): if `settings.preferredWeightUnit` is `lbs`, return lbs range; else return kg range
   - For all other types: return the single fixed range from `_kgRanges`
5. [ ] Add static method `ProfileMeasurements.validationUnitLabel(String type, SettingsState settings)` that returns the display unit string for the error message:
   - For `unit-kg` types: `UnitFormatter.weightLabel(settings)` (returns `'kg'` or `'lbs'`)
   - For `unit-cm` types: `'cm'`
   - For `unit-pct` type: `'%'`

### Phase 2: Log Sheet — Validation & Truncation (@developer)
In `_MeasurementLogSheetState._save()` in `lib/features/profile/profile_screen.dart`:

1. [ ] After `double.tryParse` succeeds, check `value > 0`. If false, set `_valueError` using the range error format (the range minimum is already > 0 for all types, so the range message implicitly covers this — but the explicit positive check ensures future range changes cannot accidentally allow zero).
2. [ ] Call `ProfileMeasurements.validationRangeFor(widget.definition.type, widget.settingsState)` to get `(min, max)`.
3. [ ] If `value < range.min || value > range.max`, set:
   ```
   _valueError = 'Enter a value between ${range.min} and ${range.max} ${unitLabel}.';
   ```
   where `unitLabel` comes from `ProfileMeasurements.validationUnitLabel(...)`. Return without saving.
4. [ ] Before conversion, truncate to one decimal place:
   ```dart
   final truncated = (value * 10).truncate() / 10;
   ```
   Use `truncated` (not `value`) for the canonical-weight conversion and `logMeasurement` call.
5. [ ] Clear `_valueError` on valid input (already done via `setState(() { _valueError = null; })` before the try block — confirm this is in place).

### Phase 3: History Chart Sheet — Delete + Helper Text (@developer)
In `lib/features/profile/widgets/measurement_history_chart_sheet.dart`:

1. [ ] Add `_confirmDelete(int index)` async method:
   - Gets the entry: `final entry = _entries[index]`
   - Formats the display date (`_formatDate(...)`) and value string (same logic as `_buildLabelStrip`)
   - Shows `AlertDialog` with:
     - title: `'Delete entry?'`
     - content: `'{date} · {value} {unit} will be removed from your history.'`
     - actions: `TextButton('Cancel')` + `FilledButton('Delete')`
     - Both buttons use `OmniTheme.buttonUtilityRadius` shape (matching routine delete dialog)
     - `FilledButton` uses `theme.colorScheme.error` as background color for destructive styling:
       ```dart
       backgroundColor: WidgetStateProperty.all(theme.colorScheme.error),
       foregroundColor: WidgetStateProperty.all(theme.colorScheme.onError),
       ```
   - On confirm: `await widget.profileState.deleteMeasurementEntry(entry.id, widget.definition.type)`
   - Then call `_loadEntries()` to refresh
2. [ ] In `_buildDotTapTargets`, add `onLongPress` to the existing `GestureDetector` for each dot:
   ```dart
   onLongPress: () => _confirmDelete(i),
   ```
   The existing `onTap` behavior is unchanged.
3. [ ] Add helper text widget to `build()`:
   - Position: after `_buildChart` / `_buildLabelStrip` block, before the `Divider`
   - Only render when `!_isLoading && _entries.isNotEmpty`
   - Content: `'Tap a point to view · Long-press to delete'`
   - Style: `theme.textTheme.bodySmall?.copyWith(color: OmniTheme.textSecondary.withOpacity(0.55))`
   - Alignment: centered (`textAlign: TextAlign.center`)
4. [ ] After a non-final deletion, `_loadEntries()` already sets `_selectedIndex = orderedEntries.length - 1` — the most recent remaining entry. Confirm this is correct (it is based on existing code).
5. [ ] After the final entry deletion, `_entries.isEmpty` triggers `_buildEmptyState`. Confirm no index-out-of-bounds occurs elsewhere (the `_selectedIndex.clamp(0, _entries.length - 1)` in `_buildLabelStrip` is safe — but `_buildLabelStrip` is only called when `_entries.isNotEmpty`, so this is already guarded).

### Phase 4: Tests (@developer)
1. [ ] Add a test file `test/profile_validation_test.dart` covering:
   - Each measurement type: value at min accepted, value at min-1 rejected, value at max accepted, value at max+1 rejected
   - Zero rejected for all types
   - Negative value rejected for all types
   - Bodyweight kg range applies when settings unit is kg
   - Bodyweight lbs range applies when settings unit is lbs
   - Lean mass kg range applies when settings unit is kg
   - Lean mass lbs range applies when settings unit is lbs
   - Value with >1 decimal is truncated (e.g. `80.456` saves as `80.4`)
   - Value with exactly 1 decimal saves unchanged
   - Value with 0 decimals saves unchanged
2. [ ] Test error message format: result contains `'Enter a value between'` with correct min, max, and unit string.

### Acceptance Criteria
- [ ] Each measurement type rejects values outside its defined range.
- [ ] Zero and negative values are rejected for every measurement type.
- [ ] Body weight validation respects the user's kg/lbs preference; bounds evaluated against typed value before canonical conversion.
- [ ] Lean mass validation respects the user's kg/lbs preference; bounds evaluated against typed value before canonical conversion.
- [ ] All measurements accept one decimal place; values with more decimals are silently truncated to one decimal on save.
- [ ] No step rounding or snapping is applied to any measurement.
- [ ] Validation errors appear inline on the input field using the existing error text slot.
- [ ] Validation error message follows the format `'Enter a value between {min} and {max} {unit}.'`
- [ ] The history chart sheet shows helper text `'Tap a point to view · Long-press to delete'` below the chart whenever entries exist.
- [ ] The helper text is hidden in the empty state.
- [ ] Long-press on a chart point opens a confirmation dialog with the entry's date and value displayed.
- [ ] The confirmation dialog uses the same visual pattern as the existing routine delete dialog (AlertDialog, TextButton Cancel, FilledButton Delete with destructive/error color).
- [ ] Confirming deletion removes the entry, refreshes the chart, refreshes the label strip, and refreshes the latest-value cache on the profile screen.
- [ ] Tap-to-select behavior on chart points is unchanged.
- [ ] Deleting the final entry transitions the sheet into the existing "No entries yet" empty state without errors.
- [ ] After a non-final deletion, the chart selects the most recent remaining entry.
- [ ] The Log New Entry button remains functional in all states, including after the final entry is deleted.
- [ ] Valid entries within range continue to save without regression.

### Files Affected
- `lib/core/constants/profile_measurements.dart` — add `_ValidationRange`, range maps, and two static lookup methods
- `lib/features/profile/profile_screen.dart` — `_MeasurementLogSheetState._save()`: range check, positive check, decimal truncation, inline error message
- `lib/features/profile/widgets/measurement_history_chart_sheet.dart` — `_confirmDelete()`, `onLongPress` on dot tap targets, helper text widget
- `test/profile_validation_test.dart` — new unit tests for validation logic

### Notes
- No DBA involvement needed. `deleteMeasurementEntry` already exists in all repository implementations and `ProfileState`.
- The lbs range for bodyweight and lean mass is checked against the *display value* (before `toCanonicalWeight`). The existing `_save()` already converts to canonical after parse — truncation must occur after range check and before conversion.
- The delete confirmation uses `theme.colorScheme.error` / `onError` for the Delete button background to match destructive intent. The routine delete dialog uses the default `FilledButton` (primary color); measurement deletion may warrant stronger destructive signaling since data cannot be recovered — use error color here.
- `_buildLabelStrip` is only rendered when `_entries.isNotEmpty`, so no clamping issue exists there. The `_selectedIndex` field does not need manual reset beyond what `_loadEntries()` already does.
- The helper text SizedBox/height should not add extra padding in the empty state — gate it strictly on `!_isLoading && _entries.isNotEmpty`, same as `_buildLabelStrip`.

## Progress
- [x] Add `UserProfile` and `BodyMeasurementEntry` models
- [x] Extend `WorkoutRepository` profile/measurement API
- [x] Implement profile persistence in `HiveWorkoutRepository`
- [x] Implement compile-safe profile persistence in `MockWorkoutRepository`
- [x] Add missing measurement units required by the feature
- [x] Create `ProfileState`
- [x] Inject `ProfileState` through app constructors
- [x] Build `ProfileScreen` identity section
- [x] Build measurement rows and expansion UI
- [x] Build logging and history bottom sheets
- [x] Replace Profile tile navigation target
- [x] Add dependency/platform setup for `image_picker`
- [ ] Add tests and run smoke verification
- [ ] Request Designer review
- [x] Remove profile date input from logging sheet
- [x] Remove bodyweight note input
- [x] Remove height note input
- [x] Remove note UI from all profile measurements/history
- [x] Document web avatar testing limitation/follow-up
- [x] Show additional measurements by default without dropdown or label
- [x] Make profile plus button outlined (ghost) in primary color
- [x] Hide username edit hint after name exists
- [x] Remove profile measurement notes from data layer
- [x] Add per-measurement validation ranges
- [x] Add decimal truncation on save
- [x] Add long-press delete to history chart sheet
- [x] Add delete confirmation dialog (entry-level)
- [x] Add hint text to history chart sheet
- [x] Add profile_validation_test.dart

## Acceptance Criteria
- [ ] The System-sheet Profile tile opens a real `ProfileScreen`, not `MaintenancePlaceholderScreen`.
- [ ] The app compiles with all `WorkoutRepository` implementations after the interface change.
- [ ] A local single-user profile can be loaded and persisted with id `local-user`.
- [ ] Display name edits persist and immediately reflect in the UI.
- [ ] Avatar removal clears the saved path and falls back to the icon state.
- [ ] Missing or invalid avatar paths do not crash the screen.
- [ ] Primary measurements (`bodyweight`, `height`) load their latest values on first profile load.
- [ ] Additional measurements are visible by default below primary measurements.
- [ ] Logging a measurement stores a timestamped entry and updates the latest-value row immediately.
- [ ] Measurement history returns entries sorted by `recordedAtMs` descending.
- [ ] History bottom sheet shows at most the last 10 entries and supports delete.
- [ ] All new buttons explicitly override shape using OmniTheme button radius tokens.
- [ ] The screen uses `OmniGradientBackground` and `OmniSurface` rather than ad hoc containers.
- [ ] New UI uses theme/OmniTheme colors only; no hardcoded hex values are introduced in the new feature.
- [ ] Web builds do not crash because of avatar/file-path logic; unsupported file-path behavior degrades gracefully.
- [ ] Each measurement type rejects values outside its defined range (see Iteration 3 table).
- [ ] Zero and negative values are rejected for every measurement type.
- [ ] Bodyweight and lean mass validation respect the user's kg/lbs preference.
- [ ] Values with more than one decimal place are silently truncated to one decimal on save.
- [ ] Validation errors appear inline on the input field.
- [ ] History chart sheet shows helper text when entries exist; hidden in empty state.
- [ ] Long-press on a chart point opens an entry-delete confirmation dialog.
- [ ] Confirming deletion refreshes the chart, label strip, and latest-value cache.
- [ ] Tap-to-select on chart points is unchanged.
- [ ] Deleting the last entry transitions to empty state without errors.
- [ ] Log New Entry button remains functional in all states.

## Files Affected
- `lib/data/models/models.dart`
- `lib/data/repositories/workout_repository.dart`
- `lib/data/repositories/hive_workout_repository.dart`
- `lib/data/repositories/mock_workout_repository.dart`
- `lib/mock/seed_data.dart`
- `lib/state/profile/profile_state.dart`
- `lib/main.dart`
- `lib/app.dart`
- `lib/features/home/home_screen.dart`
- `lib/features/profile/profile_screen.dart`
- `lib/features/splash/omni_splash_screen.dart`
- `pubspec.yaml`
- `lib/core/constants/profile_measurements.dart` _(Iteration 3)_
- `lib/features/profile/widgets/measurement_history_chart_sheet.dart` _(Iteration 3)_
- `test/profile_validation_test.dart` _(Iteration 3, new)_

## Notes
- Current runtime uses Hive for both web and native via `main.dart`; no active SQLite implementation change is required for this feature.
- There is a requirement conflict between absolute file-path avatars and web support. Implementation should treat native file paths as the primary path, while web must fail safe and show the fallback avatar instead of importing `dart:io` into a web-only code path unsafely.
- User feedback supersedes the earlier date-entry assumption: measurement logging should not expose a date field in the UI; `recordedAtMs` should default to save time.
- Older intermediate constraints about bodyweight/height-only note removal are superseded by full profile note removal.
- Latest feedback supersedes earlier scope: profile screen should not render note UI anywhere (log sheets or history), and profile measurement note fields are removed from the data layer contract.
- Latest feedback also supersedes the earlier expansion pattern: additional measurements are always visible below primary measurements with a subtle gap, no dropdown toggle, and no additional section label.
- `unit-cm` and `unit-pct` are not currently present in seeded units and must be added or measurement rows will persist dangling unit IDs.
- `HomeScreen` constructor changes also ripple into `OmniSplashScreen`, even though the splash screen is currently disabled.
- Web photo testing is partially possible today through the web picker plugin, but the current native-first `avatarPath` contract is not a robust persisted-web-avatar design. A follow-up should route web avatar data through the repository as a web-safe representation instead of a local file path.
- Iteration 3 requires no DBA involvement — all repository methods needed already exist. The feature is self-contained in three files plus one new test file.

## Feedback
_None._

---

**Next recommended handoff: @developer**

@developer — Please proceed with Iteration 3. No DB changes are needed. Start with Phase 1 (validation constants in `profile_measurements.dart`), then Phase 2 (log sheet validation), then Phase 3 (chart sheet delete + hint), and finally Phase 4 (tests). The plan above is the single source of truth.