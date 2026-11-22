// The Wear wrist's sensor source over its platform channels (plan 297,
// D-29701..D-29703).
//   S-29701 a permission answer maps to the three states, per method
//   S-29702 every failure reads as unavailable
//   S-29703 the heart-rate stream yields numbers only and survives an error
//   S-29704 the location stream yields cumulative metres
//   (S-29705, the no-op workout store, was replaced by plan 300's real store)

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:omnitrain/watch/sensors/watch_sensor_recording.dart';
import 'package:omnitrain/watch/sensors/wear_sensor_source.dart';

const MethodChannel _methods = MethodChannel(WearSensorSource.methodsName);
const EventChannel _heart = EventChannel(WearSensorSource.heartRateName);
const EventChannel _location = EventChannel(WearSensorSource.locationName);

TestDefaultBinaryMessenger get _messenger =>
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

final List<String> _calls = <String>[];

void _answer(Future<Object?> Function(MethodCall call) handler) {
  _messenger.setMockMethodCallHandler(_methods, (call) {
    _calls.add(call.method);
    return handler(call);
  });
}

Future<void> _settle() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(_calls.clear);

  tearDown(() {
    _messenger.setMockMethodCallHandler(_methods, null);
    _messenger.setMockStreamHandler(_heart, null);
    _messenger.setMockStreamHandler(_location, null);
  });

  test(
    'S-29701 the channel names are the contract the native half answers',
    () {
      expect(WearSensorSource.methodsName, 'omnitrain/wear_sensors/methods');
      expect(
        WearSensorSource.heartRateName,
        'omnitrain/wear_sensors/heart_rate',
      );
      expect(WearSensorSource.locationName, 'omnitrain/wear_sensors/location');
    },
  );

  test('S-29701 a permission answer maps to the three states', () async {
    final source = WearSensorSource();
    for (final entry in const {
      'granted': WatchSensorPermission.granted,
      'denied': WatchSensorPermission.denied,
      'unavailable': WatchSensorPermission.unavailable,
    }.entries) {
      _answer((_) async => entry.key);

      expect(
        await source.heartRatePermission(),
        entry.value,
        reason: entry.key,
      );
      expect(await source.locationPermission(), entry.value, reason: entry.key);
    }

    expect(_calls.where((call) => call == 'heartRatePermission'), hasLength(3));
    expect(_calls.where((call) => call == 'locationPermission'), hasLength(3));
  });

  test('S-29702 every failure reads as unavailable', () async {
    final source = WearSensorSource();

    for (final answer in <Future<Object?> Function(MethodCall)>[
      (_) async => null,
      (_) async => 'maybe',
      (_) async => 7,
      (_) async => throw PlatformException(code: 'boom'),
    ]) {
      _answer(answer);

      expect(
        await source.heartRatePermission(),
        WatchSensorPermission.unavailable,
      );
      expect(
        await source.locationPermission(),
        WatchSensorPermission.unavailable,
      );
    }

    _messenger.setMockMethodCallHandler(_methods, null);
    expect(
      await source.heartRatePermission(),
      WatchSensorPermission.unavailable,
      reason: 'no native half at all (MissingPluginException)',
    );
  });

  test(
    'S-29703 the heart-rate stream yields numbers and survives an error',
    () async {
      _messenger.setMockStreamHandler(
        _heart,
        MockStreamHandler.inline(
          onListen: (arguments, events) {
            events.success(72);
            events.success(72.5);
            events.success('x');
            events.success(null);
            events.error(code: 'sensor', message: 'lost');
            events.success(80);
          },
        ),
      );
      final beats = <double>[];
      final errors = <Object>[];

      final subscription = WearSensorSource().heartRate().listen(
        beats.add,
        onError: errors.add,
      );
      await _settle();
      await subscription.cancel();

      expect(beats, [72.0, 72.5, 80.0]);
      expect(errors, isEmpty);
    },
  );

  test(
    'S-29703 a stream with no native half reaches no listener as an error',
    () async {
      final errors = <Object>[];

      final subscription = WearSensorSource().heartRate().listen(
        (_) {},
        onError: errors.add,
      );
      await _settle();
      await subscription.cancel();

      expect(errors, isEmpty);
    },
  );

  test('S-29704 the location stream yields cumulative metres', () async {
    _messenger.setMockStreamHandler(
      _location,
      MockStreamHandler.inline(
        onListen: (arguments, events) {
          events.success(10);
          events.success(25.5);
        },
      ),
    );
    final fixes = <double>[];

    final subscription = WearSensorSource().location().listen(
      (fix) => fixes.add(fix.distanceMeters),
    );
    await _settle();
    await subscription.cancel();

    expect(fixes, [10.0, 25.5]);
  });
}
