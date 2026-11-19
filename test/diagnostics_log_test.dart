// The phone's diagnostics log: what it records, reads and copies (plan 143).
//
// Plan: `docs/plans/2026-11-10-143-phone-diagnostics-log-plan/2026-11-10-143-phone-diagnostics-log-plan.md`
// (D-14301, D-14302, D-14307). Scenario mapping, with the Swift twin's
// fixtures (`watch/watchos/Tests/WatchSessionEngineTests/WatchDiagnosticsLogTests.swift`):
//   S-14301 persistence over a new log        → `S-14301 ...`
//   S-14302 the bound and the relaunch count  → `S-14302 ...`
//   S-14303 a torn last line                  → `S-14303 ...`
//   S-14304 a path that cannot be created     → `S-14304 ...`
//   S-14305 noteLaunch's previous reference   → `S-14305 ...`
//   S-14306 coalescing with an x<count>       → `S-14306 ...`
//   S-14307 the detail cut                    → `S-14307 ...`
//   S-14308 shareText                         → `S-14308 ...`
//   S-14302 a failed rewrite backs off        → `S-14302 ...` (review finding)

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/diagnostics_log.dart';
import 'package:omnitrain/core/services/diagnostics_storage.dart';
import 'package:omnitrain/core/services/diagnostics_storage_io.dart';

File _file(Directory dir) =>
    File('${dir.path}/watch-diagnostics/phone-diagnostics.jsonl');

List<String> _linesOf(String text) =>
    text.split('\n').where((l) => l.isNotEmpty).toList();

int _lineCount(File file) => _linesOf(file.readAsStringSync()).length;

class _FailingReplaceStorage extends InMemoryDiagnosticsStorage {
  bool failing = false;

  @override
  bool replace(String text) {
    if (failing) return false;
    return super.replace(text);
  }
}

void main() {
  group('DiagnosticsLog', () {
    test('S-14301 a new log over the same file reads the same events in order',
        () {
      var now = DateTime.utc(2026, 7, 13, 6);
      DateTime clock() => now;
      final dir = Directory.systemTemp.createTempSync('diag');
      addTearDown(() => dir.deleteSync(recursive: true));

      final first = DiagnosticsLog(
        storage: FileDiagnosticsStorage(_file(dir)),
        clock: clock,
      );
      first.note('launch');
      now = now.add(const Duration(seconds: 1));
      first.note('app_lifecycle', detail: 'paused');
      now = now.add(const Duration(seconds: 1));
      first.note('frame_sent', session: 's-1', detail: 'watch_ping delivered');

      final second = DiagnosticsLog(
        storage: FileDiagnosticsStorage(_file(dir)),
        clock: clock,
      );
      final events = second.events();
      expect(events, hasLength(3),
          reason: 'S-14301 the new log reads all three events');
      expect(events.map((e) => e.kind).toList(),
          ['launch', 'app_lifecycle', 'frame_sent'],
          reason: 'S-14301 the kinds, in order');
      expect(
        events.map((e) => e.session).toList(),
        [null, null, 's-1'],
        reason: 'S-14301 the sessions, in order',
      );
      expect(
        events.map((e) => e.detail).toList(),
        [null, 'paused', 'watch_ping delivered'],
        reason: 'S-14301 the details, in order',
      );
      expect(
        events.map((e) => e.at).toList(),
        [
          DateTime.utc(2026, 7, 13, 6),
          DateTime.utc(2026, 7, 13, 6, 0, 1),
          DateTime.utc(2026, 7, 13, 6, 0, 2),
        ],
        reason: 'S-14301 the times, in order',
      );
    });

    test('S-14302 thirty notes compact to the newest twenty', () {
      var now = DateTime.utc(2026, 7, 13, 6);
      DateTime clock() => now;
      final dir = Directory.systemTemp.createTempSync('diag');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = _file(dir);

      final log = DiagnosticsLog(
        storage: FileDiagnosticsStorage(file),
        clock: clock,
        capacity: 20,
        slack: 2,
      );
      for (var i = 1; i <= 30; i++) {
        log.note('note', detail: 'n$i');
      }

      expect(
        log.events().map((e) => e.detail).toList(),
        [for (var i = 11; i <= 30; i++) 'n$i'],
        reason: 'S-14302 the newest twenty, oldest first',
      );
      expect(_lineCount(file) <= 22, isTrue, reason: 'S-14302 the line count');

      final second = DiagnosticsLog(
        storage: FileDiagnosticsStorage(file),
        clock: clock,
      );
      expect(
        second.events().map((e) => e.detail).toList(),
        [for (var i = 11; i <= 30; i++) 'n$i'],
        reason: 'S-14302 the new log reads the same',
      );
    });

    test('S-14302 a relaunch counts what the file already holds', () {
      var now = DateTime.utc(2026, 7, 13, 6);
      DateTime clock() => now;
      final dir = Directory.systemTemp.createTempSync('diag');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = _file(dir);

      final first = DiagnosticsLog(
        storage: FileDiagnosticsStorage(file),
        clock: clock,
        capacity: 20,
        slack: 2,
      );
      for (var i = 1; i <= 21; i++) {
        first.note('note', detail: 'n$i');
      }
      expect(_lineCount(file), 21,
          reason: 'S-14302 no rewrite yet at 21 lines');

      final second = DiagnosticsLog(
        storage: FileDiagnosticsStorage(file),
        clock: clock,
        capacity: 20,
        slack: 2,
      );
      second.note('note', detail: 'n22');

      expect(_lineCount(file), 20,
          reason: 'S-14302 21 held lines and one new note compacted at once');
      expect(
        second.events().map((e) => e.detail).toList(),
        [for (var i = 3; i <= 22; i++) 'n$i'],
        reason: 'S-14302 the newest twenty survived, oldest first',
      );
    });

    test('S-14303 a torn last line is skipped and the next append starts fresh',
        () {
      var now = DateTime.utc(2026, 7, 13, 6);
      DateTime clock() => now;
      final dir = Directory.systemTemp.createTempSync('diag');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = _file(dir);

      final first = DiagnosticsLog(
        storage: FileDiagnosticsStorage(file),
        clock: clock,
      );
      first.note('launch');
      file.writeAsStringSync('{"at":"2026-07-13T06:00:0',
          mode: FileMode.append);

      final second = DiagnosticsLog(
        storage: FileDiagnosticsStorage(file),
        clock: clock,
      );
      final before = second.events();
      expect(before, hasLength(1), reason: 'S-14303 only the valid line reads');
      expect(before.first.kind, 'launch',
          reason: 'S-14303 the valid line is the launch');

      second.note('app_lifecycle');
      final after = second.events();
      expect(after.map((e) => e.kind).toList(), ['launch', 'app_lifecycle'],
          reason: 'S-14303 the new event reads back in order');

      final lines = _linesOf(file.readAsStringSync());
      expect(lines, hasLength(3), reason: 'S-14303 every record on its own line');
      expect(lines[1], '{"at":"2026-07-13T06:00:0',
          reason: 'S-14303 the torn fragment stays as it was');
      expect(jsonDecode(lines[0]), isA<Map<String, dynamic>>(),
          reason: 'S-14303 the first line is whole');
      expect(jsonDecode(lines[2]), isA<Map<String, dynamic>>(),
          reason: 'S-14303 the new event started on a fresh line');
    });

    test('S-14304 a path that cannot be created neither throws nor traps', () {
      var now = DateTime.utc(2026, 7, 13, 6);
      DateTime clock() => now;
      final dir = Directory.systemTemp.createTempSync('diag');
      addTearDown(() => dir.deleteSync(recursive: true));

      final block = File('${dir.path}/blocker');
      block.writeAsStringSync('');
      final log = DiagnosticsLog(
        storage: FileDiagnosticsStorage(File('${block.path}/sub/x.jsonl')),
        clock: clock,
      );

      expect(() => log.note('launch', detail: 'previous=none'), returnsNormally,
          reason: 'S-14304 note never throws');
      expect(log.events(), isEmpty, reason: 'S-14304 nothing was recorded');
      expect(log.shareText(), '', reason: 'S-14304 nothing to share');
    });

    test('S-14305 noteLaunch names the previous run and none when empty', () {
      var now = DateTime.utc(2026, 7, 13, 6);
      DateTime clock() => now;
      final dir = Directory.systemTemp.createTempSync('diag');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = _file(dir);

      final run1 = DiagnosticsLog(
        storage: FileDiagnosticsStorage(file),
        clock: clock,
      );
      run1.note('app_lifecycle', detail: 'paused');

      final run2 = DiagnosticsLog(
        storage: FileDiagnosticsStorage(file),
        clock: clock,
      );
      run2.noteLaunch();
      final launch = run2.events().last;
      expect(launch.kind, 'launch', reason: 'S-14305 the newest event');
      expect(launch.detail, 'previous=app_lifecycle/paused@2026-07-13T06:00:00Z',
          reason: "S-14305 the previous run's last act");

      final emptyDir = Directory.systemTemp.createTempSync('diag');
      addTearDown(() => emptyDir.deleteSync(recursive: true));
      final empty = DiagnosticsLog(
        storage: FileDiagnosticsStorage(_file(emptyDir)),
        clock: clock,
      );
      empty.noteLaunch();
      expect(empty.events().last.detail, 'previous=none',
          reason: 'S-14305 an empty log names nothing');

      final bareDir = Directory.systemTemp.createTempSync('diag');
      addTearDown(() => bareDir.deleteSync(recursive: true));
      final bare = DiagnosticsLog(
        storage: FileDiagnosticsStorage(_file(bareDir)),
        clock: clock,
      );
      bare.note('frame_sent');
      bare.noteLaunch();
      expect(bare.events().last.detail, 'previous=frame_sent@2026-07-13T06:00:00Z',
          reason: 'S-14305 no detail means no slash');
    });

    test('S-14306 a coalesced key records once per window and counts what it held',
        () {
      var now = DateTime.utc(2026, 7, 13, 6);
      DateTime clock() => now;
      final dir = Directory.systemTemp.createTempSync('diag');
      addTearDown(() => dir.deleteSync(recursive: true));

      final log = DiagnosticsLog(
        storage: FileDiagnosticsStorage(_file(dir)),
        clock: clock,
      );
      for (var i = 0; i < 30; i++) {
        log.note('frame_sent',
            detail: 'energy_live delivered',
            coalesce: 'frame_sent/energy_live');
        now = now.add(const Duration(milliseconds: 500));
      }
      now = now.add(const Duration(seconds: 61));
      log.note('frame_sent',
          detail: 'energy_live delivered', coalesce: 'frame_sent/energy_live');
      log.note('frame_sent',
          detail: 'paced delivered', coalesce: 'frame_sent/other');

      final sent = log.events().where((e) => e.kind == 'frame_sent').toList();
      expect(sent, hasLength(3),
          reason: 'S-14306 the held line, the window line, the other key');
      expect(
        sent.map((e) => e.detail).toList(),
        ['energy_live delivered x1', 'energy_live delivered x30', 'paced delivered x1'],
        reason: 'S-14306 the coalesced counts',
      );
    });

    test('S-14307 a long detail is cut to 120 characters without a newline', () {
      var now = DateTime.utc(2026, 7, 13, 6);
      DateTime clock() => now;
      final dir = Directory.systemTemp.createTempSync('diag');
      addTearDown(() => dir.deleteSync(recursive: true));

      final log = DiagnosticsLog(
        storage: FileDiagnosticsStorage(_file(dir)),
        clock: clock,
      );
      log.note('frame_sent', detail: '${'a' * 10}\n${'a' * 290}');

      final stored = log.events().first.detail;
      expect(stored, '${'a' * 10} ${'a' * 109}',
          reason: 'S-14307 the newline became a space, then the first 120');
      expect(stored!.length, 120, reason: 'S-14307 cut to the limit');
    });

    test('S-14308 shareText puts the header then one line per event', () {
      var now = DateTime.utc(2026, 7, 13, 6);
      DateTime clock() => now;
      final dir = Directory.systemTemp.createTempSync('diag');
      addTearDown(() => dir.deleteSync(recursive: true));

      final log = DiagnosticsLog(
        storage: FileDiagnosticsStorage(_file(dir)),
        clock: clock,
      );
      log.note('launch');
      now = now.add(const Duration(milliseconds: 5700));
      log.note('frame_sent', session: 's-1', detail: 'watch_ping delivered');

      expect(
        log.shareText(header: <String>[
          'OmniTrain phone diagnostics',
          'App 1.0 (1)',
          'Platform iOS',
        ]),
        'OmniTrain phone diagnostics\n'
            'App 1.0 (1)\n'
            'Platform iOS\n'
            '2026-07-13T06:00:00Z launch\n'
            '2026-07-13T06:00:05Z frame_sent s:s-1 watch_ping delivered',
        reason: 'S-14308 the header, then the events, oldest first',
      );
    });

    test('S-14302 a failed rewrite backs off instead of retrying every note',
        () {
      var now = DateTime.utc(2026, 7, 13, 6);
      DateTime clock() => now;
      final storage = _FailingReplaceStorage();

      final log = DiagnosticsLog(
        storage: storage,
        clock: clock,
        capacity: 20,
        slack: 2,
      );
      for (var i = 1; i <= 21; i++) {
        log.note('note', detail: 'n$i');
      }
      expect(_linesOf(storage.read()), hasLength(21),
          reason: 'S-14302 the twenty-one notes are held');

      storage.failing = true;
      log.note('note', detail: 'n22');
      expect(_linesOf(storage.read()), hasLength(22),
          reason: 'S-14302 the append worked and the failed rewrite left it as it was');
      expect(
        log.events().map((e) => e.detail).toList(),
        [for (var i = 1; i <= 22; i++) 'n$i'],
        reason: 'S-14302 nothing was lost',
      );

      storage.failing = false;
      log.note('note', detail: 'n23');
      expect(_linesOf(storage.read()), hasLength(23),
          reason: 'S-14302 the count backed off to 20, so no rewrite was attempted');

      log.note('note', detail: 'n24');
      expect(_linesOf(storage.read()), hasLength(20),
          reason: 'S-14302 the next note reaches the threshold and the rewrite succeeds');
      expect(
        log.events().map((e) => e.detail).toList(),
        [for (var i = 5; i <= 24; i++) 'n$i'],
        reason: 'S-14302 the newest twenty, oldest first',
      );
    });
  });
}
