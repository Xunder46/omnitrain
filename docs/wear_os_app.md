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
effort-rating flag and accent colour are stored
(`test/watch_phone_preferences_test.dart`
group `S-28302 one preferences_down copy applies`, test
`the getters show the copy and one row is stored`); the effort-rating flag
asks the question after End and at launch (the section
`## The effort-rating prompt` below), and
the accent colour tints the buttons (`test/wear_accent_theme_test.dart`
`S-28611 a delivered accent becomes the shell's`).
The accent theming is described in `## The accent colour` below.

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

## The effort rating, underneath

The rating is an engine fact first; the screen that asks for it is the
section after this one. The wrist records a session's effort rating once:
`recordEffortRating` appends one `effort_rating` observation whose id is
`rating-<sessionId>`, sends it to the phone in exactly one `observations_up`
frame, and a second call for the same session returns null and changes
nothing (`test/watch_effort_rating_engine_test.dart`, group
`S-28401 recordEffortRating`, test
`S-28401 record -> row fields and exactly ONE observations_up frame`;
`S-28402 a second recordEffortRating returns null and changes nothing`).
The engine knows a session already has a rating — when it holds the row
(`S-28403 hasEffortRating is false before, true after, false for another
session`), when the phone's own snapshot carried one
(`S-28406 the phone's session_snapshot closes the question`), and when the
phone acknowledged the wrist's rating and the row was pruned since, so a
relaunch still knows the answer (group
`S-28405 a confirmed and pruned rating is still known after relaunch`, test
`S-28405 Mock: pruneConfirmed forgets the row, not the answer`) — and a
rating outside 1 to 5 is refused with nothing stored
(`S-28404 a rating of 0 and of 6 is refused and stores nothing`). The kind
is its own observation kind, not one of the effort kinds a slot counts
(`S-28408 the constants`).

the Wear screen asks for it after End and at launch: the wrist's End can owe a
rating, and it stores that debt as a note. When the phone's setting asks
for one, the session still holds at least one effort entry after the
phone's deletions, and it has no rating yet, `end()` finishes the session
and stores one `rating_prompt` row, so that a kill before the answer still
asks at the next launch (`test/watch_effort_rating_state_test.dart`,
`S-28410 End with the setting asking stores one owed prompt`; group
`S-28414 the owed note survives a relaunch`, test
`S-28414 Mock: a fresh state over the same store still owes`). No prompt is
owed when any of the four conditions fails — the setting off, only a rest
and no effort entry, a session that already holds a rating, a wrist that
never heard from the phone (group
`S-28411 nothing is owed when one of the four conditions fails`, tests
`S-28411a the setting is off` through
`S-28411d the wrist never heard from the phone`), when the phone deleted
the only effort entry before End
(`S-28412 the phone's deletions are seen before End`), or when there is no
active session (`S-28413 no session: null, nothing stored`). With two
sessions owed the most recent is asked first, and answering it surfaces the
next (`S-28415 two owed sessions: the newest asked first, the answer clears
it`). The note row itself round-trips through both stores, and appending
the same record id twice stays one row (group
`S-28407 a WatchRatingPromptRecord round-trips through each store`, test
`S-28407 Hive: one row per session, appended twice stays one`).

The question's words and scale are the phone's own, held to
`watch/contract/watch_effort_rating_contract.json`: "How hard was this
session?" on a 1 to 5 scale, "Very easy" to "Max effort", nothing
preselected (group `S-28409 the copy holds to the contract file`, test
`S-28409 title, scale and labels match the contract`). A pick comes by tap
or by rotary detents: the first step up picks 1, further steps move one
number each and stop at the ends, a step down never returns to nothing, and
a pick outside 1 to 5 is ignored (group `S-28416 the pick rules`, tests
`S-28416 step(1) from nothing picks the lowest`,
`S-28416 step(-1) from nothing picks nothing`,
`S-28416 select(4) then step(-10) stops at the bottom` and
`S-28416 select(0) and select(6) change nothing`). Confirm works only with
a number picked
(`S-28417 Confirm needs a pick, records once, and clears the question`);
Skip closes the question without recording anything, so the phone's own
question and the first real answer are untouched — a relaunch asks again,
and a phone-side rating arriving later still closes it
(`S-28418 Skip records nothing; a later answer still closes the question`).

## The effort-rating prompt

The screen that asks the question sits above the state the previous section
holds. On a Wear watch, when the phone's effort-rating setting is on (it
reached the watch at a sync) and a workout with at least one logged effort is
ended from the menu (`End Session`, then `Finish`), the watch shows the
question alone: "How hard was this session?", the numbers 1 to 5 with the end
labels "Very easy" and "Max effort", a Confirm button that stays disabled
until a number is picked, and a small Skip
(`test/wear_effort_rating_screen_test.dart`
`S-28501 End with the setting on shows the question alone`,
`S-28508 Confirm is disabled until a number is picked`). There is no menu and
no back button on that surface: the screen builds its own `Scaffold` with no
back control (`lib/watch/logging/watch_effort_rating_screen.dart`), and the
shell's Menu button is not on it
(`test/wear_effort_rating_screen_test.dart`
`S-28501 End with the setting on shows the question alone`).

A tap picks a number
(`test/wear_effort_rating_screen_test.dart`
`S-28503 Confirm records the picked rating and shows the start surface`);
the rotary — a scroll — or a vertical drag steps it, a turn away from the
wrist raising it, the first step up picking 1
(`test/wear_effort_rating_screen_test.dart`
`S-28505 the rotary steps the number`,
`S-28505b a turn down from nothing picks nothing`,
`S-28506 a vertical drag steps the number`). Confirm sends the rating to the
phone in exactly one `observations_up` frame and shows the start screen
(`test/wear_effort_rating_screen_test.dart`
`S-28503 Confirm records the picked rating and shows the start surface`);
Skip shows the start screen and sends nothing
(`test/wear_effort_rating_screen_test.dart`
`S-28504 Skip shows the start surface and records nothing`). The numbers are
named "N of 5" for a screen reader
(`test/wear_effort_rating_screen_test.dart`
`S-28509 the numbers are named for a screen reader`).

The question is asked again at the next launch when the app was closed on it
(`test/wear_effort_rating_screen_test.dart`
`S-28510 the question is asked again at launch`) and closes by itself if the
phone answers first (`test/wear_effort_rating_screen_test.dart`
`S-28511 the phone answering first closes the prompt`). With the setting
off, with nothing logged, after a Discard, or in a shell built without the
rating state, nothing is asked (`test/wear_effort_rating_screen_test.dart`
`S-28502a the setting off shows the start surface`,
`S-28502b the setting on but nothing logged shows the start surface`,
`S-28514 Discard owes nothing`,
`S-28512 a shell without a rating state never asks`). The entry point
`lib/watch/wear_main.dart` builds the rating state and hands it to the shell.

The screen fits the 192 dp and 227 dp round watches at exact compact sizes —
Confirm 40 dp tall, Skip floored at 32 dp, the number buttons 32x36 — and
scales down rather than overflowing on a crowded one
(`test/wear_effort_rating_screen_test.dart`
`S-28507a the prompt fits 227x227`,
`S-28507b the prompt fits 192x192`,
`S-28507c a crowded watch still fits the prompt`). On the desktop QA harness
(`flutter run -d macos -t lib/watch/debug/wear_menu_debug_main.dart`) the
setting is switched on, so End shows the prompt there.

## The accent colour

The wrist wears the colour of the phone's theme. Once a sync has carried a
`preferences_down` copy with an accent, the theme's primary colour — which
the buttons, the selected number in the rating question and the selected
food's border on the nutrition screen all take — is that colour, with
labels that read on it (`test/wear_accent_theme_test.dart`
`S-28611 a delivered accent becomes the shell's`). Before the first sync,
when the copy carries no accent, and when the colour is too dark to read on
the black screen — its contrast against black under the floor
`WatchAccent.minContrastAgainstBlack` — the wrist wears the phone's default
theme colour, cyan `#2DE2E6` (`test/wear_accent_theme_test.dart`
`S-28610 the fresh shell wears the phone's default accent`;
`test/watch_accent_test.dart`
`S-28605 worn falls back or wears the accent`).
The label on a coloured button is black or white by which reads better on
that colour; all six phone themes in the contract take black
(`test/watch_accent_test.dart`
`S-28604 the label rule compares the two contrasts`,
`S-28601 the contract's six accents parse and read the table's contrast
figures`).

A colour that arrives while the watch is open shows on the repaint the
arriving frame itself triggers, with the short fade `MaterialApp` gives a
theme (`test/wear_accent_theme_test.dart`
`S-28611 a delivered accent becomes the shell's`). A newer copy replaces
the colour, an older one does not, and a later copy that carries no accent
sends the wrist back to cyan rather than keeping the old colour
(`test/wear_accent_theme_test.dart`
`S-28612 a newer copy replaces it, a copy without accent restores the
default`,
`S-28614 an older copy does not replace the newer one`). The colour
survives a restart: the restored copy dresses the first settled frame
(`S-28616 a store that holds a copy dresses the new shell`). A shell built
without a preferences owner stays on the default
(`S-28615 a shell without preferences stays on the default`).

How it works: `WatchAccent` (`lib/watch/widgets/watch_accent.dart`) is the
Dart twin of the Apple client's `WatchAccent.swift`. It accepts exactly
`#RRGGBB` and nothing else
(`test/watch_accent_test.dart`
`S-28602 the parser accepts #RRGGBB and nothing else`), computes the WCAG
relative luminance and the two contrast ratios from the hex, refuses an
accent whose contrast against black is under the floor
(`S-28603 the wearability floor is 3.0`), decides the label by which
contrast wins (`S-28604 the label rule compares the two contrasts`), keeps
the channels in the order the hex names them
(`S-28606 the channels are not mixed`), and its `worn` falls back to the
default cyan whenever the string is absent, unreadable or too dark
(`S-28605 worn falls back or wears the accent`).
`WearAppState._themeFor` (`lib/watch/app/wear_app.dart`) copies the dark
Material scheme changing only `primary` and `onPrimary`, so the destructive
and tonal buttons keep their colours, and caches the `ThemeData` by the hex
it was built from, so the shell's once-a-second rebuild does not re-theme
the tree (`test/wear_accent_theme_test.dart`
`S-28617 the theme is cached across the 1 s ticks and rebuilt on a new
accent`).

The six accents are the contract table
`watch/contract/watch_accent_contract.json`, which the tests walk rather
than restate (`test/watch_accent_test.dart`, group
`S-28601 the contract's six accents parse and read the table's contrast
figures`). The unit half is `test/watch_accent_test.dart`, scenarios
`S-28601` to `S-28606`, one clause each; the shell half is
`test/wear_accent_theme_test.dart`, scenarios `S-28610` to `S-28617`, one
clause each. Nothing about the accent stays Apple-only; what remains
different is that the desktop QA harness delivers a copy with no accent, so
it wears the default cyan and offers no accent picker
(`S-28612 a newer copy replaces it, a copy without accent restores the
default`).

## The exercise pager

With a session of two or more exercises the logging surface shows one exercise and a small `n/N` counter right after its name. A horizontal swipe moves to the neighbouring exercise: to the left for the next one, which slides in from the right edge, to the right for the previous one, which slides in from the left. A swipe past either end does nothing, a drag shorter than 24 points does nothing, and a vertical drag belongs to the value rows. While a work clock (elapsed, hold or round) runs there is no paging: the swipe gives a short vibration and the words `An effort is running` for 1.5 seconds. A move the user did not make (the phone, the menu, the rest screen's Next) shows the new exercise at once, with no slide, and with the system's reduced-motion setting the slide is a plain fade. The rest surface is not paged.

The rule is the Apple wrist's, described in [The Watch Surface: the Wrist's Exercise Pager](state_management/watch_surface_wrist_pager.md): the pager is a rule over the menu, so a settled swipe is the menu's own jump (`WatchPagerState` in `lib/watch/logging/watch_pager_state.dart`; the widget is `WatchLoggingPager`). Three things differ on Wear, each a decision of [plan 287](plans/2026-11-21-287-wear-swipe-pager-plan/2026-11-21-287-wear-swipe-pager-plan.md). There is no focus: the Apple wrist shows the swiped-to page before the engine has moved, while here the swipe awaits the jump and the logger ignores touches until it lands, so `Log` cannot write to the exercise being left. A second swipe during that jump is ignored. And the pager binds no rotary input: the value rows keep it.

## The personal bests

The phone sends each exercise's standing best in a `bests_down` message: the best estimated one-rep max in kilograms and the most reps at zero load, one entry per exercise the user has completed a set for. The Wear wrist keeps the newest frame (`WatchPersonalBests` in `lib/watch/logging/watch_personal_bests.dart`; a frame is stored as a `WatchBestsRecord`) and nothing else: a frame stamped earlier than the held one is dropped, a frame with the same numbers writes nothing, a frame the wrist cannot read is refused whole, frames are applied one at a time, and the store keeps only the newest frame (`pruneBests`, the third prune on the store contract). Given a set, the wrist can say whether it beats the standing best: the larger of the frame's best and the best of the sets the wrist itself holds, strictly greater, on the weight axis (the estimated one-rep max, at most 12 reps counted) for a loaded set and on the reps axis otherwise. A wrist that never received a frame says nothing; with a frame held, an exercise the phone has no history for makes its first set a record.

The rule is the Apple wrist's (`WatchPersonalBests.swift`; the owner's decisions are in [series 87](plans/2026-10-26-87-wrist-new-pr-banner-index.md)) and the plan is [plan 288](plans/2026-11-22-288-wear-personal-bests-plan/2026-11-22-288-wear-personal-bests-plan.md). A set that beats the standing best shows a small `New PR` banner (plan 289, `lib/watch/widgets/watch_personal_record_banner.dart`): a trophy and the words in the phone's accent colour over the top of the screen for 4 seconds, with one distinct vibration (the platform's plain vibration; the pager's click, the lock's heavy tap and the rest ping's medium tap are taken). The verdict is read on one path only, when the wrist logs the set, so a set the phone logged never fires it and a wrist that holds no frame says nothing. Logging a set starts a rest at once and the rest screen replaces the logging screen, so both screens overlay the same banner and a record is not torn down with the screen that logged it; a second record inside the window restarts the 4 seconds. The banner takes no touch, so `Log`, `Next` and `Menu` work under it, and a screen reader announces `New personal record`. One difference from the Apple wrist: a record still inside its window when the user taps `Next` is announced again by the logging screen's banner.

## The water count

The phone owns the day's water. The Wear wrist asks for it on every sync (its routines request carries `wantsWater`, and `holdsBests` when it already holds the phone's bests, so the phone sends a bests frame only when one changed; both are set in `lib/watch/wear_main.dart` on the Wear transport) and keeps the newest `water_down` frame (`WatchWaterState` in `lib/watch/nutrition/watch_water_state.dart`, stored as a `WatchWaterRecord`): an older frame is dropped, a frame with the same numbers writes nothing, an unreadable one is refused whole, frames are applied one at a time, and the store keeps only the newest (`pruneWater`, the fourth prune on the store contract).

The wrist can log one tap of the water bar (`logWaterGlass` on the engine): a glass added or removed, stored first and sent as a `water_glass` event until the phone receipts it. A tap is never part of a workout: its session id is always the day's nutrition log, even while a workout runs. The count the bar will show is never stored; it is computed on every read: the phone's count when its frame is for the wrist's local today, else 0, plus the wrist's own taps of local today that the frame does not list (confirmed or not: only the frame's list takes a tap out), in time order, an add +1 and a remove -1 but never below 0. The plus stops at 500 taps a day (the phone's own cap), the minus also at 0. The rule is the Apple wrist's (series 94-96); the plan is [plan 290](plans/2026-11-22-290-wear-water-count-plan/2026-11-22-290-wear-water-count-plan.md). The water bar sits at the bottom of the Log food screen (plan 291, `lib/watch/nutrition/watch_water_bar.dart`), under the foods list or the "No foods yet" message and nowhere else, so no water is logged from inside a workout: a minus, a drop with the count and a plus, each press one glass added or removed and shown at once, before the phone answers, with one click when a tap was stored. The minus is greyed at 0 and both buttons at the day's 500 taps. A frame that arrives while the screen is open changes the count, and local midnight with the screen open shows the new day's count within a minute (the bar re-reads once a minute). A screen reader says `Remove one glass`, `Add one glass`, and for the middle `Water` with `3 glasses` (`1 glass`). The launch prune of old confirmed taps (plan 96) is not built: taps grow by at most 500 a day and every read skips the days it does not need unread.

## What the wrist shows

The start surface (synced routines, free training, the quick-log entry, a manual
sync), the logging surface (one effort, its values, one Log), the rest surface
(the elapsed rest and one Next), and the nutrition quick-log.
The Menu button under the logging surface
and the rest surface opens the exercise menu, the Apple wrist's menu without a remove control (D-28102).
A swipe on the logging surface moves between the exercises (the pager, below).

The Apple wrist hosts more: the
workout summary, the diagnostics
view, and spoken timer cues. None of those is on the Wear wrist; the plan that
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

> **Doc freshness** — Derived from `lib/watch/`, `android/app/` and
> `packages/omnitrain_watch_link/` on 2026-11-21. If a claim here disagrees with
> the source, the source wins.
