// The Mix card's period words (Stats 100, Phase 2a) — the screen half of P1's
// horizon change, on both repository implementations. Scenarios S-17301,
// S-17302, S-17303, S-17309 and S-17312 of
// `docs/plans/2026-11-02-100-stats-block-horizons-plan/`.
//
// The window is named in the first words of the Mix card's explainer, not in a
// chip: the card's chip is gone, the strip is titled by its horizon, and the
// unrated line is replaced by the baseline note.
//
// The harness is opened and seeded in `setUp` and never inside a `testWidgets`
// body: a widget test body runs under `FakeAsync`, where Hive's real file I/O
// never settles and the test hangs.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/utils/date_utils.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/features/stats/stats_screen.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/repository_harness.dart';

/// Tall enough that every block the scenarios address is laid out, so an
/// assertion on a widget's absence is never just an off-screen miss.
const Size _kTallViewport = Size(400, 2400);

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

/// A training period from [daysAgo] to the end of today, named [name].
///
/// The four-week window ignores it; the fixture exists to prove that.
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

/// S-17301's and S-17303's fixture: a period named "Holds" covering today, a
/// 20-minute cardio session inside it, and three 60-minute lifting sessions
/// before the period starts — all unrated, so the time measure shows.
Future<void> _seedPeriodAndMixedWindow(WorkoutRepository repo) async {
  await _seedPeriod(repo, name: 'Holds', daysAgo: 3);

  final cardioStart = _at(0, 9);
  await _seedSession(
    repo,
    sessionId: 's-cardio-today',
    startedAtMs: cardioStart,
    endedAtMs: cardioStart + 20 * 60000,
  );
  await _seedCardioEffort(repo, sessionId: 's-cardio-today', seconds: 1200);

  await _seedLifting(repo, sessionId: 's-lift-8', daysAgo: 8);
  await _seedLifting(repo, sessionId: 's-lift-12', daysAgo: 12);
  await _seedLifting(repo, sessionId: 's-lift-20', daysAgo: 20);
}

/// S-17302's fixture: four rated lifting sessions 0, 8, 15 and 22 days back,
/// one in each of the last four weeks, so the load measure shows.
Future<void> _seedFourRatedLiftingSessions(WorkoutRepository repo) async {
  await _seedLifting(repo, sessionId: 's-rated-0', daysAgo: 0, rating: 4);
  await _seedLifting(repo, sessionId: 's-rated-8', daysAgo: 8, rating: 4);
  await _seedLifting(repo, sessionId: 's-rated-15', daysAgo: 15, rating: 4);
  await _seedLifting(repo, sessionId: 's-rated-22', daysAgo: 22, rating: 4);
}

/// S-17312's fixture: two completed lifting sessions 35 and 60 days back —
/// both outside the 28-day window, so the card is one line.
Future<void> _seedBreak(WorkoutRepository repo) async {
  await _seedLifting(repo, sessionId: 's-old-35', daysAgo: 35);
  await _seedLifting(repo, sessionId: 's-old-60', daysAgo: 60);
}

void main() {
  for (final factory in harnessFactories) {
    final harness = factory();

    group('Mix card horizons — ${harness.name}', () {
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

      // ─── S-17301 ─────────────────────────────────────────────────────────

      group('S-17301 the time-measure explainer opens with the window', () {
        setUp(() => _seedPeriodAndMixedWindow(repo));

        testWidgets('the explainer names the window and the chip is gone', (
          tester,
        ) async {
          await pumpStats(tester);

          expect(_textsUnder(find.byKey(const Key('mix_explainer'))), [
            'Last 4 weeks. Your training split by time spent.',
          ]);
          expect(find.byKey(const Key('stats_window_chip')), findsNothing);
          expect(tester.takeException(), isNull);
        });
      });

      // ─── S-17302 ─────────────────────────────────────────────────────────

      group('S-17302 the load-measure explainer opens with the window', () {
        setUp(() => _seedFourRatedLiftingSessions(repo));

        testWidgets('the explainer names the window and the measure', (
          tester,
        ) async {
          await pumpStats(tester);

          expect(_textsUnder(find.byKey(const Key('mix_explainer'))), [
            'Last 4 weeks. Your training split by how hard each session felt.',
          ]);
          expect(tester.takeException(), isNull);
        });
      });

      // ─── S-17303 ─────────────────────────────────────────────────────────

      group('S-17303 the strip is titled by its horizon', () {
        setUp(() => _seedPeriodAndMixedWindow(repo));

        testWidgets('the strip title leads with the horizon', (tester) async {
          await pumpStats(tester);

          expect(_textsUnder(find.byKey(const Key('mix_strip_title'))), [
            'Last 8 weeks, week by week',
          ]);
          expect(tester.takeException(), isNull);
        });
      });

      // ─── S-17309 ─────────────────────────────────────────────────────────

      group('S-17309 the unrated line is gone', () {
        group('time measure', () {
          setUp(() async {
            await _seedPeriodAndMixedWindow(repo);
            await _seedLifting(
              repo,
              sessionId: 's-unrated-time',
              daysAgo: 5,
              minutes: 30,
            );
          });

          testWidgets('the baseline note stands in for the unrated line', (
            tester,
          ) async {
            await pumpStats(tester);

            expect(find.byKey(const Key('mix_unrated_note')), findsNothing);
            expect(find.byKey(const Key('mix_baseline_note')), findsOneWidget);
            expect(tester.takeException(), isNull);
          });
        });

        group('load measure', () {
          setUp(() async {
            await _seedFourRatedLiftingSessions(repo);
            await _seedLifting(repo, sessionId: 's-unrated-load', daysAgo: 3);
          });

          testWidgets('the unrated note is gone under the load measure', (
            tester,
          ) async {
            await pumpStats(tester);

            expect(find.byKey(const Key('mix_unrated_note')), findsNothing);
            expect(tester.takeException(), isNull);
          });
        });
      });

      // ─── S-17312 ─────────────────────────────────────────────────────────

      group('S-17312 the empty-window card has no chip', () {
        setUp(() => _seedBreak(repo));

        testWidgets('the empty line stands alone under the header', (
          tester,
        ) async {
          await pumpStats(tester);

          expect(find.byKey(const Key('mix_window_empty')), findsOneWidget);
          expect(_textsUnder(find.byKey(const Key('mix_window_empty'))), [
            'No training in the last 4 weeks. '
                'Last session: ${OmniDateUtils.formatShort(_day(35))}.',
          ]);
          expect(find.byKey(const Key('stats_window_chip')), findsNothing);
          expect(find.byKey(const Key('mix_explainer')), findsNothing);
          expect(tester.takeException(), isNull);
        });
      });
    });
  }
}
