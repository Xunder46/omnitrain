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
(`testS3611TheAddListSortsCaseInsensitivelyByName`); a list of more than
`WatchMenuCopy.addLetterGridThreshold` (20) also carries the letter grid it
jumps by, one entry per distinct first key in the list's own order, with digits,
symbols and empty names sharing a `#` that opens the grid (a symbol above `z`,
such as `~`, sorts last, so the `#` entry then sits at the end:
`testS3908ASymbolThatSortsAfterZGetsItsHashEntryAtTheEnd`) and an accented
initial in the plain-lowercase place its name sorted to
(`testS3900TheLettersFollowTheListsOwnOrder`,
`testS3902TheGridNeedsMoreThanTheThreshold`,
`testS3905EveryLetterEntryCoversAContiguousRun`).

## Routing and the request frame

The sync orchestrator routes `exercises_down` to the start paths and reports
`stored` as the arrival's result; every other message keeps its own route
(`testS3818TheOrchestratorRoutesBatchesToThePaths`).

`WatchSyncTransport.requestRoutines(since:exercisesVersion:)` carries the
version of the list the wrist already holds, so the phone can send only what
changed. The key is added to the frame **only when there is a version**: a wrist
that holds no list sends exactly the frame it always did, so the contract's
`routinesSince` and `snapshot` rows (and the S-102/S-103 pins in
`WatchConnectivityBridgeTests`) are unchanged and the versioned frame has its
own `routinesExercises` row
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

The phone answers a `routines` request with `preferences_down` first, then
`routines_down` — whose `fallbackExercises` is the exercises its routines use
and nothing more (`test/watch_reference_sync_test.dart`, group `S-3840..S-3843,
S-3845, S-3846 the phone sends the list in batches`, test `S-3841 the fallback
list is the exercises the routines use`; a phone with no routine still answers,
with both lists empty, `S-3840 no templates: a message with both lists empty`)
— and then the whole catalog as `exercises_down` batches
(`S-3843 250 exercises arrive as three batches in name order`). When the
request names the version of the list the phone would send, the batches are
omitted and only the preferences and the routines travel
(`test/watch_sync_request_handler_test.dart`, group `S-3850…S-3853 the phone
sends only the list the wrist lacks`, test `S-3850 the wrist names the current
version: no batch travels`; a stale version sends the list again, `S-3852 a
version the phone no longer holds sends the whole list`; adding a custom
exercise stales the version, group `S-3854 the version round-trips, and a
change to the list stales it`, test `S-3854 a sync with the sent version sends
no batch, and a custom exercise stales it`). The phone sends the batches one at
a time in index order and stops at the first one the radio does not carry, so a
wrist that missed a batch keeps the list it had and the next Sync sends the
whole list again (`S-3853 a batch the radio refuses stops the rest, and the
answer still holds`). The request frame carries `exercisesVersion` only when
the wrist holds a list
(`test/watch_transport_test.dart`, `S-3856 a wrist that holds a list names its
version the way the contract does`, `S-3856 a request with no version holds no
version key`; the wiring hands it to the handler,
`test/watch_session_projection_test.dart`, group `S-3855 the wrist's
exercise-list version reaches the handler`; the Swift twin is
`WatchConnectivityBridgeTests.testS3820TheRoutinesRequestCarriesTheExerciseListVersionOnlyWhenThereIsOne`
and `WatchSessionStartPathsTests.testS3819SyncNamesTheExerciseListVersionTheWristHolds`).
The wrist uses the active list when it has one and the `routines_down` fallback
when it does not
(`testS3817RoutineCoverageAndTheActiveListAreUnionedOnce` pins the union, and
`testS3810TwoBatchesCompleteTheListInBatchOrder` pins that the fallback list is
untouched until a version completes). The Dart watch client (`lib/watch/`)
never reports a version (D-3805), so it is sent the full list on every Sync — a
documented divergence from the Swift wrist.

### The phone's sender since 23e2

The phone sends the exercise list as `exercises_down` batches of at most 100,
skips them when the request names the same version the list derives to, and
stops at the first batch the radio did not carry; `routines_down` from then on
carries only the routines' exercises. The tests named in the section above pin
each rule.

## What this page does not cover

The watch app target itself — its entitlements, its HealthKit use and its
behaviour on a real device — is outside the Swift package's tests. Nothing on
this page was verified by `xcodebuild` or on a watch simulator.
