# Feature: the rest ping — Wear mirror, Settings wording, the rule and the docs (22b)

> Status: Iteration 1 active — written from plan 22's Phase 3, which the governor's scope check moved here
> whole on 2026-10-08 (see plan 22's `## Split`)
> Next handoff: @developer (Phase 1)
> Binding conventions: `docs/global_conventions.md` (+ `docs/rest_tracking.md`, `docs/theme_and_settings.md`,
> `docs/watch_session_sync.md`, `docs/state_management/watch_surface.md`, `docs/documentation_standard.md`, by path)
> Follows: plan 22 — `docs/plans/2026-10-08-22-rest-ping-on-watch-plan/2026-10-08-22-rest-ping-on-watch-plan.md`
> (Phases 1–2). Its D-ids are cited **by path** below; the Ledger here (D-260…D-269) re-anchors them for this
> PR and nothing from its Ledger is restated. Scenario ids are its register's, never renumbered.
> Depends on: plan 22 **Phase 1 only** — the Dart mirror reads `watch/contract/watch_rest_ping_contract.json`,
> which Phase 1 item 6 creates, and the pings follow the rule its D-243/D-250 fix. Phase 2 (Apple Watch) is
> not a prerequisite, so this PR may land between plan 22's two phases.
> Part of the 18 series — index: `docs/plans/2026-10-08-18-watch-qa-index.md`
> Evidence: `2026-10-08-22b-rest-ping-wear-settings-docs-plan.evidence.md` · Review: `2026-10-08-22b-rest-ping-wear-settings-docs-plan.review.md`

## Overview

Plan 22 ships the rest ping on the phone and the Apple Watch (its Phases 1–2). This PR closes the feature:

- **The Wear OS Dart logging surface pings too**, from the same setting, at the same seconds as the Swift
  client and the phone — the same rule (plan 22 D-243, D-250), read from the same table
  (`watch/contract/watch_rest_ping_contract.json`, plan 22 D-246), never from a second copy of the numbers.
- **The Settings screen says which device each row reaches**: Rest Ping reaches the phone *and* the watch;
  Rest Ping Sound stays phone-only, because the wrist's ping is a haptic tap and plays no sound.
- **The rule and the docs are true again**: the convention row allows the rest ping as the one rest cue
  while still denying a rest length, a countdown and an end-of-rest alarm, and the contract test still fails
  if any of the three comes back.
- The phone's behaviour, both `WorkoutRepository` implementations and the phone's own ping function are
  **untouched** (plan 22 D-243, D-248).

### Acceptance criteria

1. The Dart `WatchRestPing` reports the table's tap seconds for every contract case — the Dart half of plan
   22's D-246 "one test per consumer" — and the phone's `shouldFireRestPing` and the Swift type already do
   (plan 22 Phase 2).
2. The interval reaches the Dart mirror through the same route as the unit preferences
   (`WatchUnitPreferences.fromSettings(SettingsState)`), so no screen reads `SettingsState` itself
   (plan 22 D-245).
3. The Dart rest screen's ping is its own haptic call, separate from any timer milestone, and the screen's
   exercise / elapsed / Next shape is unchanged (plan 22 D-251, D-252).
4. The Settings screen's two subtitles name the devices; labels, order and the picker dialog are unchanged
   (plan 22 D-241), so the existing taps keep working.
5. `docs/global_conventions.md`, `docs/rest_tracking.md`, `docs/theme_and_settings.md`,
   `docs/watch_session_sync.md` and `docs/state_management/watch_surface.md` say: no rest length, no
   countdown, no end-of-rest alarm; the rest ping is the one allowed cue (plan 22 D-240, D-247).
6. `test/rest_is_count_up_contract_test.dart` still fails on a stored rest length, a planned rest or a
   countdown, and no longer claims "no rest alarm anywhere"; its new allowance is narrow enough that
   `restPingSeconds`, `rest_ping_interval` and `playRestPing()` are not findings (plan 22 D-253).
7. The series index carries the 22 and 22b rows, and its recorded baselines are not rewritten.
8. Suites green with the baselines: `lint` at the 196-issue / 0-error baseline, the targeted suites in the
   phase's Done Criteria, the full `flutter test`, and `swift-test` unchanged (no Swift here).

## Resolved Decisions (Ledger)

New entries, numbered after plan 22's D-253. Each re-anchors a decision that lives in plan 22 (by path) for
this PR; none of them may be read as changing it.

**D-260 — What this plan owns.** Plan 22's D-245 (the Dart mirror), D-247 (the docs and the contract test)
and D-253's scanner half bind here, read at
`docs/plans/2026-10-08-22-rest-ping-on-watch-plan/2026-10-08-22-rest-ping-on-watch-plan.md`. Plan 22's D-240
(the rule), D-241 (one owner for the setting), D-243 (the ping formula), D-246 (the shared table), D-248
(out of scope), D-249 (no double ping), D-250 (the interval arriving mid-rest) and D-252 (the wrist
surface's shape) bind this plan unchanged.

**D-261 — The Dart mirror is the same rule, not a second implementation.** `WatchRestPing` is a pure Dart
type with no Flutter import, implementing D-243 exactly: per rest, `boundary = (elapsed ~/ interval) *
interval`, fire iff `boundary > 0 && boundary > lastPinged`, then `lastPinged = boundary`; `interval == 0`
never fires; the state is keyed on the rest row, so a new rest starts clean. Parity with the Swift type and
with the phone's `shouldFireRestPing` is proven by reading
`watch/contract/watch_rest_ping_contract.json` (D-246, created in plan 22 Phase 1 item 6) — never by
restating the numbers in this plan, in the test, or in a comment.

**D-262 — The Settings copy.** The "Rest Ping" row's subtitle says the interval reaches the phone **and**
the watch; the "Rest Ping Sound" row's says phone only (D-241). The row labels, their order, the values and
the picker dialog's title do not change, so `find.text('Rest Ping')` keeps opening the picker and the tests
that read the row's value keep passing.

**D-263 — The rule text.** The `docs/global_conventions.md` row "Rest rule: rest is a count-up" keeps its
name and denials and gains one allowance: the rest ping, a repeating nudge at each multiple of the interval
while a rest is open, on the device that holds the rest — a haptic tap and no sound on a wrist (D-240). The
same wording lands in `docs/rest_tracking.md` (the ping paragraph ≈15), `docs/theme_and_settings.md:9`, and
`docs/watch_session_sync.md` (the rest paragraph ≈588). Each added line carries a denial word on it or on
the line before it, or the scanner flags it (D-253).

**D-264 — The scanner and its allowance.** The contract test's denial prose names the ping as the allowed
cue instead of claiming "no rest alarm anywhere", and the scanner's allowance stays narrow. New S-250
assertions: `const restPingSeconds = 30;`, `rest_ping_interval` and `playRestPing()` yield no finding, while
a stored rest length, a planned rest and a countdown still do. The scanner keeps its roots and its two
regexes (`test/rest_is_count_up_contract_test.dart:65` `_restLengthSpelling`, `:52` `_restCountdownWording`);
`watch/contract/**` and `test/**` stay outside its roots, so the table and its tests are unscanned.

**D-265 — The route for the interval.** It arrives with the preferences, exactly as the units do:
`WatchUnitPreferences` gains `restPingSeconds` (default 0) and `WatchUnitPreferences.fromSettings(
SettingsState)` fills it from `settings.restPingInterval` (`lib/watch/logging/watch_metric_stepping.dart:45`).
No screen reaches for `SettingsState` directly, and this plan adds no second reader of the setting on the
phone.

**D-266 — The index.** The series index gets a row for 22 and a row for 22b — the scope split turned the one
planned row into two. The index's recorded baselines (4061 tests, 335 swift) stay as history; the current
baselines live in each plan's evidence file.

**D-267 — The dependency is on plan 22 Phase 1.** This PR reads the contract table and follows the rule,
both of which plan 22 Phase 1 lands. If Phase 1 has not landed, this PR is blocked until it does —
sequencing, not a two-step merge: Phase 1 is shippable alone (plan 22's Notes) and nothing here changes it.
Plan 22 Phase 2 is not required.

**D-268 — Out of scope here, stated so it stays out** (inherits plan 22 D-248): a sound on the wrist; a wrist
notification while the app is suspended (19c); the wrist rest reaching the phone's rest history (18c); the
vestigial routine "Rest duration" field; any new setting on the watch; the phone's OS-level rest
notifications (they stay the phone's).

**D-269 — Nothing else moves.** `SettingsState`, `rest_ping_utils.dart`, both `WorkoutRepository`
implementations, the phone's `RestNotificationService` and the Dart timer haptics (`WatchTimerHaptics`) are
readers of the touched surfaces, not changes: the phone's ping function is not rewritten (plan 22 D-243's
invariant) and the Dart rest screen's shape is unchanged apart from the ping (D-252's rule, mobile half).

## Feature Invariants

- **One owner for the choice.** No second setting, no watch-side edit path; the wrist holds only the last
  copy the phone sent, and on the phone the Dart mirror simply reads the setting (D-241, D-265).
- **Parity, by table.** Dart `WatchRestPing`, the Swift type and the phone's `shouldFireRestPing` report the
  same tap seconds for the same contract case, and each proves it by reading
  `watch/contract/watch_rest_ping_contract.json` (D-243, D-246, D-261).
- **The rest rule survives.** No stored rest length, no planned rest, no countdown, no end-of-rest alarm;
  the ping is the one allowed cue and the contract test still fails on the other three (D-263, D-264).
- **The phone's ping function is not rewritten** (`lib/core/utils/rest_ping_utils.dart`) — agreement by
  fixture, never by refactor (plan 22 D-243).
- **A closed rest never pings** (plan 22 D-249); on the Dart surface the rule is not consulted at all once
  the rest is closed.

## Requirements

- **R-1** `lib/watch/logging/watch_rest_ping.dart` implements the rule of D-261 in pure Dart and is tested
  against the contract table (S-241–S-245).
- **R-2** `WatchUnitPreferences.restPingSeconds` (default 0) is filled from the setting by
  `fromSettings` (D-265, S-242's Off case).
- **R-3** The Dart rest screen taps through a `WatchHaptics.playRestPing()` of its own, in the existing
  one-second tick, and records exactly the pings the rule owes (S-226, D-251).
- **R-4** The Settings subtitles name phone and watch / phone only, with labels and values unchanged
  (S-249, D-262).
- **R-5** The rule, the four docs and the contract test name the ping as the one allowed rest cue and still
  fail on a rest length, a countdown or an alarm (S-250, D-263, D-264).
- **R-6** The series index carries the 22 and 22b rows without rewriting its recorded baselines (D-266).
- **R-7** Nothing outside the Predicted Files changes, and no Dart mirror behaviour exists beyond R-1–R-3
  (D-269).

## Scenarios

Ids belong to plan 22's register and are never renumbered; the text below is this PR's (Dart, copy and rule)
half of each, with the fixture it must run on. The Swift and phone halves live in plan 22, by path.

### S-241: the table, one-second polls — Dart half
- Fixture: contract case `interval 30, polls 0…100`, `beforeFirstSync` 0; one open rest whose row id is
  stable across the polls.
- Trigger: the Dart rule asked once per poll second, `lastPinged` carried between polls.
- Flow: polls 0…100 at one-second steps.
- Expected outcome: taps at 30, 60, 90 and nowhere else — the same seconds the Swift type and the phone's
  `shouldFireRestPing` produce.
- Edge case of: none.
- Red without the change: no Dart `WatchRestPing` exists, so `test/watch_rest_ping_test.dart` does not
  compile.

### S-242: Off and unknown — Dart half
- Fixture: case `interval 0, polls 0…600`; and a `WatchUnitPreferences` built from a `SettingsState` whose
  `restPingInterval` is 0.
- Trigger: the rule asked on every poll.
- Expected outcome: no tap, ever; `fromSettings` reports 0.
- Edge case of: S-241. Red: no rule and no field.

### S-243: gap catch-up fires once — Dart half
- Fixture: case `interval 60`, polls at 0, 59, 200, 201, 240.
- Expected outcome: one tap at poll 200 (not three for the missed multiples) and one at 240.
- Edge case of: S-241. Red: no rule.

### S-244: interval change mid-rest — Dart half
- Fixture: case `interval 60` then `interval 30`: poll at 70 (tapped at 60), the interval becomes 30, poll
  again at 70.
- Expected outcome: no tap on the second 70; the next tap is at 90.
- Edge case of: S-241. Red: no rule.

### S-245: a rest ends, the next starts clean — Dart half
- Fixture: `interval 30`: rest A (row A) polled to 65 (taps 30, 60), the rest closed and Next tapped; rest
  B, a new row, polled to 35.
- Expected outcome: B taps at 30; a closed rest is never evaluated.
- Edge case of: S-241. Red: no per-row state.

### S-249: the Settings screen says it
- Fixture: the settings screen built as `test/settings_sounds_test.dart` already builds it (`makeSettings()`,
  Mock-first, no real `Future.delayed`, no Hive).
- Trigger: open Settings.
- Flow: read both subtitles; tap `find.text('Rest Ping')`; read the row's value.
- Expected outcome: Rest Ping's subtitle names the phone and the watch; Rest Ping Sound's says phone only;
  the tap still opens the picker; the row's label and value are unchanged.
- Edge case of: none. Red: today's copy says nothing about devices.

### S-250: the rule still bites
- Fixture: the contract test's denial fixture (`test/rest_is_count_up_contract_test.dart:360`) and the new
  identifiers.
- Trigger: run the scanner over its roots.
- Expected outcome: a stored rest length, a planned rest and a rest countdown are still findings;
  `const restPingSeconds = 30;`, `rest_ping_interval` and `playRestPing()` are not; the reworded prose names
  the ping as the allowed cue and still denies a countdown.
- Edge case of: none — this is the negative guard the PR must not weaken. Red: the old text and the old
  scanner allowance.

### S-221: the same second is pinged once — Dart half
- Fixture: `interval 30`, polls at 30, 30, 30 (a redraw, a resume and a tick landing inside one elapsed
  second).
- Expected outcome: exactly one tap.
- Edge case of: S-241. Red: no rule.

### S-222: the interval arrives mid-rest — Dart half
- Fixture: interval 0 until `fromSettings` returns 30 at elapsed 20; polls 0…100. Variant: the interval
  arrives at elapsed 35.
- Expected outcome: taps at 30, 60, 90; in the variant one tap on the next poll (boundary 30) and then 60
  and 90 — the formula of plan 22 D-243 governs, per its D-250.
- Edge case of: S-241. Red: no rule.

### S-223: a large interval fires only at its own multiple — Dart half
- Fixture: `interval 180` (the top of the phone's option list), polls 0…200.
- Expected outcome: one tap, at 180.
- Edge case of: S-241. Red: no rule.

### S-224: a closed rest is never evaluated — Dart half
- Fixture: `interval 30`, tap at 30, Next at 40, polls at 60, 90, 120.
- Expected outcome: no tap; the elapsed getter is nil once the rest is closed, so the rule is not consulted.
- Edge case of: S-241. Red: no rule.

### S-226: the Dart mirror's ping is its own tap (new, planner)
- Fixture: interval 30, polls 0…100; the rest screen built with the recording haptics stub
  (`_RecordingHaptics`, `test/watch_logging_surfaces_test.dart:81`).
- Trigger: drive the screen's one-second tick.
- Flow: count the `playRestPing()` calls; drive the Dart timer haptics over the same rest.
- Expected outcome: exactly three pings; the timer haptics record none for a rest; the screen still shows
  exercise, elapsed and Next.
- Edge case of: S-225 (plan 22's Swift guard) — this is its Dart counterpart. Red: `WatchHaptics` has no
  `playRestPing()`.

## Existing-Functionality Impact

These rows moved here with plan 22's Phase 3; each carries the grep that found the readers. An entry may not
read "unaffected" without one.

| Touched surface | What already reads it (the grep) | Effect of the change | Guarded by |
|---|---|---|---|
| `WatchHaptics` gains a method (Dart) | `grep -rn WatchHaptics lib/ test/` → `SystemWatchHaptics` (`lib/watch/logging/watch_logging_screen.dart:36`), `WatchLoggingScreen.haptics` (`:49`), `_RecordingHaptics` (`test/watch_logging_surfaces_test.dart:81`) | a new protocol requirement breaks every Dart conformer, so all three move with it; the Swift conformers are plan 22 Phase 2's | S-226, Phase 1 item 3 |
| `WatchRestScreen` gains a parameter | `grep -rn "WatchRestScreen(" lib/ test/` → `test/watch_rest_surface_test.dart:163`, the only other construction site | defaulted, so that test keeps compiling; no shape change | S-226, Phase 1 item 4 |
| `WatchUnitPreferences` gains a field | `grep -rn WatchUnitPreferences lib/ test/` → `watch_logging_state.dart:125,164`, `lib/watch/debug/watch_logging_debug_main.dart:130`, `watch_metric_stepping.dart:86,116`, `test/watch_logging_stepping_test.dart:112,195`, `test/watch_logging_surfaces_test.dart:153,319`, `test/watch_sensor_recording_test.dart:930` | a defaulted const field is source-compatible: no call site changes (the Swift twin with the same name is plan 22 Phase 2's) | Phase 1 item 2 |
| `settings_screen.dart` Rest Ping / Rest Ping Sound subtitles | `grep -rn "Rest Ping" test/ lib/features/settings/` → `test/settings_sounds_test.dart:173,199,230` tap `find.text('Rest Ping')`; `:64,84` read the row's value; `settings_screen.dart:384,396,614` | the labels stay, so the taps keep working; only the two subtitles change | S-249 |
| The rest contract test's scanner and its roots | `test/rest_is_count_up_contract_test.dart:65` `_restLengthSpelling`, `:52` `_restCountdownWording`, `:360` the denial fixture, `:34` `restRuleRoots` (six code roots — `lib/watch`, `lib/state/watch`, `lib/core/sync_protocol`, `watch/watchos/Sources`, `watch/sync_protocol/schemas`, `ios/OmniTrain Watch App` — and eight documents) | the new identifiers must not read as a stored rest length, and the reworded prose must still deny a countdown; `watch/contract/**` and `test/**` are not roots, so the new table and its tests are unscanned | S-250, D-264 |
| `docs/state_management/watch_surface.md` | `test/docs_indexing_contract_test.dart` (`_maxDocBytes` 64 KiB, warning band at 80% ≈ 51.2 KiB) | ≈50.9 KB today against a 51.2 KB band: **remove before adding** | Phase 1 item 7 |
| `docs/plans/2026-10-08-18-watch-qa-index.md` | the series index's PR table, its standing constraints and the baselines it records | two rows, 22 and 22b; the index's older baselines (4061 tests, 335 swift) stay as history | Phase 1 item 8 |
| `lib/watch/logging/watch_rest_screen.dart`'s tick | `grep -rn "Timer.periodic" lib/watch/logging/` → `watch_rest_screen.dart` and `watch_logging_screen.dart` | the rest screen's tick already runs every second; the ping is asked there, no new timer | S-226, D-269 |

## Iteration 1

One phase: the moved Phase 3 of plan 22, item for item — the Dart mirror, the Settings copy, the rule, the
docs and the index. It reads one table (plan 22's) and touches one track pair (`lib/watch/` and `docs/`),
which is why the split left it whole. Tracks: the phone app's watch surface (`lib/watch/`) and docs; no
Swift, no wire, no model.

### Phase 1: Wear mirror, Settings copy, rule and docs (@developer)

1. [ ] `lib/watch/logging/watch_rest_ping.dart` (new) · `WatchRestPing`, the rule of D-261 (plan 22 D-243,
   D-250), pure Dart, no Flutter import, `lastPinged` per rest row; and `test/watch_rest_ping_test.dart`
   (new), which reads `watch/contract/watch_rest_ping_contract.json` and asserts the tap seconds for
   S-241–S-245, S-221, S-222, S-223 — the Dart half of D-246's "one test per consumer". The test names its
   S-ids.
2. [ ] `lib/watch/logging/watch_metric_stepping.dart` · `WatchUnitPreferences` (≈45) gains
   `restPingSeconds` (default 0) and `WatchUnitPreferences.fromSettings(SettingsState)` (≈53) fills it from
   `settings.restPingInterval` — the route D-265 names, so no screen reaches for `SettingsState` directly.
3. [ ] `lib/watch/logging/watch_logging_screen.dart` · `WatchHaptics` (≈30) gains `playRestPing()` and
   `SystemWatchHaptics` (≈36) implements it with the `HapticFeedback.mediumImpact()` it already uses; add
   the method to `_RecordingHaptics` in `test/watch_logging_surfaces_test.dart:81` so it keeps conforming.
4. [ ] `lib/watch/logging/watch_rest_screen.dart` · `_WatchRestScreenState`: hold the rule, add the
   `haptics` parameter defaulted to `const SystemWatchHaptics()` (as `WatchLoggingScreen` has), read the
   interval from the surface it already holds — `state.units.restPingSeconds`
   (`lib/watch/logging/watch_logging_state.dart:164`, filled by item 2, so no screen reads
   `SettingsState`) — and ask the rule in the existing 1-second `Timer.periodic` tick (`:48`), tapping when
   a ping is owed. `WatchRestScreen` keeps its exercise / elapsed / Next shape, and
   `test/watch_rest_surface_test.dart:163` keeps compiling on the default. Then S-226 in
   `test/watch_logging_surfaces_test.dart`: three pings from the stub, none from the timer haptics, the three
   labels still present.
5. [ ] `lib/features/settings/settings_screen.dart` · the "Rest Ping" row (≈384) and the "Rest Ping Sound"
   row (≈396): subtitles that say the interval reaches phone **and** watch, and that the sound is
   phone-only (D-262). Labels and the picker dialog title (≈614) do not change. Then the S-249 widget test
   in `test/settings_sounds_test.dart` (Mock-first, no real `Future.delayed`, `makeSettings()` as the file
   already builds it) asserting both subtitles and that `find.text('Rest Ping')` still opens the picker.
6. [ ] `docs/global_conventions.md:17` · the "Rest rule: rest is a count-up" row: keep the row's name and
   its denials, and add the one allowance — the rest ping, a repeating nudge at each multiple of the
   interval while a rest is open, on the device that holds the rest, a haptic tap and no sound on the
   wrist (D-263). Same wording in `docs/rest_tracking.md` (the ping paragraph ≈15),
   `docs/theme_and_settings.md:9` (the bullet that says the wrist owes no alert for a rest at all) and
   `docs/watch_session_sync.md` (the rest paragraph ≈588). Each of these lines must carry a denial word on
   the line or the line before it, or the scanner flags it (D-264).
7. [ ] `docs/state_management/watch_surface.md`: **remove before adding.** State the file's size before and
   after; the new prose is a short paragraph in the wrist-rest section naming the ping, its interval's
   route and the fact that it is silent. If removing stale prose would lose current information, stop and
   raise it under `## Feedback` rather than pushing the file past the band.
8. [ ] `test/rest_is_count_up_contract_test.dart`: reword the denial fixture at `:360` (`restRuleWhere`,
   `:19`) so it names the allowance instead of claiming "no rest alarm anywhere", and add the S-250
   assertions — `const restPingSeconds = 30;`, `rest_ping_interval` and `playRestPing()` yield no finding,
   while the S-166 red cases (stored rest length, planned rest, countdown) still do. Then the 22 and 22b rows in
   `docs/plans/2026-10-08-18-watch-qa-index.md` (D-266), and the residue sweep: grep for any remaining
   reader of a rest *length* on the wrist, and for any doc still calling the ping an alarm.

**Done Criteria** (run until green): `.github/copilot/scripts/macos/gateway.sh lint` (196 baseline, 0
errors) · `.github/copilot/scripts/macos/gateway.sh test test/watch_rest_ping_test.dart
test/watch_rest_surface_test.dart test/watch_logging_surfaces_test.dart test/watch_logging_stepping_test.dart
test/settings_sounds_test.dart test/rest_is_count_up_contract_test.dart test/docs_indexing_contract_test.dart`
· the full `.github/copilot/scripts/macos/gateway.sh test` (900 s; the final phase always runs it) ·
`.github/copilot/scripts/macos/gateway.sh swift-test` (unchanged: no Swift here).

**Predicted Files**: `lib/watch/logging/watch_rest_ping.dart` (new) ·
`lib/watch/logging/watch_metric_stepping.dart` · `lib/watch/logging/watch_logging_screen.dart` ·
`lib/watch/logging/watch_rest_screen.dart` · `test/watch_rest_ping_test.dart` (new) ·
`test/watch_logging_surfaces_test.dart` · `lib/features/settings/settings_screen.dart` ·
`test/settings_sounds_test.dart` · `docs/global_conventions.md` · `docs/rest_tracking.md` ·
`docs/theme_and_settings.md` · `docs/watch_session_sync.md` · `docs/state_management/watch_surface.md` ·
`test/rest_is_count_up_contract_test.dart` · `docs/plans/2026-10-08-18-watch-qa-index.md`

## Files Affected

- **Watch client, Dart mirror** (Phase 1): the new Dart rule, the unit preferences, the haptic protocol and
  `SystemWatchHaptics`, the rest screen, and the Dart tests.
- **Settings** (Phase 1): the two subtitles of `settings_screen.dart` and their widget test. The labels, the
  values (`SettingsState`) and the picker are *readers only* — no change.
- **Docs** (Phase 1): the convention row, three feature docs, `watch_surface.md` (remove before adding) and
  the series index.
- **Dependents that only read a touched surface** (expected untouched — the reviewer re-runs their tests):
  `test/watch_rest_surface_test.dart`, `test/watch_logging_stepping_test.dart`,
  `test/watch_sensor_recording_test.dart`, `test/settings_state_test.dart`, and
  `test/watch_logging_consumer_test.dart`-style callers of the logging screen if any exist. Nothing on the
  phone app's own session path changes.

## Notes

- **Dependency graph**: plan 22 Phase 1 → this phase → (plan 22 Phase 2). This phase needs only Phase 1 (the
  contract table and the rule it fixes), so running it *before* plan 22's Phase 2 is a legal re-ordering: it
  lands the Wear half and the docs without waiting on the watch app target's `xcodebuild`, at the cost of a
  tree where the two wrist clients briefly disagree about pinging. Phase 1 here must be rebased onto plan
  22's Phase 1 if that has not landed (D-267).
- **Predicted intermediate state**: after this phase the Dart mirror pings and the docs are true; if plan 22
  Phase 2 has not run yet, the Apple Watch does not ping and the Settings screen says it does — the one
  window the re-ordering opens, and the reason plan 22's own Notes expect the normal order.
- **Legacy handling**: none. The Dart mirror reads the phone's own setting; no stored field is added, so
  there is nothing to migrate (contrast plan 22 D-242's wrist tolerance, which is Phase 2's).
- **Untouched by design**: `scripts/sqlite_schema.sql` / `scripts/sqlite_seed.sql` and
  `lib/data/models/models.dart`; both `WorkoutRepository` implementations; `rest_ping_utils.dart`; the
  phone's `RestNotificationService`; `watch_timer_haptics.dart` on both clients; the sync contract.
- **No new dependency, no codegen, no generated file.**
- The phase is at the 8-item cap on purpose: it is plan 22's Phase 3, moved whole rather than re-cut, so the
  split adds no scope and no second design.

## Progress

One line per item. Implementers append their result; the reviewer appends the evidence row.

- 1.1 Dart rule + test — `[ ]` · 1.2 unit preferences — `[ ]` · 1.3 haptic protocol +
  `SystemWatchHaptics` + stub — `[ ]` · 1.4 rest screen tick + S-226 — `[ ]` · 1.5 Settings subtitles +
  S-249 — `[ ]` · 1.6 convention row + three docs — `[ ]` · 1.7 `watch_surface.md` — `[ ]` · 1.8 scanner +
  index rows + residue sweep — `[ ]`

## Assumption Log

Executors append here (decision, options considered, choice and why — 3 lines at most) and continue; the
Conductor marks each RATIFIED (promoted to a D-x) or REVERT (a remediation item).

- (Conductor, this iteration) The split moved plan 22's Phase 3 whole rather than re-cutting it, so no
  decision here is new: the Ledger above re-anchors plan 22's D-243/D-245/D-247/D-251/D-253 by path. Options:
  restate them (drift risk) or cite them (this plan). Chose citation, with S-226 added as the one gap the
  move exposed — D-251's Dart half had no guard of its own.

## Feedback

[empty — fold into a new Iteration block when non-empty, then clear]

## Open questions

(The planner appends here. Governor's defaults, none needing the owner: the wrist's ping is a haptic tap with
no sound; the plan 22b row is added to the series index beside the 22 row.)

1. **The series index gets two rows, not one.** Plan 22's Phase 3 item 8 carried "the 22 row"; the split
   makes the series two PRs, so item 8 here adds the 22 and 22b rows together. **Default: two rows**, since
   the index exists to order the series and a PR without a row disappears from it. Vetoable: the governor
   may prefer one row for the pair.
2. **This PR may land between plan 22's two phases** (D-267, plan 22's Notes). The only cost is the window
   where Settings says the watch pings and the Apple Watch does not. **Default: keep the re-ordering
   available**; if the governor wants one tree at a time, this PR simply waits for plan 22's Phase 2.
3. **`docs/state_management/watch_surface.md` is ≈50.9 KB against the 51.2 KB warning band** (hard fail
   64 KiB — `test/docs_indexing_contract_test.dart`). **Default: item 7 removes stale prose from the same
   section before adding the ping paragraph and reports the size before and after**; if nothing stale can
   go, the paragraph moves to `docs/rest_tracking.md` and the fact is raised under `## Feedback`. Size
   claims here come from `view` output and the contract test's bands — `wc` is denied by policy.
4. **S-226 is new and has no counterpart in plan 22's register.** It guards D-251's Dart half (the ping is
   its own haptic entry point, not a timer milestone). **Default: keep it**, since without it the Dart half
   of D-251 is unproven; if the governor prefers the register untouched, the same assertions can ride inside
   S-241's Dart test.
