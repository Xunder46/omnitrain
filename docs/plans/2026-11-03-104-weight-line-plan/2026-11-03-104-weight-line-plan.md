# 104 — The Stats screen shows the 4-week weight change

Status: SEEDED by the lead 2026-11-03 (no architect run: exact production code below; exact test text sits in the builder briefs).
Base commit: `.work/2026-11-03-104-weight-line/base.txt`. Track: phone only (`lib/`, `test/`, `docs/`).
Unrelated dirty files, never touch: `lib/core/services/stats_progress_service.dart`, `test/stats_dst_day_arithmetic_test.dart` (another session's DST work). Nothing here
needs the first file: the weight line reads the repository through its own small service.
Series: Stats Signals, group 3, review item 12. Unit 3 of 5. Owner 2026-11-03: "Yes to all" (commits pre-approved, take the defaults, report at the end).

## Goal and acceptance

What a user sees after this PR:

1. **A Weight block at the bottom of the Stats screen** (after the Fuel row) with one line: `80.2 kg, −0.6 kg over 4 weeks`. The first figure is the latest weigh-in in the
   window, the second is the change from the earliest weigh-in in the window to the latest (`+0.4 kg` for a gain, `no change` when the change rounds to 0.0). It reads in the
   user's weight unit (`kg` or `lbs`, one decimal).
2. **It appears only when there are at least two weigh-ins in the last 28 days that are at least 7 calendar days apart** (earliest and latest). One weigh-in, or two within a
   week, show nothing (two readings a day apart are noise, not a trend).
3. **It can be switched off** in Settings, in a new STATS section after WORKOUT: `Weight on Stats` — `Show your weight change over the last 4 weeks` (default on).
4. With no completed session the Stats screen is the empty state alone, as today: no Weight block.
5. Nothing else on the Stats screen changes.

Not in this PR: a weight-versus-intake signal (needs the logging cadence, owner decision: later); a chart; tapping the line (it goes nowhere); Health-sync changes.
Defaults taken: placement after Fuel; the 7-day spacing rule; the Settings switch.

## Decision Ledger

| Id | Decision | Where |
|---|---|---|
| D-17701 | Pure model `lib/core/models/weight_trend.dart`: `kWeightTrendWindowDays = 28`, `kWeightTrendMinSpanDays = 7`, class `WeightTrend {double latestKg; double changeKg;}` and `WeightTrend? weightTrend({required List<BodyMeasurementEntry> entries, required DateTime now})`. Entries count only when `measurementType == 'bodyweight'`, `unitId == MetricIds.unitKg` (the canonical unit, as `latestBodyWeightKg` requires), `value > 0`, recorded within the 28 local days ending today (today included). Earliest and latest by `recordedAtMs`, whatever the list order. The spacing is whole local calendar days between them, computed on the dates re-read as UTC (so a clock change inside the window never shortens a week: a 23-hour day made `Duration.inDays` read 6 for a true 7-day gap) | `weight_trend.dart` |
| D-17702 | Pure copy function `weightTrendLine({required double latest, required double change, required String unitLabel})` in the same file: `'<latest 1 dp> <unit>, <change> over 4 weeks'` where change is `−x.x <unit>` (U+2212) for a fall, `+x.x <unit>` for a rise, and the words `no change` when the rounded magnitude is 0.0. The `4 weeks` is `kWeightTrendWindowDays ~/ 7` | `weight_trend.dart` |
| D-17703 | `WeightTrendService(WorkoutRepository)` with `Future<WeightTrend?> compute({required DateTime now})`: reads `getMeasurementHistory('bodyweight')` and applies the rule. A repository that throws gives null (a courtesy block is absent rather than breaking Stats) | `lib/core/services/weight_trend_service.dart` |
| D-17704 | `SettingsState.showWeightTrend` (default true), `setShowWeightTrend(bool)`, preference key `show_weight_trend`, read at `initialize` with the same `!= 'false'` rule as `show_feeling_survey` | `settings_state.dart` |
| D-17705 | Settings screen: a new `STATS` section directly after WORKOUT (`OmniCardHeader(title: 'STATS')`, then `_StatsSection`) with one `_SettingsRow` `Weight on Stats` / `Show your weight change over the last 4 weeks` and a `Switch` bound to `showWeightTrend`. The section sits after WORKOUT so Effort Rating stays the first Switch of the screen (`interaction_flow_test.dart` taps `find.byType(Switch).first`) | `settings_screen.dart` |
| D-17706 | Widget `WeightTrendRow({trend, settingsState, themeColors})` in `lib/features/stats/widgets/weight_trend_row.dart`: a `Column` keyed `weight_trend` with `OmniCardHeader(title: 'Weight')` over an `OmniSurface` holding one `Text` keyed `weight_trend_line` (`bodyMedium`, `themeColors.textDominant`). The conversion is `UnitFormatter.convertWeight` on both figures and the label `UnitFormatter.weightLabel(settingsState)` | the widget file |
| D-17707 | `StatsScreen._load` computes `_weightTrend` when `totals.completedSessions > 0` (otherwise null); the build draws the row directly after the Fuel block when `_weightTrend != null && widget.settingsState.showWeightTrend`. The setting is read in `build`, so a switch flipped in Settings applies on return | `stats_screen.dart` |
| D-17708 | Proof: the lead's mutation pass M1-M8; new tests do not compile at the base, so `prove-red` at the base proves nothing | Assumption Log |

## Exact production code

### P1 — everything in `lib/`

`lib/core/models/weight_trend.dart` (new file; imports `../../data/models/models.dart` for `BodyMeasurementEntry` and `../constants/metric_ids.dart` for `MetricIds`):

```dart
// The weight line on Stats (plan 104): where the body weight stands and how it
// moved over the last four weeks. Pure Dart — no repository, no clock of its
// own: `now` is a parameter.

import '../../data/models/models.dart';
import '../constants/metric_ids.dart';

/// The span the line reads: the 28 local days ending today (D-17701).
const int kWeightTrendWindowDays = 28;

/// The fewest whole calendar days between the first and the last weigh-in
/// (D-17701): closer readings are noise, not a trend.
const int kWeightTrendMinSpanDays = 7;

/// The latest weigh-in in the window and the change since the earliest.
class WeightTrend {
  const WeightTrend({required this.latestKg, required this.changeKg});

  final double latestKg;

  /// Latest minus earliest, in kilograms.
  final double changeKg;
}

/// The weight trend of [entries] at [now], or null when the window holds fewer
/// than two usable weigh-ins or they are closer than [kWeightTrendMinSpanDays]
/// calendar days (D-17701).
WeightTrend? weightTrend({
  required List<BodyMeasurementEntry> entries,
  required DateTime now,
}) {
  final fromMs = DateTime(
    now.year,
    now.month,
    now.day - (kWeightTrendWindowDays - 1),
  ).millisecondsSinceEpoch;
  final endMs = DateTime(now.year, now.month, now.day + 1).millisecondsSinceEpoch;

  final usable = entries
      .where(
        (e) =>
            e.measurementType == 'bodyweight' &&
            e.unitId == MetricIds.unitKg &&
            e.value > 0 &&
            e.recordedAtMs >= fromMs &&
            e.recordedAtMs < endMs,
      )
      .toList()
    ..sort((a, b) => a.recordedAtMs.compareTo(b.recordedAtMs));
  if (usable.length < 2) return null;

  final first = usable.first;
  final last = usable.last;
  final firstDay = DateTime.fromMillisecondsSinceEpoch(first.recordedAtMs);
  final lastDay = DateTime.fromMillisecondsSinceEpoch(last.recordedAtMs);
  // Calendar days apart on the dates re-read as UTC, so a clock change inside
  // the window never turns a true week into 6 days and 23 hours.
  final apart = DateTime.utc(lastDay.year, lastDay.month, lastDay.day)
      .difference(DateTime.utc(firstDay.year, firstDay.month, firstDay.day))
      .inDays;
  if (apart < kWeightTrendMinSpanDays) return null;

  return WeightTrend(
    latestKg: last.value,
    changeKg: last.value - first.value,
  );
}

/// The line the Weight block reads (D-17702), in the figures [latest] and
/// [change] already converted to [unitLabel]'s unit.
String weightTrendLine({
  required double latest,
  required double change,
  required String unitLabel,
}) {
  final magnitude = double.parse(change.abs().toStringAsFixed(1));
  final changeText = magnitude == 0
      ? 'no change'
      : '${change < 0 ? '−' : '+'}${magnitude.toStringAsFixed(1)} $unitLabel';
  return '${latest.toStringAsFixed(1)} $unitLabel, $changeText over '
      '${kWeightTrendWindowDays ~/ 7} weeks';
}
```

`lib/core/services/weight_trend_service.dart` (new):

```dart
import '../../data/repositories/workout_repository.dart';
import '../models/weight_trend.dart';

/// Reads the body-weight history and applies [weightTrend] (D-17703).
class WeightTrendService {
  WeightTrendService(this._repository);

  final WorkoutRepository _repository;

  /// The trend at [now], or null with too little history. A history that cannot
  /// be read is also null: the block is absent rather than breaking Stats.
  Future<WeightTrend?> compute({required DateTime now}) async {
    try {
      final entries = await _repository.getMeasurementHistory('bodyweight');
      return weightTrend(entries: entries, now: now);
    } catch (_) {
      return null;
    }
  }
}
```

`lib/state/settings/settings_state.dart`: beside `_showFeelingSurveyKey`: `static const String _showWeightTrendKey = 'show_weight_trend';`; beside `_showFeelingSurvey`: `bool _showWeightTrend = true;`;
beside its getter: `bool get showWeightTrend => _showWeightTrend;`; after `setShowFeelingSurvey` add

```dart
  Future<void> setShowWeightTrend(bool value) async {
    _showWeightTrend = value;
    await _repository.setPreferenceString(_showWeightTrendKey, value.toString());
    notifyListeners();
  }
```

and in `initialize`, after `_showFeelingSurvey = ...;`:

```dart
    final savedShowWeightTrend = await _repository.getPreferenceString(
      _showWeightTrendKey,
      defaultValue: 'true',
    );
    _showWeightTrend = savedShowWeightTrend != 'false';
```

`lib/features/settings/settings_screen.dart`: after the WORKOUT block (`_WorkoutSection(...)` and its `const SizedBox(height: 24),`) add

```dart
                  const OmniCardHeader(title: 'STATS'),
                  _StatsSection(settingsState: widget.settingsState),
                  const SizedBox(height: 24),
```

and a class after `_WorkoutSection`:

```dart
class _StatsSection extends StatelessWidget {
  final SettingsState settingsState;

  const _StatsSection({required this.settingsState});

  @override
  Widget build(BuildContext context) {
    return OmniSurface(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SettingsRow(
            label: 'Weight on Stats',
            subtitle: 'Show your weight change over the last 4 weeks',
            trailing: Switch(
              value: settingsState.showWeightTrend,
              onChanged: settingsState.setShowWeightTrend,
            ),
          ),
        ],
      ),
    );
  }
}
```

`lib/features/stats/widgets/weight_trend_row.dart` (new):

```dart
import 'package:flutter/material.dart';

import '../../../core/constants/omni_theme.dart';
import '../../../core/models/weight_trend.dart';
import '../../../core/utils/unit_formatter.dart';
import '../../../state/settings/settings_state.dart';
import '../../../widgets/layout/omni_card_header.dart';
import '../../../widgets/layout/omni_surface.dart';

/// The Weight block: where the body weight stands and how it moved over the
/// last four weeks, in the user's unit (D-17706).
class WeightTrendRow extends StatelessWidget {
  final WeightTrend trend;
  final SettingsState settingsState;
  final OmniThemeColors themeColors;

  const WeightTrendRow({
    super.key,
    required this.trend,
    required this.settingsState,
    required this.themeColors,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      key: const Key('weight_trend'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const OmniCardHeader(title: 'Weight'),
        OmniSurface(
          child: Text(
            weightTrendLine(
              latest: UnitFormatter.convertWeight(
                trend.latestKg,
                settingsState,
              ),
              change: UnitFormatter.convertWeight(
                trend.changeKg,
                settingsState,
              ),
              unitLabel: UnitFormatter.weightLabel(settingsState),
            ),
            key: const Key('weight_trend_line'),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: themeColors.textDominant,
            ),
          ),
        ),
      ],
    );
  }
}
```

`lib/features/stats/stats_screen.dart`: add the imports (`weight_trend.dart`, `weight_trend_service.dart`, `weight_trend_row.dart`), a state field `WeightTrend? _weightTrend;`, in `_load` (after the signals block, before `if (!mounted) return;`):

```dart
      final weightTrend = totals.completedSessions > 0
          ? await WeightTrendService(
              widget.workoutState.repository,
            ).compute(now: now)
          : null;
```

`_weightTrend = weightTrend;` in the `setState`, and in the build directly after the Fuel block's closing `],`:

```dart
                            if (_weightTrend != null &&
                                widget.settingsState.showWeightTrend) ...[
                              WeightTrendRow(
                                trend: _weightTrend!,
                                settingsState: widget.settingsState,
                                themeColors: themeColors,
                              ),
                              const SizedBox(height: 24),
                            ],
```

If the build is not already rebuilt when `settingsState` notifies (check whether the screen wraps its body in a `ListenableBuilder` on `settingsState`), say so in the report; do not add a listener unless it is missing.

## Scenarios

Fixed dates (`now` = 2026-03-20 12:00 local unless said) for the model; the Stats screen reads the device clock, so its fixtures count back from today. `Fails without the change` is proven by the lead's mutations (D-17708).

| Id | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-17701 | `weightTrend`: (a) 80.8 kg 27 days ago and 80.2 kg today; (b) 6 days apart; (c) exactly 7 days apart; (d) one entry; none; (e) 80.8 kg 28 days ago and 80.2 today; (f) an `unit-lb` entry and a `height` entry beside one kg weight; (g) the same entries in reverse order; (h) three entries; (i) 2026-03-05 12:00 and 2026-03-12 12:00 (a spring-forward day between) with now 2026-03-12 18:00 | (a) latest 80.2, change −0.6 (within 1e-9); (b) null; (c) a trend; (d) null; (e) null (the 28-days-ago entry is outside); (f) null (one usable entry); (g) same as (a); (h) change = last − first; (i) a trend | the `<=` spacing slip (M1), the window start off by one (M2), `Duration.inDays` on local instants reads 6 across the 23-hour day (M3), the unit filter (M6) |
| S-17702 | `weightTrendLine` for (80.2, −0.6, 'kg'), (80.2, 0.44, 'kg'), (80.2, 0.04, 'kg'), (80.2, −0.04, 'kg'), (176.8, −1.3, 'lbs') | `80.2 kg, −0.6 kg over 4 weeks`; `80.2 kg, +0.4 kg over 4 weeks`; `80.2 kg, no change over 4 weeks` twice; `176.8 lbs, −1.3 lbs over 4 weeks` | the no-change branch (M4) and the sign (M5) |
| S-17703 | `WeightTrendService.compute` on Mock and Hive: no entries; two kg entries 14 days apart | null; the trend | the service reading the wrong type or no history |
| S-17704 | `SettingsState`: default, set false, reload | `showWeightTrend` true; stored `'false'` under `show_weight_trend`; false after reload | the default flipped (M8) |
| S-17705 | Stats screen (Mock and Hive): one completed session and kg entries 27 days ago (80.8) and today (80.2) | `weight_trend_line` reads `80.2 kg, −0.6 kg over 4 weeks`; with the unit set to lbs `176.8 lbs, −1.3 lbs over 4 weeks`; below the Fuel block when food was logged; absent with the switch off, with one entry, with entries 6 days apart, and with no completed session | the block was never drawn; the switch was ignored (M7) |
| S-17706 | Settings screen: scroll to `Weight on Stats`; the Switch after Effort Rating's | tapping it sets `showWeightTrend` false and leaves `showFeelingSurvey` true; the first Switch is still Effort Rating's | the section was missing |

## Phases

| Phase | Agent | Write scope | Items | Serial/parallel |
|---|---|---|---|---|
| P1 | crew-builder-app | the new `lib/core/models/weight_trend.dart`, `lib/core/services/weight_trend_service.dart`, `lib/features/stats/widgets/weight_trend_row.dart`; `lib/state/settings/settings_state.dart`, `lib/features/settings/settings_screen.dart`, `lib/features/stats/stats_screen.dart` | the exact edits above (6 items) | first |
| P2a | crew-builder-app | new `test/weight_trend_test.dart`; `test/settings_state_test.dart` | S-17701, S-17702, S-17703, S-17704 (exact text in the brief) | after P1; parallel with P2b |
| P2b | crew-builder-app | new `test/weight_trend_screen_test.dart` | S-17705, S-17706 | after P1; parallel |
| P3 | crew-docs-keeper | `docs/stats_screen.md`, `docs/profile_and_measurements.md`, `docs/theme_and_settings.md`, `docs/state_management/app_state.md` | the Docs delta rows | after P2 |
| P4 | crew-reviewer | the plan's `.review.md` | five narrow questions | after P3 |

Done criteria: touched test files green with real counts; `flutter analyze` issue count not above the base count (181; 0 errors); full `flutter test` green; invariant grep clean;
`ui_standards_contract_test.dart` and `docs_indexing_contract_test.dart` green; `plan-lint.py after` clean. Mutations: M1 `apart < kWeightTrendMinSpanDays` to `apart <= kWeightTrendMinSpanDays`;
M2 `now.day - (kWeightTrendWindowDays - 1)` to `now.day - kWeightTrendWindowDays`; M3 the spacing from `.difference(...)` of the two local instants (`lastDay.difference(firstDay).inDays`);
M4 the `magnitude == 0 ? 'no change'` branch dropped (`false ? ...`); M5 `change < 0 ? '−' : '+'` swapped; M6 `e.unitId == MetricIds.unitKg &&` removed; M7 `&& widget.settingsState.showWeightTrend` removed in the screen;
M8 the `_showWeightTrend` default `true` to `false`.

## Docs delta

Markers are exact one-line phrases. `-` = none. The keeper also searches `docs/` (excluding plans, history, releases) for `all-time aggregates`, `four blocks`, `Fuel row`, `Effort Rating`,
and reports any other hit that became false.

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| docs/stats_screen.md | MODIFIED | alone — no Mix layer, no Signals layer, no Instruments list and no Fuel row, | no Instruments list, no Fuel row and no Weight block | S-17705 |
| docs/stats_screen.md | MODIFIED | whatever the food log holds. Otherwise it is four blocks in a fixed order: the | Otherwise it is five blocks in a fixed order | S-17705 |
| docs/stats_screen.md | MODIFIED | [Fuel row](#fuel-row) when recent food exists. Verified by | [Weight block](#weight-block) | S-17705 |
| docs/stats_screen.md | ADDED | - | ### Weight block | S-17705 |
| docs/profile_and_measurements.md | MODIFIED | (all-time aggregates, the Instruments list, the Fuel row | the Mix, Signals, Instruments, Fuel and Weight blocks | S-17705 |
| docs/profile_and_measurements.md | ADDED | - | The weight line on Stats | S-17701 |
| docs/theme_and_settings.md | ADDED | - | Weight on Stats | S-17706 |
| docs/state_management/app_state.md | ADDED | - | `_showWeightTrend` | S-17704 |
| docs/state_management/app_state.md | ADDED | - | `showWeightTrend` | S-17704 |

## Progress

- [x] P1 production
- [x] P2a model, copy, service, setting tests
- [x] P2b screen tests
- [x] Lead mutation pass M1-M8
- [x] P3 docs
- [x] `plan-lint after`
- [x] P4 review
- [x] Full suite, analyze, invariants
- [x] Commit (own files only)

## Assumption Log

- Independent review of 2026-11-03: Stats reads no weight today; bodyweight feeds only Protein Consistency (as the g/kg divisor); `getMeasurementHistory('bodyweight')` returns the entries (kg
  canonical, newest first); weigh-ins may arrive automatically from Health sync (`health_sync_service.dart` `readBodyWeightSince` → `saveMeasurementEntry`). Two weigh-ins are noisy, hence the 7-day spacing.
- Defaults taken: block under Fuel; switch in a new STATS Settings section (after WORKOUT because `interaction_flow_test.dart` taps the first Switch of the screen, which must stay Effort Rating's);
  the figures use the user's weight unit; a rounded-zero change reads `no change`.
- Not run on a device or simulator: where the block sits at a real phone width is a layout a test cannot see; the simulator look is off by default.
- Lead mutation pass M1-M8: all eight killed (M1/M2/M3/M6 by S-17701, M4/M5 by S-17702 and S-17705, M7 by S-17705, M8 re-aimed from the dead field initialiser to the `defaultValue` read and killed by S-17704). Review APPROVE, 0 blocker, 0 major, 4 minor.
- Review minor 1 (real): the Weight block sat flush against the Fuel card. Fixed by the lead: a 24 dp gap before the block when the Fuel row shows, asserted in `test/weight_trend_screen_test.dart` (`S-17705` › `two weigh-ins 27 days apart`; proved by removing the spacer: the test failed on both harnesses, restored and `cmp`-checked). Minor 2: the design-system row now cites that test. Minor 3: the lead also corrected four stale docs outside the keeper's scope (`docs/README.md`, `docs/design_system.md`, `docs/navigation_and_screens.md` twice; the last also fixed its Signals gating sentence, stale since unit 102). Minor 4: the spring-forward case guards `Duration.inDays` only in a zone with daylight saving (the pattern of plan 101); in UTC it still passes.
- Full suite `+6243 ~2 -1`: the one red is `routine_save_removes_deleted_rows_test.dart` S-R3 again (it was red at the base of units 101 and 102 and green in unit 103's run: order- or timing-dependent, not touched here); analyze 181; invariant grep clean; contract tests `+54`.
- Docs sizes: `docs/stats_screen.md` 51.9 KB (ceiling 52 KB): the next unit must not add there.
- Not run on a device or simulator: where the block sits at a real phone width is a layout a test cannot see.
