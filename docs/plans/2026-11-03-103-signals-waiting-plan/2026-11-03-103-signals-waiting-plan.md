# 103 — The Signals block says what its quiet signals are waiting for

Status: SEEDED by the lead 2026-11-03 (no architect run: exact production code below; exact test text sits in the builder briefs).
Base commit: `.work/2026-11-03-103-signals-waiting/base.txt`. Track: phone only (`lib/`, `test/`, `docs/`).
Unrelated dirty files, never touch: `lib/core/services/stats_progress_service.dart`, `test/stats_dst_day_arithmetic_test.dart` (another session's
DST work). Nothing in this unit needs the first file: it calls only its public methods `nutritionSeries` and `cardioEfforts`.
Series: Stats Signals, group 3, review item 11. Unit 2 of 5. Owner 2026-11-03: "Yes to all" (commits pre-approved, take the defaults, report at the end).
Facts come from two read-only scout sheets (abstain conditions; heart-rate, distance and food-logging sources) and the independent review of 2026-11-03.

## Goal and acceptance

What a user sees after this PR, under the Signals cards, the quiet line or the locked line (whichever the block shows):

1. **Up to three short lines saying what a sleeping signal waits for**, each starting with the signal's name, one per signal at most:
   - `Protein Consistency: log food on N more days of the last 14.` (`1 more day` for one) shown only when food was logged on 1 to 9 of the last 14 days
     (today included). With no day logged the line is absent (a user who does not log food is not nagged); with 10 or more it is absent (the signal can speak).
   - `Cardio Efficiency: needs heart rate from the watch on at least 3 workouts of the same kind in each of two periods.` shown only when the history holds
     1 to 5 cardio workouts that already carry a measured distance and an average heart rate (6 or more: the line is absent; none: absent, because without a
     watch there is nothing the user can do).
2. **The rating wait is already told** by the locked line (`Unlocks after 4 weeks of rating your workouts — N of 4 so far.`) and the hint line under a card
   (`More signals unlock after ...`), unchanged. They are the "rating" entry of the checklist; the four load-reading signals (Fuel vs Load, Sustained High
   Load, Modality Mix Shift, Interference) have no line of their own.
3. The quiet line (`No signals — nothing outside your usual range.`), the locked line and the hint keep their copy.
4. With no completed session the Stats screen is the empty state alone, as today: no signal and no waiting line is evaluated.

Not in this PR: waiting lines for the four load-reading signals; Fuel vs Load's six-week food-logging requirement; Mix Shift on time; the quiet line's own copy.
Defaults taken (owner said take defaults): no nagging of users who never log food or have no watch; at most three lines.

## Decision Ledger

| Id | Decision | Where |
|---|---|---|
| D-17601 | `Signal` gains an abstract `Future<String?> waitingFor(SignalContext context)`: one sentence on what the user can supply to wake this signal, or null when it is not short of anything the user can supply. Abstract on purpose (a new signal must decide). Five signals return null; Protein Consistency and Cardio Efficiency Drift return a line | `signals/signal.dart`, the seven signal files |
| D-17602 | `SignalsService.waitingLines({now, window, mix})` asks each registered signal in registry order, drops nulls, never throws (a `waitingFor` that throws is skipped) and returns at most `kSignalMaxWaitingLines` (3, new constant in `signals.dart`) lines. It does not read the gate | `signals_service.dart` |
| D-17603 | Pure rule `String? proteinConsistencyWaitingLine(int loggedDays)` in `protein_consistency.dart`: null below 1 and at or above `kProteinConsistencyMinLoggedDays` (10); otherwise `Protein Consistency: log food on $more more ${more == 1 ? 'day' : 'days'} of the last $kProteinConsistencyWindowDays.` The signal counts `nutritionSeries(fromMs: today-13, toMs: now).length`, the same 14-local-days-ending-today window and "a day with at least one ConsumedFood row" definition its own rule reads | `protein_consistency.dart`, `protein_consistency_signal.dart` |
| D-17604 | Pure rule `String? cardioEfficiencyWaitingLine(int eligibleEfforts)` in `cardio_efficiency_drift.dart`: null below 1 and at or above `2 * kCardioEfficiencyMinEffortsPerWindow` (6); otherwise `Cardio Efficiency: needs heart rate from the watch on at least $kCardioEfficiencyMinEffortsPerWindow workouts of the same kind in each of two periods.` The signal counts `cardioEfforts(fromMs: today - kCardioEfficiencyReferenceWeeksFrom*7, toMs: now).length`, the span its own evaluate reads | `cardio_efficiency_drift.dart`, `cardio_efficiency_drift_signal.dart` |
| D-17605 | Screen: `_load` computes the lines whenever `totals.completedSessions > 0` (same condition as the signals) into `_signalsWaiting`; `SignalsLayerSection` and `SignalsLockedSection` take `List<String> waiting` (default empty) and render one `Text` per line (key `signals_waiting_$i`, `bodySmall`, `themeColors.textSecondary`, 8 dp above each) after everything else in the block. A dismissal does not change them | `stats_screen.dart`, `signals_layer.dart` |
| D-17606 | The two `_StubSignal` test classes gain a constructor argument `waiting` (`String?`, default null) and `Future<String?> waitingFor(SignalContext context) async => waiting;` so every existing test keeps its meaning | the two stub classes |
| D-17607 | Cardio lines count only efforts that already carry a measured (not estimated) distance and an average heart rate: that is what `cardioEfforts` returns (scout B: heart rate has one producer, the wrist's `session_end` import; a phone-only user can never supply it, so a user with none sees no line). Why 6: the signal needs 3 efforts of one group in each of two windows; below 6 in total it cannot speak whatever the grouping | `stats_progress_service.dart:2689` |
| D-17608 | Proof: the lead's mutation pass M1-M7; new tests do not compile at the base, so `prove-red` at the base proves nothing | Assumption Log |

## Exact production code

### P1a — models, contract, signals, service, stubs

`lib/core/models/signals.dart`, after `kSignalMaxCards`:

```dart
/// The most waiting lines the Signals block ever shows (D-17602).
const int kSignalMaxWaitingLines = 3;
```

`lib/core/models/protein_consistency.dart`, after `proteinConsistencyGate`:

```dart
/// What would wake Protein Consistency, in one sentence, or null (D-17603).
///
/// Null with no logged day at all — a user who does not log food is not
/// nagged — and once [kProteinConsistencyMinLoggedDays] days are logged, when
/// the signal is no longer short of anything the user can supply.
String? proteinConsistencyWaitingLine(int loggedDays) {
  if (loggedDays < 1 || loggedDays >= kProteinConsistencyMinLoggedDays) {
    return null;
  }
  final more = kProteinConsistencyMinLoggedDays - loggedDays;
  return 'Protein Consistency: log food on $more more '
      '${more == 1 ? 'day' : 'days'} of the last '
      '$kProteinConsistencyWindowDays.';
}
```

`lib/core/models/cardio_efficiency_drift.dart`, as a top-level function after the constants (before the first class):

```dart
/// What would wake Cardio Efficiency Drift, in one sentence, or null (D-17604).
///
/// [eligibleEfforts] counts the efforts that already carry a measured distance
/// and an average heart rate. Null with none (nothing the user can supply
/// without a watch) and with `2 * kCardioEfficiencyMinEffortsPerWindow` or
/// more (the floor of the two windows can be met).
String? cardioEfficiencyWaitingLine(int eligibleEfforts) {
  if (eligibleEfforts < 1 ||
      eligibleEfforts >= 2 * kCardioEfficiencyMinEffortsPerWindow) {
    return null;
  }
  return 'Cardio Efficiency: needs heart rate from the watch on at least '
      '$kCardioEfficiencyMinEffortsPerWindow workouts of the same kind in '
      'each of two periods.';
}
```

`lib/core/services/signals/signal.dart`, after `bool get needsRatedWeeks;`:

```dart
  /// One sentence on what the user can supply to wake this signal, or null when
  /// it is not short of anything the user can supply (D-17601).
  Future<String?> waitingFor(SignalContext context);
```

In the five signals `fuel_vs_load`, `sustained_high_load`, `modality_mix_shift`, `interference`, `progression_rate`, directly after `needsRatedWeeks`:

```dart
  @override
  Future<String?> waitingFor(SignalContext context) async => null;
```

`lib/core/services/signals/protein_consistency_signal.dart`, directly after `needsRatedWeeks`:

```dart
  @override
  Future<String?> waitingFor(SignalContext context) async {
    final now = context.now;
    final windowStart = DateTime(
      now.year,
      now.month,
      now.day - (kProteinConsistencyWindowDays - 1),
    );
    final points = await context.progressService.nutritionSeries(
      fromMs: windowStart,
      toMs: now,
    );
    return proteinConsistencyWaitingLine(points.length);
  }
```

`lib/core/services/signals/cardio_efficiency_drift_signal.dart`, directly after `needsRatedWeeks`:

```dart
  @override
  Future<String?> waitingFor(SignalContext context) async {
    final now = context.now;
    final efforts = await context.progressService.cardioEfforts(
      fromMs: DateTime(
        now.year,
        now.month,
        now.day - kCardioEfficiencyReferenceWeeksFrom * 7,
      ),
      toMs: now,
    );
    return cardioEfficiencyWaitingLine(efforts.length);
  }
```

(import the model constants if the file does not already import the models that declare them; `protein_consistency.dart` and `cardio_efficiency_drift.dart` are already imported by their signals.)

`lib/core/services/signals_service.dart`, after `evaluateCandidates`:

```dart
  /// What the quiet signals are waiting for, one line each, in registry order
  /// (D-17602). The gate is not read: a signal answers for itself. A signal
  /// whose answer cannot be read is skipped, so a courtesy line never breaks
  /// the screen.
  Future<List<String>> waitingLines({
    required DateTime now,
    required StatsWindow window,
    required MixLayerData? mix,
  }) async {
    final context = SignalContext(
      now: now,
      window: window,
      mix: mix,
      progressService: _progressService,
      repository: _repository,
    );
    final lines = <String>[];
    for (final signal in _signals) {
      try {
        final line = await signal.waitingFor(context);
        if (line != null) lines.add(line);
      } catch (_) {
        // Absent rather than broken.
      }
    }
    return lines.take(kSignalMaxWaitingLines).toList(growable: false);
  }
```

The two `_StubSignal` classes (`test/signals_service_test.dart`, `test/signals_layer_screen_test.dart`): add `this.waiting,` to the constructor (named, after `needsRatedWeeks`), `final String? waiting;`
and `@override Future<String?> waitingFor(SignalContext context) async => waiting;`.

### P1b — layer and screen

`lib/features/stats/widgets/signals_layer.dart`: a top-level helper before `SignalsLockedSection`:

```dart
/// One quiet line per signal still waiting for something the user can supply
/// (D-17605), each 8 dp under whatever came before it.
List<Widget> _waitingLines(
  List<String> waiting,
  ThemeData theme,
  OmniThemeColors themeColors,
) => [
  for (var i = 0; i < waiting.length; i++) ...[
    const SizedBox(height: 8),
    Text(
      waiting[i],
      key: Key('signals_waiting_$i'),
      style: theme.textTheme.bodySmall?.copyWith(
        color: themeColors.textSecondary,
      ),
    ),
  ],
];
```

`SignalsLockedSection` gets `final List<String> waiting;` (`this.waiting = const []`) and, as the last child of its `Column`, `..._waitingLines(waiting, theme, themeColors),`.
`SignalsLayerSection` gets `final List<String> waiting;` (`this.waiting = const []`) and, as the last child of its `Column` (after the `if (cards.isEmpty) ... else ...` block), `..._waitingLines(waiting, Theme.of(context), themeColors),`.

`lib/features/stats/stats_screen.dart`: add `List<String> _signalsWaiting = const [];` beside `_signalsData`; in `_load` after `signalsData`:

```dart
      final signalsWaiting = evaluateSignals
          ? await signalsService.waitingLines(
              now: now,
              window: window,
              mix: mixLayer,
            )
          : const <String>[];
```

set `_signalsWaiting = signalsWaiting;` in the `setState`, and pass `waiting: _signalsWaiting,` to both `SignalsLayerSection(...)` and `SignalsLockedSection(...)`.

## Scenarios

Fixed dates or the harness helpers of the file each test lands in. `Fails without the change` is proven by the lead's mutations (D-17608).

| Id | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-17601 | `proteinConsistencyWaitingLine` for 0, 1, 9, 10, 14 days | null, `...log food on 9 more days of the last 14.`, `...on 1 more day of the last 14.`, null, null | `<` to `<=` on the upper bound shows a line at 10 (M1) |
| S-17602 | `cardioEfficiencyWaitingLine` for 0, 1, 5, 6, 9 efforts | null, the line, the line, null, null; the line reads `at least 3 workouts` | `2 *` dropped shows the line at 5 no more (M2) |
| S-17603 | `SignalsService.waitingLines` over stubs: `[null, 'a', 'b']`; a stub whose `waitingFor` throws between two lines; five stubs each with a line | `['a','b']`; the thrower skipped; the first three only | catch removed (M3); cap removed (M4) |
| S-17604 | Real `ProteinConsistencySignal.waitingFor` on Mock AND Hive repositories: 0, 4 and 10 days with a `ConsumedFood` in the last 14 days (today included); also a food 14 days ago, outside the window | null; `...log food on 6 more days of the last 14.`; null; the old food does not count | the window counted from the wrong day or the wrong definition (M5: off-by-one window start) |
| S-17605 | Screen (Mock and Hive), stub `w` with `waiting: 'Waiting line one'`: (a) gate unmet, no card: the locked section; (b) gate unmet, an unlocked card showing; (c) gate met, nothing speaks (the quiet line) | in each case `signals_waiting_0` reads the stub's text and sits below the locked line, the hint and the quiet line respectively; the other copy is unchanged | the lines were never drawn (M6, M7) |
| S-17606 | The existing empty-state test: no completed session, a stub with `waiting` set | `waitingFor` is never called (count 0); no `signals_waiting_0` | `evaluateSignals` gating dropped for the lines (M8) |
| S-17607 | The existing S-1702, S-17505, S-1703 screen tests | stay green untouched: the locked line, the hint and the quiet line keep their copy | guards the copy |

## Phases

| Phase | Agent | Write scope | Items | Serial/parallel |
|---|---|---|---|---|
| P1a | crew-builder-app | `lib/core/models/signals.dart`, `lib/core/models/protein_consistency.dart`, `lib/core/models/cardio_efficiency_drift.dart`, `lib/core/services/signals/**`, `lib/core/services/signals_service.dart`, the two stub classes | the exact edits above (items: signals.dart const, protein fn, cardio fn, signal.dart, five nulls, protein signal, cardio signal, service, stubs) | first |
| P1b | crew-builder-app | `lib/features/stats/widgets/signals_layer.dart`, `lib/features/stats/stats_screen.dart` | the exact edits above | after P1a |
| P2a | crew-builder-app | new `test/signals_waiting_test.dart` | S-17601, S-17602, S-17603, S-17604 (exact text in the brief) | after P1b; parallel with P2b |
| P2b | crew-builder-app | `test/signals_layer_screen_test.dart` | S-17605, S-17606 | after P1b; parallel |
| P3 | crew-docs-keeper | `docs/signals.md`, `docs/stats_screen.md`, `docs/widget_catalog.md` | the Docs delta rows | after P2 |
| P4 | crew-reviewer | the plan's `.review.md` | five narrow questions | after P3 |

Done criteria: touched test files green with real counts; `flutter analyze` issue count not above the base count (181; 0 errors); full `flutter test` green apart from
the known red (`routine_save_removes_deleted_rows_test.dart` S-R3, red at the base); invariant grep clean; `ui_standards_contract_test.dart` and
`docs_indexing_contract_test.dart` green; `plan-lint.py after` clean. Mutations: M1 `loggedDays >= kProteinConsistencyMinLoggedDays` to `>`; M2 `2 *
kCardioEfficiencyMinEffortsPerWindow` to `1 *`... (see D-17604; the test uses 5 efforts); M3 remove the `try`/`catch` in `waitingLines` (let it throw); M4 remove `.take(kSignalMaxWaitingLines)`;
M5 the protein signal's `windowStart` day offset `kProteinConsistencyWindowDays - 1` to `kProteinConsistencyWindowDays`; M6 the screen passes `waiting: const []` to `SignalsLockedSection`;
M7 `SignalsLayerSection` omits `..._waitingLines(...)`; M8 `evaluateSignals` forced true for the waiting call only.

## Docs delta

Markers are exact one-line phrases. `-` = none. The keeper also searches `docs/` (excluding plans, history, releases) for `waitingFor`, `evaluateCandidates`, `SignalsService`,
`quiet line`, `nothing else`, and reports any other hit that became false.

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| docs/signals.md | MODIFIED | priority and `evaluate`. `SignalContext` carries everything one evaluation may | what it is waiting for | S-17603 |
| docs/signals.md | ADDED | - | Each signal can say what it is waiting for | S-17603 |
| docs/signals.md | ADDED | - | proteinConsistencyWaitingLine | S-17601 |
| docs/signals.md | ADDED | - | cardioEfficiencyWaitingLine | S-17602 |
| docs/stats_screen.md | MODIFIED | its header and `kSignalQuietLine` and nothing else. The layer is never hidden | one line for each signal that is still waiting for data | S-17605 |
| docs/stats_screen.md | ADDED | - | Protein Consistency: log food on | S-17604 |
| docs/stats_screen.md | ADDED | - | Cardio Efficiency: needs heart rate from the watch | S-17602 |
| docs/widget_catalog.md | MODIFIED | a dismiss callback and an optional `lockedRatedWeeks` | a dismiss callback, the waiting lines and an optional `lockedRatedWeeks` | S-17605 |

## Progress

- [x] P1a models, contract, signals, service, stubs
- [x] P1b layer and screen
- [x] P2a signals_waiting_test
- [x] P2b screen tests
- [x] Lead mutation pass M1-M8
- [x] P3 docs
- [x] `plan-lint after`
- [x] P4 review
- [x] Full suite, analyze, invariants
- [x] Commit (own files only)

## Assumption Log

- Scouts (2026-11-03): heart rate has a single producer, the watch import (`watch_session_importer.dart` `_createTimedInstance`); no manual phone entry or Health sync writes it. Distance is
  typed on the phone (source `entered`) or sent by the wrist (`gps`); only `estimated` is excluded. Protein Consistency counts 14 local days ending today; the Fuel row counts 7 finished days
  ending yesterday, so the two logged-day counts are deliberately not shared.
- With Effort Rating off the automatic prompt is skipped, but the Summary's Add/Change rating button still records a rating, so the gate can open; the locked line is therefore still honest.
- Default taken: no waiting line for the four load-reading signals (the locked line covers the rating wait); Fuel vs Load's six weeks of 5-plus food days is not listed.
- Lead-written parts: the unused `waiting` argument of the service test's `_StubSignal` was removed (analyzer warning); the contract sentence in `docs/signals.md` now lists `needsRatedWeeks` (review minor 1). The review's minor 2 (the two file-table rows in `docs/stats_screen.md` the keeper also updated, not named in the Docs delta) is bookkeeping: both sentences are true.
- Lead mutation pass M1-M8: all eight killed (M1/M2 by S-17601/S-17602, M3/M4 by S-17603, M5 by S-17604 on both harnesses, M6/M7 by S-17605, M8 by S-17606).
- Full suite `+6211 ~2` (all passed; the base's one red, `routine_save_removes_deleted_rows_test.dart` S-R3, passed in this tree), analyze 181 (baseline 181), invariant grep clean, UI standards + docs contract tests `+54`.
- Docs sizes after this unit: `docs/signals.md` 51.2 KB, `docs/stats_screen.md` 51.7 KB (ceiling 52 KB): the next unit that adds docs there must split a page first.
