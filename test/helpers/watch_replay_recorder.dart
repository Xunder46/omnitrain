/// The differential replay recorder — plan 152 Phase 1.
///
/// Plan: `docs/plans/2026-11-13-152-swift-replay-plan/2026-11-13-152-swift-replay-plan.md`
/// (D-15203 format, D-15204 canonicalizer, D-15205 summary, D-15206 comparison
/// rule 1, D-15207 rig, D-15209 staleness).
///
/// Four pieces, in the order a recording passes through them:
///
/// 1. [WatchPairHarness] (with `recordReplay` on) collects the raw events — the
///    frames the wrist was handed, its own actions, its kills.
/// 2. [ReplayCanonicalizer] rewrites every value the phone's real clock minted
///    into a stable alias, so two processes recording the same story produce
///    the same bytes (D-15204).
/// 3. [WristSummary] reads the wrist's observable state from the append-only
///    store by the one rule both engines' summaries mirror (D-15205).
/// 4. [ReplayReplayer] applies a recording to a fresh Dart wrist and returns the
///    same summary, which is D-15206's rule 1: a mismatch is a recorder defect.
library;

import 'dart:convert';

import 'package:omnitrain/core/sync_protocol/message_validator.dart';
import 'package:omnitrain/watch/session/in_memory_watch_session_store.dart';
import 'package:omnitrain/watch/session/watch_records.dart';
import 'package:omnitrain/watch/session/watch_session_engine.dart';
import 'package:omnitrain/watch/session/watch_session_store.dart';

import 'sync_protocol_harness.dart' show TestClock;
import 'watch_pair_harness.dart' show WatchPairHarness;

/// The recording format this file writes and reads (D-15203).
const int kReplayFormatVersion = 1;

/// One source of the corpus: `kind` is `seed` or `trace`, `name` is what the
/// file and the manifest call it.
class ReplaySource {
  const ReplaySource({required this.kind, required this.name});

  final String kind;
  final String name;
}

/// Rewrites the values the phone's real clock minted into stable aliases
/// (D-15204).
///
/// Two alias tables, keyed by the exact value:
///
/// * an **id** — a string with a digit run of ten or more, or a UUID — becomes
///   `x-<n>`, minted in first-appearance order, so an id's alias survives
///   recomposition of the same story;
/// * an **off-grid timestamp** — an ISO instant or a plausible epoch-ms number
///   the run's own clock never held — becomes
///   `gridStartMs + 1_000_000_000 + k × 1000` ms, above the whole grid span
///   so a phone stamp still sorts after every grid stamp, as it did in the real
///   run. `k` is the instant's rank among the distinct off-grid instants in
///   value order — which is send order, because a stamp is minted at the moment
///   the phone sends it — so a stamp minted earlier sorts earlier however a
///   queue reorders its frame, and two stamps that were equal stay equal.
///
/// Value order, not appearance order, for the reason the queue exists: a frame
/// that waited in the queue is delivered after a frame sent later, so ranking by
/// appearance would invert exactly the two stamps the engine compares.
///
/// The frame stamps themselves are wall-clock, by design (`watch_sync_wiring`:
/// the mirror keeps its own clock so a graph clock that stands still cannot
/// defeat snapshot order), and how many distinct instants a run mints depends on
/// the machine — two reads inside one millisecond are one value. An alias is
/// therefore not a function of the story alone, so the guards that compare two
/// recordings compare with alias instants masked.
///
/// Everything else records verbatim. [enabled] is false only in the S-15203
/// mutation proof, which has to show the scan can see the raw values.
class ReplayCanonicalizer {
  ReplayCanonicalizer({
    required this.gridStartMs,
    required Set<int> grid,
    Map<int, int> stamps = const {},
    this.enabled = true,
  }) : _grid = grid,
       _stamps = stamps;

  /// A canonicalizer whose alias table is built from every value the recording
  /// will carry.
  ///
  /// The table is collected up front rather than minted as values are met: the
  /// phone's stamps are compared by the wrist's engine for order *and* equality,
  /// and ranking the distinct instants in value order keeps both — a stamp
  /// minted earlier keeps a smaller alias even when a queue delivers its frame
  /// later. [roots] are walked in recording order — the events first, then the
  /// expected summary.
  factory ReplayCanonicalizer.forValues({
    required int gridStartMs,
    required Set<int> grid,
    required Iterable<Object?> roots,
    bool enabled = true,
  }) {
    final instants = <int>[];
    for (final root in roots) {
      _collectOffGrid(root, grid, instants);
    }
    final ordered = instants.toSet().toList()..sort();
    return ReplayCanonicalizer(
      gridStartMs: gridStartMs,
      grid: grid,
      stamps: {
        for (var rank = 0; rank < ordered.length; rank++)
          ordered[rank]: gridStartMs + stampEpochOffsetMs + rank * 1000,
      },
      enabled: enabled,
    );
  }

  final int gridStartMs;

  /// Every instant the run's own clock held (the harness's `clockGrid`).
  final Set<int> _grid;

  /// Each off-grid instant this recording carries, and the alias it reads as.
  final Map<int, int> _stamps;

  final bool enabled;

  /// The first alias instant's distance from [gridStartMs]: one thousand
  /// seconds, far above any run's own span.
  static const int stampEpochOffsetMs = 1000000000;

  /// A plausible epoch-ms instant. Below it an int is a count — reps, a
  /// duration, a revision — and records verbatim.
  static final int _epochFloor = DateTime.utc(2000).millisecondsSinceEpoch;
  static final int _epochCeiling = DateTime.utc(2100).millisecondsSinceEpoch;

  static final RegExp _digitRun = RegExp(r'[0-9]{10,}');
  static final RegExp _uuid = RegExp(
    r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}',
  );
  static final RegExp _isoShape = RegExp(r'^\d{4}-\d{2}-\d{2}T');

  final Map<String, String> _idAliases = {};

  /// How many distinct ids the recording aliased.
  int get idAliasCount => _idAliases.length;

  /// How many distinct off-grid instants the recording aliased.
  int get stampAliasCount => _stamps.length;

  /// [value] with every unstable leaf rewritten. Maps come back as
  /// `Map<String, Object?>`, so a canonical event is ready to encode.
  Object? canonicalize(Object? value) {
    if (!enabled) return value;
    if (value is String) return _canonicalString(value);
    if (value is int) return _canonicalInt(value);
    if (value is List) return [for (final item in value) canonicalize(item)];
    if (value is Map) {
      return <String, Object?>{
        for (final entry in value.entries)
          '${canonicalize('${entry.key}')}': canonicalize(entry.value),
      };
    }
    return value;
  }

  Object _canonicalString(String value) {
    if (_isoShape.hasMatch(value)) {
      final instant = DateTime.tryParse(value);
      if (instant != null) {
        final ms = instant.toUtc().millisecondsSinceEpoch;
        if (_isOnGrid(ms)) return value;
        return utcIso(
          DateTime.fromMillisecondsSinceEpoch(_alias(ms), isUtc: true),
        );
      }
    }
    if (_digitRun.hasMatch(value) || _uuid.hasMatch(value)) {
      return _idAliases.putIfAbsent(value, () => 'x-${_idAliases.length + 1}');
    }
    return value;
  }

  Object _canonicalInt(int value) {
    if (value < _epochFloor || value > _epochCeiling) return value;
    return _isOnGrid(value) ? value : _alias(value);
  }

  bool _isOnGrid(int ms) => _grid.contains(ms);

  int _alias(int ms) {
    final alias = _stamps[ms];
    if (alias == null) {
      throw StateError(
        'off-grid instant $ms was not collected before canonicalization; '
        'the alias table is built from every value the recording carries',
      );
    }
    return alias;
  }

  /// Appends every off-grid instant in [value] to [out], repeats included, in
  /// the order [canonicalize] will meet them.
  static void _collectOffGrid(Object? value, Set<int> grid, List<int> out) {
    if (value is String) {
      if (!_isoShape.hasMatch(value)) return;
      final instant = DateTime.tryParse(value);
      if (instant == null) return;
      final ms = instant.toUtc().millisecondsSinceEpoch;
      if (!grid.contains(ms)) out.add(ms);
      return;
    }
    if (value is int) {
      if (value < _epochFloor || value > _epochCeiling) return;
      if (!grid.contains(value)) out.add(value);
      return;
    }
    if (value is List) {
      for (final item in value) {
        _collectOffGrid(item, grid, out);
      }
      return;
    }
    if (value is Map) {
      for (final entry in value.entries) {
        _collectOffGrid('${entry.key}', grid, out);
        _collectOffGrid(entry.value, grid, out);
      }
    }
  }
}

/// One session's observable state (D-15205).
class SessionSummary {
  const SessionSummary({
    required this.status,
    required this.entries,
    required this.timers,
  });

  final String status;

  /// The sorted entry ids stored for the session, minus the session-end
  /// observation A-152a allowlists.
  final List<String> entries;

  /// Newest timer row per kind, as `{state, startedAtMs}`.
  final Map<String, Map<String, Object?>> timers;

  Map<String, Object?> toJson() => {
    'status': status,
    'entries': entries,
    'timers': timers,
  };
}

/// The wrist's observable state: the only thing the Dart and Swift replays
/// compare (D-15205).
///
/// One reading rule, from the append-only store and never from a projection:
/// the newest session row's status, the stored observation ids minus the
/// session-end ones, the newest timer row per kind, and the engine's held
/// session.
class WristSummary {
  const WristSummary({required this.sessions, required this.current});

  final Map<String, SessionSummary> sessions;
  final String? current;

  /// The session-end observation's id for [sessionId] (A-152a): Swift stores
  /// one, the Dart twin does not, and the summary excludes it on both sides.
  static String sessionEndId(String sessionId) => 'end-$sessionId';

  static Future<WristSummary> fromStore(
    WatchSessionStore store, {
    required String? heldSessionId,
  }) async => fromContents(await store.readAll(), heldSessionId: heldSessionId);

  static WristSummary fromContents(
    WatchStoreContents contents, {
    required String? heldSessionId,
  }) {
    final newestStatus = <String, String>{};
    for (final row in contents.sessions) {
      newestStatus[row.sessionId] = row.status;
    }
    final entries = <String, Set<String>>{};
    for (final observation in contents.observations) {
      final id = observation.sessionId;
      if (!newestStatus.containsKey(id)) continue;
      final entryId = observation.entryId;
      if (entryId == sessionEndId(id)) continue;
      entries.putIfAbsent(id, () => <String>{}).add(entryId);
    }
    final timers = <String, Map<String, Map<String, Object?>>>{};
    for (final row in contents.timers) {
      if (!newestStatus.containsKey(row.sessionId)) continue;
      timers.putIfAbsent(row.sessionId, () => {})[row.kind] = {
        'state': row.state,
        'startedAtMs': row.startedAt.millisecondsSinceEpoch,
      };
    }
    final ids = newestStatus.keys.toList()..sort();
    return WristSummary(
      current: heldSessionId,
      sessions: {
        for (final id in ids)
          id: SessionSummary(
            status: newestStatus[id]!,
            entries: (entries[id] ?? const <String>{}).toList()..sort(),
            timers: {
              for (final kind in (timers[id] ?? const {}).keys.toList()
                ..sort())
                kind: timers[id]![kind]!,
            },
          ),
      },
    );
  }

  Map<String, Object?> toJson() => {
    'current': current,
    'sessions': {
      for (final id in sessions.keys) id: sessions[id]!.toJson(),
    },
  };

  /// The summary as one comparable string: what a test asserts against
  /// `expected`.
  String get signature => jsonEncode(toJson());
}

/// Every row of a store as a comparable line, sorted — the multiset S-15202
/// compares beside the summary.
///
/// The row ids and sequence numbers are left out on purpose: they are the
/// store's bookkeeping across two rigs with different counter lifetimes, not
/// state either engine exposes.
List<String> replayRowSignatures(WatchStoreContents contents) {
  final rows = <String>[
    for (final row in contents.sessions)
      'session ${row.sessionId} status=${row.status} '
          'idx=${row.currentExerciseIndex} revision=${row.revision} '
          'startedAtMs=${row.startedAt.millisecondsSinceEpoch} '
          'recordedAtMs=${row.recordedAt.millisecondsSinceEpoch} '
          'modality=${row.modality} '
          'exercises=${jsonEncode(row.exercises)}',
    for (final row in contents.observations)
      'observation ${row.sessionId} ${row.entryId} kind=${row.kind} '
          'payload=${jsonEncode(row.payload)}',
    for (final row in contents.timers)
      'timer ${row.sessionId} ${row.kind} ${row.state} '
          'startedAtMs=${row.startedAt.millisecondsSinceEpoch} '
          'pausedAtMs=${row.pausedAt?.millisecondsSinceEpoch} '
          'stoppedAtMs=${row.stoppedAt?.millisecondsSinceEpoch} '
          'plannedDurationMs=${row.plannedDurationMs}',
  ];
  return rows..sort();
}

/// One recording: the wrist's input timeline and the state it ended in
/// (D-15203).
class ReplayRecording {
  const ReplayRecording({
    required this.source,
    required this.gridStartMs,
    required this.events,
    required this.expected,
  });

  final ReplaySource source;
  final int gridStartMs;
  final List<Map<String, Object?>> events;

  /// The wrist's summary at close, already canonicalized.
  final Map<String, Object?> expected;

  /// Records a finished run: canonicalizes its raw events and its closing
  /// summary, and pins the summary as `expected`.
  ///
  /// With [canonicalize] false the raw values pass through — the S-15203
  /// mutation proof's build, never the corpus's.
  static Future<ReplayRecording> capture(
    WatchPairHarness pair, {
    required String kind,
    required String name,
    bool canonicalize = true,
  }) async {
    final summary = await WristSummary.fromStore(
      pair.wristStore,
      heldSessionId: pair.wristEngine.session?.sessionId,
    );
    final summaryJson = summary.toJson();
    final canonicalizer = ReplayCanonicalizer.forValues(
      gridStartMs: pair.gridStartMs,
      grid: pair.clockGrid,
      roots: [pair.replayEvents, summaryJson],
      enabled: canonicalize,
    );
    return ReplayRecording(
      source: ReplaySource(kind: kind, name: name),
      gridStartMs: pair.gridStartMs,
      events: [
        for (final event in pair.replayEvents)
          canonicalizer.canonicalize(event)! as Map<String, Object?>,
      ],
      expected: _normalized(
        canonicalizer.canonicalize(summaryJson)! as Map<String, Object?>,
      ),
    );
  }

  /// The expected block with its two maps keyed and listed in canonical order:
  /// the alias tables run after the reader sorted the raw ids, so the order has
  /// to be re-established on the canonical ids the replay will produce.
  static Map<String, Object?> _normalized(Map<String, Object?> expected) {
    final sessions = (expected['sessions']! as Map).cast<String, Object?>();
    final ids = sessions.keys.toList()..sort();
    return {
      'current': expected['current'],
      'sessions': {
        for (final id in ids)
          id: _normalizedSession(sessions[id]! as Map<String, Object?>),
      },
    };
  }

  static Map<String, Object?> _normalizedSession(Map<String, Object?> session) {
    final timers = (session['timers']! as Map).cast<String, Object?>();
    final kinds = timers.keys.toList()..sort();
    return {
      'status': session['status'],
      'entries': [...?(session['entries'] as List?)?.cast<String>()]..sort(),
      'timers': {for (final kind in kinds) kind: timers[kind]},
    };
  }

  Map<String, Object?> toJson() => {
    'formatVersion': kReplayFormatVersion,
    'source': {'kind': source.kind, 'name': source.name},
    'gridStartMs': gridStartMs,
    'events': events,
    'expected': expected,
  };

  /// The checked-in form: one compact JSON event per line, so a recording reads
  /// and diffs as a timeline.
  String serialize() {
    final buffer = StringBuffer()
      ..writeln('{')
      ..writeln('  "formatVersion": $kReplayFormatVersion,')
      ..writeln(
        '  "source": ${jsonEncode({'kind': source.kind, 'name': source.name})},',
      )
      ..writeln('  "gridStartMs": $gridStartMs,')
      ..writeln('  "events": [');
    for (var index = 0; index < events.length; index++) {
      final comma = index == events.length - 1 ? '' : ',';
      buffer.writeln('    ${jsonEncode(events[index])}$comma');
    }
    final expectedText = const JsonEncoder.withIndent('  ')
        .convert(expected)
        .replaceAll('\n', '\n  ');
    buffer
      ..writeln('  ],')
      ..writeln('  "expected": $expectedText')
      ..writeln('}');
    return buffer.toString();
  }

  static ReplayRecording fromJson(Map<String, Object?> json) {
    final source = (json['source']! as Map).cast<String, Object?>();
    return ReplayRecording(
      source: ReplaySource(
        kind: source['kind']! as String,
        name: source['name']! as String,
      ),
      gridStartMs: json['gridStartMs']! as int,
      events: [
        for (final event in json['events']! as List)
          (event as Map).cast<String, Object?>(),
      ],
      expected: (json['expected']! as Map).cast<String, Object?>(),
    );
  }
}

/// What a replay ended in: the summary D-15205 reads, and the store's rows.
class ReplayResult {
  const ReplayResult({required this.summary, required this.rows});

  final WristSummary summary;

  /// [replayRowSignatures] of the replayed store.
  final List<String> rows;
}

/// Applies a recording to a fresh Dart wrist (D-15206 rule 1, D-15207's rig in
/// Dart form).
///
/// No radio, no phone, no orchestrator: the recorded frames are the whole input
/// the wrist's session surface ever saw. A `kill` builds a new engine over the
/// same store and restores it, exactly as the harness's relaunch does.
class ReplayReplayer {
  const ReplayReplayer._();

  /// Replays [recording] from its own clock grid.
  ///
  /// [validator] is the protocol validator the harness builds its engine with;
  /// passing it keeps the engine's conformance guard (an emission refused
  /// before it is stored) identical to the recorded run's.
  static Future<ReplayResult> replay(
    ReplayRecording recording, {
    SyncProtocolValidator? validator,
  }) async {
    final store = InMemoryWatchSessionStore();
    final clock = TestClock(
      DateTime.fromMillisecondsSinceEpoch(recording.gridStartMs, isUtc: true),
    );
    var recordSerial = 0;
    var sessionSerial = 0;
    late WatchSessionEngine engine;
    void launch() {
      engine = WatchSessionEngine(
        store,
        validator: validator,
        clock: clock.call,
        idFactory: () => 'rec-${++recordSerial}',
        sessionIdFactory: () => 's-w-${++sessionSerial}',
      );
    }

    launch();
    for (final event in recording.events) {
      clock.now = DateTime.fromMillisecondsSinceEpoch(
        event['clockMs']! as int,
        isUtc: true,
      );
      switch (event['t']) {
        case 'frame':
          try {
            await engine.applyMessage(
              (event['envelope']! as Map).cast<String, Object?>(),
            );
          } on WatchEmissionRejected {
            // A frame the engine refuses to answer is applied exactly as far as
            // it got in the live run: the snapshot the wrist then asked for is
            // its own recorded reply, replayed in its own place.
            continue;
          }
        case 'action':
          await _applyAction(engine, event);
        case 'kill':
          launch();
          await engine.restore();
        default:
          throw FormatException('replay event type ${event['t']}');
      }
    }
    final contents = await store.readAll();
    return ReplayResult(
      summary: WristSummary.fromContents(
        contents,
        heldSessionId: engine.session?.sessionId,
      ),
      rows: replayRowSignatures(contents),
    );
  }

  static Future<void> _applyAction(
    WatchSessionEngine engine,
    Map<String, Object?> event,
  ) async {
    switch (event['name']) {
      case 'start':
        await engine.createSession(
          modality: event['modality'] as String?,
          exercises: [
            for (final slot in (event['exercises'] as List?) ?? const [])
              (slot as Map).cast<String, Object?>(),
          ],
        );
      case 'logSet':
        await engine.appendObservation(
          (event['event']! as Map).cast<String, Object?>(),
        );
      case 'finish':
        await engine.finishSession();
      case 'discard':
        await engine.abandonSession();
      case 'restStart':
        await engine.startTimer(
          (event['kind'] as String?) ?? WatchTimerKind.rest,
        );
      default:
        throw FormatException('replay action ${event['name']}');
    }
  }
}
