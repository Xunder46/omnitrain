# The Wear OS App

**Scope.** The Android wrist app: its build target, the shell that hosts the
wrist surfaces, and the radio that carries frames between the two devices. The
client it hosts is the shared Dart wrist code in `lib/watch/` — the same engine,
storage and surfaces the watchOS package mirrors — so this page is about the
shell, the transport and the Android build, not about what the wrist logs. What
a wrist session becomes on the phone is
[Watch Session Capture](watch_session_capture.md); which session is whose across
the two devices is [Watch Session Sync](watch_session_sync.md); the models the
wrist stores are in [Data Models — watch](data_models_watch.md); the hands-on
guide to installing and exercising either wrist is
[Wearable App — Setup and QA](watch-app-setup-and-qa.md). The Apple shell and the
Swift client are described in
[State Management — the Wrist's Half](state_management/watch_surface_wrist.md).

## Two devices, one project

The phone app and the wrist app are the same Flutter project. What separates
them is an Android product flavor and a Dart entry point:

| | Phone | Wear OS |
|---|---|---|
| Flavor | `phone` | `wear` |
| Entry point | `lib/main.dart` | `lib/watch/wear_main.dart` |
| Manifest | `android/app/src/main/AndroidManifest.xml` | the same, merged with `android/app/src/wear/AndroidManifest.xml` |
| Advertised capability | `omnitrain_phone` | `omnitrain_wear` |
| Minimum SDK | 26 | 30 |
| It has, the other does not | the whole app | the watch feature in its manifest |

Both flavors keep the application id `dev.sasha.omnitrain`, so one Play listing
is meant to carry both and the watch feature is what routes one of them to a
watch. Today the wrist APK is built and installed directly.

```
flutter build apk --release --flavor wear -t lib/watch/wear_main.dart
flutter build appbundle --release --flavor phone
```

Every Flutter build has to name a flavor now, including the release workflow and
the pre-release gate (`scripts/pre_release_check.sh`), which look for the
flavored artifact first and an unflavored one second so an artifact left by an
older build is still inspected.

## The radio

`packages/omnitrain_watch_link/` is one plugin over two platforms:
`WCSession` on iOS, the Wear data layer on Android. The Dart side
(`WatchLink`, two channels) is the same for both, so every layer above it —
`WatchConnectivityChannel`, `WatchConnectivityTransport` and the phone's watch
graph — is platform-blind.

The Android half runs on **both** devices, because both apps compile it. It
learns which role it is playing from the device's own feature set, and it looks
for the peer by the other side's capability. The two capabilities are declared
in each flavor's `res/values/wear.xml`, so a peer that is installed is known
before it ever launches a sync.

The five calls mirror the watchOS plugin: `status`, `sendMessage`,
`transferUserInfo`, `outstandingTransfers`, `cancelTransfers`. The four event
kinds are the same: `message`, `userInfo`, `reachability`, `state`.

Where the two platforms differ is the queue. watchOS has `transferUserInfo` and
`outstandingUserInfoTransfers`; Android has the data layer, so a queued frame
becomes one data item under its own `messageId`, carried when the two devices
next meet. One rule follows from that and is worth knowing when reading the
transport's queue tests: a data item is deleted by whichever side takes it, so
the sender's list of outstanding frames shrinks when the peer receives one, not
only when the sender withdraws it.

A queued frame is read back with its lifecycle state and its sentAt: the plugin
decodes each item's stored frame, so the transport can tell a terminal lifecycle
from a live one and a newer copy from an older one
(`test/watch_link_package_test.dart`, group `S-29414`).

A frame queued while the app was closed is read when the app starts. The data
layer raises a change event only to a listener that is attached when the item
arrives, so each time the plugin attaches it also lists the items waiting and
takes each one the way a change event does: emitted to Dart, then deleted. This
holds on the watch and on the Android phone. The plugin's source guards are in
`test/watch_link_start_up_read_test.dart`; no background service is built, so a
watch whose app is closed updates at its next open, not before.

A frame is serialized as JSON on Android rather than carried as a property list,
with explicit nulls preserved, because the protocol uses a null to clear a
timer.

## The shell

`WearApp` (`lib/watch/app/wear_app.dart`) is what the wrist launches. It is
handed an engine, the start paths, the nutrition state, the orchestrator and the
transport — everything injected, which is what lets a desktop test build it over
an in-memory store and a fake link.

It decides one thing: which surface is on screen. A running session shows the
logging surface; a running rest shows the rest surface; anything else shows the
start surface. Nutrition is pushed over the top, so the platform's own back
gesture returns to the session. The shell reaches its navigator through its own
key (`navigatorKey` on `WearApp`), which is what lets the start surface's
nutrition quick-log open (`test/wear_app_test.dart` `S-28137 the Log food
button opens the nutrition screen through the shell navigator`); before that
repair `Navigator.of(context)` had no navigator above the shell. While a session runs, one rebuild a second keeps
countdowns and the rest clock moving, including for a session restored at
launch; with nothing running — and once a session ends from the menu — there is
nothing to tick (`test/wear_menu_screen_test.dart`
`S-28136 after End the shell stops its one-second ticker`).

The shell owns three things besides layout:

- **The launch sequence.** Restore the engine, the start paths and the nutrition
  state from the wrist's own storage, then start the radio and catch up.
- **Inbound frames.** A request frame asking for the wrist's state is answered
  with the wrist's snapshot; every other frame goes to `WatchSyncOrchestrator`,
  which routes it to the roster catalogue, the food list, or the engine. Frames
  are handled one at a time in arrival order.
- **The app's own lifecycle.** A resumed app catches the wrist up when the phone
  is reachable.

`WearWatchTransport` (`lib/watch/app/wear_watch_transport.dart`) is the wrist's
radio over the link package. Reachability is the platform's answer, re-read
rather than cached; a durable frame — a logged observation, a lifecycle message,
a session start, or the snapshot of a workout still running — is handed to the
OS queue when the radio refuses it, and anything else is reported and dropped
for the next sync to re-send. Only the newest copy of a workout waits: a
snapshot replaces the session's queued snapshots, a lifecycle its non-terminal
lifecycles, and a terminal lifecycle (`completed`, `abandoned`) replaces both and
is never stale; a copy stamped later than the frame wins and the frame is not
queued; a logged observation is never withdrawn; a snapshot or lifecycle that
goes out live withdraws the older copies still waiting
(`test/wear_queue_newest_test.dart`). Its durability table and its
newest-copy rule are the same ones the Swift `WatchConnectivityBridge` uses.

The wrist stores everything in its own Hive directory (`omnitrain_watch`), so a
watch never shares a box with anything else on the device.

## The Start screen on a small watch

On a screen shorter than 260 dp the Start screen is one scrolling list: the routines first, then `Sync`, `Free workout`, `Log food`, `Diagnostics` (debug and profile builds) and the `Search on phone` hint, each button 40 dp tall with a 4 dp gap and 16 dp of room above the first and below the last item for the round bezel (`WatchStartScreen`, plan 296). Before this the pinned buttons left the routine list no height at 192 dp, so no routine could be started, and the column overflowed by 96 px at 192 dp and 45 px at 227 dp with Diagnostics and the phone in range. On a taller screen the layout is unchanged: the buttons pinned under a scrolling routine list, 56 dp tall (`test/wear_start_screen_compact_test.dart`).

## The exercise menu

`WatchMenuScreen` (`lib/watch/logging/watch_menu_screen.dart`) is the wrist's
session menu, the Dart counterpart of the Apple client's `WatchMenuView`, built
on `WatchMenuState` in the same directory. It lists one row per exercise in
ladder order — the exercise's name, with `N logged` under it when N is above
zero and never a `0 logged` — and marks the current exercise, which the screen
draws as the prominent row (`test/wear_menu_screen_test.dart`
`S-28122b the current exercise is the prominent row`); the rows and counts are
`WatchMenuState.rows` (verified by `test/watch_menu_state_test.dart`
`S-28110 rows are the ladder in order, with the position and the counts`).
There is no remove control: a removal arrives only when the phone removes an
exercise, and the row is gone within a second
(`test/wear_menu_screen_test.dart`
`S-28122 the menu lists the ladder, the actions, and no remove control`,
`S-28133 a slot the phone removed vanishes, and its stale row tap does nothing`,
`S-28135 a session whose only slot was removed keeps its actions`). The
menu's End
ends through the effort-rating state when the shell wires one (D-28503).
It ends the session and asks the question when one is owed
(`test/wear_effort_rating_screen_test.dart`
`S-28513 the menu's End goes through the rating state`).

While a hold, a round or a timed (elapsed) work clock runs, the exercise rows
are disabled and the caption `An effort is running` says why; a running rest
never locks them, and the three actions are never disabled (the lock's halves
by `test/watch_menu_state_test.dart`
`S-28112a a running elapsed clock locks the menu`,
`S-28112b a running hold locks the menu`,
`S-28112c a running round locks the menu`,
`S-28112d a running rest never locks the menu`,
`S-28112e a stopped work clock never locks the menu`; on the screen by
`test/wear_menu_screen_test.dart`
`S-28127 a running hold shows the caption, locks the rows, spares the actions`,
`S-28127b once the hold stops the menu refreshes and the rows work`).

A tap on a row jumps to that exercise and closes the menu
(`test/wear_menu_screen_test.dart`
`S-28126 tapping a row jumps and closes the menu`; the engine move by
`test/watch_session_menu_engine_test.dart`
`S-28101 selectExercise moves to the named slot and announces it once`).
`Add Exercise` opens the exercise list; the pick is appended at the END of the
ladder and the user stays on the exercise they were on
(`test/wear_menu_screen_test.dart`
`S-28128 Add Exercise appends at the end and keeps the position`; the engine
call by `test/watch_session_menu_engine_test.dart`
`S-28103 addExerciseToEnd appends last and keeps the position`), and the list
ignores a second tap inside the same frame (`S-28134 a double-tap in the Add
list adds exactly one slot`, `S-28134b two picks raced inside one frame add
exactly one slot`: the second tap must not pop the menu under the list either).
The picker's default, which the start screen's free-workout list uses, is
unchanged: its pick still moves to the new exercise (`S-28131 the picker
default follows the pick on a live session`, `S-28131b a keepPosition pick
never moves the session`; the start screen's own call site is not pinned by a
test).

End Session asks Finish Workout? only when a logged effort or a running work clock is there
(verified by `test/wear_menu_screen_test.dart`
`S-28123 End with a logged effort asks Finish, cancels, then finishes`); with
neither it asks the discard question instead (`S-28124 End with nothing logged
asks the discard question`), and the rule's two halves are `hasWorkToSave`
(`test/watch_menu_state_test.dart`
`S-28118a one logged effort gives End something to save`,
`S-28118b a running work clock gives End something to save`,
`S-28118c an untouched session has nothing to save`).
A clock the phone started is not logged by the wrist's End
— the Wear wrist starts no work clock of its own — but a running one still
counts as work to save, so a wrist Discard cannot abandon the phone's copy
(`S-28118b ...` above; the entries a Discard keeps by
`S-28117 Discard abandons the session and keeps the entries`).
`Discard Session` asks `Discard session?` and abandons the session, and the
entries already logged stay in history
(`test/wear_menu_screen_test.dart`
`S-28125 Discard asks first, cancels without change, then abandons`).
The Finish and Discard questions are a full-screen page
rather than a centred dialog, which did not fit a watch (the screen tests above
exercise both questions and their cancel-and-confirm halves; the page is as big
as the app and not a centred dialog: `S-28123c the Finish question is a
full-screen page, not a dialog`; dismissing one
without a button confirms nothing: `S-28123b dismissing the Finish question is
not confirming it`; a phone ending the session closes the question page too:
`S-28129b the phone ending the session closes the question page too`).

The menu closes by the system back gesture, a successful jump, Finish or
Discard, and it closes by itself when the session stops being active — the
phone ended it — after which, and after a Finish or a Discard, the start
surface shows. A refresh once a second is what notices a clock the phone
stopped, a slot the phone removed, or a session the phone ended
(`test/wear_menu_screen_test.dart`
`S-28129 the phone ending the session closes the menu by itself`,
`S-28127b ...`, `S-28133 ...` above).

On a screen under 260 dp tall the logging surface takes a compact look
(the 192 dp and 227 dp watches); a larger screen — the phone-sized
desktop harness, tests at 800x600 — keeps the old layout exactly
(`S-28207 the large layout is unchanged at 800x600`). The compact look:
the value rows are tighter — smaller numerals, step buttons 36 dp, and
the unit joins its label on one line (`Load · kg`,
`S-28208 a compact row joins its label and unit`); the countdown line
and the sensor line share one line (`S-28204 the worst compact header
fits 192x160`); `Log` is 40 dp tall (the large look: 56) and the
shell's `Menu` button 32 dp (the large look: at least 48), with 2 dp
between them (`S-28202 <kind> at <size> dp: Log and Menu are on
screen`, run for all four effort kinds at 227 and 192 dp); if a
crowded header still leaves the rows too little room they scale down
instead of overflowing, the rows never taking the drag away from the
crown or a swipe (`S-28204b the rows scale down inside their space
when the header is crowded`). Nothing overflows on any of the four
effort kinds at 227 or 192 dp
(`S-28201 <kind> at <size> dp lays out without overflow`), `Log` still
logs one set (`S-28206 tapping Log logs exactly one set at 192x192`),
the step buttons and the crown still dial
(`S-28205 the compact rows stay dialable: tap and crown`), and the
rest surface (Next, Menu) fits both sizes
(`S-28207b the rest surface fits at <size> dp`). The compact controls
sit below the 48 dp Wear touch guideline (`Log` 40, `Menu` 32, the
step buttons 36), and the round bezel clips the corners of a
full-width button; both are owner checks on a real watch (item 5 of
"Checks on a watch" below)
(decisions D-28201..D-28207 in plan 282; guarded by
`test/wear_logging_layout_test.dart`). To see the menu without a watch,
`flutter run -d macos -t lib/watch/debug/wear_menu_debug_main.dart`
opens a 227x227 round-clipped window over a running three-exercise session on
an in-memory store, with a Back button and Esc standing in for the watch's
swipe-back; the radio fails quietly there (no native link). It shows layout
and flow, not the round bezel or the watch's pixel density
(verified by `test/wear_os_config_test.dart`, group
`S-28132 the Wear menu harness`,
`is a QA entry point no production file imports`).

## The phone's settings, the effort rating and the accent colour

The phone's settings, the effort rating and the accent colour moved to [The Wear OS App: the phone's settings](wear_os_app_phone_settings.md), with their tests and their owner checks (6, 7 and 8 below).

## The exercise pager

With a session of two or more exercises the logging surface shows one exercise and a small `n/N` counter right after its name. A horizontal swipe moves to the neighbouring exercise: to the left for the next one, which slides in from the right edge, to the right for the previous one, which slides in from the left. A swipe past either end does nothing, a drag shorter than 24 points does nothing, and a vertical drag belongs to the value rows. While a work clock (elapsed, hold or round) runs there is no paging: the swipe gives a short vibration and the words `An effort is running` for 1.5 seconds. A move the user did not make (the phone, the menu, the rest screen's Next) shows the new exercise at once, with no slide, and with the system's reduced-motion setting the slide is a plain fade. The rest surface is not paged.

The rule is the Apple wrist's, described in [The Watch Surface: the Wrist's Exercise Pager](state_management/watch_surface_wrist_pager.md): the pager is a rule over the menu, so a settled swipe is the menu's own jump (`WatchPagerState` in `lib/watch/logging/watch_pager_state.dart`; the widget is `WatchLoggingPager`). Three things differ on Wear, each a decision of [plan 287](plans/2026-11-21-287-wear-swipe-pager-plan/2026-11-21-287-wear-swipe-pager-plan.md). There is no focus: the Apple wrist shows the swiped-to page before the engine has moved, while here the swipe awaits the jump and the logger ignores touches until it lands, so `Log` cannot write to the exercise being left. A second swipe during that jump is ignored. And the pager binds no rotary input: the value rows keep it.

## The personal bests

The phone sends each exercise's standing best in a `bests_down` message: the best estimated one-rep max in kilograms and the most reps at zero load, one entry per exercise the user has completed a set for. The Wear wrist keeps the newest frame (`WatchPersonalBests` in `lib/watch/logging/watch_personal_bests.dart`; a frame is stored as a `WatchBestsRecord`) and nothing else: a frame stamped earlier than the held one is dropped, a frame with the same numbers writes nothing, a frame the wrist cannot read is refused whole, frames are applied one at a time, and the store keeps only the newest frame (`pruneBests`, the third prune on the store contract). Given a set, the wrist can say whether it beats the standing best: the larger of the frame's best and the best of the sets the wrist itself holds, strictly greater, on the weight axis (the estimated one-rep max, at most 12 reps counted) for a loaded set and on the reps axis otherwise. A wrist that never received a frame says nothing; with a frame held, an exercise the phone has no history for makes its first set a record.

The rule is the Apple wrist's (`WatchPersonalBests.swift`; the owner's decisions are in [series 87](plans/2026-10-26-87-wrist-new-pr-banner-index.md)) and the plan is [plan 288](plans/2026-11-22-288-wear-personal-bests-plan/2026-11-22-288-wear-personal-bests-plan.md). A set that beats the standing best shows a small `New PR` banner (plan 289, `lib/watch/widgets/watch_personal_record_banner.dart`): a trophy and the words in the phone's accent colour over the top of the screen for 4 seconds, with one distinct vibration (the platform's plain vibration; the pager's click, the lock's heavy tap and the rest ping's medium tap are taken). The verdict is read on one path only, when the wrist logs the set, so a set the phone logged never fires it and a wrist that holds no frame says nothing. Logging a set starts a rest at once and the rest screen replaces the logging screen, so both screens overlay the same banner and a record is not torn down with the screen that logged it; a second record inside the window restarts the 4 seconds. The banner takes no touch, so `Log`, `Next` and `Menu` work under it, and a screen reader announces `New personal record`. One difference from the Apple wrist: a record still inside its window when the user taps `Next` is announced again by the logging screen's banner.

## The water count

The phone owns the day's water. The Wear wrist asks for it on every sync (its routines request carries `wantsWater`, and `holdsBests` when it already holds the phone's bests, so the phone sends a bests frame only when one changed; both are set in `lib/watch/wear_main.dart` on the Wear transport) and keeps the newest `water_down` frame (`WatchWaterState` in `lib/watch/nutrition/watch_water_state.dart`, stored as a `WatchWaterRecord`): an older frame is dropped, a frame with the same numbers writes nothing, an unreadable one is refused whole, frames are applied one at a time, and the store keeps only the newest (`pruneWater`, the fourth prune on the store contract).

The wrist can log one tap of the water bar (`logWaterGlass` on the engine): a glass added or removed, stored first and sent as a `water_glass` event until the phone receipts it. A tap is never part of a workout: its session id is always the day's nutrition log, even while a workout runs. The count the bar will show is never stored; it is computed on every read: the phone's count when its frame is for the wrist's local today, else 0, plus the wrist's own taps of local today that the frame does not list (confirmed or not: only the frame's list takes a tap out), in time order, an add +1 and a remove -1 but never below 0. The plus stops at 500 taps a day (the phone's own cap), the minus also at 0. The rule is the Apple wrist's (series 94-96); the plan is [plan 290](plans/2026-11-22-290-wear-water-count-plan/2026-11-22-290-wear-water-count-plan.md). The water bar sits at the bottom of the Log food screen (plan 291, `lib/watch/nutrition/watch_water_bar.dart`), under the foods list or the "No foods yet" message and nowhere else, so no water is logged from inside a workout: a minus, a drop with the count and a plus, each press one glass added or removed and shown at once, before the phone answers, with one click when a tap was stored. The minus is greyed at 0 and both buttons at the day's 500 taps. A frame that arrives while the screen is open changes the count, and local midnight with the screen open shows the new day's count within a minute (the bar re-reads once a minute). A screen reader says `Remove one glass`, `Add one glass`, and for the middle `Water` with `3 glasses` (`1 glass`). A launch drops the water taps the phone has confirmed that are older than 72 hours (`WatchWaterState.restore` calls `pruneWaterTaps` on the engine, after the engine's own restore; the Apple wrist's plan 96, here [plan 302](plans/2026-11-22-302-wear-water-tap-prune-plan/2026-11-22-302-wear-water-tap-prune-plan.md)): the gate is a receipt and a `loggedAt` strictly earlier than now minus 72 hours, so an unconfirmed tap of any age, a recent tap, a tap whose time cannot be read, any other kind of row and the confirmation rows all stay, and the count the bar shows cannot change because no count reads a tap older than 25 hours. The prune runs only at launch, never when a frame arrives or a tap is pressed (`test/watch_water_prune_test.dart`).

## The workout summary

When the wrist ends a workout that holds at least one logged effort, and the app saw that workout running, a screen titled `Workout done` follows the effort question (when the phone asks for one; Skip leads to it too): `Time 12:34` (`h:mm:ss` from an hour), `Sets 12` (`Efforts 2` when the workout holds a timed effort, a round or a hold), `Avg HR 128 bpm` only when the wrist holds heart-rate readings stamped inside the workout, and a `Done` button that returns to the start screen (`lib/watch/logging/watch_workout_summary.dart`, plan 292; the rule is the Apple wrist's, plan 66a). A workout ended with nothing logged, an abandoned or discarded one, one the phone ended, and one that ended while the app was closed show nothing; a workout that starts while the summary is up replaces it. The wrist reads the heart rate from Health Services (plan 298), so the heart-rate row shows once a reading has been stored. The Apple wrist's note that explains a missing heart rate (Health access off) is not built: Wear has no such state. The summary is local: nothing is sent or stored, and it does not survive a relaunch.

## The logging screen on a round watch

On a screen shorter than 260 dp the logging screen's header is centred and starts 22 dp from the top: the name row (the exercise name and the `n/N` counter) is at most 112 dp wide, so a long name ellipsizes, and the merged countdown and sensor line is at most 144 dp wide, so both lines have all four corners inside the visible circle of a 192 or 227 dp round face (`WatchLoggingScreen`, plan 301). Before this the header was left-aligned at the top-left, outside the circle, and the first words of the name and the heart-rate number were cut off (seen on the emulator). The value rows, which already scale down to the room they are given, take the 20 dp the header gained; on a taller screen the layout is unchanged (`test/wear_logging_bezel_test.dart`).

## The sensors

The wrist wires the session's sensors in the shell (plan 297, the Dart half of plan 280 item 9), and the platform side is built for the heart rate (plan 298), the distance (plan 299) and the workout itself (plan 300). `WearApp` takes the session's `WatchSessionSensors`; the shell starts them once when a session becomes active and stops them when none is, on every path that starts or ends a session, because each of those paths already passes through the shell's once-per-change `_syncTicker`: a session started from the Start screen or a routine, one the phone started, one restored at launch, an End or a Discard from the menu, and a session the phone ended. Starting and stopping run one at a time on one lane and each step gives up after 5 seconds, so a native call that never answers cannot keep a later session's sensors from starting. The heart-rate readings go through the recorder that already existed, into the session's own store, and the logging surface's sensor line shows the newest one (`91 bpm`). Logging never depends on a sensor: a refused, absent or failing source changes nothing the user sees (`test/wear_sensors_shell_test.dart`).

`WearSensorSource` (`lib/watch/sensors/wear_sensor_source.dart`) is the contract the native half will answer: a method channel `omnitrain/wear_sensors/methods` with `heartRatePermission` and `locationPermission`, each answering `granted`, `denied` or `unavailable` (a call asks the user first when the state is undetermined), and two event channels, `omnitrain/wear_sensors/heart_rate` (beats per minute) and `omnitrain/wear_sensors/location` (cumulative metres). Any failure, including no native half at all, reads as `unavailable` (`test/wear_sensor_source_test.dart`).

The heart rate comes from Health Services' `MeasureClient` (`WearSensors` in `android/app/src/wear/kotlin/`, plan 298): a watch with no heart-rate sensor answers `unavailable`; otherwise the first question asks the system for the body-sensor permission (`BODY_SENSORS`, or `READ_HEART_RATE` from Wear OS 6) unless it is already held, and answers `granted` or `denied`; with it, each reading is sent to Dart and the platform subscription ends with the workout. The phone build carries none of this. The Kotlin side has no test harness, so its guards are source checks (`test/wear_heart_rate_native_test.dart`), and on the emulator the prompt, the grant, the denial and live synthetic readings were seen. The distance comes from the fused location provider (`WearSensors` and `DistanceTracker` in `android/app/src/wear/kotlin/`, plan 299): a watch with no GPS answers `unavailable`; otherwise the first question asks the system for the location permission (fine and coarse together) unless it is held; with it, the stream asks for high-accuracy fixes every 2 seconds with a 3 metre minimum step and sends the running total in metres, which the existing sensor line shows in kilometres or miles. A fix with no accuracy or worse than 50 metres is ignored, so is one more than 10 seconds old (a cached fix from earlier), and a step that would need more than 15 metres a second is a new starting point rather than distance (the emulator's first fix once made the probe read 222 km). The Dart side subscribes only for an exercise with the `distance` capability, so a lift never wakes the radio. On the emulator the prompt, the grant, and a simulated walk (about 5.5 metres every 2 seconds adding up to the metres walked) were seen; the guards are source checks (`test/wear_distance_native_test.dart`). The platform workout is a Health Services exercise (`WearWorkout` and `WorkoutService` in `android/app/src/wear/kotlin/`, plan 300): when the session's sensors start the wrist asks the body-sensor permission (the heart-rate question, once) and, only if it is held, starts an exercise of the type the workout calls for (running for distance work, strength training for lifts, stretching for holds, otherwise a generic workout; the shared type table's watchOS name is translated to the Health Connect name by `WatchActivityTypes.wearFor`) with heart rate as its data type, then a foreground service of type `health` whose ongoing notification says `Workout in progress` and opens the app, so the system keeps the process while the wrist is down. Ending the workout, discarding it or the phone ending it ends the exercise and then stops the service; at launch the wrist first asks whether an exercise of its own is still running and ends it, before the restored session registers a fresh one. A refused permission or a Health Services failure registers nothing and changes nothing the user sees. On the emulator the exercise started, the foreground service ran as a health service with its notification channel, the exercise reported in progress, and both ended with `end`; the real app's restored session started the service; the emulator ended the exercise itself when the app was force-stopped, so a stranded exercise was not seen (`test/wear_platform_workout_store_test.dart`, `test/wear_workout_native_test.dart`). Not built: calories, the Health Connect write and the watch-face ongoing-activity chip.

## The diagnostics log

The wrist keeps a diagnostics log, the same one the phone keeps (`DiagnosticsLog` in `lib/core/services/diagnostics_log.dart`: one line per event, the newest 3000 kept, the same cut and coalescing, so the two logs read together): a `launch` line naming the last thing the previous run recorded, a `scene` line for each app lifecycle change (`active`, `inactive`, `background`), a `reachability` line each time the phone's reachability changes (never one per tick), a `frame_sent` line for each frame the wrist sends (`live` or `queued`), `frame_not_sent` when the radio refused it (with the error's type), `frame_received` for each arrival and `frame_handler_failed` when its handler threw. A line names the frame's type, the session it names, an outcome word and an error's type, never a payload value. It records in every build. In debug and profile builds (and in release while the phone's `kHideDiagnosticsInRelease` is false) the Start screen shows a `Diagnostics` button that opens a screen with the plain sentences (`Started 09:12`, `Before that: last seen on screen at 09:10` or `First run recorded.`) and the newest 40 lines, newest first. The rule is the Apple wrist's (plans 142 and 177) and the plan is [plan 293](plans/2026-11-22-293-wear-diagnostics-plan/2026-11-22-293-wear-diagnostics-plan.md). Not built: sending the log to the phone (the Apple wrist hands the phone a file; the Wear platform plugin has no file transfer), and the workout, sensor and recovery lines (the Wear wrist has no platform workout yet).

## What the wrist shows

The start surface (synced routines, free training, the quick-log entry, a manual
sync), the logging surface (one effort, its values, one Log), the rest surface
(the elapsed rest and one Next), and the nutrition quick-log.
The Menu button under the logging surface
and the rest surface opens the exercise menu, the Apple wrist's menu without a remove control (D-28102).
A swipe on the logging surface moves between the exercises (the pager, below).

The Apple wrist hosts more: spoken
timer cues, which are not on the Wear wrist; the plan that
built this shell
records each one, and the sizes they are (the Apple client is roughly twice the
Dart client), in
[the plan](plans/2026-11-20-280-wear-os-shell-plan/2026-11-20-280-wear-os-shell-plan.md).

Live sensors are the same story. `WatchSensorSource` is the seam a platform
satisfies; on Wear OS the live feed is the health-services exercise client
rather than HealthKit, and the shell passes no source yet, so the wrist logs
without heart rate and distance exactly as it would on a device with no sensor.

## How it is verified without a watch

- `test/wear_watch_transport_test.dart` — reachability, the request frames, the
  durable queue, the non-durable drop, the radio-safe rewrite, arrival order,
  and the durability table.
- `test/wear_queue_newest_test.dart` — the newest-copy rule over a mock data
  layer that keeps a queue: each replacement arm, the stale and equal-stamp
  edges, the unreadable stamp, the live withdraw, the failures, the lane, and a
  source guard on the plugin's read of `state` and `sentAt`.
- `test/watch_link_start_up_read_test.dart` — source guards on the plugin's
  start-up read: its place in the attach, a failed listing, the buffer release,
  and the one rule shared with the change event.
- `test/wear_start_screen_compact_test.dart` — the Start screen at 192, 227 and 300 dp: no
  overflow, the first routine on screen, the order, exact button heights and
  insets, every button reachable by scrolling, and the roomy layout unchanged.
- `test/wear_sensor_source_test.dart` — the sensor source's channel contract: the
  three permission answers, every failure reading as unavailable, numbers only on
  the streams, and the channel names.
- `test/wear_heart_rate_native_test.dart` — source guards on the Kotlin heart-rate
  client: the permission question, the prompt's answer reaching every waiting
  caller, the stream's gate and cleanup, the activity wiring and channel names,
  and the manifests and dependency.
- `test/wear_distance_native_test.dart` — source guards on the Kotlin distance
  client: the location question, the prompt's answer, the stream's gate,
  filters and cleanup, the tracker's rules, and the manifests and dependency.
- `test/wear_platform_workout_store_test.dart` — the platform workout store: the
  translated type on `begin`, a refused permission starting nothing, every failure
  reading as nothing happened, the in-progress list, `end`, and the translation
  helper.
- `test/wear_workout_native_test.dart` — source guards on the Kotlin exercise
  client and the service: the permission gate, the type table and its generic
  default, the config, the service only after a successful start and stopped
  after the end, and the manifests.
- `test/wear_sensors_shell_test.dart` — the shell's sensor wiring: start, stop, a
  restored session, an abandoned one, denial, a throwing source, two sessions in
  a row, a stop that never answers, and the entry point.
- `test/wear_logging_bezel_test.dart` — the logging header at 192, 227 and 300 dp:
  every corner of the name and of the sensor line inside the circle, a long name
  and the counter, no overflow on every effort kind with `Log` where it was, and
  the roomy layout unchanged.
- `test/wear_app_test.dart` — the shell's choice of surface and the two ways it
  handles an arriving frame, over an in-memory store.
- `test/watch_session_menu_engine_test.dart` — the jump, the append-at-end add
  and the slot ids.
- `test/watch_menu_state_test.dart` — the menu's rows and counts, the
  work-clock lock, and what End has to save.
- `test/wear_menu_screen_test.dart` — the menu over the shell: the ladder rows,
  the three actions, the Finish and Discard questions, the add path and the
  phone-side removal.
- `test/watch_pager_state_test.dart` — the pager rule: page, count and label,
  the lock, the neighbour page with no wrap, the jump a settled swipe makes,
  and the notice window.
- `test/wear_pager_screen_test.dart` — the pager as a widget: both swipe
  directions, the ends, the short and vertical drags, the locked notice, `Log`
  after a swipe, the held landing, the slide side and its absence, reduced
  motion, the counter at 192 and 227 dp, and the shell wiring.
- `test/watch_bests_store_test.dart` — the stored bests frame, the prune that
  keeps the newest, and a reopen, under the in-memory store and Hive.
- `test/watch_personal_bests_test.dart` — the judge: strict greater-than on both
  axes, the first-ever record, the own best, the 12-rep cap, an older frame, a tie,
  an unreadable frame, a relaunch, two frames at once, and the schema validator.
- `test/wear_personal_bests_wiring_test.dart` — the orchestrator's route, the
  shell's restore, and the entry point's wiring.
- `test/wear_personal_record_state_test.dart` — the verdict on a log: the window,
  its restart, the flag, an absent owner or frame, a timed effort, a failed
  write, a set the engine takes without a log, and the two axes through a real log.
- `test/wear_personal_record_banner_test.dart` — the banner and tap as widgets:
  shown once and gone after 4 seconds, nothing on a non-record, the fit at 192
  and 227 dp, no touch taken, the rest screen's banner in the accent and
  announced, and the platform vibration.
- `test/watch_water_prune_test.dart` — the launch prune of old confirmed taps: the
  receipt and age gate on both stores, nothing written when nothing is old, the
  engine's memory, the retention, and that only restore prunes.
- `test/watch_water_store_test.dart` — the stored water frame, the prune that keeps
  the newest, and a reopen, under the in-memory store and Hive.
- `test/watch_water_engine_test.dart` — the tap: the nutrition session id, never a
  workout, an unknown change refused, confirmed taps kept, a relaunch, the schema.
- `test/watch_water_state_test.dart` — the count: the phone's base, the wrist's
  unlisted taps, the time order and the floor, another day, midnight, the 500
  cap, malformed taps, the frame rules, a restart, and two at once.
- `test/wear_water_wiring_test.dart` — the orchestrator's route, the two request
  flags on the Wear transport, the shell's restore and the entry point.
- `test/wear_water_bar_test.dart` — the bar: its place under the list, a press
  at once with one click, the inert buttons at 0 and at the cap, the names a
  screen reader says, a frame and midnight while open, the fit at 192 and
  227 dp, the listener's clean-up, the shell's wiring and a failed write.
- `test/wear_workout_summary_state_test.dart` — the summary's rule: the duration
  text, the rows and labels, the efforts it counts, the heart-rate window and
  rounding, every gate, the phone's end, a new workout and Done.
- `test/wear_workout_summary_screen_test.dart` — the screen and the shell: title,
  rows and Done, Finish then summary then start screen, the effort question
  first, the fit at 192 and 227 dp, an empty or phone-ended workout, and a new
  workout over a summary.
- `test/wear_diagnostics_summary_test.dart` — the screen's sentences and lines:
  the first run, what was last seen, the phrases, a restart, the newest 40 and
  the line format.
- `test/wear_diagnostics_transport_test.dart` — what the transport records: a
  live, a queued and a refused send, the name rule, an arrival before its
  handler, a failing handler, no payload value, and a transport with no log.
- `test/wear_diagnostics_shell_test.dart` — the shell: the lifecycle lines, the
  reachability lines once per change, the Start screen's button, the screen, its
  fit at 192 and 227 dp and the entry point's wiring.
- `test/wear_os_config_test.dart` — the flavors, the watch feature, the two
  capabilities, the plugin's Android registration and its five calls, the
  production entry point, and the two release invocations.
- `flutter build apk --flavor wear -t lib/watch/wear_main.dart` — the build
  target itself.
- `test/watch_transport_test.dart` — the phone's side, including the platform
  choice that now includes Android.

What none of those can prove is that the two devices pair and carry a frame.
That is the paired-device level of
[Wearable App — Setup and QA](watch-app-setup-and-qa.md), and it needs a watch.

## Checks on a watch

The suite cannot see a round face or a paired phone. These are the owner's
checks, run on real hardware:

1. (owner) on a Wear emulator or watch: the `Menu` button on the logging and
   the rest surface, the menu opens, each of the three exercise rows, jump,
   Add Exercise, End and Discard questions readable on the round screen at the
   watch's size
2. (owner) the system swipe-back returns from the menu without choosing
   anything
3. (owner) with a paired phone: ending the session on the phone closes an open
   menu; removing an exercise on the phone while the menu is open drops its
   row; a phone-started clock locks the rows and shows the caption
4. (owner) the nutrition quick-log opens from the start surface (the navigator
   repair)
5. (owner) the logging surface at 192 dp and 227 dp: every control on screen and big enough to hit
   (the compact controls sit below the 48 dp Wear touch guideline:
   `Log` 40, `Menu` 32, the step buttons 36), and the corners of
   `Log` near the round bezel, which clips the corners of a
   full-width button
6. (owner) with a paired phone set to pounds and miles, sync the watch:
   weights show in lb and distances in miles on the logging surface; set the
   phone's Rest Ping to 30 seconds, sync, and a rest on the watch taps every
   30 seconds
7. (owner) with a paired phone whose effort-rating setting is on: finish a
   workout with a logged set from the menu and the question appears alone; a
   tap or a rotary turn picks a number; Confirm saves it (the phone shows the
   rating); on another workout Skip shows the start screen; closing the app
   on the question and reopening asks again; the question fits the round
   screen
8. (owner) with a paired phone set to a colour theme: sync the watch and
   the buttons and the selected rating number wear the phone's theme colour
   with readable labels; switch the phone to another theme and sync again,
   the colour changes; before any sync the watch's buttons are cyan, not
   purple
9. (owner) on a Wear emulator or watch: swipe between the exercises of a
   three-exercise session; a swipe to the left shows the next exercise
   sliding in from the right with `2/3` beside the name, a swipe to the right
   goes back; check the system does not take the right swipe as "leave the
   app" (if it does, tell the owner: the follow-up is a control, not a silent
   change); a swipe while a clock runs vibrates and shows `An effort is
   running`; `Log` right after a swipe writes to the exercise on screen; the
   counter fits beside a long exercise name at the watch's size
10. (owner) on a Wear watch with a paired phone whose bests are synced: log a
   set that beats your best for that exercise; a small `New PR` capsule in the
   theme colour appears over the top of the screen, stays through the rest
   screen and goes after about 4 seconds, with one vibration unlike the pager's
   click; a set that does not beat it shows nothing and does not vibrate; a
   watch that has never synced shows nothing; `Log`, `Next` and `Menu` work
   under the capsule; tapping `Next` inside the window shows it again on the
   logging screen
11. (owner) on a Wear watch with a paired phone that has water logged today: open
   Log food; the bar sits at the bottom, also before any food has synced, and
   shows the phone's count after a sync; `+` and `-` change it at once with a
   click, the minus is greyed at 0; a glass tapped on the phone shows after the
   next sync; the bar fits above the bezel with a food selected
12. (owner) on a Wear watch: start a Free workout, log a set, End Session and
   Finish; after the effort question when the phone asks for one the
   `Workout done` screen shows the time and the set count, and `Done` returns
   to the start screen; a workout ended with nothing logged shows none; ending
   the workout from the phone shows none; the screen fits the round face and
   scrolls on a small one
13. (owner) on a Wear watch in a debug or profile build: the Start screen shows
   `Diagnostics`; it opens a screen that says when the app started and what it
   saw last before that, with the newest log lines under it (a launch, a scene
   change, a reachability change, a frame sent or received); the lines name
   frame types and never a weight, a name or a number you logged
14. (owner) on a Wear watch with the phone out of reach (its Bluetooth off): do a
   workout, adding three exercises and logging sets, and end it; turn Bluetooth
   back on; the phone shows the workout once, complete, with every logged set,
   not one copy per change (the watch's Diagnostics lines show one queued
   snapshot per change, the phone's history one workout)
15. (owner) on a paired watch and phone: close the watch app (swipe it away),
   start a workout on the phone and add an exercise, then open the watch app; it
   shows the workout without pressing `Sync`. Then close the phone app, finish a
   workout on the watch with the phone out of reach, bring the phone back and
   open its app; the workout is in its history
16. (owner) on a real small round watch: the Start screen scrolls as one list;
   the first routine is on screen and starts; `Sync`, `Free workout` and
   `Log food` can be scrolled to and pressed; no word of the first line is
   clipped by the bezel; no overflow banner in a debug build
17. (owner) on a real Wear watch (Wear OS 5 and, if you have one, Wear OS 6): start
   a workout; the system asks to allow access to vital-sign sensor data; allow
   it and the logging screen shows a heart rate that follows your pulse; end the
   workout and the `Workout done` screen shows `Avg HR`; deny it and logging works
   with no heart rate
20. (owner) on a real Wear watch: start a workout; a `Workout in progress`
   notification appears and the heart rate keeps updating when you lower your
   wrist for a minute and raise it; end the workout and the notification goes;
   force-stop the app mid-workout and reopen it: no workout is left running in
   the watch's own workout list
19. (owner) on a real Wear watch with GPS: start a run (an exercise with a
   distance); the system asks to allow location; allow it and walk or run in the
   open; the logging screen's sensor line shows a distance that grows with you in
   the phone's unit, and the `Workout done` screen's figures agree; deny it and
   logging works with no distance; an exercise without a distance never asks
18. (owner) on a real small round watch: the logging screen's exercise name and
   heart-rate line are whole and centred at the top, the `n/N` counter shows with
   a long name, and `Log` and `Menu` are where they were

> **Doc freshness** — Derived from `lib/watch/`, `android/app/` and
> `packages/omnitrain_watch_link/` on 2026-11-21. If a claim here disagrees with
> the source, the source wins.
