/// The Wear Diagnostics screen: the summary's plain sentences and the newest log
/// lines, read once when the screen opens.
///
/// Plan: `docs/plans/2026-11-22-293-wear-diagnostics-plan/2026-11-22-293-wear-diagnostics-plan.md`
/// (D-29305). The Dart counterpart of the Apple client's `WatchDiagnosticsView`.
/// One scrolling list, so a short screen never overflows.
library;

import 'package:flutter/material.dart';

import '../../core/services/diagnostics_log.dart';
import 'watch_diagnostics_summary.dart';

class WatchDiagnosticsScreen extends StatefulWidget {
  const WatchDiagnosticsScreen({super.key, required this.log});

  final DiagnosticsLog log;

  static const String title = 'Diagnostics';

  @override
  State<WatchDiagnosticsScreen> createState() => _WatchDiagnosticsScreenState();
}

class _WatchDiagnosticsScreenState extends State<WatchDiagnosticsScreen> {
  late final WatchDiagnosticsSummary _summary = WatchDiagnosticsSummary.of(
    widget.log.events(),
  );

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
          ],
        ),
      ),
    );
  }
}
