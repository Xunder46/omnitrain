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
has answered; a launch that has asked nothing says nothing. `WatchPhoneReachability.unknown` is the state a `Bool` cannot
express, which is why the app target's host starts there and moves only when the
bridge reports what the platform observed — the platform's answer is always an
observation, never a "not yet". Verified by
`WatchConnectivityBridgeTests.testS111TheSurfaceSaysConnectedOrUnreachableOnlyAfterObservingIt`.
The sentence lives in the package's `WatchStartSurfaceCopy` rather than the
contract's `startSurface` block; it moves into the contract if the Wear OS client
ever ships a transport.

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
armed row once, the way a system picker does — on the logging, rating and
food-portion screens alike; the Dart client counts its drag points separately.
Verified by `WatchCrownUnitTests.swift` (S-7501..S-7505: the constant, a reps
row and the rating scale stepping one per unit, and the three Crown sites
passing the constant, never a literal). How a click *feels* — the rotation one
step needs at the chosen sensitivity — is checked on a device, not in the
package tests: the simulator has no Crown.

**Each exercise keeps its own dialled numbers.** `WatchLoggingState.dialled` is
keyed by the slot's `sessionExerciseId` (Dart mirror `_dialled` in
`lib/watch/logging/watch_logging_state.dart`), so switching exercise shows that
exercise's own numbers and a Log clears only the logged exercise's. Verified by
`WatchDialledPerExerciseTests.swift` (S-6410..S-6413) and
`test/watch_dialled_per_exercise_test.dart` (groups S-6410..S-6413).

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
for another slot is not shown as the current exercise's clock, while a clock
the wrist started itself keeps running across an exercise jump
(`WatchTimedWorkTests.testS6004APhoneTimerForAnotherSlotIsNotTheWristsWorkClock`,
`…testS6004AClockTheWristStartedSurvivesTheJump`); the wire holds one timer per
kind, so a newer timer of that kind for another slot supersedes the wrist's own
row.

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
"Rest" (`WatchTimedWorkTests.testS3409TheRestSurfaceNamesItself`).
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

Both wrist clients tap at each multiple of the interval the phone sent in
`preferences_down` (`restPingSeconds`) — one Rest Ping setting, silent, and no
sound on the wrist (`WatchRestPingTests.testS241AnIntervalTapsAtItsMultiples
AndNowhereElse`; Dart twin, `test/watch_rest_ping_test.dart`, S-241).

**Food is reachable with or without a workout, and the phone's rest arrives.**
The watch app builds one `WatchNutritionState` for its life — `WatchAppHost`'s
`nutrition`, handed to the sync orchestrator and restored at launch — the start
screen shows `Log food` (`WatchStartView.logFoodLabel`) directly under Free
workout and opens `WatchNutritionView` in a sheet, and the session menu carries
a `Log food` row (`WatchMenuCopy.logFoodLabel`, the same words) between Add
Exercise and End Session that pushes the same screen; the row is never
disabled, because food is independent of the effort. Verified by
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
wrist keeps its default look rather than the last accent it saw
(`WatchRestPingTests.testS3713TheWristStoresTheAccentAndReadsTheNewestCopyWithIt`,
`…testS3714ABadAccentIsRefusedAndThePreviousOneStays`; Dart twin,
`test/watch_session_start_test.dart`, S-3701).
The app's root hands the usable accent to every surface through an environment value
(`watchAccent`, `WatchAccentStyle.swift`, set in `ContentView`), and every prominent button
asks for it with `watchProminent()`: the accent as fill with its label color, or exactly the
default prominent look when there is none. The phone sends the accent of its current theme
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
button on a 40 mm screen; a page that is not the current exercise is a preview
card (`WatchExercisePreviewPage`: name, logged count, counter). The shell's
`loggingSurface` mounts the pager and not the bare logging view, the pager
mounts exactly one `TabView` with no dots and answers a drag only in the locked
branch, and the pager binds no Crown and takes no focus — the Crown stays on
`WatchLoggingView`, stepping the outlined value, and never changes exercise.
Verified by `WatchPagerSourceTests.swift`
(`testS6610TheLoggingSurfaceMountsThePagerAndNotTheBareView`,
`…testS6611ThePagerIsOneTabViewWithoutDotsAndAnswersADragWhenLocked`,
`…testS6612ThePagerTakesNoCrownAndNoFocus`). The rest screen replaces the
logging screen as before, so there is no paging in rest; the phone screen does
not follow a wrist swipe (owner decision O-5).
