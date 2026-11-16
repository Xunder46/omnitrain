// Plan 211 — a Best is one session (screens half).
//
// `docs/plans/2026-11-16-211-stats-best-is-one-session-plan/
// 2026-11-16-211-stats-best-is-one-session-plan.md`, scenarios S-21205 and
// S-21206: the two all-time screens read
// `computeExerciseMetrics(bestSingleSession: true)` (P1), so a no-distance
// cardio exercise shows its longest single session on Records & Trends, and a
// rounds exercise shows its best one session on Exercise Progress — not the
// all-history total.
//
// Both repository implementations run. The harness is opened and seeded in
// `setUp` and never inside a `testWidgets` body: a widget test body runs under
// `FakeAsync`, where Hive's real file I/O never settles and the test hangs.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/features/stats/exercise_progress_screen.dart';
import 'package:omnitrain/features/stats/records_and_trends_screen.dart';
import 'package:omnitrain/features/stats/widgets/stats_pill.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/repository_harness.dart';

/// The height every scenario pumps at: tall enough that every section of the
/// screen is laid out, so an assertion on a widget's absence is never just an
/// off-screen miss.
const Size _kTallViewport = Size(400, 2400);

// ─── Fixture helpers (copied from test/stats_best_single_session_test.dart) ─

/// A `timed` effort on [segmentId], with no entries yet.
Future<void> addTimedEffort(
  WorkoutRepository repo, {
  required String segmentId,
  required String effortId,
  required String exerciseId,
  int orderIndex = 0,
}) => repo.createEffort(
  SegmentEffort(
    id: effortId,
    segmentId: segmentId,
    orderIndex: orderIndex,
    effortKind: 'timed',
    exerciseId: exerciseId,
    createdAtMs: fixtureStart,
    updatedAtMs: fixtureStart,
  ),
);

/// One finished timed entry of [effortId]: [durationSecs] long, with a distance
/// row of [metres] when it is given.
Future<void> seedTimedEntry(
  WorkoutRepository repo, {
  required String effortId,
  required int entryIndex,
  required int durationSecs,
  double? metres,
}) async {
  await repo.createTimedInstance(
    timedInstance(
      effortId,
      entryIndex,
      durationSecs: durationSecs,
      entryIndex: entryIndex,
    ),
  );
  if (metres != null) {
    await repo.createObservation(
      distanceRow(effortId, entryIndex, metres, atMs: fixtureRowAt(entryIndex)),
    );
  }
}

/// Every `Text` under [scope], in document order.
List<String> _textsUnder(Finder scope) {
  final texts = <String>[];
  for (final element
      in find.descendant(of: scope, matching: find.byType(Text)).evaluate()) {
    final data = (element.widget as Text).data;
    if (data != null) texts.add(data);
  }
  return texts;
}

void main() {
  for (final factory in harnessFactories) {
    final harness = factory();

    group('Best single session screens — ${harness.name}', () {
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

      Future<void> pump(WidgetTester tester, Widget screen) async {
        await tester.binding.setSurfaceSize(_kTallViewport);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(MaterialApp(home: screen));
        await tester.pumpAndSettle();
      }

      Widget recordsScreen() => RecordsAndTrendsScreen(
        workoutState: workoutState,
        settingsState: settingsState,
      );

      // ─── S-21205 ──────────────────────────────────────────────────────────

      group('S-21205', () {
        setUp(() async {
          // The S-21201 fixture: a no-distance cardio exercise, three sessions
          // of 1200 s, 2100 s and 1500 s — the best one session reads 35:00,
          // the all-history total would read 1:20:00.
          await seedExercise(
            repo,
            id: 'ex-ell',
            name: 'Elliptical',
            capabilities: const ['time'],
          );
          for (final (sessionId, daysAgo, durationSecs) in const [
            ('s-ell-a', 3, 1200),
            ('s-ell-b', 2, 2100),
            ('s-ell-c', 1, 1500),
          ]) {
            await seedSession(
              repo,
              sessionId: sessionId,
              modality: 'cardio_endurance',
              daysAgo: daysAgo,
            );
            await addTimedEffort(
              repo,
              segmentId: 'seg-$sessionId',
              effortId: 'eff-${sessionId.substring(2)}',
              exerciseId: 'ex-ell',
            );
            await seedTimedEntry(
              repo,
              effortId: 'eff-${sessionId.substring(2)}',
              entryIndex: 0,
              durationSecs: durationSecs,
            );
          }
        });

        testWidgets('S-21205 the Records & Trends entry reads the best single '
            'session', (tester) async {
          await pump(tester, recordsScreen());

          final entry = find.byKey(const Key('records_entry_ex-ell'));
          expect(entry, findsOneWidget);
          final texts = _textsUnder(entry);
          expect(
            texts,
            contains('35:00'),
            reason: 'the best single session (2100 s), not the total',
          );
          expect(
            texts,
            isNot(contains('1:20:00')),
            reason: 'the 4800 s all-history total never reads as the Best',
          );
        });
      });

      // ─── S-21206 ──────────────────────────────────────────────────────────

      group('S-21206', () {
        setUp(() async {
          // The S-21202 fixture: three BJJ sessions of 3 rounds of 180 s,
          // 5 of 120 s and 2 of 90 s, finished with start stamps — the best
          // one session reads 5 rounds / 10 min, the all-history total would
          // read 10 rounds / 22 min.
          await seedExercise(repo, id: 'ex-bjj', name: 'BJJ');
          await seedSession(
            repo,
            sessionId: 's-bjj-a',
            modality: 'sports',
            daysAgo: 3,
          );
          await seedRoundEffort(
            repo,
            segmentId: 'seg-s-bjj-a',
            effortId: 'eff-bjj-a',
            exerciseId: 'ex-bjj',
            rounds: [
              roundInstance(
                'eff-bjj-a',
                0,
                durationSecs: 180,
                startedAtMs: fixtureStart,
              ),
              roundInstance(
                'eff-bjj-a',
                1,
                durationSecs: 180,
                startedAtMs: fixtureStart + 1000,
              ),
              roundInstance(
                'eff-bjj-a',
                2,
                durationSecs: 180,
                startedAtMs: fixtureStart + 2000,
              ),
            ],
          );
          await seedSession(
            repo,
            sessionId: 's-bjj-b',
            modality: 'sports',
            daysAgo: 2,
          );
          await seedRoundEffort(
            repo,
            segmentId: 'seg-s-bjj-b',
            effortId: 'eff-bjj-b',
            exerciseId: 'ex-bjj',
            rounds: [
              for (var i = 0; i < 5; i++)
                roundInstance(
                  'eff-bjj-b',
                  i,
                  durationSecs: 120,
                  startedAtMs: fixtureStart + i * 1000,
                ),
            ],
          );
          await seedSession(
            repo,
            sessionId: 's-bjj-c',
            modality: 'sports',
            daysAgo: 1,
          );
          await seedRoundEffort(
            repo,
            segmentId: 'seg-s-bjj-c',
            effortId: 'eff-bjj-c',
            exerciseId: 'ex-bjj',
            rounds: [
              roundInstance(
                'eff-bjj-c',
                0,
                durationSecs: 90,
                startedAtMs: fixtureStart,
              ),
              roundInstance(
                'eff-bjj-c',
                1,
                durationSecs: 90,
                startedAtMs: fixtureStart + 1000,
              ),
            ],
          );
        });

        testWidgets('S-21206 the Exercise Progress Best pill reads the best '
            'single session', (tester) async {
          await pump(
            tester,
            ExerciseProgressScreen(
              workoutState: workoutState,
              settingsState: settingsState,
              exerciseId: 'ex-bjj',
            ),
          );

          // The winning session's own day row in RECENT SESSIONS reads
          // '5 rounds' too (the per-day points are unchanged), so the Best
          // figure is asserted through its pill below.
          expect(find.text('10 min'), findsOneWidget);
          expect(find.text('10 rounds'), findsNothing);
          expect(find.text('22 min'), findsNothing);

          // The ALL TIME row is a labelled pill row (label uppercased inside
          // the pill), so each figure is asserted through its pill.
          final pills = {
            for (final pill in tester.widgetList<StatsPill>(
              find.byType(StatsPill),
            ))
              pill.label: pill.value,
          };
          expect(pills['Best'], '5 rounds');
          expect(pills['Total time'], '10 min');
          expect(pills['Sessions'], '3');
        });
      });
    });
  }
}
