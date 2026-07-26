// Tests for the startup-failure screen and the retry path that
// re-runs the entire `main()` initialization sequence. The
// scenarios in `.github/agents/plans/startup-failure-screen-plan.md`
// (S-001..S-004) map 1:1 to the four tests below.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/app.dart';
import 'package:omnitrain/app/startup_root.dart';
import 'package:omnitrain/core/models/app_version_info.dart';
import 'package:omnitrain/core/services/preferences_service.dart';
import 'package:omnitrain/core/services/startup_failure_diagnostic_writer.dart';
import 'package:omnitrain/core/utils/rest_notification_service.dart';
import 'package:omnitrain/core/utils/timer_alert_service.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/startup/startup_failure_screen.dart';
import 'package:omnitrain/main.dart' as app_main;

class _CapturedStartupFailure {
  _CapturedStartupFailure(this.error, this.stackTrace);

  final Object error;
  final StackTrace stackTrace;
}

Future<void> _noopPersist(Object _, StackTrace __) async {}
void _noopLog(Object _, StackTrace __) {}

class _FakePreferencesService implements PreferencesService {
  int _hubOpenCount = 0;

  @override
  Future<void> init() async {}

  @override
  int getHubOpenCount() => _hubOpenCount;

  @override
  Future<void> incrementHubOpenCount() async {
    _hubOpenCount += 1;
  }
}

class _SucceedingRestNotificationService extends RestNotificationService {
  _SucceedingRestNotificationService() : super.noop();

  bool initializeCalled = false;

  @override
  Future<void> initialize() async {
    initializeCalled = true;
  }
}

class _FailingRestNotificationService extends RestNotificationService {
  _FailingRestNotificationService(this.error, this.stackTrace) : super.noop();

  final Object error;
  final StackTrace stackTrace;
  bool initializeCalled = false;

  @override
  Future<void> initialize() async {
    initializeCalled = true;
    Error.throwWithStackTrace(error, stackTrace);
  }
}

void main() {
  group('StartupFailureScreen', () {
    testWidgets(
      'S-001 — copy has no developer terminology and the Retry control is present',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: StartupFailureScreen(onRetry: () {}),
          ),
        );
        await tester.pumpAndSettle();

        // Collect every visible Text payload in the widget tree,
        // lowercased, so a single contains() check covers every
        // label we render (headline, secondary line, button text).
        final visibleText = tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => (t.data ?? '').toLowerCase())
            .join('\n');

        // The explicit assertions called out in the acceptance
        // criteria: no "console", no raw error text, no log
        // language, no exception/stack/debug/developer verbiage.
        expect(visibleText, isNot(contains('console')));
        expect(visibleText, isNot(contains('error')));
        expect(visibleText, isNot(contains('exception')));
        expect(visibleText, isNot(contains('stack')));
        expect(visibleText, isNot(contains('debug')));
        expect(visibleText, isNot(contains('developer')));

        // Retry control is visible and enabled.
        final retryFinder = find.widgetWithText(FilledButton, 'Retry');
        expect(retryFinder, findsOneWidget);
        final FilledButton retry = tester.widget(retryFinder);
        expect(retry.onPressed, isNotNull);
      },
    );
  });

  group('StartupRoot — retry wiring', () {
    testWidgets(
      'S-002 — tapping Retry re-invokes the startup routine exactly once more',
      (WidgetTester tester) async {
        var callCount = 0;

        Future<Widget> alwaysFail() async {
          callCount += 1;
          throw StateError('simulated startup failure');
        }

        await tester.pumpWidget(
          StartupRoot(
            startupRunner: alwaysFail,
            onStartupFailurePersisted: _noopPersist,
          ),
        );
        await tester.pumpAndSettle();

        // The first attempt runs from initState.
        expect(callCount, 1);
        expect(find.byType(StartupFailureScreen), findsOneWidget);

        await tester.tap(find.widgetWithText(FilledButton, 'Retry'));
        await tester.pumpAndSettle();

        // Exactly one additional invocation — no surprise retries.
        expect(callCount, 2);
        expect(find.byType(StartupFailureScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'S-003 — retry after a transient failure lands in the normal app surface',
      (WidgetTester tester) async {
        var attempt = 0;

        Future<Widget> recoverOnRetry() async {
          attempt += 1;
          if (attempt == 1) {
            throw StateError('transient');
          }
          // Wrap in a MaterialApp so the Scaffold has the
          // Directionality ancestor it requires — mirrors what
          // `MyApp(...)` does in production.
          return const MaterialApp(
            home: Scaffold(body: Text('APP-SURFACE-MARKER')),
          );
        }

        await tester.pumpWidget(
          StartupRoot(
            startupRunner: recoverOnRetry,
            onStartupFailurePersisted: _noopPersist,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(StartupFailureScreen), findsOneWidget);
        expect(find.text('APP-SURFACE-MARKER'), findsNothing);

        await tester.tap(find.widgetWithText(FilledButton, 'Retry'));
        await tester.pumpAndSettle();

        // After the retry succeeds the failure screen is gone and
        // the widget the runner returned is now mounted.
        expect(find.byType(StartupFailureScreen), findsNothing);
        expect(find.text('APP-SURFACE-MARKER'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'S-004 — repeated retries under persistent failure stay on the failure screen without throwing',
      (WidgetTester tester) async {
        var callCount = 0;

        Future<Widget> persistentFailure() async {
          callCount += 1;
          throw StateError('never recovers');
        }

        await tester.pumpWidget(
          StartupRoot(
            startupRunner: persistentFailure,
            onStartupFailurePersisted: _noopPersist,
          ),
        );
        await tester.pumpAndSettle();

        for (var i = 0; i < 3; i++) {
          expect(
            find.byType(StartupFailureScreen),
            findsOneWidget,
            reason: 'failure screen must remain on iteration $i',
          );
          expect(
            tester.takeException(),
            isNull,
            reason: 'no exception must escape on iteration $i',
          );

          await tester.tap(find.widgetWithText(FilledButton, 'Retry'));
          await tester.pumpAndSettle();
        }

        // Initial attempt + 3 retries = 4 runner invocations.
        expect(callCount, 4);
        expect(find.byType(StartupFailureScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'S-005 — a successful first attempt never renders the failure screen',
      (WidgetTester tester) async {
        Future<Widget> succeedImmediately() async {
          return const MaterialApp(
            home: Scaffold(body: Text('FIRST-LAUNCH-SURFACE')),
          );
        }

        await tester.pumpWidget(
          StartupRoot(
            startupRunner: succeedImmediately,
            onStartupFailurePersisted: _noopPersist,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(StartupFailureScreen), findsNothing);
        expect(find.text('FIRST-LAUNCH-SURFACE'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('StartupRoot — startup-failure observability', () {
    testWidgets(
      'forwards the original startup exception + stack trace to the log hook',
      (WidgetTester tester) async {
        final stack = StackTrace.current;
        final error = StateError('simulated startup crash');
        final captured = <_CapturedStartupFailure>[];

        Future<Widget> alwaysFail() async {
          Error.throwWithStackTrace(error, stack);
        }

        await tester.pumpWidget(
          StartupRoot(
            startupRunner: alwaysFail,
            onStartupFailureLogged: (Object e, StackTrace st) {
              captured.add(_CapturedStartupFailure(e, st));
            },
            onStartupFailurePersisted: _noopPersist,
          ),
        );
        await tester.pumpAndSettle();

        expect(captured, hasLength(1));
        expect(identical(captured.first.error, error), isTrue);
        expect(identical(captured.first.stackTrace, stack), isTrue);
      },
    );

    testWidgets(
      'reports startup failure exactly once with the same error object',
      (WidgetTester tester) async {
        final stack = StackTrace.current;
        final error = ArgumentError('bad startup state');
        final reported = <_CapturedStartupFailure>[];

        Future<Widget> alwaysFail() async {
          Error.throwWithStackTrace(error, stack);
        }

        await tester.pumpWidget(
          StartupRoot(
            startupRunner: alwaysFail,
            onStartupFailureReported: (Object e, StackTrace st) async {
              reported.add(_CapturedStartupFailure(e, st));
            },
            onStartupFailurePersisted: _noopPersist,
          ),
        );
        await tester.pumpAndSettle();

        expect(reported, hasLength(1));
        expect(identical(reported.first.error, error), isTrue);
        expect(identical(reported.first.stackTrace, stack), isTrue);
      },
    );

    testWidgets(
      'successful startup does not trigger startup-failure log or report hooks',
      (WidgetTester tester) async {
        var logCalls = 0;
        var reportCalls = 0;

        Future<Widget> succeedImmediately() async {
          return const MaterialApp(
            home: Scaffold(body: Text('SUCCESS-ONLY')),
          );
        }

        await tester.pumpWidget(
          StartupRoot(
            startupRunner: succeedImmediately,
            onStartupFailureLogged: (_, __) => logCalls += 1,
            onStartupFailureReported: (_, __) async => reportCalls += 1,
            onStartupFailurePersisted: _noopPersist,
          ),
        );
        await tester.pumpAndSettle();

        expect(logCalls, 0);
        expect(reportCalls, 0);
        expect(find.text('SUCCESS-ONLY'), findsOneWidget);
      },
    );
  });

  group('Startup notification initialization', () {
    test(
      'runStartup still returns the running app when notification initialization fails',
      () async {
        final startupIssue = <_CapturedStartupFailure>[];
        final initError = StateError('invalid_icon');
        final initStack = StackTrace.fromString('#0 notification init');

        final app = await app_main.runStartup(
          createRepository: () async => MockWorkoutRepository(),
          createPreferencesService: () => _FakePreferencesService(),
          createTimerAlertService: () => TimerAlertService.forTesting(isWeb: true),
          createRestNotificationService: () =>
              _FailingRestNotificationService(initError, initStack),
          createImageStorageService: () async => null,
          loadAppVersionInfo: () async =>
              const AppVersionInfo(version: '1.0.0', build: '1'),
          onNonFatalStartupIssue: (Object error, StackTrace stackTrace) async {
            startupIssue.add(_CapturedStartupFailure(error, stackTrace));
          },
        );

        expect(app, isA<MyApp>());
        expect(startupIssue, hasLength(1));
        expect(
          startupIssue.single.error.toString(),
          contains('Non-fatal startup notification initialization failure'),
        );
        expect(
          startupIssue.single.error.toString(),
          contains('invalid_icon'),
        );
        expect(identical(startupIssue.single.stackTrace, initStack), isTrue);

        final myApp = app as MyApp;
        expect(myApp.restNotificationService, isNot(isA<_FailingRestNotificationService>()));
      },
    );

    testWidgets(
      'notification initialization failure does not show the startup failure screen',
      (WidgetTester tester) async {
        final initError = StateError('invalid_icon');
        final initStack = StackTrace.fromString('#0 notification init');

        await tester.pumpWidget(
          StartupRoot(
            startupRunner: () => app_main.runStartup(
              createRepository: () async => MockWorkoutRepository(),
              createPreferencesService: () => _FakePreferencesService(),
              createTimerAlertService: () =>
                  TimerAlertService.forTesting(isWeb: true),
              createRestNotificationService: () =>
                  _FailingRestNotificationService(initError, initStack),
              createImageStorageService: () async => null,
              loadAppVersionInfo: () async =>
                  const AppVersionInfo(version: '1.0.0', build: '1'),
              onNonFatalStartupIssue: (_, __) async {},
            ),
            onStartupFailurePersisted: _noopPersist,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(StartupFailureScreen), findsNothing);
        expect(find.byType(MyApp), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    test(
      'successful notification initialization keeps the original notification service',
      () async {
        final notificationService = _SucceedingRestNotificationService();
        var nonFatalCalls = 0;

        final app = await app_main.runStartup(
          createRepository: () async => MockWorkoutRepository(),
          createPreferencesService: () => _FakePreferencesService(),
          createTimerAlertService: () => TimerAlertService.forTesting(isWeb: true),
          createRestNotificationService: () => notificationService,
          createImageStorageService: () async => null,
          loadAppVersionInfo: () async =>
              const AppVersionInfo(version: '1.0.0', build: '1'),
          onNonFatalStartupIssue: (_, __) async => nonFatalCalls += 1,
        );

        expect(app, isA<MyApp>());
        expect(notificationService.initializeCalled, isTrue);
        expect(nonFatalCalls, 0);
        expect(
          identical(
            (app as MyApp).restNotificationService,
            notificationService,
          ),
          isTrue,
        );
      },
    );
  });

  group('StartupRoot — startup-failure diagnostic file', () {
    test(
      'writes the latest startup failure error + stack trace to a file',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'omnitrain_startup_diag_test_1_',
        );
        addTearDown(() async {
          if (tempDir.existsSync()) {
            await tempDir.delete(recursive: true);
          }
        });

        final writer = StartupFailureDiagnosticWriter.fromBaseDirectory(
          tempDir.path,
        );
        final writeDone = Completer<void>();
        final expectedStack = StackTrace.current;
        final expectedError = StateError('startup-file-test-first');

        await handleStartupFailure(
          error: expectedError,
          stackTrace: expectedStack,
          onStartupFailureLogged: _noopLog,
          onStartupFailureReported: _noopPersist,
          onStartupFailurePersisted: (Object e, StackTrace st) async {
            await writer.writeLatestFailure(e, st);
            writeDone.complete();
          },
        );
        await writeDone.future;

        final diagnosticFile = File(
          '${tempDir.path}${Platform.pathSeparator}'
          '${StartupFailureDiagnosticWriter.diagnosticFileName}',
        );

        expect(diagnosticFile.existsSync(), isTrue);
        final text = diagnosticFile.readAsStringSync();
        expect(text, contains('error: $expectedError'));
        expect(text, contains('$expectedStack'));
      },
    );

    test(
      'consecutive startup failures overwrite the file with only the latest error',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'omnitrain_startup_diag_test_2_',
        );
        addTearDown(() async {
          if (tempDir.existsSync()) {
            await tempDir.delete(recursive: true);
          }
        });

        final writer = StartupFailureDiagnosticWriter.fromBaseDirectory(
          tempDir.path,
        );
        final firstDone = Completer<void>();
        final secondDone = Completer<void>();

        await handleStartupFailure(
          error: StateError('startup-first-failure'),
          stackTrace: StackTrace.current,
          onStartupFailureLogged: _noopLog,
          onStartupFailureReported: _noopPersist,
          onStartupFailurePersisted: (Object e, StackTrace st) async {
            await writer.writeLatestFailure(e, st);
            firstDone.complete();
          },
        );
        await firstDone.future;

        await handleStartupFailure(
          error: StateError('startup-second-failure'),
          stackTrace: StackTrace.current,
          onStartupFailureLogged: _noopLog,
          onStartupFailureReported: _noopPersist,
          onStartupFailurePersisted: (Object e, StackTrace st) async {
            await writer.writeLatestFailure(e, st);
            secondDone.complete();
          },
        );
        await secondDone.future;

        final diagnosticFile = File(
          '${tempDir.path}${Platform.pathSeparator}'
          '${StartupFailureDiagnosticWriter.diagnosticFileName}',
        );
        expect(diagnosticFile.existsSync(), isTrue);

        final text = diagnosticFile.readAsStringSync();
        expect(text, contains('startup-second-failure'));
        expect(text, isNot(contains('startup-first-failure')));
      },
    );

    test(
      'file-write failure does not let an exception escape the write attempt',
      () async {
        await handleStartupFailure(
          error: StateError('still failing'),
          stackTrace: StackTrace.current,
          onStartupFailureLogged: _noopLog,
          onStartupFailureReported: _noopPersist,
          onStartupFailurePersisted: (Object _, StackTrace __) async {
            throw FileSystemException('simulated diagnostic write failure');
          },
        );

        // If we reach this line, the failing persister did not escape
        // through the startup-failure handler.
        expect(true, isTrue);
      },
    );
  });
}