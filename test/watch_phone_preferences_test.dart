// WatchPhonePreferences — the record, its storage and its owner class.
//
// Plan: `docs/plans/2026-11-21-283-wear-phone-settings-plan/2026-11-21-283-wear-phone-settings-plan.md`.
// Scenario mapping:
//   S-28301 a fresh owner over an empty store shows every default  → `S-28301 ...`
//   S-28302 one preferences_down copy applies and is stored        → `S-28302 ...`
//   S-28303 a newer copy replaces an older one                     → `S-28303 ...`
//   S-28304 a late older copy is dropped, not stored               → `S-28304 ...`
//   S-28305 a tie in generatedAt goes to the later-received copy   → `S-28305 ...`
//   S-28306 an absent unit key reads as the default, not the last  → `S-28306 ...`
//   S-28307 a relaunch restores the copy from storage              → `S-28307 ...`
//   S-28308 an unreadable copy is refused whole, nothing stored    → `S-28308 ...`
//   S-28308f an envelope of another type is not a preferences copy → `S-28308f ...`
//   S-28308g the schema validator's refusal stores nothing         → `S-28308g ...`
//   S-28309 the same envelope applied twice is one row             → `S-28309 ...`
//   S-28309b a replayed messageId with a newer stamp does not apply → `S-28309b ...`
//
// Plain `test()` throughout: this is the state layer, no widgets. The Mock
// store carries every scenario; S-28307 repeats its round-trip over Hive the
// way `test/watch_nutrition_quick_log_test.dart` does.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:omnitrain/core/sync_protocol/message_validator.dart';
import 'package:omnitrain/watch/session/hive_watch_session_store.dart';
import 'package:omnitrain/watch/session/in_memory_watch_session_store.dart';
import 'package:omnitrain/watch/session/watch_records.dart';
import 'package:omnitrain/watch/session/watch_session_store.dart';
import 'package:omnitrain/watch/start/watch_phone_preferences.dart';

const String _t1 = '2026-09-25T09:00:00Z';
const String _t2 = '2026-09-25T10:00:00Z';
const String _t3 = '2026-09-25T11:00:00Z';

const String _protocolRoot = 'watch/sync_protocol';

/// The shared schemas, keyed the way `$ref` addresses them, the way
/// `test/watch_logging_surfaces_test.dart` builds its validator.
SyncProtocolValidator _validator() {
  final root = Directory('${Directory.current.path}/$_protocolRoot/schemas');
  return SyncProtocolValidator({
    for (final file in root.listSync(recursive: true).whereType<File>())
      if (file.path.endsWith('.json'))
        file.path.substring(root.path.length + 1): jsonDecode(
          file.readAsStringSync(),
        ),
  });
}

/// A `preferences_down` envelope in the shape the valid fixtures carry
/// (`watch/sync_protocol/fixtures/valid/preferences_down.json` and
/// `preferences_down_units.json`): protocolVersion 1, a phone origin, and a
/// payload whose optional keys are present only when given.
Map<String, Object?> _envelope({
  String messageId = 'msg-prefs',
  Object? generatedAt,
  Object? effortRatingPrompt,
  Object? restPingSeconds,
  String? accentColorHex,
  String? weightUnit,
  String? distanceUnit,
}) => {
  'protocolVersion': 1,
  'messageId': messageId,
  'type': 'preferences_down',
  'origin': 'phone',
  'sentAt': '2026-09-25T09:00:00Z',
  'payload': {
    'generatedAt': ?generatedAt,
    'effortRatingPrompt': ?effortRatingPrompt,
    'restPingSeconds': ?restPingSeconds,
    'accentColorHex': ?accentColorHex,
    'weightUnit': ?weightUnit,
    'distanceUnit': ?distanceUnit,
  },
};

/// The round-trip S-28307 runs over both stores: a copy applied, a new owner
/// built over the same storage, and the getters read back.
Future<void> _restoreRoundTrip(WatchSessionStore store) async {
  final first = WatchPhonePreferences(store: store);
  expect(
    await first.applyPreferencesDown(
      _envelope(
        messageId: 'msg-units',
        generatedAt: _t1,
        effortRatingPrompt: true,
        restPingSeconds: 90,
        accentColorHex: '#336699',
        weightUnit: 'lbs',
        distanceUnit: 'miles',
      ),
    ),
    isTrue,
  );

  final fresh = WatchPhonePreferences(store: store);
  await fresh.restore();
  expect(fresh.current, isNotNull);
  expect(fresh.asksForEffortRating, isTrue);
  expect(fresh.restPingSeconds, 90);
  expect(fresh.accentColorHex, '#336699');
  expect(fresh.units.weightUnit, 'lbs');
  expect(fresh.units.distanceUnit, 'miles');
  expect(fresh.units.restPingSeconds, 90);
  expect(fresh.current!.recordId, 'prefs-msg-units');
  expect(fresh.current, isA<WatchPreferencesRecord>());
}

void main() {
  group('S-28301 a fresh owner over an empty store', () {
    test('every getter reads its default and current is null', () async {
      final prefs = WatchPhonePreferences(
        store: InMemoryWatchSessionStore(),
      );

      expect(prefs.asksForEffortRating, isFalse);
      expect(prefs.restPingSeconds, 0);
      expect(prefs.accentColorHex, isNull);
      expect(prefs.units.weightUnit, 'kg');
      expect(prefs.units.distanceUnit, 'km');
      expect(prefs.units.restPingSeconds, 0);
      expect(prefs.current, isNull);
    });
  });

  group('S-28302 one preferences_down copy applies', () {
    test('the getters show the copy and one row is stored', () async {
      final store = InMemoryWatchSessionStore();
      final prefs = WatchPhonePreferences(store: store);

      final applied = await prefs.applyPreferencesDown(
        _envelope(
          messageId: 'msg-prefs',
          generatedAt: _t1,
          effortRatingPrompt: true,
          restPingSeconds: 90,
          accentColorHex: '#336699',
          weightUnit: 'lbs',
          distanceUnit: 'miles',
        ),
      );

      expect(applied, isTrue);
      expect(prefs.asksForEffortRating, isTrue);
      expect(prefs.restPingSeconds, 90);
      expect(prefs.accentColorHex, '#336699');
      expect(prefs.units.weightUnit, 'lbs');
      expect(prefs.units.distanceUnit, 'miles');
      expect(prefs.units.restPingSeconds, 90);
      expect(prefs.current, isNotNull);
      expect(prefs.current!.generatedAt, DateTime.parse(_t1));

      final contents = await store.readAll();
      expect(contents.preferences, hasLength(1));
      expect(contents.preferences.single.weightUnit, 'lbs');
      expect(contents.preferences.single.restPingSeconds, 90);
    });
  });

  group('S-28303 a newer copy replaces an older one', () {
    test('the second copy applies and both rows are stored', () async {
      final store = InMemoryWatchSessionStore();
      final prefs = WatchPhonePreferences(store: store);

      expect(
        await prefs.applyPreferencesDown(
          _envelope(
            messageId: 'msg-1',
            generatedAt: _t1,
            effortRatingPrompt: true,
            restPingSeconds: 90,
            weightUnit: 'lbs',
          ),
        ),
        isTrue,
      );
      expect(
        await prefs.applyPreferencesDown(
          _envelope(
            messageId: 'msg-2',
            generatedAt: _t2,
            effortRatingPrompt: false,
            restPingSeconds: 0,
            weightUnit: 'kg',
          ),
        ),
        isTrue,
      );

      expect(prefs.units.weightUnit, 'kg');
      expect(prefs.restPingSeconds, 0);
      expect(prefs.asksForEffortRating, isFalse);
      expect((await store.readAll()).preferences, hasLength(2));
    });
  });

  group('S-28304 a late older copy is dropped', () {
    test('it returns false, the newer copy stands and no row is added',
        () async {
      final store = InMemoryWatchSessionStore();
      final prefs = WatchPhonePreferences(store: store);

      expect(
        await prefs.applyPreferencesDown(
          _envelope(
            messageId: 'msg-new',
            generatedAt: _t2,
            effortRatingPrompt: false,
            restPingSeconds: 0,
            weightUnit: 'kg',
          ),
        ),
        isTrue,
      );
      expect(
        await prefs.applyPreferencesDown(
          _envelope(
            messageId: 'msg-late',
            generatedAt: _t1,
            effortRatingPrompt: true,
            restPingSeconds: 90,
            weightUnit: 'lbs',
          ),
        ),
        isFalse,
      );

      expect(prefs.units.weightUnit, 'kg');
      expect(prefs.restPingSeconds, 0);
      expect((await store.readAll()).preferences, hasLength(1));
    });
  });

  group('S-28305 a tie in generatedAt', () {
    test('the later-received copy applies', () async {
      final store = InMemoryWatchSessionStore();
      final prefs = WatchPhonePreferences(store: store);

      expect(
        await prefs.applyPreferencesDown(
          _envelope(
            messageId: 'msg-a',
            generatedAt: _t1,
            effortRatingPrompt: false,
            restPingSeconds: 0,
            weightUnit: 'lbs',
          ),
        ),
        isTrue,
      );
      expect(
        await prefs.applyPreferencesDown(
          _envelope(
            messageId: 'msg-b',
            generatedAt: _t1,
            effortRatingPrompt: false,
            restPingSeconds: 0,
            weightUnit: 'kg',
          ),
        ),
        isTrue,
      );

      expect(prefs.units.weightUnit, 'kg');
    });
  });

  group('S-28306 an absent key reads as the default', () {
    test('a newer copy without unit or accent resets them', () async {
      final store = InMemoryWatchSessionStore();
      final prefs = WatchPhonePreferences(store: store);

      expect(
        await prefs.applyPreferencesDown(
          _envelope(
            messageId: 'msg-1',
            generatedAt: _t1,
            effortRatingPrompt: false,
            restPingSeconds: 0,
            accentColorHex: '#336699',
            weightUnit: 'lbs',
            distanceUnit: 'miles',
          ),
        ),
        isTrue,
      );
      expect(
        await prefs.applyPreferencesDown(
          _envelope(
            messageId: 'msg-2',
            generatedAt: _t2,
            effortRatingPrompt: false,
            restPingSeconds: 0,
          ),
        ),
        isTrue,
      );

      expect(prefs.units.weightUnit, 'kg');
      expect(prefs.units.distanceUnit, 'km');
      expect(prefs.accentColorHex, isNull);
    });
  });

  group('S-28307 a relaunch restores the copy', () {
    test('Mock: a new owner over the same store reads the copy back',
        () async {
      await _restoreRoundTrip(InMemoryWatchSessionStore());
    });

    test('Hive: a new owner over the same boxes reads the copy back',
        () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'watch_phone_preferences_',
      );
      addTearDown(() async {
        await Hive.close();
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });
      Hive.init(tempDir.path);

      await _restoreRoundTrip(HiveWatchSessionStore());
    });
  });

  group('S-28308 an unreadable copy is refused whole', () {
    test('(a) a negative restPingSeconds is refused, nothing stored',
        () async {
      final store = InMemoryWatchSessionStore();
      final prefs = WatchPhonePreferences(store: store);
      expect(
        await prefs.applyPreferencesDown(
          _envelope(
            messageId: 'msg-good',
            generatedAt: _t1,
            effortRatingPrompt: true,
            restPingSeconds: 90,
            weightUnit: 'lbs',
          ),
        ),
        isTrue,
      );

      expect(
        await prefs.applyPreferencesDown(
          _envelope(
            messageId: 'msg-bad',
            generatedAt: _t2,
            effortRatingPrompt: true,
            restPingSeconds: -1,
          ),
        ),
        isFalse,
      );

      expect((await store.readAll()).preferences, hasLength(1));
      expect(prefs.restPingSeconds, 90);
      expect(prefs.units.weightUnit, 'lbs');
    });

    test('(b) a fractional restPingSeconds is refused, nothing stored',
        () async {
      final store = InMemoryWatchSessionStore();
      final prefs = WatchPhonePreferences(store: store);
      expect(
        await prefs.applyPreferencesDown(
          _envelope(
            messageId: 'msg-good',
            generatedAt: _t1,
            effortRatingPrompt: true,
            restPingSeconds: 90,
            weightUnit: 'lbs',
          ),
        ),
        isTrue,
      );

      expect(
        await prefs.applyPreferencesDown(
          _envelope(
            messageId: 'msg-bad',
            generatedAt: _t2,
            effortRatingPrompt: true,
            restPingSeconds: 90.5,
          ),
        ),
        isFalse,
      );

      expect((await store.readAll()).preferences, hasLength(1));
      expect(prefs.restPingSeconds, 90);
      expect(prefs.units.weightUnit, 'lbs');
    });

    test('(c) a string restPingSeconds is refused, nothing stored', () async {
      final store = InMemoryWatchSessionStore();
      final prefs = WatchPhonePreferences(store: store);
      expect(
        await prefs.applyPreferencesDown(
          _envelope(
            messageId: 'msg-good',
            generatedAt: _t1,
            effortRatingPrompt: true,
            restPingSeconds: 90,
            weightUnit: 'lbs',
          ),
        ),
        isTrue,
      );

      expect(
        await prefs.applyPreferencesDown(
          _envelope(
            messageId: 'msg-bad',
            generatedAt: _t2,
            effortRatingPrompt: true,
            restPingSeconds: '90',
          ),
        ),
        isFalse,
      );

      expect((await store.readAll()).preferences, hasLength(1));
      expect(prefs.restPingSeconds, 90);
      expect(prefs.units.weightUnit, 'lbs');
    });

    test('(d) a non-bool effortRatingPrompt is refused, nothing stored',
        () async {
      final store = InMemoryWatchSessionStore();
      final prefs = WatchPhonePreferences(store: store);
      expect(
        await prefs.applyPreferencesDown(
          _envelope(
            messageId: 'msg-good',
            generatedAt: _t1,
            effortRatingPrompt: true,
            restPingSeconds: 90,
            weightUnit: 'lbs',
          ),
        ),
        isTrue,
      );

      expect(
        await prefs.applyPreferencesDown(
          _envelope(
            messageId: 'msg-bad',
            generatedAt: _t2,
            effortRatingPrompt: 'yes',
            restPingSeconds: 90,
          ),
        ),
        isFalse,
      );

      expect((await store.readAll()).preferences, hasLength(1));
      expect(prefs.asksForEffortRating, isTrue);
      expect(prefs.units.weightUnit, 'lbs');
    });

    test('(e) a bad generatedAt is refused, nothing stored', () async {
      final store = InMemoryWatchSessionStore();
      final prefs = WatchPhonePreferences(store: store);
      expect(
        await prefs.applyPreferencesDown(
          _envelope(
            messageId: 'msg-good',
            generatedAt: _t1,
            effortRatingPrompt: true,
            restPingSeconds: 90,
            weightUnit: 'lbs',
          ),
        ),
        isTrue,
      );

      expect(
        await prefs.applyPreferencesDown(
          _envelope(
            messageId: 'msg-bad',
            generatedAt: 'not a time',
            effortRatingPrompt: true,
            restPingSeconds: 90,
          ),
        ),
        isFalse,
      );

      expect((await store.readAll()).preferences, hasLength(1));
      expect(
        prefs.current!.generatedAt,
        DateTime.parse(_t1),
        reason: 'the good copy still applies',
      );
      expect(prefs.units.weightUnit, 'lbs');
    });

    test('(f) an envelope of another type is not a preferences copy',
        () async {
      final store = InMemoryWatchSessionStore();
      final prefs = WatchPhonePreferences(store: store);
      final envelope = _envelope(
        messageId: 'msg-foods',
        generatedAt: _t1,
        effortRatingPrompt: true,
        restPingSeconds: 90,
        accentColorHex: '#336699',
        weightUnit: 'lbs',
        distanceUnit: 'miles',
      );

      expect(
        await prefs.applyPreferencesDown({
          ...envelope,
          'type': 'foods_down',
        }),
        isFalse,
      );

      expect(prefs.current, isNull);
      expect(prefs.asksForEffortRating, isFalse);
      expect(prefs.restPingSeconds, 0);
      expect(prefs.accentColorHex, isNull);
      expect(prefs.units.weightUnit, 'kg');
      expect(prefs.units.distanceUnit, 'km');
      expect((await store.readAll()).preferences, isEmpty);
    });

    test('(g) the schema validator\'s refusal stores nothing', () async {
      final store = InMemoryWatchSessionStore();
      final prefs = WatchPhonePreferences(
        store: store,
        validator: _validator(),
      );

      expect(
        await prefs.applyPreferencesDown(
          _envelope(
            messageId: 'msg-good',
            generatedAt: _t1,
            effortRatingPrompt: true,
            restPingSeconds: 90,
            weightUnit: 'lbs',
          ),
        ),
        isTrue,
      );

      expect(
        await prefs.applyPreferencesDown({
          ..._envelope(
            messageId: 'msg-watch',
            generatedAt: _t2,
            effortRatingPrompt: false,
            restPingSeconds: 0,
            weightUnit: 'kg',
          ),
          'origin': 'watch',
        }),
        isFalse,
      );

      expect((await store.readAll()).preferences, hasLength(1));
      expect(prefs.asksForEffortRating, isTrue);
      expect(prefs.restPingSeconds, 90);
      expect(prefs.units.weightUnit, 'lbs');
    });
  });

  group('S-28309 the same envelope applied twice', () {
    test('is one row, the getters unchanged, and the replay returns true',
        () async {
      final store = InMemoryWatchSessionStore();
      final prefs = WatchPhonePreferences(store: store);
      final envelope = _envelope(
        messageId: 'msg-same',
        generatedAt: _t1,
        effortRatingPrompt: true,
        restPingSeconds: 90,
        weightUnit: 'lbs',
      );

      expect(await prefs.applyPreferencesDown(envelope), isTrue);
      final replayed = await prefs.applyPreferencesDown(envelope);

      expect(replayed, isTrue);
      expect((await store.readAll()).preferences, hasLength(1));
      expect(prefs.restPingSeconds, 90);
      expect(prefs.units.weightUnit, 'lbs');
    });

    test('(b) a replayed messageId with a newer stamp does not apply',
        () async {
      final store = InMemoryWatchSessionStore();
      final prefs = WatchPhonePreferences(store: store);

      expect(
        await prefs.applyPreferencesDown(
          _envelope(
            messageId: 'msg-1',
            generatedAt: _t1,
            effortRatingPrompt: true,
            restPingSeconds: 90,
            weightUnit: 'lbs',
          ),
        ),
        isTrue,
      );
      expect(
        await prefs.applyPreferencesDown(
          _envelope(
            messageId: 'msg-2',
            generatedAt: _t2,
            effortRatingPrompt: false,
            restPingSeconds: 0,
            weightUnit: 'kg',
          ),
        ),
        isTrue,
      );

      expect(
        await prefs.applyPreferencesDown(
          _envelope(
            messageId: 'msg-1',
            generatedAt: _t3,
            effortRatingPrompt: true,
            restPingSeconds: 90,
            weightUnit: 'lbs',
          ),
        ),
        isFalse,
      );

      expect(prefs.units.weightUnit, 'kg');
      expect(prefs.restPingSeconds, 0);
      expect(prefs.asksForEffortRating, isFalse);
      expect((await store.readAll()).preferences, hasLength(2));
    });
  });
}
