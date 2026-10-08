/// Watch↔phone sync protocol conformance validator.
///
/// Pure Dart — no Flutter, no `dart:io` — so the same code runs in the app
/// bundle, in tests, and behind any future transport. Schema documents are
/// supplied by the caller (which is what keeps `dart:io` out of this file) and
/// keyed the way `$ref` addresses them: relative to
/// `watch/sync_protocol/schemas/`.
///
/// The spec these schemas encode lives in `watch/sync_protocol/PROTOCOL.md`,
/// and the fixtures the gate runs on live in
/// `watch/sync_protocol/fixtures/`.
library;

import 'dart:convert';

/// Machine-facing rejection codes, documented one by one in PROTOCOL.md.
const String _unsupportedProtocolVersion = 'unsupported_protocol_version';
const String _unknownMessageType = 'unknown_message_type';
const String _missingSchema = 'missing_schema';
const String _unresolvableReference = 'unresolvable_reference';
const String _missingRequiredField = 'missing_required_field';
const String _unexpectedField = 'unexpected_field';
const String _invalidType = 'invalid_type';
const String _invalidEnumValue = 'invalid_enum_value';
const String _invalidConstValue = 'invalid_const_value';
const String _constraintViolation = 'constraint_violation';
const String _noMatchingVariant = 'no_matching_variant';
const String _semanticViolation = 'semantic_violation';

/// Root of every message path, as a constant so `$` never needs escaping.
const String _root = r'$';

/// A single reason a message did not conform.
class SyncProtocolRejection {
  const SyncProtocolRejection({
    required this.code,
    required this.path,
    required this.message,
  });

  /// Stable machine-readable code.
  final String code;

  /// Location inside the message, e.g. `$.payload.routines[0].routineId`.
  final String path;

  /// Human-readable explanation.
  final String message;

  @override
  String toString() => '$code at $path: $message';
}

/// What a receiver does with an incoming message.
class SyncMessageDecision {
  const SyncMessageDecision({
    required this.decision,
    required this.reason,
    required this.respondWithSnapshot,
    required this.rejections,
  });

  /// One of [SyncProtocolValidator.acceptDecision],
  /// [SyncProtocolValidator.rejectDecision], or
  /// [SyncProtocolValidator.rejectAndResyncDecision].
  final String decision;

  final String reason;

  /// True when the receiver must answer with a `session_snapshot`.
  final bool respondWithSnapshot;

  final List<SyncProtocolRejection> rejections;

  bool get accepted => decision == SyncProtocolValidator.acceptDecision;

  List<String> get rejectionCodes =>
      rejections.map((rejection) => rejection.code).toList(growable: false);
}

/// Validates sync messages against the protocol schemas.
///
/// The schema dialect is the subset of JSON Schema 2020-12 the protocol
/// actually uses: `type`, `const`, `enum`, `required`, `properties`,
/// `additionalProperties`, `items`, `minItems`, `minLength`, `minimum`,
/// `maximum`, `pattern`, `allOf`, `oneOf`, and `$ref` — where a `$ref` target is
/// either `#/…` inside the current document or `<document>.schema.json#/…`
/// relative to `schemas/`.
class SyncProtocolValidator {
  SyncProtocolValidator(Map<String, Object?> schemaDocuments)
    : _documents = {
        for (final entry in schemaDocuments.entries)
          entry.key: _asObject(entry.value),
      };

  final Map<String, Map<String, Object?>> _documents;

  /// The only version this validator, and this repository, speaks.
  static const int protocolVersion = 1;

  static const String acceptDecision = 'accept';
  static const String rejectDecision = 'reject';
  static const String rejectAndResyncDecision = 'reject_and_resync';

  static const List<String> messageTypes = [
    'routines_down',
    'foods_down',
    'preferences_down',
    'exercise_push',
    'structure_change',
    'observations_up',
    'receipt',
    'session_lifecycle',
    'session_snapshot',
    'timer_state',
  ];

  static const List<String> timerKinds = ['rest', 'round', 'hold', 'elapsed'];

  /// Entry kinds that are not logged against a slot: a nutrition quick-log,
  /// and the two session-scoped kinds, which describe the whole session.
  static const Set<String> _slotlessKinds = {
    'nutrition_quick_log',
    'effort_rating',
    'session_end',
  };

  /// The entry kinds each capture field may travel on, in the order the
  /// semantic layer reports them. The wrist computes these values for the
  /// entries they describe and no other, so a field anywhere else is a sender
  /// defect (PROTOCOL.md, "Session capture").
  static const Map<String, List<String>> _captureFieldKinds = {
    'steps': ['timed'],
    'distanceSource': ['timed'],
    'avgHeartRateBpm': ['timed', 'round', 'hold', 'session_end'],
    'maxHeartRateBpm': ['timed', 'round', 'hold', 'session_end'],
    'pausedMs': ['round'],
    'setBlockHeartRates': ['session_end'],
    'rating': ['effort_rating'],
    'status': ['session_end'],
    'modality': ['session_end'],
  };

  /// Every code this validator can emit. PROTOCOL.md documents each one, and
  /// the fixture test fails if a code is invented without being documented.
  static const List<String> rejectionCodes = [
    _unsupportedProtocolVersion,
    _unknownMessageType,
    _missingSchema,
    _unresolvableReference,
    _missingRequiredField,
    _unexpectedField,
    _invalidType,
    _invalidEnumValue,
    _invalidConstValue,
    _constraintViolation,
    _noMatchingVariant,
    _semanticViolation,
  ];

  bool hasSchemaFor(String messageType) =>
      _documents.containsKey(_schemaPathFor(messageType));

  /// Returns an empty list when [message] conforms to protocol v1.
  List<SyncProtocolRejection> validateEnvelope(Map<String, Object?> message) {
    final type = message['type'];
    if (type is! String || !messageTypes.contains(type)) {
      return [
        SyncProtocolRejection(
          code: _unknownMessageType,
          path: '$_root.type',
          message:
              '${_describe(type)} is not one of ${jsonEncode(messageTypes)}',
        ),
      ];
    }

    final schema = _documents[_schemaPathFor(type)];
    if (schema == null) {
      return [
        SyncProtocolRejection(
          code: _missingSchema,
          path: '$_root.type',
          message: 'no schema document for message type $type',
        ),
      ];
    }

    final schemaRejections = _validate(message, schema, _root, schema);
    if (schemaRejections.isNotEmpty) {
      return schemaRejections;
    }

    // Shape is proven from here on, so the semantic layer below may read the
    // payload with narrow casts.
    return _semanticRejections(message);
  }

  /// The verdict for [message] from [validator], or an accept when the receiver
  /// carries no schema set to judge with.
  ///
  /// A build that ships without the schemas cannot tell a conformant message
  /// from a malformed one, and a receiver that cannot read is not a receiver
  /// that should refuse. Every entry point gates incoming messages through here
  /// so none of them can answer that question differently.
  static SyncMessageDecision evaluateOrAccept(
    SyncProtocolValidator? validator,
    Map<String, Object?> message,
  ) {
    final verdict = validator?.evaluateIncoming(
      message,
      receiverVersion: protocolVersion,
    );
    if (verdict != null) return verdict;

    return const SyncMessageDecision(
      decision: acceptDecision,
      reason: 'accepted',
      respondWithSnapshot: false,
      rejections: [],
    );
  }

  /// The receiver-side gate: version first, then conformance.
  ///
  /// The version check runs before validation on purpose — a payload written
  /// for another version must not be interpreted, only rejected.
  SyncMessageDecision evaluateIncoming(
    Map<String, Object?> message, {
    required int receiverVersion,
  }) {
    final version = message['protocolVersion'];
    if (version != receiverVersion) {
      return SyncMessageDecision(
        decision: rejectAndResyncDecision,
        reason:
            'a v$receiverVersion receiver cannot interpret a message that '
            'advertises ${_describe(version)}',
        respondWithSnapshot: true,
        rejections: const [
          SyncProtocolRejection(
            code: _unsupportedProtocolVersion,
            path: '$_root.protocolVersion',
            message: 'unsupported protocol version; the payload was not read',
          ),
        ],
      );
    }

    final rejections = validateEnvelope(message);
    return SyncMessageDecision(
      decision: rejections.isEmpty ? acceptDecision : rejectDecision,
      reason: rejections.isEmpty
          ? 'conforms to protocol v$protocolVersion'
          : 'rejected: ${rejections.first}',
      respondWithSnapshot: rejections.isNotEmpty,
      rejections: rejections,
    );
  }

  String _schemaPathFor(String messageType) =>
      'messages/$messageType.schema.json';

  // ---------------------------------------------------------------------------
  // Semantic layer — rules JSON Schema cannot express.
  // ---------------------------------------------------------------------------

  List<SyncProtocolRejection> _semanticRejections(
    Map<String, Object?> message,
  ) {
    final payload = _asObject(message['payload']);
    switch (message['type']) {
      case 'timer_state':
        final timers = _asObject(payload['timers']);
        return [
          ..._timerKindRejections(timers),
          ..._restLengthRejections(timers),
        ];
      case 'session_snapshot':
        final timers = payload['timers'];
        return [
          ..._snapshotRejections(payload),
          ..._restLengthRejections(timers is Map ? _asObject(timers) : null),
        ];
      case 'observations_up':
        return [
          ..._duplicateEventRejections(payload),
          ..._captureRejections(
            payload['events']! as List,
            '$_root.payload.events',
          ),
        ];
      case 'receipt':
        return _duplicateAcknowledgementRejections(payload);
      case 'routines_down':
        return _fallbackCoverageRejections(payload);
      default:
        return const [];
    }
  }

  /// A timer must declare the kind it is filed under.
  List<SyncProtocolRejection> _timerKindRejections(
    Map<String, Object?> timers,
  ) {
    final rejections = <SyncProtocolRejection>[];
    for (final kind in timerKinds) {
      final timer = timers[kind];
      if (timer is! Map || timer['kind'] == kind) continue;
      rejections.add(
        SyncProtocolRejection(
          code: _semanticViolation,
          path: '$_root.payload.timers.$kind.kind',
          message: "timer '$kind' declares kind ${_describe(timer['kind'])}",
        ),
      );
    }
    return rejections;
  }

  /// The one timer that never carries a planned length is the rest: rest is a
  /// count-up (`docs/global_conventions.md`, rest rule). A `timer_state` and a
  /// `session_snapshot` both carry `timers`, so both are held to this rule and
  /// a rest with a plan is never adopted into the wrist's own row (D-164,
  /// D-169).
  List<SyncProtocolRejection> _restLengthRejections(
    Map<String, Object?>? timers,
  ) {
    final rest = timers?['rest'];
    if (rest is! Map || rest['plannedDurationMs'] == null) return const [];
    return [
      SyncProtocolRejection(
        code: _semanticViolation,
        path: '$_root.payload.timers.rest.plannedDurationMs',
        message:
            'a rest has no planned length: rest is a count-up '
            '(docs/global_conventions.md, rest rule)',
      ),
    ];
  }

  /// Position stays inside the exercise list, slots are unique, and workout
  /// entries name the slot they were logged against.
  List<SyncProtocolRejection> _snapshotRejections(
    Map<String, Object?> payload,
  ) {
    final rejections = <SyncProtocolRejection>[];
    final exercises = payload['exercises']! as List;
    final index = payload['currentExerciseIndex']! as int;

    if (exercises.isEmpty ? index != 0 : index >= exercises.length) {
      rejections.add(
        SyncProtocolRejection(
          code: _semanticViolation,
          path: '$_root.payload.currentExerciseIndex',
          message:
              'currentExerciseIndex $index is out of range for '
              '${exercises.length} exercises',
        ),
      );
    }

    final entries = payload['entries']! as List;
    rejections.addAll(_duplicateSlotRejections(exercises));
    rejections.addAll(_entryIdentityRejections(entries));
    rejections.addAll(_captureRejections(entries, '$_root.payload.entries'));

    return rejections;
  }

  /// A slot id addresses an exercise for the life of the session, so a snapshot
  /// that reuses one is ambiguous: the receiver could not tell the two slots
  /// apart. The same `exerciseId` in two slots is legitimate and not reported.
  List<SyncProtocolRejection> _duplicateSlotRejections(
    List<Object?> exercises,
  ) {
    final seen = <String>{};
    final duplicates = <String>[];
    for (final exercise in exercises) {
      final slotId = _asObject(exercise)['sessionExerciseId']! as String;
      if (!seen.add(slotId)) duplicates.add(slotId);
    }
    if (duplicates.isEmpty) return const [];
    return [
      SyncProtocolRejection(
        code: _semanticViolation,
        path: '$_root.payload.exercises',
        message:
            'every sessionExerciseId MUST be unique within a session; '
            'repeated ${duplicates.join(', ')}',
      ),
    ];
  }

  /// A workout entry has to say both which exercise it recorded and which slot
  /// it logged in; a nutrition quick-log, an effort rating, and a session end
  /// are not tied to a slot at all.
  List<SyncProtocolRejection> _entryIdentityRejections(List<Object?> entries) {
    final withoutIdentity = <String>[];
    for (final entry in entries) {
      final record = _asObject(entry);
      if (_slotlessKinds.contains(record['kind'])) continue;
      if (!record.containsKey('exerciseId') ||
          !record.containsKey('sessionExerciseId')) {
        withoutIdentity.add(record['entryId']! as String);
      }
    }
    if (withoutIdentity.isEmpty) return const [];
    return [
      SyncProtocolRejection(
        code: _semanticViolation,
        path: '$_root.payload.entries',
        message:
            'a workout entry must name the exercise it logged and the slot '
            'it logged it in; missing on ${withoutIdentity.join(', ')}',
      ),
    ];
  }

  /// The fields the wrist computes from its own readings, held to the rules the
  /// schema cannot state: each travels only on the kinds it describes, the
  /// heart-rate pair travels whole and in order, a round's pause fits inside
  /// its window, and a session end names each set block once. `observations_up`
  /// events and snapshot entries are the same entries, so both are held to it.
  List<SyncProtocolRejection> _captureRejections(
    List<Object?> entries,
    String path,
  ) {
    final rejections = <SyncProtocolRejection>[];
    for (var index = 0; index < entries.length; index++) {
      final entry = _asObject(entries[index]);
      final at = '$path[$index]';
      final kind = entry['kind']! as String;
      final entryId = entry['entryId']! as String;

      for (final MapEntry(key: field, value: kinds)
          in _captureFieldKinds.entries) {
        if (!entry.containsKey(field) || kinds.contains(kind)) continue;
        rejections.add(
          SyncProtocolRejection(
            code: _semanticViolation,
            path: '$at.$field',
            message:
                '$field is carried only by ${kinds.join(', ')} entries; '
                '$entryId is a $kind entry',
          ),
        );
      }

      rejections.addAll(_heartRatePairRejections(entry, at, entryId));
      rejections.addAll(_distanceSourceRejections(entry, at, entryId));
      rejections.addAll(_pauseWindowRejections(entry, at, entryId));
      rejections.addAll(_blockHeartRateRejections(entry, at, entryId));
    }
    return rejections;
  }

  /// A source describes a distance, so one without the other says nothing about
  /// where a value came from that is not there.
  List<SyncProtocolRejection> _distanceSourceRejections(
    Map<String, Object?> entry,
    String path,
    String entryId,
  ) {
    if (entry['distanceSource'] == null || entry['distanceMeters'] != null) {
      return const [];
    }
    return [
      SyncProtocolRejection(
        code: _semanticViolation,
        path: '$path.distanceSource',
        message:
            'distanceSource travels with distanceMeters; '
            '$entryId carries no distanceMeters',
      ),
    ];
  }

  /// An average and a maximum describe the same readings, so one without the
  /// other is half a measurement, and an average above its maximum is not one.
  List<SyncProtocolRejection> _heartRatePairRejections(
    Map<String, Object?> record,
    String path,
    String where,
  ) {
    final average = record['avgHeartRateBpm'];
    final maximum = record['maxHeartRateBpm'];
    if (average == null && maximum == null) return const [];
    if (average is! num || maximum is! num) {
      final present = average == null ? 'maxHeartRateBpm' : 'avgHeartRateBpm';
      return [
        SyncProtocolRejection(
          code: _semanticViolation,
          path: path,
          message:
              'avgHeartRateBpm and maxHeartRateBpm travel together; '
              '$where carries only $present',
        ),
      ];
    }
    if (average <= maximum) return const [];
    return [
      SyncProtocolRejection(
        code: _semanticViolation,
        path: '$path.avgHeartRateBpm',
        message:
            'avgHeartRateBpm must not exceed maxHeartRateBpm, but does on '
            '$where',
      ),
    ];
  }

  /// A round cannot have been paused for longer than it lasted.
  List<SyncProtocolRejection> _pauseWindowRejections(
    Map<String, Object?> entry,
    String path,
    String entryId,
  ) {
    final pausedMs = entry['pausedMs'];
    final startedAt = DateTime.tryParse(entry['startedAt'] as String? ?? '');
    final endedAt = DateTime.tryParse(entry['endedAt'] as String? ?? '');
    if (pausedMs is! num || startedAt == null || endedAt == null) {
      return const [];
    }
    if (pausedMs <= endedAt.difference(startedAt).inMilliseconds) {
      return const [];
    }
    return [
      SyncProtocolRejection(
        code: _semanticViolation,
        path: '$path.pausedMs',
        message:
            'pausedMs must not exceed the time between startedAt and endedAt, '
            'but does on $entryId',
      ),
    ];
  }

  /// A set block is every set logged for one slot and exercise, so a session
  /// end names each block once, and each block's pair is a measurement.
  List<SyncProtocolRejection> _blockHeartRateRejections(
    Map<String, Object?> entry,
    String path,
    String entryId,
  ) {
    final blocks = entry['setBlockHeartRates'];
    if (blocks is! List) return const [];

    final rejections = <SyncProtocolRejection>[];
    final seen = <String>{};
    final repeated = <String>[];
    for (var index = 0; index < blocks.length; index++) {
      final block = _asObject(blocks[index]);
      final key = '${block['sessionExerciseId']}/${block['exerciseId']}';
      if (!seen.add(key)) repeated.add(key);
      rejections.addAll(
        _heartRatePairRejections(
          block,
          '$path.setBlockHeartRates[$index]',
          '$entryId set block $key',
        ),
      );
    }
    if (repeated.isNotEmpty) {
      rejections.add(
        SyncProtocolRejection(
          code: _semanticViolation,
          path: '$path.setBlockHeartRates',
          message:
              'a set block may appear once per sessionExerciseId and '
              'exerciseId pair; repeated ${repeated.join(', ')} on $entryId',
        ),
      );
    }
    return rejections;
  }

  /// One eventId may appear once per message — the idempotency key has to mean
  /// something inside a batch too.
  List<SyncProtocolRejection> _duplicateEventRejections(
    Map<String, Object?> payload,
  ) {
    final seen = <String>{};
    final duplicates = <String>[];
    for (final event in payload['events']! as List) {
      final eventId = _asObject(event)['eventId']! as String;
      if (!seen.add(eventId)) duplicates.add(eventId);
    }
    if (duplicates.isEmpty) return const [];
    return [
      SyncProtocolRejection(
        code: _semanticViolation,
        path: '$_root.payload.events',
        message: 'the same eventId appears twice: ${duplicates.join(', ')}',
      ),
    ];
  }

  /// One entry may be acknowledged once per receipt — the same id twice says
  /// nothing more the second time, and a sender that does it is confused about
  /// what it holds.
  List<SyncProtocolRejection> _duplicateAcknowledgementRejections(
    Map<String, Object?> payload,
  ) {
    final seen = <String>{};
    final duplicates = <String>[];
    for (final entryId in payload['entryIds']! as List) {
      if (!seen.add(entryId! as String)) duplicates.add(entryId);
    }
    if (duplicates.isEmpty) return const [];
    return [
      SyncProtocolRejection(
        code: _semanticViolation,
        path: '$_root.payload.entryIds',
        message: 'the same entryId appears twice: ${duplicates.join(', ')}',
      ),
    ];
  }

  /// Every exercise a routine references must be in the fallback list, or the
  /// watch can hold a routine it cannot log.
  List<SyncProtocolRejection> _fallbackCoverageRejections(
    Map<String, Object?> payload,
  ) {
    final listed = {
      for (final exercise in payload['fallbackExercises']! as List)
        _asObject(exercise)['exerciseId']! as String,
    };

    final missing = <String>[];
    for (final routine in payload['routines']! as List) {
      for (final segment in _asObject(routine)['segments']! as List) {
        for (final effort in _asObject(segment)['efforts']! as List) {
          final exerciseId = _asObject(effort)['exerciseId']! as String;
          if (!listed.contains(exerciseId) && !missing.contains(exerciseId)) {
            missing.add(exerciseId);
          }
        }
      }
    }

    if (missing.isEmpty) return const [];
    return [
      SyncProtocolRejection(
        code: _semanticViolation,
        path: '$_root.payload.fallbackExercises',
        message:
            'every exercise a routine references must be listed in '
            'fallbackExercises; missing ${missing.join(', ')}',
      ),
    ];
  }

  // ---------------------------------------------------------------------------
  // Schema layer.
  // ---------------------------------------------------------------------------

  List<SyncProtocolRejection> _validate(
    Object? value,
    Map<String, Object?> schema,
    String path,
    Map<String, Object?> document,
  ) {
    final reference = schema[r'$ref'];
    if (reference is String) {
      final resolved = _resolve(reference, document);
      if (resolved == null) {
        return [
          SyncProtocolRejection(
            code: _unresolvableReference,
            path: path,
            message: 'the reference $reference cannot be resolved',
          ),
        ];
      }
      return _validate(value, resolved.schema, path, resolved.document);
    }

    final expectedType = schema['type'];
    if (expectedType is String && !_matchesType(value, expectedType)) {
      return [
        SyncProtocolRejection(
          code: _invalidType,
          path: path,
          message: 'expected $expectedType, found ${_describe(value)}',
        ),
      ];
    }

    final rejections = <SyncProtocolRejection>[];

    if (schema.containsKey('const') && !_deepEquals(value, schema['const'])) {
      rejections.add(
        SyncProtocolRejection(
          code: _invalidConstValue,
          path: path,
          message:
              'expected ${_describe(schema['const'])}, '
              'found ${_describe(value)}',
        ),
      );
    }

    final allowed = schema['enum'];
    if (allowed is List &&
        !allowed.any((candidate) => _deepEquals(value, candidate))) {
      rejections.add(
        SyncProtocolRejection(
          code: _invalidEnumValue,
          path: path,
          message: '${_describe(value)} is not one of ${jsonEncode(allowed)}',
        ),
      );
    }

    if (value is Map) {
      rejections.addAll(_validateObject(value, schema, path, document));
    } else if (value is List) {
      rejections.addAll(_validateArray(value, schema, path, document));
    } else if (value is String) {
      rejections.addAll(_validateString(value, schema, path));
    } else if (value is num) {
      rejections.addAll(_validateNumber(value, schema, path));
    }

    // Combinators run last so a value that is simply the wrong shape reports
    // that first, instead of a wall of branch failures.
    rejections.addAll(_validateAllOf(value, schema['allOf'], path, document));
    rejections.addAll(_validateOneOf(value, schema['oneOf'], path, document));

    return rejections;
  }

  List<SyncProtocolRejection> _validateObject(
    Map<Object?, Object?> value,
    Map<String, Object?> schema,
    String path,
    Map<String, Object?> document,
  ) {
    final rejections = <SyncProtocolRejection>[];

    final required = schema['required'];
    if (required is List) {
      for (final name in required.whereType<String>()) {
        if (!value.containsKey(name)) {
          rejections.add(
            SyncProtocolRejection(
              code: _missingRequiredField,
              path: '$path.$name',
              message: 'required field "$name" is missing',
            ),
          );
        }
      }
    }

    final properties = schema['properties'];
    if (properties is! Map) return rejections;

    for (final name in properties.keys) {
      final childSchema = properties[name];
      if (name is! String || childSchema is! Map || !value.containsKey(name)) {
        continue;
      }
      rejections.addAll(
        _validate(value[name], _asObject(childSchema), '$path.$name', document),
      );
    }

    if (schema['additionalProperties'] == false) {
      for (final key in value.keys.whereType<String>()) {
        if (!properties.containsKey(key)) {
          rejections.add(
            SyncProtocolRejection(
              code: _unexpectedField,
              path: '$path.$key',
              message: 'field "$key" is not defined by the schema',
            ),
          );
        }
      }
    }

    return rejections;
  }

  List<SyncProtocolRejection> _validateArray(
    List<Object?> value,
    Map<String, Object?> schema,
    String path,
    Map<String, Object?> document,
  ) {
    final rejections = <SyncProtocolRejection>[];

    final minItems = schema['minItems'];
    if (minItems is int && value.length < minItems) {
      rejections.add(
        _constraint(
          path,
          'expected at least $minItems items, found ${value.length}',
        ),
      );
    }

    final items = schema['items'];
    if (items is Map) {
      for (var index = 0; index < value.length; index++) {
        rejections.addAll(
          _validate(value[index], _asObject(items), '$path[$index]', document),
        );
      }
    }

    return rejections;
  }

  List<SyncProtocolRejection> _validateString(
    String value,
    Map<String, Object?> schema,
    String path,
  ) {
    final rejections = <SyncProtocolRejection>[];

    final minLength = schema['minLength'];
    if (minLength is int && value.length < minLength) {
      rejections.add(
        _constraint(
          path,
          'expected at least $minLength characters, found ${value.length}',
        ),
      );
    }

    final pattern = schema['pattern'];
    if (pattern is String && !RegExp(pattern).hasMatch(value)) {
      rejections.add(
        _constraint(
          path,
          '${_describe(value)} does not match the required pattern',
        ),
      );
    }

    return rejections;
  }

  List<SyncProtocolRejection> _validateNumber(
    num value,
    Map<String, Object?> schema,
    String path,
  ) {
    final rejections = <SyncProtocolRejection>[];

    final minimum = schema['minimum'];
    if (minimum is num && value < minimum) {
      rejections.add(
        _constraint(path, 'expected at least $minimum, found $value'),
      );
    }

    final maximum = schema['maximum'];
    if (maximum is num && value > maximum) {
      rejections.add(
        _constraint(path, 'expected at most $maximum, found $value'),
      );
    }

    return rejections;
  }

  List<SyncProtocolRejection> _validateAllOf(
    Object? value,
    Object? branches,
    String path,
    Map<String, Object?> document,
  ) {
    if (branches is! List) return const [];
    return [
      for (final branch in branches)
        if (branch is Map)
          ..._validate(value, _asObject(branch), path, document),
    ];
  }

  List<SyncProtocolRejection> _validateOneOf(
    Object? value,
    Object? branches,
    String path,
    Map<String, Object?> document,
  ) {
    if (branches is! List) return const [];

    var matches = 0;
    final failures = <List<SyncProtocolRejection>>[];
    for (final branch in branches) {
      if (branch is! Map) continue;
      final branchRejections = _validate(
        value,
        _asObject(branch),
        path,
        document,
      );
      if (branchRejections.isEmpty) {
        matches++;
      } else {
        failures.add(branchRejections);
      }
    }
    if (matches == 1) return const [];

    final firstFailure = failures.isEmpty ? null : failures.first.first;
    final mismatch = firstFailure == null
        ? ''
        : ' (first mismatch: ${firstFailure.message})';
    return [
      SyncProtocolRejection(
        code: _noMatchingVariant,
        path: path,
        message:
            'value matches $matches of ${branches.length} allowed shapes'
            '$mismatch',
      ),
      // When nothing matched, the branch failures are the useful part: they say
      // which field was wrong, not just that the shape was.
      if (matches == 0) ...[for (final failure in failures) ...failure],
    ];
  }

  SyncProtocolRejection _constraint(String path, String message) =>
      SyncProtocolRejection(
        code: _constraintViolation,
        path: path,
        message: message,
      );

  /// Resolves a `$ref` to the schema it names, together with the document that
  /// schema lives in — nested `#/…` references keep resolving inside it.
  ({Map<String, Object?> schema, Map<String, Object?> document})? _resolve(
    String reference,
    Map<String, Object?> document,
  ) {
    if (reference.startsWith('#')) {
      final schema = _resolvePointer(document, reference.substring(1));
      return schema == null ? null : (schema: schema, document: document);
    }

    final hash = reference.indexOf('#');
    final documentName = hash < 0 ? reference : reference.substring(0, hash);
    final targetDocument = _documents[documentName];
    if (targetDocument == null) return null;
    if (hash < 0) return (schema: targetDocument, document: targetDocument);

    final schema = _resolvePointer(
      targetDocument,
      reference.substring(hash + 1),
    );
    return schema == null ? null : (schema: schema, document: targetDocument);
  }

  Map<String, Object?>? _resolvePointer(
    Map<String, Object?> document,
    String pointer,
  ) {
    Object? current = document;
    for (final rawSegment in pointer.split('/')) {
      if (rawSegment.isEmpty) {
        continue; // the empty segment before the first '/'
      }
      final segment = rawSegment.replaceAll('~1', '/').replaceAll('~0', '~');
      if (current is Map) {
        current = current[segment];
      } else if (current is List) {
        final index = int.tryParse(segment);
        current = (index == null || index < 0 || index >= current.length)
            ? null
            : current[index];
      } else {
        return null;
      }
      if (current == null) return null;
    }
    return current is Map ? _asObject(current) : null;
  }

  bool _matchesType(Object? value, String type) {
    switch (type) {
      case 'object':
        return value is Map;
      case 'array':
        return value is List;
      case 'string':
        return value is String;
      case 'integer':
        return value is int;
      case 'number':
        return value is num;
      case 'boolean':
        return value is bool;
      case 'null':
        return value == null;
      default:
        return true; // an unknown type keyword is not this dialect's business
    }
  }
}

Map<String, Object?> _asObject(Object? value) =>
    (value as Map).cast<String, Object?>();

String _describe(Object? value) {
  final text = jsonEncode(value);
  return text.length <= 60 ? text : '${text.substring(0, 57)}...';
}

bool _deepEquals(Object? a, Object? b) {
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || !_deepEquals(a[key], b[key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      if (!_deepEquals(a[index], b[index])) return false;
    }
    return true;
  }
  return a == b;
}
