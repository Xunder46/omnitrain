# Review: 2026-10-11-23e1-watch-exercise-batches-plan · phases A–D + fix rounds · 3fc1e25..working tree
Verdict: CHANGES_REQUESTED
Counts: blocker 0 · major 1 · minor 3 · tests: governor-run (swift test 549/0, flutter test +4278 ~1, analyze 196, xcodebuild watch scheme BUILD SUCCEEDED; 15 mutations E1–E15 red)
Diff vs Predicted Files: conforms (24 files, +1868/−52; docs/README.md link row disclosed in report-D)

## Findings
1. [Major] watch/watchos/Sources/WatchSessionEngine/WatchStartPaths.swift:434 — the activation
   guard re-checks only `activeExercisesVersion != sent.catalogVersion` and completeness, not the
   generatedAt drop rule it passed before the awaits. Cross-version interleaving: active = v1(T1);
   Task A (v2, T2) and Task B (v3, T1<T3<T2) both pass rule 2 while active is v1; A activates v2
   and prunes v1's rows; B resumes with complete v3 rows, the guard passes (v2≠v3), B activates v3
   — an older list than the one just activated — and prunes v2's rows. The wrist regresses to an
   older list within one burst, and the newer rows are gone. The in-code comment ("the version
   that activated must not change under the two of them") covers only the same-version case the
   S-3836 fix round addressed. Fix: add the drop rule to the guard, e.g.
   `guard activeExercisesVersion != sent.catalogVersion, (activeExercisesGeneratedAt ?? .distantPast) <= sent.generatedAt, ...`
   and return `stored: true, activated: false` on failure — restore picks by generatedAt, so state
   stays consistent. Guard: a SuspendingStore test with completing batches of two versions
   interleaved so the older version's task resumes last → the newer version must stay active.
2. [Minor] watch/watchos/Tests/WatchSessionEngineTests/WatchConnectivityBridgeTests.swift:197,
   1230, 1284 — plan item D6/D-3818 says the four test doubles "record both arguments"; only
   `RecordingTransport` records `exercisesVersion` (as `requestedVersions`). `WireLog`,
   `GatedTransport` and `GatedRequestTransport` keep only `requested: [Date?]`. No scenario is
   unpinned (S-3819/S-3820 assert the frames themselves), so this is a plan-wording deviation.
   Fix: add a `requestedVersions` array to the three doubles, or note the deviation in the plan.
3. [Minor] watch/watchos/Sources/WatchSessionEngine/WatchStartPaths.swift:669 —
   `StoredWatchRecord.exerciseBatchRow` is unused in Sources (left behind by the S-3836 fix
   round; report-fix-race notes it). Dead surface a maintainer must keep in parity with the
   record type. Fix: delete it, or use it where the extension lives.
4. [Minor] docs/state_management/watch_reference_data.md (rule 2 paragraph) — the documented
   drop rule has an undocumented consequence: after a restore, a phone whose clock falls behind
   the stored active `generatedAt` can never replace the wrist's list until its clock passes that
   instant (every batch is dropped by rule 2; the version string is opaque to the wrist per
   D-3802). The wrist never ends up with nothing, so the behaviour is as designed — but a
   maintainer debugging "the wrist won't take my list" has nothing to read. Fix: one sentence in
   the rule-2 paragraph naming the consequence, tied to testS3816.

## Assumption Log rulings
- Plan Assumption Log is empty after a complex four-phase build — noted; the entries below are
  the ones the review could reconstruct from the brief and reports.
- Clock-backwards consequence of D-3815 rule 2 (finding 4): ratified as intended behaviour under
  D-3802/D-3815 (generatedAt is the only ordering the wrist derives; the wrist is never left
  without a usable list). The docs gap itself stands as the Minor finding.
- maxItems/maxLength added to exercises_down.schema.json beyond the plan's letter (report-A/B):
  ratified — needed to pin S-3808's 100-exercise ceiling at the schema layer; no existing schema
  behaviour changes (the keys exist only in that file).
- `try?` around `WatchCatalogExercise(json:)` in `assemble`: ratified — unreachable for validated
  input (schema `$defs/catalogExercise` requires the same strings the initializer requires).

## Scenario coverage
S-3801 → SyncProtocolFixturesTests · valid/exercises_down.json fixture walk (both stacks) | covered
S-3802 → SyncProtocolFixturesTests · valid/exercises_down_single_batch.json walk | covered
S-3803 → SyncProtocolFixturesTests · valid/routines_down_empty.json walk | covered
S-3804 → SyncProtocolFixturesTests · invalid/exercises_down_batch_index_out_of_range.json | covered
S-3805 → SyncProtocolFixturesTests · total_below_batch + total_above_capacity fixtures | covered
S-3806 → SyncProtocolFixturesTests · invalid/exercises_down_duplicate_exercise.json | covered
S-3807 → SyncProtocolFixturesTests · empty_batch + missing_version fixtures | covered
S-3808 → WatchSessionStartPathsTests · testS3808ABatchOverOneHundredExercisesIsRefused + Dart twin | covered
S-3810 → WatchSessionStartPathsTests:1362 · testS3810TwoBatchesCompleteTheListInBatchOrder | covered
S-3811 → WatchSessionStartPathsTests:1461 · testS3811AHalfSyncedNewerListLeavesTheOlderOneActive | covered
S-3812 → WatchSessionStartPathsTests:1503 · testS3812ACompletedNewerListReplacesTheOlderOneAndItsRows | covered
S-3813 → WatchSessionStartPathsTests:1548/1588/1628 · testS3813A/B/C | covered
S-3814 → WatchSessionStartPathsTests:1664 · testS3814TheSameBatchTwiceStoresOneRowAndActivatesOnce | covered
S-3815 → WatchSessionStartPathsTests:1686 · testS3815ABatchDisagreeingWithStoredRowsOfItsVersionIsRefusedWhole | covered
S-3816 → WatchSessionStartPathsTests:1728 · testS3816ACompleteListOlderThanTheActiveOneIsDropped | covered
S-3817 → WatchSessionStartPathsTests:1760 · testS3817RoutineCoverageAndTheActiveListAreUnionedOnce | covered
S-3818 → WatchSessionStartPathsTests:1811 · testS3818TheOrchestratorRoutesBatchesToThePaths | covered
S-3819 → WatchSessionStartPathsTests:1842 · testS3819SyncNamesTheExerciseListVersionTheWristHolds | covered
S-3820 → WatchConnectivityBridgeTests:301 · testS3820TheRoutinesRequestCarriesTheExerciseListVersionOnlyWhenThereIsOne | covered
S-3821 → WatchFileStoreTests:1040/1101/1177 · testS3821A×3 (prune, torn tail, round-trip) | covered
S-3822 → WatchSessionEngineTests · testS004NoMutatingOperationExistsAnywhereInTheModule (edited) | covered
S-3830 → WatchSessionStartPathsTests:1868 · testS3830ASingleBatchListCompletesImmediately | covered
S-3831 → WatchSessionStartPathsTests:1885 · testS3831AVersionWhoseCountsDoNotAddUpNeverActivatesAndNeverPrunes | covered
S-3832 → WatchSessionStartPathsTests:1949 · testS3832ARelaunchWithNoCompleteVersionHasNoListAndNoError | covered
S-3833 → WatchSessionStartPathsTests:1974 · testS3833ABatchAtTheActiveListsOwnInstantIsNotDropped | covered
S-3834 → SyncProtocolValidatorTests:173 · testS3834ARoutinesDownWithAnEmptyFallbackIsStillRefused + Dart twin | covered
S-3835 → WatchFileStoreTests:1144 · testS3835APruneWithNoBatchesWritesNothing | covered
S-3836 → WatchSessionStartPathsTests:1409 · testS3836InterleavedBatchesStillActivateTheList | covered
S-3837 → WatchSessionStartPathsTests:2005 · testS3837AGapInTheBatchIndexesNeverActivates | covered

## Verified clean (no findings)
- Store prunes: FileWatchSessionStore.pruneExerciseBatchesLocked and the InMemory twin follow the
  sibling prunes exactly; D-3821's empty-drop-no-write guard present in both (S-3835).
- Contract/validator parity: same rules, same order, same rejection text in SyncProtocolValidator
  and message_validator.dart; the semantic layer runs only after the schema layer passes in both,
  so the Dart narrow casts are safe by the file's existing convention.
- Request frame: `routinesFrame(since:exercisesVersion:)` adds the key only when non-nil; the
  phone reader (lib/state/watch/watch_sync_wiring.dart:234) uses `WatchTransportRequest.nameOf`
  only, so the extra key cannot break it; Dart wrist client's `default: return false` confirms
  D-3819. Shared contract untouched (D-3820); S-102/S-103 pins unchanged.
- Docs: every behaviour sentence in watch_reference_data.md names an existing test (each name
  checked on disk this run); PROTOCOL.md amendment row names real tests; the two index edits name
  existing types. docs/09-21-13-watch-integration-shipping.md:1214 carries a stale "minItems: 1"
  but is a historical plan doc, untouched by this diff.
- No existing assertion weakened: the only deleted test line across all test files is the
  requestRoutines signature update; the S-004 guard edit names five real operations.
