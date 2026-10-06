// A transport for tests that only need to know what the phone sent: it records
// what the phone emitted and carries nothing.
//
// The wire itself is proven in `test/phone_manage_bridge_test.dart`, where both
// devices are real.

import 'package:omnitrain/state/watch/live_session_mirror_state.dart';

/// Records what the phone emitted and carries nothing.
class RecordingMirrorTransport implements WatchMirrorTransport {
  final List<Map<String, Object?>> sent = [];
  int snapshotRequests = 0;

  /// The payloads of every message of [type] the phone sent.
  List<Map<String, Object?>> payloadsOf(String type) => [
    for (final envelope in sent)
      if (envelope['type'] == type) (envelope['payload']! as Map).cast(),
  ];

  /// The `changes` of the one `structure_change` the phone sent, as the `kind`
  /// of each change.
  List<Object?> changeKinds() => [
    for (final payload in payloadsOf('structure_change'))
      for (final change in payload['changes']! as List) (change as Map)['kind'],
  ];

  @override
  Future<void> send(Map<String, Object?> envelope) async => sent.add(envelope);

  @override
  Future<void> requestSnapshot() async => snapshotRequests++;
}
