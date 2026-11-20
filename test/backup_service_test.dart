// Plan 278a P4 — `BackupService`: export to text, safe restore, describe,
// file name. Plan: `docs/plans/2026-11-19-278a-backup-file-engine-plan/
// 2026-11-19-278a-backup-file-engine-plan.md` (D-27806, D-27807, D-27809,
// D-27811; S-27804..S-27811, S-27817, S-27819, S-27820).

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/data_version.dart';
import 'package:omnitrain/core/constants/metric_ids.dart';
import 'package:omnitrain/core/models/app_version_info.dart';
import 'package:omnitrain/core/services/backup_service.dart';
import 'package:omnitrain/data/models/backup_codec.dart';
import 'package:omnitrain/data/models/backup_snapshot.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';

import 'helpers/repository_harness.dart';

const AppVersionInfo appVersion = AppVersionInfo(version: '1.0.0', build: '1');

/// The series rule text a repeating plan stores, exactly as
/// `RecurrenceRule.encode` writes it.
const String recurrenceRuleText =
    '{"v":1,"series":"s1","unit":"week","every":1,"weekdays":[4],'
    '"end":"count","count":2}';

/// Local midnight [daysAfter] the fixture day.
int fixtureDayMs([int daysAfter = 0]) =>
    DateTime(2026, 12, 3 + daysAfter).millisecondsSinceEpoch;

// ─── Canonical form ─────────────────────────────────────────────────────────

/// [value] with every map's keys sorted, so two snapshots compare by content
/// and not by the order the store happened to hand their rows back in.
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

/// [text] with the header values [header] merged in.
String withHeader(String text, Map<String, Object?> header) {
  final root = jsonDecode(text) as Map<String, Object?>;
  root.addAll(header);
  return jsonEncode(root);
}

/// The message the codec refuses [text] with, taken from the codec itself.
String codecMessage(String text) {
  try {
    decodeBackup(text);
  } on BackupFormatException catch (e) {
    return e.message;
  }
  fail('expected the codec to refuse this text');
}

// ─── Fixture ────────────────────────────────────────────────────────────────

/// Every kind of user row the backup must carry, written only through the
/// interface's real writers.
Future<void> seedEverything(WorkoutRepository repo) async {
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

  await repo.setPreferenceString('app_theme', 'x');
  await repo.setPreferenceString('preferred_weight_unit', 'lb');
  await repo.setPreferenceBool('onboarding_complete', true);
  await repo.markSeedEntryTouched('exercise', 'ex-custom');
}

// ─── A repository whose first import fails halfway ──────────────────────────

class _FailingRepo extends MockWorkoutRepository {
  int importCalls = 0;

  @override
  Future<void> importSnapshot(BackupSnapshot snapshot) async {
    importCalls++;
    if (importCalls == 1) {
      await super.importSnapshot(
        BackupSnapshot(
          collections: <String, Map<String, Object?>>{
            'sessions': const <String, Object?>{},
          },
          lists: const <String, Map<String, List<Object?>>>{},
          meta: const <String, Object?>{},
          dataVersion: snapshot.dataVersion,
          catalogVersion: snapshot.catalogVersion,
        ),
      );
      throw StateError('simulated halfway failure');
    }
    await super.importSnapshot(snapshot);
  }
}

// ─── A repository whose every import fails ──────────────────────────────────

class _AlwaysFailingImportRepo extends MockWorkoutRepository {
  bool failImports = false;

  @override
  Future<void> importSnapshot(BackupSnapshot snapshot) async {
    if (failImports) {
      throw StateError('boom');
    }
    await super.importSnapshot(snapshot);
  }
}

void main() {
  test('S-27811 fileName is the local date, zero-padded', () {
    expect(
      BackupService.fileName(DateTime(2026, 11, 19, 23, 59)),
      'omnitrain-backup-2026-11-19.json',
      reason: 'S-27811 the local date, zero-padded',
    );
    expect(
      BackupService.fileName(DateTime(2027, 1, 5, 0, 0)),
      'omnitrain-backup-2027-01-05.json',
      reason: 'S-27811 a new year and a single-digit month and day',
    );
  });

  for (final factory in harnessFactories) {
    final harness = factory();
    group('${harness.name} — BackupService', () {
      late WorkoutRepository repo;
      late BackupService service;

      setUp(() async {
        repo = await harness.open();
        service = BackupService(repo, appVersion);
      });
      tearDown(() async => await harness.close());

      test(
        'S-27804 the exported text carries no excluded boxes or device keys',
        () async {
          await repo.setPreferenceBool('notification_permission_asked', true);
          await seedEverything(repo);
          final text = await service.exportToText();
          final snapshot = decodeBackup(text);

          // The wrist inbox IS carried, so its rows legitimately hold the
          // stored key `watch_session_id`; the exclusion is about the watch
          // app's own `watch_session_*` boxes, checked by box name.
          for (final name in snapshot.collections.keys) {
            expect(
              name.startsWith('watch_session_'),
              isFalse,
              reason: 'S-27804 the text carries the watch box $name',
            );
            expect(
              name,
              isNot('foods_catalog'),
              reason: 'S-27804 the text carries the bundled catalog box',
            );
          }
          for (final key in const [
            'notification_permission_asked',
            'data_version_last_from',
            'data_version_last_to',
          ]) {
            expect(
              snapshot.meta.containsKey(key),
              isFalse,
              reason: 'S-27804 the text carries the device-only key $key',
            );
          }
        },
      );

      test('S-27805 malformed texts are refused and change nothing', () async {
        await seedEverything(repo);
        final before = await repo.exportSnapshot();
        final valid = encodeBackup(before, appVersion: appVersion.version);

        final badFormat = jsonDecode(valid) as Map<String, Object?>
          ..['formatVersion'] = 2;
        final stringRow = jsonDecode(valid) as Map<String, Object?>;
        (stringRow['collections'] as Map)['sessions'] = <String, Object?>{
          'k1': 'row',
        };

        final cases = <String, String>{
          'nope': codecMessage('nope'),
          '{}': codecMessage('{}'),
          jsonEncode(badFormat): codecMessage(jsonEncode(badFormat)),
          jsonEncode(stringRow): codecMessage(jsonEncode(stringRow)),
        };
        for (final entry in cases.entries) {
          final result = await service.restoreFromText(entry.key);
          expect(
            result.isRestored,
            isFalse,
            reason: 'S-27805 the text was accepted: ${entry.value}',
          );
          expect(
            result.refusal,
            entry.value,
            reason: 'S-27805 the refusal is not the codec message',
          );
          expect(
            canon(await repo.exportSnapshot()),
            canon(before),
            reason: 'S-27805 the store changed after a refusal',
          );
        }
      });

      test(
        'S-27806 a newer dataVersion is refused; 1 and the current one restore',
        () async {
          await seedEverything(repo);
          final before = await repo.exportSnapshot();
          final valid = encodeBackup(before, appVersion: appVersion.version);

          final newer = withHeader(valid, {
            'dataVersion': currentDataVersion + 1,
          });
          final newerResult = await service.restoreFromText(newer);
          expect(
            newerResult.isRestored,
            isFalse,
            reason: 'S-27806 a newer backup was accepted',
          );
          expect(newerResult.refusal, BackupService.newerAppMessage);
          expect(
            canon(await repo.exportSnapshot()),
            canon(before),
            reason: 'S-27806 the store changed after the refusal',
          );

          final oldest = withHeader(valid, {'dataVersion': 1});
          expect(
            (await service.restoreFromText(oldest)).isRestored,
            isTrue,
            reason: 'S-27806 dataVersion 1 is accepted',
          );
          expect(
            (await service.restoreFromText(valid)).isRestored,
            isTrue,
            reason: 'S-27806 the current dataVersion is accepted',
          );
        },
      );

      test('S-27807 a running workout blocks the restore', () async {
        await seedEverything(repo);
        final valid = encodeBackup(
          await repo.exportSnapshot(),
          appVersion: appVersion.version,
        );

        await repo.createSession(
          TrainingSession(
            id: 'running-live',
            ownerUserId: 'user-1',
            startedAtMs: fixtureStart,
            endedAtMs: null,
            isRolling: false,
            createdAtMs: fixtureStart,
            updatedAtMs: fixtureStart,
          ),
        );
        final blocked = await service.restoreFromText(valid);
        expect(
          blocked.isRestored,
          isFalse,
          reason: 'S-27807 the running workout did not block',
        );
        expect(blocked.refusal, BackupService.runningWorkoutMessage);
      });

      test('S-27807 a rolling session with no end does not block', () async {
        await seedEverything(repo);
        await seedSession(repo, sessionId: 'rolling-live', isRolling: true);
        final valid = encodeBackup(
          await repo.exportSnapshot(),
          appVersion: appVersion.version,
        );
        expect(
          (await service.restoreFromText(valid)).isRestored,
          isTrue,
          reason: 'S-27807 a rolling session blocked the restore',
        );
      });

      test('S-27807 a finished session does not block', () async {
        await seedEverything(repo);
        await seedSession(repo, sessionId: 'finished-past');
        final valid = encodeBackup(
          await repo.exportSnapshot(),
          appVersion: appVersion.version,
        );
        expect(
          (await service.restoreFromText(valid)).isRestored,
          isTrue,
          reason: 'S-27807 a finished session blocked the restore',
        );
      });

      test(
        'S-27809 an older backup runs the pending data steps at the next start',
        () async {
          if (harness.name != 'Hive') {
            // Hive-only scenario: needs a real restart over stored files.
            return;
          }
          await seedEverything(repo);
          final valid = await service.exportToText();
          final root = jsonDecode(valid) as Map<String, Object?>;
          root['dataVersion'] = 5;
          (root['meta'] as Map)['data_version'] = 5;

          final result = await service.restoreFromText(jsonEncode(root));
          expect(
            result.isRestored,
            isTrue,
            reason: 'S-27809 an older backup was refused',
          );

          final restarted = await harness.restart();
          expect(
            await restarted.getDataVersion(),
            currentDataVersion,
            reason: 'S-27809 the pending data steps did not run',
          );
        },
      );

      test(
        'S-27810 describe reads the file without writing anything',
        () async {
          await seedEverything(repo);
          final before = await repo.exportSnapshot();
          final lowerBound = DateTime.now().toUtc().millisecondsSinceEpoch;
          final text = await service.exportToText();
          final upperBound = DateTime.now().toUtc().millisecondsSinceEpoch;

          final info = service.describe(text);
          expect(info, isNotNull);
          expect(
            info!.appVersion,
            appVersion.version,
            reason: 'S-27810 the header app version is wrong',
          );
          expect(
            info.exportedAtMs,
            inInclusiveRange(lowerBound, upperBound),
            reason: 'S-27810 the header date is not the export time',
          );
          expect(
            info.sessions,
            2,
            reason: 'S-27810 the session count is wrong',
          );
          expect(
            info.routines,
            1,
            reason: 'S-27810 the routine count is wrong',
          );
          expect(info.foods, 1, reason: 'S-27810 the food count is wrong');
          expect(
            canon(await repo.exportSnapshot()),
            canon(before),
            reason: 'S-27810 describe wrote something',
          );

          expect(
            service.describe('nope'),
            isNull,
            reason: 'S-27810 a refused text returned info',
          );
          expect(service.describe('{}'), isNull);
        },
      );

      test(
        'S-27810b describe counts what the file holds, whatever the numbers',
        () async {
          // A shape different from seedEverything: three finished sessions,
          // two custom foods and no routines, written through the real
          // writers on top of whatever a fresh store already holds.
          await repo.createFoodGroup(
            FoodGroup(
              id: 'group-shape',
              name: 'Shape',
              color: '#00FF00',
              createdAtMs: fixtureStart,
              updatedAtMs: fixtureStart,
            ),
          );
          for (final index in const [0, 1]) {
            await repo.createFood(
              Food(
                id: 'food-shape-$index',
                name: 'Shape $index',
                groupId: 'group-shape',
                unitType: FoodUnitType.grams,
                referenceAmount: 100,
                referenceLabel: 'g',
                protein: 10,
                carbs: 5,
                fat: 1,
                createdAtMs: fixtureStart,
                updatedAtMs: fixtureStart,
              ),
            );
          }
          for (var n = 0; n < 3; n++) {
            await seedSession(
              repo,
              sessionId: 'shape-session-$n',
              daysAgo: n + 1,
            );
          }

          final text = await service.exportToText();
          final info = service.describe(text);
          expect(info, isNotNull);

          // The expectations come from the store, not from hard-coded numbers:
          // a fresh Mock already holds its seeded rows, a fresh Hive holds none.
          final sessions = (await repo.getAllSessions()).length;
          final routines = (await repo.getTemplates()).length;
          final foods = decodeBackup(text).collections['foods']!.length;

          // The three counts are pairwise distinct, so one hard-coded value
          // cannot satisfy two fields; none of them may be the 2 (sessions) or
          // 1 (foods) seedEverything happens to hold. This shape's foods count
          // is 2 by construction, so only the hard-coded 1 is excluded there.
          expect(sessions, isNot(foods), reason: 'S-27810b counts collide');
          expect(sessions, isNot(routines), reason: 'S-27810b counts collide');
          expect(foods, isNot(routines), reason: 'S-27810b counts collide');
          expect(sessions, isNot(2), reason: 'S-27810b sessions count is 2');
          expect(sessions, isNot(1), reason: 'S-27810b sessions count is 1');
          expect(routines, isNot(2), reason: 'S-27810b routines count is 2');
          expect(routines, isNot(1), reason: 'S-27810b routines count is 1');
          expect(foods, isNot(1), reason: 'S-27810b foods count is 1');

          expect(
            info!.sessions,
            sessions,
            reason: 'S-27810b the session count is wrong',
          );
          expect(
            info.routines,
            routines,
            reason: 'S-27810b the routine count is wrong',
          );
          expect(info.foods, foods, reason: 'S-27810b the food count is wrong');
        },
      );

      test(
        'S-27819 a store with 500 observations exports and restores in time',
        () async {
          await seedSession(repo, sessionId: 'big-session');
          await repo.createEffort(
            SegmentEffort(
              id: 'big-effort',
              segmentId: 'seg-big-session',
              orderIndex: 0,
              effortKind: 'set',
              exerciseId: 'ex-big',
              createdAtMs: fixtureStart,
              updatedAtMs: fixtureStart,
            ),
          );
          for (var n = 0; n < 500; n++) {
            await repo.createObservation(
              repsRow('big-effort', n, n, atMs: fixtureRowAt(n)),
            );
          }

          final watch = Stopwatch()..start();
          final text = await service.exportToText();
          final result = await service.restoreFromText(text);
          watch.stop();

          expect(
            result.isRestored,
            isTrue,
            reason: 'S-27819 the restore was refused',
          );
          expect(
            watch.elapsed,
            lessThan(const Duration(seconds: 10)),
            reason: 'S-27819 500 observations took too long',
          );
        },
      );

      test('S-27820 after a refusal the repository still works', () async {
        await seedEverything(repo);
        final refusal = await service.restoreFromText('nope');
        expect(refusal.isRestored, isFalse);

        await repo.createPlannedSession(
          PlannedSession(
            id: 'plan-after',
            ownerUserId: 'user-1',
            scheduledDateMs: fixtureDayMs(),
            createdAtMs: fixtureStart,
            updatedAtMs: fixtureStart,
          ),
        );
        final plans = await repo.getPlannedSessions();
        expect(
          plans.any((p) => p.id == 'plan-after'),
          isTrue,
          reason: 'S-27820 the repository no longer writes and reads',
        );
      });
    });
  }

  test('S-27817 the service takes the repository interface', () {
    final WorkoutRepository typed = MockWorkoutRepository();
    final interfaceService = BackupService(typed, appVersion);
    expect(
      interfaceService.describe('nope'),
      isNull,
      reason: 'S-27817 the service did not construct through the interface',
    );
  });

  test(
    "S-27808 a failed restore puts back the phone's OWN data, not the file's",
    () async {
      // The backup text comes from a DIFFERENT repository, so rolling back to
      // the file's own snapshot would leave the phone holding the file's rows.
      final sourceRepo = MockWorkoutRepository();
      await sourceRepo.initialize();
      await seedEverything(sourceRepo);
      final text = encodeBackup(
        await sourceRepo.exportSnapshot(),
        appVersion: appVersion.version,
      );

      final repo = _FailingRepo();
      await repo.initialize();
      await seedEverything(repo);
      await seedSession(repo, sessionId: 'junk-session', daysAgo: 3);
      await repo.setPreferenceString('junk_pref', 'keep-me');
      final before = await repo.exportSnapshot();
      final service = BackupService(repo, appVersion);

      final result = await service.restoreFromText(text);
      expect(
        result.isRestored,
        isFalse,
        reason: 'S-27808 the failure restored',
      );
      expect(result.refusal, BackupService.failedMessage);
      expect(
        repo.importCalls,
        2,
        reason: 'S-27808 the rollback import did not run',
      );
      expect(
        canon(await repo.exportSnapshot()),
        canon(before),
        reason: "S-27808 the store is not the phone's own state from before",
      );
      expect(
        canon(await repo.exportSnapshot()),
        isNot(canon(decodeBackup(text))),
        reason: "S-27808 the store holds the file's snapshot, not its own",
      );
    },
  );

  test('S-27808c a failed rollback says some data may have changed', () async {
    final sourceRepo = MockWorkoutRepository();
    await sourceRepo.initialize();
    await seedEverything(sourceRepo);
    final text = encodeBackup(
      await sourceRepo.exportSnapshot(),
      appVersion: appVersion.version,
    );

    final repo = _AlwaysFailingImportRepo();
    await repo.initialize();
    await seedEverything(repo);
    repo.failImports = true;
    final service = BackupService(repo, appVersion);

    final result = await service.restoreFromText(text);
    expect(result.isRestored, isFalse, reason: 'S-27808c the restore ran');
    expect(
      result.refusal,
      BackupService.partialMessage,
      reason: 'S-27808c the failed rollback still claimed nothing was changed',
    );
    expect(
      result.refusal,
      isNot(BackupService.failedMessage),
      reason: 'S-27808c a failed rollback is not a clean refusal',
    );
  });
}
