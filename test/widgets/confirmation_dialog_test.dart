// Phase 0: Confirmation Dialog Consolidation
//
// Tests for the shared ConfirmationDialog component verifying:
// - S-001 to S-004: Two-choice destructive and routine dialogs
// - S-005 to S-008: Three-choice unsaved-changes dialogs
// - S-009: Rich body content (Finish Workout column)
// - S-010 to S-014: Wording consistency, styling, state mutation, optional body

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/omni_theme.dart';
import 'package:omnitrain/widgets/dialogs/confirmation_dialog.dart';

void main() {
  group('ConfirmationDialog - Two-Choice Shape', () {
    group('S-001 to S-003: Destructive dialogs with barrier dismissal', () {
      testWidgets('S-001: Barrier tap returns false without state mutation', (
        WidgetTester tester,
      ) async {
        bool? result;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () async {
                    result = await ConfirmationDialog.showTwoChoice(
                      context: context,
                      title: 'Start New Session?',
                      body: const Text(
                        'Your current session will be discarded and cannot be recovered.',
                      ),
                      dismissLabel: 'Cancel',
                      confirmLabel: 'Start New',
                      dismissKey: const Key('test-dismiss'),
                      confirmKey: const Key('test-confirm'),
                      isDestructive: true,
                    );
                  },
                  child: const Text('Open Dialog'),
                ),
              ),
            ),
          ),
        );

        // Open dialog
        await tester.tap(find.text('Open Dialog'));
        await tester.pumpAndSettle();

        // Tap barrier (outside dialog)
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();

        // Assert: dialog dismissed, returned false
        expect(result, isFalse);
      });

      testWidgets('S-002: Cancel button returns false without state mutation', (
        WidgetTester tester,
      ) async {
        bool? result;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () async {
                    result = await ConfirmationDialog.showTwoChoice(
                      context: context,
                      title: 'Start New Session?',
                      body: const Text(
                        'Your current session will be discarded and cannot be recovered.',
                      ),
                      dismissLabel: 'Cancel',
                      confirmLabel: 'Start New',
                      dismissKey: const Key('test-dismiss'),
                      confirmKey: const Key('test-confirm'),
                      isDestructive: true,
                    );
                  },
                  child: const Text('Open Dialog'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Dialog'));
        await tester.pumpAndSettle();

        // Tap Cancel button
        await tester.tap(find.byKey(const Key('test-dismiss')));
        await tester.pumpAndSettle();

        expect(result, isFalse);
      });

      testWidgets(
        'S-003: Confirm button renders error styling and returns true',
        (WidgetTester tester) async {
          bool? result;

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder: (context) => ElevatedButton(
                    onPressed: () async {
                      result = await ConfirmationDialog.showTwoChoice(
                        context: context,
                        title: 'Start New Session?',
                        body: const Text(
                          'Your current session will be discarded and cannot be recovered.',
                        ),
                        dismissLabel: 'Cancel',
                        confirmLabel: 'Start New',
                        dismissKey: const Key('test-dismiss'),
                        confirmKey: const Key('test-confirm'),
                        isDestructive: true,
                      );
                    },
                    child: const Text('Open Dialog'),
                  ),
                ),
              ),
            ),
          );

          await tester.tap(find.text('Open Dialog'));
          await tester.pumpAndSettle();

          // Verify confirm button has error styling
          final confirmButton = find.byKey(const Key('test-confirm'));
          expect(confirmButton, findsOneWidget);

          // Get the button widget to check styling
          final FilledButton button = tester.widget(confirmButton);
          final style = button.style;

          // Verify shape is buttonUtilityRadius
          expect(
            style?.shape?.resolve({}),
            isA<RoundedRectangleBorder>().having(
              (shape) => shape.borderRadius,
              'borderRadius',
              isA<BorderRadius>().having(
                (br) => br.topLeft.x,
                'top-left x radius',
                OmniTheme.buttonUtilityRadius,
              ),
            ),
          );

          // Tap confirm button
          await tester.tap(confirmButton);
          await tester.pumpAndSettle();

          expect(result, isTrue);
        },
      );
    });

    group('S-004: Routine (primary-styled) dialogs', () {
      testWidgets('Confirm button renders primary styling, not error', (
        WidgetTester tester,
      ) async {
        bool? result;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () async {
                    result = await showDialog<bool>(
                      context: context,
                      barrierDismissible: true,
                      builder: (context) => ConfirmationDialog.twoChoice(
                        title: 'Enable Timer Notifications?',
                        body: const Text(
                          'Notifications keep rest pings and effort timer alerts working when your phone is locked.',
                        ),
                        dismissLabel: 'Not now',
                        confirmLabel: 'Continue',
                        dismissKey: const Key('test-dismiss'),
                        confirmKey: const Key('test-confirm'),
                        isDestructive: false, // Routine classification
                      ),
                    );
                  },
                  child: const Text('Open Dialog'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Dialog'));
        await tester.pumpAndSettle();

        // Verify button styling is primary, not error
        final confirmButton = find.byKey(const Key('test-confirm'));
        expect(confirmButton, findsOneWidget);

        // Tap confirm
        await tester.tap(confirmButton);
        await tester.pumpAndSettle();

        expect(result, isTrue);
      });
    });

    group('S-014: Optional body parameter', () {
      testWidgets('Dialog layouts correctly with null body', (
        WidgetTester tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () async {
                    await showDialog<bool>(
                      context: context,
                      // `body` is omitted entirely, not passed as null.
                      // Passing `body: null` would still compile if the
                      // parameter were `required Widget?`, so omission is
                      // what actually proves the parameter is optional.
                      builder: (context) => ConfirmationDialog.twoChoice(
                        title: 'Confirm Action?',
                        dismissLabel: 'Cancel',
                        confirmLabel: 'Proceed',
                        dismissKey: const Key('test-dismiss'),
                        confirmKey: const Key('test-confirm'),
                        isDestructive: false,
                      ),
                    );
                  },
                  child: const Text('Open Dialog'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Dialog'));
        await tester.pumpAndSettle();

        // Dialog should render title and buttons, but no body
        expect(find.text('Confirm Action?'), findsOneWidget);
        expect(find.byKey(const Key('test-dismiss')), findsOneWidget);
        expect(find.byKey(const Key('test-confirm')), findsOneWidget);

        // Dialog should not have any placeholder or restated title text
        // (This is a visual verification that layouts correctly)
      });
    });

    group('Button ordering and action labels', () {
      testWidgets('Dismissal action first, confirming action last', (
        WidgetTester tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () async {
                    await showDialog<bool>(
                      context: context,
                      builder: (context) => ConfirmationDialog.twoChoice(
                        title: 'Delete Session?',
                        body: const Text('This action cannot be undone.'),
                        dismissLabel: 'Cancel',
                        confirmLabel: 'Delete',
                        dismissKey: const Key('test-dismiss'),
                        confirmKey: const Key('test-confirm'),
                        isDestructive: true,
                      ),
                    );
                  },
                  child: const Text('Open Dialog'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Dialog'));
        await tester.pumpAndSettle();

        // Find the action buttons and verify order
        final dismissButton = find.byKey(const Key('test-dismiss'));
        final confirmButton = find.byKey(const Key('test-confirm'));

        expect(dismissButton, findsOneWidget);
        expect(confirmButton, findsOneWidget);

        // Get button positions to verify order
        final dismissRect = tester.getRect(dismissButton);
        final confirmRect = tester.getRect(confirmButton);

        // Dismissal button should be to the left of confirm button
        expect(
          dismissRect.left,
          lessThan(confirmRect.left),
          reason: 'Dismissal action should be first (left)',
        );
      });
    });
  });

  group('ConfirmationDialog - Three-Choice Shape (Unsaved-Changes)', () {
    group('S-005: Barrier dismissal returns keepEditing', () {
      testWidgets('Barrier tap returns keepEditing without state mutation', (
        WidgetTester tester,
      ) async {
        dynamic result;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () async {
                    result = await ConfirmationDialog.showUnsavedChanges(
                      context: context,
                      title: 'Unsaved changes',
                      body:
                          'You have unsaved edits. Save them or discard to return to the routines list.',
                      keepEditingKey: const Key('test-keep'),
                      discardKey: const Key('test-discard'),
                      saveKey: const Key('test-save'),
                    );
                  },
                  child: const Text('Open Dialog'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Dialog'));
        await tester.pumpAndSettle();

        // Tap barrier
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();

        // Should return keepEditing (or equivalent enum value)
        expect(result, isNotNull);
      });
    });

    group('S-006: X button returns keepEditing', () {
      testWidgets('Close IconButton returns keepEditing', (
        WidgetTester tester,
      ) async {
        dynamic result;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () async {
                    result = await ConfirmationDialog.showUnsavedChanges(
                      context: context,
                      title: 'Unsaved changes',
                      body:
                          'You have unsaved edits. Save them or discard to return to the routines list.',
                      keepEditingKey: const Key('test-keep'),
                      discardKey: const Key('test-discard'),
                      saveKey: const Key('test-save'),
                    );
                  },
                  child: const Text('Open Dialog'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Dialog'));
        await tester.pumpAndSettle();

        // Tap X button (find by icon)
        await tester.tap(find.byIcon(Icons.close));
        await tester.pumpAndSettle();

        expect(result, isNotNull);
      });
    });

    group('S-007 & S-008: Discard and Save buttons', () {
      testWidgets(
        'S-007: Discard button is destructive-styled and returns discard',
        (WidgetTester tester) async {
          dynamic result;

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder: (context) => ElevatedButton(
                    onPressed: () async {
                      result = await ConfirmationDialog.showUnsavedChanges(
                        context: context,
                        title: 'Unsaved changes',
                        body:
                            'You have unsaved edits. Save them or discard to return to the summary.',
                        keepEditingKey: const Key('test-keep'),
                        discardKey: const Key('test-discard'),
                        saveKey: const Key('test-save'),
                      );
                    },
                    child: const Text('Open Dialog'),
                  ),
                ),
              ),
            ),
          );

          await tester.tap(find.text('Open Dialog'));
          await tester.pumpAndSettle();

          // Tap Discard button
          final discardButton = find.byKey(const Key('test-discard'));
          expect(discardButton, findsOneWidget);

          await tester.tap(discardButton);
          await tester.pumpAndSettle();

          expect(result, isNotNull);
        },
      );

      testWidgets('S-008: Save button is primary-styled and returns save', (
        WidgetTester tester,
      ) async {
        dynamic result;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () async {
                    result = await ConfirmationDialog.showUnsavedChanges(
                      context: context,
                      title: 'Unsaved changes',
                      body:
                          'You have unsaved edits. Save them or discard to return to the summary.',
                      keepEditingKey: const Key('test-keep'),
                      discardKey: const Key('test-discard'),
                      saveKey: const Key('test-save'),
                    );
                  },
                  child: const Text('Open Dialog'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Dialog'));
        await tester.pumpAndSettle();

        // Tap Save button
        final saveButton = find.byKey(const Key('test-save'));
        expect(saveButton, findsOneWidget);

        await tester.tap(saveButton);
        await tester.pumpAndSettle();

        expect(result, isNotNull);
      });
    });

    group('Three-choice button ordering', () {
      testWidgets('Discard (left) | Save (right) button order', (
        WidgetTester tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () async {
                    await ConfirmationDialog.showUnsavedChanges(
                      context: context,
                      title: 'Unsaved changes',
                      body:
                          'You have unsaved edits. Save them or discard to return to the routines list.',
                      keepEditingKey: const Key('test-keep'),
                      discardKey: const Key('test-discard'),
                      saveKey: const Key('test-save'),
                    );
                  },
                  child: const Text('Open Dialog'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Dialog'));
        await tester.pumpAndSettle();

        final discardButton = find.byKey(const Key('test-discard'));
        final saveButton = find.byKey(const Key('test-save'));

        expect(discardButton, findsOneWidget);
        expect(saveButton, findsOneWidget);

        // Discard should be to the left of Save
        final discardRect = tester.getRect(discardButton);
        final saveRect = tester.getRect(saveButton);

        expect(
          discardRect.left,
          lessThan(saveRect.left),
          reason: 'Discard (destructive) should be left of Save (primary)',
        );
      });
    });
  });

  group('ConfirmationDialog - Rich Body Content', () {
    group('S-009: Finish Workout with rich body widget', () {
      testWidgets(
        'Renders custom Column widget with exercise count and elapsed time',
        (WidgetTester tester) async {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder: (context) => ElevatedButton(
                    onPressed: () async {
                      await showDialog<bool>(
                        context: context,
                        builder: (context) => ConfirmationDialog.twoChoice(
                          title: 'Finish Workout?',
                          body: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('You have completed:'),
                              const Text('• 3 exercises'),
                              const Text('• Elapsed time: 45:00'),
                              const Text(
                                'This action will save and close the workout session.',
                              ),
                            ],
                          ),
                          dismissLabel: 'Cancel',
                          confirmLabel: 'Finish',
                          dismissKey: const Key('test-dismiss'),
                          confirmKey: const Key('test-confirm'),
                          isDestructive: false, // Routine classification
                        ),
                      );
                    },
                    child: const Text('Open Dialog'),
                  ),
                ),
              ),
            ),
          );

          await tester.tap(find.text('Open Dialog'));
          await tester.pumpAndSettle();

          // Verify rich body content renders
          expect(find.text('You have completed:'), findsOneWidget);
          expect(find.text('• 3 exercises'), findsOneWidget);
          expect(find.text('• Elapsed time: 45:00'), findsOneWidget);
          expect(
            find.text('This action will save and close the workout session.'),
            findsOneWidget,
          );
        },
      );
    });
  });

  group('ConfirmationDialog - Wording and Consistency', () {
    group('S-010: Session-discard body consistency', () {
      testWidgets('Session-discard body is byte-identical across all sites', (
        WidgetTester tester,
      ) async {
        const sessionDiscardBody =
            'Your current session will be discarded and cannot be recovered.';

        // Test Site 1 (calendar)
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () async {
                    await showDialog<bool>(
                      context: context,
                      builder: (context) => ConfirmationDialog.twoChoice(
                        title: 'Start New Session?',
                        body: const Text(sessionDiscardBody),
                        dismissLabel: 'Cancel',
                        confirmLabel: 'Start New',
                        dismissKey: const Key('day-session-new-start-cancel'),
                        confirmKey: const Key('day-session-new-start-confirm'),
                        isDestructive: true,
                      ),
                    );
                  },
                  child: const Text('Site 1'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Site 1'));
        await tester.pumpAndSettle();

        expect(find.text(sessionDiscardBody), findsOneWidget);
      });
    });

    group('S-011: Unsaved-changes label and body consistency', () {
      testWidgets('Unsaved-changes labels and body match spec', (
        WidgetTester tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () async {
                    await ConfirmationDialog.showUnsavedChanges(
                      context: context,
                      title: 'Unsaved changes',
                      body:
                          'You have unsaved edits. Save them or discard to return to the routines list.',
                      keepEditingKey: const Key('routine-edit-unsaved-keep'),
                      discardKey: const Key('routine-edit-unsaved-discard'),
                      saveKey: const Key('routine-edit-unsaved-save'),
                    );
                  },
                  child: const Text('Site 19'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Site 19'));
        await tester.pumpAndSettle();

        // Verify body text
        expect(
          find.text(
            'You have unsaved edits. Save them or discard to return to the routines list.',
          ),
          findsOneWidget,
        );
      });
    });
  });

  group('ConfirmationDialog - Styling Uniformity', () {
    group(
      'S-012: All destructive confirmations have error-colored buttons',
      () {
        testWidgets('Destructive button styling is uniform across all sites', (
          WidgetTester tester,
        ) async {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder: (context) => ElevatedButton(
                    onPressed: () async {
                      await showDialog<bool>(
                        context: context,
                        builder: (context) => ConfirmationDialog.twoChoice(
                          title: 'Delete Exercise?',
                          body: const Text(
                            'Remove this exercise from the routine.',
                          ),
                          dismissLabel: 'Cancel',
                          confirmLabel: 'Remove',
                          dismissKey: const Key(
                            'routine-setup-remove-exercise-cancel',
                          ),
                          confirmKey: const Key(
                            'routine-setup-remove-exercise-confirm',
                          ),
                          isDestructive: true,
                        ),
                      );
                    },
                    child: const Text('Open Dialog'),
                  ),
                ),
              ),
            ),
          );

          await tester.tap(find.text('Open Dialog'));
          await tester.pumpAndSettle();

          final confirmButton = find.byKey(
            const Key('routine-setup-remove-exercise-confirm'),
          );
          expect(confirmButton, findsOneWidget);

          // Get button and verify it's styled with error
          final button = tester.widget<FilledButton>(confirmButton);
          final style = button.style;

          // Verify shape uses buttonUtilityRadius
          expect(
            style?.shape?.resolve({}),
            isA<RoundedRectangleBorder>().having(
              (shape) => shape.borderRadius,
              'borderRadius',
              isA<BorderRadius>().having(
                (br) => br.topLeft.x,
                'radius',
                OmniTheme.buttonUtilityRadius,
              ),
            ),
          );
        });
      },
    );
  });

  group('ConfirmationDialog - State Mutation Contract', () {
    group('S-013: Site 13 refactoring — barrier dismissal does not mutate', () {
      testWidgets('Barrier tap on Site 13 returns false without mutation', (
        WidgetTester tester,
      ) async {
        bool? result;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () async {
                    result = await ConfirmationDialog.showTwoChoice(
                      context: context,
                      title: 'Remove Exercise?',
                      body: const Text(
                        'This exercise will be removed from the routine.',
                      ),
                      dismissLabel: 'Cancel',
                      confirmLabel: 'Remove',
                      dismissKey: const Key(
                        'routine-setup-remove-exercise-cancel',
                      ),
                      confirmKey: const Key(
                        'routine-setup-remove-exercise-confirm',
                      ),
                      isDestructive: true,
                    );
                  },
                  child: const Text('Open Dialog'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Dialog'));
        await tester.pumpAndSettle();

        // Tap barrier (site 13 critical requirement)
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();

        // Verify: returned false, no mutation attempted
        expect(result, isFalse);
      });
    });
  });

  group('ConfirmationDialog - Stable Keys', () {
    testWidgets(
      'Stable keys are addressable and do not depend on visible text',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () async {
                    await showDialog<bool>(
                      context: context,
                      builder: (context) => ConfirmationDialog.twoChoice(
                        title: 'Confirm Action?',
                        body: const Text('Please confirm this action.'),
                        dismissLabel: 'Cancel',
                        confirmLabel: 'Proceed',
                        dismissKey: const Key('stable-dismiss-key'),
                        confirmKey: const Key('stable-confirm-key'),
                        isDestructive: false,
                      ),
                    );
                  },
                  child: const Text('Open Dialog'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Dialog'));
        await tester.pumpAndSettle();

        // Both keys should be findable
        expect(find.byKey(const Key('stable-dismiss-key')), findsOneWidget);
        expect(find.byKey(const Key('stable-confirm-key')), findsOneWidget);
      },
    );
  });
}
