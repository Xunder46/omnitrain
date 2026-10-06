// Watch logging surfaces — the four effort kinds, end to end.
//
// Plan: `docs/plans/2026-07-13-07-a2-watch-wrist-logging-surfaces-plan.md`.
// Scenario mapping:
//   S-001 log a set (reps + load)                            → `S-001 ...`
//   S-002 log timed work (duration, optional distance)       → `S-002 ...`
//   S-003 log a round                                        → `S-003 ...`
//   S-004 log a hold / drill                                 → `S-004 ...`
//   S-006 manual distance entry without GPS                  → `S-006 ...`
//   S-007 metric stepping                                    → watch_logging_stepping_test.dart
//   S-008 terminology parity with the phone                  → `S-008 ...`
//   S-062 zero still means "no load claim"                   → `S-062 ...`
//   S-063 the assist carries to the next set                 → `S-063 ...`
//   S-064 a leading minus renders in the user's unit         → `S-064 ...`
//
// Every event asserted here is validated against the shared protocol schemas
// read from the repository — the same documents the phone's validator and the
// watchOS suite use — so "identical in shape to a phone-logged equivalent" is
// the schema's verdict, not this file's opinion.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/modality_config.dart';
import 'package:omnitrain/core/constants/modality_display.dart';
import 'package:omnitrain/core/sync_protocol/message_validator.dart';
import 'package:omnitrain/watch/logging/watch_logging_screen.dart';
import 'package:omnitrain/watch/logging/watch_logging_state.dart';
import 'package:omnitrain/watch/logging/watch_metric_stepping.dart';
import 'package:omnitrain/watch/logging/watch_timer_haptics.dart';
import 'package:omnitrain/watch/session/in_memory_watch_session_store.dart';
import 'package:omnitrain/watch/session/watch_records.dart';
import 'package:omnitrain/watch/session/watch_session_engine.dart';

const String _protocolRoot = 'watch/sync_protocol';

/// Deterministic clock. Timestamps in an emitted event are asserted against
/// this, never against `DateTime.now()`.
class _Clock {
  _Clock(this.now);

  DateTime now;

  DateTime call() => now;

  void advance(Duration delta) => now = now.add(delta);
}

Map<String, Object?> _slot(String id, List<String> capabilities) => {
  'sessionExerciseId': id,
  'exerciseId': 'ex-$id',
  'name': id,
  'capabilities': capabilities,
};

/// One `session_lifecycle` from the phone — its own way of saying the session
/// is over.
Map<String, Object?> _phoneLifecycle(
  String sessionId, {
  String state = WatchLifecycleState.completed,
  String messageId = 'msg-phone-lifecycle',
}) => {
  'protocolVersion': SyncProtocolValidator.protocolVersion,
  'messageId': messageId,
  'sessionId': sessionId,
  'type': 'session_lifecycle',
  'origin': 'phone',
  'sentAt': '2026-07-13T17:01:00Z',
  'payload': {'state': state, 'at': '2026-07-13T17:01:00Z'},
};

Map<String, Object?> _asObject(Object? value) =>
    (value as Map).cast<String, Object?>();

/// Records what the screen asked the haptic channel to play, so the wiring from
/// a due countdown to the platform channel can be asserted rather than assumed.
class _RecordingHaptics implements WatchHaptics {
  final List<WatchTimerMilestone> played = [];

  @override
  void play(WatchTimerMilestone milestone) {
    played.add(milestone);
  }
}

/// The stepping, terminology and effort-kind values both watch clients are held
/// to. The watchOS suite reads this same file, so a change to the table on
/// either platform fails on both.
Map<String, Object?> _contract() => _asObject(
  jsonDecode(
    File(
      '${Directory.current.path}/watch/contract/watch_logging_contract.json',
    ).readAsStringSync(),
  ),
);

/// The shared schemas, keyed the way `$ref` addresses them.
SyncProtocolValidator _validator() {
  final root = Directory('${Directory.current.path}/$_protocolRoot/schemas');
  return SyncProtocolValidator({
    for (final file in root.listSync(recursive: true).whereType<File>())
      if (file.path.endsWith('.json'))
        file.path.substring(root.path.length + 1): jsonDecode(
          file.readAsStringSync(),
        ),
  });
}

/// A logged event, with the schema's verdict on the message that carried it.
typedef _Logged = ({
  Map<String, Object?> event,
  List<SyncProtocolRejection> rejections,
});

/// Every event the surface emitted through the engine, in order. Timer messages
/// are skipped: an effort kind that starts a countdown emits one of those too.
List<_Logged> _logged(List<Map<String, Object?>> emitted) {
  final validator = _validator();
  final events = <_Logged>[];

  for (final raw in emitted) {
    final envelope = _asObject(raw);
    if (envelope['type'] != 'observations_up') continue;
    expect(envelope['origin'], 'watch');
    final rejections = validator.validateEnvelope(envelope);
    for (final event in _asObject(envelope['payload'])['events']! as List) {
      events.add((event: _asObject(event), rejections: rejections));
    }
  }

  return events;
}

/// The event the surface logged last, validated against the shared schemas.
_Logged _emittedEvent(List<Map<String, Object?>> emitted) {
  final events = _logged(emitted);
  expect(events, isNotEmpty);
  return events.last;
}

void main() {
  late _Clock clock;
  late List<Map<String, Object?>> emitted;
  late WatchSessionEngine engine;

  Future<WatchLoggingState> surfaceFor(
    String? modality,
    Map<String, Object?> slot, {
    WatchUnitPreferences units = const WatchUnitPreferences(),
  }) async {
    engine = WatchSessionEngine(
      InMemoryWatchSessionStore(),
      clock: clock.call,
      onEmit: emitted.add,
    );
    await engine.createSession(modality: modality, exercises: [slot]);
    return WatchLoggingState(
      engine: engine,
      clock: clock.call,
      units: units,
    );
  }

  double fieldValue(WatchLoggingState surface, String metricKey) =>
      surface.fields.firstWhere((field) => field.metricKey == metricKey).value;

  WatchMetricField fieldOf(WatchLoggingState surface, String metricKey) =>
      surface.fields.firstWhere((field) => field.metricKey == metricKey);

  setUp(() {
    clock = _Clock(DateTime.utc(2026, 7, 13, 17));
    emitted = [];
  });

  group('S-001 log a set (reps + load)', () {
    test(
      'S-001 rotary values are logged as a protocol set observation',
      () async {
        final surface = await surfaceFor(
          'resistance_lifting',
          _slot('sx-bench', ['reps', 'sets', 'load']),
        );

        // The whole logging interaction: turn the crown, confirm. Load starts at
        // the effort-kind default (0 kg) and is dialled up in 2.5 kg detents.
        surface.adjust(WatchMetricKey.reps, 2);
        surface.adjust(WatchMetricKey.weight, 33);
        await surface.log();

        final logged = _emittedEvent(emitted);
        expect(logged.rejections, isEmpty);
        expect(logged.event, containsPair('kind', 'set'));
        expect(logged.event, containsPair('reps', 12));
        expect(logged.event, containsPair('loadKg', 82.5));
        expect(logged.event, containsPair('sessionExerciseId', 'sx-bench'));
        expect(logged.event, containsPair('exerciseId', 'ex-sx-bench'));
        expect(logged.event['loggedAt'], '2026-07-13T17:00:00.000Z');
      },
    );

    test(
      'S-001 the next set is presented with the values just logged',
      () async {
        final surface = await surfaceFor(
          'resistance_lifting',
          _slot('sx-bench', ['reps', 'sets', 'load']),
        );

        surface.adjust(WatchMetricKey.reps, 2);
        surface.adjust(WatchMetricKey.weight, 33);
        await surface.log();

        expect(surface.fields, hasLength(2));
        expect(fieldValue(surface, WatchMetricKey.reps), 12);
        expect(fieldValue(surface, WatchMetricKey.weight), 82.5);
      },
    );

    test('S-001 a bodyweight set carries no load at all', () async {
      final surface = await surfaceFor(
        'resistance_lifting',
        _slot('sx-pushup', ['reps', 'sets']),
      );

      expect(surface.fields.map((field) => field.metricKey), [
        WatchMetricKey.reps,
      ]);
      expect(fieldValue(surface, WatchMetricKey.reps), 10);

      await surface.log();

      final logged = _emittedEvent(emitted);
      expect(logged.rejections, isEmpty);
      expect(logged.event.containsKey('loadKg'), isFalse);
    });
  });

  group('S-062 zero still means "no load claim"', () {
    test('S-062 an assisted load is emitted with its sign', () async {
      final surface = await surfaceFor(
        'resistance_lifting',
        _slot('sx-assisted', ['reps', 'sets', 'load']),
      );

      // Eight detents down from the 0 kg default: a 20 kg band assist.
      surface.adjust(WatchMetricKey.weight, -8);
      expect(fieldValue(surface, WatchMetricKey.weight), -20);

      await surface.log();

      final logged = _emittedEvent(emitted);
      expect(logged.rejections, isEmpty);
      expect(logged.event, containsPair('loadKg', -20));
    });

    test('S-062 an untouched dial and a bodyweight set send no loadKg', () async {
      final untouched = await surfaceFor(
        'resistance_lifting',
        _slot('sx-bench', ['reps', 'sets', 'load']),
      );
      await untouched.log();
      expect(_emittedEvent(emitted).event.containsKey('loadKg'), isFalse);

      emitted.clear();
      final bodyweight = await surfaceFor(
        'resistance_lifting',
        _slot('sx-pushup', ['reps', 'sets']),
      );
      await bodyweight.log();
      expect(_emittedEvent(emitted).event.containsKey('loadKg'), isFalse);
    });

    test('S-062 a drill sends its extra load and never a loadKg', () async {
      final surface = await surfaceFor(
        'isometric_stretching',
        _slot('sx-plank', ['hold', 'time']),
      );

      surface.adjust(WatchMetricKey.extraWeight, -4);
      await surface.log();

      final logged = _emittedEvent(emitted);
      expect(logged.rejections, isEmpty);
      expect(logged.event, containsPair('extraLoadKg', -10));
      expect(logged.event.containsKey('loadKg'), isFalse);
    });
  });

  group('S-063 the assist carries to the next set', () {
    test('S-063 the next set opens at the assisted load just logged', () async {
      final surface = await surfaceFor(
        'resistance_lifting',
        _slot('sx-assisted', ['reps', 'sets', 'load']),
      );

      surface.adjust(WatchMetricKey.weight, -8);
      await surface.log();

      // The carry-over reads the stored `loadKg` back, sign and all; it must
      // not fall back to zero.
      expect(fieldValue(surface, WatchMetricKey.weight), -20);
    });
  });

  group('S-064 a leading minus renders in the user\'s unit', () {
    test('S-064 a negative load prints a leading minus in kg and lbs', () async {
      final kg = await surfaceFor(
        'resistance_lifting',
        _slot('sx-assisted', ['reps', 'sets', 'load']),
      );
      kg.adjust(WatchMetricKey.weight, -8);
      expect(fieldOf(kg, WatchMetricKey.weight).displayValue, '-20.0');
      expect(fieldOf(kg, WatchMetricKey.weight).unitLabel, 'kg');

      const pounds = WatchUnitPreferences(weightUnit: 'lbs');
      final lbs = await surfaceFor(
        'resistance_lifting',
        _slot('sx-assisted', ['reps', 'sets', 'load']),
        units: pounds,
      );
      final step = WatchMetricStepping.stepFor(
        WatchMetricKey.weight,
        units: pounds,
      );
      // Dial to exactly -20 kg, so the same load prints in the saved unit.
      lbs.adjust(WatchMetricKey.weight, -20 / step);
      expect(fieldValue(lbs, WatchMetricKey.weight), -20);
      expect(fieldOf(lbs, WatchMetricKey.weight).displayValue, '-44.1');
      expect(fieldOf(lbs, WatchMetricKey.weight).unitLabel, 'lbs');
    });

    test('S-064 a zero load never prints a signed zero', () async {
      final surface = await surfaceFor(
        'resistance_lifting',
        _slot('sx-assisted', ['reps', 'sets', 'load']),
      );

      // A fractional detent that rounds to zero must not leave a "-0.0"
      // behind: zero is zero.
      surface.adjust(WatchMetricKey.weight, -0.0001);
      expect(fieldOf(surface, WatchMetricKey.weight).displayValue, '0.0');
    });
  });

  group('S-002 log timed work (duration, optional distance)', () {
    test(
      'S-002 duration is logged as a window ending when the user logged it',
      () async {
        final surface = await surfaceFor(
          'cardio_endurance',
          _slot('sx-run', ['time', 'distance']),
        );

        expect(surface.effortKind, 'timed');
        surface.adjust(WatchMetricKey.duration, 60);
        expect(fieldValue(surface, WatchMetricKey.duration), 300);

        clock.advance(const Duration(minutes: 6));
        await surface.log();

        final logged = _emittedEvent(emitted);
        expect(logged.rejections, isEmpty);
        expect(logged.event, containsPair('kind', 'timed'));
        expect(
          logged.event,
          containsPair('startedAt', '2026-07-13T17:01:00.000Z'),
        );
        expect(
          logged.event,
          containsPair('endedAt', '2026-07-13T17:06:00.000Z'),
        );
      },
    );

    test('S-002 the next effort presents a fresh duration', () async {
      final surface = await surfaceFor(
        'cardio_endurance',
        _slot('sx-run', ['time', 'distance']),
      );

      surface.adjust(WatchMetricKey.duration, 60);
      surface.adjust(WatchMetricKey.distance, 5);
      await surface.log();

      expect(fieldValue(surface, WatchMetricKey.duration), 0);
      expect(fieldValue(surface, WatchMetricKey.distance), 0);
    });

    test(
      'S-002 an exercise that cannot cover distance offers no distance',
      () async {
        final surface = await surfaceFor(
          'cardio_endurance',
          _slot('sx-row', ['time']),
        );

        expect(surface.fields.map((field) => field.metricKey), [
          WatchMetricKey.duration,
        ]);
      },
    );
  });

  group('S-003 log a round', () {
    test('S-003 the round carries the terminology the phone uses', () async {
      final surface = await surfaceFor(
        'sports',
        _slot('sx-period', ['time', 'rounds']),
      );

      expect(surface.effortKind, 'round');
      expect(surface.roundsLabel, ModalityDisplay.getRoundsLabel('sports'));
    });

    test(
      'S-003 logging a round numbers it and starts the next countdown',
      () async {
        final surface = await surfaceFor(
          'sports',
          _slot('sx-period', ['time', 'rounds']),
        );

        expect(surface.nextRoundNumber, 1);
        await surface.log();

        final logged = _emittedEvent(emitted);
        expect(logged.rejections, isEmpty);
        expect(logged.event, containsPair('kind', 'round'));
        expect(logged.event, containsPair('roundNumber', 1));

        expect(surface.nextRoundNumber, 2);
        final countdown = engine.timerFor(WatchTimerKind.round);
        expect(countdown, isNotNull);
        expect(countdown!.plannedDurationMs, 180000);
      },
    );

    test(
      'S-003 a round that ran its countdown ends when the countdown did',
      () async {
        final surface = await surfaceFor(
          'sports',
          _slot('sx-period', ['time', 'rounds']),
        );

        await surface.log();
        final countdown = engine.timerFor(WatchTimerKind.round)!;
        final roundEnd = countdown.startedAt.add(
          Duration(milliseconds: countdown.plannedDurationMs!),
        );

        // The user looks down twenty seconds after the round is over.
        clock.advance(const Duration(seconds: 200));
        await surface.log();

        final second = _emittedEvent(emitted).event;
        expect(second, containsPair('roundNumber', 2));
        expect(
          second['endedAt'],
          utcIso(roundEnd),
          reason:
              'the round ended when its countdown did, not when it was seen',
        );
        expect(
          second['startedAt'],
          utcIso(countdown.startedAt),
          reason: 'round two is the countdown\'s own window',
        );
      },
    );
  });

  group('S-004 log a hold / drill', () {
    test('S-004 hold duration and extra load are logged together', () async {
      final surface = await surfaceFor(
        'isometric_stretching',
        _slot('sx-plank', ['hold', 'time']),
      );

      expect(surface.effortKind, 'drill');
      surface.adjust(WatchMetricKey.duration, 12);
      surface.adjust(WatchMetricKey.extraWeight, -4);

      await surface.log();

      final logged = _emittedEvent(emitted);
      expect(logged.rejections, isEmpty);
      expect(logged.event, containsPair('kind', 'hold'));
      expect(
        logged.event,
        containsPair('startedAt', '2026-07-13T16:59:00.000Z'),
      );
      expect(logged.event, containsPair('endedAt', '2026-07-13T17:00:00.000Z'));
      expect(logged.event, containsPair('extraLoadKg', -10));
    });
  });

  group('S-006 manual distance entry without GPS', () {
    test(
      'S-006 a manual distance reaches the observation with no fix needed',
      () async {
        final surface = await surfaceFor(
          'cardio_endurance',
          _slot('sx-ride', ['time', 'distance']),
        );

        surface.adjust(WatchMetricKey.duration, 120);
        surface.adjust(WatchMetricKey.distance, 4);
        await surface.log();

        final logged = _emittedEvent(emitted);
        expect(logged.rejections, isEmpty);
        expect(logged.event, containsPair('distanceMeters', 400));
      },
    );

    test('S-006 the logging layer asks no location service for anything', () {
      final sources = Directory('${Directory.current.path}/lib/watch/logging')
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'));

      for (final source in sources) {
        final text = source.readAsStringSync().toLowerCase();
        for (final dependency in const [
          'geolocator',
          'location service',
          'gps',
        ]) {
          expect(
            text.contains(dependency),
            isFalse,
            reason: '${source.path} must not depend on $dependency',
          );
        }
      }
    });
  });

  group('S-008 terminology parity with the phone', () {
    test(
      'S-008 every modality keeps the phone\'s round term on the wrist',
      () async {
        for (final modality
            in ModalityConfig.configs.keys.whereType<String>()) {
          final surface = await surfaceFor(
            modality,
            _slot('sx-round', ['time', 'rounds']),
          );

          expect(
            surface.roundsLabel,
            ModalityDisplay.getRoundsLabel(modality),
            reason: '$modality must read the same on the wrist as on the phone',
          );
          expect(
            ModalityDisplay.getRoundsLabel(modality),
            ModalityConfig.getRoundsLabel(modality),
            reason: 'the two phone-side label helpers must not disagree',
          );
        }
      },
    );

    test('S-008 free training falls back to a set surface', () async {
      final surface = await surfaceFor(
        null,
        _slot('sx-free', ['reps', 'load']),
      );

      expect(surface.effortKind, 'set');
      expect(surface.roundsLabel, ModalityDisplay.getRoundsLabel(null));
    });

    test('S-008 the shared contract carries the phone\'s own labels', () {
      final labels = (_contract()['roundsLabels']! as List)
          .cast<Map<String, Object?>>();

      for (final entry in labels) {
        expect(
          ModalityDisplay.getRoundsLabel(entry['modality'] as String?),
          entry['label'],
          reason:
              'the wrist asserts against this file, so the phone must agree '
              'with it for ${entry['modality']}',
        );
      }
    });

    test(
      'S-008 the first capability present decides the effort kind',
      () async {
        final precedence = (_contract()['capabilityPrecedence']! as List)
            .cast<String>();
        final kinds = (_contract()['effortKindByMetric']! as Map)
            .cast<String, String>();

        // Each capability in turn, leading a slot that carries every one after
        // it: the leading capability is the one that must win.
        for (var index = 0; index < precedence.length; index++) {
          final surface = await surfaceFor(
            'resistance_lifting',
            _slot('sx-$index', precedence.sublist(index)),
          );

          expect(
            surface.effortKind,
            kinds[precedence[index]],
            reason: '${precedence[index]} leads ${precedence.sublist(index)}',
          );
        }
      },
    );
  });

  group('Surfaces refuse what they cannot log', () {
    test('no session means nothing to log', () async {
      final orphan = WatchLoggingState(
        engine: WatchSessionEngine(
          InMemoryWatchSessionStore(),
          clock: clock.call,
        ),
        clock: clock.call,
      );

      expect(orphan.canLog, isFalse);
      expect(orphan.fields, isEmpty);
      expect(orphan.log, throwsStateError);
    });

    test('S-52 the wrist\'s own End closes the logging surface', () async {
      final store = InMemoryWatchSessionStore();
      final engine = WatchSessionEngine(
        store,
        clock: clock.call,
        onEmit: emitted.add,
        validator: _validator(),
      );
      await engine.createSession(
        modality: null,
        exercises: [_slot('sx-free', ['reps', 'load'])],
      );
      final surface = WatchLoggingState(engine: engine, clock: clock.call);
      await surface.log();

      await engine.finishSession();
      expect(engine.session!.status, WatchSessionStatus.completed);

      // The count after the end includes the `session_end` row the engine
      // appends; the refused log must add nothing to it.
      final afterEnd = (await store.readAll()).observations.length;

      expect(
        surface.canLog,
        isFalse,
        reason: 'a finished session is not a surface to log into',
      );
      expect(surface.fields, isEmpty);

      await expectLater(surface.log(), throwsStateError);
      expect(
        (await store.readAll()).observations.length,
        afterEnd,
        reason: 'the refused log appended no observation row',
      );
    });

    test('S-52 a session the phone ended is not a surface to log into', () async {
      final store = InMemoryWatchSessionStore();
      final engine = WatchSessionEngine(
        store,
        clock: clock.call,
        onEmit: emitted.add,
        validator: _validator(),
      );
      await engine.createSession(
        modality: null,
        exercises: [_slot('sx-free', ['reps', 'load'])],
      );
      final surface = WatchLoggingState(engine: engine, clock: clock.call);
      await surface.log();
      final sessionId = engine.session!.sessionId;

      clock.advance(const Duration(minutes: 1));
      expect(await engine.applyMessage(_phoneLifecycle(sessionId)), isTrue);
      expect(engine.session!.status, WatchSessionStatus.completed);

      final afterEnd = (await store.readAll()).observations.length;

      expect(
        surface.canLog,
        isFalse,
        reason: 'S-52 a session the phone ended is not a surface to log into',
      );
      expect(surface.fields, isEmpty);

      await expectLater(surface.log(), throwsStateError);
      expect(
        (await store.readAll()).observations.length,
        afterEnd,
        reason: 'the refused log appended no observation row',
      );
    });
  });

  group('The surface the user taps', () {
    Future<WatchLoggingState> pumpSurface(
      WidgetTester tester, {
      required String? modality,
      required Map<String, Object?> slot,
    }) async {
      final surface = await surfaceFor(modality, slot);
      await tester.pumpWidget(
        MaterialApp(home: WatchLoggingScreen(state: surface)),
      );
      await tester.pump();
      return surface;
    }

    testWidgets('two deliberate interactions log a set', (tester) async {
      final surface = await pumpSurface(
        tester,
        modality: 'resistance_lifting',
        slot: _slot('sx-bench', ['reps', 'sets', 'load']),
      );

      // One rotary turn on the reps row, then one confirm. Two interactions,
      // and the set is logged — nothing else is in the way.
      await tester.drag(
        find.text('Reps'),
        const Offset(0, -2 * WatchLoggingScreen.pointsPerDetent),
      );
      await tester.pump();

      final reps = fieldValue(surface, WatchMetricKey.reps);
      expect(reps, greaterThan(10), reason: 'the turn moved the value');

      await tester.tap(find.text('Log'));
      await tester.pump();

      final logged = _emittedEvent(emitted);
      expect(logged.rejections, isEmpty);
      expect(logged.event, containsPair('reps', reps.toInt()));
    });

    testWidgets('the surface reads in the phone\'s terms', (tester) async {
      final surface = await pumpSurface(
        tester,
        modality: 'sports',
        slot: _slot('sx-period', ['time', 'rounds']),
      );

      expect(
        find.text(ModalityDisplay.getRoundsLabel('sports')),
        findsOneWidget,
      );
      expect(find.text('Log'), findsOneWidget);
      expect(surface.canLog, isTrue);
    });

    testWidgets('half a detent is carried, not rounded off', (tester) async {
      final surface = await pumpSurface(
        tester,
        modality: 'resistance_lifting',
        slot: _slot('sx-bench', ['reps', 'sets', 'load']),
      );
      final before = fieldValue(surface, WatchMetricKey.reps);

      // Rotary input arrives as a scroll, so this is the crown's own path —
      // free of the touch slop that would swallow a sub-detent drag.
      final centre = tester.getCenter(find.text('Reps'));
      void turn(double travel) => tester.binding.handlePointerEvent(
        PointerScrollEvent(position: centre, scrollDelta: Offset(0, travel)),
      );

      const half = WatchLoggingScreen.pointsPerDetent / 2;

      turn(-half);
      await tester.pump();
      expect(
        fieldValue(surface, WatchMetricKey.reps),
        before,
        reason: 'half a detent is not a step',
      );

      turn(-half);
      await tester.pump();
      expect(
        fieldValue(surface, WatchMetricKey.reps),
        before + 1,
        reason: 'the two halves add up to the one detent the user turned',
      );
    });

    testWidgets('a due countdown reaches the injected haptic channel', (
      tester,
    ) async {
      final haptics = _RecordingHaptics();
      final surface = await surfaceFor(
        'resistance_lifting',
        _slot('sx-bench', ['reps', 'sets', 'load']),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: WatchLoggingScreen(state: surface, haptics: haptics),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Log'));
      await tester.pump();

      // The rest countdown ran while the screen did not. Coming back is the
      // moment its haptic is owed.
      clock.advance(const Duration(minutes: 5));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      expect(
        haptics.played,
        isNotEmpty,
        reason:
            'the screen must hand a due countdown to the channel it was '
            'given, not to the platform one',
      );
    });
  });

  group('Banned-framings audit', () {
    test('S-901 no coaching-theater strings in the logging surfaces', () {
      const banned = [
        'should',
        'try to',
        'consider',
        'great job',
        'warning',
        'recovery',
        'readiness',
      ];

      final files = [
        for (final root in const [
          'lib/watch/logging',
          'lib/watch/nutrition',
          'lib/watch/debug',
        ])
          ...Directory('${Directory.current.path}/$root')
              .listSync()
              .whereType<File>()
              .where((file) => file.path.endsWith('.dart')),
        // The native surfaces are new surfaces too, and their strings are read
        // by the same rule.
        for (final surface in const [
          'WatchLoggingView.swift',
          'WatchNutritionView.swift',
        ])
          File(
            '${Directory.current.path}/watch/watchos/Sources/'
            'WatchSessionEngine/$surface',
          ),
      ];
      expect(files, isNotEmpty);
      expect(
        files.where((file) => file.path.endsWith('.swift')),
        isNotEmpty,
        reason:
            'the watchOS surfaces must be scanned, not just the Flutter one',
      );

      final quoted = [RegExp(r"'([^'\n]*)'"), RegExp(r'"([^"\n]*)"')];
      for (final file in files) {
        final raw = file.readAsStringSync();
        final literals = quoted
            .expand((pattern) => pattern.allMatches(raw))
            .map((match) => match.group(1) ?? '')
            .join('\n')
            .toLowerCase();

        for (final term in banned) {
          expect(
            literals.contains(term),
            isFalse,
            reason: '${file.path} carries banned framing "$term"',
          );
        }
      }
    });
  });
}
