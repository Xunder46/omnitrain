// The watch-face chip of a running workout (plan 309).
//
// Plan: `docs/plans/2026-11-22-309-wear-ongoing-activity-plan/2026-11-22-309-wear-ongoing-activity-plan.md`
//   S-30901 the dependencies (wear flavor only)
//   S-30902 the service attaches the Ongoing Activity to its notification
//   S-30903 the status: type and a stopwatch
//   S-30904 the words on the chip
//   S-30905 the activity name travels from the workout to the service
//   S-30906 the icon
//   S-30907 the notification question: Dart store and Kotlin answer
//
// No Kotlin test harness exists, so the Kotlin is guarded as text; its behaviour
// is the emulator observation in the plan's evidence file and owner check 24.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:omnitrain/watch/sensors/watch_sensor_recording.dart';
import 'package:omnitrain/watch/sensors/wear_sensor_source.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

const String _kt = 'android/app/src/wear/kotlin/dev/sasha/omnitrain';

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

const MethodChannel _workout = MethodChannel('omnitrain/wear_workout/methods');
const MethodChannel _sensors = MethodChannel('omnitrain/wear_sensors/methods');

TestDefaultBinaryMessenger get _messenger =>
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

final List<String> _order = <String>[];

class _Source
    implements WatchSensorSource, WatchEnergySource, WatchNotificationSource {
  _Source({this.throwOnNotification = false});

  final bool throwOnNotification;

  @override
  Future<WatchSensorPermission> heartRatePermission() async {
    _order.add('heart');
    return WatchSensorPermission.granted;
  }

  @override
  Future<WatchSensorPermission> activeEnergyPermission() async {
    _order.add('energy');
    return WatchSensorPermission.granted;
  }

  @override
  Future<WatchSensorPermission> notificationPermission() async {
    _order.add('notifications');
    if (throwOnNotification) throw StateError('no prompt');
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

class _NoNotifications implements WatchSensorSource, WatchEnergySource {
  @override
  Future<WatchSensorPermission> heartRatePermission() async {
    _order.add('heart');
    return WatchSensorPermission.granted;
  }

  @override
  Future<WatchSensorPermission> activeEnergyPermission() async {
    _order.add('energy');
    return WatchSensorPermission.granted;
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('S-30901 the dependencies', () {
    final gradle = _read('android/app/build.gradle.kts');

    test(
      'the wear flavor carries both libraries, the phone flavor neither',
      () {
        expect(
          gradle,
          contains('"wearImplementation"("androidx.wear:wear-ongoing:'),
        );
        expect(gradle, contains('"wearImplementation"("androidx.core:core:'));
        expect(
          gradle,
          isNot(contains('"phoneImplementation"("androidx.wear:wear-ongoing')),
        );
        expect(
          RegExp(r'\n    implementation\([^\n]*wear-ongoing').hasMatch(gradle),
          isFalse,
          reason: 'not in the shared block',
        );
      },
    );
  });

  group('S-30902 the service attaches the Ongoing Activity', () {
    final service = _read('$_kt/WorkoutService.kt');
    String start() => _body(service, 'override fun onStartCommand(');

    test('a compat builder: ongoing, workout category, opens the app', () {
      expect(start(), contains('NotificationCompat.Builder(this, CHANNEL_ID)'));
      expect(start(), contains('.setOngoing(true)'));
      expect(
        start(),
        contains('.setCategory(NotificationCompat.CATEGORY_WORKOUT)'),
      );
      expect(start(), contains('.setContentIntent(open)'));
      expect(start(), contains('.setSmallIcon(R.drawable.ic_workout)'));
    });

    test('the activity: the notification id, the icon, the touch intent', () {
      expect(
        start(),
        contains(
          'OngoingActivity.Builder(applicationContext, NOTIFICATION_ID, builder)',
        ),
      );
      expect(start(), contains('.setStaticIcon(R.drawable.ic_workout)'));
      expect(start(), contains('.setTouchIntent(open)'));
      expect(start(), contains('.setStatus(status)'));
      expect(start(), contains('.apply(applicationContext)'));
    });

    test('applied before the notification is posted; service unchanged', () {
      expect(
        start().indexOf('.apply(applicationContext)'),
        lessThan(start().indexOf('startForeground(')),
      );
      expect(
        start(),
        contains(
          'startForeground(NOTIFICATION_ID, builder.build(), ServiceInfo.FOREGROUND_SERVICE_TYPE_HEALTH)',
        ),
      );
      expect(start(), contains('return START_NOT_STICKY'));
    });
  });

  group('S-30903 the status', () {
    final service = _read('$_kt/WorkoutService.kt');

    test('type then a stopwatch from the service start', () {
      expect(service, contains('.addTemplate("#type# #time#")'));
      expect(service, contains('.addPart("type", Status.TextPart(label))'));
      expect(
        service,
        contains(
          '.addPart("time", Status.StopwatchPart(SystemClock.elapsedRealtime()))',
        ),
      );
      expect(service.indexOf('"type"'), lessThan(service.indexOf('"time"')));
    });
  });

  group('S-30904 the words on the chip', () {
    final service = _read('$_kt/WorkoutService.kt');
    String label() => _body(service, 'fun labelFor(');

    test('a Health Connect name becomes words; anything else is Workout', () {
      expect(
        service,
        contains('private const val NAME_PREFIX = "exercise_type_"'),
      );
      expect(service, contains('private const val FALLBACK_LABEL = "Workout"'));
      expect(
        label(),
        contains(
          'if (name == null || !name.startsWith(NAME_PREFIX)) return FALLBACK_LABEL',
        ),
      );
      expect(
        label(),
        contains(".removePrefix(NAME_PREFIX).replace('_', ' ').trim()"),
      );
      expect(label(), contains('if (words.isEmpty()) return FALLBACK_LABEL'));
      expect(label(), contains('words.replaceFirstChar { it.uppercase() }'));
    });

    test('the text of the notification names the activity', () {
      expect(
        service,
        contains(
          'val label = labelFor(intent?.getStringExtra(EXTRA_ACTIVITY))',
        ),
      );
      expect(service, contains('.setContentText("\$label in progress")'));
    });
  });

  group('S-30905 the name travels from the workout', () {
    final workout = _read('$_kt/WearWorkout.kt');
    final service = _read('$_kt/WorkoutService.kt');

    test('begin keeps it and the service intent carries it', () {
      expect(
        _body(workout, 'private fun begin('),
        contains('activityName = name'),
      );
      final startService = _body(workout, 'private fun startService(');
      expect(
        startService,
        contains('.putExtra(WorkoutService.EXTRA_ACTIVITY, activityName)'),
      );
      expect(service, contains('const val EXTRA_ACTIVITY = "activityType"'));
    });
  });

  group('S-30906 the icon', () {
    test('a white vector on transparent', () {
      final xml = _read('android/app/src/wear/res/drawable/ic_workout.xml');

      expect(xml, contains('<vector '));
      expect(xml, contains('android:fillColor="#FFFFFFFF"'));
      expect(xml, contains('android:pathData='));
      expect(xml, isNot(contains('<bitmap')));
    });
  });

  group('S-30907 the notification question', () {
    setUp(() {
      _order.clear();
      _messenger.setMockMethodCallHandler(_workout, (call) async {
        _order.add('native:${call.method}');
        return null;
      });
    });
    tearDown(() {
      _messenger.setMockMethodCallHandler(_workout, null);
      _messenger.setMockMethodCallHandler(_sensors, null);
    });

    test(
      'asked after heart rate and calories, before the workout starts',
      () async {
        await WearPlatformWorkoutStore(source: _Source()).begin('running');

        expect(_order, ['heart', 'energy', 'notifications', 'native:begin']);
      },
    );

    test('a source without the question asks nothing more', () async {
      await WearPlatformWorkoutStore(
        source: _NoNotifications(),
      ).begin('running');

      expect(_order, ['heart', 'energy', 'native:begin']);
    });

    test(
      'a refusal, or a question that throws, still starts the workout',
      () async {
        await WearPlatformWorkoutStore(source: _Source()).begin('running');
        expect(_order, contains('native:begin'));

        _order.clear();
        await WearPlatformWorkoutStore(
          source: _Source(throwOnNotification: true),
        ).begin('running');
        expect(_order, ['heart', 'energy', 'notifications', 'native:begin']);
      },
    );

    test('heart rate refused: no question, no workout', () async {
      final refusing = _RefusingHeart();
      await WearPlatformWorkoutStore(source: refusing).begin('running');

      expect(_order, ['heart']);
    });

    test(
      'the Wear source asks the native half and remembers a refusal',
      () async {
        var asked = 0;
        var answer = 'denied';
        _messenger.setMockMethodCallHandler(_sensors, (call) async {
          if (call.method == 'notificationPermission') asked++;
          return answer;
        });
        final source = WearSensorSource();

        expect(
          await source.notificationPermission(),
          WatchSensorPermission.denied,
        );
        expect(
          await source.notificationPermission(),
          WatchSensorPermission.denied,
        );
        expect(asked, 1, reason: 'a refusal is asked once per process');

        final other = WearSensorSource();
        answer = 'granted';
        await other.notificationPermission();
        await other.notificationPermission();
        expect(asked, 3, reason: 'granted is asked each time');
        answer = 'unavailable';
        await other.notificationPermission();
        await other.notificationPermission();
        expect(asked, 5, reason: 'unavailable is asked each time');
        expect(source, isA<WatchNotificationSource>());
      },
    );

    test('a missing native half reads unavailable', () async {
      expect(
        await WearSensorSource().notificationPermission(),
        WatchSensorPermission.unavailable,
      );
    });

    group('the Kotlin answer (source guards)', () {
      final source = _read('$_kt/WearSensors.kt');

      test('registered, handled, and nothing to ask before Android 13', () {
        expect(
          _body(source, 'override fun onMethodCall('),
          contains(
            '"notificationPermission" -> notificationPermission(result)',
          ),
        );
        expect(
          source,
          contains('private const val REQUEST_NOTIFICATIONS = 29804'),
        );
        expect(
          _body(source, 'override fun onRequestPermissionsResult('),
          contains(
            'REQUEST_NOTIFICATIONS -> answerNotifications(grantResults)',
          ),
        );
        final body = _body(source, 'private fun notificationPermission(');
        expect(
          body,
          contains('Build.VERSION.SDK_INT < 33 -> result.success("granted")'),
        );
        expect(body, contains('Manifest.permission.POST_NOTIFICATIONS'));
        expect(body, contains('else -> askNotifications(result)'));
      });

      test('one shared prompt, granted or denied to every waiter', () {
        final ask = _body(source, 'private fun askNotifications(');
        expect(ask, contains('waitingNotifications.add(result)'));
        expect(ask, contains('if (waitingNotifications.size == 1) {'));
        final answer = _body(source, 'private fun answerNotifications(');
        expect(
          answer,
          contains('val answer = if (granted) "granted" else "denied"'),
        );
        expect(answer, contains('waitingNotifications.clear()'));
        expect(
          answer,
          contains('for (result in pending) result.success(answer)'),
        );
      });
    });

    test('the wear manifest declares the permission itself', () {
      expect(
        _read('android/app/src/wear/AndroidManifest.xml'),
        contains(
          '<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />',
        ),
      );
    });
  });
}

class _RefusingHeart extends _NoNotifications {
  @override
  Future<WatchSensorPermission> heartRatePermission() async {
    _order.add('heart');
    return WatchSensorPermission.denied;
  }
}
