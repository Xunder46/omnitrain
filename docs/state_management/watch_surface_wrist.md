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
the next `sync()` re-sending from storage: a `timer_state`, a request, and the
snapshot of a workout that has ended would arrive wrong, so they are never
queued. **A durable frame the radio refuses is queued instead.** When the phone
is unreachable or the radio refuses, the bridge hands the OS queue
(`transferUserInfo`) an `observations_up`, every `session_lifecycle`, and a
`session_snapshot` whose `payload.status` is `active`; the app target's
`OmniTrainWatchConnectivity` receives `didReceiveUserInfo` like a message, and
the OS delivering a queued transfer to a closed phone app is an owner check on
real devices. **Only the newest copy waits.**
`WatchConnectivityBridge.queueNewest(_:on:)` runs list → withdraw → queue under
one lock: a snapshot replaces the waiting snapshots of its session, a
non-terminal lifecycle (`started`, `exercise_advanced`) the waiting
non-terminal ones, a terminal lifecycle (`completed`, `abandoned`) both;
observations and terminal lifecycles are never withdrawn; of two competing
copies the later `sentAt` wins (a terminal lifecycle is never stale); a waiting
copy under the same `messageId` is not queued again except a snapshot, whose id
does not change with its content; and a frame that goes out live also withdraws
the older waiting copies. The seam gained `outstandingTransfers()` and
`cancelTransfers(messageIds:)` — the package's `WatchConnectivitySession`
declares them with defaults for a conformer that cannot list or cancel, and the
app target's `OmniTrainWatchConnectivity` implements them over
`WCSession.outstandingUserInfoTransfers` and `cancel()`; its late-refusal path
(the `sendMessage` error handler) calls `queueNewest` instead of queuing
directly. **A queued copy is a carrier, not a delivery**: the phone's `receipt`
is the only thing that settles an owed entry. A queue that itself refuses is
reported through the same failure hook. Verified by
`WatchBridgeReplacementTests.swift` (S-9903..S-9914, S-9916),
`WatchBridgeQueueTests.swift` (S-9901, S-9902, S-9909, S-6701..S-6705) and
`WatchQueueSourceTests.swift` (S-6708, S-9915). **The bridge itself still sends nothing
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

**Today's planned workout is the surface's first control.** The wrist's today
plan is the Planned button, above the "No routines yet" line and the routine
rows: `.bordered`, never `.watchProminent()`, captioned with the
single startable plan's name, or "Planned"
(`WatchStartSurfaceCopy.plannedLabel`) when two or more are startable and the
tap opens a picker of the day's plans. It re-reads on every host `revision`
bump, never on a clock tick. Verified by
`WatchPlannedSurfaceSourceTests.testS8965ThePlannedButtonComesBeforeTheRoutineList`,
`…testS8965ThePlannedButtonWearsBorderedAndTheRoutineStaysProminent`,
`…testS8965ThePlannedCaptionCountsThePlans`,
`…testS8965ThePlanPickerSheetAndItsStateExist`,
`…testS8969ThePlannedCopyLivesInWatchStartSurfaceCopy` — and the `revision`
refresh, `WatchPhoneProblemWiringSourceTests.testS9004TheStartSurfaceSaysWhenARoutineVanished`
and `WatchSyncProgressWiringTests.testS8512TheTickerEndsTheSpinnerWithoutBumpingRevision`.

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

**A sync is finished by its replies, not by the request.** The orchestrator
awaits only the sends, so the phone's answer arrives afterwards through
`receive` and "still syncing" cannot be read from the request. The window lives
in the pure `WatchSyncProgress`
(`watch/watchos/Sources/WatchSessionEngine/WatchSyncProgress.swift`), a struct
with an injected clock: a sync begins with a request — or with a catch-up that
will actually run — and ends once `routines_down` has arrived *and* the newest
reply has been quiet for `WatchSyncProgressCopy.quietSeconds`, or at
`WatchSyncProgressCopy.capSeconds`, whichever is first. A reply of another type
neither ends nor extends it, and the routines gate keeps a sync that received
only foods open to the cap. The types that count are
`WatchSyncProgressCopy.replyTypes` (`WatchSyncProgressTests`,
`WatchWaterSyncTests.testS94b18AWaterFrameExtendsARunningSyncLikeAnyReply`). The phone sends the
bests last in an answer whenever they changed or the wrist does not hold them,
so the spinner waits for them as before, and a bests-last sync ends
`quietSeconds` after the newest reply
(`WatchSyncProgressTests.testS87b12TheBestsReplyKeepsTheSyncRunningUntilItsOwnQuietWindow`,
`…testS87b12AStragglingBestsReplyDoesNotReviveTheSync`). The start surface takes `isSyncing`
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
`WatchSyncProgressCopy.replyTypes`, or the next manual Sync, clears it — the
bests are one of them, so an answer carrying only the bests clears the line
while the routines gate keeps the sync itself open to its cap. The copy
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

The wrist shell's second surface — the logging view, its effort kinds and the one menu list — is described on its own page: [The Watch Surface — the Wrist's Logging Session](watch_surface_wrist_logging.md).

## The logging screen pages the session's exercises

The swipe between exercises (one logger, the slide-in from the swiped side, no name card, the lock while an effort clock runs) is described on its own page: [The Watch Surface — the Wrist's Exercise Pager](watch_surface_wrist_pager.md).
