// The Stats and Records & Trends heading consistency guards (plan 113,
// scenarios S-18701…S-18707, S-18710 and S-18712…S-18716). They were written
// guards-first against the unchanged screen: S-18701…S-18705 were red then, for
// the reason the plan's table names; S-18706, S-18707 and S-18710 were green.
// The production change landed in the same PR, and these tests pin it.
//
// Plan: docs/plans/2026-11-04-113-stats-heading-consistency-plan/
// 2026-11-04-113-stats-heading-consistency-plan.md
//
// Mock harness only (D-18709): opened and seeded in `setUp`, never inside a
// `testWidgets` body. The theme is set on `OmniTheme.activeTheme` and restored
// in `tearDown`.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/metric_ids.dart';
import 'package:omnitrain/core/constants/omni_theme.dart';
import 'package:omnitrain/core/models/exercise_metric.dart';
import 'package:omnitrain/core/models/instrument_list.dart';
import 'package:omnitrain/core/models/signals.dart';
import 'package:omnitrain/core/models/training_load.dart';
import 'package:omnitrain/core/services/signals/signal.dart';
import 'package:omnitrain/core/services/stats_progress_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/features/stats/exercise_progress_screen.dart';
import 'package:omnitrain/features/stats/records_and_trends_screen.dart';
import 'package:omnitrain/features/stats/stats_screen.dart';
import 'package:omnitrain/features/stats/widgets/recent_pr_list.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:omnitrain/widgets/layout/omni_card_header.dart';
import 'package:omnitrain/widgets/layout/omni_surface.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/repository_harness.dart';

/// Tall enough that every block is laid out (the plan's default viewport).
const Size _kTallViewport = Size(400, 2400);

/// The plan's narrow viewport (`SupportedViewport.minWidth`).
const Size _kNarrowViewport = Size(360, 2400);

/// F-A's adversarial long exercise name (S-18706).
const String _kExLongName =
    'Single-Arm Dumbbell Romanian Deadlift With Pause And Tempo Control';

/// F-A's one positive stub card, injected through the screen's `signals:`
/// seam the way `signals_layer_screen_test.dart` builds its stubs.
class _PositiveStub implements Signal {
  const _PositiveStub();

  @override
  final String id = 'p-1';

  @override
  final SignalKind kind = SignalKind.positive;

  @override
  final int priority = 10;

  @override
  final bool needsRatedWeeks = true;

  @override
  Future<SignalCard?> evaluate(SignalContext context) async => SignalCard(
    id: id,
    kind: kind,
    priority: priority,
    title: 'Positive',
    observation: 'You rated four weeks of training.',
  );

  @override
  Future<String?> waitingFor(SignalContext context) async => null;
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

/// One completed session with one segment, rated [rating] when given.
Future<void> _seedSession(
  WorkoutRepository repo, {
  required String sessionId,
  required int startedAtMs,
  required int endedAtMs,
  int? rating,
}) async {
  await repo.createSession(
    TrainingSession(
      id: sessionId,
      ownerUserId: 'user-1',
      startedAtMs: startedAtMs,
      endedAtMs: endedAtMs,
      sessionFeeling: rating,
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

/// One completed session [daysAgo] days back at 9 o'clock, an hour long.
Future<void> _seedDaySession(
  WorkoutRepository repo, {
  required String sessionId,
  required int daysAgo,
  int? rating,
}) async {
  final start = _at(daysAgo, 9);
  await _seedSession(
    repo,
    sessionId: sessionId,
    startedAtMs: start,
    endedAtMs: start + 3600000,
    rating: rating,
  );
}

/// The repository's food log, emptied: the Mock harness opens with
/// `SeedData.sampleConsumedFoods()` already written.
Future<void> _clearConsumedFoods(WorkoutRepository repo) async {
  const farFutureMs = 4102444800000; // 2100-01-01
  for (final row in await repo.getConsumedFoodsInRange(0, farFutureMs)) {
    await repo.deleteConsumedFood(row.id);
  }
}

/// The repository's weigh-ins, emptied (the Mock harness may open with
/// samples).
Future<void> _clearWeights(WorkoutRepository repo) async {
  for (final entry in await repo.getMeasurementHistory('bodyweight')) {
    await repo.deleteMeasurementEntry(entry.id);
  }
}

/// One logged `ConsumedFood` on the local day [daysAgo] days back.
///
/// Fat and fibre default to zero and the consumed amount equals the
/// reference, so with the defaults the row's calories are
/// `4 × (protein + carbs)` and a fixture can name its days in round kcal.
Future<void> _seedFood(
  WorkoutRepository repo, {
  required String id,
  required int daysAgo,
  required double protein,
  required double carbs,
  double fat = 0,
  double fiber = 0,
}) async {
  final dateMs = _day(daysAgo).millisecondsSinceEpoch;
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
      fiber: fiber,
      fat: fat,
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

/// A logged day of [calories] kcal and [protein] g, as the fixture's own macro
/// pair: `4 × (protein + carbs)` with no fat (`fuel_row_screen_test.dart`
/// S-1101's values).
Future<void> _seedDay(
  WorkoutRepository repo, {
  required String id,
  required int daysAgo,
  required double protein,
  required double calories,
}) => _seedFood(
  repo,
  id: id,
  daysAgo: daysAgo,
  protein: protein,
  carbs: (calories / 4) - protein,
);

/// One weigh-in of [kg] on the local day [daysAgo] days back.
Future<void> _seedWeight(
  WorkoutRepository repo,
  String id,
  double kg,
  int daysAgo,
) => repo.saveMeasurementEntry(
  BodyMeasurementEntry(
    id: id,
    measurementType: 'bodyweight',
    value: kg,
    unitId: MetricIds.unitKg,
    recordedAtMs: _at(daysAgo, 12),
  ),
);

/// F-A, every block: one rated session per exercise (effort rating 6), the
/// 1/8/15/22 day spacing that puts rated work in four distinct weeks, one
/// effort each, three logged food days and two weigh-ins.
Future<void> _seedEveryBlock(WorkoutRepository repo) async {
  await _clearConsumedFoods(repo);
  await _clearWeights(repo);

  await seedExercise(
    repo,
    id: 'ex-squat',
    name: 'Back Squat',
    capabilities: const ['load', 'reps'],
  );
  await seedExercise(
    repo,
    id: 'ex-long',
    name: _kExLongName,
    capabilities: const ['load', 'reps'],
  );
  await seedExercise(
    repo,
    id: 'ex-plank',
    name: 'Plank',
    capabilities: const ['hold'],
  );
  await seedExercise(
    repo,
    id: 'ex-bjj',
    name: 'BJJ',
    capabilities: const ['rounds'],
  );

  // ex-squat, daysAgo 1: 3×5 @ 100 kg.
  await _seedDaySession(repo, sessionId: 's-squat', daysAgo: 1, rating: 6);
  await seedSetEffort(
    repo,
    segmentId: 'seg-s-squat',
    effortId: 'eff-s-squat',
    exerciseId: 'ex-squat',
    entryCount: 3,
    hasExtraWeight: false,
    weightFactor: 100.0,
    repsBase: 5,
  );

  // ex-long, daysAgo 8: 3×8 @ 30 kg.
  await _seedDaySession(repo, sessionId: 's-long', daysAgo: 8, rating: 6);
  await seedSetEffort(
    repo,
    segmentId: 'seg-s-long',
    effortId: 'eff-s-long',
    exerciseId: 'ex-long',
    entryCount: 3,
    hasExtraWeight: false,
    weightFactor: 30.0,
    repsBase: 8,
  );

  // ex-run, daysAgo 15: 30 min, 5 km (the helper seeds the exercise itself).
  await _seedDaySession(repo, sessionId: 's-run', daysAgo: 15, rating: 6);
  await seedTimedEntries(
    repo,
    segmentId: 'seg-s-run',
    effortId: 'eff-s-run',
    entryCount: 1,
    secondsPerEntry: 1800,
    metresBase: 5000.0,
    exerciseId: 'ex-run',
    exerciseName: 'Treadmill Run',
  );

  // ex-plank, daysAgo 22: 3 holds × 60 s.
  await _seedDaySession(repo, sessionId: 's-plank', daysAgo: 22, rating: 6);
  await seedHoldEffort(
    repo,
    segmentId: 'seg-s-plank',
    effortId: 'eff-s-plank',
    exerciseId: 'ex-plank',
    entryCount: 3,
    secondsPerEntry: 60,
  );

  // ex-bjj, daysAgo 2: 5 rounds × 5 min.
  await _seedDaySession(repo, sessionId: 's-bjj', daysAgo: 2, rating: 6);
  await seedRoundEffort(
    repo,
    segmentId: 'seg-s-bjj',
    effortId: 'eff-s-bjj',
    exerciseId: 'ex-bjj',
    rounds: [
      for (var i = 0; i < 5; i++) roundInstance('eff-s-bjj', i, durationSecs: 300),
    ],
  );

  await _seedDay(repo, id: 'food-1', daysAgo: 1, protein: 50, calories: 1000);
  await _seedDay(repo, id: 'food-2', daysAgo: 2, protein: 100, calories: 2000);
  await _seedDay(repo, id: 'food-3', daysAgo: 3, protein: 125, calories: 2500);

  await _seedWeight(repo, 'w-27', 80.8, 27);
  await _seedWeight(repo, 'w-0', 80.2, 0);
}

/// F-B, break from training: two completed unrated lifting sessions outside
/// the window, no food, no weigh-ins.
Future<void> _seedBreak(WorkoutRepository repo) async {
  await _clearConsumedFoods(repo);
  await _clearWeights(repo);
  await seedExercise(
    repo,
    id: 'ex-squat',
    name: 'Back Squat',
    capabilities: const ['load', 'reps'],
  );
  for (final entry in const [('s-break-1', 35), ('s-break-2', 60)]) {
    final sessionId = entry.$1;
    await _seedDaySession(repo, sessionId: sessionId, daysAgo: entry.$2);
    await seedSetEffort(
      repo,
      segmentId: 'seg-$sessionId',
      effortId: 'eff-$sessionId',
      exerciseId: 'ex-squat',
      entryCount: 3,
      hasExtraWeight: false,
      weightFactor: 100.0,
      repsBase: 5,
    );
  }
}

/// F-C, zero sessions: an empty repository plus one food on daysAgo 1 — food
/// alone must not produce headings.
Future<void> _seedFoodOnly(WorkoutRepository repo) async {
  await _clearConsumedFoods(repo);
  await _clearWeights(repo);
  await _seedDay(repo, id: 'food-1', daysAgo: 1, protein: 50, calories: 1000);
}

/// The uppercase kind headings (D-18710) and the title-case kinds the Mix
/// legend and bar semantics keep reading (D-18704).
const List<String> _kUppercaseKinds = [
  'RESISTANCE',
  'CARDIO',
  'ISOMETRIC',
  'SPORTS',
];

const List<String> _kTitleCaseKinds = [
  'Resistance ',
  'Cardio ',
  'Isometric ',
  'Sports ',
];

/// Every `Text` on screen that reads an uppercase kind must sit inside an
/// `OmniCardHeader`: the heading is the only place the uppercase form may
/// appear (S-18712).
void _expectNoBareUppercaseKind(WidgetTester tester, String screen) {
  for (final element in find.byType(Text).evaluate()) {
    final text = element.widget as Text;
    if (text.data != null && _kUppercaseKinds.contains(text.data)) {
      expect(
        find.ancestor(
          of: find.byWidget(text),
          matching: find.byType(OmniCardHeader),
        ),
        findsOneWidget,
        reason: '$screen: "${text.data}" only reads as an OmniCardHeader title',
      );
    }
  }
}

/// The one tolerated exception at the narrow viewport: the Recent PRs card's
/// Row overflows at 360 dp with text scale 2.0 — a pre-existing
/// `RecentPRList` layout bug outside this headings-only change's scope
/// (reported to the governor). Everything else fails the test.
bool _isKnownPrListOverflow(String text) {
  return text.contains('A RenderFlex overflowed') &&
      text.contains('recent_pr_list.dart');
}

// ─── the suite ──────────────────────────────────────────────────────────────

void main() {
  group('Stats heading consistency — Mock harness (plan 113)', () {
    late WorkoutRepository repo;
    late WorkoutState workoutState;
    late SettingsState settingsState;

    /// F-A's Instruments sections, read from the service that builds them —
    /// S-18703 reads the kind order from here, never from a literal.
    List<InstrumentSectionData> sections = const [];

    final harness = MockRepositoryHarness();

    setUp(() async {
      repo = await harness.open();
      workoutState = WorkoutState(repo);
      settingsState = SettingsState(repo, fakePreferencesService());
      await settingsState.initialize();
    });

    tearDown(() async {
      OmniTheme.activeTheme = AppTheme.abyssalNeon;
      await harness.close();
    });

    /// Seeds F-A and asserts the fixture's preconditions on the service's own
    /// reads, so the scenarios cannot pass vacuously.
    Future<void> seedEveryBlock() async {
      await _seedEveryBlock(repo);
      final service = StatsProgressService(repo);
      final now = DateTime.now();
      final window = StatsProgressService.statsWindow(now: now);
      sections = await service.computeInstrumentSections(window: window);
      final mix = await service.computeMixLayer(
        window: window,
        now: now,
        startOfWeek: settingsState.startOfWeek,
      );
      expect(
        signalsGateMet(mix),
        isTrue,
        reason: 'F-A precondition: the 1/8/15/22 day spacing must put rated '
            'work in $kTrainingLoadMinRatedWeeks distinct weeks, so the '
            'Signals gate is met',
      );
      expect(
        sections.map((section) => section.section),
        containsAll(ExerciseSection.values),
        reason: 'F-A precondition: every kind must have a section',
      );
    }

    Future<void> pumpStats(
      WidgetTester tester, {
      Size size = _kTallViewport,
      double textScale = 1.0,
      List<Signal> signals = const <Signal>[],
      Object? freshTreeKey,
    }) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: MaterialApp(
            // A keyed pump mounts a fresh element tree: the screens build
            // `const OmniCardHeader` instances, which a retained tree would
            // never rebuild, keeping the first pump's title style.
            key: freshTreeKey == null ? null : ValueKey<Object>(freshTreeKey),
            home: StatsScreen(
              workoutState: workoutState,
              settingsState: settingsState,
              signals: signals,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    /// The block's `OmniCardHeader`, by its title in either case: today the
    /// kind, Fuel and Weight headings are title case; the change under test
    /// uppercases them (D-18704).
    Finder headerOf(String title) => find.byWidgetPredicate(
      (widget) =>
          widget is OmniCardHeader &&
          (widget.title == title || widget.title == title.toUpperCase()),
    );

    /// The `omniCardHeader_title` texts in document order.
    List<String> headerTitles(WidgetTester tester) => tester
        .widgetList<Text>(find.byKey(const Key('omniCardHeader_title')))
        .map((text) => text.data!)
        .toList();

    /// The Mix block's first content: after the change under test it is the
    /// keyed card; today it is the explainer (F-A) or the empty line (F-B).
    /// `first` picks the outermost match in document order either way.
    Finder mixContent() => find
        .byWidgetPredicate(
          (widget) =>
              const Key('mix_layer_card') == widget.key ||
              const Key('mix_explainer') == widget.key ||
              const Key('mix_window_empty') == widget.key,
        )
        .first;

    /// Every block F-A builds, as (name, header, first content widget), in
    /// document order. The kind blocks follow the service's own order.
    List<(String, Finder, Finder)> faBlocks() => [
      ('Mix', headerOf('TRAINING MIX'), mixContent()),
      (
        'Signals',
        headerOf('SIGNALS'),
        find.byKey(const Key('signal_card_p-1')),
      ),
      for (var i = 0; i < sections.length; i++)
        (
          'Instrument ${sections[i].section.label}',
          headerOf(sections[i].section.label),
          i == 0
              ? find.byKey(const Key('instrument_caption'))
              : find.byKey(
                  Key(
                    'instrument_row_'
                    '${sections[i].rows.first.summary.exerciseId}',
                  ),
                ),
        ),
      (
        'Fuel',
        headerOf('Fuel'),
        find
            .descendant(
              of: find.byKey(const Key('fuel_section')),
              matching: find.byType(OmniSurface),
            )
            .first,
      ),
      (
        'Weight',
        headerOf('Weight'),
        find
            .descendant(
              of: find.byKey(const Key('weight_trend')),
              matching: find.byType(OmniSurface),
            )
            .first,
      ),
    ];

    /// Every block F-B builds.
    List<(String, Finder, Finder)> fbBlocks() => [
      ('Mix', headerOf('TRAINING MIX'), mixContent()),
      (
        'Signals locked',
        headerOf('SIGNALS'),
        find.byKey(const Key('signals_locked_line')),
      ),
    ];

    // ─── S-18701 ────────────────────────────────────────────────────────────

    group('S-18701 no Stats heading sits inside a card', () {
      setUp(seedEveryBlock);

      testWidgets(
        'F-A: every OmniCardHeader is on the background, above its block\'s '
        'first content',
        (tester) async {
          await pumpStats(tester, signals: const [_PositiveStub()]);

          final blocks = faBlocks();
          expect(
            tester.widgetList(find.byType(OmniCardHeader)).length,
            blocks.length,
            reason: 'the block map must cover every OmniCardHeader on screen',
          );
          for (final (name, header, content) in blocks) {
            expect(
              find.ancestor(of: header, matching: find.byType(OmniSurface)),
              findsNothing,
              reason: '$name: the heading never sits inside a card',
            );
            expect(
              tester.getBottomLeft(header).dy,
              lessThanOrEqualTo(tester.getTopLeft(content).dy),
              reason: '$name: the heading sits above its first content',
            );
          }
        },
      );
    });

    // ─── S-18702 ────────────────────────────────────────────────────────────

    group('S-18702 the empty-window branch keeps the heading above its card', () {
      setUp(() => _seedBreak(repo));

      testWidgets(
        'F-B: TRAINING MIX and SIGNALS on the background, the empty line '
        'inside the Mix card',
        (tester) async {
          await pumpStats(tester);

          expect(headerTitles(tester), ['TRAINING MIX', 'SIGNALS']);
          expect(
            find.ancestor(
              of: headerOf('TRAINING MIX'),
              matching: find.byType(OmniSurface),
            ),
            findsNothing,
            reason: 'the TRAINING MIX heading never sits inside a card',
          );
          expect(
            find.descendant(
              of: find.byKey(const Key('mix_layer_card')),
              matching: find.byKey(const Key('mix_window_empty')),
            ),
            findsOneWidget,
            reason: 'mix_window_empty is a descendant of mix_layer_card',
          );
          expect(
            find.ancestor(
              of: headerOf('SIGNALS'),
              matching: find.byType(OmniSurface),
            ),
            findsNothing,
            reason: 'the locked SIGNALS heading never sits inside a card',
          );
        },
      );
    });

    // ─── S-18703 ────────────────────────────────────────────────────────────

    group('S-18703 every Stats heading is uppercase', () {
      setUp(seedEveryBlock);

      testWidgets(
        'F-A: the titles in document order, in the service\'s kind order, '
        'each equal to its own toUpperCase()',
        (tester) async {
          await pumpStats(tester, signals: const [_PositiveStub()]);

          final titles = headerTitles(tester);
          final expected = [
            'TRAINING MIX',
            'SIGNALS',
            for (final section in sections) section.section.label.toUpperCase(),
            'FUEL',
            'WEIGHT',
          ];
          expect(titles, expected, reason: 'document order');
          for (final title in titles) {
            expect(title, title.toUpperCase(), reason: '"$title" is title case');
          }
        },
      );
    });

    // ─── S-18704 ────────────────────────────────────────────────────────────

    group('S-18704 the legacy headings are gone, the kind headings unique', () {
      setUp(seedEveryBlock);

      testWidgets(
        'F-A: STRENGTH, NUTRITION and stats_legacy_sections find nothing; '
        'CARDIO, ISOMETRIC, SPORTS each find one OmniCardHeader title inside '
        'instrument_list',
        (tester) async {
          await pumpStats(tester, signals: const [_PositiveStub()]);

          expect(find.text('STRENGTH'), findsNothing);
          expect(find.text('NUTRITION'), findsNothing);
          expect(find.byKey(const Key('stats_legacy_sections')), findsNothing);

          for (final label in const ['CARDIO', 'ISOMETRIC', 'SPORTS']) {
            final heading = find.text(label);
            expect(heading, findsOneWidget, reason: label);
            expect(
              find.ancestor(
                of: heading,
                matching: find.byKey(const Key('instrument_list')),
              ),
              findsOneWidget,
              reason: '$label descends from instrument_list',
            );
            expect(
              find.ancestor(of: heading, matching: find.byType(OmniCardHeader)),
              findsOneWidget,
              reason: '$label is an OmniCardHeader title',
            );
          }
        },
      );
    });

    // ─── S-18705 ────────────────────────────────────────────────────────────

    group('S-18705 every heading-to-content gap is the same', () {
      group('F-A', () {
        setUp(seedEveryBlock);

        testWidgets('each header\'s bottom meets its block\'s first content', (
          tester,
        ) async {
          await pumpStats(tester, signals: const [_PositiveStub()]);

          for (final (name, header, content) in faBlocks()) {
            expect(
              tester.getBottomLeft(header).dy,
              closeTo(tester.getTopLeft(content).dy, 0.5),
              reason: '$name: the header\'s own bottom padding is the only gap',
            );
          }
        });
      });

      group('F-B', () {
        setUp(() => _seedBreak(repo));

        testWidgets('each header\'s bottom meets its block\'s first content', (
          tester,
        ) async {
          await pumpStats(tester);

          for (final (name, header, content) in fbBlocks()) {
            expect(
              tester.getBottomLeft(header).dy,
              closeTo(tester.getTopLeft(content).dy, 0.5),
              reason: '$name: the header\'s own bottom padding is the only gap',
            );
          }
        });
      });
    });

    // ─── S-18706 ────────────────────────────────────────────────────────────

    group('S-18706 headings keep one line at the narrow viewport', () {
      setUp(seedEveryBlock);

      testWidgets(
        'F-A at 360x2400, text scale 2.0 and again 1.0: no exception, no '
        'ellipsized heading, the long row name on one line',
        (tester) async {
          for (final textScale in const [2.0, 1.0]) {
            await pumpStats(
              tester,
              size: _kNarrowViewport,
              textScale: textScale,
              signals: const [_PositiveStub()],
            );

            expect(tester.takeException(), isNull, reason: 'text scale $textScale');
            for (final element
                in find.byKey(const Key('omniCardHeader_title')).evaluate()) {
              final text = element.widget as Text;
              expect(
                text.maxLines,
                1,
                reason: 'text scale $textScale: "${text.data}" maxLines',
              );
              expect(
                text.overflow,
                TextOverflow.ellipsis,
                reason: 'text scale $textScale: "${text.data}" overflow',
              );
              final paragraph = element.renderObject! as RenderParagraph;
              expect(
                paragraph.didExceedMaxLines,
                isFalse,
                reason:
                    'text scale $textScale: "${text.data}" does not fit one '
                    'line',
              );
            }
            final name = tester.widget<Text>(find.text(_kExLongName));
            expect(name.maxLines, 1, reason: 'text scale $textScale');
            expect(name.overflow, TextOverflow.ellipsis);
            final nameParagraph = tester.renderObject<RenderParagraph>(
              find.text(_kExLongName),
            );
            expect(
              nameParagraph.didExceedMaxLines,
              isTrue,
              reason:
                  'text scale $textScale: the long name is truncated to one '
                  'line, not overflowed',
            );
          }
        },
      );
    });

    // ─── S-18707 ────────────────────────────────────────────────────────────

    group('S-18707 every header title uses the theme\'s textMuted', () {
      setUp(seedEveryBlock);

      testWidgets(
        'F-A, once per AppTheme: the title colour, the S-18701 placement, '
        'no exception',
        (tester) async {
          for (final theme in AppTheme.values) {
            OmniTheme.activeTheme = theme;
            await settingsState.setAppTheme(theme);
            await pumpStats(
              tester,
              signals: const [_PositiveStub()],
              freshTreeKey: theme,
            );

            expect(tester.takeException(), isNull, reason: theme.name);
            final muted = OmniTheme.colorsForTheme(theme).textMuted;
            for (final element
                in find.byKey(const Key('omniCardHeader_title')).evaluate()) {
              final text = element.widget as Text;
              expect(
                text.style?.color,
                muted,
                reason: '${theme.name}: "${text.data}"',
              );
            }
            for (final (name, header, content) in faBlocks()) {
              expect(
                tester.getBottomLeft(header).dy,
                lessThanOrEqualTo(tester.getTopLeft(content).dy),
                reason: '${theme.name}: $name header above its content',
              );
            }
          }
        },
      );
    });

    // ─── S-18710 ────────────────────────────────────────────────────────────

    group('S-18710 the empty state shows no heading', () {
      setUp(() => _seedFoodOnly(repo));

      testWidgets('F-C: zero sessions, one food, no OmniCardHeader', (
        tester,
      ) async {
        await pumpStats(tester);

        expect(find.byType(OmniCardHeader), findsNothing);
      });
    });

    // ─── Records & Trends (S-18712…S-18716, added by P1d) ───────────────────

    /// Pumps [RecordsAndTrendsScreen] directly, the way
    /// `records_and_trends_screen_test.dart` opens it (D-18709: Mock harness
    /// only, plain `testWidgets`).
    Future<void> pumpRecords(
      WidgetTester tester, {
      Size size = _kTallViewport,
      double textScale = 1.0,
      Object? freshTreeKey,
    }) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: MaterialApp(
            key: freshTreeKey == null ? null : ValueKey<Object>(freshTreeKey),
            home: RecordsAndTrendsScreen(
              workoutState: workoutState,
              settingsState: settingsState,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    // ─── S-18712 ────────────────────────────────────────────────────────────

    group('S-18712 non-heading text keeps its case', () {
      setUp(seedEveryBlock);

      testWidgets(
        'F-A: the Mix legend, bar semantics and row name stay title case on '
        'Stats; the R&T entry carries the same exact name; no bare uppercase '
        'kind text on either screen',
        (tester) async {
          await pumpStats(tester, signals: const [_PositiveStub()]);

          final legendTexts = tester
              .widgetList<Text>(
                find.descendant(
                  of: find.byKey(const Key('mix_legend')),
                  matching: find.byType(Text),
                ),
              )
              .map((text) => text.data!)
              .toList();
          expect(legendTexts, isNotEmpty, reason: 'F-A has work in every kind');
          for (final text in legendTexts) {
            expect(
              _kTitleCaseKinds.any((kind) => text.startsWith(kind)),
              isTrue,
              reason: '"$text" starts with a title-case kind',
            );
          }
          expect(
            tester
                .widget<Semantics>(find.byKey(const Key('mix_bar')))
                .properties
                .label,
            contains('Resistance'),
          );
          expect(
            find.descendant(
              of: find.byKey(const Key('instrument_row_ex-long')),
              matching: find.text(_kExLongName),
            ),
            findsOneWidget,
          );
          _expectNoBareUppercaseKind(tester, 'Stats');

          await tester.tap(find.byTooltip('Records & Trends'));
          await tester.pumpAndSettle();

          expect(
            find.descendant(
              of: find.byKey(const Key('records_entry_ex-long')),
              matching: find.text(_kExLongName),
            ),
            findsOneWidget,
          );
          _expectNoBareUppercaseKind(tester, 'Records & Trends');
        },
      );
    });

    // ─── S-18713 ────────────────────────────────────────────────────────────

    group('S-18713 R&T headings are uppercase in the enum order', () {
      setUp(seedEveryBlock);

      testWidgets(
        'F-A: ALL TIME, NUTRITION, RECENT PRS only when the list renders, '
        'then the kinds uppercased; no title-case kind text',
        (tester) async {
          await pumpRecords(tester);

          final expected = <String>['ALL TIME', 'NUTRITION'];
          if (tester.widgetList(find.byType(RecentPRList)).isNotEmpty) {
            expected.add('RECENT PRS');
          }
          for (final section in ExerciseSection.values) {
            expected.add(section.label.toUpperCase());
          }
          final titles = headerTitles(tester);
          expect(titles, expected, reason: 'document order');
          for (final title in titles) {
            expect(
              title,
              title.toUpperCase(),
              reason: '"$title" is title case',
            );
          }
          expect(find.text('Resistance'), findsNothing);
        },
      );
    });

    // ─── S-18714 ────────────────────────────────────────────────────────────

    group('S-18714 the search filter keeps the kind headings uppercase', () {
      setUp(seedEveryBlock);

      testWidgets(
        'F-A: romanian leaves RESISTANCE and the ex-long entry only; zzzz '
        'leaves no kind heading; clearing restores all four',
        (tester) async {
          await pumpRecords(tester);

          final field = find.byKey(
            const Key('records_and_trends_search_field'),
          );
          expect(field, findsOneWidget);
          List<String> kindHeadings() => headerTitles(tester)
              .where((title) => _kUppercaseKinds.contains(title))
              .toList();

          await tester.enterText(field, 'romanian');
          await tester.pumpAndSettle();
          expect(kindHeadings(), ['RESISTANCE']);
          expect(
            find.byKey(const Key('records_entry_ex-long')),
            findsOneWidget,
          );
          expect(
            find.byKey(const Key('records_entry_ex-squat')),
            findsNothing,
          );

          await tester.enterText(field, 'zzzz');
          await tester.pumpAndSettle();
          expect(kindHeadings(), isEmpty);
          expect(find.byKey(const Key('records_entry_ex-long')), findsNothing);

          await tester.enterText(field, '');
          await tester.pumpAndSettle();
          expect(
            kindHeadings(),
            [
              for (final section in ExerciseSection.values)
                section.label.toUpperCase(),
            ],
          );
        },
      );
    });

    // ─── S-18715 ────────────────────────────────────────────────────────────

    group('S-18715 R&T headings survive text scale and themes', () {
      setUp(seedEveryBlock);

      testWidgets(
        'F-A at 360x2400, text scale 2.0 then 1.0: no unexpected exception, '
        'every header on one line, the long entry within the width',
        (tester) async {
          for (final textScale in const [2.0, 1.0]) {
            // The Recent PRs card's Row overflows at this viewport and scale
            // — a pre-existing `RecentPRList` layout bug outside this
            // headings-only change's scope (reported to the governor). Every
            // other exception fails the test. Each detail is stringified as
            // it is caught: the rendered text names the error-causing widget
            // only while the tree that threw is still alive.
            final errors = <String>[];
            final previousHandler = FlutterError.onError;
            FlutterError.onError = (details) {
              try {
                errors.add(details.toString());
              } catch (_) {
                errors.add('${details.exception}');
              }
            };
            try {
              await pumpRecords(
                tester,
                size: _kNarrowViewport,
                textScale: textScale,
              );

              // The ListView mounts its children lazily, so the walk records
              // every header title and the long entry as they pass through
              // the viewport.
              final observed = <String, Text>{};
              final exceeded = <String, bool>{};
              double? entryRight;
              void record() {
                for (final element
                    in find
                        .byKey(const Key('omniCardHeader_title'))
                        .evaluate()) {
                  final text = element.widget as Text;
                  observed[text.data!] = text;
                  exceeded[text.data!] =
                      (element.renderObject! as RenderParagraph)
                          .didExceedMaxLines;
                }
                final entry = find.byKey(const Key('records_entry_ex-long'));
                if (tester.any(entry)) {
                  entryRight = tester.getTopRight(entry).dx;
                }
              }

              record();
              final scrollable = find.byType(Scrollable).first;
              var guard = 0;
              while (guard++ < 60) {
                final position =
                    tester.state<ScrollableState>(scrollable).position;
                if (position.pixels >= position.maxScrollExtent) break;
                await tester.drag(scrollable, const Offset(0, -400));
                await tester.pumpAndSettle();
                record();
              }

              final expectedHeaders = <String>['ALL TIME', 'NUTRITION'];
              if (observed.containsKey('RECENT PRS')) {
                expectedHeaders.add('RECENT PRS');
              }
              for (final section in ExerciseSection.values) {
                expectedHeaders.add(section.label.toUpperCase());
              }
              expect(
                observed.keys.toSet(),
                expectedHeaders.toSet(),
                reason:
                    'text scale $textScale: every header passed the viewport',
              );
              for (final title in observed.keys) {
                final text = observed[title]!;
                expect(
                  text.maxLines,
                  1,
                  reason: 'text scale $textScale: "$title" maxLines',
                );
                expect(
                  text.overflow,
                  TextOverflow.ellipsis,
                  reason: 'text scale $textScale: "$title" overflow',
                );
                expect(
                  exceeded[title],
                  isFalse,
                  reason: 'text scale $textScale: "$title" fits one line',
                );
              }
              expect(
                entryRight,
                isNotNull,
                reason: 'text scale $textScale: the long entry was mounted',
              );
              expect(
                entryRight!,
                lessThanOrEqualTo(_kNarrowViewport.width),
                reason:
                    'text scale $textScale: the long entry stays within the '
                    'width',
              );
            } finally {
              FlutterError.onError = previousHandler;
            }
            final unexpected = [
              for (final error in errors)
                if (!_isKnownPrListOverflow(error)) error,
            ];            expect(
              unexpected,
              isEmpty,
              reason:
                  'text scale $textScale: the only tolerated exception is the '
                  'pre-existing RecentPRList overflow',
            );
          }
        },
      );

      testWidgets(
        'F-A at 400x2400, once per AppTheme: every header title uses the '
        'theme\'s textMuted',
        (tester) async {
          for (final theme in AppTheme.values) {
            OmniTheme.activeTheme = theme;
            await settingsState.setAppTheme(theme);
            await pumpRecords(tester, freshTreeKey: theme);

            expect(tester.takeException(), isNull, reason: theme.name);
            final muted = OmniTheme.colorsForTheme(theme).textMuted;
            for (final element
                in find.byKey(const Key('omniCardHeader_title')).evaluate()) {
              final text = element.widget as Text;
              expect(
                text.style?.color,
                muted,
                reason: '${theme.name}: "${text.data}"',
              );
            }
          }
        },
      );
    });

    // ─── S-18716 ────────────────────────────────────────────────────────────

    group('S-18716 Exercise Progress keeps its uppercase headings', () {
      setUp(seedEveryBlock);

      testWidgets(
        'F-A: tapping the squat entry opens Exercise Progress with ALL TIME, '
        'TREND, RECENT SESSIONS, each uppercase',
        (tester) async {
          await pumpRecords(tester);

          await tester.tap(find.byKey(const Key('records_entry_ex-squat')));
          await tester.pumpAndSettle();

          expect(find.byType(ExerciseProgressScreen), findsOneWidget);
          final titles = headerTitles(tester);
          expect(
            titles,
            ['ALL TIME', 'TREND', 'RECENT SESSIONS'],
            reason: 'document order',
          );
          for (final title in titles) {
            expect(
              title,
              title.toUpperCase(),
              reason: '"$title" is title case',
            );
          }
        },
      );
    });
  });
}
