// The phone side of F-CAP, shared by the two suites that import wrist sessions:
// `test/watch_session_import_test.dart` (scenarios S-261 – S-274) and
// `test/watch_capture_contract_test.dart` (the Dart half of the capture
// contract on Mock and Hive, S-272).
//
// Plan: `docs/plans/2026-09-25-02-stats-pr2-watch-capture-plan.md`.
//
// The expected values are the contract's own (`watch/contract/
// watch_capture_contract.json`, `expectedImport`), so a change to the importer
// is judged against the same numbers the wrist's capture is.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/metric_ids.dart';
import 'package:omnitrain/core/services/watch_session_importer.dart';
import 'package:omnitrain/core/sync_protocol/message_validator.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/core/platform/watch_delivery.dart';
import 'package:omnitrain/state/watch/live_session_mirror_state.dart';

/// The capture contract, parsed.
Map<String, Object?> readCaptureContract() =>
    (jsonDecode(
              File(
                '${Directory.current.path}/watch/contract/watch_capture_contract.json',
              ).readAsStringSync(),
            )
            as Map)
        .cast<String, Object?>();

Map<String, Object?> _object(Object? value) =>
    (value! as Map).cast<String, Object?>();

List<Map<String, Object?>> _objects(Object? value) => [
  for (final element in (value! as List)) _object(element),
];

/// One case of the contract (`full`, `no-sensors`, `prompt-off`).
Map<String, Object?> captureCase(String name) => _objects(
  readCaptureContract()['cases'],
).singleWhere((c) => c['name'] == name);

/// The events a wrist emits for [caseName], in store order.
List<Map<String, Object?>> captureEvents(String caseName) =>
    _objects(captureCase(caseName)['expectedEvents']);

/// What the phone holds after importing [caseName].
Map<String, Object?> captureExpectedImport(String caseName) =>
    _object(captureCase(caseName)['expectedImport']);

/// One `observations_up` envelope for [sessionId] carrying [events], as a wrist
/// sends it.
Map<String, Object?> observationsUp(
  String sessionId,
  List<Map<String, Object?>> events, {
  required String messageId,
  String sentAt = '2026-09-25T11:00:00Z',
}) => {
  'protocolVersion': SyncProtocolValidator.protocolVersion,
  'messageId': messageId,
  'sessionId': sessionId,
  'type': 'observations_up',
  'origin': 'watch',
  'sentAt': sentAt,
  'payload': {
    'events': [for (final event in events) Map<String, Object?>.of(event)],
  },
};

/// The contract's phone catalog, stored with its capabilities.
Future<void> seedCaptureCatalog(WorkoutRepository repository) async {
  for (final exercise in _objects(readCaptureContract()['phoneCatalog'])) {
    await seedExercise(
      repository,
      id: exercise['exerciseId']! as String,
      name: exercise['name']! as String,
      capabilities: (exercise['capabilities']! as List).cast<String>(),
    );
  }
}

/// One catalog exercise with its capabilities.
Future<void> seedExercise(
  WorkoutRepository repository, {
  required String id,
  required String name,
  required List<String> capabilities,
}) async {
  const at = 1788000000000;
  await repository.createExercise(
    Exercise(id: id, name: name, createdAtMs: at, updatedAtMs: at),
  );
  await repository.setExerciseCapabilities(id, capabilities);
}

/// A transport that records what the phone sent and carries nothing.
class CaptureTransport implements WatchMirrorTransport {
  final List<Map<String, Object?>> sent = [];

  /// Called with each envelope before it is recorded, so a test can look at
  /// the repository at the moment the phone answered.
  Future<void> Function(Map<String, Object?> envelope)? onSend;

  /// Every `entryId` any receipt named, in the order they were sent.
  List<String> get receiptedEntryIds => [
    for (final envelope in sent)
      if (envelope['type'] == 'receipt')
        ...(_object(envelope['payload'])['entryIds']! as List).cast<String>(),
  ];

  List<Map<String, Object?>> ofType(String type) => [
    for (final envelope in sent)
      if (envelope['type'] == type) envelope,
  ];

  @override
  Future<WatchDelivery> send(Map<String, Object?> envelope) async {
    await onSend?.call(envelope);
    sent.add(envelope);
    return WatchDelivery.delivered;
  }

  @override
  Future<void> requestSnapshot() async {}
}

int _ms(Object? iso) =>
    DateTime.parse(iso! as String).toUtc().millisecondsSinceEpoch;

/// The one segment an imported session holds.
Future<SessionSegment> importedSegment(
  WorkoutRepository repository,
  String sessionId,
) async => (await repository.getSessionSegments(sessionId)).single;

/// The efforts of an imported session, in the order the phone lists them.
Future<List<SegmentEffort>> importedEfforts(
  WorkoutRepository repository,
  String sessionId,
) async {
  final segments = await repository.getSessionSegments(sessionId);
  if (segments.isEmpty) return const [];
  return repository.getSegmentEfforts(segments.single.id);
}

/// An effort's observations, sorted by id — Hive and Mock return them in
/// different orders, and the id is what carries the entry index.
Future<List<EffortObservation>> sortedObservations(
  WorkoutRepository repository,
  String effortId,
) async =>
    (await repository.getEffortObservations(effortId))
      ..sort((a, b) => a.id.compareTo(b.id));

/// The observation `obs-<effortId>-<entryIndex>-<metricKey>`, or null.
Future<EffortObservation?> observationAt(
  WorkoutRepository repository,
  String effortId,
  int entryIndex,
  String metricKey,
) async {
  final id = 'obs-$effortId-$entryIndex-$metricKey';
  for (final observation in await repository.getEffortObservations(effortId)) {
    if (observation.id == id) return observation;
  }
  return null;
}

/// Every row the repository holds for [sessionId] — session, segments,
/// efforts, observations, instances, summaries and staged inbox rows — by
/// `toMap`, in a stable order. Two repositories that imported the same thing
/// the same way produce equal dumps.
Future<Map<String, Object?>> importedRows(
  WorkoutRepository repository,
  String sessionId,
) async {
  final session = await repository.getSession(sessionId);
  final segments = await repository.getSessionSegments(sessionId);
  final efforts = <SegmentEffort>[
    for (final segment in segments)
      ...await repository.getSegmentEfforts(segment.id),
  ];
  final observations = <EffortObservation>[];
  final timed = <TimedInstance>[];
  final rounds = <RoundInstance>[];
  for (final effort in efforts) {
    observations.addAll(await repository.getEffortObservations(effort.id));
    timed.addAll(await repository.getTimedInstances(effort.id));
    rounds.addAll(await repository.getRoundInstances(effort.id));
  }
  int byId(Map<String, dynamic> a, Map<String, dynamic> b) =>
      (a['id'] as String).compareTo(b['id'] as String);

  return {
    'session': session?.toMap(),
    'segments': [for (final s in segments) s.toMap()],
    'efforts': [for (final e in efforts) e.toMap()],
    'observations': [for (final o in observations) o.toMap()]..sort(byId),
    'timedInstances': [for (final t in timed) t.toMap()]..sort(byId),
    'roundInstances': [for (final r in rounds) r.toMap()]..sort(byId),
    'summaries': [
      for (final s in await repository.getSensorSummariesForSession(sessionId))
        s.toMap(),
    ],
    'inbox': [
      for (final row in await repository.getWatchInboxEntriesForSession(
        sessionId,
      ))
        row.toMap(),
    ],
  };
}

/// Checks the repository against a case's `expectedImport`, row by row. The
/// contract names efforts by slot, which the phone does not store: the effort
/// id the importer derives from the slot is how a slot is found.
Future<void> expectCaptureImport(
  WorkoutRepository repository,
  Map<String, Object?> expected, {
  required List<String> receiptedEntryIds,
  String? reasonPrefix,
}) async {
  final label = reasonPrefix ?? 'F-CAP';
  final expectedSession = _object(expected['session']);
  final sessionId = expectedSession['id']! as String;

  final session = await repository.getSession(sessionId);
  expect(session, isNotNull, reason: '$label: the session is imported');
  expect(
    session!.startedAtMs,
    _ms(expectedSession['startedAt']),
    reason: '$label: session!.startedAtMs',
  );
  expect(
    session.endedAtMs,
    _ms(expectedSession['endedAt']),
    reason: '$label: session.endedAtMs',
  );
  expect(
    session.modality,
    expectedSession['modality'],
    reason: '$label: session.modality',
  );
  expect(
    session.sessionFeeling,
    expectedSession['sessionFeeling'],
    reason: '$label: the rating the phone holds',
  );

  final efforts = await importedEfforts(repository, sessionId);
  final expectedEfforts = _objects(expected['efforts']);
  expect(
    [for (final effort in efforts) effort.id],
    [
      for (final effort in expectedEfforts)
        WatchSessionImporter.effortIdFor(
          sessionId,
          effort['sessionExerciseId']! as String,
          effort['exerciseId']! as String,
          effort['effortKind']! as String,
        ),
    ],
    reason:
        '$label: one effort per slot, exercise and kind, in first-entry order',
  );

  for (var i = 0; i < efforts.length; i++) {
    final effort = efforts[i];
    final want = expectedEfforts[i];
    expect(
      effort.exerciseId,
      want['exerciseId'],
      reason: '$label: effort.exerciseId',
    );
    expect(
      effort.effortKind,
      want['effortKind'],
      reason: '$label: effort.effortKind',
    );
    final observations = await sortedObservations(repository, effort.id);

    switch (want['effortKind']) {
      case 'timed':
        final instances = await repository.getTimedInstances(effort.id);
        final wantInstances = _objects(want['timedInstances']);
        expect(
          instances,
          hasLength(wantInstances.length),
          reason: '$label: instances',
        );
        for (var j = 0; j < instances.length; j++) {
          final instance = instances[j];
          final w = wantInstances[j];
          expect(
            instance.id,
            WatchSessionImporter.timedInstanceIdFor(
              sessionId,
              w['entryId']! as String,
            ),
            reason: '$label: the timed instance derives from its entry',
          );
          expect(
            instance.entryIndex,
            w['entryIndex'],
            reason: '$label: instance.entryIndex',
          );
          expect(
            instance.startedAtMs,
            _ms(w['startedAt']),
            reason: '$label: instance.startedAtMs',
          );
          expect(
            instance.finishedAtMs,
            _ms(w['finishedAt']),
            reason: '$label: instance.finishedAtMs',
          );
          expect(
            instance.actualDurationSecs,
            w['actualDurationSecs'],
            reason: '$label: instance.actualDurationSecs',
          );
          expect(
            instance.state,
            TimedState.finished,
            reason: '$label: instance.state',
          );
        }
        for (final w in _objects(want['observations'])) {
          final index = w['entryIndex']! as int;
          final distance = await observationAt(
            repository,
            effort.id,
            index,
            'distance',
          );
          final extra = await observationAt(
            repository,
            effort.id,
            index,
            'extra-weight',
          );
          expect(
            distance?.valueReal,
            (w['distanceMeters']! as num).toDouble(),
            reason: '$label: distance?.valueReal',
          );
          expect(
            distance?.metricId,
            MetricIds.distance,
            reason: '$label: distance?.metricId',
          );
          expect(
            extra?.valueReal,
            (w['extraWeightKg']! as num).toDouble(),
            reason: '$label: extra?.valueReal',
          );
          expect(
            extra?.metricId,
            MetricIds.extraWeight,
            reason: '$label: extra?.metricId',
          );
        }
        expect(
          observations,
          hasLength(2 * wantInstances.length),
          reason: '$label: observations',
        );
      case 'round':
        final rounds = await repository.getRoundInstances(effort.id);
        final wantRounds = _objects(want['roundInstances']);
        expect(rounds, hasLength(wantRounds.length), reason: '$label: rounds');
        for (var j = 0; j < rounds.length; j++) {
          final round = rounds[j];
          final w = wantRounds[j];
          expect(
            round.id,
            WatchSessionImporter.roundInstanceIdFor(
              sessionId,
              w['entryId']! as String,
            ),
            reason: '$label: the round instance derives from its entry',
          );
          expect(
            round.roundIndex,
            w['roundIndex'],
            reason: '$label: round.roundIndex',
          );
          expect(
            round.startedAtMs,
            _ms(w['startedAt']),
            reason: '$label: round.startedAtMs',
          );
          expect(
            round.finishedAtMs,
            _ms(w['finishedAt']),
            reason: '$label: round.finishedAtMs',
          );
          expect(
            round.totalPausedDurationMs,
            w['totalPausedDurationMs'],
            reason: '$label: round.totalPausedDurationMs',
          );
          expect(
            round.actualDurationSecs,
            w['actualDurationSecs'],
            reason: '$label: round.actualDurationSecs',
          );
          expect(
            round.plannedDurationSecs,
            w['plannedDurationSecs'],
            reason: '$label: round.plannedDurationSecs',
          );
          expect(
            round.completed,
            w['completed'],
            reason: '$label: round.completed',
          );
          expect(
            round.state,
            RoundState.finished,
            reason: '$label: round.state',
          );
        }
        expect(observations, isEmpty, reason: '$label: observations');
      case 'set':
        final wantSets = _objects(want['observations']);
        for (final w in wantSets) {
          final index = w['entryIndex']! as int;
          final reps = await observationAt(
            repository,
            effort.id,
            index,
            'reps',
          );
          final weight = await observationAt(
            repository,
            effort.id,
            index,
            'weight',
          );
          expect(reps?.valueInt, w['reps'], reason: '$label: set $index reps');
          expect(
            weight?.valueReal,
            (w['weightKg']! as num).toDouble(),
            reason: '$label: weight?.valueReal',
          );
        }
        final extraWeight = [
          for (final o in observations)
            if (o.metricId == MetricIds.extraWeight) o,
        ];
        expect(
          extraWeight.isNotEmpty,
          want['extraWeightObservations'],
          reason: '$label: extra weight exactly when the exercise lacks load',
        );
        expect(
          observations,
          hasLength(
            wantSets.length * (want['extraWeightObservations'] == true ? 3 : 2),
          ),
          reason: '$label: exactly the set rows, no more',
        );
    }
  }

  final summaries = await repository.getSensorSummariesForSession(sessionId);
  final expectedSummaries = [
    for (final s in _objects(expected['sensorSummaries']))
      {
        'scope': s['scope'],
        'targetId': _summaryTarget(sessionId, s),
        'avg': (s['avgHeartRateBpm'] as num?)?.toDouble(),
        'max': (s['maxHeartRateBpm'] as num?)?.toDouble(),
        'steps': s['steps'],
      },
  ];
  int byKey(Map<String, Object?> a, Map<String, Object?> b) =>
      '${a['scope']}/${a['targetId']}'.compareTo(
        '${b['scope']}/${b['targetId']}',
      );
  expect(
    [
      for (final s in summaries)
        {
          'scope': s.scope,
          'targetId': s.targetId,
          'avg': s.avgHeartRateBpm,
          'max': s.maxHeartRateBpm,
          'steps': s.steps,
        },
    ]..sort(byKey),
    expectedSummaries..sort(byKey),
    reason:
        '$label: exactly the summaries the wrist measured, on their targets',
  );
  for (final summary in summaries) {
    expect(summary.sessionId, sessionId, reason: '$label: summary.sessionId');
    expect(
      summary.source,
      SensorSummary.sourceWatch,
      reason: '$label: summary.source',
    );
  }

  expect(
    receiptedEntryIds.toSet(),
    (expected['receiptedEntryIds']! as List).cast<String>().toSet(),
    reason: '$label: the union of receipted entryIds',
  );
}

String _summaryTarget(String sessionId, Map<String, Object?> summary) {
  final target = _object(summary['target']);
  switch (summary['scope']) {
    case SensorSummary.scopeSession:
      return target['sessionId']! as String;
    case SensorSummary.scopeEffort:
      return WatchSessionImporter.effortIdFor(
        sessionId,
        target['sessionExerciseId']! as String,
        target['exerciseId']! as String,
        target['effortKind']! as String,
      );
    case SensorSummary.scopeTimedInstance:
      return WatchSessionImporter.timedInstanceIdFor(
        sessionId,
        target['entryId']! as String,
      );
    default:
      return WatchSessionImporter.roundInstanceIdFor(
        sessionId,
        target['entryId']! as String,
      );
  }
}
