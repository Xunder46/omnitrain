# 105 — Two signals that read the user's own training rhythm: Consistency and Training Gap

Status: SEEDED by the lead 2026-11-03 (no architect run: exact production code below; exact test text sits in the builder briefs).
Base commit: `.work/2026-11-03-105-consistency/base.txt`. Track: phone only (`lib/`, `test/`, `docs/`).
Unrelated dirty files, never touch: `lib/core/services/stats_progress_service.dart`, `test/stats_dst_day_arithmetic_test.dart` (another session's DST work).
Series: Stats Signals, group 3, review item 10 (Consistency). Unit 4 of 5. Owner 2026-11-03: "Yes to all", with the rule **the week ends on Sunday or Saturday by the
Start of Week setting** (Settings > Preferences > Start of Week: Mon = week ends Sunday, Sun = week ends Saturday). Commits pre-approved, take the defaults, report at the end.
The independent review of 2026-11-03 supplied the guards against the obvious false alarms (a partial week, a record gap that is only days long, too little history).

## Goal and acceptance

What a user sees after this PR, in the Signals block (they follow the existing card rules: at most two cards, one caution above one positive, dismissible for 14 days):

1. **Consistency (positive):** `Last week you logged 4 sessions, above your usual 2.5 a week over the last 8 weeks.` — shown when the last COMPLETED week held at least 3
   sessions and at least one more than the average of the completed weeks before and including it (up to 8 weeks). The current, still-running week is never counted
   (so Monday never reads as a bad week). Weeks follow the Start of Week setting (a Monday start ends the week on Sunday; a Sunday start ends it on Saturday).
2. **Training Gap (caution, worth a look):** `No session in 6 days, longer than any gap in your last 8 weeks (the longest was 3 days).` — shown when the last session was at least 5 days
   ago and that gap is longer than every gap between two session days in the last 56 days.
3. **Both stay silent until there is a rhythm to compare with:** at least 6 completed weeks of history (counted from the week of the first session); the gap card also needs at
   least 4 session days in the last 56 days. Neither reads ratings or the load measure, so both can speak before four rated weeks (`needsRatedWeeks` false).
4. A session still in progress is not a session; several sessions on one day count as separate sessions for Consistency and as one day for the gap.
5. Nothing else changes; the card cap and the waiting lines are as before. Neither signal has a waiting line.

Not in this PR: any hold or cardio duration trend (unit 106); a rest-week or holiday exemption (the card can be dismissed for 14 days); the three-day-streak rhythm of the Calendar.
Defaults taken (owner said take defaults): 6 weeks of history before either card speaks (not "week two": a partial pattern would cry wolf), a floor of 5 days for the gap, a floor of 3 sessions for Consistency,
completed weeks only, no suggestion line on either card (no coaching), the gap caution the lowest-priority caution and Consistency below Progression Rate.

## Decision Ledger

| Id | Decision | Where |
|---|---|---|
| D-17801 | Pure model `lib/core/models/consistency.dart` (imports `../utils/date_utils.dart` for `OmniDateUtils.startOfWeek`): constants `kConsistencyWeeks = 8`, `kConsistencyMinHistoryWeeks = 6`, `kConsistencyMinWeekSessions = 3`, `kTrainingGapWindowDays = 56`, `kTrainingGapMinDays = 5`, `kTrainingGapMinSessionDays = 4`, `kConsistencyPriority = 50`, `kTrainingGapPriority = 25`; `consistency(...)`, `trainingGap(...)` and their two copy functions. Weeks are counted from the week of the FIRST session to the current week, exclusive: `history = daysApart(firstWeekStart, currentWeekStart) ~/ 7`, with days counted on the dates re-read as UTC so a clock change never shortens a week | `consistency.dart` |
| D-17802 | `SignalContext` gains `final String startOfWeek` (named, default `'monday'`, the setting's own vocabulary `monday`/`sunday`). `SignalsService.evaluateCandidates` and `waitingLines` gain an optional `String startOfWeek = 'monday'` and put it into the context; `StatsScreen._load` passes `widget.settingsState.startOfWeek` to both | `signal.dart`, `signals_service.dart`, `stats_screen.dart` |
| D-17803 | New file `lib/core/services/signals/session_history.dart`: `Future<List<DateTime>> completedSessionStarts(SignalContext)` reads `repository.getSessionsByDateRange(0, now)` and keeps the start time of every session with `endedAtMs != null`. Both new signals read it (two reads of the session list per load, the cost the Mix layer's own full-history read already sets) | `session_history.dart` |
| D-17804 | Two registered signals (a signal has one fixed kind): `ConsistencySignal` (id `consistency`, positive, priority `kConsistencyPriority`) and `TrainingGapSignal` (id `training-gap`, caution, priority `kTrainingGapPriority`). Both `needsRatedWeeks` false, `waitingFor` null, no suggestion on the card. Registry order: `TrainingGapSignal` first (it is the lowest caution; the registry lists cautions in ascending priority), `ConsistencySignal` after `ProgressionRateSignal` | `consistency_signal.dart`, `training_gap_signal.dart`, `signal_registry.dart` |
| D-17805 | Tests that pin the registry change with it: `test/interference_test.dart` (`the caution order holds and the registry is ordered by it`: the list gains `training-gap` first) and `test/signals_service_test.dart` (`S-17503`: the map gains `training-gap` false and `consistency` false) | the two tests |
| D-17806 | Proof: the lead's mutation pass M1-M10; the new tests do not compile at the base, so `prove-red` at the base proves nothing | Assumption Log |

## Exact production code

### P1 — everything in `lib/`

`lib/core/models/consistency.dart` (new):

```dart
// The Consistency and Training Gap signals' rules (plan 105): how many sessions
// the last completed week held against the weeks before it, and how long it has
// been since the last session against the longest earlier gap. Pure Dart: `now`
// and the week's first day are parameters.

import '../utils/date_utils.dart';

/// The completed weeks the comparison reads, at most (D-17801).
const int kConsistencyWeeks = 8;

/// The completed weeks of history before either signal speaks (D-17801).
const int kConsistencyMinHistoryWeeks = 6;

/// The fewest sessions the last week holds for Consistency to speak.
const int kConsistencyMinWeekSessions = 3;

/// The span the Training Gap compares against: 56 local days ending today.
const int kTrainingGapWindowDays = kConsistencyWeeks * 7;

/// The fewest days since the last session for the gap to speak.
const int kTrainingGapMinDays = 5;

/// The fewest session days in the window before a gap means anything.
const int kTrainingGapMinSessionDays = 4;

/// Consistency ranks below Progression Rate among the positives.
const int kConsistencyPriority = 50;

/// The Training Gap is the lowest caution.
const int kTrainingGapPriority = 25;

DateTime _localDay(DateTime d) => DateTime(d.year, d.month, d.day);

/// Whole calendar days from [from] to [to], on the dates re-read as UTC so a
/// clock change inside the span never turns a day into 23 or 25 hours.
int _daysApart(DateTime from, DateTime to) =>
    DateTime.utc(to.year, to.month, to.day)
        .difference(DateTime.utc(from.year, from.month, from.day))
        .inDays;

/// Completed weeks from the week of the earliest of [days] up to the week that
/// starts at [currentWeekStart], that one excluded.
int _completedHistoryWeeks(
  Iterable<DateTime> days,
  DateTime currentWeekStart,
  String startOfWeek,
) {
  final first = days.reduce((a, b) => a.isBefore(b) ? a : b);
  final firstWeekStart = OmniDateUtils.startOfWeek(
    first,
    startOfWeek: startOfWeek,
  );
  return _daysApart(firstWeekStart, currentWeekStart) ~/ 7;
}

/// The last completed week against the weeks before it.
class ConsistencyResult {
  const ConsistencyResult({
    required this.lastWeekSessions,
    required this.weeks,
    required this.totalSessions,
  });

  /// Sessions in the last completed week.
  final int lastWeekSessions;

  /// Completed weeks averaged, the last one included.
  final int weeks;

  /// Sessions in those [weeks] weeks, the last week's included.
  final int totalSessions;

  double get average => totalSessions / weeks;
}

/// Consistency for [sessionStarts] at [now], or null (D-17801).
///
/// The weeks are the completed weeks (the running one is never counted)
/// starting on [startOfWeek] (`monday` or `sunday`). Speaks when at least
/// [kConsistencyMinHistoryWeeks] completed weeks of history exist and the last
/// week holds at least [kConsistencyMinWeekSessions] sessions and at least one
/// more than the average of the (up to [kConsistencyWeeks]) completed weeks.
ConsistencyResult? consistency({
  required List<DateTime> sessionStarts,
  required DateTime now,
  required String startOfWeek,
}) {
  if (sessionStarts.isEmpty) return null;
  final days = [for (final start in sessionStarts) _localDay(start)];
  final currentWeekStart = OmniDateUtils.startOfWeek(
    now,
    startOfWeek: startOfWeek,
  );
  final history = _completedHistoryWeeks(days, currentWeekStart, startOfWeek);
  if (history < kConsistencyMinHistoryWeeks) return null;

  final weeks = history < kConsistencyWeeks ? history : kConsistencyWeeks;
  final windowStart = DateTime(
    currentWeekStart.year,
    currentWeekStart.month,
    currentWeekStart.day - 7 * weeks,
  );
  final lastWeekStart = DateTime(
    currentWeekStart.year,
    currentWeekStart.month,
    currentWeekStart.day - 7,
  );
  var total = 0;
  var lastWeek = 0;
  for (final day in days) {
    if (day.isBefore(windowStart) || !day.isBefore(currentWeekStart)) continue;
    total++;
    if (!day.isBefore(lastWeekStart)) lastWeek++;
  }
  if (lastWeek < kConsistencyMinWeekSessions) return null;
  if (lastWeek * weeks < total + weeks) return null;
  return ConsistencyResult(
    lastWeekSessions: lastWeek,
    weeks: weeks,
    totalSessions: total,
  );
}

/// The time since the last session and the longest gap before it.
class TrainingGapResult {
  const TrainingGapResult({required this.days, required this.longestBefore});

  /// Days since the last session day.
  final int days;

  /// The longest gap between two session days in the window.
  final int longestBefore;
}

/// The Training Gap for [sessionStarts] at [now], or null (D-17801).
///
/// Speaks when at least [kConsistencyMinHistoryWeeks] completed weeks of
/// history exist, the last session day is at least [kTrainingGapMinDays] days
/// ago, the last [kTrainingGapWindowDays] days hold at least
/// [kTrainingGapMinSessionDays] session days, and the gap is longer than every
/// gap between two of those session days.
TrainingGapResult? trainingGap({
  required List<DateTime> sessionStarts,
  required DateTime now,
  required String startOfWeek,
}) {
  final today = _localDay(now);
  final days =
      {
        for (final start in sessionStarts) _localDay(start),
      }.where((day) => !day.isAfter(today)).toList()
        ..sort();
  if (days.isEmpty) return null;

  final currentWeekStart = OmniDateUtils.startOfWeek(
    today,
    startOfWeek: startOfWeek,
  );
  if (_completedHistoryWeeks(days, currentWeekStart, startOfWeek) <
      kConsistencyMinHistoryWeeks) {
    return null;
  }

  final gap = _daysApart(days.last, today);
  if (gap < kTrainingGapMinDays) return null;

  final windowStart = DateTime(
    today.year,
    today.month,
    today.day - kTrainingGapWindowDays,
  );
  final inWindow = days.where((day) => !day.isBefore(windowStart)).toList();
  if (inWindow.length < kTrainingGapMinSessionDays) return null;

  var longest = 0;
  for (var i = 1; i < inWindow.length; i++) {
    final apart = _daysApart(inWindow[i - 1], inWindow[i]);
    if (apart > longest) longest = apart;
  }
  if (gap <= longest) return null;
  return TrainingGapResult(days: gap, longestBefore: longest);
}

String _figure(double value) {
  final text = value.toStringAsFixed(1);
  return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
}

/// The observation on the Consistency card (D-17801).
String consistencyObservation(ConsistencyResult result) =>
    'Last week you logged ${result.lastWeekSessions} sessions, above your '
    'usual ${_figure(result.average)} a week over the last ${result.weeks} '
    'weeks.';

/// The observation on the Training Gap card (D-17801).
String trainingGapObservation(TrainingGapResult result) =>
    'No session in ${result.days} days, longer than any gap in your last '
    '$kConsistencyWeeks weeks (the longest was ${result.longestBefore} '
    '${result.longestBefore == 1 ? 'day' : 'days'}).';
```

`lib/core/services/signals/session_history.dart` (new):

```dart
import 'signal.dart';

/// The start of every completed session, oldest history included (D-17803).
///
/// A session still in progress has no end and is not a session yet.
Future<List<DateTime>> completedSessionStarts(SignalContext context) async {
  final sessions = await context.repository.getSessionsByDateRange(
    0,
    context.now.millisecondsSinceEpoch,
  );
  return [
    for (final session in sessions)
      if (session.endedAtMs != null)
        DateTime.fromMillisecondsSinceEpoch(session.startedAtMs),
  ];
}
```

`lib/core/services/signals/consistency_signal.dart` (new):

```dart
import '../../models/consistency.dart';
import '../../models/signals.dart';
import 'session_history.dart';
import 'signal.dart';

const String _kConsistencyTitle = 'Consistency';

/// Proposes the Consistency card, or abstains (D-17804).
class ConsistencySignal implements Signal {
  const ConsistencySignal();

  @override
  String get id => 'consistency';

  @override
  SignalKind get kind => SignalKind.positive;

  @override
  int get priority => kConsistencyPriority;

  @override
  bool get needsRatedWeeks => false;

  @override
  Future<String?> waitingFor(SignalContext context) async => null;

  @override
  Future<SignalCard?> evaluate(SignalContext context) async {
    final result = consistency(
      sessionStarts: await completedSessionStarts(context),
      now: context.now,
      startOfWeek: context.startOfWeek,
    );
    if (result == null) return null;
    return SignalCard(
      id: id,
      kind: kind,
      priority: priority,
      title: _kConsistencyTitle,
      observation: consistencyObservation(result),
    );
  }
}
```

`lib/core/services/signals/training_gap_signal.dart` (new): the same shape — class `TrainingGapSignal`, `id` `'training-gap'`, `kind` `SignalKind.caution`, `priority` `kTrainingGapPriority`, `needsRatedWeeks` false,
`waitingFor` null, title `'Training gap'`, `evaluate` calls `trainingGap(sessionStarts: ..., now: context.now, startOfWeek: context.startOfWeek)` and builds the card with `trainingGapObservation(result)`.

`lib/core/services/signals/signal_registry.dart`: import the two new signals and make the list

```dart
List<Signal> buildSignalRegistry() => const <Signal>[
  TrainingGapSignal(),
  CardioEfficiencyDriftSignal(),
  SustainedHighLoadSignal(),
  ProteinConsistencySignal(),
  FuelVsLoadSignal(),
  ProgressionRateSignal(),
  ConsistencySignal(),
  ModalityMixShiftSignal(),
  InterferenceSignal(),
];
```

`lib/core/services/signals/signal.dart`, in `SignalContext`: a field `final String startOfWeek;` with a doc line (`The Start of Week setting, \`monday\` or \`sunday\` (D-17802).`) and the constructor argument `this.startOfWeek = 'monday',` (the constructor stays `const`; the doc line "All five members are carried" becomes "All six").

`lib/core/services/signals_service.dart`: both `evaluateCandidates` and `waitingLines` gain `String startOfWeek = 'monday',` (named, optional) and pass `startOfWeek: startOfWeek,` to the `SignalContext(...)` they build.

`lib/features/stats/stats_screen.dart`: in `_load`, pass `startOfWeek: widget.settingsState.startOfWeek,` to `signalsService.evaluateCandidates(...)` and to `signalsService.waitingLines(...)`.

## Scenarios

Fixed dates in 2026, `now` = Wednesday 2026-03-18 12:00 local (Mondays: Mar 16, Mar 9, Mar 2, Feb 23, Feb 16, Feb 9, Feb 2, Jan 26, Jan 19). Sessions at noon. The lead re-derived every
number with a throwaway script (`scratchpad/consistency_check.py`). `Fails without the change` is proven by the lead's mutations (D-17806).

Fixture A (20 sessions in the 8 weeks W8..W1 with Monday weeks): W8 Jan 20, 21, 22, 23; W7 Jan 27, 29; W6 Feb 3, 5; W5 Feb 10, 12; W4 Feb 17, 19; W3 Feb 24, 26; W2 Mar 3, 5; W1 Mar 10, 11, 13, 15 (a Sunday).
Fixture G (22 session days, every 2 or 3 days, last Mar 12): Jan 19, 21, 24, 26, 29, 31, Feb 3, 5, 8, 10, 13, 15, 18, 20, 23, 25, 28, Mar 2, 5, 7, 10, 12.

| Id | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-17801 | A, Monday start | `consistency` returns last week 4, 8 weeks, 20 sessions, average 2.5; the observation reads `Last week you logged 4 sessions, above your usual 2.5 a week over the last 8 weeks.` | the rule does not exist |
| S-17802 | A, Sunday start | null: Sunday Mar 15 now opens the running week, the last completed week holds 3 of 19 over 8 weeks (3*8 = 24 < 27) | the week boundary ignored the setting (M3) |
| S-17803 | A plus sessions on Mar 16, 17 and 18 (the running week), Monday start | the same result as S-17801 | the running week was counted (M4) |
| S-17804 | A without every session before Feb 9 (5 completed weeks of history); A without every session before Feb 3 (exactly 6) | null; a result with weeks 6, total 14, last week 4 (average 2.3 as `2.3`) | the history floor (M1) |
| S-17805 | Eight weeks with W8 4, W7 4, W6 3, W5 3, W4 2, W3 2, W2 2, W1 4 (24 sessions: 4*8 = 32 = 24+8); the same plus one session in W2 (25) | a result with average 3 shown as `3`; null | the boundary is inclusive (M2) |
| S-17806 | W8..W2 one session each, W1 two (below the floor of 3) | null | the floor of 3 sessions |
| S-17807 | G: now Mar 18 (gap 6, longest earlier 3); Mar 17 (gap 5); Mar 16 (gap 4); G without Feb 20 with now Mar 17 (gap 5, longest 5) and Mar 18 (gap 6, longest 5); G without Feb 20..Feb 28 (an earlier 12-day gap); `[Jan 19, Jan 21, Mar 1, Mar 2]`; G from Feb 10 on (5 weeks of history); sessions only Jan 5..14 | fires (6, 3); fires (5, 3); null; null; fires (6, 5); null; null; null; null | the 5-day floor (M5), the strict comparison (M6), the window and the history floors |
| S-17808 | `trainingGapObservation` for (6, 3) and (6, 1); `consistencyObservation` with average 2.5 and 3 | `No session in 6 days, longer than any gap in your last 8 weeks (the longest was 3 days).`; `... (the longest was 1 day).`; `usual 2.5 a week`; `usual 3 a week` | a copy sentence drifts from the shipped wording (the copy functions are new; no mutation expected to differ) |
| S-17809 | `ConsistencySignal` and `TrainingGapSignal` `evaluate` on Mock AND Hive repositories with fixtures A and G as completed sessions; in-progress sessions added in the last week of the low fixture | the cards with ids `consistency` (positive, `Consistency`) and `training-gap` (caution, `Training gap`), no suggestion; Sunday start gives no Consistency card; in-progress sessions change nothing | the in-progress filter (M7) |
| S-17810 | `buildSignalRegistry()` | the id-to-`needsRatedWeeks` map gains `training-gap` false and `consistency` false (9 entries); the cautions in registry order start with `training-gap`; priorities ascending | registry/priority drift |
| S-17811 | `SignalsService` with a stub that records `context.startOfWeek` in `evaluate` and `waitingFor`; no argument, then `startOfWeek: 'sunday'` | `monday` by default; `sunday` in both methods when given | the service dropped the argument (M8) |
| S-17812 | Stats screen (Mock) with `settingsState.setStartOfWeek('sunday')` done in `setUp` and a recording stub | the stub saw `sunday` | the screen did not pass the setting (M9) |

## Phases

| Phase | Agent | Write scope | Items | Serial/parallel |
|---|---|---|---|---|
| P1 | crew-builder-app | the new `lib/core/models/consistency.dart`, `lib/core/services/signals/session_history.dart`, `consistency_signal.dart`, `training_gap_signal.dart`; `signal_registry.dart`, `signal.dart`, `lib/core/services/signals_service.dart`, `lib/features/stats/stats_screen.dart` | the exact edits above (8 items) | first |
| P2a | crew-builder-app | new `test/consistency_test.dart` | S-17801..S-17808 (exact text in the brief) | after P1; parallel |
| P2b | crew-builder-app | new `test/consistency_signal_test.dart`; `test/interference_test.dart`; `test/signals_service_test.dart` | S-17809, S-17810, S-17811 | after P1; parallel |
| P2c | crew-builder-app | `test/signals_layer_screen_test.dart` | S-17812 | after P1; parallel |
| P3 | crew-docs-keeper | `docs/signals.md`, `docs/signals_registered.md`, `docs/stats_screen.md`, `docs/theme_and_settings.md` | the Docs delta rows | after P2 |
| P4 | crew-reviewer | the plan's `.review.md` | five narrow questions | after P3 |

Done criteria: touched test files green with real counts; `flutter analyze` issue count not above the base count (181; 0 errors); full `flutter test` green apart from the known flaky red
(`routine_save_removes_deleted_rows_test.dart` S-R3); invariant grep clean; `ui_standards_contract_test.dart` and `docs_indexing_contract_test.dart` green; `plan-lint.py after` clean. Mutations: M1 `history < kConsistencyMinHistoryWeeks` to `<=`
in `consistency`; M2 `lastWeek * weeks < total + weeks` to `<=`; M3 `startOfWeek: startOfWeek,` replaced by `startOfWeek: 'monday',` in `consistency`'s `currentWeekStart` call; M4 `!day.isBefore(currentWeekStart)` to `day.isAfter(now)`;
M5 `gap < kTrainingGapMinDays` to `<=`; M6 `gap <= longest` to `gap < longest`; M7 the `if (session.endedAtMs != null)` filter removed; M8 `waitingLines` builds its context without `startOfWeek`; M9 the screen's `evaluateCandidates` call without `startOfWeek`;
M10 the registry without `TrainingGapSignal()` first (moved last).

## Docs delta

Markers are exact one-line phrases. `-` = none. The keeper also searches `docs/` (excluding plans, history, releases) for `Six cautions`, `seven`, `registered signals`, `Start of Week`, and reports any other hit that became false.
`docs/stats_screen.md` is about 51.9 KB: keep its additions to a few lines (the detail lives in `docs/signals_registered.md`).

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| docs/signals.md | MODIFIED | is a property of the signals. Six cautions are registered today, in ascending | Seven cautions are registered today, in ascending | S-17810 |
| docs/signals.md | MODIFIED | priority: Cardio Efficiency Drift (`kCardioEfficiencyDriftPriority`), Sustained | Training Gap (`kTrainingGapPriority`) | S-17810 |
| docs/signals.md | MODIFIED | (`kCrossModalityInterferencePriority`). The registered positive is Progression | The registered positives are Progression | S-17810 |
| docs/signals.md | MODIFIED | The seven registered signals — Progression Rate, Modality Mix Shift, | The nine registered signals | S-17810 |
| docs/signals.md | ADDED | - | `startOfWeek` | S-17811 |
| docs/signals_registered.md | MODIFIED | **Scope.** The seven registered signals' definitions and adapters, split out of | The nine registered signals' definitions and adapters | S-17810 |
| docs/signals_registered.md | ADDED | - | `consistency({required sessionStarts` | S-17801 |
| docs/signals_registered.md | ADDED | - | `trainingGap({required sessionStarts` | S-17807 |
| docs/stats_screen.md | MODIFIED | lists seven, described here in the order they shipped | lists nine, described here in the order they shipped | S-17810 |
| docs/stats_screen.md | ADDED | - | The eighth is the Consistency | S-17801 |
| docs/stats_screen.md | ADDED | - | The ninth is the Training Gap | S-17807 |
| docs/theme_and_settings.md | MODIFIED | - calendar display (`Start of Week`) | - calendar display and the weeks the Consistency signal counts (`Start of Week`) | S-17802 |

## Progress

- [x] P1 production
- [x] P2a rule tests
- [x] P2b adapter, registry and service tests
- [x] P2c screen test
- [x] Lead mutation pass M1-M10
- [x] P3 docs
- [x] `plan-lint after`
- [x] P4 review
- [x] Full suite, analyze, invariants
- [x] Commit (own files only)

## Assumption Log

- Independent review of 2026-11-03: a partial current week makes Monday read as a bad week (hence completed weeks only); "longest gap in 8 weeks" fires the moment the user passes their own record, which with
  little history is a 3-day gap (hence the 6-week history floor and the 5-day floor); rest weeks and holidays would trigger it (hence dismissal, no exemption); it competes with Progression Rate for the positive slot
  (hence a lower priority). The Calendar's streak is a different rhythm (consecutive days) and is not reused.
- Owner rule: the week ends on Sunday or Saturday by the Start of Week setting; `OmniDateUtils.startOfWeek(date, startOfWeek: 'monday'|'sunday')` is the existing helper, already used by the Mix layer.
- The signal id `training-gap` and the title `Training gap` are the lead's names; the card copy is the lead's default (no suggestion line).
- Not run on a device or simulator.
- Lead mutation pass M1-M10 all killed on the first run; the review then found M11 (the floor of three sessions removed) would survive, because the first low fixture is also rejected by the average rule. Fixed by the lead: a second fixture (W8..W3 one session each, W2 none, W1 two: 8 sessions in 8 weeks, 2*8 = 8+8) that clears the average alone, so only the floor rejects it; M11 is now killed (`consistency_test.dart` `S-17806` › `two sessions that clear the average alone are still not enough`).
- A reader of the registry the seed missed (D-17805 listed two): `test/modality_mix_shift_signal_screen_test.dart` (`the registry` › `lists exactly the nine shipped signals, in order`) pinned the seven-entry id list; the full suite found it. The lead updated it (nine ids, registry order). The lead also split the screen test's recorded start of week per call (`seenOnEvaluate`, `seenOnWaiting`) because one shared field let a dropped argument in one call hide behind the other (M9).
- Doc sizes: `docs/stats_screen.md` was cut back to 52.4 KB (the 80% band of the 64 KiB ceiling is 52,428 bytes; the two new paragraphs were shortened after the keeper's version crossed it); `docs/signals_registered.md` 44.9 KB; `docs/README.md` row and `docs/theme_and_settings.md` marker fixed by the lead.
- Not run on a device or simulator: a test cannot show how two cards read together on a phone, and the simulator look is off by default.
