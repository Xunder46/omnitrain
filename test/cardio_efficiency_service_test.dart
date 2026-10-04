// Stats PR 9b Phase 2 — `StatsProgressService.cardioEfforts`, the eligible
// cardio efforts the Cardio Efficiency Drift rule reads.
//
// The service read is the rule's only history walker: one pass over the cached
// history snapshot, the shipped `DistancePairing.forEntries` pairing and the
// shipped `timed_instance` sensor summaries. An eligible effort is a finished
// timed instance of a `timed` effort in a completed session with a paired
// distance above zero whose source is not the watch's estimate, an
// instance-scope average heart rate above zero, and a duration above zero
// (D-1802). The method applies no window decision of its own beyond the span
// the caller asks for (D-1816).
//
// Plan: `docs/plans/2026-10-04-09b-stats-pr9b-cardio-efficiency-drift-plan/2026-10-04-09b-stats-pr9b-cardio-efficiency-drift-plan.md`
// (D-1802, D-1812, D-1816; S-2504, S-2505, S-2508, S-2512).

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/models/cardio_efficiency_drift.dart';
import 'package:omnitrain/core/services/stats_progress_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';

import 'helpers/repository_harness.dart';

// ─── The plan's clock ───────────────────────────────────────────────────────

/// The plan's `now`: a fixed anchor, so every fixture day is a calendar day
/// and nothing moves with the real clock.
final DateTime _now = DateTime(2026, 5, 13, 10);

/// Local midnight [daysAgo] days before `now`.
DateTime _day(int daysAgo) =>
    DateTime(_now.year, _now.month, _now.day - daysAgo);

/// The whole span the adapter asks for: `[day(42), now]`.
DateTime get _spanFrom => _day(42);

// ─── Fixtures ───────────────────────────────────────────────────────────────

/// One completed session holding one segment, starting at [start].
Future<void> _seedSession(
  WorkoutRepository repo, {
  required String id,
  required DateTime start,
  bool incomplete = false,
}) async {
  final startMs = start.millisecondsSinceEpoch;
  await repo.createSession(
    TrainingSession(
      id: id,
      ownerUserId: 'user-1',
      startedAtMs: startMs,
      endedAtMs: incomplete ? null : startMs + 3600000,
      createdAtMs: startMs,
      updatedAtMs: startMs,
    ),
  );
  await repo.createSegment(
    SessionSegment(
      id: 'seg-$id',
      sessionId: id,
      orderIndex: 0,
      segmentType: 'workout',
      name: 'Main Workout',
      createdAtMs: startMs,
      updatedAtMs: startMs,
    ),
  );
}

/// One `timed` effort on [segmentId] for [exerciseId].
Future<void> _seedTimedEffort(
  WorkoutRepository repo, {
  required String segmentId,
  required String effortId,
  required String exerciseId,
}) async {
  await repo.createEffort(
    SegmentEffort(
      id: effortId,
      segmentId: segmentId,
      orderIndex: 0,
      effortKind: 'timed',
      exerciseId: exerciseId,
      createdAtMs: fixtureStart,
      updatedAtMs: fixtureStart,
    ),
  );
}

/// One finished timed instance of [effortId] at [entryIndex], started at
/// [start], lasting [durationSecs].
Future<void> _seedInstance(
  WorkoutRepository repo, {
  required String effortId,
  required int entryIndex,
  required DateTime start,
  required int durationSecs,
  TimedState state = TimedState.finished,
}) async {
  await repo.createTimedInstance(
    timedInstance(
      effortId,
      entryIndex,
      durationSecs: durationSecs,
      entryIndex: entryIndex,
      state: state,
      startedAtMs: start.millisecondsSinceEpoch,
    ),
  );
}

/// One distance row for [effortId]'s entry [entryIndex], with [source].
Future<void> _seedDistance(
  WorkoutRepository repo, {
  required String effortId,
  required int entryIndex,
  required double metres,
  String? source,
}) async {
  await repo.createObservation(
    distanceRow(
      effortId,
      entryIndex,
      metres,
      atMs: fixtureRowAt(entryIndex),
      source: source,
    ),
  );
}

/// One instance-scope sensor summary carrying [avgHeartRateBpm] for
/// [instanceId] on [sessionId].
Future<void> _seedInstanceHeartRate(
  WorkoutRepository repo, {
  required String sessionId,
  required String instanceId,
  required double avgHeartRateBpm,
}) async {
  await seedSensorSummary(
    repo,
    sensorSummary(
      sessionId: sessionId,
      scope: SensorSummary.scopeTimedInstance,
      targetId: instanceId,
      windowStartMs: fixtureStart,
      windowEndMs: fixtureStart + 60000,
      avgHeartRateBpm: avgHeartRateBpm,
    ),
  );
}

/// The eligibility table's fixture: one completed session holding one `timed`
/// effort with a single finished 480 s instance, a [metres] distance stored
/// with [source] and — when [heartRateBpm] is not null — an instance-scope
/// summary carrying it.
Future<void> _seedOneEffort(
  WorkoutRepository repo, {
  required double metres,
  String? source,
  double? heartRateBpm,
}) async {
  await seedExercise(
    repo,
    id: 'ex-run',
    name: 'Treadmill Run',
    capabilities: ['time', 'distance'],
  );
  await _seedSession(repo, id: 's-one', start: _day(3));
  await _seedTimedEffort(
    repo,
    segmentId: 'seg-s-one',
    effortId: 'e-one',
    exerciseId: 'ex-run',
  );
  await _seedInstance(
    repo,
    effortId: 'e-one',
    entryIndex: 0,
    start: _day(3),
    durationSecs: 480,
  );
  await _seedDistance(
    repo,
    effortId: 'e-one',
    entryIndex: 0,
    metres: metres,
    source: source,
  );
  if (heartRateBpm != null) {
    await _seedInstanceHeartRate(
      repo,
      sessionId: 's-one',
      instanceId: 'ti-e-one-0',
      avgHeartRateBpm: heartRateBpm,
    );
  }
}

/// S-2501's fixture: one exercise (`Treadmill Run`) with four recent efforts at
/// 480 s and 2790 m and four reference efforts at 480 s and 3000 m, each with
/// an average heart rate of 150. The recent efforts start 3, 6, 9 and 12 days
/// ago; the reference efforts 30, 33, 36 and 39 days ago.
///
/// [recentMetres] is the recent distance each effort carries, so a variant can
/// move the drift; [recentSource] is the source the **first** recent effort's
/// row is stored with, so a variant can make one an estimate while the other
/// three stay measured.
Future<void> _seedS2501(
  WorkoutRepository repo, {
  double recentMetres = 2790.0,
  String? recentSource,
  int recentCount = 4,
  int referenceCount = 4,
}) async {
  await seedExercise(
    repo,
    id: 'ex-run',
    name: 'Treadmill Run',
    capabilities: ['time', 'distance'],
  );

  const recentDays = [3, 6, 9, 12];
  const referenceDays = [30, 33, 36, 39];

  for (var i = 0; i < recentCount; i++) {
    final sessionId = 's-recent-$i';
    final effortId = 'e-recent-$i';
    await _seedSession(repo, id: sessionId, start: _day(recentDays[i]));
    await _seedTimedEffort(
      repo,
      segmentId: 'seg-$sessionId',
      effortId: effortId,
      exerciseId: 'ex-run',
    );
    await _seedInstance(
      repo,
      effortId: effortId,
      entryIndex: 0,
      start: _day(recentDays[i]),
      durationSecs: 480,
    );
    await _seedDistance(
      repo,
      effortId: effortId,
      entryIndex: 0,
      metres: recentMetres,
      source: i == 0 ? recentSource : null,
    );
    await _seedInstanceHeartRate(
      repo,
      sessionId: sessionId,
      instanceId: 'ti-$effortId-0',
      avgHeartRateBpm: 150,
    );
  }

  for (var i = 0; i < referenceCount; i++) {
    final sessionId = 's-ref-$i';
    final effortId = 'e-ref-$i';
    await _seedSession(repo, id: sessionId, start: _day(referenceDays[i]));
    await _seedTimedEffort(
      repo,
      segmentId: 'seg-$sessionId',
      effortId: effortId,
      exerciseId: 'ex-run',
    );
    await _seedInstance(
      repo,
      effortId: effortId,
      entryIndex: 0,
      start: _day(referenceDays[i]),
      durationSecs: 480,
    );
    await _seedDistance(
      repo,
      effortId: effortId,
      entryIndex: 0,
      metres: 3000.0,
    );
    await _seedInstanceHeartRate(
      repo,
      sessionId: sessionId,
      instanceId: 'ti-$effortId-0',
      avgHeartRateBpm: 150,
    );
  }
}

/// The eligible efforts as `exerciseId|start|duration|distance|heartRate` rows,
/// so two stores' lists compare whole.
List<String> _describe(List<CardioEffort> efforts) => [
  for (final effort in efforts)
    '${effort.exerciseId}|${effort.exerciseName}|'
        '${effort.start.millisecondsSinceEpoch}|${effort.durationSecs}|'
        '${effort.distanceMetres}|${effort.avgHeartRateBpm}',
];

Future<List<CardioEffort>> _read(WorkoutRepository repo) =>
    StatsProgressService(repo).cardioEfforts(fromMs: _spanFrom, toMs: _now);

void main() {
  for (final factory in harnessFactories) {
    final harness = factory();

    group('${harness.name} — cardioEfforts', () {
      late WorkoutRepository repo;

      setUp(() async => repo = await harness.open());
      tearDown(() async => await harness.close());

      group('the eligibility table', () {
        // D-1802: only the watch's own estimate is excluded. Every other
        // stored source — `'gps'`, `'entered'`, and a row stored with no
        // source at all — is eligible, and any of them stops being eligible
        // the moment the instance carries no average heart rate.
        const rows = <({String label, String? source, bool eligible})>[
          (label: 'gps', source: EffortObservation.sourceGps, eligible: true),
          (
            label: 'entered',
            source: EffortObservation.sourceEntered,
            eligible: true,
          ),
          (
            label: 'estimated',
            source: EffortObservation.sourceEstimated,
            eligible: false,
          ),
          (label: 'no source', source: null, eligible: true),
        ];

        for (final row in rows) {
          test('a ${row.label} distance with a heart rate', () async {
            await _seedOneEffort(
              repo,
              metres: 3000,
              source: row.source,
              heartRateBpm: 150,
            );

            final efforts = await _read(repo);

            expect(efforts, hasLength(row.eligible ? 1 : 0));
          });

          test('a ${row.label} distance with no heart rate', () async {
            await _seedOneEffort(repo, metres: 3000, source: row.source);

            final efforts = await _read(repo);

            expect(efforts, isEmpty);
          });
        }
      });

      test('S-2504 an estimated indoor distance is never eligible', () async {
        await _seedS2501(repo, recentSource: EffortObservation.sourceEstimated);

        final efforts = await _read(repo);

        // Four reference efforts plus the three recent ones that are not
        // estimates; the estimated one is absent.
        expect(efforts, hasLength(7));
        expect(efforts.where((e) => e.start.isAfter(_day(14))), hasLength(3));
      });

      test(
        'S-2504 an outdoor fallback to the estimate is the same stored source',
        () async {
          // The watch wrote the same `'estimated'` source when an outdoor run
          // had no GPS fix, so the effort is excluded exactly as the indoor
          // one is.
          await _seedS2501(
            repo,
            recentSource: EffortObservation.sourceEstimated,
          );

          final efforts = await _read(repo);

          expect(efforts, hasLength(7));
          expect(efforts.where((e) => e.start.isAfter(_day(14))), hasLength(3));
        },
      );

      test(
        'S-2504 a correction to entered makes the effort eligible',
        () async {
          await _seedS2501(
            repo,
            recentSource: EffortObservation.sourceEstimated,
          );
          expect(await _read(repo), hasLength(7));

          // The user corrects the distance: the row is re-stored through the
          // repository's observation write path with `'entered'`.
          final row = (await repo.getEffortObservations('e-recent-0')).single;
          await repo.updateObservation(
            EffortObservation(
              id: row.id,
              effortId: row.effortId,
              metricId: row.metricId,
              unitId: row.unitId,
              valueReal: row.valueReal,
              valueSource: EffortObservation.sourceEntered,
              createdAtMs: row.createdAtMs,
              updatedAtMs: row.updatedAtMs,
            ),
          );

          final efforts = await _read(repo);

          expect(efforts, hasLength(8));
          expect(efforts.where((e) => e.start.isAfter(_day(14))), hasLength(4));
        },
      );

      test('S-2504 a gps row and a row with no source stay eligible', () async {
        await _seedS2501(repo, recentSource: EffortObservation.sourceGps);
        expect(await _read(repo), hasLength(8));

        await _seedS2501(repo, recentSource: null);
        expect(await _read(repo), hasLength(8));
      });

      test('S-2505 no instance summary is never eligible', () async {
        await _seedS2501(repo);
        // Drop the first recent effort's summary by deleting its instance,
        // which deletes the summary with it (D-131), then re-seeding the
        // instance without a summary.
        await repo.deleteTimedInstance('ti-e-recent-0-0');
        await _seedInstance(
          repo,
          effortId: 'e-recent-0',
          entryIndex: 0,
          start: _day(3),
          durationSecs: 480,
        );

        final efforts = await _read(repo);

        expect(efforts, hasLength(7));
        expect(efforts.where((e) => e.start.isAfter(_day(14))), hasLength(3));
      });

      test(
        'S-2505 a summary with a null heart rate is never eligible',
        () async {
          await _seedS2501(repo);
          await repo.deleteTimedInstance('ti-e-recent-0-0');
          await _seedInstance(
            repo,
            effortId: 'e-recent-0',
            entryIndex: 0,
            start: _day(3),
            durationSecs: 480,
          );
          await seedSensorSummary(
            repo,
            sensorSummary(
              sessionId: 's-recent-0',
              scope: SensorSummary.scopeTimedInstance,
              targetId: 'ti-e-recent-0-0',
              windowStartMs: fixtureStart,
              windowEndMs: fixtureStart + 60000,
              steps: 100,
            ),
          );

          final efforts = await _read(repo);

          expect(efforts, hasLength(7));
        },
      );

      test(
        'S-2505 a session-scope summary does not qualify the effort',
        () async {
          await _seedS2501(repo);
          await repo.deleteTimedInstance('ti-e-recent-0-0');
          await _seedInstance(
            repo,
            effortId: 'e-recent-0',
            entryIndex: 0,
            start: _day(3),
            durationSecs: 480,
          );
          await seedSensorSummary(
            repo,
            sensorSummary(
              sessionId: 's-recent-0',
              scope: SensorSummary.scopeSession,
              targetId: 's-recent-0',
              windowStartMs: fixtureStart,
              windowEndMs: fixtureStart + 60000,
              avgHeartRateBpm: 150,
            ),
          );

          final efforts = await _read(repo);

          expect(efforts, hasLength(7));
        },
      );

      test('S-2505 seeding the instance summary restores the effort', () async {
        await _seedS2501(repo);
        await repo.deleteTimedInstance('ti-e-recent-0-0');
        await _seedInstance(
          repo,
          effortId: 'e-recent-0',
          entryIndex: 0,
          start: _day(3),
          durationSecs: 480,
        );
        expect(await _read(repo), hasLength(7));

        await _seedInstanceHeartRate(
          repo,
          sessionId: 's-recent-0',
          instanceId: 'ti-e-recent-0-0',
          avgHeartRateBpm: 150,
        );

        expect(await _read(repo), hasLength(8));
      });

      test('S-2504 an unfinished instance is never eligible', () async {
        await _seedS2501(repo);
        await repo.deleteTimedInstance('ti-e-recent-0-0');
        await _seedInstance(
          repo,
          effortId: 'e-recent-0',
          entryIndex: 0,
          start: _day(3),
          durationSecs: 480,
          state: TimedState.active,
        );

        final efforts = await _read(repo);

        expect(efforts, hasLength(7));
      });

      test('S-2504 a zero distance is never eligible', () async {
        await _seedS2501(repo);
        final row = (await repo.getEffortObservations('e-recent-0')).single;
        await repo.updateObservation(
          EffortObservation(
            id: row.id,
            effortId: row.effortId,
            metricId: row.metricId,
            unitId: row.unitId,
            valueReal: 0.0,
            valueSource: row.valueSource,
            createdAtMs: row.createdAtMs,
            updatedAtMs: row.updatedAtMs,
          ),
        );

        final efforts = await _read(repo);

        expect(efforts, hasLength(7));
      });

      test('S-2504 a session in progress is never eligible', () async {
        await _seedS2501(repo);
        // Re-seed the first recent session as still in progress: the effort
        // and its distance and heart rate stay, only the session's end goes.
        final session = (await repo.getSession('s-recent-0'))!;
        await repo.updateSession(
          TrainingSession(
            id: session.id,
            ownerUserId: session.ownerUserId,
            startedAtMs: session.startedAtMs,
            endedAtMs: null,
            createdAtMs: session.createdAtMs,
            updatedAtMs: session.updatedAtMs,
          ),
        );

        final efforts = await _read(repo);

        expect(efforts, hasLength(7));
      });

      test('S-2508 the span is the caller\'s, ordered by start', () async {
        await _seedS2501(repo);

        final efforts = await _read(repo);

        expect(efforts, hasLength(8));
        for (var i = 1; i < efforts.length; i++) {
          expect(
            efforts[i].start.isBefore(efforts[i - 1].start),
            isFalse,
            reason: 'efforts are ordered by start',
          );
        }
        expect(efforts.first.start, _day(39));
        expect(efforts.last.start, _day(3));
      });

      test('S-2508 the span excludes efforts outside it', () async {
        await _seedS2501(repo);

        final efforts = await StatsProgressService(
          repo,
        ).cardioEfforts(fromMs: _day(14), toMs: _now);

        expect(efforts, hasLength(4));
        expect(efforts.every((e) => !e.start.isBefore(_day(14))), isTrue);
      });
    });
  }

  test('S-2512 Hive and Mock return identical eligible efforts', () async {
    Future<List<String>> read(RepositoryHarness harness) async {
      final repo = await harness.open();
      await _seedS2501(repo);
      final efforts = await _read(repo);
      await harness.close();
      return _describe(efforts);
    }

    final mock = await read(MockRepositoryHarness());
    final hive = await read(HiveRepositoryHarness());

    expect(mock, hive);
    expect(mock, hasLength(8));
  });
}
