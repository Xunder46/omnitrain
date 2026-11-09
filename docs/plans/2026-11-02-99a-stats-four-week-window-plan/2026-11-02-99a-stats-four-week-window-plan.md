# 99a — The Stats screen describes the last four weeks

Series: `docs/plans/2026-11-02-99-stats-four-week-view-series.md` (owner decisions O-1, O-2; D-17001, D-17002).
Status: SEEDED by the lead 2026-11-02. Base commit: see `.work/2026-11-02-99a-stats-four-week-window/base.txt` (HEAD 418c1ea4).
Track: phone only (`lib/`, `test/`, `docs/`). Another session owns the dirty watch/timer files; never touch them.

## Goal and acceptance

What a user sees after this PR:

1. Stats always describes the 28 days ending today. A training period no longer changes it; the "· Holds"-style chip is
   gone and both the Training Mix card and the first Instruments header read "· Last 4 weeks".
2. The Mix bar and legend are shares of those 28 days. The Instruments rows compare with the 28 days before.
3. After 4 weeks without training the Training Mix card shows header, chip and one line,
   "No training in the last 4 weeks. Last session: <date>." No bar, no strip, no Instruments. ALL TIME and Fuel stay.
4. Records & Trends is unchanged.

Not in this PR: rated-week counting (99b), Fuel (99c).

## Decision Ledger

| Id | Decision | Where |
|---|---|---|
| D-17001 | New `StatsProgressService.statsWindow({DateTime? now})`; `resolveWindow` and `computeProgressData` are untouched (Records & Trends reads them) | `stats_progress_service.dart` (`resolveWindow` ~L2332; R&T `records_and_trends_screen.dart:87`) |
| D-17002 | `StatsScreen._loadData` stops calling `computeProgressData` (only `.window` was read); uses one `now` for the window, the Mix layer and the signals | `stats_screen.dart:120-161` |
| D-17003 | `kStatsWindowDays = 28`; `fromMs = DateTime(y, m, d - 27)`, `toMs = DateTime(y, m, d, 23, 59, 59, 999)`, calendar arithmetic (DST), label `'Last 4 weeks'`, `isPeriodScoped: false`, `recentDays: null` | new, beside `kRecentTrainingDaysWindow` |
| D-17004 | `StatsWindowChip`, `InstrumentList._caption`, `previousRangeFor` and `StatsWindow.dayCount` are unchanged: "· Last 4 weeks" and "vs the 28 days before it" fall out of the new window | `window_chip.dart`, `instrument_list.dart:68`, `stats_progress_service.dart:1240` |
| D-17005 | `MixLayerData` gets `final bool windowIsEmpty` (constructor default `false`, so no existing caller changes). `computeMixLayer` passes `keepEmptyWindow: true` to `_mixPayload`; `computeMixPeriod` does not (the two signals still get null for an empty period) | `training_load.dart:93`, `stats_progress_service.dart:482,526,710` |
| D-17006 | In `_mixPayload`, when `windowTimeSeconds <= 0`: return null unless `keepEmptyWindow` AND no completed session started inside the window AND a completed session exists anywhere; then return the empty payload (below). A window with a zero-time session stays null, so the line never says "no training" next to a session inside the window | `stats_progress_service.dart:775` |
| D-17007 | The empty payload carries the real `ratedBaselineWeeks` and `lastSessionDay`, so the Signals gate and card for a user returning from a break behave as before | same |
| D-17008 | `MixLayerSection` renders the empty-window card when `layer.windowIsEmpty`; the line says `${window.dayCount ~/ 7}` weeks (no service import) | `mix_layer.dart:154` |

## Exact production code

`stats_progress_service.dart`, new members before `resolveWindow`:

```dart
  /// Calendar days the Stats screen describes: the four weeks ending today.
  static const int kStatsWindowDays = 28;

  /// The window every part of the Stats screen reads (D-17003): the
  /// [kStatsWindowDays] calendar days ending with the end of today. Periods
  /// play no part; they keep their meaning on the calendar and period screens.
  static StatsWindow statsWindow({DateTime? now}) {
    final today = now ?? DateTime.now();
    return StatsWindow(
      fromMs: DateTime(today.year, today.month, today.day - (kStatsWindowDays - 1)),
      toMs: DateTime(today.year, today.month, today.day, 23, 59, 59, 999),
      label: 'Last 4 weeks',
      isPeriodScoped: false,
    );
  }
```

`_mixPayload`: add `bool keepEmptyWindow = false` (named, optional); count `windowSessionCount++` inside the existing
`if (_sessionInWindow(session, fromMs, toMs))` branch; replace `if (windowTimeSeconds <= 0) return null;` with:

```dart
    if (windowTimeSeconds <= 0) {
      if (!keepEmptyWindow || windowSessionCount > 0 || latestStartMs == null) {
        return null;
      }
      return MixLayerData(
        measure: MixMeasure.time,
        segments: const [],
        baselineSegments: const [],
        unratedSessionCount: 0,
        ratedBaselineWeeks: ratedBaselineBlocks.length,
        weeks: const [],
        lastSessionDay: localMidnightDay(
          DateTime.fromMillisecondsSinceEpoch(latestStartMs),
        ),
        windowIsEmpty: true,
      );
    }
```

`computeMixLayer` passes `keepEmptyWindow: true` in its `_mixPayload(...)` call.

`MixLayerSection.build`: first statement after `final theme`:

```dart
    if (layer.windowIsEmpty) {
      return OmniSurface(
        key: const Key('mix_layer'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            OmniCardHeader(
              title: 'TRAINING MIX',
              actions: [StatsWindowChip(window: window, themeColors: themeColors)],
            ),
            const SizedBox(height: _blockGap),
            _buildEmptyWindow(theme),
          ],
        ),
      );
    }
```

```dart
  /// The empty window's one line (D-17008): a break is not a card of nothing.
  Widget _buildEmptyWindow(ThemeData theme) {
    final weeks = window.dayCount ~/ 7;
    final lastSessionDay = layer.lastSessionDay;
    return Text(
      lastSessionDay == null
          ? 'No training in the last $weeks weeks.'
          : 'No training in the last $weeks weeks. '
                'Last session: ${OmniDateUtils.formatShort(lastSessionDay)}.',
      key: const Key('mix_window_empty'),
      style: theme.textTheme.bodySmall?.copyWith(color: themeColors.textMuted),
    );
  }
```

`stats_screen.dart` `_loadData`: delete `final progressData = await service.computeProgressData();` and its comment; move
`final now = DateTime.now();` above the instruments call, add `final window = StatsProgressService.statsWindow(now: now);`
and replace the four `progressData.window` uses and `_window = progressData.window` with `window`.

## Scenarios (fixtures re-derived with `python3`: 2026-11-02 − 27 d = 2026-10-06; − 35 d = 2026-09-28; 2026-10-06 − 28 d = 2026-09-08; 2026-02-16 − 28 d = 2026-01-19)

| Id | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-17001 | `statsWindow(now: DateTime(2026,11,2,14,30))` | `fromMs` 2026-10-06 00:00, `toMs` 2026-11-02 23:59:59.999, label `Last 4 weeks`, `dayCount` 28, `isPeriodScoped` false | method does not exist |
| S-17002 | `now = DateTime(2026,3,15,9)` (spans a US spring-forward) | `fromMs` 2026-02-16, `dayCount` 28, `previousRangeFor.fromMs` = `DateTime(2026,1,19)` ms and `.toMs` = `DateTime(2026,2,16)` ms − 1 | same |
| S-17003 | Service, `now = DateTime(2026,11,2,14,30)`: two unrated 60 min sessions with no efforts, one starting 2026-10-06 09:00 (day 27 back) and one 2026-10-05 09:00 (day 28 back); `computeMixLayer(window: statsWindow(now: now))` | `unratedSessionCount` is 1 and the bar is Resistance 100%; the day-28 session is out | window start off by one (`- 28`) counts 2 |
| S-17004 | Screen: period "Holds" (start 3 d ago, end 10 d ahead) holds one 20 min cardio session today; rated 60 min resistance sessions 8, 12, 20 d ago (before the period) | bar names Resistance and Cardio with Resistance the larger share (first red run prints exact shares; time measure, unrated baseline); chip text `· Last 4 weeks`; no text `Holds` in the chip | old rule picked the period: bar was 100% Cardio, chip `Holds` |
| S-17005 | Same fixture | Instruments caption reads `Change: vs the 28 days before it` | old window was the period |
| S-17006 | Only completed sessions 35 and 60 d ago | `computeMixLayer` non-null, `windowIsEmpty` true, `segments`/`weeks` empty, `lastSessionDay` 2026-09-28 | returned null |
| S-17007 | Screen with S-17006's history | `mix_window_empty` reads `No training in the last 4 weeks. Last session: Sep 28.`; no `mix_bar`, `mix_strip_title`, `instrument_caption`; `ALL TIME` present; chip present | card absent |
| S-17008 | Twin: no completed session at all | `computeMixLayer` null (screen shows the empty state) | guards D-17006 `latestStartMs == null` |
| S-17009 | Twin: a completed session 2 d ago with duration 0 and no efforts | `computeMixLayer` null, no `windowIsEmpty` payload | guards D-17006 `windowSessionCount > 0` |
| S-17010 | `computeMixPeriod` for an empty period with older history | still null | guards `keepEmptyWindow` default false |
| S-17011 | Existing `stats_progress_test.dart` period cases (`data.window.isPeriodScoped` true, period name) and the 14-training-day cases | stay green, untouched | guards D-17001 |

Readers of `MixLayerData`: `mix_layer.dart`, `signals.dart`, `stats_screen.dart`, the two period signals
(`modality_mix_shift_signal.dart:51`, `cardio_efficiency_drift_signal.dart:67`), and many tests that construct it. The new
field defaults, so no constructor call changes.

Tests that already run `StatsScreen` or a resolved window, and will need fixture changes if red (found by running, not
guessed): `instrument_list_screen_test`, `mix_layer_screen_test`, `mix_layer_service_test`, `signals_layer_screen_test`,
`fuel_row_screen_test`, `stats_legacy_removal_test`, `stats_primer_screen_test`, `stats_load_failure_test`,
`header_standardization_test`, `screen_widget_test`, `screen_overflow_contract_test`, `entry_identity_summary_test`,
`nutrition_trend_screen_test`, `records_and_trends_screen_test` (must stay green untouched) and the seven `*_signal_screen_test`.

## Phases

| Phase | Agent | Write scope | Items | Serial/parallel |
|---|---|---|---|---|
| P1 | crew-builder-app | `lib/core/services/stats_progress_service.dart`, `lib/core/models/training_load.dart`, `lib/features/stats/stats_screen.dart`, new `test/stats_four_week_window_service_test.dart` | statsWindow; `_mixPayload` empty payload; `MixLayerData.windowIsEmpty`; screen wiring; S-17001/2/3/6/8/9/10 | first |
| P2 | crew-builder-app | `lib/features/stats/widgets/mix_layer.dart` | empty-window card (exact code above) | after P1 |
| P3 | crew-builder-app | new `test/stats_four_week_window_screen_test.dart` | S-17004/5/7, copying the pump helper from `mix_layer_screen_test.dart` | after P2 |
| P4 | crew-builder-app | the test files the red run names | fixture changes only; no production edit | after P3 |
| P5 | crew-docs-keeper | `docs/stats_screen.md` and any doc the grep names | Selection Window section, chip text, empty-window card, constants table | after P4 |

Done criteria: touched test files green with real counts; `flutter analyze` issue count not above baseline; full
`flutter test` green; invariant grep clean; prover mutations: window start `- 28`; `windowSessionCount > 0` dropped;
`keepEmptyWindow` default flipped; `latestStartMs == null` dropped.

## Progress
- [x] P1 — service + screen: `statsWindow`, the `_mixPayload` empty payload, `MixLayerData.windowIsEmpty`, screen wiring; `test/stats_four_week_window_service_test.dart` +14 passed
- [x] P2 — the empty-window card in `lib/features/stats/widgets/mix_layer.dart`
- [x] P3 — `test/stats_four_week_window_screen_test.dart` +8 passed
- [x] P4 — test adaptation: instrument list +36, mix layer +110, fuel row +50, modality mix shift +10, protein consistency +16
- [x] P5 — docs (this phase)
- [ ] prove  - [ ] review

## Assumption Log
- Baseline `flutter analyze` count: to be recorded in evidence before P1.
- Time/load shares in S-17004 are confirmed by the first run, not asserted from arithmetic.

## Feedback
Review: `2026-11-02-99a-stats-four-week-window-plan.review.md` (0 blocker, 2 major, 2 minor).
- [x] F1 empty-strip line and one-day caption wording: direct widget tests restored (fix round 1; each fails if its branch is deleted).
- [x] F3 S-1909 group renamed; the D-1201 guard (signal computes its own period) can no longer be separated from the Stats window.
- [ ] F2 nutrition target lookup loses inherited targets the day after a DST change: pre-existing, outside this PR; proposed as its own session (`_seedWindowTarget` keeps a documented workaround until then).
- Open (owner): the empty-strip branch of `MixLayerSection` is unreachable from the Stats screen now; kept as a generic widget behaviour with a test.
