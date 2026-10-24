# The Watch Surface — the Wrist's Half

**Scope.** The wrist side of the live session mirror: the Swift connectivity
bridge over the same radio, the wrist's start surface and the wrist's logging
surface (the Digital Crown and the per-exercise dialled numbers included), in
`watch/watchos/Sources/WatchSessionEngine/` and the app target
`ios/OmniTrain Watch App/`.

> Part of [State Management & Services](../state_management.md), split from
> [The Watch Surface](watch_surface.md) on 2026-10-20 to keep that page under
> the size band. Nothing was dropped: the three sections below moved verbatim
> (headings promoted one level). The phone side of the mirror and the area's
> invariants stay in [The Watch Surface](watch_surface.md).

---

## The wrist's half of the same radio

**Files**: `watch/watchos/Sources/WatchSessionEngine/WatchConnectivityBridge.swift`,
`.../PropertyListFrames.swift`; the real session is
`ios/OmniTrain Watch App/OmniTrainWatchConnectivity.swift`.

The wrist's transport is written against a seam rather than against
`WatchConnectivity`: `WatchConnectivitySession` is send, report a failure, report
reachability and deliver an arriving frame, and `WatchConnectivityBridge` is the
`WatchSyncTransport` conformance over it. That seam is what lets the whole bridge
run under `swift test` on macOS against a fake session; the only file that
imports `WatchConnectivity` is the app target's, and it supplies the real
session and nothing else.

**A request frame is byte-for-byte the phone's shape and carries no `type`**,
because the presence of `type` is what makes a frame a message rather than a
request. `since` is omitted rather than nulled when the wrist has never synced,
and is formatted by the package's own UTC encoder — three fractional digits,
where Dart's `toIso8601String()` can emit six. The divergence is known and
unread, because the phone ignores `since` today. The three frames are pinned in
`watch/contract/watch_start_paths_contract.json` under `transportRequests`, which
both suites read. Verified by
`WatchConnectivityBridgeTests.testS102FirstSyncAsksForRoutinesWithNoSince`,
`…testS103LaterSyncCarriesSince` and `…testS104SyncWithNoSessionAsksForASnapshot`.

**An outbound frame is checked for plist safety before the radio sees it.** A
`WCSession` message dictionary holds property-list values only, and `NSNull` is
not one — the platform rejects the whole message, so the check refuses the frame
rather than stripping the null, and reports it through the same failure hook a
refused send uses. `Date` becomes the package's UTC string, and `String`, `Bool`,
`NSNumber`, arrays and dictionaries of accepted values pass through **unchanged**
— an `Int` stays an `Int` and a `Double` stays a `Double`, because the protocol's
integer fields are integers and the phone's validator refuses a whole-number
`Double` (witness: `fixtures/invalid/observations_up_steps_as_double.json`). The
refusal costs nothing today because the wrist's wire encoders omit absent
optional fields rather than nulling them; it turns a future regression into a
reported failure instead of a silently dropped message. Verified by
`WatchConnectivityBridgeTests.testS112TheFramesTheWristSendsSurviveThePlistRoundTrip`,
`…testS113AFrameThatCannotBeRepresentedIsReported` and
`…testD5NumbersAreNeverCoerced`.

**A live-only frame that fails is still reported and dropped**, and recovery is
the next `sync()` re-sending from storage. **A durable frame the radio refuses
is queued instead.** `WatchConnectivitySession` gained `queue` — hands the phone
one frame the OS delivers later — and `WatchConnectivityBridge.isDurable` is
true exactly for `observations_up` and `session_lifecycle`: when `send` fails, a
durable frame goes to the queue rather than being reported, a queue that itself
refuses is reported through the same failure hook, and a frame that sends is
never also queued. The app target's `OmniTrainWatchConnectivity` queues with
`transferUserInfo`, skipping a transfer whose `messageId` is already
outstanding, and receives `didReceiveUserInfo` like a message; the OS delivering
a queued transfer to a closed phone app is an owner check on real devices.
Verified by `WatchBridgeQueueTests.swift` (S-6701..S-6707) and
`WatchQueueSourceTests.swift` (S-6708). **The bridge itself still sends nothing
unsolicited** — it answers a user action or nothing, so a Sync is still the only
thing that asks the phone for an answer. Verified by
`WatchConnectivityBridgeTests.testBridgeSendsNothingUntilAsked` and
`…testASendThePlatformRefusesIsReported` (a refused request frame, the live-only
case).

**Reachability is three-state, and starts unknown.** The start surface carries one
status line: "Phone connected" or "Phone not reachable", said only once the radio
has answered; a launch that has asked nothing says nothing on that line. `WatchPhoneReachability.unknown` is the state a `Bool` cannot
express, which is why the app target's host starts there and moves only when the
bridge reports what the platform observed — the platform's answer is always an
observation, never a "not yet". Verified by
`WatchConnectivityBridgeTests.testS111TheSurfaceSaysConnectedOrUnreachableOnlyAfterObservingIt`.
The sentence lives in the package's `WatchStartSurfaceCopy` rather than the
contract's `startSurface` block; it moves into the contract if the Wear OS client
ever ships a transport.

**A link that cannot come up at all is said, not just a phone out of reach.** The
real session (`ios/OmniTrain Watch App/OmniTrainWatchConnectivity.swift`) records
a link problem when `WCSession.isSupported()` is false, or when
`activationDidCompleteWith` ends with an error or a state other than
`.activated`, and reports it through `onLinkProblem(_:)` — once at registration,
and again on every activation result, a good activation reporting false so the
line goes away when the link comes up. The host's `linkUnavailable` follows it,
and `WatchAppHost.phoneProblem` boils the phone's problems down to one line for
the surface: the link line first, else the no-answer line below, else nil;
`WatchStartView` renders it under the phone status line. The copy is
`WatchStartSurfaceCopy.linkUnavailableLabel`, deliberately not a contract value
like `syncingLabel`. Verified by
`WatchPhoneProblemWiringSourceTests.testS9004TheRadioReportsWhenItCannotComeUp`
and `…testS9004TheHostRaisesTheNoAnswerAndLinkLines` (source text — the views
compile only under xcodebuild), and the sentence itself by
`WatchSyncNoAnswerTests.testS9002LinkUnavailableLabelIsExactlyThePlannedSentence`.

**What is still owed is said on both surfaces.** Under the status line on the
start surface, and at the top of the session menu (the list button's sheet), one
line says when what you logged is still waiting for the phone: "1 entry waiting
for your phone" or "N entries waiting for your phone". The line is the pure
function `deriveSyncNotice(pending:reachability:now:)` in
`watch/watchos/Sources/WatchSessionEngine/WatchSyncNotice.swift`, with the copy
and the wait in `WatchSyncNoticeCopy`: nothing when nothing is pending; always
when the radio says the phone is unreachable; when the phone is reachable or not
yet known, only once the oldest pending entry has waited
`WatchSyncNoticeCopy.graceSeconds` or more, so a receipt that lands within a
second or two shows nothing. A rest window the wrist stores between two efforts
is neither counted nor aged. The pending list is
`WatchSessionEngine.unconfirmedObservations` — the stored observations with no
receipt — and the shell host derives `syncNotice` at render and hands it to
`WatchStartView` and `WatchMenuView`; the logging and rest screens carry no such
line (plan 51d D-4: no room on 40 mm). Verified by
`WatchSyncNoticeTests.testS7701NoPendingIsNilForEveryReachability`,
`…testS7702UnreachableSaysTheCountOfFreshEntries`,
`…testS7703ReachableWaitsForTheGraceAndCountsAllPending`,
`…testS7704UnknownGetsTheSameGraceAsReachable`,
`…testS7705TheExactGraceBoundaryShows`,
`…testS7706TheEngineCountsUnconfirmedAndAReceiptRemovesOne`,
`…testS7708RestWindowsAreNotCounted` and the source guards
`…testS7707TheShellHostPassesTheNoticeToBothViews`,
`…testS7707BothViewsDeclareAndShowTheNotice`.

## The engine's session-row writers run one at a time

**Files**: `watch/watchos/Sources/WatchSessionEngine/WatchAsyncMutex.swift`,
`.../WatchSessionEngine.swift`; the host hop is
`ios/OmniTrain Watch App/ContentView.swift`.

The engine's five session-row writers — `createSession`, `transitionTo`,
`applySnapshot`, `applyStructureChange`, `applyLifecycle` — serialise through
one first-in-first-out, non-reentrant `WatchAsyncMutex`: each public name keeps
its signature and the old body lives in a private `<name>Exclusive` function
run inside `exclusive`. The point is ordering, not exclusion of reads: each
writer is built from the latest session, so a menu pick and an overlapping
phone snapshot, structure change or lifecycle message both land and the later
arrival wins, and two starts at once make one session. Verified by
`WatchEngineSerialisationTests.swift` (S-6501..S-6505) and, for the mutex
itself, `WatchAsyncMutexTests.swift` (S-6506). The host bumps its refresh
counter for incoming messages on the main actor, so the surface is told on the
main thread while the engine work stays off it
(`WatchHostHopSourceTests.swift`, S-6507).

Known limits, stated honestly: the engine's timers and observations are not
serialised; the engine is not main-actor isolated; the mutex is not reentrant,
so `exclusive` must never be taken inside a body already inside it
(`WatchAsyncMutex.swift` says so at the top), and `applyMessage`,
`advanceExercise`, `selectExercise`, `finishSession`, `abandonSession`,
`insertExercise`, `applyExercisePush`, `stopTimer` and `appendTimer`
deliberately do not take it (plan 46c, D-5).

**Inbound frames are handled one at a time, and a stale snapshot is refused
whole.** `WatchInboundLane`
(`watch/watchos/Sources/WatchSessionEngine/WatchInboundLane.swift`) hands frames
to one handler one at a time in the order they were offered, and
`OmniTrainWatchConnectivity.deliver` (the app target) enqueues each radio
arrival on it instead of starting a task per frame. On top of that ordering,
`WatchSessionEngine.applySnapshotExclusive` refuses WHOLE — no entry stored, no
tombstone cleared, nothing answered — a snapshot whose `sentAt` is earlier than
`newestSnapshotAt`, the newest applied snapshot stamp across all workouts; the
stamp is rebuilt on `restore()` from the stored `snap-` rows' `recordedAt`. A
sender whose clock is set backwards by hand is ignored until its clock passes
the old instant. Verified by `WatchInboundLaneTests` (S-9310),
`WatchStaleSnapshotTests` (S-9311..S-9314) and
`WatchInboundLaneWiringSourceTests` (S-9315).

## The wrist's start surface, and what an arrival does to it

**A push with no session to land in is read and dropped.** The wrist's start
paths can only grow a session that exists, so an `exercise_push` arriving with
nothing open changes nothing, stores nothing and creates nothing: the engine
returns nil instead of requiring a session, and the message reports itself not
applied. The guard sits *after* the conformance gate on purpose — a frame this
build cannot read is still a refusal, while a readable frame with nowhere to go
is simply nothing to do. Verified by
`WatchConnectivityBridgeTests.testS110APushWithNoLiveSessionChangesNothing` and
`…testS108APushIntoAnOpenFreeWorkoutLands`.

**An arrival is a revision, not a listener.** `WatchSessionStartPaths` is a plain
class that publishes nothing, so the app target's host bumps its own revision on
every frame it routes and hands it to the start surface, which is what re-runs
the picker's body; the rows themselves are derived on every read. A row is keyed
by its own slot id rather than by the exercise, because one exercise may
legitimately hold two slots, and the session's slots come first with
`availablePickerExercises` — `addableExercises`, the menu's own A to Z list,
minus what the ladder already shows — behind them. Verified by
`WatchConnectivityBridgeTests.testPickerRowsListTheSessionFirstAndNeverTwice` and
`…testPickerRowsFallBackToTheFallbackListWhileTheSessionIsEmpty`, and the two
lists are one list in one order by
`WatchSessionStartPathsTests.testS3113AThePickerRowsAndTheAvailableExercisesAgree`.

**Closing the picker without a pick gives the empty Free workout back.** Dismissing
the picker sheet runs `WatchSessionStartPaths.cancelEmptyFreeWorkout()`, which
abandons the live session only when it is active and holds no exercise, and tells
the host, which re-reads the engine; after a pick, or when the phone pushed a slot
while the picker was open, nothing is cancelled, and the phone consumes an
abandoned empty session without history. Verified by
`WatchCancelEmptyFreeWorkoutTests` (S-8701..S-8706:
`testS8701CancellingAnEmptyFreeWorkoutAbandonsIt`,
`…testS8702AFreshFreeWorkoutStartsAfterTheCancel`,
`…testS8703ASessionWithAnExerciseIsNotCancelled`,
`…testS8704ASessionHoldingAPushedSlotIsNotCancelled`,
`…testS8705ACompletedSessionIsNotCancelled`,
`…testS8705WithNoSessionAtAllCancelIsFalse`,
`…testS8706ThePickerSheetCancelsOnDismissAndTheHostReReads`).

**A routine the watch no longer holds says so when you tap it.** A Sync that
replaces the list between the screen drawing and your tap leaves a row whose
copy is gone, and `WatchStartView.start(_:)` no longer swallows that: it catches
the one throw `paths.startFromRoutine` has (`WatchStartPathError.unknownRoutine`)
and shows `WatchStartSurfaceCopy.routineMissingLabel` under the routine buttons.
The line clears on the next start of any routine, and on any surface re-read —
`.onChange(of: revision)`, and the host bumps the revision on an arrival and on
a reachability change, so a Sync that brings the routines clears it too. The
Sync button itself is unchanged. Verified by
`WatchSyncNoAnswerTests.testS9003UnknownRoutineThrowsAndLeavesTheSessionUnchanged`
(the throw, and the session left exactly as it was),
`…testS9002RoutineMissingLabelIsExactlyThePlannedSentence` (the sentence) and
`WatchPhoneProblemWiringSourceTests.testS9004TheStartSurfaceSaysWhenARoutineVanished`
(the wiring: the catch, the two clears, the unchanged Sync button).

**A sync is finished by its replies, not by the request.** The watch's
orchestrator awaits only the sends, so the phone's answer arrives afterwards
through `receive` and "still syncing" cannot be read from the request. The
window therefore lives in the pure `WatchSyncProgress`
(`watch/watchos/Sources/WatchSessionEngine/WatchSyncProgress.swift`), a struct
with an injected clock: a sync begins with a request — or with a catch-up that
will actually run — and ends once a `routines_down` has arrived *and* the newest
reply has been quiet for `WatchSyncProgressCopy.quietSeconds`, or at
`WatchSyncProgressCopy.capSeconds`, whichever comes first. A reply of another
type neither ends nor extends it, and the routines gate means a sync that only
ever received foods stays open to the cap. The start surface takes `isSyncing`
and renders a non-tappable syncing row instead of the Sync button while the
window is open, inside the same `onRequestSync` and `offersSync` gate as the
button, so a second tap starts nothing new and a watch with no transport shows
neither. The host owns one window, notes every arriving frame *before* `receive`
— a frame the wrist refuses still counts, because the phone spoke — and begins
the catch-up's window only when the phone is reachable and only when the wrist
holds no routines catalog yet (plan 62: a wrist that holds one asks only for
what changed, a phone with nothing new sends nothing, so there is no answer to
wait on; the Sync button always opens the window), since there is nothing to
wait for otherwise. Because the window ends by the clock, the host re-reads it on
its own tick while one may be running, and that tick assigns `isSyncing` alone:
bumping the revision the workout and sensors observe would put their refresh on
the tick's cycle. The copy is `WatchStartSurfaceCopy.syncingLabel`, deliberately
not a value in `watch/contract/watch_start_paths_contract.json`: the
wrist↔phone contract is unchanged, and the start surface already keeps
`unreachableLabel` for itself. Verified by `WatchSyncProgressTests`
(S-8501..S-8507, S-8510),
`WatchSyncProgressWiringTests.testS8508RequestSyncBeginsTheWindowBeforeAwaiting`,
`…testS8508ArrivalsAreNotedBeforeTheReceive`,
`…testS8508CatchUpBeginsOnlyWhenReachable`,
`…testS8509TheStartSurfaceTakesIsSyncingAndSpins`,
`…testS8511TheSpinnerSitsInsideTheSyncGate`,
`…testS8512TheTickerEndsTheSpinnerWithoutBumpingRevision` and
`…testS9221AnIncrementalCatchUpOpensNoWindow`.

**A sync the phone never answers is said when the spinner stops.**
`WatchSyncProgress.endedWithoutAnswer(at:)` is true exactly when a sync began,
is over — only the cap ends a sync that got no `routines_down` — and never
received the routines; `noteArrival` already refuses arrivals once the sync is
over, so a late reply cannot flip it. Only a manual Sync can raise the line: the
host sets `manualSyncPending` in `requestSync()` (the Sync button; an automatic
catch-up never does), and when the spinner's ticker finds the sync over it sets
`syncNoAnswer` from `endedWithoutAnswer`. Any phone reply of a type in
`WatchSyncProgressCopy.replyTypes`, or the next manual Sync, clears it. The copy
is `WatchStartSurfaceCopy.syncNoAnswerLabel`, again not a contract value.
Verified by `WatchSyncNoAnswerTests` (S-9001:
`testS9001aNeverBeganIsFalse`, `…testS9001bFiveSecondsInIsStillRunningSoFalse`,
`…testS9001cCapWithNoArrivalsIsTrue`,
`…testS9001dRoutinesArrivedIsAnsweredSoFalse`,
`…testS9001eOnlyPreferencesArrivedIsStillUnanswered`,
`…testS9001fNewBeginAfterCapIsRunningAgainSoFalseThenTrueAtItsCap`,
`…testS9001gArrivalAfterTheCapDoesNotTurnTrueIntoFalse`; the sentence
`…testS9002SyncNoAnswerLabelIsExactlyThePlannedSentence`) and the wiring by
`WatchPhoneProblemWiringSourceTests.testS9004TheHostRaisesTheNoAnswerAndLinkLines`.

**One list serves both entry points.** The picker and the menu's Add Exercise
list render the same `WatchExerciseLetterList` (`WatchExerciseListView.swift`),
each supplying only its own rows and its own action (D-3105, D-3112); it is a
`List` rather than a `LazyVStack`, so a letter jump lands on a measured row
(D-3106). Verified by
`WatchMenuTests.testS3106AOneListServesBothEntryPoints`.

Within it the sections are walked by position: only the *first* run of a key
carries its letter as the scroll id, so a key that opens two runs — a digit name
sorts before `A`, a `~` name after `Z` — cannot put two views under one identity
the reader holds (`WatchMenuTests.testS3114ARepeatedLetterRunsCarryOneScrollId`,
D-3117). The grid is drawn by the watch app target, which `swift test` does not
compile. The picker carries no phone hint: the phone's status is the start
surface's line.

## The wrist shell's second surface

Once a session is open, the second surface is the package's logging view for the
current exercise — its own effort kind (a set, a timed hold, a round or a drill)
— and one list button opening the session menu: the ladder's exercises with
their logged counts to jump to, then Add Exercise (an A to Z list of the phone's
whole exercise list; a pick is appended to the end of the ladder, the session
does not move, the ladder change reaches the phone like any wrist-added
exercise), then End Session, which asks "Finish Workout?" first (Cancel /
Finish, the phone's own words;
`WatchMenuTests.testS3401TheMenuCopyIsTheOwnersWords`,
`…testS3611TheAddListSortsCaseInsensitivelyByName`,
`…testS3612AddExerciseAppendsAtTheEndAndKeepsThePosition`,
`…testS3613TheSameExerciseTwiceGetsTwoSlots`,
`…testS3614TheAddAnnouncesTheLadderChangeToThePhone`). A
set keeps its value rows and one Log button; a timed, drill or round effort shows
one clock readout and one Start/Log button
(`WatchTimedWorkTests.testS1312ARelaunchKeepsTheButtonOnLog`), a period counting
down from the phone's number, or the wrist's preset with none
(`WatchLoggingTimersTests.testS1401TheWristCountsDownFromTheSlotsOwnLength` and
`…testS1402ASlotWithNoNumberKeepsTheWristsPreset`), and the jump alone refused
while an effort runs (`WatchMenuTests.testS1307TheMenuDoesNotJumpWhileAWorkClockRuns`,
`…testS3615AddExerciseWorksWhileAWorkClockRuns`).

**One Crown turns the armed row.** The logging surface holds one Digital Crown
binding for the whole view, not one per row: `WatchLoggingModel.armedMetricKey`
names the row the Crown steps — the first row no sensor keeps, until a tap on a
row or its − / + calls `WatchLoggingModel.arm(_:)`, and the armed row wears a
2 pt outline in the phone's accent (white before the first Sync).
`WatchLoggingModel.turn(to:)` reads the Crown's one absolute position, so the
position stays continuous across arming while the travel short of a detent is
dropped. Before 46a each row owned its own binding and none received rotation
on a real watch or the 40 mm simulator. Verified by `WatchCrownArmingTests.swift`
(S-6401..S-6406, S-6408) and
`WatchLoggingTimersTests.testCrownTurnsAccumulateIntoWholeDetents` (S-6407).

**One Crown click is one value step.** The Crown's unit on watchOS is one value
unit per detent (`WatchMetricStepping.pointsPerDetent`), so one click steps the
armed row once, the way a system picker does; the Dart client counts its drag
points separately. On the logging screen the Crown is the fine control and the
− / + buttons the quick one: a click moves a weight (and an extra weight) by one
kilogram or one pound, and a duration or a period's length by one second
(`WatchMetricStepping.fineStep(for:units:)`, picked by the `fine` flag on
`WatchMetricStepping.adjust` and `WatchLoggingState.adjust(_:detents:fine:)`
and stored per row as `WatchMetricField.fineStep`;
`WatchLoggingModel.turn(to:)` is the only fine caller), while the buttons keep
the quick step — a plate and five seconds — and reps, rounds and distance keep
their step. The rating screen and the food portion keep their own
one-per-detent steps. Verified by `WatchCrownUnitTests.swift` (S-7501..S-7505:
the constant, a reps row and the rating scale stepping one per unit, and the
three Crown sites passing the constant, never a literal) and
`WatchFineCrownTests.swift` (S-7901..S-7905: the fine table, a weight and a
length stepping one unit per click while the buttons keep the quick step,
pounds moving the display by one, and a field without a fine step borrowing its
step). How a click *feels* — the rotation one step needs at the chosen
sensitivity — is checked on a device, not in the package tests: the simulator
has no Crown.

**Each exercise keeps its own dialled numbers.** `WatchLoggingState.dialled` is
keyed by the slot's `sessionExerciseId` (Dart mirror `_dialled` in
`lib/watch/logging/watch_logging_state.dart`), so switching exercise shows that
exercise's own numbers and a Log clears only the logged exercise's. Verified by
`WatchDialledPerExerciseTests.swift` (S-6410..S-6413) and
`test/watch_dialled_per_exercise_test.dart` (groups S-6410..S-6413).

**A timed effort on a distance exercise offers a Distance row.**
`WatchLoggingState.metricKeysByKind` gives a timed effort on an exercise with
the distance capability a `distance` row, dialled with the Crown or − / + — the
unit and step follow the phone's distance unit, and the value is stored in
metres — until GPS has measured movement inside this effort's own window; from
then on the row is measured and read-only, showing the effort's own metres
rather than the session total. At Log the GPS metres win when above zero
(`distanceSource: "gps"`); otherwise a dialled distance above zero is sent as
`distanceMeters` with `distanceSource: "entered"`, and with neither dialled nor
measured neither field is sent. Logging clears the dialled value, so the next
effort starts at zero; hold, round and set efforts are unchanged. Verified by
`WatchHandDistanceTests.swift` (S-9501..S-9510, plus S-9504b) and
`WatchLoggingSurfacesTests.testS9503ADialledDistanceReachesTheObservation`.

A set with two values (reps and weight) shows them as two side-by-side tiles
with one shared − / + pair under them: the outlined tile is the one the Crown
and the pair step, and tapping a tile arms it
(`WatchLoggingModel.stepArmed(_:)` steps the armed row and is a no-op without
one; `WatchLoggingStatusTests.swift`, S-7511..S-7512). A screen with one value
(a period's length, a drill's extra weight) keeps its single row with − and +
around the value. The step buttons are fixed-size plain-style capsules instead
of bordered buttons, whose drawn size was larger than their frame and overlapped
the next row (S-7514, the same file's source guard). The header carries one
status line — the set caption and the sensor readings joined by a dot ("Set 3
of 5 · 143 bpm"), either half alone, or nothing
(`WatchLoggingStatusTests.swift`, S-7513).

Every set offers the weight tile, as on the phone, whether or not the exercise
carries the `load` capability (a push-up, an ab wheel rollout included):
`WatchLoggingState.capability(for:)` gates only distance now. The tile is the
set's added weight or, negative, its assist, floored at
`WatchMetricStepping.minimumLoadKg`; a log sends the dialled value as the set's
`loadKg` and sends nothing at exactly 0, the next set starts where the last one
logged, and a planned row starts the tile at its own `loadKg`. On the phone that
`loadKg` lands in the set's extra-weight row and the phone's added weight comes
back as `loadKg` (plan 52c; `docs/watch_session_sync.md`,
`watch/sync_protocol/PROTOCOL.md`). A hold keeps only its extra-weight row and a
timed effort has no weight tile. The Dart watch client under `lib/watch` still
ties the weight row to `load` (`_capabilityFor` in
`lib/watch/logging/watch_logging_state.dart`) — a known parity gap. Verified by
`WatchBodyweightLoadTests.swift` (S-8101..S-8105).

On a 40 mm watch the − / + capsules, the unit beside the value and the
one-line name below the menu button (clearance `WatchLoggingView.titleClearance`)
are meant to keep Log fully visible; the two-tile layout has not yet been
measured on the 40 mm screen. The position of Log is checked on a device, not
in the package tests: no unit test sees a layout.

**The work clock names its exercise.** The clock is the engine's timer row of
the effort's kind, read through `WatchLoggingState.workTimer`; a work timer the
wrist starts (`elapsed`, `hold`, `round`) stamps the current slot's
`sessionExerciseId` on the row and on the `timer_state` frame it emits, and the
follow-on rest a log starts carries none
(`WatchTimedWorkTests.testS6002AStartOfATimedSlotNamesTheSlotOnTheWire`,
`…testS6002AStartOfAHoldSlotNamesTheSlotOnTheWire`,
`…testS6002AStartOfARoundsSlotNamesTheSlotAndKeepsItsLength`,
`…testS6002TheRestTheFollowingLogStartsCarriesNoSlot`; the row keeps the slot
across pause, resume, stop and the store round trip —
`WatchLoggingTimersTests.testS6003ATimerRowWithItsSlotSurvivesTheStoreRoundTrip`,
`…testS6003PauseResumeAndStopKeepTheSlot`; Dart twin,
`test/watch_session_engine_test.dart`, group
`S-6006 a work timer says which exercise it is for`). At adoption the owner's
rule is the earlier start wins, for the work kinds only: an incoming running or
paused timer of the same kind and the same slot with a later `startedAt` than
the held, not-stopped timer is ignored, a stopped row always applies, a timer
for another slot is stored beside, and a rest keeps last-write
(`WatchLoggingTimersTests.testS6005AnEarlierPhoneStartReplacesTheWristsRunningTimer`,
`…testS6005ALaterPhoneStartLeavesTheWristsTimerAlone`,
`…testS6005AStoppedPhoneRowWithALaterStartStillStopsTheTimer`,
`…testS6005AnEarlierPhoneStartForAnotherSlotIsStored`,
`…testS6005RestIsNotAnEarlierStartWinsKind`; Dart twin,
`test/watch_logging_timers_test.dart`, group
`S-6006 the earlier start wins at adoption`). A timer that came from a message
for another slot the session does not hold is not shown as the current
exercise's clock, while a clock the wrist started itself keeps running across
an exercise jump
(`WatchTimedWorkTests.testS6004APhoneTimerForASlotTheLadderDoesNotHoldIsNotTheWristsWorkClock`,
`…testS6004AClockTheWristStartedSurvivesTheJump`); the wire holds one timer per
kind, so a newer timer of that kind for another slot supersedes the wrist's own
row. A message-borne work timer (`elapsed`, `hold`, `round`), running or
paused, that names another slot the live session holds moves the wrist to that
exercise through the engine's own select path, one `exercise_advanced` frame
(`WatchTimedWorkTests.testS6004APhoneTimerForAHeldSlotMovesTheWristToIt`;
`WatchFollowPhoneEffortTests.swift` S-8401, S-8403, S-8412); a rest, a stopped
or cleared timer, a slot the session does not hold, the current slot, a session
that is no longer active and a row the earlier-start rule dropped move nothing
and emit nothing (the same file's S-8402 cases, S-8411, S-8413). Several
candidates in one frame jump once, to the earliest start (S-8415). The jump
adds no lock of its own: the lock is still any running work timer of the
session and clears on the clear frame (S-8404), the pager follows because its
index is derived, and a swipe in flight is refused with its focus cleared
(S-8414).

**The live label follows the sensor.** The grey "bpm" and distance lines of that
surface are derived on every read from the sensors' newest recorded sample, so
while the logging screen is up they move with the wrist's own beats and never
wait for the phone
(`WatchSensorCoordinatorTests.testS3108TheLiveLabelShowsTheNewestBeat`,
`WatchSensorRecordingTests.testS3109ATheLabelFollowsEveryBeat`).

Before Start, a period (sports) shows a length row with minus and plus, opening
at the phone's number or 3:00 with none; the length cannot change once the period
runs, and the chosen length carries to the next period of the same exercise
(`WatchTimedWorkTests.testS3405TurningTheLengthChangesWhatStartCountsDownFrom`,
`…testS3406ARunningPeriodHasNoLengthRowAndKeepsTheDialledLength`).
A logged effort of any kind — a set, a timed entry, a hold or a period — starts
the rest with no length, which the rest screen counts up, and whose end reaches
the phone
(`WatchRestSurfaceTests.testS161TheRestElapsedCountsUpAndSurvivesARelaunch`;
`WatchTimedWorkTests.testS3502ATimedEntryStartAndLogLeavesTheRestRunning`,
`…testS3503AHoldStartsARestAfterItsLog`,
`…testS3503BAPeriodStartsARestAfterItsLog`;
`test/watch_session_engine_test.dart`, S-320). The Wear client's Dart twin still
starts a rest after a set alone (documented divergence, plan 23b D-3502); the
rest screen is captioned
"Rest" (`WatchTimedWorkTests.testS3409TheRestSurfaceNamesItself`), and its clock
is the same scale as the logging screen's work readouts
(`WatchRestSurfaceTests.testS8621TheRestClockMatchesTheWorkReadoutsScale`).
Since plan 51b the rest screen also says what was just done and what is next:
the name line reads "Barbell Bench Press · Set 2 done" for a set effort that has
logged sets, and the exercise name alone for a timed, hold or round effort or an
exercise with nothing logged yet; a "Next: …" line above the Next button names
the next set ("Next: Set 3 of 3" with a plan, "Next: Set 4" without), the next
unfinished exercise ("Next: Barbell Back Squat · Set 1 of 2"), the next period
("Next: Period 2") or "Nothing planned next"
(`WatchRestLabelsTests.testS7601APlannedSetCountsTheLoggedSets`,
`…testS7602ACompletePlanNamesTheLaterExercise`,
`…testS7603TheForwardSearchWinsThenTheBackwardOne`,
`…testS7604EverythingDoneSaysNothingPlannedNext`,
`…testS7605AFreeSetCountsPastThePlan`,
`…testS7606AJumpedToExerciseWithNothingLogged`,
`…testS7607ARoundEffortNamesTheNextPeriod`,
`…testS7608ATimedEffortNamesTheNextExerciseWithWork`,
`…testS7609ThroughTheEngineThePhonesSetCounts`,
`…testS7610TheRestViewReadsTheLabels`). The labels come from the pure function
`deriveRestLabels` in `WatchRestLabels.swift` through
`WatchLoggingState.restLabels`: a slot is done when all its planned sets are
logged, or with no plan when anything is logged
(`…testS7603cAnExerciseWithItsPlanExactlyLoggedIsSkipped`,
`…testS7611OnlySetEntriesCountAsSets`); the next exercise is searched forward
from the current one, then from the top; the phone's logged sets count like the
wrist's. The Dart twin `lib/watch/logging/watch_rest_screen.dart` does not show
these two lines yet (parity gap, plan 51b D-5).
The rest screen carries the same list button the logging surface does, and both
open the one session menu: a jump or an add made from there moves nothing the
running rest logs (`WatchMenuTests.testS3103ATheRestScreenCarriesTheMenuButton`,
`…testS3101AJumpDuringARestKeepsTheRestRunning`,
`…testS3102AAddingAnExerciseDuringARestKeepsTheRestRunning`); the rest ends only
through Next or the next Log (`…testS3111ALogClosesTheRunningRestAndStartsTheNext`).

**A recorded log is confirmed with one tap.** The wrist's haptics are the rest
ping (below), the pager's failure tap, and three confirmations: a log the wrist
recorded — through the one button (`WatchLoggingModel.primaryAction()` and
`log()`) or the food screen's Log — plays one success tap, and Next on the rest
screen plays one lighter directional tap (`WristHaptics` maps them to `.success`
and `.directionUp`). The tap is guarded by the record: a refused log, and Start
on a timed effort (starting is not logging), play nothing. Verified by
`WatchLoggedHapticTests.testS7801ASetPlaysOneTapPerLoggedSet`,
`…testS7802ATimedEffortStartsSilentlyAndLogsOnTheSecondTap`,
`…testS7803LogPlaysTheTap`, `…testS7804ARefusedLogPlaysNothing` and the source
guard `…testS7805TheSurfacesPlayTheTapsAndNameTheListButton`, which also holds
that both toolbar list buttons (logging and rest screens) carry
`.accessibilityLabel("Exercises")`.

Both wrist clients tap at each multiple of the interval the phone sent in
`preferences_down` (`restPingSeconds`) — one Rest Ping setting, silent, and no
sound on the wrist (`WatchRestPingTests.testS241AnIntervalTapsAtItsMultiples
AndNowhereElse`; Dart twin, `test/watch_rest_ping_test.dart`, S-241). Since
plan 61 the rule (`WatchRestPing`) is asked on its own clock, not the rest
view's redraw: the host owns one `WatchRestPingScheduler` (`restPings`) whose
`arm()` asks the rule once — so a boundary crossed while nobody was looking is
caught up with one tap — and then sleeps to just after the next boundary of
the persisted rest row (`nextWait` adds a 50 ms margin so the wake never lands
before the boundary), repeating until the rest closes or the interval is Off.
The host arms it on every `revision` bump (every rest start/end, frame
receipt, interval change) and when the app becomes active
(`catchUpOnActivation`); the workout session is what keeps the app running
with the wrist down. The rest view only shows the clock: dimmed (Always On,
`isLuminanceReduced`) it shows whole minutes and its timeline ticks once a
minute on the rest's own minute marks (`restStartedAt`); raised, it shows
m:ss again. Verified by `WatchRestPingSchedulerTests` (S-9101..S-9108: the
wait table, `step()` at and around a boundary, a gap taps once, Off and a
mid-rest interval, the arm loop, disarm and re-arm, no rest, the dimmed clock)
and the source guards `WatchRestPingWiringSourceTests` (S-9109: the view shows
the dimmed clock and asks no ping; the host owns the scheduler and arms it on
every rest change). The Dart twin `lib/watch` has no scheduler and is
unchanged.

**Food is reachable with or without a workout, and the phone's rest arrives.**
The watch app builds one `WatchNutritionState` for its life — `WatchAppHost`'s
`nutrition`, handed to the sync orchestrator and restored at launch — and one
`WatchNutritionModel` beside it (`nutritionModel`) that both entry points hand
to the screen, so either reuses the one observable rather than building a model
on each body pass (`WatchNutritionWiringSourceTests.testS8311TheHostOwnsTheOneNutritionModel`,
`…testS8318TheMenuPushesTheHostsNutritionModel`). The start
screen shows `Log food` (`WatchStartView.logFoodLabel`) directly under Free
workout and opens `WatchNutritionView` in a sheet, and the session menu carries
a `Log food` row (`WatchMenuCopy.logFoodLabel`, the same words) between Add
Exercise and End Session that pushes the same screen; the row is never
disabled, because food is independent of the effort. A tapped food opens its
own screen (`WatchFoodPortionView`: the portion row, the kcal and Log), and
the portion's Crown turns the raising direction the logging screen's Crown does:
positive travel raises the portion, one detent per
`WatchNutritionPortion.stepServings`, through
`WatchPortionCrown.turn(from:to:)` via `WatchNutritionModel.turn(to:)`
(`WatchPortionCrownTests` S-8611..S-8616, the arithmetic and the model's use of
it), and leaving it — the back button or a swipe — returns to the list with nothing
selected, so the next food opens at its own amount rather than at the portion
the last one was left at
(`WatchNutritionWiringSourceTests.testS8312TheListIsTheListAndTheFoodScreenEdits`,
`WatchNutritionFreshnessTests.testS8301LeavingAFoodClearsItAndTheNextOneOpensAtItsOwnAmount`,
`…testS8313DeselectingNothingChangesNothing`,
`…testS8314ANewerListThatDropsTheSelectedFoodClearsTheSelection`). A food's
starting amount is the wrist's own newest log of it when that log is newer than
the phone's list, and the phone's pre-fill otherwise — derived on every read, so
a relaunch keeps it and an older list cannot revert it
(`…testS8302ALogBecomesTheFoodsStartingAmount`,
`…testS8303ANewerListWinsAndAnOlderOneDoesNotRevertALog`,
`…testS8304ARelaunchKeepsTheDerivedStartingAmount`,
`…testS8306ALogOlderThanTheCatalogKeepsTheCatalogsAmount`), and a selection
clamps the amount it is handed (`…testS8315ASelectionClampsTheListedAmount`).
A `foods_down` that lands while the list or a food screen is open redraws what
is shown (`…testS8305FoodChangesAreAnnouncedOnlyWhenTheListChanges`); that is
what the one model's change observer is for. The Dart twin's screen keeps its
single-screen layout — the quantity row still sits under the list there
(`lib/watch/nutrition/watch_nutrition_screen.dart`) — a stated UI parity gap;
the twin's state carries the same `deselect()` and derived amount
(`test/watch_nutrition_quick_log_test.dart`, group `S-8307, S-8317 the Dart
twin deselects and derives the starting amount`; plan 53 D-9). Verified by
`WatchNutritionWiringSourceTests.swift` (S-7201..S-7203 and S-7205, source
scans; the start screen's button was seen on the 40 mm simulator); S-7204 is
the existing `WatchNutritionQuickLogTests` and the S-3103 guards run unchanged,
not rewritten. A restore that runs while a `foods_down` is applied keeps the
newer list over the older stored row
(`WatchNutritionQuickLogTests.testS7206ARestoreCannotPutTheStoredListOverANewerOne`,
S-7206).

The phone's own rest reaches the wrist too: `WatchTimerPush` sends the phone's
open rest as a `rest` timer counting from the instant the set was logged, a
pause on the phone's chip freezes the wrist's count, and the wrist's own rest
started within 2000 ms of the phone's is the same rest and is not echoed back
(`test/watch_timer_push_test.dart`, groups `S-7301` to `S-7310`). Next on the
wrist's rest screen ends the phone's rest as well, whichever device logged the
set: the importer resolves the `rest` event's `afterEntryId` for a phone-logged
entry (`test/watch_session_rest_phone_entries_test.dart`, S-7401..S-7405).
[Rest Tracking](../rest_tracking.md) carries the cross-device rules.

The same copy carries the phone's theme accent (`accentColorHex`, `#RRGGBB`), and
the wrist keeps it for the look it renders: an accent is worn only when it clears
the contrast floor both clients share — `minContrastAgainstBlack`, 3.0 — and it
takes the label color its own contrast picks out, dark labels when black reads
better on it than white
(`WatchAccentTests.testS3710EveryRowOfTheSharedTableParsesWithTheTablesLabel`,
`…testS3711AStringThatIsNotSixHexDigitsParsesToNothing`,
`…testS3712ANearBlackAccentIsRefusedRatherThanWorn`; the six accents both clients
agree on are `watch/contract/watch_accent_contract.json`). A copy that carries no
accent, and one generated before the wrist knew the field, read as no accent — the
wrist wears the phone's default theme accent, `WatchAccent.fallbackHex` (the
contract's `abyssalNeon`), rather than the last accent it saw
(`WatchAccentTests.testS8601WornWithNoHexIsThePhoneDefaultThemeAccent`;
`WatchRestPingTests.testS3713TheWristStoresTheAccentAndReadsTheNewestCopyWithIt`,
`…testS3714ABadAccentIsRefusedAndThePreviousOneStays`; Dart twin,
`test/watch_session_start_test.dart`, S-3701).
The app's root hands the accent `WatchAccent.worn(hex:)` resolves — the usable
accent, or the fallback when the copy carries none or one too dark to wear — to
every surface through an environment value
(`watchAccent`, `WatchAccentStyle.swift`, set in `ContentView`), and every prominent button
asks for it with `watchProminent()`: the accent as fill with its label color, or the
fallback with the label color its own contrast picks out
(`WatchAccentTests.testS8602UnusableOrMalformedHexWearsTheFallback`,
`…testS8603EveryContractThemeIsWornAsItselfNotTheFallback`,
`…testS8604ContentViewWearsWornAndTheAssetCarriesTheColor`). The phone sends the accent of its current theme
at every Sync (`WatchReferenceSync.accentHexOf`; `test/watch_accent_contract_test.dart`, S-3720..S-3723).

Logged rows leave the wrist as they are logged: the engine's emissions go to
`WatchEmitForwarder` over the connectivity bridge, in emission order, and a
refused frame is reported once and dropped without disturbing the frames behind
it (`WatchEmitForwarderTests.testTheEnginesEmissionsReachTheSinkInOrder`,
`…testEveryRefusedFrameIsReportedOnceAndDropped`). An ended session is no longer
a logging surface
(`WatchLoggingSurfacesTests.testS029AnEndedSessionCannotBeLoggedInto`; on the Dart twin,
`test/watch_logging_surfaces_test.dart`'s `S-52 the wrist's own End closes the logging surface`
and `S-52 a session the phone ended is not a surface to log into`).

**The wrist announces its own session and its own adds (D-90, D-91).** The
engine's own changes are mirrored to the phone without being asked: a start
emits its lifecycle frame and then the session's own `session_snapshot`, and a
slot the wrist puts into its ladder emits a second snapshot with the revision
moved, because the shape is the wrist's own (D-101). A change that arrived from
the phone is applied silently — an `exercise_push`, a `structure_change` and a
snapshot emit nothing back. Verified on the Dart twin by
`test/watch_session_engine_test.dart`
(`S-100 a wrist start sends its lifecycle, then its own snapshot`,
`S-101 a wrist-added exercise arrives as a second snapshot with a moved
revision` and `S-104 nothing from the phone is announced back`) and by
`WatchSessionEngineTests.testS100AWristStartSendsItsLifecycleThenItsOwnSnapshot`,
`…testS101AWristAddedExerciseArrivesAsASecondSnapshotWithAMovedRevision` and
`…testS104AnExercisePushFromThePhoneIsNeverAnnouncedBack`.

The shell builds an append-only file store, `FileWatchSessionStore`, over the
app's Application Support directory (`watch-session/`), so a relaunch brings back
the session, its logged rows, a running rest and any unanswered rating
question; the engine is restored at launch, before the start paths, preferences
and rating. What survives is asserted by the store's two-engine cases
(`watch/watchos/Tests/WatchSessionEngineTests/WatchFileStoreTests.swift`:
`testS44ALoggedSetSurvivesTheProcess`,
`…testS47TheOwedRatingQuestionSurvivesTheKill`), and that a commit which suspends
still shows the owed question by
`WatchEffortRatingTests.testS55ASlowCommitStillShowsTheOwedQuestion` and
`…testS55ASlowAnswerNotifiesAfterTheRatingIsRecorded`. What a relaunch does not keep is the projection lens:
a re-stated entry holds the phone's new value only until the process ends, and
the stored first value shows again until the next Sync re-states it (D-50,
`WatchFileStoreTests.testD50ARestatedSetShowsItsFirstValueAfterARelaunchUntilTheNextSync`).

## The logging screen pages the session's exercises

**Files**: `watch/watchos/Sources/WatchSessionEngine/WatchPagerModel.swift`,
`.../WatchLoggingPagerView.swift`; the shell mount is
`ios/OmniTrain Watch App/ContentView.swift` (`loggingSurface`).

**The pager is a rule over the menu, not a second way to move the session.**
`WatchPagerModel` is a `@MainActor` model over one `WatchMenuState`, with one
construction site (`menuState`) read by both the pager and the menu sheet. Every
access constructs a plain wrapper over the same engine, paths and rating, so the
instances are equivalent; a settled swipe is the menu's own select path,
`jump(to:)`, and nothing else writes the session. The rows, the position and the
counter are read from the menu on every access, never cached, so a frame that
lands while the pager is open is already the page the user sees. Verified by
`WatchPagerModelTests.swift` (`testS6601TheModelReadsTheLadderAndThePositionOnEveryAccess`,
`…testS6607APhoneSideAdvanceIsVisibleOnTheNextRead`).

**The session moves only when the swipe has settled.** `WatchPagerModel.land(on:)`
makes one select per settled page — one `exercise_advanced` lifecycle frame, the
existing emission — and a page that is already current settles true without
selecting anything. A page outside the rows, including one the phone removed
between the swipe and the settle, changes nothing and is not a locked swipe.
Verified by `…testS6602ASettledPageMovesTheSessionOnceAndEmitsOneFrame`,
`…testS6602TheSameIndexArmSelectsNothing`,
`…testS6604APageOutsideTheRowsChangesNothing` and
`…testS6608SettlingOnAPageThePhoneRemovedChangesNothing`. (The method is
`land`, not `settle`: the module's S-004 source guard bans new names that start
with `set`.)

**While an effort clock runs there is no pager.** `showsPager` is false, the
view renders one page without a `TabView`, and a mostly-horizontal swipe over
the drag minimum plays the failure haptic and raises the one-line notice
`WatchPagerCopy.lockedNotice` — the menu's own lock words — for
`WatchPagerCopy.noticeSeconds`; a running rest is not a lock and the pager
stays free. Verified by `…testS6603ASwipeDuringAWorkClockIsRefusedAndRaisesTheNotice`,
`…testS6605ARunningRestLeavesThePagerFree` and
`…testS6606ThePagerShowsOnlyForSeveralExercisesAndAnUnlockedMenu`, which also
holds that a session with one exercise shows no pager and no counter at all
(`pageLabel` nil).

**The view is the shape around that model, and the desktop toolchain holds only
its outline.** `WatchLoggingPagerView` (watchOS-only) is a page-style `TabView`
whose own n/m counter sits beside the exercise name
(`WatchLoggingView(pageLabel:)`) instead of dots, which would sit on the Log
button on a 40 mm screen. When a swipe settles, the selection binding calls
`WatchPagerModel.focusSlotId(for:)` and puts the result in
`WatchLoggingState.focusSlotId`, so the logging surface shows the exercise the
user swiped to before the engine has moved; the page at the selected index is
the logger — its counter reads the selected page of the count — and the
name-only preview card (`WatchExercisePreviewPage`: name, logged count,
counter) remains only for the pages that are sliding in. `land(on:)` clears the
focus whether it moved or was refused (also on its early return, and
`followEngine()` clears a focus left over when no landing is in flight), and the
next settled swipe names its own focus again. While the focus is ahead of the
engine, `startWork()` is refused, so a clock is never started against an
exercise the engine has not reached and a refused landing cannot strand one
(`WatchPagerFocusTests` S-7915, S-7916). The shell's `loggingSurface` mounts the pager and not the bare
logging view, the pager mounts exactly one `TabView` with no dots and answers a
drag only in the locked branch, and the pager binds no Crown and takes no
`.focusable` focus — the Crown stays on `WatchLoggingView`, stepping the
outlined value, and never changes exercise. Verified by
`WatchPagerSourceTests.swift`
(`testS6610TheLoggingSurfaceMountsThePagerAndNotTheBareView`,
`…testS6611ThePagerIsOneTabViewWithoutDotsAndAnswersADragWhenLocked`,
`…testS6612ThePagerTakesNoCrownAndNoFocus`) and `WatchPagerFocusTests.swift`
(S-7911..S-7914: the focus shows the focused exercise and logs against it, the
pager names a focus only for another live page and none for a locked session,
the view's wiring as source guards, and a slot with no id of its own reached
through the id its exercise derives). The rest screen replaces the
logging screen as before, so there is no paging in rest; the phone screen does
not follow a wrist swipe (owner decision O-5).
