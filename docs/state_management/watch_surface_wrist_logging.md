# The Watch Surface — the Wrist's Logging Session

> Part of [The Watch Surface — the Wrist's Half](watch_surface_wrist.md). Split out 2026-11-06 (plan 129) to keep the
> parent page inside the indexing ceiling.

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

**A timed effort shows a Distance tile only while GPS measures it (plan 93).**
On an exercise with the distance capability, `WatchLoggingState.fields` holds a
`distance` row only while the location subscription runs and the running work
clock's own window has covered any distance; otherwise the screen is the clock
and Start/Log alone; nothing is dialled. The tile is measured, read-only and
drawn without − / +: the effort's own metres (never the session total) in the
phone's distance unit; it never takes the Crown or moves the primary button. Before Start,
after Log and on the next effort until its own window measures movement there
is no tile. A Log carries `distanceMeters` with `distanceSource: "gps"` exactly
when the tile would show; otherwise neither key, and the distance is entered on
the phone's Session Summary. The wrist never sends `entered`. Verified by
`WatchGpsDistanceTileTests.swift` (S-16001..S-16013) and
`WatchLoggingSurfacesTests.testS006…`.

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

**A Health workout that did not open is said, once.** When Health access is on
but the platform refuses to open the workout, the logging header's notice
lines lead with "Health workout didn't start" (no retry), and the summary says
"No heart rate, the Health workout did not start" when that is why there is no
average — the access-off wording wins and is unchanged. The flag is
`WatchPlatformWorkout.openFailed` (copied from the store's `lastBeginFailed`;
reset by the next `start`, left set by `end`). Verified by
`WatchOpenFailureTests.swift` (S-15101, S-15102),
`WatchSensorAccessNoticeTests.swift` (S-15103, S-15104),
`WatchWorkoutSummaryWiringSourceTests.swift` (S-15108).

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
`…testS7610TheRestViewReadsTheLabels`). Since plan 79 the "Next: …" line also
carries the announced exercise's slot id (`WatchRestLabels.nextSlotId`, set
only when the line names another exercise, nil for "Next: Set n",
"Next: Period n" and "Nothing planned next"), and the rest screen's Next
button reads it before it ends the rest and then jumps through the menu
(`advance: { await menuState.jump(to: $0) }` in `ContentView.swift`): when the
line names an exercise, Next opens that exercise's logger; with sets
remaining, no plan, a period, or nothing planned it returns to the same
exercise as before; a refused jump leaves the rest ended and the same exercise
shown. An extra set on a finished exercise: swipe back to it. Verified by
`WatchRestLabelsTests` (`testS9101TheAnnouncedExerciseCarriesItsSlotId`,
`…testS9102ASetCountCarriesNoSlotId`,
`…testS9103ASetCountWithoutAPlanCarriesNoSlotId`,
`…testS9104NothingPlannedCarriesNoSlotId`,
`…testS9105APeriodCarriesNoSlotId`,
`…testS9106ATimedEffortAnnouncesTheExerciseAndTheWrapHolds`,
`…testS9107ASlotWithoutItsOwnIdAnnouncesTheCatalogSlotId`) and
`WatchRestAdvanceTests.swift`
(`testS9108TheRestsNextJumpsToTheAnnouncedExercise` through the engine,
`testS9109TheNextReadsTheTargetBeforeItEndsTheRest` as the source guard). The labels come from the pure function
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
`.accessibilityLabel("Exercises")`. Since plan 82 a countdown's end is felt by
its kind: a round end keeps `.notification`, a hold end plays `.stop`, a
timed-target end plays `.retry` (`WatchTimerHaptics.cue(for:)` maps the kind
to a `WatchHapticCue`, `WristHaptics.play` switches on it), and confirming
Finish in the menu plays one `.success` tap before `finish()`, Cancel none
(`WatchTimerCueTests.swift` S-15105, S-15106, S-15107). The Wear OS twin keeps
one tap.

**A record logged on the wrist is announced with a banner and its own tap.**
A `set` effort that strictly beats the best the wrist knows raises a trophy
banner reading "New PR" over the wrist surfaces for about four seconds
(`WatchPersonalRecordCopy.bannerSeconds`) and plays the record tap
(`WristHaptics.playPersonalRecord`, `.start`) instead of the logged tap. One
`WatchPersonalRecordBanner` serves both: the logging screen overlays it, and the
rest screen the shell swaps in when a record log starts a rest shows it too, on
each screen's own tick and no timer. It lets taps through
(`allowsHitTesting(false)`), so Log, rest and Next work; a second record restarts
its window, and only its opacity changes, so Reduce Motion needs nothing extra.
VoiceOver reads "New personal record" (`WatchSpokenText.personalRecord`) and, on
watchOS 10 and later, hears one announcement per record, whichever screen is up;
watchOS 9 reads the label alone. A log that is not a record keeps the logged tap
and shows nothing. Verified by `WatchPersonalRecordBannerTests`
`testS87b9ARecordLogPlaysTheRecordTapAndNotTheLoggedOne`,
`testS87b10TheBannerIsVisibleUntilTheWindowEnds`,
`...testS88_1TheAnnouncementIsTakenOncePerRecordAndNeverForANonRecord`,
`...testS88_2TheAnnouncementWaitsPastTheBannerWindow`,
`...testS88_3TheRestSurfaceHostsTheBannerInsideItsTimeline` and
`WatchSpokenTextTests.testS87b14TheRecordBannerSpeaksTheWholeSentence`.

**The rule is the phone's "Congrats! New PR" toast, mirrored.** Only a `set`
effort counts. A loaded set is compared by its estimated one-rep max in
kilograms — `loadKg * (1 + reps / 30)`, the phone's own Epley order — and a set
with no weight or a band assist by reps; the comparison is strict, so an equal
set is no record. The best is the larger of the phone's copy and the wrist's own
earlier sets, which stops one set firing twice — after a relaunch too, and
before the phone has taken the workout in — and a wrist that never received a
frame says nothing, while an exercise the frame omits is a first-ever record.
Sets the phone logged and mirrored raise nothing. Two limits stay open, stated
in `docs/watch_session_capture.md` ("Why the wrist's record banner has two
limits") and in the QA walkthrough's gaps. Verified by
`WatchPersonalBestsTests.testS87b1AnEqualSetIsNotARecordAndAHeavierOneIs`,
`testS87b2AWristThatNeverReceivedAFrameSaysNothing`,
`testS87b5TheSameSetTwiceIsOneRecordAndAHeavierOneIsTheNext`,
`testS87b7OnlySetEffortsGetAVerdictOrMoveTheOwnBest` and
`testS87b16AnAssistedSetWinsOnTheRepsAxis`.

**The wrist's surfaces speak to VoiceOver.** The rest clock reads "Rest time"
with a spoken value ("2 minutes 5 seconds", via `WatchSpokenText.duration`)
and is marked as updating frequently; the rest Next button carries the
"Next: …" line as its hint; menu rows read name and count as one element,
summary rows label and value as one element with the title a header; the
rating buttons read "Rating 3 of 5" (the selected one marked selected), the
Crown view reads the current choice or "No rating", Confirm carries the hint
"Saves your rating". Dynamic Type is untouched. Verified by
`WatchAccessibilitySourceTests.swift` (S-15303..S-15307) and
`WatchSpokenTextTests.swift` (S-15301, S-15302, S-15309).

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
`WatchNutritionModel` beside it (`nutritionModel`) that the start screen's sheet
hands to the screen, so it reuses the one observable rather than building a model
on each body pass (`WatchNutritionWiringSourceTests.testS8311TheHostOwnsTheOneNutritionModel`).
The start screen shows `Nutrition` (`WatchStartView.nutritionLabel`) directly under Free
workout, then a separator line, then Sync, and opens `WatchNutritionView` in a sheet. The session menu has no Nutrition
row: food is logged from the start screen only, not while a session is in
progress (`…testS7202TheSessionMenuHasNoLogFoodRow`). A tapped food opens its
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
