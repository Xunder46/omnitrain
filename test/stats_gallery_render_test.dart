// The Stats wording gallery: renders every state of the Stats screens to a PNG
// and writes a manifest of the words each one shows, so the copy can be read
// and approved without waiting weeks for a condition to come true.
//
// Not a check: it asserts nothing and is skipped in a normal run. To render:
//
//   STATS_GALLERY_OUT=/absolute/folder flutter test test/stats_gallery_render_test.dart
//
// Every card's words come from the app's own copy functions, fed plausible
// figures, so the gallery cannot drift from what the app says.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/app.dart';
import 'package:omnitrain/core/constants/metric_ids.dart';
import 'package:omnitrain/core/constants/omni_theme.dart';
import 'package:omnitrain/core/models/cardio_efficiency_drift.dart';
import 'package:omnitrain/core/models/consistency.dart';
import 'package:omnitrain/core/models/exercise_metric.dart';
import 'package:omnitrain/core/models/fuel_summary.dart';
import 'package:omnitrain/core/models/fuel_vs_load.dart';
import 'package:omnitrain/core/models/hold_progress.dart';
import 'package:omnitrain/core/models/instrument_list.dart';
import 'package:omnitrain/core/models/interference.dart';
import 'package:omnitrain/core/models/modality_mix_shift.dart';
import 'package:omnitrain/core/models/progression_rate.dart';
import 'package:omnitrain/core/models/protein_consistency.dart';
import 'package:omnitrain/core/models/signals.dart';
import 'package:omnitrain/core/models/sustained_high_load.dart';
import 'package:omnitrain/core/models/training_load.dart';
import 'package:omnitrain/core/models/weight_trend.dart';
import 'package:omnitrain/core/services/stats_progress_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/features/stats/exercise_progress_screen.dart';
import 'package:omnitrain/features/stats/records_and_trends_screen.dart';
import 'package:omnitrain/features/stats/stats_screen.dart';
import 'package:omnitrain/features/stats/widgets/fuel_section.dart';
import 'package:omnitrain/features/stats/widgets/instrument_list.dart';
import 'package:omnitrain/features/stats/widgets/load_failure_view.dart';
import 'package:omnitrain/features/stats/widgets/mix_layer.dart';
import 'package:omnitrain/features/stats/widgets/signals_layer.dart';
import 'package:omnitrain/features/stats/widgets/weight_trend_row.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:omnitrain/widgets/layout/omni_gradient_background.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/repository_harness.dart';

final String? _out = Platform.environment['STATS_GALLERY_OUT'];
final List<Map<String, Object?>> _manifest = [];

Future<ByteData> _bytes(String path) async =>
    ByteData.view(File(path).readAsBytesSync().buffer);

Future<void> _loadFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  final dir = '$root/bin/cache/artifacts/material_fonts';
  await (FontLoader('Roboto')
        ..addFont(_bytes('$dir/Roboto-Regular.ttf'))
        ..addFont(_bytes('$dir/Roboto-Medium.ttf'))
        ..addFont(_bytes('$dir/Roboto-Bold.ttf')))
      .load();
  await (FontLoader('MaterialIcons')
        ..addFont(_bytes('$dir/MaterialIcons-Regular.otf')))
      .load();
  // Roboto has no arrow glyphs; a phone falls back to a system font.
  const symbols = '/System/Library/Fonts/Apple Symbols.ttf';
  if (File(symbols).existsSync()) {
    await (FontLoader('GallerySymbols')..addFont(_bytes(symbols))).load();
  }
}

DateTime _day(int daysAgo, {int hour = 18}) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day - daysAgo, hour);
}

// ─── A typical 11-week history, for the whole-screen shots ──────────────────

Future<String> _session(
  WorkoutRepository repo,
  int daysAgo, {
  required int minutes,
  required int? rating,
  required String tag,
}) async {
  final start = _day(daysAgo).millisecondsSinceEpoch;
  final id = 'g-s-$daysAgo-$tag';
  await repo.createSession(
    TrainingSession(
      id: id,
      ownerUserId: 'user-1',
      startedAtMs: start,
      endedAtMs: start + minutes * 60000,
      sessionFeeling: rating,
      createdAtMs: start,
      updatedAtMs: start,
    ),
  );
  await repo.createSegment(
    SessionSegment(
      id: 'seg-$id',
      sessionId: id,
      orderIndex: 0,
      segmentType: 'workout',
      name: 'Main Workout',
      createdAtMs: start,
      updatedAtMs: start,
    ),
  );
  return id;
}

Future<String> _effort(
  WorkoutRepository repo,
  String sessionId,
  String exerciseId,
  String kind,
  int order,
) async {
  final id = 'eff-$sessionId-$exerciseId';
  await repo.createEffort(
    SegmentEffort(
      id: id,
      segmentId: 'seg-$sessionId',
      orderIndex: order,
      effortKind: kind,
      exerciseId: exerciseId,
      createdAtMs: fixtureStart,
      updatedAtMs: fixtureStart,
    ),
  );
  return id;
}

Future<void> _sets(
  WorkoutRepository repo,
  String effortId,
  List<(int reps, double kg)> sets,
) async {
  for (var n = 0; n < sets.length; n++) {
    await repo.createObservation(
      repsRow(effortId, n, sets[n].$1, atMs: fixtureRowAt(n)),
    );
    await repo.createObservation(
      weightRow(effortId, n, sets[n].$2, atMs: fixtureRowAt(n)),
    );
  }
}

Future<void> _clearPersonalData(WorkoutRepository repo) async {
  for (final entry in await repo.getMeasurementHistory('bodyweight')) {
    await repo.deleteMeasurementEntry(entry.id);
  }
  for (final row in await repo.getConsumedFoodsInRange(0, 4102444800000)) {
    await repo.deleteConsumedFood(row.id);
  }
}

Future<void> _seedHistory(WorkoutRepository repo, {bool oneSessionOnly = false}) async {
  await _clearPersonalData(repo);
  const load = ['sets', 'reps', 'load'];
  await seedExercise(repo, id: 'g-bench', name: 'Bench Press', capabilities: load);
  await seedExercise(repo, id: 'g-squat', name: 'Back Squat', capabilities: load);
  await seedExercise(repo, id: 'g-row', name: 'Barbell Row', capabilities: load);
  await seedExercise(repo, id: 'g-dead', name: 'Romanian Deadlift', capabilities: load);
  await seedExercise(repo, id: 'g-ohp', name: 'Overhead Press', capabilities: load);
  await seedExercise(repo, id: 'g-pull', name: 'Pull-Up', capabilities: const ['sets', 'reps']);
  await seedExercise(repo, id: 'g-run', name: 'Outdoor Run');
  await seedExercise(repo, id: 'g-bike', name: 'Stationary Bike');
  await seedExercise(repo, id: 'g-plank', name: 'Plank');
  await seedExercise(repo, id: 'g-box', name: 'Heavy Bag');

  if (oneSessionOnly) {
    final s = await _session(repo, 0, minutes: 35, rating: null, tag: 'run');
    final e = await _effort(repo, s, 'g-run', 'timed', 0);
    await repo.createTimedInstance(
      timedInstance(e, 0, durationSecs: 1800, entryIndex: 0),
    );
    await repo.createObservation(distanceRow(e, 0, 5000, atMs: fixtureRowAt(0)));
    return;
  }

  for (var d = 76; d >= 0; d--) {
    final week = (76 - d) ~/ 7;
    switch (d % 7) {
      case 6:
        final s = await _session(repo, d, minutes: 62, rating: 3 + week % 2, tag: 'a');
        await _sets(repo, await _effort(repo, s, 'g-bench', 'set', 0), [
          (8, 60 + week * 1.25),
          (8, 60 + week * 1.25),
          (7, 60 + week * 1.25),
        ]);
        await _sets(repo, await _effort(repo, s, 'g-squat', 'set', 1), [
          (5, 90 + week * 2.5),
          (5, 90 + week * 2.5),
        ]);
        await _sets(repo, await _effort(repo, s, 'g-row', 'set', 2), [
          (10, 55 + week * 1.0),
          (10, 55 + week * 1.0),
        ]);
      case 4:
        final s = await _session(repo, d, minutes: 36, rating: 3, tag: 'run');
        final e = await _effort(repo, s, 'g-run', 'timed', 0);
        await repo.createTimedInstance(
          timedInstance(e, 0, durationSecs: 1860 - week * 12, entryIndex: 0),
        );
        await repo.createObservation(
          distanceRow(e, 0, 5000, atMs: fixtureRowAt(0)),
        );
      case 2:
        final s = await _session(repo, d, minutes: 70, rating: 4, tag: 'b');
        final w = await _effort(repo, s, 'g-bike', 'timed', 0);
        await repo.createTimedInstance(
          timedInstance(w, 0, durationSecs: 600, entryIndex: 0),
        );
        await _sets(repo, await _effort(repo, s, 'g-dead', 'set', 1), [
          (8, 80 + week * 2.5),
          (8, 80 + week * 2.5),
        ]);
        await _sets(repo, await _effort(repo, s, 'g-ohp', 'set', 2), [
          (6, 40 + week * 0.5),
          (5, 40 + week * 0.5),
        ]);
        await _sets(repo, await _effort(repo, s, 'g-pull', 'set', 3), [
          (6 + week ~/ 3, 0),
          (5 + week ~/ 3, 0),
        ]);
      case 0:
        final s = await _session(repo, d, minutes: 25, rating: 2, tag: 'hold');
        final e = await _effort(repo, s, 'g-plank', 'drill', 0);
        for (var n = 0; n < 3; n++) {
          await repo.createTimedInstance(
            timedInstance(e, n, durationSecs: 60 + week * 4, entryIndex: n),
          );
        }
      case 1:
        if (week.isEven) {
          final s = await _session(repo, d, minutes: 45, rating: 5, tag: 'box');
          final e = await _effort(repo, s, 'g-box', 'round', 0);
          for (var n = 0; n < 6; n++) {
            await repo.createRoundInstance(roundInstance(e, n));
          }
        }
    }
  }

  for (var d = 13; d >= 0; d--) {
    if (d == 9 || d == 4) continue;
    final dateMs = _day(d, hour: 0).millisecondsSinceEpoch;
    await repo.createConsumedFood(
      ConsumedFood(
        id: 'g-food-$d',
        loggedAtMs: dateMs + 12 * 3600000,
        dateMs: dateMs,
        sourceFoodId: 'g-food-$d',
        name: 'Day total',
        unitType: FoodUnitType.grams,
        referenceAmount: 100,
        referenceLabel: '100 g',
        protein: 118 + (d % 3) * 6,
        carbs: 240 + (d % 4) * 10,
        fiber: 0,
        fat: 68 + (d % 2) * 6,
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
  await repo.saveNutritionTargetForDate(
    _day(20, hour: 0).millisecondsSinceEpoch,
    NutritionTarget(calories: 2500, protein: 150, carbs: 300, fat: 80),
  );
  for (final (id, kg, d) in [('w1', 80.4, 26), ('w2', 79.8, 12), ('w3', 79.2, 1)]) {
    await repo.saveMeasurementEntry(
      BodyMeasurementEntry(
        id: 'g-$id',
        measurementType: 'bodyweight',
        value: kg,
        unitId: MetricIds.unitKg,
        recordedAtMs: _day(d, hour: 8).millisecondsSinceEpoch,
      ),
    );
  }
}

// ─── Cards built from the app's own copy functions ──────────────────────────

SignalCard _card(String id, SignalKind kind, String observation, [String? suggestion]) =>
    SignalCard(
      id: id,
      kind: kind,
      priority: 0,
      title: id,
      observation: observation,
      suggestion: suggestion,
    );

MixWeek _week(int weeksAgo, Map<ExerciseSection, double> by, {bool now = false}) {
  final start = _day(weeksAgo * 7 + DateTime.now().weekday - 1, hour: 0);
  return MixWeek(
    weekStart: start,
    segments: mixSegments(by),
    measure: by.values.fold(0, (a, b) => a + b),
    inProgress: now,
  );
}

List<MixWeek> _weeks({bool empty = false}) => [
  for (var i = 7; i >= 0; i--)
    _week(
      i,
      empty
          ? const {}
          : {
              ExerciseSection.resistance: 150.0 + (i % 3) * 30,
              if (i.isEven) ExerciseSection.cardio: 45,
              if (i % 4 == 1) ExerciseSection.sports: 40,
            },
      now: i == 0,
    ),
];

InstrumentRow _row(
  String name,
  ExerciseSection section,
  NativeValue best, {
  NativeValue? previous,
  List<double> trend = const [],
  int? bpm,
  int? cadence,
}) => InstrumentRow(
  summary: ExerciseMetricSummary(
    exerciseId: 'g-${name.toLowerCase().replaceAll(' ', '-')}',
    name: name,
    section: section,
    best: best,
    points: [
      for (var i = 0; i < trend.length; i++)
        ExerciseMetricPoint(
          dayMs: _day(trend.length - i).millisecondsSinceEpoch,
          value: NativeValue(metric: best.metric, value: trend[i]),
        ),
    ],
    lastTrainedMs: _day(1).millisecondsSinceEpoch,
    sessionCount: trend.length,
  ),
  previousValue: previous,
  averageHeartRateBpm: bpm,
  cadenceStepsPerMin: cadence,
);

FuelSummary _fuel({
  int loggedDays = 6,
  bool targets = true,
  double? burned,
  int burnedCount = 0,
  bool burnedEstimate = false,
  double protein = 124,
}) => FuelSummary(
  loggedDays: loggedDays,
  caloriesAverage: 2184,
  proteinAverage: protein,
  carbsAverage: 260,
  fatAverage: 72,
  previousCaloriesAverage: 2310,
  previousProteinAverage: 131,
  previousCarbsAverage: 255,
  previousFatAverage: 78,
  trainingCaloriesAverage: 2290,
  trainingLoggedDays: 3,
  restCaloriesAverage: 2040,
  restLoggedDays: 4,
  burnedKcalAverage: burned,
  burnedSessionCount: burnedCount,
  burnedIsEstimate: burnedEstimate,
  targetCalories: targets ? 2500 : 0,
  targetProtein: targets ? 150 : 0,
  targetCarbs: targets ? 300 : 0,
  targetFat: targets ? 80 : 0,
);

void main() {
  final out = _out;
  if (out == null) {
    test('Stats gallery (set STATS_GALLERY_OUT to render)', () {}, skip: true);
    return;
  }

  late WorkoutRepository repo;
  late WorkoutState workoutState;
  late SettingsState settingsState;
  late OmniThemeColors colors;

  setUpAll(() async {
    Directory(out).createSync(recursive: true);
    await _loadFonts();
  });

  tearDownAll(() {
    File('$out/manifest.json').writeAsStringSync(
      const JsonEncoder.withIndent(' ').convert(_manifest),
    );
  });

  setUp(() async {
    repo = await MockRepositoryHarness().open();
    workoutState = WorkoutState(repo);
    settingsState = SettingsState(repo, FakePreferencesService());
    await settingsState.initialize();
    OmniTheme.activeTheme = settingsState.appTheme;
    colors = OmniTheme.colorsForTheme(settingsState.appTheme);
  });

  ThemeData theme() {
    final t = settingsState.appTheme;
    final base = buildTheme(
      theme: t,
      brightness: Brightness.dark,
      background: colors.backgroundBottom,
      surface: colors.surface,
      secondary: colors.secondary,
      textPrimary: colors.textDominant,
      textSecondary: colors.textSecondary,
      divider: colors.divider,
      onPrimary: getOnPrimaryForTheme(t),
      onSecondary: getOnSecondaryForTheme(t),
    );
    return base.copyWith(
      textTheme: base.textTheme.apply(
        fontFamilyFallback: const ['GallerySymbols'],
      ),
    );
  }

  const shotKey = Key('gallery_shot');

  Future<void> capture(
    WidgetTester tester, {
    required String id,
    required String group,
    required String title,
    required String when,
  }) async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(shotKey),
    );
    final texts = <String>[];
    for (final element
        in find
            .descendant(of: find.byKey(shotKey), matching: find.byType(Text))
            .evaluate()) {
      final widget = element.widget as Text;
      final text = widget.data ?? widget.textSpan?.toPlainText();
      if (text != null && text.trim().isNotEmpty) texts.add(text);
    }
    late int width;
    late int height;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      width = image.width;
      height = image.height;
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      File('$out/$id.png').writeAsBytesSync(data!.buffer.asUint8List());
    });
    _manifest.add({
      'id': id,
      'group': group,
      'title': title,
      'when': when,
      'texts': texts,
      'w': width ~/ 2,
      'h': height ~/ 2,
    });
  }

  void view(WidgetTester tester, Size size) {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
  }

  /// One block on the page background, as wide as a phone.
  Future<void> block(
    WidgetTester tester, {
    required String id,
    required String group,
    required String title,
    required String when,
    required Widget child,
  }) async {
    view(tester, const Size(400, 3000));
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme(),
        home: Scaffold(
          backgroundColor: colors.backgroundBottom,
          body: SingleChildScrollView(
            child: RepaintBoundary(
              key: shotKey,
              child: Container(
                width: 400,
                color: colors.backgroundBottom,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await capture(tester, id: id, group: group, title: title, when: when);
  }

  /// A whole screen at [size].
  Future<void> screen(
    WidgetTester tester, {
    required Widget child,
    required Size size,
  }) async {
    view(tester, size);
    await tester.pumpWidget(
      RepaintBoundary(
        key: shotKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: theme(),
          builder: (context, child) =>
              OmniGradientBackground(child: child ?? const SizedBox.shrink()),
          home: child,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Widget signals(
    List<SignalCard> cards, {
    bool quiet = false,
    int? lockedRatedWeeks,
    List<String> waiting = const [],
  }) => SignalsLayerSection(
    data: SignalsData(cards: cards, showQuietLine: quiet),
    themeColors: colors,
    onDismiss: (_) {},
    lockedRatedWeeks: lockedRatedWeeks,
    waiting: waiting,
  );

  // ── Whole screens ─────────────────────────────────────────────────────────

  const gScreens = '1. Whole screens';

  testWidgets('first-use card', (tester) async {
    await screen(
      tester,
      size: const Size(400, 640),
      child: StatsScreen(
        workoutState: workoutState,
        settingsState: settingsState,
        showPrimerHelp: true,
      ),
    );
    await capture(
      tester,
      id: 'screen-first-use',
      group: gScreens,
      title: 'Before your first workout',
      when: 'No finished workout exists yet.',
    );
  });

  testWidgets('primer sheet', (tester) async {
    await screen(
      tester,
      size: const Size(400, 760),
      child: StatsScreen(
        workoutState: workoutState,
        settingsState: settingsState,
        showPrimerHelp: true,
      ),
    );
    await tester.tap(find.byKey(const Key('stats_primer_help')));
    await tester.pumpAndSettle();
    await capture(
      tester,
      id: 'screen-primer',
      group: gScreens,
      title: 'The "How Stats works" sheet',
      when:
          'Opens by itself on the first Stats tap, and again from the "?" or '
          'the "How Stats works" button.',
    );
  });

  testWidgets('day one', (tester) async {
    await tester.runAsync(() => _seedHistory(repo, oneSessionOnly: true));
    await screen(
      tester,
      size: const Size(400, 760),
      child: StatsScreen(
        workoutState: workoutState,
        settingsState: settingsState,
        showPrimerHelp: true,
      ),
    );
    await capture(
      tester,
      id: 'screen-day-one',
      group: gScreens,
      title: 'After one workout',
      when: 'One finished workout (a 30-minute run), not rated, no food logged.',
    );
  });

  testWidgets('week eleven', (tester) async {
    await tester.runAsync(() => _seedHistory(repo));
    await screen(
      tester,
      size: const Size(400, 2360),
      child: StatsScreen(
        workoutState: workoutState,
        settingsState: settingsState,
        showPrimerHelp: true,
      ),
    );
    await capture(
      tester,
      id: 'screen-week-eleven',
      group: gScreens,
      title: 'After eleven weeks',
      when:
          'Eleven weeks of rated lifting, running, holds and bag work, with '
          'food logged on most of the last 14 days and three weigh-ins.',
    );
  });

  testWidgets('load failure', (tester) async {
    await block(
      tester,
      id: 'screen-load-failure',
      group: gScreens,
      title: 'When Stats cannot load',
      when: 'Reading the saved workouts failed.',
      child: SizedBox(
        height: 200,
        child: LoadFailureView(
          message: 'Could not load your stats.',
          onRetry: () {},
        ),
      ),
    );
  });

  // ── Training Mix ──────────────────────────────────────────────────────────

  const gMix = '2. Training Mix';
  final window = StatsProgressService.statsWindow();

  final mixStates = <(String, String, String, MixLayerData)>[
    (
      'mix-time-counting',
      'Time, while effort is still locked',
      'Fewer than 4 of the last 12 weeks hold a rated workout (here 2).',
      MixLayerData(
        measure: MixMeasure.time,
        segments: mixSegments(const {
          ExerciseSection.resistance: 620,
          ExerciseSection.cardio: 150,
          ExerciseSection.isometric: 40,
        }),
        baselineSegments: const [],
        unratedSessionCount: 6,
        ratedWeeks: 2,
        weeks: _weeks(),
        lastSessionDay: _day(1, hour: 0),
      ),
    ),
    (
      'mix-time-unrated',
      'Time, because too much is unrated',
      '4 or more rated weeks, but over a quarter of the last 4 weeks is '
          'unrated.',
      MixLayerData(
        measure: MixMeasure.time,
        segments: mixSegments(const {
          ExerciseSection.resistance: 620,
          ExerciseSection.cardio: 150,
        }),
        baselineSegments: const [],
        unratedSessionCount: 5,
        ratedWeeks: 6,
        weeks: _weeks(),
        lastSessionDay: _day(1, hour: 0),
      ),
    ),
    (
      'mix-effort',
      'Effort, with your usual split',
      '4 or more rated weeks and most of the last 4 weeks rated.',
      MixLayerData(
        measure: MixMeasure.load,
        segments: mixSegments(const {
          ExerciseSection.resistance: 1900,
          ExerciseSection.cardio: 420,
          ExerciseSection.sports: 300,
          ExerciseSection.isometric: 60,
        }),
        baselineSegments: mixSegments(const {
          ExerciseSection.resistance: 5200,
          ExerciseSection.cardio: 1900,
          ExerciseSection.sports: 500,
        }),
        unratedSessionCount: 0,
        ratedWeeks: 10,
        weeks: _weeks(),
        lastSessionDay: _day(1, hour: 0),
      ),
    ),
    (
      'mix-empty-window',
      'After a break of more than 4 weeks',
      'No workout in the last 4 weeks, but older ones exist.',
      MixLayerData(
        measure: MixMeasure.time,
        segments: const [],
        baselineSegments: const [],
        unratedSessionCount: 0,
        ratedWeeks: 0,
        weeks: const [],
        lastSessionDay: _day(41, hour: 0),
        windowIsEmpty: true,
      ),
    ),
  ];

  for (final (id, title, cond, layer) in mixStates) {
    testWidgets(id, (tester) async {
      await block(
        tester,
        id: id,
        group: gMix,
        title: title,
        when: cond,
        child: MixLayerSection(layer: layer, window: window, themeColors: colors),
      );
    });
  }

  // ── The Signals block around the cards ────────────────────────────────────

  const gFrame = '3. Signals: locked, quiet and waiting';
  final proteinCard = _card(
    'protein-consistency',
    SignalKind.caution,
    proteinConsistencyCopy(
      const ProteinConsistency(
        mode: ProteinComparisonMode.target,
        average: 124,
        comparisonMean: 150,
        shortfallPercent: 17,
        perKg: 1.6,
      ),
    ).observation,
    proteinConsistencyCopy(
      const ProteinConsistency(
        mode: ProteinComparisonMode.target,
        average: 124,
        comparisonMean: 150,
        shortfallPercent: 17,
        perKg: 1.6,
      ),
    ).suggestion,
  );

  testWidgets('frame states', (tester) async {
    await block(
      tester,
      id: 'signals-locked-0',
      group: gFrame,
      title: 'Locked, nothing rated yet',
      when: 'No rated week yet, and no signal has anything to say.',
      child: SignalsLockedSection(ratedWeeks: 0, themeColors: colors),
    );
    await block(
      tester,
      id: 'signals-locked-3-waiting',
      group: gFrame,
      title: 'Locked, with waiting lines',
      when:
          '3 rated weeks; food logged on 7 of the last 14 days; a couple of '
          'runs with heart rate from the watch.',
      child: SignalsLockedSection(
        ratedWeeks: 3,
        themeColors: colors,
        waiting: [
          proteinConsistencyWaitingLine(7)!,
          cardioEfficiencyWaitingLine(2)!,
        ],
      ),
    );
    await block(
      tester,
      id: 'signals-waiting-one-day',
      group: gFrame,
      title: 'Waiting line, one day short',
      when: 'Food logged on 9 of the last 14 days.',
      child: SignalsLockedSection(
        ratedWeeks: 1,
        themeColors: colors,
        waiting: [proteinConsistencyWaitingLine(9)!],
      ),
    );
    await block(
      tester,
      id: 'signals-card-with-hint',
      group: gFrame,
      title: 'A card while the rest is locked',
      when:
          'Fewer than 4 rated weeks, but a signal that needs no ratings '
          'speaks.',
      child: signals([proteinCard], lockedRatedWeeks: 2),
    );
    await block(
      tester,
      id: 'signals-quiet',
      group: gFrame,
      title: 'Unlocked, nothing to say',
      when: '4 or more rated weeks and no signal qualifies.',
      child: signals(const [], quiet: true),
    );
    await block(
      tester,
      id: 'signals-quiet-waiting',
      group: gFrame,
      title: 'Unlocked, nothing to say, one signal waiting',
      when: '4 or more rated weeks, no card, food logged on 4 of 14 days.',
      child: signals(
        const [],
        quiet: true,
        waiting: [proteinConsistencyWaitingLine(4)!],
      ),
    );
    await block(
      tester,
      id: 'signals-two-cards',
      group: gFrame,
      title: 'Two cards together',
      when:
          'One "Worth a look" card and one "Positive" card qualify. Two is '
          'the most ever shown.',
      child: signals([
        proteinCard,
        _card(
          'hold-progress',
          SignalKind.positive,
          holdProgressObservation(
            const HoldProgressResult(
              name: 'Plank',
              exerciseId: 'g-plank',
              recentSecs: 100,
              previousSecs: 84,
            ),
            weeks: 4,
          ),
        ),
      ]),
    );
  });

  // ── Every signal card ─────────────────────────────────────────────────────

  const gCards = '4. Signal cards';

  SignalCard fromCopy(String id, SignalKind kind, ({String observation, String? suggestion}) c) =>
      _card(id, kind, c.observation, c.suggestion);

  final progression = progressionRateCopy(
    ProgressionRate.fromCounts(
      recentProgressions: 13,
      recentCounted: 16,
      priorProgressions: 10,
      priorCounted: 16,
    ),
  );
  final mixShiftGrown = modalityMixShiftCopy(
    const ModalityMixShift(
      section: ExerciseSection.cardio,
      recentPercent: 6,
      baselinePercent: 18,
      grownSection: ExerciseSection.resistance,
      grownPercent: 81,
    ),
  );
  final mixShiftPlain = modalityMixShiftCopy(
    const ModalityMixShift(
      section: ExerciseSection.isometric,
      recentPercent: 4,
      baselinePercent: 12,
      grownSection: null,
      grownPercent: null,
    ),
  );
  final interferenceRise = crossModalityInterferenceCopy(
    const Interference(
      k: 3,
      n: 4,
      lo: 11,
      hi: 16,
      hasSportsLoadRise: true,
      sportsLoadRisePercent: 35,
    ),
  );
  final interferencePlain = crossModalityInterferenceCopy(
    const Interference(
      k: 3,
      n: 3,
      lo: 12,
      hi: 12,
      hasSportsLoadRise: false,
      sportsLoadRisePercent: 0,
    ),
  );
  final fuelLoad = fuelVsLoadCopy(const FuelVsLoad(loadRisePercent: 28));
  final proteinUsualKg = proteinConsistencyCopy(
    const ProteinConsistency(
      mode: ProteinComparisonMode.ownBaseline,
      average: 104,
      comparisonMean: 128,
      shortfallPercent: 19,
      perKg: 1.3,
    ),
  );
  final proteinUsualNoKg = proteinConsistencyCopy(
    const ProteinConsistency(
      mode: ProteinComparisonMode.ownBaseline,
      average: 104,
      comparisonMean: 128,
      shortfallPercent: 19,
      perKg: null,
    ),
  );
  final highLoadHabit = sustainedHighLoadCopy(
    const SustainedHighLoad(streakWeeks: 6, easierGapWeeks: 4),
  );
  final highLoadPlain = sustainedHighLoadCopy(
    const SustainedHighLoad(streakWeeks: 5, easierGapWeeks: null),
  );
  final driftLift = cardioEfficiencyDriftCopy(
    const CardioEfficiencyDriftResult(
      exerciseId: 'g-run',
      exerciseName: 'Outdoor Run',
      anchorSecs: 1800,
      driftPercent: 7,
      liftRisePercent: 22,
    ),
  );
  final driftPlain = cardioEfficiencyDriftCopy(
    const CardioEfficiencyDriftResult(
      exerciseId: 'g-run',
      exerciseName: 'Outdoor Run',
      anchorSecs: 1800,
      driftPercent: 5,
      liftRisePercent: null,
    ),
  );

  final cards = <(String, String, String, SignalCard)>[
    (
      'card-progression',
      'Progression rate',
      'At least 8 lift-sessions in each of the last two 4-week spans; 75% or '
          'more of the recent ones matched or beat the time before, and that '
          'share is up by 10 points or more. Needs no ratings.',
      _card('progression-rate', SignalKind.positive, progression.observation,
          progression.suggestion),
    ),
    (
      'card-consistency',
      'Consistency',
      'At least 6 finished weeks of history; last week had 3 or more '
          'workouts and at least one more than your weekly average. Needs no '
          'ratings.',
      _card(
        'consistency',
        SignalKind.positive,
        consistencyObservation(
          const ConsistencyResult(lastWeekSessions: 5, weeks: 8, totalSessions: 28),
        ),
      ),
    ),
    (
      'card-hold',
      'Hold progress',
      'A hold trained in 3 or more workouts in the last 4 weeks whose longest '
          'hold is up by 10 seconds and 10% on the 4 weeks before. Needs no '
          'ratings.',
      _card(
        'hold-progress',
        SignalKind.positive,
        holdProgressObservation(
          const HoldProgressResult(
            name: 'Plank',
            exerciseId: 'g-plank',
            recentSecs: 100,
            previousSecs: 84,
          ),
          weeks: 4,
        ),
      ),
    ),
    (
      'card-gap',
      'Training gap',
      'At least 6 weeks of history, 5 or more days since the last workout, '
          'and longer than any gap in the last 8 weeks. Needs no ratings.',
      _card(
        'training-gap',
        SignalKind.caution,
        trainingGapObservation(const TrainingGapResult(days: 9, longestBefore: 4)),
      ),
    ),
    (
      'card-gap-one-day',
      'Training gap, after training daily',
      'Same rule, when the longest earlier gap was a single day.',
      _card(
        'training-gap',
        SignalKind.caution,
        trainingGapObservation(const TrainingGapResult(days: 5, longestBefore: 1)),
      ),
    ),
    (
      'card-protein-target',
      'Protein, against your target',
      'Food logged on 10 of the last 14 days, 2 or more lifting workouts, a '
          'protein target set, and the average 15% or more under it. Body '
          'weight on file adds the g/kg figure. Needs no ratings.',
      proteinCard,
    ),
    (
      'card-protein-usual',
      'Protein, against your usual',
      'Same, with no protein target: compared with your own earlier weeks. '
          'Body weight on file.',
      _card('protein-consistency', SignalKind.caution,
          proteinUsualKg.observation, proteinUsualKg.suggestion),
    ),
    (
      'card-protein-usual-no-weight',
      'Protein, against your usual, no body weight',
      'Same, with no target and no body weight on file: no second line.',
      _card('protein-consistency', SignalKind.caution,
          proteinUsualNoKg.observation, proteinUsualNoKg.suggestion),
    ),
    (
      'card-cardio-drift',
      'Cardio efficiency',
      '3 or more similar-length efforts of one cardio exercise in the last 2 '
          'weeks and in the 2 weeks a month earlier, each with a measured '
          'distance and watch heart rate; 5% or more worse. Needs no ratings.',
      _card('cardio-efficiency-drift', SignalKind.caution,
          driftPlain.observation, driftPlain.suggestion),
    ),
    (
      'card-cardio-drift-lifting',
      'Cardio efficiency, with lifting up',
      'Same, when lifting effort over the last 4 weeks is also 15% or more '
          'above usual.',
      _card('cardio-efficiency-drift', SignalKind.caution,
          driftLift.observation, driftLift.suggestion),
    ),
    (
      'card-high-load',
      'Sustained high load',
      '5 or more finished weeks in a row at 110% or more of your usual '
          'effort, against a 12-week baseline. Needs 4 rated weeks.',
      _card('sustained-high-load', SignalKind.caution,
          highLoadPlain.observation, highLoadPlain.suggestion),
    ),
    (
      'card-high-load-habit',
      'Sustained high load, with your old habit',
      'Same, when your earlier history shows an easier week every 3 to 5 '
          'weeks.',
      _card('sustained-high-load', SignalKind.caution,
          highLoadHabit.observation, highLoadHabit.suggestion),
    ),
    (
      'card-fuel-load',
      'Fuel vs load',
      'Effort up 20% or more over the last 3 weeks against the 3 before, '
          'while average calories rose 5% or less; food logged 5 days in each '
          'of those 6 weeks. Needs 4 rated weeks.',
      _card('fuel-vs-load', SignalKind.caution, fuelLoad.observation,
          fuelLoad.suggestion),
    ),
    (
      'card-mix-shift',
      'Mix shift',
      'A kind of training you usually do (10% or more of your effort) has '
          'fallen to under half its usual share over 4 weeks. Needs 4 rated '
          'weeks.',
      _card('modality-mix-shift', SignalKind.caution,
          mixShiftPlain.observation, mixShiftPlain.suggestion),
    ),
    (
      'card-mix-shift-grown',
      'Mix shift, naming what grew',
      'Same, when a different kind of training is now the biggest share.',
      _card('modality-mix-shift', SignalKind.caution,
          mixShiftGrown.observation, mixShiftGrown.suggestion),
    ),
    (
      'card-interference',
      'After hard sports sessions',
      '8 or more rated sports sessions in 90 days; after the hardest quarter '
          'of them, the next lifting day (within 36 hours) came in 10% or '
          'more below usual, 3 or more times in 45 days. Needs 4 rated weeks.',
      _card('cross-modality-interference', SignalKind.caution,
          interferencePlain.observation, interferencePlain.suggestion),
    ),
    (
      'card-interference-rise',
      'After hard sports sessions, with sports up',
      'Same, when sports effort is also up 30% or more over 3 weeks.',
      _card('cross-modality-interference', SignalKind.caution,
          interferenceRise.observation, interferenceRise.suggestion),
    ),
  ];

  // Keep the analyzer honest about the helper used only for its shape.
  assert(fromCopy('x', SignalKind.positive, (observation: 'o', suggestion: null)).id == 'x');

  for (final (id, title, cond, card) in cards) {
    testWidgets(id, (tester) async {
      await block(
        tester,
        id: id,
        group: gCards,
        title: title,
        when: cond,
        child: signals([card]),
      );
    });
  }

  // ── Exercise rows ─────────────────────────────────────────────────────────

  const gRows = '5. Exercise rows';

  testWidgets('rows', (tester) async {
    NativeValue v(NativeMetric m, double x, {bool est = false, double? added}) =>
        NativeValue(metric: m, value: x, estimated: est, addedWeightKg: added);
    await block(
      tester,
      id: 'rows-all-kinds',
      group: gRows,
      title: 'Every kind of row',
      when:
          'One row per exercise trained in the last 4 weeks. "new" means '
          'nothing to compare with; the dash means no change.',
      child: InstrumentList(
        window: window,
        themeColors: colors,
        workoutState: workoutState,
        settingsState: settingsState,
        sections: [
          InstrumentSectionData(
            section: ExerciseSection.resistance,
            trainingDayCount: 8,
            rows: [
              _row('Back Squat', ExerciseSection.resistance,
                  v(NativeMetric.estimatedOneRepMax, 134.2),
                  previous: v(NativeMetric.estimatedOneRepMax, 122.5),
                  trend: [124, 127, 130, 134.2]),
              _row('Bench Press', ExerciseSection.resistance,
                  v(NativeMetric.estimatedOneRepMax, 88),
                  previous: v(NativeMetric.estimatedOneRepMax, 91),
                  trend: [91, 90, 88]),
              _row('Pull-Up', ExerciseSection.resistance,
                  v(NativeMetric.reps, 9, added: 5),
                  previous: v(NativeMetric.reps, 9),
                  trend: [8, 9, 9]),
              _row('Face Pull', ExerciseSection.resistance,
                  v(NativeMetric.estimatedOneRepMax, 32.7)),
            ],
          ),
          InstrumentSectionData(
            section: ExerciseSection.cardio,
            trainingDayCount: 4,
            rows: [
              _row('Outdoor Run', ExerciseSection.cardio,
                  v(NativeMetric.pace, 348),
                  previous: v(NativeMetric.pace, 358),
                  trend: [358, 355, 350, 348],
                  bpm: 152,
                  cadence: 168),
              _row('Treadmill', ExerciseSection.cardio,
                  v(NativeMetric.pace, 372, est: true),
                  previous: v(NativeMetric.pace, 365)),
              _row('Stationary Bike', ExerciseSection.cardio,
                  v(NativeMetric.duration, 2400),
                  previous: v(NativeMetric.duration, 1800),
                  trend: [600, 600, 600, 600]),
            ],
          ),
          InstrumentSectionData(
            section: ExerciseSection.isometric,
            trainingDayCount: 4,
            rows: [
              _row(
                'Plank',
                ExerciseSection.isometric,
                const NativeValue(
                  metric: NativeMetric.hold,
                  value: 100,
                  secondaryMetric: NativeMetric.duration,
                  secondaryValue: 1128,
                ),
                previous: v(NativeMetric.hold, 84),
                trend: [84, 90, 96, 100],
              ),
            ],
          ),
          InstrumentSectionData(
            section: ExerciseSection.sports,
            trainingDayCount: 2,
            rows: [
              _row(
                'Heavy Bag',
                ExerciseSection.sports,
                const NativeValue(
                  metric: NativeMetric.rounds,
                  value: 12,
                  secondaryMetric: NativeMetric.roundMinutes,
                  secondaryValue: 36,
                ),
                previous: v(NativeMetric.rounds, 18),
                bpm: 141,
              ),
            ],
          ),
        ],
      ),
    );
  });

  // ── Fuel ──────────────────────────────────────────────────────────────────

  const gFuel = '6. Fuel';
  final fuelStates = <(String, String, String, FuelSummary)>[
    (
      'fuel-targets',
      'With daily targets',
      'Food logged on 3 or more of the last 7 finished days, targets set. '
          'Protein under its target is the one figure shown in red.',
      _fuel(burned: 312, burnedCount: 5, burnedEstimate: true),
    ),
    (
      'fuel-no-targets',
      'Without targets',
      'Same, with no targets: each figure is compared with the 7 days '
          'before. Calories burned measured by the watch.',
      _fuel(targets: false, burned: 287, burnedCount: 1),
    ),
    (
      'fuel-no-burned',
      'No calories-burned figure',
      'Same, when no workout in the 7 days has a calories-burned figure.',
      _fuel(protein: 156),
    ),
    (
      'fuel-too-few-days',
      'Too few logged days',
      'Food logged on fewer than 3 of the last 7 finished days.',
      _fuel(loggedDays: 2),
    ),
  ];
  for (final (id, title, cond, summary) in fuelStates) {
    testWidgets(id, (tester) async {
      await block(
        tester,
        id: id,
        group: gFuel,
        title: title,
        when: cond,
        child: FuelSection(summary: summary, themeColors: colors, onTap: () {}),
      );
    });
  }

  // ── Weight ────────────────────────────────────────────────────────────────

  const gWeight = '7. Weight';
  testWidgets('weight', (tester) async {
    for (final (id, title, change) in [
      ('weight-down', 'Weight down', -1.2),
      ('weight-up', 'Weight up', 0.8),
      ('weight-same', 'No change', 0.0),
    ]) {
      await block(
        tester,
        id: id,
        group: gWeight,
        title: title,
        when:
            'Two or more weigh-ins in the last 4 weeks, at least 7 days '
            'apart.',
        child: WeightTrendRow(
          trend: WeightTrend(latestKg: 79.2, changeKg: change),
          settingsState: settingsState,
          themeColors: colors,
        ),
      );
    }
  });

  // ── Records & Trends, Exercise Progress ───────────────────────────────────

  const gRecords = '8. Records & Trends and Exercise Progress';

  testWidgets('records', (tester) async {
    await tester.runAsync(() => _seedHistory(repo));
    await screen(
      tester,
      size: const Size(400, 1500),
      child: RecordsAndTrendsScreen(
        workoutState: workoutState,
        settingsState: settingsState,
      ),
    );
    await capture(
      tester,
      id: 'records',
      group: gRecords,
      title: 'Records & Trends',
      when: 'The chart icon in the Stats header, after eleven weeks.',
    );
  });

  testWidgets('records empty', (tester) async {
    await screen(
      tester,
      size: const Size(400, 420),
      child: RecordsAndTrendsScreen(
        workoutState: workoutState,
        settingsState: settingsState,
      ),
    );
    await capture(
      tester,
      id: 'records-empty',
      group: gRecords,
      title: 'Records & Trends, before any workout',
      when: 'No finished workout exists yet.',
    );
  });

  for (final (id, exercise, title, tall) in [
    ('progress-lift', 'g-bench', 'Exercise Progress, a lift', 1180.0),
    ('progress-run', 'g-run', 'Exercise Progress, a run', 1180.0),
    ('progress-hold', 'g-plank', 'Exercise Progress, a hold', 1180.0),
  ]) {
    testWidgets(id, (tester) async {
      await tester.runAsync(() => _seedHistory(repo));
      await screen(
        tester,
        size: Size(400, tall),
        child: ExerciseProgressScreen(
          workoutState: workoutState,
          settingsState: settingsState,
          exerciseId: exercise,
        ),
      );
      await capture(
        tester,
        id: id,
        group: gRecords,
        title: title,
        when: 'Tapping an exercise row, after eleven weeks.',
      );
    });
  }

  testWidgets('progress one session', (tester) async {
    await tester.runAsync(() => _seedHistory(repo, oneSessionOnly: true));
    await screen(
      tester,
      size: const Size(400, 560),
      child: ExerciseProgressScreen(
        workoutState: workoutState,
        settingsState: settingsState,
        exerciseId: 'g-run',
      ),
    );
    await capture(
      tester,
      id: 'progress-one-session',
      group: gRecords,
      title: 'Exercise Progress, one session',
      when: 'An exercise trained on a single day.',
    );
  });
}
