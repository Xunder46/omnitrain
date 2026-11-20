import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:omnitrain/core/services/backup_file_gateway.dart';

void main() {
  test(
    'S-27830 shareText: share seam receives file name and UTF-8 bytes, returns true',
    () async {
      final received = <String, Object?>{};
      final gateway = PlatformBackupFileGateway(
        share: (fileName, bytes) async {
          received['fileName'] = fileName;
          received['bytes'] = bytes;
        },
        pick: () => throw StateError('not used'),
      );
      const text = 'héllo 💪 {"a":1}';
      const fileName = 'omnitrain-backup-2026-11-19.json';

      final shown = await gateway.shareText(fileName: fileName, text: text);

      expect(
        shown,
        isTrue,
        reason: 'S-27830: shareText returns true when the seam succeeds',
      );
      expect(
        received['fileName'],
        fileName,
        reason: 'S-27830: share seam receives the file name',
      );
      final bytes = received['bytes']! as Uint8List;
      expect(
        utf8.decode(bytes),
        text,
        reason: 'S-27830: share seam receives UTF-8 bytes of the text',
      );
      expect(
        bytes,
        utf8.encode(text),
        reason: 'S-27830: bytes equal utf8.encode of the text',
      );
    },
  );

  test(
    'S-27830 shareText: throwing share seam returns false without throwing',
    () async {
      final gateway = PlatformBackupFileGateway(
        share: (fileName, bytes) => throw StateError('share sheet unavailable'),
        pick: () => throw StateError('not used'),
      );

      final shown = await gateway.shareText(fileName: 'x.json', text: '{}');

      expect(
        shown,
        isFalse,
        reason: 'S-27830: shareText returns false when the seam throws',
      );
    },
  );

  test('S-27830 pickText: pick seam bytes are decoded to text', () async {
    const text = '{"format":"omnitrain-backup"}';
    final gateway = PlatformBackupFileGateway(
      share: (fileName, bytes) => throw StateError('not used'),
      pick: () async => Uint8List.fromList(utf8.encode(text)),
    );

    expect(
      await gateway.pickText(),
      text,
      reason: 'S-27830: pickText decodes bytes to text',
    );
  });

  test('S-27830 pickText: cancelled pick returns null', () async {
    final gateway = PlatformBackupFileGateway(
      share: (fileName, bytes) => throw StateError('not used'),
      pick: () async => null,
    );

    expect(
      await gateway.pickText(),
      isNull,
      reason: 'S-27830: cancelled pick returns null',
    );
  });

  test(
    'S-27830 pickText: invalid UTF-8 returns empty string without throwing',
    () async {
      final gateway = PlatformBackupFileGateway(
        share: (fileName, bytes) => throw StateError('not used'),
        pick: () async => Uint8List.fromList(<int>[0xff, 0xfe, 0xfd]),
      );

      expect(
        await gateway.pickText(),
        '',
        reason: 'S-27830: invalid UTF-8 comes back as empty string',
      );
    },
  );

  test('S-27832 source guard: gateway has no dart:io import', () {
    final source = File(
      'lib/core/services/backup_file_gateway.dart',
    ).readAsStringSync();

    expect(
      source.contains("import 'dart:io'"),
      isFalse,
      reason: "S-27832: backup_file_gateway.dart must not import dart:io",
    );
  });

  test(
    'S-27832 source guard: no share_plus/file_picker import outside the gateway',
    () {
      final offenders = <String>[];
      for (final dir in <String>['lib/features', 'lib/state', 'lib/widgets']) {
        for (final entity in Directory(dir).listSync(recursive: true)) {
          if (entity is! File || !entity.path.endsWith('.dart')) continue;
          final text = entity.readAsStringSync();
          if (text.contains('package:share_plus') ||
              text.contains('package:file_picker')) {
            offenders.add(entity.path);
          }
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'S-27832: only backup_file_gateway.dart may import share_plus/file_picker',
      );
    },
  );
}
