# Feature: profile-cleanup (Height → identity, reorder, Lean Mass → computed)

## Overview

Clean up the Profile screen without changing the look of the individual measurement cards. Three substantive changes:

1. **Height stops being a charted card.** A height chart over time is a flat line (height is effectively constant), so height leaves the `ProfileMeasurements.additional`/`primary` charted lists entirely. It becomes a compact, tappable, editable value inside the identity area at the top of the screen, sitting next to the display name. The user's existing height (if any) is preserved — editing it writes through to the same `BodyMeasurementEntry` repository the chart path used to use, so the Settings preview keeps working with no migration.

2. **Reorder the charted measurements to composition-first, tape-second.** Top to bottom: Body Weight, Body Fat %, Waist, Lean Mass, Hips, Thigh, Chest, Arm. Body weight sits with the identity-relevant measurements; physique tape (chest / arm / thigh) falls to the bottom.

3. **Lean Mass becomes a computed, read-only value.** Three independently-typed fields that are mathematically linked (body weight, body fat %, lean mass) will inevitably contradict each other. Lean mass is derived as `latestBodyWeight × (1 - latestBodyFatPct/100)` from the user's most recent body weight and body fat entries. Manual log controls are removed for lean mass only; if either input is missing, the card shows a not-yet-available state. Pre-existing lean mass entries stay in the repository (no deletion); they simply stop being displayed and stop being writable.

Untouched measurements render exactly as they do today — no collapsing, hiding, or slim-row substitution.

## Requirements

- `ProfileMeasurements.additional` (the charted list shown under the `MEASUREMENTS` eyebrow) no longer contains `height`.
- The charted list, top to bottom, is: Body Weight, Body Fat %, Waist, Lean Mass, Hips, Thigh, Chest, Arm.
- The identity area shows an editable height value next to the display name (single tap to edit, dialog with `Done`/`Cancel`, validates via the existing cm/ftin range, persists via the existing `BodyMeasurementEntry` for `type='height'`).
- Editing height persists the new value to the repository and updates the Settings height preview (which already reads from `profileState.getMeasurementHistory('height')`).
- `lean_mass` card renders a calculated value `latestBodyWeight × (1 - latestBodyFatPct / 100)` from the latest body weight and body fat entries.
- If body weight or body fat is missing, the lean mass card shows a not-yet-available state (em-dash), not a number and not an error.
- The lean mass card has no `+` (manual log) button and no tappable chart-sparkline area (the card body still renders the value column with a read-only calculation; the chart area collapses to a read-only "Computed" label so the card's geometry matches its peers).
- Pre-existing `lean_mass` `BodyMeasurementEntry` rows are not deleted; they remain in the repository but are no longer queried for display.
- Lean mass range keys (`lean_mass` kg/lbs ranges in `ProfileMeasurements`) remain in place — they are still needed if any pre-existing log code paths are exercised by other tests, but they are no longer referenced by the new UI. We keep the range maps defensively to avoid breaking `validationRangeFor('lean_mass', ...)` callers.

## Acceptance Criteria

- [ ] Height no longer appears as a charted measurement card anywhere in the measurements list.
- [ ] Height appears as an editable value in the identity area near the name; tapping it lets the user change it, and the change persists.
- [ ] A height the user entered before this change still displays after it; nothing is reset.
- [ ] The Settings height preview shows the same value as the Profile identity field after an edit.
- [ ] The measurements render in this order, top to bottom: Body Weight, Body Fat %, Waist, Lean Mass, Hips, Thigh, Chest, Arm.
- [ ] Lean Mass displays a value derived from the latest Body Weight and latest Body Fat percentage and updates when either of those changes.
- [ ] Lean Mass has no manual add/log control.
- [ ] When Body Weight or Body Fat is missing, Lean Mass shows a not-yet-available state, not a number and not an error.
- [ ] Untouched measurements render identically to their current appearance — no collapsing, hiding, or slim-row substitution is introduced.

## Scenarios

### S-001: Height removed from the charted measurements list
- Trigger: User opens the Profile screen.
- Precondition: User has any combination of measurements entered.
- Flow: Profile screen mounts → renders identity section + a single charted-measurements column.
- Expected outcome: The charted column contains exactly the ordered list Body Weight, Body Fat %, Waist, Lean Mass, Hips, Thigh, Chest, Arm. Height is not present in the charted column.
- Edge case of: none.

### S-002: Height lives as a tappable, editable value in the identity area
- Trigger: User opens the Profile screen and taps the height value under the display name.
- Precondition: User has height recorded (180 cm).
- Flow: Profile renders → identity shows "180 cm" beneath the name → user taps it → dialog opens with `Value (cm)` field pre-filled with 180 and `Done` / `Cancel` → user changes to 182, taps `Done`.
- Expected outcome: Repository now has a `BodyMeasurementEntry(measurementType='height', value=182, unitId='unit-cm')` with a fresh timestamp. Identity area now reads "182 cm". Settings preview also reads "182 cm".
- Edge case of: none.

### S-003: Pre-existing height survives the cleanup
- Trigger: App upgrade from a version where height was a charted card to this version.
- Precondition: User already has a stored height entry in the repository.
- Flow: Profile mounts with the existing repository state.
- Expected outcome: The identity area reads the stored height (in the active unit). Nothing is reset, no migration required.
- Edge case of: S-002.

### S-004: Measurement list order is the exact specified sequence
- Trigger: Profile mounts.
- Precondition: None.
- Flow: Profile renders → the charted column's `OmniCardHeader` titles render in order.
- Expected outcome: Titles in order, top to bottom: BODY WEIGHT, BODY FAT, WAIST, LEAN MASS, HIPS, THIGH, CHEST, ARM.
- Edge case of: none.

### S-005: Lean Mass = weight × (1 - bodyFat/100) and recomputes on change
- Trigger: User logs a body weight or a body fat % entry.
- Precondition: User has both body weight and body fat entries.
- Flow: Body weight = 80 kg, body fat = 15% → Lean Mass card reads "68 kg". User updates body fat to 12% → Lean Mass card reads "70.4 kg" (or `70 kg` after 1dp truncation to match the existing formatter).
- Expected outcome: Lean Mass value updates whenever either input changes; the value is mathematically derived, not stored.
- Edge case of: none.

### S-006: Lean Mass has no manual entry control
- Trigger: Profile mounts.
- Precondition: User has body weight + body fat entries.
- Flow: Profile renders → user looks at the Lean Mass card row.
- Expected outcome: No `+` button is present on the Lean Mass card. Tapping the chart area does nothing (no `InkWell` opens a sheet for `lean_mass`).
- Edge case of: S-005.

### S-007: Lean Mass shows not-yet-available when an input is missing
- Trigger: Profile mounts.
- Precondition: User has body weight but no body fat (or vice versa, or neither).
- Flow: Profile renders.
- Expected outcome: Lean Mass card's value column reads "—" (em dash), matching the existing "missing measurement" rendering used by every other measurement.
- Edge case of: S-005.

### S-008: Untouched measurements render identically
- Trigger: Profile mounts.
- Precondition: Any.
- Flow: Profile renders.
- Expected outcome: Body Weight, Body Fat %, Waist, Hips, Thigh, Chest, Arm render with the same chart + value + add-button row geometry they had before this change. No slim row, no collapse, no different padding.
- Edge case of: none.

## Iteration 1

### DB Changes
- **Models**: no schema change. `BodyMeasurementEntry` and `UserProfile` are unchanged.
- **Repository surface**: unchanged. `saveMeasurementEntry(type='height', ...)` is the same write path the chart-card used; we just stop calling it from the chart card UI and start calling it from a new identity-area editor.
- **Seed data**: `lib/mock/seed_data.dart` — no change required.
- **`ProfileMeasurements` constants** (`lib/core/constants/profile_measurements.dart`):
  - `additional` list shrinks from `[bodyFatPct, leanMass, waist, chest, hips, thigh, arm]` to `[bodyweight, bodyFatPct, waist, leanMass, hips, thigh, chest, arm]` (note: bodyweight moves into `additional` since `primary` will go away). Order matches S-004.
  - `primary` list is removed entirely (the screen no longer has a primary/additional split — a single charted column).
  - The `height` definition stays so `ProfileMeasurements.definitionFor('height')` and `validationRangeFor('height', ...)` keep working.
  - The `lean_mass` definition stays so the computed card can find its label/unit. Its kg/lbs range entries remain for backward compat with `validationRangeFor('lean_mass', ...)` callers (none in the new UI; keep them).
  - `all` list reflects the new world: `[bodyweight, bodyFatPct, waist, leanMass, hips, thigh, chest, arm]`.
- **SQLite parity**: no schema change. The `body_measurements` table continues to accept `height` and `lean_mass` rows indefinitely; the cleanup only stops reading them for display.

### Backend Changes
- `lib/state/profile/profile_state.dart`:
  - Add `Future<void> updateHeight(double cmCanonical)` — delegates to `logMeasurement('height', cmCanonical, 'unit-cm')`. This is the same write path the chart card used, so no new repo method is needed.
  - Add `double? get latestHeightCm` → returns `_latestMeasurements['height']?.value`.
  - Add `double? get latestBodyWeightKg` → returns `_latestMeasurements['bodyweight']?.value`.
  - Add `double? get latestBodyFatPct` → returns `_latestMeasurements['body_fat_pct']?.value`.
  - Add `double? get computedLeanMassKg` → returns `latestBodyWeightKg != null && latestBodyFatPct != null ? latestBodyWeightKg! * (1 - latestBodyFatPct! / 100) : null`.
  - These getters are pure derivations of `_latestMeasurements`; no separate load.
  - `loadLatestMeasurements` already loads both primary and additional — we shift the set it loads to the new `ProfileMeasurements.additional` list (so it no longer loads `height` and `lean_mass` for the charted column). However, `loadProfile` still needs to load `height` so the identity area can read it. Concretely:
    - `loadProfile()` (and the screen's `initState`) calls `loadLatestMeasurements(['height'])` for the identity field, in addition to loading the charted column's set.
    - The screen's `initState` is updated to call `loadLatestMeasurements([...additional.map, 'height'])` so `height` is loaded even though it is no longer in `additional`.
  - No new private fields; the new getters read existing state.

### Frontend Changes
- `lib/features/profile/profile_screen.dart`:
  - **Identity area**: below the display name (and the existing "Tap to edit" hint when name is empty), add a single tappable row that shows the current height value (via `UnitFormatter.formatHeight(...)` so it honors the active unit) and opens a new dialog `_HeightDialog` on tap. The dialog mirrors the cm/ftin input shape of `_MeasurementLogSheet` but is local to the identity area (height is no longer a charted measurement; using `_MeasurementLogSheet` would expose the chart and "+" controls).
  - **Measurements section**: drop the primary/additional two-section layout. Render a single section whose `definitions` is `ProfileMeasurements.additional` (now containing all charted measurements including bodyweight). The `OmniCardHeader` titles render in `definitions[i].label.toUpperCase()` order, giving S-004.
  - **Lean Mass row** (computed path):
    - Reuse the existing card body structure (chart rectangle + value column + add button) but only for definitions whose `type != 'lean_mass'`. For `lean_mass`, render a simpler card body that has a `Computed` label on the left and the calculated value on the right, with NO `+` button and NO `InkWell`-wrapped chart area (so tapping does nothing — S-006).
    - The value column reads from `profileState.computedLeanMassKg` and formats via `UnitFormatter.formatWeight(computedLeanMassKg, settingsState)` so it honors the active weight unit (kg or lbs). If null → em dash (S-007).
  - **Untouched measurements**: their card body is untouched. We don't change `_buildMeasurementSection`'s per-row layout for non-`lean_mass` rows.
  - **No collapse / hide / slim-row**: every row keeps its `OmniSurface` + 3-column body. Only `lean_mass` swaps the middle column's contents (chart-area → read-only "Computed" label, value-column stays, no `+` button).
- `lib/widgets/hub/hub_sheet.dart`: no change — `SettingsScreen` already reads height through `profileState.getMeasurementHistory('height')`.
- `lib/features/settings/settings_screen.dart`: no change required — the existing height preview already reads `profileState.getMeasurementHistory('height')` and will pick up the new writes immediately. We do, however, verify the path round-trips with a new test.

### Implementation Steps
1. **Phase 0.5 (TDD)**: write tests for S-001 through S-008 + regression tests against `profile_screen_test.dart` (drop the `Icons.add` index assumptions that referenced height being the second primary card) and `header_standardization_test.dart` (the `ProfileMeasurements.primary.length + ProfileMeasurements.additional.length` count must be re-expressed as just `ProfileMeasurements.additional.length`; `ProfileMeasurements.all.map` references must still work for the uppercased-titles walk). Confirm tests fail (red).
2. **Constants**: rewrite `ProfileMeasurements.additional` (reordered, includes bodyweight), drop `primary`, keep `lean_mass` range entries, update `all`.
3. **State**: add `latestHeightCm`, `latestBodyWeightKg`, `latestBodyFatPct`, `computedLeanMassKg`, `updateHeight(...)` to `ProfileState`.
4. **Screen**: rewrite `initState` to load `height` separately; add `_buildHeightIdentityRow` + `_HeightDialog`; replace primary/additional double section with a single `additional` section; special-case the `lean_mass` row.
5. **Tests**: run `flutter test test/profile_screen_test.dart test/profile_state_test.dart test/profile_validation_test.dart test/header_standardization_test.dart test/interaction_flow_test.dart test/screen_widget_test.dart`; iterate until green.
6. **Doc hygiene**: update `docs/profile_and_measurements.md` (drop `Primary measurements` mention, document the identity-area height editor, document the computed lean mass).
7. **Final test run**: `flutter test`.

## Progress

- [x] Phase 0 — Plan
- [x] Phase 0.5 — TDD red tests
- [x] Phase 1 — Data layer (constants + state + repo)
- [x] Phase 2 — UI (identity height + reordered cards + computed lean mass)
- [x] Phase 2 — Tests green
- [x] Phase 2 — Doc hygiene
- [x] Phase 3 — Code review

### Phase 0 Complete ✓
### Phase 1 Complete ✓
### Phase 2 Complete ✓
### Phase 3 Complete ✓

## Feedback