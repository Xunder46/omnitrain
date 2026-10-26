# Wearable App — The Wrist's Own Logging QA Walkthrough

Level 3 (paired devices) of [the Setup and QA guide](watch-app-setup-and-qa.md),
moved to its own page so neither page nears the 64 KiB indexing ceiling. Steps
keep their numbers; "What QA passed means" in the main guide counts them.

This walkthrough exercises the wrist logging surface, which has not run on
hardware yet.

1. **Start a workout on the wrist and pick an exercise.** Tap **Free workout**.
   A Free workout starts with no exercise, so the picker comes up first; pick
   one and the logging screen appears with that exercise's value rows. Dial 3
   reps and tap **Log**: the row is accepted and the rest screen appears counting
   up, with exactly one control, **Next**
   (`WatchRestSurfaceTests.testS162NextEndsTheRestAtTheTapInstant`).
2. **The set is on the phone at the moment it is logged.** Phone app in the
   foreground and reachable. Without touching the wrist, the phone's session for
   this wrist session shows the set. The phone must show it before any Sync —
   only an untouched wrist proves the set is handed over as it is logged.
   Nothing is sent on a timer.
3. **End Session and answer once.** Turn Settings → Effort Rating on, on the
   phone, and sync from the wrist. On the wrist tap the list button, then
   **End Session**, then **Finish** in the prompt; the question appears alone —
   no back or swipe, only the small Skip under Confirm. Answer 4. The phone's
   calendar holds one entry for the session and its Summary shows 4 / 5.
4. **A workout logged with the phone out of reach catches up by itself — (owner).**
   Start another wrist workout and log a set with the phone in Airplane Mode.
   Nothing arrives. Turn Airplane Mode off: with the phone back in reach the wrist
   catches up on its own — the set lands exactly once without tapping **Sync**
   (`WatchConnectivityBridgeTests.testS107TheWristCatchesUpOnAReachabilityEdgeOnce`:
   the owed entries leave once, and a second notification while one is in flight
   is dropped). The **Sync** button still fetches routines, preferences and the
   food catalog, and retries by hand.
5. **A band-assisted set logs a negative load** *(owner)*. Pick a set exercise
   with a load. Dial the load down past zero: the crown stops at the wire's floor
   however long you keep turning
   (`WatchLoggingTimersTests.testS061AnAssistedLoadStopsAtTheWireFloor`, and the
   phone's own floor in `watch_logging_stepping_test.dart`). Log the set: the
   phone's session for this wrist session shows the same assisted value, not
   zero, and its summary counts it
   (`WatchLoggingSurfacesTests.testS062AnAssistedLoadIsEmittedWithItsSign`;
   `test/watch_session_import_test.dart`,
   `S-58 a set logged at −20 kg imports at −20 kg and sums −160`), and the next
   set opens at that assisted load rather than resetting to zero
   (`testS063TheNextSetCarriesTheAssist`). A set whose load was never touched
   still claims no load at all (`testS062AnUntouchedLoadDialSendsNoLoadKg`).
   Dialling back up to zero leaves a plain `0.0`, never a `-0.0`
   (`testS064AZeroLoadNeverPrintsASignedZero`).
6. **A timed effort logs one Start-to-Log window** *(owner)*. Pick a timed
   exercise: logging shows one clock readout and one **Start** button, with no
   duration, distance, rounds or length row. Tap **Start** and the readout counts
   up while the button reads **Log**
   (`WatchTimedWorkTests.testS1300TimedWorkIsLoggedAsTheWindowFromStartToLog`);
   log it and the phone's session shows one entry for that window. A round
   exercise picked with the phone's number counts down from it — 40:00 for a
   soccer half
   (`WatchLoggingTimersTests.testS1401TheWristCountsDownFromTheSlotsOwnLength`),
   while one whose slot carries no number keeps the wrist's preset at 3:00
   (`…testS1402ASlotWithNoNumberKeepsTheWristsPreset`). **End Session** still ends
   the session
   (`…testS1311FinishLeavesTheWorkClockRunningAndTakesTheReadout`).
7. **End Session asks first — (owner).** On the menu tap **End Session**: the
   prompt reads **Finish Workout?** with the phone's own words — "This action
   will save and close the workout session." — and **Cancel** / **Finish**
   (`WatchMenuTests.testS3401TheMenuCopyIsTheOwnersWords`). Tap **Cancel**: the
   menu is still there and the session is still running. Tap **End Session**,
   then **Finish** in the prompt: the session ends and the effort-rating question
   follows as in step 3. Also on this pass: a rest screen names itself, with a
   **Rest** caption above the clock
   (`WatchTimedWorkTests.testS3409TheRestSurfaceNamesItself`).
8. **A sports period's length is dialled before Start — (owner).** Pick a sports
   (round) exercise: logging shows a length row of minus, a value and plus. Its
   start value is the phone's number for that slot, or 3:00 with none; turn the
   row down to 1:00 with the minus or the crown
   (`WatchTimedWorkTests.testS3405TurningTheLengthChangesWhatStartCountsDownFrom`).
   Tap **Start**: the countdown begins at 1:00 and the length row is gone, so the
   length cannot be changed while the period runs
   (`…testS3406ARunningPeriodHasNoLengthRowAndKeepsTheDialledLength`). Tap
   **Log**: the next period of the same exercise opens at 1:00, while a different
   exercise's period opens at its own number.
9. **Every effort ends on the rest screen — (owner).** Log a **Plank** hold, a
   cardio interval and a sports period on the wrist: each one leaves the rest
   screen counting up with **Next** as its one control
   (`WatchTimedWorkTests.testS3502ATimedEntryStartAndLogLeavesTheRestRunning`;
   the hold and the period,
   `…testS3503AHoldStartsARestAfterItsLog` and
   `…testS3503BAPeriodStartsARestAfterItsLog`). Tap **Next**: the wrist is back
   to logging the same exercise, and the phone's session for this wrist session
   shows the rest time that just ended
   (`…testS3505EndingTheRestAfterATimedEntryReportsThatEntry`). Start the next
   interval instead of tapping Next: the rest ends at the Start instant and only
   then does the new window open
   (`…testS3504StartOfTheNextTimedEffortEndsTheRestItWalksInto`).
10. **End Session sits apart from the exercises — (owner).** Open the list on the
    wrist: the session's exercises are one group, and **Add Exercise** and
    **End Session** sit below a divider, so neither reads as one more exercise
    row. The extra space sits between the line and **Add Exercise**; **Add
    Exercise** and **End Session** keep the normal row spacing.
11. **Add an exercise from the watch — (owner).** Sync, open the list, tap
    **Add Exercise**, pick one: it is the last row, it has no count, the
    exercise being logged did not change, and the phone's open session shows
    the new exercise; tap the same one again: a second slot. The list is the
    phone's whole exercise list, so it only reaches the wrist at **Sync**
    (`WatchMenuTests.testS3611TheAddListSortsCaseInsensitivelyByName`,
    `…testS3612AddExerciseAppendsAtTheEndAndKeepsThePosition`,
    `…testS3613TheSameExerciseTwiceGetsTwoSlots`,
    `…testS3614TheAddAnnouncesTheLadderChangeToThePhone`), and a phone holding
    no routine sends it too (D-3601).
12. **The wrist wears the phone's theme accent — (owner).** On the phone
    (Settings) pick each of the six themes in turn and **Sync** from the wrist.
    On the wrist's prominent buttons — **Start** / **Log** on the logging
    surface, **Next** on the rest surface, the current row of the menu, a
    routine row on Start — the fill is that theme's accent and the label reads:
    the accent's own contrast decides whether the label is dark or light, and
    every theme today takes dark labels
    (`WatchAccentTests.testS3710EveryRowOfTheSharedTableParsesWithTheTablesLabel`
    holds every row of `watch/contract/watch_accent_contract.json` to the label
    it names). The accent arrives with the Sync, like every other phone setting,
    and picking a new theme shows at the next one. Before any Sync — a fresh
    install — the buttons wear the phone's default theme accent
    (`WatchAccent.fallbackHex`, the contract's `abyssalNeon`), and a copy that
    carries no accent, or one too dark to read on, is worn as that fallback
    rather than as the last one seen
    (`WatchAccentTests.testS8601WornWithNoHexIsThePhoneDefaultThemeAccent`,
    `…testS8602UnusableOrMalformedHexWearsTheFallback`,
    `…testS3712ANearBlackAccentIsRefusedRatherThanWorn`).
    Nothing else changes color; the wrist's black stays black.
13. **The exercise list arrives in batches, and only when it changed —
    (owner).** On a real pair, tap **Sync** and open **Add Exercise**: the full
    list is there, custom exercises included, A to Z. Tap **Sync** again with
    nothing changed on the phone: the list is unchanged — the phone sends the
    preferences and the routines and no exercise list the second time, which
    you can only see in the phone's logs. Add a custom exercise on the phone,
    tap **Sync**: it appears in **Add Exercise** in its A-to-Z place. Turning
    the phone's Bluetooth off mid-way is not part of this step. The behaviour
    behind it is pinned off-device by `test/watch_reference_sync_test.dart`
    (`S-3843 250 exercises arrive as three batches in name order`),
    `test/watch_sync_request_handler_test.dart` (`S-3850 the wrist names the
    current version: no batch travels`, `S-3854 a sync with the sent version
    sends no batch, and a custom exercise stales it`) and
    `WatchMenuTests.testS3611TheAddListSortsCaseInsensitivelyByName`.
14. **Jump to a letter in a long exercise list — (owner).** Sync so the wrist
    holds the full list, then open **Add Exercise**: above the rows sits a grid
    of the letters the list actually has, four per row — not the whole alphabet
    — and a name the list put under a digit or a symbol sits under `#`, which is
    first, while an accented initial like **Élan** has its own letter at the
    end. Tap a letter: the list moves so that letter's first exercise is at the
    top, nothing is added and the screen does not close; a letter jump is a
    scroll, not a pick. Far letters land too: the list measures every row it
    holds, so a tap on **T** brings T's own exercise to the top instead of
    estimating and missing it (D-3106). Tap an exercise as before: it is still
    added at the end of the session's list and the screen returns to the menu.
    With a short list — a fresh install with 20 exercises or fewer at **Sync**
    — there is no grid at all. The Free workout picker is the other entry point
    and draws the same list in the same order: the grid is its first row, then
    the exercises the session already holds, then the one section per letter.
    The one component both render is pinned by
    `WatchMenuTests.testS3106AOneListServesBothEntryPoints`. The letters and
    their order are pinned off-device by
    `WatchMenuTests.testS3900TheLettersFollowTheListsOwnOrder`,
    `…testS3901DigitsAndSymbolsShareOneHashEntryFirst`,
    `…testS3902TheGridNeedsMoreThanTheThreshold`,
    `…testS3904AnAccentedInitialIsItsOwnLetterAndSortsLast` and
    `…testS3905EveryLetterEntryCoversAContiguousRun`; the grid itself is drawn
    by the watch app target, which `swift test` does not compile.
15. **The menu is one tap away during a rest — (owner).** Log a set so the rest
    screen is up: it carries the same top-right list button the logging screen
    does, and tapping it opens the same menu over the rest. Tap **Add
    Exercise**, pick one and go back: the wrist is on the rest screen again with
    the timer still counting and the new exercise last in the ladder. A jump
    from that menu returns to the rest screen too, and the rest ends only
    through **Next** or by logging the next set
    (`WatchMenuTests.testS3103ATheRestScreenCarriesTheMenuButton`,
    `…testS3101AJumpDuringARestKeepsTheRestRunning`,
    `…testS3102AAddingAnExerciseDuringARestKeepsTheRestRunning`,
    `…testS3111ALogClosesTheRunningRestAndStartsTheNext`).
16. **The Crown turns the armed row — (owner).** Open a set exercise and turn
    the Crown without touching the screen: Reps changes with each tick — the
    first row is armed by itself. Tap the Load row (or its − / +): the outline
    moves to Load and the Crown now steps the load. If the Crown still does
    nothing, the cause is not focus and plan 46a reopens. The model side is
    pinned by `WatchCrownArmingTests.swift` (S-6401..S-6406, S-6408).
17. **Each exercise keeps its own numbers — (owner).** Dial the load to 60 kg
    (or its equivalent in the phone's unit) on a set exercise, then open
    another exercise from the menu: it shows its own starting load, not the 60
    you dialled, and coming back shows the 60 again
    (`WatchDialledPerExerciseTests.swift` S-6410..S-6412; Dart twin
    `test/watch_dialled_per_exercise_test.dart`). Log on the second exercise:
    only its numbers clear; the first exercise keeps its dialled ones (S-6411).
18. **Swipe between the session's exercises — (owner).** On a session with
    three exercises, swipe left on the logging screen: the next exercise slides
    in as a preview card — its name, how many sets are logged on it and the
    counter — and when the swipe settles it becomes the current exercise with
    its own rows and numbers; the counter beside the name moves from 1/3 to
    2/3. The phone's screen does not move. A session with one exercise shows no
    counter and does not page. The rules are pinned off-device by
    `WatchPagerModelTests.swift` (S-6601..S-6608) and the shell mount and view
    shape by `WatchPagerSourceTests.swift` (S-6610..S-6612); the swipe itself,
    the preview card and the counter on hardware are this step — the Simulator
    could not be driven.
19. **A swipe during a timed effort is refused — (owner).** Start a timed
    effort so its clock runs, then swipe: the exercise does not change, you
    feel one failure tap, and a one-line notice, "An effort is running"
    (`WatchPagerCopy.lockedNotice`), shows for about a second and a half
    (`WatchPagerCopy.noticeSeconds`;
    `WatchPagerModelTests.testS6603ASwipeDuringAWorkClockIsRefusedAndRaisesTheNotice`
    holds the refusal, the words and the notice window off-device). The haptic
    and the notice on hardware are this step. With the effort stopped, swiping
    works again, and the Crown still steps the outlined value and never changes
    exercise (`WatchPagerSourceTests.testS6612ThePagerTakesNoCrownAndNoFocus`).
20. **Plans 56 and 57's four surfaces — (owner).** Four checks in one pass on a real
    watch. Delete the app and reinstall, open it before any **Sync**: the
    prominent buttons are cyan with dark labels, not grey
    (`WatchAccentTests.testS8604ContentViewWearsWornAndTheAssetCarriesTheColor`).
    On a food's portion row, turn the Crown the way that raises Reps on the
    logging screen: the portion goes up
    (`WatchPortionCrownTests` S-8611..S-8616). Log a set so the rest screen
    shows: its clock is as large as the work clock
    (`WatchRestSurfaceTests.testS8621TheRestClockMatchesTheWorkReadoutsScale`).
    Start a **Free workout**, then close the picker without picking: the start
    screen returns with no workout running, and the phone's Home shows no live
    watch session (`WatchCancelEmptyFreeWorkoutTests` S-8701..S-8706 for the wrist; the
    phone side is `test/watch_session_import_test.dart` S-265, an abandoned session
    creates no history).
21. **The watch says when a start cannot happen — (owner).** Three grey lines on
    the Start screen, each needing a real pair or a simulator trick. Delete or
    replace a routine on the phone and do **not** Sync, then tap the stale
    routine on the watch: a grey line, "That routine is no longer on the watch.
    Tap Sync."
    (`WatchSyncNoAnswerTests.testS9003UnknownRoutineThrowsAndLeavesTheSessionUnchanged`
    holds the throw and the untouched session off-device;
    `WatchPhoneProblemWiringSourceTests.testS9004TheStartSurfaceSaysWhenARoutineVanished`
    holds the wiring). Force-quit the phone app with the phone still reachable
    and tap **Sync**: the spinner runs about 20 s, stops, and a grey line says
    "No answer from your phone. Open OmniTrain on it and try again." — it goes
    when you Sync again or any answer from the phone arrives
    (`WatchSyncNoAnswerTests.testS9001cCapWithNoArrivalsIsTrue` is the 20 s cap,
    `…testS9001dRoutinesArrivedIsAnsweredSoFalse` the answered case;
    `WatchPhoneProblemWiringSourceTests.testS9004TheHostRaisesTheNoAnswerAndLinkLines`
    the wiring). The third line, "Phone link unavailable. Restart the watch
    app.", needs a watch whose WatchConnectivity activation fails — hard to
    provoke on hardware, so it is unit-tested only
    (`WatchPhoneProblemWiringSourceTests.testS9004TheRadioReportsWhenItCannotComeUp`;
    the sentence `WatchSyncNoAnswerTests.testS9002LinkUnavailableLabelIsExactlyThePlannedSentence`).
22. **The wrist taps on time with the screen down, and a dimmed rest shows
    minutes — (owner).** Three checks on a real watch. Rest Ping 30 s on the
    phone, start a workout on the watch, log a set, lower the wrist so the
    screen goes dark: a tap at 30 s, 60 s and 90 s. Same with the screen dimmed
    but on (Always On): the rest shows "N min"; raise the wrist and the m:ss
    clock is back and correct. Phone locked, watch on the wrist, phone app in
    the background: at a boundary count the taps — one tap is fine; two close
    taps mean the phone's own rest notification mirrors to the watch as a
    second tap, tell the lead. The scheduler, the catch-up and the dimmed
    minutes clock are held off-device by `WatchRestPingSchedulerTests`
    (S-9101..S-9108) and `WatchRestPingWiringSourceTests` (S-9109); whether
    watchOS lets the app tap with the wrist down, and the dimmed redraw
    cadence, are this step.
23. **A wrist raise sends nothing when nothing changed — (owner).** Four checks
    on paired hardware. Raise the wrist twice in a row with the phone in
    reach: the second raise stores nothing new. Change a phone setting (the
    accent or Rest Ping), raise the wrist: the watch picks it up; raise again:
    nothing new. Add a routine on the phone and raise the wrist: it appears.
    Tap **Sync** on the watch's start screen: it still completes (a full
    re-send — the way out when the phone's "nothing changed" answer is wrong).
    On a raise with nothing changed the start screen shows no syncing spinner;
    a watch with nothing synced yet (a fresh install) still shows it, and
    tapping **Sync** shows it. The phone's changed-only answer is held
    off-device by `test/watch_sync_changed_only_test.dart` (S-9201..S-9212),
    the Sync button's full ask by `WatchManualSyncSourceTests` (S-9220), and
    the spinner gating by `WatchSyncProgressWiringTests`
    (`testS8508CatchUpBeginsOnlyWhenReachable`,
    `testS9221AnIncrementalCatchUpOpensNoWindow`).

29. **The exercise page fits a 40 mm watch — (owner).** On a 40 mm watch start
    a ride (or any distance exercise) in a Free workout, then a lift. On both
    pages the "2/3" counter sits to the left of the menu button, the exercise
    name stops short of the button, and the Start (or Log) button is fully on
    screen. With Location refused, a distance exercise shows one grey line
    "No distance, Location access is off" and Start is still on screen.
    Heart-rate refusal no longer adds a line to exercise pages
    (`WatchExercisePageFitTests`, plan 70).

30. **Health access off is said on the Start screen and the summary — (owner).**
    With Health access refused: the Start screen says so (unchanged); finish a
    workout and the summary shows "No heart rate, Health access is off" below
    its rows. With access on and a heart rate recorded, no such line shows.

31. **A phone-started workout brings the watch's heart rate to the phone —
    (owner).** Start a workout on the phone with the watch on the wrist, log a
    set or two, finish on the phone. The session summary opens at once; within
    a few seconds the Avg and Max heart-rate row appears without leaving the
    screen. Delete the session from History before the numbers arrive (watch
    out of range): when the watch reconnects, no session reappears. A workout
    started on the watch still shows its heart rate as before
    (`WatchFollowedSessionEndTests`, `test/watch_followed_end_import_test.dart`,
    `test/session_summary_late_heart_rate_test.dart`, plans 71 and 72).

32. **A message that arrives while the watch app opens is kept — (owner).**
    With the watch app closed, finish a workout on the phone (or log a set on
    the phone during a live workout), wait a minute, then open the watch app:
    it shows the new state without pressing Sync. The simulators do not
    deliver queued transfers, so only a real watch can show this
    (`WatchInboundLaneTests`, S-10301..S-10305, plan 73).

33. **Rides, rows and walks record as themselves, and a run inside a routine
    keeps its map — (owner).** Finish a Zone 2 Ride: Fitness shows Cycling, not
    Run; a rowing exercise shows Rowing; Brisk Walk shows Walking; Hike shows
    Hiking. A custom cardio exercise made with discipline Cycling records as
    Cycling; with no discipline it records as a Run. A routine that starts with
    a lift and has an outdoor run in the middle: Health > Workouts > the
    workout > Route exists afterwards (note whether Fitness draws it for a
    Strength workout); a lifting-only workout leaves no route
    (`WatchHealthActivityTests`, `WatchRouteKeeperTests`, plans 75 and 76).

Two known gaps this walkthrough must not be read as failing on: each device owns
only the timer it started, so a Sync stops a countdown the phone wrote and
leaves a wrist-started one running (`test/watch_logging_timers_test.dart`,
`S-79 a snapshot leaves the wrist's countdown running and stops the phone's own`;
the phone-written case is the reconciliation fixture `timer_cleared.json`,
replayed by `WatchLiveMirroringTests.testEveryReconciliationFixtureConverges`),
and the load label is always in kg, whatever unit the phone is set to
(`WatchLoggingTimersTests.testS007APoundPreferenceStepsInPoundsStoredInKilograms`
holds the kilogram payload underneath).
