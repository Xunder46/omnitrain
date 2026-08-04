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
  final List<CapturedSignal> capturedSignals = <CapturedSignal>[];
  bool _enabled = false;
  Map<String, String>? initMetadata;

  @override
  bool get isEnabled => _enabled;

  @override
  String get implementationName => 'fake';

  @override
  Future<void> init({required bool enabled, Map<String, String>? metadata}) async {
    _enabled = enabled;
    initMetadata = metadata;
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
  Future<void> recordInfoSignal({
    required String fingerprint,
    required String message,
    Map<String, String>? metadata,
    String? errorContext,
  }) async {
    capturedSignals.add(
      CapturedSignal(
        fingerprint: fingerprint,
        message: message,
        metadata: metadata ?? const <String, String>{},
        errorContext: errorContext,
      ),
    );
  }

  @override
  Future<void> recordTestCrash() async {
    // Surface as an unhandled Dart error to mirror what the production
    // wrapper does on a developer-triggered crash.
    capturedErrors.add(FlutterError('forced test crash'));
  }
}

/// Snapshot of a low-severity informational signal emitted via
/// [CrashReporter.recordInfoSignal]. Captured by [FakeCrashReporter]
/// so tests can assert on the stable fingerprint / message contract.
class CapturedSignal {
  CapturedSignal({
    required this.fingerprint,
    required this.message,
    required this.metadata,
    required this.errorContext,
  });

  final String fingerprint;
  final String message;
  final Map<String, String> metadata;
  final String? errorContext;
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
        // Identity payload must be supplied at init, not only per-event.
        expect(reporter.initMetadata, isNotNull,
            reason: 'bootstrap must forward metadata to reporter.init');
        expect(reporter.initMetadata!['appVersion'], '1.0.1+11',
            reason: 'init must receive the real app version, not a placeholder');
        expect(reporter.initMetadata!['osVersion'], isNotNull);
        expect(reporter.initMetadata!['deviceModel'], isNotNull);
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
        // Metadata is still forwarded so the reporter can store it for
        // any deferred-init path.
        expect(reporter.initMetadata, isNotNull,
            reason: 'bootstrap must forward metadata even when disabled');
      },
    );

    test(
      'bootstrap supplies a non-placeholder version label to reporter.init',
      () async {
        final reporter = FakeCrashReporter();
        await CrashReportingService.bootstrap(
          reporter: reporter,
          enabled: true,
          buildMetadata: _stubMetadata,
        );

        expect(reporter.initMetadata, isNotNull);
        final version = reporter.initMetadata!['appVersion'];
        expect(version, isNotNull);
        expect(version, isNot('unknown@unknown'),
            reason: 'Sentry placeholder must not appear — real version must be '
                'supplied at init time');
        expect(version, isNot('unknown'),
            reason: 'Generic unknown placeholder must not appear');
        expect(version, '1.0.1+11',
            reason: 'Must match the value returned by buildMetadata');
      },
    );

    test(
      'when PackageInfo is unavailable the fallback label is greppable '
      'and not a plausible real version',
      () async {
        // Simulate the startup fallback that main.dart uses when
        // PackageInfo.fromPlatform() throws.
        final reporter = FakeCrashReporter();
        await CrashReportingService.bootstrap(
          reporter: reporter,
          enabled: true,
          buildMetadata: _fallbackMetadata,
        );

        expect(reporter.isEnabled, isTrue,
            reason: 'Service must still boot when version lookup failed');
        expect(FlutterError.onError, isNotNull,
            reason: 'Handlers must still be installed after version-lookup failure');
        expect(PlatformDispatcher.instance.onError, isNotNull);
        final version = reporter.initMetadata?['appVersion'];
        expect(version, 'version-unavailable+0',
            reason: 'Fallback must be the designated greppable string, '
                'not a plausible version number like 0.0.0+0');
      },
    );

    test(
      'version, OS, and device identity recorded on reporter at boot '
      'regardless of whether any error passes through recordError',
      () async {
        // This test verifies the second gap: identity must be established
        // at SDK-initialization time so platform-originated failures
        // (which bypass recordError) still carry the full identity payload.
        final reporter = FakeCrashReporter();
        await CrashReportingService.bootstrap(
          reporter: reporter,
          enabled: true,
          buildMetadata: _stubMetadata,
        );

        // No recordError call — identity must come from init alone.
        expect(reporter.capturedErrors, isEmpty,
            reason: 'No errors reported — identity check is init-only');
        expect(reporter.initMetadata, isNotNull);
        expect(reporter.initMetadata!.keys.toSet(),
            {'appVersion', 'osVersion', 'deviceModel'},
            reason: 'Exactly three fields — the allow-list — must be supplied '
                'at init time, not more and not fewer');
        expect(reporter.initMetadata!['appVersion'], '1.0.1+11');
        expect(reporter.initMetadata!['osVersion'], 'test-os');
        expect(reporter.initMetadata!['deviceModel'], 'test-device');
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
      'exactly three fields in allow-list — no fourth field may appear '
      'even after identity moves to initialization time',
      () {
        // The allow-list contract must hold at the init payload level too.
        final cleaned = CrashReportingService.buildMetadata(
          appVersion: '1.0.1+11',
          osVersion: 'iOS 17.4',
          deviceModel: 'iPhone15,2',
        );
        expect(cleaned.keys.toSet(),
            {'appVersion', 'osVersion', 'deviceModel'},
            reason: 'A fourth field appearing here would violate privacy contract');
        expect(cleaned.length, 3,
            reason: 'Exactly three fields — length guards against silent additions');
      },
    );

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
      'below the throttle threshold the wrapper strips extra keys before '
      'forwarding to the reporter (one call → one forwarded report)',
      () async {
        final reporter = FakeCrashReporter();
        await CrashReportingService.bootstrap(
          reporter: reporter,
          enabled: true,
          buildMetadata: _stubMetadata,
          // threshold 100, well above the single call below — forwarding
          // is unconditional at this volume, so the original
          // unconditional-forwarding assertion still holds.
          throttleConfig: const CrashReportThrottleConfig(
            threshold: 100,
            cooldown: Duration(minutes: 15),
          ),
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

        expect(reporter.capturedMetadata, hasLength(1),
            reason: 'A single call below threshold must produce exactly one '
                'forwarded report');
        final payload = reporter.capturedMetadata.first;
        expect(payload.keys.toSet(),
            {'appVersion', 'osVersion', 'deviceModel'},
            reason: 'Allow-list is exactly the three identity fields for an '
                'unthrottled report');
        // No email, no screen, no leaked behavioural key.
        expect(payload.containsKey('email'), isFalse);
        expect(payload.containsKey('screen'), isFalse);
        // No suppressed-occurrence figure on an unthrottled report.
        expect(payload.containsKey('suppressedOccurrences'), isFalse,
            reason: 'suppressedOccurrences must not appear on a fresh report');
      },
    );
  });

  group('CrashReportingService per-signature rate limit', () {
    test(
      'reporting one signature beyond the threshold stops transmission '
      'at exactly the threshold count',
      () async {
        final reporter = FakeCrashReporter();
        await CrashReportingService.bootstrap(
          reporter: reporter,
          enabled: true,
          buildMetadata: _stubMetadata,
          throttleConfig: const CrashReportThrottleConfig(
            threshold: 3,
            cooldown: Duration(hours: 1),
          ),
        );

        const context = 'test_signatures::A';
        for (var i = 0; i < 7; i++) {
          await CrashReportingService.recordError(
            StateError('boom $i'),
            stackTrace: StackTrace.fromString('#0 caller'),
            errorContext: context,
          );
        }

        expect(reporter.capturedErrors, hasLength(3),
            reason: 'Exactly threshold reports must be transmitted');
        expect(reporter.capturedErrors, everyElement(isA<StateError>()));
        // All transmitted reports carry the allow-list identity only.
        for (final payload in reporter.capturedMetadata) {
          expect(payload['errorContext'], context);
          expect(payload.containsKey('suppressedOccurrences'), isFalse,
              reason: 'Below-threshold-then-throttled reports do not carry '
                  'a suppressed figure (cooldown has not elapsed)');
        }
      },
    );

    test(
      'two distinct signatures throttle independently and neither blocks '
      'the other',
      () async {
        final reporter = FakeCrashReporter();
        await CrashReportingService.bootstrap(
          reporter: reporter,
          enabled: true,
          buildMetadata: _stubMetadata,
          throttleConfig: const CrashReportThrottleConfig(
            threshold: 2,
            cooldown: Duration(hours: 1),
          ),
        );

        const contextA = 'test_signatures::A';
        const contextB = 'test_signatures::B';
        for (var i = 0; i < 5; i++) {
          await CrashReportingService.recordError(
            StateError('boom A $i'),
            stackTrace: StackTrace.fromString('#0 callerA'),
            errorContext: contextA,
          );
        }
        for (var i = 0; i < 5; i++) {
          await CrashReportingService.recordError(
            FormatException('boom B $i'),
            stackTrace: StackTrace.fromString('#0 callerB'),
            errorContext: contextB,
          );
        }

        expect(reporter.capturedErrors, hasLength(4),
            reason: 'Two signatures × threshold 2 = 4 forwarded reports');
        final contexts = reporter.capturedMetadata
            .map((m) => m['errorContext'])
            .toList();
        expect(contexts.where((c) => c == contextA), hasLength(2));
        expect(contexts.where((c) => c == contextB), hasLength(2),
            reason: 'Signature B must not be suppressed while A is throttled');
      },
    );

    test(
      'first report transmitted after a cooldown carries a '
      'suppressedOccurrences count equal to the number dropped',
      () async {
        final clock = _MutableClock(DateTime.utc(2026, 8, 3, 12));
        final reporter = FakeCrashReporter();
        await CrashReportingService.bootstrap(
          reporter: reporter,
          enabled: true,
          buildMetadata: _stubMetadata,
          throttleConfig: CrashReportThrottleConfig(
            threshold: 2,
            cooldown: const Duration(minutes: 10),
            clock: clock.now,
          ),
        );

        const context = 'test_signatures::cooldown';
        // 2 below/equal to threshold — both forwarded.
        await CrashReportingService.recordError(
          StateError('boom 1'),
          stackTrace: StackTrace.fromString('#0 caller'),
          errorContext: context,
        );
        await CrashReportingService.recordError(
          StateError('boom 2'),
          stackTrace: StackTrace.fromString('#0 caller'),
          errorContext: context,
        );
        // 3 more occurrences, all suppressed.
        for (var i = 0; i < 3; i++) {
          await CrashReportingService.recordError(
            StateError('dropped $i'),
            stackTrace: StackTrace.fromString('#0 caller'),
            errorContext: context,
          );
        }
        expect(reporter.capturedErrors, hasLength(2),
            reason: 'No reports forwarded during throttle window');
        // Advance past the cooldown and trigger one more occurrence.
        clock.advance(const Duration(minutes: 11));
        await CrashReportingService.recordError(
          StateError('resumed'),
          stackTrace: StackTrace.fromString('#0 caller'),
          errorContext: context,
        );

        expect(reporter.capturedErrors, hasLength(3),
            reason: 'Exactly one report forwarded after cooldown');
        final resumedPayload = reporter.capturedMetadata.last;
        expect(resumedPayload['suppressedOccurrences'], '3',
            reason: 'Resumed report must carry exactly the number of '
                'occurrences dropped during the cooldown window');
        // Allow-list still holds for the resumed payload.
        expect(resumedPayload.keys.toSet(),
            {'appVersion', 'osVersion', 'deviceModel',
              'errorContext', 'suppressedOccurrences'});
      },
    );

    test(
      'throttle state does not survive a service reset — fresh launch '
      'transmits the first occurrence of a previously-throttled signature',
      () async {
        final reporter = FakeCrashReporter();
        await CrashReportingService.bootstrap(
          reporter: reporter,
          enabled: true,
          buildMetadata: _stubMetadata,
          throttleConfig: const CrashReportThrottleConfig(
            threshold: 2,
            cooldown: Duration(hours: 1),
          ),
        );

        const context = 'test_signatures::reset';
        for (var i = 0; i < 5; i++) {
          await CrashReportingService.recordError(
            StateError('boom $i'),
            stackTrace: StackTrace.fromString('#0 caller'),
            errorContext: context,
          );
        }
        expect(reporter.capturedErrors, hasLength(2));

        // Reset for tests (mirrors a fresh app launch).
        CrashReportingService.resetForTests();
        await CrashReportingService.bootstrap(
          reporter: reporter,
          enabled: true,
          buildMetadata: _stubMetadata,
          throttleConfig: const CrashReportThrottleConfig(
            threshold: 2,
            cooldown: Duration(hours: 1),
          ),
        );

        await CrashReportingService.recordError(
          StateError('post-reset'),
          stackTrace: StackTrace.fromString('#0 caller'),
          errorContext: context,
        );
        expect(reporter.capturedErrors, hasLength(3),
            reason: 'Throttle state must clear on reset; the next occurrence '
                'is forwarded');
        final postResetPayload = reporter.capturedMetadata.last;
        expect(postResetPayload['errorContext'], context);
        expect(postResetPayload.containsKey('suppressedOccurrences'), isFalse,
            reason: 'A fresh state has nothing suppressed to report');
      },
    );

    test(
      'a signature reported below the threshold is never throttled and '
      'never carries a suppressedOccurrences figure',
      () async {
        final reporter = FakeCrashReporter();
        await CrashReportingService.bootstrap(
          reporter: reporter,
          enabled: true,
          buildMetadata: _stubMetadata,
          throttleConfig: const CrashReportThrottleConfig(
            threshold: 100,
            cooldown: Duration(minutes: 15),
          ),
        );

        const context = 'test_signatures::light';
        for (var i = 0; i < 5; i++) {
          await CrashReportingService.recordError(
            StateError('boom $i'),
            stackTrace: StackTrace.fromString('#0 caller'),
            errorContext: context,
          );
        }

        expect(reporter.capturedErrors, hasLength(5),
            reason: 'All 5 occurrences below the threshold are forwarded');
        for (final payload in reporter.capturedMetadata) {
          expect(payload.containsKey('suppressedOccurrences'), isFalse,
              reason: 'No suppressed figure should appear when nothing was '
                  'suppressed');
        }
      },
    );
  });
}

/// Manually-controllable clock used by the cooldown test. Real production
/// uses DateTime.now() via [CrashReportThrottleConfig]'s default clock.
class _MutableClock {
  _MutableClock(this._now);

  DateTime _now;

  DateTime now() => _now;

  void advance(Duration d) {
    _now = _now.add(d);
  }
}

Map<String, String> _stubMetadata() => <String, String>{
      'appVersion': '1.0.1+11',
      'osVersion': 'test-os',
      'deviceModel': 'test-device',
    };

/// Simulates the fallback path in main.dart when PackageInfo.fromPlatform()
/// throws — the version must be the designated greppable string.
Map<String, String> _fallbackMetadata() => <String, String>{
      'appVersion': 'version-unavailable+0',
      'osVersion': 'test-os',
      'deviceModel': 'test-device',
    };
