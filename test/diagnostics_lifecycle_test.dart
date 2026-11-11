import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:omnitrain/core/services/diagnostics_lifecycle_observer.dart';
import 'package:omnitrain/core/services/diagnostics_log.dart';
import 'package:omnitrain/core/services/diagnostics_storage.dart';

void main() {
  test('S-14314 the observer records app_lifecycle for every state, in order', () {
    final storage = InMemoryDiagnosticsStorage();
    final log = DiagnosticsLog(storage: storage);
    final observer = DiagnosticsLifecycleObserver(log);

    for (final state in AppLifecycleState.values) {
      observer.didChangeAppLifecycleState(state);
    }

    final events = log.events();
    expect(events.length, AppLifecycleState.values.length);
    for (var i = 0; i < AppLifecycleState.values.length; i++) {
      expect(events[i].kind, 'app_lifecycle');
      expect(events[i].detail, AppLifecycleState.values[i].name);
    }
  });

  test('S-14314 the observer never throws out of a throwing storage', () {
    final log = DiagnosticsLog(storage: _ThrowingStorage());
    final observer = DiagnosticsLifecycleObserver(log);

    for (final state in AppLifecycleState.values) {
      expect(
        () => observer.didChangeAppLifecycleState(state),
        returnsNormally,
      );
    }
  });
}

class _ThrowingStorage implements DiagnosticsStorage {
  @override
  String read() => throw StateError('boom');

  @override
  bool append(String text) => throw StateError('boom');

  @override
  bool replace(String text) => throw StateError('boom');
}
