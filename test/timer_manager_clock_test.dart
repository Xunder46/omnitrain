// The four timer transitions stamp their start and finish from the
// `TimerManager` clock seam, not from the real clock (S-7001).
//
// Plan: `docs/plans/2026-10-21-48-auto-push-flake-plan/
// 2026-10-21-48-auto-push-flake-plan.md`, D-1 and S-7001.
//
// The instant is unlike the real clock, so a stamp taken from `DateTime.now()`
// cannot pass by accident.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/state/workout/timer_manager.dart';

/// A frozen instant no real clock would produce during the run.
final DateTime _frozen = DateTime.utc(2001, 2, 3, 4, 5, 6);

/// A timer manager whose every read of the clock answers [_frozen].
Future<(MockWorkoutRepository, TimerManager)> _manager() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  final timer = TimerManager(
    repo,
    notify: () {},
    setError: (_) {},
    clearError: () {},
    clock: () => _frozen,
  );
  return (repo, timer);
}

void main() {
  test(
    'S-7001 startTimedEntry stamps startedAtMs from the injected clock',
    () async {
      final (repo, timer) = await _manager();
      await timer.addTimedEntry('e-t');

      await timer.startTimedEntry('e-t', 0);

      final instance = (await repo.getTimedInstances('e-t')).single;
      expect(instance.startedAtMs, _frozen.millisecondsSinceEpoch);
    },
  );

  test(
    'S-7001 finishTimedEntry stamps finishedAtMs from the injected clock',
    () async {
      final (repo, timer) = await _manager();
      await timer.addTimedEntry('e-t');
      await timer.startTimedEntry('e-t', 0);

      await timer.finishTimedEntry('e-t', 0);

      final instance = (await repo.getTimedInstances('e-t')).single;
      expect(instance.startedAtMs, _frozen.millisecondsSinceEpoch);
      expect(instance.finishedAtMs, _frozen.millisecondsSinceEpoch);
    },
  );

  test(
    'S-7001 startRound stamps startedAtMs from the injected clock',
    () async {
      final (repo, timer) = await _manager();
      await timer.addRound('e-r', plannedDurationSecs: 0);

      await timer.startRound('e-r', 0);

      final round = (await repo.getRoundInstances('e-r')).single;
      expect(round.startedAtMs, _frozen.millisecondsSinceEpoch);
    },
  );

  test('S-7001 completeRound stamps from the injected clock', () async {
    final (repo, timer) = await _manager();
    // A zero plan makes the finish equal the start, so the frozen start and
    // finish are the same stamped instant.
    await timer.addRound('e-r', plannedDurationSecs: 0);
    await timer.startRound('e-r', 0);

    await timer.completeRound('e-r', 0);

    final round = (await repo.getRoundInstances('e-r')).single;
    expect(round.startedAtMs, _frozen.millisecondsSinceEpoch);
    expect(round.finishedAtMs, _frozen.millisecondsSinceEpoch);
  });
}
