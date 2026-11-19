// Plan 219 — a visible way into Records & Trends at the end of the Stats list
// (`docs/plans/2026-11-16-219-stats-visible-records-link-plan/`).
//
// Scenarios S-21901..S-21906.
//
// Mock only: a widget test body runs under `FakeAsync`, where a Hive read
// never settles, so the store under test is the in-memory
// `MockWorkoutRepository`, seeded in `setUp`.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/metric_ids.dart';
import 'package:omnitrain/core/constants/omni_theme.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/features/stats/records_and_trends_screen.dart';
import 'package:omnitrain/features/stats/stats_screen.dart';
import 'package:omnitrain/features/stats/widgets/instrument_list.dart';
import 'package:omnitrain/features/stats/widgets/records_link_row.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:omnitrain/widgets/common/omni_empty_state.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/repository_harness.dart';

/// Tall enough that every section and the closing row are laid out, so a
/// position assertion is never an off-screen miss.
const Size _kViewport = Size(400, 1600);

/// A repository whose history read throws while [failing] is on — the fixture
/// of `test/stats_load_failure_test.dart` (S-2704).
class _FlakyRepository extends MockWorkoutRepository {
  bool failing = false;

  @override
  Future<List<TrainingSession>> getAllSessions() async {
    if (failing) throw StateError('the store cannot be read');
    return super.getAllSessions();
  }
}

final Key _linkKey = const Key('stats_records_link');

/// Weigh-ins, cleared: the Mock harness may open with samples.
Future<void> _clearWeights(WorkoutRepository repo) async {
  for (final entry in await repo.getMeasurementHistory('bodyweight')) {
    await repo.deleteMeasurementEntry(entry.id);
  }
}

/// The food log, cleared (the Mock harness opens with samples).
Future<void> _clearConsumedFoods(WorkoutRepository repo) async {
  const farFutureMs = 4102444800000; // 2100-01-01
  for (final row in await repo.getConsumedFoodsInRange(0, farFutureMs)) {
    await repo.deleteConsumedFood(row.id);
  }
}

/// One weigh-in [daysAgo] days back (as `test/weight_trend_screen_test.dart`).
Future<void> _seedWeight(
  WorkoutRepository repo,
  String id,
  double kg,
  int daysAgo,
) {
  final now = DateTime.now();
  final at = DateTime(now.year, now.month, now.day - daysAgo, 12);
  return repo.saveMeasurementEntry(
    BodyMeasurementEntry(
      id: id,
      measurementType: 'bodyweight',
      value: kg,
      unitId: MetricIds.unitKg,
      recordedAtMs: at.millisecondsSinceEpoch,
    ),
  );
}

/// One logged food [daysAgo] days back (as `test/fuel_row_screen_test.dart`).
Future<void> _seedFood(WorkoutRepository repo, int daysAgo) async {
  final now = DateTime.now();
  final day = DateTime(now.year, now.month, now.day - daysAgo);
  final dateMs = day.millisecondsSinceEpoch;
  await repo.createConsumedFood(
    ConsumedFood(
      id: 'food-$daysAgo',
      loggedAtMs: dateMs + (12 * 60 * 60 * 1000),
      dateMs: dateMs,
      sourceFoodId: 'food-$daysAgo',
      name: 'food-$daysAgo',
      unitType: FoodUnitType.grams,
      referenceAmount: 100,
      referenceLabel: '100 g',
      protein: 100,
      carbs: 400,
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

void main() {
  group('S-21901 the row itself', () {
    testWidgets('title, hint, chevron, and a tap calls onTap once', (
      tester,
    ) async {
      var taps = 0;
      final settings = SettingsState(
        MockWorkoutRepository(),
        fakePreferencesService(),
      );
      await settings.initialize();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: RecordsLinkRow(
                themeColors: OmniTheme.colorsForTheme(settings.appTheme),
                onTap: () => taps++,
              ),
            ),
          ),
        ),
      );

      expect(
        tester
            .widget<Text>(find.byKey(const Key('stats_records_link_title')))
            .data,
        'Records & Trends',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('stats_records_link_hint')))
            .data,
        'Your personal records and the full history of each exercise.',
      );
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);

      await tester.tap(find.byKey(_linkKey));
      expect(taps, 1);
      expect(tester.takeException(), isNull);
    });
  });

  group('S-21902 the row closes a populated list', () {
    late MockWorkoutRepository repo;
    late WorkoutState workoutState;
    late SettingsState settingsState;

    setUp(() async {
      repo = MockWorkoutRepository();
      await repo.initialize();
      workoutState = WorkoutState(repo);
      settingsState = SettingsState(repo, fakePreferencesService());
      await settingsState.initialize();
      await seedSession(repo, sessionId: 'sess-1', daysAgo: 1);
      await seedExercise(
        repo,
        id: 'ex-row',
        name: 'Row',
        capabilities: ['load'],
      );
      await seedSetEffort(
        repo,
        segmentId: 'seg-sess-1',
        effortId: 'eff-1',
        exerciseId: 'ex-row',
        entryCount: 2,
        hasExtraWeight: false,
      );
    });

    Future<void> pump(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(_kViewport);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: StatsScreen(
            workoutState: workoutState,
            settingsState: settingsState,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('the row sits below the Instruments list and opens Records', (
      tester,
    ) async {
      await pump(tester);

      final link = find.byKey(_linkKey);
      expect(link, findsOneWidget);
      expect(
        tester.getTopLeft(link).dy,
        greaterThan(tester.getBottomLeft(find.byType(InstrumentList)).dy),
      );

      await tester.ensureVisible(link);
      await tester.pumpAndSettle();
      await tester.tap(link);
      await tester.pumpAndSettle();

      expect(find.byType(RecordsAndTrendsScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('S-21903 the row is the last section, below Weight and Fuel', () {
    late MockWorkoutRepository repo;
    late WorkoutState workoutState;
    late SettingsState settingsState;

    setUp(() async {
      repo = MockWorkoutRepository();
      await repo.initialize();
      workoutState = WorkoutState(repo);
      settingsState = SettingsState(repo, fakePreferencesService());
      await settingsState.initialize();
      await _clearWeights(repo);
      await _clearConsumedFoods(repo);
      await seedSession(repo, sessionId: 'sess-1', daysAgo: 1);
      await seedExercise(
        repo,
        id: 'ex-row',
        name: 'Row',
        capabilities: ['load'],
      );
      await seedSetEffort(
        repo,
        segmentId: 'seg-sess-1',
        effortId: 'eff-1',
        exerciseId: 'ex-row',
        entryCount: 2,
        hasExtraWeight: false,
      );
      await _seedWeight(repo, 'w1', 80.8, 27);
      await _seedWeight(repo, 'w2', 80.2, 0);
      await _seedFood(repo, 1);
    });

    testWidgets('the row is below the Weight trend and still exactly one', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(_kViewport);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: StatsScreen(
            workoutState: workoutState,
            settingsState: settingsState,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final link = find.byKey(_linkKey);
      expect(link, findsOneWidget);
      expect(
        tester.getTopLeft(link).dy,
        greaterThan(tester.getBottomLeft(find.byKey(const Key('weight_trend'))).dy),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('S-21904 the row closes every branch', () {
    testWidgets('no sessions: the row follows the empty card', (tester) async {
      final repo = MockWorkoutRepository();
      await repo.initialize();
      final settingsState = SettingsState(repo, fakePreferencesService());
      await settingsState.initialize();

      await tester.binding.setSurfaceSize(_kViewport);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: StatsScreen(
            workoutState: WorkoutState(repo),
            settingsState: settingsState,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No sessions yet'), findsOneWidget);
      final link = find.byKey(_linkKey);
      expect(link, findsOneWidget);
      // The row sits below the empty card: its top is under the card's
      // bottom (the card is the OmniEmptyState the surface wraps).
      expect(
        tester.getTopLeft(link).dy,
        greaterThan(tester.getBottomLeft(find.byType(OmniEmptyState)).dy),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a failed load shows no row', (tester) async {
      final repo = _FlakyRepository();
      await repo.initialize();
      final settingsState = SettingsState(repo, fakePreferencesService());
      await settingsState.initialize();
      repo.failing = true;

      await tester.binding.setSurfaceSize(_kViewport);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: StatsScreen(
            workoutState: WorkoutState(repo),
            settingsState: settingsState,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Could not load your stats.'), findsOneWidget);
      expect(find.byKey(_linkKey), findsNothing);
    });
  });

  group('S-21905 the header has no chart icon', () {
    late MockWorkoutRepository repo;
    late WorkoutState workoutState;
    late SettingsState settingsState;

    setUp(() async {
      repo = MockWorkoutRepository();
      await repo.initialize();
      workoutState = WorkoutState(repo);
      settingsState = SettingsState(repo, fakePreferencesService());
      await settingsState.initialize();
      await seedSession(repo, sessionId: 'sess-1', daysAgo: 1);
      await seedExercise(
        repo,
        id: 'ex-row',
        name: 'Row',
        capabilities: ['load'],
      );
      await seedSetEffort(
        repo,
        segmentId: 'seg-sess-1',
        effortId: 'eff-1',
        exerciseId: 'ex-row',
        entryCount: 2,
        hasExtraWeight: false,
      );
    });

    testWidgets('the "?" stays and the chart icon is gone', (tester) async {
      await tester.binding.setSurfaceSize(_kViewport);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: StatsScreen(
            workoutState: workoutState,
            settingsState: settingsState,
            showPrimerHelp: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.show_chart), findsNothing);
      expect(find.byTooltip('Records & Trends'), findsNothing);
      expect(find.byKey(const Key('stats_primer_help')), findsOneWidget);
      expect(find.byTooltip('About Stats'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('S-21906 the primer names the row, not an icon', () {
    testWidgets(
      'the third block reads RECORDS & TRENDS with the new body, reached '
      'through the "?"',
      (tester) async {
        final repo = MockWorkoutRepository();
        await repo.initialize();
        final settingsState = SettingsState(repo, fakePreferencesService());
        await settingsState.initialize();

        await tester.binding.setSurfaceSize(_kViewport);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            home: StatsScreen(
              workoutState: WorkoutState(repo),
              settingsState: settingsState,
              showPrimerHelp: true,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('stats_primer_help')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('stats_primer_block_records')),
            findsOneWidget);
        expect(find.text('RECORDS & TRENDS'), findsOneWidget);
        expect(
          find.text(
            'Opens from the row at the end of this page: your personal '
            'records and the full history of each exercise. Tap an exercise '
            'there to see its progress.',
          ),
          findsOneWidget,
        );
        expect(find.text('THE CHART ICON'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
