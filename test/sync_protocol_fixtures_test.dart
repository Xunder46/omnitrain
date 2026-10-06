// Watch↔phone sync protocol conformance gate.
//
// This validates the platform-neutral contract specified by
// `watch/sync_protocol/PROTOCOL.md`, which the native watchOS client and the
// Flutter Wear OS client consume from the very same JSON fixtures. It is not a
// behaviour test for a client: the *apply* rules each client implements are
// exercised by `test/live_mirroring_test.dart` (phone mirror + Wear OS engine)
// and by the watchOS suite's `WatchLiveMirroringTests`. What this gate owns is
// the register itself — every fixture in the manifest validates, every invalid
// one is rejected as stated, and the spec's normative sentences are present.
// The fixtures are read from the repository, not from an asset bundle, so the
// tests fail first if the spec or the fixtures drift.
//
// Scenario mapping (plan: 2026-07-13-05-pr4-watch-phone-sync-protocol-plan.md):
//   S-001 routines-down + fixture conformance → `S-001 fixtures`
//   S-002 idempotent observations              → `S-002 ...`
//   S-003 timers carry no remaining time       → `S-003 ...`
//   S-004 snapshot + divergent events          → `S-004 ...`
//   S-005 remove the watch's current exercise  → `S-005 ...`
//   S-006 version mismatch behaviour           → `S-006 ...`
//   S-007 normative authority rules            → `S-007 ...`

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/sync_protocol/message_validator.dart';
import 'package:omnitrain/core/sync_protocol/session_reconciler.dart';

const String _protocolRoot = 'watch/sync_protocol';

File _protocolFile(String relativePath) =>
    File('${Directory.current.path}/$_protocolRoot/$relativePath');

Map<String, Object?> _asObject(Object? value) =>
    (value as Map).cast<String, Object?>();

List<Map<String, Object?>> _objectsIn(Object? list) =>
    ((list as List?) ?? const []).map(_asObject).toList(growable: false);

Map<String, Object?> _readJson(String relativePath) =>
    _asObject(jsonDecode(_protocolFile(relativePath).readAsStringSync()));

Map<String, Object?> _payloadOf(Object? envelope) =>
    _asObject(_asObject(envelope)['payload']);

/// Every schema document, keyed the way `$ref` addresses it — relative to
/// `schemas/` (see PROTOCOL.md, "Schema layout").
Map<String, Object?> _loadSchemaDocuments() {
  final root = Directory('${Directory.current.path}/$_protocolRoot/schemas');
  return {
    for (final file in root.listSync(recursive: true).whereType<File>())
      if (file.path.endsWith('.json'))
        file.path.substring(root.path.length + 1): jsonDecode(
          file.readAsStringSync(),
        ),
  };
}

/// Fixture files that carry session state — valid fixtures and reconciliation
/// scenarios. Invalid fixtures are excluded on purpose: they exist to be
/// rejected, and one of them deliberately carries a remaining-time field.
Iterable<File> _stateFixtureFiles() sync* {
  for (final group in ['valid', 'reconciliation']) {
    final directory = Directory(
      '${Directory.current.path}/$_protocolRoot/fixtures/$group',
    );
    yield* directory
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.json'));
  }
}

SyncSessionReconciler _reconcilerFor(Object? snapshotEnvelope) =>
    SyncSessionReconciler.fromSnapshot(_payloadOf(snapshotEnvelope));

void _applyStream(
  SyncSessionReconciler reconciler,
  List<Map<String, Object?>> stream,
) {
  for (final message in stream) {
    reconciler.applyMessage(message);
  }
}

SyncSessionReconciler _replay(
  Object? snapshotEnvelope,
  List<Map<String, Object?>> stream,
) {
  final reconciler = _reconcilerFor(snapshotEnvelope);
  _applyStream(reconciler, stream);
  return reconciler;
}

List<Map<String, Object?>> _streamOf(Map<String, Object?> scenario) =>
    _objectsIn(scenario['stream']);

/// Scenario fixtures that replay from a snapshot. The version-mismatch scenario
/// carries cases instead, and is driven by its own test.
bool _isReplayable(Map<String, Object?> scenario) {
  final fixture = _readJson('fixtures/${scenario['path']}');
  return fixture['snapshot'] != null &&
      fixture['stream'] != null &&
      fixture['expected'] != null;
}

/// The exercise slots a scenario's own content can reference, in slot order.
List<String> _slotIds(List<Map<String, Object?>> exercises) => exercises
    .map((exercise) => exercise['sessionExerciseId']! as String)
    .toList(growable: false);

/// Entry ids the scenario's own content can legitimately produce: the snapshot
/// plus every distinct event in the stream.
Set<String> _distinctEntryIds(Map<String, Object?> scenario) {
  final ids = <String>{
    for (final entry in _objectsIn(_payloadOf(scenario['snapshot'])['entries']))
      entry['entryId']! as String,
  };
  for (final message in _streamOf(scenario)) {
    for (final event in _objectsIn(_payloadOf(message)['events'])) {
      ids.add(event['entryId']! as String);
    }
  }
  return ids;
}

/// PROTOCOL.md with runs of whitespace collapsed to single spaces.
///
/// Assertions about a normative sentence must not depend on where the file
/// happens to wrap, otherwise rewrapping a paragraph would read as a spec
/// change.
String _specText() => _protocolFile(
  'PROTOCOL.md',
).readAsStringSync().replaceAll(RegExp(r'\s+'), ' ');

final Map<String, Object?> _manifest = _readJson('fixtures/manifest.json');
final SyncProtocolValidator _validator = SyncProtocolValidator(
  _loadSchemaDocuments(),
);

void main() {
  final validFixtures = _objectsIn(_manifest['valid']);
  final invalidFixtures = _objectsIn(_manifest['invalid']);
  final scenarios = _objectsIn(_manifest['scenarios']);

  group('fixture manifest', () {
    test('lists every fixture file on disk, exactly once', () {
      final fixturesRoot = '${Directory.current.path}/$_protocolRoot/fixtures/';
      final onDisk =
          Directory(fixturesRoot)
              .listSync(recursive: true)
              .whereType<File>()
              .map((file) => file.path.substring(fixturesRoot.length))
              .where(
                (path) => path != 'manifest.json' && path.endsWith('.json'),
              )
              .toList()
            ..sort();
      final listed = [
        ...validFixtures,
        ...invalidFixtures,
        ...scenarios,
      ].map((fixture) => fixture['path']! as String).toList()..sort();

      expect(listed, equals(onDisk));
    });

    test('gives every message type a schema and a valid fixture', () {
      for (final type in SyncProtocolValidator.messageTypes) {
        expect(
          _validator.hasSchemaFor(type),
          isTrue,
          reason: 'no schema document for message type $type',
        );
        expect(
          validFixtures.where((fixture) => fixture['type'] == type),
          isNotEmpty,
          reason: 'no valid fixture for message type $type',
        );
      }
    });

    test('states an expected rejection code and reason for every invalid '
        'fixture', () {
      for (final fixture in invalidFixtures) {
        expect(
          fixture['expectedCode'],
          isA<String>().having((code) => code.isNotEmpty, 'isNotEmpty', isTrue),
          reason: '${fixture['path']} must state its rejection code',
        );
        expect(
          fixture['expectedReasonContains'],
          isA<String>().having((text) => text.isNotEmpty, 'isNotEmpty', isTrue),
          reason: '${fixture['path']} must state its rejection reason',
        );
      }
    });

    test('every fixture envelope declares the current protocol version', () {
      for (final fixture in [...validFixtures, ...invalidFixtures]) {
        final envelope = _readJson('fixtures/${fixture['path']}');
        expect(
          envelope['protocolVersion'],
          SyncProtocolValidator.protocolVersion,
          reason: fixture['path']! as String,
        );
      }
    });
  });

  group('S-001 fixtures', () {
    for (final fixture in validFixtures) {
      test('${fixture['path']} conforms to ${fixture['type']}', () {
        final rejections = _validator.validateEnvelope(
          _readJson('fixtures/${fixture['path']}'),
        );

        expect(rejections.map((r) => r.toString()).toList(), isEmpty);
      });
    }

    for (final fixture in invalidFixtures) {
      test('${fixture['path']} is rejected as '
          '${fixture['expectedCode']}', () {
        final rejections = _validator.validateEnvelope(
          _readJson('fixtures/${fixture['path']}'),
        );

        expect(
          rejections,
          isNotEmpty,
          reason: 'an invalid fixture must not conform',
        );
        expect(
          rejections.map((r) => r.code).toList(),
          contains(fixture['expectedCode']),
        );
        expect(
          rejections.map((r) => r.message).join(' | '),
          contains(fixture['expectedReasonContains']),
        );
      });
    }
  });

  group('S-31 phone-logged entries', () {
    final fixture = _readJson(
      'fixtures/valid/session_snapshot_with_entries.json',
    );
    final entries = _objectsIn(_payloadOf(fixture)['entries']);

    test('the phone\'s snapshot carries its own entries and conforms', () {
      expect(
        _validator.validateEnvelope(fixture).map((r) => r.toString()).toList(),
        isEmpty,
      );
      expect(
        entries.map((entry) => entry['entryId']),
        equals(<String>['entry-slot-bench-0', 'entry-slot-bench-1']),
      );

      final state = _reconcilerFor(fixture).convergedState();

      expect(
        (state['entries']! as List).map((entry) => _asObject(entry)['entryId']),
        equals(<String>['entry-slot-bench-0', 'entry-slot-bench-1']),
        reason: 'a receiver materialises every entry the answer carries',
      );
    });

    test('an entry names its slot, its exercise, its set and its log time', () {
      expect(
        entries.first,
        equals(<String, Object?>{
          'entryId': 'entry-slot-bench-0',
          'eventId': 'entry-slot-bench-0',
          'kind': 'set',
          'loggedAt': '2026-10-05T10:05:00Z',
          'sessionExerciseId': 'slot-bench',
          'exerciseId': 'ex-bench',
          'reps': 8,
          'loadKg': 60,
        }),
      );
      expect(
        _slotIds(_objectsIn(_payloadOf(fixture)['exercises'])),
        contains(entries.first['sessionExerciseId']),
        reason: 'an entry must name a slot the snapshot carries',
      );
      expect(entries.last['loadKg'], 62.5);
      expect(entries.last['loggedAt'], '2026-10-05T10:10:00Z');
      expect(
        entries.first['eventId'],
        equals(entries.first['entryId']),
        reason: 'a phone entry\'s eventId is its entryId',
      );
    });
  });

  group('S-59 the band-assisted set travels with its sign', () {
    final fixture = _readJson(
      'fixtures/valid/session_snapshot_band_assist.json',
    );
    final entries = _objectsIn(_payloadOf(fixture)['entries']);

    test('an assisted snapshot conforms and reaches the converged state', () {
      expect(
        _validator.validateEnvelope(fixture).map((r) => r.toString()).toList(),
        isEmpty,
      );
      expect(
        entries.map((entry) => entry['entryId']),
        equals(<String>['entry-slot-bench-0', 'entry-slot-bench-1']),
      );

      final state = _reconcilerFor(fixture).convergedState();

      expect(
        (state['entries']! as List).map((entry) => _asObject(entry)['entryId']),
        equals(<String>['entry-slot-bench-0', 'entry-slot-bench-1']),
      );
    });

    test('an assisted entry names its slot, its set and its negative load', () {
      expect(
        entries.first,
        equals(<String, Object?>{
          'entryId': 'entry-slot-bench-0',
          'eventId': 'entry-slot-bench-0',
          'kind': 'set',
          'loggedAt': '2026-10-06T10:05:00Z',
          'sessionExerciseId': 'slot-bench',
          'exerciseId': 'ex-bench',
          'reps': 8,
          'loadKg': -20,
        }),
      );
      expect(
        _slotIds(_objectsIn(_payloadOf(fixture)['exercises'])),
        contains(entries.first['sessionExerciseId']),
        reason: 'an entry must name a slot the snapshot carries',
      );
      expect(
        entries.last['loadKg'],
        -200,
        reason: 'the floor is carried verbatim, not rounded or re-signed',
      );
    });
  });

  group('S-58 an assisted set on the observations wire', () {
    test('observations_up carries a negative load and conforms', () {
      final fixture = _readJson(
        'fixtures/valid/observations_up_band_assist.json',
      );

      expect(
        _validator.validateEnvelope(fixture).map((r) => r.toString()).toList(),
        isEmpty,
      );
      expect(
        _objectsIn(_payloadOf(fixture)['events']).last,
        equals(<String, Object?>{
          'eventId': 'evt-assist-2',
          'entryId': 'evt-assist-2',
          'kind': 'set',
          'loggedAt': '2026-10-06T18:14:00Z',
          'sessionExerciseId': 'sx-bench',
          'exerciseId': 'ex-bench',
          'reps': 5,
          'loadKg': -200,
        }),
      );
    });
  });

  group('S-65/S-66 one floor for a correction and a target', () {
    test('a correction may carry an assist down to the floor', () {
      final fixture = _readJson(
        'fixtures/valid/structure_change_band_assist.json',
      );

      expect(
        _validator.validateEnvelope(fixture).map((r) => r.toString()).toList(),
        isEmpty,
      );
      expect(
        _objectsIn(_payloadOf(fixture)['changes'])
            .where((change) => change['kind'] == 'correct_entry')
            .map((change) => _asObject(change['correction'])['loadKg'])
            .where((load) => load != null),
        equals(<Object?>[-20, -200]),
      );
    });

    test('a routine target may carry an assist down to the floor', () {
      final fixture = _readJson('fixtures/valid/routines_down_band_assist.json');

      expect(
        _validator.validateEnvelope(fixture).map((r) => r.toString()).toList(),
        isEmpty,
      );
      final efforts = _objectsIn(
        _objectsIn(
          _objectsIn(_payloadOf(fixture)['routines']).first['segments'],
        ).first['efforts'],
      );

      expect(
        {
          for (final effort in efforts)
            if (_asObject(effort['targets'])['loadKg'] != null)
              effort['effortId']: _asObject(effort['targets'])['loadKg'],
        },
        equals(<String, Object?>{'eff-bench': -20, 'eff-goblet-squat': -200}),
      );
    });
  });

  test('S-002 duplicate delivery: replaying a stream changes nothing', () {
    final scenario = _readJson(
      'fixtures/reconciliation/duplicate_delivery.json',
    );
    final stream = _streamOf(scenario);

    final appliedOnce = _replay(scenario['snapshot'], stream);
    final appliedTwice = _replay(scenario['snapshot'], stream);
    _applyStream(appliedTwice, stream);

    expect(
      (appliedOnce.convergedState()['entries'] as List).length,
      _distinctEntryIds(scenario).length,
      reason: 'each distinct entry must materialise exactly once',
    );
    expect(appliedOnce.convergedState(), equals(scenario['expected']));
    expect(appliedTwice.convergedState(), equals(appliedOnce.convergedState()));
  });

  test('S-003 no state-carrying fixture names a remaining-time field', () {
    const forbidden = [
      'remaining',
      'countdown',
      'secondsleft',
      'timeleft',
      'time_left',
    ];
    final offenders = <String>[];

    for (final file in _stateFixtureFiles()) {
      final text = file.readAsStringSync().toLowerCase();
      for (final needle in forbidden) {
        if (text.contains(needle)) {
          offenders.add('${file.path}: $needle');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'timers are wall-clock timestamps plus pause bookkeeping; a '
          'remaining-time field must never appear in a timer fixture',
    );
  });

  test('S-003 every timer kind is covered by a valid fixture', () {
    final kinds = <String>{};
    for (final fixture in validFixtures.where(
      (f) => f['type'] == 'timer_state',
    )) {
      kinds.addAll(
        _asObject(
          _payloadOf(_readJson('fixtures/${fixture['path']}'))['timers'],
        ).keys,
      );
    }

    expect(kinds, unorderedEquals(SyncProtocolValidator.timerKinds));
  });

  test(
    'S-004 every reconciliation fixture converges on its expected state',
    () {
      final replayable = scenarios.where(_isReplayable).toList();

      expect(
        replayable.length,
        scenarios.length - 1,
        reason: 'only the version-mismatch scenario is not a replay',
      );

      for (final scenario in replayable) {
        final fixture = _readJson('fixtures/${scenario['path']}');
        final reconciled = _replay(fixture['snapshot'], _streamOf(fixture));

        expect(
          reconciled.convergedState(),
          equals(fixture['expected']),
          reason: scenario['property']! as String,
        );
      }
    },
  );

  test(
    'S-005 removing the current exercise advances to the next valid one',
    () {
      final scenario = _readJson(
        'fixtures/reconciliation/remove_current_exercise.json',
      );
      final startIndex =
          _payloadOf(scenario['snapshot'])['currentExerciseIndex']! as int;
      expect(
        startIndex,
        1,
        reason: 'fixture must remove the watch\'s exercise',
      );

      final reconciled = _replay(scenario['snapshot'], _streamOf(scenario));
      final state = reconciled.convergedState();
      final exercises = (state['exercises']! as List).map(_asObject).toList();

      expect(state, equals(scenario['expected']));
      expect(state['currentExerciseIndex'], 1);
      expect(exercises[1]['sessionExerciseId'], 'sx-squat');
      expect(exercises[1]['exerciseId'], 'ex-goblet-squat');
      expect(
        _asObject((state['timers']! as Map)['elapsed'])['state'],
        'running',
        reason: 'a running timer elsewhere in the session must be unaffected',
      );
      expect(
        (state['entries']! as List).map(
          (entry) => _asObject(entry)['sessionExerciseId'],
        ),
        containsAll(<String>['sx-bench', 'sx-plank']),
        reason: 'removing a slot must not remove the entries logged against it',
      );
    },
  );

  test('S-005 the same exercise in two slots is two addresses', () {
    final scenario = _readJson(
      'fixtures/reconciliation/repeated_exercise.json',
    );
    final exercises = _objectsIn(_payloadOf(scenario['snapshot'])['exercises']);
    final benchSlots = _slotIds(
      exercises
          .where(
            (exercise) => exercise['exerciseId'] == 'ex-barbell-bench-press',
          )
          .toList(growable: false),
    );

    expect(
      benchSlots,
      hasLength(2),
      reason: 'a session may hold the same exercise in two slots',
    );

    final state = _replay(
      scenario['snapshot'],
      _streamOf(scenario),
    ).convergedState();
    final remaining = (state['exercises']! as List).map(_asObject).toList();

    expect(
      _slotIds(remaining),
      contains(benchSlots.last),
      reason: 'removing one slot must leave the other standing',
    );
  });

  test('S-005 a slot id can be introduced only once', () {
    final scenario = _readJson(
      'fixtures/reconciliation/duplicate_slot_add.json',
    );
    final snapshotSlots = _slotIds(
      _objectsIn(_payloadOf(scenario['snapshot'])['exercises']),
    );

    final state = _replay(
      scenario['snapshot'],
      _streamOf(scenario),
    ).convergedState();
    final exercises = (state['exercises']! as List).map(_asObject).toList();

    expect(state, equals(scenario['expected']));
    expect(
      _slotIds(exercises),
      equals(snapshotSlots),
      reason: 'a re-delivered push or add must not duplicate a slot',
    );
    expect(
      exercises.first['exerciseId'],
      'ex-barbell-bench-press',
      reason: 'a push at an occupied slot must not overwrite what it holds',
    );
  });

  test('S-006 version mismatch is rejected and answered with a snapshot', () {
    final scenario = _readJson('fixtures/reconciliation/version_mismatch.json');

    for (final mismatch in _objectsIn(scenario['cases'])) {
      final expected = _asObject(mismatch['expected']);
      final decision = _validator.evaluateIncoming(
        _asObject(mismatch['message']),
        receiverVersion: mismatch['receiverVersion']! as int,
      );

      expect(
        decision.decision,
        expected['decision'],
        reason: mismatch['name']! as String,
      );
      expect(
        decision.respondWithSnapshot,
        expected['respondWithSnapshot'],
        reason: mismatch['name']! as String,
      );
      expect(decision.accepted, isFalse, reason: mismatch['name']! as String);
      expect(
        decision.rejectionCodes,
        contains(expected['reasonCode']),
        reason: mismatch['name']! as String,
      );
    }
  });

  test('S-006 a same-version message is accepted without a resync', () {
    final decision = _validator.evaluateIncoming(
      _readJson('fixtures/valid/observations_up.json'),
      receiverVersion: SyncProtocolValidator.protocolVersion,
    );

    expect(decision.decision, SyncProtocolValidator.acceptDecision);
    expect(decision.respondWithSnapshot, isFalse);
    expect(decision.rejections, isEmpty);
  });

  group('S-007 specification', () {
    test('states the authority rules normatively', () {
      final spec = _specText();

      for (final statement in const [
        'The watch MUST NOT edit or delete existing records',
        'The phone MUST be authoritative for session structure',
        'MUST advance to the next valid exercise',
        'MUST accept watch-appended observations',
      ]) {
        expect(spec, contains(statement));
      }
      expect('MUST'.allMatches(spec).length, greaterThanOrEqualTo(6));
    });

    test('states the exercise-identity rules normatively', () {
      final spec = _specText();

      for (final statement in const [
        'sessionExerciseId',
        'MUST be unique within a session',
        'is already present MUST be ignored',
      ]) {
        expect(spec, contains(statement));
      }
    });

    test('states the lifecycle ordering rule normatively', () {
      final spec = _specText();

      for (final statement in const [
        'Lifecycle messages are applied in the order received',
        'the most recent status wins',
      ]) {
        expect(spec, contains(statement));
      }
    });

    test('states the protocol version the validator implements', () {
      final spec = _specText();

      expect(
        spec,
        contains(
          '**Protocol version: ${SyncProtocolValidator.protocolVersion}.**',
        ),
        reason: 'the spec and the validator must not drift apart',
      );
    });

    test('documents every rejection code the validator can emit', () {
      final spec = _specText();

      for (final code in SyncProtocolValidator.rejectionCodes) {
        expect(spec, contains('`$code`'), reason: '$code is undocumented');
      }
    });

    test('links only to schema and fixture paths that exist', () {
      final spec = _specText();
      final referenced = RegExp(
        r'`((?:schemas|fixtures)/[A-Za-z0-9_./-]+)`',
      ).allMatches(spec).map((match) => match.group(1)!).toSet();

      expect(referenced, isNotEmpty);
      for (final path in referenced) {
        expect(
          FileSystemEntity.typeSync(_protocolFile(path).path),
          isNot(FileSystemEntityType.notFound),
          reason: 'PROTOCOL.md links $path but it does not exist',
        );
      }
    });
  });

  group('the receiver gate', () {
    /// Every entry point that takes a message from a peer calls
    /// [SyncProtocolValidator.evaluateOrAccept]: the version check and the
    /// conformance verdict have one owner, so a receiver cannot answer
    /// differently from the protocol it claims to speak.
    test('accepts a conformant message and refuses a malformed one', () {
      final conformant = _readJson('fixtures/valid/foods_down.json');

      expect(_accepted(conformant), isTrue);

      final malformed = _readJson(
        'fixtures/invalid/foods_down_missing_food_id.json',
      );
      expect(_accepted(malformed), isFalse);
    });

    test('refuses a message written for another protocol version', () {
      final otherVersion = {
        ..._readJson('fixtures/valid/foods_down.json'),
        'protocolVersion': SyncProtocolValidator.protocolVersion + 1,
      };

      expect(_accepted(otherVersion), isFalse);
      expect(
        _validator
            .evaluateIncoming(
              otherVersion,
              receiverVersion: SyncProtocolValidator.protocolVersion,
            )
            .respondWithSnapshot,
        isTrue,
        reason: 'a version this build cannot read is answered with a resync',
      );
    });

    test('accepts anything when the receiver carries no schemas', () {
      // A build that ships without the schema set cannot tell a conformant
      // message from a malformed one, and refusing everything it cannot read
      // would be worse than reading what it can.
      expect(
        SyncProtocolValidator.evaluateOrAccept(null, {'type': 'foods_down'}),
        isA<SyncMessageDecision>().having(
          (decision) => decision.accepted,
          'accepted',
          isTrue,
        ),
      );
    });
  });
}

/// The shared gate's verdict on [message], as every receiver sees it.
bool _accepted(Map<String, Object?> message) =>
    SyncProtocolValidator.evaluateOrAccept(_validator, message).accepted;
