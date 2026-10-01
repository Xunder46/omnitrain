// The Instruments list on the main Stats screen — Stats PR 4b2.
//
// Scenarios S-1001, S-1011, S-1012, S-1014, S-1015 (the Instruments half),
// S-1016 and S-1017.
//
// Plan: `docs/plans/2026-10-01-04b2-stats-pr4b2-instruments-list-plan/`.
//
// Every scenario runs on both repository implementations. The harness is
// opened and seeded in `setUp` and never inside a `testWidgets` body: a widget
// test body runs under `FakeAsync`, where Hive's real file I/O never settles
// and the test hangs.
//
// The screen is driven through `StatsScreen` only. The model half of every
// expectation is read from the same service the screen calls, so no figure is
// hand-copied into the test.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/models/exercise_metric.dart';
import 'package:omnitrain/core/models/instrument_list.dart';
import 'package:omnitrain/core/models/stats_progress.dart';
import 'package:omnitrain/core/services/stats_progress_service.dart';
import 'package:omnitrain/core/utils/date_utils.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/features/stats/exercise_progress_screen.dart';
import 'package:omnitrain/features/stats/stats_screen.dart';
import 'package:omnitrain/features/stats/widgets/native_value_format.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:omnitrain/widgets/layout/omni_back_header.dart';
import 'package:omnitrain/widgets/layout/omni_card_header.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/repository_harness.dart';

/// The height every scenario pumps at: tall enough that every Instruments
/// section and every legacy section is laid out, so an assertion on a widget's
/// absence is never just an off-screen miss.
const Size _kTallViewport = Size(400, 2400);

/// The sparkline's drawn size when a row has a series to draw.
const Size _kSparklineSize = Size(56, 24);

/// What the change chip reads when there is nothing comparable to show.
const String _kNoChange = '—';

// ─── finders and readers ────────────────────────────────────────────────────

bool _isInstrumentRow(Widget widget) {
  final key = widget.key;
  return key is ValueKey<String> && key.value.startsWith('instrument_row_');
}

/// Every Instruments row key on screen, in document order.
List<String> _instrumentRowKeys() {
  final keys = <String>[];
  for (final element in find.byWidgetPredicate(_isInstrumentRow).evaluate()) {
    keys.add((element.widget.key! as ValueKey<String>).value);
  }
  return keys;
}

/// Every `Text` under [scope], in document order. A keyed `Text` counts as its
/// own match, so a finder on a chip reads that chip's label.
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

/// Every `Text` inside one Instruments row, in document order.
List<String> _rowTexts(String exerciseId) =>
    _textsUnder(find.byKey(Key('instrument_row_$exerciseId')));

/// The change chip's own label for [exerciseId].
String _changeLabel(String exerciseId) =>
    _textsUnder(find.byKey(Key('instrument_change_$exerciseId'))).single;

/// The row cap control's own label.
String _capControlLabel(String sectionName) =>
    _textsUnder(find.byKey(Key('instrument_show_all_$sectionName'))).single;

/// The one row for [exerciseId] across every section.
InstrumentRow _rowOf(List<InstrumentSectionData> sections, String exerciseId) =>
    sections
        .expand((section) => section.rows)
        .firstWhere((row) => row.summary.exerciseId == exerciseId);

/// The rows of [section], which the fixture guarantees exists.
List<InstrumentRow> _rowsOf(
  List<InstrumentSectionData> sections,
  ExerciseSection section,
) => sections.firstWhere((s) => s.section == section).rows;

/// The label a training day [daysAgo] days back reads as in a history list.
String _dayLabel(int daysAgo) =>
    OmniDateUtils.formatShort(DateTime.now().subtract(Duration(days: daysAgo)));

/// The secondary line a row shows for [value], as the row composes it.
String _secondaryLine(NativeValue value, SettingsState settings) =>
    '${nativeSecondaryLabel(value.secondaryMetric)} '
    '${formatNativeSecondary(value, settings)}';

// ─── fixtures ───────────────────────────────────────────────────────────────

/// One completed session holding one set effort of [reps] reps at [weightKg].
Future<void> _seedSetSession(
  WorkoutRepository repo, {
  required String sessionId,
  required int daysAgo,
  required String exerciseId,
  required double weightKg,
  required int reps,
}) async {
  await seedSession(repo, sessionId: sessionId, daysAgo: daysAgo);
  await seedSetEffort(
    repo,
    segmentId: 'seg-$sessionId',
    effortId: 'eff-$sessionId',
    exerciseId: exerciseId,
    entryCount: 1,
    hasExtraWeight: false,
    weightFactor: weightKg,
    repsBase: reps,
  );
}

/// A cardio session: one finished 600 s instance over an **estimated** 6 km.
Future<void> _seedEstimatedRun(WorkoutRepository repo) async {
  await seedSession(
    repo,
    sessionId: 's-card',
    daysAgo: 2,
    modality: 'cardio_endurance',
  );
  await repo.createEffort(
    SegmentEffort(
      id: 'eff-s-card',
      segmentId: 'seg-s-card',
      orderIndex: 0,
      effortKind: 'timed',
      exerciseId: 'ex-run',
      createdAtMs: fixtureStart,
      updatedAtMs: fixtureStart,
    ),
  );
  await repo.createTimedInstance(
    timedInstance('eff-s-card', 0, durationSecs: 600, entryIndex: 0),
  );
  await repo.createObservation(
    distanceRow(
      'eff-s-card',
      0,
      6000,
      atMs: fixtureRowAt(0),
      source: EffortObservation.sourceEstimated,
    ),
  );
}

/// The flagship population: four kinds of work inside the window, a duplicate
/// exercise name, and history outside it.
///
/// Days 1–14 are the window (14 distinct training days, days 5–14 are empty
/// filler sessions). `ex-squat` also has history 20 and 40 days back, so it has
/// a comparable previous range and a history older than the window.
Future<void> _seedFlagship(WorkoutRepository repo) async {
  await seedExercise(
    repo,
    id: 'ex-squat',
    name: 'Back Squat',
    capabilities: const ['load', 'reps'],
  );
  await seedExercise(
    repo,
    id: 'ex-row',
    name: 'Back Squat',
    capabilities: const ['load', 'reps'],
  );
  await seedExercise(
    repo,
    id: 'ex-old',
    name: 'Deadlift',
    capabilities: const ['load', 'reps'],
  );
  await seedExercise(
    repo,
    id: 'ex-run',
    name: 'Treadmill Run',
    capabilities: const ['time', 'distance'],
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

  // (a) Resistance: two exercises sharing a name, one training day each.
  await seedSession(repo, sessionId: 's-res', daysAgo: 1);
  await seedSetEffort(
    repo,
    segmentId: 'seg-s-res',
    effortId: 'eff-s-res-squat',
    exerciseId: 'ex-squat',
    entryCount: 1,
    hasExtraWeight: false,
    weightFactor: 100,
    repsBase: 5,
  );
  await seedSetEffort(
    repo,
    segmentId: 'seg-s-res',
    effortId: 'eff-s-res-row',
    exerciseId: 'ex-row',
    entryCount: 1,
    hasExtraWeight: false,
    weightFactor: 80,
    repsBase: 5,
  );

  // (b) Cardio.
  await _seedEstimatedRun(repo);

  // (c) Isometric.
  await seedSession(repo, sessionId: 's-iso', daysAgo: 3);
  await seedHoldEffort(
    repo,
    segmentId: 'seg-s-iso',
    effortId: 'eff-s-iso',
    exerciseId: 'ex-plank',
    entryCount: 1,
    secondsPerEntry: 90,
  );

  // (d) Sports.
  await seedSession(repo, sessionId: 's-sport', daysAgo: 4, modality: 'sports');
  await seedRoundEffort(
    repo,
    segmentId: 'seg-s-sport',
    effortId: 'eff-s-sport',
    exerciseId: 'ex-bjj',
    rounds: [
      roundInstance('eff-s-sport', 0),
      roundInstance('eff-s-sport', 1),
      roundInstance('eff-s-sport', 2),
    ],
  );

  // History outside the window: 20 days back (also the previous range, so the
  // change chip has something to compare against) and 40 days back.
  await _seedSetSession(
    repo,
    sessionId: 's-squat-20',
    daysAgo: 20,
    exerciseId: 'ex-squat',
    weightKg: 60,
    reps: 3,
  );
  await _seedSetSession(
    repo,
    sessionId: 's-squat-40',
    daysAgo: 40,
    exerciseId: 'ex-squat',
    weightKg: 50,
    reps: 3,
  );
  await _seedSetSession(
    repo,
    sessionId: 's-old',
    daysAgo: 20,
    exerciseId: 'ex-old',
    weightKg: 140,
    reps: 5,
  );

  // Days 5–14: empty completed sessions, so the window's 14 most recent
  // training days stop at day 14 and days 20 and 40 fall outside it.
  for (var daysAgo = 5; daysAgo <= 14; daysAgo++) {
    await seedSession(repo, sessionId: 's-f$daysAgo', daysAgo: daysAgo);
  }
}

void main() {
  for (final factory in harnessFactories) {
    final harness = factory();

    group('Instruments list — ${harness.name}', () {
      late WorkoutRepository repo;
      late WorkoutState workoutState;
      late SettingsState settingsState;
      late StatsWindow window;
      late List<InstrumentSectionData> sections;

      setUp(() async {
        repo = await harness.open();
        workoutState = WorkoutState(repo);
        settingsState = SettingsState(repo, fakePreferencesService());
        await settingsState.initialize();
      });

      tearDown(() async {
        await harness.close();
      });

      /// The window and the sections the screen is about to compute, read from
      /// the same service with the same arguments.
      Future<void> readModel() async {
        final service = StatsProgressService(repo);
        final data = await service.computeProgressData();
        window = data.window;
        sections = await service.computeInstrumentSections(window: window);
      }

      Future<void> pumpStats(WidgetTester tester) async {
        await tester.binding.setSurfaceSize(_kTallViewport);
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

      // ─── S-1001: four sections in one window ──────────────────────────────

      group('S-1001', () {
        setUp(() async {
          await _seedFlagship(repo);
          await readModel();
        });

        testWidgets('four sections render in the order Resistance, Cardio, '
            'Isometric, Sports', (tester) async {
          await pumpStats(tester);

          expect(
            [for (final section in sections) section.section],
            [
              ExerciseSection.resistance,
              ExerciseSection.cardio,
              ExerciseSection.isometric,
              ExerciseSection.sports,
            ],
          );
          expect(find.text('Resistance'), findsOneWidget);
          expect(find.text('Cardio'), findsOneWidget);
          expect(find.text('Isometric'), findsOneWidget);
          expect(find.text('Sports'), findsOneWidget);
        });

        testWidgets('one row per exercise, in section order, id ascending '
            'inside a section', (tester) async {
          await pumpStats(tester);

          expect(_instrumentRowKeys(), [
            'instrument_row_ex-row',
            'instrument_row_ex-squat',
            'instrument_row_ex-run',
            'instrument_row_ex-plank',
            'instrument_row_ex-bjj',
          ]);
          expect(_rowsOf(sections, ExerciseSection.resistance), hasLength(2));
        });

        testWidgets('the duplicate name appears twice, and the exercise that '
            'was never trained in the window has no row', (tester) async {
          await pumpStats(tester);

          expect(_rowTexts('ex-row').first, 'Back Squat');
          expect(_rowTexts('ex-squat').first, 'Back Squat');
          expect(
            _rowOf(sections, 'ex-row').summary.exerciseId,
            isNot(_rowOf(sections, 'ex-squat').summary.exerciseId),
          );
          // `ex-old` is trained 20 days back — outside the window, so no row.
          expect(
            _instrumentRowKeys(),
            isNot(contains('instrument_row_ex-old')),
          );
          expect(
            sections
                .expand((section) => section.rows)
                .map((row) => row.summary.exerciseId),
            isNot(contains('ex-old')),
          );
          expect(find.text('Deadlift'), findsNothing);
        });

        testWidgets('every row shows the figure the service reports for the '
            'same window', (tester) async {
          await pumpStats(tester);

          final squat = _rowOf(sections, 'ex-squat');
          expect(squat.summary.best.metric, NativeMetric.estimatedOneRepMax);
          expect(
            _rowTexts('ex-squat'),
            contains(formatNativeValue(squat.summary.best, settingsState)),
          );

          final row = _rowOf(sections, 'ex-row');
          expect(
            _rowTexts('ex-row'),
            contains(formatNativeValue(row.summary.best, settingsState)),
          );

          final run = _rowOf(sections, 'ex-run');
          expect(run.summary.best.metric, NativeMetric.pace);
          final pace = formatNativeValue(run.summary.best, settingsState);
          expect(pace, endsWith('est.'));
          expect(_rowTexts('ex-run'), contains(pace));

          final plank = _rowOf(sections, 'ex-plank');
          expect(
            _rowTexts('ex-plank'),
            contains(formatNativeValue(plank.summary.best, settingsState)),
          );

          final bjj = _rowOf(sections, 'ex-bjj');
          expect(
            _rowTexts('ex-bjj'),
            contains(formatNativeValue(bjj.summary.best, settingsState)),
          );
        });

        testWidgets('the secondary line joins the hold and round-minutes '
            'parts in order', (tester) async {
          await pumpStats(tester);

          // Resistance has no secondary line at all: name, figure, change.
          expect(_rowTexts('ex-squat'), hasLength(3));

          final plank = _rowOf(sections, 'ex-plank');
          expect(plank.summary.best.secondaryMetric, NativeMetric.duration);
          expect(
            nativeSecondaryLabel(plank.summary.best.secondaryMetric),
            'Total hold',
          );
          expect(
            _rowTexts('ex-plank'),
            contains(_secondaryLine(plank.summary.best, settingsState)),
          );

          final bjj = _rowOf(sections, 'ex-bjj');
          expect(bjj.summary.best.secondaryMetric, NativeMetric.roundMinutes);
          expect(
            nativeSecondaryLabel(bjj.summary.best.secondaryMetric),
            'Total time',
          );
          expect(
            _rowTexts('ex-bjj'),
            contains(_secondaryLine(bjj.summary.best, settingsState)),
          );
        });

        testWidgets('the change chip compares against the previous range, and '
            'reads a dash when there is nothing to compare', (tester) async {
          await pumpStats(tester);

          final squat = _rowOf(sections, 'ex-squat');
          expect(squat.previousValue, isNotNull);
          expect(
            _changeLabel('ex-squat'),
            formatNativeChange(
              squat.summary.best.metric,
              squat.summary.best.value - squat.previousValue!.value,
              settingsState,
            ),
          );

          // No history in the preceding range → nothing to compare against.
          expect(_rowOf(sections, 'ex-row').previousValue, isNull);
          expect(_changeLabel('ex-row'), _kNoChange);
          expect(_changeLabel('ex-run'), _kNoChange);
        });
      });

      // ─── S-1011: the window is the existing window ────────────────────────

      group('S-1011', () {
        setUp(() async {
          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          await repo.createPeriod(
            TrainingPeriod(
              id: 'p-1011',
              name: 'Block A',
              startDateMs: today
                  .subtract(const Duration(days: 7))
                  .millisecondsSinceEpoch,
              endDateMs:
                  today.add(const Duration(days: 1)).millisecondsSinceEpoch - 1,
              focusModalities: const [],
              createdAtMs: 1000,
              updatedAtMs: 1000,
            ),
          );
          await seedExercise(
            repo,
            id: 'ex-in',
            name: 'Back Squat',
            capabilities: const ['load', 'reps'],
          );
          await seedExercise(
            repo,
            id: 'ex-out',
            name: 'Deadlift',
            capabilities: const ['load', 'reps'],
          );
          await _seedSetSession(
            repo,
            sessionId: 's-in',
            daysAgo: 3,
            exerciseId: 'ex-in',
            weightKg: 100,
            reps: 5,
          );
          await _seedSetSession(
            repo,
            sessionId: 's-out',
            daysAgo: 20,
            exerciseId: 'ex-out',
            weightKg: 140,
            reps: 5,
          );
          await readModel();
        });

        testWidgets('the Instruments list is the period window and the chip '
            'says so', (tester) async {
          await pumpStats(tester);

          expect(window.isPeriodScoped, isTrue);
          expect(window.label, 'Block A');

          // The Instruments rows are the exercises the window yields.
          expect(
            [for (final section in sections) section.section],
            [ExerciseSection.resistance],
          );
          expect(_instrumentRowKeys(), ['instrument_row_ex-in']);
          expect(find.text('Deadlift'), findsNothing);

          // Five chips: four legacy headers plus the Instruments header, and
          // the Instruments one is the first, on the Resistance header.
          final chips = find.byKey(const Key('stats_window_chip'));
          expect(chips, findsNWidgets(5));
          expect(_textsUnder(chips), everyElement('· ${window.label}'));
          final instrumentsHeader = find.ancestor(
            of: chips.first,
            matching: find.byType(OmniCardHeader),
          );
          expect(
            tester.widget<OmniCardHeader>(instrumentsHeader).title,
            'Resistance',
          );
        });
      });

      // ─── S-1012: a window with nothing logged in it ───────────────────────

      group('S-1012', () {
        setUp(() async {
          await seedSession(repo, sessionId: 's-old-35', daysAgo: 35);
          await seedSession(repo, sessionId: 's-old-40', daysAgo: 40);
          await readModel();
        });

        testWidgets('no Instruments content renders and the legacy layout is '
            'untouched', (tester) async {
          await pumpStats(tester);

          // Nothing is logged, so nothing is selectable.
          expect(sections, isEmpty);

          expect(find.text('Resistance'), findsNothing);
          expect(find.text('Cardio'), findsNothing);
          expect(find.text('Isometric'), findsNothing);
          expect(find.text('Sports'), findsNothing);
          expect(
            find.byKey(const Key('instrument_show_all_resistance')),
            findsNothing,
          );
          expect(_instrumentRowKeys(), isEmpty);

          // The legacy layout renders exactly as it does without the list.
          expect(
            find.byKey(const Key('stats_legacy_sections')),
            findsOneWidget,
          );
          expect(find.text('ALL TIME'), findsOneWidget);
          expect(find.text('STRENGTH'), findsOneWidget);
          expect(find.text('CARDIO'), findsOneWidget);
          expect(find.text('ISOMETRIC'), findsOneWidget);
          expect(find.text('SPORTS'), findsOneWidget);
          expect(find.text('NUTRITION'), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      });

      // ─── S-1014: a row opens Exercise Progress ────────────────────────────

      group('S-1014', () {
        setUp(() async {
          await _seedFlagship(repo);
          await readModel();
        });

        testWidgets('a row tap opens Exercise Progress for that exercise, and '
            'back returns to the list', (tester) async {
          await pumpStats(tester);

          await tester.tap(find.byKey(const Key('instrument_row_ex-squat')));
          await tester.pumpAndSettle();

          expect(find.byType(ExerciseProgressScreen), findsOneWidget);
          expect(
            tester
                .widget<ExerciseProgressScreen>(
                  find.byType(ExerciseProgressScreen),
                )
                .exerciseId,
            'ex-squat',
          );
          // The pushed screen covers history older than the window: the
          // day-40 and day-20 sessions are there, on the chart's axis and as
          // history rows.
          expect(find.text(_dayLabel(40)), findsWidgets);
          expect(find.text(_dayLabel(20)), findsWidgets);
          expect(find.text(_dayLabel(1)), findsWidgets);

          final progressHeader = find.ancestor(
            of: find.text('Exercise Progress'),
            matching: find.byType(OmniBackHeader),
          );
          await tester.tap(
            find.descendant(
              of: progressHeader,
              matching: find.byIcon(Icons.arrow_back),
            ),
          );
          await tester.pumpAndSettle();

          // A different row opens that other exercise.
          await tester.tap(find.byKey(const Key('instrument_row_ex-run')));
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<ExerciseProgressScreen>(
                  find.byType(ExerciseProgressScreen),
                )
                .exerciseId,
            'ex-run',
          );
        });
      });

      // ─── S-1015: both layouts on screen at once ───────────────────────────

      group('S-1015', () {
        setUp(() async {
          await _seedFlagship(repo);
          await readModel();
        });

        testWidgets('the Instruments list sits above the untouched legacy '
            'sections', (tester) async {
          await pumpStats(tester);

          expect(find.text('Resistance'), findsOneWidget);
          expect(
            find.byKey(const Key('stats_legacy_sections')),
            findsOneWidget,
          );
          expect(
            tester.getTopLeft(find.text('Resistance')).dy,
            lessThan(tester.getTopLeft(find.text('STRENGTH')).dy),
          );
          // Every legacy header is still there, in its old order.
          for (final title in const [
            'ALL TIME',
            'STRENGTH',
            'CARDIO',
            'ISOMETRIC',
            'SPORTS',
            'NUTRITION',
          ]) {
            expect(find.text(title), findsOneWidget);
          }
        });
      });

      // ─── S-1016: the row cap and its control ──────────────────────────────

      group('S-1016', () {
        setUp(() async {
          // Resistance: exactly 5. Cardio: 6. Isometric: 8. One training day
          // each, so the sections tie on the rank and order by kind.
          for (var n = 1; n <= 5; n++) {
            await seedExercise(repo, id: 'ex-cap5-$n', name: 'Cap Five $n');
          }
          for (var n = 1; n <= 6; n++) {
            await seedExercise(repo, id: 'ex-cap6-$n', name: 'Cap Six $n');
          }
          for (var n = 1; n <= 8; n++) {
            await seedExercise(repo, id: 'ex-cap8-$n', name: 'Cap Eight $n');
          }

          await seedSession(repo, sessionId: 's-cap5', daysAgo: 1);
          for (var n = 1; n <= 5; n++) {
            await seedSetEffort(
              repo,
              segmentId: 'seg-s-cap5',
              effortId: 'eff-cap5-$n',
              exerciseId: 'ex-cap5-$n',
              entryCount: 1,
              hasExtraWeight: false,
              weightFactor: 100,
              repsBase: 5,
            );
          }

          await seedSession(repo, sessionId: 's-cap6', daysAgo: 2);
          for (var n = 1; n <= 6; n++) {
            await seedHoldEffort(
              repo,
              segmentId: 'seg-s-cap6',
              effortId: 'eff-cap6-$n',
              exerciseId: 'ex-cap6-$n',
              entryCount: 1,
              secondsPerEntry: 60,
              effortKind: 'timed',
            );
          }

          await seedSession(repo, sessionId: 's-cap8', daysAgo: 3);
          for (var n = 1; n <= 8; n++) {
            await seedHoldEffort(
              repo,
              segmentId: 'seg-s-cap8',
              effortId: 'eff-cap8-$n',
              exerciseId: 'ex-cap8-$n',
              entryCount: 1,
              secondsPerEntry: 60,
            );
          }
          await readModel();
        });

        testWidgets('the cap is five rows per section, and the control '
            'expands and collapses that section only', (tester) async {
          await pumpStats(tester);

          // (a) exactly 5 → 5 rows, no control.
          expect(_rowsOf(sections, ExerciseSection.resistance), hasLength(5));
          expect(
            find.byKey(const Key('instrument_show_all_resistance')),
            findsNothing,
          );

          // (b) 6 → 6 in the model, 5 rendered.
          expect(_rowsOf(sections, ExerciseSection.cardio), hasLength(6));
          expect(
            find.byKey(const Key('instrument_show_all_cardio')),
            findsOneWidget,
          );
          expect(_capControlLabel('cardio'), 'Show all (6)');

          await tester.tap(find.byKey(const Key('instrument_show_all_cardio')));
          await tester.pumpAndSettle();
          expect(_capControlLabel('cardio'), 'Show less');
          expect(_instrumentRowKeys(), hasLength(6 + 5 + 5));

          await tester.tap(find.byKey(const Key('instrument_show_all_cardio')));
          await tester.pumpAndSettle();
          expect(_capControlLabel('cardio'), 'Show all (6)');
          expect(_instrumentRowKeys(), hasLength(5 + 5 + 5));

          // (c) 8 → all 8 after the tap, in this section only.
          expect(_rowsOf(sections, ExerciseSection.isometric), hasLength(8));
          expect(_capControlLabel('isometric'), 'Show all (8)');
          await tester.tap(
            find.byKey(const Key('instrument_show_all_isometric')),
          );
          await tester.pumpAndSettle();
          expect(_instrumentRowKeys(), hasLength(5 + 5 + 8));
          expect(_capControlLabel('isometric'), 'Show less');
        });
      });

      // ─── S-1017: the sparkline's visibility rule ──────────────────────────

      group('S-1017', () {
        setUp(() async {
          await seedExercise(repo, id: 'ex-spark3', name: 'Three Days');
          await seedExercise(repo, id: 'ex-spark1', name: 'One Day');
          await seedExercise(repo, id: 'ex-zero', name: 'No Reading');

          for (var daysAgo = 1; daysAgo <= 3; daysAgo++) {
            await _seedSetSession(
              repo,
              sessionId: 's-spark3-$daysAgo',
              daysAgo: daysAgo,
              exerciseId: 'ex-spark3',
              weightKg: 100,
              reps: 5,
            );
          }
          await _seedSetSession(
            repo,
            sessionId: 's-spark1',
            daysAgo: 4,
            exerciseId: 'ex-spark1',
            weightKg: 100,
            reps: 5,
          );
          await seedSession(repo, sessionId: 's-zero', daysAgo: 5);
          await seedSetEffort(
            repo,
            segmentId: 'seg-s-zero',
            effortId: 'eff-s-zero',
            exerciseId: 'ex-zero',
            entryCount: 1,
            hasExtraWeight: false,
            weightFactor: 0.0,
            repsBase: 0,
          );
          await readModel();
        });

        testWidgets('the sparkline is drawn for two or more points and takes '
            'no space otherwise', (tester) async {
          await pumpStats(tester);

          expect(_rowOf(sections, 'ex-spark3').summary.points, hasLength(3));
          expect(_rowOf(sections, 'ex-spark1').summary.points, hasLength(1));
          expect(_rowOf(sections, 'ex-zero').summary.points, isEmpty);

          // (a) three training days → drawn.
          final spark3 = find.byKey(
            const Key('instrument_sparkline_ex-spark3'),
          );
          expect(spark3, findsOneWidget);
          expect(tester.getSize(spark3), _kSparklineSize);

          // (b) one point and (c) no readable points → no box, no placeholder,
          // no reserved space.
          expect(
            tester.getSize(
              find.byKey(const Key('instrument_sparkline_ex-spark1')),
            ),
            Size.zero,
          );
          expect(
            tester.getSize(
              find.byKey(const Key('instrument_sparkline_ex-zero')),
            ),
            Size.zero,
          );

          // The zero-valued row still appears, with the service's zero figure.
          expect(_rowTexts('ex-zero').first, 'No Reading');
          expect(
            _rowTexts('ex-zero'),
            contains(
              formatNativeValue(
                _rowOf(sections, 'ex-zero').summary.best,
                settingsState,
              ),
            ),
          );
        });
      });
    });
  }
}
