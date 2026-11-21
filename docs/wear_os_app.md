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
for the next sync to re-send. Its durability table is the same one the Swift
`WatchConnectivityBridge` uses.

The wrist stores everything in its own Hive directory (`omnitrain_watch`), so a
watch never shares a box with anything else on the device.

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
`S-28135 a session whose only slot was removed keeps its actions`). The menu
has no effort-rating prompt either — that is plan 280's open item 3.

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

## The phone's settings

The phone sends its settings to the wrist in a `preferences_down` message,
which the shell hands to `WatchSyncOrchestrator` and the orchestrator routes to
the wrist's `WatchPhonePreferences` (`test/wear_phone_settings_test.dart`
`S-28310 the orchestrator routes preferences_down to the settings owner`).
A watch that has never heard from the phone keeps the old behaviour:
until the phone has sent its settings the wrist reads kilograms and kilometres,
with the rest ping off and no effort rating asked
(`test/watch_phone_preferences_test.dart`
group `S-28301 a fresh owner over an empty store`, test
`every getter reads its default and current is null`).

A copy the wrist accepts honours the weight and the distance unit on the
logging surface — the value, the step and the label — while the dialled and
logged values stay in kilograms underneath, so a unit change never converts a
stored value twice (`test/wear_phone_settings_test.dart`
`S-28311 the logging state reads the phone's unit on every access`), and the
Rest Ping interval in seconds (0 = Off) on the rest surface
(`S-28313 the rest ping interval follows the phone`). The copy's
effort-rating flag and accent colour are stored but nothing shows them yet —
the rating prompt and the accent theming stay on the Apple-only list above
(`test/watch_phone_preferences_test.dart`
group `S-28302 one preferences_down copy applies`, test
`the getters show the copy and one row is stored`).

The wrist stores every copy it accepts and applies the newest by the phone's
own stamp: a late copy with an older stamp is dropped and not stored
(`test/watch_phone_preferences_test.dart`
group `S-28304 a late older copy is dropped`, test
`it returns false, the newer copy stands and no row is added`), a tie in the
stamp goes to the copy received later (group
`S-28305 a tie in generatedAt`, test `the later-received copy applies`), a
newer copy that carries no unit puts the wrist back to kilograms or
kilometres rather than keeping the earlier copy's unit (group
`S-28306 an absent key reads as the default`, test
`a newer copy without unit or accent resets them`), a copy the wrist cannot
read is refused whole with nothing stored (group
`S-28308 an unreadable copy is refused whole`, tests `(a)`–`(g)` and the
`(f)` other-type and `(g)` validator-refusal variants), and the same message
delivered twice is stored once (group
`S-28309 the same envelope applied twice`, test
`is one row, the getters unchanged, and the replay returns true`).
The settings survive a restart: the shell restores them before the first
screen (`test/wear_phone_settings_test.dart`
`S-28312 the shell restores the stored settings at launch`), the same
round-trip over the in-memory store and the Hive store (group
`S-28307 a relaunch restores the copy` in
`test/watch_phone_preferences_test.dart`, tests
`Mock: a new owner over the same store reads the copy back` and
`Hive: a new owner over the same boxes reads the copy back`). A unit the
phone changes while a session runs reaches the wrist at its next sync and
shows on the next once-a-second repaint
(`test/wear_phone_settings_test.dart`
`S-28312b a copy that arrives while the session runs shows on the next repaint`).

## What the wrist shows

The start surface (synced routines, free training, the quick-log entry, a manual
sync), the logging surface (one effort, its values, one Log), the rest surface
(the elapsed rest and one Next), and the nutrition quick-log.
The Menu button under the logging surface
and the rest surface opens the exercise menu, the Apple wrist's menu without a remove control (D-28102).

The Apple wrist hosts more: the swipe pager between exercises,
the effort-rating prompt,
the personal-record banner, the water bar, the
workout summary, the diagnostics view, spoken timer cues and the accent
theming. None of those is on the Wear wrist; the plan that built this shell
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
- `test/wear_app_test.dart` — the shell's choice of surface and the two ways it
  handles an arriving frame, over an in-memory store.
- `test/watch_session_menu_engine_test.dart` — the jump, the append-at-end add
  and the slot ids.
- `test/watch_menu_state_test.dart` — the menu's rows and counts, the
  work-clock lock, and what End has to save.
- `test/wear_menu_screen_test.dart` — the menu over the shell: the ladder rows,
  the three actions, the Finish and Discard questions, the add path and the
  phone-side removal.
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

> **Doc freshness** — Derived from `lib/watch/`, `android/app/` and
> `packages/omnitrain_watch_link/` on 2026-11-21. If a claim here disagrees with
> the source, the source wins.
