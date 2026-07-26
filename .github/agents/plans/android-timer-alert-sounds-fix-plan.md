# Feature: Fix Android Rest/Effort Timer Alert Sounds

## Overview
On Android the app advertises five selectable rest/effort timer alert sounds, but
none of them are installed as raw resources under `res/raw/`, so the platform
notification system throws `PlatformException(invalid_sound, …)` when the
service tries to schedule a notification that carries a sound. This bug
silently breaks audible alerts and floods Sentry with the same error.

The fix has two halves:
1. **Materialize the five sounds as Android raw resources** under
   `android/app/src/main/res/raw/`, so the phone's notification system can
   actually play them.
2. **Add a guaranteed-silent fallback** in `RestNotificationService`: if
   scheduling a notification that carries a sound fails, retry the same
   notification with `playSound: false` and no sound attached so the
   user still receives the visual alert and the workout is never interrupted.

iOS already has the `.caf` files in the iOS bundle, so the schedule path on
iOS is unchanged. Foreground-silent / background-audible lifecycle behavior
is preserved unchanged.

## Requirements
- The five sounds (`boxing_bell`, `digital_buzzer`, `soft_chime`, `double_tap`,
  `signal_tone`) are present as Android raw resources under
  `android/app/src/main/res/raw/`.
- `android/app/src/main/res/raw/keep.xml` keeps the raw resources through R8
  shrink so they survive release builds.
- `RestNotificationService.scheduleRestPings` and
  `RestNotificationService.scheduleEffortTimerExpiry` retry without a sound
  when the audible schedule call throws, so the user still gets a visual
  notification at the scheduled time.
- The methods never propagate an exception to the caller. Any failure is
  reported through the existing non-fatal / cache-schema signal paths.
- The cache-schema signal is treated like every other non-cache-schema
  schedule error: the silent retry happens before the reporter is invoked.
- iOS scheduling remains unchanged (`.caf` sound names, no silent retry needed
  on iOS).
- No new public API surface; the silent retry is internal to the service.

## Acceptance Criteria
- [ ] All five `.mp3` sound files are present at
  `android/app/src/main/res/raw/{boxing_bell,digital_buzzer,soft_chime,double_tap,signal_tone}.mp3`.
- [ ] `android/app/src/main/res/raw/keep.xml` is updated to keep those raw
  resources through R8 resource shrinking.
- [ ] `RestNotificationService.scheduleRestPings` retries each iteration
  without a sound when the first schedule call throws, and never propagates
  the exception.
- [ ] `RestNotificationService.scheduleEffortTimerExpiry` retries without a
  sound when the first schedule call throws, and never propagates the
  exception.
- [ ] The silent retry uses the same notification ID, scheduled time, title,
  and body — only the `playSound` flag and the sound attachment change.
- [ ] The methods continue to honor the foreground-silent / background-audible
  contract: when `playSound: true` is passed, the first attempt carries the
  selected sound; the silent retry only fires on failure.
- [ ] iOS Darwin notification details (`.caf` sound) are not modified.
- [ ] No new `RestNotificationService` public method is added.
- [ ] No sounds are added or removed; no UI changes; default sound unchanged.

## Scenarios

### S-001: Rest ping with audible sound
- Trigger: `scheduleRestPings(restStartMs, intervalSecs: 60, soundId: 'boxing_bell', playSound: true)`
- Precondition: The selected sound exists as a raw resource on the device.
- Flow: `scheduleRestPings` schedules up to 50 rest-ping notifications.
- Expected outcome: All notifications are scheduled with
  `RawResourceAndroidNotificationSound('boxing_bell')` and `playSound: true`.
  No silent retry is attempted. No exception is thrown.
- Edge case of: none

### S-002: Rest ping silent fallback when selected sound is invalid
- Trigger: `scheduleRestPings(restStartMs, intervalSecs: 60, soundId: 'boxing_bell', playSound: true)`
- Precondition: The `zonedScheduleOverride` throws
  `PlatformException(code: 'invalid_sound', …)` on the first call for each
  notification ID.
- Flow: `scheduleRestPings` attempts each notification ID. Each first
  attempt throws; each second attempt must use no sound and `playSound: false`.
- Expected outcome: The method completes without throwing. Every scheduled
  ID has at least one successful silent schedule attempt. The non-fatal
  error is reported for each audible attempt.
- Edge case of: S-001

### S-003: Effort timer silent fallback when selected sound is invalid
- Trigger: `scheduleEffortTimerExpiry(fireAtMs, soundId: 'soft_chime', playSound: true)`
- Precondition: The `zonedScheduleOverride` throws
  `PlatformException(code: 'invalid_sound', …)` on the first call.
- Flow: `scheduleEffortTimerExpiry` first attempts an audible schedule,
  which throws. It then retries the same notification ID silently.
- Expected outcome: The silent retry is invoked with the same notification
  ID (`effortTimerNotificationId`), `playSound: false`, and no sound attached.
  The method does not throw.
- Edge case of: S-001

### S-004: Silent fallback does not run when playSound is already false
- Trigger: `scheduleEffortTimerExpiry(fireAtMs, soundId: 'boxing_bell', playSound: false)`
- Precondition: The `zonedScheduleOverride` always throws.
- Flow: `scheduleEffortTimerExpiry` schedules silently. The first attempt
  throws.
- Expected outcome: The method surfaces the failure as a non-fatal report
  and does not retry (the user already asked for silent). No silent-retry
  call is made beyond the initial silent schedule attempt.
- Edge case of: S-003

### S-005: _createAndroidChannels tolerates a per-sound failure
- Trigger: `initialize()` with one of the per-sound channel-creation calls
  throwing.
- Precondition: The override for `createNotificationChannel` throws for one
  of the five sound IDs and succeeds for the rest.
- Flow: `initialize` iterates the sound list and calls
  `_createAndroidChannels`.
- Expected outcome: All remaining channels are still created; the failure
  for the offending sound is reported through the non-fatal path; `initialize`
  does not rethrow.
- Edge case of: none

### S-006: scheduleRestPings silent fallback preserves body and title
- Trigger: `scheduleRestPings(restStartMs, intervalSecs: 60, soundId: 'soft_chime', playSound: true)`
- Precondition: The first schedule call throws for every iteration.
- Flow: Each iteration's silent retry runs.
- Expected outcome: The silent retry passes the same `body` string
  (`'${n * intervalSecs}s - rest time'`) and title (`'Rest timer'`) as the
  audible attempt. Only the sound attachment and `playSound` flag differ.
- Edge case of: S-002

## Iteration 1

### DB Changes
_None. This feature does not touch any repository, model, or schema._

### Backend Changes
_None. No service other than the local notification scheduler changes._

### Frontend Changes

#### `android/app/src/main/res/raw/`
- Add five MP3 files copied from `assets/sounds/`:
  - `boxing_bell.mp3`
  - `digital_buzzer.mp3`
  - `soft_chime.mp3`
  - `double_tap.mp3`
  - `signal_tone.mp3`
- These are what `RawResourceAndroidNotificationSound(soundId)` resolves to
  under the hood.

#### `android/app/src/main/res/raw/keep.xml`
- Extend `tools:keep` to include the five sound files. R8 / shrinker
  otherwise removes them in release builds because nothing in the Android
  manifest references them by name (they are looked up by string at runtime).

#### `lib/core/utils/rest_notification_service.dart`
- Extract a small private helper
  `_scheduleWithSilentFallback({required int notifId, required String title, required String body, required tz.TZDateTime scheduledDate, required NotificationDetails audibleDetails, required String errorContext, String? silentDetails})` that:
  1. Tries the audible schedule. If it throws (and `playSound == true` on the
     audible details), retries once with `playSound: false` and no sound
     attached. If the silent retry also throws, the error is reported
     through `_reportNonFatal` and the method returns normally.
  2. When `audibleDetails.android.playSound == false`, the helper does not
     retry — a silent-first failure is reported and the method returns
     normally.
- `scheduleRestPings` and `scheduleEffortTimerExpiry` are refactored to
  delegate to that helper. Public method signatures and behavior contracts
  (foreground-silent / background-audible) are unchanged.
- `_createAndroidChannels` wraps the per-sound `createNotificationChannel`
  call in a try/catch so a single failure does not abort the rest. Any
  failure is reported through `_reportNonFatal`.
- `zonedScheduleOverride` and the real `_plugin.zonedSchedule` path are
  both routed through the helper so tests can exercise the failure path
  without needing the real platform.

### Implementation Steps
1. **TDD-first (Phase 0.5):** Add new tests to
   `test/rest_notification_service_test.dart` covering S-002, S-003, S-004,
   S-005, and S-006. Extend
   `test/helpers/fake_rest_notification_service.dart` only if needed for
   S-005 (it does not need to be extended for S-002/S-003/S-004/S-006
   because they target the real `RestNotificationService.withPlugin` path).
2. Run `flutter test test/rest_notification_service_test.dart` and confirm
   the new tests fail (the silent fallback does not exist yet).
3. Implement the silent fallback in
   `lib/core/utils/rest_notification_service.dart`.
4. Run the full `flutter test` suite and confirm the new tests pass and no
   previously passing tests have regressed.
5. Add the five `.mp3` files to
   `android/app/src/main/res/raw/`.
6. Update `android/app/src/main/res/raw/keep.xml` to keep them.
7. Run `flutter analyze` and `flutter test` once more for the doc-hygiene
   sweep.

## Progress
- [x] Phase 0: Plan written
- [x] Phase 1: Android raw sound resources + keep rule
- [x] Phase 2.0.5: TDD red — silent-fallback tests fail
- [x] Phase 2: Silent fallback implemented + tests green
- [x] Phase 3: Code review
- [x] Phase 0 Complete ✓
- [x] Phase 1 Complete ✓
- [x] Phase 2 Complete ✓
- [x] Phase 3 Complete ✓

## Feedback
_Header reserved. Body intentionally empty._
