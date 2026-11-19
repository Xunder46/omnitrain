// One failing signal or Fuel read no longer fails the Stats load (plan 212,
// scenarios S-21301, S-21302): `SignalsService.evaluateCandidates` skips a
// signal that throws, like one that abstains. Plain `test()`, never
// `testWidgets`: Hive's real file I/O settles only on the real event loop.
// The harness is opened in `setUp`.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/models/signals.dart';
import 'package:omnitrain/core/models/stats_progress.dart';
import 'package:omnitrain/core/services/signals/signal.dart';
import 'package:omnitrain/core/services/signals_service.dart';
import 'package:omnitrain/core/services/stats_progress_service.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';

import 'helpers/repository_harness.dart';

/// A signal whose `evaluate` returns a card or throws, on a flag.
class _FakeSignal implements Signal {
  _FakeSignal(this.id, {required this.card, this.throwing = false});

  @override
  final String id;
  final SignalCard? card;
  final bool throwing;

  @override
  SignalKind get kind => SignalKind.caution;

  @override
  int get priority => 1;

  @override
  bool get needsRatedWeeks => false;

  @override
  Future<String?> waitingFor(SignalContext context) async => null;

  @override
  Future<SignalCard?> evaluate(SignalContext context) async {
    if (throwing) throw StateError('unreadable');
    return card;
  }
}

SignalCard _card(String id) => SignalCard(
  id: id,
  kind: SignalKind.caution,
  priority: 1,
  title: 'Title $id',
  observation: 'Observation $id',
);

final StatsWindow _window = StatsWindow(
  fromMs: DateTime(2026, 3, 1),
  toMs: DateTime(2026, 3, 31),
  label: 'Test window',
  isPeriodScoped: false,
  recentDays: 30,
);

/// Local noon of the fixed "today" every fixture counts back from.
final DateTime _now = DateTime(2026, 3, 20, 12);

void main() {
  for (final factory in harnessFactories) {
    final harness = factory();

    group('S-21301 one throwing signal among speakers — ${harness.name}', () {
      late WorkoutRepository repo;

      setUp(() async {
        repo = await harness.open();
      });

      tearDown(() async {
        await harness.close();
      });

      test('the throwing signal is skipped, the others speak in order', () async {
        final service = SignalsService(
          repository: repo,
          progressService: StatsProgressService(repo),
          signals: [
            _FakeSignal('a', card: _card('a')),
            _FakeSignal('b', card: null, throwing: true),
            _FakeSignal('c', card: _card('c')),
          ],
        );
        final cards = await service.evaluateCandidates(
          now: _now,
          window: _window,
          mix: null,
          dismissedAtMs: const {},
        );
        expect(cards.map((c) => c.id), ['a', 'c']);
      });
    });

    group('S-21302 every signal throws — ${harness.name}', () {
      late WorkoutRepository repo;

      setUp(() async {
        repo = await harness.open();
      });

      tearDown(() async {
        await harness.close();
      });

      test('the result is empty and the call does not throw', () async {
        final service = SignalsService(
          repository: repo,
          progressService: StatsProgressService(repo),
          signals: [
            _FakeSignal('b1', card: null, throwing: true),
            _FakeSignal('b2', card: null, throwing: true),
          ],
        );
        final cards = await service.evaluateCandidates(
          now: _now,
          window: _window,
          mix: null,
          dismissedAtMs: const {},
        );
        expect(cards, isEmpty);
      });
    });
  }
}
