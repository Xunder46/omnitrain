// The Wear wrist's platform workout store and the type translation (plan 300,
// D-30001, D-30002, D-30005).
//   S-30001 begin names the Health Connect type of what it was given
//   S-30002 a lift, a hold and an unknown type register as themselves / generic
//   S-30003 a refused or unavailable permission starts nothing
//   S-30004 every platform failure reads as nothing happened
//   S-30005 the in-progress list is read, and anything else is empty
//   S-30006 end reaches the platform once
//   S-30007 the translation helper

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:omnitrain/watch/sensors/watch_platform_workout.dart';
import 'package:omnitrain/watch/sensors/watch_sensor_recording.dart';
import 'package:omnitrain/watch/sensors/wear_sensor_source.dart';

const MethodChannel _methods = MethodChannel(
  WearPlatformWorkoutStore.methodsName,
);

TestDefaultBinaryMessenger get _messenger =>
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

final List<MethodCall> _calls = <MethodCall>[];

void _answer(Future<Object?> Function(MethodCall call) handler) {
  _messenger.setMockMethodCallHandler(_methods, (call) {
    _calls.add(call);
    return handler(call);
  });
}

class _Source implements WatchSensorSource {
  _Source(this.heart);

  final WatchSensorPermission heart;

  @override
  Future<WatchSensorPermission> heartRatePermission() async => heart;

  @override
  Future<WatchSensorPermission> locationPermission() async =>
      WatchSensorPermission.unavailable;

  @override
  Stream<double> heartRate() => const Stream<double>.empty();

  @override
  Stream<WatchLocationFix> location() => const Stream<WatchLocationFix>.empty();
}

WearPlatformWorkoutStore _store([
  WatchSensorPermission heart = WatchSensorPermission.granted,
]) => WearPlatformWorkoutStore(source: _Source(heart));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    _calls.clear();
    _answer((_) async => null);
  });

  tearDown(() => _messenger.setMockMethodCallHandler(_methods, null));

  test('S-30001 the channel name is the contract the native half answers', () {
    expect(
      WearPlatformWorkoutStore.methodsName,
      'omnitrain/wear_workout/methods',
    );
  });

  test('S-30001 begin names the Health Connect type', () async {
    await _store().begin('running');

    expect(_calls.map((call) => call.method), ['begin']);
    expect(_calls.single.arguments, 'exercise_type_running');
  });

  test('S-30002 a lift, a hold and an unknown type', () async {
    final store = _store();

    await store.begin('traditionalStrengthTraining');
    await store.begin('flexibility');
    await store.begin('somethingNew');

    expect(_calls.map((call) => call.arguments), [
      'exercise_type_strength_training',
      'exercise_type_flexibility',
      'exercise_type_other_workout',
    ]);
  });

  test('S-30003 a refused or unavailable permission starts nothing', () async {
    await _store(WatchSensorPermission.denied).begin('running');
    await _store(WatchSensorPermission.unavailable).begin('running');

    expect(_calls, isEmpty);
  });

  test('S-30004 every platform failure reads as nothing happened', () async {
    _answer((_) async => throw PlatformException(code: 'boom'));
    final store = _store();

    await store.begin('running');
    await store.end();
    expect(await store.inProgressActivityTypes(), isEmpty);

    _messenger.setMockMethodCallHandler(_methods, null);
    await store.begin('running');
    await store.end();
    expect(
      await store.inProgressActivityTypes(),
      isEmpty,
      reason: 'no native half at all (MissingPluginException)',
    );
  });

  test('S-30005 the in-progress list is read', () async {
    final store = _store();

    _answer((_) async => <Object?>['exercise_type_running', 7, null]);
    expect(await store.inProgressActivityTypes(), ['exercise_type_running']);

    _answer((_) async => 'nope');
    expect(await store.inProgressActivityTypes(), isEmpty);

    _answer((_) async => null);
    expect(await store.inProgressActivityTypes(), isEmpty);
    expect(_calls.map((call) => call.method).toSet(), {'inProgress'});
  });

  test('S-30006 end reaches the platform once', () async {
    await _store().end();

    expect(_calls.map((call) => call.method), ['end']);
  });

  test('S-30007 the translation helper', () {
    expect(WatchActivityTypes.wearFor('running'), 'exercise_type_running');
    expect(
      WatchActivityTypes.wearFor('traditionalStrengthTraining'),
      'exercise_type_strength_training',
    );
    expect(WatchActivityTypes.wearFor('yoga'), 'exercise_type_yoga');
    expect(WatchActivityTypes.wearFor('cycling'), 'exercise_type_biking');
    expect(WatchActivityTypes.wearFor('other'), 'exercise_type_other_workout');
    expect(WatchActivityTypes.wearFor(''), 'exercise_type_other_workout');
    expect(WatchActivityTypes.wearFor('nope'), 'exercise_type_other_workout');

    for (final type in WatchActivityTypes.byModality.values) {
      expect(
        WatchActivityTypes.wearFor(type.watchOs),
        isNotEmpty,
        reason: type.watchOs,
      );
    }
  });
}
