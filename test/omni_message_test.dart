// filepath: test/omni_message_test.dart
//
// S-2701 — `OmniMessage` is the one look for a small bottom message: the
// theme's surface colour, the theme's text colour, and the same corner radius
// the dialog buttons use. Placement stays the default bottom bar (D-27.1).
//
// Plan: `docs/plans/2026-10-13-27-ui-messages-plan/`.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/omni_theme.dart';
import 'package:omnitrain/widgets/feedback/omni_message.dart';

const String _message = 'Could not save the entry. Try again.';

/// Pumps a `Scaffold` whose button shows [isError] ? `OmniMessage.error` :
/// `OmniMessage.show`, then taps it so the `SnackBar` is on screen.
Future<void> _pumpAndTap(
  WidgetTester tester, {
  required ThemeData theme,
  required bool isError,
  SnackBarAction? action,
  Duration? duration,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: FilledButton(
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    OmniTheme.buttonBorderRadius,
                  ),
                ),
              ),
              onPressed: () {
                if (isError) {
                  OmniMessage.error(context, _message);
                } else {
                  OmniMessage.show(
                    context,
                    _message,
                    action: action,
                    duration: duration,
                  );
                }
              },
              child: const Text('show'),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('show'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

/// Pumps a `Scaffold` whose button captures the messenger and the theme
/// before an `await` and shows `OmniMessage.errorOn` / `OmniMessage.showOn`
/// after it — the shape used by tap handlers that persist first.
Future<void> _pumpAndTapAwaited(
  WidgetTester tester, {
  required ThemeData theme,
  required bool isError,
  SnackBarAction? action,
  Duration? duration,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: FilledButton(
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    OmniTheme.buttonBorderRadius,
                  ),
                ),
              ),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                final capturedTheme = Theme.of(context);
                // A real gap: the message must not need the context again.
                await Future<void>.value();
                if (isError) {
                  OmniMessage.errorOn(messenger, capturedTheme, _message);
                } else {
                  OmniMessage.showOn(
                    messenger,
                    capturedTheme,
                    _message,
                    action: action,
                    duration: duration,
                  );
                }
              },
              child: const Text('show'),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('show'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

SnackBar _snackBar(WidgetTester tester) =>
    tester.widget<SnackBar>(find.byType(SnackBar));

Text _messageText(WidgetTester tester) => tester.widget<Text>(
  find.descendant(of: find.byType(SnackBar), matching: find.text(_message)),
);

void main() {
  final themes = <String, ThemeData>{
    'light': ThemeData.light(),
    'dark': ThemeData.dark(),
  };

  for (final entry in themes.entries) {
    group('S-2701: OmniMessage on the ${entry.key} theme', () {
      testWidgets('show paints the theme surface and text colour', (
        tester,
      ) async {
        final theme = entry.value;

        await _pumpAndTap(tester, theme: theme, isError: false);

        final snackBar = _snackBar(tester);
        expect(snackBar.backgroundColor, theme.colorScheme.surface);
        expect(_messageText(tester).style?.color, theme.colorScheme.onSurface);
      });

      testWidgets('show uses the dialog corner radius', (tester) async {
        await _pumpAndTap(tester, theme: entry.value, isError: false);

        final shape = _snackBar(tester).shape;
        expect(shape, isA<RoundedRectangleBorder>());
        expect(
          (shape! as RoundedRectangleBorder).borderRadius,
          BorderRadius.circular(OmniTheme.buttonUtilityRadius),
        );
      });

      testWidgets('show carries no error icon', (tester) async {
        await _pumpAndTap(tester, theme: entry.value, isError: false);

        expect(find.byIcon(Icons.error_outline), findsNothing);
      });

      testWidgets('error adds the error icon in the theme error colour', (
        tester,
      ) async {
        final theme = entry.value;

        await _pumpAndTap(tester, theme: theme, isError: true);

        final icon = tester.widget<Icon>(
          find.byIcon(Icons.error_outline),
        );
        expect(icon.color, theme.colorScheme.error);
        expect(find.text(_message), findsOneWidget);
      });

      testWidgets('showOn paints the theme captured before the await', (
        tester,
      ) async {
        final theme = entry.value;

        await _pumpAndTapAwaited(tester, theme: theme, isError: false);

        final snackBar = _snackBar(tester);
        expect(snackBar.backgroundColor, theme.colorScheme.surface);
        expect(_messageText(tester).style?.color, theme.colorScheme.onSurface);
        expect(find.byIcon(Icons.error_outline), findsNothing);
      });

      testWidgets('errorOn adds the error icon captured theme error colour', (
        tester,
      ) async {
        final theme = entry.value;

        await _pumpAndTapAwaited(tester, theme: theme, isError: true);

        final icon = tester.widget<Icon>(
          find.byIcon(Icons.error_outline),
        );
        expect(icon.color, theme.colorScheme.error);
        expect(find.text(_message), findsOneWidget);
      });
    });
  }

  testWidgets('showOn passes an action and a duration through', (tester) async {
    await _pumpAndTapAwaited(
      tester,
      theme: ThemeData.light(),
      isError: false,
      action: SnackBarAction(label: 'Undo', onPressed: () {}),
      duration: const Duration(seconds: 2),
    );

    final snackBar = _snackBar(tester);
    expect(snackBar.action?.label, 'Undo');
    expect(snackBar.duration, const Duration(seconds: 2));
  });

  testWidgets('show passes an action and a duration through', (tester) async {
    await _pumpAndTap(
      tester,
      theme: ThemeData.light(),
      isError: false,
      action: SnackBarAction(label: 'Undo', onPressed: () {}),
      duration: const Duration(seconds: 2),
    );

    final snackBar = _snackBar(tester);
    expect(snackBar.action?.label, 'Undo');
    expect(snackBar.duration, const Duration(seconds: 2));
  });
}
