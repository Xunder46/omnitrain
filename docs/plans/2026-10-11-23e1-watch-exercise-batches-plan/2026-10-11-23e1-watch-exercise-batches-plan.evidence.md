# Evidence — plan 23e1 (watch exercise batches)

Filled by the builders, the prover and the governor as the phases run. The architect leaves the phase sections empty.

## Baselines

Governor, at base `3fc1e256` (do not re-measure):

| when | swift test | flutter test | flutter analyze | xcodebuild watch scheme | docs guards |
|---|---|---|---|---|---|
| before | 524 tests / 0 failures | +4267 ~1, all passed | 196 issues / 0 errors | — | 19 tests passed |
| after | 549 tests / 0 failures | +4278 ~1, all passed | 196 issues / 0 errors | BUILD SUCCEEDED | 9/9 (`test/docs_indexing_contract_test.dart`) |

## Phase A — contract: schema, fixtures, Swift validator (report-A.md)

- New `watch/sync_protocol/schemas/messages/exercises_down.schema.json` (closed payload; `catalogVersion` 1..64, `batchIndex` ≥ 0, `batchCount` ≥ 1, `totalCount` ≥ 1, `exercises` 1..100 of `catalogExercise`); `"exercises_down"` added to the envelope `type` enum; `routines_down.fallbackExercises` relaxed to `minItems: 0` with the D-3812 description; coverage rule untouched.
- 9 fixtures (3 valid, 6 invalid) + manifest rewrite; the governor deleted `invalid/routines_down_empty_fallback.json`.
- Swift validator: `"exercises_down"` in `messageTypes`, semantic case `exerciseBatchRejections(_:)` with the three D-3811 rules in order; plus generic `maxItems`/`maxLength` checks in the schema layer (the plan did not name them — see the plan's Assumption Log).
- PROTOCOL.md: message-families row, the same-day "catalog with no routines" row's superseded clauses struck through, a new 2026-10-11 amendment row.
- Tests: `SyncProtocolValidatorTests.testS3808ABatchOverOneHundredExercisesIsRefused`, `testS3834ARoutinesDownWithAnEmptyFallbackIsStillRefused`.
- Checks: `swift-test --filter SyncProtocolValidatorTests` 7/0; `--filter SyncProtocolFixturesTests` 6/0; full `swift-test` 526/0.

## Phase B — Dart validator twin (report-B.md)

- `lib/core/sync_protocol/message_validator.dart`: `'exercises_down'` in `messageTypes`; `_exerciseBatchRejections` with the Swift rule order and message text verbatim; `maxItems`/`maxLength` added to `_validateArray`/`_validateString` with the Swift wording.
- `test/sync_protocol_fixtures_test.dart`: new `S-3808` group (101 exercises → `constraint_violation` `expected at most 100 items, found 101`; 65-character `catalogVersion` → `expected at most 64 characters, found 65`) and `S-3834 an empty fallback with routines still fails coverage (D-3812)`.
- Checks: `gateway.sh test test/sync_protocol_fixtures_test.dart` 116 passed (red before this phase); `lint` 196 issues / 0 errors; full `flutter test` +4278 ~1 all passed.

## Phase C — wrist storage (report-C.md)

- `WatchExerciseBatchRecord` in `WatchRoutineRecords.swift`; `StoredWatchRecord.exerciseBatch` + the case in all 8 exhaustive switches; `WatchStoreContents.exerciseBatches` (default empty, `isEmpty` conjunct) + both `readAll` switches; `pruneExerciseBatches(keepingVersion:)` on the protocol, InMemory and File (`pruneExerciseBatchesLocked` follows `pruneConfirmedLocked`, with the D-3821 empty-drop early return); the two test doubles forward; the S-004 guard's allowed set gains `pruneExerciseBatches` (five deliberate names).
- Tests: `WatchFileStoreTests.testS3821APruneDropsEveryOtherVersionAndNothingElse`, `testS3821APruneAfterATornTailStillDropsTheOtherVersion`, `testS3835APruneWithNoBatchesWritesNothing`, `testS3821ABatchRowRoundTripsThroughTheFile`; batch family added to `fileFamilyJSON`.
- Checks: full `swift-test` 530/0 (baseline 526 + 4).

## Phase D — assembly, restore, union, routing, request, docs (report-D.md)

- `WatchSessionStartPaths`: `applyExercisesDown(_:)` with D-3815 rules (1)–(6) in order; `restore()` batch assembly per D-3816; public `exercisesVersion`; `syncedFallback` = active list first, then the catalog's `fallbackExercises` not already present, then `deriveFallbackExercises` as before; `receive` routes `exercises_down` (returns `stored`); `sync` passes `paths.exercisesVersion`; `WatchSyncTransport.requestRoutines(since:exercisesVersion:)` with the key added to the frame only when non-nil (contract untouched, D-3820); the four test doubles updated.
- Tests: `testS3810`…`testS3819`, `testS3820`, `testS3830`…`testS3833` (16 new; exact names in `WatchSessionStartPathsTests.swift` / `WatchConnectivityBridgeTests.swift`).
- Docs: new `docs/state_management/watch_reference_data.md`, linked from `docs/state_management.md` (scope sentence, Pages table, Class → Page Lookup) and `docs/README.md`.
- Checks: full `swift-test` 547/0; docs contract test 9/9; `lint` 196; full `flutter test` +4278 ~1.

## Race fix (report-fix-race.md)

- Finding: with two interleaved `applyExercisesDown` tasks (each suspends inside the store between its read and its append), completeness was judged on the pre-append rows merged with the sent batch, so neither task saw both rows and nothing activated — `testS3836InterleavedBatchesStillActivateTheList` red (`exercisesVersion == nil`, empty list) before the fix.
- Fix: completeness and assembly now read the store fresh AFTER the append (`merged = (await store.readAll()).exerciseBatches…`); the pre-append read remains only for the rule-3 disagreement refusal. Test red → green; full package 548/0 after the fix.

## Guards fix (report-fix-guards.md)

- Finding: mutation E1 (completeness loses its index-set clause) survived — the delivered exercises still summed to `totalCount`, so a gapped list activated; and mutation E10 (union drops the catalog fallback) survived because every catalog-fallback exercise in the old S-3817 was also named by a routine.
- Fix: new `testS3837AGapInTheBatchIndexesNeverActivates` (batches 0 and 2 of a 3-batch version, index 1 never delivered: stored, never activated) and `testS3817RoutineCoverageAndTheActiveListAreUnionedOnce` strengthened with a phone-only `ex-only-fallback` exercise so E10 goes red. Full package 549/0.

## Prover verdicts

not run: the governor proved the guards by mutation (see read-backs).

## Governor read-backs

Mutations E1..E15 applied to the production lines by `.work/2026-10-11-23e1/mutate.py` (first run) and `mutate2.py` (after the guards fix), restored byte-identical each run. First run: E1 and E10 survived (MISS); after the guards fix E1..E15 ALL red. The red test per mutation (first-run log `.work/2026-10-11-23e1/mutate.out`; the second run's per-mutation lists are not on disk — the brief records the outcome):

| # | Mutation | Test that went red |
|---|---|---|
| E1 | activates without all indexes present | `testS3837AGapInTheBatchIndexesNeverActivates` (added by the guards fix; first run: no test was red) |
| E2 | assembles in arrival order | `testS3810TwoBatchesCompleteTheListInBatchOrder` (also `testS3836InterleavedBatchesStillActivateTheList`) |
| E3 | never prunes after activation | `testS3812ACompletedNewerListReplacesTheOlderOneAndItsRows` |
| E4 | in-memory prune keeps the wrong version | `testS3821APruneDropsEveryOtherVersionAndNothingElse` (11 tests red) |
| E5 | file prune keeps the wrong version | `testS3821APruneAfterATornTailStillDropsTheOtherVersion`, `testS3821APruneDropsEveryOtherVersionAndNothingElse` (7 red) |
| E6 | restore ignores completeness | `testS3813ARelaunchRestoresTheNewestCompleteVersionAndIgnoresAHalfOne`, `testS3832ARelaunchWithNoCompleteVersionHasNoListAndNoError` |
| E7 | request frame never carries the version | `testS3820TheRoutinesRequestCarriesTheExerciseListVersionOnlyWhenThereIsOne` |
| E8 | sync never says which list it holds | `testS3819SyncNamesTheExerciseListVersionTheWristHolds` (also `testS3820…`) |
| E9 | validator accepts `batchIndex == batchCount` | `testEveryInvalidFixtureIsRejectedAsStated` (also `testS3818TheOrchestratorRoutesBatchesToThePaths`) |
| E10 | union drops the `routines_down` fallback list | `testS3817RoutineCoverageAndTheActiveListAreUnionedOnce` (strengthened by the guards fix; first run: no S-3817 red) |
| E11 | an older list is no longer dropped | `testS3816ACompleteListOlderThanTheActiveOneIsDropped` |
| E12 | disagreeing counts are no longer refused | `testS3815ABatchDisagreeingWithStoredRowsOfItsVersionIsRefusedWhole` (also `testS3831…`) |
| E13 | completeness read before the append (the race) | `testS3836InterleavedBatchesStillActivateTheList` |
| E14 | counts need not add up | `testS3831AVersionWhoseCountsDoNotAddUpNeverActivatesAndNeverPrunes` |
| E15 | routing reports activation instead of storage | `testS3818TheOrchestratorRoutesBatchesToThePaths` (also `testS3810…`) |

Race finding: completeness was judged on a pre-append read merged with the sent batch, so two interleaved tasks of one version each saw only their own row and nothing activated; fixed by reading the store fresh after the append (D-3823, S-3836, mutation E13 red).

Guards finding: the completeness check's index-set half and the fallback union had no test that went red under E1/E10; fixed by adding `testS3837AGapInTheBatchIndexesNeverActivates` and strengthening `testS3817RoutineCoverageAndTheActiveListAreUnionedOnce` with a phone-only fallback exercise; second mutation run E1..E15 all red.
