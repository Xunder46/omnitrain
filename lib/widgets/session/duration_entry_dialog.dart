import 'package:flutter/material.dart';
import '../../core/constants/omni_theme.dart';
import '../inputs/numeric_field_with_done_bar.dart';

/// Shared h/m/s duration-entry dialog used by WorkoutSessionScreen (live and
/// edit modes) and RoutineSetupScreen (round/timed targets).
///
/// Returns the confirmed duration in whole seconds, or null if dismissed
/// without confirming. There is NO Cancel button; tapping outside the dialog
/// barrier dismisses without applying.
Future<int?> showDurationEntryDialog(
  BuildContext context, {
  String title = 'Edit Duration',
  String subtitle = '',
  required int initialSecs,
}) async {
  final h = initialSecs ~/ 3600;
  final m = (initialSecs % 3600) ~/ 60;
  final s = initialSecs % 60;

  final hhCtrl = TextEditingController(text: h.toString());
  final mmCtrl = TextEditingController(text: m.toString().padLeft(2, '0'));
  final ssCtrl = TextEditingController(text: s.toString().padLeft(2, '0'));

  final theme = Theme.of(context);

  final int? result = await showDialog<int>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (subtitle.isNotEmpty) ...[
            Text(
              subtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: OmniTheme.colors.textSecondary,
              ),
            ),
            const SizedBox(height: 20),
          ],
          Row(
            children: [
              Expanded(
                child: NumericFieldWithDoneBar(
                  controller: hhCtrl,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Hours',
                    suffixText: 'h',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: NumericFieldWithDoneBar(
                  controller: mmCtrl,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(
                    labelText: 'Min',
                    suffixText: 'm',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: NumericFieldWithDoneBar(
                  controller: ssCtrl,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(
                    labelText: 'Sec',
                    suffixText: 's',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () {
            final hVal = int.tryParse(hhCtrl.text.trim()) ?? 0;
            final mVal = int.tryParse(mmCtrl.text.trim()) ?? 0;
            final sVal = int.tryParse(ssCtrl.text.trim()) ?? 0;
            Navigator.pop(context, hVal * 3600 + mVal * 60 + sVal);
          },
          style: ButtonStyle(
            shape: WidgetStateProperty.all(
              RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(
                  OmniTheme.buttonUtilityRadius,
                ),
              ),
            ),
          ),
          child: const Text('Ok'),
        ),
      ],
    ),
  );

  // Defer controller disposal until the dialog exit animation completes.
  // Disposing immediately causes "used after being disposed" errors because
  // the dialog's TextField widgets briefly outlive the showDialog future.
  Future.delayed(const Duration(milliseconds: 300), () {
    hhCtrl.dispose();
    mmCtrl.dispose();
    ssCtrl.dispose();
  });

  return result;
}
