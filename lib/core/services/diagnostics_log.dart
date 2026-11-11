import 'dart:convert';

import 'diagnostics_storage.dart';

/// One recorded line of the diagnostics log (plan 143).
class DiagnosticsEvent {
  const DiagnosticsEvent({
    required this.at,
    required this.kind,
    this.session,
    this.detail,
  });

  final DateTime at;
  final String kind;
  final String? session;
  final String? detail;
}

/// The phone's own record of the watch link: launches, app lifecycle,
/// reachability and every sync frame with its outcome (plan 143, D-14301).
///
/// The Dart twin of the watch's `WatchDiagnosticsLog` (plan 142): the same
/// line shape, bound, coalescing and cut, so the two logs read together.
///
/// Observation only (D-14302): nothing reads it to decide anything, every call
/// swallows its own failure, and a collaborator holding null records nothing.
/// A kill mid-append leaves a torn last line that reads skip and the next
/// append starts on a fresh line.
class DiagnosticsLog {
  DiagnosticsLog({
    required DiagnosticsStorage storage,
    DateTime Function()? clock,
    int capacity = 3000,
    int slack = 300,
  }) : _storage = storage,
       _clock = clock ?? DateTime.now,
       _capacity = capacity,
       _slack = slack;

  /// A coalesced event is recorded at most once per this long.
  static const Duration coalesceWindow = Duration(seconds: 60);

  /// A detail is cut to this many characters.
  static const int detailLimit = 120;

  final DiagnosticsStorage _storage;
  final DateTime Function() _clock;
  final int _capacity;
  final int _slack;

  int? _lineCount;
  final Map<String, _Held> _coalesced = <String, _Held>{};

  /// Records one event. With a [coalesce] key, events under that key are
  /// recorded at most once per [coalesceWindow]: the first at once, then one
  /// line per window whose detail ends `x<number of events it stands for>`.
  void note(
    String kind, {
    String? session,
    String? detail,
    String? coalesce,
  }) {
    try {
      final now = _clock();
      var text = detail;
      if (coalesce != null) {
        final state = _coalesced[coalesce];
        if (state != null && now.difference(state.last) < coalesceWindow) {
          state.held += 1;
          return;
        }
        final total = (state?.held ?? 0) + 1;
        text = <String>[?detail, 'x$total'].join(' ');
        _coalesced[coalesce] = _Held(now);
      }
      _append(
        DiagnosticsEvent(
          at: now,
          kind: kind,
          session: session,
          detail: text == null ? null : _cut(text),
        ),
      );
    } catch (_) {
      // Best-effort: the log never throws.
    }
  }

  /// Records the start of a run, naming the last thing the previous run
  /// recorded: `previous=<kind>[/<detail>]@<UTC time>`, or `previous=none`.
  void noteLaunch() {
    try {
      final all = events();
      final String previous;
      if (all.isEmpty) {
        previous = 'previous=none';
      } else {
        final last = all.last;
        final what = last.detail == null
            ? last.kind
            : '${last.kind}/${last.detail}';
        previous = 'previous=$what@${_iso(last.at)}';
      }
      note('launch', detail: previous);
    } catch (_) {
      // Best-effort.
    }
  }

  /// Every readable event, oldest first. A torn line is skipped.
  List<DiagnosticsEvent> events() {
    try {
      return _decodeAll(_storage.read());
    } catch (_) {
      return const <DiagnosticsEvent>[];
    }
  }

  /// The log as text to paste: the [header] lines, then one line per event,
  /// oldest first: `<UTC time> <kind>[ s:<session>][ <detail>]`.
  String shareText({List<String> header = const <String>[]}) {
    final lines = <String>[...header];
    for (final event in events()) {
      final session = event.session == null ? '' : ' s:${event.session}';
      final detail = event.detail == null ? '' : ' ${event.detail}';
      lines.add('${_iso(event.at)} ${event.kind}$session$detail');
    }
    return lines.join('\n');
  }

  // -- Storage ---------------------------------------------------------------

  void _append(DiagnosticsEvent event) {
    var out = '';
    if (_lineCount == null) {
      // First use in this process: count what is there and start on a fresh
      // line when a kill left the last one torn.
      final existing = _storage.read();
      _lineCount = _lines(existing).length;
      if (existing.isNotEmpty && !existing.endsWith('\n')) out = '\n';
    }
    out += '${_encode(event)}\n';
    if (!_storage.append(out)) return;
    _lineCount = (_lineCount ?? 0) + 1;
    if ((_lineCount ?? 0) >= _capacity + _slack) _compact();
  }

  /// Keeps the newest `capacity` events. A read that finds nothing never
  /// empties the file, and a rewrite that fails leaves it as it was; both back
  /// the count off to the capacity, so the next attempt comes after `slack`
  /// more events instead of at every note.
  void _compact() {
    final all = _decodeAll(_storage.read());
    final kept = all.length > _capacity
        ? all.sublist(all.length - _capacity)
        : all;
    if (kept.isEmpty) {
      _lineCount = _capacity;
      return;
    }
    final text = kept.map((e) => '${_encode(e)}\n').join();
    _lineCount = _storage.replace(text) ? kept.length : _capacity;
  }

  // -- Lines -----------------------------------------------------------------

  static List<String> _lines(String text) =>
      text.split('\n').where((l) => l.isNotEmpty).toList();

  static List<DiagnosticsEvent> _decodeAll(String text) {
    final events = <DiagnosticsEvent>[];
    for (final line in _lines(text)) {
      final event = _decode(line);
      if (event != null) events.add(event);
    }
    return events;
  }

  static String _cut(String text) {
    final flat = text.replaceAll('\n', ' ');
    return flat.length <= detailLimit ? flat : flat.substring(0, detailLimit);
  }

  /// UTC, seconds precision, like the watch's log: `2026-07-13T06:00:00Z`.
  static String _iso(DateTime at) =>
      at.toUtc().toIso8601String().replaceFirst(RegExp(r'\.\d+Z$'), 'Z');

  static String _encode(DiagnosticsEvent event) {
    return jsonEncode(<String, String>{
      'at': _iso(event.at),
      'kind': event.kind,
      if (event.session != null) 'session': event.session!,
      if (event.detail != null) 'detail': event.detail!,
    });
  }

  static DiagnosticsEvent? _decode(String line) {
    try {
      final object = jsonDecode(line);
      if (object is! Map<String, dynamic>) return null;
      final at = object['at'];
      final kind = object['kind'];
      if (at is! String || kind is! String) return null;
      return DiagnosticsEvent(
        at: DateTime.parse(at),
        kind: kind,
        session: object['session'] as String?,
        detail: object['detail'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}

class _Held {
  _Held(this.last);

  final DateTime last;
  int held = 0;
}
