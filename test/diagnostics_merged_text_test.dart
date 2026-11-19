// The phone's Copy row merges the watch's received log into the share text
// (plan 144, S-14405, D-14405).

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/diagnostics_log.dart';
import 'package:omnitrain/core/services/diagnostics_storage.dart';

void main() {
  final phoneClockTimes = [
    DateTime.utc(2026, 7, 13, 6),
    DateTime.utc(2026, 7, 13, 6, 0, 2),
  ];

  DiagnosticsLog phoneLog() {
    var i = 0;
    final log = DiagnosticsLog(
      storage: InMemoryDiagnosticsStorage(),
      clock: () => phoneClockTimes[i++],
    );
    log.note('launch');
    log.note('frame_sent', session: 's-1', detail: 'watch_ping delivered');
    return log;
  }

  /// A storage holding the watch's two lines, written through a log so the
  /// line shape is the log's own.
  DiagnosticsStorage watchStorageOf(List<DiagnosticsEvent> events) {
    final storage = InMemoryDiagnosticsStorage();
    var at = DateTime.utc(2026, 7, 13, 6, 0, 1);
    final writer = DiagnosticsLog(
      storage: storage,
      clock: () => at,
    );
    for (final event in events) {
      writer.note(event.kind, session: event.session, detail: event.detail);
      at = at.add(const Duration(seconds: 2));
    }
    return storage;
  }

  test('S-14405 the merged text interleaves both logs by time, tagged', () {
    final log = phoneLog();
    log.attachWatchReceived(
      watchStorageOf(<DiagnosticsEvent>[
        DiagnosticsEvent(at: DateTime.utc(2026, 7, 13, 6, 0, 1), kind: 'launch'),
        DiagnosticsEvent(
          at: DateTime.utc(2026, 7, 13, 6, 0, 3),
          kind: 'scene',
          detail: 'background',
        ),
      ]),
      () => DateTime.utc(2026, 7, 13, 6, 5),
    );

    expect(log.shareTextWithWatch(header: ['H']), 'H\n'
        'Watch log received 2026-07-13T06:05:00Z\n'
        "Times are each device's own clock\n"
        '2026-07-13T06:00:00Z [phone] launch\n'
        '2026-07-13T06:00:01Z [watch] launch\n'
        '2026-07-13T06:00:02Z [phone] frame_sent s:s-1 watch_ping delivered\n'
        '2026-07-13T06:00:03Z [watch] scene background');
  });

  test('S-14405 equal times put the phone first, then stored order', () {
    final log = phoneLog();
    final watchStorage = InMemoryDiagnosticsStorage();
    final writer = DiagnosticsLog(
      storage: watchStorage,
      clock: () => DateTime.utc(2026, 7, 13, 6),
    );
    writer.note('scene', detail: 'first');
    writer.note('scene', detail: 'second');
    log.attachWatchReceived(watchStorage, () => null);

    expect(log.shareTextWithWatch(), 'Watch log received (time unknown)\n'
        "Times are each device's own clock\n"
        '2026-07-13T06:00:00Z [phone] launch\n'
        '2026-07-13T06:00:00Z [watch] scene first\n'
        '2026-07-13T06:00:00Z [watch] scene second\n'
        '2026-07-13T06:00:02Z [phone] frame_sent s:s-1 watch_ping delivered');
  });

  test('S-14405 an attached but empty watch log says so and tags the phone', () {
    final log = phoneLog();
    log.attachWatchReceived(InMemoryDiagnosticsStorage(), () => null);

    expect(log.shareTextWithWatch(header: ['H']), 'H\n'
        'Watch log not received\n'
        '2026-07-13T06:00:00Z [phone] launch\n'
        '2026-07-13T06:00:02Z [phone] frame_sent s:s-1 watch_ping delivered');
  });

  test('S-14405 no attached storage is exactly shareText', () {
    final log = phoneLog();

    expect(
      log.shareTextWithWatch(header: ['H']),
      log.shareText(header: ['H']),
      reason: 'S-14405 without a watch log the text is unchanged',
    );
    expect(
      log.shareTextWithWatch(header: ['H']),
      contains('2026-07-13T06:00:00Z launch'),
      reason: 'S-14405 untagged, as shareText writes it',
    );
    expect(log.shareTextWithWatch(header: ['H']), isNot(contains('[phone]')));
  });

  test('S-14405 a null receivedAt with events says the time is unknown', () {
    final log = phoneLog();
    log.attachWatchReceived(watchStorageOf(<DiagnosticsEvent>[
      DiagnosticsEvent(at: DateTime.utc(2026, 7, 13, 6, 0, 1), kind: 'launch'),
    ]), () => null);

    expect(
      log.shareTextWithWatch(header: ['H']).split('\n')[1],
      'Watch log received (time unknown)',
    );
  });

  test('S-14405 watchEvents skips a torn last line', () {
    final storage = InMemoryDiagnosticsStorage();
    final writer = DiagnosticsLog(storage: storage, clock: () => DateTime.utc(2026, 7, 13, 6));
    writer.note('launch');
    storage.append('{"at":"2026-07-13T06:00:0');

    final log = DiagnosticsLog(storage: InMemoryDiagnosticsStorage());
    log.attachWatchReceived(storage, () => null);

    final watch = log.watchEvents();
    expect(watch, hasLength(1), reason: 'S-14405 only the whole line reads');
    expect(watch.first.kind, 'launch');
  });
}
