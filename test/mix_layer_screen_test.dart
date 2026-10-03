// The Mix layer (Stats PR 5b, Phase 1) — the screen half of 5a's data.
//
// Scenarios S-1601…S-1614 and S-1616 of
// `docs/plans/2026-10-02-05b-stats-pr5b-mix-screen-plan/`, on both repository
// implementations. Every figure asserted here is one 5a's `MixLayerData`
// supplies: the layer renders and computes nothing, so a fixture only has to
// give the service sessions, ratings and a window.
//
// The window is the fixture's hidden variable. `resolveWindow` prefers a
// training period covering today that holds at least one session, and falls
// back to the 14 most recent distinct training days. A fixture that needs
// rated baseline sessions *outside* the window therefore scopes the window
// with a period: with only a handful of distinct training days the recency
// fallback would swallow those sessions, and the weeks they rate would land
// inside the window instead of in the baseline.
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
import 'package:omnitrain/core/models/training_load.dart';
import 'package:omnitrain/core/utils/date_utils.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/features/stats/stats_screen.dart';
import 'package:omnitrain/features/stats/widgets/instrument_list.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:omnitrain/widgets/chart/scrollable_trend_chart.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/repository_harness.dart';

/// Tall enough that every block the scenarios address is laid out, so an
/// assertion on a widget's absence is never just an off-screen miss.
const Size _kTallViewport = Size(400, 2400);

/// S-1601's viewport: short enough that the Mix block sits above the fold of
/// everything the layer pushes down.
const Size _kFirstBlockViewport = Size(400, 1600);

/// The five section titles the removed legacy layout rendered (D-606).
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

/// The section each Instruments header names, in document order.
List<String> _listSections() => [
  for (final text in _textsUnder(find.byType(InstrumentList)))
    if (_kSectionLabels.contains(text)) text,
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

/// The two window chips' texts, in document order.
List<String> _chipTexts() => _textsUnder(
  find.byKey(const Key('stats_window_chip')),
);

/// The colour of the segment keyed [key].
Color? _segmentColor(WidgetTester tester, Key key) =>
    tester.widget<Container>(find.byKey(key)).color;

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
/// `resolveWindow` prefers it over the recency fallback, which is how every
/// baseline fixture keeps its rated sessions outside the window.
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

/// Rated baseline sessions [daysAgo] days back from the window's start day,
/// each [minutes] long and rated [rating] — the weeks the load measure needs
/// before it is shown (D-908, D-934).
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
/// No baseline session at all: the recency window is the single day, and
/// nothing can rate a baseline week.
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

/// FX-BASELINE3 (S-1605, S-1607-A's twin): a period-scoped window holding
/// FX-TIME's unrated session, with 3 rated weeks of baseline behind it — time
/// measure, the note, no usual bar.
Future<void> _seedThreeRatedWeeks(WorkoutRepository repo) async {
  await _seedPeriod(repo, name: 'Test Block', daysAgo: 10);
  await _seedRatedBaseline(repo, fromDay: 10, offsets: const [80, 60, 40]);
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

/// FX-LOAD (S-1601, S-1603, S-1606, S-1607-C, S-1612, S-1616): a period-scoped
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
/// — and an isometric session before the period that the recency fallback would
/// have picked up.
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

  final outsideStart = _at(12, 9);
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

/// S-1615's fixture: the densest layer the screen can draw — a period-scoped
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

      group('S-1601 the layer is the first block, above ALL TIME', () {
        setUp(() => _seedLoadReady(repo));

        testWidgets('the Mix block sits above ALL TIME, the list and the Fuel '
            'row, and there is exactly one of it', (tester) async {
          await pumpStats(tester, size: _kFirstBlockViewport);

          expect(find.byKey(const Key('mix_layer')), findsOneWidget);
          expect(find.text('TRAINING MIX'), findsOneWidget);

          final mixTop = tester.getTopLeft(find.byKey(const Key('mix_layer'))).dy;
          final allTimeTop = tester.getTopLeft(find.text('ALL TIME')).dy;
          final listTop = tester.getTopLeft(find.text('Resistance')).dy;
          final fuelTop = tester.getTopLeft(find.byKey(const Key('fuel_row'))).dy;

          expect(mixTop, lessThan(allTimeTop));
          expect(allTimeTop, lessThan(listTop));
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

      group('S-1603 one measure label on both blocks, and the chip', () {
        setUp(() => _seedLoadReady(repo));

        testWidgets('the load measure labels the bar and the strip twice, and '
            'never names the other measure', (tester) async {
          await pumpStats(tester);

          expect(find.text('by load'), findsNWidgets(2));
          expect(find.text('by time'), findsNothing);

          final barTop = tester.getTopLeft(find.byKey(const Key('mix_bar'))).dy;
          final stripTop = tester
              .getTopLeft(find.byKey(const Key('mix_week_0')))
              .dy;
          final labels = [
            for (final element in find.text('by load').evaluate())
              tester.getTopLeft(find.byWidget(element.widget)).dy,
          ];
          expect(labels.first, lessThan(barTop));
          expect(labels.last, lessThan(stripTop));
          expect(labels.last, greaterThan(barTop));

          expect(_chipTexts(), ['· Test Block', '· Test Block']);
          expect(tester.takeException(), isNull);
        });
      });

      group('S-1603 the twin: an unrated, baseline-less window', () {
        setUp(() => _seedTimeWindow(repo));

        testWidgets('reads by time twice and never by load', (tester) async {
          await pumpStats(tester);

          expect(find.text('by time'), findsNWidgets(2));
          expect(find.text('by load'), findsNothing);
        });
      });

      // ─── S-1604 ──────────────────────────────────────────────────────────

      group('S-1604 the legend never renders a bare modality name', () {
        setUp(() => _seedTimeWindow(repo));

        testWidgets('a modality name is found once — the Instruments header — '
            'and the legend only as its full string', (tester) async {
          await pumpStats(tester);

          expect(find.text('Resistance'), findsOneWidget);
          expect(find.text('Cardio'), findsOneWidget);
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

          expect(find.text('by time'), findsNWidgets(2));
          expect(find.text('Load baseline: 3 of 4 weeks rated'), findsOneWidget);
          expect(find.byKey(const Key('mix_usual_bar')), findsNothing);
          expect(find.text('usual'), findsNothing);
          expect(
            _semanticsLabels().where(
              (label) => label.startsWith('Usual split:'),
            ),
            isEmpty,
          );
          expect(find.text('1 unrated session'), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      });

      // ─── S-1606 ──────────────────────────────────────────────────────────

      group('S-1606 load ready — load measure, the usual bar, no note', () {
        setUp(() => _seedLoadReady(repo));

        testWidgets('the usual bar sits directly under the bar at the same '
            'width, labelled and read out', (tester) async {
          await pumpStats(tester);

          expect(find.text('by load'), findsNWidgets(2));
          expect(find.byKey(const Key('mix_usual_bar')), findsOneWidget);
          expect(find.text('usual'), findsOneWidget);
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

          expect(
            _allTexts().where((text) => text.startsWith('Load baseline:')),
            isEmpty,
          );
          expect(tester.takeException(), isNull);
        });
      });

      group('S-1606 the twin: an unrated window', () {
        setUp(() => _seedTimeWindow(repo));

        testWidgets('draws no usual bar', (tester) async {
          await pumpStats(tester);

          expect(find.byKey(const Key('mix_usual_bar')), findsNothing);
          expect(find.text('usual'), findsNothing);
        });
      });

      // ─── S-1607 ──────────────────────────────────────────────────────────

      group('S-1607 the unrated count in words, or absent', () {
        setUp(() => _seedTimeWindow(repo));

        testWidgets('one unrated session reads in the singular', (tester) async {
          await pumpStats(tester);

          expect(find.text('1 unrated session'), findsOneWidget);
          expect(find.text('1 unrated sessions'), findsNothing);
        });
      });

      group('S-1607 three unrated sessions', () {
        setUp(() async {
          await _seedLifting(repo, sessionId: 's-u2', daysAgo: 2);
          await _seedLifting(repo, sessionId: 's-u3', daysAgo: 3);
          await _seedLifting(repo, sessionId: 's-u4', daysAgo: 4);
        });

        testWidgets('read in the plural', (tester) async {
          await pumpStats(tester);

          expect(find.text('3 unrated sessions'), findsOneWidget);
          expect(find.text('3 unrated session'), findsNothing);
        });
      });

      group('S-1607 no unrated session', () {
        setUp(() => _seedLoadReady(repo));

        testWidgets('reads nowhere', (tester) async {
          await pumpStats(tester);

          expect(find.text('0 unrated sessions'), findsNothing);
          expect(
            _allTexts().where((text) => text.contains('unrated')),
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

      group('S-1609 the strip reads the same measure as the bar', () {
        setUp(() => _seedStrip(repo));

        testWidgets('the time measure names minutes per week', (tester) async {
          await pumpStats(tester);

          expect(find.text('by time'), findsNWidgets(2));
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

      group('S-1609 the strip reads the same measure as the bar, rated', () {
        setUp(() => _seedRatedStrip(repo));

        testWidgets('the load measure names load per week', (tester) async {
          await pumpStats(tester);

          expect(find.text('by load'), findsNWidgets(2));
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

          expect(find.text('ALL TIME'), findsOneWidget);
          expect(find.byKey(const Key('all_time_card')), findsOneWidget);
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
          expect(find.text('usual'), findsOneWidget);
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

      group('S-1612 exactly two window chips, and the Fuel row has none', () {
        setUp(() => _seedLoadReady(repo));

        testWidgets('the layer and the Instruments list each carry one, both '
            'naming the same window', (tester) async {
          await pumpStats(tester);

          expect(
            find.byKey(const Key('stats_window_chip')),
            findsNWidgets(2),
          );
          expect(_chipTexts(), ['· Test Block', '· Test Block']);
          expect(
            find.descendant(
              of: find.byKey(const Key('mix_layer')),
              matching: find.byKey(const Key('stats_window_chip')),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: find.byKey(const Key('fuel_section')),
              matching: find.byKey(const Key('stats_window_chip')),
            ),
            findsNothing,
          );
          expect(tester.takeException(), isNull);
        });
      });

      // ─── S-1613 ──────────────────────────────────────────────────────────

      group('S-1613 the layer reads the same window as the list', () {
        setUp(() => _seedPeriodWindow(repo));

        testWidgets('the bar describes the period, and the chip names it', (
          tester,
        ) async {
          await pumpStats(tester);

          expect(_chipTexts(), ['· Test Block', '· Test Block']);
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
            expect(find.text(title), findsNothing, reason: title);
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
            // the note, the unrated line and the strip all rendered.
            expect(find.byKey(const Key('mix_layer')), findsOneWidget);
            expect(find.byKey(const Key('mix_bar_segment_0')), findsOneWidget);
            expect(find.byKey(const Key('mix_usual_bar')), findsOneWidget);
            expect(find.text('usual'), findsOneWidget);
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
          expect(find.text('usual'), findsOneWidget);
          expect(_textsUnder(find.byKey(const Key('mix_legend'))), [
            'Resistance 100%',
          ]);
          expect(_chipTexts(), ['· Test Block', '· Test Block']);
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

          // `usual` belongs to the layer's own vocabulary, so it is not a
          // modality name and the legacy guard cannot count it. Breaks it: a
          // legend of bare names, which is what `test/stats_legacy_removal_`
          // `test.dart` asserts against (S-1604).
          expect(find.text('usual'), findsOneWidget);
          expect(_kSectionLabels.contains('usual'), isFalse);

          for (final label in _kSectionLabels) {
            expect(
              find.text(label),
              findsOneWidget,
              reason: 'a bare "$label" is not the list header',
            );
            expect(
              find.descendant(
                of: find.byType(InstrumentList),
                matching: find.text(label),
              ),
              findsOneWidget,
              reason: label,
            );
            expect(
              find.descendant(
                of: find.byKey(const Key('mix_layer')),
                matching: find.text(label),
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
    });
  }
}
