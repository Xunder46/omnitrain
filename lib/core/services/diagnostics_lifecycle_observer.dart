import 'package:flutter/widgets.dart';

import 'diagnostics_log.dart';

/// Notes every app lifecycle state into the diagnostics log (plan 143,
/// D-14304): `resumed`, `inactive`, `hidden`, `paused` and `detached`.
///
/// `lib/state/watch/watch_resume_sync.dart` acts on `resumed` only; this one
/// only records, for every state, so a gap in the log can be read against what
/// the app was last doing. Observation only: it never changes what happens.
class DiagnosticsLifecycleObserver with WidgetsBindingObserver {
  DiagnosticsLifecycleObserver(this._log);

  final DiagnosticsLog _log;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _log.note('app_lifecycle', detail: state.name);
  }
}
