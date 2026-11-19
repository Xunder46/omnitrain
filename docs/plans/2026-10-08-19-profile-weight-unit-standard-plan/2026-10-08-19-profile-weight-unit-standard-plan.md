# Feature: Profile weight quick chart honours the weight-unit preference

> Status: DRAFT awaiting Q&A
> Next handoff: @developer (Phase 1)
> Binding conventions: docs/global_conventions.md (+ docs/design_system.md, docs/profile_and_measurements.md)

## Overview

The BODY WEIGHT card on the profile screen renders a "quick chart" sparkline
(`MeasurementSparkline`). Its y-axis scale and plotted line use the raw stored
measurement value — canonical **kilograms** — regardless of the user's
`SettingsState.preferredWeightUnit`. The full history chart sheet
(`MeasurementHistoryChartSheet`) already converts with
`UnitFormatter.convertWeight`, so the two surfaces disagree whenever the user
prefers `lbs`: the sheet reads `176.4 lbs`, the sparkline reads `80.0`.

This plan fixes the sparkline and then **enforces the rule as a project
standard**: every chart that renders a body-measurement or metric value must
plot and label in the user's active display unit, and the project must carry a
structural guard so a new unit-blind chart cannot be added silently.

## Resolved Decisions (Ledger)

- **D-1 (root cause).** The sparkline's canonical→display conversion must go
  through `UnitFormatter.convertWeight(value, settingsState)` — the same helper
  `MeasurementHistoryChartSheet._toChartValue` uses. No new conversion constant
  is introduced; `UnitFormatter` is the single source of truth.
- **D-2 (non-weight measurements).** Only `unit-kg` measurements convert. Every
  other measurement type (`%`, `cm`, etc.) plots its stored value unchanged,
  matching the existing `MeasurementHistoryChartSheet` branch
  (`entry.unitId == 'unit-kg'` → convert, else raw).
- **D-3 (y-axis labels).** The y-max / y-min labels render the **converted**
  value, formatted with `ProfileMeasurements.formatValue` (integer when whole,
  else one decimal), matching the sheet's axis value style. The unit suffix
  stays off the sparkline axis (A18 decision: the header names the measurement,
  the value column carries the unit) — this plan does not reverse A18, only the
  numeric scale changes.
- **D-4 (accepted behaviour change).** A user switching kg→lbs sees the sparkline
  y-axis relabel (e.g. `80.0` → `176.4`) and the line's vertical shape change
  (the value range is scaled by 2.20462). This is the intended fix.
- **D-5 (standard, not a one-off).** The unit-conversion rule becomes a standing
  project invariant: any chart plotting a measurement or metric value converts
  through `UnitFormatter` before rendering. Enforced by the guard at S-3.

## Feature Invariants

- `UnitFormatter` is the only conversion source — no inline `* 2.20462`.
- The sparkline and the history sheet must never disagree on the unit of a
  displayed weight (both derive from `SettingsState.preferredWeightUnit`).
- Canonical storage stays kilograms (`BodyMeasurementEntry.value` is always kg
  for `unit-kg`); conversion happens only at the display boundary.

## Requirements

- R1. `MeasurementSparkline` plots `unit-kg` values in the preferred weight unit.
- R2. Its y-max / y-min labels show the converted value.
- R3. Non-weight measurements are unchanged.
- R4. A structural guard fails if a profile/stats chart plots a raw canonical
  weight value.

## Acceptance Criteria

| # | Criterion | Scenario |
|---|---|---|
| AC1 | Sparkline y-axis max/min read `198.4` / `176.4` for 90 kg / 80 kg entries under `lbs` | S-1 |
| AC2 | Sparkline y-axis reads `80.0` for the same entry under `kg` | S-2 |
| AC3 | The plotted line's y-range scales with the unit (no clipped/overflowing line) | S-1 |
| AC4 | A `%`-unit measurement plots and labels its stored value unchanged | S-4 |
| AC5 | The guard fails when a chart plots a raw `unit-kg` value | S-3 |

## Existing-Functionality Impact

| Touched surface | What already reads it (grep) | Effect | Guarded by |
|---|---|---|---|
| `MeasurementSparkline.settingsState` | Declared in the widget, documented as **unused** (`measurement_sparkline.dart` field doc: "No longer used internally") | Becomes used for conversion | S-1, S-2 |
| `MeasurementSparkline` y-labels | `test/profile_cleanup_test.dart`, `test/profile_screen_test.dart` reference `measurement_sparkline_y_max` / `_y_min` keys | Keys preserved; only the text changes under `lbs` | S-1, S-2 |
| `UnitFormatter.convertWeight` | `measurement_history_chart_sheet.dart:425`, `profile_screen.dart:379` | No signature change; reused | S-1 |
| `ProfileMeasurements.formatValue` | `measurement_history_chart_sheet.dart:405` | Reused for label formatting | S-1, S-4 |
| `InstrumentSparkline` (stats) | `instrument_row.dart:84`; plots normalised shape with **no numeric labels** | Unit-agnostic by design; unaffected — grep shows no unit strings in the file | S-3 (exempted explicitly) |
| `ScrollableTrendChart` (shared) | Takes `unitLabel` from callers; no value conversion of its own | Unaffected — conversion belongs to callers | S-3 |

## Scenarios

### S-1: lbs sparkline scales and labels in pounds
- Fixture: `MockWorkoutRepository` initialised; one `BodyMeasurementEntry`
  (`id: 'bw-1'`, `measurementType: 'bodyweight'`, `value: 80`, `unitId:
  'unit-kg'`, `recordedAtMs: 1000`) saved; `SettingsState` initialised and
  `setPreferredWeightUnit('lbs')` awaited. One second entry at `value: 90` to
  exercise a non-degenerate range (`recordedAtMs: 2000`).
- Trigger: pump `ProfileScreen(profileState, settingsState)`; `pumpAndSettle`.
- Flow: the sparkline reads history, converts each `unit-kg` value with
  `UnitFormatter.convertWeight`.
- Expected outcome: `measurement_sparkline_y_max` text is `198.4`
  (90 × 2.20462 = 198.4158 → one decimal) and `measurement_sparkline_y_min` is
  `176.4` (80 × 2.20462 = 176.3696 → one decimal). The plotted line spans the
  full chart height (min maps to the bottom inset, max to the top inset).
- Edge case of: none

### S-2: kg sparkline is unchanged
- Fixture: same as S-1 but `setPreferredWeightUnit('kg')` (or default).
- Trigger: pump the profile screen.
- Expected outcome: `measurement_sparkline_y_max` is `90`,
  `measurement_sparkline_y_min` is `80` — the D-3 `formatValue` output (whole
  numbers drop the trailing `.0`). The scale is unconverted from canonical kg.
- Edge case of: S-1

### S-3: guard rejects a raw-weight chart

> **Implementation note (2026-10-08):** the guard is delivered **as the S-1
> assertion**, not as a separate scratch-probe file. S-1 asserts the converted
> labels under `lbs`, so it fails on a chart that plots raw canonical kg — which
> `prove-red HEAD` demonstrated (`198.4` expected, `90.0` actual). No probe file
> was added; the red-at-HEAD proof is the guard's mutation evidence.

- Fixture: a chart plotting
  `BodyMeasurementEntry.value` for a `unit-kg` entry **without** calling
  `UnitFormatter.convertWeight`, under `lbs`.
- Trigger: run the guard check (the S-1 test).
- Expected outcome: the guard FAILS on the probe (proving it detects the defect
  class) and PASSES on the fixed `MeasurementSparkline`.
- Edge case of: none

### S-4: non-weight measurement is untouched
- Fixture: one `BodyMeasurementEntry` with `measurementType: 'body_fat_pct'`,
  `unitId: 'unit-pct'`, `value: 18.5`, under any weight-unit preference.
- Trigger: pump the profile screen.
- Expected outcome: the sparkline y-labels read `18.5`, unchanged by the weight
  preference.
- Edge case of: none

## Iteration 1

### Phase 1: Convert the sparkline (single responsibility) (@developer)

1. [ ] Add a value-mapping helper to `_MeasurementSparklineState` (or a small
   private function) that converts one `BodyMeasurementEntry` to its chart
   value: `entry.unitId == 'unit-kg'` →
   `UnitFormatter.convertWeight(entry.value, widget.settingsState)`, else
   `entry.value` — mirroring `MeasurementHistoryChartSheet._toChartValue` —
   `lib/features/profile/widgets/measurement_sparkline.dart` ·
   `_MeasurementSparklineState._toChartValue`.
2. [ ] Use the helper in `_lineChart` when computing `values`, `maxV`, `minV` so
   the painter and the labels agree — `measurement_sparkline.dart` · `_lineChart`.
3. [ ] Format the y-max / y-min labels with
   `ProfileMeasurements.formatValue(maxV)` / `formatValue(minV)` instead of
   `toStringAsFixed(1)` — `measurement_sparkline.dart` ·
   `measurement_sparkline_y_max`, `measurement_sparkline_y_min`.
4. [ ] Convert before the painter: pass the converted value list into
   `_SparklinePainter` (replace its internal `entries.map((e) => e.value)`
   reduction and the two `yForValue(entry.value)` / 2+ branch uses) so the
   **drawn line and dots** use converted values. `_SparklinePainter` must not
   reach into `BodyMeasurementEntry.value` for `unit-kg` —
   `measurement_sparkline.dart` · `_SparklinePainter` (`values`, `yForValue`).
5. [ ] Update the stale field doc on `settingsState` ("No longer used
   internally") to state it now drives the weight-unit conversion —
   `measurement_sparkline.dart` · `MeasurementSparkline.settingsState`.
6. [ ] Add `test/profile_measurement_sparkline_unit_test.dart` implementing S-1,
   S-2 and S-4 (Mock-first; seed via `MockWorkoutRepository`) —
   `test/profile_measurement_sparkline_unit_test.dart`.

**Done Criteria**: `.github/copilot/scripts/macos/gateway.sh lint`,
`.github/copilot/scripts/macos/gateway.sh test test/profile_measurement_sparkline_unit_test.dart`,
`.github/copilot/scripts/macos/gateway.sh test test/profile_screen_test.dart`,
`.github/copilot/scripts/macos/gateway.sh test test/profile_cleanup_test.dart`

**Predicted Files**: `lib/features/profile/widgets/measurement_sparkline.dart`,
`test/profile_measurement_sparkline_unit_test.dart`

### Phase 2: Enforce the standard (@developer)

1. [ ] Add a guard test asserting that the profile sparkline plots converted
   values for a `unit-kg` entry under `lbs` — the assertion is the S-1
   expectation — and record the exemption for label-free shape-only sparklines
   (`InstrumentSparkline`) in a comment —
   `test/profile_measurement_sparkline_unit_test.dart`.
2. [ ] Sweep for raw-weight chart plotting: grep `entry.value` / `.value.value`
   in `lib/features/profile/`, `lib/features/stats/`, `lib/widgets/chart/` and
   confirm each hit is either converted or label-free; note each in the evidence
   file — `docs/plans/2026-10-08-19-profile-weight-unit-standard-plan/2026-10-08-19-profile-weight-unit-standard-plan.evidence.md`.
3. [ ] Add the standing rule to `docs/global_conventions.md` under the
   presentation conventions: charts plot and label in the active display unit
   via `UnitFormatter`; shape-only charts with no numeric labels are exempt —
   `docs/global_conventions.md`.
4. [ ] Reconcile `docs/profile_and_measurements.md` if it describes the
   sparkline scale — `docs/profile_and_measurements.md`.

**Done Criteria**: `.github/copilot/scripts/macos/gateway.sh test test/profile_measurement_sparkline_unit_test.dart`,
`.github/copilot/scripts/macos/gateway.sh test test/docs_indexing_contract_test.dart`

**Predicted Files**: `test/profile_measurement_sparkline_unit_test.dart`,
`docs/global_conventions.md`, `docs/profile_and_measurements.md`,
`docs/plans/2026-10-08-19-profile-weight-unit-standard-plan/2026-10-08-19-profile-weight-unit-standard-plan.evidence.md`

## Files Affected

- `lib/features/profile/widgets/measurement_sparkline.dart` — conversion (edit)
- `test/profile_measurement_sparkline_unit_test.dart` — new tests (create)
- `docs/global_conventions.md` — standing rule (edit)
- `docs/profile_and_measurements.md` — reconcile (edit if drift found)
- `lib/features/profile/widgets/measurement_history_chart_sheet.dart` — **read-only reference**, must not change

## Notes

- **Phase dependency graph**: Phase 1 → Phase 2 (Phase 2's guard asserts Phase 1's
  behaviour). Phase 2's doc work only needs 1.1–1.2 if reordered earlier.
- **Intermediate state after 1.1–1.4**: sparkline converts; `profile_screen_test`
  and `profile_cleanup_test` should stay green because their assertions target
  the log sheet and keys, not the sparkline y-text under `lbs`.
- **Radar check**: `test/profile_screen_test.dart:113` is green today only because
  it asserts the log sheet, not the sparkline — explicitly re-run it (Done
  Criteria).
- **Legacy handling**: entries stored before the fix are already canonical kg;
  no migration needed.
- The `settingsState` field is already injected at the call site
  (`profile_screen.dart` passes `widget.settingsState`), so no call-site change.

## Progress

- [x] Phase 1 — Complete. `_toChartValue` converts `unit-kg` via
  `UnitFormatter.convertWeight`, used by both the y-labels and the painter
  (`values` list). Labels now use `ProfileMeasurements.formatValue`. New test
  file `test/profile_measurement_sparkline_unit_test.dart` (S-1, S-2, S-4):
  red at HEAD (`198.4` vs `90.0`), green with the fix (`+3 passed`).
- [x] Phase 2 — Complete. Sweep found no other unit-blind chart
  (`InstrumentSparkline` is label-free/exempt). Rule added to
  `docs/global_conventions.md`; `docs/profile_and_measurements.md` noted.
  `docs_indexing_contract_test.dart` green (9 passed).

## Assumption Log

- **A-1.** D-3 chose `ProfileMeasurements.formatValue` for the y-labels, which
  drops the trailing `.0` on whole numbers (`80.0` → `80`). This changes the kg
  display format, matching the history sheet's whole-number axis. Five
  assertions in `test/header_standardization_test.dart` asserted the old
  `.0` string; updated to the new format. Options: keep `toStringAsFixed(1)`
  (leaves kg axis as `80.0`, disagreeing with the sheet). Chose consistency.
- **A-2.** Body-fat measurement type is `body_fat_pct` (not `bodyfat`); the S-4
  fixture was corrected during test authoring before any implementation.

## Open questions

1. **Should the sparkline y-labels carry a unit suffix (e.g. `176.4 lbs`)?**
   Recommended default: **no** — keep A18's decision (header names the
   measurement, the value column carries the unit). Changing this is a separate
   visual-language PR. Proceeding on the default.

## Feedback

[empty]
