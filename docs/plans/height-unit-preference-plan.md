# Feature: Dedicated Height Unit Preference

## Overview
Add a standalone `Height` unit preference (centimeters vs feet/inches) that
applies everywhere height is shown or entered on the Profile screen. Bodyweight
and lean mass already follow the existing weight setting; circumference
measurements (waist, chest, hips, thigh, arm) stay in centimeters. This is a
single-axis toggle, not a global metric/imperial switch.

Canonical storage stays in centimeters: existing heights logged before this
setting existed must display correctly under either unit with no migration
step, and a height saved in one unit must round-trip exactly when the toggle
flips back and forth (the canonical cm value is never rewritten by a unit
switch).

## Requirements
- Add a persisted `preferredHeightUnit` to `SettingsState` (key
  `preferred_height_unit`) with two accepted values: `cm` (default) and
  `ftin`. Normalize unknown values to `cm`.
- Extend `UnitFormatter` with height helpers: `normalizeHeightUnit`,
  `heightLabel`, `formatHeight`, `formatHeightValue`, `convertHeightFromCm`,
  `toCanonicalHeight`, and compound helpers `cmToFeetInches` /
  `feetInchesToCm` / `formatFeetInches`. Storage is unchanged (cm).
- Apply the active unit to:
  - Profile card value (compound `5 ft 11 in` in ft/in mode; `180 cm` in cm mode).
  - Height log sheet — separate `Feet` and `Inches` fields (inches 0–11) in
    ft/in mode; single centimeter field in cm mode. Round-trip exact.
  - Height history chart — y-axis and selected-point label reflect the active
    unit; in ft/in mode the chart plots total inches with compound label.
- Validation must reject implausible heights with a message stated in the
  active unit. The same physical range as today (50–250 cm) is preserved
  regardless of which unit is active.
- Add a `Height` row to the existing `PREFERENCES` section of the Settings
  screen using the same segmented toggle pattern as Weight and Distance.
- Do not change circumference measurements, bodyweight, or lean mass. Do not
  introduce a global metric/imperial switch.

## Acceptance Criteria
- [ ] `SettingsState` exposes `preferredHeightUnit` with getter, setter, and
  persistence under the key `preferred_height_unit`
- [ ] Default height unit is `cm`; unknown or legacy values normalize to `cm`
- [ ] `UnitFormatter` exposes `normalizeHeightUnit`, `heightLabel`,
  `heightLabelUpper`, `formatHeight`, `formatHeightValue`,
  `convertHeightFromCm`, `toCanonicalHeight`, `cmToFeetInches`,
  `feetInchesToCm`, and `formatFeetInches`
- [ ] `UnitFormatter.formatHeight(180, settingsCm)` → `"180 cm"`
- [ ] `UnitFormatter.formatHeight(180, settingsFtin)` → `"5 ft 11 in"`
- [ ] `UnitFormatter.toCanonicalHeight(5, 11, settingsFtin)` round-trips to
  exactly 180.34 cm; back through `formatHeight` reads as `"5 ft 11 in"`
- [ ] `UnitFormatter.toCanonicalHeight(180, settingsCm)` returns 180.0 exactly
- [ ] Profile screen height card reflects the active unit (`180 cm` in cm
  mode, `5 ft 11 in` in ft/in mode)
- [ ] Profile screen height log sheet presents `Feet` and `Inches` fields in
  ft/in mode and a single `Value (cm)` field in cm mode; inches input is
  bounded to 0–11
- [ ] Settings screen shows a `Height` row with `cm` and `ft/in` segmented
  toggle in the existing `PREFERENCES` section
- [ ] Height history chart y-axis and selected-point label reflect the active
  unit
- [ ] A height saved as 180 cm, viewed in ft/in mode, then viewed in cm mode
  again, shows `180 cm` exactly (no drift)
- [ ] A height saved before this setting existed (unitId `unit-cm`, value
  180.0) displays correctly under both units with no user action
- [ ] Entering an implausible height (e.g., `0 ft 0 in`, `9 ft 0 in`,
  `0 cm`, `999 cm`) is rejected with a message expressed in the active unit
- [ ] Circumference measurements, bodyweight, and lean mass remain
  centimeter / kilogram / pound unit-only behavior; no regression
- [ ] All buttons touched by this feature (Settings rows, log sheet Save,
  dialog actions) keep the explicit `shape:` override convention
- [ ] `docs/theme_and_settings.md` updated with the new preference key,
  default, and setter
- [ ] `docs/profile_and_measurements.md` updated with the height unit
  behavior, log sheet input shape, and chart label
- [ ] `docs/widget_catalog.md` updated if a new shared widget is introduced
- [ ] `scripts/sqlite_schema.sql` and `docs/db_integration.md` unchanged
  (storage is `unit-cm` only)

## Scenarios
### S-001: Default Height unit is centimeters
- Trigger: First launch / no saved preference.
- Precondition: No `preferred_height_unit` value in repository.
- Flow: App starts; user navigates to Settings → PREFERENCES section.
- Expected outcome: `Height` row segmented toggle is set to `cm`.
- Edge case of: none.

### S-002: Height unit persists across save and reload
- Trigger: User taps `ft/in` in Settings.
- Precondition: SettingsState initialized with default `cm`.
- Flow: User toggles Height row to `ft/in`; user kills app and relaunches.
- Expected outcome: `preferredHeightUnit` reads back as `ft/in` and Settings
  shows the `ft/in` segment selected.
- Edge case of: S-001.

### S-003: Normalize invalid stored value to `cm`
- Trigger: Repository has `preferred_height_unit` = `inches` (or any unknown).
- Precondition: SettingsState initialized.
- Flow: App starts.
- Expected outcome: `preferredHeightUnit` reads as `cm` and Settings
  reflects `cm`.
- Edge case of: S-001.

### S-004: Profile card shows compound feet/inches in ft/in mode
- Trigger: User has a 180 cm height entry and switches to ft/in mode.
- Precondition: `BodyMeasurementEntry(measurementType='height', value=180.0,
  unitId='unit-cm')` exists.
- Flow: User opens Profile screen; the Height row's value column is observed.
- Expected outcome: Value renders as `5 ft 11 in` (180 cm × 0.3937 →
  70.866 in → rounded to 71 in → 5 ft 11 in).
- Edge case of: none.

### S-005: Profile card shows centimeters in cm mode
- Trigger: User has a 180 cm height entry and the unit is `cm`.
- Precondition: `BodyMeasurementEntry(measurementType='height', value=180.0,
  unitId='unit-cm')` exists.
- Flow: User opens Profile screen; the Height row's value column is observed.
- Expected outcome: Value renders as `180 cm`.
- Edge case of: none.

### S-006: Height log sheet presents feet/inches inputs in ft/in mode
- Trigger: User taps the `+` button on the Height row in ft/in mode.
- Precondition: `preferredHeightUnit` is `ftin`.
- Flow: User opens the log sheet.
- Expected outcome: Two `NumericFieldWithDoneBar` inputs are visible with
  label text `Feet` and `Inches`; saving with valid values persists the
  converted cm value with `unitId='unit-cm'`.
- Edge case of: none.

### S-007: Height log sheet presents single centimeter input in cm mode
- Trigger: User taps the `+` button on the Height row in cm mode.
- Precondition: `preferredHeightUnit` is `cm`.
- Flow: User opens the log sheet.
- Expected outcome: A single `NumericFieldWithDoneBar` with label
  `Value (cm)` is visible; saving persists the value directly.
- Edge case of: none.

### S-008: Inches input rejects values above 11
- Trigger: User enters 12 in the Inches field of the height log sheet.
- Precondition: ft/in mode active.
- Flow: User taps Save.
- Expected outcome: Validation error rendered in the active unit (e.g.
  `"Enter a value between 1 ft 0 in and 8 ft 2 in"`), entry is not saved.
- Edge case of: S-006.

### S-009: Implausible height rejected in cm mode
- Trigger: User enters `999` in the cm field of the height log sheet.
- Precondition: cm mode active.
- Flow: User taps Save.
- Expected outcome: Validation error in cm (`"Enter a value between 50 and
  250 cm."`).
- Edge case of: S-007.

### S-010: Implausible height rejected in ft/in mode
- Trigger: User enters `9 ft 0 in` in the height log sheet.
- Precondition: ft/in mode active.
- Flow: User taps Save.
- Expected outcome: Validation error in ft/in (`"Enter a value between
  1 ft 8 in and 8 ft 2 in."`).
- Edge case of: S-006.

### S-011: Round-trip integrity: cm → ft/in → cm shows original
- Trigger: User saves `180 cm` in cm mode, switches to ft/in, then back.
- Precondition: `BodyMeasurementEntry(value=180.0, unitId='unit-cm')` exists.
- Flow: User toggles Height unit twice.
- Expected outcome: After the second switch back to cm, the Profile card
  shows `180 cm` (no drift).
- Edge case of: none.

### S-012: Round-trip integrity: ft/in entry → cm shows converted value
- Trigger: User saves `5 ft 11 in` in ft/in mode and switches to cm.
- Precondition: ft/in mode active.
- Flow: User logs `5 ft 11 in`; user switches to cm mode and opens Profile.
- Expected outcome: Profile card shows `180.3 cm` (5×30.48 + 11×2.54 =
  180.34 → truncated to 180.3 per the existing 1-decimal policy).
- Edge case of: none.

### S-013: Pre-existing height displays correctly under both units
- Trigger: User has a height logged before the setting existed.
- Precondition: `BodyMeasurementEntry(measurementType='height', value=175.5,
  unitId='unit-cm')` exists; `preferredHeightUnit` is unset → defaults to
  `cm`.
- Flow: User opens Profile; user switches to ft/in; user opens Profile
  again.
- Expected outcome: First view shows `175.5 cm`; second view shows
  `5 ft 9 in` (175.5 / 2.54 = 69.094 in → 69 in → 5 ft 9 in).
- Edge case of: S-011, S-012.

### S-014: Height history chart y-axis labels reflect the active unit
- Trigger: User opens the height history chart in ft/in mode.
- Precondition: ≥1 height entry exists; `preferredHeightUnit` is `ftin`.
- Flow: User taps the sparkline on the Height row.
- Expected outcome: Y-axis labels are whole-inch numbers and the
  selected-point label reads in compound form (e.g. `5 ft 9 in`).
- Edge case of: none.

### S-015: Height history chart value label reflects the active unit (cm)
- Trigger: User opens the height history chart in cm mode.
- Precondition: ≥1 height entry exists; `preferredHeightUnit` is `cm`.
- Flow: User taps the sparkline on the Height row.
- Expected outcome: Selected-point label reads as `180 cm` (with the unit
  suffix).
- Edge case of: none.

### S-016: Bodyweight, lean mass, and circumferences are untouched
- Trigger: User logs a bodyweight entry while the height unit is `ftin`.
- Precondition: `preferredWeightUnit` is `kg`; `preferredHeightUnit` is
  `ftin`.
- Flow: User logs `80.5 kg` in the Bodyweight log sheet.
- Expected outcome: Entry saved as `80.5 kg` (canonical kg) and displayed
  as `80.5 kg` regardless of the height unit setting. Waist/Chest/Hips/
  Thigh/Arm also remain cm-only.
- Edge case of: none.

## Iteration 1

### Analysis
- STANDARD feature. New `preferredHeightUnit` preference, new unit-aware
  display path for height on the Profile card, the height log sheet, and the
  height history chart. New compound input UI in the log sheet for ft/in mode.
  Storage contract is unchanged (cm is canonical, unitId stays `unit-cm`).
- Scenarios S-001..S-016 cover defaults, persistence, validation, both
  display modes, both entry modes, the round-trip contract, and the
  out-of-scope guards (circumference / bodyweight untouched).
- No new repository methods; `WorkoutRepository.setPreferenceString` /
  `getPreferenceString` already cover the new key.
- No schema change: `BodyMeasurementEntry.value` continues to be stored in
  canonical cm with `unitId='unit-cm'`.
- The compound ft/in input is contained to the height log sheet — every
  other measurement (and every other entry path) keeps the single
  `NumericFieldWithDoneBar` input shape.
- The chart's height y-axis plots total inches in ft/in mode; the
  selected-point label is the compound `5 ft 11 in` form. In cm mode the
  chart keeps its existing cm plotting path.

### DB Changes
- None. `scripts/sqlite_schema.sql` unchanged.

### Backend Changes
- None. `WorkoutRepository` interface unchanged; the new preference is stored
  via the existing `setPreferenceString` / `getPreferenceString` pair.

### Frontend Changes
- `lib/state/settings/settings_state.dart` — new `preferredHeightUnit`
  field, getter, setter, normalization, and load path.
- `lib/core/utils/unit_formatter.dart` — height helpers: `normalizeHeightUnit`,
  `heightLabel` / `heightLabelUpper`, `formatHeight` / `formatHeightValue`,
  `convertHeightFromCm`, `toCanonicalHeight`, `cmToFeetInches`,
  `feetInchesToCm`, `formatFeetInches`.
- `lib/core/constants/profile_measurements.dart` — `validationRangeFor`
  accepts a `heightUnit` argument; new `_heightImperialRanges` map; height
  unit label returned from `validationUnitLabel` matches the active unit.
- `lib/features/profile/profile_screen.dart` — `_formatMeasurementValue`
  routes height through `UnitFormatter.formatHeight`; the height log sheet
  branches on the active unit to render either a single cm field or a
  feet+inches field pair with `Inches 0–11` constraint and
  `UnitFormatter.feetInchesToCm` conversion on save.
- `lib/features/profile/widgets/measurement_history_chart_sheet.dart` —
  height entries use the active unit for the y-axis plot, the y-axis label
  format, and the selected-point value label.
- `lib/features/settings/settings_screen.dart` — add a `Height` row to the
  existing `PREFERENCES` section using the segmented toggle pattern
  (defaults to `cm`, `ft/in` second option).
- `lib/features/profile/widgets/measurement_sparkline.dart` — pass through
  the height unit context where appropriate (the actual chart already
  receives `settingsState`).
- Test updates in:
  - `test/settings_state_test.dart` — defaults, persistence, normalization.
  - `test/utils_test.dart` — height conversion, round-trip, compound
    format helpers.
  - `test/profile_validation_test.dart` — height validation in cm and
    ft/in; error messages in the active unit.
  - `test/profile_screen_test.dart` — height card reflects active unit;
    height log sheet presents the right input shape; cm save stays cm.
  - `test/screen_widget_test.dart` — height history chart value label
    reflects the active unit.
  - `test/interaction_flow_test.dart` — full height flow in both units.

### Implementation Steps
1. [ ] Add `preferredHeightUnit` to `SettingsState` with normalize-to-`cm`
   fallback and persistence under `preferred_height_unit`.
2. [ ] Add height helpers to `UnitFormatter` (normalize, label,
   format, convert, round-trip, compound helpers).
3. [ ] Extend `ProfileMeasurements.validationRangeFor` and
   `validationUnitLabel` to handle the height unit argument and the
   imperial range.
4. [ ] Add a `Height` row in the `PREFERENCES` section of
   `SettingsScreen` with the `cm` / `ft in` segmented toggle.
5. [ ] Route Profile card height display through
   `UnitFormatter.formatHeight`.
6. [ ] Update the height log sheet to branch on the active unit: single cm
   field vs feet+inches field pair with `Inches 0–11` constraint.
7. [ ] Update `MeasurementHistoryChartSheet` to use the active unit for
   height y-axis plotting and the selected-point label.
8. [ ] Update tests for settings defaults, height round-trip, validation in
   both units, log sheet input shape, chart labels.
9. [ ] Update `docs/theme_and_settings.md` and
   `docs/profile_and_measurements.md`.

## Progress
- [x] Add `preferredHeightUnit` to `SettingsState`
- [x] Add `UnitFormatter` height helpers
- [x] Extend `ProfileMeasurements` validation for the height unit
- [x] Add `Height` row in `SettingsScreen` PREFERENCES
- [x] Route Profile card height through `UnitFormatter.formatHeight`
- [x] Update height log sheet for dual input mode
- [x] Update height history chart y-axis and label
- [x] Add / update tests for defaults, round-trip, validation, log sheet, chart
- [x] Update `docs/theme_and_settings.md` and
  `docs/profile_and_measurements.md`
- [x] Run `flutter analyze` and `flutter test` end-to-end

## Feedback
(empty)

### Phase 0 Complete ✓
Plan written. Scenarios S-001..S-016 cover defaults, persistence,
normalization, both display paths, both entry paths, validation, the
round-trip contract, and the out-of-scope guards. Moving to Phase 1
(Data Layer).

### Phase 1 Complete ✓
Data layer analysis:
- `lib/data/models/models.dart` — `BodyMeasurementEntry` is unchanged.
  Height is still stored in canonical cm with `unitId='unit-cm'`. No
  new fields, no new types.
- `lib/data/repositories/workout_repository.dart` — interface unchanged.
  The new `preferred_height_unit` preference rides on the existing
  `getPreferenceString` / `setPreferenceString` pair.
- `lib/data/repositories/mock_workout_repository.dart` — unchanged. The
  in-memory `_stringPrefs` map already covers arbitrary string keys.
- `lib/data/repositories/hive_workout_repository.dart` — unchanged.
- `lib/mock/seed_data.dart` — unchanged.
- `scripts/sqlite_schema.sql` — unchanged. No new columns or tables.
- `scripts/sqlite_seed.sql` — unchanged.
- `docs/data_models.md` — unchanged (no model change).
- `docs/db_integration.md` — unchanged (no repository or schema change).
- `docs/widget_catalog.md` — unchanged unless a new shared widget is
  introduced in Phase 2 (the height log sheet's dual input can stay
  private to the profile feature).

The "data layer" effect of this feature lives in `lib/state/settings/`
(the new `preferredHeightUnit`) and `lib/core/utils/unit_formatter.dart`
(the new height helpers). Both are pure-Dart, environment-safe, and
covered by Phase 2 tests.

### Phase 2 Complete ✓
- Red tests added first to `test/utils_test.dart`,
  `test/settings_state_test.dart`, `test/profile_validation_test.dart`,
  `test/profile_screen_test.dart`, and `test/screen_widget_test.dart`.
- Implementation:
  - `lib/core/utils/unit_formatter.dart` — new `normalizeHeightUnit`,
    `heightLabel` / `heightLabelUpper`, `formatHeight`,
    `formatHeightValue`, `convertHeightFromCm`,
    `toCanonicalHeightFeetInches`, `cmToFeetInches`, `feetInchesToCm`,
    `formatFeetInches` helpers.
  - `lib/state/settings/settings_state.dart` — new
    `preferredHeightUnit` field, getter, setter, normalize-to-`cm`
    fallback, persistence under `preferred_height_unit`.
  - `lib/core/constants/profile_measurements.dart` —
    `validationRangeFor` and `validationUnitLabel` accept a
    `heightUnit` named arg; new `_heightFtinRange` (20–98 total inches
    = 1 ft 8 in – 8 ft 2 in = 50.8–248.92 cm).
  - `lib/features/settings/settings_screen.dart` — new `Height` row in
    the existing `PREFERENCES` section using the shared
    `_SegmentedToggle` pattern.
  - `lib/features/profile/profile_screen.dart` — `_formatMeasurementValue`
    routes height through `UnitFormatter.formatHeight`; the height log
    sheet branches on the active unit to render a single cm field
    (`_valueController`) or a side-by-side feet/inches field pair
    (`_feetController`, `_inchesController`) with 0–11 inch validation.
    The `ListenableBuilder` now merges `profileState` and
    `settingsState` so the unit-aware display rebuilds on toggle.
  - `lib/features/profile/widgets/measurement_history_chart_sheet.dart` —
    new `_formatSelectedValueLabel` and `_toChartValue` helpers route
    height through the unit-aware formatter; the chart y-axis plots
    total inches in ftin mode and cm in cm mode.
- Test status: `flutter test` (full suite) — 1627 passed, 5 skipped
  (pre-existing), 0 failed.
- Analyze status: pre-existing analyzer warnings/info in the touched
  files; none are introduced by this change.
- Doc status: `docs/theme_and_settings.md` and
  `docs/profile_and_measurements.md` updated.

### Phase 3 Complete ✓
- Code review verdict: ✅ Approved with 4 non-blocking suggestions.
- Layers in scope: state, features, core, docs. Layers skipped:
  models, repositories, widgets (no new shared widget), and the docs
  that don't apply to this change.
- Acceptance criteria: 16/16 met.
- Scenario register: all 16 scenarios (S-001..S-016) covered by tests.
- Findings:
  - 💡 Suggest 1: `_MeasurementLogSheetState._valueController` is kept
    alive even when `_isHeightFtinMode` is true. Consider narrowing
    its lifecycle to the cm path.
  - 💡 Suggest 2: `_isHeightFtinMode` is recomputed on every build;
    acceptable at current scope.
  - 💡 Suggest 3: `heightUnit` is a `String`; consider an enum if more
    conditional branches land.
  - 💡 Suggest 4: Add a one-line comment linking the
    `'5 ft 11 in'` literal to `cmToFeetInches` so the test doesn't
    silently rot if the rounding policy ever changes.
- Doc hygiene: both touched docs (`theme_and_settings.md`,
  `profile_and_measurements.md`) reflect the post-implementation code;
  the other 5 docs are N/A.
- Global conventions: PASS on 5 rules, N/A on 2, 0 FAILs.
- Architecture compliance: all in-scope layers pass.
- Buttons: every touched button keeps the explicit `shape:` override
  with `OmniTheme` tokens.
- Dead code: removed the unused `toCanonicalHeight` (always
  passthrough, never called from production).
- Test coverage: 28 new tests; full suite green.
- Environment safety: no `dart:io`, no SQLite in mock, no concrete
  repo references, no `Platform.is*`.
- DRY + clean: helpers concentrated in `UnitFormatter`; validation in
  `ProfileMeasurements`; one redundant call in `convertHeightFromCm`
  simplified; function sizes small; comments explain WHY.
- Final: 0 critical, 0 warnings, 4 suggestions.

⏸️ PIPELINE COMPLETE — Implementation and review delivered. Approved
for merge. Suggestions are non-blocking.
