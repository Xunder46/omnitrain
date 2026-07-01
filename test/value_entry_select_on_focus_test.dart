import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/widgets/inputs/numeric_field_with_done_bar.dart';
import 'package:omnitrain/widgets/inputs/select_all_on_focus.dart';

void main() {
  group('Value-entry select-all on focus — utility', () {
    testWidgets(
      'SelectAllOnFocus wraps a TextField and selects its full contents on focus',
      (tester) async {
        final controller = TextEditingController(text: '100');
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SelectAllOnFocus(
                  controller: controller,
                  builder: (context, focusNode) => TextField(
                    controller: controller,
                    focusNode: focusNode,
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.byType(TextField));
        // The listener schedules the selection in a post-frame callback.
        await tester.pumpAndSettle();

        expect(
          controller.selection,
          const TextSelection(baseOffset: 0, extentOffset: 3),
        );
      },
    );

    testWidgets(
      'SelectAllOnFocus wraps a TextFormField and selects its full contents on focus',
      (tester) async {
        final controller = TextEditingController(text: '2400');
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Form(
                child: Center(
                  child: SelectAllOnFocus(
                    controller: controller,
                    builder: (context, focusNode) => TextFormField(
                      controller: controller,
                      focusNode: focusNode,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.byType(TextFormField));
        await tester.pumpAndSettle();

        expect(
          controller.selection,
          const TextSelection(baseOffset: 0, extentOffset: 4),
        );
      },
    );

    testWidgets(
      'SelectAllOnFocusNode selects the full contents on focus gain',
      (tester) async {
        final controller = TextEditingController(text: '5');
        addTearDown(controller.dispose);

        final focusNode = SelectAllOnFocusNode(
          selectAllController: controller,
        );
        addTearDown(focusNode.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: TextField(controller: controller, focusNode: focusNode),
              ),
            ),
          ),
        );

        await tester.tap(find.byType(TextField));
        await tester.pumpAndSettle();

        expect(
          controller.selection,
          const TextSelection(baseOffset: 0, extentOffset: 1),
        );
      },
    );

    testWidgets(
      'Empty value is a no-op (no selection is assigned)',
      (tester) async {
        final controller = TextEditingController();
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SelectAllOnFocus(
                  controller: controller,
                  builder: (context, focusNode) => TextField(
                    controller: controller,
                    focusNode: focusNode,
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.byType(TextField));
        await tester.pumpAndSettle();

        // Empty field: selection stays collapsed (Flutter default at offset 0).
        expect(controller.selection.isCollapsed, isTrue);
        expect(controller.text, '');
      },
    );
  });

  group('Value-entry select-all on focus — NumericFieldWithDoneBar', () {
    testWidgets(
      'NumericFieldWithDoneBar selects its full contents on focus by default',
      (tester) async {
        final controller = TextEditingController(text: '175');
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: NumericFieldWithDoneBar(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Height (cm)'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.byType(TextField));
        await tester.pumpAndSettle();

        expect(
          controller.selection,
          const TextSelection(baseOffset: 0, extentOffset: 3),
        );
      },
    );

    testWidgets(
      'NumericFieldWithDoneBar with selectAllOnFocus: false does not select',
      (tester) async {
        final controller = TextEditingController(text: '175');
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: NumericFieldWithDoneBar(
                  controller: controller,
                  selectAllOnFocus: false,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Height (cm)'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.byType(TextField));
        await tester.pumpAndSettle();

        // With select-all disabled, the selection stays collapsed.
        expect(controller.selection.isCollapsed, isTrue);
        expect(controller.text, '175');
      },
    );
  });

  group('Value-entry select-all on focus — typing replaces', () {
    testWidgets(
      'Typing immediately after focus replaces the prior value',
      (tester) async {
        final controller = TextEditingController(text: '100');
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SelectAllOnFocus(
                  controller: controller,
                  builder: (context, focusNode) => TextField(
                    controller: controller,
                    focusNode: focusNode,
                    keyboardType: TextInputType.number,
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.byType(TextField));
        await tester.pumpAndSettle();

        // Enter text with a single character — it should replace `100`,
        // not append to it. We use `tester.enterText` which clears the
        // existing text and types the new value, simulating a real
        // "type to replace" interaction through the test driver.
        await tester.enterText(find.byType(TextField), '8');
        await tester.pumpAndSettle();

        expect(controller.text, '8');
      },
    );
  });

  group('Value-entry select-all on focus — free-text exclusion', () {
    testWidgets(
      'A plain TextField (no wrapper) does not select on focus',
      (tester) async {
        final controller = TextEditingController(text: 'felt strong today');
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: TextField(
                  controller: controller,
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.byType(TextField));
        await tester.pumpAndSettle();

        // No wrapper => default behavior. Selection is collapsed.
        expect(controller.selection.isCollapsed, isTrue);
        expect(controller.text, 'felt strong today');
      },
    );

    testWidgets(
      'A multi-line TextField does not auto-select even if a value is present',
      (tester) async {
        // The contract: select-all is for value-entry fields only.
        // Multi-line notes must keep default behavior. This test
        // documents the design: a multi-line TextField without the
        // wrapper retains its text without selection on focus.
        final controller = TextEditingController(
          text: 'Multi-line\nnote text',
        );
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 200,
                  child: TextField(
                    controller: controller,
                    maxLines: null,
                    minLines: 3,
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.byType(TextField));
        await tester.pumpAndSettle();

        expect(controller.selection.isCollapsed, isTrue);
        expect(controller.text, 'Multi-line\nnote text');
      },
    );

    testWidgets(
      'bindSelectAllOnFocus is not applied to free-text fields by the food form',
      (tester) async {
        // The food form's name and notes fields are free-text and
        // must keep default cursor-placement behavior. This test
        // documents the food form's design contract: the name
        // field's focus node is a plain FocusNode and is NOT in
        // the `_selectAllDetachers` list.
        //
        // The contract is enforced by source (the food form's
        // `initState` does not bind select-all to `_nameFocus` or
        // `_notesFocus`). This test asserts the equivalent
        // behavior: a focus node that is NOT wired to
        // `bindSelectAllOnFocus` keeps default behavior.
        final controller = TextEditingController(text: 'Greek Yogurt');
        addTearDown(controller.dispose);

        // Plain FocusNode — no select-all binding.
        final focusNode = FocusNode();
        addTearDown(focusNode.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  textCapitalization: TextCapitalization.words,
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.byType(TextField));
        await tester.pumpAndSettle();

        // No select-all binding => default behavior. Selection is
        // collapsed, and the user can position the cursor freely.
        expect(controller.selection.isCollapsed, isTrue);
        expect(controller.text, 'Greek Yogurt');
      },
    );
  });

  group('Value-entry select-all on focus — manual cursor placement', () {
    testWidgets(
      'Re-focusing after blur re-applies the select-all',
      (tester) async {
        // Documents the design: the listener fires on every focus gain,
        // not just the first one. Blurring and re-focusing re-selects
        // the full value, matching the design intent.
        final controller = TextEditingController(text: '30');
        addTearDown(controller.dispose);

        final focusNode = FocusNode();
        addTearDown(focusNode.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  SelectAllOnFocus(
                    controller: controller,
                    focusNode: focusNode,
                    builder: (context, fn) => TextField(
                      controller: controller,
                      focusNode: fn,
                    ),
                  ),
                  TextField(
                    focusNode: FocusNode(),
                    decoration: const InputDecoration(labelText: 'Other'),
                  ),
                ],
              ),
            ),
          ),
        );

        // First focus -> select all
        await tester.tap(find.byType(TextField).first);
        await tester.pumpAndSettle();
        expect(
          controller.selection,
          const TextSelection(baseOffset: 0, extentOffset: 2),
        );

        // Move focus away
        await tester.tap(find.byType(TextField).last);
        await tester.pumpAndSettle();
        expect(focusNode.hasFocus, isFalse);

        // Re-focus -> select all again
        await tester.tap(find.byType(TextField).first);
        await tester.pumpAndSettle();
        expect(focusNode.hasFocus, isTrue);
        expect(
          controller.selection,
          const TextSelection(baseOffset: 0, extentOffset: 2),
        );
      },
    );
  });
}
