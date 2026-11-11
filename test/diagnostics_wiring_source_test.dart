import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('S-14316 main.dart builds the log once, notes the launch, observes', () {
    final source = File('lib/main.dart').readAsStringSync();
    expect(
      source,
      contains('final diagnostics = DiagnosticsLog(storage: await openDefaultDiagnosticsStorage());'),
      reason: 'main.dart must build the diagnostics log once at startup',
    );
    expect(
      source,
      contains('diagnostics.noteLaunch();'),
      reason: 'main.dart must note the launch into the log',
    );
    expect(
      source,
      contains('WidgetsBinding.instance.addObserver(DiagnosticsLifecycleObserver(diagnostics));'),
      reason: 'main.dart must mount the lifecycle observer',
    );

    // The log reaches the watch graph: `diagnostics: diagnostics,` sits inside
    // the createWatchSync( call, not in some later one.
    final callAt = source.indexOf('await createWatchSync(');
    expect(callAt, greaterThan(0), reason: 'main.dart lost the watch graph build');
    final callEnd = source.indexOf(');', callAt);
    expect(callEnd, greaterThan(callAt));
    expect(
      source.substring(callAt, callEnd),
      contains('diagnostics: diagnostics,'),
      reason: 'the log must be passed into the createWatchSync call',
    );
  });

  test('S-14316 the wiring passes diagnostics to the platform transport', () {
    final source = File('lib/state/watch/watch_sync_wiring.dart').readAsStringSync();

    expect(
      source,
      contains('DiagnosticsLog? diagnostics,'),
      reason: 'createWatchSync must take the optional diagnostics parameter',
    );

    final transportAt = source.indexOf('createPlatformWatchTransport(');
    expect(
      transportAt,
      greaterThan(0),
      reason: 'the wiring lost the platform transport build',
    );
    final transportEnd = source.indexOf(');', transportAt);
    expect(transportEnd, greaterThan(transportAt));
    expect(
      source.substring(transportAt, transportEnd),
      contains('diagnostics: diagnostics'),
      reason: 'the diagnostics log must reach createPlatformWatchTransport',
    );
  });
}
