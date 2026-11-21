// The Android side's configuration, read as source: the wear flavor, its
// manifest, the capabilities each side advertises, the plugin's Android
// registration, and the production wrist entry point.
//
// Plan: `docs/plans/2026-11-20-280-wear-os-shell-plan/2026-11-20-280-wear-os-shell-plan.md`
// (D-28002, D-28003, D-28007, D-28008). Scenario mapping:
//   S-28030 the app has a `phone` and a `wear` flavor
//   S-28031 the wear manifest is the one that declares watch hardware
//   S-28032 each side advertises the capability the other looks for
//   S-28033 the link plugin is registered for Android and carries the data layer
//   S-28034 the wrist entry point is production, not a debug harness
//   S-28035 both release invocations name the phone flavor
//
// These are the assertions a desktop test can make about things that only exist
// as files. What they cannot prove — that the APK installs and pairs — is what
// the plan's QA section says a watch has to show.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) {
  final file = File(path);
  expect(file.existsSync(), isTrue, reason: '$path should exist');
  return file.readAsStringSync();
}

void main() {
  group('S-28030 flavors', () {
    test('the app builds a phone and a wear flavor', () {
      final gradle = _read('android/app/build.gradle.kts');
      expect(gradle, contains('flavorDimensions'));
      expect(gradle, contains('create("phone")'));
      expect(gradle, contains('create("wear")'));
    });

    test('the wear flavor raises the floor to Wear OS 3', () {
      final gradle = _read('android/app/build.gradle.kts');
      final wear = gradle.substring(gradle.indexOf('create("wear")'));
      expect(wear, contains('minSdk = 30'));
    });
  });

  group('S-28031 the wear manifest', () {
    test('declares watch hardware and only the wear flavor does', () {
      final wearManifest = _read('android/app/src/wear/AndroidManifest.xml');
      expect(wearManifest, contains('android.hardware.type.watch'));
      expect(wearManifest, contains('android:required="true"'));

      final mainManifest = _read('android/app/src/main/AndroidManifest.xml');
      expect(
        mainManifest,
        isNot(contains('android.hardware.type.watch')),
        reason: 'the phone build must not claim to be a watch app',
      );
    });
  });

  group('S-28032 capabilities', () {
    test('each side advertises what the other looks for', () {
      final wear = _read('android/app/src/wear/res/values/wear.xml');
      final phone = _read('android/app/src/phone/res/values/wear.xml');
      expect(wear, contains('<item>omnitrain_wear</item>'));
      expect(phone, contains('<item>omnitrain_phone</item>'));

      final plugin = _read(
        'packages/omnitrain_watch_link/android/src/main/kotlin/dev/sasha/'
        'omnitrain/watch_link/OmniTrainWatchLinkPlugin.kt',
      );
      expect(plugin, contains('"omnitrain_phone"'));
      expect(plugin, contains('"omnitrain_wear"'));
    });
  });

  group('S-28033 the link plugin', () {
    test('is registered for Android', () {
      final pubspec = _read('packages/omnitrain_watch_link/pubspec.yaml');
      expect(pubspec, contains('android:'));
      expect(pubspec, contains('pluginClass: OmniTrainWatchLinkPlugin'));
    });

    test('carries the Wear data layer and the same five calls iOS answers', () {
      final gradle = _read(
        'packages/omnitrain_watch_link/android/build.gradle.kts',
      );
      expect(gradle, contains('play-services-wearable'));

      final plugin = _read(
        'packages/omnitrain_watch_link/android/src/main/kotlin/dev/sasha/'
        'omnitrain/watch_link/OmniTrainWatchLinkPlugin.kt',
      );
      for (final call in <String>[
        '"status"',
        '"sendMessage"',
        '"transferUserInfo"',
        '"outstandingTransfers"',
        '"cancelTransfers"',
      ]) {
        expect(plugin, contains(call), reason: '$call is part of the contract');
      }
      for (final kind in <String>['"message"', '"userInfo"', '"reachability"']) {
        expect(plugin, contains(kind));
      }
    });
  });

  group('S-28034 the wrist entry point', () {
    test('is the production app, built on the real store and the radio', () {
      final main = _read('lib/watch/wear_main.dart');
      expect(main, contains('HiveWatchSessionStore'));
      expect(main, contains('WearWatchTransport'));
      expect(main, contains('runApp('));
      expect(main, contains('WearApp('));

      // The four QA harnesses stay harnesses: none of them is what the wear
      // build runs.
      for (final harness in <String>[
        'lib/watch/debug/watch_start_debug_main.dart',
        'lib/watch/debug/watch_logging_debug_main.dart',
        'lib/watch/debug/watch_session_debug_main.dart',
      ]) {
        expect(
          File(harness).readAsStringSync().toLowerCase(),
          contains('debug entry point'),
          reason: '$harness should stay a harness',
        );
      }
    });
  });

  group('S-28035 the release invocations', () {
    test('name the phone flavor', () {
      expect(
        _read('.github/workflows/release.yml'),
        contains('flutter build appbundle --release --flavor phone'),
      );
      expect(
        _read('scripts/pre_release_check.sh'),
        contains('flutter build appbundle --release --flavor phone'),
      );
    });

    test('the gate still looks for an unflavored artifact', () {
      // An artifact left by an older build must still be inspected rather than
      // skipped, so the gate's §11r keeps working across the flavor change.
      final gate = _read('scripts/pre_release_check.sh');
      expect(gate, contains('build/app/outputs/bundle/phoneRelease/'));
      expect(gate, contains('build/app/outputs/bundle/release/app-release.aab'));
      expect(gate, contains('mapping/phoneRelease/seeds.txt'));
      expect(gate, contains('mapping/release/seeds.txt'));
    });
  });
}
