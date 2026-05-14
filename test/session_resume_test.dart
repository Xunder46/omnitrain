import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/hive_workout_repository.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

// ── Helpers ──────────────────────────────────────────────────────────────

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  return repo;
}

TrainingSession _session({
  required String id,
  required int startedAtMs,
  int? endedAtMs,
}) {
  return TrainingSession(
    id: id,
    ownerUserId: 'user-1',
    startedAtMs: startedAtMs,
    endedAtMs: endedAtMs,
    createdAtMs: startedAtMs,
    updatedAtMs: startedAtMs,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ════════════════════════════════════════════════════════════════════════
  // getInProgressSessions — repository contract
  // ════════════════════════════════════════════════════════════════════════

  group('MockWorkoutRepository.getInProgressSessions', () {
    test('returns empty list when no sessions exist', () async {
      final repo = await _freshRepo();
      final result = await repo.getInProgressSessions();
      expect(result, isEmpty);
    });

    test('returns empty list when all sessions are finished', () async {
      final repo = await _freshRepo();
      final now = DateTime.now().millisecondsSinceEpoch;
      await repo.createSession(
        _session(id: 'a', startedAtMs: now, endedAtMs: now + 1000),
      );
      await repo.createSession(
        _session(id: 'b', startedAtMs: now + 1, endedAtMs: now + 2000),
      );

      final result = await repo.getInProgressSessions();
      expect(result, isEmpty);
    });

    test('returns sessions where endedAtMs is null', () async {
      final repo = await _freshRepo();
      final now = DateTime.now().millisecondsSinceEpoch;
      // One finished, two in-progress
      await repo.createSession(
        _session(id: 'done', startedAtMs: now, endedAtMs: now + 1),
      );
      await repo.createSession(_session(id: 'ip-old', startedAtMs: now + 1));
      await repo.createSession(_session(id: 'ip-new', startedAtMs: now + 2));

      final result = await repo.getInProgressSessions();
      expect(
        result.map((s) => s.id).toList(),
        containsAll(['ip-old', 'ip-new']),
      );
      expect(result.any((s) => s.id == 'done'), isFalse);
    });

    test('results are sorted most-recent startedAtMs first', () async {
      final repo = await _freshRepo();
      final base = DateTime.now().millisecondsSinceEpoch;
      await repo.createSession(_session(id: 'first', startedAtMs: base));
      await repo.createSession(
        _session(id: 'second', startedAtMs: base + 1000),
      );
      await repo.createSession(_session(id: 'third', startedAtMs: base + 2000));

      final result = await repo.getInProgressSessions();
      expect(result.first.id, 'third');
      expect(result.last.id, 'first');
    });
  });

  // ════════════════════════════════════════════════════════════════════════
  // WorkoutState.checkForInProgressSession
  // ════════════════════════════════════════════════════════════════════════

  group('WorkoutState.checkForInProgressSession', () {
    test('returns null when storage is empty', () async {
      final repo = await _freshRepo();
      final state = WorkoutState(repo);

      final result = await state.checkForInProgressSession();

      expect(result, isNull);
    });

    test('returns null when all sessions are finished', () async {
      final repo = await _freshRepo();
      final now = DateTime.now().millisecondsSinceEpoch;
      await repo.createSession(
        _session(id: 's1', startedAtMs: now, endedAtMs: now + 1),
      );

      final state = WorkoutState(repo);
      final result = await state.checkForInProgressSession();

      expect(result, isNull);
    });

    test('returns the in-progress session when exactly one exists', () async {
      final repo = await _freshRepo();
      final now = DateTime.now().millisecondsSinceEpoch;
      await repo.createSession(_session(id: 'ip-1', startedAtMs: now));

      final state = WorkoutState(repo);
      final result = await state.checkForInProgressSession();

      expect(result, isNotNull);
      expect(result!.id, 'ip-1');
    });

    test(
      'returns most-recent session when multiple in-progress sessions exist',
      () async {
        final repo = await _freshRepo();
        final base = DateTime.now().millisecondsSinceEpoch;
        await repo.createSession(_session(id: 'old', startedAtMs: base));
        await repo.createSession(_session(id: 'new', startedAtMs: base + 5000));

        final state = WorkoutState(repo);
        final result = await state.checkForInProgressSession();

        expect(result!.id, 'new');
      },
    );

    test(
      'deletes older duplicates when multiple in-progress sessions exist',
      () async {
        final repo = await _freshRepo();
        final base = DateTime.now().millisecondsSinceEpoch;
        await repo.createSession(_session(id: 'oldest', startedAtMs: base));
        await repo.createSession(
          _session(id: 'middle', startedAtMs: base + 1000),
        );
        await repo.createSession(
          _session(id: 'newest', startedAtMs: base + 2000),
        );

        final state = WorkoutState(repo);
        await state.checkForInProgressSession();

        // Only 'newest' should survive
        final remaining = await repo.getInProgressSessions();
        expect(remaining.map((s) => s.id).toList(), ['newest']);
      },
    );

    test('does not delete the returned (most-recent) session', () async {
      final repo = await _freshRepo();
      final now = DateTime.now().millisecondsSinceEpoch;
      await repo.createSession(_session(id: 'solo', startedAtMs: now));

      final state = WorkoutState(repo);
      final result = await state.checkForInProgressSession();

      expect(result!.id, 'solo');
      final session = await repo.getSession('solo');
      expect(session, isNotNull);
    });
  });

  // ════════════════════════════════════════════════════════════════════════
  // WorkoutState.deleteSessionById
  // ════════════════════════════════════════════════════════════════════════

  group('WorkoutState.deleteSessionById', () {
    test('removes session from storage', () async {
      final repo = await _freshRepo();
      final now = DateTime.now().millisecondsSinceEpoch;
      await repo.createSession(_session(id: 'to-delete', startedAtMs: now));

      final state = WorkoutState(repo);
      await state.deleteSessionById('to-delete');

      final session = await repo.getSession('to-delete');
      expect(session, isNull);
    });

    test('does not affect currentSession in memory', () async {
      final repo = await _freshRepo();
      // Create and start a session the normal way
      final state = WorkoutState(repo);
      await state.createNewSession(modality: 'resistance_lifting');
      final currentId = state.currentSession!.id;

      // Delete some other unrelated session
      final now = DateTime.now().millisecondsSinceEpoch;
      await repo.createSession(_session(id: 'other', startedAtMs: now));
      await state.deleteSessionById('other');

      // In-memory session should be unchanged
      expect(state.currentSession, isNotNull);
      expect(state.currentSession!.id, currentId);
    });

    test('does not throw when session id does not exist', () async {
      final repo = await _freshRepo();
      final state = WorkoutState(repo);

      // Should complete without error
      await expectLater(state.deleteSessionById('non-existent-id'), completes);
    });
  });

  // ════════════════════════════════════════════════════════════════════════
  // WorkoutState.countSetsForSession
  // ════════════════════════════════════════════════════════════════════════

  group('WorkoutState.countSetsForSession', () {
    test('returns 0 when session has no segments/efforts', () async {
      final repo = await _freshRepo();
      final state = WorkoutState(repo);

      final result = await state.countSetsForSession('missing-session');

      expect(result, 0);
    });

    test('counts observations across multiple segments and efforts', () async {
      final repo = await _freshRepo();
      final state = WorkoutState(repo);
      await state.createNewSession(modality: 'resistance_lifting');

      final exercises = await repo.getExercises();
      expect(exercises.length, greaterThanOrEqualTo(2));

      final firstEffortId = await state.addExerciseToSession(exercises[0]);
      await state.addEntry(firstEffortId);

      final now = DateTime.now().millisecondsSinceEpoch;
      final secondSegmentId = 'segment-extra-$now';
      await repo.createSegment(
        SessionSegment(
          id: secondSegmentId,
          sessionId: state.currentSession!.id,
          orderIndex: 1,
          segmentType: 'workout',
          name: 'Extra Segment',
          createdAtMs: now,
          updatedAtMs: now,
        ),
      );

      await state.loadSessionData();
      final secondEffortId = await state.addExerciseToSession(
        exercises[1],
        segmentId: secondSegmentId,
      );
      await state.addEntry(secondEffortId);

      final segments = await repo.getSessionSegments(state.currentSession!.id);
      var expectedObservationCount = 0;
      for (final segment in segments) {
        final efforts = await repo.getSegmentEfforts(segment.id);
        for (final effort in efforts) {
          final observations = await repo.getEffortObservations(effort.id);
          expectedObservationCount += observations.length;
        }
      }

      final count = await state.countSetsForSession(state.currentSession!.id);

      expect(count, expectedObservationCount);
      expect(count, greaterThan(0));
    });
  });

  // ════════════════════════════════════════════════════════════════════════
  // Hive malformed-record regression
  // ════════════════════════════════════════════════════════════════════════

  group('HiveWorkoutRepository.getInProgressSessions', () {
    test('skips malformed records without crashing', () async {
      const pathProviderChannel = MethodChannel(
        'plugins.flutter.io/path_provider',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProviderChannel, (call) async {
            return '/tmp';
          });

      try {
        final repo = HiveWorkoutRepository();
        await repo.initialize();

        final sessionsBox = Hive.box<Map>('sessions');
        await sessionsBox.clear();

        final now = DateTime.now().millisecondsSinceEpoch;
        final active = _session(id: 'hive-active', startedAtMs: now);
        final done = _session(
          id: 'hive-done',
          startedAtMs: now - 1000,
          endedAtMs: now - 500,
        );

        await repo.createSession(active);
        await repo.createSession(done);

        // Intentionally malformed shape for TrainingSession.fromMap parsing.
        await sessionsBox.put('hive-bad', {'started_at_ms': 'not-a-number'});

        final result = await repo.getInProgressSessions();

        expect(result.map((s) => s.id), contains('hive-active'));
        expect(result.any((s) => s.id == 'hive-done'), isFalse);
        expect(result.any((s) => s.id == 'hive-bad'), isFalse);
      } finally {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(pathProviderChannel, null);
      }
    });
  });

  // ════════════════════════════════════════════════════════════════════════
  // Cold-start guard: hasActiveSession suppresses check
  // ════════════════════════════════════════════════════════════════════════

  group('Cold-start guard', () {
    test(
      'checkForInProgressSession is irrelevant when in-memory session exists',
      () async {
        // This models the guard in HomeScreen.initState:
        //   if (widget.workoutState.hasActiveSession) return;
        // When hasActiveSession is true the check is never called.
        // Here we verify the guard condition itself is correct.
        final repo = await _freshRepo();
        final state = WorkoutState(repo);
        await state.createNewSession(modality: 'resistance_lifting');

        // Need at least one effort for hasActiveSession to be true
        final exercises = await repo.getExercises();
        expect(
          exercises,
          isNotEmpty,
          reason: 'Seed data must contain at least one exercise for this test',
        );
        await state.addExerciseToSession(exercises.first);

        expect(
          state.hasActiveSession,
          isTrue,
          reason: 'hasActiveSession must be true after adding an exercise',
        );

        // Even if storage has a stale session, the check should not run
        // because the guard (hasActiveSession) short-circuits it.
        // We confirm the guard flag works independently.
      },
    );
  });
}
