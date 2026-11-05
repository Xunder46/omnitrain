// S-2801: the shared "nothing here yet" widget (plan 28, phase 1 / D-28.1).
//
// `OmniEmptyState` is the one composition every empty screen and list uses, so
// this file pins its shape: the muted icon, the title, the one-line hint, the
// optional action, the smaller compact variant, and that it fits a 320x568
// phone at both theme brightnesses.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/app.dart';
import 'package:omnitrain/core/constants/omni_theme.dart';
import 'package:omnitrain/widgets/common/omni_empty_state.dart';

const Size _kShortPhone = Size(320, 568);
const String _kTitle = 'No sessions yet';
const String _kHint = 'Complete your first session to see stats here.';

/// The app's real ThemeData at [brightness]: the widget reads
/// `colorScheme.onSurface`, so the production roles — not Material's defaults —
/// must be what these assertions compare against. The app ships dark only, so
/// the light palette is the mirrors-image of the dark one at the same roles.
ThemeData _theme(Brightness brightness) {
  final colors = OmniTheme.colorsForTheme(AppTheme.abyssalNeon);
  final light = brightness == Brightness.light;
  return buildTheme(
    theme: AppTheme.abyssalNeon,
    brightness: brightness,
    secondary: colors.secondary,
    background: light ? const Color(0xFFF4F6F8) : colors.backgroundBottom,
    surface: light ? const Color(0xFFFFFFFF) : colors.surface,
    textPrimary: light ? const Color(0xFF11161C) : colors.textDominant,
    textSecondary: light ? const Color(0xFF39414B) : colors.textSecondary,
    divider: light ? const Color(0xFFD9DDE2) : colors.divider,
    onPrimary: getOnPrimaryForTheme(AppTheme.abyssalNeon),
    onSecondary: getOnSecondaryForTheme(AppTheme.abyssalNeon),
  );
}

void _useShortPhone(WidgetTester tester) {
  tester.view.physicalSize = _kShortPhone;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<void> _pump(
  WidgetTester tester, {
  required Brightness brightness,
  String title = _kTitle,
  String? hint = _kHint,
  IconData icon = Icons.inbox_outlined,
  Widget? action,
  bool compact = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: _theme(brightness),
      home: Scaffold(
        body: OmniEmptyState(
          title: title,
          hint: hint,
          icon: icon,
          action: action,
          compact: compact,
        ),
      ),
    ),
  );
}

ColorScheme _schemeOf(WidgetTester tester) =>
    Theme.of(tester.element(find.byType(OmniEmptyState))).colorScheme;

void main() {
  group('S-2801 OmniEmptyState', () {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      testWidgets('$brightness: the icon, title and hint render on a 320x568 '
          'phone without an overflow', (tester) async {
        _useShortPhone(tester);
        await _pump(tester, brightness: brightness);

        expect(find.byIcon(Icons.inbox_outlined), findsOneWidget);
        expect(find.text(_kTitle), findsOneWidget);
        expect(find.text(_kHint), findsOneWidget);
        expect(tester.takeException(), isNull);

        // The composition fits the short phone: nothing is laid out past the
        // bottom edge.
        expect(
          tester.getBottomLeft(find.text(_kHint)).dy,
          lessThanOrEqualTo(_kShortPhone.height),
        );
      });
    }

    testWidgets('the icon, title and hint carry the muted onSurface alphas', (
      tester,
    ) async {
      _useShortPhone(tester);
      await _pump(tester, brightness: Brightness.dark);

      final onSurface = _schemeOf(tester).onSurface;

      expect(
        tester.widget<Icon>(find.byIcon(Icons.inbox_outlined)).color,
        onSurface.withValues(alpha: 0.3),
        reason: 'the icon is the muted anchor of the composition',
      );
      expect(
        tester.widget<Text>(find.text(_kTitle)).style?.color,
        onSurface.withValues(alpha: 0.6),
      );
      expect(
        tester.widget<Text>(find.text(_kHint)).style?.color,
        onSurface.withValues(alpha: 0.45),
      );
    });

    testWidgets('the compact variant uses the smaller icon and keeps the '
        'title and hint', (tester) async {
      _useShortPhone(tester);
      await _pump(tester, brightness: Brightness.dark, compact: true);
      final compactSize = tester.getSize(
        find.byIcon(Icons.inbox_outlined),
      ).width;

      await _pump(tester, brightness: Brightness.dark);
      final fullSize = tester.getSize(find.byIcon(Icons.inbox_outlined)).width;

      expect(compactSize, lessThan(fullSize));
      expect(find.text(_kTitle), findsOneWidget);
      expect(find.text(_kHint), findsOneWidget);
    });

    testWidgets('the action renders below the hint', (tester) async {
      _useShortPhone(tester);
      const actionKey = Key('probe_empty_state_action');
      await _pump(
        tester,
        brightness: Brightness.dark,
        action: const TextButton(
          key: actionKey,
          onPressed: null,
          child: Text('How Stats works'),
        ),
      );

      expect(find.byKey(actionKey), findsOneWidget);
      expect(
        tester.getTopLeft(find.text(_kHint)).dy,
        lessThan(tester.getTopLeft(find.byKey(actionKey)).dy),
      );
    });

    testWidgets('a hint is optional and a long title still fits, rather than '
        'overflowing', (tester) async {
      _useShortPhone(tester);
      await _pump(
        tester,
        brightness: Brightness.dark,
        hint: null,
        title: 'Nothing is in the catalog right now, and the search field '
            'found no exercise matching what was typed',
      );

      expect(find.text(_kHint), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
