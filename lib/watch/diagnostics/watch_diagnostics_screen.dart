/// The Wear Diagnostics screen: the summary's plain sentences and the newest log
/// lines, read once when the screen opens.
///
/// Plan: `docs/plans/2026-11-22-293-wear-diagnostics-plan/2026-11-22-293-wear-diagnostics-plan.md`
/// (D-29305). The Dart counterpart of the Apple client's `WatchDiagnosticsView`.
/// One scrolling list, so a short screen never overflows.
library;

import 'package:flutter/material.dart';

import '../../core/constants/omni_theme.dart';
import '../../core/services/diagnostics_log.dart';
import 'watch_diagnostics_send_outcome.dart';
import 'watch_diagnostics_summary.dart';

class WatchDiagnosticsScreen extends StatefulWidget {
  const WatchDiagnosticsScreen({super.key, required this.log, this.onSend});

  final DiagnosticsLog log;

  /// Sends the log to the phone and says what happened (plan 304, D-30406).
  /// Left null the screen has no Send button.
  final Future<WatchDiagnosticsSendOutcome> Function()? onSend;

  static const String title = 'Diagnostics';

  /// The Send button's label.
  static const String sendLabel = 'Send to phone';

  @override
  State<WatchDiagnosticsScreen> createState() => _WatchDiagnosticsScreenState();
}

class _WatchDiagnosticsScreenState extends State<WatchDiagnosticsScreen> {
  late final WatchDiagnosticsSummary _summary = WatchDiagnosticsSummary.of(
    widget.log.events(),
  );

  bool _sending = false;
  WatchDiagnosticsSendOutcome? _outcome;

  Future<void> _send() async {
    final onSend = widget.onSend;
    if (onSend == null || _sending) return;
    setState(() => _sending = true);
    WatchDiagnosticsSendOutcome outcome;
    try {
      outcome = await onSend();
    } on Object {
      outcome = WatchDiagnosticsSendOutcome.failed;
    }
    if (!mounted) return;
    setState(() {
      _sending = false;
      _outcome = outcome;
    });
  }

  @override
  Widget build(BuildContext context) {
    final styles = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          children: [
            Semantics(
              header: true,
              child: Text(
                WatchDiagnosticsScreen.title,
                style: styles.titleMedium,
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 6),
            for (final line in _summary.headline)
              Text(line, style: styles.bodySmall),
            const Divider(),
            for (final line in _summary.lines)
              Text(
                line,
                style: styles.labelSmall?.copyWith(
                  fontFamily: 'monospace',
                  color: scheme.onSurfaceVariant,
                ),
              ),
            if (widget.onSend != null) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 40,
                child: FilledButton(
                  onPressed: _sending ? null : _send,
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        OmniTheme.buttonBorderRadius,
                      ),
                    ),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(WatchDiagnosticsScreen.sendLabel),
                ),
              ),
              if (_outcome != null) ...[
                const SizedBox(height: 4),
                Text(
                  _outcome!.message,
                  style: styles.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 16),
            ],
          ],
        ),
      ),
    );
  }
}
