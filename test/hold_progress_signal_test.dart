// The Hold Progress signal on real repositories (plan 106), scenario S-17908 of
// `docs/plans/2026-11-03-106-hold-progress-plan/`. Plain `test()`, never
// `testWidgets`: Hive's real file I/O settles only on the real event loop.
//
// Sessions are seeded with the shared helpers: `daysAgo` counts back from the
// device clock, the Stats window is the four weeks ending today and the window
// before it is the 28 days before that.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/models/signals.dart';
import 'package:omnitrain/core/services/signals/hold_progress_signal.dart';
import 'package:omnitrain/core/services/signals/signal.dart';
import 'package:omnitrain/core/services/stats_progress_service.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';

import 'helpers/repository_harness.dart';

/// One session [daysAgo] days back holding one hold of [secs] seconds.
Future<void> _hold(
  WorkoutRepository repo, {
  required String sessionId,
  required int daysAgo,
  required int secs,
}) async {
  await seedSession(repo, sessionId: sessionId, daysAgo: daysAgo);
  await seedHoldEffort(
    repo,
    segmentId: 'seg-$sessionId',
    effortId: 'eff-$sessionId',
    exerciseId: 'ex-hold-test',
    entryCount: 1,
    secondsPerEntry: secs,
  );
}

Future<void> _clearSessions(WorkoutRepository repo) async {
  const farFutureMs = 4102444800000; // 2100-01-01
  for (final session in await repo.getSessionsByDateRange(0, farFutureMs)) {
    await repo.deleteSession(session.id);
  }
}

SignalContext _context(WorkoutRepository repo) {
  final now = DateTime.now();
  return SignalContext(
    now: now,
    window: StatsProgressService.statsWindow(now: now),
    mix: null,
    progressService: StatsProgressService(repo),
    repository: repo,
  );
}

void main() {
  for (final factory in harnessFactories) {
    final harness = factory();

    group('S-17908 the Hold Progress signal on real sessions — ${harness.name}', () {
      late WorkoutRepository repo;

      setUp(() async {
        repo = await harness.open();
        await _clearSessions(repo);
        await seedExercise(repo, id: 'ex-hold-test', name: 'Deep Squat');
      });

      tearDown(() async {
        await harness.close();
      });

      test('three sessions in the window against two before it: the card', () async {
        await _hold(repo, sessionId: 's-w1', daysAgo: 1, secs: 50);
        await _hold(repo, sessionId: 's-w2', daysAgo: 3, secs: 60);
        await _hold(repo, sessionId: 's-w3', daysAgo: 5, secs: 70);
        await _hold(repo, sessionId: 's-p1', daysAgo: 31, secs: 40);
        await _hold(repo, sessionId: 's-p2', daysAgo: 34, secs: 45);

        final card = await const HoldProgressSignal().evaluate(_context(repo));

        expect(card, isNotNull);
        expect(card!.id, 'hold-progress');
        expect(card.kind, SignalKind.positive);
        expect(card.title, 'Hold progress');
        expect(card.priority, 40);
        expect(
          card.observation,
          'Your longest hold on Deep Squat is up 25 s over the last 4 weeks, '
          'now 70 s.',
        );
        expect(card.suggestion, isNull);
      });

      test('only two sessions in the window: no card', () async {
        await _hold(repo, sessionId: 's-w1', daysAgo: 1, secs: 50);
        await _hold(repo, sessionId: 's-w2', daysAgo: 3, secs: 70);
        await _hold(repo, sessionId: 's-p1', daysAgo: 31, secs: 40);
        await _hold(repo, sessionId: 's-p2', daysAgo: 34, secs: 45);

        expect(await const HoldProgressSignal().evaluate(_context(repo)), isNull);
      });

      test('nothing before the window: no card', () async {
        await _hold(repo, sessionId: 's-w1', daysAgo: 1, secs: 50);
        await _hold(repo, sessionId: 's-w2', daysAgo: 3, secs: 60);
        await _hold(repo, sessionId: 's-w3', daysAgo: 5, secs: 70);

        expect(await const HoldProgressSignal().evaluate(_context(repo)), isNull);
      });

      test('the signal reads no ratings and waits for nothing', () async {
        expect(const HoldProgressSignal().needsRatedWeeks, isFalse);
        expect(await const HoldProgressSignal().waitingFor(_context(repo)), isNull);
      });
    });
  }
}
