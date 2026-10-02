// Stats PR 4c — the removed Stats layout is unreachable, proven twice (D-606).
//
// S-1208 (behavioural): in a pumped `StatsScreen` no legacy section title and
// no `Key('stats_legacy_sections')` is findable in any of the three states —
// all kinds of history, sessions without food, zero sessions.
// S-1209 (structural): the source text of the screen holds none of the removed
// fragments. S-1210: no chart widget remains on the screen.
//
// S-836 (D-610) is transcribed here verbatim: the km↔mi conversion goes
// through `UnitFormatter`, never through a literal in the screen.
//
// Plan: `docs/plans/2026-10-01-04c-stats-pr4c-remove-legacy-sections-plan/`.
//
// The behavioural half runs on both repository implementations. The harness is
// opened and seeded in `setUp` and never inside a `testWidgets` body: a widget
// test body runs under `FakeAsync`, where Hive's real file I/O never settles
// and the test hangs.
import 'dart:io';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/features/stats/stats_screen.dart';
import 'package:omnitrain/features/stats/widgets/scrollable_trend_chart.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/repository_harness.dart';

/// The screen the guard is about.
const String _kScreenPath = 'lib/features/stats/stats_screen.dart';

/// The five section titles the removed legacy layout rendered.
const List<String> _kLegacyTitles = <String>[
  'STRENGTH',
  'CARDIO',
  'ISOMETRIC',
  'SPORTS',
  'NUTRITION',
];

/// The fragments D-606(b) forbids in the screen's source.
const List<String> _kForbiddenFragments = <String>[
  'stats_legacy_sections',
  'STRENGTH',
  'CARDIO',
  'ISOMETRIC',
  'SPORTS',
  'NUTRITION',
  'RecentPRList',
  'fl_chart',
  '_ChartSeries',
  '_LinearScale',
];

/// The Instruments section headers the live list draws.
const List<String> _kInstrumentSections = <String>[
  'Resistance',
  'Cardio',
  'Isometric',
  'Sports',
];

/// Tall enough that the whole screen is laid out, so an assertion on a widget's
/// absence is never just an off-screen miss.
const Size _kTallViewport = Size(400, 2400);

// ─── readers ────────────────────────────────────────────────────────────────

String _screenSource() => File(_kScreenPath).readAsStringSync();

/// Every Instruments row key on screen, in document order.
List<String> _instrumentRowKeys() {
  final keys = <String>[];
  for (final element
      in find
          .byWidgetPredicate(
            (widget) =>
                widget.key is ValueKey<String> &&
                (widget.key! as ValueKey<String>).value.startsWith(
                  'instrument_row_',
                ),
          )
          .evaluate()) {
    keys.add((element.widget.key! as ValueKey<String>).value);
  }
  return keys;
}

// ─── fixtures ───────────────────────────────────────────────────────────────

/// The repository's food log, emptied.
///
/// The Mock harness opens with `SeedData.sampleConsumedFoods()` already
/// written, so a scenario that wants no food has to clear it; the Hive harness
/// opens empty.
Future<void> _clearConsumedFoods(WorkoutRepository repo) async {
  const farFutureMs = 4102444800000; // 2100-01-01
  for (final row in await repo.getConsumedFoodsInRange(0, farFutureMs)) {
    await repo.deleteConsumedFood(row.id);
  }
}

/// One logged `ConsumedFood` on the local day [daysAgo] days back.
Future<void> _seedFood(
  WorkoutRepository repo, {
  required String id,
  required int daysAgo,
  required double protein,
  required double carbs,
  required double fat,
}) async {
  final now = DateTime.now();
  final day = DateTime(now.year, now.month, now.day - daysAgo);
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

/// A `timed` effort of one finished 1800 s instance on an exercise carrying the
/// time and distance capabilities.
Future<void> _seedTimedEffort(
  WorkoutRepository repo, {
  required String sessionId,
  required String exerciseId,
  required String exerciseName,
}) async {
  final effortId = 'eff-$sessionId';
  await seedExercise(
    repo,
    id: exerciseId,
    name: exerciseName,
    capabilities: const ['time', 'distance'],
  );
  await repo.createEffort(
    SegmentEffort(
      id: effortId,
      segmentId: 'seg-$sessionId',
      orderIndex: 0,
      effortKind: 'timed',
      exerciseId: exerciseId,
      createdAtMs: fixtureStart,
      updatedAtMs: fixtureStart,
    ),
  );
  await repo.createTimedInstance(
    timedInstance(effortId, 0, durationSecs: 1800, entryIndex: 0),
  );
}

/// S-1201's fixture: one completed session per effort kind inside the window,
/// food on 2 of the last 3 days and a target for today.
Future<void> _seedAllKinds(WorkoutRepository repo) async {
  await seedSession(repo, sessionId: 's-set', daysAgo: 1);
  await seedExercise(
    repo,
    id: 'ex-a',
    name: 'Back Squat',
    capabilities: const ['load', 'reps'],
  );
  await seedSetEffort(
    repo,
    segmentId: 'seg-s-set',
    effortId: 'eff-s-set',
    exerciseId: 'ex-a',
    entryCount: 3,
    hasExtraWeight: false,
    weightFactor: 100.0,
    repsBase: 5,
  );

  await seedSession(
    repo,
    sessionId: 's-timed',
    daysAgo: 1,
    modality: 'cardio_endurance',
  );
  await _seedTimedEffort(
    repo,
    sessionId: 's-timed',
    exerciseId: 'ex-b',
    exerciseName: 'Easy Run',
  );

  await seedSession(repo, sessionId: 's-drill', daysAgo: 1);
  await seedExercise(
    repo,
    id: 'ex-c',
    name: 'Plank',
    capabilities: const ['hold'],
  );
  await seedHoldEffort(
    repo,
    segmentId: 'seg-s-drill',
    effortId: 'eff-s-drill',
    exerciseId: 'ex-c',
    entryCount: 3,
  );

  await seedSession(repo, sessionId: 's-round', daysAgo: 1, modality: 'sports');
  await seedExercise(
    repo,
    id: 'ex-d',
    name: 'BJJ Round',
    capabilities: const ['rounds'],
  );
  await seedRoundEffort(
    repo,
    segmentId: 'seg-s-round',
    effortId: 'eff-s-round',
    exerciseId: 'ex-d',
    rounds: [for (var n = 0; n < 5; n++) roundInstance('eff-s-round', n)],
  );

  await _clearConsumedFoods(repo);
  await _seedFood(
    repo,
    id: 'food-1',
    daysAgo: 1,
    protein: 120,
    carbs: 220,
    fat: 55,
  );
  await _seedFood(
    repo,
    id: 'food-2',
    daysAgo: 2,
    protein: 150,
    carbs: 250,
    fat: 60,
  );
  final now = DateTime.now();
  await repo.saveNutritionTargetForDate(
    DateTime(now.year, now.month, now.day).millisecondsSinceEpoch,
    NutritionTarget(calories: 2200, protein: 150, carbs: 250, fat: 70),
  );
}

/// S-1202's fixture: two completed sessions with set efforts, no food.
Future<void> _seedSessionsNoFood(WorkoutRepository repo) async {
  await _clearConsumedFoods(repo);
  for (final daysAgo in const [1, 2]) {
    final sessionId = 's-$daysAgo';
    await seedSession(repo, sessionId: sessionId, daysAgo: daysAgo);
    await seedExercise(
      repo,
      id: 'ex-$daysAgo',
      name: 'Row $daysAgo',
      capabilities: const ['load', 'reps'],
    );
    await seedSetEffort(
      repo,
      segmentId: 'seg-$sessionId',
      effortId: 'eff-$sessionId',
      exerciseId: 'ex-$daysAgo',
      entryCount: 3,
      hasExtraWeight: false,
      weightFactor: 60.0,
      repsBase: 8,
    );
  }
}

/// S-1203's fixture: no completed session and no food at all.
Future<void> _seedNothing(WorkoutRepository repo) async {
  await _clearConsumedFoods(repo);
  for (final session in await repo.getAllSessions()) {
    await repo.deleteSession(session.id);
  }
}

void main() {
  // ══════════════════════════════════════════════════════════════════════════
  // S-1209 — the source guard (structural)
  // ══════════════════════════════════════════════════════════════════════════

  group('S-1209 source guard', () {
    test('the screen holds none of the removed fragments', () {
      final source = _screenSource();
      for (final fragment in _kForbiddenFragments) {
        expect(
          source.contains(fragment),
          isFalse,
          reason:
              'D-606(b): `$fragment` must never return to $_kScreenPath — the '
              'legacy layout is removed, not hidden',
        );
      }
    });

    test('S-836 the Stats screen holds no km↔mi constant', () {
      final source = _screenSource();
      for (final literal in ['0.621371', '1.609344', '1609.3']) {
        expect(
          source.contains(literal),
          isFalse,
          reason:
              'D-314: the conversion belongs to UnitFormatter.metresPerUnit, '
              'never to a literal in this file ($literal)',
        );
      }
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // S-1208 — the legacy titles are absent in every state (behavioural)
  // ══════════════════════════════════════════════════════════════════════════

  for (final factory in harnessFactories) {
    final harness = factory();

    group('S-1208 behavioural guard — ${harness.name}', () {
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

      /// No legacy title, no legacy key, and the pump threw nothing.
      void expectNoLegacySurface(WidgetTester tester) {
        expect(find.byKey(const Key('stats_legacy_sections')), findsNothing);
        for (final title in _kLegacyTitles) {
          expect(
            find.text(title),
            findsNothing,
            reason: 'D-606(a): `$title` must never return to the screen',
          );
        }
        expect(tester.takeException(), isNull);
      }

      /// No chart of any kind is left on the screen (S-1210).
      void expectNoChart() {
        expect(find.byType(LineChart), findsNothing);
        expect(find.byType(ScrollableTrendChart), findsNothing);
      }

      // ─── S-1201: every kind of history ────────────────────────────────────

      group('all kinds of history', () {
        setUp(() => _seedAllKinds(repo));

        testWidgets('the live screen renders and no legacy surface does', (
          tester,
        ) async {
          await pumpStats(tester);

          // Not empty: the all-time eyebrow, one row per logged kind and the
          // Fuel row are all there.
          expect(find.text('ALL TIME'), findsOneWidget);
          expect(_instrumentRowKeys().toSet(), {
            'instrument_row_ex-a',
            'instrument_row_ex-b',
            'instrument_row_ex-c',
            'instrument_row_ex-d',
          });
          for (final section in _kInstrumentSections) {
            expect(find.text(section), findsOneWidget);
          }
          expect(find.byKey(const Key('fuel_section')), findsOneWidget);
          expect(
            tester.getTopLeft(find.byKey(const Key('fuel_section'))).dy,
            greaterThan(tester.getTopLeft(find.text('Resistance')).dy),
          );

          expectNoLegacySurface(tester);
          expectNoChart();
        });
      });

      // ─── S-1202: sessions but no food ─────────────────────────────────────

      group('sessions but no food', () {
        setUp(() => _seedSessionsNoFood(repo));

        testWidgets('the live screen renders and no legacy surface does', (
          tester,
        ) async {
          await pumpStats(tester);

          expect(find.text('ALL TIME'), findsOneWidget);
          expect(_instrumentRowKeys(), hasLength(2));
          expect(find.text('Resistance'), findsOneWidget);
          expect(find.byKey(const Key('fuel_section')), findsNothing);

          expectNoLegacySurface(tester);
          expectNoChart();
        });
      });

      // ─── S-1203: zero completed sessions ──────────────────────────────────

      group('zero completed sessions', () {
        setUp(() => _seedNothing(repo));

        testWidgets('the empty state renders and no legacy surface does', (
          tester,
        ) async {
          await pumpStats(tester);

          expect(find.text('No sessions yet'), findsOneWidget);
          expect(find.text('ALL TIME'), findsNothing);
          expect(_instrumentRowKeys(), isEmpty);
          for (final section in _kInstrumentSections) {
            expect(find.text(section), findsNothing);
          }
          expect(find.byKey(const Key('fuel_section')), findsNothing);

          expectNoLegacySurface(tester);
          expectNoChart();
        });
      });
    });
  }
}
