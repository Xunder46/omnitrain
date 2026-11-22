// The Wear Diagnostics screen's sentences and lines (plan 293, D-29304).
//
// Scenario mapping:
//   S-29301  no events
//   S-29302  the first run
//   S-29303  what was last seen before a launch, and the phrases
//   S-29304  a restart by the system
//   S-29305  the newest 40 lines, newest first
//   S-29306  the line format
//   S-29307  the headline reads from the last launch
//
// Plain `test()` throughout: a pure type over events. Times are compared with
// the same local-time rule the summary uses, so every case holds in any zone.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/diagnostics_log.dart';
import 'package:omnitrain/watch/diagnostics/watch_diagnostics_summary.dart';

final DateTime _t0 = DateTime.utc(2026, 11, 22, 9, 10, 5);

String _two(int v) => v.toString().padLeft(2, '0');
String _hm(DateTime at) {
  final l = at.toLocal();
  return '${_two(l.hour)}:${_two(l.minute)}';
}

String _hms(DateTime at) {
  final l = at.toLocal();
  return '${_two(l.hour)}:${_two(l.minute)}:${_two(l.second)}';
}

DiagnosticsEvent _event(
  String kind, {
  DateTime? at,
  String? detail,
  String? session,
}) => DiagnosticsEvent(
  at: at ?? _t0,
  kind: kind,
  detail: detail,
  session: session,
);

void main() {
  test('S-29301 no events', () {
    final summary = WatchDiagnosticsSummary.of(const []);

    expect(summary.headline, ['No start recorded yet.']);
    expect(summary.lines, isEmpty);
  });

  test('S-29302 the first run', () {
    final summary = WatchDiagnosticsSummary.of([_event('launch')]);

    expect(summary.headline, ['Started ${_hm(_t0)}', 'First run recorded.']);
  });

  test('S-29303 what was last seen before a launch, and the phrases', () {
    final before = _t0.subtract(const Duration(minutes: 7));
    String headline1(DiagnosticsEvent previous) =>
        WatchDiagnosticsSummary.of([previous, _event('launch')]).headline[1];

    expect(
      headline1(_event('scene', at: before, detail: 'background')),
      'Before that: last seen in the background at ${_hm(before)}',
    );
    expect(
      headline1(_event('scene', at: before, detail: 'active')),
      'Before that: last seen on screen at ${_hm(before)}',
    );
    expect(
      headline1(_event('scene', at: before, detail: 'inactive')),
      'Before that: last seen dimmed at ${_hm(before)}',
    );
    expect(
      headline1(_event('frame_sent', at: before, detail: 'timer_state live')),
      'Before that: last seen frame_sent at ${_hm(before)}',
    );
    expect(
      headline1(_event('scene', at: before, detail: 'sideways')),
      'Before that: last seen scene at ${_hm(before)}',
      reason: 'an unknown scene detail falls back to the kind',
    );
  });

  test('S-29304 a restart by the system', () {
    final after = WatchDiagnosticsSummary.of([
      _event('launch'),
      _event('recovery_relaunch'),
    ]);
    expect(
      after.headline.first,
      'Started ${_hm(_t0)} — restarted by the system',
    );

    final before = WatchDiagnosticsSummary.of([
      _event('recovery_relaunch'),
      _event('launch'),
    ]);
    expect(
      before.headline.first,
      'Started ${_hm(_t0)}',
      reason: 'a relaunch before the last launch is not this run\'s',
    );
  });

  test('S-29305 the newest 40 lines, newest first', () {
    final events = [
      for (var i = 0; i < 45; i++)
        _event('e$i', at: _t0.add(Duration(seconds: i))),
    ];

    final lines = WatchDiagnosticsSummary.of(events).lines;

    expect(WatchDiagnosticsSummary.lineLimit, 40);
    expect(lines, hasLength(40));
    expect(lines.first, endsWith(' e44'));
    expect(lines.last, endsWith(' e5'));
    expect(lines.any((line) => line.endsWith(' e4')), isFalse);
  });

  test('S-29306 the line format', () {
    final lines = WatchDiagnosticsSummary.of([
      _event('frame_received', detail: 'timer_state', session: 'abcdef-123'),
      _event('scene', detail: 'active'),
      _event('launch'),
      _event('frame_sent', detail: 'x', session: 'ab'),
    ]).lines;

    expect(lines, [
      '${_hms(_t0)} frame_sent x s:ab',
      '${_hms(_t0)} launch',
      '${_hms(_t0)} scene active',
      '${_hms(_t0)} frame_received timer_state s:abcd',
    ]);
  });

  test('S-29307 the headline reads from the last launch', () {
    final first = _t0;
    final seen = _t0.add(const Duration(minutes: 3));
    final second = _t0.add(const Duration(minutes: 9));

    final summary = WatchDiagnosticsSummary.of([
      _event('launch', at: first),
      _event('scene', at: seen, detail: 'background'),
      _event('launch', at: second),
    ]);

    expect(summary.headline, [
      'Started ${_hm(second)}',
      'Before that: last seen in the background at ${_hm(seen)}',
    ]);
  });
}
