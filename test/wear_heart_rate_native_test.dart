// The Wear wrist's native heart-rate client (plan 298, D-29801..D-29805).
//
// No Kotlin test harness exists, so these are source guards on the Kotlin,
// gradle and manifest text; the behaviour on a platform is the emulator proof
// (S-29806) and owner check 17.
//   S-29801 the permission question: capability, shortcut, request
//   S-29802 the prompt's answer reaches every waiting caller
//   S-29803 the stream: permission gate, data type, main-thread post, cleanup
//   S-29804 the activity wiring and the Kotlin/Dart channel names
//   S-29805 the manifests and the dependency

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:omnitrain/watch/sensors/wear_sensor_source.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

final String _wearSensors = _read(
  'android/app/src/wear/kotlin/dev/sasha/omnitrain/WearSensors.kt',
);

/// The member of [source] that starts with [signature], up to the next member
/// or comment block at the same indentation.
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
  test('S-29801 the permission question: capability, shortcut, request', () {
    final ask = _body(_wearSensors, 'private fun heartRatePermission(');

    expect(ask, contains('measureClient().getCapabilitiesAsync()'));
    expect(
      ask,
      contains('supportedDataTypesMeasure.contains(DataType.HEART_RATE_BPM)'),
    );
    expect(ask, contains('!supported -> result.success("unavailable")'));
    expect(ask, contains('heartRateGranted() -> result.success("granted")'));
    expect(ask, contains('else -> askHeartRate(result)'));
    final unsupported = ask.indexOf('"unavailable"');
    final granted = ask.indexOf('"granted"');
    expect(unsupported, lessThan(granted), reason: 'capability comes first');

    final name = _body(_wearSensors, 'private fun heartRatePermissionName(');
    expect(name, contains('Build.VERSION.SDK_INT >= 36'));
    expect(name, contains('"android.permission.health.READ_HEART_RATE"'));
    expect(name, contains('android.Manifest.permission.BODY_SENSORS'));

    final request = _body(_wearSensors, 'private fun askHeartRate(');
    expect(request, contains('waiting.add(result)'));
    expect(request, contains('if (waiting.size == 1) {'));
    expect(
      request,
      contains(
        'activity.requestPermissions(arrayOf(heartRatePermissionName())',
      ),
    );

    final methods = _body(_wearSensors, 'override fun onMethodCall(');
    expect(methods, contains('"heartRatePermission" -> heartRatePermission'));
    expect(
      methods,
      contains('"locationPermission" -> locationPermission(result)'),
    );
  });

  test('S-29802 the prompt answer reaches every waiting caller', () {
    final dispatch = _body(
      _wearSensors,
      'override fun onRequestPermissionsResult(',
    );
    expect(
      dispatch,
      contains('REQUEST_HEART_RATE -> answerHeartRate(grantResults)'),
    );
    expect(dispatch, contains('else -> false'));

    final answer = _body(_wearSensors, 'private fun answerHeartRate(');
    expect(answer, contains('grantResults.isNotEmpty()'));
    expect(
      answer,
      contains('grantResults[0] == PackageManager.PERMISSION_GRANTED'),
    );
    expect(answer, contains('val pending = waiting.toList()'));
    expect(answer, contains('waiting.clear()'));
    expect(answer, contains('for (result in pending) result.success(answer)'));
    expect(answer, contains('return true'));
    final snapshot = answer.indexOf('waiting.toList()');
    final clear = answer.indexOf('waiting.clear()');
    final reply = answer.indexOf('result.success(answer)');
    expect(snapshot, lessThan(clear));
    expect(clear, lessThan(reply));
  });

  test('S-29803 the stream: permission gate, data type, post, cleanup', () {
    final listen = _body(_wearSensors, 'override fun onListen(');

    expect(listen, contains('if (!heartRateGranted()) {'));
    expect(listen, contains('events?.endOfStream()'));
    expect(listen, contains('stopMeasuring()'));
    expect(
      listen,
      contains('data.getData(DataType.HEART_RATE_BPM).lastOrNull() ?: return'),
    );
    expect(listen, contains('main.post { sink?.success(reading.value) }'));
    expect(
      listen,
      contains(
        'measureClient().registerMeasureCallback(DataType.HEART_RATE_BPM, measuring)',
      ),
    );
    final gate = listen.indexOf('heartRateGranted()');
    final register = listen.indexOf('registerMeasureCallback');
    expect(gate, lessThan(register), reason: 'no subscription without it');

    final cancel = _body(_wearSensors, 'override fun onCancel(');
    expect(cancel, contains('stopMeasuring()'));
    expect(cancel, contains('sink = null'));

    final stop = _body(_wearSensors, 'private fun stopMeasuring(');
    expect(stop, contains('val measuring = callback ?: return'));
    expect(stop, contains('callback = null'));
    expect(
      stop,
      contains(
        'unregisterMeasureCallbackAsync(DataType.HEART_RATE_BPM, measuring)',
      ),
    );
  });

  test('S-29804 the activity wiring and the Kotlin and Dart channel names', () {
    final activity = _read(
      'android/app/src/main/kotlin/dev/sasha/omnitrain/MainActivity.kt',
    );
    expect(
      activity,
      contains('sensors = registerSensors(this, flutterEngine)'),
    );
    final forward = _body(activity, 'override fun onRequestPermissionsResult(');
    final handled = forward.indexOf(
      'sensors?.onRequestPermissionsResult(requestCode, permissions, grantResults) == true',
    );
    final fallback = forward.indexOf(
      'super.onRequestPermissionsResult(requestCode, permissions, grantResults)',
    );
    expect(handled, greaterThan(0));
    expect(fallback, greaterThan(handled), reason: 'ours first, then super');

    final phone = _read(
      'android/app/src/phone/kotlin/dev/sasha/omnitrain/SensorsRegistrar.kt',
    );
    expect(
      phone,
      contains(
        'fun registerSensors(activity: Activity, engine: FlutterEngine): SensorBridge? = null',
      ),
    );
    final wear = _read(
      'android/app/src/wear/kotlin/dev/sasha/omnitrain/SensorsRegistrar.kt',
    );
    expect(wear, contains('val sensors = WearSensors(activity, messenger)'));

    expect(
      _wearSensors,
      contains('const val METHODS = "${WearSensorSource.methodsName}"'),
    );
    expect(
      _wearSensors,
      contains('const val HEART_RATE = "${WearSensorSource.heartRateName}"'),
    );
    expect(
      _wearSensors,
      contains('private const val REQUEST_HEART_RATE = 29801'),
    );
  });

  test('S-29805 the manifests and the dependency', () {
    final wear = _read('android/app/src/wear/AndroidManifest.xml');
    expect(
      wear,
      contains(
        '<uses-permission android:name="android.permission.BODY_SENSORS" />',
      ),
    );
    expect(
      wear,
      contains(
        '<uses-permission android:name="android.permission.health.READ_HEART_RATE" />',
      ),
    );

    final main = _read('android/app/src/main/AndroidManifest.xml');
    expect(main, isNot(contains('BODY_SENSORS')));
    expect(main, isNot(contains('READ_HEART_RATE')));

    final gradle = _read('android/app/build.gradle.kts');
    expect(
      gradle,
      contains(
        '"wearImplementation"("androidx.health:health-services-client:1.0.0")',
      ),
    );
    expect(gradle, isNot(contains('    implementation("androidx.health')));
    expect(gradle, isNot(contains('    implementation("com.google.guava')));
  });
}
