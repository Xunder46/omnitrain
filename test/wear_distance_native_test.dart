// The Wear wrist's native distance client (plan 299, D-29901..D-29905).
//
// No Kotlin test harness exists, so these are source guards on the Kotlin,
// gradle and manifest text; the behaviour on a platform is the emulator proof
// (S-29906) and owner check 19.
//   S-29901 the location question: GPS, shortcut, request
//   S-29902 the prompt's answer reaches every waiting location caller
//   S-29903 the stream: permission gate, request, filters, post, cleanup
//   S-29904 the distance tracker's rules
//   S-29905 the manifests and the dependency

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:omnitrain/watch/sensors/wear_sensor_source.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

const String _dir = 'android/app/src/wear/kotlin/dev/sasha/omnitrain/';
final String _sensors = _read('${_dir}WearSensors.kt');
final String _tracker = _read('${_dir}DistanceTracker.kt');

/// The member of [source] that starts with [signature], up to the next member
/// or comment block at the same indentation.
String _body(String source, String signature) {
  final start = source.indexOf(signature);
  expect(start, greaterThan(0), reason: '$signature is missing');
  final rest = source.substring(start + signature.length);
  final next = RegExp(
    r'\n    (/\*\*|// MARK|private fun |private val |override fun |fun )',
  ).firstMatch(rest);
  return source.substring(
    start,
    next == null ? source.length : start + signature.length + next.start,
  );
}

void main() {
  test('S-29901 the location question: GPS, shortcut, request', () {
    final ask = _body(_sensors, 'private fun locationPermission(');

    expect(
      ask,
      contains(
        '!activity.packageManager.hasSystemFeature(PackageManager.FEATURE_LOCATION_GPS) ->',
      ),
    );
    expect(ask, contains('result.success("unavailable")'));
    expect(ask, contains('locationGranted() -> result.success("granted")'));
    expect(ask, contains('else -> askLocation(result)'));
    expect(
      ask.indexOf('FEATURE_LOCATION_GPS'),
      lessThan(ask.indexOf('locationGranted()')),
      reason: 'a watch without GPS never prompts',
    );

    final granted = _body(_sensors, 'private fun locationGranted(');
    expect(granted, contains('Manifest.permission.ACCESS_FINE_LOCATION'));

    final request = _body(_sensors, 'private fun askLocation(');
    expect(request, contains('waitingLocation.add(result)'));
    expect(request, contains('if (waitingLocation.size == 1) {'));
    expect(request, contains('Manifest.permission.ACCESS_FINE_LOCATION,'));
    expect(request, contains('Manifest.permission.ACCESS_COARSE_LOCATION,'));
    expect(request, contains('REQUEST_LOCATION,'));

    final methods = _body(_sensors, 'override fun onMethodCall(');
    expect(
      methods,
      contains('"locationPermission" -> locationPermission(result)'),
    );
  });

  test('S-29902 the prompt answer reaches every waiting location caller', () {
    expect(_sensors, contains('private const val REQUEST_LOCATION = 29802'));
    expect(_sensors, contains('private const val REQUEST_HEART_RATE = 29801'));
    final dispatch = _body(
      _sensors,
      'override fun onRequestPermissionsResult(',
    );
    expect(
      dispatch,
      contains('REQUEST_LOCATION -> answerLocation(permissions, grantResults)'),
    );
    expect(dispatch, contains('else -> false'));

    final answer = _body(_sensors, 'private fun answerLocation(');
    expect(
      answer,
      contains('permissions.indexOf(Manifest.permission.ACCESS_FINE_LOCATION)'),
    );
    expect(
      answer,
      contains(
        'grantResults.getOrNull(fine) == PackageManager.PERMISSION_GRANTED',
      ),
    );
    expect(answer, contains('val pending = waitingLocation.toList()'));
    expect(answer, contains('waitingLocation.clear()'));
    expect(answer, contains('for (result in pending) result.success(answer)'));
    expect(
      answer.indexOf('waitingLocation.toList()'),
      lessThan(answer.indexOf('waitingLocation.clear()')),
    );
    expect(
      answer.indexOf('waitingLocation.clear()'),
      lessThan(answer.indexOf('result.success(answer)')),
    );
  });

  test('S-29903 the stream: gate, request, filters, post, cleanup', () {
    final stream = _body(_sensors, 'private val locationStream = ');
    final listen = stream.substring(
      stream.indexOf('override fun onListen('),
      stream.indexOf('override fun onCancel('),
    );
    final cancel = stream.substring(stream.indexOf('override fun onCancel('));

    expect(listen, contains('if (!locationGranted()) {'));
    expect(listen, contains('events?.endOfStream()'));
    expect(listen, contains('stopLocation()'));
    expect(listen, contains('tracker.reset()'));
    expect(
      listen,
      contains(
        'LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, LOCATION_INTERVAL_MS)',
      ),
    );
    expect(
      listen,
      contains('.setMinUpdateDistanceMeters(LOCATION_MIN_STEP_M)'),
    );
    expect(
      listen,
      contains(
        'SystemClock.elapsedRealtimeNanos() - fix.elapsedRealtimeNanos > MAX_FIX_AGE_NANOS) continue',
      ),
    );
    expect(
      listen,
      contains('val accuracy = if (fix.hasAccuracy()) fix.accuracy else null'),
    );
    expect(listen, contains('fix.elapsedRealtimeNanos,'));
    expect(listen, contains('main.post { locationSink?.success(total) }'));
    expect(
      listen.indexOf('locationGranted()'),
      lessThan(listen.indexOf('requestLocationUpdates')),
      reason: 'no updates without the permission',
    );

    expect(cancel, contains('stopLocation()'));
    expect(cancel, contains('locationSink = null'));
    expect(cancel, contains('tracker.reset()'));

    final stop = _body(_sensors, 'private fun stopLocation(');
    expect(stop, contains('val updates = locationUpdates ?: return'));
    expect(stop, contains('locationUpdates = null'));
    expect(stop, contains('fused().removeLocationUpdates(updates)'));

    expect(
      _sensors,
      contains('private const val LOCATION_INTERVAL_MS = 2000L'),
    );
    expect(_sensors, contains('private const val LOCATION_MIN_STEP_M = 3f'));
    expect(
      _sensors,
      contains('private const val MAX_FIX_AGE_NANOS = 10_000_000_000L'),
    );
    expect(
      _sensors,
      contains('const val LOCATION = "${WearSensorSource.locationName}"'),
    );
    expect(
      _sensors,
      contains(
        'EventChannel(messenger, LOCATION).setStreamHandler(locationStream)',
      ),
    );
  });

  test('S-29904 the distance tracker rules', () {
    expect(_tracker, contains('const val MAX_ACCURACY_M = 50f'));
    expect(_tracker, contains('const val MAX_SPEED_MPS = 15.0'));

    final accept = _body(_tracker, 'fun accept(');
    expect(
      accept,
      contains(
        'if (accuracy == null || accuracy > MAX_ACCURACY_M) return null',
      ),
    );
    expect(accept, contains('val seconds = (elapsedNanos - lastNanos) / 1e9'));
    expect(accept, contains('if (seconds <= 0.0) return null'));
    expect(
      accept,
      contains(
        'Location.distanceBetween(previousLatitude, previousLongitude, latitude, longitude, step)',
      ),
    );
    expect(
      accept,
      contains('if (step[0] / seconds <= MAX_SPEED_MPS) total += step[0]'),
    );
    expect(accept, contains('lastLatitude = latitude'));
    expect(accept, contains('lastLongitude = longitude'));
    expect(accept, contains('lastNanos = elapsedNanos'));
    expect(accept, contains('return total'));
    expect(
      accept.indexOf('total += step[0]'),
      lessThan(accept.indexOf('lastLatitude = latitude')),
      reason:
          'the step is measured from the previous fix, then the anchor moves',
    );

    final reset = _body(_tracker, 'fun reset(');
    expect(reset, contains('lastLatitude = null'));
    expect(reset, contains('lastLongitude = null'));
    expect(reset, contains('lastNanos = 0L'));
    expect(reset, contains('total = 0.0'));
  });

  test('S-29905 the manifests and the dependency', () {
    final wear = _read('android/app/src/wear/AndroidManifest.xml');
    expect(
      wear,
      contains(
        '<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />',
      ),
    );
    expect(
      wear,
      contains(
        '<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />',
      ),
    );

    final main = _read('android/app/src/main/AndroidManifest.xml');
    expect(main, isNot(contains('ACCESS_FINE_LOCATION')));
    expect(main, isNot(contains('ACCESS_COARSE_LOCATION')));

    final gradle = _read('android/app/build.gradle.kts');
    expect(
      gradle,
      contains(
        '"wearImplementation"("com.google.android.gms:play-services-location:21.3.0")',
      ),
    );
    expect(
      gradle,
      isNot(
        contains(
          '    implementation("com.google.android.gms:play-services-location',
        ),
      ),
    );
  });
}
