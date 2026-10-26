// The phone half of the accent contract: the accents both stacks agree on, and
// the one the phone sends with its preferences.
//
// Plan: `docs/plans/2026-10-11-23d-watch-accent-color-plan/2026-10-11-23d-watch-accent-color-plan.md`
// (D-3702, D-3705). Scenario mapping:
//   S-3722 the shared table equals the phone's own themes  → `S-3722 ...`
//   S-3723 the phone sends the accent of the theme it holds → `S-3723 ...`
//
// S-3720 (the built message carries the table's hex and conforms) and S-3721
// (a theme change is a different message id) live in
// `test/watch_reference_sync_test.dart`, beside the `S-253` group that owns the
// message they build.
//
// The table is the single source of the six accents, so this file walks it
// against `OmniTheme` instead of restating the hexes: a theme color that moves
// fails here until the row moves with it.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/omni_theme.dart';
import 'package:omnitrain/core/platform/watch_delivery.dart';
import 'package:omnitrain/core/platform/watch_transport.dart';
import 'package:omnitrain/core/utils/watch_reference_sync.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/state/food_library_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/watch/live_session_mirror_state.dart';
import 'package:omnitrain/state/watch/watch_sync_request_handler.dart';
import 'package:omnitrain/state/watch/watch_sync_wiring.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/sync_protocol_harness.dart';

/// `watch/contract/watch_accent_contract.json`, parsed.
Map<String, Object?> _contract() => asObject(
  jsonDecode(
    File(
      '${Directory.current.path}/watch/contract/'
      'watch_accent_contract.json',
    ).readAsStringSync(),
  ),
);

/// The table's rows, in file order.
List<Map<String, Object?>> _rows() => objectsOf(_contract()['themes']);

/// The theme a row names.
AppTheme _theme(Map<String, Object?> row) =>
    AppTheme.values.byName(row['theme']! as String);

/// The accent the phone colors that theme with.
Color _accent(AppTheme theme) => OmniTheme.colorsForTheme(theme).primary;

final DateTime _now = DateTime.utc(2026, 10, 11, 12);

/// A transport that keeps what it was handed, so the phone's answer can be read.
class _RecordingTransport implements WatchMirrorTransport {
  final List<Map<String, Object?>> sent = [];

  @override
  Future<WatchDelivery> send(Map<String, Object?> envelope) async {
    sent.add(envelope);
    return WatchDelivery.delivered;
  }

  @override
  Future<void> requestSnapshot() async {}
}

void main() {
  group('S-3722 the shared table equals the phone\'s own themes', () {
    test('S-3722 the rows are the themes, in the phone\'s order, under the '
        'phone\'s own names', () {
      expect(
        [for (final row in _rows()) row['theme']],
        AppTheme.values.map((theme) => theme.name),
        reason:
            'S-3722 the table is read by the wrist and written against the '
            'phone, so a theme the phone adds or renames fails here',
      );
    });

    test('S-3722 every row carries the color the phone paints that theme '
        'with', () {
      for (final row in _rows()) {
        final theme = _theme(row);

        expect(
          row['hex'],
          WatchReferenceSync.accentHexOf(_accent(theme)),
          reason:
              'S-3722 ${theme.name} reaches the wrist as #RRGGBB upper-case, '
              'and the table must move with the theme it names',
        );
      }
    });

    test('S-3722 every accent clears the floor, and each row names the label '
        'the contrast picks', () {
      final floor = (_contract()['minContrastAgainstBlack']! as num).toDouble();

      for (final row in _rows()) {
        final theme = _theme(row);
        final accent = _accent(theme);
        final againstBlack = OmniTheme.contrastRatio(accent, Colors.black);
        final againstWhite = OmniTheme.contrastRatio(accent, Colors.white);

        expect(
          againstBlack,
          greaterThanOrEqualTo(floor),
          reason:
              'S-3722 an accent below the floor is one the wrist refuses to '
              'wear, so the table cannot list it (${theme.name})',
        );
        expect(
          againstBlack >= againstWhite,
          row['labelIsDark'],
          reason:
              'S-3722 ${theme.name} takes dark labels exactly when black text '
              'reads better on it than white',
        );
      }
    });
  });

  group('S-3723 the phone sends the accent of the theme it holds', () {
    test('S-3723 a sync after the theme changes carries the new accent, not '
        'the one before it', () async {
      final repository = MockWorkoutRepository();
      await repository.initialize();
      final settings = SettingsState(repository, fakePreferencesService());
      final transport = _RecordingTransport();
      final handler = WatchSyncRequestHandler(
        mirror: LiveSessionMirrorState(
          transport: transport,
          snapshot: watchSessionPlaceholder,
        ),
        transport: transport,
        repository: repository,
        settings: settings,
        foodLibrary: FoodLibraryState(repository),
        clock: () => _now,
      );

      await handler.handle(WatchTransportRequest.routines);
      final first = transport.sent.firstWhere(
        (frame) => frame['type'] == 'preferences_down',
      );
      expect(
        asObject(first['payload'])['accentColorHex'],
        WatchReferenceSync.accentHexOf(_accent(settings.appTheme)),
        reason:
            'S-3723 the accent the wrist wears is the one the phone is '
            'wearing when the wrist asks',
      );

      await settings.setAppTheme(AppTheme.crimsonDojo);
      transport.sent.clear();
      await handler.handle(WatchTransportRequest.routines);

      final second = transport.sent.firstWhere(
        (frame) => frame['type'] == 'preferences_down',
      );
      expect(
        asObject(second['payload'])['accentColorHex'],
        WatchReferenceSync.accentHexOf(_accent(AppTheme.crimsonDojo)),
        reason:
            'S-3723 a theme changed on the phone reaches the wrist at its '
            'next sync, like every other setting',
      );
      expect(
        second['messageId'],
        isNot(first['messageId']),
        reason:
            'S-3723 the two accents are two messages rather than one dropped '
            'as a redelivery',
      );
    });
  });
}
