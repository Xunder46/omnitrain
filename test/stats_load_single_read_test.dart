// One Stats load reads history once and builds the Instruments sections once
// per window (plan 107), scenarios S-18102..S-18104. Plain `test()`, never
// `testWidgets`: Hive's real file I/O settles only on the real event loop.
// `now` is Wednesday 2026-03-18 12:00 local.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/models/stats_progress.dart';
import 'package:omnitrain/core/services/signals/session_history.dart';
import 'package:omnitrain/core/services/signals/signal.dart';
import 'package:omnitrain/core/services/signals_service.dart';
import 'package:omnitrain/core/services/stats_progress_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';

import 'helpers/repository_harness.dart';

DateTime _d(int month, int day) => DateTime(2026, month, day, 12);

final DateTime _now = DateTime(2026, 3, 18, 12);

final StatsWindow _window = StatsWindow(
  fromMs: DateTime(2026, 3, 1),
  toMs: DateTime(2026, 3, 31),
  label: 'Test window',
  isPeriodScoped: false,
  recentDays: 30,
);

/// Counts the session-list reads a Stats load pays for.
class _CountingRepository extends MockWorkoutRepository {
  int allReads = 0;
  int rangeReads = 0;

  @override
  Future<List<TrainingSession>> getAllSessions() async {
    allReads++;
    return super.getAllSessions();
  }

  @override
  Future<List<TrainingSession>> getSessionsByDateRange(
    int fromMs,
    int toMs,
  ) async {
    rangeReads++;
    return super.getSessionsByDateRange(fromMs, toMs);
  }
}

Future<void> _seed(
  WorkoutRepository repo,
  DateTime start, {
  bool ended = true,
  String suffix = '',
}) async {
  final ms = start.millisecondsSinceEpoch;
  await repo.createSession(
    TrainingSession(
      id: 's-$ms$suffix',
      ownerUserId: 'user-1',
      startedAtMs: ms,
      endedAtMs: ended ? ms + 3600000 : null,
      createdAtMs: ms,
      updatedAtMs: ms,
    ),
  );
}

Future<void> _clearSessions(WorkoutRepository repo) async {
  const farFutureMs = 4102444800000; // 2100-01-01
  for (final session in await repo.getSessionsByDateRange(0, farFutureMs)) {
    await repo.deleteSession(session.id);
  }
}

SignalContext _context(WorkoutRepository repo) => SignalContext(
  now: _now,
  window: _window,
  mix: null,
  progressService: StatsProgressService(repo),
  repository: repo,
);

void main() {
  group('S-18102 one Stats load reads the session list once', () {
    test(
      'computeTotals plus the signals evaluate on one getAllSessions',
      () async {
        final repo = _CountingRepository();
        await repo.initialize();
        await _clearSessions(repo);
        for (final start in [
          _d(3, 2),
          _d(3, 5),
          _d(3, 9),
          _d(3, 12),
          _d(3, 16),
        ]) {
          await _seed(repo, start);
        }
        // The counters measure the Stats load, not the seeding.
        repo.allReads = 0;
        repo.rangeReads = 0;

        final service = StatsProgressService(repo);
        await service.computeTotals();
        await SignalsService(
          repository: repo,
          progressService: service,
        ).evaluateCandidates(now: _now, window: _window, mix: null);

        expect(repo.rangeReads, 0);
        expect(repo.allReads, 1);
      },
    );
  });

  for (final factory in harnessFactories) {
    final harness = factory();

    group('S-18103 completedSessionStarts — ${harness.name}', () {
      late WorkoutRepository repo;

      setUp(() async {
        repo = await harness.open();
        await _clearSessions(repo);
      });

      tearDown(() async {
        await harness.close();
      });

      test(
        'oldest first, no open session, no future one, the one at now in',
        () async {
          // Newest first, as the brief seeds them.
          await _seed(repo, DateTime(2026, 3, 16, 9));
          await _seed(repo, DateTime(2026, 3, 2, 9));
          await _seed(
            repo,
            DateTime(2026, 3, 17, 9),
            ended: false,
            suffix: '-open',
          );
          await _seed(repo, DateTime(2026, 3, 20, 9), suffix: '-future');
          await _seed(repo, _now, suffix: '-now');

          expect(
            await StatsProgressService(repo).completedSessionStarts(now: _now),
            equals([DateTime(2026, 3, 2, 9), DateTime(2026, 3, 16, 9), _now]),
          );
        },
      );

      test(
        'the session_history read for the signals returns the same three',
        () async {
          await _seed(repo, DateTime(2026, 3, 16, 9));
          await _seed(repo, DateTime(2026, 3, 2, 9));
          await _seed(
            repo,
            DateTime(2026, 3, 17, 9),
            ended: false,
            suffix: '-open',
          );
          await _seed(repo, DateTime(2026, 3, 20, 9), suffix: '-future');
          await _seed(repo, _now, suffix: '-now');

          expect(
            await completedSessionStarts(_context(repo)),
            equals([DateTime(2026, 3, 2, 9), DateTime(2026, 3, 16, 9), _now]),
          );
        },
      );
    });
  }

  group('S-18104 the Instruments sections are built once per window', () {
    test(
      'a second ask for the same window is the first list; a new window rebuilds',
      () async {
        final repo = MockWorkoutRepository();
        await repo.initialize();
        await _clearSessions(repo);
        await seedExercise(repo, id: 'ex-hold-test', name: 'Deep Squat');
        await seedSession(repo, sessionId: 's-hold-1', daysAgo: 1);
        await seedHoldEffort(
          repo,
          segmentId: 'seg-s-hold-1',
          effortId: 'eff-s-hold-1',
          exerciseId: 'ex-hold-test',
          entryCount: 1,
          secondsPerEntry: 50,
        );

        final service = StatsProgressService(repo);
        final now = DateTime.now();
        final w = StatsProgressService.statsWindow(now: now);

        final first = await service.computeInstrumentSections(window: w);
        final second = await service.computeInstrumentSections(window: w);
        expect(first, isNotEmpty);
        expect(identical(first, second), isTrue);

        final third = await service.computeInstrumentSections(
          window: StatsWindow(
            fromMs: w.fromMs,
            toMs: w.toMs.add(const Duration(days: 1)),
            label: w.label,
            isPeriodScoped: w.isPeriodScoped,
          ),
        );
        expect(identical(first, third), isFalse);
      },
    );
  });
}
