import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/data_version.dart';
import 'package:omnitrain/core/models/app_version_info.dart';
import 'package:omnitrain/core/services/backup_file_gateway.dart';
import 'package:omnitrain/core/services/backup_service.dart';
import 'package:omnitrain/data/models/backup_codec.dart';
import 'package:omnitrain/data/models/backup_snapshot.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/settings/settings_screen.dart';
import 'package:omnitrain/state/settings/settings_state.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/fake_rest_notification_service.dart';
import 'helpers/fake_timer_alert_service.dart';
import 'helpers/repository_harness.dart';

/// A [BackupFileGateway] that records what the screen asks of it, so the
/// tests can assert on the export flow without a real share sheet
/// (plan 278b S-27822, S-27834).
class FakeBackupFileGateway implements BackupFileGateway {
  final List<({String fileName, String text})> shares = [];
  final List<void> pickCalls = [];

  /// Settable result of [shareText]; null falls back to "shown" (true).
  Future<bool> Function(String, String)? shareResult;

  /// When set, [shareText] throws it instead of returning.
  Object? shareThrows;

  /// Settable result of [pickText]; null falls back to "cancelled" (null).
  Future<String?> Function()? pick;

  @override
  Future<bool> shareText({
    required String fileName,
    required String text,
  }) async {
    shares.add((fileName: fileName, text: text));
    if (shareThrows != null) throw shareThrows!;
    final result = shareResult;
    if (result != null) return result(fileName, text);
    return true;
  }

  @override
  Future<String?> pickText() async {
    pickCalls.add(null);
    final pick = this.pick;
    if (pick != null) return pick();
    return null;
  }
}

/// A [BackupService] whose export always fails, for S-27834.
class ThrowingExportService extends BackupService {
  ThrowingExportService(super.repository, super.appVersion);

  @override
  Future<String> exportToText() async => throw StateError('boom');
}

/// A [BackupService] that holds `restoreFromText` on a completer the test
/// resolves, for the in-flight scenarios (S-27827). `inspect`/`describe` stay
/// real, so the screen runs its checks on a genuinely valid text.
class HeldRestoreService extends BackupService {
  HeldRestoreService(super.repository, super.appVersion);

  int restoreCalls = 0;
  final Completer<BackupRestoreResult> hold = Completer<BackupRestoreResult>();

  @override
  Future<BackupRestoreResult> restoreFromText(String text) async {
    restoreCalls++;
    return hold.future;
  }
}

/// A [BackupService] whose `restoreFromText` throws, for S-27826b: the screen
/// must turn the throw into the refusal message, not crash. `inspect` stays
/// real, so the text passes the pre-restore checks.
class ThrowingRestoreService extends BackupService {
  ThrowingRestoreService(super.repository, super.appVersion);

  @override
  Future<BackupRestoreResult> restoreFromText(String text) async =>
      throw StateError('boom');
}

/// Backs up the separate source repository A: one finished session, one
/// routine, and the two preferences a restore must carry (S-27825). The
/// screen under test restores into a different repository B.
Future<String> backupTextFrom(MockWorkoutRepository repo) async {
  await seedSession(repo, sessionId: 'b-sess-a');
  await repo.createTemplate(
    WorkoutTemplate(
      id: 'b-tmpl-a',
      name: 'Push Day',
      createdAtMs: fixtureStart,
      updatedAtMs: fixtureStart,
    ),
  );
  await repo.setPreferenceString('app_theme', 'x');
  await repo.setPreferenceBool('onboarding_complete', false);
  return (await makeService(repo)).exportToText();
}

/// An unfinished, non-rolling session: the running workout that blocks a
/// restore (S-27826). `seedSession` cannot express it — it always ends a
/// non-rolling session.
Future<void> seedRunningWorkout(MockWorkoutRepository repo) async {
  final start = fixtureStart;
  await repo.createSession(
    TrainingSession(
      id: 'b-running',
      ownerUserId: 'user-1',
      startedAtMs: start,
      endedAtMs: null,
      isRolling: false,
      createdAtMs: start,
      updatedAtMs: start,
    ),
  );
  await repo.createSegment(
    SessionSegment(
      id: 'seg-b-running',
      sessionId: 'b-running',
      orderIndex: 0,
      segmentType: 'workout',
      name: 'Main Workout',
      createdAtMs: start,
      updatedAtMs: start,
    ),
  );
}

/// A backup written by a newer build (S-27835): the real writer on the other
/// phone carries a `dataVersion` above this app's `currentDataVersion`. This
/// app's own writer refuses to produce one, so the fixture rewrites a valid
/// backup text the way a newer build would.
Future<String> backupTextFromNewerBuild(String text) async {
  final newer = currentDataVersion + 1;
  final root = jsonDecode(text) as Map<String, Object?>;
  root['dataVersion'] = newer;
  root['meta'] = <String, Object?>{
    ...(root['meta'] as Map).cast<String, Object?>(),
    'data_version': newer,
  };
  return jsonEncode(root);
}

/// A well-formed backup text whose header names 19 Nov 2026 23:30 (device
/// local) and whose collections carry [sessionCount] sessions and
/// [routineCount] routines (S-27833). The rows are copies of one real stored
/// row under different ids — `inspect` only counts them.
Future<String> backupTextWithCounts(
  MockWorkoutRepository repo, {
  required int sessionCount,
  required int routineCount,
}) async {
  await seedSession(repo, sessionId: 'b-row-source');
  await repo.createTemplate(
    WorkoutTemplate(
      id: 'b-tmpl-source',
      name: 'Source',
      createdAtMs: fixtureStart,
      updatedAtMs: fixtureStart,
    ),
  );
  final snapshot = await repo.exportSnapshot();
  final built = BackupSnapshot(
    collections: {
      'sessions': {
        for (var n = 0; n < sessionCount; n++)
          'b-s-$n': {
            ...(snapshot.collections['sessions']!.values.first
                as Map<String, Object?>),
            'id': 'b-s-$n',
          },
      },
      'templates': {
        for (var n = 0; n < routineCount; n++)
          'b-t-$n': {
            ...(snapshot.collections['templates']!.values.first
                as Map<String, Object?>),
            'id': 'b-t-$n',
          },
      },
    },
    lists: const {},
    meta: const {},
    dataVersion: await repo.getDataVersion(),
    catalogVersion: await repo.getCatalogVersion(),
  );
  return encodeBackup(
    built,
    appVersion: '1.0.0',
    now: DateTime(2026, 11, 19, 23, 30),
  );
}

Future<BackupService> makeService(MockWorkoutRepository repo) async =>
    BackupService(repo, const AppVersionInfo(version: '0.0.0', build: '0'));

Future<SettingsState> makeSettingsWith(MockWorkoutRepository repo) async {
  final state = SettingsState(repo, fakePreferencesService());
  await state.initialize();
  return state;
}

Future<SettingsState> makeSettings() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  return makeSettingsWith(repo);
}

/// Pumps the Settings screen at [size], with the DATA section dependencies
/// injected. Called after all repository/`SettingsState` awaits: a Hive or
/// preferences write inside `testWidgets` never settles.
Future<void> pumpSettings(
  WidgetTester tester, {
  BackupService? service,
  BackupFileGateway? gateway,
  VoidCallback? onRestored,
  SettingsState? settingsState,
  Size size = const Size(600, 3000),
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: SettingsScreen(
        settingsState: settingsState ?? await makeSettings(),
        timerAlertService: FakeTimerAlertService(),
        restNotificationService: FakeRestNotificationService(),
        appVersionInfo: const AppVersionInfo(version: '0.0.0', build: '0'),
        backupService: service,
        backupFileGateway: gateway,
        onDataRestored: onRestored,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('DATA section rows', () {
    testWidgets(
      'S-27821 the DATA header and both rows render between HEALTH and APPEARANCE',
      (WidgetTester tester) async {
        final repo = MockWorkoutRepository();
        await repo.initialize();
        final settings = await makeSettingsWith(repo);
        final service = await makeService(repo);
        final gateway = FakeBackupFileGateway();

        await pumpSettings(
          tester,
          settingsState: settings,
          service: service,
          gateway: gateway,
        );

        expect(
          find.text('DATA'),
          findsOneWidget,
          reason: 'S-27821: the DATA header renders with both dependencies',
        );
        expect(
          find.text('Export data'),
          findsOneWidget,
          reason: 'S-27821: the export row renders with both dependencies',
        );
        expect(
          find.text('Import data'),
          findsOneWidget,
          reason: 'S-27821: the import row renders with both dependencies',
        );

        final healthTop = tester.getTopLeft(find.text('HEALTH')).dy;
        final dataTop = tester.getTopLeft(find.text('DATA')).dy;
        final appearanceTop = tester.getTopLeft(find.text('APPEARANCE')).dy;
        expect(
          healthTop,
          lessThan(dataTop),
          reason: 'S-27821: the DATA section sits after HEALTH',
        );
        expect(
          dataTop,
          lessThan(appearanceTop),
          reason: 'S-27821: the DATA section sits before APPEARANCE',
        );

        final exportTop = tester
            .getTopLeft(find.byKey(const Key('data-export-row')))
            .dy;
        final importTop = tester
            .getTopLeft(find.byKey(const Key('data-import-row')))
            .dy;
        expect(
          exportTop,
          lessThan(importTop),
          reason: 'S-27821: Export data sits above Import data',
        );
      },
    );

    testWidgets(
      'S-27821 with a null backupService the DATA section is absent',
      (WidgetTester tester) async {
        await pumpSettings(tester, gateway: FakeBackupFileGateway());

        expect(
          find.text('DATA'),
          findsNothing,
          reason: 'S-27821: a null service hides the whole section',
        );
        expect(
          find.text('Export data'),
          findsNothing,
          reason: 'S-27821: a null service hides the export row',
        );
        expect(
          find.text('Import data'),
          findsNothing,
          reason: 'S-27821: a null service hides the import row',
        );
      },
    );

    testWidgets(
      'S-27821 with a null backupFileGateway the DATA section is absent',
      (WidgetTester tester) async {
        final repo = MockWorkoutRepository();
        await repo.initialize();
        final service = await makeService(repo);
        await pumpSettings(tester, service: service);

        expect(
          find.text('DATA'),
          findsNothing,
          reason: 'S-27821: a null gateway hides the whole section',
        );
        expect(
          find.text('Export data'),
          findsNothing,
          reason: 'S-27821: a null gateway hides the export row',
        );
        expect(
          find.text('Import data'),
          findsNothing,
          reason: 'S-27821: a null gateway hides the import row',
        );
      },
    );
  });

  group('Export data flow', () {
    testWidgets(
      'S-27822 tapping the export row shares one backup file with today\'s name',
      (WidgetTester tester) async {
        final repo = MockWorkoutRepository();
        await repo.initialize();
        final settings = await makeSettingsWith(repo);
        final service = await makeService(repo);
        final gateway = FakeBackupFileGateway();

        await pumpSettings(
          tester,
          settingsState: settings,
          service: service,
          gateway: gateway,
        );

        await tester.tap(find.byKey(const Key('data-export-row')));
        await tester.pumpAndSettle();

        // Computed after the share: the day cannot change mid-test.
        final fileName = BackupService.fileName(DateTime.now());
        expect(
          gateway.shares,
          hasLength(1),
          reason: 'S-27822: one export tap shares exactly one file',
        );
        expect(
          gateway.shares.single.fileName,
          fileName,
          reason: 'S-27822: the shared file is omnitrain-backup-<today>.json',
        );

        final snapshot = decodeBackup(gateway.shares.single.text);
        expect(
          snapshot.dataVersion,
          await repo.getDataVersion(),
          reason:
              'S-27822: the shared text is a valid backup of this repo\'s '
              'data version',
        );
        expect(
          find.text('Could not export. Try again.'),
          findsNothing,
          reason: 'S-27822: a shown share sheet shows no error message',
        );
      },
    );

    testWidgets(
      'S-27822 a gateway that returns false shows the error message and no dialog',
      (WidgetTester tester) async {
        final repo = MockWorkoutRepository();
        await repo.initialize();
        final service = await makeService(repo);
        final gateway = FakeBackupFileGateway()
          ..shareResult = (fileName, text) async => false;
        await pumpSettings(tester, service: service, gateway: gateway);

        await tester.tap(find.byKey(const Key('data-export-row')));
        await tester.pumpAndSettle();

        expect(
          find.text('Could not export. Try again.'),
          findsOneWidget,
          reason: 'S-27822: a hidden share sheet shows the error message',
        );
        expect(
          find.byType(AlertDialog),
          findsNothing,
          reason: 'S-27822: the failure is a message, not a dialog',
        );
      },
    );

    testWidgets(
      'S-27822 a gateway that throws shows the error message and no dialog',
      (WidgetTester tester) async {
        final repo = MockWorkoutRepository();
        await repo.initialize();
        final service = await makeService(repo);
        final gateway = FakeBackupFileGateway()
          ..shareThrows = StateError('share failed');
        await pumpSettings(tester, service: service, gateway: gateway);

        await tester.tap(find.byKey(const Key('data-export-row')));
        await tester.pumpAndSettle();

        expect(
          find.text('Could not export. Try again.'),
          findsOneWidget,
          reason: 'S-27822: a throwing gateway shows the error message',
        );
        expect(
          find.byType(AlertDialog),
          findsNothing,
          reason: 'S-27822: the failure is a message, not a dialog',
        );
      },
    );

    testWidgets(
      'S-27834 a service whose export throws shows the error message and never shares',
      (WidgetTester tester) async {
        final repo = MockWorkoutRepository();
        await repo.initialize();
        final service = ThrowingExportService(
          repo,
          const AppVersionInfo(version: '0.0.0', build: '0'),
        );
        final gateway = FakeBackupFileGateway();
        await pumpSettings(tester, service: service, gateway: gateway);

        await tester.tap(find.byKey(const Key('data-export-row')));
        await tester.pumpAndSettle();

        expect(
          find.text('Could not export. Try again.'),
          findsOneWidget,
          reason: 'S-27834: a throwing export shows the error message',
        );
        expect(
          gateway.shares,
          isEmpty,
          reason: 'S-27834: a failed export never reaches the gateway',
        );
        expect(
          find.byType(AlertDialog),
          findsNothing,
          reason: 'S-27834: the failure is a message, not a dialog',
        );
      },
    );
  });

  group('DATA section layout', () {
    testWidgets(
      'S-27831 the DATA section scrolls at 390x844 with no overflow and labelled rows',
      (WidgetTester tester) async {
        final repo = MockWorkoutRepository();
        await repo.initialize();
        final service = await makeService(repo);
        final gateway = FakeBackupFileGateway();
        final semantics = tester.ensureSemantics();
        try {
          await pumpSettings(
            tester,
            service: service,
            gateway: gateway,
            size: const Size(390, 844),
          );

          await tester.scrollUntilVisible(
            find.text('DATA'),
            300,
            scrollable: find.byType(Scrollable).first,
          );
          // Bring the import row (the last of the section) on screen too, so
          // both rows can be measured inside the surface.
          await tester.scrollUntilVisible(
            find.byKey(const Key('data-import-row')),
            100,
            scrollable: find.byType(Scrollable).first,
          );

          expect(
            tester.takeException(),
            isNull,
            reason: 'S-27831: scrolling to DATA throws no layout exception',
          );

          final dataTop = tester.getTopLeft(find.text('DATA')).dy;
          final exportRect = tester.getRect(
            find.byKey(const Key('data-export-row')),
          );
          final importRect = tester.getRect(
            find.byKey(const Key('data-import-row')),
          );

          expect(
            exportRect.bottom,
            lessThanOrEqualTo(844),
            reason:
                'S-27831: the export row is inside the 390x844 surface '
                '(DATA top=$dataTop, export rect=$exportRect)',
          );
          expect(
            importRect.bottom,
            lessThanOrEqualTo(844),
            reason:
                'S-27831: the import row is inside the 390x844 surface '
                '(DATA top=$dataTop, import rect=$importRect)',
          );

          // The keyed row's outer node (its Material) is unlabeled; the label
          // lives on the row's own Semantics node, so resolve it inside the row.
          final exportSemantics = tester.getSemantics(
            find.descendant(
              of: find.byKey(const Key('data-export-row')),
              matching: find.bySemanticsLabel(RegExp('Export data')),
            ),
          );
          expect(
            exportSemantics.label,
            contains('Export data'),
            reason: 'S-27831: the export row carries its semantic label',
          );
          final importSemantics = tester.getSemantics(
            find.descendant(
              of: find.byKey(const Key('data-import-row')),
              matching: find.bySemanticsLabel(RegExp('Import data')),
            ),
          );
          expect(
            importSemantics.label,
            contains('Import data'),
            reason: 'S-27831: the import row carries its semantic label',
          );
        } finally {
          semantics.dispose();
        }
      },
    );

    testWidgets(
      'S-27831b the rows announce their full action labels, not the plain text',
      (WidgetTester tester) async {
        final repo = MockWorkoutRepository();
        await repo.initialize();
        final service = await makeService(repo);
        final gateway = FakeBackupFileGateway();
        final semantics = tester.ensureSemantics();
        try {
          await pumpSettings(tester, service: service, gateway: gateway);

          expect(
            find.bySemanticsLabel('Export data, saves everything to a file'),
            findsOneWidget,
            reason: 'S-27831b: the export row announces its full action label',
          );
          expect(
            find.bySemanticsLabel(
              'Import data, replaces everything with a backup file',
            ),
            findsOneWidget,
            reason: 'S-27831b: the import row announces its full action label',
          );
          expect(
            find.bySemanticsLabel('Export data'),
            findsNothing,
            reason:
                'S-27831b: the plain row text is not announced on its own',
          );
          expect(
            find.bySemanticsLabel('Import data'),
            findsNothing,
            reason:
                'S-27831b: the plain row text is not announced on its own',
          );
        } finally {
          semantics.dispose();
        }
      },
    );
  });

  group('Export re-entry guard', () {
    testWidgets(
      'S-27822b a second tap while the first share is pending does not share twice',
      (WidgetTester tester) async {
        final repo = MockWorkoutRepository();
        await repo.initialize();
        final service = await makeService(repo);
        final completer = Completer<bool>();
        final gateway = FakeBackupFileGateway()
          ..shareResult = (fileName, text) => completer.future;
        await pumpSettings(tester, service: service, gateway: gateway);

        await tester.tap(find.byKey(const Key('data-export-row')));
        await tester.pump();
        // The row is expected to be disabled (onTap null) while the share is
        // pending, so this tap deliberately misses the now-inert InkWell.
        await tester.tap(
          find.byKey(const Key('data-export-row')),
          warnIfMissed: false,
        );
        await tester.pump();

        expect(
          gateway.shares,
          hasLength(1),
          reason: 'S-27822b: a pending export blocks the second tap',
        );

        completer.complete(true);
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'S-27822c the export handler ignores a second call while a share is pending',
      (WidgetTester tester) async {
        final repo = MockWorkoutRepository();
        await repo.initialize();
        final service = await makeService(repo);
        final completer = Completer<bool>();
        final gateway = FakeBackupFileGateway()
          ..shareResult = (fileName, text) => completer.future;
        await pumpSettings(tester, service: service, gateway: gateway);

        final inkwell = find.descendant(
          of: find.byKey(const Key('data-export-row')),
          matching: find.byType(InkWell),
        );
        // The handler reached through the row before the row disabled itself:
        // invoking it again is the only way a second call can arrive at all.
        final staleHandler = tester.widget<InkWell>(inkwell).onTap!;

        await tester.tap(find.byKey(const Key('data-export-row')));
        await tester.pump();

        expect(
          gateway.shares,
          hasLength(1),
          reason: 'S-27822c: the pending share is recorded exactly once',
        );
        expect(
          inkwell,
          findsNothing,
          reason:
              'S-27822c: the row disables itself while the share is pending '
              '(no InkWell remains, so onTap is effectively null)',
        );

        staleHandler();
        await tester.pump();

        expect(
          gateway.shares,
          hasLength(1),
          reason: 'S-27822c: the handler ignores a second call while exporting',
        );

        completer.complete(true);
        await tester.pumpAndSettle();
      },
    );
  });

  group('Import data flow', () {
    testWidgets('S-27823 the picker returning null does nothing', (
      WidgetTester tester,
    ) async {
      final repo = MockWorkoutRepository();
      await repo.initialize();
      final settings = await makeSettingsWith(repo);
      final service = await makeService(repo);
      final gateway = FakeBackupFileGateway();
      var restoredCalls = 0;

      await pumpSettings(
        tester,
        settingsState: settings,
        service: service,
        gateway: gateway,
        onRestored: () => restoredCalls++,
      );

      await tester.tap(find.byKey(const Key('data-import-row')));
      await tester.pumpAndSettle();

      expect(
        gateway.pickCalls,
        hasLength(1),
        reason: 'S-27823: one import tap asks the picker once',
      );
      expect(
        find.byType(AlertDialog),
        findsNothing,
        reason: 'S-27823: a cancelled pick opens no dialog',
      );
      expect(
        find.byType(SnackBar),
        findsNothing,
        reason: 'S-27823: a cancelled pick shows no message',
      );
      expect(
        restoredCalls,
        0,
        reason: 'S-27823: a cancelled pick restores nothing',
      );
    });

    testWidgets(
      'S-27824 a picked text that is not a backup shows the reason, opens no dialog and changes nothing',
      (WidgetTester tester) async {
        final repo = MockWorkoutRepository();
        await repo.initialize();
        final settings = await makeSettingsWith(repo);
        final service = await makeService(repo);
        final gateway = FakeBackupFileGateway()
          ..pick = () async => 'definitely not a backup';
        var restoredCalls = 0;

        await pumpSettings(
          tester,
          settingsState: settings,
          service: service,
          gateway: gateway,
          onRestored: () => restoredCalls++,
        );

        final sessionIdsBefore = {
          for (final session in await repo.getAllSessions()) session.id,
        };

        await tester.tap(find.byKey(const Key('data-import-row')));
        await tester.pump();

        expect(
          find.text('This is not an OmniTrain backup file.'),
          findsOneWidget,
          reason: 'S-27824: the refusal reason shows as an error message',
        );
        expect(
          find.byType(AlertDialog),
          findsNothing,
          reason: 'S-27824: no confirmation dialog opens for an invalid file',
        );
        expect(
          {for (final session in await repo.getAllSessions()) session.id},
          sessionIdsBefore,
          reason: 'S-27824: an invalid file leaves the store unchanged',
        );
        expect(
          restoredCalls,
          0,
          reason: 'S-27824: an invalid file never restores',
        );
      },
    );

    testWidgets(
      'S-27835 a backup from a newer build shows the newer-app reason and restores nothing',
      (WidgetTester tester) async {
        final repoA = MockWorkoutRepository();
        await repoA.initialize();
        final newerText = await backupTextFromNewerBuild(
          await backupTextFrom(repoA),
        );
        final repo = MockWorkoutRepository();
        await repo.initialize();
        final settings = await makeSettingsWith(repo);
        final held = HeldRestoreService(
          repo,
          const AppVersionInfo(version: '0.0.0', build: '0'),
        );
        final gateway = FakeBackupFileGateway()..pick = () async => newerText;
        var restoredCalls = 0;

        await pumpSettings(
          tester,
          settingsState: settings,
          service: held,
          gateway: gateway,
          onRestored: () => restoredCalls++,
        );

        final sessionIdsBefore = {
          for (final session in await repo.getAllSessions()) session.id,
        };

        await tester.tap(find.byKey(const Key('data-import-row')));
        await tester.pump();

        expect(
          find.text(BackupService.newerAppMessage),
          findsOneWidget,
          reason: 'S-27835: the newer-app reason shows as an error message',
        );
        expect(
          find.byType(AlertDialog),
          findsNothing,
          reason: 'S-27835: no confirmation dialog opens for a newer backup',
        );
        expect(
          held.restoreCalls,
          0,
          reason: 'S-27835: the restore is never reached',
        );
        expect(
          {for (final session in await repo.getAllSessions()) session.id},
          sessionIdsBefore,
          reason: 'S-27835: a newer backup leaves the store unchanged',
        );
        expect(
          restoredCalls,
          0,
          reason: 'S-27835: a newer backup never restores',
        );
      },
    );

    testWidgets(
      'S-27833 the confirmation body names the file\'s date and counts, plural and singular',
      (WidgetTester tester) async {
        final repoA = MockWorkoutRepository();
        await repoA.initialize();
        final many = await backupTextWithCounts(
          repoA,
          sessionCount: 142,
          routineCount: 6,
        );
        final one = await backupTextWithCounts(
          repoA,
          sessionCount: 1,
          routineCount: 1,
        );
        final repo = MockWorkoutRepository();
        await repo.initialize();
        final settings = await makeSettingsWith(repo);
        final service = await makeService(repo);
        var pickedText = many;
        final gateway = FakeBackupFileGateway()..pick = () async => pickedText;

        await pumpSettings(
          tester,
          settingsState: settings,
          service: service,
          gateway: gateway,
        );

        await tester.tap(find.byKey(const Key('data-import-row')));
        await tester.pumpAndSettle();

        expect(
          find.text('Replace all data?'),
          findsOneWidget,
          reason: 'S-27833: the confirmation dialog opens',
        );
        expect(
          find.text(
            'This replaces everything on this phone with the backup from '
            '19 Nov 2026: 142 workouts, 6 routines. Your current data is not '
            'kept. This cannot be undone.',
          ),
          findsOneWidget,
          reason: 'S-27833: the body reads the file\'s date and counts exactly',
        );

        // Cancel, then read the singular wording for a 1-workout file.
        await tester.tap(find.byKey(const Key('data-import-cancel')));
        await tester.pumpAndSettle();
        pickedText = one;
        await tester.tap(find.byKey(const Key('data-import-row')));
        await tester.pumpAndSettle();
        expect(
          find.text(
            'This replaces everything on this phone with the backup from '
            '19 Nov 2026: 1 workout, 1 routine. Your current data is not '
            'kept. This cannot be undone.',
          ),
          findsOneWidget,
          reason: 'S-27833: one workout and one routine read in the singular',
        );
      },
    );

    testWidgets(
      'S-27825 Cancel and a barrier tap restore nothing; Replace restores the file\'s data',
      (WidgetTester tester) async {
        final repoA = MockWorkoutRepository();
        await repoA.initialize();
        final text = await backupTextFrom(repoA);
        final repo = MockWorkoutRepository();
        await repo.initialize();
        final settings = await makeSettingsWith(repo);
        final service = await makeService(repo);
        final gateway = FakeBackupFileGateway()..pick = () async => text;
        var restoredCalls = 0;

        await pumpSettings(
          tester,
          settingsState: settings,
          service: service,
          gateway: gateway,
          onRestored: () => restoredCalls++,
        );

        final sessionIdsBefore = {
          for (final session in await repo.getAllSessions()) session.id,
        };

        // Cancel.
        await tester.tap(find.byKey(const Key('data-import-row')));
        await tester.pumpAndSettle();
        expect(
          find.text('Replace all data?'),
          findsOneWidget,
          reason: 'S-27825: a valid backup shows the confirmation',
        );
        await tester.tap(find.byKey(const Key('data-import-cancel')));
        await tester.pumpAndSettle();
        expect(
          find.byType(AlertDialog),
          findsNothing,
          reason: 'S-27825: Cancel closes the dialog',
        );
        expect(
          {for (final session in await repo.getAllSessions()) session.id},
          sessionIdsBefore,
          reason: 'S-27825: Cancel leaves the store unchanged',
        );
        expect(restoredCalls, 0, reason: 'S-27825: Cancel never restores');

        // A barrier tap counts as Cancel too.
        await tester.tap(find.byKey(const Key('data-import-row')));
        await tester.pumpAndSettle();
        await tester.tapAt(const Offset(5, 5));
        await tester.pumpAndSettle();
        expect(
          find.byType(AlertDialog),
          findsNothing,
          reason: 'S-27825: a barrier tap closes the dialog',
        );
        expect(
          {for (final session in await repo.getAllSessions()) session.id},
          sessionIdsBefore,
          reason: 'S-27825: a barrier tap leaves the store unchanged',
        );
        expect(
          restoredCalls,
          0,
          reason: 'S-27825: a barrier tap never restores',
        );

        // Replace restores the file's data into this phone's store.
        await tester.tap(find.byKey(const Key('data-import-row')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('data-import-confirm')));
        await tester.pumpAndSettle();

        expect(
          {for (final session in await repo.getAllSessions()) session.id},
          {'b-sess-a'},
          reason: 'S-27825: Replace stores the backup\'s sessions',
        );
        expect(
          {for (final template in await repo.getTemplates()) template.id},
          {'b-tmpl-a'},
          reason: 'S-27825: Replace stores the backup\'s routines',
        );
        expect(
          await repo.getPreferenceString('app_theme'),
          'x',
          reason: 'S-27825: Replace carries the backup\'s preferences',
        );
        expect(
          restoredCalls,
          1,
          reason: 'S-27825: a restored import reports once',
        );
      },
    );

    testWidgets(
      'S-27826 a restored import reports once, after the data changed',
      (WidgetTester tester) async {
        final repoA = MockWorkoutRepository();
        await repoA.initialize();
        final text = await backupTextFrom(repoA);
        final repo = MockWorkoutRepository();
        await repo.initialize();
        final settings = await makeSettingsWith(repo);
        final service = await makeService(repo);
        final gateway = FakeBackupFileGateway()..pick = () async => text;
        var restoredCalls = 0;
        Set<String>? idsAtReport;

        await pumpSettings(
          tester,
          settingsState: settings,
          service: service,
          gateway: gateway,
          onRestored: () {
            restoredCalls++;
            unawaited(
              repo.getAllSessions().then(
                (sessions) =>
                    idsAtReport = {for (final session in sessions) session.id},
              ),
            );
          },
        );

        await tester.tap(find.byKey(const Key('data-import-row')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('data-import-confirm')));
        await tester.pumpAndSettle();

        expect(
          restoredCalls,
          1,
          reason: 'S-27826: a restored import reports exactly once',
        );
        expect(
          idsAtReport,
          {'b-sess-a'},
          reason: 'S-27826: the report lands only after the data changed',
        );
        expect(
          {for (final session in await repo.getAllSessions()) session.id},
          {'b-sess-a'},
          reason: 'S-27826: the store holds the backup\'s data',
        );
      },
    );

    testWidgets(
      'S-27826 a running workout refuses the restore with zero reports',
      (WidgetTester tester) async {
        final repoA = MockWorkoutRepository();
        await repoA.initialize();
        final text = await backupTextFrom(repoA);
        final repo = MockWorkoutRepository();
        await repo.initialize();
        await seedRunningWorkout(repo);
        final settings = await makeSettingsWith(repo);
        final service = await makeService(repo);
        final gateway = FakeBackupFileGateway()..pick = () async => text;
        var restoredCalls = 0;

        await pumpSettings(
          tester,
          settingsState: settings,
          service: service,
          gateway: gateway,
          onRestored: () => restoredCalls++,
        );

        await tester.tap(find.byKey(const Key('data-import-row')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('data-import-confirm')));
        await tester.pumpAndSettle();

        expect(
          find.text(BackupService.runningWorkoutMessage),
          findsOneWidget,
          reason: 'S-27826: the refusal reason shows as an error message',
        );
        expect(
          restoredCalls,
          0,
          reason: 'S-27826: a refused restore never reports',
        );
        expect(
          {for (final session in await repo.getAllSessions()) session.id},
          {'b-running'},
          reason: 'S-27826: a refused restore leaves the store unchanged',
        );
      },
    );

    testWidgets(
      'S-27827 the restore holds the blocking progress and blocks re-entry until it resolves',
      (WidgetTester tester) async {
        final repoA = MockWorkoutRepository();
        await repoA.initialize();
        final text = await backupTextFrom(repoA);
        final repo = MockWorkoutRepository();
        await repo.initialize();
        final settings = await makeSettingsWith(repo);
        final held = HeldRestoreService(
          repo,
          const AppVersionInfo(version: '0.0.0', build: '0'),
        );
        final gateway = FakeBackupFileGateway()..pick = () async => text;
        var restoredCalls = 0;

        await pumpSettings(
          tester,
          settingsState: settings,
          service: held,
          gateway: gateway,
          onRestored: () => restoredCalls++,
        );

        await tester.tap(find.byKey(const Key('data-import-row')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('data-import-confirm')));
        await tester.pump();

        expect(
          find.byType(CircularProgressIndicator),
          findsOneWidget,
          reason: 'S-27827: the blocking progress shows while the restore runs',
        );
        expect(
          held.restoreCalls,
          1,
          reason: 'S-27827: one confirm starts exactly one restore',
        );

        // The progress is not barrier-dismissible.
        await tester.tapAt(const Offset(5, 5));
        await tester.pump();
        expect(
          find.byType(CircularProgressIndicator),
          findsOneWidget,
          reason: 'S-27827: a barrier tap does not dismiss the progress',
        );

        // A second import tap sits behind the modal barrier and starts nothing.
        await tester.tap(
          find.byKey(const Key('data-import-row')),
          warnIfMissed: false,
        );
        await tester.pump();
        expect(
          held.restoreCalls,
          1,
          reason: 'S-27827: the held restore is not started twice',
        );
        expect(
          gateway.pickCalls,
          hasLength(1),
          reason: 'S-27827: the second import tap never reaches the picker',
        );

        held.hold.complete(const BackupRestoreResult.restored());
        await tester.pumpAndSettle();

        expect(
          find.byType(CircularProgressIndicator),
          findsNothing,
          reason: 'S-27827: the progress closes when the restore resolves',
        );
        expect(
          restoredCalls,
          1,
          reason: 'S-27827: the resolved restore reports once',
        );
      },
    );

    testWidgets(
      'S-27827 a restore that resolves refused shows the reason with no report',
      (WidgetTester tester) async {
        final repoA = MockWorkoutRepository();
        await repoA.initialize();
        final text = await backupTextFrom(repoA);
        final repo = MockWorkoutRepository();
        await repo.initialize();
        final settings = await makeSettingsWith(repo);
        final held = HeldRestoreService(
          repo,
          const AppVersionInfo(version: '0.0.0', build: '0'),
        );
        final gateway = FakeBackupFileGateway()..pick = () async => text;
        var restoredCalls = 0;

        await pumpSettings(
          tester,
          settingsState: settings,
          service: held,
          gateway: gateway,
          onRestored: () => restoredCalls++,
        );

        await tester.tap(find.byKey(const Key('data-import-row')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('data-import-confirm')));
        await tester.pump();

        held.hold.complete(
          const BackupRestoreResult.refused(BackupService.failedMessage),
        );
        await tester.pumpAndSettle();

        expect(
          find.text(BackupService.failedMessage),
          findsOneWidget,
          reason: 'S-27827: a refused restore shows its reason',
        );
        expect(
          restoredCalls,
          0,
          reason: 'S-27827: a refused restore never reports',
        );
        expect(
          find.byType(CircularProgressIndicator),
          findsNothing,
          reason: 'S-27827: the progress closes on a refusal',
        );
      },
    );

    testWidgets(
      'S-27824b a picker that throws shows the open-failure message and no dialog',
      (WidgetTester tester) async {
        final repo = MockWorkoutRepository();
        await repo.initialize();
        final settings = await makeSettingsWith(repo);
        final service = await makeService(repo);
        final gateway = FakeBackupFileGateway()
          ..pick = () async => throw StateError('no file picker');
        var restoredCalls = 0;

        await pumpSettings(
          tester,
          settingsState: settings,
          service: service,
          gateway: gateway,
          onRestored: () => restoredCalls++,
        );

        await tester.tap(find.byKey(const Key('data-import-row')));
        await tester.pump();

        expect(
          find.text('Could not open the file. Try again.'),
          findsOneWidget,
          reason: 'S-27824b: a throwing picker shows the open-failure message',
        );
        expect(
          find.byType(AlertDialog),
          findsNothing,
          reason: 'S-27824b: the failure is a message, not a dialog',
        );
        expect(
          restoredCalls,
          0,
          reason: 'S-27824b: a throwing picker never restores',
        );
      },
    );

    testWidgets(
      'S-27827b the import handler ignores a second call while a restore runs',
      (WidgetTester tester) async {
        final repoA = MockWorkoutRepository();
        await repoA.initialize();
        final text = await backupTextFrom(repoA);
        final repo = MockWorkoutRepository();
        await repo.initialize();
        final settings = await makeSettingsWith(repo);
        final held = HeldRestoreService(
          repo,
          const AppVersionInfo(version: '0.0.0', build: '0'),
        );
        final gateway = FakeBackupFileGateway()..pick = () async => text;
        var restoredCalls = 0;

        await pumpSettings(
          tester,
          settingsState: settings,
          service: held,
          gateway: gateway,
          onRestored: () => restoredCalls++,
        );

        await tester.tap(find.byKey(const Key('data-import-row')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('data-import-confirm')));
        await tester.pump();
        // Let the first confirmation dialog's exit transition finish, so a
        // second dialog opened by a re-entry would be the only one visible.
        await tester.pump(const Duration(milliseconds: 400));

        expect(
          find.byType(CircularProgressIndicator),
          findsOneWidget,
          reason: 'S-27827b: the restore is held with the progress showing',
        );

        // The modal barrier blocks a real second tap; invoke the row's own
        // handler directly to reach the in-flight guard.
        tester
            .widget<InkWell>(
              find.descendant(
                of: find.byKey(const Key('data-import-row')),
                matching: find.byType(InkWell),
              ),
            )
            .onTap!();
        await tester.pump();

        expect(
          gateway.pickCalls,
          hasLength(1),
          reason: 'S-27827b: the in-flight import never reopens the picker',
        );
        expect(
          find.byType(AlertDialog),
          findsNothing,
          reason: 'S-27827b: no second confirmation dialog opens',
        );
        expect(
          held.restoreCalls,
          1,
          reason: 'S-27827b: the held restore is not started twice',
        );

        held.hold.complete(const BackupRestoreResult.restored());
        await tester.pumpAndSettle();

        expect(
          restoredCalls,
          1,
          reason: 'S-27827b: the resolved restore reports once',
        );
      },
    );

    testWidgets(
      'S-27826b a restore that throws shows the failure message and reports nothing',
      (WidgetTester tester) async {
        final repoA = MockWorkoutRepository();
        await repoA.initialize();
        final text = await backupTextFrom(repoA);
        final repo = MockWorkoutRepository();
        await repo.initialize();
        final settings = await makeSettingsWith(repo);
        final throwing = ThrowingRestoreService(
          repo,
          const AppVersionInfo(version: '0.0.0', build: '0'),
        );
        final gateway = FakeBackupFileGateway()..pick = () async => text;
        var restoredCalls = 0;

        await pumpSettings(
          tester,
          settingsState: settings,
          service: throwing,
          gateway: gateway,
          onRestored: () => restoredCalls++,
        );

        await tester.tap(find.byKey(const Key('data-import-row')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('data-import-confirm')));
        await tester.pumpAndSettle();

        expect(
          find.byType(CircularProgressIndicator),
          findsNothing,
          reason: 'S-27826b: the progress closes when the restore throws',
        );
        expect(
          find.text(BackupService.failedMessage),
          findsOneWidget,
          reason: 'S-27826b: a thrown restore shows the failure message',
        );
        expect(
          restoredCalls,
          0,
          reason: 'S-27826b: a thrown restore never reports',
        );
        expect(
          tester.takeException(),
          isNull,
          reason: 'S-27826b: the throw is contained, not raised to the zone',
        );
        expect(
          await repo.getAllSessions(),
          isEmpty,
          reason: 'S-27826b: the store is unchanged after a thrown restore',
        );
      },
    );

    testWidgets(
      'S-27823b a screen that is gone while the picker is open does nothing when it returns',
      (WidgetTester tester) async {
        final repoA = MockWorkoutRepository();
        await repoA.initialize();
        final text = await backupTextFrom(repoA);
        final repo = MockWorkoutRepository();
        await repo.initialize();
        final settings = await makeSettingsWith(repo);
        final service = await makeService(repo);
        final hold = Completer<String?>();
        final gateway = FakeBackupFileGateway()..pick = () => hold.future;
        var restoredCalls = 0;

        await pumpSettings(
          tester,
          settingsState: settings,
          service: service,
          gateway: gateway,
          onRestored: () => restoredCalls++,
        );

        await tester.tap(find.byKey(const Key('data-import-row')));
        await tester.pump();

        // Replace the whole tree while the picker future is still pending.
        await tester.pumpWidget(const SizedBox());
        await tester.pump();

        hold.complete(text);
        await tester.pump();

        expect(
          tester.takeException(),
          isNull,
          reason: 'S-27823b: the gone screen never touches a disposed context',
        );
        expect(
          find.byType(AlertDialog),
          findsNothing,
          reason: 'S-27823b: a gone screen opens no confirmation dialog',
        );
        expect(
          restoredCalls,
          0,
          reason: 'S-27823b: a gone screen never restores',
        );
      },
    );
  });
}
