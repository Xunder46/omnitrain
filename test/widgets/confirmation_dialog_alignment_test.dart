// Owner request (2026-10-13): the unsaved-changes dialog must look like the
// destructive two-choice dialog, so the two cannot drift. Owner decision
// (2026-10-18): it offers only Keep editing / Discard (no Save), because
// three actions did not fit one row on a phone.
//
// Pinned here:
// - the dialog has no X/`IconButton`; its actions are Keep editing
//   (TextButton) and Discard (destructive FilledButton), left to right, with
//   no Save
// - PARITY: Discard carries the same background, foreground and shape as a
//   destructive two-choice confirm; Keep editing carries the same
//   text-button shape as Cancel
// - no overflow and both actions stay tappable on a 280-wide and a 320x568
//   view. Whether the two fit one row depends on the real font: flutter_test
//   renders every glyph 14 px wide, so the row is not asserted here
// - a barrier tap still coalesces to keep editing
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/omni_theme.dart';
import 'package:omnitrain/widgets/dialogs/confirmation_dialog.dart';

const String _kBody =
    'You have unsaved edits. Discard them to return to the summary.';

const Key _kUnsavedKeep = Key('align-unsaved-keep');
const Key _kUnsavedDiscard = Key('align-unsaved-discard');

const Key _kTwoChoiceDismiss = Key('align-two-dismiss');
const Key _kTwoChoiceConfirm = Key('align-two-confirm');

/// A dark scheme whose `error`/`primary` are far apart, so a swapped
/// destructive style cannot pass unnoticed.
ThemeData _theme() => ThemeData(
  brightness: Brightness.dark,
  colorScheme: const ColorScheme.dark(
    primary: Color(0xFF1166CC),
    onPrimary: Color(0xFFF0F4F8),
    error: Color(0xFFB3261E),
    onError: Color(0xFFFFFFFF),
  ),
);

/// The unsaved-changes prompt as a static widget (the same two-choice dialog
/// [ConfirmationDialog.showUnsavedChanges] shows).
Widget _unsavedPrompt() => ConfirmationDialog.twoChoice(
  title: 'Unsaved changes',
  body: const Text(_kBody),
  dismissLabel: 'Keep editing',
  confirmLabel: 'Discard',
  dismissKey: _kUnsavedKeep,
  confirmKey: _kUnsavedDiscard,
  isDestructive: true,
);

Widget _destructiveTwoChoice() => ConfirmationDialog.twoChoice(
  title: 'Discard session?',
  body: const Text('This session will be discarded and cannot be recovered.'),
  dismissLabel: 'Cancel',
  confirmLabel: 'Discard',
  dismissKey: _kTwoChoiceDismiss,
  confirmKey: _kTwoChoiceConfirm,
  isDestructive: true,
);

/// Mounts [dialog] as the whole body; enough for shape/colour assertions.
Future<void> _pumpStatic(WidgetTester tester, Widget dialog) async {
  await tester.pumpWidget(
    MaterialApp(theme: _theme(), home: Scaffold(body: dialog)),
  );
  await tester.pumpAndSettle();
}

/// The `Material` a [ButtonStyleButton] builds, which carries the resolved
/// colour and shape the user actually sees.
Material _buttonMaterial(WidgetTester tester, Key key) => tester.widget<Material>(
  find.descendant(of: find.byKey(key), matching: find.byType(Material)).first,
);

ButtonStyle _buttonStyle(WidgetTester tester, Key key) =>
    (tester.widget(find.byKey(key)) as ButtonStyleButton).style!;

Color? _foregroundOf(WidgetTester tester, Key key) =>
    _buttonStyle(tester, key).foregroundColor?.resolve(const <WidgetState>{});

void main() {
  group('Mock ConfirmationDialog - unsaved-changes alignment', () {
    testWidgets('offers Keep editing then Discard, with no X and no Save', (
      WidgetTester tester,
    ) async {
      await _pumpStatic(tester, _unsavedPrompt());

      final dialog = find.byType(AlertDialog);
      expect(dialog, findsOneWidget);
      expect(
        find.descendant(of: dialog, matching: find.byType(IconButton)),
        findsNothing,
        reason: 'the title carries no X close affordance',
      );
      expect(
        find.descendant(of: dialog, matching: find.text('Keep editing')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dialog, matching: find.text('Discard')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dialog, matching: find.text('Save')),
        findsNothing,
        reason: 'every guarded form has its own Save button',
      );

      final keep = tester.getRect(find.byKey(_kUnsavedKeep));
      final discard = tester.getRect(find.byKey(_kUnsavedDiscard));
      expect(
        keep.left,
        lessThan(discard.left),
        reason: 'Keep editing is the first (leftmost) action',
      );
    });

    testWidgets('PARITY: Discard matches a destructive confirm, Keep editing '
        'matches Cancel', (WidgetTester tester) async {
      final theme = _theme();

      await _pumpStatic(tester, _unsavedPrompt());
      final discard = _buttonMaterial(tester, _kUnsavedDiscard);
      final discardForeground = _foregroundOf(tester, _kUnsavedDiscard);
      final keepShape = _buttonMaterial(tester, _kUnsavedKeep).shape;

      await _pumpStatic(tester, _destructiveTwoChoice());
      final twoConfirm = _buttonMaterial(tester, _kTwoChoiceConfirm);
      final twoConfirmForeground = _foregroundOf(tester, _kTwoChoiceConfirm);
      final twoDismissShape = _buttonMaterial(tester, _kTwoChoiceDismiss).shape;

      const utilityShape = RoundedRectangleBorder(
        borderRadius: BorderRadius.all(
          Radius.circular(OmniTheme.buttonUtilityRadius),
        ),
      );

      expect(discard.color, twoConfirm.color);
      expect(discardForeground, twoConfirmForeground);
      expect(discard.shape, twoConfirm.shape);
      expect(keepShape, twoDismissShape);

      // Anchors, so both sides drifting together still fails.
      expect(discard.color, theme.colorScheme.error);
      expect(discardForeground, theme.colorScheme.onError);
      expect(discard.shape, utilityShape);
      expect(keepShape, utilityShape);
    });

    testWidgets('PARITY: the destructive fill is not the primary fill', (
      WidgetTester tester,
    ) async {
      final theme = _theme();

      await _pumpStatic(tester, _unsavedPrompt());
      expect(
        _buttonMaterial(tester, _kUnsavedDiscard).color,
        isNot(theme.colorScheme.primary),
      );

      await _pumpStatic(tester, _destructiveTwoChoice());
      expect(
        _buttonMaterial(tester, _kTwoChoiceConfirm).color,
        isNot(theme.colorScheme.primary),
      );
    });

    for (final size in <Size>[Size(280, 700), Size(320, 568)]) {
      testWidgets(
        'both actions stay tappable without overflow at '
        '${size.width.toInt()}x${size.height.toInt()}',
        (WidgetTester tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);

          bool? result;

          await tester.pumpWidget(
            MaterialApp(
              theme: _theme(),
              home: Scaffold(
                body: Builder(
                  builder: (context) => Center(
                    child: ElevatedButton(
                      onPressed: () async {
                        result = await ConfirmationDialog.showUnsavedChanges(
                          context: context,
                          title: 'Unsaved changes',
                          body: _kBody,
                          keepEditingKey: _kUnsavedKeep,
                          discardKey: _kUnsavedDiscard,
                        );
                      },
                      child: const Text('open dialog'),
                    ),
                  ),
                ),
              ),
            ),
          );

          final expected = <Key, bool>{
            _kUnsavedKeep: false,
            _kUnsavedDiscard: true,
          };

          for (final entry in expected.entries) {
            await tester.tap(find.text('open dialog'));
            await tester.pumpAndSettle();
            expect(find.byType(AlertDialog), findsOneWidget);

            // Keep editing comes first, whether the actions share a row or
            // stack.
            expect(
              tester.getRect(find.byKey(_kUnsavedKeep)).top,
              lessThanOrEqualTo(
                tester.getRect(find.byKey(_kUnsavedDiscard)).top,
              ),
            );

            await tester.tap(find.byKey(entry.key));
            await tester.pumpAndSettle();

            expect(
              tester.takeException(),
              isNull,
              reason: 'no layout overflow at '
                  '${size.width.toInt()}x${size.height.toInt()}',
            );
            expect(result, entry.value);
            expect(find.byType(AlertDialog), findsNothing);
          }
        },
      );
    }

    testWidgets('barrier tap coalesces to keep editing', (
      WidgetTester tester,
    ) async {
      bool? result;

      await tester.pumpWidget(
        MaterialApp(
          theme: _theme(),
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await ConfirmationDialog.showUnsavedChanges(
                    context: context,
                    title: 'Unsaved changes',
                    body: _kBody,
                    keepEditingKey: _kUnsavedKeep,
                    discardKey: _kUnsavedDiscard,
                  );
                },
                child: const Text('open dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open dialog'));
      await tester.pumpAndSettle();

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(result, isFalse);
      expect(find.byType(AlertDialog), findsNothing);
    });
  });
}
