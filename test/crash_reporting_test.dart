// Tests for the crash-reporting integration.
//
// Two responsibilities:
//   1. Global error routing. In release (enabled: true) the harness installs
//      both FlutterError.onError and PlatformDispatcher.onError handlers; in
//      debug they are left untouched.
//   2. Metadata allow-list. Anything outside {appVersion, osVersion, deviceModel}
//      is dropped at the boundary, so a future SDK upgrade or accidental
//      context.setTag call can never widen the data-collection footprint.
//
// Scenario coverage map:
//   S-001, S-002 — global error routing tests below dispatch the errors
//                  the SDK would normally receive.
//   S-003        — `enabled: false` path proves debug builds do not route.
//   S-004        — enforced by `scripts/pre_release_check.sh` (not a Dart test).
//   S-005        — metadata allow-list tests.

import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/crash_reporting_service.dart';

// A fake reporter that records every event it is asked to capture so tests
// can assert on payloads without spinning up the real Sentry SDK.
class FakeCrashReporter implements CrashReporter {
  final List<Object> capturedErrors = <Object>[];
  final List<Map<String, String>> capturedMetadata =
      <Map<String, String>>[];
  final List<StackTrace> capturedStacks = <StackTrace>[];
  bool _enabled = false;

  @override
  bool get isEnabled => _enabled;

  @override
  String get implementationName => 'fake';

  @override
  Future<void> init({required bool enabled, Map<String, String>? metadata}) async {
    _enabled = enabled;
  }

  @override
  Future<void> recordError(
    Object error, {
    StackTrace? stackTrace,
    Map<String, String>? metadata,
    String? errorContext,
  }) async {
    capturedErrors.add(error);
    capturedStacks.add(stackTrace ?? StackTrace.empty);
    if (metadata != null) capturedMetadata.add(metadata);
  }

  @override
  Future<void> recordTestCrash() async {
    // Surface as an unhandled Dart error to mirror what the production
    // wrapper does on a developer-triggered crash.
    capturedErrors.add(FlutterError('forced test crash'));
  }
}

void main() {
  // Reset the framework-installed error sinks between tests so a handler
  // installed under `enabled: true` does not leak into the `enabled: false`
  // case.
  FlutterExceptionHandler? savedFlutterOnError;
  ErrorCallback? savedPlatformOnError;

  setUp(() {
    savedFlutterOnError = FlutterError.onError;
    savedPlatformOnError = PlatformDispatcher.instance.onError;
    FlutterError.onError = null;
    PlatformDispatcher.instance.onError = null;
    // The bootstrap is idempotent at runtime; tests need a fresh instance
    // each time so the new fake reporter and a new enabled flag are used.
    CrashReportingService.resetForTests();
  });

  tearDown(() {
    FlutterError.onError = savedFlutterOnError;
    PlatformDispatcher.instance.onError = savedPlatformOnError;
    CrashReportingService.resetForTests();
  });

  group('CrashReportingService.bootstrap', () {
    test(
      'enabled: true installs both FlutterError.onError and '
      'PlatformDispatcher.onError handlers',
      () async {
        final reporter = FakeCrashReporter();
        await CrashReportingService.bootstrap(
          reporter: reporter,
          enabled: true,
          buildMetadata: _stubMetadata,
        );

        expect(FlutterError.onError, isNotNull,
            reason: 'Flutter framework error sink should be installed in release');
        expect(PlatformDispatcher.instance.onError, isNotNull,
            reason: 'PlatformDispatcher async-error sink should be installed in '
                'release');
        expect(reporter.isEnabled, isTrue);
      },
    );

    test(
      'enabled: false leaves both handlers untouched '
      '(debug builds do not report)',
      () async {
        final reporter = FakeCrashReporter();
        await CrashReportingService.bootstrap(
          reporter: reporter,
          enabled: false,
          buildMetadata: _stubMetadata,
        );

        expect(FlutterError.onError, isNull,
            reason: 'Debug builds must not install a Flutter error sink');
        expect(PlatformDispatcher.instance.onError, isNull,
            reason: 'Debug builds must not install a PlatformDispatcher sink');
        expect(reporter.isEnabled, isFalse);
      },
    );

    test(
      'FlutterError.onError forwards the framework error to the reporter',
      () async {
        final reporter = FakeCrashReporter();
        await CrashReportingService.bootstrap(
          reporter: reporter,
          enabled: true,
          buildMetadata: _stubMetadata,
        );

        final details = FlutterErrorDetails(
          exception: StateError('boom from a build'),
          stack: StackTrace.fromString('#0 frameworkLine\n#1 caller'),
        );
        FlutterError.onError!(details);

        await Future<void>.delayed(Duration.zero);

        expect(reporter.capturedErrors, isNotEmpty);
        expect(reporter.capturedErrors.first, isA<StateError>());
      },
    );

    test(
      'PlatformDispatcher.onError forwards async errors to the reporter',
      () async {
        final reporter = FakeCrashReporter();
        await CrashReportingService.bootstrap(
          reporter: reporter,
          enabled: true,
          buildMetadata: _stubMetadata,
        );

        final result = PlatformDispatcher.instance.onError!(
          StateError('async boom'),
          StackTrace.fromString('#0 zone (boom)\n#1 caller'),
        );
        await Future<void>.delayed(Duration.zero);

        expect(result, isTrue,
            reason: 'Handler must signal it handled the error');
        expect(reporter.capturedErrors, isNotEmpty);
        expect(reporter.capturedErrors.first, isA<StateError>());
      },
    );
  });

  group('CrashReportingService.buildMetadata (allow-list)', () {
    test(
      'returns only appVersion, osVersion, deviceModel — drops everything else',
      () {
        final cleaned = CrashReportingService.buildMetadata(
          appVersion: '1.0.1+11',
          osVersion: 'iOS 17.4',
          deviceModel: 'iPhone15,2',
          extra: <String, String>{
            'user_id': 'u-abc-123',
            'email': 'someone@example.com',
            'location': '37.77,-122.41',
            'screen': 'home',
            'event': 'tap_save',
            'install_id': 'ga-1',
          },
        );

        expect(cleaned.keys.toSet(),
            {'appVersion', 'osVersion', 'deviceModel'});
        expect(cleaned['appVersion'], '1.0.1+11');
        expect(cleaned['osVersion'], 'iOS 17.4');
        expect(cleaned['deviceModel'], 'iPhone15,2');
      },
    );

    test(
      'still sanitizes when extra is empty',
      () {
        final cleaned = CrashReportingService.buildMetadata(
          appVersion: '1.0.1+11',
          osVersion: 'Android 14',
          deviceModel: 'Pixel 8 Pro',
        );

        expect(cleaned.keys.toSet(),
            {'appVersion', 'osVersion', 'deviceModel'});
        expect(cleaned['deviceModel'], 'Pixel 8 Pro');
      },
    );
  });

  group('CrashReportingService.recordError allow-list', () {
    test(
      'the wrapper strips extra keys before forwarding to the reporter',
      () async {
        final reporter = FakeCrashReporter();
        await CrashReportingService.bootstrap(
          reporter: reporter,
          enabled: true,
          buildMetadata: _stubMetadata,
        );

        await CrashReportingService.recordError(
          StateError('boom with extras'),
          stackTrace: StackTrace.fromString('#0 caller'),
          metadata: <String, String>{
            'appVersion': '1.0.1+11',
            'osVersion': 'iOS 17.4',
            'deviceModel': 'iPhone15,2',
            'email': 'someone@example.com',
            'screen': 'home',
          },
        );

        expect(reporter.capturedMetadata, hasLength(1));
        final payload = reporter.capturedMetadata.first;
        expect(payload.keys.toSet(),
            {'appVersion', 'osVersion', 'deviceModel'});
        // No email, no screen, no leaked behavioural key.
        expect(payload.containsKey('email'), isFalse);
        expect(payload.containsKey('screen'), isFalse);
      },
    );
  });
}

Map<String, String> _stubMetadata() => <String, String>{
      'appVersion': '1.0.1+11',
      'osVersion': 'test-os',
      'deviceModel': 'test-device',
    };
