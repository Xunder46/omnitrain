// Phone hardening Phase 3 — an end is never stored before its start (D-153).
//
// Scenarios: S-155 of
// `docs/plans/2026-10-08-18a-phone-hardening-plan/2026-10-08-18a-phone-hardening-plan.md`.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  return repo;
}

/// The invariant every phone-owned writer must leave behind (D-153): a row
/// either has no end or an end at or after its start.
void _expectOrderedWindow(TrainingSession? stored, {required String writer}) {
  expect(stored, isNotNull, reason: '$writer left no row in the store');
  final endedAtMs = stored!.endedAtMs;
  if (endedAtMs != null) {
    expect(
      endedAtMs,
      greaterThanOrEqualTo(stored.startedAtMs),
      reason:
          '$writer stored an end ($endedAtMs) before its start '
          '(${stored.startedAtMs})',
    );
  }
}

void main() {
  // ══════════════════════════════════════════════════════════════════════════
  // S-155 — the real writer path: end, then the first exercise is added
  // ══════════════════════════════════════════════════════════════════════════

  test(
    'S-155: the reset after an end writes nothing and the stored window stays ordered',
    () async {
      final repo = await _freshRepo();
      final state = WorkoutState(repo);

      await state.createNewSession();
      await state.endSession();

      final afterEnd = (await repo.getSession(state.currentSession!.id))!;
      expect(
        afterEnd.endedAtMs,
        isNotNull,
        reason: 'the fixture needs a finished window to invert',
      );

      // The real-world gap this scenario comes from: the wrist ends the
      // session, the user adds the first exercise on the phone a moment later.
      // The clock is real here (plain test, no FakeAsync), so the reset would
      // land the start after the stored end without the fix.
      await Future<void>.delayed(const Duration(milliseconds: 2));
      await state.resetSessionTimerStart();

      final stored = (await repo.getSession(afterEnd.id))!;
      expect(
        stored.endedAtMs,
        isNotNull,
        reason: 'the reset must not clear the end either',
      );
      expect(
        stored.endedAtMs!,
        greaterThanOrEqualTo(stored.startedAtMs),
        reason: 'endedAtMs >= startedAtMs must hold for the stored row',
      );
      expect(
        stored.startedAtMs,
        afterEnd.startedAtMs,
        reason: 'the reset wrote nothing: a finished window is history',
      );
      expect(
        stored.updatedAtMs,
        afterEnd.updatedAtMs,
        reason: 'the reset issued no write at all',
      );
    },
  );

  // ══════════════════════════════════════════════════════════════════════════
  // S-155 — the writer table: every phone-owned writer leaves the row ordered
  // ══════════════════════════════════════════════════════════════════════════

  group('S-155 writer table — every phone-owned writer leaves an ordered window', () {
    test('endSession stores an end at or after the start', () async {
      final repo = await _freshRepo();
      final state = WorkoutState(repo);

      await state.createNewSession();
      final startedAtMs = state.currentSession!.startedAtMs;

      await state.endSession();

      final stored = (await repo.getSession(state.currentSession!.id))!;
      _expectOrderedWindow(stored, writer: 'endSession');
      expect(stored.endedAtMs, isNotNull);
      expect(
        stored.startedAtMs,
        startedAtMs,
        reason: 'the end write never moves the start',
      );
    });

    test('endSession clamps a start that lies ahead of the phone clock', () async {
      final repo = await _freshRepo();

      // The state layer reads the real clock, so the only way to put `now`
      // before `startedAtMs` is a row whose start is in the future — exactly
      // the case the clamp exists for.
      final futureStartMs = DateTime.now().millisecondsSinceEpoch + 3600000;
      await repo.createSession(
        TrainingSession(
          id: 's-future-start',
          ownerUserId: 'user-1',
          startedAtMs: futureStartMs,
          createdAtMs: futureStartMs,
          updatedAtMs: futureStartMs,
        ),
      );
      final state = WorkoutState(repo);
      await state.loadHistoricalSession('s-future-start');

      await state.endSession();

      final stored = (await repo.getSession('s-future-start'))!;
      _expectOrderedWindow(stored, writer: 'endSession (future start)');
      expect(
        stored.endedAtMs,
        futureStartMs,
        reason: 'the end is clamped up to the start it cannot precede',
      );
    });

    test(
      'updateSessionEndTime with a zero or negative duration writes nothing',
      () async {
        final repo = await _freshRepo();
        final state = WorkoutState(repo);

        await state.createNewSession();
        await state.endSession();
        final afterEnd = (await repo.getSession(state.currentSession!.id))!;

        await state.updateSessionEndTime(0);
        await state.updateSessionEndTime(-300);

        final stored = (await repo.getSession(afterEnd.id))!;
        _expectOrderedWindow(stored, writer: 'updateSessionEndTime');
        expect(
          stored.endedAtMs,
          afterEnd.endedAtMs,
          reason: 'a zero or negative duration is a no-op',
        );
        expect(
          stored.updatedAtMs,
          afterEnd.updatedAtMs,
          reason: 'the no-op issued no write at all',
        );
      },
    );

    test('resetSessionTimerStart still moves a running session start', () async {
      final repo = await _freshRepo();
      final state = WorkoutState(repo);

      await state.createNewSession();
      final originalStart = state.currentSession!.startedAtMs;

      await Future<void>.delayed(const Duration(milliseconds: 2));
      await state.resetSessionTimerStart();

      final stored = (await repo.getSession(state.currentSession!.id))!;
      _expectOrderedWindow(stored, writer: 'resetSessionTimerStart (running)');
      expect(stored.endedAtMs, isNull);
      expect(
        stored.startedAtMs,
        greaterThan(originalStart),
        reason: 'a session without an end still starts counting when it starts',
      );
    });
  });
}
