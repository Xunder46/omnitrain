// The Mix layer (Stats PR 5b, Phase 1) — the screen half of 5a's data.
//
// Scenarios S-1601…S-1614 and S-1616 of
// `docs/plans/2026-10-02-05b-stats-pr5b-mix-screen-plan/`, on both repository
// implementations. Every figure asserted here is one 5a's `MixLayerData`
// supplies: the layer renders and computes nothing, so a fixture only has to
// give the service sessions, ratings and a window.
//
// The window is the fixture's hidden variable. The screen always describes
// the 28 calendar days ending today (`StatsProgressService.statsWindow`): a
// period no longer scopes it and no recency fallback names it. A fixture that
// needs rated sessions *outside* the window therefore puts them 29 or more
// days back. The rated weeks are the 12 seven-day blocks ending at the
// window's end day — today — so sessions up to 83 days back rate the count,
// current weeks included (D-17104); the usual bar's baseline is still the 12
// seven-day blocks before the window's first day.
//
// The harness is opened and seeded in `setUp` and never inside a `testWidgets`
// body: a widget test body runs under `FakeAsync`, where Hive's real file I/O
// never settles and the test hangs. S-1616 is the one exception — it seeds
// *after* a pump, inside `tester.runAsync`.

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/modality_colors.dart';
import 'package:omnitrain/core/constants/omni_theme.dart';
import 'package:omnitrain/core/models/exercise_metric.dart';
import 'package:omnitrain/core/models/stats_progress.dart';
import 'package:omnitrain/core/models/training_load.dart';
import 'package:omnitrain/core/services/stats_progress_service.dart';
import 'package:omnitrain/core/utils/date_utils.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/features/stats/stats_screen.dart';
import 'package:omnitrain/features/stats/widgets/instrument_list.dart';
import 'package:omnitrain/features/stats/widgets/mix_layer.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:omnitrain/widgets/chart/scrollable_trend_chart.dart';
import 'package:omnitrain/widgets/layout/omni_card_header.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/repository_harness.dart';

/// Tall enough that every block the scenarios address is laid out, so an
/// assertion on a widget's absence is never just an off-screen miss.
const Size _kTallViewport = Size(400, 2400);

/// S-1601's viewport: short enough that the Mix block sits above the fold of
/// everything the layer pushes down.
const Size _kFirstBlockViewport = Size(400, 1600);

/// The five section titles the removed legacy layout rendered (D-18705).
const List<String> _kLegacyTitles = <String>[
  'STRENGTH',
  'CARDIO',
  'ISOMETRIC',
  'SPORTS',
  'NUTRITION',
];

/// The substrings no string on the layer may carry (S-1614): nothing here is
/// estimated, nothing coaches and nothing counts calories or heart rate.
const List<String> _kForbiddenCopy = <String>[
  'est.',
  'should',
  'calories',
  'heart',
  'bpm',
];

// ─── structural guards (Phase 2) ────────────────────────────────────────────

/// Every section name `ExerciseSection.label` renders — the only vocabulary
/// either surface may name a modality with.
final Set<String> _kSectionLabels = <String>{
  for (final section in ExerciseSection.values) section.label,
};

/// The `ModalityColors` accent each section must draw in. The layer names its
/// own map (`MixLayerSection._sectionColors`); this one is written out so a
/// drift between the two — or a colour the layer invents — fails a test.
const Map<String, Color> _kSectionAccents = <String, Color>{
  'Resistance': ModalityColors.resistanceLifting,
  'Cardio': ModalityColors.cardioEndurance,
  'Isometric': ModalityColors.isometricStretching,
  'Sports': ModalityColors.sports,
};

/// The section each legend entry names, in the bar's order. A legend entry is
/// `'<label> <pct>%'` (D-925).
List<String> _legendSections() => [
  for (final entry in _textsUnder(find.byKey(const Key('mix_legend'))))
    entry.replaceFirst(RegExp(r' \d+%$'), ''),
];

/// The section each Instruments header names, in document order. The header
/// renders the uppercase label (D-18704), so the match is case-insensitive and
/// the canonical title-case label is returned.
List<String> _listSections() => [
  for (final text in _textsUnder(find.byType(InstrumentList)))
    for (final label in _kSectionLabels)
      if (label.toLowerCase() == text.toLowerCase()) label,
];

// ─── readers ────────────────────────────────────────────────────────────────

/// Every `Text` under [scope], in document order.
List<String> _textsUnder(Finder scope) {
  final texts = <String>[];
  for (final element
      in find
          .descendant(of: scope, matching: find.byType(Text), matchRoot: true)
          .evaluate()) {
    final data = (element.widget as Text).data;
    if (data != null) texts.add(data);
  }
  return texts;
}

/// Every `Text` on the screen, in document order.
List<String> _allTexts() {
  final texts = <String>[];
  for (final element in find.byType(Text).evaluate()) {
    final data = (element.widget as Text).data;
    if (data != null) texts.add(data);
  }
  return texts;
}

/// The accessibility label the `Semantics` keyed [key] carries.
String? _labelOf(WidgetTester tester, Key key) =>
    tester.widget<Semantics>(find.byKey(key)).properties.label;

/// The data of the `Text` keyed [key] (S-4005, S-4006).
String _textOf(WidgetTester tester, Key key) =>
    tester.widget<Text>(find.byKey(key)).data!;

/// The style colour the `Text` keyed [key] carries (S-4020).
Color? _textColorOf(WidgetTester tester, Key key) =>
    tester.widget<Text>(find.byKey(key)).style?.color;

/// The accessibility labels of every `Semantics` on the screen.
List<String> _semanticsLabels() {
  final labels = <String>[];
  for (final element
      in find
          .byWidgetPredicate((widget) => widget is Semantics)
          .evaluate()) {
    final label = (element.widget as Semantics).properties.label;
    if (label != null) labels.add(label);
  }
  return labels;
}

/// The colour of the segment keyed [key].
Color? _segmentColor(WidgetTester tester, Key key) =>
    tester.widget<Container>(find.byKey(key)).color;

/// The fill colour of the decoration on the box keyed [key] — the legend's
/// rounded dots (S-3203).
Color? _decorationColor(WidgetTester tester, Key key) {
  final decoration = tester.widget<Container>(find.byKey(key)).decoration;
  return decoration is BoxDecoration ? decoration.color : null;
}

/// The border of the strip column [i]'s own container.
Border? _columnBorder(WidgetTester tester, int i) {
  final container = tester.widget<Container>(find.byKey(Key('mix_week_$i')));
  final decoration = container.foregroundDecoration;
  return decoration is BoxDecoration ? decoration.border as Border? : null;
}

/// The usual bar's segment indices, left to right.
List<int> _usualIndices() {
  final indices = <int>[];
  for (final element
      in find
          .byWidgetPredicate(
            (widget) =>
                widget.key is ValueKey<String> &&
                (widget.key! as ValueKey<String>).value.startsWith(
                  'mix_usual_segment_',
                ),
          )
          .evaluate()) {
    final name = (element.widget.key! as ValueKey<String>).value;
    indices.add(int.parse(name.split('_').last));
  }
  return indices..sort();
}

/// The stack-segment indices the strip column [i] holds, bottom-most first.
List<int> _stackIndices(int i) {
  final indices = <int>[];
  for (final element
      in find
          .byWidgetPredicate(
            (widget) =>
                widget.key is ValueKey<String> &&
                (widget.key! as ValueKey<String>).value.startsWith(
                  'mix_week_${i}_segment_',
                ),
          )
          .evaluate()) {
    final name = (element.widget.key! as ValueKey<String>).value;
    indices.add(int.parse(name.split('_').last));
  }
  return indices..sort();
}

/// The strip index of the week holding [sessionStart], computed from the
/// public week-start helper rather than hard-coded (S-1608).
int _weekIndexOf(DateTime sessionStart, String startOfWeek) {
  final currentWeekStart = OmniDateUtils.startOfWeek(
    DateTime.now(),
    startOfWeek: startOfWeek,
  );
  final weekStarts = [
    for (var i = kMixStripWeeks - 1; i >= 0; i--)
      DateTime(
        currentWeekStart.year,
        currentWeekStart.month,
        currentWeekStart.day - i * 7,
      ),
  ];
  final target = OmniDateUtils.startOfWeek(
    sessionStart,
    startOfWeek: startOfWeek,
  );
  return weekStarts.indexWhere(
    (weekStart) =>
        weekStart.millisecondsSinceEpoch == target.millisecondsSinceEpoch,
  );
}

/// The oldest strip week's start day for [startOfWeek], derived from the same
/// week-start helper the service uses rather than hard-coded (S-4005).
DateTime _oldestWeekStart(String startOfWeek) {
  final currentWeekStart = OmniDateUtils.startOfWeek(
    DateTime.now(),
    startOfWeek: startOfWeek,
  );
  return DateTime(
    currentWeekStart.year,
    currentWeekStart.month,
    currentWeekStart.day - (kMixStripWeeks - 1) * 7,
  );
}

/// Every strip key in the tree (`mix_week*`), so an all-empty strip is
/// asserted as a whole rather than one key at a time (S-4006).
List<String> _stripKeys() {
  final keys = <String>[];
  for (final element
      in find
          .byWidgetPredicate(
            (widget) =>
                widget.key is ValueKey<String> &&
                (widget.key! as ValueKey<String>).value.startsWith('mix_week'),
          )
          .evaluate()) {
    keys.add((element.widget.key! as ValueKey<String>).value);
  }
  return keys;
}

// ─── fixtures ───────────────────────────────────────────────────────────────

/// Local midnight of the day [daysAgo] days back.
DateTime _day(int daysAgo) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day - daysAgo);
}

/// [daysAgo]'s day at [hour] o'clock, in epoch ms.
int _at(int daysAgo, int hour) {
  final day = _day(daysAgo);
  return DateTime(day.year, day.month, day.day, hour).millisecondsSinceEpoch;
}

/// One completed session with one segment. Written directly because the shared
/// `seedSession` cannot express a rating and marks a rolling session
/// unfinished.
Future<void> _seedSession(
  WorkoutRepository repo, {
  required String sessionId,
  required int startedAtMs,
  required int endedAtMs,
  int? rating,
  bool isRolling = false,
}) async {
  await repo.createSession(
    TrainingSession(
      id: sessionId,
      ownerUserId: 'user-1',
      startedAtMs: startedAtMs,
      endedAtMs: endedAtMs,
      sessionFeeling: rating,
      isRolling: isRolling,
      createdAtMs: startedAtMs,
      updatedAtMs: startedAtMs,
    ),
  );
  await repo.createSegment(
    SessionSegment(
      id: 'seg-$sessionId',
      sessionId: sessionId,
      orderIndex: 0,
      segmentType: 'workout',
      name: 'Main Workout',
      createdAtMs: startedAtMs,
      updatedAtMs: startedAtMs,
    ),
  );
}

/// A lifting-only session of [minutes]: every second of it is the session's
/// resistance remainder, so it needs no effort to be measured (D-905).
Future<void> _seedLifting(
  WorkoutRepository repo, {
  required String sessionId,
  required int daysAgo,
  int minutes = 60,
  int? rating,
  int hour = 9,
}) async {
  final start = _at(daysAgo, hour);
  await _seedSession(
    repo,
    sessionId: sessionId,
    startedAtMs: start,
    endedAtMs: start + minutes * 60000,
    rating: rating,
  );
}

/// A `set` effort on [sessionId] — the resistance row the Instruments list
/// shows, and the effort kind that measures nothing (D-902).
Future<void> _seedSetEffort(
  WorkoutRepository repo, {
  required String sessionId,
}) async {
  final exerciseId = 'ex-squat-$sessionId';
  await seedExercise(
    repo,
    id: exerciseId,
    name: 'Back Squat',
    capabilities: const ['load', 'reps'],
  );
  await seedSetEffort(
    repo,
    segmentId: 'seg-$sessionId',
    effortId: 'eff-$sessionId-set',
    exerciseId: exerciseId,
    entryCount: 3,
    hasExtraWeight: false,
    weightFactor: 100.0,
    repsBase: 5,
  );
}

/// A `timed` effort measuring [seconds] of cardio on [sessionId].
Future<void> _seedCardioEffort(
  WorkoutRepository repo, {
  required String sessionId,
  required int seconds,
}) async {
  final exerciseId = 'ex-cardio-$sessionId';
  await seedExercise(
    repo,
    id: exerciseId,
    name: 'Easy Run',
    capabilities: const ['time', 'distance'],
  );
  await seedHoldEffort(
    repo,
    segmentId: 'seg-$sessionId',
    effortId: 'eff-$sessionId-cardio',
    exerciseId: exerciseId,
    entryCount: 1,
    secondsPerEntry: seconds,
    effortKind: 'timed',
  );
}

/// A `drill` effort measuring [seconds] of isometric work on [sessionId].
Future<void> _seedIsometricEffort(
  WorkoutRepository repo, {
  required String sessionId,
  required int seconds,
}) async {
  final exerciseId = 'ex-hold-$sessionId';
  await seedExercise(
    repo,
    id: exerciseId,
    name: 'Plank',
    capabilities: const ['hold'],
  );
  await seedHoldEffort(
    repo,
    segmentId: 'seg-$sessionId',
    effortId: 'eff-$sessionId-isometric',
    exerciseId: exerciseId,
    entryCount: 1,
    secondsPerEntry: seconds,
  );
}

/// A `round` effort measuring [seconds] of sports work on [sessionId].
Future<void> _seedSportsEffort(
  WorkoutRepository repo, {
  required String sessionId,
  required int seconds,
}) async {
  final exerciseId = 'ex-round-$sessionId';
  await seedExercise(
    repo,
    id: exerciseId,
    name: 'BJJ Round',
    capabilities: const ['rounds'],
  );
  await seedRoundEffort(
    repo,
    segmentId: 'seg-$sessionId',
    effortId: 'eff-$sessionId-sports',
    exerciseId: exerciseId,
    rounds: [
      roundInstance('eff-$sessionId-sports', 0, durationSecs: seconds),
    ],
  );
}

/// A training period from [daysAgo] to the end of today, named [name].
///
/// The screen's window no longer reads periods (`statsWindow`), so a period
/// here is inert for the layer and the list; the fixtures keep one so the
/// window assertions prove the window is not named after it.
Future<void> _seedPeriod(
  WorkoutRepository repo, {
  required String name,
  required int daysAgo,
}) async {
  final start = _day(daysAgo);
  final now = DateTime.now();
  await repo.createPeriod(
    TrainingPeriod(
      id: 'period-1',
      ownerUserId: 'user-1',
      name: name,
      startDateMs: start.millisecondsSinceEpoch,
      endDateMs: DateTime(
        now.year,
        now.month,
        now.day,
        23,
        59,
        59,
        999,
      ).millisecondsSinceEpoch,
      focusModalities: const [],
      createdAtMs: start.millisecondsSinceEpoch,
      updatedAtMs: start.millisecondsSinceEpoch,
    ),
  );
}

/// Rated sessions [daysAgo] + [offset] days back, each [minutes] long and
/// rated [rating] — behind the window, so they fill the usual bar's baseline
/// blocks, and within 83 days of today they also count as rated weeks
/// (D-908, D-934, D-17104).
Future<void> _seedRatedBaseline(
  WorkoutRepository repo, {
  required int fromDay,
  List<int> offsets = const [80, 60, 40, 20],
  int minutes = 60,
  int rating = 4,
}) async {
  for (final offset in offsets) {
    await _seedLifting(
      repo,
      sessionId: 's-baseline-$offset',
      daysAgo: fromDay + offset,
      minutes: minutes,
      rating: rating,
    );
  }
}

/// The repository's food log, emptied: the Mock harness opens with
/// `SeedData.sampleConsumedFoods()` already written, the Hive harness empty.
Future<void> _clearConsumedFoods(WorkoutRepository repo) async {
  const farFutureMs = 4102444800000; // 2100-01-01
  for (final row in await repo.getConsumedFoodsInRange(0, farFutureMs)) {
    await repo.deleteConsumedFood(row.id);
  }
}

/// One logged `ConsumedFood` on the local day [daysAgo] days back, so the Fuel
/// row renders below the Instruments list.
Future<void> _seedFood(
  WorkoutRepository repo, {
  required String id,
  required int daysAgo,
  double protein = 100,
  double carbs = 400,
}) async {
  final day = _day(daysAgo);
  final dateMs = day.millisecondsSinceEpoch;
  await repo.createConsumedFood(
    ConsumedFood(
      id: id,
      loggedAtMs: dateMs + (12 * 60 * 60 * 1000),
      dateMs: dateMs,
      sourceFoodId: id,
      name: id,
      unitType: FoodUnitType.grams,
      referenceAmount: 100,
      referenceLabel: '100 g',
      protein: protein,
      carbs: carbs,
      fiber: 0,
      fat: 0,
      sodium: null,
      amountConsumed: 100,
      groupIdSnapshot: 'food-group-proteins',
      groupNameSnapshot: 'Proteins',
      targetCalories: 0,
      targetProtein: 0,
      targetCarbs: 0,
      targetFat: 0,
      createdAtMs: dateMs,
      updatedAtMs: dateMs,
    ),
  );
}

/// FX-TIME (S-1602, S-1603's twin, S-1604, S-1605's window, S-1607-A): one
/// unrated 75-minute session on day 3 — a lifting set effort and a 15-minute
/// timed warm-up, so the window reads 80% resistance, 20% cardio by time.
///
/// No baseline session at all, and nothing rates any week.
Future<void> _seedTimeWindow(WorkoutRepository repo) async {
  final start = _at(3, 9);
  await _seedSession(
    repo,
    sessionId: 's-time',
    startedAtMs: start,
    endedAtMs: start + 75 * 60000,
  );
  await _seedSetEffort(repo, sessionId: 's-time');
  await _seedCardioEffort(repo, sessionId: 's-time', seconds: 900);
}

/// FX-BASELINE3 (S-1605, S-1607-A's twin): the 28-day window holding
/// FX-TIME's unrated session, with 3 rated weeks behind it — time measure, the
/// note, no usual bar.
///
/// The offsets put the rated sessions 80, 60 and 40 days back: rated blocks
/// `11 − ⌊d / 7⌋` = 0, 3 and 6 — three distinct blocks of the 12 ending today,
/// so the note reads 3 of 4 (D-17104). The old offsets put them 90, 70 and 50
/// days back, and 90 is outside the 12 blocks, which left only 2 weeks.
Future<void> _seedThreeRatedWeeks(WorkoutRepository repo) async {
  await _seedPeriod(repo, name: 'Test Block', daysAgo: 10);
  await _seedRatedBaseline(repo, fromDay: 10, offsets: const [70, 50, 30]);
  final start = _at(3, 9);
  await _seedSession(
    repo,
    sessionId: 's-time',
    startedAtMs: start,
    endedAtMs: start + 75 * 60000,
  );
  await _seedSetEffort(repo, sessionId: 's-time');
  await _seedCardioEffort(repo, sessionId: 's-time', seconds: 900);
}

/// FX-LOAD (S-1601, S-1603, S-1606, S-1607-C, S-1612, S-1616): the 28-day
/// window holding one rated 60-minute lifting session, 4 rated weeks of
/// baseline, and two logged food days so the Fuel row is below the layer.
Future<void> _seedLoadReady(WorkoutRepository repo) async {
  await _seedPeriod(repo, name: 'Test Block', daysAgo: 10);
  await _seedRatedBaseline(repo, fromDay: 10);
  await _seedLifting(
    repo,
    sessionId: 's-window',
    daysAgo: 3,
    minutes: 60,
    rating: 4,
  );
  await _seedSetEffort(repo, sessionId: 's-window');
  await _clearConsumedFoods(repo);
  await _seedFood(repo, id: 'food-1', daysAgo: 1);
  await _seedFood(repo, id: 'food-2', daysAgo: 2);
}

/// FX-LOAD3 (S-1611): FX-LOAD's baseline with three lifting sessions in the
/// window — two rated 60-minute ones and one unrated 10-minute one, so the
/// unrated share stays under the boundary and the measure stays load.
Future<void> _seedLiftingOnlyWindow(WorkoutRepository repo) async {
  await _seedPeriod(repo, name: 'Test Block', daysAgo: 10);
  await _seedRatedBaseline(repo, fromDay: 10);
  await _seedLifting(repo, sessionId: 's-a', daysAgo: 2, rating: 4);
  await _seedLifting(repo, sessionId: 's-b', daysAgo: 4, rating: 3);
  await _seedLifting(repo, sessionId: 's-c', daysAgo: 6, minutes: 10);
}

/// FX-UNRATED (S-18601): the rated baseline (4 rated weeks) with a window
/// holding one rated 30-minute session and one unrated 60-minute one, so the
/// unrated share is 60/90 = 66%, over the 25% boundary — the measure stays
/// time while the rated weeks already meet the threshold.
Future<void> _seedUnratedWindow(WorkoutRepository repo) async {
  await _seedPeriod(repo, name: 'Test Block', daysAgo: 10);
  await _seedRatedBaseline(repo, fromDay: 10);
  await _seedLifting(
    repo,
    sessionId: 's-r',
    daysAgo: 3,
    minutes: 30,
    rating: 4,
  );
  await _seedLifting(repo, sessionId: 's-u', daysAgo: 5, minutes: 60);
}

/// FX-EDGE (S-18602): the rated baseline (4 rated weeks) with a window holding
/// one rated 45-minute session and one unrated 15-minute one, so the unrated
/// share is 15/60 = exactly 25% — on the inclusive boundary, so the measure is
/// load and no baseline note renders.
Future<void> _seedEdgeShareWindow(WorkoutRepository repo) async {
  await _seedPeriod(repo, name: 'Test Block', daysAgo: 10);
  await _seedRatedBaseline(repo, fromDay: 10);
  await _seedLifting(
    repo,
    sessionId: 's-r',
    daysAgo: 3,
    minutes: 45,
    rating: 4,
  );
  await _seedLifting(repo, sessionId: 's-u', daysAgo: 5, minutes: 15);
}

/// FX-STRIP (S-1608, S-1609-A): no baseline, so the strip's weeks are the whole
/// story — a lifting-only session in the current week, a lifting + cardio
/// session a week back, and a lifting-only session a month back.
Future<void> _seedStrip(WorkoutRepository repo) async {
  final now = DateTime.now().millisecondsSinceEpoch;
  await _seedSession(
    repo,
    sessionId: 's-now',
    startedAtMs: now,
    endedAtMs: now + 3600000,
  );

  final mixedStart = _at(7, 9);
  await _seedSession(
    repo,
    sessionId: 's-mixed',
    startedAtMs: mixedStart,
    endedAtMs: mixedStart + 75 * 60000,
  );
  await _seedSetEffort(repo, sessionId: 's-mixed');
  await _seedCardioEffort(repo, sessionId: 's-mixed', seconds: 900);

  await _seedLifting(repo, sessionId: 's-month', daysAgo: 30);
}

/// S-1609-B's fixture: a rated window in a load-ready baseline — a rated
/// session today and one a week back.
Future<void> _seedRatedStrip(WorkoutRepository repo) async {
  await _seedPeriod(repo, name: 'Test Block', daysAgo: 10);
  await _seedRatedBaseline(repo, fromDay: 10);
  final now = DateTime.now().millisecondsSinceEpoch;
  await _seedSession(
    repo,
    sessionId: 's-now',
    startedAtMs: now,
    endedAtMs: now + 3600000,
    rating: 4,
  );
  await _seedLifting(repo, sessionId: 's-week', daysAgo: 7, rating: 3);
}

/// S-1613's fixture: a period holding three sessions — two lifting, one cardio
/// — and an isometric session 30 days back, outside the 28-day window the
/// screen always reads.
Future<void> _seedPeriodWindow(WorkoutRepository repo) async {
  await _seedPeriod(repo, name: 'Test Block', daysAgo: 10);
  await _seedLifting(repo, sessionId: 's-p1', daysAgo: 2);
  await _seedLifting(repo, sessionId: 's-p2', daysAgo: 4);

  final cardioStart = _at(6, 9);
  await _seedSession(
    repo,
    sessionId: 's-p3',
    startedAtMs: cardioStart,
    endedAtMs: cardioStart + 60 * 60000,
  );
  await _seedCardioEffort(repo, sessionId: 's-p3', seconds: 3600);

  final outsideStart = _at(30, 9);
  await _seedSession(
    repo,
    sessionId: 's-outside',
    startedAtMs: outsideStart,
    endedAtMs: outsideStart + 60 * 60000,
  );
  await _seedIsometricEffort(repo, sessionId: 's-outside', seconds: 900);
}

/// S-1614's fixture: one session holding all four modalities — a set effort,
/// and 15 measured minutes each of cardio, isometric and sports work.
Future<void> _seedEveryModality(WorkoutRepository repo) async {
  final start = _at(3, 9);
  await _seedSession(
    repo,
    sessionId: 's-all',
    startedAtMs: start,
    endedAtMs: start + 75 * 60000,
  );
  await _seedSetEffort(repo, sessionId: 's-all');
  await _seedCardioEffort(repo, sessionId: 's-all', seconds: 900);
  await _seedIsometricEffort(repo, sessionId: 's-all', seconds: 900);
  await _seedSportsEffort(repo, sessionId: 's-all', seconds: 900);
}

/// S-1610-B's fixture: a completed rolling session holding only set efforts, so
/// the window has no measurable time at all.
Future<void> _seedRollingSets(WorkoutRepository repo) async {
  final start = _at(1, 9);
  await _seedSession(
    repo,
    sessionId: 's-rolling',
    startedAtMs: start,
    endedAtMs: start + 3600000,
    isRolling: true,
  );
  await _seedSetEffort(repo, sessionId: 's-rolling');
}

/// S-1615's fixture: the densest layer the screen can draw — the 28-day
/// window holding a rated session with all four modalities, a rated baseline
/// behind it (so the measure is load and the usual bar renders), and an
/// unrated session in the window (so the unrated line renders too).
Future<void> _seedDensest(WorkoutRepository repo) async {
  await _seedPeriod(repo, name: 'Test Block', daysAgo: 10);
  await _seedRatedBaseline(repo, fromDay: 10);

  final start = _at(3, 9);
  await _seedSession(
    repo,
    sessionId: 's-dense',
    startedAtMs: start,
    endedAtMs: start + 75 * 60000,
    rating: 4,
  );
  await _seedSetEffort(repo, sessionId: 's-dense');
  await _seedCardioEffort(repo, sessionId: 's-dense', seconds: 900);
  await _seedIsometricEffort(repo, sessionId: 's-dense', seconds: 900);
  await _seedSportsEffort(repo, sessionId: 's-dense', seconds: 900);

  await _seedLifting(repo, sessionId: 's-dense-unrated', daysAgo: 5, minutes: 5);
}

/// S-4006's fixture: the screenshot's shape — two completed sessions two months
/// back and nothing inside the window's 28 days, so the window is empty and
/// the card is the one-line empty-window card.
///
/// The offsets are constants, not `now`-derived: the strip's oldest week
/// starts between 49 and 55 days back (49 + up to 6 days into the week, either
/// start-of-week convention), so anything 57 or more days back is outside the
/// strip on every run day — and outside the 28-day window on every run day.
Future<void> _seedStriplessHistory(WorkoutRepository repo) async {
  await _seedLifting(repo, sessionId: 's-old-a', daysAgo: 60);
  await _seedLifting(repo, sessionId: 's-old-b', daysAgo: 57);
}

/// S-4015's fixture: `_seedStriplessHistory` plus an unfinished session today.
///
/// Nothing qualifies the window — the period no longer plays any part — and
/// the unfinished one is excluded from every payload (D-911), so it must name
/// neither the empty line nor `lastSessionDay`.
Future<void> _seedStriplessHistoryWithUnfinished(
  WorkoutRepository repo,
) async {
  await _seedPeriod(repo, name: 'Test Block', daysAgo: 10);
  await _seedStriplessHistory(repo);
  await _seedUnfinished(repo, sessionId: 's-today-unfinished', daysAgo: 0);
}

/// One session with no end: the shape `_seedSession` cannot write, and the
/// shape every payload excludes (D-911).
Future<void> _seedUnfinished(
  WorkoutRepository repo, {
  required String sessionId,
  required int daysAgo,
  int hour = 8,
}) async {
  final start = _at(daysAgo, hour);
  await repo.createSession(
    TrainingSession(
      id: sessionId,
      ownerUserId: 'user-1',
      startedAtMs: start,
      endedAtMs: null,
      createdAtMs: start,
      updatedAtMs: start,
    ),
  );
}

/// S-4014's fixture: one completed session in each of the eight strip weeks, so
/// the caption's two ends are both a real week whatever the week starts on.
Future<void> _seedEveryStripWeek(WorkoutRepository repo) async {
  for (var i = 0; i < kMixStripWeeks; i++) {
    await _seedLifting(
      repo,
      sessionId: 's-week-$i',
      daysAgo: (kMixStripWeeks - 1 - i) * 7,
      hour: 0,
    );
  }
}

void main() {
  for (final factory in harnessFactories) {
    final harness = factory();

    group('Mix layer — ${harness.name}', () {
      late WorkoutRepository repo;
      late WorkoutState workoutState;
      late SettingsState settingsState;

      setUp(() async {
        repo = await harness.open();
        workoutState = WorkoutState(repo);
        settingsState = SettingsState(repo, fakePreferencesService());
        await settingsState.initialize();
      });

      tearDown(() async {
        await harness.close();
      });

      Future<void> pumpStats(
        WidgetTester tester, {
        Size size = _kTallViewport,
        double textScale = 1.0,
      }) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
            child: MaterialApp(
              home: StatsScreen(
                workoutState: workoutState,
                settingsState: settingsState,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      // ─── S-1601 ──────────────────────────────────────────────────────────

      group('S-1601 the layer is the first block', () {
        setUp(() => _seedLoadReady(repo));

        testWidgets('the Mix block sits above the list and the Fuel row, and '
            'there is exactly one of it', (tester) async {
          await pumpStats(tester, size: _kFirstBlockViewport);

          expect(find.byKey(const Key('mix_layer')), findsOneWidget);
          expect(find.text('TRAINING MIX'), findsOneWidget);

          final mixTop = tester.getTopLeft(find.byKey(const Key('mix_layer'))).dy;
          final listTop = tester
              .getTopLeft(find.byKey(const Key('instrument_caption')))
              .dy;
          final fuelTop = tester.getTopLeft(find.byKey(const Key('fuel_row'))).dy;

          expect(mixTop, lessThan(listTop));
          expect(listTop, lessThan(fuelTop));

          // The first card header in the body is the layer's.
          expect(
            _textsUnder(find.byType(Text)).firstWhere(
              (text) => text == 'TRAINING MIX' || text == 'ALL TIME',
            ),
            'TRAINING MIX',
          );
          expect(tester.takeException(), isNull);
        });
      });

      // ─── S-1602 ──────────────────────────────────────────────────────────

      group('S-1602 the bar splits by modality, largest first', () {
        setUp(() => _seedTimeWindow(repo));

        testWidgets('two segments, resistance four times cardio, with the '
            'legend reading the rounded shares', (tester) async {
          await pumpStats(tester);

          expect(find.byKey(const Key('mix_bar_segment_0')), findsOneWidget);
          expect(find.byKey(const Key('mix_bar_segment_1')), findsOneWidget);
          expect(find.byKey(const Key('mix_bar_segment_2')), findsNothing);

          final resistance = tester.getSize(
            find.byKey(const Key('mix_bar_segment_0')),
          );
          final cardio = tester.getSize(
            find.byKey(const Key('mix_bar_segment_1')),
          );
          expect(resistance.width / cardio.width, closeTo(4.0, 0.5));

          expect(
            _segmentColor(tester, const Key('mix_bar_segment_0')),
            ModalityColors.resistanceLifting,
          );
          expect(
            _segmentColor(tester, const Key('mix_bar_segment_1')),
            ModalityColors.cardioEndurance,
          );

          expect(_textsUnder(find.byKey(const Key('mix_legend'))), [
            'Resistance 80%',
            'Cardio 20%',
          ]);
          expect(tester.takeException(), isNull);
        });
      });

      // ─── S-1603 ──────────────────────────────────────────────────────────

      group('S-1603 the measure is stated once per block, and no chip', () {
        setUp(() => _seedLoadReady(repo));

        testWidgets('the explainer states the load measure above the bar and '
            'the strip title above the columns, and neither old word survives',
            (tester) async {
          await pumpStats(tester);

          expect(
            _textOf(tester, const Key('mix_explainer')),
            'Last 4 weeks. Your training split by how hard each session felt.',
          );
          expect(
            _textOf(tester, const Key('mix_strip_title')),
            'Last $kMixStripWeeks weeks, week by week',
          );
          final layerTexts = _textsUnder(find.byKey(const Key('mix_layer')));
          for (final gone in const ['by load', 'by time', 'usual']) {
            expect(layerTexts, isNot(contains(gone)), reason: gone);
          }

          final barTop = tester.getTopLeft(find.byKey(const Key('mix_bar'))).dy;
          final stripTop = tester
              .getTopLeft(find.byKey(const Key('mix_week_0')))
              .dy;
          final explainerTop = tester
              .getTopLeft(find.byKey(const Key('mix_explainer')))
              .dy;
          final titleTop = tester
              .getTopLeft(find.byKey(const Key('mix_strip_title')))
              .dy;
          expect(explainerTop, lessThan(barTop));
          expect(titleTop, lessThan(stripTop));
          expect(titleTop, greaterThan(barTop));

          expect(find.byKey(const Key('stats_window_chip')), findsNothing);
          expect(tester.takeException(), isNull);
        });
      });

      group('S-1603 the twin: an unrated, baseline-less window', () {
        setUp(() => _seedTimeWindow(repo));

        testWidgets('states the time measure and never the load one',
            (tester) async {
          await pumpStats(tester);

          expect(
            _textOf(tester, const Key('mix_explainer')),
            'Last 4 weeks. Your training split by time spent.',
          );
          expect(find.text('by load'), findsNothing);
          expect(find.text('by time'), findsNothing);
        });
      });

      // ─── S-1604 ──────────────────────────────────────────────────────────

      group('S-1604 the legend never renders a bare modality name', () {
        setUp(() => _seedTimeWindow(repo));

        testWidgets('a modality name is found once — the Instruments header — '
            'and the legend only as its full string', (tester) async {
          await pumpStats(tester);

          expect(find.text('RESISTANCE'), findsOneWidget);
          expect(find.text('CARDIO'), findsOneWidget);
          expect(find.text('Resistance 80%'), findsOneWidget);
          expect(find.text('Cardio 20%'), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      });

      // ─── S-1605 ──────────────────────────────────────────────────────────

      group('S-1605 no ratings — time measure, the note, no usual bar', () {
        setUp(() => _seedThreeRatedWeeks(repo));

        testWidgets('the note counts the rated weeks and the usual bar is '
            'absent', (tester) async {
          await pumpStats(tester);

          expect(
            _textOf(tester, const Key('mix_baseline_note')),
            'Showing time for now. Effort appears once '
            '$kTrainingLoadMinRatedWeeks weeks are rated '
            '(3 of $kTrainingLoadMinRatedWeeks so far).',
          );
          expect(find.byKey(const Key('mix_usual_bar')), findsNothing);
          expect(find.text('usual'), findsNothing);
          expect(find.text('Your usual'), findsNothing);
          expect(
            _semanticsLabels().where(
              (label) => label.startsWith('Usual split:'),
            ),
            isEmpty,
          );
          expect(tester.takeException(), isNull);
        });

        testWidgets('the baseline note caps to two lines and ellipsizes',
            (tester) async {
          await pumpStats(tester);

          final text =
              tester.widget<Text>(find.byKey(const Key('mix_baseline_note')));
          expect(text.maxLines, 2, reason: 'D-3204: the note caps to two lines');
          expect(
            text.overflow,
            TextOverflow.ellipsis,
            reason: 'D-3204: the note ellipsizes',
          );
          expect(tester.takeException(), isNull);
        });
      });

      // ─── S-1606 ──────────────────────────────────────────────────────────

      group('S-1606 load ready — load measure, the usual bar, no note', () {
        setUp(() => _seedLoadReady(repo));

        testWidgets('the usual bar sits directly under the bar at the same '
            'width, labelled and read out', (tester) async {
          await pumpStats(tester);

          expect(
            _textOf(tester, const Key('mix_explainer')),
            'Last 4 weeks. Your training split by how hard each session felt.',
          );
          expect(find.byKey(const Key('mix_usual_bar')), findsOneWidget);
          expect(_textOf(tester, const Key('mix_usual_label')), 'Your usual');
          expect(
            _labelOf(tester, const Key('mix_usual_bar')),
            'Usual split: Resistance 100%',
          );
          expect(find.byKey(const Key('mix_usual_segment_0')), findsOneWidget);
          expect(
            _segmentColor(tester, const Key('mix_usual_segment_0')),
            ModalityColors.resistanceLifting,
          );

          final bar = tester.getRect(find.byKey(const Key('mix_bar')));
          final usual = tester.getRect(find.byKey(const Key('mix_usual_bar')));
          expect(usual.width, bar.width);
          expect(usual.top, greaterThan(bar.bottom));
          expect(usual.top - bar.bottom, lessThan(40));

          expect(find.byKey(const Key('mix_baseline_note')), findsNothing);
          expect(tester.takeException(), isNull);
        });
      });

      group('S-1606 the twin: an unrated window', () {
        setUp(() => _seedTimeWindow(repo));

        testWidgets('draws no usual bar', (tester) async {
          await pumpStats(tester);

          expect(find.byKey(const Key('mix_usual_bar')), findsNothing);
          expect(find.text('usual'), findsNothing);
          expect(find.text('Your usual'), findsNothing);
        });
      });

      // ─── S-1607 ──────────────────────────────────────────────────────────
      //
      // The unrated line is gone (D-17305); S-17309 in
      // test/stats_mix_horizon_screen_test.dart covers its removal. The
      // remaining test keeps the absence claim.

      group('S-1607 the unrated count in words, or absent', () {
        setUp(() => _seedLoadReady(repo));

        testWidgets('reads nowhere', (tester) async {
          await pumpStats(tester);

          expect(find.byKey(const Key('mix_unrated_note')), findsNothing);
          expect(
            _allTexts().where((text) => text.contains('effort rating')),
            isEmpty,
          );
        });
      });

      // ─── S-1608 ──────────────────────────────────────────────────────────

      group('S-1608 the strip is 8 stacked columns with the current one marked',
          () {
        setUp(() => _seedStrip(repo));

        testWidgets('every column is addressable, the last is the current one, '
            'and the weeks stack by modality', (tester) async {
          await pumpStats(tester);

          for (var i = 0; i < kMixStripWeeks; i++) {
            expect(find.byKey(Key('mix_week_$i')), findsOneWidget);
          }
          expect(find.byKey(const Key('mix_week_current')), findsOneWidget);
          expect(
            find.ancestor(
              of: find.byKey(const Key('mix_week_7')),
              matching: find.byKey(const Key('mix_week_current')),
            ),
            findsOneWidget,
          );
          expect(
            tester.getRect(find.byKey(const Key('mix_week_current'))),
            tester.getRect(find.byKey(const Key('mix_week_7'))),
          );

          final muted = OmniTheme.colorsForTheme(
            settingsState.appTheme,
          ).textMuted;
          final currentBorder = _columnBorder(tester, 7);
          expect(currentBorder, isNotNull);
          expect(currentBorder!.top.color, muted);
          for (var i = 0; i < kMixStripWeeks - 1; i++) {
            expect(_columnBorder(tester, i), isNull, reason: 'column $i');
          }

          // The current column is named and marked in progress.
          final currentLabel = _labelOf(
            tester,
            const Key('mix_week_7_semantics'),
          );
          expect(currentLabel, endsWith(' (in progress)'));
          for (var i = 0; i < kMixStripWeeks - 1; i++) {
            expect(
              _labelOf(tester, Key('mix_week_${i}_semantics')),
              isNot(endsWith(' (in progress)')),
              reason: 'column $i',
            );
          }

          // The two-modality week stacks resistance under cardio.
          final mixedIndex = _weekIndexOf(
            _day(7),
            settingsState.startOfWeek,
          );
          expect(mixedIndex, isNot(7));
          expect(_stackIndices(mixedIndex), [0, 1]);
          expect(
            _segmentColor(
              tester,
              Key('mix_week_${mixedIndex}_segment_0'),
            ),
            ModalityColors.resistanceLifting,
          );
          expect(
            _segmentColor(
              tester,
              Key('mix_week_${mixedIndex}_segment_1'),
            ),
            ModalityColors.cardioEndurance,
          );
          final resistanceStack = tester.getSize(
            find.byKey(Key('mix_week_${mixedIndex}_segment_0')),
          );
          final cardioStack = tester.getSize(
            find.byKey(Key('mix_week_${mixedIndex}_segment_1')),
          );
          expect(
            resistanceStack.height / cardioStack.height,
            closeTo(4.0, 0.2),
          );

          // The lifting-only weeks hold one segment each, and every column
          // that holds work is no taller than the strip.
          for (final index in [
            7,
            _weekIndexOf(_day(30), settingsState.startOfWeek),
          ]) {
            expect(_stackIndices(index), [0], reason: 'column $index');
            expect(
              _segmentColor(tester, Key('mix_week_${index}_segment_0')),
              ModalityColors.resistanceLifting,
            );
          }
          final emptyIndices = [
            for (var i = 0; i < kMixStripWeeks; i++)
              if (![7, mixedIndex, _weekIndexOf(_day(30), settingsState.startOfWeek)]
                  .contains(i))
                i,
          ];
          for (final index in emptyIndices) {
            expect(_stackIndices(index), isEmpty, reason: 'column $index');
            expect(
              tester.getSize(find.byKey(Key('mix_week_$index'))).height,
              greaterThan(0),
            );
          }
          expect(tester.takeException(), isNull);
        });
      });

      // ─── S-1609 ──────────────────────────────────────────────────────────

      group('S-1609 / S-3207 the strip’s figures are the measure the explainer '
          'states', () {
        setUp(() => _seedStrip(repo));

        testWidgets('the time explainer names minutes per week', (tester) async {
          await pumpStats(tester);

          expect(
            _textOf(tester, const Key('mix_explainer')),
            'Last 4 weeks. Your training split by time spent.',
          );
          for (var i = 0; i < kMixStripWeeks - 1; i++) {
            final label = _labelOf(tester, Key('mix_week_${i}_semantics'));
            expect(label, matches(RegExp(r'^\w{3} \d{2}: \d+ min$')));
          }
          expect(
            _labelOf(tester, Key('mix_week_7_semantics')),
            '${OmniDateUtils.formatShort(OmniDateUtils.startOfWeek(DateTime.now(), startOfWeek: settingsState.startOfWeek))}: 60 min (in progress)',
          );
          expect(tester.takeException(), isNull);
        });
      });

      group('S-1609 / S-3207 the strip’s figures are the measure the explainer '
          'states, rated', () {
        setUp(() => _seedRatedStrip(repo));

        testWidgets('the load explainer names load per week', (tester) async {
          await pumpStats(tester);

          expect(
            _textOf(tester, const Key('mix_explainer')),
            'Last 4 weeks. Your training split by how hard each session felt.',
          );
          for (var i = 0; i < kMixStripWeeks - 1; i++) {
            final label = _labelOf(tester, Key('mix_week_${i}_semantics'));
            expect(label, matches(RegExp(r'^\w{3} \d{2}: \d+ load$')));
          }
          expect(
            _labelOf(tester, Key('mix_week_7_semantics')),
            matches(RegExp(r'^\w{3} \d{2}: \d+ load \(in progress\)$')),
          );
          expect(tester.takeException(), isNull);
        });
      });

      // ─── S-4005, S-4014 ──────────────────────────────────────────────────
      //
      // The strip's caption (D-3205): eight columns with no time axis cannot be
      // read, so the caption brackets them — `7 weeks ago` on the left, `This
      // week so far` on the right — while the columns keep the dates their own
      // semantics carry.

      group('S-4005 the strip carries a caption naming its span', () {
        setUp(() => _seedStrip(repo));

        testWidgets('`7 weeks ago` sits on the left and `This week so far` on '
            'the right, both muted and with the oldest column under them',
            (tester) async {
          await tester.runAsync(
            () => settingsState.setStartOfWeek('sunday'),
          );
          await pumpStats(tester);

          final muted = OmniTheme.colorsForTheme(
            settingsState.appTheme,
          ).textMuted;
          expect(
            _textOf(tester, const Key('mix_strip_start_label')),
            '${kMixStripWeeks - 1} weeks ago',
          );
          expect(
            _textOf(tester, const Key('mix_strip_current_label')),
            'This week so far',
          );
          expect(
            _textColorOf(tester, const Key('mix_strip_start_label')),
            muted,
          );
          expect(
            _textColorOf(tester, const Key('mix_strip_current_label')),
            muted,
          );

          // `7 weeks ago` is the oldest column's own week start day (A-3): the
          // column's semantics still name that date, so the caption and the
          // date cannot drift apart.
          expect(
            _labelOf(tester, const Key('mix_week_0_semantics')),
            startsWith(
              '${OmniDateUtils.formatShort(_oldestWeekStart(settingsState.startOfWeek))}: ',
            ),
          );

          // The caption is under the columns, not over them: the strip's own
          // title stays between the legend and the first column.
          final columnsBottom = tester
              .getBottomLeft(find.byKey(const Key('mix_week_7')))
              .dy;
          expect(
            tester.getTopLeft(find.byKey(const Key('mix_strip_start_label'))).dy,
            greaterThan(columnsBottom),
          );
          expect(
            tester
                .getTopLeft(find.byKey(const Key('mix_strip_current_label')))
                .dy,
            greaterThan(columnsBottom),
          );
          expect(
            tester.getTopLeft(find.byKey(const Key('mix_strip_title'))).dy,
            lessThan(tester.getTopLeft(find.byKey(const Key('mix_week_0'))).dy),
          );

          expect(find.byKey(const Key('mix_strip_empty')), findsNothing);
          expect(find.text('This week so far'), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      });

      group('S-4014 the caption’s two ends bracket the eight columns', () {
        setUp(() => _seedEveryStripWeek(repo));

        testWidgets('the same two ends under Monday and Sunday, over an oldest '
            'column whose own date moves with the setting', (tester) async {
          await tester.runAsync(
            () => settingsState.setStartOfWeek('sunday'),
          );
          await pumpStats(tester);

          final sundayStart = _textOf(
            tester,
            const Key('mix_strip_start_label'),
          );
          expect(sundayStart, '${kMixStripWeeks - 1} weeks ago');
          final sundayOldestDate = OmniDateUtils.formatShort(
            _oldestWeekStart('sunday'),
          );
          expect(
            _labelOf(tester, const Key('mix_week_0_semantics')),
            startsWith('$sundayOldestDate: '),
          );
          final sundayColumnsBottom = tester
              .getBottomLeft(find.byKey(const Key('mix_week_7')))
              .dy;
          expect(
            tester.getTopLeft(find.byKey(const Key('mix_strip_start_label'))).dy,
            greaterThan(sundayColumnsBottom),
          );
          expect(
            _textOf(tester, const Key('mix_strip_current_label')),
            'This week so far',
          );

          // A fresh element of the same type at the same position would reuse
          // the State and never run `initState`, so the tree is emptied first.
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
          await tester.runAsync(
            () => settingsState.setStartOfWeek('monday'),
          );
          await pumpStats(tester);

          final mondayStart = _textOf(
            tester,
            const Key('mix_strip_start_label'),
          );
          expect(mondayStart, '${kMixStripWeeks - 1} weeks ago');
          expect(sundayStart, mondayStart);
          final mondayOldestDate = OmniDateUtils.formatShort(
            _oldestWeekStart('monday'),
          );
          expect(
            mondayOldestDate,
            isNot(sundayOldestDate),
            reason: 'Monday and Sunday really start the strip on two days',
          );
          expect(
            _labelOf(tester, const Key('mix_week_0_semantics')),
            startsWith('$mondayOldestDate: '),
          );
          final mondayColumnsBottom = tester
              .getBottomLeft(find.byKey(const Key('mix_week_7')))
              .dy;
          expect(
            tester.getTopLeft(find.byKey(const Key('mix_strip_start_label'))).dy,
            greaterThan(mondayColumnsBottom),
          );
          expect(
            _textOf(tester, const Key('mix_strip_current_label')),
            'This week so far',
          );
          expect(tester.takeException(), isNull);
        });
      });

      // ─── S-18205 ─────────────────────────────────────────────────────────
      //
      // The strip follows Start of Week while Stats is open (D-18201): the
      // screen listens to the settings state and reloads silently, so the
      // oldest column's date moves without a spinner (D-18205: Mock only).

      if (harness.name == 'Mock') {
        group('S-18205 the strip follows Start of Week while Stats is open', () {
          setUp(() => _seedEveryStripWeek(repo));

          testWidgets('S-18205 the oldest column’s date moves when the setting '
              'flips mid-session', (tester) async {
            await pumpStats(tester);

            expect(
              _labelOf(tester, const Key('mix_week_0_semantics')),
              startsWith(
                '${OmniDateUtils.formatShort(_oldestWeekStart('monday'))}: ',
              ),
            );

            await tester.runAsync(
              () => settingsState.setStartOfWeek('sunday'),
            );
            await tester.pump();
            // The silent reload was started inside `runAsync`, so it runs on
            // the real event loop and needs the real turns these rounds give
            // (a bare `pumpAndSettle` never reaches it) — same reason the
            // signals screen tests give for their `settleStore`.
            for (var round = 0; round < 3; round++) {
              await tester.runAsync(
                () => Future<void>.delayed(const Duration(milliseconds: 20)),
              );
              await tester.pump();
            }
            await tester.pumpAndSettle();

            expect(
              _labelOf(tester, const Key('mix_week_0_semantics')),
              startsWith(
                '${OmniDateUtils.formatShort(_oldestWeekStart('sunday'))}: ',
              ),
            );
            expect(
              OmniDateUtils.formatShort(_oldestWeekStart('sunday')),
              isNot(OmniDateUtils.formatShort(_oldestWeekStart('monday'))),
              reason: 'Monday and Sunday really start the strip on two days',
            );
            expect(tester.takeException(), isNull);
            expect(find.byType(CircularProgressIndicator), findsNothing);
          });
        });
      }

      // ─── S-4006, S-4007, S-4008, S-4015 ──────────────────────────────────
      //
      // An all-empty strip (D-4004): eight columns of zero are not a strip, and
      // drawing one claims eight weeks of data the payload does not have. One
      // line says what is true, and the bar, legend and notes above it stay.

      group('S-4006 eight empty weeks render one line, not a strip', () {
        setUp(() => _seedStriplessHistory(repo));

        testWidgets('no bar, no legend, no strip — the card is the '
            'empty-window line naming the last session', (tester) async {
          await pumpStats(tester);

          // The window holds no session, so the card is the one-line
          // empty-window card: header, then the line — no chip, no explainer,
          // no bar, no legend, no strip.
          expect(find.byKey(const Key('mix_window_empty')), findsOneWidget);
          expect(find.text('TRAINING MIX'), findsOneWidget);
          expect(find.byKey(const Key('stats_window_chip')), findsNothing);
          expect(find.byKey(const Key('mix_explainer')), findsNothing);
          expect(find.byKey(const Key('mix_bar')), findsNothing);
          expect(find.byKey(const Key('mix_legend')), findsNothing);
          expect(find.byKey(const Key('mix_strip_title')), findsNothing);
          expect(_stripKeys(), isEmpty);
          expect(find.byKey(const Key('mix_strip_start_label')), findsNothing);
          expect(find.byKey(const Key('mix_strip_current_label')), findsNothing);

          final lastSessionDay = _day(57);
          expect(
            _textOf(tester, const Key('mix_window_empty')),
            'No training in the last 4 weeks. '
            'Last session: ${OmniDateUtils.formatShort(lastSessionDay)}.',
          );
          expect(
            _textColorOf(tester, const Key('mix_window_empty')),
            OmniTheme.colorsForTheme(settingsState.appTheme).textMuted,
          );
          expect(tester.takeException(), isNull);
        });

      // The empty-strip line itself (`mix_strip_empty`, D-4004) is no longer
      // reachable from the screen — the fixed 28-day window puts every window
      // session inside the strip's span — but the widget is generic over its
      // payload, so these pump `MixLayerSection` directly with hand-built
      // all-empty weeks (the S-4021 pump pattern).
      Future<void> pumpEmptyStrip(
        WidgetTester tester, {
        required DateTime? lastSessionDay,
      }) async {
        await tester.binding.setSurfaceSize(_kTallViewport);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final currentWeekStart = DateTime(2026, 4, 20);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MixLayerSection(
                layer: MixLayerData(
                  measure: MixMeasure.time,
                  segments: const [],
                  baselineSegments: const [],
                  unratedSessionCount: 0,
                  ratedWeeks: 0,
                  weeks: [
                    for (var i = 0; i < kMixStripWeeks; i++)
                      MixWeek(
                        weekStart: DateTime(
                          currentWeekStart.year,
                          currentWeekStart.month,
                          currentWeekStart.day -
                              (kMixStripWeeks - 1 - i) * 7,
                        ),
                        segments: const [],
                        measure: 0,
                        inProgress: i == kMixStripWeeks - 1,
                      ),
                  ],
                  lastSessionDay: lastSessionDay,
                  windowIsEmpty: false,
                ),
                window: StatsWindow(
                  fromMs: DateTime(2026, 4, 1),
                  toMs: DateTime(2026, 4, 30),
                  label: 'Test window',
                  isPeriodScoped: false,
                ),
                themeColors: OmniTheme.colorsForTheme(
                  settingsState.appTheme,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      testWidgets('an all-empty strip whose last session predates the span '
          'renders the empty-strip line', (tester) async {
        // The oldest week starts 49 days before the current week, so this day
        // is before the span: the line may name it.
        await pumpEmptyStrip(tester, lastSessionDay: DateTime(2026, 3, 1));

        expect(find.byKey(const Key('mix_strip_empty')), findsOneWidget);
        expect(
          _textOf(tester, const Key('mix_strip_empty')),
          'No training in the last $kMixStripWeeks weeks. '
          'Last session: ${OmniDateUtils.formatShort(DateTime(2026, 3, 1))}.',
        );
        expect(find.byKey(const Key('mix_strip_title')), findsNothing);
        expect(find.byKey(const Key('mix_bar_segment_0')), findsNothing);
        expect(find.byKey(const Key('mix_strip_start_label')), findsNothing);
        expect(find.byKey(const Key('mix_strip_current_label')), findsNothing);
        expect(tester.takeException(), isNull);
      });

      testWidgets('an all-empty strip with no session at all renders the '
          'line without a last-session date', (tester) async {
        await pumpEmptyStrip(tester, lastSessionDay: null);

        expect(find.byKey(const Key('mix_strip_empty')), findsOneWidget);
        expect(
          _textOf(tester, const Key('mix_strip_empty')),
          'No training in the last $kMixStripWeeks weeks.',
        );
        expect(find.byKey(const Key('mix_strip_title')), findsNothing);
        expect(find.byKey(const Key('mix_bar_segment_0')), findsNothing);
        expect(tester.takeException(), isNull);
      });

      testWidgets('the twin: a last session inside the span keeps the strip '
          'and the empty-strip line stays out', (tester) async {
        await pumpEmptyStrip(tester, lastSessionDay: DateTime(2026, 4, 20));

        expect(find.byKey(const Key('mix_strip_empty')), findsNothing);
        expect(find.byKey(const Key('mix_strip_title')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
      });

      group('S-4007 only the current week has training', () {
        setUp(
          () => _seedLifting(repo, sessionId: 's-current', daysAgo: 0, hour: 0),
        );

        testWidgets('the strip renders and no empty line does', (tester) async {
          await pumpStats(tester);

          expect(find.byKey(const Key('mix_strip_title')), findsOneWidget);
          expect(find.byKey(const Key('mix_explainer')), findsOneWidget);
          expect(find.byKey(const Key('mix_strip_empty')), findsNothing);
          expect(
            _stackIndices(_weekIndexOf(_day(0), settingsState.startOfWeek)),
            [0],
          );
          expect(
            _textOf(tester, const Key('mix_strip_current_label')),
            'This week so far',
          );
          expect(tester.takeException(), isNull);
        });
      });

      group('S-4008 the oldest of the eight weeks has training', () {
        setUp(() async {
          await _seedLifting(repo, sessionId: 's-oldest', daysAgo: 49, hour: 0);
          // The strip renders only when the window itself holds a session, so
          // the fixture adds one in the current week; the oldest column stays
          // the 49-days-back one.
          await _seedLifting(repo, sessionId: 's-window', daysAgo: 0, hour: 0);
        });

        testWidgets('the strip renders, the oldest column holds its work, and '
            'no line renders', (tester) async {
          await pumpStats(tester);

          expect(
            _weekIndexOf(_day(49), settingsState.startOfWeek),
            0,
            reason: 'the fixture must land in the oldest column',
          );
          expect(find.byKey(const Key('mix_strip_title')), findsOneWidget);
          expect(find.byKey(const Key('mix_strip_empty')), findsNothing);
          expect(find.byKey(const Key('mix_window_empty')), findsNothing);
          expect(_stackIndices(0), [0]);
          expect(
            _textOf(tester, const Key('mix_strip_start_label')),
            '${kMixStripWeeks - 1} weeks ago',
          );
          final currentWeek = _weekIndexOf(_day(0), settingsState.startOfWeek);
          for (var i = 1; i < kMixStripWeeks; i++) {
            if (i == currentWeek) continue;
            expect(_stackIndices(i), isEmpty, reason: 'column $i');
          }
          expect(tester.takeException(), isNull);
        });
      });

      group('S-4015 the empty line names the last completed session', () {
        setUp(() => _seedStriplessHistoryWithUnfinished(repo));

        testWidgets('it names the last completed session — not the oldest '
            'session, not the window’s end and not today’s unfinished one',
            (tester) async {
          await pumpStats(tester);

          final lastSessionDay = _day(57);
          final oldestDay = _day(60);
          final line = _textOf(tester, const Key('mix_window_empty'));
          expect(
            line,
            'No training in the last 4 weeks. '
            'Last session: ${OmniDateUtils.formatShort(lastSessionDay)}.',
          );
          expect(line, isNot(contains(OmniDateUtils.formatShort(oldestDay))));
          expect(line, isNot(contains(OmniDateUtils.formatShort(_day(0)))));

          // Everything the empty-window card leaves alone still renders: the
          // header, and nothing of the bar or the strip.
          expect(find.text('TRAINING MIX'), findsOneWidget);
          expect(find.byKey(const Key('stats_window_chip')), findsNothing);
          expect(find.byKey(const Key('mix_bar')), findsNothing);
          expect(_stripKeys(), isEmpty);
          expect(tester.takeException(), isNull);
        });

        test('the service’s own payload carries that day and not today',
            () async {
          final window = StatsProgressService.statsWindow(now: DateTime.now());
          expect(window.isPeriodScoped, isFalse);

          final layer = await StatsProgressService(repo).computeMixLayer(
            window: window,
            now: DateTime.now(),
            startOfWeek: settingsState.startOfWeek,
          );
          expect(layer, isNotNull);
          expect(layer!.windowIsEmpty, isTrue);
          expect(layer.lastSessionDay, localMidnightDay(_day(57)));
          expect(layer.weeks, isEmpty);
        });
      });

      group('S-4016 a payload with no weeks builds no strip', () {
        testWidgets('the widget the period payload feeds renders nothing it '
            'cannot claim', (tester) async {
          await tester.binding.setSurfaceSize(_kTallViewport);
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final themeColors = OmniTheme.colorsForTheme(
            settingsState.appTheme,
          );

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: MixLayerSection(
                  layer: const MixLayerData(
                    measure: MixMeasure.time,
                    segments: [],
                    baselineSegments: [],
                    unratedSessionCount: 0,
                    ratedWeeks: 0,
                    weeks: [],
                  ),
                  window: StatsWindow(
                    fromMs: DateTime(2026, 4, 1),
                    toMs: DateTime(2026, 4, 30),
                    label: 'Test window',
                    isPeriodScoped: false,
                  ),
                  themeColors: themeColors,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(find.byKey(const Key('mix_layer')), findsOneWidget);
          expect(_stripKeys(), isEmpty);
          expect(find.byKey(const Key('mix_strip_title')), findsNothing);
          expect(find.byKey(const Key('mix_strip_start_label')), findsNothing);
          expect(find.byKey(const Key('mix_strip_current_label')), findsNothing);
          expect(find.byKey(const Key('mix_strip_empty')), findsNothing);
          expect(tester.takeException(), isNull);
        });
      });

      // ─── S-4021 ──────────────────────────────────────────────────────────

      group('S-4021 a zero-measure session inside the span keeps the strip', () {
        testWidgets('the strip draws and the empty line does not', (
          tester,
        ) async {
          await tester.binding.setSurfaceSize(_kTallViewport);
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final themeColors = OmniTheme.colorsForTheme(settingsState.appTheme);

          // A completed session inside the span whose measure is zero — an
          // unrated session under the load measure, or a zero-duration one
          // under the time measure. The line that says "No training in the
          // last 8 weeks" would contradict its own last-session date, so the
          // strip draws instead.
          final currentWeekStart = DateTime(2026, 4, 20);
          final weeks = <MixWeek>[
            for (var i = 0; i < kMixStripWeeks; i++)
              MixWeek(
                weekStart: DateTime(
                  currentWeekStart.year,
                  currentWeekStart.month,
                  currentWeekStart.day - (kMixStripWeeks - 1 - i) * 7,
                ),
                segments: const [],
                measure: 0,
                inProgress: i == kMixStripWeeks - 1,
              ),
          ];

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: MixLayerSection(
                  layer: MixLayerData(
                    measure: MixMeasure.time,
                    segments: const [],
                    baselineSegments: const [],
                    unratedSessionCount: 0,
                    ratedWeeks: 0,
                    weeks: weeks,
                    lastSessionDay: currentWeekStart,
                  ),
                  window: StatsWindow(
                    fromMs: DateTime(2026, 4, 1),
                    toMs: DateTime(2026, 4, 30),
                    label: 'Test window',
                    isPeriodScoped: false,
                  ),
                  themeColors: themeColors,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(find.byKey(const Key('mix_strip_empty')), findsNothing);
          expect(
            find.byKey(const Key('mix_strip_start_label')),
            findsOneWidget,
          );
          expect(
            find.byKey(const Key('mix_strip_current_label')),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        });
      });

      // ─── S-1610 ──────────────────────────────────────────────────────────

      group('S-1610 a window with no measurable time renders no layer', () {
        testWidgets('a fresh profile keeps the empty state', (tester) async {
          await pumpStats(tester);

          expect(find.text('No sessions yet'), findsOneWidget);
          expect(find.text('TRAINING MIX'), findsNothing);
          expect(find.byKey(const Key('mix_layer')), findsNothing);
          expect(tester.takeException(), isNull);
        });
      });

      group('S-1610 a window of set-only rolling work renders no layer', () {
        setUp(() => _seedRollingSets(repo));

        testWidgets('a rolling session of sets alone renders the screen '
            'without the layer', (tester) async {
          await pumpStats(tester);

          expect(find.byKey(const Key('instrument_caption')), findsOneWidget);
          expect(find.text('TRAINING MIX'), findsNothing);
          expect(find.byKey(const Key('mix_layer')), findsNothing);
          expect(tester.takeException(), isNull);
        });
      });

      // ─── S-1611 ──────────────────────────────────────────────────────────

      group('S-1611 a lifting-only window is one full-width segment', () {
        setUp(() => _seedLiftingOnlyWindow(repo));

        testWidgets('one segment fills the bar, the usual bar carries one '
            'segment, and every week stacks one', (tester) async {
          await pumpStats(tester);

          expect(find.byKey(const Key('mix_bar_segment_0')), findsOneWidget);
          expect(find.byKey(const Key('mix_bar_segment_1')), findsNothing);
          expect(
            tester.getSize(find.byKey(const Key('mix_bar_segment_0'))).width,
            tester.getSize(find.byKey(const Key('mix_bar'))).width,
          );
          expect(
            _segmentColor(tester, const Key('mix_bar_segment_0')),
            ModalityColors.resistanceLifting,
          );
          expect(_textsUnder(find.byKey(const Key('mix_legend'))), [
            'Resistance 100%',
          ]);
          expect(
            _allTexts().where((text) => RegExp(r'(^|\s)0%$').hasMatch(text)),
            isEmpty,
          );

          expect(find.byKey(const Key('mix_usual_bar')), findsOneWidget);
          expect(_textOf(tester, const Key('mix_usual_label')), 'Your usual');
          expect(find.byKey(const Key('mix_usual_segment_0')), findsOneWidget);
          expect(find.byKey(const Key('mix_usual_segment_1')), findsNothing);

          for (var i = 0; i < kMixStripWeeks; i++) {
            final indices = _stackIndices(i);
            if (indices.isEmpty) continue;
            expect(indices, [0], reason: 'column $i');
            expect(
              _segmentColor(tester, Key('mix_week_${i}_segment_0')),
              ModalityColors.resistanceLifting,
              reason: 'column $i',
            );
          }
          expect(tester.takeException(), isNull);
        });
      });

      // ─── S-1612 ──────────────────────────────────────────────────────────

      group('S-1612 the window is named in words, not by a chip', () {
        setUp(() => _seedLoadReady(repo));

        testWidgets('the explainer and the Instruments caption each start '
            'with the window, and no chip renders anywhere', (tester) async {
          await pumpStats(tester);

          expect(find.byKey(const Key('stats_window_chip')), findsNothing);
          expect(
            _textOf(tester, const Key('mix_explainer')),
            startsWith('Last 4 weeks. '),
          );
          expect(
            _textOf(tester, const Key('instrument_caption')),
            startsWith('Last 4 weeks. '),
          );
          // The Fuel card's own horizon line is the only other place the
          // window's length is named.
          expect(find.byKey(const Key('fuel_horizon')), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      });

      // ─── S-1613 ──────────────────────────────────────────────────────────

      group('S-1613 the layer reads the same window as the list', () {
        setUp(() => _seedPeriodWindow(repo));

        testWidgets('the bar describes the 28 days, and the explainer names '
            'the window — the period names nothing', (tester) async {
          await pumpStats(tester);

          expect(find.byKey(const Key('stats_window_chip')), findsNothing);
          expect(
            _textOf(tester, const Key('mix_explainer')),
            startsWith('Last 4 weeks. '),
          );
          expect(_textsUnder(find.byKey(const Key('mix_legend'))), [
            'Resistance 67%',
            'Cardio 33%',
          ]);
          expect(find.byKey(const Key('mix_bar_segment_2')), findsNothing);
          expect(tester.takeException(), isNull);
        });
      });

      // ─── S-1614 ──────────────────────────────────────────────────────────

      group('S-1614 no chart primitive, no legacy title, no coaching copy', () {
        setUp(() => _seedEveryModality(repo));

        testWidgets('the layer is containers, and every string it renders is '
            'a figure', (tester) async {
          await pumpStats(tester);

          expect(find.byType(LineChart), findsNothing);
          expect(find.byType(ScrollableTrendChart), findsNothing);
          for (final title in _kLegacyTitles) {
            if (title == 'STRENGTH' || title == 'NUTRITION') {
              expect(
                find.text(title),
                findsNothing,
                reason: 'D-18705: `$title` must never return to the screen',
              );
              continue;
            }
            // D-18705: CARDIO, ISOMETRIC and SPORTS survive only as
            // Instruments headings — at most once each, only as an
            // OmniCardHeader title under Key('instrument_list').
            final matches = find.text(title);
            expect(
              matches.evaluate().length,
              lessThanOrEqualTo(1),
              reason: 'D-18705: `$title` may appear at most once on Stats',
            );
            if (matches.evaluate().isEmpty) {
              continue;
            }
            expect(
              find.ancestor(of: matches, matching: find.byType(OmniCardHeader)),
              findsOneWidget,
              reason:
                  'D-18705: `$title` renders only as an OmniCardHeader title',
            );
            expect(
              find.ancestor(
                of: matches,
                matching: find.byKey(const Key('instrument_list')),
              ),
              findsOneWidget,
              reason:
                  'D-18705: `$title` descends from Key(\'instrument_list\')',
            );
          }

          expect(_textsUnder(find.byKey(const Key('mix_legend'))), [
            'Resistance 40%',
            'Cardio 20%',
            'Isometric 20%',
            'Sports 20%',
          ]);

          final layerTexts = _textsUnder(find.byKey(const Key('mix_layer')));
          for (final forbidden in _kForbiddenCopy) {
            expect(
              layerTexts.where(
                (text) => text.toLowerCase().contains(forbidden),
              ),
              isEmpty,
              reason: forbidden,
            );
          }
          expect(tester.takeException(), isNull);
        });
      });

      // ─── S-1615 ──────────────────────────────────────────────────────────

      group('S-1615 the layer is overflow-safe at the narrowest viewport and '
          'the largest text scale', () {
        setUp(() => _seedDensest(repo));

        // The same matrix `test/screen_overflow_contract_test.dart` uses: the
        // shortest iPhone at the largest non-accessibility text scale, and the
        // tallest at the default.
        const cases = <String, (Size, double)>{
          '375x667 at 1.3x text': (Size(375, 667), 1.3),
          '440x956 at 1.0x text': (Size(440, 956), 1.0),
        };

        for (final entry in cases.entries) {
          testWidgets('the densest layer fits ${entry.key}', (tester) async {
            final (size, scale) = entry.value;
            final overflows = <String>[];
            final previous = FlutterError.onError;
            FlutterError.onError = (details) {
              final text = details.exceptionAsString();
              if (text.contains('overflowed')) {
                overflows.add(text.split('\n').first);
              } else {
                previous?.call(details);
              }
            };

            try {
              await pumpStats(tester, size: size, textScale: scale);
            } finally {
              FlutterError.onError = previous;
            }

            expect(
              overflows.toSet(),
              isEmpty,
              reason: 'the layer overflows at ${entry.key}: '
                  '${overflows.toSet().join(" | ")}',
            );
            expect(tester.takeException(), isNull);

            // The densest layer really is on screen: the bar, the usual bar,
            // the note and the strip all rendered.
            expect(find.byKey(const Key('mix_layer')), findsOneWidget);
            expect(find.byKey(const Key('mix_bar_segment_0')), findsOneWidget);
            expect(find.byKey(const Key('mix_usual_bar')), findsOneWidget);
            expect(
              _textOf(tester, const Key('mix_usual_label')),
              'Your usual',
            );
            expect(find.byKey(const Key('mix_usual_label')), findsOneWidget);
            expect(find.byKey(const Key('mix_week_current')), findsOneWidget);

            // Nothing the layer draws is wider than the card that holds it.
            final cardWidth = tester
                .getSize(find.byKey(const Key('mix_layer')))
                .width;
            for (final key in const [
              Key('mix_bar'),
              Key('mix_usual_bar'),
              Key('mix_legend'),
              Key('mix_week_current'),
            ]) {
              expect(
                tester.getSize(find.byKey(key)).width,
                lessThanOrEqualTo(cardWidth),
                reason: '$key is wider than the card at ${entry.key}',
              );
            }
          });
        }
      });

      // ─── the caption at large text ───────────────────────────────────────

      group('Guard — the caption fits 390x844 dp and 2.0 text scale', () {
        setUp(() => _seedStrip(repo));

        testWidgets('the two caption ends ellipsise instead of overflowing the '
            'card', (tester) async {
          await pumpStats(tester, size: const Size(390, 844), textScale: 2.0);

          expect(tester.takeException(), isNull);
          expect(
            find.byKey(const Key('mix_strip_start_label')),
            findsOneWidget,
          );
          expect(
            find.byKey(const Key('mix_strip_current_label')),
            findsOneWidget,
          );
        });
      });

      // ─── S-1616 ──────────────────────────────────────────────────────────

      group('S-1616 the layer is refreshed by the screen’s one load pass', () {
        testWidgets('a fresh screen renders no layer, and re-entering it '
            'renders the seeded window', (tester) async {
          await pumpStats(tester);
          expect(find.text('TRAINING MIX'), findsNothing);

          // The seed runs outside the fake clock: Hive's file I/O never
          // settles under `FakeAsync`.
          await tester.runAsync(() => _seedLoadReady(repo));
          await tester.pumpAndSettle();

          // A fresh element of the same type at the same position would reuse
          // the State and never run `initState`, so the tree is emptied first.
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
          await pumpStats(tester);

          expect(find.byKey(const Key('mix_layer')), findsOneWidget);
          expect(find.byKey(const Key('mix_bar_segment_0')), findsOneWidget);
          expect(find.byKey(const Key('mix_usual_bar')), findsOneWidget);
          expect(_textOf(tester, const Key('mix_usual_label')), 'Your usual');
          expect(_textsUnder(find.byKey(const Key('mix_legend'))), [
            'Resistance 100%',
          ]);
          expect(find.byKey(const Key('stats_window_chip')), findsNothing);
          expect(tester.takeException(), isNull);
        });
      });

      // ─── Phase 2 structural guards ───────────────────────────────────────
      //
      // The layer and the Instruments list read a modality off an effort in two
      // different services (5a's mix service and its progress service), and the
      // layer names four accents of its own. Each guard below names what breaks
      // it, so a later change to one side fails here instead of drifting.

      group('Guard — one modality mapping across the layer and the list', () {
        setUp(() => _seedEveryModality(repo));

        testWidgets('every modality the layer draws is a section the '
            'Instruments list heads for the same effort', (tester) async {
          await pumpStats(tester);

          // The legend names one section per bar segment, in the bar's order;
          // the list heads one section per kind of work in the window. Both
          // come from the same effort→section rule, so the two sets are equal.
          // Breaks it: a second mapping in the widget that renames, drops or
          // adds a section relative to the list.
          final layerSections = _legendSections();
          final listSections = _listSections();

          expect(layerSections, isNotEmpty);
          expect(listSections, isNotEmpty);
          expect(layerSections.toSet(), listSections.toSet());
          expect(tester.takeException(), isNull);
        });
      });

      group('Guard — the layer never renders a bare modality name', () {
        setUp(() => _seedDensest(repo));

        testWidgets('a modality name on screen is only ever an Instruments '
            'header, and the usual label is not one of them', (tester) async {
          await pumpStats(tester);

          // `Your usual` belongs to the layer's own vocabulary, so it is not a
          // modality name and the legacy guard cannot count it. Breaks it: a
          // legend of bare names, which is what `test/stats_legacy_removal_`
          // `test.dart` asserts against (S-1604).
          expect(find.text('Your usual'), findsOneWidget);
          expect(_kSectionLabels.contains('Your usual'), isFalse);

          for (final label in _kSectionLabels) {
            // D-18704: the list header is the uppercase label, so the bare
            // title-case name renders nowhere on the screen.
            expect(
              find.text(label),
              findsNothing,
              reason: 'a bare "$label" is not on the screen',
            );
            expect(
              find.text(label.toUpperCase()),
              findsOneWidget,
              reason: 'a bare "$label" is not the list header',
            );
            expect(
              find.descendant(
                of: find.byType(InstrumentList),
                matching: find.text(label.toUpperCase()),
              ),
              findsOneWidget,
              reason: label,
            );
            expect(
              find.descendant(
                of: find.byKey(const Key('mix_layer')),
                matching: find.text(label.toUpperCase()),
              ),
              findsNothing,
              reason: label,
            );
          }
          expect(tester.takeException(), isNull);
        });
      });

      group('Guard — the layer draws no chart and no colour of its own', () {
        setUp(() => _seedDensest(repo));

        testWidgets('every segment colour is the ModalityColors accent of its '
            'modality', (tester) async {
          await pumpStats(tester);

          // Breaks it: any chart primitive pulled into the layer.
          final layer = find.byKey(const Key('mix_layer'));
          for (final chart in <Type>[
            CustomPaint,
            LineChart,
            ScrollableTrendChart,
          ]) {
            expect(
              find.descendant(of: layer, matching: find.byType(chart)),
              findsNothing,
              reason: '$chart inside the layer',
            );
          }

          // The bar: the legend is the bar's segments in the bar's order, so
          // segment i must draw the accent its own legend entry names. Breaks
          // it: a segment bound to the wrong section's accent, or to a literal.
          final legend = _legendSections();
          expect(legend, isNotEmpty);
          for (var i = 0; i < legend.length; i++) {
            expect(
              _segmentColor(tester, Key('mix_bar_segment_$i')),
              _kSectionAccents[legend[i]],
              reason: 'bar segment $i is ${legend[i]}',
            );
          }

          // The usual bar and every strip stack segment: one of the four
          // accents and nothing else, so a colour the layer invents has no
          // accent to match.
          final accents = _kSectionAccents.values.toSet();
          final segments = <Key>[
            for (var i = 0; i < kMixStripWeeks; i++)
              for (final j in _stackIndices(i)) Key('mix_week_${i}_segment_$j'),
            for (final i in _usualIndices()) Key('mix_usual_segment_$i'),
          ];
          expect(segments, isNotEmpty);
          for (final key in segments) {
            expect(
              accents,
              contains(_segmentColor(tester, key)),
              reason: '$key is not a ModalityColors accent',
            );
          }
          expect(tester.takeException(), isNull);
        });
      });

      group('Guard — the strip stacks by modality', () {
        setUp(() => _seedStrip(repo));

        testWidgets('a two-modality week renders two segments in the data’s '
            'order and a lifting-only week renders one', (tester) async {
          await pumpStats(tester);

          // The fixture's one mixed week: a set effort then a cardio effort, so
          // the bottom-most segment is resistance and the one above it cardio.
          // Breaks it: collapsing the column back to a single-colour block.
          final mixedIndex = _weekIndexOf(_day(7), settingsState.startOfWeek);
          expect(mixedIndex, isNot(7));
          expect(_stackIndices(mixedIndex), [0, 1]);
          expect(
            _segmentColor(tester, Key('mix_week_${mixedIndex}_segment_0')),
            ModalityColors.resistanceLifting,
          );
          expect(
            _segmentColor(tester, Key('mix_week_${mixedIndex}_segment_1')),
            ModalityColors.cardioEndurance,
          );

          // Every other week with work holds set efforts only.
          for (final index in [
            7,
            _weekIndexOf(_day(30), settingsState.startOfWeek),
          ]) {
            expect(_stackIndices(index), [0], reason: 'column $index');
            expect(
              _segmentColor(tester, Key('mix_week_${index}_segment_0')),
              ModalityColors.resistanceLifting,
              reason: 'column $index',
            );
          }
          expect(tester.takeException(), isNull);
        });
      });

      // ─── Phase A: the card says what it means (S-3201…S-3208) ────────────
      //
      // Plan 32, phase A (D-3201…D-3206): the copy fixes the owner asked for.
      // Every figure asserted below is still one the payload carries.

      /// Pumps the layer alone, from a payload the test builds — the shapes a
      /// seeded window cannot always be steered into (S-3203, S-3205, S-3208).
      ///
      /// The Stats screen draws the layer inside a `ListView` padded 20/20, so
      /// the same padding and the same unbounded height here keep the width and
      /// the fit assertions honest: a card that grows taller than the viewport
      /// scrolls on the screen and must not be reported as an overflow.
      Future<void> pumpLayer(
        WidgetTester tester,
        MixLayerData layer, {
        Size size = _kTallViewport,
        double textScale = 1.0,
      }) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
            child: MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: MixLayerSection(
                    layer: layer,
                    window: StatsWindow(
                      fromMs: DateTime(2026, 4, 1),
                      toMs: DateTime(2026, 4, 30),
                      label: 'Test window',
                      isPeriodScoped: false,
                    ),
                    themeColors: OmniTheme.colorsForTheme(
                      settingsState.appTheme,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      /// The style the `Text` keyed [key] carries.
      TextStyle? styleOf(WidgetTester tester, Key key) =>
          tester.widget<Text>(find.byKey(key)).style;

      // ─── S-3201 ──────────────────────────────────────────────────────────

      group('S-3201 one sentence says what the split is', () {
        setUp(() => _seedLoadReady(repo));

        testWidgets('the load measure reads in words, once, and the old measure '
            'labels are gone', (tester) async {
          await pumpStats(tester);

          expect(find.byKey(const Key('mix_explainer')), findsOneWidget);
          expect(
            _textOf(tester, const Key('mix_explainer')),
            'Last 4 weeks. Your training split by how hard each session felt.',
          );
          expect(
            styleOf(tester, const Key('mix_explainer'))?.color,
            OmniTheme.colorsForTheme(settingsState.appTheme).textSecondary,
          );

          final layerTexts = _textsUnder(find.byKey(const Key('mix_layer')));
          for (final gone in const ['by load', 'by time', 'usual']) {
            expect(layerTexts, isNot(contains(gone)), reason: gone);
          }
          expect(tester.takeException(), isNull);
        });
      });

      group('S-3201 the twin: the time measure reads in its own words', () {
        setUp(() => _seedTimeWindow(repo));

        testWidgets('exactly one explainer, naming time', (tester) async {
          await pumpStats(tester);

          expect(find.byKey(const Key('mix_explainer')), findsOneWidget);
          expect(
            _textOf(tester, const Key('mix_explainer')),
            'Last 4 weeks. Your training split by time spent.',
          );
          expect(tester.takeException(), isNull);
        });
      });

      // ─── S-3202 ──────────────────────────────────────────────────────────

      group('S-3202 the two bars are labelled', () {
        setUp(() => _seedLoadReady(repo));

        testWidgets('In this window sits above the bar and Your usual below it',
            (tester) async {
          await pumpStats(tester);

          expect(
            _textOf(tester, const Key('mix_window_bar_label')),
            'In this window',
          );
          expect(_textOf(tester, const Key('mix_usual_label')), 'Your usual');
          expect(
            styleOf(tester, const Key('mix_window_bar_label'))?.color,
            OmniTheme.colorsForTheme(settingsState.appTheme).textMuted,
          );

          final bar = tester.getRect(find.byKey(const Key('mix_bar')));
          expect(
            tester
                .getTopLeft(find.byKey(const Key('mix_window_bar_label')))
                .dy,
            lessThan(bar.top),
          );
          expect(
            tester.getTopLeft(find.byKey(const Key('mix_usual_label'))).dy,
            greaterThan(bar.bottom),
          );
          expect(tester.takeException(), isNull);
        });
      });

      group('S-3202 the twin: no usual bar, no bar labels', () {
        setUp(() => _seedTimeWindow(repo));

        testWidgets('neither label renders', (tester) async {
          await pumpStats(tester);

          expect(find.byKey(const Key('mix_window_bar_label')), findsNothing);
          expect(find.byKey(const Key('mix_usual_label')), findsNothing);
          expect(tester.takeException(), isNull);
        });
      });

      // ─── S-3203 ──────────────────────────────────────────────────────────

      group('S-3203 the legend drops the 0% entries and gives each one a dot',
          () {
        testWidgets('three entries and three dots while the bar still draws '
            'four segments and names Sports 0%', (tester) async {
          await pumpLayer(
            tester,
            const MixLayerData(
              measure: MixMeasure.load,
              segments: [
                MixSegment(
                  section: ExerciseSection.resistance,
                  measure: 98.4,
                  percent: 98,
                ),
                MixSegment(
                  section: ExerciseSection.isometric,
                  measure: 1.0,
                  percent: 1,
                ),
                MixSegment(
                  section: ExerciseSection.cardio,
                  measure: 0.6,
                  percent: 1,
                ),
                MixSegment(
                  section: ExerciseSection.sports,
                  measure: 0.0,
                  percent: 0,
                ),
              ],
              baselineSegments: [],
              unratedSessionCount: 0,
              ratedWeeks: kTrainingLoadMinRatedWeeks,
              weeks: [],
            ),
          );

          expect(_textsUnder(find.byKey(const Key('mix_legend'))), [
            'Resistance 98%',
            'Isometric 1%',
            'Cardio 1%',
          ]);
          for (var i = 0; i < 3; i++) {
            expect(find.byKey(Key('mix_legend_dot_$i')), findsOneWidget);
          }
          expect(find.byKey(const Key('mix_legend_dot_3')), findsNothing);
          expect(
            tester.getSize(find.byKey(const Key('mix_legend_dot_0'))),
            const Size(10, 10),
          );
          expect(
            _decorationColor(tester, const Key('mix_legend_dot_0')),
            ModalityColors.resistanceLifting,
          );
          expect(
            _decorationColor(tester, const Key('mix_legend_dot_1')),
            ModalityColors.isometricStretching,
          );
          expect(
            _decorationColor(tester, const Key('mix_legend_dot_2')),
            ModalityColors.cardioEndurance,
          );

          final textTheme = Theme.of(
            tester.element(find.byKey(const Key('mix_legend'))),
          ).textTheme;
          final legendStyle = tester
              .widget<Text>(find.text('Resistance 98%'))
              .style;
          expect(
            legendStyle?.color,
            OmniTheme.colorsForTheme(settingsState.appTheme).textSecondary,
          );
          expect(legendStyle?.fontSize, textTheme.bodyMedium?.fontSize);

          // The bar is untouched by the legend's copy: four segments, and its
          // semantics still names the modality the legend dropped.
          for (var i = 0; i < 4; i++) {
            expect(find.byKey(Key('mix_bar_segment_$i')), findsOneWidget);
          }
          expect(
            _labelOf(tester, const Key('mix_bar')),
            contains('Sports 0%'),
          );
          expect(tester.takeException(), isNull);
        });
      });

      // ─── S-3204 ──────────────────────────────────────────────────────────

      group('S-3204 the baseline note says what happens and when', () {
        setUp(() => _seedThreeRatedWeeks(repo));

        testWidgets('three of four rated weeks are named with the threshold',
            (tester) async {
          await pumpStats(tester);

          expect(
            _textOf(tester, const Key('mix_baseline_note')),
            'Showing time for now. Effort appears once '
            '$kTrainingLoadMinRatedWeeks weeks are rated '
            '(3 of $kTrainingLoadMinRatedWeeks so far).',
          );
          expect(find.textContaining('Load baseline:'), findsNothing);
          expect(tester.takeException(), isNull);
        });
      });

      group('S-3204 the twin: no rated week at all', () {
        setUp(() => _seedTimeWindow(repo));

        testWidgets('reads nought of four', (tester) async {
          await pumpStats(tester);

          expect(
            _textOf(tester, const Key('mix_baseline_note')),
            'Showing time for now. Effort appears once '
            '$kTrainingLoadMinRatedWeeks weeks are rated '
            '(0 of $kTrainingLoadMinRatedWeeks so far).',
          );
          expect(tester.takeException(), isNull);
        });
      });

      group('S-3204 the load measure explains nothing', () {
        setUp(() => _seedLoadReady(repo));

        testWidgets('no baseline note renders at all', (tester) async {
          await pumpStats(tester);

          expect(find.byKey(const Key('mix_baseline_note')), findsNothing);
          expect(find.textContaining('Showing time for now'), findsNothing);
          expect(tester.takeException(), isNull);
        });
      });

      // S-18603: the fewer-than-4-rated-weeks sentence is already pinned by
      // the two S-3204 groups above ('three of four' / 'no rated week at
      // all'); those must stay green.

      // ─── S-18601 / S-18602 ──────────────────────────────────────────────
      //
      // The unrated-share rule (D-18601): with the rated weeks at the
      // threshold, the measure is load only while the window's unrated time
      // is at most 25% of it.

      group('S-18601 the baseline note when effort is hidden by unrated time',
          () {
        setUp(() => _seedUnratedWindow(repo));

        testWidgets('over the share, time keeps the note without "so far"',
            (tester) async {
          await pumpStats(tester);

          expect(
            _textOf(tester, const Key('mix_baseline_note')),
            'Showing time for now. '
            'Effort needs most of the last 4 weeks rated.',
          );
          expect(tester.takeException(), isNull);
        });
      });

      group('S-18602 the unrated share boundary is inclusive', () {
        setUp(() => _seedEdgeShareWindow(repo));

        testWidgets('exactly 25% unrated keeps load and no note',
            (tester) async {
          await pumpStats(tester);

          expect(find.byKey(const Key('mix_baseline_note')), findsNothing);
          expect(find.textContaining('Showing time for now'), findsNothing);
          expect(tester.takeException(), isNull);
        });
      });

      // ─── S-3205 ──────────────────────────────────────────────────────────
      //
      // The unrated line is gone (D-17305); S-17309 in
      // test/stats_mix_horizon_screen_test.dart covers its removal. The
      // remaining test keeps the absence claim.

      group('S-3205 the twin: every session rated', () {
        setUp(() => _seedLoadReady(repo));

        testWidgets('no unrated line renders', (tester) async {
          await pumpStats(tester);

          expect(find.byKey(const Key('mix_unrated_note')), findsNothing);
          expect(tester.takeException(), isNull);
        });
      });

      // ─── S-3206 ──────────────────────────────────────────────────────────

      group('S-3206 the strip is titled, captioned and shows eight columns',
          () {
        setUp(() => _seedStrip(repo));

        testWidgets('title, two ends, five 2 dp stubs on the empty columns and '
            'none on the three with work, columns still 64 dp', (tester) async {
          await pumpStats(tester);

          expect(
            _textOf(tester, const Key('mix_strip_title')),
            'Last $kMixStripWeeks weeks, week by week',
          );
          expect(
            _textOf(tester, const Key('mix_strip_start_label')),
            '${kMixStripWeeks - 1} weeks ago',
          );
          expect(
            _textOf(tester, const Key('mix_strip_current_label')),
            'This week so far',
          );
          expect(
            styleOf(tester, const Key('mix_strip_title'))?.color,
            OmniTheme.colorsForTheme(settingsState.appTheme).textMuted,
          );

          // The fixture puts work in three of the eight weeks: today's, the
          // week a week back and the week a month back.
          final withWork = <int>{
            7,
            _weekIndexOf(_day(7), settingsState.startOfWeek),
            _weekIndexOf(_day(30), settingsState.startOfWeek),
          };
          expect(withWork, hasLength(3), reason: 'three distinct weeks');

          final stubs = <int>[];
          for (var i = 0; i < kMixStripWeeks; i++) {
            final stub = find.byKey(Key('mix_week_${i}_empty'));
            if (withWork.contains(i)) {
              expect(stub, findsNothing, reason: 'column $i holds work');
            } else {
              expect(stub, findsOneWidget, reason: 'column $i is empty');
              expect(
                tester.getSize(stub).height,
                2,
                reason: 'column $i stub is 2 dp',
              );
              stubs.add(i);
            }
            expect(
              tester.getSize(find.byKey(Key('mix_week_$i'))).height,
              64,
              reason: 'column $i keeps the strip height',
            );
            // The stub is not a stack segment.
            expect(
              _stackIndices(i),
              withWork.contains(i) ? isNotEmpty : isEmpty,
              reason: 'column $i',
            );
          }
          expect(stubs, hasLength(5));
          expect(tester.takeException(), isNull);
        });
      });

      group('S-3206 the twin: an all-empty strip keeps its one line', () {
        setUp(() => _seedStriplessHistory(repo));

        testWidgets('the one line is the empty-window card, and no strip '
            'renders', (tester) async {
          await pumpStats(tester);

          // The strip's eight weeks are all empty and the window holds no
          // session, so the card's one line is the empty-window line — the
          // strip's own empty line never renders.
          expect(find.byKey(const Key('mix_window_empty')), findsOneWidget);
          expect(find.byKey(const Key('mix_strip_empty')), findsNothing);
          expect(find.byKey(const Key('mix_strip_title')), findsNothing);
          expect(find.byKey(const Key('mix_strip_start_label')), findsNothing);
          expect(find.byKey(const Key('mix_strip_current_label')), findsNothing);
          expect(_stripKeys(), isEmpty);
          expect(tester.takeException(), isNull);
        });
      });

      // ─── S-3208 ──────────────────────────────────────────────────────────

      group('S-3208 the whole card fits every viewport and text scale', () {
        // The densest writing the card can carry: a zero-share modality, both
        // notes, the usual bar and eight columns, four of them empty.
        MixLayerData densest() {
          final currentWeekStart = DateTime(2026, 4, 20);
          return MixLayerData(
            measure: MixMeasure.time,
            segments: const [
              MixSegment(
                section: ExerciseSection.resistance,
                measure: 98.4,
                percent: 98,
              ),
              MixSegment(
                section: ExerciseSection.isometric,
                measure: 1.0,
                percent: 1,
              ),
              MixSegment(
                section: ExerciseSection.cardio,
                measure: 0.6,
                percent: 1,
              ),
              MixSegment(
                section: ExerciseSection.sports,
                measure: 0.0,
                percent: 0,
              ),
            ],
            baselineSegments: const [
              MixSegment(
                section: ExerciseSection.resistance,
                measure: 60,
                percent: 60,
              ),
              MixSegment(
                section: ExerciseSection.cardio,
                measure: 40,
                percent: 40,
              ),
            ],
            unratedSessionCount: 3,
            ratedWeeks: kTrainingLoadMinRatedWeeks - 1,
            weeks: [
              for (var i = 0; i < kMixStripWeeks; i++)
                MixWeek(
                  weekStart: DateTime(
                    currentWeekStart.year,
                    currentWeekStart.month,
                    currentWeekStart.day -
                        (kMixStripWeeks - 1 - i) * 7,
                  ),
                  segments: i.isEven
                      ? const [
                          MixSegment(
                            section: ExerciseSection.resistance,
                            measure: 60,
                            percent: 100,
                          ),
                        ]
                      : const [],
                  measure: i.isEven ? 60 : 0,
                  inProgress: i == kMixStripWeeks - 1,
                ),
            ],
          );
        }

        const cases = <String, (Size, double)>{
          '390x844 at 1.0x text': (Size(390, 844), 1.0),
          '320x568 at 1.3x text': (Size(320, 568), 1.3),
          '320x568 at 2.0x text': (Size(320, 568), 2.0),
        };

        for (final entry in cases.entries) {
          testWidgets('the densest card fits ${entry.key}', (tester) async {
            final (size, scale) = entry.value;
            final overflows = <String>[];
            final previous = FlutterError.onError;
            FlutterError.onError = (details) {
              final text = details.exceptionAsString();
              if (text.contains('overflowed')) {
                overflows.add(text.split('\n').first);
              } else {
                previous?.call(details);
              }
            };

            try {
              await pumpLayer(
                tester,
                densest(),
                size: size,
                textScale: scale,
              );
            } finally {
              FlutterError.onError = previous;
            }

            expect(
              overflows.toSet(),
              isEmpty,
              reason: 'the card overflows at ${entry.key}: '
                  '${overflows.toSet().join(" | ")}',
            );
            expect(tester.takeException(), isNull);

            // Every block the copy changed is really on screen.
            for (final key in const [
              Key('mix_explainer'),
              Key('mix_window_bar_label'),
              Key('mix_usual_label'),
              Key('mix_baseline_note'),
              Key('mix_strip_title'),
              Key('mix_strip_start_label'),
              Key('mix_strip_current_label'),
            ]) {
              expect(
                find.byKey(key),
                findsOneWidget,
                reason: '$key at ${entry.key}',
              );
            }

            // Nothing the card draws is wider than the card itself — and no
            // line of it runs past the card's right edge either (a `Wrap`
            // child wider than the card overflows without a Flex to report).
            final cardRect = tester.getRect(find.byKey(const Key('mix_layer')));
            for (final key in const [
              Key('mix_bar'),
              Key('mix_usual_bar'),
              Key('mix_legend'),
              Key('mix_strip_title'),
              Key('mix_week_current'),
            ]) {
              expect(
                tester.getSize(find.byKey(key)).width,
                lessThanOrEqualTo(cardRect.width),
                reason: '$key is wider than the card at ${entry.key}',
              );
            }
            final boxes = tester.renderObjectList<RenderBox>(find.byType(Text));
            expect(boxes, isNotEmpty);
            for (final box in boxes) {
              final rect = box.localToGlobal(Offset.zero) & box.size;
              expect(
                rect.left,
                greaterThanOrEqualTo(cardRect.left - 0.01),
                reason: 'a line starts left of the card at ${entry.key}',
              );
              expect(
                rect.right,
                lessThanOrEqualTo(cardRect.right + 0.01),
                reason: 'a line runs past the card at ${entry.key}',
              );
            }
          });
        }
      });
    });
  }
}
