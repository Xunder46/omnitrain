# 106 — Hold Progress: a positive signal for the one kind of work Progression Rate ignores

Status: SEEDED by the lead 2026-11-03 (no architect run: exact production code below; exact test text sits in the builder briefs).
Base commit: `.work/2026-11-03-106-hold-progress/base.txt`. Track: phone only (`lib/`, `test/`, `docs/`).
Unrelated dirty files, never touch: `lib/core/services/stats_progress_service.dart`, `test/stats_dst_day_arithmetic_test.dart` (another session's DST work). The signal CALLS the public
`computeInstrumentSections` of the first file and changes nothing in it.
Series: Stats Signals, group 3, review item 10 (hold and cardio duration trend). Unit 5 of 5. Owner 2026-11-03: "Yes to all" (commits pre-approved, take the defaults, report at the end).
The independent review corrected the proposal's premise: Instruments computes the LONGEST single hold per window, not an average, and each Instruments row already shows its own change against the four weeks before;
the real gap is that Progression Rate reads only `set` efforts, so no positive signal covers holds.

## Goal and acceptance

What a user sees after this PR, in the Signals block (existing card rules: at most two cards, dismissible for 14 days, speaks before four rated weeks):

1. **A positive card for holds:** `Your longest hold on Deep Squat is up 20 s over the last 4 weeks, now 60 s.` — shown when an isometric exercise (a repeated-hold effort) has at least 3 completed sessions in the
   last four weeks, its longest hold in those four weeks is at least 10 s longer than its longest hold in the four weeks before, and that gain is at least 10% of the earlier figure. With several such exercises the biggest gain wins
   (a tie goes to the name alphabetically). Nothing is said about a hold that did not improve by that much, a new exercise with no earlier four weeks, or fewer than 3 sessions.
2. The card has no suggestion line; the signal reads no ratings, so it can speak before four rated weeks; it has no waiting line. Its priority sits below Consistency's among the positives (Progression Rate 100, Consistency 50, Hold Progress 40).
3. **Cardio is not added.** A cardio row shows its fastest pace (or its total duration only when it has no pace) and its own change against the four weeks before in the Instruments list; a duration card would repeat that row, and
   a pace "trend" reads the other way round (lower is better). Default taken; the owner can ask for it later.
4. Nothing else changes.

## Decision Ledger

| Id | Decision | Where |
|---|---|---|
| D-17901 | Pure model `lib/core/models/hold_progress.dart` (imports `exercise_metric.dart` and `instrument_list.dart`): `kHoldProgressMinSessions = 3`, `kHoldProgressMinGainSecs = 10`, `kHoldProgressMinGainPercent = 10`, `kHoldProgressPriority = 40`; `HoldProgressResult {name, exerciseId, recentSecs, previousSecs, gainSecs}`; `holdProgress(List<InstrumentSectionData> sections)` and `holdProgressObservation(result, {required int weeks})` | `hold_progress.dart` |
| D-17902 | The rule reads the Instruments rows the screen already shows: only rows of the `isometric` section whose best value AND previous value are on the `hold` metric, with `summary.sessionCount >= 3`, `previousSecs > 0`, `gain >= 10` and `100 * gain >= 10 * previousSecs` (both inclusive); the values are the rows' own figures rounded to whole seconds. The biggest gain wins; ties by name ascending, then exercise id ascending | `hold_progress.dart` |
| D-17903 | `HoldProgressSignal` (id `hold-progress`, positive, priority `kHoldProgressPriority`, `needsRatedWeeks` false, `waitingFor` null, title `Hold progress`, no suggestion) reads `context.progressService.computeInstrumentSections(window: context.window)` and builds the copy with `weeks = StatsProgressService.kStatsWindowDays ~/ 7` (the screen's window is always those four weeks, D-17003). Registered after `ConsistencySignal()` | `hold_progress_signal.dart`, `signal_registry.dart` |
| D-17904 | Tests that pin the registry change with it: `test/signals_service_test.dart` (`S-17503`: the map gains `hold-progress` false) and `test/modality_mix_shift_signal_screen_test.dart` (`the registry` › `lists exactly the nine shipped signals, in order` becomes `ten`, the list gains `hold-progress` after `consistency`). The seed lists them because unit 105's full suite found the second one | the two tests |
| D-17905 | Proof: the lead's mutation pass M1-M8; the new tests do not compile at the base, so `prove-red` at the base proves nothing | Assumption Log |

## Exact production code

### P1 — `lib/`

`lib/core/models/hold_progress.dart` (new):

```dart
// The Hold Progress signal's rule (plan 106): an isometric exercise whose
// longest hold in the Stats window beat its longest hold in the window before
// by enough to mean something. Pure Dart: the rule reads the Instruments rows
// the screen already shows.

import 'exercise_metric.dart';
import 'instrument_list.dart';

/// The fewest completed sessions the exercise has in the window (D-17902).
const int kHoldProgressMinSessions = 3;

/// The smallest gain in seconds (D-17902), inclusive.
const int kHoldProgressMinGainSecs = 10;

/// The smallest gain as a percentage of the earlier longest hold (D-17902),
/// inclusive.
const int kHoldProgressMinGainPercent = 10;

/// Hold Progress ranks below Consistency among the positives.
const int kHoldProgressPriority = 40;

/// The exercise whose longest hold improved the most.
class HoldProgressResult {
  const HoldProgressResult({
    required this.name,
    required this.exerciseId,
    required this.recentSecs,
    required this.previousSecs,
  });

  final String name;
  final String exerciseId;

  /// The longest hold in the window, whole seconds.
  final int recentSecs;

  /// The longest hold in the window before it, whole seconds.
  final int previousSecs;

  int get gainSecs => recentSecs - previousSecs;
}

/// The Hold Progress result for [sections], or null (D-17902).
HoldProgressResult? holdProgress(List<InstrumentSectionData> sections) {
  HoldProgressResult? best;
  for (final section in sections) {
    if (section.section != ExerciseSection.isometric) continue;
    for (final row in section.rows) {
      final previous = row.previousValue;
      if (previous == null) continue;
      if (row.summary.best.metric != NativeMetric.hold ||
          previous.metric != NativeMetric.hold) {
        continue;
      }
      if (row.summary.sessionCount < kHoldProgressMinSessions) continue;

      final recentSecs = row.summary.best.value.round();
      final previousSecs = previous.value.round();
      if (previousSecs <= 0) continue;
      final gain = recentSecs - previousSecs;
      if (gain < kHoldProgressMinGainSecs) continue;
      if (100 * gain < kHoldProgressMinGainPercent * previousSecs) continue;

      final candidate = HoldProgressResult(
        name: row.summary.name,
        exerciseId: row.summary.exerciseId,
        recentSecs: recentSecs,
        previousSecs: previousSecs,
      );
      if (best == null || _beats(candidate, best)) best = candidate;
    }
  }
  return best;
}

bool _beats(HoldProgressResult a, HoldProgressResult b) {
  if (a.gainSecs != b.gainSecs) return a.gainSecs > b.gainSecs;
  final byName = a.name.compareTo(b.name);
  if (byName != 0) return byName < 0;
  return a.exerciseId.compareTo(b.exerciseId) < 0;
}

/// The observation on the Hold Progress card (D-17903).
String holdProgressObservation(
  HoldProgressResult result, {
  required int weeks,
}) =>
    'Your longest hold on ${result.name} is up ${result.gainSecs} s over the '
    'last $weeks weeks, now ${result.recentSecs} s.';
```

`lib/core/services/signals/hold_progress_signal.dart` (new):

```dart
import '../../models/hold_progress.dart';
import '../../models/signals.dart';
import '../stats_progress_service.dart';
import 'signal.dart';

const String _kHoldProgressTitle = 'Hold progress';

/// Proposes the Hold Progress card, or abstains (D-17903).
class HoldProgressSignal implements Signal {
  const HoldProgressSignal();

  @override
  String get id => 'hold-progress';

  @override
  SignalKind get kind => SignalKind.positive;

  @override
  int get priority => kHoldProgressPriority;

  @override
  bool get needsRatedWeeks => false;

  @override
  Future<String?> waitingFor(SignalContext context) async => null;

  @override
  Future<SignalCard?> evaluate(SignalContext context) async {
    final sections = await context.progressService.computeInstrumentSections(
      window: context.window,
    );
    final result = holdProgress(sections);
    if (result == null) return null;
    return SignalCard(
      id: id,
      kind: kind,
      priority: priority,
      title: _kHoldProgressTitle,
      observation: holdProgressObservation(
        result,
        weeks: StatsProgressService.kStatsWindowDays ~/ 7,
      ),
    );
  }
}
```

`lib/core/services/signals/signal_registry.dart`: import it and add `HoldProgressSignal(),` directly after `ConsistencySignal(),` (ten entries).

## Scenarios

Rule tests use synthetic Instruments rows (`InstrumentRow`, `ExerciseMetricSummary`, `NativeValue` with the `hold` metric). The adapter test seeds real hold efforts with the shared helpers.
`Fails without the change` is proven by the lead's mutations (D-17905).

| Id | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-17901 | One isometric row `Deep Squat`: recent 60 s, previous 40 s, 3 sessions | a result: gain 20, recent 60, previous 40; the observation reads `Your longest hold on Deep Squat is up 20 s over the last 4 weeks, now 60 s.` | the rule does not exist |
| S-17902 | Gain thresholds, recent vs previous: 49 vs 40 (gain 9); 110 vs 100 (gain 10, exactly 10%); 111 vs 101 (gain 10, 9.9%) | null; a result; null | the gain floor (M1) and the percent floor (M2) |
| S-17903 | Sessions: 2 sessions with a big gain; 3 sessions | null; a result | the session floor (M3) |
| S-17904 | No previous value; a previous value on another metric; previous 0; recent below previous | each null | missing earlier window is not progress |
| S-17905 | An isometric-section row on the `duration` metric with a large gain; a resistance-section row with a large `estimatedOneRepMax` gain | both ignored: null | the metric check (M4) |
| S-17906 | Three qualifying rows with gains 15, 25, 25 (the two 25s named `Plank` and `Dead Hang`) | `Dead Hang` (the biggest gain, then the name ascending) | the pick (M5) |
| S-17907 | `holdProgressObservation` for a 15 s gain on `Dead Hang` now 75 s, 4 weeks | `Your longest hold on Dead Hang is up 15 s over the last 4 weeks, now 75 s.` | a copy sentence drifts from the shipped wording (new function; no mutation expected to differ) |
| S-17908 | Mock AND Hive repositories, real sessions: three sessions in the last four weeks with holds 50, 60 and 70 s on one exercise, two sessions 31 and 34 days ago with holds 40 and 45 s; a second fixture with only two sessions in the window | the card `hold-progress` (positive, `Hold progress`, no suggestion): `Your longest hold on Deep Squat is up 25 s over the last 4 weeks, now 70 s.`; null | the weeks in the copy (M6) |
| S-17909 | `buildSignalRegistry()` | the id-to-`needsRatedWeeks` map gains `hold-progress` false (ten entries); the modality test's registry list gains `hold-progress` after `consistency` | the registration (M7) |

## Phases

| Phase | Agent | Write scope | Items | Serial/parallel |
|---|---|---|---|---|
| P1 | crew-builder-app | the new `lib/core/models/hold_progress.dart`, `lib/core/services/signals/hold_progress_signal.dart`; `lib/core/services/signals/signal_registry.dart` | the exact edits above (3 items) | first |
| P2a | crew-builder-app | new `test/hold_progress_test.dart` | S-17901..S-17907 (exact text in the brief) | after P1; parallel |
| P2b | crew-builder-app | new `test/hold_progress_signal_test.dart`; `test/signals_service_test.dart`; `test/modality_mix_shift_signal_screen_test.dart` | S-17908, S-17909 | after P1; parallel |
| P3 | crew-docs-keeper | `docs/signals.md`, `docs/signals_registered.md`, `docs/stats_screen.md` | the Docs delta rows | after P2 |
| P4 | crew-reviewer | the plan's `.review.md` | five narrow questions | after P3 |

Done criteria: touched test files green with real counts; `flutter analyze` issue count not above the base count (181; 0 errors); full `flutter test` green apart from the known flaky red
(`routine_save_removes_deleted_rows_test.dart` S-R3); invariant grep clean; `ui_standards_contract_test.dart` and `docs_indexing_contract_test.dart` green; `plan-lint.py after` clean. Mutations: M1 `gain < kHoldProgressMinGainSecs` to `<=`;
M2 `100 * gain < kHoldProgressMinGainPercent * previousSecs` to `<=`; M3 `row.summary.sessionCount < kHoldProgressMinSessions` to `<=`; M4 drop `row.summary.best.metric != NativeMetric.hold ||`; M5 `_beats`'s `a.gainSecs > b.gainSecs` to `<`;
M6 `kStatsWindowDays ~/ 7` to `~/ 14`; M7 `HoldProgressSignal(),` removed from the registry; M8 drop the `section.section != ExerciseSection.isometric` filter.

## Docs delta

Markers are exact one-line phrases. `-` = none. The keeper also searches `docs/` (excluding plans, history, releases) for `nine`, `registered positives`, `Consistency` and reports any other hit that became false.
`docs/stats_screen.md` is at its size band (about 52.4 KB; the band is 52,428 bytes): the two paragraphs `The eighth is the Consistency ...` and `The ninth is the Training Gap ...` are REPLACED by the ONE paragraph given in the brief, which is shorter than the two together.

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| docs/signals.md | MODIFIED | Rate, whose priority is `kProgressionRatePriority`, and Consistency, whose | Hold Progress (`kHoldProgressPriority`) | S-17909 |
| docs/signals.md | MODIFIED | The nine registered signals — Training Gap, Progression Rate, Consistency, | The ten registered signals | S-17909 |
| docs/signals.md | MODIFIED | which pins the nine registered ids; by | which pins the ten registered ids; by | S-17909 |
| docs/signals_registered.md | MODIFIED | The nine registered signals' definitions and adapters | The ten registered signals' definitions and adapters | S-17909 |
| docs/signals_registered.md | ADDED | - | `holdProgress(List<InstrumentSectionData>` | S-17901 |
| docs/stats_screen.md | MODIFIED | lists nine, described here in the order they shipped | lists ten, described here in the order they shipped | S-17909 |
| docs/stats_screen.md | MODIFIED | The eighth is the Consistency: last week held more sessions than usual, a | The eighth to tenth are the Consistency | S-17908 |
| docs/stats_screen.md | REMOVED | The ninth is the Training Gap: five or more days without a session, longer | - | S-17908 |

## Progress

- [x] P1 production
- [x] P2a rule tests
- [x] P2b adapter and registry tests
- [x] Lead mutation pass M1-M8
- [x] P3 docs
- [x] `plan-lint after`
- [x] P4 review
- [x] Full suite, analyze, invariants
- [x] Commit (own files only)

## Assumption Log

- Independent review of 2026-11-03: Instruments computes the longest single hold (`_isometricValue`), not an average; the total hold time is a secondary figure; each row already shows the change against the previous four weeks
  (`previousValue`); Progression Rate walks `set` efforts only. Hence the card says "longest hold", requires 3 sessions and a gain big enough not to repeat every tiny wobble the row shows, and leaves cardio out.
- Defaults taken: cardio duration/pace not added (see Goal 3); thresholds 10 s and 10% and 3 sessions; one card at most (the biggest gain).
- Not run on a device or simulator.
- Lead mutation pass M1-M8: M4 (the best-metric check) and M8 (the section filter) first survived because the metric check and the section filter rejected the same fixtures. Closed by two tests-only additions by the lead: a row whose best is on `duration` while its previous is on `hold`, and a hold-metric row in the cardio section; both mutants are now killed. Review APPROVE, 0 findings.
- The reviewer confirmed from the code that a real isometric row never has `best` and `previousValue` on different metrics (`comparable` requires equal metrics), so the double metric check guards synthetic rows only; and that `sessionCount` is the window's count of completed sessions.
- Full suite `+6310 ~2 -1`: the one red is `routine_save_removes_deleted_rows_test.dart` S-R3 (flaky, red at the base of units 101, 102, 104, 105 and green in 103); analyze 181; invariant grep clean; contract tests `+54`. `docs/stats_screen.md` 52.3 KB after the merge of the two paragraphs (band 52,428 bytes).
- Not run on a device or simulator.
