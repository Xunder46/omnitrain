# Plan 214 — Stats says why effort is locked when Effort Rating is off

Series: Stats pre-launch review group E (item 7, the "never says why" half, of memory `stats-prelaunch-review-2026-11-12`; index `docs/plans/2026-11-13-157-stats-what-counts-series.md`). Phone only (`lib/core/models/signals.dart`, three Stats widgets, `stats_screen.dart`), one builder run for the code, one for the screen tests, then docs. Status: BUILT, reviewed (APPROVE WITH FIXES, fixed), uncommitted.

## Goal and acceptance

With Effort Rating switched off (Settings, Workout, `SettingsState.showFeelingSurvey` false) no workout ever gets an effort, so the Signals layer stays locked and the Mix strip stays on time, but the copy keeps saying "Unlocks after 4 weeks of rating your workouts — 0 of 4 so far" and "Effort appears once 4 weeks are rated" as if the user were just early. After this change, while Effort Rating is off and the gate is unmet, those lines say the setting is the reason.

Acceptance: S-21401..S-21405 green, the ones marked "fails without" red at the base commit; the existing locked-line, hint and Mix-note tests (`signals_layer_screen_test`, `progression_rate_signal_screen_test`, `mix_layer_screen_test`, `stats_rated_weeks_screen_test`) green and unchanged; `flutter analyze` at baseline (181, 0 errors); full suite no new red.

## What the user sees

- Effort Rating ON (the default): nothing changes.
- Effort Rating OFF, fewer than 4 rated weeks:
  - Locked Signals line: `Effort Rating is off in Settings, so signals that need it stay locked — N of 4 weeks rated so far.`
  - Line under a card that needs no ratings: `Effort Rating is off in Settings, so more signals stay locked — N of 4 weeks rated so far.`
  - Mix note under the time strip: `Showing time for now. Effort Rating is off in Settings (N of 4 weeks rated).`
- Effort Rating OFF but 4 or more rated weeks already: nothing changes (the signals are unlocked; the Mix note's other variant, "Effort needs most of the last 4 weeks rated", is left as it is).
- Flipping the switch while Stats is open updates the lines at once (the screen already repaints on any setting change; no reload).
- To SEE it: Settings, Workout, switch Effort Rating off; open Stats on a history with fewer than 4 rated weeks.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-1 | `signalsLockedLine(int ratedWeeks, {bool ratingOff = false})` and `signalsMoreLine(int ratedWeeks, {bool ratingOff = false})` (`lib/core/models/signals.dart:91`, `:101`) return the off copy above when `ratingOff` is true. The default keeps every existing call and test as is. The count is clamped as today. | existing tests `signals_layer_screen_test.dart:752`, `:809`, `:1326` |
| D-2 | `SignalsLockedSection` and `SignalsLayerSection` (`signals_layer.dart:53`, `:97`) take `bool ratingOff = false` and pass it to those two functions. They stay presentation-only. | file header, D-4001 |
| D-3 | `MixLayerSection` (`mix_layer.dart`) takes `bool ratingOff = false`; in the baseline note, the `layer.ratedWeeks < kTrainingLoadMinRatedWeeks` branch reads the off copy when `ratingOff`; the other branch and the load measure are unchanged. | `mix_layer.dart:190-205` |
| D-4 | `StatsScreen` passes `ratingOff: !widget.settingsState.showFeelingSurvey` to the three widgets, read inside the existing `ListenableBuilder` build, so a setting change repaints without a reload. No load, service or model change. | `stats_screen.dart:296-300` |
| D-5 | No change to the gate, the Mix measure, the waiting lines, the wrist or any stored value. | scope |

## Scenarios

All on `StatsScreen` over Mock (a widget test body runs under FakeAsync) unless said; one completed session with no rating so the gate is unmet and the Mix strip is on time. Finders: `Key('signals_locked_line')`, `Key('signals_locked_hint')`, `Key('mix_baseline_note')`.

| ID | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-21401 | Pure: `signalsLockedLine(2, ratingOff: true)` and `signalsMoreLine(2, ratingOff: true)`; and the defaults. | The two off strings above with N = 2; clamped (`signalsLockedLine(9, ratingOff: true)` reads `4 of 4`, `signalsLockedLine(-3, ratingOff: true)` reads `0 of 4`); the default calls equal today's strings. | the parameter does not exist |
| S-21402 | Effort Rating off; no signals injected (`signals: const []`). | the locked line text is the off copy with `0 of 4`; control (Effort Rating on): the existing `signalsLockedLine(0)`. | the line reads "Unlocks after 4 weeks of rating your workouts" |
| S-21403 | Effort Rating off; a stub signal that needs no ratings and shows a card (copy `_StubSignal` of `signals_layer_screen_test.dart`, line ~752's setup). | the hint under the card is the off copy; control (on): `signalsMoreLine(0)`. | the hint reads "More signals unlock after..." |
| S-21404 | Effort Rating off; the Mix strip shows time with `ratedWeeks` 0. | `mix_baseline_note` reads `Showing time for now. Effort Rating is off in Settings (0 of 4 weeks rated).`; control (on): `Showing time for now. Effort appears once 4 weeks are rated (0 of 4 so far).` | the note reads "Effort appears once 4 weeks are rated" |
| S-21405 | Effort Rating off, screen open; then `settingsState.setShowFeelingSurvey(true)` inside `tester.runAsync`, pumped. | the locked line returns to `signalsLockedLine(0)` and the Mix note to the default, with no second load (the screen does not reload on this setting). | passes the "no reload" half with and without the change on purpose (it pins D-4's no-reload); the text half fails without it |

## Input-reality checklist

1. Writers and units: the setting is written by the Settings switch (and travels to the wrist as `effortRatingPrompt`); no stored value changes.
2. Lifecycle: the copy follows the setting live, per build.
3. Settings changing while open: S-21405.
4. Time: none.
5. Cost: none (a bool passed to three widgets).
6. Words: the three strings above; plain, no jargon, the setting named as Settings shows it (`Effort Rating`, `lib/features/settings/settings_screen.dart:869`).
7. Slot competition: these are the only three places that say "rated" to a user with the gate unmet; the Mix note's second variant and the waiting lines are unchanged (Open items).

## Phases

1. **P1 builder-app, scope `lib/core/models/signals.dart`, `lib/features/stats/widgets/signals_layer.dart`, `lib/features/stats/widgets/mix_layer.dart`, `lib/features/stats/stats_screen.dart`, `test/stats_effort_rating_off_copy_test.dart` (new):** the exact production code in the brief and S-21401 (pure, plain `test()`). Report FIRST as a skeleton. No full suite.
2. **P2 builder-app, scope `test/stats_effort_rating_off_screen_test.dart` (new):** S-21402..S-21405 (Mock). Separate run because a screen-test file has design latitude.
3. **P3 lead:** docs, mutation pass, `crew-reviewer`, full suite.

## Readers (existing tests that pin the old rule)

`test/signals_layer_screen_test.dart` (`S-4002`, `S-4013`, `S-17505`, `S-17507`), `test/progression_rate_signal_screen_test.dart:402`, `test/mix_layer_screen_test.dart` (`S-3204`), `test/stats_rated_weeks_screen_test.dart`. They run with Effort Rating on (the default), so none should change. A red is reported, not edited.

## Mutation list (lead)

(a) the screen passes `ratingOff: false` always; (b) `ratingOff` inverted; (c) the Mix branch tests the wrong `ratedWeeks` branch (off copy in the "needs most of the last 4 weeks" variant); (d) `signalsMoreLine` ignores `ratingOff`; (e) the count unclamped in the off copy.

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| `docs/signals.md` | ADDED | - | Effort Rating is off in Settings | S-21401, S-21402 |
| `docs/stats_screen/signals_layer.md` | ADDED | - | Effort Rating is off in Settings | S-21402, S-21403 |
| `docs/stats_screen.md` | ADDED | - | Effort Rating is off in Settings | S-21404, S-21405 |
| `docs/stats_screen.md` | ADDED | - | `test/stats_effort_rating_off_screen_test.dart` | S-21404 |

Stale-term sweep (`grep -rIniE "Unlocks after|weeks of rating|appears once|so far\)" docs`, minus plans/history/releases): `signals.md:58`, `stats_screen/signals_layer.md:18-22`, `stats_screen.md:200-202` and `widget_catalog.md:30,35` (the two widget rows, which gained the `ratingOff` input after the review) (all stay true for Effort Rating on; the new sentences sit beside them).

## Open items

1. The other half of item 7 (a thin first month: every Instruments row reads "new", totals live on Records & Trends) is not in this plan.
2. The Mix note's second variant (4 or more rated weeks but most of the window unrated) and the waiting lines do not mention the setting; with the setting off and old ratings still inside the 12-week baseline those lines can still read as today.
3. `stats_primer_sheet.dart:105-108` (the Signals primer) still says other signals need about four weeks of rating without naming the setting; the review left it to the owner (the line under the cards now names it).
4. (owner) A device check: Settings, Workout, Effort Rating off, then open Stats with under 4 rated weeks.

## Predicted files

`signals.dart` (+14), `signals_layer.dart` (+8), `mix_layer.dart` (+10), `stats_screen.dart` (+3), two new test files, three docs.

## Progress

- [x] Seeded (scout of the locked line, the hint, the Mix note, the toggle)
- [x] P1 build (3.5 min)
- [x] P2 screen tests (4.2 min)
- [x] Docs, mutation pass (5 mutants, 5 killed)
- [x] Review: APPROVE WITH FIXES (major: widget catalog rows, fixed; minors fixed or listed)
- [x] Full suite (+7774, 0 failures)

## Assumption Log

- 2026-11-16: base commit from `git rev-parse HEAD` after plan 212; other sessions' `docs/plans/2026-11-15-208-fuel-burned-per-day-plan/` and `test/stats_gallery_render_test.dart` are outside this plan.
- 2026-11-16: scenario ids S-214xx; grep over `test`, `docs`, `lib`, `watch` found none.
- 2026-11-16: wording is mine (owner said to proceed and explain defaults); owner can change the three strings in one place.

## Feedback

(none yet)
