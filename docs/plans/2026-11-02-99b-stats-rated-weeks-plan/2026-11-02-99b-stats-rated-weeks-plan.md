# 99b — Rated weeks count the last 12 weeks, current ones included

Series: `docs/plans/2026-11-02-99-stats-four-week-view-series.md`. Builds on 99a (uncommitted in the tree; same files).
Status: SEEDED by the lead 2026-11-02. Base: HEAD 418c1ea4 plus the uncommitted 99a work. Phone only. Another session owns the watch/timer files.

## Goal and acceptance

What a user sees: the workouts they rate now count. "Of the last 12 weeks, how many have at least one rated workout" is counted
up to today, current week included. That one number drives (a) the Mix note "Showing time for now ... (N of 4 so far)", (b) whether the bar
shows effort (load) or time, and (c) whether Signals unlock ("Unlocks after 4 weeks of rating your workouts — N of 4 so far").
The "Your usual" comparison bar keeps its meaning: the 12 weeks before the window, which genuinely has to be the past.

## Decision Ledger

| Id | Decision | Where |
|---|---|---|
| D-17101 | "A week" is a 7-day block anchored at the payload's end day, not the calendar week or the start-of-week setting (as the baseline blocks already are, D-935). 12 blocks tile `[endDay − 83 days, endDay + 1 day)`; block 11 is `[endDay − 6, endDay]` | new helper beside `baselineBlockStarts`, `training_load.dart:147` |
| D-17102 | New `List<DateTime> ratedWeekBlockStarts(DateTime endDay)` returns the 12 starts oldest first, built with `DateTime(y, m, d - 83 + 7 * i)` (never a Duration) | `training_load.dart` |
| D-17103 | `MixLayerData.ratedBaselineWeeks` is renamed `ratedWeeks` and now holds that count. `sustained_high_load.dart` has its own unrelated `ratedBaselineWeeks`: untouched | `training_load.dart:105`, readers below |
| D-17104 | `_mixPayload` counts rated weeks from the sessions with `sessionFeeling != null` whose start falls in `[starts.first, endDay + 1 day)`, where `endDay = localMidnightDay(toMs)`. The measure gate (`ratedWeeks >= kTrainingLoadMinRatedWeeks && unrated share <= max`) reads it. The baseline sums for the usual bar stay as they are; the old per-block rated set is deleted | `stats_progress_service.dart:~725,754-760,777-783` |
| D-17105 | Same rule for `computeMixPeriod` (anchored at the period's end day), so the two period signals gate their measure the same way as the layer. The empty-window payload from 99a carries the new count | same |
| D-17106 | `signalsGateMet` and `signalsLockedLine` read `ratedWeeks`; no copy change | `signals.dart:70-85` |
| D-17107 | Consequence, accepted: the load measure can now show while the baseline holds no rated work; the usual bar then simply does not draw (already handled: `baselineTotal > 0`) | `stats_progress_service.dart:~793` |

Readers of the renamed field: `stats_progress_service.dart` (~L777-797), `signals.dart:73`, `stats_screen.dart:320`, `mix_layer.dart:84,193`; tests construct or read it in
`cardio_efficiency_drift_signal_screen_test`, `mix_layer_screen_test`, `mix_layer_service_test`, `modality_mix_period_service_test`, `modality_mix_shift_signal_screen_test` (comment),
`nutrition_series_service_test`, `signals_framework_test`, `signals_layer_screen_test`, `signals_service_test`, `training_load_test` (check), plus docs.

## Scenarios (fixtures re-derived with python; `now` = 2026-11-02, endDay Nov 2, first block starts Aug 11)

Block of a day `d` days back = `11 - floor(d / 7)` for `d <= 83`: d 0 and 3 → 11; 8 → 10; 15 → 9; 22 → 8; 29 → 7; 83 → 0; 84 → outside.

| Id | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-17101 | Rated 60 min sessions 0, 8, 15, 22 days back, `computeMixLayer(window: statsWindow(now), now)` | `ratedWeeks` 4; `measure` load | old count looked only before Oct 6: 0, time |
| S-17102 | Rated sessions 0 and 3 days back (same block 11) | `ratedWeeks` 1 | two sessions in one block count once |
| S-17103 | Sessions 0, 8, 15, 22 days back, the 8-day one UNRATED | `ratedWeeks` 3 | an unrated session must not count |
| S-17104 | Rated sessions 83 and 84 days back | `ratedWeeks` 1 (only the 83 one, block 0) | 84 days back is outside the 12 blocks |
| S-17105 | `computeMixPeriod(from 2026-09-01, to 2026-09-28 23:59:59.999)` with rated sessions 2026-09-28, 2026-09-18, 2026-09-08, 2026-07-20 (d 0, 10, 20, 70 from Sep 28) | `ratedWeeks` 4, measure load | anchor is the period end, not "today" and not the period start |
| S-17106 | Pure: `signalsGateMet` with `ratedWeeks` 4 true, 3 false; `signalsLockedLine(2)` reads `Unlocks after 4 weeks of rating your workouts — 2 of 4 so far.` | as stated | existing framework tests renamed |
| S-17107 | Screen: rated sessions today and 8 days back only | locked Signals line reads `2 of 4 so far`; Mix note reads `(2 of 4 so far)` | old count was 0 |
| S-17108 | Screen: rated sessions 0, 8, 15, 22 days back, nothing older | no `mix_baseline_note`; no `mix_usual_bar`; no exception; the Signals layer (not the locked line) renders | gate met by current weeks; D-17107 |
| S-17109 | The usual bar still describes the 12 blocks before the window start (existing `mix_layer_service_test` baseline cases, adapted so their rated baseline weeks sit within 84 days of today only where they must) | existing assertions on `baselineSegments` unchanged | guards that the baseline sums did not move |


## Phases

| Phase | Agent | Write scope | Items | Order |
|---|---|---|---|---|
| P1 | crew-builder-app | `lib/core/models/training_load.dart`, `lib/core/models/signals.dart`, `lib/core/services/stats_progress_service.dart`, `lib/features/stats/stats_screen.dart`, `lib/features/stats/widgets/mix_layer.dart`, new `test/stats_rated_weeks_service_test.dart` | helper, rename, `_mixPayload`, readers, S-17101..S-17105 | first |
| P2a | crew-builder-app | the test files that construct/read the field (list above) | mechanical rename `ratedBaselineWeeks` → `ratedWeeks` only (not `sustained_high_load*`) | after P1 |
| P2b/c | crew-builder-app x2 | disjoint test files named by the red run | fixture dates so rated sessions sit where the test needs them under the new count | parallel, after P2a |
| P3 | crew-builder-app | new `test/stats_rated_weeks_screen_test.dart` | S-17107, S-17108 | after P2 |
| P4 | crew-docs-keeper | `docs/stats_screen.md`, `docs/signals.md` and the docs a grep names | the rated-week rule, the three consumers | after P3 |

Done: touched tests green; lint not above 181; full suite shows no new failures against today's list (the 9 date-sensitive ones belong to the DST task and S-R3 to routine save);
lead mutations: anchor day, block width, the `sessionFeeling != null` filter, the 83/84 boundary, the period anchor; review, one fix round at most.

## Progress
- [x] P1
- [x] P2a
- [x] P2b/c
- [x] P3
- [x] P4
- [x] prove
- [ ] review

## Feedback
Review: `2026-11-02-99b-stats-rated-weeks-plan.review.md` (1 blocker, 1 major, 4 minor, all fixed in two closed rounds).
- [x] F1 stale measure-gate bullets in `docs/state_management/services_and_utils.md` and the `navigation_and_screens.md` gloss; also `training_load.md` "window is rated enough".
- [x] F2 S-1904b fixture: the day-10 session is unrated again so the signal's period measures time.
- [x] F3-F5 comment fixes (S-17105 block numbers, S-4013 helper name, doubled word).
- Open (owner): when four or more weeks are rated but more than 25% of the window's time is unrated, the Mix shows time with neither the "N of 4" note nor the locked line (pre-existing shape).
