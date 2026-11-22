// A frame the peer queued while the app was closed is read when the plugin
// attaches (Android).
//
// Plan: `docs/plans/2026-11-22-295-wear-start-up-read-plan/2026-11-22-295-wear-start-up-read-plan.md`
// (D-29501..D-29503). No Kotlin test harness exists, so these are source
// guards on the plugin; the behaviour on a data layer is the emulator proof
// (S-29505) and owner check 15.
//   S-29501 the attach reads what is waiting, after the listeners, before the peer
//   S-29502 the read lists the data items, survives a failed listing, releases
//   S-29503 the change event and the read share one rule
//   S-29504 the rule: queued frames of the peer only, emitted before deleted

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final String _source = File(
  'packages/omnitrain_watch_link/android/src/main/kotlin/dev/sasha/'
  'omnitrain/watch_link/OmniTrainWatchLinkPlugin.kt',
).readAsStringSync().replaceAll('\r\n', '\n');

/// The text of the member that starts with [signature], up to the next member
/// or comment block at the same indentation.
String _body(String signature) {
  final start = _source.indexOf(signature);
  expect(start, greaterThan(0), reason: '$signature is missing');
  final rest = _source.substring(start + signature.length);
  final next = RegExp(
    r'\n    (/\*\*|// MARK|private fun |override fun )',
  ).firstMatch(rest);
  return _source.substring(
    start,
    next == null ? _source.length : start + signature.length + next.start,
  );
}

void main() {
  test('S-29501 the attach reads what is waiting, after the listeners', () {
    final body = _body('override fun onAttachedToEngine(');

    final listeners = body.indexOf('attachListeners()');
    final read = body.indexOf('drainWaiting()');
    final peer = body.indexOf('resolvePeer()');
    expect(listeners, greaterThan(0));
    expect(read, greaterThan(listeners));
    expect(peer, greaterThan(read));
  });

  test(
    'S-29502 the read lists the data items, survives a failure, releases',
    () {
      final body = _body('private fun drainWaiting(');

      expect(body, contains('val client = dataClient ?: return'));
      expect(body, contains('client.dataItems.addOnCompleteListener'));
      expect(
        body,
        contains('if (!task.isSuccessful) return@addOnCompleteListener'),
      );
      expect(body, contains('for (item in items) takeQueuedItem(item)'));
      final loop = body.indexOf('takeQueuedItem(item)');
      final finallyAt = body.indexOf('finally');
      final release = body.indexOf('items.release()');
      expect(finallyAt, greaterThan(loop));
      expect(release, greaterThan(finallyAt));
    },
  );

  test('S-29503 the change event and the read share one rule', () {
    final body = _body('private fun onDataChanged(');

    expect(
      body,
      contains('if (event.type != DataEvent.TYPE_CHANGED) continue'),
    );
    expect(body, contains('takeQueuedItem(event.dataItem)'));
    expect(body, contains('buffer.release()'));
    expect(body, isNot(contains('QUEUE_PREFIX')));
    expect(body, isNot(contains('KEY_ROLE')));
    expect(body, isNot(contains('deleteDataItems')));
    expect(body, isNot(contains('emit(')));
  });

  test(
    'S-29504 the rule takes the peer\'s queued frames, emit before delete',
    () {
      final body = _body('private fun takeQueuedItem(');

      expect(body, contains('if (!path.startsWith(QUEUE_PREFIX)) return'));
      expect(
        body,
        contains('if (map.getString(KEY_ROLE) == ownRole()) return'),
      );
      expect(body, contains('val frame = decodeFrame(frameBytes) ?: return'));
      final emit = body.indexOf('emit(mapOf("kind" to "userInfo"');
      final delete = body.indexOf('dataClient?.deleteDataItems(uri)');
      expect(emit, greaterThan(0));
      expect(delete, greaterThan(emit));
    },
  );
}
