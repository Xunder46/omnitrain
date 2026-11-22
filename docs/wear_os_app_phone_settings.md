# The Wear OS App: the phone's settings, the effort rating and the accent colour

> Split from [The Wear OS App](wear_os_app.md) on 2026-11-22 to keep both pages under the indexing ceiling; the sections below moved whole.

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
theme colour, cyan (`test/wear_accent_theme_test.dart`
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

> **Doc freshness** — Derived from `lib/watch/` on 2026-11-21. If a claim here disagrees with
> the source, the source wins.
