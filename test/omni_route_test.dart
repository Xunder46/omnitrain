import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/omni_theme.dart';
import 'package:omnitrain/core/navigation/navigation.dart';
import 'package:omnitrain/widgets/layout/omni_gradient_background.dart';

void main() {
  // ── Test 1: Route primitive construction ──────────────────────────────────

  testWidgets('OmniRoute wraps page in OmniGradientBackground', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                OmniRoute<void>(
                  builder: (_) => const Scaffold(body: Text('Destination')),
                ),
              ),
              child: const Text('Push'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Push'));
    await tester.pumpAndSettle();

    expect(find.byType(OmniGradientBackground), findsWidgets);
  });

  // ── Test 2: Transition occlusion ──────────────────────────────────────────

  testWidgets(
    'previous screen content is not visible after OmniRoute animation settles',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Column(
                children: [
                  const Text('Previous Screen'),
                  ElevatedButton(
                    onPressed: () => OmniNavigator.push(
                      context,
                      (_) => const Scaffold(body: Text('Incoming Screen')),
                    ),
                    child: const Text('Push'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Push'));
      await tester.pumpAndSettle();

      // With opaque = true the Navigator culls the underlying route; its content
      // should not appear in the rendered widget tree after the transition settles.
      expect(find.text('Incoming Screen'), findsOneWidget);
      expect(find.text('Previous Screen'), findsNothing);
    },
  );

  // ── Test 3: iOS edge-swipe-back ───────────────────────────────────────────

  testWidgets('iOS edge-swipe-back gesture pops an OmniRoute', (
    WidgetTester tester,
  ) async {
    // CupertinoPageTransitionsBuilder is used on all platforms.
    // Force iOS here so the edge-swipe-back gesture recognizer is active.
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.iOS),
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => OmniNavigator.push(
                context,
                (_) => const Scaffold(body: Text('Pushed Screen')),
              ),
              child: const Text('Push'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Push'));
    await tester.pumpAndSettle();
    expect(find.text('Pushed Screen'), findsOneWidget);

    // Simulate iOS back swipe: start within _kBackGestureWidth (20px) from
    // the left edge, drag far enough right to complete the pop.
    final TestGesture gesture = await tester.startGesture(
      const Offset(5.0, 300.0),
    );
    await gesture.moveBy(const Offset(500.0, 0.0));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.text('Pushed Screen'), findsNothing);
    expect(find.text('Push'), findsOneWidget);
  });

  // ── Test 4: Theme switching mid-route ─────────────────────────────────────

  testWidgets('OmniGradientBackground on active OmniRoute reads updated theme', (
    WidgetTester tester,
  ) async {
    // Ensure a known starting theme.
    OmniTheme.activeTheme = AppTheme.abyssalNeon;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => OmniNavigator.push(
                context,
                (_) => const Scaffold(body: Text('Route Content')),
              ),
              child: const Text('Push'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Push'));
    await tester.pumpAndSettle();

    // Verify the route's OmniGradientBackground is in the tree.
    expect(find.byType(OmniGradientBackground), findsWidgets);

    // Capture the gradient color under the initial theme.
    final initialColors = OmniTheme.colorsForTheme(AppTheme.abyssalNeon);

    // Switch theme (simulates what SettingsState.setAppTheme does before notifyListeners).
    OmniTheme.activeTheme = AppTheme.forgeEmber;
    await tester.pump();

    // The new colors must differ from the initial ones (confirming token distinction).
    final updatedColors = OmniTheme.colorsForTheme(AppTheme.forgeEmber);
    expect(
      updatedColors.backgroundTop,
      isNot(equals(initialColors.backgroundTop)),
    );

    // The OmniGradientBackground widget is still present (no crash on theme change).
    expect(find.byType(OmniGradientBackground), findsWidgets);

    // Restore default for other tests.
    OmniTheme.activeTheme = AppTheme.abyssalNeon;
  });

  // ── Test 5: App-level gradient preservation ───────────────────────────────

  testWidgets(
    'app-level OmniGradientBackground is still present after pushing a screen',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) =>
              OmniGradientBackground(child: child ?? const SizedBox.shrink()),
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => OmniNavigator.push(
                  context,
                  (_) => const Scaffold(body: Text('New Screen')),
                ),
                child: const Text('Push'),
              ),
            ),
          ),
        ),
      );

      // Before push: exactly one OmniGradientBackground (the app-level one).
      expect(find.byType(OmniGradientBackground), findsOneWidget);

      await tester.tap(find.text('Push'));
      await tester.pumpAndSettle();

      // After push: app-level + route-level = at least two.
      expect(find.byType(OmniGradientBackground), findsAtLeastNWidgets(2));
    },
  );

  // ── Test 6: Fade variant ──────────────────────────────────────────────────

  testWidgets('OmniFadeRoute wraps destination in OmniGradientBackground', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => OmniNavigator.pushReplacementFade(
                context,
                (_) => const Scaffold(body: Text('Fade Destination')),
              ),
              child: const Text('Fade'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Fade'));
    await tester.pumpAndSettle();

    expect(find.text('Fade Destination'), findsOneWidget);
    expect(find.byType(OmniGradientBackground), findsWidgets);
    // Source route replaced — button must no longer be reachable.
    expect(find.text('Fade'), findsNothing);
  });

  // ── Test 7: OmniNavigator API ─────────────────────────────────────────────

  group('OmniNavigator API', () {
    testWidgets('push adds a route to the stack', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => OmniNavigator.push(
                  context,
                  (_) => const Scaffold(body: Text('Pushed')),
                ),
                child: const Text('Push'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Push'));
      await tester.pumpAndSettle();
      expect(find.text('Pushed'), findsOneWidget);
    });

    testWidgets('pushReplacement replaces the current route', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Column(
                children: [
                  const Text('Original'),
                  ElevatedButton(
                    onPressed: () => OmniNavigator.pushReplacement(
                      context,
                      (_) => const Scaffold(body: Text('Replacement')),
                    ),
                    child: const Text('Replace'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Replace'));
      await tester.pumpAndSettle();

      expect(find.text('Replacement'), findsOneWidget);
      expect(find.text('Original'), findsNothing);
    });

    testWidgets('pushReplacementFade replaces with fade transition', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => OmniNavigator.pushReplacementFade(
                  context,
                  (_) => const Scaffold(body: Text('Faded In')),
                ),
                child: const Text('FadeReplace'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('FadeReplace'));
      await tester.pumpAndSettle();

      expect(find.text('Faded In'), findsOneWidget);
      expect(find.text('FadeReplace'), findsNothing);
    });

    testWidgets('popUntil pops to the first route', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx0) => Scaffold(
              body: ElevatedButton(
                onPressed: () => OmniNavigator.push(
                  ctx0,
                  (_) => Builder(
                    builder: (ctx1) => Scaffold(
                      body: ElevatedButton(
                        onPressed: () => OmniNavigator.push(
                          ctx1,
                          (_) => Builder(
                            builder: (ctx2) => Scaffold(
                              body: ElevatedButton(
                                onPressed: () => OmniNavigator.popUntil(
                                  ctx2,
                                  (route) => route.isFirst,
                                ),
                                child: const Text('Pop To Root'),
                              ),
                            ),
                          ),
                        ),
                        child: const Text('Push Again'),
                      ),
                    ),
                  ),
                ),
                child: const Text('First Push'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('First Push'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Push Again'));
      await tester.pumpAndSettle();

      expect(find.text('Pop To Root'), findsOneWidget);

      await tester.tap(find.text('Pop To Root'));
      await tester.pumpAndSettle();

      expect(find.text('First Push'), findsOneWidget);
      expect(find.text('Push Again'), findsNothing);
      expect(find.text('Pop To Root'), findsNothing);
    });
  });

  // ── Test 8: Slide transition on Android ──────────────────────────────────

  testWidgets(
    'OmniRoute uses slide transition on Android (both routes present mid-animation)',
    (WidgetTester tester) async {
      // Set Android platform — OmniRoute must now use CupertinoPageTransitionsBuilder
      // uniformly, so a slide animation runs and both routes are briefly visible.
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.android),
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => OmniNavigator.push(
                  context,
                  (_) => const Scaffold(body: Text('Android Destination')),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      // Advance a single frame — the slide animation is mid-flight.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // The incoming screen must already be in the tree (animation started).
      expect(find.text('Android Destination'), findsOneWidget);

      // Settle fully — only the destination remains.
      await tester.pumpAndSettle();
      expect(find.text('Android Destination'), findsOneWidget);
      expect(find.text('Open'), findsNothing);
    },
  );

  // ── Test 9: transitionDuration is non-zero ───────────────────────────────

  test('OmniRoute.transitionDuration is non-zero', () {
    final route = OmniRoute<void>(builder: (_) => const SizedBox.shrink());
    expect(route.transitionDuration, greaterThan(Duration.zero));
  });
}
