import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'app.dart';
import 'app/startup_root.dart';
import 'core/models/app_version_info.dart';
import 'core/services/bundled_catalog_source.dart';
import 'core/services/catalog_refresh_service.dart';
import 'core/services/exercise_library_service.dart';
import 'core/services/health_platform_gateway.dart';
import 'core/services/health_platform_service.dart';
import 'core/services/health_sync_service.dart';
import 'core/services/image_storage_service.dart';
import 'core/services/preferences_service.dart';
import 'core/services/routine_session_service.dart';
import 'core/services/session_summary_service.dart';
import 'core/services/startup_failure_diagnostic_writer.dart';
import 'data/repositories/hive_workout_repository.dart';
import 'data/repositories/workout_repository.dart';
import 'state/workout/workout_state.dart';
import 'state/home/home_state.dart';
import 'state/routine/routine_state.dart';
import 'state/calendar/calendar_state.dart';
import 'state/period/period_state.dart';
import 'state/profile/profile_state.dart';
import 'core/constants/health_constants.dart';
import 'core/constants/omni_theme.dart';
import 'core/constants/profile_measurements.dart';
import 'state/settings/settings_state.dart';
import 'state/nutrition_state.dart';
import 'state/food_library_state.dart';
import 'state/nutrition/nutrition_primer_state.dart';
import 'state/stats/stats_primer_state.dart';
import 'state/exercise/exercise_library_state.dart';
import 'state/watch/watch_sync_wiring.dart';
import 'core/utils/timer_alert_service.dart';
import 'core/services/crash_reporting_service.dart';
import 'core/utils/rest_notification_service.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

final _startupDiagnosticWriter = StartupFailureDiagnosticWriter.create();

/// App-lifetime listener driving the platform health read pipeline on
/// every foreground. Held at library scope so nothing collects it; a
/// retry startup pass disposes and replaces it so reads never run
/// through a stale service graph.
AppLifecycleListener? _healthLifecycleListener;

typedef StartupRepositoryFactory = Future<WorkoutRepository> Function();
typedef StartupPreferencesServiceFactory = PreferencesService Function();
typedef StartupTimerAlertServiceFactory = TimerAlertService Function();
typedef StartupRestNotificationServiceFactory =
    RestNotificationService Function();
typedef StartupImageStorageServiceFactory =
    Future<ImageStorageService?> Function();
typedef StartupHealthPlatformServiceFactory = HealthPlatformService Function();
typedef StartupAppVersionInfoLoader = Future<AppVersionInfo> Function();
typedef StartupNonFatalIssueHandler =
    Future<void> Function(Object error, StackTrace stackTrace);

class StartupNotificationInitializationError implements Exception {
  StartupNotificationInitializationError(this.cause);

  final Object cause;

  @override
  String toString() {
    return 'Non-fatal startup notification initialization failure: $cause';
  }
}

/// Build the app's storage engine.
///
/// One repository implementation, `HiveWorkoutRepository`, services every
/// platform — web, iOS, and Android. Hive-backed persistence is web-safe
/// and works natively too, so there is no platform-branching repository
/// choice. Adding a new platform later will reuse this same constructor.
Future<WorkoutRepository> _createRepository() async {
  return HiveWorkoutRepository();
}

/// Imports body weight from the platform health store and refreshes the
/// Profile measurement view so the imported rows are visible without a
/// manual reload. Never throws — [HealthSyncService.syncOnForeground]
/// reports failure as an empty result.
@visibleForTesting
Future<void> syncHealthBodyWeight(
  HealthSyncService healthSync,
  ProfileState profileState,
) async {
  final imported = await healthSync.syncOnForeground();
  if (imported.isEmpty) return;
  await profileState.loadLatestMeasurements([
    ProfileMeasurements.bodyweight.type,
  ]);
}

/// Builds the app-lifetime listener that drives [syncHealthBodyWeight] on
/// every foreground. Exposed so the read trigger can be exercised in a test
/// through the same construction the app uses.
@visibleForTesting
AppLifecycleListener createHealthLifecycleListener(
  HealthSyncService healthSync,
  ProfileState profileState,
) {
  return AppLifecycleListener(
    onResume: () => unawaited(syncHealthBodyWeight(healthSync, profileState)),
  );
}

Future<void> _initializeLocalTimezone() async {
  tzdata.initializeTimeZones();
  if (kIsWeb) {
    return;
  }

  try {
    final timezoneName = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(timezoneName));
  } catch (_) {
    // Keep tz.local as the default fallback when platform timezone lookup fails.
  }
}

Future<void> _reportNonFatalStartupIssue(
  Object error,
  StackTrace stackTrace,
) async {
  debugPrint('OmniTrain startup non-fatal issue: $error');
  debugPrintStack(stackTrace: stackTrace);

  try {
    await CrashReportingService.recordError(
      error,
      stackTrace: stackTrace,
      errorContext: 'startup.notificationInitialization',
    );
  } catch (reportError, reportStack) {
    debugPrint('Startup non-fatal reporter hook failed: $reportError');
    debugPrintStack(stackTrace: reportStack);
  }

  await _startupDiagnosticWriter.writeLatestFailure(error, stackTrace);
}

Future<RestNotificationService> _initializeRestNotificationServiceSafely({
  required StartupRestNotificationServiceFactory createRestNotificationService,
  required StartupNonFatalIssueHandler onNonFatalStartupIssue,
}) async {
  final restNotificationService = createRestNotificationService();
  try {
    await restNotificationService.initialize();
    return restNotificationService;
  } catch (error, stackTrace) {
    await onNonFatalStartupIssue(
      StartupNotificationInitializationError(error),
      stackTrace,
    );
    return RestNotificationService.noop();
  }
}

Future<AppVersionInfo> _loadAppVersionInfo() async {
  try {
    final packageInfo = await PackageInfo.fromPlatform();
    return AppVersionInfo(
      version: packageInfo.version,
      build: packageInfo.buildNumber,
    );
  } catch (e, st) {
    debugPrint('Failed to read PackageInfo: $e');
    debugPrintStack(stackTrace: st);
    return const AppVersionInfo(version: '0.0.0', build: '0');
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _initializeLocalTimezone();

  // Crash reporting bootstrap. Release builds only — debug and
  // profile builds skip the install path entirely so the debug overlay
  // continues to surface errors directly. The DSN is injected via
  // `--dart-define` at release-build time; on a developer machine the
  // empty string simply produces a no-op Sentry init that the wrapper
  // logs once via debugPrint and continues. The wrapper itself never
  // blocks startup: a missing DSN, a Sentry outage, or a malformed
  // payload drops the event instead of crashing the launch.
  const sentryDsn = String.fromEnvironment('SENTRY_DSN', defaultValue: '');
  // Resolve the installed app version once via package_info_plus so
  // every emitted event carries the same canonical value. A plugin
  // failure (rare on supported platforms) falls back to "0.0.0" — the
  // reporting layer prefers a known-but-imprecise value over no value.
  // 'version-unavailable+0' is the designated fallback: it is greppable
  // in the Sentry dashboard and visibly not a real version string, so
  // it is distinguishable from a genuine build (unlike '0.0.0+0').
  var appVersion = 'version-unavailable+0';
  try {
    final pkg = await PackageInfo.fromPlatform();
    appVersion = '${pkg.version}+${pkg.buildNumber}';
  } catch (e, st) {
    debugPrint('Crash-reporting metadata: PackageInfo unavailable: $e');
    debugPrintStack(stackTrace: st);
  }
  await CrashReportingService.bootstrap(
    reporter: SentryCrashReporter(dsn: sentryDsn),
    // kReleaseMode is true only for `--release` builds. debug and
    // profile builds stay at `enabled: false` and install no handlers.
    enabled: kReleaseMode,
    buildMetadata: () => defaultDeviceMetadata(appVersion: appVersion),
  );

  runApp(StartupRoot(startupRunner: _runStartup));
}

/// One full pass through OmniTrain's startup work.
///
/// Builds the repository, hydrates every state object, and returns
/// the [MyApp] widget that should be mounted on success. Throws if
/// any step fails — [StartupRoot] catches the throw and re-runs
/// this routine when the user taps Retry. Every step is
/// intentionally re-executed on retry; no state is cached across
/// attempts because a partial init can leave state holders
/// holding stale references.
Future<Widget> _runStartup() async {
  return runStartup();
}

@visibleForTesting
Future<Widget> runStartup({
  StartupRepositoryFactory createRepository = _createRepository,
  StartupPreferencesServiceFactory createPreferencesService =
      PreferencesServiceImpl.new,
  StartupTimerAlertServiceFactory createTimerAlertService =
      TimerAlertService.new,
  StartupRestNotificationServiceFactory createRestNotificationService =
      RestNotificationService.new,
  StartupImageStorageServiceFactory? createImageStorageService,
  StartupHealthPlatformServiceFactory? createHealthPlatformGateway,
  StartupAppVersionInfoLoader loadAppVersionInfo = _loadAppVersionInfo,
  StartupNonFatalIssueHandler onNonFatalStartupIssue =
      _reportNonFatalStartupIssue,
}) async {
  // Initialize services
  final preferencesService = createPreferencesService();
  await preferencesService.init();

  // Initialize repository (injectable, can be swapped per environment)
  final repository = await createRepository();
  await repository.initialize();

  // Adopt the user's saved theme as soon as it is readable — before the
  // catalog refresh below, which can hit the network. `MyApp` sets this
  // again from `SettingsState`; doing it here only moves the moment
  // earlier, so the preparing screen renders in the user's palette
  // instead of flashing the default theme for the length of startup.
  OmniTheme.activeTheme = await SettingsState.readPersistedTheme(repository);

  // Reconcile the device's stored catalog against the bundled
  // catalog. Runs at app start (after repository.initialize, before
  // state construction) so every state class sees the post-refresh
  // catalog. Failures are logged but do NOT block app startup —
  // a transient I/O error will be retried on the next launch.
  final catalogRefresh = CatalogRefreshService(
    repository,
    const BundledCatalogSource(),
  );
  try {
    await catalogRefresh.refresh();
  } catch (e, st) {
    debugPrint('Catalog refresh failed (will retry next launch): $e');
    debugPrintStack(stackTrace: st);
  }

  // Check first-launch onboarding flag
  final onboardingComplete = await repository.getPreferenceBool(
    'onboarding_complete',
  );
  final showOnboarding = !onboardingComplete;

  // Native-only image storage helper (Phase 2 of the
  // image-persistence fix plan). Owns the managed directory
  // `<applicationDocumentsDirectory>/omni_images/` and is the
  // sole gate for the pick-and-store flow on profile avatars and
  // food photos. Construction resolves the documents directory
  // once at app start; the same instance is shared by every
  // state and screen that needs it (D-8).
  // On web, skip initialization as it's not supported there.
  final imageStorageServiceFactory =
      createImageStorageService ??
      () async => kIsWeb ? null : ImageStorageService.create();
  final imageStorageService = await imageStorageServiceFactory();

  // Platform health gateway (Apple Health / Health Connect). Self-selects
  // a no-op on web and desktop — see `health_platform_gateway.dart`.
  final healthPlatform =
      (createHealthPlatformGateway ?? createHealthPlatformService)();

  // Create state with repository
  final homeState = HomeState(repository);
  await homeState.init();
  final settingsState = SettingsState(
    repository,
    preferencesService,
    healthPlatform: healthPlatform,
  );
  await settingsState.initialize();
  final profileState = ProfileState(
    repository,
    imageStorage: imageStorageService,
  );

  final healthSyncService = HealthSyncService(
    platform: healthPlatform,
    repository: repository,
    isWriteEnabled: () =>
        settingsState.healthWriteWorkouts == HealthToggleState.on,
    isReadEnabled: () =>
        settingsState.healthReadBodyWeight == HealthToggleState.on,
  );

  // Foreground trigger for the health body-weight read. Reads never
  // prompt for permission, so this is safe to fire on every resume.
  _healthLifecycleListener?.dispose();
  _healthLifecycleListener = createHealthLifecycleListener(
    healthSyncService,
    profileState,
  );

  final routineState = RoutineState(repository);
  final calendarState = CalendarState(repository);
  final periodState = PeriodState(repository);
  final nutritionState = NutritionState(repository);
  await nutritionState.loadNutritionTarget();
  final foodLibraryState = FoodLibraryState(
    repository,
    imageStorage: imageStorageService,
  );
  // One-shot Daily Nutrition primer state. Hydrated eagerly
  // so the first home-strip tap consults the persisted
  // seen-flag from frame 1 (no flicker of the auto-show).
  final nutritionPrimerState = NutritionPrimerState(repository);
  await nutritionPrimerState.init();
  // One-shot Stats primer state. Hydrated eagerly, exactly like the
  // Nutrition primer, so the first Stats tap from Home consults the
  // persisted seen-flag from frame 1.
  final statsPrimerState = StatsPrimerState(repository);
  await statsPrimerState.init();
  final timerAlertService = createTimerAlertService();
  await timerAlertService.initialize();
  final restNotificationService =
      await _initializeRestNotificationServiceSafely(
        createRestNotificationService: createRestNotificationService,
        onNonFatalStartupIssue: onNonFatalStartupIssue,
      );

  // Create service with repository
  final routineSessionService = RoutineSessionService(repository);
  final sessionSummaryService = SessionSummaryService(repository);
  final exerciseLibraryService = ExerciseLibraryService(repository);

  // The watch graph, when this platform has a watch to talk to. Null on web,
  // desktop, and Android (the Wear OS client is a later plan), and null when the
  // transport cannot be set up — a wrist that is not there is not a reason to
  // refuse to start.
  final watchSync = await createWatchSync(
    repository: repository,
    nutritionState: nutritionState,
    foodLibraryState: foodLibraryState,
    settingsState: settingsState,
    // A wrist session that lands in history shows in the calendar's month.
    onHistoryChanged: calendarState.refresh,
    onFailure: (error, stackTrace) {
      debugPrint('Watch transport unavailable: $error');
      debugPrintStack(stackTrace: stackTrace);
    },
  );

  // Built after the watch graph: the graph's recovery handle is what lets an
  // Edit Session Discard keep a watch entry that arrived while the screen was
  // open (D-811).
  final workoutState = WorkoutState(
    repository,
    healthSync: healthSyncService,
    watchLateEntryRecovery: watchSync?.lateEntryRecovery,
  );

  // The session the wrist is running becomes this phone's own (D-2): the graph
  // adopts a snapshot into the state built just above, once the mirror has
  // reconciled it.
  watchSync?.adoption.bindWorkoutState(workoutState);
  // The phone's own session reaches the wrist by itself (D-75): the graph's one
  // push listens to the same state.
  watchSync?.autoPush.bindWorkoutState(workoutState);
  final exerciseLibraryState = ExerciseLibraryState(
    service: exerciseLibraryService,
    workoutState: workoutState,
  );

  // Build-metadata for the Settings footer.
  //
  // Source of truth = `pubspec.yaml`'s `version:` line, compiled into
  // the native bundle and surfaced at runtime via `package_info_plus`.
  // Reading once at startup is sufficient — the values are static for
  // the lifetime of the process. A plugin failure (rare on supported
  // platforms) falls back to a "0.0.0+0" placeholder so the footer
  // remains renderable while the app keeps running. We deliberately
  // do NOT bake any version literal into `lib/` — the placeholder
  // string lives in this catch block only, never reaches a widget.
  final appVersionInfo = await loadAppVersionInfo();

  return MyApp(
    repository: repository,
    showOnboarding: showOnboarding,
    workoutState: workoutState,
    homeState: homeState,
    routineState: routineState,
    routineSessionService: routineSessionService,
    sessionSummaryService: sessionSummaryService,
    calendarState: calendarState,
    periodState: periodState,
    profileState: profileState,
    settingsState: settingsState,
    nutritionState: nutritionState,
    foodLibraryState: foodLibraryState,
    nutritionPrimerState: nutritionPrimerState,
    statsPrimerState: statsPrimerState,
    exerciseLibraryState: exerciseLibraryState,
    timerAlertService: timerAlertService,
    restNotificationService: restNotificationService,
    appVersionInfo: appVersionInfo,
    // D-96: the phone asks the wrist for its session once per resume. Null
    // without a watch graph, so no observer is mounted at all.
    onWatchResume: watchSync?.sync,
  );
}
