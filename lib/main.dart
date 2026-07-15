import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'app.dart';
import 'app/startup_root.dart';
import 'core/models/app_version_info.dart';
import 'core/services/bundled_catalog_source.dart';
import 'core/services/catalog_refresh_service.dart';
import 'core/services/image_storage_service.dart';
import 'core/services/preferences_service.dart';
import 'core/services/routine_session_service.dart';
import 'core/services/session_summary_service.dart';
import 'data/repositories/hive_workout_repository.dart';
import 'data/repositories/workout_repository.dart';
import 'state/workout/workout_state.dart';
import 'state/home/home_state.dart';
import 'state/routine/routine_state.dart';
import 'state/calendar/calendar_state.dart';
import 'state/period/period_state.dart';
import 'state/profile/profile_state.dart';
import 'state/settings/settings_state.dart';
import 'state/nutrition_state.dart';
import 'state/food_library_state.dart';
import 'state/nutrition/nutrition_primer_state.dart';
import 'core/utils/timer_alert_service.dart';
import 'core/services/crash_reporting_service.dart';
import 'core/utils/rest_notification_service.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Build the app's storage engine.
///
/// One repository implementation, `HiveWorkoutRepository`, services every
/// platform — web, iOS, and Android. Hive-backed persistence is web-safe
/// and works natively too, so there is no platform-branching repository
/// choice. Adding a new platform later will reuse this same constructor.
Future<WorkoutRepository> _createRepository() async {
  return HiveWorkoutRepository();
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
  var appVersion = '0.0.0+0';
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
  // Initialize services
  final preferencesService = PreferencesServiceImpl();
  await preferencesService.init();

  // Initialize repository (injectable, can be swapped per environment)
  final repository = await _createRepository();
  await repository.initialize();

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
  final imageStorageService = kIsWeb
      ? null
      : await ImageStorageService.create();

  // Create state with repository
  final workoutState = WorkoutState(repository);
  final homeState = HomeState(repository);
  await homeState.init();
  final routineState = RoutineState(repository);
  final calendarState = CalendarState(repository);
  final periodState = PeriodState(repository);
  final profileState = ProfileState(
    repository,
    imageStorage: imageStorageService,
  );
  final settingsState = SettingsState(repository, preferencesService);
  await settingsState.initialize();
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
  final timerAlertService = TimerAlertService();
  await timerAlertService.initialize();
  final restNotificationService = RestNotificationService();
  await restNotificationService.initialize();

  // Create service with repository
  final routineSessionService = RoutineSessionService(repository);
  final sessionSummaryService = SessionSummaryService(repository);

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
  AppVersionInfo appVersionInfo;
  try {
    final packageInfo = await PackageInfo.fromPlatform();
    appVersionInfo = AppVersionInfo(
      version: packageInfo.version,
      build: packageInfo.buildNumber,
    );
  } catch (e, st) {
    debugPrint('Failed to read PackageInfo: $e');
    debugPrintStack(stackTrace: st);
    appVersionInfo = const AppVersionInfo(version: '0.0.0', build: '0');
  }

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
    timerAlertService: timerAlertService,
    restNotificationService: restNotificationService,
    appVersionInfo: appVersionInfo,
  );
}
