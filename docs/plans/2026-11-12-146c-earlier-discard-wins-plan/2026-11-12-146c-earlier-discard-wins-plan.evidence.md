# Evidence — 146c: an earlier discard wins (146 PR 3)

Baselines, suite outputs, red→green tables and footprints live here; implementers write here, not into
the plan.

## Baselines (measured at planning, 2026-11-12)

- Plan 146's final soak (2000 seeds): **1777 converge, 146 diverging** on a shipping trace,
  `{status: 166, absorbing: 21, heal: 32, entries: 11, timers: 2}`
  (`.work/gateway/test-20261112-000556-15213.log`, recorded in plan 146's evidence `## Phase 5.Z`).
- Sweep contract: `knownClasses` = `{status, absorbing, entries, timers, heal}`; `shippingRatchet` =
  `(kSeedCount * 18 / 200).ceil()` (18 measured on seeds 1..200 in Phase 5.Z) —
  `test/watch_convergence_random_test.dart` :171-204.
- `flutter analyze`: **181 issues**, the repo baseline.
- Full suite at plan 146's close: **+7441 ~2: All tests passed!** (5m24s;
  `.work/gateway/test-20261112-000733-15770.log`).
- A-146-15's interim lives in two files: `lib/watch/session/watch_session_engine.dart`
  (`_applyLifecycle`, the completed-beats-abandoned skip ~766-776) and
  `watch/watchos/Sources/WatchSessionEngine/WatchSessionEngine.swift`
  (`applyLifecycleExclusive`, the same skip ~826-833). The phone's reconciler
  (`lib/core/sync_protocol/session_reconciler.dart`, `_incomingEndWins` :226-241) already resolves
  earlier-instant-first with the D-14601 tie-break and has no interim — verified by read, no change
  planned.

## Phase outputs

*(filled in by the implementing agent at the end of its own phase: command, result, red→green table,
footprint)*

### Phases 1-3 (developer run 2026-11-12, PR 3)

Red→green per scenario (every RED is a `prove-red HEAD` run on the code without the change):

| Scenario | Test | RED at HEAD | Green |
|---|---|---|---|
| S-14630 | `test/watch_session_adoption_bridge_test.dart` → `S-14630 the wrist's earlier discard deletes the phone's finished workout` | `Expected: null / Actual: <Instance of 'TrainingSession'>` at the `getSession` assertion | pass |
| S-14632 | same file → `S-14632 an arriving discard at exactly the held end instant is ignored` | green before the change: it is the *guard on the guard*; proved by mutation (`<` → `<=` in the bridge) failing `Expected: <1791201900000> / Actual: <null>`, then restored and re-run green | pass |
| S-14633 | `test/watch_session_import_test.dart` → `S-14633 a winning discard leaves no phantom workout` (3 tests) | part of the same RED AT HEAD run below (no `S-14633` group can pass before the delete) | pass |
| S-14640 | `test/watch_session_engine_test.dart` → `S-14640 an earlier discard replaces the twin's completed` (2 tests) | `--plain-name S-1464` RED AT HEAD (exit 1) | pass |
| S-14641 | same file → `S-14641 a later phone completion loses to the wrist's discard`, `S-14641 both arrival orders converge on the same ending` | `Expected: false / Actual: <true>` and `Expected: 'abandoned' / Actual: 'completed'` | pass |
| S-14642 | `watch/sync_protocol/fixtures/reconciliation/discard_before_finish.json` walked by `test/sync_protocol_fixtures_test.dart` `S-004 every reconciliation fixture converges on its expected state` | the fixture does not exist at HEAD | pass |
| S-14643 | `test/watch_reconciliation_cross_stack_test.dart` → `S-14643 an earlier discard wins on both stacks` (3 tests) | `Expected: ['abandoned', 'abandoned'] / Actual: ['abandoned', 'completed']` — the two stacks diverged at HEAD, which is the defect | pass |
| S-14650 | `watch/watchos/Tests/WatchSessionEngineTests/WatchEndedIsFinalTests.swift` → `testS14650AnEarlierDiscardBeatsALaterCompletionInEitherOrder`, `testS14650ALaterDiscardLosesToAnEarlierCompletionInEitherOrder` | `prove-red HEAD swift-test --filter WatchEndedIsFinalTests` → RED AT HEAD: 3 failures on `XCTAssertFalse … a later completion loses` / status `completed` where `abandoned` was expected | pass |
| S-14651 | `WatchLiveMirroringTests.testEveryReconciliationFixtureConverges` (walks the new fixture, asserts `expected.status`) | walked only after Phase 2 created the fixture; the same walker is RED on the unmodified engine (it keeps `completed`) | pass |

Prove-red verdict lines:

```
gateway: prove-red: RED AT HEAD (exit 1).  [test test/watch_session_adoption_bridge_test.dart — S-14630]
gateway: prove-red: RED AT HEAD (exit 1).  [test test/watch_reconciliation_cross_stack_test.dart — S-14643, Actual: ['abandoned', 'completed']]
gateway: prove-red: RED AT HEAD (exit 1).  [swift-test --filter WatchEndedIsFinalTests — S-14650, 3 failures]
```

Suite counts (real, pasted):

| Check | Command | Result |
|---|---|---|
| Phase 1 | `gateway.sh test test/watch_session_adoption_bridge_test.dart test/watch_session_import_test.dart test/watch_session_finish_test.dart` | **133 passed, 0 failed** |
| Phase 2 (Dart) | `gateway.sh test test/sync_protocol_fixtures_test.dart` (S-004) | pass |
| Phase 2 (Dart) | `gateway.sh test test/watch_reconciliation_cross_stack_test.dart test/sync_protocol_fixtures_test.dart` | **210 passed, 0 failed** |
| Phase 2 (Dart) | `gateway.sh test test/watch_convergence_harness_test.dart test/watch_session_engine_test.dart test/watch_session_adoption_bridge_test.dart test/watch_session_import_test.dart test/watch_session_finish_test.dart` | **233 passed, 0 failed** (S-14512 re-pointed: prints `phone abandoned wrist abandoned`) |
| Docs | `gateway.sh test … test/docs_indexing_contract_test.dart` | pass (PROTOCOL.md still under the 64 KiB cap) |
| UI standards | `gateway.sh test test/ui_standards_contract_test.dart` | **41 passed, 0 failed** |
| Phase 3 (Swift) | `gateway.sh swift-test --filter WatchEndedIsFinalTests` | **12 passed, 0 failed** |
| Phase 3 (Swift) | `gateway.sh swift-test` (whole package) | **1388 passed, 0 failed** |
| Lint | `gateway.sh lint` | **181 issues** — the baseline, no new notice in a touched file |

Mutation (S-14632 only): the bridge's `atMs < held.endedAtMs` was changed to `atMs <=
held.endedAtMs`; `--plain-name "S-14632"` then failed `Expected: <1791201900000> / Actual: <null>`;
the exact original line was restored and the suite re-ran green (133 passed). No mutation is left
applied.

Footprint (`gateway.sh git-diff --stat`): 13 files, +~940/-~60. All inside the plan's Predicted Files
for Phases 1-3, plus the new fixture file and one helper-signature change inside a predicted test file
(`_phone(..., clock:)`).

## Governor actions

*(recorded by the planner when the work needs something its tools deny)*

## Lead note: S-14508 re-based (2026-11-13)
After phases 1-3 the S-14508 mutation proof (a wrist that ignores `completed` lifecycles) turned red on 0 of 60 seeds (it was 7, 9, 40 before): the new rule lets the heal repair that wrist through snapshots, so the proof no longer proved the sweep can fail. Re-based on `_DeafToEndWrist` (refuses completed lifecycles AND completed snapshots, the same mutation S-14510 uses): red on seeds [1, 11, 46, 52, 55, 56, 57]. A stronger mutation, not a weaker assertion. The developer run had reported all suites green without running this file.
Lead-verified: focused Flutter suites 491 passed; Swift full 1388 passed; new tests fail on the old sources (Dart 4 failures, Swift 3).
