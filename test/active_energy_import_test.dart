// The watch-import settle (plan 134a, fix round 1, D-13420).
//
// The inbox's `onSessionHistoryChanged` callback is the difference between a
// wrist-created session that carries an energy estimate and one that does not:
// the callback is the app's `ActiveEnergyService.settle`. Scenarios:
//
//   S-13418 a session the phone does not hold: the wrist's end prices it
//   S-13419 a Free Training session the wrist ran: timed entries split the price
//   S-13420 a pass that changes nothing does not call the callback
//   S-13421 a throwing callback never fails the pass
//
// Both repositories run each scenario (the parity invariant). Plain `test()`:
// no widget is involved, and a Hive write inside a widget test's fake-async
// zone never drains.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/active_energy_service.dart';
import 'package:omnitrain/core/services/stats_progress_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/state/watch/watch_session_inbox.dart';

import 'helpers/repository_harness.dart';

String _iso(int ms) =>
    DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toIso8601String();

/// `fixtureStart` pinned once per test: the getter re-reads the real clock, so
/// the moments the wrist staged must not drift against the ones asserted.
late int _start;

/// A wrist `session_end` in the protocol's shape. [modality] absent means Free
/// Training: the session's own modality stays null and the estimate reads the
/// measured split.
Map<String, Object?> _wristEnd(String sessionId, {String? modality}) => {
  'entryId': 'end-$sessionId',
  'eventId': 'end-$sessionId',
  'kind': 'session_end',
  'loggedAt': _iso(_start + 3600000),
  'startedAt': _iso(_start),
  'endedAt': _iso(_start + 3600000),
  'status': 'completed',
  'modality': ?modality,
};

/// A wrist set (the S-10106 regression arm): without an effort row behind it a
/// completed end is consumed as an empty session, not imported (D-133).
Map<String, Object?> _wristSet(String entryId, String sessionExerciseId) => {
  'entryId': entryId,
  'eventId': entryId,
  'kind': 'set',
  'loggedAt': _iso(_start + 60000),
  'sessionExerciseId': sessionExerciseId,
  'exerciseId': 'ex-bench',
  'reps': 9,
};

/// One wrist timed entry of 1200 s.
Map<String, Object?> _wristTimed(String entryId, String sessionExerciseId) => {
  'entryId': entryId,
  'eventId': entryId,
  'kind': 'timed',
  'loggedAt': _iso(_start + 1200000),
  'sessionExerciseId': sessionExerciseId,
  'exerciseId': 'ex-run',
  'startedAt': _iso(_start),
  'endedAt': _iso(_start + 1200000),
};

/// One `observations_up` envelope carrying [events], as a wrist sends it.
Map<String, Object?> _observationsUp(
  String sessionId,
  List<Map<String, Object?>> events, {
  required String messageId,
}) => {
  'messageId': messageId,
  'sessionId': sessionId,
  'type': 'observations_up',
  'origin': 'watch',
  'sentAt': _iso(_start + 7200000),
  'payload': {'events': events},
};

/// One call to the settle the app wires in.
ActiveEnergyService _service(WorkoutRepository repo) =>
    ActiveEnergyService(repo, () => StatsProgressService(repo));

void main() {
  for (final harnessFactory in harnessFactories) {
    final harness = harnessFactory();
    group('active energy through the watch inbox (${harness.name})', () {
      late WorkoutRepository repo;

      setUp(() async {
        _start = fixtureStart;
        repo = await harness.open();
        await repo.saveMeasurementEntry(
          BodyMeasurementEntry(
            id: 'bm-1',
            measurementType: 'bodyweight',
            value: 80.0,
            unitId: 'unit-kg',
            recordedAtMs: _start,
          ),
        );
      });

      tearDown(harness.close);

      test('S-13418 a session the phone does not hold: the wrist end prices '
          'it through the settle callback', () async {
        await seedExercise(repo, id: 'ex-bench', name: 'Bench', capabilities: [
          'load',
        ]);
        final inbox = WatchSessionInbox(
          repository: repo,
          onSessionHistoryChanged: _service(repo).settle,
        );

        await inbox.receive(
          _observationsUp('w-energy-1', [
            _wristSet('t-set-1', 'sx-bench'),
            _wristEnd('w-energy-1', modality: 'resistance_lifting'),
          ], messageId: 'm-1'),
        );

        final session = await repo.getSession('w-energy-1');
        expect(session, isNotNull, reason: 'S-13418 the session is imported');
        expect(session!.endedAtMs, _start + 3600000);
        final row = await repo.getSessionEnergy('w-energy-1');
        expect(row, isNotNull, reason: 'S-13418 the estimate is stored');
        expect(row!.source, SessionEnergy.sourceEstimated);
        // (3.5 - 1) x 80 kg x 1 h = 200.0.
        expect(row.activeKcal, closeTo(200.0, 1e-6));
        expect(row.bodyWeightKg, closeTo(80.0, 1e-6));
      });

      test('S-13418 control — the same fixture without the callback stores no '
          'row', () async {
        await seedExercise(repo, id: 'ex-bench', name: 'Bench', capabilities: [
          'load',
        ]);
        final inbox = WatchSessionInbox(repository: repo);

        await inbox.receive(
          _observationsUp('w-energy-1', [
            _wristSet('t-set-1', 'sx-bench'),
            _wristEnd('w-energy-1', modality: 'resistance_lifting'),
          ], messageId: 'm-1'),
        );

        expect(
          await repo.getSession('w-energy-1'),
          isNotNull,
          reason: 'S-13418 control the session is still imported',
        );
        expect(
          await repo.getSessionEnergy('w-energy-1'),
          isNull,
          reason: 'S-13418 control no callback, no estimate',
        );
      });

      test('S-13419 a Free Training session the wrist ran: the timed entry '
          'and the remainder are priced separately', () async {
        await seedExercise(repo, id: 'ex-run', name: 'Easy Run', capabilities: [
          'time',
        ]);
        final inbox = WatchSessionInbox(
          repository: repo,
          onSessionHistoryChanged: _service(repo).settle,
        );

        await inbox.receive(
          _observationsUp('w-energy-2', [
            _wristTimed('t-run-1', 'sx-run'),
            _wristEnd('w-energy-2', modality: null),
          ], messageId: 'm-1'),
        );

        final row = await repo.getSessionEnergy('w-energy-2');
        expect(row, isNotNull, reason: 'S-13419 the estimate is stored');
        expect(row!.source, SessionEnergy.sourceEstimated);
        // Cardio 1200 s: (6 - 1) x 80 x 1200/3600 = 133.333...; the rest of the hour
        // at resistance: (3.5 - 1) x 80 x 2400/3600 = 133.333...; together
        // 266.6666666666667.
        expect(row.activeKcal, closeTo(266.6666666666667, 1e-6));
      });

      test('S-13420 a pass that changes nothing does not call the callback',
          () async {
        await seedExercise(repo, id: 'ex-bench', name: 'Bench', capabilities: [
          'load',
        ]);
        final service = _service(repo);
        var calls = 0;
        final inbox = WatchSessionInbox(
          repository: repo,
          onSessionHistoryChanged: (sessionId) async {
            calls++;
            await service.settle(sessionId);
          },
        );
        await inbox.receive(
          _observationsUp('w-energy-1', [
            _wristSet('t-set-1', 'sx-bench'),
            _wristEnd('w-energy-1', modality: 'resistance_lifting'),
          ], messageId: 'm-1'),
        );
        final rowBefore = (await repo.getSessionEnergy('w-energy-1'))!;
        expect(calls, 1, reason: 'S-13420 the first pass called the callback');

        await inbox.receive(
          _observationsUp('w-energy-1', [
            _wristSet('t-set-1', 'sx-bench'),
            _wristEnd('w-energy-1', modality: 'resistance_lifting'),
          ], messageId: 'm-2'),
        );

        expect(
          calls,
          1,
          reason: 'S-13420 the second pass wrote nothing, so no callback',
        );
        final rowAfter = await repo.getSessionEnergy('w-energy-1');
        expect(rowAfter!.updatedAtMs, rowBefore.updatedAtMs);
        expect(rowAfter.activeKcal, rowBefore.activeKcal);
      });

      test('S-13421 a throwing callback never fails the pass', () async {
        await seedExercise(repo, id: 'ex-bench', name: 'Bench', capabilities: [
          'load',
        ]);
        final inbox = WatchSessionInbox(
          repository: repo,
          onSessionHistoryChanged: (_) async => throw StateError('boom'),
        );

        final result = await inbox.receive(
          _observationsUp('w-energy-3', [
            _wristSet('t-set-1', 'sx-bench'),
            _wristEnd('w-energy-3', modality: 'resistance_lifting'),
          ], messageId: 'm-1'),
        );

        // An unshielded throw reaches `receive`'s catch: the result is
        // `failed` and nothing is receipted, so the wrist would re-send.
        expect(
          result.outcome,
          isNot(WatchInboxOutcome.failed),
          reason: 'S-13421 the callback failure never fails the pass',
        );
        expect(
          result.receiptedEntryIds,
          contains('end-w-energy-3'),
          reason: 'S-13421 the end is still receipted to the wrist',
        );
        expect(
          await repo.getSession('w-energy-3'),
          isNotNull,
          reason: 'S-13421 the pass still imports the session',
        );
        expect(
          (await repo.getWatchInboxEntry('end-w-energy-3'))!.appliedAtMs,
          isNotNull,
          reason: 'S-13421 the end row is applied',
        );
      });
    });
  }
}
