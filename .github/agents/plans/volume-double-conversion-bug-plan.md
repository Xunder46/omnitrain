# Feature: Volume Double-Conversion Bug Fix

## Overview
Total volume on the session summary screen shows ~2.2× the actual weight lifted for users whose preferred weight unit is lbs. The bug is a double unit-conversion: weight values are stored as the raw display value (lbs) but the summary display treats them as kg and applies another ×2.20462 conversion.

---

## Analysis

### Root Cause: Weight observations are stored in display units, not canonical kg

**Trace:**

1. `InlineMetricEditor` in `workout_session_detail_view.dart` displays the raw stored `weight` value with `_preferredWeightUnitLabel` ("LBS") — no conversion on the way out.
2. When the user drags up/down, `_updateMetricValue` calls `workoutState.updateEntryValue(effortId, entryIndex, 'weight', value)` — the raw display value (lbs) is passed directly, **no canonical conversion to kg**.
3. The observation is persisted with `unitId: MetricIds.unitKg` but `valueReal` = the lbs value (e.g., 100.0 for 100 lbs).
4. `SessionSummaryBuilder.buildSessionSummary()` computes `totalVolume += reps * weight` — this is now in lbs (e.g., 10 × 100 = 1000).
5. `SessionSummary.totalVolume = 1000` is assigned to `SessionGroupMetrics.totalVolumeKg`.
6. `session_summary_screen.dart` calls `_formatWeight(metrics.totalVolumeKg)` → `UnitFormatter.formatWeight(1000, settingsState)` → `1000 × 2.20462 = 2204.62 lbs` displayed.

**Expected:** 10 × 100 lbs = 1000 lbs total volume
**Actual shown:** ~2204 lbs (2.2× inflation)

For **kg users**: no visible bug — `convertWeight` is a no-op (factor = 1.0) so the error is hidden.

### Bilateral exercises: NOT a contributing cause
The `bilateral` capability flag exists in the exercise model but has no effect on the volume formula in `SessionSummaryBuilder`. Volume is summed as `reps × weight` with no bilateral multiplier. This cause can be ruled out.

### Second affected path: `_computeVolumeFromObservations` in `session_summary_service.dart`
The volume comparison (previous session delta) uses `_computeVolumeFromObservations` which applies the same `reps * weight` formula directly from raw observations. It also produces an inflated value for lbs users, meaning the delta arrow is also wrong.

---

## Requirements

- Weight observations must be stored canonically in kg at write time.
- When displaying weight in the session (active session, edit mode, post-session view), convert kg → display unit.
- `SessionSummary.totalVolume` must contain a kg value so `formatWeight(valueKg, settings)` produces the correct display.
- Fix applies to both the live-session path and the edit-mode path.
- No new db schema changes needed; this is a pure state/UI fix.

---

## Acceptance Criteria

- [ ] Total volume on session summary matches manual sum of (reps × weight) in user's display unit.
- [ ] The fix is at the calculation source (storage and/or summary calculation), not the display label.
- [ ] Fix works correctly for both `kg` and `lbs` users.
- [ ] Volume comparison delta (previous session arrow) is also correct.
- [ ] Active session weight display is unchanged for the user (still shows their preferred unit).
- [ ] Existing `services_test.dart` volume tests are reviewed — if they passed while the bug existed, update them to use real kg values.
- [ ] New unit tests cover: single-exercise kg session, single-exercise lbs session, multi-exercise session, session containing bilateral-capable exercises, volume comparison delta for lbs user.
- [ ] A regression test documents the specific failure mode (lbs stored as kg label, double-converted).

---

## Scenarios

### S-001: lbs user logs a set — volume displays correctly on summary
- Trigger: User with preferred unit = lbs logs a set (e.g. 10 reps × 100 lbs) and ends the session
- Precondition: App weight unit preference is set to lbs; one exercise with `load` capability is in the session
- Flow: User adjusts weight to 100 in `InlineMetricEditor` → `_updateMetricValue` converts 100 lbs → ~45.36 kg → stores observation as canonical kg → session ends → `SessionSummaryBuilder` computes `totalVolume = 10 × 45.36 = 453.6 kg` → summary screen calls `formatWeight(453.6, settings)` → displays "1000 lbs"
- Expected outcome: Summary shows "1000 lbs", not ~2204 lbs
- Edge case of: none

### S-002: kg user logs a set — volume is unchanged
- Trigger: User with preferred unit = kg logs a set (e.g. 10 reps × 100 kg) and ends the session
- Precondition: App weight unit preference is set to kg
- Flow: `_updateMetricValue` stores 100.0 kg directly (no conversion) → `SessionSummaryBuilder` computes `1000 kg` → `formatWeight(1000, settings)` → "1000 kg"
- Expected outcome: Summary shows "1000 kg" with no regression
- Edge case of: S-001

### S-003: lbs user — active session weight editor shows preferred unit
- Trigger: User views in-progress set with a stored 45.36 kg observation
- Precondition: Display-read path applies `UnitFormatter.convertWeight` before passing value to `InlineMetricEditor`
- Flow: `entryData['weight'] = 45.36` → `convertWeight(45.36, lbsSettings) ≈ 100.0` → editor shows "100 LBS"
- Expected outcome: Editor shows the display-unit value, not the raw canonical kg value
- Edge case of: S-001

### S-004: timed/drill extra-weight — display path uses converted value
- Trigger: User with preferred unit = lbs views a timed or drill effort with a stored extra-weight of 22.68 kg (~50 lbs)
- Precondition: `entryData['extra-weight']` contains canonical kg; display path calls `convertWeight` before rendering
- Flow: `drillExtraWeight = convertWeight(22.68, lbsSettings) ≈ 50.0` → `InlineMetricEditor` shows "50 LBS"
- Expected outcome: Editor shows ~50 LBS, not ~22.68 LBS; subsequent edits save back through `_updateMetricValue` which re-converts to kg
- Edge case of: S-001

### S-005: volume comparison delta is correct for lbs user
- Trigger: lbs user completes a second session; app computes volume delta vs. previous session
- Precondition: Both sessions have canonical-kg observations stored
- Flow: `compareToPreviousSession(current, currentVolumeKg)` → `_computeSessionVolume` reads stored canonical-kg observations → computes previous volume in kg → delta in kg
- Expected outcome: Delta reflects the kg difference; display layer converts both values to lbs before showing the arrow
- Edge case of: S-001

### S-006: regression — double-conversion must not recur
- Trigger: 100 lbs weight is stored as canonical kg (~45.36) and then displayed on summary
- Precondition: fix is in place
- Flow: `formatWeight(10 × 45.36, lbsSettings)` → "1000 lbs"
- Expected outcome: Result is ~1000 lbs, not ~2204 lbs (which would indicate the bug has regressed)
- Edge case of: S-001

---

## Implementation Plan

### Phase 1: Fix at save time — convert display→kg before persisting

**File: `lib/features/session/workout_session_screen.dart`**

In `_updateMetricValue` (around line 906), add canonical conversion for weight metrics **before** calling `workoutState.updateEntryValue`:

```dart
// Convert display-unit weight to canonical kg before persisting.
if ((metricKey == 'weight' || metricKey == 'extra-weight') &&
    value is double) {
  value = UnitFormatter.toCanonicalWeight(value, widget.settingsState);
}
```

Apply this to both the normal-mode path (the `await workoutState.updateEntryValue` call) **and** the edit-mode buffer path (the `_editBuffer[key]![metricKey] = value` assignment before the early `return`).

> ⚠️ Edit-mode buffers are later committed via `_saveEditedEntry` (or equivalent). Confirm the buffer flows through a path that also calls `updateEntryValue` — if so, a single conversion point at the top of `_updateMetricValue` (before the `if (widget.editMode)` branch) covers both.

**File: `lib/features/session/workout_session_screen.dart` — `_persistEntryValues`**

The `_persistEntryValues` method (around line 680) saves weights from `currentEntry`. At this point `currentEntry['weight']` is the **already-converted** value (it comes from the in-memory observations map which, after the above fix, will hold kg). No additional change needed here as long as `_updateMetricValue` is the single write path.

### Phase 2: Fix at read/display time — convert kg→display when building entry UI

**File: `lib/features/session/workout_session_detail_view.dart`**

In `_buildMetricEditorForEntry` (the `case 'set':` branch around line 150), convert stored kg to display units before passing to `InlineMetricEditor`:

```dart
// Stored in kg; convert to display unit for the editor.
final weight = UnitFormatter.convertWeight(
  entryData['weight'] as double? ?? 0.0,
  widget.settingsState,
);
final extraWeight = UnitFormatter.convertWeight(
  (entryData['extra-weight'] as num?)?.toDouble() ?? 0.0,
  widget.settingsState,
);
```

Also apply the same conversion to the `_buildWeightAdjustmentSection` call for `extra-weight`.

> ⚠️ In edit mode the `_editBuffer` values are also displayed via `InlineMetricEditor`. Any weight values read from `_editBuffer` for display also need `convertWeight` applied. Check whether the edit-mode branch reads `entryData` (which comes from `_editBuffer`) or from the canonical map.

### Phase 3: Verify no other weight display paths are missed

Search and confirm that these are the **only** two UI paths where `weight` from entry data is shown to the user as a measurement value:

- `workout_session_detail_view.dart` — active session inline editor (fixed above)
- Any other places that read `entry['weight']` for display (e.g., session edit history screen, `workout_session_list_view.dart` subtitle)

Quick search: `grep -r "entry\['weight'\]\|entryData\['weight'\]" lib/` to enumerate all readers.

### Phase 4: Confirm `_computeVolumeFromObservations` in `session_summary_service.dart`

After Phase 1 is in place, new observations will be stored in kg and the summary will be correct. However, for the **previous session comparison** (`_computeSessionVolume`), observations from older sessions (stored in lbs) will still be inflated. Document this as a known limitation for sessions logged before the fix.

No code change needed in `session_summary_service.dart` if Phase 1 is complete — the formula is correct, the stored values just need to be kg.

### Phase 5: Routine pre-fill / template values

Check whether template targets (`TemplateTarget.targetMin`) are also stored in display units. If the routine setup screen lets users enter a target weight in lbs and stores it without conversion, loading a routine pre-fills the session with a lbs value stored as if kg — the same double-conversion would apply when the session entry is first created.

**File: `lib/state/workout/session_core_entry.dart` — `addEntry`**

The initial `valueReal: (previousValues?['weight'] as double?) ?? 0.0` comes from the in-memory observations map. After Phase 1, in-memory weights will already be in kg (because they were saved as kg and loaded back as kg). No change needed here.

If `previousValues` is populated from a **template target** (not a previous observation), that target value needs the same canonical treatment. Trace where template targets produce `previousValues`.

### Phase 6: Tests

**File: `test/data_tracking_fixes_test.dart`** (or a new `volume_calculation_test.dart`)

Required tests:

| Test | Description |
|------|-------------|
| Single-exercise kg session | 3 sets × 10 reps × 100 kg → totalVolume = 3000.0 kg |
| Single-exercise lbs session | 3 sets × 10 reps × 100 lbs (stored as ~45.36 kg) → totalVolume ≈ 1360.8 kg; formatted as "1000 lbs" |
| Multi-exercise session | Two exercises, verify volumes are summed correctly |
| Bilateral-capable exercise | Same formula as non-bilateral (no multiplier expected) — guards against future regression |
| lbs regression test | Directly verify that storing a 100-lbs value (→ 45.36 kg) and calling `SessionGroupMetrics.totalVolumeKg` does NOT produce 2204 when formatted as lbs |
| Volume delta (previous session) | `compareToPreviousSession` returns the correct kg delta for a lbs user |

**Review `test/services_test.dart`** — existing tests around `totalVolume: 500.0` and `totalVolume: 1200` are likely testing with hard-coded summary objects and don't exercise the save/load path. They pass regardless of the bug. Update them to use real observation fixtures or at minimum add a comment explaining they're not testing the unit-conversion path.

---

## Files Affected

| File | Change |
|------|--------|
| `lib/features/session/workout_session_screen.dart` | Add `toCanonicalWeight` conversion in `_updateMetricValue` before weight is persisted |
| `lib/features/session/workout_session_detail_view.dart` | Add `convertWeight` when reading `weight` / `extra-weight` from entry data for display |
| `lib/state/workout/session_core_entry.dart` | Review only (likely no change needed) |
| `lib/core/services/session_summary_service.dart` | Review only — correct after Phase 1 lands |
| `lib/state/workout/session_summary_builder.dart` | Review only — correct after Phase 1 lands |
| `test/data_tracking_fixes_test.dart` (or new file) | New regression + unit tests for volume calculation |
| `test/services_test.dart` | Review existing volume tests; annotate or update |

---

## Notes

- The field `SessionGroupMetrics.totalVolumeKg` and the helper `_formatWeight(valueKg, ...)` on the summary screen are correctly named — the pattern already expects kg as the canonical unit. The bug is that the values stored in the observations never got converted to kg at write time.
- For sessions already logged in lbs (before this fix), `totalVolume` will still show inflated values. This is a known data quality issue for existing sessions; no migration is planned for the current Hive-backed web environment.
- The `bilateral` flag does not affect volume calculation and is not related to this bug.

---

## Progress

- [x] Add `toCanonicalWeight` conversion in `workout_session_screen.dart` `_updateMetricValue`
- [x] Add `convertWeight` for weight display in `workout_session_detail_view.dart`
- [x] Verify edit-mode buffer path is covered (single conversion point before `if (widget.editMode)` branch)
- [x] Write regression test for lbs double-conversion
- [x] Write unit tests: single-exercise kg, lbs, multi-exercise, bilateral, delta
- [x] All 6 new volume tests pass; full suite of 824 tests passes (no regressions)
- [x] Review existing volume tests in `services_test.dart` — added scope-clarifying comments explaining `currentVolume` is a pre-computed parameter and that write-path canonicalization is tested in `data_tracking_fixes_test.dart`; `previousVolume` computation from observations is exercised here with canonical kg fixtures
- [x] Add widget assertions for scenario S-004 numeric display conversion in timed/drill extra-weight editors (canonical kg storage renders correctly in lbs UI)
- [x] Add explicit `Doc Updates` status block for reviewer traceability
- [ ] Check template/routine pre-fill path for same issue (out of scope for this fix)
- [ ] Manual verification: log session in lbs, confirm summary volume is correct

### Phase Status: **Complete** (pending manual device verification)

## Doc Updates

- `.github/agents/docs/navigation_and_screens.md`: no update required (no navigation flow, route, or constructor dependency change)
- `.github/agents/docs/state_management.md`: no update required (no state API or state-class behavior contract change; conversion remains in screen layer)
- `.github/agents/docs/widget_catalog.md`: no update required (no new reusable widget or widget API change)
- `.github/agents/docs/data_models.md`: no update required (no model/schema field changes)
- `.github/agents/docs/db_integration.md`: no update required (no persistence schema or migration changes)

## Iteration 2

### Analysis

Same double-conversion root cause as Iteration 1, but in the **routine template setup screen**. `routine_setup_screen.dart` writes raw display-unit values (lbs) to `TemplateTarget.targetMin` with `unitId: MetricIds.unitKg`. When `populateFromManifest` → `updateEntryValue` uses those values to seed session observations, they land in canonical observation storage still as the raw lbs number. The session display (which now correctly applies `convertWeight` from canonical kg → display lbs) then double-converts: `35.0 × 2.20462 = 77.16 ≈ 77.2`.

Additionally, the code reviewer flagged two items from Iteration 1:
1. **Reviewer feedback #1** (Timed/Drill extra-weight display path): Current code inspection shows `UnitFormatter.convertWeight` IS already applied at all timed/drill `extra-weight` display call sites in `workout_session_detail_view.dart` (lines 264, 339, 542). The reviewer likely saw a pre-fix snapshot. Verify during implementation; if confirmed resolved, close it.
2. **Reviewer feedback #2** (`services_test.dart` volume test gaps): `test/services_test.dart` contains hard-coded `SessionSummary(totalVolume: 500.0/1200)` fixtures that passed regardless of the bug. These need annotation or update.

### Implementation Plan

#### Phase 1: Fix `routine_setup_screen.dart` save path — @developer

In `_buildMetricWidget`, for each weight metric `onValueChanged`, wrap the raw display value with `UnitFormatter.toCanonicalWeight` before passing to `setTargetValue`. `widget.settingsState` can be null (the screen accepts an optional settings); fall back to the raw value (no-op for kg) when null.

1. [ ] For `'set'` effort kind — weight `onValueChanged`:
   ```dart
   onValueChanged: (value) {
     final canonical = widget.settingsState != null
         ? UnitFormatter.toCanonicalWeight(value as double, widget.settingsState!)
         : value as double;
     widget.routineState.setTargetValue(
       effort.id, MetricIds.weight, MetricIds.unitKg,
       setIndex: setIndex, targetMin: canonical,
     );
   },
   ```
2. [ ] For `'timed'` effort kind — extra-weight `onValueChanged`: same `toCanonicalWeight` wrapping.
3. [ ] For `'drill'` effort kind — extra-weight `onValueChanged`: same wrapping.
4. [ ] Consider extracting a one-line private helper `double _toCanonical(double v) => widget.settingsState != null ? UnitFormatter.toCanonicalWeight(v, widget.settingsState!) : v;` to avoid repeating the null check three times.

#### Phase 2: Fix `routine_setup_screen.dart` display path — @developer

In `_buildMetricWidget`, when reading stored target values for weight/extra-weight display, apply `UnitFormatter.convertWeight` so the editor shows the user's preferred unit. Stored targets will (going forward) be canonical kg; apply the same null-guard pattern.

1. [ ] For `'set'` weight display — change:
   ```dart
   final weight = _getTargetDouble(targets, MetricIds.weight, setIndex);
   ```
   to:
   ```dart
   final weight = widget.settingsState != null
       ? UnitFormatter.convertWeight(
           _getTargetDouble(targets, MetricIds.weight, setIndex),
           widget.settingsState!)
       : _getTargetDouble(targets, MetricIds.weight, setIndex);
   ```
   (or use the private helper if added: `_fromCanonical(_getTargetDouble(...))`)
2. [ ] For `'timed'` extra-weight display: same `convertWeight` wrapping on `timedExtraWeight`.
3. [ ] For `'drill'` extra-weight display: same on `extraWeight`.

> ⚠️ Note on existing data: Routines created before this fix have `targetMin` stored in raw lbs. After the fix, those values will appear as `35 lbs → convertWeight(35.0, lbs) = 77.2 LBS` in the routine editor (the reverse problem). For in-progress development with Hive-backed storage, advise users to re-enter weights in affected routines. A data migration is out of scope for this iteration.

#### Phase 3: Verify session detail view timed/drill extra-weight — @developer

1. [ ] Confirm `workout_session_detail_view.dart` already applies `convertWeight` at all `extra-weight` display call sites:
   - Line ~264: timed edit mode `_buildWeightAdjustmentSection(currentValue: UnitFormatter.convertWeight(...))`
   - Line ~339: timed non-edit mode same call
   - Line ~542: drill `drillExtraWeight = UnitFormatter.convertWeight(...)`
2. [ ] If all three confirmed correct → close reviewer feedback #1 as resolved.
3. [ ] If any are missing → apply `convertWeight` at the missing site.

#### Phase 4: `services_test.dart` volume test coverage — @developer

1. [ ] Open `test/services_test.dart`; locate fixtures using `SessionSummary(totalVolume: 500.0)` and `SessionSummary(totalVolume: 1200)`.
2. [ ] Add inline comments clarifying these test pre-computed `SessionSummary` inputs (not the write-path), so future reviewers don't mistake passing tests for canonicalization coverage.
3. [ ] Optionally add one fixture-based test that constructs a `SessionSummary` via `SessionSummaryBuilder` from canonical-kg observations, confirming the output `totalVolumeKg` is correct.

#### Phase 5: Tests — @developer

| Test | Expected behaviour |
|------|--------------------|
| Routine target save — lbs user sets 35 lbs | `target.targetMin ≈ 15.88 kg` (not 35.0) |
| Routine target display — stored 15.88 kg loaded for lbs user | Editor shows ≈ 35 lbs |
| Round-trip: 35 lbs set → `populateFromManifest` → session display | Session shows ≈ 35 lbs (not 77.2) |
| kg user round-trip: 100 kg set → session display | Session shows 100 kg, no loss |
| Regression: raw-lbs value 35.0 stored as observation → `convertWeight(35.0, lbs)` = 77.2 (documents the old bug) | — |

### Acceptance Criteria

- [ ] Setting 35 lbs in a routine and starting that routine shows 35 lbs in the session (not 77.2).
- [ ] Setting 100 kg in a routine and starting it shows 100 kg — no regression for kg users.
- [ ] Routine weight editor displays the correct display-unit value when re-opening the routine (not the raw kg value).
- [ ] All 5 new tests from Phase 5 pass.
- [ ] Reviewer feedback #1 (timed/drill detail view) is confirmed resolved or fixed.
- [ ] Reviewer feedback #2 (`services_test.dart`) is annotated/updated.
- [ ] Full test suite passes with no regressions.

### Files Affected

| File | Change |
|------|--------|
| `lib/features/routine/routine_setup_screen.dart` | Add `toCanonicalWeight` on save; add `convertWeight` on display for weight/extra-weight |
| `lib/features/session/workout_session_detail_view.dart` | Verify timed/drill extra-weight display paths (may be no-op) |
| `test/services_test.dart` | Annotate existing volume fixtures |
| `test/data_tracking_fixes_test.dart` or new test file | New routine round-trip unit tests |

### Known Limitation

Existing routines created before this fix (with raw lbs values in `targetMin`) will display inflated weights in the routine editor after Phase 2 lands. Users must re-enter weight targets. No automated data migration is planned for the current Hive-backed development environment.

---

## Progress (Iteration 2)

- [x] Add `toCanonicalWeight` conversion to all weight `onValueChanged` callbacks in `routine_setup_screen.dart`
- [x] Add `convertWeight` display conversion for all weight/extra-weight targets in `routine_setup_screen.dart`
- [x] Extract `_toCanonicalWeight` / `_fromCanonicalWeight` private helpers to avoid repeating null-guard
- [x] Verify timed/drill extra-weight display in `workout_session_detail_view.dart` — confirmed all 3 call sites already apply `convertWeight` (reviewer feedback #1 resolved)
- [x] Annotate/update `services_test.dart` volume fixtures (reviewer feedback #2 resolved — 4 fixtures now have scope-clarifying comments)
- [x] Write 4 new routine round-trip tests in `data_tracking_fixes_test.dart` (lbs round-trip, kg no-regression, regression guard, conversion losslessness)
- [x] Full test suite passes: 830 tests, 0 failures
- [x] Add dedicated widget regression test for S-003 set-weight display conversion (canonical kg -> lbs)
- [x] Remove stale trailing reviewer notes from this plan file

### Phase Status: **Complete** (pending manual device verification)

## Doc Updates (Iteration 2)

- `docs/navigation_and_screens.md`: no update required
- `docs/state_management.md`: no update required
- `docs/widget_catalog.md`: no update required
- `docs/data_models.md`: no update required
- `docs/db_integration.md`: no update required


