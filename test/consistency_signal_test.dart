// The Consistency and Training Gap signals on real repositories (plan 105),
// scenario S-17809 of `docs/plans/2026-11-03-105-consistency-plan/`. Plain
// `test()`, never `testWidgets`: Hive's real file I/O settles only on the real
// event loop. `now` is Wednesday 2026-03-18 12:00 local.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/models/signals.dart';
import 'package:omnitrain/core/models/stats_progress.dart';
import 'package:omnitrain/core/services/signals/consistency_signal.dart';
import 'package:omnitrain/core/services/signals/signal.dart';
import 'package:omnitrain/core/services/signals/training_gap_signal.dart';
import 'package:omnitrain/core/services/stats_progress_service.dart';
import 'package:omnitrain/data/models/models.dart';
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

/// 20 sessions in eight Monday weeks, four in the last (see test/consistency_test.dart).
final List<DateTime> _fixtureA = [
  _d(1, 20), _d(1, 21), _d(1, 22), _d(1, 23),
  _d(1, 27), _d(1, 29), _d(2, 3), _d(2, 5), _d(2, 10), _d(2, 12),
  _d(2, 17), _d(2, 19), _d(2, 24), _d(2, 26), _d(3, 3), _d(3, 5),
  _d(3, 10), _d(3, 11), _d(3, 13), _d(3, 15),
];

/// One session a week in W8..W2 and two in the last week.
final List<DateTime> _fixtureLow = [
  _d(1, 20), _d(1, 27), _d(2, 3), _d(2, 10), _d(2, 17), _d(2, 24), _d(3, 3),
  _d(3, 10), _d(3, 12),
];

/// 22 session days, every 2 or 3 days, the last on Mar 12.
final List<DateTime> _fixtureG = [
  _d(1, 19), _d(1, 21), _d(1, 24), _d(1, 26), _d(1, 29), _d(1, 31),
  _d(2, 3), _d(2, 5), _d(2, 8), _d(2, 10), _d(2, 13), _d(2, 15),
  _d(2, 18), _d(2, 20), _d(2, 23), _d(2, 25), _d(2, 28),
  _d(3, 2), _d(3, 5), _d(3, 7), _d(3, 10), _d(3, 12),
];

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

SignalContext _context(WorkoutRepository repo, {String startOfWeek = 'monday'}) =>
    SignalContext(
      now: _now,
      window: _window,
      mix: null,
      progressService: StatsProgressService(repo),
      repository: repo,
      startOfWeek: startOfWeek,
    );

void main() {
  for (final factory in harnessFactories) {
    final harness = factory();

    group('S-17809 the signals on real sessions — ${harness.name}', () {
      late WorkoutRepository repo;

      setUp(() async {
        repo = await harness.open();
        await _clearSessions(repo);
      });

      tearDown(() async {
        await harness.close();
      });

      test('Consistency proposes its card from fixture A, Monday weeks', () async {
        for (final start in _fixtureA) {
          await _seed(repo, start);
        }

        final card = await const ConsistencySignal().evaluate(_context(repo));

        expect(card, isNotNull);
        expect(card!.id, 'consistency');
        expect(card.kind, SignalKind.positive);
        expect(card.title, 'Consistency');
        expect(card.priority, 50);
        expect(
          card.observation,
          'Last week you logged 4 sessions, above your usual 2.5 a week over '
          'the last 8 weeks.',
        );
        expect(card.suggestion, isNull);
      });

      test('Consistency abstains with Sunday weeks on the same sessions', () async {
        for (final start in _fixtureA) {
          await _seed(repo, start);
        }

        expect(
          await const ConsistencySignal().evaluate(
            _context(repo, startOfWeek: 'sunday'),
          ),
          isNull,
        );
      });

      test('a session still in progress is not a session', () async {
        for (final start in _fixtureLow) {
          await _seed(repo, start);
        }
        // Counted, it would make three sessions last week and fire.
        await _seed(repo, _d(3, 11), ended: false, suffix: '-open');

        expect(await const ConsistencySignal().evaluate(_context(repo)), isNull);
      });

      test('the Training Gap proposes its card from fixture G', () async {
        for (final start in _fixtureG) {
          await _seed(repo, start);
        }

        final card = await const TrainingGapSignal().evaluate(_context(repo));

        expect(card, isNotNull);
        expect(card!.id, 'training-gap');
        expect(card.kind, SignalKind.caution);
        expect(card.title, 'Training gap');
        expect(card.priority, 25);
        expect(
          card.observation,
          'No session in 6 days, longer than any gap in your last 8 weeks '
          '(the longest was 3 days).',
        );
        expect(card.suggestion, isNull);
      });

      test('an open session yesterday does not close the gap', () async {
        for (final start in _fixtureG) {
          await _seed(repo, start);
        }
        await _seed(repo, _d(3, 17), ended: false, suffix: '-open');

        expect(await const TrainingGapSignal().evaluate(_context(repo)), isNotNull);
      });

      test('both signals read no ratings and wait for nothing', () async {
        expect(const ConsistencySignal().needsRatedWeeks, isFalse);
        expect(const TrainingGapSignal().needsRatedWeeks, isFalse);
        expect(await const ConsistencySignal().waitingFor(_context(repo)), isNull);
        expect(await const TrainingGapSignal().waitingFor(_context(repo)), isNull);
      });
    });

    group('S-18305 the Training Gap signal follows Start of Week — ${harness.name}', () {
      late WorkoutRepository repo;

      setUp(() async {
        repo = await harness.open();
        await _clearSessions(repo);
      });

      tearDown(() async {
        await harness.close();
      });

      final List<DateTime> sundayStart = [
        for (var i = 0; i < 11; i++) DateTime(2026, 2, 8 + 3 * i, 12),
      ];

      test('Monday weeks: the card speaks', () async {
        for (final start in sundayStart) {
          await _seed(repo, start);
        }

        final card = await const TrainingGapSignal().evaluate(_context(repo));

        expect(card, isNotNull);
        expect(
          card!.observation,
          'No session in 8 days, longer than any gap in your last 8 weeks '
          '(the longest was 3 days).',
        );
      });

      test('Sunday weeks: five completed weeks of history is too little', () async {
        for (final start in sundayStart) {
          await _seed(repo, start);
        }

        expect(
          await const TrainingGapSignal().evaluate(
            _context(repo, startOfWeek: 'sunday'),
          ),
          isNull,
        );
      });
    });

    group('S-18306 a session dated after now changes neither card — ${harness.name}', () {
      late WorkoutRepository repo;

      setUp(() async {
        repo = await harness.open();
        await _clearSessions(repo);
      });

      tearDown(() async {
        await harness.close();
      });

      test('the Training Gap card is the same with a session dated after now', () async {
        for (final start in _fixtureG) {
          await _seed(repo, start);
        }
        await _seed(repo, DateTime(2026, 3, 20, 12), suffix: '-future');

        final card = await const TrainingGapSignal().evaluate(_context(repo));

        expect(card, isNotNull);
        expect(
          card!.observation,
          'No session in 6 days, longer than any gap in your last 8 weeks '
          '(the longest was 3 days).',
        );
      });

      test('the Consistency card is the same with sessions dated after now', () async {
        for (final start in _fixtureA) {
          await _seed(repo, start);
        }
        await _seed(repo, _d(3, 19), suffix: '-f1');
        await _seed(repo, _d(3, 20), suffix: '-f2');
        await _seed(repo, _d(3, 21), suffix: '-f3');

        final card = await const ConsistencySignal().evaluate(_context(repo));

        expect(card, isNotNull);
        expect(
          card!.observation,
          'Last week you logged 4 sessions, above your usual 2.5 a week over '
          'the last 8 weeks.',
        );
      });
    });
  }
}
