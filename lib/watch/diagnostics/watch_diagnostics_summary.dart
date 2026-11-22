/// The plain sentences and the newest lines the Wear Diagnostics screen shows,
/// built from the log's events.
///
/// Plan: `docs/plans/2026-11-22-293-wear-diagnostics-plan/2026-11-22-293-wear-diagnostics-plan.md`
/// (D-29304). The Dart twin of the Apple client's `WatchDiagnosticsSummary`
/// (plan 142 D-14210). A pure type: no widget, no clock, no file access.
library;

import '../../core/services/diagnostics_log.dart';

class WatchDiagnosticsSummary {
  WatchDiagnosticsSummary._({required this.headline, required this.lines});

  /// The newest events shown, newest first.
  static const int lineLimit = 40;

  /// Plain sentences for the top of the screen.
  final List<String> headline;

  /// The newest events, newest first, at most [lineLimit]:
  /// `HH:mm:ss kind detail s:<first four characters of the session>`.
  final List<String> lines;

  /// Builds the summary of [events] (oldest first, as the log returns them) in
  /// the device's local time.
  factory WatchDiagnosticsSummary.of(List<DiagnosticsEvent> events) {
    final headline = <String>[];
    final launch = events.lastIndexWhere((event) => event.kind == 'launch');
    if (launch >= 0) {
      var start = 'Started ${_clock(events[launch].at)}';
      final restarted = events
          .skip(launch + 1)
          .any((event) => event.kind == 'recovery_relaunch');
      if (restarted) start += ' — restarted by the system';
      headline.add(start);
      if (launch > 0) {
        final previous = events[launch - 1];
        headline.add(
          'Before that: last seen ${_phrase(previous)} at ${_clock(previous.at)}',
        );
      } else {
        headline.add('First run recorded.');
      }
    } else {
      headline.add('No start recorded yet.');
    }

    final newest = events.length > lineLimit
        ? events.sublist(events.length - lineLimit)
        : events;
    final lines = [
      for (final event in newest.reversed)
        [
          '${_stamp(event.at)} ${event.kind}',
          if (event.detail case final detail?) ' $detail',
          if (event.session case final session?)
            ' s:${session.length > 4 ? session.substring(0, 4) : session}',
        ].join(),
    ];
    return WatchDiagnosticsSummary._(headline: headline, lines: lines);
  }

  static String _two(int value) => value.toString().padLeft(2, '0');

  static String _clock(DateTime at) {
    final local = at.toLocal();
    return '${_two(local.hour)}:${_two(local.minute)}';
  }

  static String _stamp(DateTime at) {
    final local = at.toLocal();
    return '${_two(local.hour)}:${_two(local.minute)}:${_two(local.second)}';
  }

  static String _phrase(DiagnosticsEvent event) {
    if (event.kind == 'scene') {
      switch (event.detail) {
        case 'background':
          return 'in the background';
        case 'active':
          return 'on screen';
        case 'inactive':
          return 'dimmed';
      }
    }
    return event.kind;
  }
}
