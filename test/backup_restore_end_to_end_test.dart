import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/app/startup_root.dart';
import 'package:omnitrain/core/models/app_version_info.dart';
import 'package:omnitrain/core/services/backup_file_gateway.dart';
import 'package:omnitrain/core/services/backup_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/settings/settings_screen.dart';
import 'package:omnitrain/state/settings/settings_state.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/fake_rest_notification_service.dart';
import 'helpers/fake_timer_alert_service.dart';
import 'helpers/repository_harness.dart';

/// A [BackupFileGateway] that records the picker calls and returns the text a
/// test sets on [pick] (copied from `test/settings_data_section_test.dart`).
class FakeBackupFileGateway implements BackupFileGateway {
  final List<({String fileName, String text})> shares = [];
  final List<void> pickCalls = [];

  Future<bool> Function(String, String)? shareResult;
  Object? shareThrows;
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

/// Backs up the source repository A: one finished session, one routine and
/// the two preferences a restore must carry, one of them
/// `onboarding_complete` = false (plan 278b S-27829, S-27836).
Future<String> backupTextFrom(MockWorkoutRepository repo) async {
  await seedSession(repo, sessionId: 'a-sess');
  await repo.createTemplate(
    WorkoutTemplate(
      id: 'a-tmpl',
      name: 'Push Day',
      createdAtMs: fixtureStart,
      updatedAtMs: fixtureStart,
    ),
  );
  await repo.setPreferenceString('app_theme', 'theme-a');
  await repo.setPreferenceBool('onboarding_complete', false);
  return (await makeService(repo)).exportToText();
}

/// Data on the target repository B that differs from A's in every row
/// (S-27829): another finished session, another routine, onboarding done
/// and a different theme.
Future<void> seedOtherData(MockWorkoutRepository repo) async {
  await seedSession(repo, sessionId: 'b-sess');
  await repo.createTemplate(
    WorkoutTemplate(
      id: 'b-tmpl',
      name: 'Leg Day',
      createdAtMs: fixtureStart,
      updatedAtMs: fixtureStart,
    ),
  );
  await repo.setPreferenceString('app_theme', 'theme-b');
  await repo.setPreferenceBool('onboarding_complete', true);
}

/// An unfinished, non-rolling session: the running workout that refuses a
/// restore (S-27829b). Copied from `test/settings_data_section_test.dart`.
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

Future<BackupService> makeService(MockWorkoutRepository repo) async =>
    BackupService(repo, const AppVersionInfo(version: '0.0.0', build: '0'));

Future<SettingsState> makeSettingsWith(MockWorkoutRepository repo) async {
  final state = SettingsState(repo, fakePreferencesService());
  await state.initialize();
  return state;
}

/// The widget a successful startup runner mounts: the Settings screen wired
/// the way `HomeScreen` wires it — the `onDataRestored` callback comes from
/// the `AppRestart` the `StartupRoot` puts above the running app (D-27824).
class _Running extends StatelessWidget {
  const _Running({
    required this.settingsState,
    required this.backupService,
    required this.backupFileGateway,
  });

  final SettingsState settingsState;
  final BackupService backupService;
  final BackupFileGateway backupFileGateway;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Builder(
        builder: (context) => SettingsScreen(
          settingsState: settingsState,
          timerAlertService: FakeTimerAlertService(),
          restNotificationService: FakeRestNotificationService(),
          appVersionInfo: const AppVersionInfo(version: '0.0.0', build: '0'),
          backupService: backupService,
          backupFileGateway: backupFileGateway,
          onDataRestored: AppRestart.maybeOf(context)?.showRestartRequired,
        ),
      ),
    );
  }
}

/// Pumps the whole chain — `StartupRoot` → runner → `_Running` → Settings —
/// on a tall surface. Everything is seeded before the pump; the runner mounts
/// a Settings screen over repository B whose picker returns [pickedText].
/// `StartupRoot`'s other params use their defaults.
Future<void> pumpStartupRoot(
  WidgetTester tester, {
  required MockWorkoutRepository repoB,
  required String pickedText,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(600, 3000);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final settingsState = await makeSettingsWith(repoB);
  final service = await makeService(repoB);
  final gateway = FakeBackupFileGateway()..pick = () async => pickedText;

  await tester.pumpWidget(
    StartupRoot(
      startupRunner: () async => _Running(
        settingsState: settingsState,
        backupService: service,
        backupFileGateway: gateway,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Drives the import flow up to and including the confirmation tap.
Future<void> importAndConfirm(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('data-import-row')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('data-import-confirm')));
  await tester.pumpAndSettle();
}

void main() {
  group('Backup restore end to end', () {
    testWidgets(
      'S-27829 the whole chain: repo A exports, repo B restores through the Settings flow inside StartupRoot',
      (WidgetTester tester) async {
        final repoA = MockWorkoutRepository();
        await repoA.initialize();
        final backupText = await backupTextFrom(repoA);

        final repoB = MockWorkoutRepository();
        await repoB.initialize();
        await seedOtherData(repoB);

        await pumpStartupRoot(tester, repoB: repoB, pickedText: backupText);

        expect(
          find.byType(SettingsScreen),
          findsOneWidget,
          reason: 'S-27829: the startup runner mounts the Settings screen',
        );

        await importAndConfirm(tester);

        expect(
          find.byType(SettingsScreen),
          findsNothing,
          reason: 'S-27829: the Settings screen is gone after the restore',
        );
        expect(
          find.byKey(const Key('restore-complete-title')),
          findsOneWidget,
          reason:
              'S-27829: the app was replaced by the Restore-complete screen',
        );
        expect(
          find.text('Restore complete'),
          findsOneWidget,
          reason: 'S-27829: the title copy reads "Restore complete"',
        );
        expect(
          {for (final session in await repoB.getAllSessions()) session.id},
          {for (final session in await repoA.getAllSessions()) session.id},
          reason: 'S-27829: B stores A\'s sessions',
        );
        expect(
          {for (final template in await repoB.getTemplates()) template.id},
          {for (final template in await repoA.getTemplates()) template.id},
          reason: 'S-27829: B stores A\'s routines',
        );
        expect(
          await repoB.getPreferenceString('app_theme'),
          'theme-a',
          reason: 'S-27829: B stores A\'s theme preference',
        );
      },
    );

    testWidgets(
      'S-27836 the next launch\'s flag read sees the restored onboarding_complete and data version',
      (WidgetTester tester) async {
        final repoA = MockWorkoutRepository();
        await repoA.initialize();
        final backupText = await backupTextFrom(repoA);

        final repoB = MockWorkoutRepository();
        await repoB.initialize();
        await seedOtherData(repoB);

        await pumpStartupRoot(tester, repoB: repoB, pickedText: backupText);

        await importAndConfirm(tester);

        expect(
          find.byKey(const Key('restore-complete-title')),
          findsOneWidget,
          reason: 'S-27836: the restore completed before the flag read',
        );
        expect(
          await repoB.getPreferenceBool('onboarding_complete'),
          isFalse,
          reason:
              'S-27836: B holds A\'s false onboarding_complete — the value '
              'runStartup reads at the next launch',
        );
        expect(
          await repoB.getDataVersion(),
          await repoA.getDataVersion(),
          reason: 'S-27836: B carries A\'s data version',
        );
      },
    );

    testWidgets(
      'S-27829b a refused restore (running workout) leaves the app on Settings with B unchanged',
      (WidgetTester tester) async {
        final repoA = MockWorkoutRepository();
        await repoA.initialize();
        final backupText = await backupTextFrom(repoA);

        final repoB = MockWorkoutRepository();
        await repoB.initialize();
        await seedOtherData(repoB);
        await seedRunningWorkout(repoB);

        await pumpStartupRoot(tester, repoB: repoB, pickedText: backupText);

        await importAndConfirm(tester);

        expect(
          find.byType(SettingsScreen),
          findsOneWidget,
          reason: 'S-27829b: the Settings screen is still showing',
        );
        expect(
          find.text(BackupService.runningWorkoutMessage),
          findsOneWidget,
          reason: 'S-27829b: the refusal message shows',
        );
        expect(
          find.byKey(const Key('restore-complete-title')),
          findsNothing,
          reason: 'S-27829b: no Restore-complete screen appears',
        );
        expect(
          {for (final session in await repoB.getAllSessions()) session.id},
          {'b-sess', 'b-running'},
          reason: 'S-27829b: B\'s sessions are unchanged',
        );
        expect(
          {for (final template in await repoB.getTemplates()) template.id},
          {'b-tmpl'},
          reason: 'S-27829b: B\'s routines are unchanged',
        );
        expect(
          await repoB.getPreferenceString('app_theme'),
          'theme-b',
          reason: 'S-27829b: B\'s theme preference is unchanged',
        );
        expect(
          await repoB.getPreferenceBool('onboarding_complete'),
          isTrue,
          reason: 'S-27829b: B\'s onboarding flag is unchanged',
        );
      },
    );

    testWidgets(
      'S-27829c Cancel at the confirmation keeps Settings and B unchanged',
      (WidgetTester tester) async {
        final repoA = MockWorkoutRepository();
        await repoA.initialize();
        final backupText = await backupTextFrom(repoA);

        final repoB = MockWorkoutRepository();
        await repoB.initialize();
        await seedOtherData(repoB);

        await pumpStartupRoot(tester, repoB: repoB, pickedText: backupText);

        await tester.tap(find.byKey(const Key('data-import-row')));
        await tester.pumpAndSettle();
        expect(
          find.text('Replace all data?'),
          findsOneWidget,
          reason: 'S-27829c: the confirmation dialog opens for a valid backup',
        );
        await tester.tap(find.byKey(const Key('data-import-cancel')));
        await tester.pumpAndSettle();

        expect(
          find.byType(AlertDialog),
          findsNothing,
          reason: 'S-27829c: Cancel closes the confirmation dialog',
        );
        expect(
          find.byType(SettingsScreen),
          findsOneWidget,
          reason: 'S-27829c: the Settings screen stays',
        );
        expect(
          find.byKey(const Key('restore-complete-title')),
          findsNothing,
          reason: 'S-27829c: no Restore-complete screen appears',
        );
        expect(
          {for (final session in await repoB.getAllSessions()) session.id},
          {'b-sess'},
          reason: 'S-27829c: B\'s sessions are unchanged',
        );
        expect(
          {for (final template in await repoB.getTemplates()) template.id},
          {'b-tmpl'},
          reason: 'S-27829c: B\'s routines are unchanged',
        );
        expect(
          await repoB.getPreferenceString('app_theme'),
          'theme-b',
          reason: 'S-27829c: B\'s theme preference is unchanged',
        );
        expect(
          await repoB.getPreferenceBool('onboarding_complete'),
          isTrue,
          reason: 'S-27829c: B\'s onboarding flag is unchanged',
        );
      },
    );
  });
}
