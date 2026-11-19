// filepath: test/health_active_energy_read_test.dart
//
// Plan 208 Phase 2a: the daily active-energy read from the platform health
// store (Apple Health on iOS, Health Connect on Android), the switch's
// state in `SettingsState`, and the platform permission wiring.
//
//   * S-20820 — pure bucketing of samples into local days.
//   * S-20821 — a DST day's bounds are 23 h or 25 h, not a fixed 24 h.
//   * S-20823 — the `Read active energy` switch lifecycle (Mock and Hive).
//   * S-20824 — the read gate: only when the switch is on and a source exists.
//   * S-20826 — the iOS Info.plist permission sentence (D-10).
//   * S-20827 — the per-day gateway read on both platforms via the `dayQuery`
//     seam, including a day whose query throws and a store that is missing.
//   * S-20828 — web and desktop are inert.
//   * S-20846 — the Android manifest carries the active-calories permission.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/health_constants.dart';
import 'package:omnitrain/core/services/health_platform_gateway_io.dart';
import 'package:omnitrain/core/services/health_platform_service.dart';
import 'package:omnitrain/state/settings/settings_state.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/repository_harness.dart';

/// The 7 local midnights 2026-11-02 .. 2026-11-08 (d7..d1 of the window).
final List<DateTime> windowDayStarts = [
  for (var d = 2; d <= 8; d++) DateTime(2026, 11, d),
];

DateTime _midnight(int day) => DateTime(2026, 11, day);

/// Test double for [HealthActiveEnergySource] used by the SettingsState
/// scenarios: counts permission asks and reads, answers from [granted] and
/// [onRead].
class _FakeActiveEnergySource implements HealthActiveEnergySource {
  _FakeActiveEnergySource({this.granted = true, this.onRead});

  final bool granted;
  int permissionRequests = 0;
  int readCalls = 0;
  final Map<int, double> Function(List<DateTime> dayStarts)? onRead;

  @override
  Future<bool> requestActiveEnergyReadPermission() async {
    permissionRequests++;
    return granted;
  }

  @override
  Future<Map<int, double>> readDailyActiveEnergy(List<DateTime> dayStarts) =>
      Future(() {
        readCalls++;
        return onRead?.call(dayStarts) ?? const {};
      });
}

/// Local midnight of the day after the first DST change in 2026, or null when
/// the zone has none — the same loop as
/// `test/stats_dst_day_arithmetic_test.dart`.
DateTime? _dayAfterFirstDstChange() {
  for (
    var d = DateTime(2026, 1, 1);
    d.year == 2026;
    d = DateTime(d.year, d.month, d.day + 1)
  ) {
    final next = DateTime(d.year, d.month, d.day + 1);
    if (next.difference(d) != const Duration(hours: 24)) return next;
  }
  return null;
}

void main() {
  // ── S-20820 ────────────────────────────────────────────────────────────────
  test('S-20820 — activeEnergyTotalsByDay sums per local day and skips '
      'non-numeric points', () {
    final points = <ActiveEnergyPoint>[
      // 11-08: a single sample of an unusual value.
      (dateFrom: _midnight(8), kcal: 512.4),
      // 11-07: two samples in one day, summed.
      (dateFrom: DateTime(2026, 11, 7, 9), kcal: 300),
      (dateFrom: DateTime(2026, 11, 7, 18), kcal: 200),
      // 11-06: a numeric 0 day — the day exists with sum 0.0.
      (dateFrom: DateTime(2026, 11, 6, 10), kcal: 0),
      // 11-05: a non-numeric sample — never creates a day.
      (dateFrom: DateTime(2026, 11, 5, 10), kcal: null),
      // 11-09 00:00 is outside every window (next day).
      (dateFrom: DateTime(2026, 11, 9, 0, 0), kcal: 999),
      // 11-01 23:59 is before the window.
      (dateFrom: DateTime(2026, 11, 1, 23, 59), kcal: 999),
    ];

    final totals = activeEnergyTotalsByDay(
      dayStarts: windowDayStarts,
      points: points,
    );

    expect(totals, {
      _midnight(8).millisecondsSinceEpoch: 512.4,
      _midnight(7).millisecondsSinceEpoch: 500.0,
      _midnight(6).millisecondsSinceEpoch: 0.0,
    });
    // No keys for the non-numeric day or the empty days.
    for (final day in [2, 3, 4, 5]) {
      expect(
        totals.containsKey(_midnight(day).millisecondsSinceEpoch),
        isFalse,
        reason: 'no key for 2026-11-$day',
      );
    }
  });

  // ── S-20821 ────────────────────────────────────────────────────────────────
  test('S-20821 — activeEnergyDayBounds spans a DST day to the next local '
      'midnight, an ordinary day 24 h', () {
    final after = _dayAfterFirstDstChange();
    final dstDay = DateTime(after!.year, after.month, after.day - 1);
    final bounds = activeEnergyDayBounds(dstDay);

    expect(bounds.end, after);
    expect(bounds.end.hour, 0);
    expect(
      bounds.seconds,
      anyOf(23 * 3600, 25 * 3600),
      reason: 'a DST day is 23 h or 25 h long',
    );

    final ordinary = activeEnergyDayBounds(DateTime(2026, 11, 10));
    expect(ordinary.end, DateTime(2026, 11, 11));
    expect(ordinary.seconds, 24 * 3600);
  }, skip: _dayAfterFirstDstChange() == null ? 'time zone without DST' : null);

  // ── S-20823 / S-20824: SettingsState scenarios on Mock and Hive ───────────
  for (final factory in harnessFactories) {
    final harness = factory();

    test('S-20823 — ${harness.name}: the active-energy switch lifecycle — '
        'asks once, persists, disables without asking, refusal is denied',
        () async {
      final repo = await harness.open();
      addTearDown(harness.close);
      final bodyWeightPrefBefore =
          await repo.getPreferenceString(HealthPrefs.readBodyWeightKey);

      final granting = _FakeActiveEnergySource(granted: true);
      final settings = SettingsState(
        repo,
        FakePreferencesService(),
        activeEnergySource: granting,
      );
      await settings.initialize();
      expect(settings.healthReadActiveEnergy, HealthToggleState.off);
      expect(settings.healthReadBodyWeight, HealthToggleState.off);

      // Enable: exactly one permission ask, persisted as `on`.
      await settings.setHealthReadActiveEnergyEnabled(true);
      expect(granting.permissionRequests, 1);
      expect(settings.healthReadActiveEnergy, HealthToggleState.on);
      expect(
        await repo.getPreferenceString(HealthPrefs.readActiveEnergyKey),
        'on',
      );

      // A fresh SettingsState over the same store reads the persisted state.
      final restarted = await harness.restart();
      final reloaded = SettingsState(
        restarted,
        FakePreferencesService(),
        activeEnergySource: _FakeActiveEnergySource(granted: true),
      );
      await reloaded.initialize();
      expect(reloaded.healthReadActiveEnergy, HealthToggleState.on);

      // Disable: no further permission ask.
      await reloaded.setHealthReadActiveEnergyEnabled(false);
      expect(granting.permissionRequests, 1);
      expect(reloaded.healthReadActiveEnergy, HealthToggleState.off);
      expect(
        await restarted.getPreferenceString(HealthPrefs.readActiveEnergyKey),
        'off',
      );

      // A refusing source: `denied`, persisted.
      final refusing = _FakeActiveEnergySource(granted: false);
      final refused = SettingsState(
        restarted,
        FakePreferencesService(),
        activeEnergySource: refusing,
      );
      await refused.initialize();
      await refused.setHealthReadActiveEnergyEnabled(true);
      expect(refusing.permissionRequests, 1);
      expect(refused.healthReadActiveEnergy, HealthToggleState.permissionDenied);
      expect(
        await restarted.getPreferenceString(HealthPrefs.readActiveEnergyKey),
        'denied',
      );

      // The body-weight switch is untouched throughout.
      expect(refused.healthReadBodyWeight, HealthToggleState.off);
      expect(
        await restarted.getPreferenceString(HealthPrefs.readBodyWeightKey),
        bodyWeightPrefBefore,
      );
    });

    test('S-20824 — ${harness.name}: a refused switch (denied) reads nothing '
        'and never calls the source', () async {
      final repo = await harness.open();
      addTearDown(harness.close);
      final d1 = _midnight(4);
      final refusing = _FakeActiveEnergySource(
        granted: false,
        onRead: (_) => {d1.millisecondsSinceEpoch: 730.0},
      );
      final settings = SettingsState(
        repo,
        FakePreferencesService(),
        activeEnergySource: refusing,
      );
      await settings.initialize();

      await settings.setHealthReadActiveEnergyEnabled(true);
      expect(settings.healthReadActiveEnergy, HealthToggleState.permissionDenied);
      expect(await settings.readDailyActiveEnergy([d1]), isEmpty);
      expect(refusing.readCalls, 0);
    });

    test('S-20824 — ${harness.name}: readDailyActiveEnergy only when the '
        'switch is on and a source exists', () async {
      final repo = await harness.open();
      addTearDown(harness.close);
      final d1 = _midnight(4);
      final source = _FakeActiveEnergySource(
        onRead: (_) => {d1.millisecondsSinceEpoch: 500.0},
      );
      final settings = SettingsState(
        repo,
        FakePreferencesService(),
        activeEnergySource: source,
      );
      await settings.initialize();

      // Switch off: no read at all.
      final offRead = await settings.readDailyActiveEnergy([d1]);
      expect(offRead, isEmpty);
      expect(source.readCalls, 0);

      // Switch on: the source is called exactly once.
      await settings.setHealthReadActiveEnergyEnabled(true);
      expect(await settings.readDailyActiveEnergy([d1]), {
        d1.millisecondsSinceEpoch: 500.0,
      });
      expect(source.readCalls, 1);

      // Switch on but no source: `{}`. The persisted `on` is carried over;
      // the fresh state is built without a source (tests, no gateway).
      final sourceless = SettingsState(
        repo,
        FakePreferencesService(),
        activeEnergySource: null,
      );
      await sourceless.initialize();
      expect(sourceless.healthReadActiveEnergy, HealthToggleState.on);
      expect(await sourceless.readDailyActiveEnergy([d1]), isEmpty);
    });
  }

  // ── S-20826 ────────────────────────────────────────────────────────────────
  test('S-20826 — the iOS Info.plist permission sentence covers active '
      'energy', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    final match = RegExp(
      r'<key>NSHealthShareUsageDescription</key>\s*<string>([^<]*)</string>',
    ).firstMatch(plist);
    expect(match, isNotNull);
    final sentence = match!.group(1)!;
    expect(
      sentence,
      startsWith('OmniTrain reads your body weight from Apple Health'),
    );
    expect(
      sentence,
      endsWith(
        'It also reads your active energy so the Stats screen can show '
        'the calories you burn per day.',
      ),
    );
  });

  // ── S-20827 ────────────────────────────────────────────────────────────────
  test('S-20827 — the per-day read calls the day query once per local day, '
      'on iOS and Android, and never throws', () async {
    final iosCalls = <(DateTime, DateTime, int)>[];
    final iosService = HealthPluginPlatformService(
      isIOS: true,
      dayQuery: (start, end, seconds) async {
        iosCalls.add((start, end, seconds));
        if (start == _midnight(8)) {
          return [(dateFrom: start, kcal: 512.4)];
        }
        if (start == _midnight(7)) {
          return [(dateFrom: DateTime(2026, 11, 7, 9), kcal: 500.0)];
        }
        return const [];
      },
    );

    final androidCalls = <(DateTime, DateTime, int)>[];
    final androidService = HealthPluginPlatformService(
      isIOS: false,
      dayQuery: (start, end, seconds) async {
        androidCalls.add((start, end, seconds));
        if (start == _midnight(5)) throw Exception('Health Connect failed');
        final kcal = start == _midnight(8)
            ? 512.4
            : start == _midnight(7)
            ? 500.0
            : 0.0;
        return [(dateFrom: start, kcal: kcal)];
      },
    );

    final iosRead = await iosService.readDailyActiveEnergy(windowDayStarts);
    final androidRead = await androidService.readDailyActiveEnergy(
      windowDayStarts,
    );

    // Each day is queried with (midnight, next midnight, length in seconds).
    for (var d = 2; d <= 8; d++) {
      final expected = (
        _midnight(d),
        DateTime(2026, 11, d + 1),
        DateTime(2026, 11, d + 1).difference(_midnight(d)).inSeconds,
      );
      expect(iosCalls, contains(expected), reason: 'iOS day 2026-11-$d');
      expect(androidCalls, contains(expected), reason: 'Android day 2026-11-$d');
    }
    expect(iosCalls, hasLength(7));
    expect(androidCalls, hasLength(7));

    expect(iosRead, {
      _midnight(8).millisecondsSinceEpoch: 512.4,
      _midnight(7).millisecondsSinceEpoch: 500.0,
    });

    expect(androidRead[_midnight(8).millisecondsSinceEpoch], 512.4);
    expect(androidRead[_midnight(7).millisecondsSinceEpoch], 500.0);
    // Health Connect answers 0 for a day without records; the day is carried.
    for (final d in [2, 3, 4, 6]) {
      expect(
        androidRead[_midnight(d).millisecondsSinceEpoch],
        0.0,
        reason: 'Android 0 day 2026-11-$d carried as 0.0',
      );
    }
    // The failing day is absent; the other days stand.
    expect(
      androidRead.containsKey(_midnight(5).millisecondsSinceEpoch),
      isFalse,
    );

    // A store that is missing entirely: every day fails, the read is empty.
    final missing = HealthPluginPlatformService(
      isIOS: false,
      dayQuery: (start, end, seconds) async {
        throw Exception('Health Connect not installed');
      },
    );
    expect(await missing.readDailyActiveEnergy(windowDayStarts), isEmpty);
  });

  // ── S-20828 ────────────────────────────────────────────────────────────────
  test('S-20828 — web and desktop are inert: the unavailable gateway reads '
      'nothing and asks nothing', () async {
    const unavailable = UnavailableHealthPlatformService();
    expect(
      await unavailable.requestActiveEnergyReadPermission(),
      isFalse,
    );
    expect(await unavailable.readDailyActiveEnergy(windowDayStarts), isEmpty);

    // On the macOS test host the factory picks the unavailable gateway.
    final created = createHealthPlatformService();
    expect(created, isA<UnavailableHealthPlatformService>());
    final asSource = created as HealthActiveEnergySource;
    expect(await asSource.readDailyActiveEnergy(windowDayStarts), isEmpty);
  });

  // ── S-20846 ────────────────────────────────────────────────────────────────
  test('S-20846 — the Android manifest declares the active-calories read '
      'permission beside the Health permissions', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(
      RegExp(
        'android.permission.health.READ_ACTIVE_CALORIES_BURNED',
      ).allMatches(manifest),
      hasLength(1),
    );
    expect(manifest, contains('android.permission.health.READ_WEIGHT'));
    expect(manifest, contains('android.permission.health.WRITE_EXERCISE'));
  });
}
