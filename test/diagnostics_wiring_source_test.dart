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

  // Plan 174 (D-17401, S-17401..S-17412): the same log the transport gets also
  // reaches the adoption bridge and the inbox — the inbox forwards it to the
  // importer it builds, which is how the importer's decisions are recorded
  // without a second seam. A build that drops either argument records nothing
  // for a wrist session, which is what this scan catches.
  test('the wiring passes diagnostics to the adoption bridge and the inbox', () {
    final source = File('lib/state/watch/watch_sync_wiring.dart').readAsStringSync();

    for (final call in const [
      'final adoption = _WiringAdoptionBridge(',
      'final inbox = WatchSessionInbox(',
    ]) {
      final at = source.indexOf(call);
      expect(at, greaterThan(0), reason: 'the wiring lost the `$call` build');
      final end = source.indexOf('\n  );', at);
      expect(end, greaterThan(at));
      expect(
        source.substring(at, end),
        contains('diagnostics: diagnostics'),
        reason:
            '`$call` must receive the graph\'s diagnostics log, or the phone '
            'records no decision about a wrist session (D-17401)',
      );
    }
  });
}
