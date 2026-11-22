// The Wear wrist's judge of a logged set against the phone's standing bests
// (plan 288, D-28803..D-28807).
//
// Scenario mapping:
//   S-28810  no frame: no verdict                                  → `S-28810 ...`
//   S-28811  strict greater-than on the weight axis, Epley order   → `S-28811 ...`
//   S-28812  an exercise absent from the frame: first-ever record  → `S-28812 ...`
//   S-28813  an empty frame is a frame                             → `S-28813 ...`
//   S-28814  unloaded, assisted and zero-load sets use the reps axis → `S-28814 ...`
//   S-28815  only a set with reps and an exercise is a claim       → `S-28815 ...`
//   S-28816  the same set never celebrates twice                   → `S-28816 ...`
//   S-28817  a set is folded even while no frame is held           → `S-28817 ...`
//   S-28818  the estimate counts at most 12 reps                   → `S-28818 ...`
//   S-28819  an older frame is dropped                             → `S-28819 ...`
//   S-28820  a tie applies, an unchanged frame writes nothing      → `S-28820 ...`
//   S-28821  an unreadable frame is refused whole                  → `S-28821 ...`
//   S-28822  a relaunch restores the frame and rebuilds the own best → `S-28822 ...`
//   S-28823  two frames applied together: the newer decides        → `S-28823 ...`
//   S-28824  the schema validator is consulted                     → `S-28824 ...`
//
// Plain `test()` throughout: the state layer, no widgets, the in-memory store.
// S-28822 repeats its round-trip over Hive, the way
// `test/watch_phone_preferences_test.dart` S-28307 does.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:omnitrain/core/sync_protocol/message_validator.dart';
import 'package:omnitrain/watch/logging/watch_personal_bests.dart';
import 'package:omnitrain/watch/session/hive_watch_session_store.dart';
import 'package:omnitrain/watch/session/in_memory_watch_session_store.dart';
import 'package:omnitrain/watch/session/watch_records.dart';
import 'package:omnitrain/watch/session/watch_session_engine.dart';
import 'package:omnitrain/watch/session/watch_session_store.dart';

const String _t0 = '2026-11-22T09:00:00Z';
const String _tBefore = '2026-11-22T08:59:00Z';
const String _tAfter = '2026-11-22T09:01:00Z';
const String _tLater = '2026-11-22T10:00:00Z';

const String _protocolRoot = 'watch/sync_protocol';

/// The shared schemas, keyed the way `$ref` addresses them. The keys use `/`
/// on every platform: `file.path` has `\` on Windows and the validator looks the
/// schema up by `messages/<type>.schema.json`.
SyncProtocolValidator _validator() {
  final root = Directory('${Directory.current.path}/$_protocolRoot/schemas');
  return SyncProtocolValidator({
    for (final file in root.listSync(recursive: true).whereType<File>())
      if (file.path.endsWith('.json'))
        file.path.substring(root.path.length + 1).replaceAll(r'\', '/'):
            jsonDecode(file.readAsStringSync()),
  });
}

/// A `bests_down` envelope in the shape the valid fixtures carry
/// (`watch/sync_protocol/fixtures/valid/bests_down.json`).
Map<String, Object?> _envelope({
  String messageId = 'msg-bests',
  Object? generatedAt = _t0,
  Object? bests = const <Object?>[],
  Map<String, Object?> extra = const {},
}) => {
  'protocolVersion': 1,
  'messageId': messageId,
  'type': 'bests_down',
  'origin': 'phone',
  'sentAt': _t0,
  'payload': {'generatedAt': ?generatedAt, 'bests': ?bests, ...extra},
};

Map<String, Object?> _entry(String id, {Object? e1rmKg, Object? repsBest}) => {
  'exerciseId': id,
  'e1rmKg': ?e1rmKg,
  'repsBest': ?repsBest,
};

/// Epley in the phone's operation order: what a frame would carry for a set.
double _e1rm(double loadKg, int reps) => loadKg * (1 + reps / 30.0);

class _Rig {
  _Rig({WatchSessionStore? store, SyncProtocolValidator? validator})
    : store = store ?? InMemoryWatchSessionStore() {
    bests = WatchPersonalBests(store: this.store, validator: validator);
  }

  final WatchSessionStore store;
  late final WatchPersonalBests bests;

  Future<bool> apply(Map<String, Object?> envelope) =>
      bests.applyBestsDown(envelope);

  bool set(String exerciseId, int reps, {double? loadKg}) => bests.noteLogged(
    kind: WatchObservationKind.set,
    exerciseId: exerciseId,
    reps: reps,
    loadKg: loadKg,
  );

  Future<List<String>> storedIds() async => [
    for (final row in (await store.readAll()).bests) row.recordId,
  ];
}

void main() {
  test('S-28810 a wrist with no frame gives no verdict', () {
    final rig = _Rig();

    expect(rig.bests.hasFrame, isFalse);
    expect(rig.set('ex-bench', 5, loadKg: 200), isFalse);
    expect(rig.set('ex-push-up', 40), isFalse);
  });

  test(
    'S-28811 a set must be strictly greater, in the phone\'s Epley order',
    () async {
      final rig = _Rig();
      await rig.apply(
        _envelope(bests: [_entry('ex-bench', e1rmKg: _e1rm(80, 5))]),
      );

      expect(rig.set('ex-bench', 5, loadKg: 80), isFalse, reason: 'equal');
      expect(rig.set('ex-bench', 5, loadKg: 79), isFalse, reason: 'below');
      expect(rig.set('ex-bench', 5, loadKg: 85), isTrue, reason: 'above');
    },
  );

  test('S-28811b an equal set compares equal bit for bit', () async {
    // 20 x 4 and 20 x 5 are loads where `w * (1 + r / 30.0)` and
    // `w + w * r / 30.0` differ in the last bit, one each way.
    for (final reps in [4, 5]) {
      final rig = _Rig();
      await rig.apply(
        _envelope(bests: [_entry('ex-bench', e1rmKg: _e1rm(20, reps))]),
      );

      expect(
        rig.set('ex-bench', reps, loadKg: 20),
        isFalse,
        reason: '20 kg x $reps equals the frame it was computed for',
      );
    }
  });

  test(
    'S-28812 an exercise absent from the frame is a first-ever record',
    () async {
      final rig = _Rig();
      await rig.apply(
        _envelope(bests: [_entry('ex-bench', e1rmKg: _e1rm(80, 5))]),
      );

      expect(rig.set('ex-squat', 5, loadKg: 60), isTrue);
      expect(rig.set('ex-squat', 5, loadKg: 60), isFalse, reason: 'folded');
    },
  );

  test(
    'S-28813 an empty frame is a frame: every first set is a record',
    () async {
      final rig = _Rig();

      expect(await rig.apply(_envelope()), isTrue);

      expect(rig.bests.hasFrame, isTrue);
      expect(rig.set('ex-bench', 3, loadKg: 40), isTrue);
    },
  );

  test(
    'S-28814 unloaded, assisted and zero-load sets use the reps axis',
    () async {
      final rig = _Rig();
      await rig.apply(_envelope(bests: [_entry('ex-push-up', repsBest: 12)]));

      expect(rig.set('ex-push-up', 12), isFalse);
      expect(rig.set('ex-push-up', 13), isTrue);
      expect(rig.set('ex-push-up', 14, loadKg: -20), isTrue, reason: 'assist');
      expect(rig.set('ex-push-up', 15, loadKg: 0), isTrue, reason: 'zero load');
      expect(rig.set('ex-push-up', 15, loadKg: 0), isFalse, reason: 'folded');
    },
  );

  test('S-28815 only a set with reps and an exercise is a claim', () async {
    final rig = _Rig();
    await rig.apply(_envelope());

    for (final claim in [
      (kind: WatchObservationKind.timed, id: 'ex-run', reps: 5),
      (kind: WatchObservationKind.round, id: 'ex-run', reps: 5),
      (kind: WatchObservationKind.set, id: 'ex-run', reps: 0),
      (kind: WatchObservationKind.set, id: '', reps: 5),
    ]) {
      expect(
        rig.bests.noteLogged(
          kind: claim.kind,
          exerciseId: claim.id,
          reps: claim.reps,
          loadKg: 50,
        ),
        isFalse,
        reason: '$claim',
      );
    }
    expect(rig.set('ex-run', 5, loadKg: 50), isTrue, reason: 'nothing folded');
  });

  test('S-28816 the same set never celebrates twice', () async {
    final rig = _Rig();
    await rig.apply(_envelope(bests: [_entry('ex-bench', e1rmKg: 100)]));

    expect(rig.set('ex-bench', 5, loadKg: 110), isTrue);
    expect(rig.set('ex-bench', 5, loadKg: 110), isFalse);
    expect(rig.set('ex-bench', 5, loadKg: 105), isFalse, reason: 'below own');
  });

  test('S-28817 a set is folded even while no frame is held', () async {
    final rig = _Rig();
    expect(rig.set('ex-bench', 5, loadKg: 120), isFalse, reason: 'no frame');

    await rig.apply(_envelope(bests: [_entry('ex-bench', e1rmKg: 100)]));

    expect(
      rig.set('ex-bench', 5, loadKg: 120),
      isFalse,
      reason: 'the wrist already held that set',
    );
  });

  test('S-28818 the estimate counts at most 12 reps', () async {
    final rig = _Rig();
    await rig.apply(
      _envelope(bests: [_entry('ex-bench', e1rmKg: _e1rm(50, 12))]),
    );

    expect(rig.set('ex-bench', 12, loadKg: 50), isFalse);
    expect(
      rig.set('ex-bench', 20, loadKg: 50),
      isFalse,
      reason: 'twenty reps count as twelve',
    );
  });

  test('S-28819 an older frame is dropped', () async {
    final rig = _Rig();
    await rig.apply(
      _envelope(messageId: 'msg-new', bests: [_entry('ex-bench', e1rmKg: 100)]),
    );

    final applied = await rig.apply(
      _envelope(
        messageId: 'msg-old',
        generatedAt: _tBefore,
        bests: [_entry('ex-bench', e1rmKg: 50)],
      ),
    );

    expect(applied, isFalse);
    expect(await rig.storedIds(), ['bests-msg-new']);
    expect(
      rig.set('ex-bench', 1, loadKg: 90),
      isFalse,
      reason: 'the newer frame (100) still decides, not the older (50)',
    );
  });

  test('S-28820 a tie applies and an unchanged frame writes nothing', () async {
    final rig = _Rig();
    await rig.apply(
      _envelope(messageId: 'msg-1', bests: [_entry('ex-bench', e1rmKg: 100)]),
    );

    final tie = await rig.apply(
      _envelope(messageId: 'msg-2', bests: [_entry('ex-bench', e1rmKg: 120)]),
    );
    final same = await rig.apply(
      _envelope(messageId: 'msg-3', bests: [_entry('ex-bench', e1rmKg: 120)]),
    );

    expect(tie, isTrue, reason: 'stamped the same moment: the later applies');
    expect(same, isFalse, reason: 'the same numbers');
    expect(await rig.storedIds(), ['bests-msg-2']);
    expect(
      rig.set('ex-bench', 5, loadKg: 100),
      isFalse,
      reason: 'decided by 120, not 100',
    );
  });

  test('S-28821 an unreadable frame is refused whole', () async {
    final rig = _Rig();
    await rig.apply(
      _envelope(
        messageId: 'msg-good',
        bests: [_entry('ex-bench', e1rmKg: 100)],
      ),
    );

    final bad = <Map<String, Object?>>[
      _envelope(bests: [_entry('', e1rmKg: 100)]),
      _envelope(
        bests: [
          {'e1rmKg': 100},
        ],
      ),
      _envelope(bests: [_entry('ex-a')]),
      _envelope(bests: [_entry('ex-a', e1rmKg: 0)]),
      _envelope(bests: [_entry('ex-a', e1rmKg: 'heavy')]),
      _envelope(bests: [_entry('ex-a', repsBest: 15.0)]),
      _envelope(bests: [_entry('ex-a', repsBest: true)]),
      _envelope(bests: [_entry('ex-a', repsBest: 0)]),
      _envelope(
        bests: [_entry('ex-ok', e1rmKg: 90), _entry('ex-a', repsBest: -3)],
      ),
      _envelope(bests: 'not a list'),
      _envelope(generatedAt: 'yesterday'),
    ];
    for (var i = 0; i < bad.length; i++) {
      bad[i]['messageId'] = 'msg-bad-$i';
      (bad[i]['payload']! as Map<String, Object?>)['generatedAt'] ??= _tLater;
      if ((bad[i]['payload']! as Map<String, Object?>)['generatedAt'] == _t0) {
        (bad[i]['payload']! as Map<String, Object?>)['generatedAt'] = _tLater;
      }
      expect(await rig.apply(bad[i]), isFalse, reason: 'bad frame #$i');
    }

    expect(await rig.storedIds(), ['bests-msg-good']);
    expect(rig.set('ex-bench', 5, loadKg: 80), isFalse, reason: 'still 100');
    expect(rig.set('ex-ok', 5, loadKg: 10), isTrue, reason: 'not half-read');
  });

  Future<void> restoreRoundTrip(WatchSessionStore store) async {
    final first = _Rig(store: store);
    await first.apply(
      _envelope(messageId: 'msg-r', bests: [_entry('ex-bench', e1rmKg: 100)]),
    );
    final engine = WatchSessionEngine(
      store,
      clock: () => DateTime.utc(2026, 11, 22, 9, 30),
    );
    await engine.createSession(
      modality: 'resistance_lifting',
      exercises: [
        {
          'sessionExerciseId': 'sx-bench',
          'exerciseId': 'ex-bench',
          'name': 'Bench Press',
          'capabilities': ['reps', 'sets', 'load'],
        },
      ],
    );
    await engine.appendObservation({
      'entryId': 'held-1',
      'eventId': 'held-1',
      'kind': WatchObservationKind.set,
      'loggedAt': '2026-11-22T09:30:00Z',
      'sessionExerciseId': 'sx-bench',
      'exerciseId': 'ex-bench',
      'reps': 5,
      'loadKg': 120,
    });
    // An effort that is not a set carries no claim, whatever else it holds.
    await engine.appendObservation({
      'entryId': 'held-2',
      'eventId': 'held-2',
      'kind': WatchObservationKind.round,
      'loggedAt': '2026-11-22T09:31:00Z',
      'sessionExerciseId': 'sx-bench',
      'exerciseId': 'ex-bench',
      'reps': 5,
      'loadKg': 200,
    });

    final fresh = _Rig(store: store);
    expect(
      fresh.bests.hasFrame,
      isFalse,
      reason: 'the premise: before restore',
    );
    await fresh.bests.restore();

    expect(fresh.bests.hasFrame, isTrue);
    expect(
      fresh.set('ex-bench', 5, loadKg: 110),
      isFalse,
      reason: 'below the set the wrist already holds, though above the frame',
    );
    expect(
      fresh.set('ex-bench', 5, loadKg: 150),
      isTrue,
      reason: 'above the held set (140); the round is not a set',
    );
    expect(fresh.set('ex-squat', 5, loadKg: 60), isTrue, reason: 'first-ever');
  }

  test(
    'S-28822 a relaunch restores the frame and rebuilds the own best',
    () async {
      await restoreRoundTrip(InMemoryWatchSessionStore());
    },
  );

  test('S-28822 (Hive) the same round trip over Hive', () async {
    final tempDir = await Directory.systemTemp.createTemp('watch_bests_pb_');
    Hive.init(tempDir.path);
    try {
      await restoreRoundTrip(HiveWatchSessionStore());
    } finally {
      await Hive.close();
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    }
  });

  test('S-28825 a restore over two stored frames reads the newest', () async {
    // A kill between a frame's append and its prune leaves two rows.
    WatchBestsRecord row(String id, DateTime at, double e1rm) =>
        WatchBestsRecord(
          recordId: id,
          recordedAt: at,
          generatedAt: at,
          entries: [
            {'exerciseId': 'ex-bench', 'e1rmKg': e1rm},
          ],
        );

    final byTime = InMemoryWatchSessionStore();
    await byTime.append(row('b-new', DateTime.utc(2026, 11, 22, 10), 100));
    await byTime.append(row('b-old', DateTime.utc(2026, 11, 22, 9), 50));
    final first = _Rig(store: byTime);
    await first.bests.restore();
    expect(
      first.set('ex-bench', 1, loadKg: 90),
      isFalse,
      reason:
          'the newer generatedAt (100) decides, not the later-appended (50)',
    );

    final tie = InMemoryWatchSessionStore();
    final at = DateTime.utc(2026, 11, 22, 9);
    await tie.append(row('b-1', at, 100));
    await tie.append(row('b-2', at, 120));
    final second = _Rig(store: tie);
    await second.bests.restore();
    expect(
      second.set('ex-bench', 5, loadKg: 100),
      isFalse,
      reason: 'a tie goes to the later-appended frame (120)',
    );
  });

  test(
    'S-28823 two frames applied together: the newer decides in either order',
    () async {
      for (final newerFirst in [true, false]) {
        final rig = _Rig();
        final older = _envelope(
          messageId: 'msg-old',
          generatedAt: _t0,
          bests: [_entry('ex-bench', e1rmKg: 50)],
        );
        final newer = _envelope(
          messageId: 'msg-new',
          generatedAt: _tAfter,
          bests: [_entry('ex-bench', e1rmKg: 100)],
        );

        await Future.wait([
          for (final frame in newerFirst ? [newer, older] : [older, newer])
            rig.apply(frame),
        ]);

        expect(
          rig.set('ex-bench', 1, loadKg: 90),
          isFalse,
          reason: 'newerFirst=$newerFirst: decided by the newer frame (100)',
        );
        expect(
          await rig.storedIds(),
          ['bests-msg-new'],
          reason: 'newerFirst=$newerFirst: only the newer row is kept',
        );
      }
    },
  );

  test('S-28824 the schema validator is consulted', () async {
    final validator = _validator();
    for (final name in [
      'bests_down',
      'bests_down_empty',
      'bests_down_both_axes',
    ]) {
      final fixture =
          jsonDecode(
                File(
                  '$_protocolRoot/fixtures/valid/$name.json',
                ).readAsStringSync(),
              )
              as Map<String, Object?>;
      final rig = _Rig(validator: validator);

      expect(await rig.apply(fixture), isTrue, reason: name);
      expect(rig.bests.hasFrame, isTrue, reason: name);
    }

    final rig = _Rig(validator: validator);
    final refused = await rig.apply(
      _envelope(
        bests: [_entry('ex-bench', e1rmKg: 100)],
        extra: {'unexpected': 1},
      ),
    );

    expect(refused, isFalse, reason: 'the schema is closed');
    expect(await rig.storedIds(), isEmpty);
    expect(rig.bests.hasFrame, isFalse);
  });
}
