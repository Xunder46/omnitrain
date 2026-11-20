import 'dart:convert';

import 'package:omnitrain/data/models/backup_codec.dart';
import 'package:omnitrain/data/models/backup_snapshot.dart';
import 'package:test/test.dart';

const String _notBackup = 'This is not an OmniTrain backup file.';
const String _wrongFormat =
    'This backup was made by a different version of the file format.';
const String _damaged = 'This backup file is damaged.';

BackupSnapshot _fullSnapshot() => BackupSnapshot(
  collections: {
    'training_sessions': {
      's1': <String, Object?>{
        'id': 's1',
        'scheduled_date_ms': 1788000000000,
        'volume_kg': 72.5,
        'note': 'He said "go"\nline 💪 and \\ slash',
        'deleted_at_ms': null,
        'nested': <String, Object?>{
          'a': 1,
          'b': <String, Object?>{'c': 'd'},
        },
        'tags': <Object?>['x', 2, null],
      },
    },
    'exercises': {
      'e1': <String, Object?>{'id': 'e1', 'name': 'Squat'},
    },
  },
  lists: {
    'exercise_muscle_groups': {
      's1': <Object?>[
        'quads',
        7,
        null,
        <Object?>['nested', true],
      ],
    },
  },
  meta: {'app_theme': 'dark', 'onboarding_complete': true, 'data_version': 20},
  dataVersion: 20,
  catalogVersion: 3,
);

BackupSnapshot _emptySnapshot() => const BackupSnapshot(
  collections: {},
  lists: {},
  meta: {},
  dataVersion: 20,
  catalogVersion: 3,
);

Map<String, Object?> _validBackupMap() => <String, Object?>{
  'format': 'omnitrain-backup',
  'formatVersion': 1,
  'appVersion': '1.0.0',
  'exportedAtMs': 1788000000000,
  'dataVersion': 20,
  'catalogVersion': 3,
  'collections': <String, Object?>{},
  'lists': <String, Object?>{},
  'meta': <String, Object?>{},
};

bool deepEquals(Object? a, Object? b) {
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || !deepEquals(a[key], b[key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!deepEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

Matcher _throwsBackupFormat(String message) => throwsA(
  isA<BackupFormatException>().having((e) => e.message, 'message', message),
);

void main() {
  test('S-27812 stored values survive the backup text exactly', () {
    final snapshot = _fullSnapshot();
    final decoded = decodeBackup(encodeBackup(snapshot, appVersion: '1.0.0'));

    expect(
      deepEquals(decoded.collections, snapshot.collections),
      isTrue,
      reason: 'S-27812 collections must survive encode/decode exactly',
    );
    expect(
      deepEquals(decoded.lists, snapshot.lists),
      isTrue,
      reason: 'S-27812 lists must survive encode/decode exactly',
    );
    expect(
      deepEquals(decoded.meta, snapshot.meta),
      isTrue,
      reason: 'S-27812 meta must survive encode/decode exactly',
    );
    expect(decoded.dataVersion, 20, reason: 'S-27812 dataVersion is kept');
    expect(decoded.catalogVersion, 3, reason: 'S-27812 catalogVersion is kept');

    final row =
        decoded.collections['training_sessions']!['s1']!
            as Map<String, Object?>;
    expect(
      row['scheduled_date_ms'],
      isA<int>(),
      reason: 'S-27812 an int above 2^31 stays an int',
    );
    expect(
      row['scheduled_date_ms'],
      1788000000000,
      reason: 'S-27812 an int above 2^31 keeps its value',
    );
    expect(
      row['volume_kg'],
      isA<double>(),
      reason: 'S-27812 a double stays a double',
    );
    expect(row['deleted_at_ms'], isNull, reason: 'S-27812 a null stays null');
    expect(
      row['note'],
      'He said "go"\nline 💪 and \\ slash',
      reason: 'S-27812 quotes, backslash, newline and emoji survive',
    );
    expect(
      decoded.lists['exercise_muscle_groups']!['s1'],
      isA<List>(),
      reason: 'S-27812 a list-valued box stays a list',
    );
    expect(
      deepEquals(decoded.lists['exercise_muscle_groups']!['s1'], <Object?>[
        'quads',
        7,
        null,
        <Object?>['nested', true],
      ]),
      isTrue,
      reason: 'S-27812 the nested list survives',
    );
  });

  test('S-27805 text that is not JSON is refused', () {
    expect(
      () => decodeBackup('not json'),
      _throwsBackupFormat(_notBackup),
      reason: 'S-27805 unreadable text is refused as not a backup',
    );
  });

  test('S-27805 JSON that is not an object is refused', () {
    expect(
      () => decodeBackup('[]'),
      _throwsBackupFormat(_notBackup),
      reason: 'S-27805 a JSON array is refused as not a backup',
    );
  });

  test('S-27805 an object without the marker is refused', () {
    expect(
      () => decodeBackup('{}'),
      _throwsBackupFormat(_notBackup),
      reason: 'S-27805 a JSON object without the marker is refused',
    );
  });

  test('S-27805 a different format marker is refused', () {
    final map = _validBackupMap()..['format'] = 'some-other-app';
    expect(
      () => decodeBackup(jsonEncode(map)),
      _throwsBackupFormat(_notBackup),
      reason: 'S-27805 a wrong marker is refused as not a backup',
    );
  });

  test('S-27805 formatVersion 2 is refused', () {
    final map = _validBackupMap()..['formatVersion'] = 2;
    expect(
      () => decodeBackup(jsonEncode(map)),
      _throwsBackupFormat(_wrongFormat),
      reason: 'S-27805 a different format version is refused',
    );
  });

  test('S-27805 a string formatVersion is refused', () {
    final map = _validBackupMap()..['formatVersion'] = '1';
    expect(
      () => decodeBackup(jsonEncode(map)),
      _throwsBackupFormat(_wrongFormat),
      reason: 'S-27805 a non-int format version is refused',
    );
  });

  test('S-27805 collections that is not an object is refused', () {
    final map = _validBackupMap()..['collections'] = <Object?>[];
    expect(
      () => decodeBackup(jsonEncode(map)),
      _throwsBackupFormat(_damaged),
      reason: 'S-27805 a collections value that is not an object is refused',
    );
  });

  test('S-27805 a collections value that is not an object is refused', () {
    final map = _validBackupMap()
      ..['collections'] = <String, Object?>{'training_sessions': <Object?>[]};
    expect(
      () => decodeBackup(jsonEncode(map)),
      _throwsBackupFormat(_damaged),
      reason: 'S-27805 a collection that is not an object is refused',
    );
  });

  test('S-27805 a collections row that is a string is refused', () {
    final map = _validBackupMap()
      ..['collections'] = <String, Object?>{
        'sessions': <String, Object?>{'k': 'x'},
      };
    expect(
      () => decodeBackup(jsonEncode(map)),
      _throwsBackupFormat(_damaged),
      reason: 'S-27805 a row that is a string is refused as damaged',
    );
  });

  test('S-27805 a collections row that is a number is refused', () {
    final map = _validBackupMap()
      ..['collections'] = <String, Object?>{
        'sessions': <String, Object?>{'k': 7},
      };
    expect(
      () => decodeBackup(jsonEncode(map)),
      _throwsBackupFormat(_damaged),
      reason: 'S-27805 a row that is a number is refused as damaged',
    );
  });

  test(
    'S-27805 a collections row that is an object with nested values decodes',
    () {
      final map = _validBackupMap()
        ..['collections'] = <String, Object?>{
          'sessions': <String, Object?>{
            'k': <String, Object?>{
              'id': 'k',
              'nested': <String, Object?>{'a': 1},
              'tags': <Object?>['x', 2, null],
            },
          },
        };

      final snapshot = decodeBackup(jsonEncode(map));
      expect(
        deepEquals(snapshot.collections['sessions']!['k'], <String, Object?>{
          'id': 'k',
          'nested': <String, Object?>{'a': 1},
          'tags': <Object?>['x', 2, null],
        }),
        isTrue,
        reason:
            'S-27805 a row that is an object with nested values still decodes',
      );
    },
  );

  test('S-27805 a lists value holding a non-list is refused', () {
    final map = _validBackupMap()
      ..['lists'] = <String, Object?>{
        'exercise_muscle_groups': <String, Object?>{'k1': 7},
      };
    expect(
      () => decodeBackup(jsonEncode(map)),
      _throwsBackupFormat(_damaged),
      reason: 'S-27805 a list-valued box entry that is not a list is refused',
    );
  });

  test('S-27805 a meta value that is an object is refused', () {
    final map = _validBackupMap()
      ..['meta'] = <String, Object?>{
        'custom': <String, Object?>{'a': 1},
      };
    expect(
      () => decodeBackup(jsonEncode(map)),
      _throwsBackupFormat(_damaged),
      reason: 'S-27805 a meta value that is not bool/int/String is refused',
    );
  });

  test('S-27805 a missing dataVersion is refused', () {
    final map = _validBackupMap()..remove('dataVersion');
    expect(
      () => decodeBackup(jsonEncode(map)),
      _throwsBackupFormat(_damaged),
      reason: 'S-27805 a missing dataVersion is refused as damaged',
    );
  });

  test('S-27805 a valid backup text decodes', () {
    final map = _validBackupMap()
      ..['collections'] = <String, Object?>{
        'exercises': <String, Object?>{
          'e1': <String, Object?>{'id': 'e1'},
        },
      }
      ..['lists'] = <String, Object?>{
        'exercise_muscle_groups': <String, Object?>{
          'e1': <Object?>['quads'],
        },
      }
      ..['meta'] = <String, Object?>{'app_theme': 'dark'};

    final snapshot = decodeBackup(jsonEncode(map));
    expect(snapshot.dataVersion, 20);
    expect(snapshot.catalogVersion, 3);
    expect(
      deepEquals(snapshot.collections, <String, Map<String, Object?>>{
        'exercises': <String, Object?>{
          'e1': <String, Object?>{'id': 'e1'},
        },
      }),
      isTrue,
      reason: 'S-27805 a valid text decodes its collections',
    );
    expect(
      deepEquals(snapshot.lists, <String, Map<String, List<Object?>>>{
        'exercise_muscle_groups': <String, List<Object?>>{
          'e1': <Object?>['quads'],
        },
      }),
      isTrue,
      reason: 'S-27805 a valid text decodes its lists',
    );
    expect(
      deepEquals(snapshot.meta, <String, Object?>{'app_theme': 'dark'}),
      isTrue,
      reason: 'S-27805 a valid text decodes its meta',
    );
  });

  test('S-27814 an empty snapshot round-trips', () {
    final snapshot = _emptySnapshot();
    final decoded = decodeBackup(encodeBackup(snapshot, appVersion: '1.0.0'));
    expect(
      decoded.collections,
      isEmpty,
      reason: 'S-27814 empty collections stay empty',
    );
    expect(decoded.lists, isEmpty, reason: 'S-27814 empty lists stay empty');
    expect(decoded.meta, isEmpty, reason: 'S-27814 empty meta stays empty');
    expect(decoded.dataVersion, 20, reason: 'S-27814 dataVersion is kept');
    expect(decoded.catalogVersion, 3, reason: 'S-27814 catalogVersion is kept');
  });

  test(
    'S-27812 encodeBackup writes the header and decodeBackupHeader reads it',
    () {
      final now = DateTime.utc(2026, 11, 19);
      final text = encodeBackup(_fullSnapshot(), appVersion: '2.3.4', now: now);
      final root = jsonDecode(text) as Map<String, Object?>;
      expect(
        root['format'],
        'omnitrain-backup',
        reason: 'S-27812 the marker is in the header',
      );
      expect(root['formatVersion'], 1, reason: 'S-27812 formatVersion is 1');
      expect(
        root['exportedAtMs'],
        now.millisecondsSinceEpoch,
        reason: 'S-27812 exportedAtMs is the UTC milliseconds of now',
      );
      expect(root['appVersion'], '2.3.4', reason: 'S-27812 appVersion is kept');

      final header = decodeBackupHeader(text);
      expect(header.appVersion, '2.3.4');
      expect(header.exportedAtMs, now.millisecondsSinceEpoch);
      expect(header.dataVersion, 20);
      expect(header.formatVersion, 1);
    },
  );

  test(
    'S-27812 decodeBackupHeader reads a damaged body but refuses a bad marker',
    () {
      final map = _validBackupMap()..['collections'] = <Object?>[];
      final text = jsonEncode(map);
      expect(
        () => decodeBackup(text),
        _throwsBackupFormat(_damaged),
        reason: 'S-27812 the full decode still checks the body',
      );
      final header = decodeBackupHeader(text);
      expect(header.formatVersion, 1);

      expect(
        () => decodeBackupHeader('{}'),
        _throwsBackupFormat(_notBackup),
        reason: 'S-27812 the header read refuses a text without the marker',
      );
    },
  );
}
