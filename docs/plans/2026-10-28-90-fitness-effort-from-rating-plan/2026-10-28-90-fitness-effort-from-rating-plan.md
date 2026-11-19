# Plan 90: the session's effort rating also goes into Apple Fitness ("Workout Effort")

> Status: BUILT 2026-10-29 (both phases), uncommitted; HealthKit behaviour unproven until the owner runs QA step 39 (S-90-9). Two phases (Dart side with a fake store; then the native iOS piece), one commit each. Phone track only; no wire change; no watch change. Defaults for the open questions are the owner's recommended ones from chat and are marked "owner to confirm".

## Goal and acceptance

Apple Fitness (iOS 18 and later) shows a **Workout Effort** value, 1 to 10, for a workout. OmniTrain already captures a 1 to 5 session effort rating (`TrainingSession.sessionFeeling`, 1 = very easy, 5 = max effort; set on the phone, or on the wrist and imported). The rating should land in Fitness as that workout's effort.

Acceptance: (1) with "Write workouts" on, an iPhone on iOS 18 or later, and a finished session that has a workout in Fitness, rating the session in OmniTrain sets the Fitness workout's Workout Effort to the mapped value; (2) changing the rating later changes it; (3) a value the owner set themselves in Fitness is never overwritten; (4) with the setting off, on Android, on iOS before 18, or with no workout found, nothing happens and nothing is shown; (5) deleting a session also removes the effort OmniTrain wrote; (6) the existing workout write, ledger and delete (plans 89, 89c1) are unchanged.

## Facts read from source (2026-10-28)

- The `health` plugin (13.3.1) has no effort support (no file in its `lib/` or `ios/` mentions it). Needs native code; `ios/Runner` has no method channel today (`AppDelegate.swift` registers plugins and a notification delegate only). iOS deployment target is 14.0; Xcode 26.4.1 with iOS 26.4 SDK is installed, so the iOS 18 API compiles behind `#available(iOS 18.0, *)`.
- Rating write paths: `SessionCoreLifecycle.updateSessionFeeling` (`session_core_lifecycle.dart:196`; phone UI, the summary sheet, the calendar edit, and the adoption bridge's `_catchUpSessionRow`); the wrist importer writes a wrist rating straight into the row (`watch_session_importer.dart`, `_topUpRating`, `ratingWritten`, `appliedRating` on the import result at lines 231 and 415); `adoptSessionFeeling` only mirrors an already-written rating.
- `HealthSyncService` already gates on the "Write workouts" toggle, never throws, never prompts (the prompt happens only when the owner flips the toggle, `settings_state.dart:242`), and deletes by the session's exact span, own source only (plan 89 D-5). Owner device check 2026-10-28: that delete also removes a finished watch workout.
- The native workout lookup the plugin does for delete (start inside `[start, end)`, own app source) is the lookup this plan reuses.

## Open owner questions (defaults in bold, owner to confirm)

- OQ-1 Scale: **1 to 5 maps to 2, 4, 6, 8, 10** (very easy = 2, max = 10), or a different spread.
- OQ-2 A value the owner already set in Fitness: **OmniTrain leaves it alone**, or OmniTrain's rating wins.
- OQ-3 Setting: **follows "Write workouts"**, or a separate switch.
- OQ-4 Permission: **asked only when "Write workouts" is switched on** (the existing rule: nothing prompts mid-session). Because the owner's switch is already on, they switch it off and on once to get the new Health question; no prompt appears out of the blue.

## Decision Ledger

- D-1 One new method on the platform contract: `HealthPlatformService.setWorkoutEffort(start, end, score)` returns an outcome enum `HealthEffortOutcome { written, leftAlone, noWorkout, unavailable }`, and `clearWorkoutEffort(start, end)` returns bool. Fakes and `UnavailableHealthPlatformService` return `unavailable`. Never throws.
- D-2 The mapping is a pure function in `lib/core/services/health_modality_mapper.dart`'s neighbour (`health_effort_mapper.dart`, new): `ratingToAppleEffort(int) -> int?` (null outside 1..5). Pinned by a table test.
- D-3 `HealthSyncService.onSessionRated(TrainingSession)`: gated by the write toggle; ignores a session without `endedAtMs` or without a rating; calls `setWorkoutEffort` with the session's exact span. A `noWorkout` outcome retries in-process at 20 s, 90 s and 5 min (the watch's workout reaches the phone's Health store a little after the finish); after that it gives up silently. No persisted retry list (limit L-1).
- D-4 Hooks: `SessionCore.updateSessionFeeling` calls `onSessionRated` un-awaited after a successful save, for an ended session only; the wrist-import path calls it once per import that applied a rating. The developer lists every place a rating lands with `grep -rn "session_feeling\|sessionFeeling" lib`; any place found beyond the two named above is reported, not silently skipped.
- D-5 `onSessionDeleted` calls `clearWorkoutEffort` first, then `deleteWorkouts` (D-5 of plan 89 unchanged). Best-effort.
- D-6 Native (Phase 2): a Swift class in `ios/Runner` registered from `AppDelegate`, channel `omnitrain/health_effort`, methods `requestAuthorization`, `set`, `clear`. Every body is behind `#available(iOS 18.0, *)`; on older iOS or on any error it answers `unavailable`.
  - `set`: find the own-source workout whose start lies in `[start, end)` (earliest if several); read the effort samples related to it (`predicateForWorkoutEffortSamplesRelated`); if any was saved by another source, answer `leftAlone`; delete this app's own previous effort sample if present; save the new `HKQuantity` (`appleEffortScore`) and relate it (`relateWorkoutEffortSample`). Answer `written`, or `noWorkout`.
  - `clear`: delete this app's own related effort samples for that workout.
  - `requestAuthorization`: ask to share and read the workout-effort type; called from the same place as the existing write permission request, so the one toggle asks once.
- D-7 Android and web: no effort concept used; `unavailable`, no work.
- D-8 Out of scope: writing from the watch; the watch's automatic "Estimated Effort"; reading Fitness effort back into OmniTrain; a persisted retry queue (L-1); sessions rated before this ships (no backfill, no existing user data besides the owner's).

## Scenarios

- S-90-1 Mapping table: 1,2,3,4,5 give 2,4,6,8,10; 0, 6 and negatives give null.
- S-90-2 Sync service, toggle on, ended rated session: one `setWorkoutEffort` with the session's exact span and mapped score. Toggle off: no call. Session without rating or without end: no call.
- S-90-3 A rating change: a second `onSessionRated` with a new rating calls again with the new score (the native side replaces its own sample); same rating twice is safe.
- S-90-4 Outcomes: `leftAlone` and `unavailable` stop silently with no retry; `noWorkout` retries on the 20 s / 90 s / 5 min schedule (fake clock) and stops after the last; a retry that finds the workout stops the schedule; a newer rating cancels the pending retries for that session.
- S-90-5 Hooks: rating through `updateSessionFeeling` on an ended session calls the sync service once; on a still-running session it does not; a wrist-import that applies a rating calls it once; an import that applies none does not.
- S-90-6 Delete: discarding a finished session calls `clearWorkoutEffort` then `deleteWorkouts`, both with the exact span; a discarded running session calls neither.
- S-90-7 Contract fakes: every `HealthPlatformService` fake and the unavailable service compile and answer `unavailable`; nothing in `lib/state`, `lib/features`, `lib/widgets` or `lib/core` outside the gateway imports the channel (grep).
- S-90-8 Native structure (source scan, in the style of the existing source-scan tests): the Runner registers channel `omnitrain/health_effort`; every method body sits behind `#available(iOS 18.0, *)`; `Info.plist` and the entitlements already cover Health (no new key), the update-usage text mentions effort.
- S-90-9 Device checks (owner, QA doc), iPhone on iOS 18+, "Write workouts" switched off then on: (a) finish a session on the watch, rate it 4 on the phone: Fitness shows Workout Effort 8; (b) change the rating to 2: Fitness shows 4; (c) set your own effort in Fitness on a session, then rate it in OmniTrain: your value stays (OQ-2); (d) rate a phone-only session: the same; (e) delete the session in OmniTrain: workout and effort both gone; (f) a rating given on the wrist arrives and appears in Fitness; (g) on first switch-on the Health question lists Workout Effort. Open unknowns these answer: the related-sample read when the owner's value was typed in Fitness, and the delay before a watch workout is found.

Mutation checks (developer records): map to 1 to 5 unscaled (S-90-1 fails); drop the toggle gate (S-90-2); call on a running session (S-90-5); skip `clearWorkoutEffort` (S-90-6).

## Phase 1 - Dart side, fully tested with fakes (D-1 to D-5, D-7)

1. Platform contract, unavailable service, io gateway stub that answers `unavailable` until Phase 2, `health_effort_mapper.dart`.
2. `HealthSyncService.onSessionRated` with retries (injectable clock/delay), `onSessionDeleted` clearing first.
3. Hooks in `SessionCore.updateSessionFeeling` and the wrist-import path.
4. Tests S-90-1 to S-90-7; docs: `docs/state_management/services_and_utils.md` (service paragraph), `docs/theme_and_settings.md` (Write workouts line), `docs/session_summary.md` (one sentence in Effort Rating Capture). Keep each doc net-small (`wc -c`, ceiling 64 KiB).

Done: `flutter test` on touched files; `flutter test test/ui_standards_contract_test.dart test/docs_indexing_contract_test.dart`; `flutter analyze` issue count equal to the baseline (180); `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` empty; full `flutter test` (900 s) green or any failure shown to belong to unrelated uncommitted work.

## Phase 2 - the native piece (D-6)

1. `ios/Runner/HealthEffortChannel.swift` (new), registered from `AppDelegate`; the io gateway calls the channel on iOS only and extends the permission request with the effort type.
2. S-90-8; `NSHealthUpdateUsageDescription` / read text mention effort.
3. `xcodebuild` of the Runner and the watch app succeeds (300 s wrapper); the S-90-9 steps go into `docs/watch-app-qa-wrist-logging.md` (placed by the governor; the file is near 29 KB of 64).

Done: Phase 1 checks still green, build succeeds with the output pasted; nothing is claimed about HealthKit behaviour until the owner runs S-90-9.

Predicted files: Phase 1: `lib/core/services/health_platform_service.dart`, `health_platform_gateway_io.dart`, `health_sync_service.dart`, `health_effort_mapper.dart` (new), `lib/state/workout/session_core_lifecycle.dart`, the wrist-import caller, tests under `test/`, three docs. Phase 2: `ios/Runner/HealthEffortChannel.swift` (new), `AppDelegate.swift`, `Info.plist`, project file entry, one source-scan test, QA doc. Production lines predicted about 350.

## Known limits (stated, not fixed)

- L-1 The watch's workout can take longer than five minutes to reach the phone's Health store; then no effort is written for that rating (a later rating change would write it). A persisted retry would close it.
- L-2 Whether HealthKit lets this app relate its effort sample to a workout the watch app saved is unproven (the delete worked, which is encouraging, not proof). If it refuses, the answer is a wrist-side write (a new frame) and this plan stops at Phase 2 with that finding.
- L-3 Whether the read of related samples sees a value typed in Fitness (OQ-2) is unproven; if it cannot, a typed value could be replaced.

## Progress

- [x] Phase 1 - Dart side: **Complete** 2026-10-28. 27 new tests + 2 fake checks green, M1-M4 (+M5) recorded, full suite +5842 ~2 all passed, analyze 180 (evidence file).
- [x] Phase 2 - native piece: **Complete** 2026-10-29. S-90-8 + gateway tests (9) red then green, M6-M9 recorded, Runner simulator build (watch target included) BUILD SUCCEEDED, full suite +5851 ~2, analyze 180 (evidence file). QA step not placed (governor).
- [ ] Owner device checks S-90-9

## Assumption Log

- Apple's effort type, unit and relate call are as named in D-6 from memory of the iOS 18 API; the developer confirms each name against the SDK headers before writing and records any difference in the evidence file.
- A finished session has exactly one own-source workout; if there are several the earliest is used.
- Retry times are offsets from the first try (waits 20 s, then 70 s, then 210 s), so the window ends at 5 min as L-1 reads; the other reading (three 20/90/300 s waits) was rejected.
- The importer's `_createSession` now reports its rating as `appliedRating`, so a wrist session that arrives already rated reaches Fitness (D-4 "an import that applied a rating"); the adoption callback this also fires is a no-op for a session the phone does not hold.
- Hook placement: `WatchSessionInbox` takes `healthSync` (passed via `createWatchSync` from `main.dart`); no dirty file was edited. `recordPhoneRating` is left unhooked: nothing in `lib/` calls it.
- Not covered (limit): a wrist rating that lands while the phone still runs the session, then the wrist ends it, sends no effort (the rating save sees a running session; the end does not re-send).
- Phase 2 SDK names differ in detail only (identifier `.workoutEffortScore`, `activity: nil` arguments); table in the evidence file. The watch's Estimated Effort type is not read, so it never causes `leftAlone` and is never deleted.
- Permission: the effort request runs first and also shares the workout type, so switching Write workouts on shows one Health sheet (the plugin's request after it has nothing new); its answer never changes the toggle result. Rejected: effort-only request after the plugin's (two sheets).
- `clear` answers `cleared` (true) also when there is no workout or no own effort; a save that cannot be related deletes the sample it just saved (no orphan, L-2) and answers `unavailable`.
