# Plan 93 — evidence

## Phase 1 (2026-11-01, @developer)

### Baseline (before any edit)

`bash .claude/scripts/macos/with-timeout.sh 900 swift test --package-path watch/watchos`
→ `Executed 1140 tests, with 0 failures (0 unexpected)`, exit 0.
`WatchHandDistanceTests.swift` held **14** tests (`grep -c "func test"`), not 13 as the plan's D-9 table says.

### Red on base (new tests written, `WatchLoggingState.swift` untouched)

`swift test --package-path watch/watchos --filter WatchGpsDistanceTileTests` → exit 1,
`Executed 12 tests, with 23 failures (0 unexpected)`.

| Test | Base result | Why (observed message) |
|---|---|---|
| S-16001 | red | `fields` `["distance"]` ≠ `[]` (both variants); `armedMetricKey` `"distance"` |
| S-16002 | red | `["distance"]` ≠ `[]` |
| S-16003 | red | `["distance"]` ≠ `[]` at Start and at T0+1500 |
| S-16004 | red | `["distance"]` ≠ `[]` |
| S-16005 | red | `["distance"]` ≠ `[]`; log carried `2900.0` / `"entered"` |
| S-16006 | red | before the fix: `["distance"]` ≠ `[]` (tile before movement) |
| S-16007 | red | `["distance"]` ≠ `[]` before and right after effort 2's Start |
| S-16008 | green | pins unchanged behaviour (no distance capability) |
| S-16009 | green | pins unchanged behaviour (hold, period) |
| S-16010 | green | the measured tile's unit display was already right on base |
| S-16012 | red | `["distance"]` ≠ `[]` throughout; log carried `900.0` / `"entered"` |
| S-16013 | red | hit `WatchLoggingState.swift:1096` |

### Green after Phase 1

- `--filter WatchGpsDistanceTileTests` → `Executed 12 tests, with 0 failures (0 unexpected)`, exit 0.
- `--filter 'WatchLoggingSurfacesTests|WatchSensorRecordingTests|WatchCrownArmingTests|WatchCaptureContractTests|WatchLoggingStatusTests|WatchTimedWorkTests|WatchBodyweightLoadTests|WatchEffortDistanceTests|WatchGpsByExerciseTests|WatchDialledPerExerciseTests|SyncProtocolFixturesTests'`
  → `Executed 163 tests, with 0 failures (0 unexpected)`, exit 0 (S-16014's `SyncProtocolFixturesTests` included).
- Full `swift test --package-path watch/watchos` → `Executed 1138 tests, with 0 failures (0 unexpected)`, exit 0
  (1140 − 14 deleted + 12 new = 1138). `WatchSessionEngineTests.testS004NoMutatingOperationExistsAnywhereInTheModule`
  (append-only guard) passed; `WatchLoggingStatusTests.testS7514…` view scan passed. Re-run after the mutation pass: same count, 0 failures.
- `flutter test test/distance_source_import_test.dart test/session_summary_distance_test.dart test/ui_standards_contract_test.dart test/docs_indexing_contract_test.dart`
  → `+81: All tests passed!`, exit 0.
- Greps: `grep -rn '"entered"' watch/watchos/Sources` (excluding `.build`) empty; `grep -rn "plan 65\|WatchHandDistanceTests\|testS9503" watch/watchos docs/state_management` (excluding `.build`) empty; hive import sweep empty; `wc -c docs/state_management/watch_surface_wrist.md` = 52209 (≤ 52233).

### Mutations (each applied alone, `--filter WatchGpsDistanceTileTests`, then the exact original restored and checked with `cmp`)

| Id | Original line | Mutant | Red tests | Plan predicted |
|---|---|---|---|---|
| M1 | `return windowDistanceMeters()` (measuredValue) | `return readings.distanceMeters ?? 0` | S-16006, S-16007 | S-16007 ✓ |
| M2 | `&& windowDistanceMeters() > 0` (isMeasured) | `&& true` | S-16001..S-16004, S-16006, S-16007 | S-16003, S-16004 ✓ |
| M3 | `var previous = cumulativeMeters(at: start)` | `var previous = 0.0` | S-16004, S-16006, S-16007 | S-16003, S-16006 — S-16003 stays green: its window holds no sample, so the baseline cannot matter there; killed by S-16004/6/7 |
| M4 | `if covered > 0 {` (windowPayload) | `if covered >= 0 {` | S-16002..S-16005, S-16012 | S-16004 ✓ |
| M5a | `WatchEffortKind.drill: [WatchMetricKey.extraWeight],` | `+ WatchMetricKey.distance` | S-16009 | S-16009 ✓ |
| M5b | `WatchEffortKind.round: [WatchMetricKey.roundDuration],` | `+ WatchMetricKey.distance` | none — equivalent mutant: a period has no work clock before Start (window 0, D-1 filter drops it) and `fields` is `[]` while it runs (D-3404) | — |
| M6 | `let converted = value / WatchMetricStepping.metresPerUnit(units.distanceUnit)` (displayValue) | `value / 1000` | S-16010 | S-16010 ✓ |
| M7 | `if metricKey == WatchMetricKey.distance, !isMeasured(metricKey) { return false }` | `if metricKey == WatchMetricKey.distance { return false }` | S-16006, S-16007, S-16010 | S-16006 ✓ |
| M8 | same line | line removed | S-16001..S-16007, S-16012 | S-16001 ✓ |
| M9 | `guard let timer = workTimer else { return 0 }` (windowDistanceMeters) | `workTimer ?? engine.timerFor(WatchTimerKind.elapsed)` | S-16007 | S-16007 ✓ |
| M10 | `let open = state.fields.filter { !$0.isMeasured }` (`WatchLoggingModel.armedMetricKey`) | `let open = state.fields` | S-16006 | S-16006 ✓ |
| M11 | closing `}` of `if covered > 0` | `} else if let entered = dialled[…]?[distance], entered > 0 { …"entered" }` | S-16013 | S-16013 ✓ |

M12 (− / + around a measured tile) belongs to Phase 2.
