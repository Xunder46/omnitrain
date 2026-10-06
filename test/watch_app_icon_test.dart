// Watch app icon guard — the shell's 1024 watchOS slot must declare the
// flattened copy of the phone's icon, and the copy must be opaque.
//
// Plan: `docs/plans/2026-10-04-14-watch-shell-bridge-plan/`.
// Scenario: S-101 the watch icon is declared, present and opaque (D-14).
//
// The watch icon is the phone's 1024 PNG flattened: watchOS and the App Store
// reject an icon that carries an alpha channel. The guard reads the PNG header
// rather than trusting the copy, and names the phone icon's colour type in
// every failure so a mismatch is diagnosable. No image package — the IHDR is
// enough.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const String _watchIconSet =
    'ios/OmniTrain Watch App/Assets.xcassets/AppIcon.appiconset';
const String _phoneIconSet = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
const String _phoneIconName = 'Icon-App-1024x1024@1x.png';

Map<String, Object?> _readJson(String relativePath) =>
    jsonDecode(
          File('${Directory.current.path}/$relativePath').readAsStringSync(),
        )
        as Map<String, Object?>;

int _be32(List<int> bytes, int offset) =>
    (bytes[offset] << 24) |
    (bytes[offset + 1] << 16) |
    (bytes[offset + 2] << 8) |
    bytes[offset + 3];

/// The PNG IHDR: width at bytes 16–19, height at 20–23, colour type at 25.
({int width, int height, int colorType}) _readIhdr(String relativePath) {
  final bytes = File(
    '${Directory.current.path}/$relativePath',
  ).readAsBytesSync();
  return (
    width: _be32(bytes, 16),
    height: _be32(bytes, 20),
    colorType: bytes[25],
  );
}

void main() {
  test('S-101 the watch icon slot names the flattened phone icon and it is '
      'opaque', () {
    final phone = _readIhdr('$_phoneIconSet/$_phoneIconName');
    final phoneColorType = phone.colorType;

    final contents = _readJson('$_watchIconSet/Contents.json');
    final images = (contents['images']! as List).cast<Map<String, Object?>>();
    final slot = images.singleWhere(
      (image) => image['size'] == '1024x1024' && image['platform'] == 'watchos',
      orElse: () => fail('the watch appiconset has no 1024 watchos slot'),
    );

    final filename = slot['filename'] as String?;
    expect(
      filename,
      isNotNull,
      reason:
          'the 1024 watchos slot must name a file '
          '(phone icon colour type: $phoneColorType)',
    );

    final watchPath = '$_watchIconSet/$filename';
    final watchFile = File('${Directory.current.path}/$watchPath');
    expect(
      watchFile.existsSync(),
      isTrue,
      reason:
          'the slot names $filename but the file is missing '
          '(phone icon colour type: $phoneColorType)',
    );
    expect(
      watchFile.lengthSync(),
      greaterThan(0),
      reason:
          'the watch icon $filename is empty '
          '(phone icon colour type: $phoneColorType)',
    );

    final watch = _readIhdr(watchPath);
    expect(
      [watch.width, watch.height],
      [1024, 1024],
      reason:
          'the watch icon $filename must be 1024x1024 '
          '(phone icon colour type: $phoneColorType)',
    );
    expect(
      watch.colorType,
      isNot(6),
      reason:
          'the watch icon $filename carries an alpha channel (colour type '
          '6); watchOS rejects it. Phone icon colour type: $phoneColorType',
    );
  });
}
