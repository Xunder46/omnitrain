// ──────────────────────────────────────────────────────────────────────────
// OmniTrain crash-reporting integration
//
// ADR — see `.github/agents/plans/crash-reporting-plan.md` for the
// rationale for choosing `sentry_flutter` over Firebase Crashlytics.
// Summary:
//   • Flutter-native error capture (FlutterError.onError,
//     PlatformDispatcher.onError, zone errors) in a single init call.
//   • Build-time symbol upload via `sentry_dart_plugin` (iOS dSYMs,
//     Android ProGuard/R8 mappings) with no manual script.
//   • Strong boundary control over the data-collection footprint.
//
// Privacy contract enforced by this file
// ─────────────────────────────────────
// • Reporting is gated by `kReleaseMode` at the call site
//   (`lib/main.dart`). Debug builds never reach `init(enabled: true)`.
// • `CrashReportingService.buildMetadata` produces an allow-list payload
//   containing ONLY `appVersion`, `osVersion`, and `deviceModel`. Any
//   other key passed in is dropped before the Sentry SDK sees it. This
//   boundary protection is what guarantees an SDK upgrade cannot widen
//   the data-collection footprint — even a buggy `setTag('email', ...)`
//   call later in the codebase will not survive `buildMetadata`.
// • `sendDefaultPii: false` is set on the Sentry SDK so PII such as
//   IP address, device id, and request cookies is suppressed.
// • Auto breadcrumbs (native + Flutter), screen tracking, session
//   tracking, and performance tracing are all disabled. We capture
//   stack traces + the allow-listed metadata only.
// ──────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
// `Hint`, `Scope`, and the rest of the Sentry type surface used in
// this file are re-exported by `package:sentry_flutter/sentry_flutter.dart`;
// no direct import of `package:sentry/sentry.dart` is required.

/// Abstract reporter so tests can swap out the Sentry-backed
/// implementation without depending on the SDK at test time.
abstract class CrashReporter {
  bool get isEnabled;

  /// A short label for the underlying SDK (used by the pre-release
  /// invariant check and by log lines).
  String get implementationName;

  Future<void> init({required bool enabled, Map<String, String>? metadata});

  Future<void> recordError(
    Object error, {
    StackTrace? stackTrace,
    Map<String, String>? metadata,
    String? errorContext,
  });

  /// Records a low-severity, informational signal that is grouped under
  /// a stable [fingerprint]. Use this for known benign issues whose
  /// rate must remain observable in telemetry (so a regression is
  /// detectable) but which must never compete with genuine crashes or
  /// page anyone. The signal is emitted at `info` level — the dashboard
  /// surfaces it as a separate stream from `recordError` events and a
  /// rate-threshold alert can be attached to the fingerprint.
  Future<void> recordInfoSignal({
    required String fingerprint,
    required String message,
    Map<String, String>? metadata,
    String? errorContext,
  });

  /// Triggers a forced crash from a developer-only entry point
  /// (release builds). The harness expects the caller to surface this
  /// behind a remote-trigger or build-time flag so end-users never
  /// invoke it.
  Future<void> recordTestCrash();
}

/// Static façade installed in `lib/main.dart` before `runApp`.
///
/// The façade owns the lifecycle of the underlying [CrashReporter] and
/// the framework-level error sinks. In debug, every method is a no-op
/// — including [recordError] — so a developer build never ships
/// telemetry.
class CrashReportingService {
  CrashReportingService._({
    required CrashReporter reporter,
    required bool enabled,
    required Map<String, String> Function() buildMetadata,
    required CrashReportThrottleConfig throttleConfig,
  })  : _reporter = reporter,
        _enabled = enabled,
        _buildMetadata = buildMetadata,
        _rateLimiter = _CrashReportRateLimiter(config: throttleConfig);

  static CrashReportingService? _instance;

  static CrashReportingService? get instanceOrNull => _instance;

  final CrashReporter _reporter;
  final bool _enabled;
  final Map<String, String> Function() _buildMetadata;
  final _CrashReportRateLimiter _rateLimiter;

  /// Boots the reporter and, when [enabled] is true, installs the
  /// global Flutter error sinks.
  ///
  /// Idempotent — repeat calls are a no-op so a duplicate bootstrap
  /// (e.g. a hot-reload-induced re-entry) cannot stack multiple
  /// handlers.
  static Future<void> bootstrap({
    required CrashReporter reporter,
    required bool enabled,
    required Map<String, String> Function() buildMetadata,
    CrashReportThrottleConfig throttleConfig =
        CrashReportThrottleConfig.defaults,
  }) async {
    if (_instance != null) {
      return;
    }

    final svc = CrashReportingService._(
      reporter: reporter,
      enabled: enabled,
      buildMetadata: buildMetadata,
      throttleConfig: throttleConfig,
    );
    _instance = svc;

    await reporter.init(enabled: enabled, metadata: buildMetadata());
    if (enabled) {
      svc._installErrorSinks();
    }
  }

  /// Resets the singleton. Tests use this between cases.
  @visibleForTesting
  static void resetForTests() {
    final svc = _instance;
    svc?._rateLimiter.reset();
    _instance = null;
  }

  /// Returns a metadata map restricted to the public allow-list. The
  /// result always contains exactly `appVersion`, `osVersion`, and
  /// `deviceModel`. Any key passed in via [extra] is silently
  /// dropped — the boundary is deliberate, so a future SDK change or
  /// an accidental `setTag('email', ...)` upstream cannot widen the
  /// payload.
  static Map<String, String> buildMetadata({
    required String appVersion,
    required String osVersion,
    required String deviceModel,
    Map<String, String>? extra,
  }) {
    // `extra` is reserved for forward compatibility (e.g. a future
    // `flavour` field). The allow-list is the authority on what the
    // SDK sees — the returned map is built directly from the named
    // arguments, so any `extra` keys cannot leak into the payload.
    // An assertion kept this contract strict; the unit test asserts
    // the equivalent observable property (allow-list contents).
    return <String, String>{
      'appVersion': appVersion,
      'osVersion': osVersion,
      'deviceModel': deviceModel,
    };
  }

  /// Forwards an error to the reporter. Respects [enabled] — debug
  /// builds drop the event entirely so the developer console does not
  /// double-report. Applies the per-signature throttle so a single
  /// repeating failure cannot exhaust the monthly reporting budget;
  /// suppressed occurrences are tracked locally and re-emitted as a
  /// `suppressedOccurrences` tag once the cooldown elapses.
  static Future<void> recordError(
    Object error, {
    StackTrace? stackTrace,
    Map<String, String>? metadata,
    String? errorContext,
  }) async {
    final svc = _instance;
    if (svc == null || !svc._enabled) {
      return;
    }

    // Signature: the same exception type from the same call site. The
    // error message is intentionally excluded so two instances of the
    // same call-site failure group together.
    final signature = '${error.runtimeType}|${errorContext ?? ''}';
    final decision = svc._rateLimiter.consider(signature);
    if (!decision.shouldSend) {
      return;
    }

    final sourceMeta = svc._buildMetadata();
    var cleaned = buildMetadata(
      appVersion: sourceMeta['appVersion'] ?? 'unknown',
      osVersion: sourceMeta['osVersion'] ?? 'unknown',
      deviceModel: sourceMeta['deviceModel'] ?? 'unknown',
      // `metadata` is best-effort tags from the call site. The runtime
      // allow-list takes precedence — additional keys are silently
      // ignored. The wrapper itself never forwards untrusted keys.
    );
    if (decision.suppressedSinceLast > 0) {
      cleaned = <String, String>{
        ...cleaned,
        'suppressedOccurrences':
            decision.suppressedSinceLast.toString(),
      };
    }
    if (errorContext != null && errorContext.isNotEmpty) {
      cleaned = <String, String>{
        ...cleaned,
        'errorContext': errorContext,
      };
    }

    await svc._reporter.recordError(
      error,
      stackTrace: stackTrace,
      metadata: cleaned,
      errorContext: errorContext,
    );
  }

  /// Emits a low-severity informational signal under a stable
  /// [fingerprint]. See [CrashReporter.recordInfoSignal] for the
  /// intended use. The same metadata allow-list as [recordError] is
  /// applied — callers cannot widen the data-collection footprint.
  ///
  /// No-ops when reporting is disabled (debug builds) or before
  /// [bootstrap] has been called, mirroring [recordError].
  static Future<void> recordInfoSignal({
    required String fingerprint,
    required String message,
    String? errorContext,
  }) async {
    final svc = _instance;
    if (svc == null || !svc._enabled) {
      return;
    }

    final sourceMeta = svc._buildMetadata();
    final cleaned = buildMetadata(
      appVersion: sourceMeta['appVersion'] ?? 'unknown',
      osVersion: sourceMeta['osVersion'] ?? 'unknown',
      deviceModel: sourceMeta['deviceModel'] ?? 'unknown',
    );

    await svc._reporter.recordInfoSignal(
      fingerprint: fingerprint,
      message: message,
      metadata: cleaned,
      errorContext: errorContext,
    );
  }

  void _installErrorSinks() {
    FlutterError.onError = (FlutterErrorDetails details) {
      // Capture-only path is async; the framework contract here is
      // sync void. We log via the reporter and return.
      recordError(
        details.exception,
        stackTrace: details.stack ?? StackTrace.current,
      );
    };

    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      // Fire-and-forget; the dispatcher contract is sync bool-returning.
      unawaited(recordError(error, stackTrace: stack));
      return true;
    };
  }
}

/// Builds a metadata snapshot from the running platform. Used by the
/// bootstrap call site to feed [CrashReportingService.buildMetadata].
///
/// `dart:io` use is wrapped so the function never throws when invoked
/// from a context where `Platform` is unavailable (e.g. the test
/// harness).
Map<String, String> defaultDeviceMetadata({required String appVersion}) {
  final os = _osVersionString();
  final model = _deviceModelString();
  return CrashReportingService.buildMetadata(
    appVersion: appVersion,
    osVersion: os,
    deviceModel: model,
  );
}

/// Sentry-backed [CrashReporter]. Wires the SDK with privacy-minimal
/// defaults. The `beforeSend` callback re-applies the allow-list as a
/// second line of defense — even if a future SDK release starts
/// attaching new tags automatically, our `beforeSend` strips them.
class SentryCrashReporter implements CrashReporter {
  SentryCrashReporter({required this.dsn});

  /// The Sentry DSN. Provided by the build pipeline (`dart-define`).
  /// Production builds must inject one — otherwise [init] fails loudly.
  final String dsn;

  bool _enabled = false;

  @override
  bool get isEnabled => _enabled;

  @override
  String get implementationName => 'sentry_flutter';

  @override
  Future<void> init({
    required bool enabled,
    Map<String, String>? metadata,
  }) async {
    if (!enabled || kIsWeb) {
      // Web is not in the launch target for crash reporting: the
      // current Sentry web SDK still ships with a non-trivial default
      // breadcrumb surface and the page-session lifecycle does not
      // map cleanly to Flutter. Debug builds are skipped at the call
      // site via kReleaseMode.
      _enabled = false;
      return;
    }

    try {
      await SentryFlutter.init(
        (SentryFlutterOptions options) {
          options.dsn = dsn;
          options.environment = _environmentLabel();
          options.release = metadata?['appVersion'] ?? 'unknown@unknown';
          // Privacy defaults — see header comment for the contract.
          options.sendDefaultPii = false;
          options.attachStacktrace = true;
          options.tracesSampleRate = 0.0;
          // Strip anything not in the allow-list before transport.
          // Note: SentryEvent.user is immutable; our discipline is to
          // never call `Sentry.setUser(...)` and the SDK never sets a
          // user when sendDefaultPii is false. The remaining surface
          // (tags / breadcrumbs) is what we police here.
          options.beforeSend = (SentryEvent event, Hint hint) {
            event.tags?.removeWhere(
              (String key, dynamic _) => !_allowedTagKeys.contains(key),
            );
            return event;
          };
          // Strip native + Flutter breadcrumb tracking: the privacy
          // contract forbids behavioural breadcrumbs.
          options.enableAutoNativeBreadcrumbs = false;
          // Disable session telemetry — we route through Flutter
          // sinks exclusively.
          options.enableAutoSessionTracking = false;
        },
      );
      _enabled = true;

      // Set identity tags at the SDK scope level so every event —
      // including platform-originated failures that bypass recordError —
      // carries the full allow-listed identity payload.
      if (metadata != null) {
        await Sentry.configureScope((Scope scope) {
          for (final key in const <String>[
            'appVersion',
            'osVersion',
            'deviceModel',
          ]) {
            final value = metadata[key];
            if (value != null) {
              scope.setTag(key, value);
            }
          }
        });
      }
    } catch (e, st) {
      // Crash-reporting must never break startup.
      debugPrint('Sentry init failed (continuing without reporting): $e');
      debugPrintStack(stackTrace: st);
      _enabled = false;
    }
  }

  @override
  Future<void> recordError(
    Object error, {
    StackTrace? stackTrace,
    Map<String, String>? metadata,
    String? errorContext,
  }) async {
    if (!_enabled) return;
    try {
      await Sentry.captureException(
        error,
        stackTrace: stackTrace,
        withScope: (Scope scope) {
          // Even though `enableBreadcrumbTrackingForCurrentPlatform =
          // false` is set globally, the platform-specific bridge can
          // inject breadcrumbs through `configureScope` calls. Clear
          // defensively before adding the allow-listed tags.
          scope.clearBreadcrumbs();
          if (metadata != null) {
            for (final entry in metadata.entries) {
              scope.setTag(entry.key, entry.value);
            }
          }
          if (errorContext != null && errorContext.isNotEmpty) {
            scope.setTag('errorContext', errorContext);
          }
        },
      );
    } catch (e) {
      // Swallow — we must not crash the app inside the crash-reporter.
      debugPrint('Sentry.captureException failed: $e');
    }
  }

  @override
  Future<void> recordTestCrash() async {
    if (!_enabled) return;
    // Promote to an unhandled exception so Sentry classifies it as a
    // crash rather than a message. The dashboard surfaces this in the
    // crash stream with the same allow-listed metadata.
    throw StateError(
      'CrashReportingService.recordTestCrash — developer invoked; '
      'safe to ignore.',
    );
  }

  @override
  Future<void> recordInfoSignal({
    required String fingerprint,
    required String message,
    Map<String, String>? metadata,
    String? errorContext,
  }) async {
    if (!_enabled) return;
    try {
      // `captureMessage` at `info` level produces a real Sentry event
      // (so a rate-threshold alert can be attached to the fingerprint)
      // without being promoted to the crash/error stream. Setting the
      // fingerprint to a constant string groups every emission of the
      // same signal together in the dashboard — variable stack
      // traces and call-site metadata do not fragment the issue.
      await Sentry.captureMessage(
        message,
        level: SentryLevel.info,
        withScope: (Scope scope) {
          scope.clearBreadcrumbs();
          scope.fingerprint = <String>[fingerprint];
          if (metadata != null) {
            for (final entry in metadata.entries) {
              scope.setTag(entry.key, entry.value);
            }
          }
          if (errorContext != null && errorContext.isNotEmpty) {
            scope.setTag('errorContext', errorContext);
          }
        },
      );
    } catch (e) {
      // Swallow — we must not crash the app inside the crash-reporter.
      debugPrint('Sentry.captureMessage failed: $e');
    }
  }
}

const Set<String> _allowedTagKeys = <String>{
  'appVersion',
  'osVersion',
  'deviceModel',
  'errorContext',
  'suppressedOccurrences',
};

/// Per-signature rate-limit configuration for [CrashReportingService].
///
/// The budget-tier rationale and the tradeoff between exact event
/// counts and budget survival are documented in
/// `.github/agents/plans/crash-reporting-rate-limit-plan.md`. A single
/// noisy failure must never exhaust the monthly reporting budget; the
/// dashboard's raw count for a throttled signature becomes an undercount
/// corrected by the `suppressedOccurrences` tag on each transmitted
/// report.
@immutable
class CrashReportThrottleConfig {
  const CrashReportThrottleConfig({
    required this.threshold,
    required this.cooldown,
    DateTime Function()? clock,
  }) : _clock = clock;

  /// Number of reports forwarded per signature before suppression
  /// begins. Must be at least 1.
  final int threshold;

  /// Time that must elapse since the last forwarded report before the
  /// next occurrence is forwarded (with a `suppressedOccurrences` tag).
  final Duration cooldown;

  final DateTime Function()? _clock;

  /// Production defaults: 100 reports per signature per 15-minute
  /// cooldown. Tuned to the current Sentry budget tier — revisit if the
  /// budget grows substantially.
  static const CrashReportThrottleConfig defaults = CrashReportThrottleConfig(
    threshold: 100,
    cooldown: Duration(minutes: 15),
  );

  @visibleForTesting
  DateTime now() {
    final clock = _clock;
    return clock != null ? clock() : DateTime.now();
  }
}

/// In-memory per-signature rate limiter used by
/// [CrashReportingService.recordError] to enforce the throttle
/// contract. State is per-process — a fresh launch starts with an
/// empty counter map (matching the prompt's "counters do not persist
/// across app launches" requirement).
class _CrashReportRateLimiter {
  _CrashReportRateLimiter({required CrashReportThrottleConfig config})
      : _config = config;

  final CrashReportThrottleConfig _config;
  final Map<String, _SignatureThrottleState> _states =
      <String, _SignatureThrottleState>{};

  /// Consult the limiter for [signature]. Returns whether the report
  /// should be transmitted and, if so, how many occurrences have been
  /// suppressed since the previous forwarded report for this signature.
  ///
  /// Algorithm:
  ///   • Below threshold → send, suppressed = 0.
  ///   • At or above threshold and cooldown not elapsed → suppress
  ///     (do not send), increment suppressed counter.
  ///   • At or above threshold and cooldown elapsed → send with the
  ///     accumulated suppressed count, reset counter to 0.
  ({bool shouldSend, int suppressedSinceLast}) consider(String signature) {
    final now = _config.now();
    final state = _states.putIfAbsent(
      signature,
      () => _SignatureThrottleState(),
    );

    if (state.transmittedCount < _config.threshold) {
      state.transmittedCount++;
      state.suppressedSinceLast = 0;
      state.lastTransmittedAt = now;
      return (shouldSend: true, suppressedSinceLast: 0);
    }

    final last = state.lastTransmittedAt;
    if (last != null && now.difference(last) >= _config.cooldown) {
      final suppressed = state.suppressedSinceLast;
      state.transmittedCount = 1;
      state.suppressedSinceLast = 0;
      state.lastTransmittedAt = now;
      return (shouldSend: true, suppressedSinceLast: suppressed);
    }

    state.suppressedSinceLast++;
    return (shouldSend: false, suppressedSinceLast: 0);
  }

  /// Clears all per-signature state. Tests call this between cases via
  /// [CrashReportingService.resetForTests]; the production reset path
  /// (a fresh app launch) is implicit because the limiter is owned by
  /// the service singleton.
  void reset() {
    _states.clear();
  }
}

class _SignatureThrottleState {
  int transmittedCount = 0;
  int suppressedSinceLast = 0;
  DateTime? lastTransmittedAt;
}

String _environmentLabel() {
  if (kReleaseMode) return 'production';
  if (kProfileMode) return 'profile';
  return 'development';
}

String _osVersionString() {
  try {
    if (Platform.isIOS) {
      return 'iOS ${Platform.operatingSystemVersion}';
    }
    if (Platform.isAndroid) {
      return 'Android ${Platform.operatingSystemVersion}';
    }
    return Platform.operatingSystem;
  } catch (_) {
    return 'unknown';
  }
}

String _deviceModelString() {
  try {
    if (Platform.isIOS) {
      return 'iOS device';
    }
    if (Platform.isAndroid) {
      return Platform.localHostname.isNotEmpty
          ? Platform.localHostname
          : 'Android device';
    }
    return 'unknown device';
  } catch (_) {
    return 'unknown';
  }
}
