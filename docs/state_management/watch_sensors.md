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
| Writing the readings one at a time | `WatchSensorWrites`, inside `WatchSensorRecorder` |
| Starting and stopping both together | `WatchSessionSensors` |
| Starting and stopping the sensors with the session | `WatchSensorCoordinator` |
| The real sensor source on the wrist | `HealthKitSensorFeed` (`HealthKitWorkoutStore.sensorSource`) |
| Whether a session records GPS | `WatchGpsPolicy`, reading the modality's capability profile |
| Modality → platform workout type | `WatchActivityTypes` |
| What is computed from the readings before they may go | `WatchSensorSummaries`, pure functions over stored rows, called by `WatchLoggingState.log` for an entry and by `WatchSessionEngine` for a `session_end` |

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
statistics to beats per minute and cumulative steps, reports location
unavailable (no location subscription) and never prompts
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
Nothing on the wrist feeds a fix yet: the app target's feed still reports
location unavailable
(`WatchSensorSourceSourceTests.testS3109TheFeedIsTheRealSourceAndTheStoreReadsBothTypes`),
so no behaviour a user sees has changed — the feed is plan 19f's. And a logged
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
- **GPS activation derives from the modality's capability profile, never from its
name.** A modality added later is handled without touching the policy, and one
that merely sounds like distance work does not wake the radio. Verified by
`test/watch_sensor_recording_test.dart` (`S-008`) and by watchOS
`WatchSensorRecordingTests.testS008TheGpsDecisionFollowsTheCapabilityProfile`.
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
a change on one platform fails the other's tests.
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
- **Two prunes, both gated on having nothing to lose.** The store's public surface
is exactly `append`, `readAll`, `pruneConfirmed` and `pruneSensorSamples`;
confirmed observations go first, and a session's sensor log goes only after the
session is over, all of its entries are acknowledged and — for a session the
wrist created — its `session_end` is acknowledged, pruned or not. Verified by
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

> **Doc freshness** — Last reconciled against source: 2026-10-10. This page is one part of [State Management & Services](../state_management.md); see that index for the full class list. This doc is derived from source, not hand-maintained. Source of truth: the `lib/` tree. If you find a claim here that disagrees with `lib/`, `lib/` wins.
