// A followed session's end (plan 71, D-4/D-5): the wrist only followed a
// session the phone started, so its `session_end` carries the wrist's heart
// rate and nothing the phone lacks — the phone stores the summary and never
// turns the end into history.
//
// Scenario mapping (plan 71, S-101xx):
//   S-10101 a followed completed end for a session in history
//   S-10102 a followed end for a deleted session creates nothing
//   S-10103 a followed abandoned end attaches nothing and is consumed
//   S-10104 a followed end arriving twice attaches once
//   S-10105 a held session with a followed end
//   S-10106 a wrist-created end (no `followed`) still creates the session
//   S-10107 an end with `followed` true but no heart rate
//
// Both repositories run each scenario (the parity invariant). Plain `test()`:
// no widget is involved, and a Hive write inside a widget test's fake-async
// zone never drains.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/watch_session_importer.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';

import 'helpers/repository_harness.dart';

/// Heart-rate values unlike any fixture default (plan 71).
const double _avg = 133;
const double _max = 171;

String _iso(int ms) =>
    DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toIso8601String();

WatchInboxEntry _wristRow(
  String entryId,
  String kind,
  String session,
  Map<String, dynamic> payload,
) => WatchInboxEntry(
  entryId: entryId,
  watchSessionId: session,
  kind: kind,
  origin: WatchInboxEntry.originWatch,
  payload: {'eventId': entryId, 'entryId': entryId, 'kind': kind, ...payload},
  receivedAtMs: fixtureStart + 7200000,
);

WatchInboxEntry _followedEnd(
  String session, {
  String status = 'completed',
  double? avg = _avg,
  double? max = _max,
  bool followed = true,
}) {
  final start = fixtureStart;
  final end = start + 3600000;
  return _wristRow('end-$session', WatchInboxEntry.kindSessionEnd, session, {
    'loggedAt': _iso(end),
    'startedAt': _iso(start),
    'endedAt': _iso(end),
    'status': status,
    if (followed) 'followed': true,
    'avgHeartRateBpm': ?avg,
    'maxHeartRateBpm': ?max,
  });
}

/// The phone's session `phone-s1`: one segment, two set efforts, each with
/// entries, so "nothing else changed" can be counted.
Future<void> _seedPhoneSession(WorkoutRepository repo, String sessionId) async {
  await seedSession(repo, sessionId: sessionId);
  await seedExercise(repo, id: 'ex-row', name: 'Row', capabilities: ['load']);
  await seedSetEffort(
    repo,
    segmentId: 'seg-$sessionId',
    effortId: 'effort-$sessionId-a-ex-row-set',
    exerciseId: 'ex-row',
    entryCount: 2,
    hasExtraWeight: false,
  );
  await seedSetEffort(
    repo,
    segmentId: 'seg-$sessionId',
    effortId: 'effort-$sessionId-b-ex-row-set',
    exerciseId: 'ex-row',
    entryCount: 3,
    hasExtraWeight: false,
  );
}

Future<List<SegmentEffort>> _effortsOf(
  WorkoutRepository repo,
  String sessionId,
) async {
  final efforts = <SegmentEffort>[];
  for (final segment in await repo.getSessionSegments(sessionId)) {
    efforts.addAll(await repo.getSegmentEfforts(segment.id));
  }
  return efforts;
}

/// The session's shape the followed branch must not disturb: the effort ids
/// and, per effort, its row ids.
Future<Map<String, Set<String>>> _shapeOf(
  WorkoutRepository repo,
  String sessionId,
) async => {
  for (final effort in await _effortsOf(repo, sessionId))
    effort.id: {
      for (final row in await repo.getEffortObservations(effort.id)) row.id,
    },
};

Future<List<SensorSummary>> _sessionSummaries(
  WorkoutRepository repo,
  String sessionId,
) async => [
  for (final summary in await repo.getSensorSummariesForSession(sessionId))
    if (summary.scope == SensorSummary.scopeSession) summary,
];

void main() {
  for (final harnessFactory in harnessFactories) {
    final harness = harnessFactory();
    group('followed end import (${harness.name})', () {
      late WorkoutRepository repo;

      setUp(() async {
        repo = await harness.open();
      });

      tearDown(harness.close);

      test('S-10101 a followed completed end for a session in history attaches '
          'the heart rate and nothing else', () async {
        await _seedPhoneSession(repo, 'phone-s1');
        final shapeBefore = await _shapeOf(repo, 'phone-s1');
        await repo.stageWatchInboxEntry(
          _followedEnd('phone-s1'),
        );
        // One unapplied wrist set row the followed branch must leave alone.
        await repo.stageWatchInboxEntry(
          _wristRow('set-a', WatchInboxEntry.kindSet, 'phone-s1', {
            'loggedAt': _iso(fixtureStart + 60000),
            'sessionExerciseId': 'a',
            'exerciseId': 'ex-row',
            'reps': 9,
          }),
        );

        final result = await WatchSessionImporter(
          repository: repo,
        ).apply('phone-s1');

        final summaries = await _sessionSummaries(repo, 'phone-s1');
        expect(summaries, hasLength(1), reason: 'S-10101 exactly one summary');
        expect(summaries.single.avgHeartRateBpm, _avg);
        expect(summaries.single.maxHeartRateBpm, _max);
        expect(
          await _shapeOf(repo, 'phone-s1'),
          shapeBefore,
          reason: 'S-10101 the efforts and their rows are unchanged',
        );
        expect(
          (await repo.getWatchInboxEntry('end-phone-s1'))!.appliedAtMs,
          isNotNull,
          reason: 'S-10101 the end row is applied',
        );
        expect(
          (await repo.getWatchInboxEntry('set-a'))!.appliedAtMs,
          isNull,
          reason: 'S-10101 the wrist set row is still unapplied',
        );
        expect(
          result.appliedEntryIds,
          ['end-phone-s1'],
          reason: 'S-10101 the receipt names the end only',
        );
        expect(result.sensorSummaryAttached, isTrue);
      });

      test('S-10102 a followed end for a deleted session creates nothing', () async {
        await repo.stageWatchInboxEntry(_followedEnd('phone-gone'));

        final result = await WatchSessionImporter(
          repository: repo,
        ).apply('phone-gone');

        expect(
          await repo.getSession('phone-gone'),
          isNull,
          reason: 'S-10102 no session is re-created',
        );
        expect(await _sessionSummaries(repo, 'phone-gone'), isEmpty);
        expect(
          (await repo.getWatchInboxEntry('end-phone-gone'))!.appliedAtMs,
          isNotNull,
        );
        expect(result.sensorSummaryAttached, isFalse);
      });

      test('S-10103 a followed abandoned end attaches nothing and is consumed',
          () async {
        await _seedPhoneSession(repo, 'phone-s1');
        await repo.stageWatchInboxEntry(
          _followedEnd('phone-s1', status: 'abandoned'),
        );

        final result = await WatchSessionImporter(
          repository: repo,
        ).apply('phone-s1');

        expect(await _sessionSummaries(repo, 'phone-s1'), isEmpty);
        expect(
          (await repo.getWatchInboxEntry('end-phone-s1'))!.appliedAtMs,
          isNotNull,
          reason: 'S-10103 the end is consumed',
        );
        expect(result.sensorSummaryAttached, isFalse);
      });

      test('S-10104 a followed end arriving twice attaches once', () async {
        await _seedPhoneSession(repo, 'phone-s1');
        await repo.stageWatchInboxEntry(_followedEnd('phone-s1'));
        final importer = WatchSessionImporter(repository: repo);
        final first = await importer.apply('phone-s1');
        expect(first.sensorSummaryAttached, isTrue);

        final second = await importer.apply('phone-s1');

        expect(
          await _sessionSummaries(repo, 'phone-s1'),
          hasLength(1),
          reason: 'S-10104 the summary count stays 1',
        );
        expect(second.sensorSummaryAttached, isFalse);
      });

      test('S-10104b a later wrist row does not make an applied followed end '
          'count again', () async {
        await _seedPhoneSession(repo, 'phone-s1');
        await repo.stageWatchInboxEntry(_followedEnd('phone-s1'));
        final importer = WatchSessionImporter(repository: repo);
        await importer.apply('phone-s1');
        // A wrist row arriving afterwards leaves `unapplied` non-empty, so the
        // applied end reaches the followed branch again.
        await repo.stageWatchInboxEntry(
          _wristRow('set-late', WatchInboxEntry.kindSet, 'phone-s1', {
            'loggedAt': _iso(fixtureStart + 90000),
            'sessionExerciseId': 'a',
            'exerciseId': 'ex-row',
            'reps': 7,
          }),
        );

        final second = await importer.apply('phone-s1');

        expect(
          second.appliedEntryIds,
          isEmpty,
          reason: 'S-10104b the applied end is not named in a second receipt',
        );
        expect(second.sensorSummaryAttached, isFalse);
        expect(await _sessionSummaries(repo, 'phone-s1'), hasLength(1));
      });

      test('S-10105 a held session with a followed end', () async {
        await _seedPhoneSession(repo, 'phone-s1');
        final sessionBefore = (await repo.getSession('phone-s1'))!;
        await repo.stageWatchInboxEntry(_followedEnd('phone-s1'));

        final result = await WatchSessionImporter(
          repository: repo,
        ).apply('phone-s1', phoneOwnsSession: true);

        final summaries = await _sessionSummaries(repo, 'phone-s1');
        expect(summaries, hasLength(1), reason: 'S-10105 summary attached');
        expect(summaries.single.avgHeartRateBpm, _avg);
        expect(summaries.single.maxHeartRateBpm, _max);
        expect(result.sensorSummaryAttached, isTrue);
        final sessionAfter = (await repo.getSession('phone-s1'))!;
        expect(
          sessionAfter.startedAtMs,
          sessionBefore.startedAtMs,
          reason: 'S-10105 the session row is untouched',
        );
        expect(sessionAfter.endedAtMs, sessionBefore.endedAtMs);
        expect(sessionAfter.updatedAtMs, sessionBefore.updatedAtMs);
      });

      test('S-10106 a wrist-created end (no `followed`) still creates the '
          'session', () async {
        await repo.stageWatchInboxEntry(
          _followedEnd('phone-new', followed: false),
        );
        // A completed end with no effort behind it is consumed as an empty
        // session (D-133), so the regression arm stages one wrist set.
        await repo.stageWatchInboxEntry(
          _wristRow('set-a', WatchInboxEntry.kindSet, 'phone-new', {
            'loggedAt': _iso(fixtureStart + 60000),
            'sessionExerciseId': 'a',
            'exerciseId': 'ex-row',
            'reps': 9,
          }),
        );

        final result = await WatchSessionImporter(
          repository: repo,
        ).apply('phone-new');

        expect(
          await repo.getSession('phone-new'),
          isNotNull,
          reason: 'S-10106 the regression arm: the session is created',
        );
        expect(result.sensorSummaryAttached, isTrue);
      });

      test('S-10107 an end with `followed` true but no heart rate', () async {
        await _seedPhoneSession(repo, 'phone-s1');
        await repo.stageWatchInboxEntry(
          _followedEnd('phone-s1', avg: null, max: null),
        );

        final result = await WatchSessionImporter(
          repository: repo,
        ).apply('phone-s1');

        expect(await _sessionSummaries(repo, 'phone-s1'), isEmpty);
        expect(
          (await repo.getWatchInboxEntry('end-phone-s1'))!.appliedAtMs,
          isNotNull,
          reason: 'S-10107 the end row is consumed',
        );
        expect(result.sensorSummaryAttached, isFalse);
      });
    });
  }
}
