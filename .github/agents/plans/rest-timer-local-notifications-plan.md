# Feature: Rest + Effort Timer Local Notifications

## Overview
The rest timer pings (`fireRestPingAlert`) already have an OS-level local notification path, but the Effort Timer expiry event still only plays in-app audio. When a round timer or timed/duration set timer reaches zero while the phone is locked or the app is backgrounded, users miss the signal entirely.

The next iteration extends the existing notification service and permission flow so Effort Timer expiry uses the same bundled sounds, scheduling infrastructure, and foreground-suppression behavior already built for Rest Ping notifications. Rest Ping behavior itself remains unchanged.

**Explicitly out of scope**: Critical Alerts entitlement (bypasses silent mode — requires Apple approval).

## Requirements
- Rest pings continue to fire reliably when the phone is locked (ringer on = sound; silent = no sound)
- Effort Timer expiry fires a single OS notification exactly at zero for both round timers and timed/duration set timers
- The user's selected Effort Timer Sound is used for effort-expiry notifications; no system default fallback sound is introduced
- Works on iOS and Android
- No duplicate sound when app is in foreground (in-app timer sound handles that path; notification remains silent in foreground)
- Cancelling a rest cancels the scheduled rest notifications
- Pausing an effort timer cancels its scheduled expiry notification; resuming reschedules it to the new projected zero point
- Cancelling or manually advancing an effort timer cancels its scheduled notification
- If app is killed mid-rest or mid-effort timer, the OS delivers the notification
- Permission denial remains handled gracefully; surfaced in Settings under SOUNDS & ALERTS with copy that covers both rest and effort alerts
- Web remains a no-op for native notification scheduling

## Acceptance Criteria
- [ ] Rest ping fires (notification) when phone is locked + ringer on
- [ ] Rest ping is silent when phone is locked + silent mode
- [ ] Round timer reaching zero fires one notification when phone is locked + ringer on
- [ ] Timed/duration set timer reaching zero fires one notification when phone is locked + ringer on
- [ ] Effort Timer expiry fires exactly once at zero; no interval pinging
- [ ] User's selected rest ping sound is used
- [ ] User's selected Effort Timer Sound is used for effort-expiry notifications
- [ ] Silent mode is respected for effort expiry notifications
- [ ] No double sound when app is in foreground (notification appears but plays no sound)
- [ ] Cancelling a rest cancels all scheduled notifications
- [ ] Adjusting ping interval reschedules correctly
- [ ] App-killed-mid-rest: notification still fires
- [ ] Pausing a round cancels its scheduled expiry notification; resume reschedules correctly
- [ ] Cancelling or manually advancing a timer cancels its scheduled expiry notification
- [ ] App-killed-mid-effort-timer: notification still fires
- [ ] Permission denial: Settings shows a "Notifications disabled" indicator with tap-to-open-system-settings action and copy that covers rest and effort alerts
- [ ] Web: feature is entirely skipped (no-op service)
- [ ] Existing rest notification tests still pass and do not masquerade as effort-timer coverage
- [ ] New effort notification unit/widget tests pass
- [ ] App compiles and runs on physical iOS and Android devices

---

## Pre-condition (Manual — Aleks)

Before agents begin, complete the following platform sound setup:

### iOS — Convert `.mp3` → `.caf`
`flutter_local_notifications` on iOS requires notification sounds to be `.caf`, `.aiff`, or `.wav` files placed in the main bundle (`ios/Runner/`).

Run for each sound:
```bash
ffmpeg -i assets/sounds/boxing_bell.mp3    ios/Runner/boxing_bell.caf
ffmpeg -i assets/sounds/digital_buzzer.mp3 ios/Runner/digital_buzzer.caf
ffmpeg -i assets/sounds/soft_chime.mp3     ios/Runner/soft_chime.caf
ffmpeg -i assets/sounds/double_tap.mp3     ios/Runner/double_tap.caf
ffmpeg -i assets/sounds/signal_tone.mp3    ios/Runner/signal_tone.caf
```

Then in Xcode, add all `.caf` files to the Runner target's **Build Phases > Copy Bundle Resources** so they are embedded in the app bundle.

### Android — Copy `.mp3` to `res/raw/`
```bash
mkdir -p android/app/src/main/res/raw
cp assets/sounds/boxing_bell.mp3    android/app/src/main/res/raw/boxing_bell.mp3
cp assets/sounds/digital_buzzer.mp3 android/app/src/main/res/raw/digital_buzzer.mp3
cp assets/sounds/soft_chime.mp3     android/app/src/main/res/raw/soft_chime.mp3
cp assets/sounds/double_tap.mp3     android/app/src/main/res/raw/double_tap.mp3
cp assets/sounds/signal_tone.mp3    android/app/src/main/res/raw/signal_tone.mp3
```

Agents proceed once these files are in place and committed.

---

## Iteration 1

### Analysis

**Current rest ping flow** (foreground only):
1. User taps Log Set → `_logSet()` in `workout_session_screen.dart` creates an `EntryRest` record via `workoutState`
2. Every 1 s, `_tick()` → `_checkRestPings()` reads `getRestElapsedSeconds()` from the `EntryRest` wall-clock record
3. When elapsed crosses an interval boundary: `timerAlertService.fireRestPingAlert(pingSound)` → in-app `just_audio` sound

**What breaks when locked**: `_ticker` stops (or the app loses foreground) → `_checkRestPings()` never runs → no sound.

**Fix**: At rest start, compute all ping-boundary timestamps and schedule them as local notifications. At rest end, cancel them. On iOS foreground, configure the notification presentation to suppress sound (in-app handles it).

**Key constraint — "App killed mid-rest fires"**: This works with local notifications because the OS holds scheduled notifications independently of the app process.

**Deduplication strategy**:
- iOS: In `AppDelegate.swift`, implement `UNUserNotificationCenterDelegate.willPresent` and return `[.list, .banner]` (no `.sound`) when the app is in foreground. The in-app `_checkRestPings` fires the real sound.
- Android: Use a notification channel with `importance: HIGH` but configure the in-app ticker to suppress the in-app sound if the notification already fired within the last 500ms (use a `_lastNotificationFiredAt` debounce in `WorkoutSessionGlobalTimerExt`).

**Notification ID strategy**:
- Use IDs `100` through `149` for rest ping notifications (50 max pings per rest — covers 30 min at 30s intervals, or 150 min at 3 min intervals, well beyond any realistic rest period)
- Cancel IDs 100–149 to clear all rest pings

**Sound name mapping** (soundId → platform file):
- iOS: `'boxing_bell'` → `'boxing_bell.caf'` (custom), etc.
- Android: `'boxing_bell'` → URI `android.resource://com.omnitrain.app/raw/boxing_bell`

## Scenarios

### S-001: Schedule rest notifications on rest start
- Trigger: User logs a non-skipped set/entry and rest starts.
- Precondition: Session is active, rest ping interval is > 0, notifications are permitted.
- Flow: `_logSet()` records rest start and calls notification scheduling with rest start timestamp, interval, and selected rest sound.
- Expected outcome: Pending rest ping notifications are scheduled at future interval boundaries.
- Edge case of: none

### S-002: Skip notification scheduling when rest ping is off
- Trigger: User logs a set while rest ping interval is set to Off (0).
- Precondition: Session is active.
- Flow: Rest start path invokes scheduling with interval 0.
- Expected outcome: Existing pending rest notifications are canceled and no new notifications are scheduled.
- Edge case of: S-001

### S-003: Cancel notifications when rest ends in timer-start flows
- Trigger: User starts a timed/round/drill timer that closes open rests.
- Precondition: An open rest exists with pending scheduled notifications.
- Flow: `closeAllOpenRests` path runs and notification cancellation is invoked.
- Expected outcome: All rest notification IDs are canceled and no stale ping fires.
- Edge case of: S-001

### S-004: Cancel notifications when rest ends in log-set flow
- Trigger: User logs next set and `_logSet()` closes latest open rest via `recordRestEnd`.
- Precondition: An open rest exists and notifications were scheduled.
- Flow: `_logSet()` records rest end and invokes notification cancellation.
- Expected outcome: Pending rest notifications are canceled immediately.
- Edge case of: S-001

### S-005: Cancel notifications on session finish/dispose
- Trigger: Session is finished, discarded, or screen disposes.
- Precondition: Pending rest notifications exist.
- Flow: Session finish/dispose lifecycle invokes cancellation.
- Expected outcome: No rest notifications fire after the session is no longer active.
- Edge case of: S-001

### S-006: Reschedule when ping settings change during active rest
- Trigger: User changes rest ping interval or sound while a rest is currently open.
- Precondition: At least one open rest exists.
- Flow: Settings listener identifies most recent open rest and re-runs scheduling with current setting values.
- Expected outcome: New schedule reflects updated interval/sound; interval Off cancels all pending notifications.
- Edge case of: S-001

### S-007: Foreground behavior avoids duplicate sound
- Trigger: A scheduled rest ping fires while app is foregrounded.
- Precondition: App is active in foreground; in-app rest ticker path is alive.
- Flow: Foreground notification presentation is suppressed entirely; in-app ping path remains sound source.
- Expected outcome: No notification sound and no duplicate rest ping sound.
- Edge case of: S-001

### S-008: Web uses no-op notification path
- Trigger: Any notification service API is called on web.
- Precondition: Runtime platform is web.
- Flow: `initialize`, `requestPermission`, `hasPermission`, `scheduleRestPings`, `cancelRestNotifications` early-return.
- Expected outcome: No platform notification calls are made and app behavior remains stable.
- Edge case of: none

### S-009: Settings row shows not-yet-asked status
- Trigger: User opens Settings > Sounds & Alerts before any notification prompt was made.
- Precondition: `notificationPermissionAsked == false`.
- Flow: Permission row renders status from stored asked-flag.
- Expected outcome: Status is shown as "Not yet asked".
- Edge case of: none

### S-010: Settings row request path
- Trigger: User taps notification permission row while status is not-yet-asked.
- Precondition: Platform supports notifications and asked-flag is false.
- Flow: App shows contextual prompt, then (if accepted) requests permission and stores asked-flag.
- Expected outcome: Asked-flag is persisted true; row status updates according to resulting permission state.
- Edge case of: S-009

### S-011: Settings row denied path opens system settings
- Trigger: User taps notification permission row while permission is denied.
- Precondition: asked-flag true and permission state disabled.
- Flow: Tap action opens app system settings.
- Expected outcome: User is routed to system settings for manual permission enablement.
- Edge case of: S-009

### S-012: First interval activation prompt keeps setting on decline
- Trigger: User changes rest ping interval from Off to non-zero for first time.
- Precondition: asked-flag is false.
- Flow: Contextual prompt is shown; user declines permission request flow.
- Expected outcome: Selected interval remains saved; notifications remain unavailable until permission is granted later.
- Edge case of: S-010

## Phase 0 Red Test Run

- Command: `flutter test test/rest_notification_service_test.dart test/settings_state_test.dart test/settings_sounds_test.dart`
- Result: **RED (expected before implementation)**
- Failures confirm missing feature pieces:
  - `flutter_local_notifications` dependency not yet added
  - `lib/core/utils/rest_notification_service.dart` not yet created
  - `SettingsState.notificationPermissionAsked` and `setNotificationPermissionAsked()` not yet implemented
  - `SettingsScreen` does not yet accept `restNotificationService`

---

### Phase 1: Dependency + `RestNotificationService` (@developer)

**Context**: No existing notification code in the codebase. The new service must be no-op on web (`kIsWeb`). It wraps `flutter_local_notifications` with a clean interface that `WorkoutSessionScreen` calls.

#### Steps

1. [ ] **Add to `pubspec.yaml`**:
   ```yaml
   flutter_local_notifications: ^17.2.0
   ```
   Run `flutter pub get` to confirm resolution. Confirm `just_audio` and `audio_session` remain unaffected.

2. [ ] **Create `lib/core/utils/rest_notification_service.dart`**:

   ```dart
   import 'package:flutter/foundation.dart';
   import 'package:flutter_local_notifications/flutter_local_notifications.dart';
   
   class RestNotificationService {
     static const int _restPingBaseId = 100;
     static const int _maxRestPings = 50;
   
     final FlutterLocalNotificationsPlugin _plugin;
     final bool? _isWebOverride;
   
     RestNotificationService()
         : _plugin = FlutterLocalNotificationsPlugin(),
           _isWebOverride = null;
   
     @visibleForTesting
     RestNotificationService.withPlugin(
       FlutterLocalNotificationsPlugin plugin, {
       bool isWeb = false,
     }) : _plugin = plugin,
          _isWebOverride = isWeb;
   
     bool get _isWeb => _isWebOverride ?? kIsWeb;
   
     /// Initializes notification channels and foreground behavior.
     /// Safe to call multiple times (idempotent).
     Future<void> initialize() async {
       if (_isWeb) return;
       // Android: create notification channel per sound
       const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
       // iOS: request permission=false here; use requestPermission() when contextually appropriate
       final darwinInit = DarwinInitializationSettings(
         requestAlertPermission: false,
         requestBadgePermission: false,
         requestSoundPermission: false,
       );
       await _plugin.initialize(
         InitializationSettings(android: androidInit, iOS: darwinInit),
       );
     }
   
     /// Requests notification permission (iOS 14+, Android 13+).
     /// Returns true if granted.
     Future<bool> requestPermission() async {
       if (_isWeb) return false;
       // iOS
       final iosPlugin = _plugin
           .resolvePlatformSpecificImplementation<
             IOSFlutterLocalNotificationsPlugin>();
       if (iosPlugin != null) {
         final granted = await iosPlugin.requestPermissions(
           alert: true,
           sound: true,
           badge: false,
         );
         return granted ?? false;
       }
       // Android 13+
       final androidPlugin = _plugin
           .resolvePlatformSpecificImplementation<
             AndroidFlutterLocalNotificationsPlugin>();
       if (androidPlugin != null) {
         final granted = await androidPlugin.requestNotificationsPermission();
         return granted ?? false;
       }
       return false;
     }
   
     /// Returns true if notification permission is currently granted.
     Future<bool> hasPermission() async {
       if (_isWeb) return false;
       final androidPlugin = _plugin
           .resolvePlatformSpecificImplementation<
             AndroidFlutterLocalNotificationsPlugin>();
       if (androidPlugin != null) {
         return await androidPlugin.areNotificationsEnabled() ?? false;
       }
       // iOS: check via pending notifications as a proxy (no direct status API)
       // Use requestPermission() if unsure — it does not re-prompt if already granted/denied.
       return true; // iOS: assume granted until explicitly denied
     }
   
     /// Cancels all scheduled rest ping notifications then schedules new ones.
     ///
     /// Call this when a rest period starts.
     /// [restStartMs] — epoch ms when the rest began (from EntryRest.restStartMs)
     /// [intervalSecs] — ping interval in seconds (from SettingsState.restPingInterval; 0 = off)
     /// [soundId] — sound key from SettingsState.restPingSound
     Future<void> scheduleRestPings({
       required int restStartMs,
       required int intervalSecs,
       required String soundId,
     }) async {
       if (_isWeb) return;
       await cancelRestNotifications();
       if (intervalSecs == 0) return;
       final now = DateTime.now().millisecondsSinceEpoch;
       for (int n = 1; n <= _maxRestPings; n++) {
         final fireAtMs = restStartMs + (n * intervalSecs * 1000);
         if (fireAtMs <= now) continue; // already past
         final fireAt = DateTime.fromMillisecondsSinceEpoch(fireAtMs);
         final notifId = _restPingBaseId + (n - 1);
         await _plugin.zonedSchedule(
           notifId,
           'Rest timer',
           '${n * intervalSecs}s — rest time',
           _toTZDateTime(fireAt),
           NotificationDetails(
             android: AndroidNotificationDetails(
               'rest_pings_$soundId',
               'Rest Pings',
               channelDescription: 'Rest period interval alerts',
               importance: Importance.high,
               priority: Priority.high,
               sound: RawResourceAndroidNotificationSound(soundId),
               playSound: true,
             ),
             iOS: DarwinNotificationDetails(
               sound: '$soundId.caf',
               presentAlert: true,
               presentBadge: false,
               presentSound: true,
             ),
           ),
           androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
           uiLocalNotificationDateInterpretation:
               UILocalNotificationDateInterpretation.absoluteTime,
         );
       }
     }
   
     /// Cancels all scheduled rest ping notifications (IDs 100–149).
     Future<void> cancelRestNotifications() async {
       if (_isWeb) return;
       for (int i = _restPingBaseId; i < _restPingBaseId + _maxRestPings; i++) {
         await _plugin.cancel(i);
       }
     }
   
     // Helper: convert DateTime to TZDateTime using local timezone.
     // flutter_local_notifications requires timezone-aware scheduling.
     Object _toTZDateTime(DateTime dt) {
       // Requires timezone package or use the workaround below.
       // Developer must add: timezone: ^0.9.x to pubspec and call
       // tz.initializeTimeZones() in main().
       // Placeholder: return the raw DateTime — developer to replace with tz.TZDateTime.from(dt, tz.local).
       return dt;
     }
   }
   ```

   **Critical implementation note**: `zonedSchedule` requires the `timezone` package. Add `timezone: ^0.9.4` to `pubspec.yaml` and call `tz.initializeTimeZones()` in `main.dart` before `runApp`. Replace the `_toTZDateTime` placeholder with `tz.TZDateTime.from(dt, tz.local)`.

3. [ ] **Add `timezone: ^0.9.4`** to `pubspec.yaml` dependencies.

4. [ ] **Update `lib/main.dart`**:
   - Import `package:timezone/data/latest_all.dart` as `tzdata`
   - Import `package:timezone/timezone.dart` as `tz`
   - Call `tzdata.initializeTimeZones()` before `runApp`
   - Instantiate `final restNotificationService = RestNotificationService()`
   - Call `await restNotificationService.initialize()` after `timerAlertService.initialize()`
   - Pass `restNotificationService` into `MyApp(...)`

5. [ ] **Thread `RestNotificationService` through `MyApp`** and all navigating screens (same pattern as `TimerAlertService`). It is passed to `WorkoutSessionScreen` as a new required parameter.

#### Affected Files
- `pubspec.yaml` (add 2 deps)
- `lib/core/utils/rest_notification_service.dart` (new)
- `lib/main.dart`
- `lib/app.dart`
- All call sites of `WorkoutSessionScreen` (see Phase 3)

---

### Phase 2: Platform Configuration (@developer)

#### iOS — `AppDelegate.swift` foreground suppression

Edit `ios/Runner/AppDelegate.swift` to register as `UNUserNotificationCenterDelegate` and suppress notification sound when the app is in the foreground (in-app ping handles that case):

```swift
import Flutter
import UIKit
import UserNotifications

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate, UNUserNotificationCenterDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // When app is foregrounded, show notification banner/list but DO NOT play sound.
  // The in-app ticker already fires the ping sound via TimerAlertService.
  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.alert, .list]) // banner + notification centre; no .sound
  }
}
```

**Steps**:
1. [ ] Modify `ios/Runner/AppDelegate.swift` with the foreground suppression delegate as shown above.
2. [ ] Add `NSUserNotificationsUsageDescription` key to `ios/Runner/Info.plist` (if not already present):
   ```xml
   <key>NSUserNotificationUsageDescription</key>
   <string>Rest timer pings notify you when it's time to start your next set.</string>
   ```

#### Android — Manifest permission

1. [ ] Add to `android/app/src/main/AndroidManifest.xml` (inside `<manifest>`, before `<application>`):
   ```xml
   <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
   <!-- Required for exact alarms on Android 12+ -->
   <uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM" />
   ```
2. [ ] Verify `minSdkVersion` in `android/app/build.gradle.kts` — exact alarms require API 31+. If `minSdk < 31`, use `AndroidScheduleMode.inexact` as a fallback for older devices.

#### Affected Files
- `ios/Runner/AppDelegate.swift`
- `ios/Runner/Info.plist`
- `android/app/src/main/AndroidManifest.xml`

---

### Phase 3: Session Integration (@developer)

**Context**: `WorkoutSessionScreen` already accepts `TimerAlertService` as a required param. Add `RestNotificationService` as a new required param. Hook into rest start and rest end lifecycle events.

#### Steps

1. [ ] **Update `WorkoutSessionScreen` constructor** in `lib/features/session/workout_session_screen.dart`:
   ```dart
   final RestNotificationService restNotificationService;
   ```
   Add to `const WorkoutSessionScreen({...})` and `_WorkoutSessionScreenState`.

2. [ ] **At rest start** — in `_logSet()` (after the `EntryRest` record is created):
   ```dart
   unawaited(widget.restNotificationService.scheduleRestPings(
     restStartMs: DateTime.now().millisecondsSinceEpoch,
     intervalSecs: widget.settingsState.restPingInterval,
     soundId: widget.settingsState.restPingSound,
   ));
   ```
   Note: this is called for every set log. `scheduleRestPings` internally cancels previous ones first, so back-to-back logs are safe.

3. [ ] **At rest end** — override the `closeAllOpenRests` call path. The existing call sites in `_toggleEffortTimer` (in `workout_session_timer_mixin.dart`) already call `closeAllOpenRests`. Add cancellation after each:
   ```dart
   unawaited(widget.workoutState.closeAllOpenRests(effortId));
   unawaited(widget.restNotificationService.cancelRestNotifications());
   _lastRestPingFiredAt.remove(effortId);
   ```
   Search for all `closeAllOpenRests` call sites (currently 2 in `workout_session_timer_mixin.dart` + 1 in `workout_session_screen.dart`) and add the cancel call.

4. [ ] **On session finish** — in `_WorkoutSessionFinishExt` or wherever `_finishSession()` is called, cancel all rest notifications:
   ```dart
   unawaited(widget.restNotificationService.cancelRestNotifications());
   ```
   The `dispose()` override in `_WorkoutSessionScreenState` should also cancel:
   ```dart
   @override
   void dispose() {
     unawaited(widget.restNotificationService.cancelRestNotifications());
     // ... existing dispose logic
     super.dispose();
   }
   ```

5. [ ] **Settings-change rescheduling** — If the user changes `restPingInterval` or `restPingSound` while a rest is active, reschedule. Add a `ChangeNotifier` listener to `settingsState` in `initState`:
   ```dart
   widget.settingsState.addListener(_onSettingsChanged);
   ```
   ```dart
   void _onSettingsChanged() {
     final restKey = _getMostRecentOpenRestKey();
     if (restKey == null) return;
     final rest = widget.workoutState.getEntryRests(restKey.effortId)
         .where((r) => r.restEndMs == null)
         .firstOrNull;
     if (rest == null) return;
     unawaited(widget.restNotificationService.scheduleRestPings(
       restStartMs: rest.restStartMs,
       intervalSecs: widget.settingsState.restPingInterval,
       soundId: widget.settingsState.restPingSound,
     ));
   }
   ```

6. [ ] **Update ALL `WorkoutSessionScreen(...)` call sites** to pass `restNotificationService`:
   - `lib/features/home/home_screen.dart` (~5 occurrences)
   - `lib/features/exercise/exercise_detail_screen.dart` (1)
   - `lib/features/calendar/day_session_list_screen.dart` (1)
   - `lib/features/routine/my_routines_screen.dart` (1)
   - `lib/features/session/session_summary_screen.dart` (1)
   - All test files: use `FakeRestNotificationService` (see Phase 5)

#### Affected Files
- `lib/features/session/workout_session_screen.dart`
- `lib/features/session/workout_session_timer_mixin.dart` (close-rest call sites)
- `lib/features/home/home_screen.dart`
- `lib/features/exercise/exercise_detail_screen.dart`
- `lib/features/calendar/day_session_list_screen.dart`
- `lib/features/routine/my_routines_screen.dart`
- `lib/features/session/session_summary_screen.dart`

---

### Phase 4: Settings — Permission Handling (@developer)

**Context**: Settings screen has a `SOUNDS & ALERTS` section. Add a notification permission row below the existing sounds rows. Tapping opens iOS system settings (or triggers Android permission dialog if not yet asked).

#### SettingsState changes

1. [ ] Add preference key + stored field:
   ```dart
   static const String _notificationPermissionAskedKey = 'notification_permission_asked';
   bool _notificationPermissionAsked = false;
   bool get notificationPermissionAsked => _notificationPermissionAsked;
   ```
   Load from prefs in `_loadFromPrefs()`. Persist via `setNotificationPermissionAsked()`.

2. [ ] Add method:
   ```dart
   Future<void> setNotificationPermissionAsked() async {
     _notificationPermissionAsked = true;
     await _repository.setPreferenceString(_notificationPermissionAskedKey, 'true');
     notifyListeners();
   }
   ```

#### SettingsScreen changes

The `RestNotificationService` needs to be passed into `SettingsScreen`:

1. [ ] Add `RestNotificationService restNotificationService` param to `SettingsScreen`.
2. [ ] Add a `_NotificationPermissionRow` widget inside `_SoundsAlertsSection`:
   - Shows current status: "Enabled" (green), "Disabled — tap to open Settings" (warning amber), or "Not yet asked"
   - On tap when denied: `openAppSettings()` from `app_settings` package (add to pubspec) **OR** use `FlutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>().requestPermissions()` which prompts or opens Settings if already denied.
   - On tap when not-yet-asked: request permission via `restNotificationService.requestPermission()` + `settingsState.setNotificationPermissionAsked()`
   - On web: row is hidden

**Permission prompt timing**: The row in Settings triggers the permission prompt only when the user explicitly taps it. This satisfies Apple's requirement for contextual permission requests (not on first launch).

3. [ ] **Contextual permission prompt at first ping-interval activation**: When the user first sets `restPingInterval > 0` in Settings, if `!notificationPermissionAsked`, show a contextual prompt explaining why notifications improve the experience, then call `requestPermission()`. This is the most user-friendly moment to ask.

#### Affected Files
- `lib/state/settings/settings_state.dart`
- `lib/features/settings/settings_screen.dart`
- All `SettingsScreen(...)` call sites (to pass `restNotificationService`)
- `pubspec.yaml` (if `app_settings` package is added for open-settings action)

---

### Phase 5: Test Coverage (@developer)

#### New test double

1. [ ] Create `test/helpers/fake_rest_notification_service.dart`:
   ```dart
   import 'package:omnitrain/core/utils/rest_notification_service.dart';
   import 'package:flutter_local_notifications/flutter_local_notifications.dart';

   class FakeRestNotificationService extends RestNotificationService {
     final List<({int restStartMs, int intervalSecs, String soundId})> scheduled = [];
     int cancelCallCount = 0;
     bool permissionGranted = true;

     @override
     Future<void> initialize() async {}

     @override
     Future<bool> requestPermission() async => permissionGranted;

     @override
     Future<bool> hasPermission() async => permissionGranted;

     @override
     Future<void> scheduleRestPings({
       required int restStartMs,
       required int intervalSecs,
       required String soundId,
     }) async {
       scheduled.add((restStartMs: restStartMs, intervalSecs: intervalSecs, soundId: soundId));
     }

     @override
     Future<void> cancelRestNotifications() async {
       cancelCallCount++;
     }
   }
   ```

2. [ ] **Unit tests** in `test/rest_notification_service_test.dart`:
   - `scheduleRestPings` with `intervalSecs: 0` → no notifications scheduled
   - `scheduleRestPings` with `intervalSecs: 60` and `restStartMs` in the past → skips past boundaries, schedules future ones
   - `cancelRestNotifications` → cancels IDs 100–149
   - `requestPermission` returns result from platform
   - Constructor `RestNotificationService.withPlugin(mockPlugin)` enables testing without real platform

3. [ ] **Update existing test files** that construct `WorkoutSessionScreen` to pass `FakeRestNotificationService()`:
   - `test/widget_test.dart`
   - `test/unsaved_changes_dialog_test.dart`
   - `test/session_finish_timers_test.dart`
   - `test/session_edit_duration_test.dart`
   - `test/screen_widget_test.dart`
   - Any other test file that constructs `WorkoutSessionScreen` directly

4. [ ] **Update `test/settings_sounds_test.dart`** to pass `FakeRestNotificationService()` to `SettingsScreen` (once that param is added in Phase 4).

5. [ ] **Manual verification checklist** (document in the PR description):
   - [ ] Phone locked + ringer on → ping sound plays at correct interval
   - [ ] Phone locked + silent mode → no sound (notification appears silently)
   - [ ] App in foreground + unlocked → in-app sound plays; no notification sound
   - [ ] Kill app mid-rest → notification fires at scheduled time
   - [ ] Cancel rest (start next set) → scheduled notifications do not fire
   - [ ] Change ping interval in settings mid-rest → new interval takes effect
   - [ ] Deny notification permission → Settings row shows "Disabled" + tap opens system settings

#### Affected Files
- `test/helpers/fake_rest_notification_service.dart` (new)
- `test/rest_notification_service_test.dart` (new)
- `test/widget_test.dart`
- `test/unsaved_changes_dialog_test.dart`
- `test/session_finish_timers_test.dart`
- `test/session_edit_duration_test.dart`
- `test/screen_widget_test.dart`
- `test/settings_sounds_test.dart`

---

## Files Affected — Complete List

### New Files
- `lib/core/utils/rest_notification_service.dart`
- `test/helpers/fake_rest_notification_service.dart`
- `test/rest_notification_service_test.dart`
- `ios/Runner/boxing_bell.caf` + 4 others (manual)
- `android/app/src/main/res/raw/boxing_bell.mp3` + 4 others (manual)

### Modified Files
- `pubspec.yaml` (+ `flutter_local_notifications`, `timezone`)
- `lib/main.dart`
- `lib/app.dart`
- `lib/core/utils/rest_notification_service.dart`
- `lib/state/settings/settings_state.dart`
- `lib/features/settings/settings_screen.dart`
- `lib/features/session/workout_session_screen.dart`
- `lib/features/session/workout_session_timer_mixin.dart`
- `lib/features/home/home_screen.dart`
- `lib/features/exercise/exercise_detail_screen.dart`
- `lib/features/calendar/day_session_list_screen.dart`
- `lib/features/routine/my_routines_screen.dart`
- `lib/features/session/session_summary_screen.dart`
- `ios/Runner/AppDelegate.swift`
- `ios/Runner/Info.plist`
- `android/app/src/main/AndroidManifest.xml`
- All test files referencing `WorkoutSessionScreen` or `SettingsScreen`

---

## Implementation Notes

### Timezone dependency
`flutter_local_notifications` v17+ requires `timezone` for `zonedSchedule`. The call in `main.dart` is:
```dart
import 'package:timezone/data/latest_all.dart' as tzdata;
tzdata.initializeTimeZones();
```
This adds ~200 KB to the bundle — acceptable.

### Exact alarms on Android 12+
`SCHEDULE_EXACT_ALARM` grants exact wake-up. On Android 14+, this may require user approval in system settings (Battery). Use `AndroidScheduleMode.exactAllowWhileIdle` which is the correct flag. If the permission is not granted, fall back to `AndroidScheduleMode.inexact` and log a debug message.

### Channel ID per sound
Each sound gets its own Android notification channel (`rest_pings_boxing_bell`, etc.) so the OS can map the correct sound. This is a one-time setup per install.

### `cancelRestNotifications` loop
Cancelling 50 IDs in a loop is O(50) and fast (each cancel is a DB delete by ID). This is fine for the use case.

### Web
`RestNotificationService` checks `kIsWeb` and returns early from all methods. No special web handling needed in calling code.

### No schema changes
`EntryRest.restStartMs` already provides everything needed. No new DB tables, columns, or migrations.

---

## Iteration 2

### Analysis

Carry-forward from prior feedback: the rest-notification foundation is already in place and previously reported implementation, test, and documentation blockers were revalidated as resolved. This iteration should build on that foundation rather than create a parallel notification stack.

The missing behavior is specific and local: the Effort Timer expiry path still relies on in-app audio only, so round timers and timed/duration set timers do not notify the user when the app is backgrounded or the phone is locked. The correct change is to extend the existing notification service with a one-shot effort-expiry schedule/cancel API, then wire the shared effort timer lifecycle to call it on start, pause, resume, cancel, early completion, and zero.

This is a fast-track Developer task: no schema changes, no new settings rows, and no new repository/state surface should be required if the existing timer/session lifecycle already exposes the zero-time and pause/resume transitions.

### Questions

No blocking product questions. The implementation assumption is that both round timers and timed/duration set timers already converge on a shared Effort Timer expiry control path; if they do not, the Developer should wire both paths explicitly but still keep the notification API shared.

### Scenarios

### S-013: Schedule effort-expiry notification on timer start
- Trigger: User starts a round timer or timed/duration set timer.
- Precondition: Notifications are permitted and the timer has a projected zero time.
- Flow: Shared effort-timer start path schedules a one-shot notification for the zero timestamp using the selected Effort Timer Sound.
- Expected outcome: Exactly one pending effort-expiry notification exists for the active timer.
- Edge case of: none

### S-014: Pause cancels effort-expiry notification
- Trigger: User pauses a round timer.
- Precondition: A pending effort-expiry notification exists.
- Flow: Pause handler cancels the pending effort-expiry notification.
- Expected outcome: No stale expiry notification fires while paused.
- Edge case of: S-013

### S-015: Resume reschedules effort-expiry notification
- Trigger: User resumes a paused round timer.
- Precondition: Timer has remaining duration after pause.
- Flow: Resume handler recomputes the projected zero time and reschedules a single effort-expiry notification.
- Expected outcome: Notification fires once at the new zero point.
- Edge case of: S-014

### S-016: Early cancel or manual advance clears effort-expiry notification
- Trigger: User cancels, skips, or manually advances before zero.
- Precondition: A pending effort-expiry notification exists.
- Flow: Completion/cancel path invokes effort notification cancellation.
- Expected outcome: No expiry notification fires after the timer is no longer active.
- Edge case of: S-013

### S-017: Foreground expiry avoids duplicate sound
- Trigger: Effort Timer reaches zero while the app is foregrounded and unlocked.
- Precondition: In-app timer-alert path is active.
- Flow: Scheduled notification remains silent in foreground; existing in-app effort timer sound plays.
- Expected outcome: User hears a single effort-expiry sound.
- Edge case of: S-013

### S-018: App killed mid-effort timer still delivers at zero
- Trigger: App is terminated after effort notification scheduling but before timer expiry.
- Precondition: Notification was successfully scheduled with the OS.
- Flow: OS delivers the pending local notification at zero.
- Expected outcome: User receives the effort-expiry alert without the app process running.
- Edge case of: S-013

### S-019: Settings permission copy covers both alert types
- Trigger: User opens Settings > Sounds & Alerts.
- Precondition: Notification permission row is visible.
- Flow: Permission row description is rendered.
- Expected outcome: Copy references both rest and effort/round timer alerts, not rest only.
- Edge case of: none

### Phase 1: Notification Service Extension (@developer)

1. [ ] Extend `RestNotificationService` rather than creating a second service. Add one-shot effort-expiry scheduling and cancellation methods with a dedicated notification ID range or singleton ID that cannot collide with rest-ping IDs.
2. [ ] Reuse the existing bundled-sound mapping and platform channel strategy so effort expiry plays the user's selected Effort Timer Sound on iOS and Android.
3. [ ] Confirm the existing foreground suppression behavior applies to effort-expiry notifications too. If Android uses a debounce path for duplicate suppression, extend that same mechanism to the effort expiry event.
4. [ ] Keep web as a strict no-op for all new effort notification APIs.

### Phase 2: Session Timer Integration (@developer)

1. [ ] Find the shared effort-timer control path that starts countdowns for round timers and timed/duration set timers, and schedule the effort-expiry notification there using the computed zero timestamp.
2. [ ] Cancel the effort-expiry notification on pause, manual advance, cancellation, and any early-complete path.
3. [ ] Reschedule the notification on resume using the recomputed projected zero point.
4. [ ] Cancel the pending effort notification immediately when the zero handler runs, so the lifecycle stays single-shot even if the user interacts at the boundary.
5. [ ] Ensure screen dispose/session finish paths clear any pending effort notification just as they already clear rest notifications.

### Phase 3: Settings Copy + Tests (@developer)

1. [ ] Update the notification-permission row description string so it covers both rest reminders and effort/round timer alerts while staying concise and consistent with the current settings tone.
2. [ ] Add or update unit tests for: effort notification scheduling at zero for round timers and timed/duration timers; pause cancel; resume reschedule; early cancel/manual advance; foreground duplicate suppression; selected Effort Timer Sound propagation.
3. [ ] Update or replace any existing test that asserts the old rest-only permission copy.
4. [ ] Review the existing rest notification tests and explicitly verify that none of them were implicitly treated as generic timer-notification coverage.

### Phase 4: Native Verification (@developer)

1. [ ] Compile and run on a physical iOS device; manually verify locked-phone zero-time notification delivery for a round timer and a timed/duration set timer.
2. [ ] Compile and run on a physical Android device; manually verify the same flows.
3. [ ] Manually verify silent-mode behavior, foreground single-sound behavior, pause/resume rescheduling, and early cancellation on both platforms.

### Files Affected

- `lib/core/utils/rest_notification_service.dart`
- `lib/features/session/workout_session_screen.dart`
- `lib/features/session/workout_session_timer_mixin.dart`
- Any session-timer helper or extension files that own round or timed-set countdown lifecycle
- `lib/features/settings/settings_screen.dart`
- Existing timer-notification test files plus any new focused effort-notification tests

### Notes

- Do not introduce new settings, permissions, or bundled sound assets.
- Do not change Rest Ping behavior except where shared notification code must be generalized safely.
- Physical-device verification is required; a passing web build is not evidence for this feature because the native notification plugin path is excluded there.

## Progress
- [x] Extend the existing notification service for one-shot effort-expiry scheduling and cancellation
- [x] Wire round and timed/duration timer lifecycle events to schedule, cancel, and reschedule effort notifications
- [x] Update settings permission-row copy to cover rest and effort alerts
- [x] Add focused effort-notification tests and re-audit existing rest-notification coverage
- [x] Fix analyzer regressions in session part files and notification-adjacent tests
- [x] Prevent foreground duplicate timer audio by foreground-silent/background-audible notification scheduling
- [ ] Verify on a physical iOS device
- [x] Verify on a physical Android device (waived by product owner for this release; merge allowed with known risk)

### Phase Status
In review (Android physical verification waived; iOS verification still pending)

## Risk Acceptance

- Waiver decision date: 2026-05-24.
- Waiver scope: physical Android device verification for local rest/effort notification delivery.
- Approved by: product owner/user in review thread.
- Rationale: no Android device available in the current environment.
- Residual risk accepted: Android OEM-specific notification behavior (Doze/channel/device policy variance) remains unvalidated on hardware for this release.
- Post-merge follow-up required: run the locked-phone, app-backgrounded, and app-killed manual notification checks on at least one physical Android device and log outcomes in this plan.

## Feedback

- Physical-device acceptance remains open for iOS: on-device manual verification for locked-phone delivery is still required unless explicitly waived.
- Android physical-device validation is waived for this release (see Risk Acceptance).
- App-killed-mid-effort-timer delivery remains manual-only evidence in this environment; no automated test can fully substitute for native OS delivery when process is terminated.

