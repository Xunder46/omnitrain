import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('S-14404 the phone plugin keeps the diagnostics log file the watch sends', () {
    final source =
        File('packages/omnitrain_watch_link/ios/Classes/OmniTrainWatchLinkPlugin.swift')
            .readAsStringSync();

    final signatureAt = source.indexOf('public func session(_ session: WCSession, didReceive file: WCSessionFile) {');
    expect(
      signatureAt,
      greaterThan(0),
      reason: 'the plugin must implement session(_:didReceive:)',
    );
    expect(
      source,
      contains('guard (file.metadata?["kind"] as? String) == "diagnostics_log" else { return }'),
      reason: 'only the diagnostics log is kept',
    );
    expect(
      source,
      contains('"watch-diagnostics"'),
      reason: 'the log lands in Application Support/watch-diagnostics',
    );
    expect(
      source,
      contains('"watch-received.jsonl"'),
      reason: 'the received file is stored as watch-received.jsonl',
    );
    expect(
      source,
      contains('try FileManager.default.copyItem(at: file.fileURL, to: staged)'),
      reason: 'the file must be copied before the callback ends',
    );
    expect(
      source,
      contains('try FileManager.default.replaceItemAt(destination, withItemAt: staged)'),
      reason: 'an existing received log is replaced atomically',
    );
    expect(
      source,
      contains('try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: destination.path)'),
      reason: 'the received log carries a fresh modification date',
    );

    final endAt = source.indexOf('NSLog("OmniTrainWatchLink: diagnostics log received")');
    expect(endAt, greaterThan(signatureAt), reason: 'the copy completes before the received log line');
    final body = source.substring(signatureAt, endAt);
    for (final forbidden in ['Task', 'async', 'await', 'DispatchQueue']) {
      expect(
        body,
        isNot(contains(forbidden)),
        reason: 'the copy must finish inside the callback, no $forbidden',
      );
    }

    expect(
      body,
      isNot(contains('emit(')),
      reason: 'a received file emits nothing to Dart',
    );
  });
}
