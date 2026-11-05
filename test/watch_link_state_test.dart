// The watch link state: what the phone says about the watch, and when it last
// heard from it.
//
// Plan: `docs/plans/2026-10-21-47c-watch-status-on-phone-plan/2026-10-21-47c-watch-status-on-phone-plan.md`
// (D-1, D-2). Scenario mapping:
//   S-6901 phase per WatchLinkInfo            → `S-6901 ...`
//   S-6902 the labels                         → `S-6902 ...`
//   S-6903 persistence on a heard event       → `S-6903 ...`
//   S-6904 initialize reads the stored value  → `S-6904 ...`
//   S-6905 changes and refresh                → `S-6905 ...`
//   S-6906 a failing preference read is thrown by initialize
//         → `S-6906 ...` (plan 47c review)
//   S-6907 a failed write escapes nowhere    → `S-6907 ...` (plan 47c review)

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/platform/watch_link_info.dart';
import 'package:omnitrain/core/platform/watch_link_source.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/state/watch/watch_link_state.dart';

/// A fixed instant, in local time, the labels are measured against.
final DateTime _now = DateTime(2026, 10, 21, 12);

const WatchLinkInfo _connected = WatchLinkInfo(
  paired: true,
  appInstalled: true,
  reachable: true,
);

class _Source implements WatchLinkSource {
  WatchLinkInfo infoValue = _connected;
  Object? infoError;

  final StreamController<WatchLinkInfo> changes =
      StreamController<WatchLinkInfo>.broadcast();
  final StreamController<DateTime> heardEvents =
      StreamController<DateTime>.broadcast();

  int infoReads = 0;

  @override
  Future<WatchLinkInfo> linkInfo() async {
    infoReads++;
    final error = infoError;
    if (error != null) throw error;
    return infoValue;
  }

  @override
  Stream<WatchLinkInfo> get linkChanges => changes.stream;

  @override
  Stream<DateTime> get heard => heardEvents.stream;

  Future<void> close() async {
    await changes.close();
    await heardEvents.close();
  }
}

class _RecordingRepository extends MockWorkoutRepository {
  final Map<String, int> writesByKey = <String, int>{};

  int get lastHeardWrites => writesByKey[WatchLinkState.lastHeardKey] ?? 0;

  @override
  Future<void> setPreferenceString(String key, String value) async {
    writesByKey[key] = (writesByKey[key] ?? 0) + 1;
    await super.setPreferenceString(key, value);
  }
}

/// A repository whose preference read always fails, as a storage failure would
/// leave it: the contract the wiring wraps.
class _UnreadableRepository extends _RecordingRepository {
  @override
  Future<String?> getPreferenceString(
    String key, {
    String? defaultValue,
  }) async {
    throw StateError('preferences are unreadable');
  }
}

/// A repository whose preference write always fails.
class _UnwritableRepository extends _RecordingRepository {
  int writeAttempts = 0;

  @override
  Future<void> setPreferenceString(String key, String value) async {
    writeAttempts++;
    throw StateError('preferences are unwritable');
  }
}

/// Lets queued stream events and unawaited writes run.
Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  late _Source source;
  late _RecordingRepository repository;
  late DateTime clockNow;
  late WatchLinkState state;
  late int notifications;

  WatchLinkState build() => WatchLinkState(
    source: source,
    repository: repository,
    clock: () => clockNow,
  );

  setUp(() async {
    source = _Source();
    repository = _RecordingRepository();
    await repository.initialize();
    clockNow = _now;
    notifications = 0;
  });

  tearDown(() async {
    state.dispose();
    await source.close();
  });

  group('S-6901 the phase follows what the watch reports', () {
    test('S-6901 a phone with no watch paired reads notPaired', () async {
      source.infoValue = const WatchLinkInfo(
        paired: false,
        appInstalled: false,
        reachable: false,
      );
      state = build();
      await state.initialize();

      expect(state.phase, WatchLinkPhase.notPaired);
    });

    test('S-6901 a paired watch without the app reads appNotInstalled, even '
        'when it is out of reach', () async {
      source.infoValue = const WatchLinkInfo(
        paired: true,
        appInstalled: false,
        reachable: false,
      );
      state = build();
      await state.initialize();

      expect(state.phase, WatchLinkPhase.appNotInstalled);
    });

    test(
      'S-6901 a paired watch with the app out of reach reads notReachable',
      () async {
        source.infoValue = const WatchLinkInfo(
          paired: true,
          appInstalled: true,
          reachable: false,
        );
        state = build();
        await state.initialize();

        expect(state.phase, WatchLinkPhase.notReachable);
      },
    );

    test(
      'S-6901 a paired, installed, reachable watch reads connected',
      () async {
        state = build();
        await state.initialize();

        expect(state.phase, WatchLinkPhase.connected);
      },
    );

    test('S-6901 before the first answer the phase is notReachable', () async {
      source.infoError = StateError('the radio has not answered');
      state = build();
      await state.initialize();

      expect(state.phase, WatchLinkPhase.notReachable);
    });
  });

  group('S-6902 the labels', () {
    test('S-6902 each phase has its status label', () async {
      source.infoValue = const WatchLinkInfo(
        paired: false,
        appInstalled: false,
        reachable: false,
      );
      state = build();
      await state.initialize();
      expect(state.statusLabel, 'Not paired');

      source.infoValue = const WatchLinkInfo(
        paired: true,
        appInstalled: false,
        reachable: false,
      );
      await state.refresh();
      expect(state.statusLabel, 'Watch app not installed');

      source.infoValue = const WatchLinkInfo(
        paired: true,
        appInstalled: true,
        reachable: false,
      );
      await state.refresh();
      expect(state.statusLabel, 'Not reachable');

      source.infoValue = _connected;
      await state.refresh();
      expect(state.statusLabel, 'Connected');
    });

    test(
      'S-6902 lastSyncedLabel with nothing heard reads Never synced',
      () async {
        state = build();
        await state.initialize();

        expect(state.lastSyncedLabel(_now), 'Never synced');
      },
    );

    test('S-6902 lastSyncedLabel boundaries read as the table says', () async {
      final cases = <Duration, String>{
        const Duration(seconds: 59): 'Last synced just now',
        const Duration(seconds: 60): 'Last synced 1 min ago',
        const Duration(minutes: 59): 'Last synced 59 min ago',
        const Duration(minutes: 60): 'Last synced 1 h ago',
        const Duration(hours: 23): 'Last synced 23 h ago',
        const Duration(hours: 24): 'Last synced 1 d ago',
        const Duration(days: 6): 'Last synced 6 d ago',
      };

      for (final entry in cases.entries) {
        await repository.setPreferenceString(
          WatchLinkState.lastHeardKey,
          _now.subtract(entry.key).toUtc().millisecondsSinceEpoch.toString(),
        );
        final labeled = build();
        await labeled.initialize();
        expect(labeled.lastSyncedLabel(_now), entry.value);
        labeled.dispose();
      }
      // tearDown disposes the shared state, so leave a live one behind.
      state = build();
      await state.initialize();
    });

    test('S-6902 a week old reads the date, day and English month', () async {
      state = build();
      await repository.setPreferenceString(
        WatchLinkState.lastHeardKey,
        DateTime(2026, 10, 12, 9).toUtc().millisecondsSinceEpoch.toString(),
      );
      await state.initialize();

      expect(
        state.lastSyncedLabel(DateTime(2026, 10, 21, 12)),
        'Last synced 12 Oct',
      );
    });

    test('S-6902 a future instant reads just now', () async {
      state = build();
      final future = _now.add(const Duration(minutes: 5));
      await repository.setPreferenceString(
        WatchLinkState.lastHeardKey,
        future.toUtc().millisecondsSinceEpoch.toString(),
      );
      await state.initialize();

      expect(state.lastSyncedLabel(_now), 'Last synced just now');
    });
  });

  group('S-6903 a heard frame', () {
    test('S-6903 sets lastHeard, notifies and persists once', () async {
      state = build();
      await state.initialize();
      state.addListener(() => notifications++);

      final heard = DateTime.utc(2026, 10, 21, 12);
      source.heardEvents.add(heard);
      await _settle();

      expect(state.lastHeard, heard);
      expect(notifications, 1);
      expect(repository.lastHeardWrites, 1);
      expect(
        await repository.getPreferenceString(WatchLinkState.lastHeardKey),
        heard.millisecondsSinceEpoch.toString(),
      );
    });

    test('S-6903 a second frame inside persistEvery notifies but does not '
        'write, and one after it writes again', () async {
      state = build();
      await state.initialize();
      state.addListener(() => notifications++);

      source.heardEvents.add(DateTime.utc(2026, 10, 21, 12));
      await _settle();
      expect(repository.lastHeardWrites, 1);

      clockNow = _now.add(const Duration(seconds: 10));
      source.heardEvents.add(DateTime.utc(2026, 10, 21, 12, 1));
      await _settle();
      expect(notifications, 2);
      expect(repository.lastHeardWrites, 1);

      clockNow = _now.add(const Duration(seconds: 40));
      source.heardEvents.add(DateTime.utc(2026, 10, 21, 12, 2));
      await _settle();
      expect(notifications, 3);
      expect(repository.lastHeardWrites, 2);
      expect(
        await repository.getPreferenceString(WatchLinkState.lastHeardKey),
        DateTime.utc(2026, 10, 21, 12, 2).millisecondsSinceEpoch.toString(),
      );
    });
  });

  group('S-6904 initialize', () {
    test('S-6904 reads the stored last heard value', () async {
      final stored = DateTime.utc(2026, 10, 20, 9);
      await repository.setPreferenceString(
        WatchLinkState.lastHeardKey,
        stored.millisecondsSinceEpoch.toString(),
      );

      state = build();
      await state.initialize();

      expect(state.lastHeard, stored);
    });

    test('S-6904 a garbage stored string reads as null', () async {
      await repository.setPreferenceString(WatchLinkState.lastHeardKey, 'soon');

      state = build();
      await state.initialize();

      expect(state.lastHeard, isNull);
    });
  });

  group('S-6905 link changes and refresh', () {
    test('S-6905 a linkChanges event updates the phase and notifies', () async {
      state = build();
      await state.initialize();
      state.addListener(() => notifications++);
      expect(state.phase, WatchLinkPhase.connected);

      source.changes.add(
        const WatchLinkInfo(paired: true, appInstalled: true, reachable: false),
      );
      await _settle();

      expect(state.phase, WatchLinkPhase.notReachable);
      expect(notifications, 1);
    });

    test('S-6905 refresh re-reads the link', () async {
      state = build();
      await state.initialize();
      expect(state.phase, WatchLinkPhase.connected);

      source.infoValue = const WatchLinkInfo(
        paired: true,
        appInstalled: true,
        reachable: false,
      );
      await state.refresh();

      expect(state.phase, WatchLinkPhase.notReachable);
    });

    test('S-6905 a throwing linkInfo keeps the previous phase', () async {
      state = build();
      await state.initialize();
      expect(state.phase, WatchLinkPhase.connected);
      final reads = source.infoReads;

      source.infoError = StateError('the radio is down');
      await state.refresh();

      expect(source.infoReads, reads + 1);
      expect(state.phase, WatchLinkPhase.connected);
    });
  });

  // 47c review: the wiring builds the link defensively, so initialize() may
  // throw and the caller wraps it. This pins the contract it wraps.
  group('S-6906 a failing preference read', () {
    test('S-6906 initialize lets the read failure through', () async {
      final unreadable = _UnreadableRepository();
      await unreadable.initialize();
      state = WatchLinkState(
        source: source,
        repository: unreadable,
        clock: () => clockNow,
      );

      await expectLater(state.initialize(), throwsA(isA<StateError>()));
    });
  });

  // 47c review: a failed write means the stamp is not remembered across a
  // restart. It must not surface as an uncaught error.
  group('S-6907 a failing persist write', () {
    test('S-6907 a heard frame still updates, notifies, and escapes nowhere',
        () async {
      final unwritable = _UnwritableRepository();
      await unwritable.initialize();
      final localSource = _Source();
      addTearDown(localSource.close);
      final local = WatchLinkState(
        source: localSource,
        repository: unwritable,
        clock: () => clockNow,
      );
      state = local;
      await local.initialize();
      local.addListener(() => notifications++);

      final heard = DateTime.utc(2026, 10, 21, 12);
      final escaped = <Object>[];
      await runZonedGuarded(() async {
        localSource.heardEvents.add(heard);
        await _settle();
      }, (error, stack) => escaped.add(error));

      expect(local.lastHeard, heard);
      expect(notifications, 1);
      expect(unwritable.writeAttempts, 1);
      expect(escaped, isEmpty);
    });
  });
}
