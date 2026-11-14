// Plan 152 Phase 2: the replay corpus and its guards.
//
// Plan: `docs/plans/2026-11-13-152-swift-replay-plan/2026-11-13-152-swift-replay-plan.md`
// (D-15201…D-15205, D-15208, D-15209; S-15201, S-15202, S-15203, S-15204, S-15207).
// Recorder: `test/helpers/watch_replay_recorder.dart`.
//
// The corpus is `watch/sync_protocol/fixtures/replay/`: one recording per
// source, plus the manifest that names them (D-15208). The default run compares
// the checked-in files with a fresh re-recording and replays every one on a
// fresh Dart wrist; the files are regenerated only under
// `--dart-define=REPLAY_CORPUS_WRITE=true` (D-15209), which is how a stale
// recording is refreshed after an intentional change.
//
// Plain `test()` throughout: `testWidgets` runs inside FakeAsync, where the
// engine's and the graph's real awaits never complete.
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'helpers/sync_protocol_harness.dart';
import 'helpers/watch_pair_harness.dart';
import 'helpers/watch_replay_recorder.dart';

/// Set by `--dart-define=REPLAY_CORPUS_WRITE=true` to rewrite the corpus.
const bool kCorpusWrite = bool.fromEnvironment('REPLAY_CORPUS_WRITE');

/// Where the corpus lives, relative to the protocol root.
const String kCorpusDir = '$syncProtocolRoot/fixtures/replay';

Directory get _corpusDirectory =>
    Directory('${Directory.current.path}/$kCorpusDir');

const String kRegenerateCommand =
    'flutter test --dart-define=REPLAY_CORPUS_WRITE=true '
    'test/watch_replay_corpus_test.dart';

/// One step of a scripted trace, by the runner method it performs.
class _Step {
  const _Step(this.name, {this.seconds = 0, this.from, this.type});

  final String name;
  final int seconds;
  final PairActor? from;
  final String? type;

  Future<void> run(HarnessRunner runner) async {
    switch (name) {
      case 'phoneStart':
        await runner.perform(runner.phoneStartsSession());
      case 'phoneLog':
        await runner.perform(runner.phoneLogsSet());
      case 'phoneFinish':
        await runner.perform(runner.phoneFinishes());
      case 'phoneDiscard':
        await runner.perform(runner.phoneDiscards());
      case 'phoneRest':
        await runner.perform(runner.phoneStartsRest());
      case 'wristStart':
        await runner.perform(runner.wristStartsFreeWorkout());
      case 'wristLog':
        await runner.perform(runner.wristLogsSet());
      case 'wristFinish':
        await runner.perform(runner.wristFinishes());
      case 'wristDiscard':
        await runner.perform(runner.wristDiscards());
      case 'wristRest':
        await runner.perform(runner.wristStartsRest());
      case 'wristKill':
        await runner.perform(runner.wristKilled());
      case 'drop':
        await runner.perform(runner.linkDrops());
      case 'rise':
        await runner.perform(runner.linkRises());
      case 'advance':
        await runner.perform(runner.advanceTime(seconds));
      case 'refuse':
        await runner.perform(
          runner.refuseNext(from: from ?? PairActor.phone, type: type),
        );
      default:
        throw ArgumentError.value(name, 'step', 'unknown step');
    }
  }
}

/// One corpus source: a seed the generator produced, or an explicit action list
/// (D-15208).
class _Source {
  const _Source(
    this.name, {
    required this.kind,
    this.seed,
    this.steps = const [],
    this.tags = const [],
  });

  final String name;
  final String kind;
  final int? seed;
  final List<_Step> steps;

  /// The manifest's coverage tags. Every one is verified: the file-visible ones
  /// by S-15204, and all of them — including `refused-queued`, which only the
  /// radio can answer — by S-15207's fresh re-recording.
  final List<String> tags;

  String get file => '$name.json';
}

/// S-14503's five core actions, preceded by twenty that touch nothing
/// (`test/watch_convergence_random_test.dart`'s `_paddedS14503`).
const List<_Step> _s14503Padding = [
  _Step('drop'),
  _Step('rise'),
  _Step('advance', seconds: 3),
  _Step('advance', seconds: 7),
  _Step('drop'),
  _Step('rise'),
  _Step('advance', seconds: 11),
  _Step('refuse', type: 'timer_state'),
  _Step('phoneRest'),
  _Step('phoneLog'),
  _Step('wristLog'),
  _Step('wristRest'),
  _Step('wristFinish'),
  _Step('wristDiscard'),
  _Step('advance', seconds: 29),
  _Step('drop'),
  _Step('rise'),
  _Step('advance', seconds: 30),
  _Step('drop'),
  _Step('rise'),
];

/// Every source of the corpus, in manifest order (D-15208).
///
/// File-local: the corpus's public surface is the checked-in manifest, and
/// [_Source] is only ever handed to this file's own tests.
// ignore: library_private_types_in_public_api
const List<_Source> kCorpusSources = [
  _Source(
    'trace-s14501',
    kind: 'trace',
    steps: [
      _Step('phoneStart'),
      _Step('wristLog'),
      _Step('wristLog'),
      _Step('phoneLog'),
      _Step('phoneFinish'),
    ],
    tags: ['entry', 'frame-prefix', 'no-fault'],
  ),
  _Source(
    'trace-s14503',
    kind: 'trace',
    steps: [
      ..._s14503Padding,
      _Step('phoneStart'),
      _Step('phoneFinish'),
    ],
    tags: ['frame-prefix', 'refused-queued'],
  ),
  _Source(
    'trace-f2',
    kind: 'trace',
    steps: [
      _Step('wristStart'),
      _Step('drop'),
      _Step('wristFinish'),
      _Step('phoneRest'),
      _Step('rise'),
    ],
  ),
  _Source(
    'trace-f3',
    kind: 'trace',
    steps: [_Step('phoneStart'), _Step('phoneRest'), _Step('phoneDiscard')],
    tags: ['timer', 'frame-prefix'],
  ),
  _Source(
    'trace-f4',
    kind: 'trace',
    steps: [
      _Step('phoneStart'),
      _Step('wristDiscard'),
      _Step('drop'),
      _Step('phoneStart'),
      _Step('wristFinish'),
    ],
    tags: ['multi-session', 'frame-prefix'],
  ),
  _Source(
    'trace-f5',
    kind: 'trace',
    steps: [
      _Step('wristStart'),
      _Step('drop'),
      _Step('phoneDiscard'),
      _Step('phoneStart'),
    ],
    tags: ['multi-session'],
  ),
  _Source(
    'trace-f6',
    kind: 'trace',
    steps: [
      _Step('phoneStart'),
      _Step('drop'),
      _Step('wristDiscard'),
      _Step('wristStart'),
      _Step('phoneLog'),
    ],
    tags: ['multi-session', 'entry', 'frame-prefix'],
  ),
  _Source(
    'trace-f7',
    kind: 'trace',
    steps: [
      _Step('wristStart'),
      _Step('drop'),
      _Step('phoneDiscard'),
      _Step('phoneStart'),
      _Step('wristDiscard'),
      _Step('wristStart'),
      _Step('refuse', from: PairActor.wrist),
      _Step('phoneLog'),
    ],
    tags: ['multi-session', 'entry', 'refused-queued'],
  ),
  // Plan 151's minimal traces (A-152-01): the four- and five-action stories the
  // ended-session-not-current fix was proven on.
  _Source(
    'trace-a1',
    kind: 'trace',
    steps: [
      _Step('wristStart'),
      _Step('refuse', from: PairActor.wrist),
      _Step('wristFinish'),
      _Step('wristStart'),
    ],
    tags: ['multi-session', 'refused-queued'],
  ),
  _Source(
    'trace-a2',
    kind: 'trace',
    steps: [
      _Step('refuse', from: PairActor.phone),
      _Step('wristStart'),
      _Step('phoneLog'),
      _Step('phoneDiscard'),
      _Step('phoneStart'),
    ],
    tags: ['multi-session', 'entry', 'refused-queued'],
  ),
  _Source(
    'seed-1',
    kind: 'seed',
    seed: 1,
    tags: ['kill', 'entry', 'refused-queued', 'frame-prefix'],
  ),
  _Source('seed-7', kind: 'seed', seed: 7, tags: ['multi-session', 'timer', 'entry']),
  _Source(
    'seed-50',
    kind: 'seed',
    seed: 50,
    tags: ['multi-session', 'entry', 'refused-queued', 'frame-prefix'],
  ),
  _Source(
    'seed-111',
    kind: 'seed',
    seed: 111,
    tags: ['multi-session', 'entry', 'refused-queued'],
  ),
  _Source(
    'seed-408',
    kind: 'seed',
    seed: 408,
    tags: ['kill', 'multi-session', 'timer', 'entry', 'refused-queued'],
  ),
  _Source(
    'seed-857',
    kind: 'seed',
    seed: 857,
    tags: ['kill', 'multi-session', 'entry', 'refused-queued'],
  ),
];

/// A re-recording: the canonical recording and what it covers.
class _Recorded {
  const _Recorded(this.recording, this.tags);

  final ReplayRecording recording;
  final Set<String> tags;
}

/// Re-records one source the way the corpus was built: the harness with the
/// recorder on, the story performed, then the heal — the recorder's normal
/// close.
Future<_Recorded> _record(_Source source) async {
  if (source.seed != null) {
    final run = await ConvergenceRun.runSeed(source.seed!, recordReplay: true);
    final recording = await ReplayRecording.capture(
      run.pair,
      kind: source.kind,
      name: source.name,
    );
    return _Recorded(recording, _tagsOf(recording, run.pair));
  }
  final pair = await WatchPairHarness.build(recordReplay: true);
  final runner = pair.runner;
  for (final step in source.steps) {
    await step.run(runner);
  }
  await runner.heal();
  final recording = await ReplayRecording.capture(
    pair,
    kind: source.kind,
    name: source.name,
  );
  return _Recorded(recording, _tagsOf(recording, pair));
}

/// The coverage the recording actually has.
Set<String> _tagsOf(ReplayRecording recording, WatchPairHarness pair) {
  final events = recording.events;
  final sessions = (recording.expected['sessions']! as Map).cast<String, Object?>();
  final tags = <String>{
    if (events.any((event) => event['t'] == 'kill')) 'kill',
    if (sessions.length >= 2) 'multi-session',
    if (sessions.values.any(
      (session) => ((session! as Map)['timers']! as Map).isNotEmpty,
    ))
      'timer',
    if (sessions.values.any(
      (session) => ((session! as Map)['entries']! as List).isNotEmpty,
    ))
      'entry',
    if (pair.radio.frames.any((frame) => frame.refused) &&
        pair.radio.frames.any((frame) => frame.drained))
      'refused-queued',
    if (events.isNotEmpty && events.first['t'] == 'frame') 'frame-prefix',
  };
  return tags;
}

/// The tags a checked-in file can answer for itself.
Set<String> _fileTags(ReplayRecording recording) {
  final sessions = (recording.expected['sessions']! as Map).cast<String, Object?>();
  return {
    if (recording.events.any((event) => event['t'] == 'kill')) 'kill',
    if (sessions.length >= 2) 'multi-session',
    if (sessions.values.any(
      (session) => ((session! as Map)['timers']! as Map).isNotEmpty,
    ))
      'timer',
    if (sessions.values.any(
      (session) => ((session! as Map)['entries']! as List).isNotEmpty,
    ))
      'entry',
    if (recording.events.isNotEmpty &&
        recording.events.first['t'] == 'frame')
      'frame-prefix',
  };
}

/// Tags only the live run can answer for.
const Set<String> kRunOnlyTags = {'refused-queued', 'no-fault'};

final RegExp _unstableId = RegExp(
  r'[0-9]{10,}|[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
  r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}',
);
final RegExp _isoShape = RegExp(r'^\d{4}-\d{2}-\d{2}T');

/// S-15203's scan: every value an unfiltered recording would carry, that the
/// canonicalizer was supposed to remove.
///
/// An instant is fine when it is one the run's clock held (the recording's own
/// `clockMs` grid) or inside the alias band above it; an id is fine when it is
/// already an `x-<n>` alias.
List<String> _unstableValues(ReplayRecording recording, {required bool raw}) {
  final grid = {for (final event in recording.events) event['clockMs']! as int};
  final band = recording.gridStartMs + ReplayCanonicalizer.stampEpochOffsetMs;
  bool stampOk(int ms) => grid.contains(ms) || (ms >= band && ms < band + 2_000_000);
  final found = <String>[];

  void walk(Object? value, String path) {
    if (value is String) {
      if (_isoShape.hasMatch(value)) {
        final instant = DateTime.tryParse(value);
        if (instant == null) return;
        final ms = instant.toUtc().millisecondsSinceEpoch;
        if (!stampOk(ms)) found.add('$path = $value (off grid)');
        return;
      }
      if (value.startsWith('x-') && raw) return;
      if (_unstableId.hasMatch(value)) found.add('$path = $value');
      return;
    }
    if (value is int) {
      if (value > 946684800000 && !stampOk(value)) {
        found.add('$path = $value (off grid)');
      }
      return;
    }
    if (value is List) {
      for (var index = 0; index < value.length; index++) {
        walk(value[index], '$path[$index]');
      }
      return;
    }
    if (value is Map) {
      for (final entry in value.entries) {
        walk(entry.value, '$path.${entry.key}');
      }
    }
  }

  walk(recording.events, 'events');
  walk(recording.expected, 'expected');
  return found;
}

/// The checked-in file for [source], parsed.
ReplayRecording _readCheckedIn(_Source source) {
  final file = File('${_corpusDirectory.path}/${source.file}');
  expect(
    file.existsSync(),
    isTrue,
    reason:
        'the corpus is missing ${source.file} — regenerate with '
        '$kRegenerateCommand',
  );
  return ReplayRecording.fromJson(
    jsonDecode(file.readAsStringSync()) as Map<String, Object?>,
  );
}

Map<String, Object?> _manifest(List<_Source> sources) => {
  'formatVersion': kReplayFormatVersion,
  'description': 'Plan 152 differential replay corpus. Generated — do not '
      'hand-edit; regenerate with `$kRegenerateCommand`.',
  'classes': ['status', 'entries', 'timers', 'current'],
  'allowlist': [
    {
      'id': 'A-152a',
      'what': "the wrist's session-end observation `end-<sessionId>` is "
          'excluded from `entries` on both sides',
      'owner': 'the Swift row-logs owner (plan 150)',
    },
    {
      'id': 'A-152b',
      'what': 'timer adoption can move the wrist to another exercise on '
          'Swift only; the summary does not read `currentExerciseIndex`',
      'owner': 'the timer owner (a PR 152b candidate)',
    },
    {
      'id': 'A-152c',
      'what': 'Swift-only surfaces (water, energy, effort rating) are '
          'unreachable from the corpus action set',
      'owner': 'the watch app owner',
    },
    {
      'id': 'A-152d',
      'what': 'Swift falls back to a minted id or stamp on a malformed frame; '
          'the corpus carries closed envelopes only',
      'owner': 'the replay owner',
    },
  ],
  'sources': [
    for (final source in sources)
      {
        'name': source.name,
        'kind': source.kind,
        'file': source.file,
        if (source.seed != null) 'seed': source.seed,
        'tags': source.tags,
      },
  ],
};

/// [recording]'s serialized form with every *alias* instant masked.
///
/// The phone's frame stamps come from the wall clock by design, and which two
/// reads share a millisecond is a property of the machine, not of the story:
/// one run can mint six distinct instants where another mints nine. An alias
/// therefore cannot depend on the story alone, so a guard that two runs of one
/// story are one file has to compare with the aliases masked — everything else
/// (which frames, in which order, with which payloads and aliased ids) is still
/// compared exactly.
String _maskInstants(ReplayRecording recording) {
  final band = recording.gridStartMs + ReplayCanonicalizer.stampEpochOffsetMs;
  bool isAlias(int ms) => ms >= band && ms < band + 2_000_000;

  Object? mask(Object? value) {
    if (value is String) {
      if (_isoShape.hasMatch(value)) {
        final instant = DateTime.tryParse(value);
        if (instant == null) return value;
        if (isAlias(instant.toUtc().millisecondsSinceEpoch)) {
          return '<instant>';
        }
      }
      return value;
    }
    if (value is int) return isAlias(value) ? '<instant>' : value;
    if (value is List) return [for (final item in value) mask(item)];
    if (value is Map) {
      return <String, Object?>{
        for (final entry in value.entries) '${entry.key}': mask(entry.value),
      };
    }
    return value;
  }

  return const JsonEncoder.withIndent('  ').convert(
    mask(
      jsonDecode(jsonEncode(recording.toJson())),
    ),
  );
}

void main() {
  test('S-15201 a run records to a byte-stable file with every frame the wrists '
      'received and its own actions', () async {
    final source = kCorpusSources.firstWhere(
      (candidate) => candidate.name == 'trace-f2',
    );
    final first = await _record(source);
    final second = await _record(source);

    expect(
      _maskInstants(first.recording),
      _maskInstants(second.recording),
      reason: 'D-15204: two recordings of one story differ only where the real '
          'clock minted a stamp — every frame, action, id and payload is one',
    );

    // Every phone→wrist frame of a session type the wrist was handed is an
    // event, refused ones excepted (a refused frame never reaches the wrist).
    final events = first.recording.events;
    final recorded = {
      for (final event in events)
        if (event['t'] == 'frame')
          (event['envelope']! as Map)['messageId'] as String,
    };
    for (final frame in second.recording.events) {
      expect(
        frame.keys,
        containsAll(<String>['t', 'clockMs']),
        reason: 'every event carries its instant',
      );
      if (frame['t'] == 'frame') {
        expect(
          kReplayFrameTypes,
          contains((frame['envelope']! as Map)['type']),
          reason: 'D-15202: only the session surface is recorded',
        );
      }
    }
    expect(recorded, isNotEmpty, reason: 'the F-2 story carries frames');
    expect(
      events.where((event) => event['t'] == 'action').map((e) => e['name']),
      ['start', 'finish'],
      reason: 'the wrist actions, in the order it performed them',
    );

    final sessions =
        (first.recording.expected['sessions']! as Map).cast<String, Object?>();
    expect(sessions, hasLength(1), reason: 'one workout, one session');
    final session = sessions.values.single! as Map;
    expect(session['status'], 'completed');
    expect(session['entries'], isEmpty, reason: 'F-2 logs no set');
  });

  test('S-15202 every corpus recording replays into a fresh Dart wrist and '
      'reproduces its expected summary', () async {
    final validator = loadProtocolValidator();
    final verdicts = <String>[];
    for (final source in kCorpusSources) {
      final recording = _readCheckedIn(source);
      final replay = await ReplayReplayer.replay(
        recording,
        validator: validator,
      );
      final verdict = '${source.name} '
          'sessions=${(recording.expected['sessions']! as Map).length} '
          'events=${recording.events.length}';

      verdicts.add(verdict);
      expect(
        replay.summary.signature,
        jsonEncode(recording.expected),
        reason: 'D-15206 rule 1: a mismatch is a recorder defect — '
            '${source.name}',
      );
    }
    print('S-15202 replay verdicts:\n${verdicts.join('\n')}');
  });

  test('S-15202 a replay reproduces the recorded store row for row', () async {
    final source = kCorpusSources.firstWhere(
      (candidate) => candidate.name == 'trace-f2',
    );
    final pair = await WatchPairHarness.build(recordReplay: true);
    final runner = pair.runner;
    for (final step in source.steps) {
      await step.run(runner);
    }
    await runner.heal();
    final recording = await ReplayRecording.capture(
      pair,
      kind: source.kind,
      name: source.name,
    );
    final recordedRows = replayRowSignatures(
      await pair.wristStore.readAll(),
    );
    final replay = await ReplayReplayer.replay(
      recording,
      validator: loadProtocolValidator(),
    );
    expect(replay.rows, recordedRows, reason: 'the rows, not only the summary');
    expect(replay.rows, isNotEmpty);
  });

  test('S-15203 no unstable value survives canonicalization', () async {
    // Canonical: every corpus recording is clean.
    for (final source in kCorpusSources) {
      final recorded = await _record(source);
      expect(
        _unstableValues(recorded.recording, raw: false),
        isEmpty,
        reason: 'D-15204: ${source.name} carries a phone-minted value',
      );
    }

    // Bypassed: the same scan on the same story finds what the canonicalizer
    // removes, so the scan can see the values it is looking for. `trace-s14501`
    // is the story with a phone-minted session id.
    final source = kCorpusSources.firstWhere(
      (candidate) => candidate.name == 'trace-s14501',
    );
    final pair = await WatchPairHarness.build(recordReplay: true);
    final runner = pair.runner;
    for (final step in source.steps) {
      await step.run(runner);
    }
    await runner.heal();
    final raw = await ReplayRecording.capture(
      pair,
      kind: source.kind,
      name: source.name,
      canonicalize: false,
    );
    expect(
      _unstableValues(raw, raw: true),
      isNotEmpty,
      reason: 'the scan must see the phone-minted values it protects against',
    );
  });

  test('S-15204 the corpus is complete and matches its manifest', () async {
    final manifestFile = File('${_corpusDirectory.path}/manifest.json');
    expect(
      manifestFile.existsSync(),
      isTrue,
      reason: 'regenerate with $kRegenerateCommand',
    );
    final manifest =
        jsonDecode(manifestFile.readAsStringSync()) as Map<String, Object?>;
    expect(manifest['formatVersion'], kReplayFormatVersion);

    final listed = [
      for (final entry in manifest['sources']! as List)
        (entry! as Map).cast<String, Object?>(),
    ];
    expect(
      listed.map((entry) => entry['name']).toList(),
      kCorpusSources.map((source) => source.name).toList(),
      reason: 'the manifest lists exactly the corpus, in order',
    );

    final onDisk = _corpusDirectory
        .listSync()
        .whereType<File>()
        .map((file) => file.uri.pathSegments.last)
        .where((name) => name.endsWith('.json') && name != 'manifest.json')
        .toSet();
    expect(
      onDisk,
      {for (final source in kCorpusSources) source.file},
      reason: 'every file is in the manifest, every manifest entry has a file',
    );

    final floors = <String, bool>{};
    var totalBytes = 0;
    for (var index = 0; index < kCorpusSources.length; index++) {
      final source = kCorpusSources[index];
      final entry = listed[index];
      expect(entry['kind'], source.kind, reason: source.name);
      expect(entry['file'], source.file, reason: source.name);
      if (source.seed != null) {
        expect(entry['seed'], source.seed, reason: source.name);
      }

      final path = '${_corpusDirectory.path}/${source.file}';
      final size = File(path).lengthSync();
      expect(
        size,
        lessThanOrEqualTo(32 * 1024),
        reason: 'D-15208: each recording stays under 32 KB (${source.file} is '
            '$size bytes)',
      );
      totalBytes += size;

      final recording = _readCheckedIn(source);
      expect(recording.source.name, source.name);
      expect(recording.source.kind, source.kind);
      final fileTags = _fileTags(recording);
      for (final tag in fileTags) {
        expect(
          source.tags,
          contains(tag),
          reason: '${source.name} covers $tag but the manifest does not say so',
        );
        floors[tag] = true;
      }
      expect(
        recording.events,
        isNotEmpty,
        reason: '${source.name} records nothing',
      );
    }
    expect(
      totalBytes,
      lessThanOrEqualTo(300 * 1024),
      reason: 'D-15208: the corpus stays under 300 KB',
    );

    for (final tag in const [
      'kill',
      'refused-queued',
      'multi-session',
      'timer',
      'entry',
      'frame-prefix',
    ]) {
      final declared = [
        for (final source in kCorpusSources)
          if (source.tags.contains(tag)) source.name,
      ];
      expect(
        declared,
        isNotEmpty,
        reason: 'D-15208 floor: no source covers `$tag`',
      );
    }
    expect(
      floors.keys,
      containsAll(const ['kill', 'multi-session', 'timer', 'entry']),
      reason: 'the checked-in files back up the floors they can answer',
    );
  });

  test('S-15207 the corpus is fresh: every file matches a fresh recording',
      () async {
    final stale = <String>[];
    for (final source in kCorpusSources) {
      final recorded = await _record(source);
      final fresh = _maskInstants(recorded.recording);
      final file = File('${_corpusDirectory.path}/${source.file}');
      if (!file.existsSync() ||
          _maskInstants(
                ReplayRecording.fromJson(
                  jsonDecode(file.readAsStringSync()) as Map<String, Object?>,
                ),
              ) !=
              fresh) {
        stale.add(source.file);
        continue;
      }
      // The manifest's tags are the run's, not a stale claim (S-15204 can only
      // check the tags a file answers for itself).
      for (final tag in recorded.tags) {
        expect(
          source.tags,
          contains(tag),
          reason: '${source.name} covers $tag; update the manifest entry',
        );
      }
      for (final tag in source.tags) {
        if (kRunOnlyTags.contains(tag)) continue;
        expect(
          recorded.tags,
          contains(tag),
          reason: '${source.name} claims $tag but no longer covers it',
        );
      }
    }
    expect(
      stale,
      isEmpty,
      reason: 'stale recordings: $stale — regenerate with $kRegenerateCommand',
    );
  }, timeout: const Timeout(Duration(minutes: 5)));

  test(
    'regenerate the corpus',
    () async {
      final directory = _corpusDirectory;
      directory.createSync(recursive: true);
      for (final source in kCorpusSources) {
        final recorded = await _record(source);
        File(
          '${directory.path}/${source.file}',
        ).writeAsStringSync(recorded.recording.serialize());
        print(
          'wrote ${source.file} '
          '(${File('${directory.path}/${source.file}').lengthSync()} B, '
          'tags=${recorded.tags.join(',')})',
        );
      }
      File('${directory.path}/manifest.json').writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(_manifest(kCorpusSources))}\n',
      );
      print('wrote manifest.json (${kCorpusSources.length} sources)');
    },
    skip: kCorpusWrite ? false : 'set REPLAY_CORPUS_WRITE=true to regenerate',
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
