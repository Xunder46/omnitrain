// The wrist's measured active energy through the watch importer (plan 134c,
// D-13463). The `session_end` may carry `activeEnergyKcal`: a `completed` end
// with a positive finite figure stores it as a `measured` `SessionEnergy` row,
// replacing and never being replaced by an estimate. Scenarios:
//
//   S-13460 a wrist-created session whose end carries measured energy
//   S-13461 a phone-held session with an estimate: the wrist's energy replaces it
//   S-13462 bad values (absent, 0, -5, '412', NaN) store nothing
//   S-13463 a followed end: completed stores, abandoned does not
//   S-13464 the same end delivered twice stores once
//   S-13465 through the inbox with the settle callback: measured not overwritten
//
// Both repositories run each scenario (the parity invariant). Plain `test()`:
// no widget is involved, and a Hive write inside a widget test's fake-async
// zone never drains.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/active_energy_service.dart';
import 'package:omnitrain/core/services/stats_progress_service.dart';
import 'package:omnitrain/core/services/watch_session_importer.dart';
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
/// Training; [energy] absent means the wrist measured nothing; [heartRate]
/// absent means the end carries no heart rate (both keys travel together).
Map<String, Object?> _wristEnd(
  String sessionId, {
  String? modality,
  double? energy,
  String status = 'completed',
  bool followed = false,
  int? heartRate,
}) => {
  'entryId': 'end-$sessionId',
  'eventId': 'end-$sessionId',
  'kind': 'session_end',
  'loggedAt': _iso(_start + 3600000),
  'startedAt': _iso(_start),
  'endedAt': _iso(_start + 3600000),
  'status': status,
  'modality': ?modality,
  'avgHeartRateBpm': ?heartRate,
  'maxHeartRateBpm': ?heartRate,
  'activeEnergyKcal': ?energy,
  if (followed) 'followed': true,
};

/// A wrist set (the D-133 regression arm): without an effort row behind it a
/// completed end is consumed as an empty session, not imported.
Map<String, Object?> _wristSet(String entryId, String sessionExerciseId) => {
  'entryId': entryId,
  'eventId': entryId,
  'kind': 'set',
  'loggedAt': _iso(_start + 60000),
  'sessionExerciseId': sessionExerciseId,
  'exerciseId': 'ex-bench',
  'reps': 9,
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

/// A staged wrist row from a payload map, the way the inbox stages one.
WatchInboxEntry _wristRow(
  String entryId,
  String kind,
  String session,
  Map<String, Object?> payload,
) => WatchInboxEntry(
  entryId: entryId,
  watchSessionId: session,
  kind: kind,
  origin: WatchInboxEntry.originWatch,
  payload: {'eventId': entryId, 'entryId': entryId, 'kind': kind, ...payload},
  receivedAtMs: _start + 7200000,
);

/// One call to the settle the app wires in (plan 134a, D-13420).
ActiveEnergyService _service(WorkoutRepository repo) =>
    ActiveEnergyService(repo, () => StatsProgressService(repo));

/// The phone's own ended session: 80 kg logged. [priced] false leaves the
/// session with no energy row.
Future<void> _seedPhoneHeld(
  WorkoutRepository repo,
  String sessionId, {
  bool priced = true,
}) async {
  await seedSession(repo, sessionId: sessionId);
  await seedExercise(
    repo,
    id: 'ex-bench',
    name: 'Bench',
    capabilities: ['load'],
  );
  if (priced) {
    await repo.putSessionEnergy(
      SessionEnergy(
        sessionId: sessionId,
        activeKcal: 200.0,
        source: SessionEnergy.sourceEstimated,
        bodyWeightKg: 80.0,
        updatedAtMs: _start - 1000,
      ),
    );
  }
}

void main() {
  for (final harnessFactory in harnessFactories) {
    final harness = harnessFactory();
    group('measured energy through the watch importer (${harness.name})', () {
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

      test('S-13460 a wrist-created session whose end carries the measured '
          'energy stores it and reports the summary attached', () async {
        await seedExercise(
          repo,
          id: 'ex-bench',
          name: 'Bench',
          capabilities: ['load'],
        );
        await repo.stageWatchInboxEntry(
          _wristRow('t-set-1', WatchInboxEntry.kindSet, 'w-energy-1', {
            ..._wristSet('t-set-1', 'sx-bench'),
          }),
        );
        await repo.stageWatchInboxEntry(
          _wristRow(
            'end-w-energy-1',
            WatchInboxEntry.kindSessionEnd,
            'w-energy-1',
            _wristEnd(
              'w-energy-1',
              modality: 'resistance_lifting',
              energy: 412.6,
            ),
          ),
        );

        final result = await WatchSessionImporter(
          repository: repo,
        ).apply('w-energy-1');

        final session = await repo.getSession('w-energy-1');
        expect(session, isNotNull, reason: 'S-13460 the session is imported');
        expect(session!.endedAtMs, _start + 3600000);
        final row = await repo.getSessionEnergy('w-energy-1');
        expect(row, isNotNull, reason: 'S-13460 the measured row is stored');
        expect(row!.source, SessionEnergy.sourceMeasured);
        expect(row.activeKcal, closeTo(412.6, 1e-9));
        expect(row.bodyWeightKg, isNull);
        expect(row.updatedAtMs, _start + 3600000);
        expect(
          result.sensorSummaryAttached,
          isTrue,
          reason:
              'S-13460 an end with no heart rate still says the summary '
              'is attached',
        );
        expect(result.historyChanged, isTrue);
      });

      test('S-13461 a held session with an estimate: the wrist end replaces '
          'it with the measured row', () async {
        await _seedPhoneHeld(repo, 'phone-s1');
        await repo.stageWatchInboxEntry(
          _wristRow(
            'end-phone-s1',
            WatchInboxEntry.kindSessionEnd,
            'phone-s1',
            _wristEnd('phone-s1', energy: 150.0),
          ),
        );

        final result = await WatchSessionImporter(
          repository: repo,
        ).apply('phone-s1', phoneOwnsSession: true);

        final row = await repo.getSessionEnergy('phone-s1');
        expect(row, isNotNull, reason: 'S-13461 the measured row is stored');
        expect(row!.source, SessionEnergy.sourceMeasured);
        expect(row.activeKcal, closeTo(150.0, 1e-9));
        expect(row.bodyWeightKg, isNull, reason: 'S-13461 no estimate weight');
        expect(
          row.updatedAtMs,
          _start + 3600000,
          reason: 'S-13461 the end\'s loggedAt, not the phone clock',
        );
        expect(result.sensorSummaryAttached, isTrue);
        expect(result.historyChanged, isTrue);
      });

      test('S-13463b an abandoned end on a phone-held session stores no '
          'measured energy and keeps the estimate', () async {
        await _seedPhoneHeld(repo, 'phone-s1');
        await repo.stageWatchInboxEntry(
          _wristRow(
            'end-phone-s1',
            WatchInboxEntry.kindSessionEnd,
            'phone-s1',
            _wristEnd('phone-s1', energy: 150.0, status: 'abandoned'),
          ),
        );

        final result = await WatchSessionImporter(
          repository: repo,
        ).apply('phone-s1', phoneOwnsSession: true);

        final row = (await repo.getSessionEnergy('phone-s1'))!;
        expect(row.source, SessionEnergy.sourceEstimated);
        expect(row.activeKcal, closeTo(200.0, 1e-9));
        expect(row.bodyWeightKg, closeTo(80.0, 1e-9));
        expect(
          row.updatedAtMs,
          _start - 1000,
          reason: 'S-13463b the seeded estimate stands untouched',
        );
        expect(result.sensorSummaryAttached, isFalse);
      });

      // S-13462: one case per bad value, on a session priced with the 200 kcal
      // estimate and once on a session with no energy row. A loop generating
      // the separate test bodies is fine.
      const badValues = <(String, Object?)>[
        ('absent (no key)', null),
        ('zero (0)', 0),
        ('negative (-5)', -5),
        ('a string ("412")', '412'),
      ];
      for (final (label, value) in badValues) {
        // The payload is built in memory: an energy the schema would refuse
        // (a string, a NaN) must still reach the importer for this scenario.
        Map<String, Object?> badEnd(String session) {
          final payload = _wristEnd(
            session,
            energy: value is double ? value : null,
          );
          if (value is int || value is String) {
            payload['activeEnergyKcal'] = value;
          }
          return payload;
        }

        test(
          'S-13462 $label on a session with an estimate keeps the estimate',
          () async {
            await _seedPhoneHeld(repo, 'phone-s1');
            final before = (await repo.getSessionEnergy('phone-s1'))!;
            await repo.stageWatchInboxEntry(
              _wristRow(
                'end-phone-s1',
                WatchInboxEntry.kindSessionEnd,
                'phone-s1',
                badEnd('phone-s1'),
              ),
            );

            await WatchSessionImporter(
              repository: repo,
            ).apply('phone-s1', phoneOwnsSession: true);

            final after = (await repo.getSessionEnergy('phone-s1'))!;
            expect(after.source, SessionEnergy.sourceEstimated);
            expect(after.activeKcal, before.activeKcal);
            expect(after.updatedAtMs, before.updatedAtMs);
            expect(after.bodyWeightKg, before.bodyWeightKg);
          },
        );
        test('S-13462 $label on a session with no row stores no row', () async {
          await _seedPhoneHeld(repo, 'phone-s1', priced: false);
          await repo.stageWatchInboxEntry(
            _wristRow(
              'end-phone-s1',
              WatchInboxEntry.kindSessionEnd,
              'phone-s1',
              badEnd('phone-s1'),
            ),
          );

          await WatchSessionImporter(
            repository: repo,
          ).apply('phone-s1', phoneOwnsSession: true);

          expect(
            await repo.getSessionEnergy('phone-s1'),
            isNull,
            reason: 'S-13462 a bad value stores nothing',
          );
        });
      }

      // A non-finite figure cannot reach the importer through the inbox: a
      // staged payload must be JSON (D-132), so the protocol can never carry
      // one. S-13462 asserts that refusal end to end, once per fixture.
      test('S-13462 not-a-number (NaN) is refused at staging, the estimate '
          'stands', () async {
        await _seedPhoneHeld(repo, 'phone-s1');
        final before = (await repo.getSessionEnergy('phone-s1'))!;
        expect(
          () => _wristRow(
            'end-phone-s1',
            WatchInboxEntry.kindSessionEnd,
            'phone-s1',
            _wristEnd('phone-s1', energy: double.nan),
          ),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              contains('staged payload must be JSON'),
            ),
          ),
          reason: 'S-13462 a non-finite energy is not a staged payload (D-132)',
        );
        final after = (await repo.getSessionEnergy('phone-s1'))!;
        expect(after.source, before.source);
        expect(after.activeKcal, before.activeKcal);
        expect(after.updatedAtMs, before.updatedAtMs);
      });

      test(
        'S-13462 not-a-number (NaN) is refused at staging, no row appears',
        () async {
          await _seedPhoneHeld(repo, 'phone-s1', priced: false);
          expect(
            () => _wristRow(
              'end-phone-s1',
              WatchInboxEntry.kindSessionEnd,
              'phone-s1',
              _wristEnd('phone-s1', energy: double.nan),
            ),
            throwsArgumentError,
          );
          expect(
            await repo.getSessionEnergy('phone-s1'),
            isNull,
            reason: 'S-13462 no row appears where there was none',
          );
        },
      );

      test('S-13463 a followed completed end replaces the estimate with the '
          'measured row', () async {
        await _seedPhoneHeld(repo, 'phone-s1');
        await repo.stageWatchInboxEntry(
          _wristRow(
            'end-phone-s1',
            WatchInboxEntry.kindSessionEnd,
            'phone-s1',
            _wristEnd(
              'phone-s1',
              energy: 300.0,
              followed: true,
              heartRate: 140,
            ),
          ),
        );

        final result = await WatchSessionImporter(
          repository: repo,
        ).apply('phone-s1');

        final row = await repo.getSessionEnergy('phone-s1');
        expect(row, isNotNull, reason: 'S-13463 the measured row is stored');
        expect(row!.source, SessionEnergy.sourceMeasured);
        expect(row.activeKcal, closeTo(300.0, 1e-9));
        expect(row.bodyWeightKg, isNull);
        expect(result.sensorSummaryAttached, isTrue);
      });

      test('S-13463 a followed abandoned end stores nothing and keeps the '
          'estimate', () async {
        await _seedPhoneHeld(repo, 'phone-s1');
        await repo.stageWatchInboxEntry(
          _wristRow(
            'end-phone-s1',
            WatchInboxEntry.kindSessionEnd,
            'phone-s1',
            _wristEnd(
              'phone-s1',
              energy: 300.0,
              status: 'abandoned',
              followed: true,
            ),
          ),
        );

        final result = await WatchSessionImporter(
          repository: repo,
        ).apply('phone-s1');

        final row = (await repo.getSessionEnergy('phone-s1'))!;
        expect(row.source, SessionEnergy.sourceEstimated);
        expect(row.activeKcal, closeTo(200.0, 1e-9));
        expect(row.bodyWeightKg, closeTo(80.0, 1e-9));
        expect(result.sensorSummaryAttached, isFalse);
      });

      test('S-13464 the same end delivered twice stores one row and the '
          'second pass reports no summary', () async {
        await seedExercise(
          repo,
          id: 'ex-bench',
          name: 'Bench',
          capabilities: ['load'],
        );
        await repo.stageWatchInboxEntry(
          _wristRow('t-set-1', WatchInboxEntry.kindSet, 'w-energy-1', {
            ..._wristSet('t-set-1', 'sx-bench'),
          }),
        );
        await repo.stageWatchInboxEntry(
          _wristRow(
            'end-w-energy-1',
            WatchInboxEntry.kindSessionEnd,
            'w-energy-1',
            _wristEnd(
              'w-energy-1',
              modality: 'resistance_lifting',
              energy: 412.6,
            ),
          ),
        );
        final importer = WatchSessionImporter(repository: repo);
        await importer.apply('w-energy-1');
        final before = (await repo.getSessionEnergy('w-energy-1'))!;

        final second = await importer.apply('w-energy-1');

        final after = (await repo.getSessionEnergy('w-energy-1'))!;
        expect(
          after.activeKcal,
          before.activeKcal,
          reason: 'S-13464 the figure is unchanged',
        );
        expect(
          after.updatedAtMs,
          before.updatedAtMs,
          reason: 'S-13464 the stamp replay is byte-identical',
        );
        expect(after.source, SessionEnergy.sourceMeasured);
        expect(
          second.sensorSummaryAttached,
          isFalse,
          reason: 'S-13464 the second pass wrote nothing',
        );
      });

      test('S-13465 through the inbox with the settle callback, the measured '
          'row survives the plan 134a hand-off', () async {
        await seedExercise(
          repo,
          id: 'ex-bench',
          name: 'Bench',
          capabilities: ['load'],
        );
        final inbox = WatchSessionInbox(
          repository: repo,
          onSessionHistoryChanged: _service(repo).settle,
        );

        final result = await inbox.receive(
          _observationsUp('w-energy-inbox', [
            _wristSet('t-set-1', 'sx-bench'),
            _wristEnd(
              'w-energy-inbox',
              modality: 'resistance_lifting',
              energy: 412.6,
            ),
          ], messageId: 'm-1'),
        );

        expect(
          result.outcome,
          isNot(WatchInboxOutcome.failed),
          reason: 'S-13465 the pass accepts the energy field',
        );
        final session = await repo.getSession('w-energy-inbox');
        expect(session, isNotNull, reason: 'S-13465 the session is imported');
        final row = await repo.getSessionEnergy('w-energy-inbox');
        expect(row, isNotNull, reason: 'S-13465 the measured row is stored');
        expect(row!.source, SessionEnergy.sourceMeasured);
        expect(row.activeKcal, closeTo(412.6, 1e-9));
        expect(
          row.bodyWeightKg,
          isNull,
          reason: 'S-13465 the settle never overwrites a measured row',
        );
      });
    });
  }
}
