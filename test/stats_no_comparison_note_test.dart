// Plan 216 — the first month says there is nothing to compare yet
// (`docs/plans/2026-11-16-216-stats-first-month-says-nothing-to-compare-plan/`).
//
// Scenarios S-21604 and S-21605 were added by the lead after the mutation pass
// (one note across sections; the note's span follows the window).
//
// Scenarios S-21601, S-21602 (pump `InstrumentList` directly with a hand-built
// section) and S-21603 (through `StatsScreen` and the real service).
//
// Mock-only: a widget test body runs under `FakeAsync`, where a Hive read
// never settles, so the store under test is the in-memory
// `MockWorkoutRepository`, seeded in `setUp`.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/omni_theme.dart';
import 'package:omnitrain/core/models/exercise_metric.dart';
import 'package:omnitrain/core/models/instrument_list.dart';
import 'package:omnitrain/core/models/stats_progress.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/stats/stats_screen.dart';
import 'package:omnitrain/features/stats/widgets/instrument_list.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/repository_harness.dart';

/// Tall enough that the caption, the note and the rows are all laid out, so a
/// position assertion is never an off-screen miss.
const Size _kViewport = Size(400, 1600);

/// The caption's own text.
String _caption(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('instrument_caption'))).data!;

/// The note's own text.
String _note(WidgetTester tester) => tester
    .widget<Text>(find.byKey(const Key('instrument_no_comparison_note')))
    .data!;

/// A hand-built one-section list, the fixture of
/// `test/instrument_list_screen_test.dart` S-4010's one-day pump, with the
/// 28-day `Last 4 weeks` window.
Widget _instrumentList(List<InstrumentRow> rows, SettingsState settings) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: InstrumentList(
          sections: [
            InstrumentSectionData(
              section: ExerciseSection.resistance,
              trainingDayCount: 1,
              rows: rows,
            ),
          ],
          window: StatsWindow(
            fromMs: DateTime(2026, 4, 1),
            toMs: DateTime(2026, 4, 28),
            label: 'Last 4 weeks',
            isPeriodScoped: false,
          ),
          themeColors: OmniTheme.colorsForTheme(settings.appTheme),
          workoutState: WorkoutState(MockWorkoutRepository()),
          settingsState: settings,
        ),
      ),
    ),
  );
}

void main() {
  group('S-21601 the first month says there is nothing to compare', () {
    testWidgets('a row with nothing earlier sits under the caption with the '
        'note', (tester) async {
      final window = StatsWindow(
        fromMs: DateTime(2026, 4, 1),
        toMs: DateTime(2026, 4, 28),
        label: 'Last 4 weeks',
        isPeriodScoped: false,
      );
      expect(window.dayCount, 28);

      await tester.binding.setSurfaceSize(_kViewport);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final day = DateTime(2026, 4, 20);
      final settings = SettingsState(
        MockWorkoutRepository(),
        fakePreferencesService(),
      );
      await tester.pumpWidget(
        _instrumentList([
          InstrumentRow(
            summary: ExerciseMetricSummary(
              exerciseId: 'ex-one',
              name: 'Back Squat',
              section: ExerciseSection.resistance,
              best: const NativeValue(
                metric: NativeMetric.estimatedOneRepMax,
                value: 140,
              ),
              points: const [],
              lastTrainedMs: day.millisecondsSinceEpoch,
              sessionCount: 1,
            ),
          ),
        ], settings),
      );
      await tester.pumpAndSettle();

      final note = find.byKey(const Key('instrument_no_comparison_note'));
      expect(note, findsOneWidget);
      expect(
        _note(tester),
        'Nothing to compare yet. Change shows once an exercise was also '
        'trained in the 4 weeks before.',
      );
      expect(
        _caption(tester),
        'Last 4 weeks. Change is against the 4 weeks before.',
      );

      final noteTop = tester.getTopLeft(note).dy;
      final captionBottom = tester
          .getBottomLeft(find.byKey(const Key('instrument_caption')))
          .dy;
      final firstRowTop = tester
          .getTopLeft(find.byKey(const Key('instrument_row_ex-one')))
          .dy;
      expect(noteTop, greaterThanOrEqualTo(captionBottom));
      expect(noteTop, lessThanOrEqualTo(firstRowTop));
      expect(tester.takeException(), isNull);
    });
  });

  group('S-21602 the note hides as soon as one row is comparable', () {
    testWidgets('one row with a previous value means no note', (tester) async {
      final window = StatsWindow(
        fromMs: DateTime(2026, 4, 1),
        toMs: DateTime(2026, 4, 28),
        label: 'Last 4 weeks',
        isPeriodScoped: false,
      );
      expect(window.dayCount, 28);

      await tester.binding.setSurfaceSize(_kViewport);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final day = DateTime(2026, 4, 20);
      final settings = SettingsState(
        MockWorkoutRepository(),
        fakePreferencesService(),
      );
      await tester.pumpWidget(
        _instrumentList([
          InstrumentRow(
            summary: ExerciseMetricSummary(
              exerciseId: 'ex-one',
              name: 'Back Squat',
              section: ExerciseSection.resistance,
              best: const NativeValue(
                metric: NativeMetric.estimatedOneRepMax,
                value: 140,
              ),
              points: const [],
              lastTrainedMs: day.millisecondsSinceEpoch,
              sessionCount: 1,
            ),
            previousValue: const NativeValue(
              metric: NativeMetric.estimatedOneRepMax,
              value: 120,
            ),
          ),
          InstrumentRow(
            summary: ExerciseMetricSummary(
              exerciseId: 'ex-two',
              name: 'Bench Press',
              section: ExerciseSection.resistance,
              best: const NativeValue(
                metric: NativeMetric.estimatedOneRepMax,
                value: 100,
              ),
              points: const [],
              lastTrainedMs: day.millisecondsSinceEpoch,
              sessionCount: 1,
            ),
          ),
        ], settings),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('instrument_no_comparison_note')),
        findsNothing,
      );
      expect(
        _caption(tester),
        'Last 4 weeks. Change is against the 4 weeks before.',
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('S-21603 through StatsScreen, real service', () {
    late MockWorkoutRepository repo;
    late WorkoutState workoutState;
    late SettingsState settingsState;

    setUp(() async {
      repo = MockWorkoutRepository();
      await repo.initialize();
      workoutState = WorkoutState(repo);
      settingsState = SettingsState(repo, fakePreferencesService());
      await settingsState.initialize();
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

    testWidgets('one session in the window and none before shows the note', (
      tester,
    ) async {
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

      await pump(tester);

      expect(
        find.byKey(const Key('instrument_no_comparison_note')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the same exercise trained 35 days ago hides the note', (
      tester,
    ) async {
      await seedSession(repo, sessionId: 'sess-1', daysAgo: 1);
      await seedSession(repo, sessionId: 'sess-2', daysAgo: 35);
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
      await seedSetEffort(
        repo,
        segmentId: 'seg-sess-2',
        effortId: 'eff-2',
        exerciseId: 'ex-row',
        entryCount: 2,
        hasExtraWeight: false,
      );

      await pump(tester);

      expect(
        find.byKey(const Key('instrument_no_comparison_note')),
        findsNothing,
      );
      expect(find.byKey(const Key('instrument_caption')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group(
    'S-21604 one note across sections, S-21605 its span follows the window',
    () {
      ExerciseMetricSummary summaryOf(String id, ExerciseSection section) =>
          ExerciseMetricSummary(
            exerciseId: id,
            name: id,
            section: section,
            best: const NativeValue(metric: NativeMetric.duration, value: 600),
            points: const [],
            lastTrainedMs: DateTime(2026, 4, 20).millisecondsSinceEpoch,
            sessionCount: 1,
          );

      Future<void> pumpList(
        WidgetTester tester, {
        required StatsWindow window,
      }) async {
        await tester.binding.setSurfaceSize(const Size(400, 2000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final settings = SettingsState(
          MockWorkoutRepository(),
          fakePreferencesService(),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: InstrumentList(
                  sections: [
                    InstrumentSectionData(
                      section: ExerciseSection.resistance,
                      trainingDayCount: 1,
                      rows: [
                        InstrumentRow(
                          summary: summaryOf(
                            'ex-a',
                            ExerciseSection.resistance,
                          ),
                        ),
                      ],
                    ),
                    InstrumentSectionData(
                      section: ExerciseSection.cardio,
                      trainingDayCount: 1,
                      rows: [
                        InstrumentRow(
                          summary: summaryOf('ex-b', ExerciseSection.cardio),
                        ),
                      ],
                    ),
                  ],
                  window: window,
                  themeColors: OmniTheme.colorsForTheme(settings.appTheme),
                  workoutState: WorkoutState(MockWorkoutRepository()),
                  settingsState: settings,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      testWidgets('S-21604 two sections, all new: exactly one note', (
        tester,
      ) async {
        await pumpList(
          tester,
          window: StatsWindow(
            fromMs: DateTime(2026, 4, 1),
            toMs: DateTime(2026, 4, 28),
            label: 'Last 4 weeks',
            isPeriodScoped: false,
          ),
        );
        expect(
          find.byKey(const Key('instrument_no_comparison_note')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('instrument_caption')), findsOneWidget);
      });

      testWidgets('S-21605 a ten-day window names the ten days before it', (
        tester,
      ) async {
        final window = StatsWindow(
          fromMs: DateTime(2026, 4, 11),
          toMs: DateTime(2026, 4, 20),
          label: 'Custom',
          isPeriodScoped: false,
        );
        expect(window.dayCount, 10);
        await pumpList(tester, window: window);
        expect(
          _note(tester),
          'Nothing to compare yet. Change shows once an exercise was also '
          'trained in the 10 days before.',
        );
      });
    },
  );
}
