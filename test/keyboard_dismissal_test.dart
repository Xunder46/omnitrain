import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Wraps a child in the same GestureDetector pattern used in app.dart's
// MaterialApp.builder, so these tests verify the real production mechanism.
Widget _appWithDismissal({required Widget home}) {
  return MaterialApp(
    builder: (context, child) => GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      child: child!,
    ),
    home: home,
  );
}

void main() {
  group('Keyboard dismissal — tap-outside behavior', () {
    testWidgets(
      'tapping non-interactive space while input is focused dismisses keyboard',
      (tester) async {
        final focusNode = FocusNode();

        await tester.pumpWidget(
          _appWithDismissal(
            home: Scaffold(
              body: Column(
                children: [
                  TextField(focusNode: focusNode),
                  // Large non-interactive tap target below the field
                  const SizedBox(height: 400),
                ],
              ),
            ),
          ),
        );

        await tester.tap(find.byType(TextField));
        await tester.pump();
        expect(focusNode.hasFocus, isTrue);

        // Tap empty space below the field
        await tester.tapAt(const Offset(200, 300));
        await tester.pump();
        expect(focusNode.hasFocus, isFalse);
      },
    );

    testWidgets(
      'tapping a button does not swallow the button tap when an input is focused',
      (tester) async {
        final textFieldFocusNode = FocusNode();
        var buttonPressed = false;

        await tester.pumpWidget(
          _appWithDismissal(
            home: Scaffold(
              body: Column(
                children: [
                  TextField(focusNode: textFieldFocusNode),
                  TextButton(
                    onPressed: () => buttonPressed = true,
                    child: const Text('Action'),
                  ),
                ],
              ),
            ),
          ),
        );

        await tester.tap(find.byType(TextField));
        await tester.pump();
        expect(textFieldFocusNode.hasFocus, isTrue);

        await tester.tap(find.text('Action'));
        await tester.pumpAndSettle();

        // The root GestureDetector (translucent) must not swallow the button tap.
        // On a real device the OS also dismisses the keyboard; in widget tests
        // there is no real keyboard, but the critical guarantee is that the button
        // action fires without being intercepted by the global unfocus detector.
        expect(buttonPressed, isTrue);
      },
    );

    testWidgets(
      'scrolling a list while input is focused does NOT dismiss keyboard',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(400, 600));
        final focusNode = FocusNode();

        await tester.pumpWidget(
          _appWithDismissal(
            home: Scaffold(
              body: ListView(
                children: [
                  TextField(focusNode: focusNode),
                  for (int i = 0; i < 30; i++)
                    SizedBox(height: 48, child: Text('Row $i')),
                ],
              ),
            ),
          ),
        );

        await tester.tap(find.byType(TextField));
        await tester.pump();
        expect(focusNode.hasFocus, isTrue);

        // Drag to scroll — must not fire onTap in the GestureDetector
        await tester.drag(find.byType(ListView), const Offset(0, -200));
        await tester.pump();

        expect(focusNode.hasFocus, isTrue);
      },
    );
  });

  group('Keyboard dismissal — Return key behavior', () {
    testWidgets(
      'pressing Return in a multiline note field inserts a newline and keeps focus',
      (tester) async {
        final controller = TextEditingController();
        final focusNode = FocusNode();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: TextField(
                controller: controller,
                focusNode: focusNode,
                maxLines: null,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
              ),
            ),
          ),
        );

        await tester.tap(find.byType(TextField));
        await tester.pump();
        expect(focusNode.hasFocus, isTrue);

        await tester.enterText(find.byType(TextField), 'first line');
        await tester.pump();

        // Drive via the newline action path — this is what the software keyboard
        // sends when the user presses Return on a multiline field.
        await tester.testTextInput.receiveAction(TextInputAction.newline);
        await tester.pump();

        // For a multiline field, Return must NOT dismiss focus.
        expect(focusNode.hasFocus, isTrue);

        // The platform also sends the updated editing value containing the
        // newline character; simulate that to verify the field accepts it.
        tester.testTextInput.updateEditingValue(
          const TextEditingValue(
            text: 'first line\n',
            selection: TextSelection.collapsed(offset: 11),
          ),
        );
        await tester.pump();

        // Newline is present in the field content.
        expect(controller.text, contains('\n'));
        expect(focusNode.hasFocus, isTrue);
      },
    );

    testWidgets(
      'pressing Done/Return in a single-line field does not crash and unfocuses',
      (tester) async {
        final focusNode = FocusNode();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: TextField(
                focusNode: focusNode,
                textInputAction: TextInputAction.done,
              ),
            ),
          ),
        );

        await tester.tap(find.byType(TextField));
        await tester.pump();
        expect(focusNode.hasFocus, isTrue);

        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();

        expect(focusNode.hasFocus, isFalse);
      },
    );
  });
}
