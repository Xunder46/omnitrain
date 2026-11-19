import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/models/session_summary.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  return repo;
}

/// Seeds a session with one set effort (reps × weight, so strength volume is
/// reps × weight) and optionally one timed effort with a single finished
/// TimedInstance of [cardioMs] milliseconds. Returns the session.
Future<TrainingSession> _seed(
  MockWorkoutRepository repo, {
  required String id,
  required int startedAtMs,
  int? endedAtMs,
  String? routineTemplateId,
  String? modality,
  String? title,
  double? strengthReps,
  double? strengthWeight,
  int? cardioMs,
}) async {
  final session = TrainingSession(
    id: id,
    ownerUserId: 'u-1',
    routineTemplateId: routineTemplateId,
    startedAtMs: startedAtMs,
    endedAtMs: endedAtMs,
    title: title,
    modality: modality,
    createdAtMs: startedAtMs,
    updatedAtMs: endedAtMs ?? startedAtMs,
  );
  await repo.createSession(session);

  final segId = 'seg-$id';
  await repo.createSegment(
    SessionSegment(
      id: segId,
      sessionId: id,
      orderIndex: 0,
      segmentType: 'main',
      createdAtMs: startedAtMs,
      updatedAtMs: startedAtMs,
    ),
  );

  if (strengthReps != null && strengthWeight != null) {
    final effortId = 'eff-$id';
    await repo.createEffort(
      SegmentEffort(
        id: effortId,
        segmentId: segId,
        orderIndex: 0,
        effortKind: 'set',
        exerciseId: 'ex-$id',
        createdAtMs: startedAtMs,
        updatedAtMs: startedAtMs,
      ),
    );
    await repo.createObservation(
      EffortObservation(
        id: 'obs-$effortId-0-reps',
        effortId: effortId,
        metricId: 'metric-reps',
        valueInt: strengthReps.round(),
        createdAtMs: startedAtMs,
        updatedAtMs: startedAtMs,
      ),
    );
    await repo.createObservation(
      EffortObservation(
        id: 'obs-$effortId-0-weight',
        effortId: effortId,
        metricId: 'metric-weight',
        valueReal: strengthWeight,
        createdAtMs: startedAtMs + 1,
        updatedAtMs: startedAtMs + 1,
      ),
    );
  }

  if (cardioMs != null) {
    final effortId = 'eff-$id-timed';
    await repo.createEffort(
      SegmentEffort(
        id: effortId,
        segmentId: segId,
        orderIndex: 1,
        effortKind: 'timed',
        exerciseId: 'ex-cardio-$id',
        createdAtMs: startedAtMs,
        updatedAtMs: startedAtMs,
      ),
    );
    final secs = cardioMs ~/ 1000;
    await repo.createTimedInstance(
      TimedInstance(
        id: 'ti-$effortId-0',
        effortId: effortId,
        entryIndex: 0,
        targetDurationSecs: secs,
        actualDurationSecs: secs,
        startedAtMs: startedAtMs,
        finishedAtMs: startedAtMs + cardioMs,
        state: TimedState.finished,
        createdAtMs: startedAtMs,
        updatedAtMs: startedAtMs,
      ),
    );
  }

  return session;
}

/// Builds the current SessionSummary by hand (comparison logic only).
SessionSummary _summary(
  String sessionId, {
  required int startedAtMs,
  required int endedAtMs,
  double volume = 0,
  int cardioMs = 0,
}) {
  return SessionSummary(
    sessionId: sessionId,
    title: 'Summary',
    startedAtMs: startedAtMs,
    endedAtMs: endedAtMs,
    totalDurationMs: endedAtMs - startedAtMs,
    totalVolume: volume,
    totalSets: volume > 0 ? 1 : 0,
    totalCardioDurationMs: cardioMs,
    exercises: const [],
  );
}

void main() {
  group('Summary comparison basis (plan 246)', () {
    test('S-24601 routine current compares with the same routine, '
        'not a free session', () async {
      final repo = await _freshRepo();
      final service = SessionSummaryService(repo);

      // S2: free session, volume 1000 (20 × 50).
      await _seed(
        repo,
        id: 's2',
        startedAtMs: 2000,
        endedAtMs: 3000,
        modality: 'resistance_lifting',
        strengthReps: 20,
        strengthWeight: 50.0,
      );
      // S1: same routine t1, volume 400 (8 × 50).
      await _seed(
        repo,
        id: 's1',
        startedAtMs: 1000,
        endedAtMs: 2000,
        routineTemplateId: 't1',
        title: 'Push Day',
        strengthReps: 8,
        strengthWeight: 50.0,
      );
      final current = await _seed(
        repo,
        id: 'current',
        startedAtMs: 5000,
        endedAtMs: 6000,
        routineTemplateId: 't1',
        title: 'Push Day',
        strengthReps: 8,
        strengthWeight: 50.0,
      );

      final result = await service.compareGroupsToPreviousSession(
        current,
        _summary('current', startedAtMs: 5000, endedAtMs: 6000, volume: 500),
      );

      expect(result.deltas['strength']!.delta, 100.0); // 500 - 400
      expect(result.deltas['strength']!.hasPrevious, true);
      expect(result.basis, isNotNull);
      expect(result.basis!.isRoutine, true);
      expect(result.basis!.label, 'Push Day');
      expect(result.basis!.previousStartedAtMs, 1000);
    });

    test('S-24602 routine current with only a free session before it '
        'has no figure and no basis', () async {
      final repo = await _freshRepo();
      final service = SessionSummaryService(repo);

      await _seed(
        repo,
        id: 's2',
        startedAtMs: 2000,
        endedAtMs: 3000,
        modality: 'resistance_lifting',
        strengthReps: 20,
        strengthWeight: 50.0,
      );
      final current = await _seed(
        repo,
        id: 'current',
        startedAtMs: 5000,
        endedAtMs: 6000,
        routineTemplateId: 't1',
        title: 'Push Day',
        strengthReps: 8,
        strengthWeight: 50.0,
      );

      final result = await service.compareGroupsToPreviousSession(
        current,
        _summary('current', startedAtMs: 5000, endedAtMs: 6000, volume: 500),
      );

      expect(result.deltas['strength']!.hasPrevious, false);
      expect(result.deltas['strength']!.delta, isNull);
      expect(result.basis, isNull);
    });

    test('S-24603 routine current with only a different routine before it '
        'has no figure and no basis', () async {
      final repo = await _freshRepo();
      final service = SessionSummaryService(repo);

      await _seed(
        repo,
        id: 's2',
        startedAtMs: 2000,
        endedAtMs: 3000,
        routineTemplateId: 't2',
        title: 'Pull Day',
        strengthReps: 20,
        strengthWeight: 50.0,
      );
      final current = await _seed(
        repo,
        id: 'current',
        startedAtMs: 5000,
        endedAtMs: 6000,
        routineTemplateId: 't1',
        title: 'Push Day',
        strengthReps: 8,
        strengthWeight: 50.0,
      );

      final result = await service.compareGroupsToPreviousSession(
        current,
        _summary('current', startedAtMs: 5000, endedAtMs: 6000, volume: 500),
      );

      expect(result.deltas['strength']!.hasPrevious, false);
      expect(result.deltas['strength']!.delta, isNull);
      expect(result.basis, isNull);
    });

    test('S-24604 free null-modality current compares with the last free '
        'null-modality session, not a routine session', () async {
      final repo = await _freshRepo();
      final service = SessionSummaryService(repo);

      // S3: routine session with a null modality — must be excluded.
      await _seed(
        repo,
        id: 's3',
        startedAtMs: 3000,
        endedAtMs: 4000,
        routineTemplateId: 't1',
        title: 'Push Day',
        strengthReps: 20,
        strengthWeight: 50.0,
      );
      // S1: free, null modality, volume 400 (8 × 50).
      await _seed(
        repo,
        id: 's1',
        startedAtMs: 1000,
        endedAtMs: 2000,
        strengthReps: 8,
        strengthWeight: 50.0,
      );
      final current = await _seed(
        repo,
        id: 'current',
        startedAtMs: 5000,
        endedAtMs: 6000,
        strengthReps: 8,
        strengthWeight: 50.0,
      );

      final result = await service.compareGroupsToPreviousSession(
        current,
        _summary('current', startedAtMs: 5000, endedAtMs: 6000, volume: 500),
      );

      expect(result.deltas['strength']!.delta, 100.0); // 500 - 400
      expect(result.deltas['strength']!.hasPrevious, true);
      expect(result.basis, isNotNull);
      expect(result.basis!.isRoutine, false);
      expect(result.basis!.label, 'Free Training');
      expect(result.basis!.previousStartedAtMs, 1000);
    });

    test(
      'S-24605 type match excludes other modalities and routine sessions',
      () async {
        final repo = await _freshRepo();
        final service = SessionSummaryService(repo);

        // S3: free but a different modality — excluded.
        await _seed(
          repo,
          id: 's3',
          startedAtMs: 3000,
          endedAtMs: 4000,
          modality: 'sports',
          strengthReps: 20,
          strengthWeight: 50.0,
        );
        // S2: same modality but a routine session — excluded.
        await _seed(
          repo,
          id: 's2',
          startedAtMs: 2000,
          endedAtMs: 3000,
          routineTemplateId: 't1',
          title: 'Push Day',
          modality: 'resistance_lifting',
          strengthReps: 20,
          strengthWeight: 50.0,
        );
        // S1: free, same modality, volume 400 (8 × 50) — the like session.
        await _seed(
          repo,
          id: 's1',
          startedAtMs: 1000,
          endedAtMs: 2000,
          modality: 'resistance_lifting',
          strengthReps: 8,
          strengthWeight: 50.0,
        );
        final current = await _seed(
          repo,
          id: 'current',
          startedAtMs: 5000,
          endedAtMs: 6000,
          modality: 'resistance_lifting',
          strengthReps: 8,
          strengthWeight: 50.0,
        );

        final result = await service.compareGroupsToPreviousSession(
          current,
          _summary('current', startedAtMs: 5000, endedAtMs: 6000, volume: 500),
        );

        expect(result.deltas['strength']!.delta, 100.0); // 500 - 400
        expect(result.deltas['strength']!.hasPrevious, true);
        expect(result.basis, isNotNull);
        expect(result.basis!.isRoutine, false);
        expect(result.basis!.label, 'Resistance / Lifting');
        expect(result.basis!.previousStartedAtMs, 1000);
      },
    );

    test('S-24606 a group the like session lacks gets no figure, '
        'a group it has gets the delta', () async {
      final repo = await _freshRepo();
      final service = SessionSummaryService(repo);

      // S1: same routine, cardio only (300000 ms), no strength.
      await _seed(
        repo,
        id: 's1',
        startedAtMs: 1000,
        endedAtMs: 2000,
        routineTemplateId: 't1',
        title: 'Push Day',
        cardioMs: 300000,
      );
      final current = await _seed(
        repo,
        id: 'current',
        startedAtMs: 5000,
        endedAtMs: 6000,
        routineTemplateId: 't1',
        title: 'Push Day',
        strengthReps: 8,
        strengthWeight: 50.0,
        cardioMs: 600000,
      );

      final result = await service.compareGroupsToPreviousSession(
        current,
        _summary(
          'current',
          startedAtMs: 5000,
          endedAtMs: 6000,
          volume: 500,
          cardioMs: 600000,
        ),
      );

      expect(result.deltas['cardio']!.hasPrevious, true);
      expect(result.deltas['cardio']!.delta, 300000.0); // 600000 - 300000
      expect(result.deltas['strength']!.hasPrevious, false);
      expect(result.deltas['strength']!.delta, isNull);
    });

    test(
      'S-24607 unfinished and started-after-current sessions are skipped',
      () async {
        final repo = await _freshRepo();
        final service = SessionSummaryService(repo);

        // S3: same routine but unfinished (endedAtMs null), volume 900 (18 × 50).
        await _seed(
          repo,
          id: 's3',
          startedAtMs: 3000,
          routineTemplateId: 't1',
          title: 'Push Day',
          strengthReps: 18,
          strengthWeight: 50.0,
        );
        // S2: same routine, finished, but started AFTER the current, volume 800.
        await _seed(
          repo,
          id: 's2',
          startedAtMs: 7000,
          endedAtMs: 8000,
          routineTemplateId: 't1',
          title: 'Push Day',
          strengthReps: 16,
          strengthWeight: 50.0,
        );
        // S1: same routine, finished, before the current, volume 400 (8 × 50).
        await _seed(
          repo,
          id: 's1',
          startedAtMs: 1000,
          endedAtMs: 2000,
          routineTemplateId: 't1',
          title: 'Push Day',
          strengthReps: 8,
          strengthWeight: 50.0,
        );
        final current = await _seed(
          repo,
          id: 'current',
          startedAtMs: 5000,
          endedAtMs: 6000,
          routineTemplateId: 't1',
          title: 'Push Day',
          strengthReps: 8,
          strengthWeight: 50.0,
        );

        final result = await service.compareGroupsToPreviousSession(
          current,
          _summary('current', startedAtMs: 5000, endedAtMs: 6000, volume: 500),
        );

        // Only S1 (400) qualifies: not 900 (unfinished) and not 800 (after).
        expect(result.deltas['strength']!.delta, 100.0); // 500 - 400
        expect(result.deltas['strength']!.hasPrevious, true);
        expect(result.basis!.previousStartedAtMs, 1000);
      },
    );

    test('S-24608 blank title falls back to this routine', () async {
      final repo = await _freshRepo();
      final service = SessionSummaryService(repo);

      await _seed(
        repo,
        id: 's1',
        startedAtMs: 1000,
        endedAtMs: 2000,
        routineTemplateId: 't1',
        title: 'Push Day',
        strengthReps: 8,
        strengthWeight: 50.0,
      );
      final current = await _seed(
        repo,
        id: 'current',
        startedAtMs: 5000,
        endedAtMs: 6000,
        routineTemplateId: 't1',
        title: '   ',
        strengthReps: 8,
        strengthWeight: 50.0,
      );

      final result = await service.compareGroupsToPreviousSession(
        current,
        _summary('current', startedAtMs: 5000, endedAtMs: 6000, volume: 500),
      );

      expect(result.basis, isNotNull);
      expect(result.basis!.isRoutine, true);
      expect(result.basis!.label, 'this routine');
    });

    test('S-24608 null title falls back to this routine', () async {
      final repo = await _freshRepo();
      final service = SessionSummaryService(repo);

      await _seed(
        repo,
        id: 's1',
        startedAtMs: 1000,
        endedAtMs: 2000,
        routineTemplateId: 't1',
        title: 'Push Day',
        strengthReps: 8,
        strengthWeight: 50.0,
      );
      final current = await _seed(
        repo,
        id: 'current',
        startedAtMs: 5000,
        endedAtMs: 6000,
        routineTemplateId: 't1',
        strengthReps: 8,
        strengthWeight: 50.0,
      );

      final result = await service.compareGroupsToPreviousSession(
        current,
        _summary('current', startedAtMs: 5000, endedAtMs: 6000, volume: 500),
      );

      expect(result.basis, isNotNull);
      expect(result.basis!.isRoutine, true);
      expect(result.basis!.label, 'this routine');
    });

    test('S-24609 an empty routine id counts as no routine', () async {
      final repo = await _freshRepo();
      final service = SessionSummaryService(repo);

      // S2: free (null routine id), volume 400 (8 × 50) — the like session.
      await _seed(
        repo,
        id: 's2',
        startedAtMs: 2000,
        endedAtMs: 3000,
        modality: 'resistance_lifting',
        strengthReps: 8,
        strengthWeight: 50.0,
      );
      // S1: empty routine id, volume 300 (6 × 50) — excluded.
      await _seed(
        repo,
        id: 's1',
        startedAtMs: 1000,
        endedAtMs: 1500,
        routineTemplateId: '',
        modality: 'resistance_lifting',
        strengthReps: 6,
        strengthWeight: 50.0,
      );
      final current = await _seed(
        repo,
        id: 'current',
        startedAtMs: 5000,
        endedAtMs: 6000,
        routineTemplateId: '',
        modality: 'resistance_lifting',
        strengthReps: 10,
        strengthWeight: 50.0,
      );

      final result = await service.compareGroupsToPreviousSession(
        current,
        _summary('current', startedAtMs: 5000, endedAtMs: 6000, volume: 500),
      );

      expect(result.deltas['strength']!.delta, 100.0); // 500 - 400
      expect(result.basis, isNotNull);
      expect(result.basis!.isRoutine, false);
      expect(result.basis!.label, 'Resistance / Lifting');
      expect(result.basis!.previousStartedAtMs, 2000);
    });
  });
}
