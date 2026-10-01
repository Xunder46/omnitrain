// The Dart half of the capture contract: what the phone holds after importing
// each F-CAP case, on both repositories (S-272).
//
// Plan: `docs/plans/2026-09-25-02-stats-pr2-watch-capture-plan.md`
// (Stats PR 2), Phase 3b.
// Scenario mapping:
//   S-272 Hive ↔ Mock parity of every imported row → `S-272 ...`
//
// The contract (`watch/contract/watch_capture_contract.json`) is shared with
// the wrist: its `expectedEvents` are what a wrist emits, and `expectedImport`
// is what this suite holds the phone to. Each case is imported on
// `MockWorkoutRepository` and on `HiveWorkoutRepository` (a temp directory,
// read back after a restart), and the two must agree row for row by `toMap`.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/hive_workout_repository.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/state/watch/watch_session_inbox.dart';

import 'helpers/sync_protocol_harness.dart';
import 'helpers/watch_capture_import_harness.dart';

const String _capId = 's-cap-1';

final DateTime _phoneNow = DateTime.utc(2026, 9, 25, 11);

/// Stand-in for the path_provider channel, which has no implementation under
/// `flutter_test` (same pattern as `test/watch_capture_repository_parity_test.dart`).
class _PathProviderChannel {
  static const MethodChannel _channel = MethodChannel(
    'plugins.flutter.io/path_provider',
  );
  static late Directory _root;

  static void install(Directory root) {
    _root = root;
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          switch (call.method) {
            case 'getApplicationDocumentsDirectory':
            case 'getApplicationSupportDirectory':
            case 'getTemporaryDirectory':
              return _root.path;
            default:
              return null;
          }
        });
  }
}

/// One repository implementation, reopened over the same storage as an app
/// restart would.
abstract class _Store {
  String get name;
  Future<WorkoutRepository> open();
  Future<WorkoutRepository> restart();
  Future<void> close();
}

class _MockStore implements _Store {
  MockWorkoutRepository? _repository;

  @override
  String get name => 'Mock';

  @override
  Future<WorkoutRepository> open() async {
    final repository = MockWorkoutRepository();
    await repository.initialize();
    return _repository = repository;
  }

  @override
  Future<WorkoutRepository> restart() async => _repository!;

  @override
  Future<void> close() async {}
}

class _HiveStore implements _Store {
  Directory? _dir;

  @override
  String get name => 'Hive';

  @override
  Future<WorkoutRepository> open() async {
    final dir = await Directory.systemTemp.createTemp('watch_capture_import_');
    _dir = dir;
    _PathProviderChannel.install(dir);
    Hive.init(dir.path);
    final repository = HiveWorkoutRepository();
    await repository.initialize();
    return repository;
  }

  @override
  Future<WorkoutRepository> restart() async {
    await Hive.close();
    final repository = HiveWorkoutRepository();
    await repository.initialize();
    return repository;
  }

  @override
  Future<void> close() async {
    await Hive.deleteFromDisk();
    final dir = _dir;
    if (dir != null && await dir.exists()) await dir.delete(recursive: true);
  }
}

/// Imports [events] one envelope each into a fresh [store], reads the result
/// back after a restart, and answers what the phone holds and receipted.
Future<({Map<String, Object?> rows, List<String> receipted})> _import(
  _Store store,
  List<Map<String, Object?>> events, {
  Future<void> Function(WorkoutRepository repository, List<String> receipted)?
  check,
}) async {
  final repository = await store.open();
  await seedCaptureCatalog(repository);
  final transport = CaptureTransport();
  var ids = 0;
  final inbox = WatchSessionInbox(
    repository: repository,
    transport: transport,
    validator: loadProtocolValidator(),
    clock: () => _phoneNow,
    idFactory: () => 'msg-phone-${++ids}',
    onFailure: Error.throwWithStackTrace,
  );
  for (var i = 0; i < events.length; i++) {
    await inbox.receive(
      observationsUp(_capId, [events[i]], messageId: 'msg-$i'),
    );
  }

  final reopened = await store.restart();
  await check?.call(reopened, transport.receiptedEntryIds);
  final rows = await importedRows(reopened, _capId);
  await store.close();
  return (rows: rows, receipted: transport.receiptedEntryIds);
}

void main() {
  for (final store in <_Store Function()>[_MockStore.new, _HiveStore.new]) {
    final name = store().name;
    group('S-272 $name imports the contract', () {
      for (final caseName in const ['full', 'no-sensors', 'prompt-off']) {
        test('S-272 $name $caseName: expectedImport, read back after a '
            'restart', () async {
          await _import(
            store(),
            captureEvents(caseName),
            check: (repository, receipted) => expectCaptureImport(
              repository,
              captureExpectedImport(caseName),
              receiptedEntryIds: receipted,
              reasonPrefix: 'S-272 $name $caseName',
            ),
          );
        });
      }

      test(
        'S-272 $name updateEffort replaces the effort with that id',
        () async {
          final s = store();
          final repository = await s.open();
          const at = 1790000000000;
          await repository.createSession(
            TrainingSession(
              id: 's-order',
              ownerUserId: 'user-1',
              startedAtMs: at,
              endedAtMs: at + 1,
              createdAtMs: at,
              updatedAtMs: at,
            ),
          );
          await repository.createSegment(
            SessionSegment(
              id: 'seg-order',
              sessionId: 's-order',
              orderIndex: 0,
              segmentType: 'workout',
              createdAtMs: at,
              updatedAtMs: at,
            ),
          );
          SegmentEffort effort(String id, int order, {int created = at}) =>
              SegmentEffort(
                id: id,
                segmentId: 'seg-order',
                orderIndex: order,
                topLevelOrderIndex: order,
                effortKind: 'set',
                exerciseId: 'ex-bench',
                createdAtMs: created,
                updatedAtMs: created,
              );
          await repository.createEffort(effort('eff-a', 0));
          await repository.createEffort(effort('eff-b', 1));

          await repository.updateEffort(effort('eff-b', 0, created: at - 5));
          await repository.updateEffort(effort('eff-a', 1));
          await repository.updateEffort(effort('eff-missing', 2));

          final reopened = await s.restart();
          final efforts = await reopened.getSegmentEfforts('seg-order');
          expect(
            [for (final e in efforts) e.id],
            ['eff-b', 'eff-a'],
            reason: 'S-272 $name: the order it is given is the order it keeps',
          );
          expect(
            efforts.first.createdAtMs,
            at - 5,
            reason: 'S-272 the given createdAt is kept',
          );
          expect(
            efforts.map((e) => e.id),
            isNot(contains('eff-missing')),
            reason: 'S-272 $name: an unknown id is not created',
          );
          await s.close();
        },
      );
    });
  }

  group('S-272 Hive and Mock hold the same rows', () {
    final events = captureEvents('full');
    final cases = {
      for (final caseName in const ['full', 'no-sensors', 'prompt-off'])
        caseName: captureEvents(caseName),
      // Reversed arrival re-ranks efforts and re-indexes entries as they
      // come in, which is where the two repositories could part.
      'full, reversed': events.reversed.toList(),
    };
    for (final entry in cases.entries) {
      test('S-272 ${entry.key}: every created row is equal by toMap', () async {
        final mock = await _import(_MockStore(), entry.value);
        final hive = await _import(_HiveStore(), entry.value);

        expect(
          hive.rows,
          equals(mock.rows),
          reason: 'S-272 ${entry.key}: Hive and Mock agree row for row',
        );
        expect(
          hive.receipted.toSet(),
          mock.receipted.toSet(),
          reason: 'S-272 the same receipt union',
        );
        expect(
          (mock.rows['efforts']! as List),
          isNotEmpty,
          reason: 'S-272 the comparison is over an imported session',
        );
      });
    }
  });

  group('F-2 concurrent frames settle one at a time', () {
    // The wrist sends one observations_up per stored observation, and the
    // real transport (`lib/core/platform/watch_transport.dart`) dispatches
    // each frame without waiting for the last one's handler. `_settle` must
    // serialise those passes itself, because nothing upstream of it does.
    for (final store in <_Store Function()>[_MockStore.new, _HiveStore.new]) {
      final name = store().name;
      for (final order in const ['contract', 'reversed']) {
        test(
          'F-2 $name $order: F-CAP frames sent without awaiting settle '
          "exactly once, in the contract's order",
          () async {
            final s = store();
            final repository = await s.open();
            await seedCaptureCatalog(repository);
            final transport = CaptureTransport();
            var ids = 0;
            final inbox = WatchSessionInbox(
              repository: repository,
              transport: transport,
              validator: loadProtocolValidator(),
              clock: () => _phoneNow,
              idFactory: () => 'msg-phone-${++ids}',
              onFailure: Error.throwWithStackTrace,
            );
            final events = order == 'contract'
                ? captureEvents('full')
                : captureEvents('full').reversed.toList();

            // Fired without awaiting between them, the way the transport
            // delivers a wrist's back-to-back sync.
            await Future.wait([
              for (var i = 0; i < events.length; i++)
                inbox.receive(
                  observationsUp(_capId, [events[i]], messageId: 'msg-$i'),
                ),
            ]);

            final reopened = await s.restart();
            await expectCaptureImport(
              reopened,
              captureExpectedImport('full'),
              receiptedEntryIds: transport.receiptedEntryIds,
              reasonPrefix: 'F-2 $name $order',
            );
            await s.close();
          },
        );
      }
    }
  });
}
