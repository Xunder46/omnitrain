# Evidence — Cardio Efficiency Drift (Stats PR 9b)

> Companion to `2026-10-04-09b-stats-pr9b-cardio-efficiency-drift-plan.md`. Implementers write
> here; nothing from this file goes into the plan. One section per phase, filled as the phase runs.

## Opening baselines (measure before Phase 1, on the branch)

| Command | Result |
|---|---|
| `flutter analyze` | `196 issues found. (ran in 7.2s)` — 0 errors. Taken on the branch with the two new files present; neither file name appears in the output, so the count is the pre-phase baseline. |
| `flutter test` | `05:08 +3789 ~1: All tests passed!` — 14 of those are this phase's new tests, so the pre-phase count was 3775. |
| `docs/signals.md` bytes | 34,099 (the plan's recorded baseline; Phase 1 touches no docs, so it is unchanged). The gateway-only tool set in this session has no byte-count command, so this figure is carried from the plan rather than re-measured. |

Known and untouched: `test/food_photo_clear_legacy_edit_test.dart` is order-dependent in a full run
and passes on re-run. (It passed in the run above.)

## Phase 1 — the pure rule

| Check | Command | Result |
|---|---|---|
| red run | `flutter test test/cardio_efficiency_drift_test.dart` | `00:00 +0 -1: Some tests failed.` — compile failure: `Error: 'with' can't be used as an identifier because it's a keyword.` plus `Method not found` / `isn't a type` for every rule symbol, since `lib/core/models/cardio_efficiency_drift.dart` did not exist. |
| green | `flutter analyze` | `196 issues found. (ran in 7.2s)` — 0 errors, no issue in either new file. |
| green | `flutter test test/cardio_efficiency_drift_test.dart test/training_load_test.dart` | `00:00 +64: All tests passed!` (14 new + 50 neighbours; the new suite alone is `00:00 +14: All tests passed!`). |
| full | `flutter test` | `05:08 +3789 ~1: All tests passed!` |

### Mutation checks

| # | Mutation | Test that must fail | Result |
|---|---|---|---|
| 1 | drift test `<=` → `<` (strict): guard `recentMean * 100 > referenceMean * (100 - k)` → `>=` | S-2502 (exactly 5%) | PASS — `00:00 +0 -1: S-2502 the 5% boundary is inclusive [E] Expected: not null / Actual: <null>`. Reverted. |
| 2 | group member compared with the previous member instead of the anchor (`anchor.durationSecs` → `list[j - 1].durationSecs`) | S-2506 (529 s merges into the 480 s group) | PASS, after a fixture gap was closed. S-2506 B and C did **not** catch it — neither has a bridging duration, so 529 s is rejected against the previous member too. S-2506 D was added (480 s + 500 s + 529 s, where 480→500 and 500→529 are each within 10% but 480→529 is not); with the mutation it failed with `Expected: [480, 529] / Actual: [480]`. Reverted. |

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
