# The Watch's Reference Data

**Scope.** What the phone pushes down to the wrist and what the wrist does with
it: the routines, the exercise list the phone sends in batches, and the version
the wrist echoes back. The owning code is the Swift wrist package
(`watch/watchos/Sources/WatchSessionEngine/WatchStartPaths.swift`,
`WatchSyncOrchestrator.swift`, `WatchConnectivityBridge.swift`) and the protocol
under `watch/sync_protocol/`. The phone-side builders
(`WatchReferenceSync.buildRoutinesDown`) are on
[The Watch Surface](watch_surface.md); the sensors are on
[The Watch Sensors and the Platform Workout](watch_sensors.md).

Reference data is one-directional: the phone owns it, the wrist stores what
arrives and never edits it. Every sentence below names the test that pins it —
a rule that changes on one platform has to change the shared contract and the
other platform's suite too.

## Two messages, two jobs

`routines_down` says "your routines, and the exercises they use". Its
`fallbackExercises` is the list that keeps a synced routine loggable offline.
It is not the whole catalog: a phone with 252 seeded exercises would send about
28 KB for a list the wrist mostly does not need at start time. The whole list
travels as `exercises_down` instead, in batches of at most 100 exercises, each
batch naming a version, its index, the version's batch count and its total
exercise count.

Both messages are walked against the schemas by
`SyncProtocolFixturesTests.testEveryValidFixtureConforms` and
`testEveryInvalidFixtureIsRejectedAsStated` (fixtures
`watch/sync_protocol/fixtures/valid/exercises_down.json`,
`..._single_batch.json` and the six invalid ones). `routines_down` may now carry
an empty `fallbackExercises` (`minItems: 0`); the validator's coverage rule is
unchanged, so a routine whose exercise the fallback list misses is still refused
(`SyncProtocolValidatorTests.testS3834ARoutinesDownWithAnEmptyFallbackIsStillRefused`).

## A batch is stored as it arrives

`WatchSessionStartPaths.applyExercisesDown(_:)` runs six rules in order, and the
order is the rule:

1. **Validate.** The envelope goes through the same validator as every other
   incoming message; a batch the wrist cannot read changes nothing
   (`WatchSessionStartPathsTests.testS3818TheOrchestratorRoutesBatchesToThePaths`).
2. **Drop a strictly older batch.** A batch whose `generatedAt` is earlier than
   the active list's is understood and dropped — an older view of the list is not
   a newer truth. A batch at the *same* instant is not dropped
   (`testS3816ACompleteListOlderThanTheActiveOneIsDropped`,
   `testS3833ABatchAtTheActiveListsOwnInstantIsNotDropped`). The consequence to
   know when debugging "the wrist will not take my list": after a restore, a
   phone whose clock is behind the stored active list's generation time cannot
   replace that list until its clock passes that instant — every batch it sends
   is dropped as older and nothing of it is stored, so the wrist keeps the list
   it has (`testS3816ACompleteListOlderThanTheActiveOneIsDropped`).
3. **Refuse a batch that disagrees with its own version.** If the wrist already
   holds rows for this version whose `batchCount` or `totalCount` differ, the
   whole batch is refused and nothing is stored — a version's shape is fixed by
   the first batch of it the wrist keeps
   (`testS3815ABatchDisagreeingWithStoredRowsOfItsVersionIsRefusedWhole`).
4. **Append.** The row's id is `exb-<catalogVersion>-<batchIndex>`, so a repeat
   delivery is the same row rather than a second one
   (`testS3814TheSameBatchTwiceStoresOneRowAndActivatesOnce`).
5. **Test completeness.** A version is complete when every index from `0` to
   `batchCount - 1` is stored *and* the stored exercises sum to `totalCount`.
   Both halves are needed: rows that are all present but hold the wrong number of
   exercises never activate (`testS3831AVersionWhoseCountsDoNotAddUpNeverActivatesAndNeverPrunes`),
   and a gap in the indexes never activates either, even when the delivered
   exercises sum to `totalCount`
   (`testS3837AGapInTheBatchIndexesNeverActivates`). Completeness is judged on a
   read taken **after** the append, so two batches of one version arriving
   interleaved — each call suspended inside the store between its read and its
   append — still activate the list exactly once, in `batchIndex` order
   (`testS3836InterleavedBatchesStillActivateTheList`). Two *versions* can
   interleave the same way, and the one completing last can be the older of the
   two, so the activation guard re-checks the drop rule of 2 against the list
   active at that instant: the older version is stored and never activated, and
   the newer one stays the wrist's list
   (`testS3838AnOlderListCompletingLastNeverReplacesANewerActiveOne`).
6. **Activate, then prune.** Only when a complete version arrives that the wrist
   was not already holding does it become the active list — the exercises in
   `batchIndex` order — and only then are the batches of every other version
   dropped (`testS3810TwoBatchesCompleteTheListInBatchOrder`,
   `testS3830ASingleBatchListCompletesImmediately`,
   `testS3812ACompletedNewerListReplacesTheOlderOneAndItsRows`).

A batch that completes nothing is still stored: that is what lets the next sync
finish the list. A half-synced newer version therefore leaves the older list in
place, and `applyExercisesDown` reports `stored == true, activated == false`
(`testS3811AHalfSyncedNewerListLeavesTheOlderOneActive`).

## What a launch restores

`WatchSessionStartPaths.restore()` rebuilds the active list from the stored
batch rows: among the versions that are complete, the one with the greatest
`generatedAt` wins, and the greatest row sequence breaks a tie. It never needs
the prune to have run, so a kill between the last append of a version and its
prune still restores the list the wrist had. No complete version means no active
list — not an error — and the routines and their fallback list still restore
(`testS3813ARelaunchRestoresTheNewestCompleteVersionAndIgnoresAHalfOne`,
`testS3813BRelaunchRestoresTheVersionThatCompletedLast`,
`testS3813CRelaunchWithTwoCompleteVersionsRestoresTheNewestByGeneratedAt`,
`testS3832ARelaunchWithNoCompleteVersionHasNoListAndNoError`).

## The list the wrist offers offline

`fallbackExercises` is the active exercise list first, then the routine
catalog's own `fallbackExercises` for every exercise the active list does not
already name, deduplicated by `exerciseId` keeping the first mention. Recents
come first of all, and every exercise a synced routine names is added even when
neither list names it, so a routine the wrist holds is always loggable
(`testS3817RoutineCoverageAndTheActiveListAreUnionedOnce`,
`testS003FallbackListUnionsRecentsAndRoutineExercisesInContractOrder`).
`addableExercises` is that same list, sorted A to Z for the Add Exercise menu
(`testS3611TheAddListSortsCaseInsensitivelyByName`).

## Routing and the request frame

The sync orchestrator routes `exercises_down` to the start paths and reports
`stored` as the arrival's result; every other message keeps its own route
(`testS3818TheOrchestratorRoutesBatchesToThePaths`).

`WatchSyncTransport.requestRoutines(since:exercisesVersion:)` carries the
version of the list the wrist already holds, so the phone can send only what
changed. The key is added to the frame **only when there is a version**: a wrist
that holds no list sends exactly the frame it always did, which is why the
shared contract's `transportRequests` rows (and the S-102/S-103 pins in
`WatchConnectivityBridgeTests`) are unchanged
(`WatchConnectivityBridgeTests.testS3820TheRoutinesRequestCarriesTheExerciseListVersionOnlyWhenThereIsOne`,
`WatchSessionStartPathsTests.testS3819SyncNamesTheExerciseListVersionTheWristHolds`).
The frame's contract is `watch/contract/watch_start_paths_contract.json`, read
by both the Swift and the Dart suites.

## Storage and pruning

Batch rows are append-only like every other record. The one way they leave is
`pruneExerciseBatches(keepingVersion:)`, which drops every batch row of another
version and returns the ids it dropped; no other record kind is touched, and a
prune with nothing to drop writes nothing
(`WatchFileStoreTests.testS3821APruneDropsEveryOtherVersionAndNothingElse`,
`testS3821APruneAfterATornTailStillDropsTheOtherVersion`,
`testS3821ABatchRowRoundTripsThroughTheFile`,
`testS3835APruneWithNoBatchesWritesNothing`).

The store's mutating surface is pinned as a whole:
`WatchSessionEngineTests.testS004NoMutatingOperationExistsAnywhereInTheModule`
fails the build if a mutating store method is added without being listed, so
the prune above is the only way batch rows leave.

## Where the two ends stand

The phone still sends the whole list in `routines_down.fallbackExercises`, so the
wrist keeps reading it exactly as before and nothing changes on screen; the
batched message is a second way for the same data to arrive, and the wrist uses
the active list when it has one and the `routines_down` fallback when it does
not (`testS3817RoutineCoverageAndTheActiveListAreUnionedOnce` pins the union, and
`testS3810TwoBatchesCompleteTheListInBatchOrder` pins that the fallback list is
untouched until a version completes). The Dart watch client (`lib/watch/`) is
untouched by this change.

### Not yet changed (23e2)

The phone still sends the whole exercise list in `routines_down.fallbackExercises`
— the sender is untouched in this PR, so `routines_down` carrying the whole list
is still true here. Plan 23e2 moves the phone to sending the list as
`exercises_down` batches and stops relying on the full fallback list; until then
the batched message is only a second way for the same data to arrive.

## What this page does not cover

The watch app target itself — its entitlements, its HealthKit use and its
behaviour on a real device — is outside the Swift package's tests. Nothing on
this page was verified by `xcodebuild` or on a watch simulator.
