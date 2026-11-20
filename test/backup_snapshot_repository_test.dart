// Plan 278a — the backup snapshot: what `exportSnapshot` carries, and what
// `importSnapshot` replaces. Both stores run every scenario, and S-27815
// compares one against the other so the two implementations cannot drift.
//
// Plan: `docs/plans/2026-11-19-278a-backup-file-engine-plan/2026-11-19-278a-backup-file-engine-plan.md`
// (D-27801, D-27802, D-27803, D-27804, D-27808, D-27810, D-27811; S-27801,
// S-27802, S-27803, S-27813, S-27814, S-27815, S-27816, S-27818).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/catalog_version.dart';
import 'package:omnitrain/core/constants/metric_ids.dart';
import 'package:omnitrain/data/models/backup_snapshot.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';

import 'helpers/repository_harness.dart';

/// The series rule text a repeating plan stores, exactly as
/// `RecurrenceRule.encode` writes it.
const String recurrenceRuleText =
    '{"v":1,"series":"s1","unit":"week","every":1,"weekdays":[4],'
    '"end":"count","count":2}';

/// Local midnight [daysAfter] the fixture day: a planned session's
/// `scheduledDateMs` is held as the local instant of its wall-clock day, so a
/// midnight instant is the value that survives the wall-clock key unchanged.
int fixtureDayMs([int daysAfter = 0]) =>
    DateTime(2026, 12, 3 + daysAfter).millisecondsSinceEpoch;

// ─── Canonical form ─────────────────────────────────────────────────────────

/// [value] with every map's keys sorted, so two snapshots compare by content
/// and not by the order Hive happened to hand their rows back in.
Object? _sorted(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    return <String, Object?>{for (final key in keys) key: _sorted(value[key])};
  }
  if (value is List) return <Object?>[for (final item in value) _sorted(item)];
  return value;
}

String canonOf(Object? value) => jsonEncode(_sorted(value));

String canon(BackupSnapshot snapshot) => canonOf(<String, Object?>{
  'collections': snapshot.collections,
  'lists': snapshot.lists,
  'meta': snapshot.meta,
  'dataVersion': snapshot.dataVersion,
  'catalogVersion': snapshot.catalogVersion,
});

/// [collections] without the sessions collection, for a test that carries a
/// smaller snapshot changing only that one.
Map<String, Map<String, Object?>> otherCollections(
  Map<String, Map<String, Object?>> collections,
) => <String, Map<String, Object?>>{
  for (final entry in collections.entries)
    if (entry.key != 'sessions') entry.key: entry.value,
};

/// The collections S-27815 leaves out of its comparison: the bundled catalog
/// is never carried and has no Mock store, and the legacy by-id nutrition box
/// has no Mock store either (D-27810).
const Set<String> uncomparedCollections = {
  'nutrition_targets',
  'foods_catalog',
};

/// One collection's rows in the form S-27815 compares them. `water_log`
/// compares the volume and the applied-tap ledger only: the Mock keeps no row
/// timestamps, and a row that never took a tap carries no ledger at all
/// (D-27810). A collection the snapshot omits compares as empty.
Map<String, Object?> comparableRows(String name, Map<String, Object?>? rows) {
  final carried = rows ?? const <String, Object?>{};
  if (name != 'water_log') return carried;
  return <String, Object?>{
    for (final entry in carried.entries)
      entry.key: <String, Object?>{
        'volume_ml': (entry.value as Map)['volume_ml'],
        'applied_tap_ids': <Object?>[
          ...?((entry.value as Map)['applied_tap_ids'] as List?)
              ?.cast<Object?>(),
        ],
      },
  };
}

// ─── Fixture ────────────────────────────────────────────────────────────────

/// Every kind of user row the backup must carry, written only through the
/// interface's real writers, so the fixture is data the app itself could
/// have written.
Future<void> seedEverything(WorkoutRepository repo) async {
  // Two finished sessions, each with a segment, efforts and observations.
  await seedSession(
    repo,
    sessionId: 'session-a',
    modality: 'resistance_lifting',
    daysAgo: 1,
  );
  await seedSession(
    repo,
    sessionId: 'session-b',
    modality: 'cardio_endurance',
    daysAgo: 2,
  );
  await seedExercise(repo, id: 'ex-row', name: 'Row', capabilities: ['load']);

  await repo.createEffort(
    SegmentEffort(
      id: 'effort-a',
      segmentId: 'seg-session-a',
      orderIndex: 0,
      effortKind: 'set',
      exerciseId: 'ex-row',
      createdAtMs: fixtureStart,
      updatedAtMs: fixtureStart,
    ),
  );
  await repo.createObservation(
    repsRow('effort-a', 0, 8, atMs: fixtureRowAt(0)),
  );
  await repo.createObservation(
    weightRow('effort-a', 0, 60.0, atMs: fixtureRowAt(1)),
  );
  await repo.createEntryRest(
    EntryRest(
      id: 'rest-effort-a-0',
      effortId: 'effort-a',
      entryIndex: 0,
      restStartMs: fixtureStart,
      restEndMs: fixtureStart + 60000,
      createdAtMs: fixtureStart,
      updatedAtMs: fixtureStart,
    ),
  );

  await repo.createEffort(
    SegmentEffort(
      id: 'effort-b',
      segmentId: 'seg-session-b',
      orderIndex: 0,
      effortKind: 'timed',
      exerciseId: 'ex-row',
      createdAtMs: fixtureStart,
      updatedAtMs: fixtureStart,
    ),
  );
  await repo.createTimedInstance(
    timedInstance('effort-b', 0, durationSecs: 60, entryIndex: 0),
  );
  await repo.createObservation(
    distanceRow('effort-b', 0, 1000.0, atMs: fixtureRowAt(0)),
  );

  // A session block with an effort assigned to it.
  await repo.createSessionBlock(
    SessionBlock(
      id: 'block-a',
      sessionId: 'session-a',
      name: 'Main',
      orderIndex: 0,
      createdAtMs: fixtureStart,
      updatedAtMs: fixtureStart,
    ),
  );
  await repo.createEffort(
    SegmentEffort(
      id: 'effort-block',
      segmentId: 'seg-session-a',
      orderIndex: 1,
      effortKind: 'set',
      exerciseId: 'ex-row',
      createdAtMs: fixtureStart,
      updatedAtMs: fixtureStart,
    ),
  );
  await repo.assignEffortToBlock('effort-block', 'block-a');

  // A custom exercise with a muscle link and a note.
  await repo.createExercise(
    Exercise(
      id: 'ex-custom',
      ownerUserId: 'user-1',
      name: 'Custom Lift',
      capabilities: const ['load'],
      createdAtMs: fixtureStart,
      updatedAtMs: fixtureStart,
    ),
  );
  await repo.setExerciseMuscleLinks('ex-custom', const [
    ExerciseMuscleLink(muscleGroupId: 'muscle-chest', role: MuscleRole.primary),
  ]);
  await repo.saveExerciseNote(
    ExerciseNote(
      id: 'note-ex-custom',
      exerciseId: 'ex-custom',
      note: 'brace hard',
      createdAtMs: fixtureStart,
      updatedAtMs: fixtureStart,
    ),
  );

  // A routine: two template segments, each with an effort and a target.
  await repo.createTemplate(
    WorkoutTemplate(
      id: 'template-1',
      ownerUserId: 'user-1',
      name: 'Push',
      createdAtMs: fixtureStart,
      updatedAtMs: fixtureStart,
    ),
  );
  for (final index in const [0, 1]) {
    final segmentId = 'tseg-1-$index';
    await repo.createTemplateSegment(
      TemplateSegment(
        id: segmentId,
        templateId: 'template-1',
        orderIndex: index,
        segmentType: 'workout',
        name: 'Part $index',
        createdAtMs: fixtureStart,
        updatedAtMs: fixtureStart,
      ),
    );
    final effortId = 'teff-1-$index';
    await repo.createTemplateEffort(
      TemplateEffort(
        id: effortId,
        templateSegmentId: segmentId,
        orderIndex: 0,
        effortKind: 'set',
        exerciseId: 'ex-row',
        restSeconds: 90,
        createdAtMs: fixtureStart,
      ),
    );
    await repo.createTemplateTarget(
      TemplateTarget(
        id: 'ttarget-1-$index',
        templateEffortId: effortId,
        metricId: MetricIds.reps,
        targetInt: 8,
        createdAtMs: fixtureStart,
        updatedAtMs: fixtureStart,
      ),
    );
  }

  // A repeating planned session and a completed one pointing at its session.
  await repo.createPlannedSession(
    PlannedSession(
      id: 'plan-series',
      ownerUserId: 'user-1',
      scheduledDateMs: fixtureDayMs(),
      modality: 'resistance_lifting',
      title: 'Series',
      recurrenceRule: recurrenceRuleText,
      createdAtMs: fixtureStart,
      updatedAtMs: fixtureStart,
    ),
  );
  await repo.createPlannedSession(
    PlannedSession(
      id: 'plan-done',
      ownerUserId: 'user-1',
      scheduledDateMs: fixtureDayMs(1),
      isCompleted: true,
      linkedSessionId: 'session-a',
      createdAtMs: fixtureStart,
      updatedAtMs: fixtureStart,
    ),
  );

  await repo.createPeriod(
    TrainingPeriod(
      id: 'period-1',
      ownerUserId: 'user-1',
      name: 'Block',
      startDateMs: fixtureDayMs(),
      endDateMs: fixtureDayMs(6),
      focusModalities: const ['cardio_endurance'],
      createdAtMs: fixtureStart,
      updatedAtMs: fixtureStart,
    ),
  );

  // Profile, two measurements, and a day's nutrition target.
  await repo.saveProfile(
    UserProfile(id: 'user-1', displayName: 'Ana', createdAtMs: fixtureStart),
  );
  for (final index in const [0, 1]) {
    await repo.saveMeasurementEntry(
      BodyMeasurementEntry(
        id: 'measure-$index',
        measurementType: 'weight',
        value: 72.5 - index,
        unitId: MetricIds.unitKg,
        recordedAtMs: fixtureDayMs(index),
      ),
    );
  }
  await repo.saveNutritionTargetForDate(
    fixtureDayMs(),
    NutritionTarget(
      calories: 2100,
      protein: 150,
      carbs: 200,
      fat: 70,
      dateMs: fixtureDayMs(),
    ),
  );

  // A food group, a custom food and two consumed-food rows.
  await repo.createFoodGroup(
    FoodGroup(
      id: 'group-1',
      name: 'Proteins',
      color: '#FF0000',
      createdAtMs: fixtureStart,
      updatedAtMs: fixtureStart,
    ),
  );
  await repo.createFood(
    Food(
      id: 'food-1',
      name: 'Skyr',
      groupId: 'group-1',
      unitType: FoodUnitType.grams,
      referenceAmount: 100,
      referenceLabel: 'g',
      protein: 11,
      carbs: 4,
      fat: 0.2,
      createdAtMs: fixtureStart,
      updatedAtMs: fixtureStart,
    ),
  );
  for (final index in const [0, 1]) {
    await repo.createConsumedFood(
      ConsumedFood(
        id: 'consumed-$index',
        loggedAtMs: fixtureDayMs() + index,
        dateMs: fixtureDayMs(),
        sourceFoodId: 'food-1',
        name: 'Skyr',
        unitType: FoodUnitType.grams,
        referenceAmount: 100,
        referenceLabel: 'g',
        protein: 11,
        carbs: 4,
        fat: 0.2,
        amountConsumed: 150,
        groupIdSnapshot: 'group-1',
        groupNameSnapshot: 'Proteins',
        targetCalories: 2100,
        targetProtein: 150,
        targetCarbs: 200,
        targetFat: 70,
        createdAtMs: fixtureStart,
        updatedAtMs: fixtureStart,
      ),
    );
  }
  await repo.saveWaterVolumeForDate(fixtureDayMs(), 750);

  // Energy, a sensor summary and a staged watch row.
  await repo.putSessionEnergy(
    SessionEnergy(
      sessionId: 'session-a',
      activeKcal: 320.5,
      source: SessionEnergy.sourceMeasured,
      updatedAtMs: fixtureStart,
    ),
  );
  await seedSensorSummary(
    repo,
    sensorSummary(
      sessionId: 'session-a',
      scope: SensorSummary.scopeSession,
      targetId: 'session-a',
      windowStartMs: fixtureStart,
      windowEndMs: fixtureStart + 1000,
      avgHeartRateBpm: 120.0,
      steps: null,
    ),
  );
  await repo.stageWatchInboxEntry(
    WatchInboxEntry(
      entryId: 'inbox-1',
      watchSessionId: 'watch-1',
      kind: WatchInboxEntry.kindSessionEnd,
      origin: WatchInboxEntry.originWatch,
      payload: <String, dynamic>{'ended_at_ms': fixtureStart},
      receivedAtMs: fixtureStart,
    ),
  );

  // Preferences and one user tombstone.
  await repo.setPreferenceString('app_theme', 'x');
  await repo.setPreferenceString('preferred_weight_unit', 'lb');
  await repo.setPreferenceBool('onboarding_complete', true);
  await repo.markSeedEntryTouched('exercise', 'ex-custom');
}

void main() {
  for (final factory in harnessFactories) {
    final harness = factory();
    group('${harness.name} — backup snapshot', () {
      late WorkoutRepository repo;

      setUp(() async => repo = await harness.open());
      tearDown(() async => await harness.close());

      test(
        'S-27801 a snapshot restores into a fresh store, row for row',
        () async {
          await seedEverything(repo);
          final snap = await repo.exportSnapshot();
          await harness.close();

          final h2 = factory();
          try {
            final restored = await h2.open();
            await restored.importSnapshot(snap);

            expect(canon(await restored.exportSnapshot()), canon(snap));

            expect((await restored.getAllSessions()).length, 2);
            final series = (await restored.getPlannedSessions()).firstWhere(
              (plan) => plan.id == 'plan-series',
            );
            expect(series.scheduledDateMs, fixtureDayMs());
            expect(series.recurrenceRule, recurrenceRuleText);
            expect(
              (await restored.getExerciseNote('ex-custom'))?.note,
              'brace hard',
            );
            expect(await restored.getPreferenceString('app_theme'), 'x');
            expect(
              await restored.isSeedEntryTouched('exercise', 'ex-custom'),
              isTrue,
            );
          } finally {
            await h2.close();
          }
        },
      );

      test(
        'S-27801b the export carries rows for every box the fixture fills',
        () async {
          await seedEverything(repo);
          final snapshot = await repo.exportSnapshot();

          // `seedEverything` writes no round effort, so `round_instances` is
          // left out; `timed_instances` carries effort-b's finished instance.
          // The reference boxes outside this list are not part of the fixture.
          const filledCollections = <String>[
            'sessions',
            'segments',
            'efforts',
            'observations',
            'entry_rests',
            'session_blocks',
            'exercises',
            'exercise_notes',
            'templates',
            'template_segments',
            'template_efforts',
            'template_targets',
            'planned_sessions',
            'training_periods',
            'user_profile',
            'body_measurements',
            'nutrition_targets_by_date',
            'foods',
            'food_groups',
            'consumed_foods',
            'water_log',
            'session_energy',
            'sensor_summaries',
            'watch_inbox',
            'timed_instances',
          ];

          for (final name in filledCollections) {
            expect(
              snapshot.collections[name],
              isNotNull,
              reason: 'S-27801b the export has no collection named $name',
            );
            expect(
              snapshot.collections[name],
              isNotEmpty,
              reason: 'S-27801b the export carries no rows for $name',
            );
          }
          expect(
            snapshot.lists['exercise_muscle_groups'],
            isNotEmpty,
            reason:
                'S-27801b the export carries no exercise_muscle_groups rows',
          );
        },
      );

      test(
        'S-27801c the carried data and catalog versions are restored',
        () async {
          await seedEverything(repo);
          final snap = await repo.exportSnapshot();
          final carried = BackupSnapshot(
            collections: snap.collections,
            lists: snap.lists,
            meta: <String, Object?>{
              ...snap.meta,
              'data_version': 7,
              'catalog_version': 3,
            },
            dataVersion: 7,
            catalogVersion: 3,
          );
          await harness.close();

          final h2 = factory();
          try {
            final restored = await h2.open();
            await restored.importSnapshot(carried);

            expect(
              await restored.getDataVersion(),
              7,
              reason: 'S-27801c the carried data version is restored',
            );
            expect(
              await restored.getCatalogVersion(),
              3,
              reason: 'S-27801c the carried catalog version is restored',
            );
          } finally {
            await h2.close();
          }
        },
      );

      test(
        'S-27802 import replaces a carried collection instead of merging',
        () async {
          await seedEverything(repo);
          final snap = await repo.exportSnapshot();

          await seedSession(repo, sessionId: 'junk-session');
          await repo.createFood(
            Food(
              id: 'junk-food',
              name: 'Junk',
              unitType: FoodUnitType.grams,
              referenceAmount: 100,
              referenceLabel: 'g',
              protein: 1,
              carbs: 1,
              fat: 1,
              createdAtMs: fixtureStart,
              updatedAtMs: fixtureStart,
            ),
          );
          expect((await repo.getAllSessions()).length, 3);

          await repo.importSnapshot(snap);

          expect(canon(await repo.exportSnapshot()), canon(snap));
          expect(
            (await repo.getAllSessions()).any((s) => s.id == 'junk-session'),
            isFalse,
          );
          expect(
            (await repo.getFoods()).any((food) => food.id == 'junk-food'),
            isFalse,
          );
        },
      );

      test(
        'S-27802b an import removes preferences the backup does not carry but '
        'keeps device-only keys',
        () async {
          await seedEverything(repo);
          final snap = await repo.exportSnapshot();

          await repo.setPreferenceString('stale_pref', 'x');
          await repo.setPreferenceBool('notification_permission_asked', true);

          await repo.importSnapshot(snap);

          expect(
            await repo.getPreferenceString('stale_pref'),
            isNull,
            reason: 'S-27802b a preference the backup lacks is removed',
          );
          expect(
            await repo.getPreferenceBool('notification_permission_asked'),
            isTrue,
            reason: 'S-27802b a device-only preference survives the import',
          );
        },
      );

      test('S-27802c an import replaces list-valued collections', () async {
        await seedEverything(repo);
        final snap = await repo.exportSnapshot();

        await repo.createExercise(
          Exercise(
            id: 'junk-exercise',
            ownerUserId: 'user-1',
            name: 'Junk',
            capabilities: const ['load'],
            createdAtMs: fixtureStart,
            updatedAtMs: fixtureStart,
          ),
        );
        await repo.setExerciseMuscleLinks('junk-exercise', const [
          ExerciseMuscleLink(
            muscleGroupId: 'muscle-chest',
            role: MuscleRole.primary,
          ),
        ]);
        expect(
          (await repo.exportSnapshot()).lists['exercise_muscle_groups']!
              .containsKey('junk-exercise'),
          isTrue,
          reason: 'S-27802c the fixture link landed in the list box',
        );

        await repo.importSnapshot(snap);

        expect(
          canonOf(
            (await repo.exportSnapshot()).lists['exercise_muscle_groups'],
          ),
          canonOf(snap.lists['exercise_muscle_groups']),
          reason:
              'S-27802c the imported list box holds exactly the snapshot rows',
        );
        expect(
          (await repo.exportSnapshot()).lists['exercise_muscle_groups']!
              .containsKey('junk-exercise'),
          isFalse,
          reason: 'S-27802c the row added after the snapshot is gone',
        );
      });

      test('S-27802d an import removes a seed tombstone the backup does not '
          'carry', () async {
        await seedEverything(repo);
        final snap = await repo.exportSnapshot();

        await repo.markSeedEntryTouched(
          SeedEntryType.exercise,
          'extra-exercise',
        );

        await repo.importSnapshot(snap);

        expect(
          await repo.isSeedEntryTouched(
            SeedEntryType.exercise,
            'extra-exercise',
          ),
          isFalse,
          reason: 'S-27802d the tombstone the backup lacks is removed',
        );
        expect(
          await repo.isSeedEntryTouched(SeedEntryType.exercise, 'ex-custom'),
          isTrue,
          reason: 'S-27802d the carried tombstone survives the import',
        );
      });

      test(
        'S-27802e an import replaces every list-valued collection',
        () async {
          await seedEverything(repo);
          final snap = await repo.exportSnapshot();

          await repo.setExerciseCapabilities('junk-exercise', const ['load']);
          await repo.setMetricEffortKinds('junk-metric', const ['set']);
          final junk = await repo.exportSnapshot();
          expect(
            junk.lists['exercise_capabilities']!.containsKey('junk-exercise'),
            isTrue,
            reason: 'S-27802e the fixture capability row landed in its box',
          );
          expect(
            junk.lists['metric_effort_kinds']!.containsKey('junk-metric'),
            isTrue,
            reason: 'S-27802e the fixture effort-kind row landed in its box',
          );

          // `exercise_equipment` and `exercise_tags` carry seeded reference
          // links and have no per-link writer in the interface, so the
          // imported snapshot carries them empty: a store that fails to clear
          // still shows its seeded equipment rows afterwards.
          expect(
            snap.lists['exercise_equipment'],
            isNotEmpty,
            reason: 'S-27802e the seeded store has equipment links to clear',
          );
          final carried = BackupSnapshot(
            collections: snap.collections,
            lists: <String, Map<String, List<Object?>>>{
              ...snap.lists,
              'exercise_equipment': const <String, List<Object?>>{},
              'exercise_tags': const <String, List<Object?>>{},
            },
            meta: snap.meta,
            dataVersion: snap.dataVersion,
            catalogVersion: snap.catalogVersion,
          );

          await repo.importSnapshot(carried);

          final after = await repo.exportSnapshot();
          for (final name in const <String>[
            'exercise_equipment',
            'exercise_tags',
            'metric_effort_kinds',
            'exercise_capabilities',
          ]) {
            expect(
              canonOf(after.lists[name]),
              canonOf(carried.lists[name]),
              reason: 'S-27802e $name holds exactly the imported rows',
            );
          }
        },
      );

      test('S-27802f an import replaces round instances, timed instances and '
          'rests', () async {
        await seedEverything(repo);
        final snap = await repo.exportSnapshot();

        await repo.createEffort(
          SegmentEffort(
            id: 'junk-effort',
            segmentId: 'seg-session-a',
            orderIndex: 2,
            effortKind: 'round',
            exerciseId: 'ex-row',
            createdAtMs: fixtureStart,
            updatedAtMs: fixtureStart,
          ),
        );
        await repo.createRoundInstance(roundInstance('junk-effort', 0));
        await repo.createTimedInstance(
          timedInstance('junk-effort', 0, durationSecs: 30, entryIndex: 0),
        );
        await repo.createEntryRest(
          EntryRest(
            id: 'rest-junk-effort-0',
            effortId: 'junk-effort',
            entryIndex: 0,
            restStartMs: fixtureStart,
            restEndMs: fixtureStart + 60000,
            createdAtMs: fixtureStart,
            updatedAtMs: fixtureStart,
          ),
        );
        final junk = await repo.exportSnapshot();
        expect(
          junk.collections['round_instances']!.containsKey('ri-junk-effort-0'),
          isTrue,
          reason: 'S-27802f the fixture round instance is stored',
        );
        expect(
          junk.collections['timed_instances']!.containsKey('ti-junk-effort-0'),
          isTrue,
          reason: 'S-27802f the fixture timed instance is stored',
        );
        expect(
          junk.collections['entry_rests']!.containsKey('rest-junk-effort-0'),
          isTrue,
          reason: 'S-27802f the fixture rest is stored',
        );

        await repo.importSnapshot(snap);

        final after = await repo.exportSnapshot();
        for (final name in const <String>[
          'round_instances',
          'timed_instances',
          'entry_rests',
        ]) {
          expect(
            canonOf(after.collections[name]),
            canonOf(snap.collections[name]),
            reason: 'S-27802f $name holds exactly the snapshot rows',
          );
        }
      });

      test(
        'S-27802g an import removes water entries the backup does not carry',
        () async {
          await seedEverything(repo);
          final snap = await repo.exportSnapshot();
          final junkDay = fixtureDayMs(2);

          await repo.saveWaterVolumeForDate(junkDay, 500);
          expect(
            await repo.getWaterVolumeForDate(junkDay),
            500,
            reason: 'S-27802g the fixture water row is stored',
          );

          await repo.importSnapshot(snap);

          expect(
            await repo.getWaterVolumeForDate(junkDay),
            0,
            reason: 'S-27802g the water day the backup lacks is gone',
          );
          expect(
            await repo.getWaterVolumeForDate(fixtureDayMs()),
            750,
            reason: 'S-27802g the carried water day keeps its volume',
          );
        },
      );

      test(
        'S-27803 boxes and meta the snapshot does not carry are left alone',
        () async {
          await seedEverything(repo);
          await repo.setPreferenceBool('notification_permission_asked', true);
          final before = await repo.exportSnapshot();

          final smaller = BackupSnapshot(
            collections: <String, Map<String, Object?>>{
              'sessions': const <String, Object?>{},
            },
            lists: const <String, Map<String, List<Object?>>>{},
            meta: const <String, Object?>{},
            dataVersion: before.dataVersion,
            catalogVersion: before.catalogVersion,
          );
          await repo.importSnapshot(smaller);
          final after = await repo.exportSnapshot();

          expect(after.collections['sessions'], isEmpty);
          expect(
            canonOf(otherCollections(after.collections)),
            canonOf(otherCollections(before.collections)),
          );
          expect(canonOf(after.lists), canonOf(before.lists));
          expect(
            await repo.getPreferenceBool('notification_permission_asked'),
            isTrue,
          );

          final unknown = BackupSnapshot(
            collections: <String, Map<String, Object?>>{
              'no_such_box': const <String, Object?>{},
            },
            lists: const <String, Map<String, List<Object?>>>{},
            meta: const <String, Object?>{},
            dataVersion: before.dataVersion,
            catalogVersion: before.catalogVersion,
          );
          final beforeUnknown = await repo.exportSnapshot();
          await expectLater(repo.importSnapshot(unknown), throwsArgumentError);
          expect(canon(await repo.exportSnapshot()), canon(beforeUnknown));

          final deviceOnly = BackupSnapshot(
            collections: const <String, Map<String, Object?>>{},
            lists: const <String, Map<String, List<Object?>>>{},
            meta: const <String, Object?>{
              'notification_permission_asked': false,
            },
            dataVersion: before.dataVersion,
            catalogVersion: before.catalogVersion,
          );
          await repo.importSnapshot(deviceOnly);
          expect(
            await repo.getPreferenceBool('notification_permission_asked'),
            isTrue,
          );
        },
      );

      test(
        'S-27803b the bundled food catalog is left alone by an import',
        () async {
          if (harness.name != 'Hive') {
            // The Mock holds no foods_catalog box: Hive-only scenario.
            return;
          }

          final catalogBefore = (await repo.getCatalogFoods()).length;
          expect(
            catalogBefore,
            greaterThan(0),
            reason: 'S-27803b the catalog is not empty before the import',
          );

          final carried = await repo.exportSnapshot();
          final onlySessions = BackupSnapshot(
            collections: <String, Map<String, Object?>>{
              'sessions': const <String, Object?>{},
            },
            lists: const <String, Map<String, List<Object?>>>{},
            meta: const <String, Object?>{},
            dataVersion: carried.dataVersion,
            catalogVersion: carried.catalogVersion,
          );

          await repo.importSnapshot(onlySessions);

          expect(
            (await repo.getCatalogFoods()).length,
            catalogBefore,
            reason: 'S-27803b the import must not clear the bundled catalog',
          );
        },
      );

      test('S-27804a the export never carries a device-only meta key', () async {
        await repo.setPreferenceBool('notification_permission_asked', true);
        await repo.setLastDataVersionTransition(2, 3);
        expect(
          await repo.getPreferenceBool('notification_permission_asked'),
          isTrue,
          reason:
              'S-27804a the device-only preference is stored before the export',
        );
        final transition = await repo.getLastDataVersionTransition();
        expect(
          transition?.from,
          2,
          reason: 'S-27804a the transition "from" is stored before the export',
        );
        expect(
          transition?.to,
          3,
          reason: 'S-27804a the transition "to" is stored before the export',
        );

        final snapshot = await repo.exportSnapshot();

        for (final key in const <String>[
          'notification_permission_asked',
          'data_version_last_from',
          'data_version_last_to',
        ]) {
          expect(
            snapshot.meta.containsKey(key),
            isFalse,
            reason: 'S-27804a the export carries the device-only key $key',
          );
        }
      });

      test(
        'S-27813 a planned session keeps its wall-clock day and series text',
        () async {
          await seedEverything(repo);
          final snap = await repo.exportSnapshot();
          await harness.close();

          final h2 = factory();
          try {
            final restored = await h2.open();
            await restored.importSnapshot(snap);

            final plans = <String, PlannedSession>{
              for (final plan in await restored.getPlannedSessions())
                plan.id: plan,
            };
            expect(plans['plan-series']!.scheduledDateMs, fixtureDayMs());
            expect(plans['plan-series']!.recurrenceRule, recurrenceRuleText);
            expect(plans['plan-done']!.scheduledDateMs, fixtureDayMs(1));
            expect(plans['plan-done']!.isCompleted, isTrue);
            expect(plans['plan-done']!.linkedSessionId, 'session-a');
          } finally {
            await h2.close();
          }
        },
      );

      test('S-27814 a fresh store exports a well-formed snapshot', () async {
        final snap = await repo.exportSnapshot();
        await harness.close();

        final h2 = factory();
        try {
          final restored = await h2.open();
          await restored.importSnapshot(snap);

          expect(canon(await restored.exportSnapshot()), canon(snap));
        } finally {
          await h2.close();
        }
      });

      test('S-27816 two consecutive exports are equal', () async {
        await seedEverything(repo);

        final first = await repo.exportSnapshot();
        final second = await repo.exportSnapshot();

        expect(canon(second), canon(first));
      });
    });
  }

  test(
    'S-27815 a Mock snapshot and a Hive snapshot carry the same rows',
    () async {
      // Reads each store back through the other's `exportSnapshot`: the rows are
      // equal collection by collection, and every meta key the Mock carries is
      // present on the Hive side with the same value (D-27810).
      void expectSameRows(
        BackupSnapshot actual,
        BackupSnapshot expected, {
        required String direction,
      }) {
        for (final entry in expected.collections.entries) {
          if (uncomparedCollections.contains(entry.key)) continue;
          expect(
            canonOf(comparableRows(entry.key, actual.collections[entry.key])),
            canonOf(comparableRows(entry.key, entry.value)),
            reason: '$direction: ${entry.key}',
          );
        }
        expect(
          canonOf(actual.lists),
          canonOf(expected.lists),
          reason: '$direction: list boxes',
        );
        // A collection one side leaves out compares as an empty one.
        for (final name in actual.collections.keys) {
          if (uncomparedCollections.contains(name)) continue;
          if (expected.collections.containsKey(name)) continue;
          expect(
            canonOf(comparableRows(name, actual.collections[name])),
            canonOf(const <String, Object?>{}),
            reason: '$direction: $name is not in the snapshot and not empty',
          );
        }
        for (final entry in expected.meta.entries) {
          expect(
            actual.meta.containsKey(entry.key),
            isTrue,
            reason: '$direction: meta ${entry.key} is missing',
          );
          expect(
            actual.meta[entry.key],
            entry.value,
            reason: '$direction: meta ${entry.key}',
          );
        }
        expect(
          actual.dataVersion,
          expected.dataVersion,
          reason: '$direction: dataVersion',
        );
        expect(
          actual.catalogVersion,
          expected.catalogVersion,
          reason: '$direction: catalogVersion',
        );
      }

      // Mock → Hive.
      final mock = MockWorkoutRepository();
      await mock.initialize();
      await seedEverything(mock);
      final fromMock = await mock.exportSnapshot();

      final hiveOut = HiveRepositoryHarness();
      try {
        final hiveRepo = await hiveOut.open();
        await hiveRepo.importSnapshot(fromMock);
        expectSameRows(
          await hiveRepo.exportSnapshot(),
          fromMock,
          direction: 'Mock → Hive',
        );
      } finally {
        await hiveOut.close();
      }

      // Hive → Mock.
      final hiveIn = HiveRepositoryHarness();
      try {
        final hiveRepo = await hiveIn.open();
        await seedEverything(hiveRepo);
        final fromHive = await hiveRepo.exportSnapshot();

        final restored = MockWorkoutRepository();
        await restored.initialize();
        await restored.importSnapshot(fromHive);
        expectSameRows(
          await restored.exportSnapshot(),
          fromHive,
          direction: 'Hive → Mock',
        );
      } finally {
        await hiveIn.close();
      }
    },
  );

  test('S-27818 every box initialize opens is classified for the backup', () {
    final source = File(
      'lib/data/repositories/hive_workout_repository.dart',
    ).readAsStringSync();

    final opened = <String>{
      for (final match in RegExp(
        r"Hive\.openBox(?:<[^>]*>)?\(\s*'([a-z_]+)'",
        dotAll: true,
      ).allMatches(source))
        match.group(1)!,
    };

    Set<String> declaration(String pattern) => <String>{
      for (final match in RegExp(pattern, dotAll: true).allMatches(source))
        for (final name in RegExp("'([a-z_]+)'").allMatches(match.group(1)!))
          name.group(1)!,
    };

    final mapBoxes = declaration(
      r'static const List<String> _backupMapBoxes = \[(.*?)\];',
    );
    final listBoxes = declaration(
      r'static const List<String> _backupListBoxes = \[(.*?)\];',
    );
    final excluded = declaration(
      r'static const Set<String> _backupExcludedBoxes = \{(.*?)\};',
    );

    expect(mapBoxes, isNotEmpty);
    expect(listBoxes, isNotEmpty);

    final classified = <String>{...mapBoxes, ...listBoxes, ...excluded};
    final openedDataBoxes = opened.difference({'meta'});

    expect(
      openedDataBoxes,
      classified,
      reason:
          'initialize opens a box the backup does not classify: '
          '${openedDataBoxes.difference(classified)}',
    );
    expect(
      mapBoxes.intersection(listBoxes),
      isEmpty,
      reason: 'a box is both a map box and a list box',
    );
    expect(
      mapBoxes.intersection(excluded),
      isEmpty,
      reason: 'a box is both carried and excluded',
    );
    expect(
      listBoxes.intersection(excluded),
      isEmpty,
      reason: 'a box is both carried and excluded',
    );
  });
}
