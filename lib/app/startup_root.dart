import 'dart:async';

import 'package:flutter/material.dart';
import '../app.dart';
import '../core/constants/omni_theme.dart';
import '../core/services/crash_reporting_service.dart';
import '../core/services/startup_failure_diagnostic_writer.dart';
import '../features/startup/startup_failure_screen.dart';

/// Signature for the routine that performs OmniTrain's startup work
/// (timezone init, repository init, state construction, theme
/// assembly, and `MyApp` widget construction) and returns the widget
/// that should be mounted on success.
///
/// On failure the routine MUST throw — `StartupRoot` catches the
/// throw, logs it for diagnostic purposes (developer console only,
/// never user-visible), and re-shows the failure screen so the user
/// can tap Retry.
typedef StartupRunner = Future<Widget> Function();
typedef StartupFailureLogger = void Function(Object error, StackTrace stackTrace);
typedef StartupFailureReporter = Future<void> Function(
  Object error,
  StackTrace stackTrace,
);
typedef StartupFailureDiagnosticPersister = Future<void> Function(
  Object error,
  StackTrace stackTrace,
);

final _startupFailureDiagnosticWriter = StartupFailureDiagnosticWriter.create();

/// Top-level widget that owns the app's startup phase.
///
/// On the first frame it invokes [startupRunner] once. Three
/// outcomes are possible:
///
///   1. Runner returns a widget → that widget is mounted and
///      becomes the running app. The failure screen never renders.
///      This is the normal-launch path; byte-for-byte identical
///      to the pre-feature behavior.
///   2. Runner throws → the failure screen is rendered with a
///      Retry button. The throw is logged for diagnostics only.
///   3. User taps Retry while on the failure screen → the runner
///      is re-invoked from the top. Success lands on outcome (1);
///      a second failure lands back on outcome (2). The cycle can
///      repeat indefinitely without leaking exceptions.
///
/// This widget exists so the production entry point (`main()`)
/// doesn't have to know about retry mechanics, and so the retry
/// path can be tested against a fake [StartupRunner] without
/// spinning up a real Hive repository or a real `MyApp`.
class StartupRoot extends StatefulWidget {
  final StartupRunner startupRunner;
  final StartupFailureLogger onStartupFailureLogged;
  final StartupFailureReporter onStartupFailureReported;
  final StartupFailureDiagnosticPersister onStartupFailurePersisted;

  /// Theme used to host the failure screen when the runner has
  /// not yet succeeded. We deliberately default to the canonical
  /// Abyssal Neon theme because at this point in the lifecycle
  /// `SettingsState` has not been constructed yet — the user
  /// will see their saved theme the moment the running app
  /// mounts. This is an acceptable degradation: the failure
  /// screen is a low-frequency surface that exists to recover
  /// from a startup error, not to showcase the user's theme.
  final ThemeData failureTheme;

  StartupRoot({
    super.key,
    required this.startupRunner,
    StartupFailureLogger? onStartupFailureLogged,
    StartupFailureReporter? onStartupFailureReported,
    StartupFailureDiagnosticPersister? onStartupFailurePersisted,
    ThemeData? failureTheme,
  })  : onStartupFailureLogged =
            onStartupFailureLogged ?? _defaultStartupFailureLogger,
        onStartupFailureReported =
            onStartupFailureReported ?? _defaultStartupFailureReporter,
      onStartupFailurePersisted =
        onStartupFailurePersisted ?? _defaultStartupFailurePersister,
        failureTheme = failureTheme ?? _defaultFailureTheme();
  // Not const — the default failure theme is computed at
  // construction time (it routes through `buildTheme`).

  @override
  State<StartupRoot> createState() => _StartupRootState();
}

ThemeData _defaultFailureTheme() {
  // Re-uses the same theme-builder as `MyApp` so the failure
  // screen's Material widgets pick up the same colorScheme,
  // typography, and Material 3 settings the rest of the app
  // uses. SettingsState-driven theme switching is intentionally
  // unavailable at this point — see the field doc on
  // [StartupRoot.failureTheme].
  final tokens = OmniTheme.colorsForTheme(AppTheme.abyssalNeon);
  return buildTheme(
    theme: AppTheme.abyssalNeon,
    brightness: Brightness.dark,
    background: tokens.backgroundBottom,
    surface: tokens.surface,
    secondary: tokens.secondary,
    textPrimary: tokens.textDominant,
    textSecondary: tokens.textSecondary,
    divider: tokens.divider,
  );
}

void _defaultStartupFailureLogger(Object error, StackTrace stackTrace) {
  // Dev-facing startup diagnostics. This does not affect the fallback
  // UI copy and remains invisible to end users.
  debugPrint('OmniTrain startup failed: $error');
  debugPrintStack(stackTrace: stackTrace);
}

Future<void> _defaultStartupFailureReporter(
  Object error,
  StackTrace stackTrace,
) {
  return CrashReportingService.recordError(
    error,
    stackTrace: stackTrace,
    errorContext: 'startup.initialization',
  );
}

Future<void> _defaultStartupFailurePersister(
  Object error,
  StackTrace stackTrace,
) {
  return _startupFailureDiagnosticWriter.writeLatestFailure(error, stackTrace);
}

Future<void> handleStartupFailure({
  required Object error,
  required StackTrace stackTrace,
  required StartupFailureLogger onStartupFailureLogged,
  required StartupFailureReporter onStartupFailureReported,
  required StartupFailureDiagnosticPersister onStartupFailurePersisted,
}) async {
  try {
    onStartupFailureLogged(error, stackTrace);
  } catch (logError, logStack) {
    // Observability hooks must never break startup-retry behavior.
    debugPrint('Startup failure logger hook failed: $logError');
    debugPrintStack(stackTrace: logStack);
  }

  try {
    await onStartupFailureReported(error, stackTrace);
  } catch (reportError, reportStack) {
    // Reporting failures are non-fatal by contract.
    debugPrint('Startup failure reporter hook failed: $reportError');
    debugPrintStack(stackTrace: reportStack);
  }

  try {
    // Keep this side-channel non-blocking so diagnostic IO can never
    // delay fallback rendering or Retry availability.
    unawaited(
      onStartupFailurePersisted(error, stackTrace).catchError((
        Object persistError,
        StackTrace persistStack,
      ) {
        debugPrint('Startup failure diagnostic hook failed: $persistError');
        debugPrintStack(stackTrace: persistStack);
      }),
    );
  } catch (persistError, persistStack) {
    // Covers synchronous throw from hook construction.
    debugPrint('Startup failure diagnostic hook failed: $persistError');
    debugPrintStack(stackTrace: persistStack);
  }
}

class _StartupRootState extends State<StartupRoot> {
  /// Holds the running app widget the moment the startup runner
  /// returns successfully. `null` means "not yet running" and
  /// the failure screen should render in its place.
  Widget? _runningApp;

  /// True while a startup attempt is in flight. Used to disable
  /// the Retry button so a fast double tap cannot trigger two
  /// concurrent startups.
  bool _attemptInFlight = false;

  @override
  void initState() {
    super.initState();
    _attempt();
  }

  /// One full startup attempt. Increments via Retry on the
  /// failure screen, and runs once automatically from
  /// `initState`.
  Future<void> _attempt() async {
    if (!mounted) return;
    setState(() => _attemptInFlight = true);
    try {
      final next = await widget.startupRunner();
      if (!mounted) return;
      setState(() => _runningApp = next);
    } catch (e, st) {
      await handleStartupFailure(
        error: e,
        stackTrace: st,
        onStartupFailureLogged: widget.onStartupFailureLogged,
        onStartupFailureReported: widget.onStartupFailureReported,
        onStartupFailurePersisted: widget.onStartupFailurePersisted,
      );
    } finally {
      if (mounted) {
        setState(() => _attemptInFlight = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = _runningApp;
    if (app != null) {
      // Happy path: the startup runner returned the real `MyApp`
      // (or any other widget the runner decided to mount).
      // Mount it directly; the failure screen never enters the
      // tree on a successful first attempt.
      return app;
    }

    // Failure path: wrap the failure screen in a MaterialApp that
    // uses the default theme tokens. We can't hand it the user's
    // saved theme — `SettingsState` doesn't exist yet — so we use
    // the canonical Abyssal Neon theme. This is acceptable for a
    // low-frequency recovery surface.
    return MaterialApp(
      title: 'Omnitrain',
      debugShowCheckedModeBanner: false,
      theme: widget.failureTheme,
      home: StartupFailureScreen(
        onRetry: _attempt,
        isRetrying: _attemptInFlight,
      ),
    );
  }
}