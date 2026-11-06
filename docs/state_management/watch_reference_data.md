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
It is not the whole catalog: a phone with more than 300 seeded exercises would send tens
of kilobytes for a list the wrist mostly does not need at start time. The whole list
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
`testS3905EveryLetterEntryCoversAContiguousRun`). `deriveExerciseSections` reads
that same list as the runs the grid jumps by, in the same order, so the
concatenation of its sections is the list itself
(`testS3105ASectionsFollowTheListAndTheLettersAgree`).

The startup picker offers the same list: `availablePickerExercises` is
`addableExercises` in its own order minus the exercises the live ladder already
holds, so an exercise the user is on is offered once, as its own in-session row
(`testS3107ATheFreePickerOffersTheAvailableExercisesAToZ`,
`testS3113AThePickerRowsAndTheAvailableExercisesAgree`). `pickerRows` are those
rows behind the ladder's own, and the picker's grid is `deriveExerciseListLetters`
over the rows it offers — the one gate both surfaces read
(`testS3108ATheLetterGridAppearsOverTwentyRows` for the menu's list,
`testS3113AThePickerRowsAndTheAvailableExercisesAgree` for the picker's).

## Routing and the request frame

The sync orchestrator routes `exercises_down` to the start paths and reports
`stored` as the arrival's result; every other message keeps its own route
(`testS3818TheOrchestratorRoutesBatchesToThePaths`).

`WatchSyncTransport.requestRoutines(since:exercisesVersion:holdsBests:wantsWater:)` carries
the version of the list the wrist already holds, so the phone can send only what
changed. The key is added to the frame **only when there is a version**: a wrist
that holds no list sends exactly the frame it always did, so the contract's
`routinesSince` and `snapshot` rows (and the S-102/S-103 pins in
`WatchConnectivityBridgeTests`) are unchanged and the versioned frame has its
own `routinesExercises` row
(`WatchConnectivityBridgeTests.testS3820TheRoutinesRequestCarriesTheExerciseListVersionOnlyWhenThereIsOne`,
`WatchSessionStartPathsTests.testS3819SyncNamesTheExerciseListVersionTheWristHolds`).
The same request carries `holdsBests` — the boolean `true` only when the wrist
holds a bests frame, omitted otherwise, never `false` and never null — so the
phone can leave out bests the wrist already has. The phone reads it as held only
when the value is the boolean `true`: a string, a number, `false` or a missing
key all mean "not held", and that wrist is sent the frame. The holding frame has
its own contract row, `routinesBests`, beside `routines`, `routinesSince` and
`routinesExercises`; a wrist that holds nothing sends the `routines` row byte
for byte (`test/watch_transport_test.dart`, `S-87c-16 a wrist that holds the
bests says so`;
`WatchConnectivityBridgeTests.testS87c16TheRoutinesRequestCarriesHoldsBestsOnlyWhenTheWristHoldsOne`).
A request may also carry `wantsWater` — the boolean `true` when the wrist asks
for the day's water count, omitted otherwise — read by the same rule: only the
boolean `true` is asking. Its contract row is `routinesWater`
(`test/watch_transport_test.dart`, `S-94a-26 a wrist that asks for the water
count says so`, group `S-94a-22 the request says whether the wrist wants the
water count`).
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

The phone answers a `routines` request with the reference frames —
`preferences_down`, then `foods_down` — an empty `foods` list is a valid
frame, so a phone with no foods sends the empty frame and the wrist empties
its list, while a foods read that threw sends no foods frame at all — then
`routines_down`, all stamped with one bundle stamp — but only when the wrist's
`since` is older than that stamp: an unchanged phone answers a wrist that
holds the current bundle with none of the three, and `routines_down` is
withheld when the preferences or the foods frame came back undelivered
(`test/watch_sync_changed_only_test.dart`, groups `S-9201`…`S-9212`; the
empty frame, `test/watch_sync_request_handler_test.dart`,
`S-7104 (S-15204) a phone with no foods sends an empty foods frame and still
sends the rest`; the emptied list,
`test/watch_sync_changed_only_test.dart`,
`S-15203 a phone that had foods and has none now sends the empty foods frame
in the middle slot`; the wiring hands the frame's `since` to the handler,
`test/watch_session_projection_test.dart`, group `S-9213 the wrist's since
reaches the handler`). The `routines_down` frame's `fallbackExercises` is the
exercises its routines use and nothing more
(`test/watch_reference_sync_test.dart`, group `S-3840..S-3843,
S-3845, S-3846 the phone sends the list in batches`, test `S-3841 the fallback
list is the exercises the routines use`; a phone with no routine still answers,
with both lists empty, `S-3840 no templates: a message with both lists empty`),
and then the whole catalog as `exercises_down` batches
(`S-3843 250 exercises arrive as three batches in name order`). When the
request names the version of the list the phone would send, the batches are
omitted
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

### The bests close every answer that needs them

`bests_down` — every trained exercise's best estimated 1RM and best bodyweight
reps — is the last frame of an answer that needs it, after the batches. The
bundle's stamp cannot stand for a best, so it is sent whatever the wrist's
`since` says; what decides it is the wrist's own word plus the phone's memory of
what it last delivered. The phone skips the frame only when all three hold: the
request says the wrist holds one, the last frame the phone sent was delivered,
and either nothing was written since it was sent (the repository's
`historyRevision` stands where it stood then) or the bests come out identical
when the phone does look. A wrist that says nothing — an older wrist, a
reinstalled one, one that lost its copy — is sent the frame every time, exactly
as before, and a phone that relaunched has forgotten what it delivered, so it
sends once. None sent is a definite answer rather than a failure (87c, D-5;
`test/watch_sync_request_handler_test.dart`, group
`S-87c-1…S-87c-14 the bests are sent only when they moved`, test `S-87c-1 a
wrist holding the bests, raising again at the same revision, is sent none and
reads no history`; a write that leaves the entries as they were costs one walk
and no frame, `S-87c-3 a write that leaves the bests identical costs one walk
and no frame`; a wrist that says nothing is sent them every time, `S-87c-4 a
request that does not say the wrist holds the bests sends the frame every
time`; a frame the radio did not carry is sent again, `S-87c-5 a frame the
radio did not carry is sent again, and after a delivered one the next request
skips it`; the wiring hands the flag to the handler,
`test/watch_session_projection_test.dart`, group `S-87c-18 the wrist's
holdsBests reaches the handler`, test `S-87c-18 a holding wrist is sent no
bests until its frame is stale`). The bests are the only history the sync
reads, so a skip is also the whole of an idle raise's cost: no
`StatsProgressService` is created and no box is read. The frame is still closed over the answer whenever it is sent
(`test/watch_sync_request_handler_test.dart`, group
`S-87a-6…S-87a-13 the bests close every answer`, test `S-87a-6 a since-current
request is answered with none of the three bundle frames and exactly one
bests_down`; a refused bests frame changes neither the batches nor the answer,
`S-87a-7 a bests frame the radio refuses leaves the batches and the answer as
they were`; `test/watch_sync_changed_only_test.dart`, group `S-9202 a wrist
holding the current bundle is sent only the bests`). A phone with no completed
session that is asked sends the frame, with an empty `bests` array, so "no
history" and "the frame never arrived" stay distinguishable
(`S-87a-13 no completed sessions reaches the wrist as an empty array`). The
frame is built from a `StatsProgressService` created per request, never a held
one, so a workout completed between two requests reaches the wrist
(`S-87a-8 a workout completed between two requests changes the next frame`),
and each frame is stamped with its own request's clock rather than the bundle's
(`S-87a-12 each frame is stamped with that request's own clock`). The frame it
sends validates against the contract (`S-87a-11 the sent frame validates, with
and without history`).

### The water count rides an answer that asks

A routines request that asks for the water count (`wantsWater`) is answered
with one `water_down` — the phone's own glass count for its today, plus the ids
of the wrist taps that count already includes — after the exercise batches and
before `bests_down`, so the bests stay last. It is sent on every such request,
whatever `since`, the exercise-list version or the bests decide, because the
count moves with every glass while the bundle's stamp does not. It is read from
storage when the request arrives; a read that throws sends no count and a frame
the radio did not carry is not retried, and neither changes the rest of the
answer (plan 94, D-6, D-8(a);
`test/watch_sync_request_handler_test.dart`, group `S-94a-21…S-94a-25 the water
count rides an answer that asks`; the wiring hands the key over,
`test/watch_session_projection_test.dart`, group `S-94a-26 the wrist's
wantsWater reaches the handler`). The same frame also follows the receipt
whenever a message carrying wrist taps arrives (`WatchWaterLogBridge`;
`docs/nutrition.md`, "Glasses tapped on the watch").

### The wrist holds one water count

A wrist built with a `WatchWaterState` asks for the count on every sync, manual
or catch-up; one built without it sends the request frames it always did, byte
for byte (`WatchWaterSyncTests.testS94b17EverySyncOfAWristWithAWaterStateAsksForTheCount`,
`…testS94b17TheBridgeCarriesTheKeyOnlyForAWristThatAsks`). The orchestrator
routes `water_down` to that state, and the frame counts as a reply in the sync
window (`…testS94b18TheFrameIsRoutedToTheWaterState`,
`…testS94b18AWaterFrameExtendsARunningSyncLikeAnyReply`).

The wrist holds ONE frame, as it holds one bests copy: a frame the validator
refuses or the wrist cannot read stores nothing, an older one is dropped, one
carrying the held content again writes nothing, and anything else is stored
before `WatchSessionStore.pruneWater(keepingRecordId:)` drops the row it
replaced; a relaunch holds the newest stored row
(`WatchWaterStateTests.testS94b4OneFrameRowAfterEachApplyAndARelaunchHoldsTheNewest`,
`…testS94b5TheNewestFrameWinsAndARepeatWritesNothing`,
`…testS94b6AFrameTheWristCannotReadChangesNothing`). A launch drops the
wrist's own taps that a receipt names and that were logged more than
`WatchWaterLimits.confirmedTapRetention` ago, before any local today began, so
no count can read them; unconfirmed taps, other rows and the confirmation rows
stay (`WatchWaterPruneTests.testS94c10TheLaunchDropsOnlyOldConfirmedTapsInMemory`,
`…OnFile`). `WatchWaterState.restore()` is that prune's only caller and
`pruneConfirmed()` has none
(`WatchWaterBarSourceTests.testS94b25aPruneConfirmedHasNoCallerAndOnlyLaunchPrunesTaps`).

### The wrist keeps one copy

The wrist holds ONE copy of the newest bests. A frame older than the copy it
holds is understood and dropped, a frame carrying the numbers it already holds
writes nothing at all, and the old copy is dropped only after the new one is
stored (`WatchSessionStore.pruneBests(keepingRecordId:)`, which the holder
calls on its store), so a store that is
append-only does not grow a row per sync. Memory is at most the frame's 300
exercises plus one best per exercise the wrist itself logged, and holding them
reads no history. A frame the wrist cannot read is refused whole, with the
previous copy still deciding, and a wrist that never received a frame says
nothing: no banner, no record tap, no change. Verified by
`WatchPersonalBestsTests.testS87b11ThreeFramesLeaveOnlyTheNewestAndARestoreReadsIt`,
`…testS87b11EqualEntriesTwiceAppendOnce`,
`…testS87b11AnOlderFrameIsUnderstoodAndDropped`,
`…testS87b13AMalformedFrameIsRefusedWholeAndThePreviousCopyStillDecides`,
`…testS87b2AWristThatNeverReceivedAFrameSaysNothing`,
`WatchPersonalBestsStoreTests.testS87b19APruneKeepsExactlyTheNamedRow` and
`…testS87b11AStoredBestsRowReadsBackAfterRelaunch`.

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
