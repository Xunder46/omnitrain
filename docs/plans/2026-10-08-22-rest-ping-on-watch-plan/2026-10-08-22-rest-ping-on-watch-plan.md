# Feature: the rest ping works on the watch too, from the one setting on the phone (22)

> Status: Iteration 1 active — Phases 1–2 only after the 2026-10-08 scope split (see ## Split). Expanded from
> the governor's seed: its Ledger, core scenarios and phase outline are kept verbatim below, the planner's
> additions are marked, and every moved entry is marked `→ moved to plan 22b`
> Next handoff: @developer (Phase 1)
> Binding conventions: `docs/global_conventions.md` (+ `docs/rest_tracking.md`, `docs/theme_and_settings.md`,
> `docs/watch_session_sync.md`, `docs/state_management/watch_surface.md`, `docs/documentation_standard.md`, by path)
> Part of the 18 series (follows 18b D-163 and its Open question 7) — index: `docs/plans/2026-10-08-18-watch-qa-index.md`
> Evidence: `2026-10-08-22-rest-ping-on-watch-plan.evidence.md` · Review: `2026-10-08-22-rest-ping-on-watch-plan.review.md`

## Split (governor's scope check, 2026-10-08)

This plan holds **Phase 1 (contract and phone)** and **Phase 2 (Apple Watch)**: the wire, the phone sender,
the Apple Watch ping and their tests. The Wear mirror, the Settings subtitles, the rule reword, the docs and
the contract test's reword moved **whole** to
`docs/plans/2026-10-08-22b-rest-ping-wear-settings-docs-plan/2026-10-08-22b-rest-ping-wear-settings-docs-plan.md`
(plan 22b), which cites this plan's D-ids by path rather than restating them. No id below is renumbered or
reused; a moved entry keeps its line and carries `→ moved to plan 22b`. Acceptance criteria 4 and 5 ship in
22b, plan 22's last phase is Phase 2, and the full `flutter test` run moved with it.

## Overview

18b made rest a count-up on both devices and left one question open (its Open question 7): the phone has an
optional **Rest Ping**, a nudge at intervals during its own open rest, and the new rule said "no rest alarm
anywhere". The owner answered:

> "It should stay and work similar on the watch too. The ping can be set in the settings screen and should
> affect both mobile and watch."

What the user sees after this PR:

- **Settings → Rest Ping** (the row that exists today: Off, 30s, 45s, 1 min, 1.5 min, 2 min, 3 min) is one
  setting for the phone **and** the watch. Its wording says so.
- **On the phone**, nothing changes: during an open rest it nudges every N seconds of elapsed rest.
- **On the watch**, while the rest screen counts up, the wrist taps every N seconds of elapsed rest, until
  Next. Off means no tap. The watch plays no sound, so **Rest Ping Sound** stays a phone-only setting and
  says so.
- A ping is still **not a rest timer**: the rest has no length, nothing counts down, nothing says the rest
  is over. It is a repeating nudge about time already spent.
- The wrist learns the interval when it syncs with the phone (the way it already learns the effort-rating
  setting), so a change made on the phone reaches the wrist at its next sync. Before it has ever synced, the
  wrist does not ping.
- Like every wrist-side cue today, the tap can only fire while the watch app is running (19c is the open
  item that would change that).

### Acceptance criteria

1. One setting (`SettingsState.restPingInterval`) drives both devices; no second watch setting exists.
2. `preferences_down` carries the interval; both validators and the schema accept it and refuse a malformed
   one; the wrist stores it with the rest of the preferences and reads the newest copy.
3. The wrist (Apple Watch client, Swift) taps at each multiple of the interval while a rest is open, never
   for a closed rest, never when the interval is Off or unknown, and fires at most once per poll even after a
   long gap (a screen that was off does not produce a burst).
4. **(→ ships in plan 22b)** The Wear OS Dart mirror of the wrist logging surface follows the same rule
   from the same fixtures.
5. **(→ ships in plan 22b)** The conventions rule, the docs and the rest contract test say: no rest length,
   no countdown, no end-of-rest alarm; the rest ping is the one allowed cue — and the contract test still
   fails if a rest length, countdown or alarm comes back.
6. Suites green with the baselines: the flutter suites named in each phase's Done Criteria, swift 359 / 0,
   analyze 196 / 0, xcodebuild of "OmniTrain Watch App" succeeds (governor runs it). The full
   `flutter test` run and the Dart-only checks ship with plan 22b.

## Decision Ledger (seeded)

**D-240 — The rule, restated.** Rest has no preset length, no countdown and no end-of-rest alarm, on any
device (18b D-160/D-163 stand). The **rest ping** is the one permitted rest cue: a repeating count-up nudge
every N seconds of elapsed rest while a rest is open, N from the setting. It ends with the rest and is never
phrased or planned as "rest over". `docs/global_conventions.md` row "Rest rule: rest is a count-up" is
reworded to say exactly this; `docs/theme_and_settings.md:9` already describes the phone's half.
**→ moved to plan 22b:** the `docs/global_conventions.md` row reword (22b D-263); D-240's rule binds Phases
1–2 here as written.

**D-241 — One owner for the setting.** The interval is `SettingsState.restPingInterval` (seconds, 0 = Off,
the closed set `restPingIntervalOptions`, `lib/state/settings/settings_state.dart:41`). The watch never
stores or edits its own copy of the choice; it only holds the last copy the phone sent (D-242). The sound
(`restPingSound`) is phone-only; the wrist's ping is a haptic tap. `settings_screen.dart` rows "Rest Ping"
(`:384`) and "Rest Ping Sound" (`:396`) get subtitles that say "phone and watch" / "phone only".
**→ moved to plan 22b:** those two subtitles (22b D-262); the labels and this ownership rule stay here.

**D-242 — Wire.** `preferences_down.payload` gains `restPingSeconds`: a non-negative integer, 0 = Off,
required. The wire carries seconds, not the option list; the closed set stays the phone's. Edits:
`WatchReferenceSync.buildPreferencesDown` (`lib/core/utils/watch_reference_sync.dart:306`) takes
`restPingSeconds` and its `messageId` includes it (a different interval stamped in the same millisecond is a
different message, as `on`/`off` already is); `WatchSyncRequestHandler._sendRoutines`
(`lib/state/watch/watch_sync_request_handler.dart:73`) passes `_settings.restPingInterval`;
`watch/sync_protocol/schemas/messages/preferences_down.schema.json` (required list and
`additionalProperties:false` both need the key); fixture `fixtures/valid/preferences_down.json` plus new
invalid fixtures (negative, string, missing); the Dart and Swift validators; `PROTOCOL.md` line 70/92. v1 is
unreleased: no compatibility shim. One tolerance only: a preferences row already stored on a wrist without
the key reads as 0 (Off).

**D-243 — The ping rule (one rule, three consumers).** State per rest: `lastPinged` seconds (0 at start).
At each poll with `elapsed` whole seconds of the open rest and `interval > 0`: `boundary = (elapsed ~/
interval) * interval`; fire iff `boundary > 0 && boundary > lastPinged`, then set `lastPinged = boundary`.
Consequences, all intended: polled every second it fires exactly at each multiple (identical to the phone's
`shouldFireRestPing`, `lib/core/utils/rest_ping_utils.dart`); a poll after a gap fires **once**, not once per
missed multiple; changing the interval mid-rest never fires immediately for an already-passed boundary.
`lastPinged` is keyed on the rest row's `recordId`, so the next rest starts clean. The phone keeps its
existing function (not rewritten); the shared fixtures prove it agrees on the one-second cases.

**D-244 — Where the wrist evaluates it.** In the module, a small `WatchRestPing` type
(`watch/watchos/Sources/WatchSessionEngine/`), testable without UI: given the open rest row, elapsed seconds
(`WatchLoggingState.restElapsedSeconds()`, `WatchLoggingState.swift:275`) and the interval
(`WatchPhonePreferences.restPingSeconds`, new, 0 before the first sync), it returns whether a tap is owed.
`WatchRestView` (`WatchRestView.swift`, its 1-second `TimelineView`) asks it on every tick and plays the tap
through the haptic player. `WatchTimerHaptics.poll` stays untouched and keeps returning nothing for a rest
(`testS164ARestIsNeverOwedAnAlert`, `WatchLoggingTimersTests.swift:102`) — the ping is a separate path, so
the "no countdown alert" guard keeps its meaning.

**D-245 — Dart mirror. → moved to plan 22b** (22b D-261, D-265): `lib/watch/logging/` gets the same rule as
a pure function/class, `watch_rest_screen.dart` taps (`HapticFeedback`) from it, and the interval comes in
through the same route as `WatchUnitPreferences.fromSettings(SettingsState)`
(`lib/watch/logging/watch_metric_stepping.dart:45`). The id stays here so it is never reused.

**D-246 — Shared fixtures.** `watch/contract/watch_rest_ping_contract.json` holds the cases (interval,
poll series in elapsed seconds, expected tap seconds). Swift, Dart and the phone rule's one-second cases all
read it — the same figure on every surface is computed from one table, and one test per consumer asserts it.
**→ moved to plan 22b:** the Dart consumer and its test (22b D-261); the table and the Swift and phone
consumers stay with Phase 1 items 6–7.

**D-247 — Docs and the contract test.** `docs/rest_tracking.md` (the ping paragraph at `:15`),
`docs/theme_and_settings.md:9`, `docs/state_management/watch_surface.md` (≈50.9 KB, ceiling 51.2 KB:
**remove before adding**), `watch/sync_protocol/PROTOCOL.md`, and the 18 index row for this PR.
`test/rest_is_count_up_contract_test.dart` (493 lines; fixture prose at `:360` says "no rest alarm
anywhere") is reworded so the scanner's allowance is named and narrow; its S-166 red cases (stored rest
length, planned rest, countdown) must still fail.
**→ moved to plan 22b:** all of it but the `PROTOCOL.md` key documentation, which stays with Phase 1 item 3
(22b D-263, D-264).

**D-248 — Out of scope, stated so it stays out.** A sound on the wrist; a wrist notification while the app
is suspended (19c); the wrist rest reaching the phone's rest history (18c — its imported rests are closed,
so they never ping on the phone, D-163/D-167); the vestigial routine "Rest duration" field; any new setting
on the watch.

**D-249 — No double ping.** Until 18c a rest lives on the device that logged the set, so one rest pings on
one device. The plan records this and 18c inherits it (closed imported rests never ping).

### Ledger additions (planner, this iteration — appended, nothing above edited)

**D-250 — D-243's formula governs the case where the interval arrives mid-rest** (derived; vetoable,
Open question 1). D-243's last consequence reads against its own formula for a boundary that fell *before*
the interval arrived: the formula fires (`boundary > 0 && boundary > lastPinged`), the sentence ("never
fires immediately for an already-passed boundary") reads as never. The formula is the contract; the
sentence describes S-244's case, a boundary that was already **pinged**. So a wrist holding 0 until a copy
with 30 lands at elapsed 20 taps at 30, 60, 90; landing at 35 it taps once on the next poll (boundary 30)
and then at 60 and 90. S-222 pins this.

**D-251 — The wrist's ping is its own haptic entry point, not a milestone.** `WatchHaptics` gains
`playRestPing()` (`watch/watchos/Sources/WatchSessionEngine/WatchLoggingModel.swift:124`; Dart
`lib/watch/logging/watch_logging_screen.dart:30`). `WatchTimerMilestone` gains no case and
`WatchTimerHaptics.poll` learns nothing about rests (D-244), so `testS164ARestIsNeverOwedAnAlert` keeps its
meaning. The tap is light and distinct from a countdown's end: `WristHaptics` (`WatchLoggingView.swift:32`)
plays `.click` for the ping and keeps `.notification` for a milestone; Dart's `SystemWatchHaptics`
(`watch_logging_screen.dart:36`) uses the `HapticFeedback.mediumImpact()` it already uses. Recording stubs
count pings: `RecordingHaptics` (`WatchLoggingModel.swift:112`), `_RecordingHaptics`
(`test/watch_logging_surfaces_test.dart:81`).
**→ moved to plan 22b:** the Dart `SystemWatchHaptics` half (22b Phase 1 item 3); the Swift half stays with
Phase 2 here.

**D-252 — The wrist surface's shape does not change.** `WatchRestView.init` gains the interval and the haptic
player, the latter defaulted the way `WatchLoggingView.init` already defaults it (`haptics: WatchHaptics =
WristHaptics()`), so the app target passes only the interval: `WatchRestView(state: host.logging,
restPingSeconds: host.preferences.restPingSeconds, …)` (`ios/OmniTrain Watch App/ContentView.swift:186`;
`host.preferences` is the `WatchPhonePreferences` the host already restores, `ContentView.swift:23`). The
screen still shows exercise, elapsed, Next — no new control, no sound, no picker. The rule's state lives in
the view's `@State`, so a new rest (a new branch, a new row) starts clean and D-243's `recordId` keying is
the second guard.

**D-253 — What the rest scanner may never be taught to accept, and the spelling trap.** The contract test's
allowance stays narrow (D-247): a rest *ping* is not a rest *length*, and `restPingSeconds` /
`rest_ping_interval` / `restPings` are not stored rest lengths. `_restLengthSpelling`
(`test/rest_is_count_up_contract_test.dart:65`) requires the literal adjacency "rest"+"seconds", so any
comment that says "rest seconds" — "every 30 rest seconds" — **is** a finding: the new code says "seconds of
the rest" or "elapsed". New S-250 assertions: `const restPingSeconds = 30;` yields no finding, and the
reworded prose still denies a countdown.
**→ moved to plan 22b:** the reworded prose, the scanner allowance and those S-250 assertions (22b D-264);
the spelling trap binds the Phase 1–2 code here as written.

## Feature Invariants

Only the invariants this feature can plausibly break (project-wide rules stay in
`docs/global_conventions.md`):

- **One owner for the choice.** No second setting and no watch-side edit path: the wrist holds only the last
  copy the phone sent (D-241).
- **Parity.** Swift `WatchRestPing`, Dart `WatchRestPing` and the phone's `shouldFireRestPing` report the
  same tap seconds for the same contract case (D-243, D-246). `HiveWorkoutRepository` and
  `MockWorkoutRepository` are untouched by this feature.
- **The rest rule survives.** No stored rest length, no planned rest, no countdown, no end-of-rest alarm —
  the ping is the one allowed cue, and the contract test still fails on the other three (D-247, D-253).
- **The phone's ping function is not rewritten** (`lib/core/utils/rest_ping_utils.dart`): it agrees with the
  new rule by fixture, never by refactor (D-243).
- **A closed rest never pings** on either device (D-249).

## Requirements

- **R-1** One setting, `SettingsState.restPingInterval`, drives both devices; the watch has none (D-241).
- **R-2** `preferences_down.payload.restPingSeconds` is required, a non-negative integer, 0 = Off (D-242).
- **R-3** The wrist stores it with the preferences and reads the newest copy; a row written without the key
  reads 0 (D-242, S-247).
- **R-4** The wrist taps at each multiple of the interval while a rest is open, never for a closed rest,
  never when Off or unknown, at most once per poll (D-243).
- **R-5** The Wear Dart mirror follows the same rule from the same table (D-245).
- **R-6** The convention row, the docs and the contract test name the ping as the one allowed rest cue and
  still fail on a rest length, a countdown or an alarm (D-247).
- **R-7** The Settings screen says which device each of the two rows reaches (D-241).

## Core scenarios (seeded)

All "red without the change" lines mean: the named thing does not exist or does not do this at the base
commit, so `prove-red` shows it failing there.

- **S-241 — the table, one-second polls.** `watch_rest_ping_contract.json` case `interval 30, polls 0…100`
  → taps at 30, 60, 90 and nowhere else. Asserted by Swift (`WatchRestPing`), Dart mirror, and the phone's
  `shouldFireRestPing` driven the way `_checkRestPings` drives it. Red: no `WatchRestPing`, no table.
  → moved to plan 22b: the Dart half (`test/watch_rest_ping_test.dart`).
- **S-242 — Off and unknown.** Interval 0, polls 0…600 → no tap. Wrist that never received preferences
  (`restPingSeconds` = 0 by default) → no tap. Red: no default exists. · → moved to plan 22b: the Dart half.
- **S-243 — gap catch-up fires once.** Interval 60, polls at 0, 59, then 200, then 201, then 240 → taps at
  poll 200 (once, not three times) and poll 240 only. Red: no rule. · → moved to plan 22b: the Dart half.
- **S-244 — interval change mid-rest.** Interval 60, poll at 70 (tapped at 60), interval becomes 30, poll
  at 70 → no tap; poll at 90 → tap. Red: no rule. · → moved to plan 22b: the Dart half.
- **S-245 — a rest ends, the next starts clean.** Interval 30: rest A polled to 65 (taps 30, 60), Next; rest
  B (new row) polled to 35 → tap at 30. A closed rest is never evaluated. Red: no per-row state.
  → moved to plan 22b: the Dart half.
- **S-246 — the wire.** `buildPreferencesDown(restPingSeconds: 90)` → payload `restPingSeconds: 90`; ids
  differ for 60 vs 90 at the same instant; valid fixture passes both validators; negative, non-integer and
  missing are refused by both. Red: payload has no such key; `additionalProperties:false` rejects it today.
- **S-247 — the wrist stores it.** Apply a `preferences_down` with 90 → `WatchPhonePreferences
  .restPingSeconds == 90`; an older `generatedAt` arriving late does not replace it; a stored row lacking the
  key reads 0. Red: no property.
- **S-248 — end to end on the phone.** `SettingsState.setRestPingInterval(45)`, then a wrist sync request →
  the sent `preferences_down` carries 45 (`test/watch_reference_sync_test.dart`, handler test). Red: sends no
  interval.
- **S-249 — the Settings screen says it. → moved to plan 22b** (22b D-262): with S-226, the only other
  user-visible copy change of this feature.
- **S-250 — the rule still bites. → moved to plan 22b** (22b D-264): the reworded convention + contract
  test — a fixture with a stored rest length, a planned rest or a rest countdown is still flagged, a rest
  ping is not, and the rule text names the allowance. Red: the old text and scanner allowance.

### Edge scenarios (planner, this iteration)

- **S-221 — the same second is pinged once.** Interval 30, polls at 30, 30, 30 (a redraw, a resume and a
  tick landing inside the same elapsed second) → exactly one tap. Red: no rule.
  → moved to plan 22b: the Dart half.
- **S-222 — the interval arrives mid-rest** (pins D-250). Interval 0 until a copy with 30 arrives at elapsed
  20; polls 0…100 → taps at 30, 60, 90 only. In the variant where it arrives at elapsed 35, the next poll
  taps once (boundary 30), then 60 and 90. Red: no rule. · → moved to plan 22b: the Dart half.
- **S-223 — a large interval fires only at its own multiple.** Interval 180, polls 0…200 → one tap, at 180.
  180 s is the top of the phone's own option list, so it is the largest value the wire can carry. Red: no
  rule. · → moved to plan 22b: the Dart half.
- **S-224 — a closed rest is never evaluated.** Interval 30, tap at 30, Next at 40, polls at 60, 90, 120 →
  no tap; `restElapsedSeconds()` is nil, so the rule is not consulted at all. Red: no rule.
  → moved to plan 22b: the Dart half.
- **S-225 — the ping is not the countdown path.** With a rest open, `WatchTimerHaptics.poll` driven across
  the same seconds returns nothing for the rest (`testS164ARestIsNeverOwedAnAlert`,
  `WatchLoggingTimersTests.swift:102`) while the ping path taps: the two paths are separate, and giving the
  rest a planned length still fails the guard. Red: no ping path.

## Existing-Functionality Impact

Every row carries the grep that found the readers. An entry may not read "unaffected" without one.

| Touched surface | What already reads it (the grep) | Effect of the change | Guarded by |
|---|---|---|---|
| `preferences_down.payload` gains a required key | `grep -rn effortRatingPrompt watch/ test/` → `WatchEffortRatingTests.swift:30` (the `preferencesDown` helper every preferences test builds), `WatchSessionStartPathsTests.swift:1096` (an inline "surprise" payload), `WatchFileStoreTests.swift:448` (a stored row), `WatchCaptureContractTests.swift:107` (the S-204 fixture replay), `test/watch_reference_sync_test.dart` (exact-payload equality), `test/watch_transport_test.dart` (two exact-payload equalities), `test/watch_capture_contract_conformance_test.dart:266` (S-204), `watch/contract/watch_effort_rating_contract.json` (`preferencesField: effortRatingPrompt`), `watch/contract/watch_capture_contract.json` (four `preferences` ops) | every one of them must carry the new key, or the closed payload refuses the message and the S-113 assertions that expect `applied == true` fail | S-246, S-247, Phase 1 item 8 |
| `watch/sync_protocol/fixtures/manifest.json` | `test/sync_protocol_fixtures_test.dart:149` asserts the manifest lists every fixture file on disk exactly once; `SyncProtocolFixturesTests.swift` walks the same manifest | a new fixture file that is not listed fails that walk; the invalid entries must also carry `expectedCode` + `expectedReasonContains` (`:184`) | Phase 1 item 2 |
| `SettingsState.restPingInterval` gains a reader | `grep -rn restPingInterval lib/ test/` → `workout_session_global_timer.dart:35` (the phone's own ping), `workout_session_timer_mixin.dart:383,417` and `workout_session_screen.dart:347,881` (`RestNotificationService.scheduleRestPings`, the phone's OS-level pings that keep firing while the app is backgrounded), `settings_screen.dart:387,436,467,627`, `settings_state.dart:186`, `test/settings_state_test.dart`, `test/settings_sounds_test.dart:185,205` | no existing reader changes; the sync handler is added alongside them. The phone's OS notifications are not extended to the wrist — that is 19c, out of scope (D-248) | S-248 |
| `WatchHaptics` gains a method | `grep -rn WatchHaptics watch/ lib/ test/` → `WristHaptics` (`WatchLoggingView.swift:32`), `RecordingHaptics` (`WatchLoggingModel.swift:112`), `_RecordingHaptics` (`test/watch_logging_surfaces_test.dart:81`), `SystemWatchHaptics` (`watch_logging_screen.dart:36`), `WatchLoggingScreen.haptics` (`:49`) | a new protocol requirement breaks every conformer, so all five move with it — two of them in Phase 2 here, three in plan 22b (D-251) | S-225, Phase 2 item 4, plan 22b Phase 1 item 3 |
| `WatchRestView` | `grep -rn "WatchRestView(" ios/ watch/` → `ContentView.swift:186`, the only construction site | one more argument, no shape change | S-224, Phase 2 item 6 |

Five further rows moved with Phase 3 to plan 22b and carry the same greps there: `WatchUnitPreferences`
gaining a field, the `settings_screen.dart` subtitles, the rest contract test's scanner and roots,
`docs/state_management/watch_surface.md` and `docs/plans/2026-10-08-18-watch-qa-index.md`.
## Phase outline (seeded; each phase ≤ 8 items; one run each)

1. **Phase 1 — contract and phone** (owner: developer). Schema, fixtures, `PROTOCOL.md`, both validators,
   `buildPreferencesDown`, `_sendRoutines`, `watch_rest_ping_contract.json`, phone-side conformance for the
   one-second cases. Scenarios S-241 (phone part), S-246, S-248. Tracks: sync contract + phone.
2. **Phase 2 — Apple Watch** (owner: developer). `WatchPhonePreferences.restPingSeconds` (+ record
   `toJson`/`fromJson`/`withSequence`/`applyPreferencesDown`), `WatchRestPing`, `WatchRestView` tick, the
   haptic player's ping tap (WatchOS implementation in `WatchLoggingView.swift`; recording stub in
   `WatchLoggingModel.swift:110`). Scenarios S-241–S-245, S-247 in Swift. The governor runs `xcodebuild`.
3. **Phase 3 — Wear mirror, Settings copy, rule and docs → moved to plan 22b** (owner: developer; it is now
   plan 22b's single phase, item for item: the Dart `WatchRestPing` + `watch_rest_screen.dart`, the
   `settings_screen.dart` subtitles, the `global_conventions.md` row, `rest_tracking.md` /
   `theme_and_settings.md` / `watch_surface.md` (remove before adding), `rest_is_count_up_contract_test.dart`
   and the series index row; scenarios S-249, S-250, S-226 and the Dart halves of S-241–S-245 and
   S-221–S-224).

Scope check (`.github/copilot/pr-scope-budget.md`): the check fired — over 500 lines and three tracks — so,
by this paragraph's own default, Phase 3 moved whole to plan 22b. This plan now holds two phases: the phone
and the Apple Watch client, plus the sync contract Phases 1–2 own.

## Code pointers (seeded)

| What | File : symbol (≈ line) |
|---|---|
| Phone ping rule / loop | `lib/core/utils/rest_ping_utils.dart` `shouldFireRestPing`; `lib/features/session/workout_session_global_timer.dart` `_checkRestPings` (34–63) |
| The setting | `lib/state/settings/settings_state.dart` `restPingIntervalOptions` (41), `setRestPingInterval` (185) |
| Settings rows | `lib/features/settings/settings_screen.dart` "Rest Ping" (384), "Rest Ping Sound" (396), dialog title (614) |
| Wire builder / sender | `lib/core/utils/watch_reference_sync.dart` `buildPreferencesDown` (306); `lib/state/watch/watch_sync_request_handler.dart` `_sendRoutines` (73) |
| Schema / fixtures | `watch/sync_protocol/schemas/messages/preferences_down.schema.json`; `fixtures/valid/preferences_down.json`; `fixtures/manifest.json` |
| Wrist preferences | `watch/watchos/Sources/WatchSessionEngine/WatchPhonePreferences.swift` `WatchPreferencesRecord`, `applyPreferencesDown` (125) |
| Wrist rest | `WatchLoggingState.swift` `isResting` (264), `restElapsedSeconds` (275); `WatchRestView.swift` |
| Wrist haptics (untouched) | `WatchTimerHaptics.swift` `poll`; `WatchLoggingModel.swift` `WatchHaptics` (124) |
| Dart mirror | `lib/watch/logging/watch_rest_screen.dart`, `watch_timer_haptics.dart`, `watch_metric_stepping.dart` `WatchUnitPreferences` (45) |
| Rule + guard | `docs/global_conventions.md:17`; `test/rest_is_count_up_contract_test.dart` (fixture prose `:360`) |

## Iteration 1

The first two phases of the seeded outline, expanded (the third moved to plan 22b whole — see `## Split`).
Every item names its file and the symbol it changes;
method, type and parameter names are mechanics unless a D-x fixes them. One run per phase, one agent each.

### Phase 1: contract and phone (@developer)

1. [x] Add `restPingSeconds` to both the `required` list and `properties` of
   `watch/sync_protocol/schemas/messages/preferences_down.schema.json` · `properties.restPingSeconds`
   (`type: integer`, `minimum: 0`, description "0 = Off; the wrist's rest-ping interval in seconds, from the
   phone's Rest Ping setting"). Keep `additionalProperties: false`.
2. [x] Add `"restPingSeconds": 90` to the `payload` of
   `watch/sync_protocol/fixtures/valid/preferences_down.json` and `"scenario": "S-246"` to its manifest
   entry; add three invalid fixtures and their manifest entries, each with `expectedCode` and
   `expectedReasonContains`: `fixtures/invalid/preferences_down_negative_rest_ping.json` (`-30`,
   `constraint_violation`, `"expected at least 0"`), `fixtures/invalid/preferences_down_string_rest_ping.json`
   (`"30"`, `invalid_type`, `"expected integer"`), `fixtures/invalid/preferences_down_missing_rest_ping.json`
   (key absent, `missing_required_field`, `restPingSeconds`) · `watch/sync_protocol/fixtures/manifest.json`.
   **No validator needs a code change**: both already enforce `required` (`message_validator.dart:742`,
   `SyncProtocolValidator.swift:622`), `type` (`:683`, `:556`) and `minimum` (`:854`, `:728`) from the schema,
   and both report every missing required field, so the existing
   `preferences_down_missing_effort_rating_prompt.json` entry keeps matching on `effortRatingPrompt`.
   `expectedReasonContains` is matched against the rejections' **messages**, not their paths
   (`test/sync_protocol_fixtures_test.dart:240`), so quote the message text — the precedent entries use
   `"expected at least 1, found 0"` and `"expected integer, found 3200.0"`. If any of the three fixtures is
   not refused, that is a validator finding, not a fixture to soften.
3. [x] Document the key in `watch/sync_protocol/PROTOCOL.md` · the `preferences_down` row of the
   message-family table (≈70) and the notes paragraph (≈92): seconds, 0 = Off, required, and that the wrist
   pings only while its own rest is open.
4. [x] `lib/core/utils/watch_reference_sync.dart` · `buildPreferencesDown({required bool effortRatingPrompt,
   required int restPingSeconds, required DateTime generatedAt})`: put the value in the payload and in the
   `msg-preferences-<ms>-<on|off>` id, so a different interval stamped in the same millisecond is a
   different message (D-242). The id's exact spelling is a mechanic; that it differs is not.
5. [x] `lib/state/watch/watch_sync_request_handler.dart` · `_sendRoutines` (≈73): pass
   `restPingSeconds: _settings.restPingInterval`.
6. [x] `watch/contract/watch_rest_ping_contract.json` (new): `description`, `preferenceKey`
   `rest_ping_interval`, `preferencesField` `restPingSeconds`, `beforeFirstSync` 0, and `cases` — one entry
   per contract case, `{name, intervalSeconds, pollsSeconds, tapSeconds}`, covering S-241, S-242, S-243,
   S-244, S-221, S-222, S-223. Shape it like `watch/contract/watch_effort_rating_contract.json` (top-level
   `description`, then named keys); it is the one table all consumers read (D-246).
7. [x] `test/rest_ping_contract_test.dart` (new): read the table and drive
   `shouldFireRestPing({elapsed, interval, lastPinged})` the way `_checkRestPings` drives it — walk the poll
   series, keep `lastPinged` per rest, skip when `interval == 0`, and start each new rest from 0 as the app
   does when it clears the map (`workout_session_screen.dart:782`,
   `workout_session_timer_mixin.dart:512,597`) — asserting the tap seconds for S-241's phone part, S-221 and
   S-223. Same file: the S-246 assertions on `buildPreferencesDown` (the payload value, and ids differing
   for 60 vs 90 at one instant) and the S-248 handler test (`SettingsState.setRestPingInterval(45)`, then a
   wrist sync request → the sent `preferences_down` carries 45).
8. [x] Update every existing preferences-payload builder and assertion the new required key breaks:
   `test/watch_reference_sync_test.dart` (its own `S-253 the preferences the wrist honours` group's exact
   payload equality and the `buildPreferencesDown` call — that S-id belongs to another plan, keep it),
   `test/watch_transport_test.dart` (two payload equalities), and on the watch side
   `watch/watchos/Tests/WatchSessionEngineTests/WatchEffortRatingTests.swift` · the `preferencesDown(_:asks:
   generatedAt:messageId:)` helper (≈23), which `WatchSessionStartPathsTests.swift` builds every S-113 case
   from, plus the stored row at `WatchFileStoreTests.swift:448`. The inline "surprise" payload at
   `WatchSessionStartPathsTests.swift:1096` is refused either way; re-check it, do not reword its comment.

**Done Criteria** (run until green): `.github/copilot/scripts/macos/gateway.sh lint` (issue count at the
196 baseline, 0 errors) · `.github/copilot/scripts/macos/gateway.sh test test/rest_ping_contract_test.dart
test/watch_reference_sync_test.dart test/watch_transport_test.dart test/sync_protocol_fixtures_test.dart
test/watch_capture_contract_conformance_test.dart` · `.github/copilot/scripts/macos/gateway.sh swift-test`
(the watch suite walks the manifest and builds these payloads, so it must be green here, not in Phase 2:
359 passing or more, 0 failing).

**Predicted Files**: `watch/sync_protocol/schemas/messages/preferences_down.schema.json` ·
`watch/sync_protocol/fixtures/valid/preferences_down.json` ·
`watch/sync_protocol/fixtures/invalid/preferences_down_negative_rest_ping.json` (new) ·
`watch/sync_protocol/fixtures/invalid/preferences_down_string_rest_ping.json` (new) ·
`watch/sync_protocol/fixtures/invalid/preferences_down_missing_rest_ping.json` (new) ·
`watch/sync_protocol/fixtures/manifest.json` · `watch/sync_protocol/PROTOCOL.md` ·
`lib/core/utils/watch_reference_sync.dart` · `lib/state/watch/watch_sync_request_handler.dart` ·
`watch/contract/watch_rest_ping_contract.json` (new) · `test/rest_ping_contract_test.dart` (new) ·
`test/watch_reference_sync_test.dart` · `test/watch_transport_test.dart` ·
`watch/watchos/Tests/WatchSessionEngineTests/WatchEffortRatingTests.swift` ·
`watch/watchos/Tests/WatchSessionEngineTests/WatchSessionStartPathsTests.swift` ·
`watch/watchos/Tests/WatchSessionEngineTests/WatchFileStoreTests.swift`

### Phase 2: Apple Watch (@developer)

1. [ ] `watch/watchos/Sources/WatchSessionEngine/WatchPhonePreferences.swift` ·
   `WatchPreferencesRecord`: add `restPingSeconds: Int` to the stored fields, `init`, `withSequence` and
   `toJson`/`fromJson`, with `fromJson` reading an absent key as 0 (D-242's one tolerance).
2. [ ] Same file · `WatchPhonePreferences`: expose `restPingSeconds` (the newest record's value, 0 when
   there is none — S-242's "never synced") and read the field in `applyPreferencesDown` (≈125): guard it the
   way `effortRatingPrompt` is guarded (a non-integer or negative payload is refused, the message is not
   stored), so S-247's "an older copy never replaces a newer one" keeps holding for the new field too.
3. [ ] `watch/watchos/Sources/WatchSessionEngine/WatchRestPing.swift` (new) · `WatchRestPing`, the rule of
   D-243/D-250 with no UI: given the open rest row's `recordId`, the elapsed whole seconds and the interval,
   it returns whether a tap is owed, keeping `lastPinged` per record and starting clean when the record
   changes. Cover S-241–S-245, S-221, S-222, S-223 by reading the contract file, not by restating numbers.
4. [ ] `watch/watchos/Sources/WatchSessionEngine/WatchLoggingModel.swift` · `WatchHaptics` (≈124) gains
   `playRestPing()`; `RecordingHaptics` (≈112) records each ping so a test can count them. Do not add a
   `WatchTimerMilestone` case and do not touch `WatchTimerHaptics.poll` (D-244, D-251).
5. [ ] `watch/watchos/Sources/WatchSessionEngine/WatchLoggingView.swift` · `WristHaptics` (≈32):
   `playRestPing()` plays `WKInterfaceDevice.current().play(.click)`; `play(_ milestone:)` keeps
   `.notification` (D-251).
6. [ ] `watch/watchos/Sources/WatchSessionEngine/WatchRestView.swift` · `WatchRestView`: take the interval
   and a `WatchHaptics` defaulted to `WristHaptics()` (as `WatchLoggingView.init` does), hold the rule in
   `@State`, and ask it inside the existing `TimelineView(.periodic(from: .now, by: 1))` tick, playing the
   tap when it is owed — the elapsed still comes from `state.restElapsedSeconds()`. Then
   `ios/OmniTrain Watch App/ContentView.swift` · `WatchAppHost`'s `Group` branch (≈186): pass
   `restPingSeconds: host.preferences.restPingSeconds`. Nothing else on the screen changes (D-252).
7. [ ] `watch/watchos/Tests/WatchSessionEngineTests/Fixtures.swift` · add the contract reader (as
   `effortRatingContract()` does) and `watch/watchos/Tests/WatchSessionEngineTests/WatchRestPingTests.swift`
   (new): S-241–S-245, S-221, S-222, S-223 driven from the contract, S-242's never-synced default, S-224's
   closed rest, S-225's separation from `WatchTimerHaptics`, and S-247's store/read/tolerance assertions.

**Done Criteria** (run until green): `.github/copilot/scripts/macos/gateway.sh swift-test` · the governor's
`xcodebuild` of the "OmniTrain Watch App" scheme (the app target is the only place the new wiring is
compiled; no agent runs it) · `.github/copilot/scripts/macos/gateway.sh lint` (no Dart changed, so the 196
baseline stands).

**Predicted Files**: `watch/watchos/Sources/WatchSessionEngine/WatchPhonePreferences.swift` ·
`watch/watchos/Sources/WatchSessionEngine/WatchRestPing.swift` (new) ·
`watch/watchos/Sources/WatchSessionEngine/WatchLoggingModel.swift` ·
`watch/watchos/Sources/WatchSessionEngine/WatchLoggingView.swift` ·
`watch/watchos/Sources/WatchSessionEngine/WatchRestView.swift` ·
`ios/OmniTrain Watch App/ContentView.swift` ·
`watch/watchos/Tests/WatchSessionEngineTests/Fixtures.swift` ·
`watch/watchos/Tests/WatchSessionEngineTests/WatchRestPingTests.swift` (new)

### Phase 3 → moved to plan 22b

The Wear mirror, the Settings copy, the rule text, the three docs and the series index, the contract test's
reword and the index row are now plan 22b's single phase, item for item with its Done Criteria and
Predicted Files:
`docs/plans/2026-10-08-22b-rest-ping-wear-settings-docs-plan/2026-10-08-22b-rest-ping-wear-settings-docs-plan.md`

## Files Affected

- **Sync contract** (Phase 1): the schema, one valid fixture, three invalid fixtures, the manifest,
  `PROTOCOL.md`, and the new `watch/contract/watch_rest_ping_contract.json`. Both validators are unchanged
  — the schema is data to them.
- **Phone** (Phase 1): `watch_reference_sync.dart`, `watch_sync_request_handler.dart` and the two test
  files that assert the payload's exact shape. `SettingsState`, `rest_ping_utils.dart` and the settings
  screen's interval rows are *readers only* — no change.
- **Watch client** (Phase 2): the preferences record and store, the new rule type, the haptic protocol and
  its two implementations, the rest view, the app target's one wiring line, and the Swift tests.
- **Moved to plan 22b** with Phase 3: the Dart mirror (the new Dart rule, the unit preferences, the haptic
  protocol and `SystemWatchHaptics`, the rest screen and the Dart tests) and the docs (the convention row,
  three feature docs, `watch_surface.md` — remove before adding — and the series index).
- **Dependents that only read a touched surface** (expected untouched — the reviewer re-runs their tests):
  `test/settings_state_test.dart`, `test/watch_capture_contract_conformance_test.dart`,
  `WatchLoggingTimersTests.swift`, `WatchSessionStartPathsTests.swift` (beyond its payload builders), and
  every `RestNotificationService` caller on the phone. The Dart mirror's dependents
  (`test/watch_rest_surface_test.dart`, `test/watch_logging_stepping_test.dart`,
  `test/watch_sensor_recording_test.dart`) are plan 22b's.

## Notes

- **Dependency graph**: Phase 1 → Phase 2. Plan 22b needs only Phase 1 (its Dart rule is table-driven, not
  Swift-driven), so 22b may land between Phase 1 and Phase 2: it brings the Wear half and the docs without
  waiting on the watch app target's `xcodebuild`, at the cost of a tree where the two wrist clients briefly
  disagree. Plan 22b's Notes carry that re-ordering.
- **Predicted intermediate states.** After Phase 1 the wire carries the interval and no device consumes it
  yet: the phone's behaviour is unchanged (it already pings from the setting) and the wrist ignores the
  field. That is shippable. After Phase 2 the Apple Watch pings and the Wear mirror does not; plan 22b
  closes the feature.
- **Legacy handling.** A `WatchPreferencesRecord` written before this change has no `restPingSeconds` and
  reads 0 (Off) — no migration, no backfill (D-242). Nothing on the phone's storage changes: the key
  `rest_ping_interval` already exists.
- **Untouched by design**: `scripts/sqlite_schema.sql` / `scripts/sqlite_seed.sql` and
  `lib/data/models/models.dart` (no model change, so `test/db_seed_test.dart` needs nothing), both
  `WorkoutRepository` implementations, and `WatchTimerHaptics` on both clients.
- **No new dependency, no codegen, no generated file.**

## Progress

One line per item. Implementers append their result; the reviewer appends the evidence row.

- Phase 1.1 schema — `[x]` required + `properties` (`integer`, `minimum: 0`) · 1.2 fixtures + manifest — `[x]`
  valid `restPingSeconds: 90` + `scenario: S-246`, three invalid fixtures, each refused as stated on both
  stacks · 1.3 PROTOCOL.md — `[x]` row + notes bullet · 1.4 `buildPreferencesDown` — `[x]` payload key and id
  suffix · 1.5 `_sendRoutines` — `[x]` passes `_settings.restPingInterval` · 1.6 contract table — `[x]` 8 rows
  for the seven scenarios · 1.7 phone conformance + wire tests — `[x]` `test/rest_ping_contract_test.dart`,
  8 tests · 1.8 payload fallout — `[x]` Dart (`watch_reference_sync_test.dart`, `watch_transport_test.dart`)
  and the Swift `preferencesDown` helper. **Phase 1: Complete** — lint 196/0 errors, the five suites 157
  passed, the full suite 4163 passed/0 failed, swift-test 359/0. Evidence: `.evidence.md`.
- Phase 2.1 record field — `[x]` `restPingSeconds: Int` (default 0) in the fields, `init`, `withSequence`
  and `toJson`; `fromJson` reads an absent key as 0 · 2.2 store + `applyPreferencesDown` — `[x]`
  `restPingSeconds` accessor (0 when nothing has synced) and the payload field guarded by `wholeSeconds`
  (absent, boolean, `90.0` and negative all refused) · 2.3 `WatchRestPing` — `[x]` D-243/D-250's rule, with
  `lastPinged` kept per `recordId` · 2.4 haptic protocol + recording stub — `[x]` `playRestPing()` and the
  `restPings` counter; `WatchTimerHaptics.poll` untouched · 2.5 `WristHaptics` — `[x]` `.click` for the ping,
  `.notification` kept for milestones · 2.6 view tick + app wiring — `[x]` `restPingSeconds: () -> Int` read
  on each tick inside the existing `TimelineView`; ContentView passes
  `host.preferences.restPingSeconds` · 2.7 Swift tests — `[x]` `WatchRestPingTests`, 17 tests over
  S-221–S-225, S-241–S-245 and S-247, read from the contract; every guard proved by mutation.
  **Phase 2: Complete** — lint 196/0 errors, swift-test 376 passed/0 failed (+17 on the 359 baseline),
  invariant grep clean; the app target still needs the governor's `xcodebuild`. Evidence: `.evidence.md`.
- Phase 3 (8 items) — **moved to plan 22b**; its Progress lines live there.

## Assumption Log

Executors append here (decision, options considered, choice and why — 3 lines at most) and continue; the
Conductor marks each RATIFIED (promoted to a D-x) or REVERT (a remediation item).

- (Conductor, derived — RATIFIED as D-250, vetoable under Open question 1) D-243's last consequence, read
  against its own formula, is ambiguous for a boundary that fell before the interval arrived. Options: read
  the sentence as "never" (adds state the Ledger does not describe) or read the formula as the contract.
  Chose the formula, with the sentence governing a boundary already pinged.
- (Conductor, derived — RATIFIED as D-253, asserted by S-250) The scanner's safety was checked against the
  regexes, not assumed: `_restLengthSpelling` needs "rest" adjacent to "seconds", so `restPingSeconds` is
  safe and a comment saying "rest seconds" is a finding. Plan 22b's phase item 8 adds both directions as
  assertions.
- (Developer, Phase 1 — RATIFY OR REVERT) The shared Swift test helper `preferencesDown` now sends
  `restPingSeconds` (default 0), and nothing on the wrist reads it yet: `WatchPhonePreferences` and
  `SyncProtocolValidator` stay untouched because Phase 2 owns that file. Options: add the read here
  (unplanned scope in a file Phase 2 rewrites) or ship the field wire-only, which the Notes call shippable.
- (Developer, Phase 1 — RATIFY OR REVERT) The table's boundary rule and the phone's `shouldFireRestPing`
  agree only where a row polls every multiple of its interval, so the phone test asserts the full tap list
  for S-241, S-221 and S-223 and table integrity for S-243 and S-222's second row. Rewriting the phone's rule
  to the boundary form instead would contradict D-250, which this phase must not change.
- (Developer, Phase 2 — RATIFY OR REVERT) The rule's `boundary > 0` clause is behaviourally redundant: the
  live clause is `boundary > lastPinged` and `lastPinged` starts at 0, so a zero boundary was never reachable
  (mutation M3, `> 0` → `>= 0`, stays green). Kept because D-243/D-250 state it; recorded as an equivalent
  mutant in the evidence instead of being claimed as a proved guard.
- (Developer, Phase 2 — RATIFY OR REVERT) The contract file carries no malformed register, and S-247's drawn
  set (absent, negative, string, boolean) missed a JSON `90.0`, so dropping `!CFNumberIsFloatType` survived in
  a first run — F-10 refuses `90.0` on the phone, so the wrist must too. The float payload was added inline
  in the test (no new fixture file) and that mutant is now red.

## Feedback

Review 1 (code-reviewer) — the code is behaviourally correct and fully covered; see
`2026-10-08-22-rest-ping-on-watch-plan.review.md` for the eight findings and the fix checklist. Only
finding 1 blocks: `docs/theme_and_settings.md:9` still asserts the wrist owes no alert for a rest, which
this PR makes false. Delete that clause in this PR (or advance 22b's item 6 for that file), then findings 5,
6, 7 and 8 are one-liners in files already open; findings 2, 3 and 4 stay with 22b. Do not expand the
plan — the split stands.

## Open questions

(The planner appends here. Governor's defaults, none needing the owner: the wrist's ping is a haptic tap with
no sound; a changed interval reaches the wrist at its next sync; the wrist does not ping before its first
sync.)

1. **D-243's last consequence against its own formula** (kept as seeded; derived reading ratified as
   D-250). "A boundary that fell before the interval arrived … never fires immediately for an
   already-passed boundary" (`2026-10-08-22-rest-ping-on-watch-plan.md`, seeded Ledger, D-243) contradicts
   its own rule `boundary > 0 && boundary > lastPinged`, which fires for any boundary above the last one
   pinged. **Default: the formula governs; the sentence describes S-244's case, a boundary already
   pinged.** S-222 pins both readings. Vetoable before Phase 2's first handoff — it changes what the wrist
   does when the interval lands mid-rest.
2. **D-243 keys `lastPinged` per rest row; the phone keys it per exercise.** D-243 says "keyed on the rest
   row's `recordId`", but the phone's map is `Map<String, int> _lastRestPingFiredAt` keyed by `effortId`
   (`lib/features/session/workout_session_screen.dart:176`, read at
   `lib/features/session/workout_session_global_timer.dart:52,58`) and cleared at each rest boundary
   (`workout_session_screen.dart:782`, `workout_session_timer_mixin.dart:512,597`). The observable result
   is the same, and the seeded entry stands. **Default: the wrist keys per `recordId`; the phone keeps its
   map and is never rewritten** (D-243, invariant "the phone's ping function is not rewritten"). No action
   needed unless the owner wants the phone's map renamed — that would be a different PR.
3. **`docs/state_management/watch_surface.md` is ≈50.9 KB against the 51.2 KB warning band** (≈0.3 KB of
   room; the hard fail is 64 KiB — `test/docs_indexing_contract_test.dart`). **Default: plan 22b's phase
   item 7
   removes stale prose from the same section before adding the ping paragraph, and reports the file's size
   before and after.** If no stale prose can be removed without losing current information, the paragraph
   moves to `docs/rest_tracking.md` and the fact is raised under `## Feedback` — not a blocker, and the
   governor may prefer a part-page split.
4. **The watch app target's build.** `ios/OmniTrain Watch App/ContentView.swift` is compiled by no gateway
   check (`swift-test` builds the package only). **Default: the governor runs `xcodebuild` for the
   "OmniTrain Watch App" scheme after Phase 2**; Phase 2's Done Criteria name it as a governor check. If the
   governor would rather not, say so and Phase 2 closes on `swift-test` plus the reviewer's read of the one
   changed line.
5. **The phone's OS-level rest notifications are not extended.** `RestNotificationService.scheduleRestPings`
   (`workout_session_timer_mixin.dart:383,417`, `workout_session_screen.dart:347,881`) fires pings while the
   app is backgrounded; the wrist has no equivalent and this plan adds none (D-248 sends it to 19c). Not a
   question for the owner, recorded so the reviewer does not read it as a gap.
6. **(The split — decided, 2026-10-08.)** The governor's scope check counted two or more soft signals and
   moved Phase 3 whole to plan 22b; what moved and where is in `## Split` above. The measurement caveat
   stands: `ls` and `wc` are denied by policy, so every size in this plan comes from `view` output and the
   docs contract test's bands, and the governor measures both plans against
   `.github/copilot/pr-scope-budget.md`.
