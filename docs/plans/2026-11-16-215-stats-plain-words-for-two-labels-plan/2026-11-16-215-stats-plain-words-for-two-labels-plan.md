# Plan 215 — Plain words for two Stats labels

Series: Stats pre-launch review group E (item 9, the jargon half, of memory `stats-prelaunch-review-2026-11-12`; index `docs/plans/2026-11-13-157-stats-what-counts-series.md`). The review named two phrases a user cannot read without knowing the code's vocabulary: the Mix legend's `In this window` and the Progression card's `Resistance progression rate`. Wording only, no behaviour: one builder run, then docs. Status: BUILT, reviewed (APPROVE), uncommitted.

## Goal and acceptance

Replace the two phrases with plain ones. The numbers, the card's conditions and everything else stay.

Acceptance: S-21501 and S-21502 green (they are the three existing tests that pinned the old strings, now pinning the new ones, so each is red at the base commit); the rest of `mix_layer_screen_test`, `progression_rate_test` and `progression_rate_signal_screen_test` green and unchanged; `flutter analyze` at baseline (181, 0 errors); full suite no new red.

## What the user sees

- Mix legend (load measure only, where a second `Your usual` bar draws): the first bar's label `In this window` becomes `Recent`. The second label `Your usual` is unchanged.
- Progression card, before: `Resistance progression rate is 80% over the last 4 weeks, up from 65%.` After: `In the last 4 weeks, 80% of your lifting sessions matched or beat your previous one for that lift, up from 65% before.` The suggestion line (`The current approach is working.`) is unchanged.
- To SEE it: the legend needs the load measure (at least 4 rated weeks); the card needs the Progression signal to qualify (a rate of at least 75% over the last 4 weeks, 10 points above the weeks before).
- Unchanged: every other word on Stats, including `Est. 1RM`, `Best set`, `Your usual`, the explainer sentences and the other nine cards.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-1 | `mix_layer.dart:251`: the first bar's label text `In this window` becomes `Recent`. The key `mix_window_bar_label` and every other label stay. | `mix_layer.dart:248-255`, `test/mix_layer_screen_test.dart:2423` |
| D-2 | `progressionRateCopy` (`lib/core/models/progression_rate.dart:244-252`) builds the observation `In the last 4 weeks, ${rate.recentPercent}% of your lifting sessions matched or beat your previous one for that lift, up from ${rate.priorPercent}% before.` It states what the number is (a progression is a session that matches or beats the exercise's previous one, `progression_rate.dart:178-184`), where the old text called it a "progression rate". The two percentages are the same two values. | `progression_rate.dart:178-184`, `docs/signals_registered.md:112` |
| D-3 | Nothing else changes: the legend's existence rule, the suggestion, the card's qualification, the other signals' copy. | scope |
| D-4 | The wording is the lead's default (the owner said to proceed and explain defaults); each phrase lives in one place. | scope |

## Scenarios

| ID | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-21501 | `test/mix_layer_screen_test.dart:2423` (the load-measure screen with a usual bar): the label above the window bar. | The text under `Key('mix_window_bar_label')` is `Recent`, above the bar; `Your usual` is still below it. | the label reads `In this window` |
| S-21502 | `test/progression_rate_test.dart:419` (the pure copy for 80% and 65%) and `test/progression_rate_signal_screen_test.dart:41` (the card on screen). | The observation is exactly `In the last 4 weeks, 80% of your lifting sessions matched or beat your previous one for that lift, up from 65% before.`; the suggestion is unchanged. | the observation reads `Resistance progression rate is 80% over...` |

## Input-reality checklist

1. Writers and units: none stored; both strings are built at render time from the two whole-number percentages.
2. Lifecycle, settings, time: none.
3. Cost: none.
4. Words: see above. The sentence is one line of plain words at 400 dp and at a larger text scale (the card wraps; the Progression card has no line cap, checked in P1 by the screen test at the file's own width).
5. Slot competition: `Recent` appears only in the Mix legend; `grep -rn "'Recent'" lib/features/stats` before the change finds no other label of that exact text.

## Phases

1. **P1 builder-app, scope `lib/features/stats/widgets/mix_layer.dart`, `lib/core/models/progression_rate.dart`, `test/mix_layer_screen_test.dart`, `test/progression_rate_test.dart`, `test/progression_rate_signal_screen_test.dart`:** the two exact string edits below and the three existing tests' expected strings (rename the mix test to start with `S-21501` and the two progression expectations' reasons to mention `S-21502`). Report FIRST as a skeleton. No full suite.
2. **P2 lead:** docs, mutation pass, `crew-reviewer`, full suite.

## Readers (existing tests that pin the old strings)

`test/mix_layer_screen_test.dart:2423-2429`, `test/progression_rate_test.dart:419`, `test/progression_rate_signal_screen_test.dart:41` are the three that pin them; they change in P1 by design. A fourth, `test/progression_samples_service_test.dart:400` (S-1811, `contains('over the last 4 weeks')`), was found only by the full suite and was updated by the lead; the first reader grep had searched the old sentence's opening words, not its tail. A red anywhere else is reported, not edited.

## Mutation list (lead)

(a) the Mix label back to `In this window`; (b) the observation back to the old sentence; (c) the observation swaps the two percentages; (d) the label `Recent` also applied to the second bar.

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| `docs/stats_screen.md` | MODIFIED | `In this window` and the second `Your usual` | `Recent` and the second `Your usual` | S-21501 |
| `docs/widget_catalog.md` | MODIFIED | the usual bar with its `In this window` / `Your usual` labels | the usual bar with its `Recent` / `Your usual` labels | S-21501 |
| `docs/signals_registered.md` | ADDED | - | In the last 4 weeks, N% of your lifting sessions matched or beat your previous one for that lift | S-21502 |

Stale-term sweep (`grep -rIn "In this window\|Resistance progression" docs`, minus plans/history/releases): the two MODIFIED rows above; no other doc names either phrase.

## Open items

1. The other half of item 9, findability (Stats in the swipe-up sheet, Records & Trends behind an unlabeled icon): a layout call, not in this plan. The icon has a tooltip and a screen-reader label; it has no visible text.
2. Other labels a new user may not know (`Est. 1RM`, `Best pace`, the signal cards' own jargon such as "cardio efficiency drift") are not changed here.
3. The review noted that the rate counts one unit per exercise in a session, so "your lifting sessions" is a slight simplification; "lift sessions" is the one-word alternative. (owner) Read the two new phrases on a device and say if you want different words.

## Predicted files

`mix_layer.dart` (1 line), `progression_rate.dart` (3 lines), three tests, three docs.

## Progress

- [x] Seeded (scout of every user-visible Stats string; the two the review named)
- [x] P1 build (2.3 min)
- [x] Docs, mutation pass (4 mutants, 4 killed)
- [x] Review: APPROVE (minor: "lifting sessions" counts exercise-sessions, Open item 3)
- [x] Full suite (+7784, 0 failures, after the 4th reader fix)

## Assumption Log

- 2026-11-16: base commit `d83ad529` on `claude_develop`; other sessions' `docs/plans/2026-11-15-208-fuel-burned-per-day-plan/` and `test/stats_gallery_render_test.dart` are outside this plan.
- 2026-11-16: scenario ids S-215xx; grep over `test`, `docs`, `lib`, `watch` found none.
- 2026-11-16: the new words are the lead's; the owner did not specify them.

## Feedback

(none yet)
