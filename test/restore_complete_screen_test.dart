import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/app/startup_root.dart';
import 'package:omnitrain/features/startup/restore_complete_screen.dart';

/// Tests for the Restore-complete screen and the `AppRestart` swap
/// (plan 278b, D-27824, scenario S-27828). No Hive, no real timers:
/// the fake runner returns a plain widget tree.
void main() {
  Future<void> noopPersist(Object _, StackTrace _) async {}

  testWidgets(
    'S-27828 — showRestartRequired replaces the fake running app, disposes it and renders the Restore-complete screen',
    (WidgetTester tester) async {
      _FakeRunningAppState.disposeCount = 0;

      await tester.pumpWidget(
        StartupRoot(
          startupRunner: () async => const _FakeRunningApp(),
          onStartupFailurePersisted: noopPersist,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byType(_FakeRunningApp),
        findsOneWidget,
        reason: 'S-27828: the fake running app must be mounted before the tap',
      );

      await tester.tap(find.text('RESTART-TRIGGER'));
      await tester.pumpAndSettle();

      expect(
        find.byType(_FakeRunningApp),
        findsNothing,
        reason: 'S-27828: the fake running app must be gone after the swap',
      );
      expect(
        _FakeRunningAppState.disposeCount,
        1,
        reason:
            'S-27828: the old running app State must record dispose exactly once',
      );
      expect(
        find.byKey(const Key('restore-complete-title')),
        findsOneWidget,
        reason: 'S-27828: the restore-complete title key must be present',
      );
      expect(
        find.text('Restore complete'),
        findsOneWidget,
        reason: 'S-27828: the title copy must read "Restore complete"',
      );
      expect(
        find.text(
          'Close OmniTrain and open it again to finish. '
          'Your data is restored.',
        ),
        findsOneWidget,
        reason: 'S-27828: the body copy must be the restart instruction',
      );
      expect(
        tester.takeException(),
        isNull,
        reason: 'S-27828: the swap must not throw',
      );
    },
  );

  testWidgets(
    'S-27828 — the restore-complete screen offers no way out: no back button, no action button, system back does nothing',
    (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: RestoreCompleteScreen()));
      await tester.pumpAndSettle();

      expect(
        find.byType(BackButton),
        findsNothing,
        reason: 'S-27828: no BackButton may be rendered',
      );
      expect(
        find.byType(IconButton),
        findsNothing,
        reason: 'S-27828: no IconButton may be rendered',
      );
      expect(
        find.byType(TextButton),
        findsNothing,
        reason: 'S-27828: no TextButton may be rendered',
      );
      expect(
        find.byType(ElevatedButton),
        findsNothing,
        reason: 'S-27828: no ElevatedButton may be rendered',
      );
      expect(
        find.byType(FilledButton),
        findsNothing,
        reason: 'S-27828: no FilledButton may be rendered',
      );

      await tester.binding.handlePopRoute();
      await tester.pump();

      expect(
        find.byKey(const Key('restore-complete-title')),
        findsOneWidget,
        reason: 'S-27828: system back must leave the screen showing',
      );
      expect(
        tester.takeException(),
        isNull,
        reason: 'S-27828: a blocked system back must not throw',
      );
    },
  );

  testWidgets(
    'S-27828 — the Restore-complete screen cannot be popped by system back',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const RestoreCompleteScreen(),
                    ),
                  ),
                  child: const Text('HOST-BUTTON'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('HOST-BUTTON'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('restore-complete-title')),
        findsOneWidget,
        reason: 'S-27828: the Restore-complete screen must be pushed on top',
      );
      expect(
        find.text('HOST-BUTTON'),
        findsNothing,
        reason: 'S-27828: the host route must be covered by the pushed screen',
      );

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('restore-complete-title')),
        findsOneWidget,
        reason: 'S-27828: system back must not pop the Restore-complete screen',
      );
      expect(
        find.text('HOST-BUTTON'),
        findsNothing,
        reason: 'S-27828: the host route must stay covered after a system back',
      );
      expect(
        tester.takeException(),
        isNull,
        reason: 'S-27828: a blocked system back must not throw',
      );
    },
  );

  testWidgets(
    'S-27828 — showRestartRequired after the root is gone does nothing',
    (WidgetTester tester) async {
      VoidCallback? captured;

      await tester.pumpWidget(
        StartupRoot(
          startupRunner: () async =>
              _FakeCaptureApp(onCaptured: (callback) => captured = callback),
          onStartupFailurePersisted: noopPersist,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        captured,
        isNotNull,
        reason: 'S-27828: the fake app must capture the restart callback',
      );

      // Replaces the whole tree, disposing the StartupRoot State.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();

      captured!();

      expect(
        tester.takeException(),
        isNull,
        reason:
            'S-27828: the captured callback must be a no-op after the root is disposed',
      );
    },
  );

  testWidgets(
    'S-27828 — the screen builds with no repository or state object',
    (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: RestoreCompleteScreen()));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('restore-complete-title')),
        findsOneWidget,
        reason: 'S-27828: the title must render from a bare MaterialApp',
      );
      expect(
        find.byKey(const Key('restore-complete-body')),
        findsOneWidget,
        reason: 'S-27828: the body must render from a bare MaterialApp',
      );
      expect(
        tester.takeException(),
        isNull,
        reason: 'S-27828: building the screen alone must not throw',
      );
    },
  );

  testWidgets(
    'S-27828 — AppRestart.maybeOf returns null outside a StartupRoot',
    (WidgetTester tester) async {
      AppRestart? captured;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              captured = AppRestart.maybeOf(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pump();

      expect(
        captured,
        isNull,
        reason: 'S-27828: maybeOf must be null without a StartupRoot ancestor',
      );
    },
  );

  testWidgets(
    'S-27828 — a route pushed over the running app still finds AppRestart',
    (WidgetTester tester) async {
      _FakeRouteAppState.disposeCount = 0;

      await tester.pumpWidget(
        StartupRoot(
          startupRunner: () async => const _FakeRouteApp(),
          onStartupFailurePersisted: noopPersist,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('PUSH-ROUTE'));
      await tester.pumpAndSettle();
      expect(
        find.text('RESTART-FROM-ROUTE'),
        findsOneWidget,
        reason: 'S-27828: the pushed route must be on top of the running app',
      );

      await tester.tap(find.text('RESTART-FROM-ROUTE'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('restore-complete-title')),
        findsOneWidget,
        reason:
            'S-27828: showRestartRequired from the pushed route must swap to the restore-complete screen',
      );
      expect(
        find.byType(_FakeRouteApp),
        findsNothing,
        reason: 'S-27828: the running app must be gone after the swap',
      );
      expect(
        find.text('RESTART-FROM-ROUTE'),
        findsNothing,
        reason: 'S-27828: the pushed route must be gone after the swap',
      );
      expect(
        _FakeRouteAppState.disposeCount,
        1,
        reason: 'S-27828: the running app State must record dispose',
      );
    },
  );
}

/// A stand-in for the running app, mounted by the startup runner under
/// `StartupRoot`; its button calls `AppRestart.showRestartRequired()`.
class _FakeRunningApp extends StatefulWidget {
  const _FakeRunningApp();

  @override
  State<_FakeRunningApp> createState() => _FakeRunningAppState();
}

class _FakeRunningAppState extends State<_FakeRunningApp> {
  static int disposeCount = 0;

  @override
  void dispose() {
    disposeCount += 1;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: FilledButton(
            onPressed: () => AppRestart.maybeOf(context)!.showRestartRequired(),
            child: const Text('RESTART-TRIGGER'),
          ),
        ),
      ),
    );
  }
}

/// A stand-in that captures the `showRestartRequired` callback from
/// the `AppRestart` above it, so a test can keep the callback after
/// the whole tree is torn down.
class _FakeCaptureApp extends StatelessWidget {
  const _FakeCaptureApp({required this.onCaptured});

  final ValueChanged<VoidCallback> onCaptured;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Builder(
        builder: (context) {
          onCaptured(AppRestart.maybeOf(context)!.showRestartRequired);
          return const SizedBox.shrink();
        },
      ),
    );
  }
}

/// Same stand-in, but its button first pushes a route over itself and
/// the pushed route's button calls `showRestartRequired()`.
class _FakeRouteApp extends StatefulWidget {
  const _FakeRouteApp();

  @override
  State<_FakeRouteApp> createState() => _FakeRouteAppState();
}

class _FakeRouteAppState extends State<_FakeRouteApp> {
  static int disposeCount = 0;

  @override
  void dispose() {
    disposeCount += 1;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Builder(
            builder: (context) => FilledButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (routeContext) => Scaffold(
                      body: Center(
                        child: FilledButton(
                          onPressed: () => AppRestart.maybeOf(
                            routeContext,
                          )!.showRestartRequired(),
                          child: const Text('RESTART-FROM-ROUTE'),
                        ),
                      ),
                    ),
                  ),
                );
              },
              child: const Text('PUSH-ROUTE'),
            ),
          ),
        ),
      ),
    );
  }
}
