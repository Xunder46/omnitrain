// Plan 90 Phase 2 (D-6): the Runner's Workout Effort channel.
//
// S-90-8 is a source scan of the native piece (no device needed): the
// Runner registers `omnitrain/health_effort`, every method answers behind
// `#available(iOS 18.0, *)`, and Info.plist / the entitlements gain no
// new key while the update-usage text mentions effort.
//
// The gateway group drives the io gateway against a mocked channel: the
// channel is used on iOS only, its answers map onto the contract, and no
// platform error escapes.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/health_platform_gateway_io.dart';
import 'package:omnitrain/core/services/health_platform_service.dart';

const _swiftPath = 'ios/Runner/HealthEffortChannel.swift';
const _appDelegatePath = 'ios/Runner/AppDelegate.swift';
const _infoPlistPath = 'ios/Runner/Info.plist';
const _entitlementsPath = 'ios/Runner/Runner.entitlements';
const _pbxprojPath = 'ios/Runner.xcodeproj/project.pbxproj';

/// The iOS 18 HealthKit names the native piece uses (confirmed against the
/// iOS 26.4 SDK headers; plan 90 evidence).
const _ios18Names = [
  'workoutEffortScore',
  'appleEffortScore',
  'relateWorkoutEffortSample',
  'predicateForWorkoutEffortSamplesRelated',
];

String _read(String path) => File(path).readAsStringSync();

/// Every `<key>` in a plist, in order.
List<String> _plistKeys(String path) => RegExp(
  r'<key>([^<]+)</key>',
).allMatches(_read(path)).map((m) => m.group(1)!).toList();

/// The string value that follows [key] in a flat plist.
String _plistString(String path, String key) {
  final match = RegExp(
    '<key>${RegExp.escape(key)}</key>\\s*<string>([^<]*)</string>',
  ).firstMatch(_read(path));
  return match?.group(1) ?? '';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('S-90-8 native structure (source scan)', () {
    test('S-90-8 the Runner registers channel omnitrain/health_effort', () {
      expect(File(_swiftPath).existsSync(), isTrue, reason: _swiftPath);
      expect(
        _read(_swiftPath),
        contains('"$healthEffortChannelName"'),
        reason: 'the Swift channel name matches the gateway constant',
      );
      final delegate = _read(_appDelegatePath);
      final registrant = delegate.indexOf('GeneratedPluginRegistrant.register');
      final effort = delegate.indexOf('HealthEffortChannel.register(');
      expect(effort, greaterThan(-1), reason: 'AppDelegate registers it');
      expect(effort, greaterThan(registrant), reason: 'after the plugins');
      expect(
        _read(_pbxprojPath),
        contains('HealthEffortChannel.swift in Sources'),
        reason: 'the file is compiled into the Runner target',
      );
    });

    test(
      'S-90-8 every method answers behind #available(iOS 18.0, *), else unavailable',
      () {
        final swift = _read(_swiftPath);
        final handle = swift.indexOf('func handle(');
        expect(handle, greaterThan(-1), reason: 'one dispatch function');
        final guardAt = swift.indexOf(
          'guard #available(iOS 18.0, *) else',
          handle,
        );
        expect(guardAt, greaterThan(handle), reason: 'the dispatch guards');
        final elseBlock = swift.substring(guardAt, swift.indexOf('}', guardAt));
        expect(elseBlock, contains('result("unavailable")'));
        final switchAt = swift.indexOf('switch call.method', handle);
        expect(switchAt, greaterThan(guardAt), reason: 'guard before switch');
        for (final method in const ['requestAuthorization', 'set', 'clear']) {
          final caseAt = swift.indexOf('case "$method":');
          expect(caseAt, greaterThan(switchAt), reason: method);
        }
        // Every iOS 18 API lives inside the type marked available from 18.
        final storeAt = swift.indexOf(
          '@available(iOS 18.0, *)\nprivate final class HealthEffortStore',
        );
        expect(storeAt, greaterThan(switchAt), reason: 'the iOS 18 store');
        for (final name in _ios18Names) {
          final first = swift.indexOf(name);
          expect(first, greaterThan(storeAt), reason: name);
        }
        // Any error answers unavailable rather than escaping.
        expect(swift, contains('catch'));
        expect(
          RegExp(r'catch\s*\{[^}]*"unavailable"').hasMatch(swift),
          isTrue,
          reason: 'a thrown HealthKit error answers unavailable',
        );
      },
    );

    test(
      'S-90-8 Info.plist and entitlements gain no key; the update text mentions effort',
      () {
        expect(_plistKeys(_infoPlistPath), const [
          'CFBundleDevelopmentRegion',
          'CFBundleDisplayName',
          'CFBundleExecutable',
          'CFBundleIdentifier',
          'CFBundleInfoDictionaryVersion',
          'CFBundleName',
          'CFBundlePackageType',
          'CFBundleShortVersionString',
          'CFBundleSignature',
          'CFBundleVersion',
          'LSRequiresIPhoneOS',
          'UILaunchStoryboardName',
          'UIMainStoryboardFile',
          'UISupportedInterfaceOrientations',
          'CADisableMinimumFrameDurationOnPhone',
          'UIApplicationSupportsIndirectInputEvents',
          'NSCameraUsageDescription',
          'NSMicrophoneUsageDescription',
          'NSPhotoLibraryUsageDescription',
          'NSPhotoLibraryAddUsageDescription',
          'NSHealthShareUsageDescription',
          'NSHealthUpdateUsageDescription',
        ]);
        expect(_plistKeys(_entitlementsPath), const [
          'com.apple.developer.healthkit',
        ]);
        expect(
          _plistString(
            _infoPlistPath,
            'NSHealthUpdateUsageDescription',
          ).toLowerCase(),
          contains('effort'),
        );
        expect(
          _plistString(
            _infoPlistPath,
            'NSHealthShareUsageDescription',
          ).toLowerCase(),
          contains('effort'),
          reason: 'the effort type is also read (OQ-2 check)',
        );
      },
    );
  });

  group('Gateway uses the effort channel on iOS only', () {
    const effort = MethodChannel(healthEffortChannelName);
    const plugin = MethodChannel('flutter_health');
    final start = DateTime.utc(2026, 10, 28, 9);
    final end = DateTime.utc(2026, 10, 28, 10);
    late List<String> calls;
    late List<Object?> effortArgs;
    late Object? Function(MethodCall) effortAnswer;

    setUp(() {
      calls = [];
      effortArgs = [];
      effortAnswer = (_) => 'unavailable';
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(effort, (call) async {
        calls.add('effort.${call.method}');
        effortArgs.add(call.arguments);
        return effortAnswer(call);
      });
      messenger.setMockMethodCallHandler(plugin, (call) async {
        calls.add('plugin.${call.method}');
        return true;
      });
    });

    tearDown(() {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(effort, null);
      messenger.setMockMethodCallHandler(plugin, null);
    });

    test('set sends the exact span and score and maps every answer', () async {
      final gateway = HealthPluginPlatformService(isIOS: true);
      const answers = {
        'written': HealthEffortOutcome.written,
        'leftAlone': HealthEffortOutcome.leftAlone,
        'noWorkout': HealthEffortOutcome.noWorkout,
        'unavailable': HealthEffortOutcome.unavailable,
        'something else': HealthEffortOutcome.unavailable,
      };
      for (final entry in answers.entries) {
        effortAnswer = (_) => entry.key;
        expect(
          await gateway.setWorkoutEffort(start, end, 8),
          entry.value,
          reason: entry.key,
        );
      }
      expect(calls, List.filled(answers.length, 'effort.set'));
      expect(effortArgs.first, {
        'start': start.millisecondsSinceEpoch,
        'end': end.millisecondsSinceEpoch,
        'score': 8,
      });
    });

    test('clear sends the exact span; true only when cleared', () async {
      final gateway = HealthPluginPlatformService(isIOS: true);
      effortAnswer = (_) => 'cleared';
      expect(await gateway.clearWorkoutEffort(start, end), isTrue);
      effortAnswer = (_) => 'unavailable';
      expect(await gateway.clearWorkoutEffort(start, end), isFalse);
      expect(calls, ['effort.clear', 'effort.clear']);
      expect(effortArgs.first, {
        'start': start.millisecondsSinceEpoch,
        'end': end.millisecondsSinceEpoch,
      });
    });

    test('a platform error or a missing channel never escapes', () async {
      final gateway = HealthPluginPlatformService(isIOS: true);
      effortAnswer = (_) => throw PlatformException(code: 'boom');
      expect(
        await gateway.setWorkoutEffort(start, end, 8),
        HealthEffortOutcome.unavailable,
      );
      expect(await gateway.clearWorkoutEffort(start, end), isFalse);
      expect(await gateway.requestWritePermission(), isTrue);

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(effort, null);
      expect(
        await gateway.setWorkoutEffort(start, end, 8),
        HealthEffortOutcome.unavailable,
      );
      expect(await gateway.clearWorkoutEffort(start, end), isFalse);
      expect(await gateway.requestWritePermission(), isTrue);
    });

    test('Android (not iOS) never calls the effort channel', () async {
      final gateway = HealthPluginPlatformService(isIOS: false);
      effortAnswer = (_) => 'written';
      expect(
        await gateway.setWorkoutEffort(start, end, 8),
        HealthEffortOutcome.unavailable,
      );
      expect(await gateway.clearWorkoutEffort(start, end), isFalse);
      expect(await gateway.requestWritePermission(), isTrue);
      expect(calls, ['plugin.requestAuthorization']);
    });

    test(
      'switching Write workouts on asks for effort first, in the same request',
      () async {
        final gateway = HealthPluginPlatformService(isIOS: true);
        effortAnswer = (_) => 'asked';
        expect(await gateway.requestWritePermission(), isTrue);
        expect(calls, [
          'effort.requestAuthorization',
          'plugin.requestAuthorization',
        ]);
      },
    );

    test('the read permission request does not ask for effort', () async {
      final gateway = HealthPluginPlatformService(isIOS: true);
      expect(await gateway.requestReadPermission(), isTrue);
      expect(calls, ['plugin.requestAuthorization']);
    });
  });
}
