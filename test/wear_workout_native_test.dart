// The Wear wrist's native platform workout (plan 300, D-30003, D-30004).
//
// No Kotlin test harness exists, so these are source guards on the Kotlin and
// manifest text; the behaviour on a platform is the emulator proof (S-30011)
// and owner check 20.
//   S-30009 the exercise client: permission, type table, config, service order
//   S-30010 the service, the manifests and the registrar

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:omnitrain/watch/sensors/watch_platform_workout.dart';
import 'package:omnitrain/watch/sensors/wear_sensor_source.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

const String _dir = 'android/app/src/wear/kotlin/dev/sasha/omnitrain/';
final String _workout = _read('${_dir}WearWorkout.kt');

/// Names the table can produce that Health Services has no closer type for:
/// they register as a generic workout (`ExerciseType.WORKOUT`).
const Set<String> _generic = {
  'exercise_type_other_workout',
  'exercise_type_cross_training',
};

/// The member of [source] that starts with [signature], up to the next member
/// or comment block at the same indentation.
String _body(String source, String signature) {
  final start = source.indexOf(signature);
  expect(start, greaterThan(0), reason: '$signature is missing');
  final rest = source.substring(start + signature.length);
  final next = RegExp(
    r'\n    (/\*\*|// MARK|private fun |override fun |fun |init )',
  ).firstMatch(rest);
  return source.substring(
    start,
    next == null ? source.length : start + signature.length + next.start,
  );
}

void main() {
  test('S-30009 the exercise client: permission, types, config, service', () {
    final begin = _body(_workout, 'private fun begin(');
    expect(begin, contains('if (name == null || !holdsBodySensors()) {'));
    expect(begin, contains('val type = exerciseTypeFor(name)'));
    expect(
      begin.indexOf('holdsBodySensors()'),
      lessThan(begin.indexOf('start(type')),
      reason: 'no exercise without the permission',
    );

    // The config moved into `start` with plan 306 (calories join the data types).
    final start = _body(_workout, 'private fun start(');
    expect(start, contains('ExerciseConfig.builder(type)'));
    expect(start, contains('setOf(DataType.HEART_RATE_BPM)'));
    expect(start, contains('.setIsAutoPauseAndResumeEnabled(false)'));
    expect(start, contains('.setIsGpsEnabled(false)'));
    expect(start, contains('client().startExerciseAsync(config)'));
    expect(start, contains('if (started) startService() else clearUpdates()'));
    expect(
      start.indexOf('future.get()'),
      lessThan(start.indexOf('startService()')),
      reason: 'the service only after the exercise started',
    );

    final end = _body(_workout, 'private fun end(');
    expect(end, contains('client().endExerciseAsync()'));
    expect(
      'stopService()'.allMatches(end),
      hasLength(2),
      reason: 'when the call fails and when the exercise has ended',
    );
    expect(
      end.lastIndexOf('stopService()'),
      greaterThan(end.indexOf('future.addListener(')),
      reason: 'the service stops once the exercise has ended',
    );
    expect(
      end.indexOf('endExerciseAsync'),
      lessThan(end.lastIndexOf('stopService()')),
      reason: 'the service stops after the exercise ends',
    );

    final progress = _body(_workout, 'private fun inProgress(');
    expect(progress, contains('client().getCurrentExerciseInfoAsync()'));
    expect(
      progress,
      contains('ExerciseTrackedStatus.OWNED_EXERCISE_IN_PROGRESS'),
    );
    expect(progress, contains('emptyList<String>()'));

    final types = _body(_workout, 'private fun exerciseTypeFor(');
    expect(types, contains('else -> ExerciseType.WORKOUT'));
    for (final entry in const {
      'exercise_type_running': 'RUNNING',
      'exercise_type_strength_training': 'STRENGTH_TRAINING',
      'exercise_type_flexibility': 'STRETCHING',
      'exercise_type_calisthenics': 'CALISTHENICS',
      'exercise_type_yoga': 'YOGA',
      'exercise_type_biking': 'BIKING',
    }.entries) {
      expect(types, contains('"${entry.key}"'));
      expect(types, contains('ExerciseType.${entry.value}'));
    }
    // Every name the Dart table can produce is either mapped or a generic one.
    for (final type in WatchActivityTypes.byModality.values) {
      expect(
        types.contains('"${type.wear}"') || _generic.contains(type.wear),
        isTrue,
        reason: type.wear,
      );
    }

    final methods = _body(_workout, 'override fun onMethodCall(');
    expect(
      methods,
      contains('"begin" -> begin(call.arguments as? String, result)'),
    );
    expect(methods, contains('"end" -> end(result)'));
    expect(methods, contains('"inProgress" -> inProgress(result)'));
    expect(
      _workout,
      contains('const val METHODS = "${WearPlatformWorkoutStore.methodsName}"'),
    );
    expect(
      _workout,
      contains('MethodChannel(messenger, METHODS).setMethodCallHandler(this)'),
    );
  });

  test('S-30010 the service, the manifests and the registrar', () {
    final service = _read('${_dir}WorkoutService.kt');
    expect(
      service,
      contains(
        'startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_HEALTH)',
      ),
    );
    expect(service, contains('.setOngoing(true)'));
    expect(service, contains('return START_NOT_STICKY'));
    expect(service, contains('.setContentText("Workout in progress")'));

    final wear = _read('android/app/src/wear/AndroidManifest.xml');
    expect(
      wear,
      contains(
        '<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />',
      ),
    );
    expect(
      wear,
      contains(
        '<uses-permission android:name="android.permission.FOREGROUND_SERVICE_HEALTH" />',
      ),
    );
    expect(wear, contains('android:name="dev.sasha.omnitrain.WorkoutService"'));
    expect(wear, contains('android:foregroundServiceType="health"'));
    expect(wear, contains('android:exported="false"'));

    final main = _read('android/app/src/main/AndroidManifest.xml');
    expect(main, isNot(contains('WorkoutService')));
    expect(main, isNot(contains('FOREGROUND_SERVICE_HEALTH')));

    final registrar = _read('${_dir}SensorsRegistrar.kt');
    expect(
      registrar,
      contains('holdsBodySensors = { sensors.heartRateGranted() },'),
    );
    expect(
      registrar,
      contains('val sensors = WearSensors(activity, messenger)'),
    );
    final phone = _read(
      'android/app/src/phone/kotlin/dev/sasha/omnitrain/SensorsRegistrar.kt',
    );
    expect(phone, isNot(contains('WearWorkout')));

    final sensors = _read('${_dir}WearSensors.kt');
    expect(sensors, contains('    fun heartRateGranted(): Boolean ='));
  });
}
