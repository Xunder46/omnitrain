# The Watch Sensors and the Platform Workout

**Scope.** The watch's sensor layer and the platform workout it records inside:
`lib/watch/sensors/`, `watch/watchos/Sources/WatchSessionEngine/`, and the
summaries computed from the sensors' readings.

> Part of [State Management & Services](../state_management.md). The mirroring
> surface these sensors run alongside is [The Watch Surface](watch_surface.md);
> return to that index for the full class list and dependency graph.

---

## Watch Sensors and the Platform Workout

Both watch clients run the same layer: `lib/watch/sensors/`
and `watch/watchos/Sources/WatchSessionEngine/WatchPlatformWorkout.swift` +
`WatchSensorRecording.swift`. The steps sensor and the summaries
(`WatchSensorSummaries.swift`) exist only in the watchOS package:
`lib/watch/` records no steps and computes no summaries.

### Structure

| Concern | Owner |
|---------|-------|
| The OS-level workout registration | `WatchPlatformWorkout`, over the watch app target's `HealthKitWorkoutStore` |
| What keeps the workout in step with the session | `WatchWorkoutCoordinator`, asking `WatchWorkoutLifecycle`'s rule over `WatchPlatformWorkout` |
| What the device's sensors read | `WatchSensorRecorder`, over a `WatchSensorSource` the app target implements |
| Raw location fixes turned into the cumulative metres the sensor seam expects | `WatchDistanceTracker` (`accept(_:)`, `totalMeters`), pure, in the watchOS package |
| Any raw fix source, seen as the sensor seam's location stream | `WatchTrackedLocation`, over a `WatchRawFixSource` |
| The wrist's raw position readings, behind that seam | `CoreLocationRawSource` (`ios/OmniTrain Watch App/CoreLocationRawSource.swift`), a `CLLocationManager` over `WatchRawFixSource` |
| Whether the registered workout is outdoor | `WatchPlatformWorkout.start`, asking the store's `begin(_:outdoors:)` over `WatchGpsPolicy` |
| Writing the readings one at a time | `WatchSensorWrites`, inside `WatchSensorRecorder` |
| Starting and stopping both together | `WatchSessionSensors` |
| Starting and stopping the sensors with the session | `WatchSensorCoordinator` |
| The real sensor source on the wrist | `HealthKitSensorFeed` (`HealthKitWorkoutStore.sensorSource`) |
| Whether a session records GPS | `WatchGpsPolicy`, reading the modality's capability profile and the current exercise's capabilities |
| Following the exercise the user is on | `WatchSensorRecorder.sessionChanged`, called by `WatchSensorCoordinator.apply` |
| Modality → platform workout type; a session with no modality takes the majority of its exercises' capabilities | `WatchActivityTypes` (`forModality`, `forSession`) |
| What is computed from the readings before they may go | `WatchSensorSummaries`, pure functions over stored rows, called by `WatchLoggingState.log` for an entry and by `WatchSessionEngine` for a `session_end` |
| What the wrist says when access is off | `WatchLoggingState.sensorNotices` (forwarded by `WatchLoggingModel.sensorNotices`), from `WatchSensorRecorder.heartRateAccess` / `locationAccess` — `WatchSensorPermission?`, nil until asked this session, cleared by `stop()` |
| Whether Health access is allowed, off or unavailable | `WatchHealthAccess` (`WatchHealthAccess.swift`), asked by the host's `askHealthAccess()` over `HealthKitWorkoutStore.requestAccess()` |

`WatchSensorSource` and `WatchPlatformWorkoutStore` are the seam the OS bindings
sit behind: `HKWorkoutSession`, `HKLiveWorkoutBuilder` and `CLLocationManager`
exist only in an app target, beyond `swift test` and any Dart suite. The workout seam's real binding is the watch app target's
`HealthKitWorkoutStore`; the sensor seam's is `HealthKitSensorFeed`
(`ios/OmniTrain Watch App/HealthKitSensorFeed.swift`), exposed as
`HealthKitWorkoutStore.sensorSource` and wired by the host into a
`WatchSensorRecorder` inside a `WatchSensorCoordinator` that the host refreshes after the workout (`ContentView.swift`;
`WatchSensorSourceSourceTests.testS3110TheHostWiresTheSensorsAndRefreshesTheWorkoutFirst`).
The coordinator starts the sensors with the session and stops them when it ends
or is replaced, and the exercise screen's live heart-rate line reads the newest
beat
(`WatchSensorCoordinatorTests.testS3100StartSubscribesAndTheFirstBeatIsStored`,
`…testS3101EndStopsAndClearsTheRecordingSessionId`,
`…testS3102AReplacedSessionStopsOneAndStartsTheOther`,
`…testS3108TheLiveLabelShowsTheNewestBeat`); the feed reduces the builder's
statistics to beats per minute and cumulative steps, and delegates its two
location members to the `WatchTrackedLocation` it is given — it never prompts
for location itself
(`WatchSensorSourceSourceTests.testS3109TheFeedIsTheRealSourceAndTheStoreReadsBothTypes`,
`…testS3114TheFeedNeverPromptsAndAnswersUnavailableWithoutHealthData`); the
summaries reach the phone through the existing capture path: the session-end
carries the sensors' heart rate
(`…testS3107TheSessionEndCarriesTheHeartRateTheSensorsFedIt`), a timed entry the
step total (`…testS3115ATimedEntryCarriesTheStepTotalTheRecorderFedIt`).

### Rationale

**Sensor readings are stored rows, not fields.** A heart rate or a distance is
appended to the watch's own store like everything else, and the live readout is
derived from the newest stored row. A value held in memory would be the one thing
on the wrist that a kill loses.

**The wrist computes its own distance, and an effort's distance is its own
window.** `WatchDistanceTracker` turns raw location fixes into a monotonic
total of metres: a fix is accepted or ignored, never corrected — the accuracy
gate, the speed gate, the time-order gate and the jitter floor are each a
reason to add nothing, and the first accepted fix is only the origin.
Verified by watchOS `WatchDistanceTrackerTests`
(`testS3200AcceptedFixesAccumulateTheGreatCircleTotal`,
`testS3201AnInaccurateFixIsNeverAnOriginAndNeverAdds`,
`testS3202AJumpIsIgnoredAndLeavesTheReferenceWhereItWas`,
`testS3203AStillWristsDriftNeverAccumulates`,
`testS3204ASlowCreepClearsTheFloorAndMovesTheReference`,
`testS3205AFixNotAfterTheLastAcceptedOneIsIgnored`,
`testS3220TheFloorScalesWithTheFixesOwnAccuracy`).
`WatchTrackedLocation` adapts any raw fix source to the sensor seam's location
stream — a fresh total per subscription, finishing and cancelling with the raw
stream, the permission answer passed through. Verified by watchOS
`WatchDistanceTrackerTests`
(`testS3206TheAdapterMapsTheSourcesFixesIntoOneMonotonicTotal`,
`testS3206TheMappedStreamFinishesWhenTheRawOneDoes`,
`testS3206CancellingTheMappedStreamStopsConsumingTheRawOne`,
`testS3207TheRecorderCarriesTheTrackedTotalAndSettlesIt`,
`testS3207DeniedRawPermissionSkipsLocationAndLoggingCarriesOn`).
The wrist now feeds fixes: the host builds the store over a
`WatchTrackedLocation` whose source is `CoreLocationRawSource`, a
`CLLocationManager` behind the package's `WatchRawFixSource` seam
(`WatchSensorSourceSourceTests.testS3313TheHostBuildsTheSourceAndTheAdapterOnce`,
`…testS3310TheRawSourceAsksWhenInUseAndNeverAlways`), and the feed hands its
two location members straight to that adapter
(`…testS3311TheFeedDelegatesItsLocationToTheAdapter`). The first time a session reaches distance work — a cardio or sports
modality, or the exercise the user is on carrying the `distance` capability —
the wrist asks for Location while in use — after the
Health question, which the Start screen asks the first time it shows (a
relaunch straight into a live session shows no Start screen, so Health still
asks at the first workout open there;
`WatchHealthAccessWiringSourceTests.testS8908HostAsksWhenTheStartScreenShows`),
with the sentence the watch target's
`INFOPLIST_KEY_NSLocationWhenInUseUsageDescription` carries
(`…testS3314TheWatchTargetAsksForLocationInOneSentenceAndNeverAlways`) — and
the HealthKit workout of such a session is registered as outdoor
(`WatchOutdoorWorkoutTests.testS3300OutdoorsFollowsTheCapabilityProfile`,
`WatchSensorSourceSourceTests.testS3312TheStoreTakesTheAdapterAndRegistersOutdoors`).
The workout is registered once (D-4803 of plan 40): a session with a modality
registers at its start, and a session with no modality — every Free workout —
waits until its type is known and registers the moment the first exercise is
picked; nothing re-registers it mid-session, and a later exercise never
changes the type Health fixed at open
(`WatchWorkoutTypeFromExercisesTests.testS8807AFreeWorkoutWaitsForItsFirstExercise`,
`…testS8808ALaterExerciseNeverChangesTheOpenWorkout`,
`…testS8809AModalityWinsOverTheExercises`), so a walk added later to a free
workout that began on a lift still records distance
(`WatchGpsByExerciseTests.testS4803TheFeedStaysOnWhenTheUserMovesBackToALift`),
and Apple Health keeps the type the workout opened with
(`WatchGpsByExerciseTests.testS4807TheWorkoutIsRegisteredOutdoorsByTheExerciseTheUserIsOn`).
The type itself: a session with a modality keeps the modality table's type; a
session with none takes the majority of its exercises' capabilities — `hold`
→ flexibility, else `distance` → running, else any of `reps`/`sets`/`load` →
traditionalStrengthTraining, else other — with a tie going to the earliest
exercise that reaches the top count and an empty list meaning "not yet known"
(`WatchWorkoutTypeFromExercisesTests.testS8801ALiftSessionRegistersAsStrengthTraining`,
`…testS8802ARunSessionRegistersAsRunningAndOutdoors`,
`…testS8803AHoldRegistersAsFlexibilityAndAPlankStaysOne`,
`…testS8804TheMajorityDecides`, `…testS8805ATieGoesToTheEarliestExercise`,
`…testS8806ATimedSlotIsGenericAndAMajorityIsNot`,
`…testS8810TheLifecycleWaitsForAKnownType`,
`…testS8811EmptyIsUnknownAndACapabilityLessSlotIsGeneric`).
The store asks to share the workout type and active energy and to read heart
rate, steps and active energy — one request — and collects active energy on
the live data source, so the saved workout carries calories
(`WatchSensorSourceSourceTests.testS8812TheStoreSharesAndReadsActiveEnergySoTheWorkoutSavesCalories`).
The ask is made through `HealthKitWorkoutStore.requestAccess()`, which answers
as `WatchHealthAccess` (`allowed` / `off` / `unavailable`) and joins the one
memoised request, so no second sheet rises later
(`WatchHealthAccessWiringSourceTests.testS8908StoreHasRequestAccessAnsweringWhatTheWristCanRead`,
`WatchSensorAccessNoticeTests.testS8907TheAnswerFollowsAvailabilityAndGrant`);
when the answer is `off`, the Start screen shows "Health access is off. Turn it
on in Health on your iPhone." (`WatchHealthAccessCopy.offLine`;
`WatchHealthAccessWiringSourceTests.testS8908StartViewSaysHealthAccessIsOff`,
`WatchSensorAccessNoticeTests.testS8907TheStartScreenLineTextIsExact`). Apple
does not report a refused *read* permission, so "access off" is read from the
workout-share permission: a user who allows the workout but refuses only heart
rate gets no line (platform limit, stated in plan 59).
The ask is never latched — every parked waiter dispatches its own
`requestWhenInUseAuthorization()`, so an expired "Allow Once" is asked again,
and an answered status ends the pending ask without a prompt
(`WatchSensorSourceSourceTests.testS3317TheAskIsNeverLatched`) — and a
permission revoked mid-session ends the feed
(`…testS3318ARevokedPermissionEndsTheFeed`). Known limitation (D-2316): a
session that ends while the Location question is still on screen keeps its
sensors until the user answers — the stop waits behind the parked start on the
sensors' serial tail.
A cached fix older than the adapter's `maxFixAgeSeconds` (10 s,
`WatchTrackedLocation.init`) at a subscription's start is dropped before the
tracker sees it
(`WatchDistanceTrackerTests.testS3303ACachedFixNeverBecomesTheOrigin`,
`…testS3304TheGateBoundaryIsInclusive`, `…testS3306TheClockIsReadOncePerCall`).
Refused or unavailable location leaves logging, rest, the menu and sync working
and sends no distance
(`WatchDistanceTrackerTests.testS3207DeniedRawPermissionSkipsLocationAndLoggingCarriesOn`,
`WatchSensorSourceSourceTests.testS3315LocationOffAnswersUnavailableBeforeAnyStatusIsRead`,
`WatchSensorRecordingTests.testS006HardwareThatIsNotThereIsNotAFailure`);
lifts and holds never ask and never use location
(`WatchOutdoorWorkoutTests.testS3300OutdoorsFollowsTheCapabilityProfile`,
`WatchGpsByExerciseTests.testS4801ALiftNeverStartsGpsAndNeverAsks`); free
training and routines ask and use location only once the user is on an
exercise that carries the `distance` capability
(`WatchGpsByExerciseTests.testS4800AWalkInAFreeWorkoutStartsGps`,
`…testS4802GpsStartsWhenTheUserReachesTheWalk`). No
route or map is stored. All of this is verified in code and builds only:
nothing here is proven on a wrist.

**When access is off, the wrist says so.** `WatchLoggingState.sensorNotices`
returns "No heart rate, Health access is off" when the recorder's
`heartRateAccess` is `.denied`, and "No distance, Location access is off" while
the current exercise's capabilities carry `distance` and `locationAccess` is
`.denied` — heart rate first, and `[]` with no sensors or an `.unavailable`
permission (`WatchSensorAccessNoticeTests.testS8904ADeniedHeartRateBecomesTheNoticeLine`,
`…testS8905TheDistanceNoticeShowsOnTheRunAndNotOnTheLift`,
`…testS8905BothRefusalsReadHeartRateFirstThenDistance`,
`…testS8906NoSensorsMeansNoNotices`,
`…testS8906AnUnavailablePermissionSaysNothing`). `WatchLoggingModel.sensorNotices`
forwards the list and `WatchLoggingView` renders each as a grey `caption2` line
under the status line
(`WatchHealthAccessWiringSourceTests.testS8908LoggingViewShowsSensorNotices`).
The recorder's answers are per session: nil until asked, and `stop()` clears
them (`WatchSensorAccessNoticeTests.testS8901HeartRateAccessIsNilBeforeStartAndTheAnswerAfter`,
`…testS8902StopReturnsBothAccessesToNil`,
`…testS8903ADeniedLocationOnADistanceSessionIsRemembered`,
`…testS8903ALiftSessionNeverAsksSoTheAnswerStaysNil`). And a logged
timed effort's `distanceMeters` is the metres covered between its Start and its
Log — a chain over the session's stored `gps` samples inside that window,
starting from the baseline total at Start, never the session total, never the
metres before Start, and never the settled `distance` sample. A total below the
previous one means the location subscription restarted, and the metres since
the restart count — the same rule the steps summary uses. Verified by watchOS
`WatchEffortDistanceTests`
(`testS3208AnEffortCarriesItsOwnWindowsMetres`,
`testS3209MetresBeforeStartAreNotTheEfforts`,
`testS3216ASettledDistanceSampleIsNotTheEffortsDistance`,
`testS3212ARelaunchedStateLogsTheSameWindow`,
`testS3221ARestartedTotalInsideTheWindowIsTheMetresSinceTheRestart`) and by
`WatchSensorSummaryTests.testAStepCounterThatRestartedAddsItsNewCount` for the
steps rule the restart case mirrors.

**Sensor rows are dropped with the session, not with a receipt.** Observations
are gated on the phone's receipt because the phone is their destination. A
reading's destination is the session that produced it: once a session is over and
every entry it produced — and, for a session the wrist created, its `session_end`
— has been acknowledged, its raw log has done its job. The distance that reached
the phone is already the logged effort's `distanceMeters` — the protocol's own
field — so no message type was added and the phone holds one source of truth for
how far the user went. A session still running, or one with an entry still
awaiting a receipt, keeps its log, which is what keeps the live readout and the
settled distance across a kill.

**Summaries are computed on the wrist, once, before the readings may go.** The
phone never receives a raw reading, and the wrist prunes its readings once the
phone holds the session, so anything derived from them has to be derived first and
carried by an event the phone already imports. An entry's heart rate, and a timed
entry's steps, are computed when it is logged, over the window the event itself
states; the session's heart rate and each set block's are computed into the
`session_end`, because a set has no window of its own — it carries only the moment
it was logged. Nothing is recomputed afterwards: the stored event is what is re-sent,
so the phone never sees one entry with two sets of values.

**One writer.** Every sensor streams on a task of its own — with steps recorded
in every session the user allows it for, at least two run at once — and the
engine and its store are built for one writer, so the recorder chains its writes
(`WatchSensorWrites`).

**The workout is recovered, not resumed.** A kill cannot be caught, so the next
launch ends whatever the health store still reports as running rather than trying
to adopt it. The session it belonged to is already over, and its logged entries
are in storage either way. Verified by
`test/watch_sensor_recording_test.dart` (`S-005`) and by watchOS
`WatchSensorRecordingTests.testS005TheNextLaunchEndsTheWorkoutTheKillLeftBehind`.

### Invariants

- **The workout follows the session.** One workout at a time: exactly one begin and one
end per session however often the surface refreshes, and a launch ends what a previous
process left open before a session can open another. Verified by watchOS
`WatchWorkoutCoordinatorTests` (S-1500...S-1505, S-1507, S-1508, S-1510).
- **GPS activation derives from the modality's capability profile and the current
exercise's capabilities, never from a name.** A modality added later is handled
without touching the policy, and one that merely sounds like distance work does
not wake the radio; an exercise decides the same way, by its `capabilities`
list, not by what it is called. Verified by
`test/watch_sensor_recording_test.dart` (`S-008`) and by watchOS
`WatchSensorRecordingTests.testS008TheGpsDecisionFollowsTheCapabilityProfile`.
- **GPS is a latch for the session.** Once the feed starts it runs until the
session stops: moving back to an exercise without distance neither stops it nor
resets the cumulative total, and however often the sensors refresh, a granted
session subscribes once. Verified by watchOS
`WatchGpsByExerciseTests.testS4803TheFeedStaysOnWhenTheUserMovesBackToALift`
and `…testS4805AGrantedWalkSubscribesOnceHoweverOftenTheSensorsRefresh`.
- **A refusal is asked once per session.** A permission read that comes back
denied or unavailable ends the asking for that session — logging carries on
with no `gps` samples — and only `stop()` restores the question for the next
one. Verified by watchOS
`WatchGpsByExerciseTests.testS4804ARefusedSessionIsAskedAboutOnceAndANewOneAgain`,
`…testS4815UnavailableIsAnsweredOnceLikeDenied` and
`…testS4814ASecondSessionMeasuresAgain`.
- **A denied permission or absent hardware never blocks logging.** The
subscription is skipped and nothing else changes; sensor fields are simply
absent. Verified by `S-006` in both sensor suites.
- **An effort's distance is its own window.** A timed effort carries the metres
covered between its Start and its Log — a chain over the session's stored `gps`
samples inside that window, starting from the baseline total at Start; a total
below the previous one is a restarted subscription and counts as the metres
since the restart — never the session's newest total, never metres from before
Start, and never the settled `distance` sample. Verified by watchOS
`WatchEffortDistanceTests`
(`testS3208AnEffortCarriesItsOwnWindowsMetres`,
`testS3209MetresBeforeStartAreNotTheEfforts`,
`testS3216ASettledDistanceSampleIsNotTheEffortsDistance`,
`testS3212ARelaunchedStateLogsTheSameWindow`,
`testS3221ARestartedTotalInsideTheWindowIsTheMetresSinceTheRestart`).
- **A measured distance never travels without its source.** When a timed
effort's window covered metres, its payload carries `distanceMeters` and
`distanceSource: "gps"` together; a window that moved nothing, and a hold
logged while the sensors measure, carry neither. Verified by watchOS
`WatchEffortDistanceTests`
(`testS3210TheSourceTravelsAndOnlyBesideADistance`,
`testS3211AWindowThatMovedNothingCarriesNoDistance`,
`testS3219AHoldLoggedWhileMeasuringCarriesNoDistance`).
- **Both clients read one vocabulary.** The sample kinds, the modality → workout
type table and the capability profile the GPS decision depends on live in
`watch/contract/watch_sensor_contract.json`, and both suites assert against it, so
a change on one platform fails the other's tests. The contract carries the
modality table only
(`WatchSensorRecordingTests.testS007EveryMappedModalityNamesBothPlatforms` pins
its values); the majority rule that types a session with no modality lives in
Swift alone, `WatchActivityTypes.forSession`, pinned by the
`WatchWorkoutTypeFromExercisesTests` group.
- **A reading is stored, never sent.** Sensor rows are written through the same
append entry point as every other row and emit nothing; the measured distance
reaches the phone inside the logged effort. Verified by
`test/watch_sensor_recording_test.dart` (`a reading is stored without being sent
anywhere`) and by watchOS
`WatchSensorRecordingTests.testAReadingIsStoredWithoutBeingSentAnywhere` and
`WatchSensorRecordingTests.testS239AppendingAStepCountEmitsNothing`.
- **The summary fields are the only values derived from readings on the wire,
and none is ever recomputed.** They are the heart-rate, steps, pause and set-block
fields `watch/sync_protocol/PROTOCOL.md` lists under "Session capture"; a re-send
carries the stored event, whatever readings arrived later. Verified by watchOS
`WatchSensorSummaryTests.testS238ALateReadingNeverRewritesWhatWasSent` and
`WatchCaptureContractTests`, which replays
`watch/contract/watch_capture_contract.json` and compares every event.
- **Nothing measured is absent, never zero.** A window with no qualifying reading
gets no pair and no step total, and a reading a summary could not send — below the
protocol's heart-rate minimum, negative, or not a number — is not a reading. A
summary therefore never makes its event unsendable. Verified by watchOS
`WatchSensorSummaryTests.testS235WithTheSensorsDeniedNoEventCarriesASummary` and
`WatchSensorSummaryTests.testAReadingBelowOneBeatPerMinuteIsNotAHeartRate`.
- **Steps change nothing else.** With steps permission refused, every other sensor
behaves exactly as with it granted. Verified by watchOS
`WatchSensorRecordingStepsDeniedTests`, which runs the whole sensor suite again with
steps denied, and `WatchSensorRecordingTests.testS239StepsPermissionChangesNothingButTheStepsRecorded`.
- **Three prunes, each gated on having nothing to lose.** The store's public surface
is exactly `append`, `readAll`, `pruneConfirmed`, `pruneSensorSamples` and
`pruneExerciseBatches`;
confirmed observations go first, and a session's sensor log goes only after the
session is over, all of its entries are acknowledged and — for a session the
wrist created — its `session_end` is acknowledged, pruned or not; a batch prune
with no rows of another version to drop writes nothing
(`WatchFileStoreTests.testS3835APruneWithNoBatchesWritesNothing`). Verified by
`test/watch_session_engine_test.dart` (`S-004 append-only enforcement at the
storage API`) and by watchOS
`WatchSessionEngineTests.testS004NoMutatingOperationExistsAnywhereInTheModule` and
the `S-237` cases in `WatchSensorRecordingTests`.
- **A prune that cannot be written replaces nothing, and a pruned row takes its
lens with it.** The file keeps its rows and the cache keeps reading them, with no
staging file left in the store's directory (`WatchFileStoreTests`
`testF2APruneThatCannotBeWrittenPrunesNothing`,
`testG1APruneOfSensorSamplesThatCannotBeWrittenPrunesNothing`,
`testG2AFailedReplaceLeavesNoTemporaryFile`). A pruned row also takes the
correction the phone sent for that id and any deletion marker against it (D-52),
so a re-carried id reads as what was delivered instead of through a lens left
over from a row that is gone
(`WatchSessionEngineTests.testS48APrunedRowTakesItsCorrectionWithIt` and
`…testS48APrunedRowTakesItsDeletionMarkerWithIt`; `test/watch_session_engine_test.dart`
group `S-48 a pruned row takes its lens with it (G3)`).
- **Timers travel as wall-clock timestamps.** A countdown is never sent;
either end derives it, which is what keeps a timer correct through a
suspension or a reconnect. Verified by `test/live_mirroring_test.dart`
(`S-005 the timer's end moment is the same on both devices`).
- **A message a receiver cannot read is refused whole.** Nothing is applied, and
the refuser answers with its own snapshot so the peer converges from real state
instead of from a stream it could not interpret. Verified by
`test/live_mirroring_test.dart` (the two `a message the receiver cannot read`
cases) and by watchOS
`WatchLiveMirroringTests.testAVersionMismatchIsRefusedAndAnsweredWithASnapshot`.

### Vocabulary

- **Snapshot exchange** — the connect/reconnect handshake defined in
`PROTOCOL.md` under "Idempotency and reconciliation".
- **Correction vs. observation** — an observation is an append by whoever logged
it and is never edited; a correction is the phone's edit to an existing entry,
which the watch reflects without rewriting its own history.
- **Reflection** — a watch's copy of session structure or timer state, which it
holds but does not originate, and which the phone's reset ends when the phone
holds a different session of its own (D-170; `PROTOCOL.md`'s 2026-10-08 row).
`PROTOCOL.md` authority rules 1 and 2 are what
make the distinction consequential.
- **Session end, set block** — defined in
[Watch Session Capture](../watch_session_capture.md), which owns what the wrist
sends for the import.

---

> **Doc freshness** — Last reconciled against source: 2026-10-23. This page is one part of [State Management & Services](../state_management.md); see that index for the full class list. This doc is derived from source, not hand-maintained. Source of truth: the `lib/` tree. If you find a claim here that disagrees with `lib/`, `lib/` wins.
