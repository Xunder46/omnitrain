# Evidence — Cardio Efficiency Drift (Stats PR 9b)

> Companion to `2026-10-04-09b-stats-pr9b-cardio-efficiency-drift-plan.md`. Implementers write
> here; nothing from this file goes into the plan. One section per phase, filled as the phase runs.

## Opening baselines (measure before Phase 1, on the branch)

| Command | Result |
|---|---|
| `flutter analyze` | _to fill_ (expected: `196 issues found.`, 0 errors — plus whatever PR 9a added) |
| `flutter test` | _to fill_ (expected: `+3731 ~1: All tests passed!`, plus 9a's new suites if landed) |
| `docs/signals.md` bytes | _to fill_ (34,099 before this PR) |

Known and untouched: `test/food_photo_clear_legacy_edit_test.dart` is order-dependent in a full run
and passes on re-run.

## Phase 1 — the pure rule

| Check | Command | Result |
|---|---|---|
| red run | `flutter test test/cardio_efficiency_drift_test.dart` | _to fill_ (must fail: file not found / does not compile) |
| green | `flutter analyze` | _to fill_ |
| green | `flutter test test/cardio_efficiency_drift_test.dart test/training_load_test.dart` | _to fill_ |
| full | `flutter test` | _to fill_ |

### Mutation checks

| # | Mutation | Test that must fail | Result |
|---|---|---|---|
| 1 | drift test `<=` → `<` (strict) | S-2502 (exactly 5%) | _to fill_ |
| 2 | group member compared with the previous member instead of the anchor | S-2506 (529 s merges into the 480 s group) | _to fill_ |

## Phase 2 — the service read

| Check | Command | Result |
|---|---|---|
| red run | `flutter test test/cardio_efficiency_service_test.dart` | _to fill_ |
| green | `flutter test test/cardio_efficiency_service_test.dart test/stats_progress_test.dart test/mix_layer_service_test.dart test/modality_mix_period_service_test.dart test/distance_source_test.dart` | _to fill_ |
| full | `flutter test` | _to fill_ |

### Mutation checks

| # | Mutation | Test that must fail | Result |
|---|---|---|---|
| 3 | drop `!DistanceSource.isEstimated(...)` | S-2504 (the estimated effort becomes eligible) | _to fill_ |
| 4 | read the heart rate from the session-scope summary | S-2505 (third variant) | _to fill_ |

## Phase 3A — the card, the registry, the guards

| Check | Command | Result |
|---|---|---|
| red run | `flutter test test/cardio_efficiency_drift_signal_screen_test.dart --plain-name "Mock"` | _to fill_ |
| green | same, Mock-first | _to fill_ |
| guards | `flutter test test/interference_test.dart test/modality_mix_shift_signal_screen_test.dart` | _to fill_ |
| full | `flutter test` | _to fill_ |

### Mutation checks

| # | Mutation | Test that must fail | Result |
|---|---|---|---|
| 5 | registry entry moved to the end | both registry guards | _to fill_ |
| 6 | `liftMeasure: MixMeasure.load` passed unconditionally | S-2509 (the time-measure variant gains a sentence) | _to fill_ |

## Phase 3B — guards, residue, docs

| Check | Command | Result |
|---|---|---|
| green | `flutter test test/docs_indexing_contract_test.dart` | _to fill_ |
| size | `docs/signals.md` byte count after the edit (must stay below 52,428) | _to fill_ |
| full | `flutter test` | _to fill_ |

### Residue sweep

| Sweep | Result |
|---|---|
| `cardio_efficiency_drift.dart` imports | _to fill_ (must be `training_load.dart`, `signals.dart` only) |
| `cardioEfficiencyDrift` / `cardioEfforts` mentioned outside the three production files | _to fill_ (must be tests and docs only) |
| `DistancePairing.forEntries` callers in `stats_progress_service.dart` | _to fill_ (one added, no second pairing introduced) |
| literal `nutritionTrend` in `stats_progress_service.dart` | _to fill_ (must be absent — `S-1263`) |

## Doc-claim-to-test table

Every behavioural sentence added to `docs/` in Phase 3B, with the test that proves it. A sentence
with no test is deleted, not kept.

| Doc | Claim | Test |
|---|---|---|
| `docs/signals.md` | _to fill_ | _to fill_ |
| `docs/stats_screen.md` | _to fill_ | _to fill_ |
| `docs/constants_reference.md` | _to fill_ | _to fill_ |
| `docs/state_management/services_and_utils.md` | _to fill_ | _to fill_ |
| `docs/distance_source.md` | _to fill_ | _to fill_ |
| `docs/training_load.md` (only if edited) | _to fill_ | _to fill_ |

## Closing

| Check | Result |
|---|---|
| `flutter analyze` | _to fill_ |
| full `flutter test` | _to fill_ |
| diff vs Predicted Files | _to fill_ |
