import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';

/// The two file jobs of the backup: hand a text file to the system share
/// sheet, and read a text file the user picks. Behind an interface so the
/// screens never touch a plugin (plan 278b, D-27821).
abstract class BackupFileGateway {
  /// Opens the share sheet with [text] as a file named [fileName]. Returns
  /// true when the sheet was shown (whatever the user then did with it), false
  /// when it could not be shown.
  Future<bool> shareText({required String fileName, required String text});

  /// Lets the user pick a file and returns its text; null when the user
  /// cancelled. A file that is not valid UTF-8 comes back as '' (the backup
  /// service then refuses it as "not a backup file").
  Future<String?> pickText();
}

typedef BackupShareFn = Future<void> Function(String fileName, Uint8List bytes);
typedef BackupPickFn = Future<Uint8List?> Function();

class PlatformBackupFileGateway implements BackupFileGateway {
  PlatformBackupFileGateway({BackupShareFn? share, BackupPickFn? pick})
    : _share = share ?? _sharePlugin,
      _pick = pick ?? _pickPlugin;
  final BackupShareFn _share;
  final BackupPickFn _pick;

  @override
  Future<bool> shareText({
    required String fileName,
    required String text,
  }) async {
    try {
      await _share(fileName, Uint8List.fromList(utf8.encode(text)));
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<String?> pickText() async {
    final bytes = await _pick();
    if (bytes == null) return null;
    try {
      return utf8.decode(bytes);
    } on FormatException {
      return '';
    }
  }

  static Future<void> _sharePlugin(String fileName, Uint8List bytes) async {
    await SharePlus.instance.share(
      ShareParams(
        files: <XFile>[
          XFile.fromData(bytes, name: fileName, mimeType: 'application/json'),
        ],
        fileNameOverrides: <String>[fileName],
        title: fileName,
      ),
    );
  }

  static Future<Uint8List?> _pickPlugin() async {
    final result = await FilePicker.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return null;
    return result.files.first.bytes;
  }
}
