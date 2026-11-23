// Calories on the Wear wrist, the native half (plan 306).
//
// Plan: `docs/plans/2026-11-22-306-wear-calories-native-plan/2026-11-22-306-wear-calories-native-plan.md`
//   S-30601 the Dart store asks the energy permission before the workout starts
//   S-30602 the Kotlin permission answer (source guards)
//   S-30603 the Kotlin energy stream (source guards)
//   S-30604 the Kotlin workout carries calories (source guards)
//   S-30605 the registrar and the manifest (source guards)
//
// No Kotlin test harness exists, so the Kotlin is guarded as text; its behaviour
// on Health Services is the emulator observation in the plan's evidence file and
// owner check 22.

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:omnitrain/watch/sensors/watch_sensor_recording.dart';
import 'package:omnitrain/watch/sensors/wear_sensor_source.dart';

const MethodChannel _workout = MethodChannel('omnitrain/wear_workout/methods');

TestDefaultBinaryMessenger get _messenger =>
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

final List<String> _order = <String>[];

class _Source implements WatchSensorSource, WatchEnergySource {
  _Source({
    this.heart = WatchSensorPermission.granted,
    this.throwOnEnergy = false,
  });

  final WatchSensorPermission heart;
  final bool throwOnEnergy;

  @override
  Future<WatchSensorPermission> heartRatePermission() async {
    _order.add('heart');
    return heart;
  }

  @override
  Future<WatchSensorPermission> activeEnergyPermission() async {
    _order.add('energy');
    if (throwOnEnergy) throw StateError('no prompt');
    return WatchSensorPermission.denied;
  }

  @override
  Stream<double> activeEnergy() => const Stream<double>.empty();

  @override
  Future<WatchSensorPermission> locationPermission() async =>
      WatchSensorPermission.unavailable;

  @override
  Stream<double> heartRate() => const Stream<double>.empty();

  @override
  Stream<WatchLocationFix> location() => const Stream<WatchLocationFix>.empty();
}

class _PlainSource implements WatchSensorSource {
  @override
  Future<WatchSensorPermission> heartRatePermission() async {
    _order.add('heart');
    return WatchSensorPermission.granted;
  }

  @override
  Future<WatchSensorPermission> locationPermission() async =>
      WatchSensorPermission.unavailable;

  @override
  Stream<double> heartRate() => const Stream<double>.empty();

  @override
  Stream<WatchLocationFix> location() => const Stream<WatchLocationFix>.empty();
}

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

final String _kt = 'android/app/src/wear/kotlin/dev/sasha/omnitrain';

/// The text of the member that starts with [signature] in [source], up to the
/// next member or comment block at the same indentation.
String _body(String source, String signature) {
  final start = source.indexOf(signature);
  expect(start, greaterThan(0), reason: '$signature is missing');
  final rest = source.substring(start + signature.length);
  final next = RegExp(
    r'\n    (/\*\*|// MARK|private fun |override fun |fun )',
  ).firstMatch(rest);
  return source.substring(
    start,
    next == null ? source.length : start + signature.length + next.start,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    _order.clear();
    _messenger.setMockMethodCallHandler(_workout, (call) async {
      _order.add('native:${call.method}');
      return null;
    });
  });

  tearDown(() => _messenger.setMockMethodCallHandler(_workout, null));

  group('S-30601 the store asks the energy permission before the start', () {
    test('after heart rate, before the native begin', () async {
      await WearPlatformWorkoutStore(source: _Source()).begin('running');

      expect(_order, ['heart', 'energy', 'native:begin']);
    });

    test('a source without energy asks nothing more', () async {
      await WearPlatformWorkoutStore(source: _PlainSource()).begin('running');

      expect(_order, ['heart', 'native:begin']);
    });

    test('heart rate refused: nothing is asked, nothing starts', () async {
      await WearPlatformWorkoutStore(
        source: _Source(heart: WatchSensorPermission.denied),
      ).begin('running');

      expect(_order, ['heart']);
    });

    test('a refused energy permission still starts the workout', () async {
      await WearPlatformWorkoutStore(source: _Source()).begin('running');

      expect(_order, contains('native:begin'));
    });

    test('an energy question that throws still starts the workout', () async {
      await WearPlatformWorkoutStore(
        source: _Source(throwOnEnergy: true),
      ).begin('running');

      expect(_order, ['heart', 'energy', 'native:begin']);
    });
  });

  group('S-30606 a refusal is asked once per process', () {
    const sensors = MethodChannel('omnitrain/wear_sensors/methods');
    var asked = 0;
    var answer = 'denied';

    setUp(() {
      asked = 0;
      _messenger.setMockMethodCallHandler(sensors, (call) async {
        asked++;
        return answer;
      });
    });
    tearDown(() => _messenger.setMockMethodCallHandler(sensors, null));

    test('denied is remembered, so the recorder is not asked again', () async {
      final source = WearSensorSource();

      expect(
        await source.activeEnergyPermission(),
        WatchSensorPermission.denied,
      );
      expect(
        await source.activeEnergyPermission(),
        WatchSensorPermission.denied,
      );

      expect(asked, 1);
    });

    test('granted and unavailable are asked every time', () async {
      final source = WearSensorSource();
      answer = 'granted';
      await source.activeEnergyPermission();
      await source.activeEnergyPermission();
      answer = 'unavailable';
      await source.activeEnergyPermission();
      await source.activeEnergyPermission();

      expect(asked, 4);
    });

    test('a new process asks again', () async {
      await WearSensorSource().activeEnergyPermission();
      await WearSensorSource().activeEnergyPermission();

      expect(asked, 2);
    });
  });

  group('S-30602 the permission answer (source guards)', () {
    final source = _read('$_kt/WearSensors.kt');

    test('the method is registered and the code handled', () {
      expect(
        _body(source, 'override fun onMethodCall('),
        contains('"activeEnergyPermission" -> activeEnergyPermission(result)'),
      );
      expect(source, contains('private const val REQUEST_ACTIVITY = 29803'));
      expect(
        _body(source, 'override fun onRequestPermissionsResult('),
        contains('REQUEST_ACTIVITY -> answerActivity(grantResults)'),
      );
    });

    test('unavailable, granted or one shared prompt', () {
      final body = _body(source, 'private fun activeEnergyPermission(');

      expect(body, contains('.contains(DataType.CALORIES_TOTAL)'));
      expect(body, contains('!supported -> result.success("unavailable")'));
      expect(
        body,
        contains('activityRecognitionGranted() -> result.success("granted")'),
      );
      expect(body, contains('else -> askActivity(result)'));
      final ask = _body(source, 'private fun askActivity(');
      expect(ask, contains('waitingActivity.add(result)'));
      expect(ask, contains('if (waitingActivity.size == 1) {'));
      expect(ask, contains('Manifest.permission.ACTIVITY_RECOGNITION'));
    });

    test('the answers are granted or denied and every waiter gets one', () {
      final body = _body(source, 'private fun answerActivity(');

      expect(
        body,
        contains('grantResults[0] == PackageManager.PERMISSION_GRANTED'),
      );
      expect(
        body,
        contains('val answer = if (granted) "granted" else "denied"'),
      );
      expect(body, contains('waitingActivity.clear()'));
      expect(body, contains('for (result in pending) result.success(answer)'));
    });
  });

  group('S-30603 the energy stream (source guards)', () {
    final source = _read('$_kt/EnergyStream.kt');

    test('its channel is the one Dart listens to', () {
      expect(
        source,
        contains('const val CHANNEL = "${WearSensorSource.energyName}"'),
      );
      expect(
        source,
        contains('EventChannel(messenger, CHANNEL).setStreamHandler(this)'),
      );
    });

    test(
      'a number goes to the main thread and is dropped with no listener',
      () {
        expect(source, contains('main.post { sink?.success(kilocalories) }'));
        expect(source, contains('sink = events'));
        final cancel = _body(source, 'override fun onCancel(');
        expect(cancel, contains('sink = null'));
      },
    );
  });

  group('S-30604 the workout carries calories (source guards)', () {
    final source = _read('$_kt/WearWorkout.kt');

    test('calories only under the permission and the capability', () {
      final begin = _body(source, 'private fun begin(');

      expect(begin, contains('client().getCapabilitiesAsync()'));
      expect(begin, contains('val calories = holdsActivity() && try {'));
      expect(begin, contains('.getExerciseTypeCapabilities(type)'));
      expect(begin, contains('.contains(DataType.CALORIES_TOTAL)'));
      expect(begin, contains('start(type, calories, result)'));
      expect(begin, contains('start(type, calories = false, result)'));
    });

    test('the data types are heart rate, plus calories only when asked', () {
      final start = _body(source, 'private fun start(');

      expect(
        start,
        contains('setOf(DataType.HEART_RATE_BPM, DataType.CALORIES_TOTAL)'),
      );
      expect(start, contains('setOf(DataType.HEART_RATE_BPM)'));
      expect(
        start,
        contains('val callback = if (calories) energyCallback() else null'),
      );
    });

    test('the callback is set before the start and cleared on failure', () {
      final start = _body(source, 'private fun start(');

      final set = start.indexOf(
        'client().setUpdateCallback(activity.mainExecutor, callback)',
      );
      final begin = start.indexOf('client().startExerciseAsync(config)');
      expect(set, greaterThan(0));
      expect(begin, greaterThan(set));
      expect(
        start,
        contains('if (started) startService() else clearUpdates()'),
      );
      expect(
        start,
        contains('} catch (error: Exception) {\n            clearUpdates()'),
      );
    });

    test('an update puts the cumulative total on the stream', () {
      final body = _body(source, 'private fun energyCallback(');

      expect(
        body,
        contains(
          'update.latestMetrics.getData(DataType.CALORIES_TOTAL)?.total ?: return',
        ),
      );
      expect(body, contains('energy.emit(total)'));
    });

    test('ending the workout clears the callback on both paths', () {
      final body = _body(source, 'private fun end(');

      expect('clearUpdates()'.allMatches(body), hasLength(2));
      final clear = _body(source, 'private fun clearUpdates(');
      expect(clear, contains('client().clearUpdateCallbackAsync(callback)'));
      expect(clear, contains('updates = null'));
    });
  });

  group('S-30605 the registrar and the manifest (source guards)', () {
    test('the stream is built and handed to the workout', () {
      final source = _read('$_kt/SensorsRegistrar.kt');

      expect(source, contains('val energy = EnergyStream(messenger)'));
      expect(
        source,
        contains('holdsActivity = { sensors.activityRecognitionGranted() },'),
      );
      expect(source, contains('energy = energy,'));
    });

    test('the permission is declared on the watch only', () {
      expect(
        _read('android/app/src/wear/AndroidManifest.xml'),
        contains(
          '<uses-permission android:name="android.permission.ACTIVITY_RECOGNITION" />',
        ),
      );
      expect(
        _read('android/app/src/main/AndroidManifest.xml'),
        isNot(contains('ACTIVITY_RECOGNITION')),
      );
    });
  });
}
