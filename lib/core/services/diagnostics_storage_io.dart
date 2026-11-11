import 'dart:convert';
import 'dart:io';

import 'diagnostics_storage.dart';

/// Keeps the log's text in one file. Every operation is synchronous and
/// swallows its own failure (plan 143, D-14301): the log is observation only.
class FileDiagnosticsStorage implements DiagnosticsStorage {
  FileDiagnosticsStorage(this.file);

  final File file;

  @override
  String read() {
    try {
      if (!file.existsSync()) return '';
      // A kill mid-append can cut a multi-byte character: decode what is there.
      return utf8.decode(file.readAsBytesSync(), allowMalformed: true);
    } catch (_) {
      return '';
    }
  }

  @override
  bool append(String text) {
    try {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(text, mode: FileMode.append);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  bool replace(String text) {
    try {
      final temp = File('${file.path}.tmp');
      temp.writeAsStringSync(text, flush: true);
      temp.renameSync(file.path);
      return true;
    } catch (_) {
      return false;
    }
  }
}
