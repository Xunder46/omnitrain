# Plan 209 — Stats Instruments rows: getting faster reads as an improvement, and a trend line plots one thing

Series: Stats pre-launch review group C (items 4 and 6c of memory `stats-prelaunch-review-2026-11-12`; index `docs/plans/2026-11-13-157-stats-what-counts-series.md`, "Group C"). Owner decisions 2026-11-15: "faster = green up" and "use my defaults for the other rules". Phone only (`lib/features/stats`, `lib/core/services`), one builder run, then docs. Status: BUILT, reviewed (fix round 1 applied), verified, committed.

## Goal and acceptance

Two defects on the Stats Instruments rows (probed by reading the code; no probe run needed, both are single lines):

1. A run that got faster reads as a loss. The change chip shows the raw sign of the change of seconds-per-kilometre: 10 s faster is `↓ -0:10 /km` in red, 10 s slower is `↑ +0:10 /km` in green (`formatNativeChange`, `native_value_format.dart:117-128`; chip colour in `InstrumentChangeChip.build`, `instrument_row.dart:146-153`).
2. A cardio row's trend line mixes two measures. The row's figure is pace when any run in the window has a distance and total time otherwise (`_cardioValue`), but each day's point is computed by the same rule over that day alone, so a window with two runs with distance and one without draws pace (about 360) and total seconds (1200) on one line (`computeExerciseMetrics`, `stats_progress_service.dart:1126-1134`). The model's own comment already promises "a day that yields no value for the exercise's metric contributes no point" (`exercise_metric.dart:97-98`).

After this change: for pace only, the arrow and colour mean better or worse. Faster reads green `↑ 0:10 /km`, slower reads red `↓ 0:10 /km` (no plus or minus sign: the arrow says it). Every other metric is unchanged (`↑ +3 reps`, `↓ -1:30`). A row's trend line plots only the days that yield the same metric as the row's figure.

Acceptance: S-21001..S-21007 green, those marked "fails without" red at the base commit; `test/instrument_change_format_test.dart` pace test updated to the new reading; `flutter analyze` at baseline; the docs-indexing and ui-standards contract tests green; full suite no new red.

## What the user sees

- Before: a faster run shows a red down arrow; a mixed-measure run row shows a trend line that jumps between two unrelated scales.
- After: faster is green up, slower red down, same size and place; the trend line shows pace days only (or total-time days only), never both. A cardio row whose pace days number fewer than two draws no trend line, as any row with fewer than two points does today.
- To SEE it: log two runs with a distance a week apart where the second is quicker, and one run with no distance between them; open Stats.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-1 | New `double nativeChangeGain(NativeMetric metric, double delta)` in `native_value_format.dart`: `metric == NativeMetric.pace ? -delta : delta`. Positive means better. | owner 2026-11-15 |
| D-2 | `formatNativeChange` for pace: `delta == 0` still `—`; otherwise arrow `↑` when `nativeChangeGain(...) > 0` else `↓`, then the magnitude of `delta.abs()` with no sign. Every other metric keeps arrow and sign from the raw delta. | owner 2026-11-15 |
| D-3 | `InstrumentRowTile` passes the chip `delta: delta == null ? null : nativeChangeGain(best.metric, delta)`. The chip's logic (positive primary colour, negative error colour, zero or null muted) is unchanged; its field doc says the value is a gain. | `InstrumentChangeChip` |
| D-4 | (Revised after review 2026-11-16: the first build dropped the days inside `computeExerciseMetrics`, which also shrank Exercise Progress's RECENT SESSIONS list and the two `points.length` sort keys, `stats_progress_service.dart:1316` and `records_and_trends_screen.dart:231`.) The service keeps one point per training day. New getter `ExerciseMetricSummary.trendPoints` = `points.where((p) => p.value.metric == best.metric)`, in `exercise_metric.dart`. The two drawings read it: the Instruments row's sparkline (`instrument_row.dart`) and Exercise Progress's TREND card and chart (`exercise_progress_screen.dart:139` and `:213`, which already labels its axis by `summary.best.metric`). RECENT SESSIONS and both sorts keep `points`. | review finding 1 |
| D-5 | The comparison with the previous window is already gated on equal metrics (`stats_progress_service.dart:1301`); unchanged. Resistance, isometric and sports rows have one metric per exercise, so D-4 changes nothing for them (S-21007 pins it). | S-21007 |
| D-7 | `ExerciseMetricSummary.points`'s doc comment is corrected: one point per training day, each in whatever metric that day reads; `trendPoints` is the single-metric series a drawing plots. | review finding 1 |
| D-6 | No wrist change, no data change, no wording other than the arrow reading. | scope |

## Scenarios

| ID | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-21001 | `formatNativeChange(NativeMetric.pace, -30, km)`; `(pace, 30, km)`; `(pace, -30, miles)`; `(pace, 0, km)`. | `'↑ 0:30 /km'`; `'↓ 0:30 /km'`; `'↑ 0:48 /mi'`; `'—'`. | the old text is `'↓ -0:30 /km'` and `'↑ +0:30 /km'` |
| S-21002 | `formatNativeChange` for reps 3 / -3, estimated 1RM 5, hold 15, duration -90, rounds 2, round minutes -3. | exactly the existing strings (`'↑ +3 reps'`, `'↓ -3 reps'`, `'↑ +5 kg'`, `'↑ +0:15'`, `'↓ -1:30'`, `'↑ +2 rounds'`, `'↓ -3 min'`). | passes with and without the change on purpose: only pace moves (mutation: apply the pace branch to every metric) |
| S-21003 | `nativeChangeGain` for pace -30, pace 30, reps 3, duration -90. | `30.0`, `-30.0`, `3.0`, `-90.0`. | the function does not exist (compile error) |
| S-21004 | Widget: `InstrumentRowTile` with a pace row, best 350 s/km, previous 360 s/km; read the chip text and its colour. | `'↑ 0:10 /km'`, colour the theme's primary. | `'↓ -0:10 /km'` in the error colour |
| S-21005 | Same tile, best 370, previous 360. | `'↓ 0:10 /km'`, colour the theme's error colour at alpha 0.8. | `'↑ +0:10 /km'` in the primary colour |
| S-21006 | Service, Mock and Hive: one Cardio exercise, three days in the window: day A one finished 1800 s run with a 5000 m distance row (pace 360), day B one finished 1200 s run with no distance, day C one finished 1750 s run with 5000 m (pace 350). `computeExerciseMetrics` over the window. | `best` is pace 350.0; `points` still hold all three days (A pace 360.0, B duration 1200.0, C pace 350.0); `trendPoints` hold two days (A and C), metric pace, values 360.0 and 350.0. | `trendPoints` does not exist (compile error); with a guard in the service instead, `points` would hold two days |
| S-21007 | Service, Mock and Hive: a Resistance exercise with a logged set on three days, and a Cardio exercise with no distance on three days. | for each, `trendPoints` has 3 points and equals `points`. | passes with and without the change on purpose: D-4 drops nothing where one metric applies (mutation: `trendPoints` drops a point when the value is below the best) |
| S-21008 | Widget: the S-21004 tile built from the S-21006 summary (three `points`, two of them pace); find the `InstrumentSparkline` in the tile. | its `points` has two entries, both pace. | the sparkline receives `summary.points` with three entries |
| S-21009 | Widget or source guard on `ExerciseProgressScreen` for the S-21006 summary (use the harness `test/records_and_trends_screen_test.dart` or `test/instrument_list_screen_test.dart` already has; if none builds the screen cheaply, a source-text guard that the chart reads `trendPoints` and the recent list reads `points`). | RECENT SESSIONS lists three entries; the chart is built from the two pace points. | RECENT SESSIONS keeps three (passes both ways by design, the guard against the first build's regression); the chart plots three points |

## Input-reality checklist

1. Writers and units: pace is stored as seconds per kilometre; the display unit is the setting (`km` or `mi`), the conversion is `formatNativeMetric`'s own, so the new text reuses it.
2. Lifecycle: nothing is stored; both changes are computed on read.
3. Settings: the preferred distance unit changes the displayed number only; S-21001 covers both units. A settings change while Stats is open rebuilds the row with the new unit as today.
4. Time edges: a window whose only distance run is one day draws no trend line (fewer than two points) while the figure still reads pace; this is the intended result of D-4.
5. Cost: no new reads.
6. Words: only the arrow reading (D-2); the new text has no sign. Docs delta below.
7. Slot competition: the chip and trend line are read by the Stats Instruments list only; Records & Trends and Exercise Progress do not use them (plan 211 touches Records & Trends separately).

## Phases

1. **P1 builder-app, scope `lib/features/stats/widgets/native_value_format.dart`, `lib/features/stats/widgets/instrument_row.dart`, `lib/core/services/stats_progress_service.dart`, `test/instrument_change_format_test.dart`, `test/stats_pace_reads_honestly_test.dart`:** (1) the exact production code below; (2) in `test/instrument_change_format_test.dart` change the existing pace test (`a pace reads per the preferred distance unit`) to the new reading (the delta 30 is now `'↓ 0:30 /km'` and `'↓ 0:48 /mi'`) and add S-21001..S-21003; (3) new `test/stats_pace_reads_honestly_test.dart` with S-21004..S-21009 (S-21004/5 use plain `testWidgets` with a pre-built `InstrumentRow`; S-21006/7 are plain `test()` over `harnessFactories`; copy the distance-seeding helper at `test/instrument_list_service_test.dart:143`). Report FIRST as a skeleton. Done: the two test files green on both stores, plus `test/instrument_list_screen_test.dart` and `test/stats_instruments_horizon_screen_test.dart`; no full suite.
2. **P2 lead:** docs (below), mutation pass, `crew-reviewer`, full suite.

Exact production code (P1).

`native_value_format.dart`: replace the body of `formatNativeChange` and add the helper after it:

```dart
String formatNativeChange(
  NativeMetric metric,
  double delta,
  SettingsState settings,
) {
  if (delta == 0) return '—';
  final arrow = nativeChangeGain(metric, delta) > 0 ? '↑' : '↓';
  if (metric == NativeMetric.pace) {
    return '$arrow ${formatNativeMetric(metric, delta.abs(), settings)}';
  }
  final sign = delta > 0 ? '+' : '-';
  return '$arrow $sign${formatNativeMetric(metric, delta.abs(), settings)}';
}

/// The change as a gain: positive when the exercise improved. Pace is stored as
/// seconds per kilometre, so a smaller figure is better (plan 209); every other
/// metric improves when it grows.
double nativeChangeGain(NativeMetric metric, double delta) =>
    metric == NativeMetric.pace ? -delta : delta;
```

with the doc comment of `formatNativeChange` rewritten to say: the sign and arrow follow the raw change for every metric but pace; for pace the arrow says better (`↑`) or worse (`↓`) and the magnitude carries no sign.

`instrument_row.dart`, `InstrumentRowTile.build`, the chip call: `delta: delta == null ? null : nativeChangeGain(best.metric, delta),` and the `label:` line is unchanged (it still passes the raw `delta`). The `InstrumentChangeChip` doc comment and its `delta` field doc say it carries the gain: positive reads in the primary colour.

`stats_progress_service.dart` (`computeExerciseMetrics`), the per-day loop: `if (value == null) continue;` becomes `if (value == null || value.metric != best.metric) continue;`.

## Readers (existing tests that pin the old rule)

`test/instrument_change_format_test.dart` (the pace test pins `'↑ +0:30 /km'`; rewritten in P1). Others read the chip through `formatNativeChange` itself with a Resistance metric (`instrument_list_screen_test.dart:689`, `:1351`) or pin `new`/dash/arrow for non-pace rows (`stats_instruments_horizon_screen_test.dart:362-365`): unchanged. P1 runs both files; a red there is reported, not edited.

## Mutation list (lead)

(a) pace branch removed from `formatNativeChange` (the old text returns); (b) `nativeChangeGain` returns `delta` for pace; (c) the pace branch applied to every metric; (d) the tile passes the raw `delta` to the chip; (e) the per-day metric test removed; (f) the per-day test compares against a constant metric.

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| `docs/stats_screen.md` | MODIFIED | *slower* pace reads as an increase, because pace is stored as time per distance. | worse — a faster run reads a green | S-21001, S-21004, S-21005 |
| `docs/stats_screen.md` | ADDED | - | row's trend line plots only the days that read in the row's own metric | S-21006 |
| `docs/state_management/services_and_utils.md` | MODIFIED | the delta, with no per-metric inversion, and the magnitude is formatted by the | the delta for every metric but pace; for pace the arrow says better (`↑`, a | D-2 |

Stale-term sweep: `grep -rIn "slower pace\|slower\* pace\|raw numeric" docs` minus plans/history/releases: `stats_screen.md:333` and `services_and_utils.md:449-450` (the rows above); the `native_value_format.dart` doc comment and `instrument_row.dart` chip doc are rewritten in P1.

## Open items

1. (owner) Build go-ahead; nothing is built yet.
2. The wrist and Exercise Progress screens show no pace change chip; not touched.
3. The Instruments row's change is `new` when the previous window held a different metric; unchanged.

## Predicted files

`native_value_format.dart` (+10), `instrument_row.dart` (+4), `stats_progress_service.dart` (1 line), `test/instrument_change_format_test.dart` (pace test, +3 tests), new `test/stats_pace_reads_honestly_test.dart`, two docs.

## Progress

- [x] Seeded: code read, both defects located, numbers derived by hand (1800/5 = 360, 1750/5 = 350, 30 s per km = 48 s per mile)
- [x] P1 build (6 min, 90 tests green)
- [x] Docs, mutation pass (6/6 killed)
- [x] Review: APPROVE WITH FIXES (major: the service guard shrank Exercise Progress's recent list and two sort keys); fix round 1 moves the rule to `trendPoints` (D-4 revised, S-21008, S-21009)
- [x] Fix round 1, re-verify (mutation 10/10), full suite (+7723, 0 failures)
- [ ] (owner) See a faster run read green on a device

## Assumption Log

- 2026-11-15: base commit `4105405937965267e4236e823e457c8d06a9d99d` on `claude_develop`; the tree holds other sessions' uncommitted watch and docs work, none in this plan's scopes.
- 2026-11-15: scenario ids S-21001.. chosen after grep over `test`, `docs`, `lib`, `watch`, `ios` found no S-21xxx.
- 2026-11-15: with no sign on a pace change (owner example "↑ 0:10"), the unit suffix `/km` stays as the formatter writes it.

## Feedback

(none yet)
