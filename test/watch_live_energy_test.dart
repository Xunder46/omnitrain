// plan 135 P2 — the wrist's `energy_live` reaches the phone (S-13503 .. S-13507).
//
// Plan: `docs/plans/2026-11-09-135-watch-calories-on-phone-plan/
// 2026-11-09-135-watch-calories-on-phone-plan.md`, items 1-2.
//
// Mock-only `test()`s — no `testWidgets`, no real waits. The holder tests run
// against `WatchLiveEnergy` alone; the graph tests build exactly the harness
// `test/watch_timer_push_test.dart` builds (the `_PhoneRadio` copy), so an
// `energy_live` frame is delivered the way the platform channel delivers one.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/platform/watch_delivery.dart';
import 'package:omnitrain/core/platform/watch_transport.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/state/food_library_state.dart';

import 'package:omnitrain/state/nutrition_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/watch/watch_live_energy.dart';
import 'package:omnitrain/state/watch/watch_sync_wiring.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:omnitrain/watch/session/in_memory_watch_session_store.dart';
import 'package:omnitrain/watch/session/watch_session_engine.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/watch_capture_import_harness.dart' show seedExercise;

final DateTime _now = DateTime.utc(2026, 11, 9, 12);

/// The session the wrist runs in the graph scenarios.
const String _sessionId = 's-13501';

/// One timed slot on the wrist ladder.
const String _slotId = 'sx-run';

/// Lets the radio's dispatch settle before the next frame is handed over.
Future<void> _settle() => pumpEventQueue();

Map<String, Object?> _asObject(Object? value) =>
    (value as Map).cast<String, Object?>();

/// One `energy_live` frame as the wrist sends it (D-13501). The default
/// instant is `12:00:00`; scenarios move only [at], [kcal] or the ids.
Map<String, Object?> _energyFrame({
  String sessionId = _sessionId,
  double kcal = 42.5,
  String at = '2026-11-09T12:00:00Z',
  String type = 'energy_live',
  String origin = 'watch',
}) => {
  'protocolVersion': 1,
  'messageId': 'msg-energy-$sessionId-$kcal-$type-$origin-$at',
  'sessionId': sessionId,
  'type': type,
  'origin': origin,
  'sentAt': at,
  'payload': {'activeEnergyKcal': kcal, 'at': at},
};

/// A catalog the phone can adopt a timed slot for.
Future<void> _seedCatalog(WorkoutRepository repository) async {
  await seedExercise(
    repository,
    id: 'ex-run',
    name: 'Run',
    capabilities: ['time', 'distance'],
  );
}

/// One ladder slot as the protocol spells it: a timed exercise.
Map<String, Object?> _slot() => <String, Object?>{
  'sessionExerciseId': _slotId,
  'exerciseId': 'ex-run',
  'name': 'Run',
  'effortKind': 'timed',
  'capabilities': ['time', 'distance'],
};

/// The phone's radio, the minimum copy of `test/watch_timer_push_test.dart`'s:
/// records what the phone sent, hands the phone one frame from the wrist the
/// way the platform channel does. This plan's paths must not fail, so the
/// failure hook only drops the report.
class _PhoneRadio implements WatchTransport {
  final void Function(Object error) onFailure;

  _PhoneRadio(this.onFailure);

  /// Every frame handed to `send`, including the ones it then failed: the
  /// frame an unreachable wrist never receives is still visible here.
  final List<Map<String, Object?>> attempted = [];

  final List<Map<String, Object?>> sent = [];

  /// True while the wrist is out of range: `send` carries nothing and answers
  /// `undelivered` without a failure.
  bool unreachable = false;

  WatchInboundHandler? _handler;

  @override
  bool get isPhoneReachable => true;

  @override
  void onIncoming(WatchInboundHandler handler) => _handler = handler;

  @override
  Future<void> refreshReachability() async {}

  @override
  Future<void> requestRoutines({DateTime? since}) async => send({});

  @override
  Future<void> requestSnapshot() async => send({});

  @override
  Future<WatchDelivery> send(Map<String, Object?> envelope) async {
    attempted.add(envelope);
    if (unreachable) return WatchDelivery.undelivered;
    sent.add(envelope);
    return WatchDelivery.delivered;
  }

  /// One frame from the wrist, the way the radio delivers one.
  Future<void> fromWrist(Map<String, Object?> frame) async {
    final handler = _handler;
    if (handler == null) {
      throw StateError('the phone graph never bound its inbound handler');
    }
    await handler(frame);
  }
}

void main() {
  group('S-13503/S-13504/S-13505 the holder', () {
    late WatchLiveEnergy holder;

    setUp(() => holder = WatchLiveEnergy());

    test('S-13503 a valid frame sets latest', () {
      holder.receive(_energyFrame());
      expect(
        holder.latest.value,
        (sessionId: _sessionId, kcal: 42.5, at: DateTime.utc(2026, 11, 9, 12)),
      );
    });

    test('S-13504a an origin "phone" frame is ignored', () {
      holder.receive(_energyFrame(origin: 'phone'));
      expect(holder.latest.value, isNull);
    });

    test('S-13504b a timer_state frame is ignored', () {
      holder.receive(_energyFrame(type: 'timer_state'));
      expect(holder.latest.value, isNull);
    });

    test('S-13504c a negative kcal is ignored', () {
      holder.receive(_energyFrame(kcal: -1));
      expect(holder.latest.value, isNull);
    });

    test('S-13504d a NaN kcal is ignored', () {
      holder.receive(_energyFrame(kcal: double.nan));
      expect(holder.latest.value, isNull);
    });

    test('S-13504e a string kcal is ignored', () {
      final frame = _energyFrame();
      frame['payload'] = {'activeEnergyKcal': '12', 'at': frame['sentAt']};
      holder.receive(frame);
      expect(holder.latest.value, isNull);
    });

    test('S-13504f a frame without at is ignored', () {
      final frame = _energyFrame();
      frame['payload'] = {'activeEnergyKcal': 42.5};
      holder.receive(frame);
      expect(holder.latest.value, isNull);
    });

    test('S-13504g an empty sessionId is ignored', () {
      holder.receive(_energyFrame(sessionId: ''));
      expect(holder.latest.value, isNull);
    });

    test('S-13504h an at without a UTC marker is ignored', () {
      holder.receive(_energyFrame(at: '2026-11-09T12:00:00'));
      expect(holder.latest.value, isNull);
    });

    test('S-13504i an at with a space instead of the T is ignored', () {
      holder.receive(_energyFrame(at: '2026-11-09 12:00:00Z'));
      expect(holder.latest.value, isNull);
    });

    test('S-13505 an older frame for the same session is ignored, another '
        'session replaces', () {
      holder.receive(_energyFrame(at: '2026-11-09T12:00:05Z', kcal: 42.5));
      // An older reading of the same session: ignored, whatever its value.
      holder.receive(_energyFrame(at: '2026-11-09T12:00:00Z', kcal: 10));
      expect(
        holder.latest.value,
        (
          sessionId: _sessionId,
          kcal: 42.5,
          at: DateTime.utc(2026, 11, 9, 12, 0, 5),
        ),
      );
      // The same instant again: not newer, ignored.
      holder.receive(_energyFrame(at: '2026-11-09T12:00:05Z', kcal: 3));
      expect(
        holder.latest.value,
        (
          sessionId: _sessionId,
          kcal: 42.5,
          at: DateTime.utc(2026, 11, 9, 12, 0, 5),
        ),
      );
      // A different session id replaces the held value.
      holder.receive(_energyFrame(sessionId: 's-13502', kcal: 7));
      expect(
        holder.latest.value,
        (sessionId: 's-13502', kcal: 7, at: DateTime.utc(2026, 11, 9, 12)),
      );
    });
  });

  group('S-13506/S-13507 the graph routes energy_live in the wiring', () {
    late MockWorkoutRepository repository;
    late WorkoutState phoneState;
    late SettingsState phoneSettings;
    late _PhoneRadio radio;
    late WatchSyncGraph graph;
    late WatchSessionEngine engine;

    setUp(() async {
      repository = MockWorkoutRepository();
      await repository.initialize();
      await _seedCatalog(repository);

      phoneState = WorkoutState(repository);
      phoneSettings = SettingsState(repository, fakePreferencesService());
      await phoneSettings.initialize();

      radio = _PhoneRadio((_) {});
      final created = await createWatchSync(
        repository: repository,
        nutritionState: NutritionState(repository),
        foodLibraryState: FoodLibraryState(repository),
        settingsState: phoneSettings,
        transport: radio,
        clock: () => _now,
      );
      graph = created!;
      // The app binds its own state to the adoption once built (D-2), as
      // `lib/main.dart` does; the fixture needs it to adopt the wrist start.
      graph.adoption.bindWorkoutState(phoneState);

      engine = WatchSessionEngine(
        InMemoryWatchSessionStore(),
        clock: () => _now,
        sessionIdFactory: () => _sessionId,
        onEmit: (_) {},
      );
    });

    /// The wrist starts [_sessionId] with one timed slot, and the phone
    /// adopts it: the fixture the graph scenarios run from.
    Future<void> wristStartsTimedSession() async {
      await engine.createSession(modality: null, exercises: [_slot()]);
      final snapshot = engine.sessionSnapshot();
      if (snapshot == null) {
        fail('the fixture: the wrist engine holds a snapshot');
      }
      await radio.fromWrist(_asObject(snapshot));
      await _settle();
      expect(
        phoneState.currentSession?.id,
        _sessionId,
        reason: "the fixture: the phone's own session is the wrist's",
      );
    }

    test('S-13506 an energy frame while a phone change is owed sends nothing '
        'back and leaves the mirror alone', () async {
      await wristStartsTimedSession();
      graph.autoPush.bindWorkoutState(phoneState);
      graph.timerPush.bindWorkoutState(phoneState);

      // The phone owes the wrist a change (its started interval), but the
      // wrist is out of reach: the owed timer frame is attempted and dropped,
      // and stays owed (D-202).
      radio.unreachable = true;
      await phoneState.startTimedEntry(_slotId, 0);
      await graph.timerPush.flush();
      await _settle();
      expect(
        radio.attempted,
        isNotEmpty,
        reason: 'the fixture: a phone change is owed',
      );
      final attemptedBefore = radio.attempted.length;
      final mirrorBefore = Map<String, Object?>.from(graph.mirror.state);

      // The wrist sends its energy frame. The wiring routes it (D-13521):
      // the holder reads it, nothing is sent back because of it, and the
      // mirror's snapshot is untouched.
      await radio.fromWrist(_energyFrame(at: '2026-11-09T12:00:05Z'));
      await _settle();

      expect(
        graph.liveEnergy.latest.value,
        (
          sessionId: _sessionId,
          kcal: 42.5,
          at: DateTime.utc(2026, 11, 9, 12, 0, 5),
        ),
      );
      expect(
        radio.attempted.length,
        attemptedBefore,
        reason: 'the energy frame must not trigger any send to the wrist',
      );
      expect(
        graph.mirror.state,
        mirrorBefore,
        reason: 'the energy frame must not move the mirror',
      );
    });

    test('S-13507 an energy frame on the transport reaches the holder and '
        'gets no answer', () async {
      final answeredBefore = radio.attempted.length;
      await radio.fromWrist(_energyFrame());
      await _settle();

      expect(
        graph.liveEnergy.latest.value,
        (sessionId: _sessionId, kcal: 42.5, at: DateTime.utc(2026, 11, 9, 12)),
      );
      expect(
        radio.attempted.length,
        answeredBefore,
        reason: 'the validator must not have rejected the frame: a rejection '
            'would answer the wrist',
      );
    });
  });
}
