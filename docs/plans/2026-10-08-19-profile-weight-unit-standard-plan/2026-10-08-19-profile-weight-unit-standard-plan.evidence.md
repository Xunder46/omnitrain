# Evidence — Profile weight quick chart honours the weight-unit preference

Plan: `docs/plans/2026-10-08-19-profile-weight-unit-standard-plan/2026-10-08-19-profile-weight-unit-standard-plan.md`

## Baselines

- `flutter analyze`: **199** issues before the change (all pre-existing info
  notices), **196** after (my file contributes zero). No new lint introduced.
- `.github/copilot/scripts/macos/gateway.sh test` (full suite): **4226 passed,
  1 skipped, 0 failed** (2 min 12 s).

## Red → Green

Command: `.github/copilot/scripts/macos/gateway.sh prove-red HEAD test test/profile_measurement_sparkline_unit_test.dart -- test/profile_measurement_sparkline_unit_test.dart`

Ran the new test file against the **unfixed** source at HEAD:

| Scenario | At HEAD (unfixed) | With the fix |
|---|---|---|
| S-1 (lbs labels) | FAIL — `Expected '198.4'`, `Actual '90.0'` (raw kg plotted) | PASS |
| S-2 (kg labels) | FAIL — `Expected '90'`, `Actual '90.0'` (old `toStringAsFixed(1)` format) | PASS |
| S-4 (non-weight) | FAIL — `Expected contains '20'`, `Actual ['20.0']` (old format) | PASS |

`prove-red` reported `RED AT HEAD (exit 1)` and each failure was an **assertion**
failure, not a compile/load error — so the guard is proven.

Fix run: `.github/copilot/scripts/macos/gateway.sh test test/profile_measurement_sparkline_unit_test.dart`
→ `00:00 +3: All tests passed!`

## Affected existing suites

- `test/header_standardization_test.dart` (sparkline Phase 4 scenarios S-013,
  S-014, S-014b, S-014c, S-019) — **5 assertions updated** from `'80.0'`/`'82.0'`/
  `'79.0'` to `'80'`/`'82'`/`'79'` to match the D-3 format. Their intent (label
  positions, count, `minV == maxV` both-labels, painter presence) is unchanged.
  Final: **106 passed** (with `profile_screen_test.dart` and
  `profile_cleanup_test.dart`).
- `test/docs_indexing_contract_test.dart` — **9 passed**.

## Phase 2 sweep — raw-weight chart plots

`grep -rn "entry.value\|\.value\.value\|point\.value" lib/features/profile lib/features/stats lib/widgets/chart`

| Hit | Verdict |
|---|---|
| `measurement_sparkline.dart` `_toChartValue` | Converted (this fix) |
| `measurement_history_chart_sheet.dart:420,427` | Already converts (`UnitFormatter.convertWeight`) |
| `stats/exercise_progress_screen.dart:205,381` | Converts via `nativeMetricDisplayValue` / `formatNativeValue` → `UnitFormatter` |
| `stats/widgets/instrument_sparkline.dart:32` | **Exempt** — shape-only sparkline, no numeric labels |
| `stats/widgets/native_value_format.dart:47` | Converts (`formatNativeMetric`) |

Conclusion: `MeasurementSparkline` was the only unit-blind chart.

## Footprint

Tracked diff (surgical):

```
 docs/global_conventions.md                        |  2 +-
 docs/profile_and_measurements.md                  |  5 +++++
 test/header_standardization_test.dart             | 18 ++++++++--------
 test/profile_measurement_sparkline_unit_test.dart | 26 ++++++++++++--------
```

`lib/features/profile/widgets/measurement_sparkline.dart` (staged vs HEAD):
import + stale-doc fix + `_toChartValue` helper + `values` param through the
painter + label format. No call-site change (`settingsState` was already
injected).

## Mutation note

The red→green above **is** the mutation evidence: HEAD is the source with the fix
absent, and the guard went red there for the assertion reason it targets. No
manual line mutation was needed.
