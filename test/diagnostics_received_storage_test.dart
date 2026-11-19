// The storage that holds the watch's received log (plan 144, S-14407, D-14406).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/diagnostics_log.dart';
import 'package:omnitrain/core/services/diagnostics_storage.dart';
import 'package:omnitrain/core/services/diagnostics_storage_default_stub.dart';
import 'package:omnitrain/core/services/diagnostics_storage_io.dart';

void main() {
  test('S-14407 modified() is null before the file exists and a time after', () {
    final dir = Directory.systemTemp.createTempSync('diag');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/watch-received.jsonl');
    final storage = FileDiagnosticsStorage(file);

    expect(storage.modified(), isNull, reason: 'S-14407 nothing received yet');

    expect(storage.replace('x'), isTrue, reason: 'S-14407 the replace wrote');
    final modified = storage.modified();
    expect(modified, isNotNull, reason: 'S-14407 the file exists now');
    expect(modified, isA<DateTime>());
  });

  test('S-14407 a log attached to a file storage reads what was written', () {
    final dir = Directory.systemTemp.createTempSync('diag');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/watch-diagnostics/watch-received.jsonl');
    final storage = FileDiagnosticsStorage(file);

    final writer = DiagnosticsLog(
      storage: storage,
      clock: () => DateTime.utc(2026, 7, 13, 6, 0, 1),
    );
    writer.note('launch', detail: 'previous=none');
    writer.note('scene', detail: 'background');

    final log = DiagnosticsLog(storage: InMemoryDiagnosticsStorage());
    log.attachWatchReceived(storage, storage.modified);

    final watch = log.watchEvents();
    expect(watch, hasLength(2), reason: 'S-14407 both events read back');
    expect(watch.map((e) => e.kind).toList(), ['launch', 'scene'],
        reason: 'S-14407 the kinds, in order');
    expect(
      log.shareTextWithWatch(header: ['H']),
      contains('2026-07-13T06:00:01Z [watch] launch'),
      reason: "S-14407 the merged text carries the file's lines",
    );
  });

  test('S-14407 the stub answers empty storage and a null receivedAt', () async {
    final source = await openWatchReceivedStorage();

    final watch = DiagnosticsLog(storage: InMemoryDiagnosticsStorage());
    watch.attachWatchReceived(source.storage, source.receivedAt);
    expect(watch.watchEvents(), isEmpty, reason: 'S-14407 the stub holds nothing');
    expect(source.receivedAt(), isNull, reason: 'S-14407 no arrival time');
  });
}
