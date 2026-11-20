import 'dart:convert';

import 'backup_snapshot.dart';

const String _formatMarker = 'omnitrain-backup';
const int _formatVersion = 1;

const String _notBackupMessage = 'This is not an OmniTrain backup file.';
const String _wrongFormatVersionMessage =
    'This backup was made by a different version of the file format.';
const String _damagedMessage = 'This backup file is damaged.';

/// Thrown when a text is not a readable, well-formed OmniTrain backup.
class BackupFormatException implements Exception {
  BackupFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The file header, readable without validating the body.
class BackupHeader {
  const BackupHeader({
    required this.appVersion,
    required this.exportedAtMs,
    required this.dataVersion,
    required this.formatVersion,
  });

  final String appVersion;
  final int exportedAtMs;
  final int dataVersion;
  final int formatVersion;
}

/// Encodes [snapshot] as the backup file text (D-27801).
String encodeBackup(
  BackupSnapshot snapshot, {
  required String appVersion,
  DateTime? now,
}) {
  return jsonEncode(<String, Object?>{
    'format': _formatMarker,
    'formatVersion': _formatVersion,
    'appVersion': appVersion,
    'exportedAtMs': (now ?? DateTime.now()).toUtc().millisecondsSinceEpoch,
    'dataVersion': snapshot.dataVersion,
    'catalogVersion': snapshot.catalogVersion,
    'collections': snapshot.collections,
    'lists': snapshot.lists,
    'meta': snapshot.meta,
  });
}

/// Decodes a backup file text, throwing [BackupFormatException] for anything
/// that is not a well-formed backup (D-27811).
BackupSnapshot decodeBackup(String text) {
  final root = _decodeRoot(text);
  _checkFormatVersion(root);

  final dataVersion = root['dataVersion'];
  if (dataVersion is! int) {
    throw BackupFormatException(_damagedMessage);
  }
  final catalogVersion = root['catalogVersion'];
  if (catalogVersion is! int) {
    throw BackupFormatException(_damagedMessage);
  }

  final rawCollections = root['collections'];
  if (rawCollections is! Map) {
    throw BackupFormatException(_damagedMessage);
  }
  final collections = <String, Map<String, Object?>>{};
  for (final entry in rawCollections.entries) {
    final key = entry.key;
    final value = entry.value;
    if (key is! String || value is! Map) {
      throw BackupFormatException(_damagedMessage);
    }
    for (final row in value.entries) {
      if (row.value is! Map) {
        throw BackupFormatException(_damagedMessage);
      }
    }
    collections[key] = _normalizeMap(value);
  }

  final rawLists = root['lists'];
  if (rawLists is! Map) {
    throw BackupFormatException(_damagedMessage);
  }
  final lists = <String, Map<String, List<Object?>>>{};
  for (final boxEntry in rawLists.entries) {
    final boxName = boxEntry.key;
    final rows = boxEntry.value;
    if (boxName is! String || rows is! Map) {
      throw BackupFormatException(_damagedMessage);
    }
    final boxRows = <String, List<Object?>>{};
    for (final rowEntry in rows.entries) {
      final rowKey = rowEntry.key;
      final value = rowEntry.value;
      if (rowKey is! String || value is! List) {
        throw BackupFormatException(_damagedMessage);
      }
      boxRows[rowKey] = _normalizeList(value);
    }
    lists[boxName] = boxRows;
  }

  final rawMeta = root['meta'];
  if (rawMeta is! Map) {
    throw BackupFormatException(_damagedMessage);
  }
  final meta = <String, Object?>{};
  for (final entry in rawMeta.entries) {
    final key = entry.key;
    final value = entry.value;
    if (key is! String || !(value is bool || value is int || value is String)) {
      throw BackupFormatException(_damagedMessage);
    }
    meta[key] = value;
  }

  return BackupSnapshot(
    collections: collections,
    lists: lists,
    meta: meta,
    dataVersion: dataVersion,
    catalogVersion: catalogVersion,
  );
}

/// Reads the header of a backup text without validating its body (D-27801).
/// Throws [BackupFormatException] for the same marker and format-version
/// failures as [decodeBackup].
BackupHeader decodeBackupHeader(String text) {
  final root = _decodeRoot(text);
  _checkFormatVersion(root);

  final appVersion = root['appVersion'];
  final exportedAtMs = root['exportedAtMs'];
  final dataVersion = root['dataVersion'];
  if (appVersion is! String || exportedAtMs is! int || dataVersion is! int) {
    throw BackupFormatException(_damagedMessage);
  }

  return BackupHeader(
    appVersion: appVersion,
    exportedAtMs: exportedAtMs,
    dataVersion: dataVersion,
    formatVersion: _formatVersion,
  );
}

Map<String, Object?> _decodeRoot(String text) {
  Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException {
    throw BackupFormatException(_notBackupMessage);
  }
  if (decoded is! Map) {
    throw BackupFormatException(_notBackupMessage);
  }

  final root = <String, Object?>{};
  for (final entry in decoded.entries) {
    final key = entry.key;
    if (key is! String) {
      throw BackupFormatException(_notBackupMessage);
    }
    root[key] = entry.value;
  }
  if (root['format'] != _formatMarker) {
    throw BackupFormatException(_notBackupMessage);
  }
  return root;
}

void _checkFormatVersion(Map<String, Object?> root) {
  final version = root['formatVersion'];
  if (version is! int || version != _formatVersion) {
    throw BackupFormatException(_wrongFormatVersionMessage);
  }
}

Map<String, Object?> _normalizeMap(Map<dynamic, dynamic> value) {
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    final key = entry.key;
    if (key is! String) {
      throw BackupFormatException(_damagedMessage);
    }
    result[key] = _normalizeValue(entry.value);
  }
  return result;
}

List<Object?> _normalizeList(List<dynamic> value) {
  return <Object?>[for (final item in value) _normalizeValue(item)];
}

Object? _normalizeValue(Object? value) {
  if (value is Map) return _normalizeMap(value);
  if (value is List) return _normalizeList(value);
  return value;
}
