// Owner request (2026-10-13): the unsaved-changes dialog must look like the
// destructive two-choice dialog, so the two shapes cannot drift again.
//
// Pinned here:
// - the three-choice dialog has no X/`IconButton`; its actions are
//   Keep editing (TextButton) / Discard (destructive FilledButton) /
//   Save (primary FilledButton), in that left-to-right order
// - PARITY: Discard carries the same background, foreground and shape as a
//   destructive two-choice confirm; Keep editing carries the same
//   text-button shape as Cancel
// - no overflow and every action stays tappable on a 280-wide and a
//   320x568 view
// - a barrier tap still coalesces to `keepEditing`
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/omni_theme.dart';
import 'package:omnitrain/widgets/dialogs/confirmation_dialog.dart';

const String _kBody =
    'You have unsaved edits. Save them or discard to return to the summary.';

const Key _kThreeChoiceKeep = Key('align-three-keep');
const Key _kThreeChoiceDiscard = Key('align-three-discard');
const Key _kThreeChoiceSave = Key('align-three-save');

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

Widget _threeChoice() => ConfirmationDialog.threeChoice(
  title: 'Unsaved changes',
  body: _kBody,
  keepEditingKey: _kThreeChoiceKeep,
  discardKey: _kThreeChoiceDiscard,
  saveKey: _kThreeChoiceSave,
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
    testWidgets(
      'three-choice drops the X and orders Keep editing / Discard / Save',
      (WidgetTester tester) async {
        await _pumpStatic(tester, _threeChoice());

        final dialog = find.byType(AlertDialog);
        expect(dialog, findsOneWidget);
        expect(
          find.descendant(of: dialog, matching: find.byType(IconButton)),
          findsNothing,
          reason: 'the title no longer carries an X close affordance',
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
          findsOneWidget,
        );

        final keep = tester.getRect(find.byKey(_kThreeChoiceKeep));
        final discard = tester.getRect(find.byKey(_kThreeChoiceDiscard));
        final save = tester.getRect(find.byKey(_kThreeChoiceSave));

        expect(
          keep.left,
          lessThan(discard.left),
          reason: 'Keep editing is the first (leftmost) action',
        );
        expect(
          discard.left,
          lessThan(save.left),
          reason: 'Save is the confirming action, last on the right',
        );
      },
    );

    testWidgets('PARITY: Discard matches a destructive confirm, Keep editing '
        'matches Cancel', (WidgetTester tester) async {
      final theme = _theme();

      await _pumpStatic(tester, _threeChoice());
      final threeDiscard = _buttonMaterial(tester, _kThreeChoiceDiscard);
      final threeDiscardForeground = _foregroundOf(tester, _kThreeChoiceDiscard);
      final threeKeepShape = _buttonMaterial(tester, _kThreeChoiceKeep).shape;

      await _pumpStatic(tester, _destructiveTwoChoice());
      final twoConfirm = _buttonMaterial(tester, _kTwoChoiceConfirm);
      final twoConfirmForeground = _foregroundOf(tester, _kTwoChoiceConfirm);
      final twoDismissShape = _buttonMaterial(tester, _kTwoChoiceDismiss).shape;

      const utilityShape = RoundedRectangleBorder(
        borderRadius: BorderRadius.all(
          Radius.circular(OmniTheme.buttonUtilityRadius),
        ),
      );

      expect(
        threeDiscard.color,
        twoConfirm.color,
        reason: 'Discard and a destructive confirm share one background',
      );
      expect(
        threeDiscardForeground,
        twoConfirmForeground,
        reason: 'Discard and a destructive confirm share one foreground',
      );
      expect(
        threeDiscard.shape,
        twoConfirm.shape,
        reason: 'Discard and a destructive confirm share one shape',
      );
      expect(
        threeKeepShape,
        twoDismissShape,
        reason: 'Keep editing and Cancel share one text-button shape',
      );

      // Anchors, so both sides drifting together still fails.
      expect(threeDiscard.color, theme.colorScheme.error);
      expect(threeDiscardForeground, theme.colorScheme.onError);
      expect(threeDiscard.shape, utilityShape);
      expect(threeKeepShape, utilityShape);
    });

    testWidgets('PARITY: the destructive fill is not the primary fill', (
      WidgetTester tester,
    ) async {
      final theme = _theme();

      await _pumpStatic(tester, _threeChoice());
      expect(
        _buttonMaterial(tester, _kThreeChoiceDiscard).color,
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
        'every action stays tappable without overflow at '
        '${size.width.toInt()}x${size.height.toInt()}',
        (WidgetTester tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);

          UnsavedChangesAction? result;

          await tester.pumpWidget(
            MaterialApp(
              theme: _theme(),
              home: Scaffold(
                body: Builder(
                  builder: (context) => Center(
                    child: ElevatedButton(
                      onPressed: () async {
                        result = await showDialog<UnsavedChangesAction>(
                          context: context,
                          barrierDismissible: true,
                          builder: (_) => _threeChoice(),
                        );
                      },
                      child: const Text('open dialog'),
                    ),
                  ),
                ),
              ),
            ),
          );

          final expected = <Key, UnsavedChangesAction>{
            _kThreeChoiceKeep: UnsavedChangesAction.keepEditing,
            _kThreeChoiceDiscard: UnsavedChangesAction.discard,
            _kThreeChoiceSave: UnsavedChangesAction.save,
          };

          for (final entry in expected.entries) {
            await tester.tap(find.text('open dialog'));
            await tester.pumpAndSettle();
            expect(find.byType(AlertDialog), findsOneWidget);

            // Observed at both sizes: three content-width actions do not fit
            // the dialog's row, so AlertDialog's OverflowBar stacks them
            // vertically (Keep editing / Discard / Save) instead.
            final keepTop = tester.getRect(find.byKey(_kThreeChoiceKeep)).top;
            final discardTop = tester
                .getRect(find.byKey(_kThreeChoiceDiscard))
                .top;
            final saveTop = tester.getRect(find.byKey(_kThreeChoiceSave)).top;
            expect(keepTop, lessThan(discardTop));
            expect(discardTop, lessThan(saveTop));

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

    testWidgets('barrier tap coalesces to keepEditing', (
      WidgetTester tester,
    ) async {
      UnsavedChangesAction? result;

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
                    keepEditingKey: _kThreeChoiceKeep,
                    discardKey: _kThreeChoiceDiscard,
                    saveKey: _kThreeChoiceSave,
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

      expect(result, UnsavedChangesAction.keepEditing);
      expect(find.byType(AlertDialog), findsNothing);
    });
  });
}
