import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/platform/screen_awake_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(screenAwakeChannelName);

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('MethodChannelScreenAwakePort (Mock)', () {
    test('S-19515a no handler: MissingPluginException is swallowed', () async {
      final port = MethodChannelScreenAwakePort();

      await port.setKeepAwake(true);
    });

    test('S-19515b a throwing handler is swallowed', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            throw PlatformException(code: 'x');
          });
      final port = MethodChannelScreenAwakePort();

      await port.setKeepAwake(true);
    });

    test('S-19515c a recording handler sees both calls in order', () async {
      final recorded = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            recorded.add(call);
            return null;
          });
      final port = MethodChannelScreenAwakePort();

      await port.setKeepAwake(true);
      await port.setKeepAwake(false);

      expect(recorded.map((c) => c.method), ['setKeepAwake', 'setKeepAwake']);
      expect(recorded.map((c) => c.arguments), [true, false]);
    });

    test(
      'S-19515d createScreenAwakePort on macOS is a no-op, no channel traffic',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        final recorded = <MethodCall>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              recorded.add(call);
              return null;
            });

        final port = createScreenAwakePort();

        expect(port, isNot(isA<MethodChannelScreenAwakePort>()));
        await port.setKeepAwake(true);
        expect(recorded, isEmpty);
      },
    );
  });

  group('source scans', () {
    test('S-19518 the channel file is imported by lib/main.dart alone', () {
      final importers = <String>[];
      for (final entity in Directory(
        'lib',
      ).listSync(recursive: true, followLinks: false)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        // The channel file's own path carries the string; exclude it by path.
        if (entity.path.contains('screen_awake_channel')) continue;
        if (entity.readAsStringSync().contains('screen_awake_channel')) {
          importers.add(entity.path);
        }
      }

      expect(importers, ['lib/main.dart']);
    });

    test('S-19518 the channel name constant', () {
      final source = File(
        'lib/core/platform/screen_awake_channel.dart',
      ).readAsStringSync();

      expect(
        source,
        contains(
          "const String screenAwakeChannelName = 'omnitrain/screen_awake';",
        ),
      );
    });

    test(
      'S-19519 the iOS piece is inline in AppDelegate after the registrant',
      () {
        final source = File('ios/Runner/AppDelegate.swift').readAsStringSync();

        expect(source, contains('omnitrain/screen_awake'));
        expect(source, contains('setKeepAwake'));
        expect(source, contains('isIdleTimerDisabled'));

        final registrant = source.indexOf('GeneratedPluginRegistrant.register');
        final channelLine = source.indexOf('omnitrain/screen_awake');
        expect(registrant, greaterThan(-1));
        expect(channelLine, greaterThan(registrant));
      },
    );

    test('S-19519 the Android piece is in MainActivity.kt', () {
      final source = File(
        'android/app/src/main/kotlin/dev/sasha/omnitrain/MainActivity.kt',
      ).readAsStringSync();

      expect(source, contains('omnitrain/screen_awake'));
      expect(source, contains('configureFlutterEngine'));
      expect(source, contains('FLAG_KEEP_SCREEN_ON'));
      expect(source, contains('addFlags'));
      expect(source, contains('clearFlags'));
    });

    test('S-19519 project.pbxproj has no ScreenAwake', () {
      final source = File(
        'ios/Runner.xcodeproj/project.pbxproj',
      ).readAsStringSync();

      expect(source, isNot(contains('ScreenAwake')));
    });
  });
}
