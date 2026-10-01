// filepath: test/confirmation_dialog_guard_test.dart
//
// Automated enforcement of confirmation dialog consolidation.
//
// Rule (see `docs/plans/confirmation-dialog-consolidation-plan.md`):
//   All confirmation dialogs (two-choice, three-choice) must use the shared
//   ConfirmationDialog component. Raw AlertDialog confirmations outside the
//   allowlist are not permitted.
//
// This test walks `lib/features/` recursively and fails if any file
// contains an AlertDialog construction that is not in the allowlist.
// The allowlist consists of files with legitimate non-confirmation uses
// of AlertDialog: input dialogs, single-acknowledgement notices, pickers,
// loading spinners, etc.
//
// A failure message names the offending file and points the author at the
// ConfirmationDialog component as the required fix.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Confirmation dialog guard test', () {
    test(
      'no raw AlertDialog confirmation construction outside allowlist',
      () async {
        // Files with legitimate (non-confirmation) AlertDialog uses:
        // - Input dialogs: user collects form data
        // - Single-acknowledgement notices: "Cannot Delete" etc.
        // - Pickers: metric choosers, modality pickers
        // - Loading spinners / progress dialogs
        final allowlistedFiles = <String>{
          'lib/features/nutrition/add_food_screen.dart',
          'lib/features/routine/routine_setup_screen.dart',
          'lib/features/profile/profile_screen.dart',
          'lib/features/exercise/exercise_library_detail_screen.dart',
          'lib/features/session/workout_session_screen.dart',
        };

        final violations = <String>[];
        final featuresDir = Directory('lib/features');

        await for (final entity in featuresDir.list(
          recursive: true,
          followLinks: false,
        )) {
          if (entity is! File || !entity.path.endsWith('.dart')) continue;

          // Skip allowlisted files — they have been manually reviewed
          // and approved for non-confirmation AlertDialog uses.
          if (allowlistedFiles.contains(entity.path)) continue;

          final content = await entity.readAsString();

          // Strip comments so they do not trigger false positives.
          var stripped = content.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
          stripped = stripped
              .split('\n')
              .map((line) {
                final i = line.indexOf('//');
                return i < 0 ? line : line.substring(0, i);
              })
              .join('\n');

          // Match AlertDialog construction. This catches any new
          // confirmation dialogs that should be using ConfirmationDialog.
          if (stripped.contains('AlertDialog(')) {
            violations.add(entity.path);
          }
        }

        expect(
          violations,
          isEmpty,
          reason: violations.isEmpty
              ? null
              : 'Confirmation dialog consolidation violation: '
                    'raw AlertDialog outside allowlist is not permitted. '
                    'Use ConfirmationDialog '
                    '(lib/widgets/dialogs/confirmation_dialog.dart) for all '
                    'confirmation prompts (two-choice, three-choice). '
                    'See docs/plans/confirmation-dialog-consolidation-plan.md.\n'
                    'Offending files:\n${violations.map((f) => '  $f').join('\n')}',
        );
      },
    );
  });
}
