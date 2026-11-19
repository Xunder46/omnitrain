import 'package:hive_flutter/hive_flutter.dart';

import '../../core/utils/date_utils.dart';
import '../models/models.dart';

/// ONE-OFF (plan 264) — retire after launch.
///
/// Plan 235 changed the stored day key of food, water and daily targets from
/// the local midnight instant to the calendar date's UTC midnight
/// ([OmniDateUtils.dayKeyMs]) and added no migration. Daily targets and water
/// totals saved by an earlier build sit under the old key, which no read looks
/// up any more, so they show as never set. Logged foods carry the day only
/// inside the row, and an old row still reads as the right day on a phone west
/// of UTC, so they were hidden only east of it.
///
/// This step moves every entry stored under the old key to the new one:
///
/// - Daily targets (`nutrition_targets_by_date`): the entry is re-keyed and its
///   `date_ms` field rewritten. If a new-style entry already exists for that
///   date it wins and the old one is dropped.
/// - Water (`water_log`): the entry is re-keyed, its `id` and `date_ms`
///   rewritten. If a new-style total already exists for that date the two
///   volumes are added: they were logged on different builds, on that date.
/// - Logged foods (`consumed_foods`): each row's `date_ms` is rewritten to the
///   new key; the row id is unchanged.
///
/// A stored day is old-style when it is not a whole number of days since the
/// epoch (a UTC midnight always is). The date is read from the key as the local
/// midnight it was, in this phone's zone; when the zone has changed since it
/// was saved, the key is rounded to the nearest UTC midnight instead, which is
/// right for any zone between UTC-11 and UTC+11. After one run nothing matches,
/// so a second run writes nothing. A fresh install has nothing to move.
///
/// Runs as data-migration step 20 (`repairDayKeys`).
///
/// Retirement procedure: replace the step's `run` body with a no-op keeping its
/// version and name, delete this file and its test, and update
/// `docs/db_integration.md` and `docs/constants_reference.md`; never renumber
/// or remove a version.
class DayKeyRepair {
  DayKeyRepair._();

  static const int _dayMs = 86400000;

  /// The new-style key for a stored day [stored], or null when it already is
  /// one (a UTC midnight).
  static int? newKeyFor(int stored) {
    if (stored % _dayMs == 0) return null;
    final local = DateTime.fromMillisecondsSinceEpoch(stored);
    if (local.hour == 0 &&
        local.minute == 0 &&
        local.second == 0 &&
        local.millisecond == 0) {
      return OmniDateUtils.dayKeyMs(local);
    }
    return ((stored + _dayMs ~/ 2) ~/ _dayMs) * _dayMs;
  }

  static Future<void> run({
    required Box<Map> targets,
    required Box<Map> water,
    required Box<Map> foods,
  }) async {
    await _repairTargets(targets);
    await _repairWater(water);
    await _repairFoods(foods);
  }

  static Future<void> _repairTargets(Box<Map> box) async {
    for (final key in box.keys.toList()) {
      final stored = int.tryParse(key.toString());
      if (stored == null) continue;
      final newKey = newKeyFor(stored);
      if (newKey == null) continue;
      final raw = box.get(key);
      if (raw != null && !box.containsKey(newKey.toString())) {
        final map = Map<String, dynamic>.from(raw);
        if (map['date_ms'] != null) map['date_ms'] = newKey;
        await box.put(newKey.toString(), map);
      }
      await box.delete(key);
    }
  }

  static Future<void> _repairWater(Box<Map> box) async {
    for (final key in box.keys.toList()) {
      final stored = int.tryParse(key.toString());
      if (stored == null) continue;
      final newKey = newKeyFor(stored);
      if (newKey == null) continue;
      final raw = box.get(key);
      if (raw != null) {
        final old = Map<String, dynamic>.from(raw);
        final existing = box.get(newKey.toString());
        final merged = existing == null
            ? (old
                ..['id'] = WaterLogEntry.idForDate(newKey)
                ..['date_ms'] = newKey)
            : (Map<String, dynamic>.from(existing)
                ..['volume_ml'] =
                    ((existing['volume_ml'] as int?) ?? 0) +
                    ((old['volume_ml'] as int?) ?? 0));
        await box.put(newKey.toString(), merged);
      }
      await box.delete(key);
    }
  }

  static Future<void> _repairFoods(Box<Map> box) async {
    for (final key in box.keys.toList()) {
      final raw = box.get(key);
      if (raw == null) continue;
      final stored = raw['date_ms'];
      if (stored is! int) continue;
      final newKey = newKeyFor(stored);
      if (newKey == null) continue;
      final map = Map<String, dynamic>.from(raw)..['date_ms'] = newKey;
      await box.put(key, map);
    }
  }
}
