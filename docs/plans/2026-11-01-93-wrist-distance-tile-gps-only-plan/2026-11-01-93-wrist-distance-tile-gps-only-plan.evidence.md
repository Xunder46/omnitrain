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

## Phase 2 (2026-11-01, @developer)

### Red on base (S-16011 written, `WatchLoggingView.swift` untouched)

`swift test --package-path watch/watchos --filter WatchGpsDistanceTileTests` →
`Executed 13 tests, with 1 failure (0 unexpected)`. The failure:
`WatchGpsDistanceTileTests.swift:481: … testS16011AMeasuredTileHasNoStepButtons : XCTUnwrap failed … the row branches on a measured field first (D-5)`
(base `row(_:)` always builds − / + around the tile, with `enabled: !field.isMeasured`). The other 12 passed.

### Implementation (D-5)

`row(_:)` is a `@ViewBuilder`: `if field.isMeasured { tile(field) } else { HStack { − tile + } }`; the unmeasured
step buttons drop the now-always-true `enabled:` argument. `tile(_:)`:
`.accessibilityAddTraits(field.isMeasured ? [] : .isButton)`; the tap guard and the accessibility label are unchanged.
Shared pair untouched: `stepArmed(` still 2 call sites, `"Less \(label)"` / `"More \(label)"` kept (S-7514 green).

The view is `#if os(watchOS)`, so `swift test` (macOS) does not compile it. Type-checked instead:
`xcrun --sdk watchos swiftc -typecheck -module-name WatchSessionEngine -target arm64-apple-watchos9.0 -parse-as-library <all module sources>`
→ exit 0, 0 errors. Proof the type-check sees the view: the same command on a scratch copy with the trait changed to
`field.isMeasured ? 42 : .isButton` → `WatchLoggingView.swift:341:56: error: result values in '? :' expression have mismatching types 'Int' and 'AccessibilityTraits'`.
Not run: `xcodebuild` of the watch app (governor).

### Mutations (`--filter WatchGpsDistanceTileTests`; original copied aside, restored, `cmp` clean)

| Id | Original | Mutant | Result |
|---|---|---|---|
| M12a | `if field.isMeasured {` / `tile(field)` | a disabled `stepButton(systemName: "minus", …)` added before `tile(field)` in the measured branch | `Executed 13 tests, with 1 failure` — killed |
| M12b | `.accessibilityAddTraits(field.isMeasured ? [] : .isButton)` | `.accessibilityAddTraits(.isButton)` | `Executed 13 tests, with 1 failure` — killed |

The failing test's name was cut by the output filter; S-16011 is the only test in the file that inspects the view's
structure (S-16013 scans for `"entered"`, absent from both mutants), and both runs passed 12 of 13.

### Green after Phase 2

- `--filter 'WatchGpsDistanceTileTests|WatchLoggingStatusTests|WatchAccessibilitySourceTests|WatchExercisePageFitTests'`
  → `Executed 39 tests, with 0 failures (0 unexpected)`.
- Full `swift test --package-path watch/watchos` → `Executed 1139 tests, with 0 failures (0 unexpected)`, exit 0
  (1138 + S-16011). `testS004NoMutatingOperationExistsAnywhereInTheModule`, `testS7514…` and `testS16011…` passed.
- `flutter test test/ui_standards_contract_test.dart test/docs_indexing_contract_test.dart` → `+54: All tests passed!`.
- `grep -rn "WatchHandDistanceTests\|testS9503\|S-950[0-9]\|S-9510" docs watch --exclude-dir=plans --exclude-dir=.build`
  empty. Without `--exclude-dir=.build` the only hit is the gitignored stale build file
  `watch/watchos/.build/…/WatchHandDistanceTests.d` (left by the Phase 1 deletion; not source).
- `grep -rn '"entered"' watch/watchos/Sources` empty; hive import sweep empty.
- `wc -c docs/state_management/watch_surface_wrist.md` = 52221 (≤ 52233); `docs/watch-app-setup-and-qa.md` = 48637.
