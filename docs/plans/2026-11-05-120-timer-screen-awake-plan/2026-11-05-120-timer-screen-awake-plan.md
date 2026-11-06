# Feature: 120 — Keep the phone screen awake while a work timer runs

> Status: Iteration 1 active (Q&A defaults applied; Q1–Q3 vetoable, see Ledger)
> Next handoff: @developer (Phase 1)
> Binding conventions: `docs/global_conventions.md`, `docs/documentation_standard.md`,
> `.github/copilot/pr-scope-budget.md`; area docs `docs/state_management/workout_state.md`,
> `docs/state_management/services_and_utils.md`, `docs/rest_tracking.md` (rest rule).
> Track: phone app only (`lib/`, plus the Runner's `ios/Runner/AppDelegate.swift` and
> `android/.../MainActivity.kt`). Never branch, never commit, never format a directory.
> Another session edits the same working tree: touch only the Predicted Files below.

## Overview

Owner request (2026-11-05): while a work timer (hold, timed interval, round) is running OR
paused on the phone's workout session screen, the phone must not auto-lock, so the owner can
log the interval without Face ID. With no work timer in progress, or once the owner leaves the
session screen, finishes, ends or discards the session, the normal Auto-Lock applies again.
Timer-only, not whole-session.

Ground truth (planner read, 2026-11-05): no wakelock / idle-timer code exists in `lib/`,
`ios/`, `android/`, `packages/` or `pubspec.yaml` (`grep -rniE "wakelock|idleTimer|keep.?awake"`
→ 0 hits). `WorkoutState.inProgressWorkTimers()` (`lib/state/workout/workout_state.dart:106`,
`TimerManager.inProgressWorkTimers` `timer_manager.dart:178`) already lists active and paused
timed/drill/round instances, returns empty when `hasActiveSession` is false (ended or no
session, `session_core.dart:142`), and every transition that changes it notifies listeners
(start/pause/resume/finish/complete/endEarly/delete, `adoptRemoteWorkTimer`
`session_core_io.dart:270`, `clearSession` `session_core.dart:207`).

## Resolved Decisions (Ledger)

- **D-19501 The one rule.** Keep-awake is ON exactly when all three hold:
  (a) at least one live-mode session screen is attached (D-19505);
  (b) the app is in the foreground (D-19506);
  (c) `workoutState.inProgressWorkTimers().isNotEmpty`.
  Otherwise OFF. Nothing else (no flag, no counter in the screen mixin) feeds the decision.
  Consequences that follow from (c) with no extra code: running and paused both count; timed,
  drill (hold) and round all count; an ended session (`endedAtMs != null`) and a discarded
  session (`currentSession == null`) yield OFF; a finished, completed, ended-early or deleted
  instance drops out.
- **D-19502 What does not count (owner).** The rest count-up, a `set` effort, and the
  session's global elapsed clock never turn keep-awake ON. FLAG for the owner, not a decision
  change: after a work timer ends a rest opens, and the phone may auto-lock during that rest
  (it starts the normal Auto-Lock countdown when the hold drops). That is the timer-only choice
  working as asked; no crash path, hot path or stuck-on risk was found that would force
  whole-session.
- **D-19503 (derived, vetoable — Q1) Watch-started timers count.** A timer the watch started and
  the phone adopted (`adoptRemoteWorkTimer`) shows running on the phone's session screen, so it
  is treated like a phone-started one by D-19501(c).
- **D-19504 (derived, vetoable — Q2) No time cap.** An open-ended timed interval (no target)
  keeps the screen awake until it is logged, paused-then-logged, deleted, or the owner leaves
  the screen / ends the session. No separate safety timeout.
- **D-19505 Attach / detach (screen presence).**
  - Only a `WorkoutSessionScreen` with `editMode == false` attaches; an edit-mode screen never
    attaches and never detaches.
  - Attach happens in `initState` (synchronous is allowed: attach never calls
    `notifyListeners`, so the build-phase rule in `docs/global_conventions.md` is not touched).
  - Detach is the first statement of `dispose` (before `removeObserver` and any timer cancel),
    so a later throw in `dispose` cannot leave a hold.
  - Presence is a count: two attached screens hold until both detach. A screen detaches only if
    it attached; the count never goes below 0 and an extra detach is a no-op.
  - (derived, vetoable — Q3) A route pushed above the session screen (exercise picker, info or
    notes sheet, dialogs) keeps the screen mounted, so the hold continues. Leaving = the session
    screen's route is popped or replaced (Back to Home, Finish → Summary, Discard), which
    disposes it.
- **D-19506 Foreground.** Foreground = `AppLifecycleState` is `null`, `resumed` or `inactive`
  (inactive covers Face ID prompts, Control Center, call banners: no churn). `paused`, `hidden`,
  `detached` → OFF. `resumed` re-evaluates D-19501. The controller observes the binding only
  while attached (count > 0) and reads `WidgetsBinding.instance.lifecycleState` at attach.
- **D-19507 Port contract.** `ScreenAwakePort.setKeepAwake(bool on)` is called only when the
  value derived by D-19501 changes, plus once with `false` when the controller is constructed
  (clears a stale hold left by a hot restart / engine restart in a living process). Evaluation
  runs on every `WorkoutState` notification while attached and on attach, detach and lifecycle
  change; it is O(efforts), never notifies, never awaits the port on the notify path, and is
  wrapped so a port or evaluation error is `debugPrint`ed and swallowed (never reaches
  `WorkoutState.error`, never stops later evaluations). After a failed call the controller
  still records the attempted value as sent (no retry loop).
- **D-19508 Platform mechanism (technical).** A small native method channel, not a package:
  channel `omnitrain/screen_awake`, method `setKeepAwake`, argument a bare `bool`.
  iOS: `UIApplication.shared.isIdleTimerDisabled = on`, written inline in
  `ios/Runner/AppDelegate.swift` after `GeneratedPluginRegistrant.register` (no new Swift file,
  so `project.pbxproj` is untouched). Android: `MainActivity` overrides `configureFlutterEngine`
  and adds / clears `WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON` on the activity window.
  Every other platform (web, macOS, test host) gets the no-op port. Why not `wakelock_plus`:
  its current 1.8.2 needs `package_info_plus >=10.1.0`, the app is on 8.3.1, and it adds dbus
  and win32; the native piece is about 25 lines on two platforms.
  Both native flags are per-process / per-window: process death or backgrounding releases them
  at OS level, so a crash cannot leave the device stuck awake.
- **D-19509 Ownership (technical).** Interface `ScreenAwakePort` (+ `ScreenAwakePort.noop()`)
  in `lib/core/services/screen_awake_port.dart`; channel implementation and the factory
  `createScreenAwakePort()` (no-op when `kIsWeb` or `defaultTargetPlatform` is not iOS/Android)
  in `lib/core/platform/screen_awake_channel.dart`. Controller `SessionScreenAwake` in
  `lib/state/workout/session_screen_awake.dart`, constructed by `WorkoutState` from a new
  optional named parameter `ScreenAwakePort? screenAwake` (default no-op) and exposed as
  `WorkoutState.screenAwake`. `lib/main.dart` (`WorkoutState(` at :389) passes
  `createScreenAwakePort()`. Why through `WorkoutState`: the session screen already receives it
  at all 11 construction sites; a new screen parameter would need threading through 6 screens,
  and a missed site would silently no-op. Only `lib/main.dart` imports the channel file.
- **D-19510 Expiry and finish paths need no new screen code.** Expiry already calls
  `finishTimedEntry` / `completeRound` (`workout_session_timer_mixin.dart`
  `_handleEffortTimerExpired`, `_restoreTimerStateFromPersisted`), Finish calls
  `_persistActiveEffortTimers` then `endSession`, Discard calls `discardCurrentSession`, the
  watch end/discard goes through the same state methods; each empties
  `inProgressWorkTimers()` and notifies. The mixin is NOT edited.

## Feature Invariants

- Keep-awake is a pure function of D-19501's three inputs; no second source of truth.
- `lib/state/` and `lib/features/` depend on `ScreenAwakePort` only; the channel class is
  imported by `lib/main.dart` alone (guarded by S-19518).
- The controller never calls `notifyListeners` and never throws into `WorkoutState`.
- The rest rule in `docs/global_conventions.md` is unchanged: rest adds no keep-awake.

## Requirements and Acceptance Criteria

| AC | Requirement | Scenarios |
|---|---|---|
| AC-1 | Running or paused timed / hold / round on the open session screen keeps the phone awake | S-19501, S-19502, S-19505, S-19520, S-19522 |
| AC-2 | No work timer in progress → normal Auto-Lock | S-19503, S-19504, S-19513, S-19514 |
| AC-3 | Leaving the screen, finishing, ending, discarding → normal Auto-Lock | S-19507, S-19508, S-19509, S-19520 |
| AC-4 | Backgrounding releases; returning re-applies | S-19510 |
| AC-5 | Watch-started timer behaves like a phone one (Q1) | S-19506 |
| AC-6 | Edit mode, platforms without the native piece, port errors never break anything | S-19511, S-19515, S-19516, S-19517, S-19521 |
| AC-7 | No stuck-on: dedupe, refcount, startup reset | S-19512, S-19516 |
| AC-8 | Native pieces and layer boundary are in place | S-19518, S-19519 |

## Existing-Functionality Impact

| Touched surface | Readers (grep that found them) | Effect | Guard |
|---|---|---|---|
| `WorkoutState(` constructor gains an optional param | `grep -rn "WorkoutState(" lib` → `lib/main.dart:389`, `lib/state/watch/live_session_mirror_debug_main.dart:344`; `grep -rl "WorkoutState(" test \| wc -l` → 150 files | Optional, default no-op: no call site changes except `main.dart` | S-19516 (construction sends `false` once; no-op default) + phase suites |
| `WorkoutSessionScreen` `initState` / `dispose` | `grep -rn "WorkoutSessionScreen(" lib` → 11 sites (home ×5, calendar day list, my routines, exercise detail, summary, overview ×2); 46 test files construct it | With the default no-op port, attach/detach only adds/removes a binding observer | S-19520, S-19521; `test/initstate_notify_contract_test.dart`, `test/session_screen_build_phase_notify_test.dart`, `test/delete_focused_timer_test.dart` stay green |
| `ios/Runner/AppDelegate.swift` | `test/health_effort_native_test.dart` (S-90-8 asserts `HealthEffortChannel.register(` after `GeneratedPluginRegistrant.register`) | New channel lines added after the registrant; health lines unchanged | that test in Phase 1 Done Criteria |
| `android/app/src/main/kotlin/dev/sasha/omnitrain/MainActivity.kt` | `grep -rln "MainActivity" test lib` → none | Gains `configureFlutterEngine` | S-19519 |
| `inProgressWorkTimers()` (read only) | `lib/state/watch/watch_timer_push.dart:256`, `test/in_progress_work_timers_test.dart`, `test/watch_timer_push_test.dart` | Unchanged; one new reader | those tests in Phase 1 Done Criteria |
| Timer mixin, rest notifications, expiry notifications | `lib/features/session/workout_session_timer_mixin.dart` | Not edited (D-19510) | Predicted Files exclude it |
| `pubspec.yaml` / `Podfile.lock` | — | Not edited (D-19508) | Predicted Files exclude them |

## UI Standards Impact

None: no widget, text or layout changes.

## Questions (one batched round; plan proceeds on the defaults)

> **Owner answered 2026-11-05: all defaults accepted (Q1 yes, Q2 no limit, Q3 yes).** D-19503, D-19504 and D-19505 are no longer vetoable.

- **Q1** A timer started on the watch, with the phone's session screen open: should the phone
  stay awake too? **Default: yes**, same as a phone-started timer (D-19503).
- **Q2** A timed interval with no set length left running: keep the screen on until you stop
  or log it, or switch off after a limit? **Default: until you stop or log it, no limit**
  (D-19504).
- **Q3** With a timer running, opening the exercise list, an info/notes sheet or a dialog on
  top of the session: keep the screen on? **Default: yes**; only going back to Home, finishing
  or discarding ends it (D-19505).

## Scenarios

Shared state fixture `F-S` (plain `test()`, `MockWorkoutRepository` initialised, a
`FakeScreenAwakePort` from `test/helpers/fake_screen_awake_port.dart` recording every
`setKeepAwake` value in order in `calls`, `WorkoutState(repo, screenAwake: fake)`,
`TestWidgetsFlutterBinding.ensureInitialized()`; lifecycle driven through the controller's
`didChangeAppLifecycleState`). Exercises are picked like `test/in_progress_work_timers_test.dart`
`_exerciseWith(repo, capability)`. Unless stated, the test attaches once after setup.
`calls` always starts `[false]` (construction, D-19507).

### S-19501: running timed interval keeps awake
- Fixture: F-S; session `cardio_endurance`; one effort from the first `time` exercise (kind
  `timed`), entry 0 notStarted.
- Trigger: `startTimedEntry(e, 0)`.
- Expected: `calls == [false, true]`; `screenAwake.isKeepingAwake` true.
- Edge case of: none

### S-19502: paused keeps awake, resume sends nothing
- Fixture: S-19501 after start.
- Flow: `pauseTimedEntry(e,0)`, `resumeTimedEntry(e,0)`, `pauseTimedEntry(e,0)`.
- Expected: `calls == [false, true]` throughout.
- Edge case of: S-19501

### S-19503: expiry / finish releases (hold and round)
- Fixture: F-S; (a) session `isometric_stretching`, `time` exercise (kind `drill`), entry 0
  started; (b) separate state, session `sports`, `rounds` exercise (kind `round`), round 0
  started.
- Trigger: (a) `finishTimedEntry(e,0)` (what `_handleEffortTimerExpired` calls); (b)
  `completeRound(e,0)`.
- Expected: each `calls == [false, true, false]`; a rest opened afterwards
  (`recordRestStart(e, 1)`) adds no call.
- Edge case of: S-19501

### S-19504: paused round ended early releases
- Fixture: F-S; `sports`, `rounds` exercise, round 0 started then paused.
- Trigger: `endRoundEarly(e,0)`.
- Expected: `calls == [false, true, false]`.
- Edge case of: S-19503

### S-19505: two timers at once
- Fixture: F-S; `sports`; effort R from the `rounds` exercise (kind `round`); effort T from the
  same exercise added with `effortKindOverride: 'timed'` (as in
  `in_progress_work_timers_test.dart` "kinds are ordered by wire kind name").
- Flow: `startRound(R,0)`, `startTimedEntry(T,0)`, `completeRound(R,0)`, `finishTimedEntry(T,0)`.
- Expected: after both starts `[false, true]`; after `completeRound` still `[false, true]`;
  after `finishTimedEntry` `[false, true, false]`.
- Edge case of: S-19501

### S-19506: watch-started timer adopted (Q1 default)
- Fixture: F-S; `cardio_endurance`; timed effort E, entry 0 notStarted; `now` = real clock.
- Trigger: `adoptRemoteWorkTimer(E, RemoteWorkTimer(wireKind: 'elapsed', startedAtMs: now - 5000))`.
- Expected: returns true; `calls == [false, true]`; then `finishTimedEntry(E,0)` →
  `[false, true, false]`.
- Edge case of: S-19501

### S-19507: screen disposed while running
- Fixture: S-19501 after start.
- Flow: `detach()`; then `attach()` again.
- Expected: after detach `[false, true, false]` and `inProgressWorkTimers()` still has length 1
  (the timer itself is untouched); after re-attach `[false, true, false, true]`.
- Edge case of: S-19501

### S-19508: session discarded while running
- Fixture: S-19501 after start.
- Trigger: `discardCurrentSession()`.
- Expected: `[false, true, false]`; `currentSession` null.

### S-19509: session ended while running (phone Finish or watch end)
- Fixture: S-19501 after start, and a second state with a round paused.
- Trigger: `endSession()`.
- Expected: each ends `[..., true, false]`.

### S-19510: backgrounded and back
- Fixture: S-19501 after start.
- Flow: lifecycle `inactive` → `paused` → `hidden` → `resumed`.
- Expected: `inactive` adds nothing; `paused` adds `false`; `hidden` adds nothing; `resumed`
  adds `true` → `[false, true, false, true]`.

### S-19511: not attached means never awake
- Fixture: F-S without attach; `cardio_endurance` timed effort.
- Trigger: `startTimedEntry(e,0)`; `adoptRemoteWorkTimer` on a second entry.
- Expected: `calls == [false]`.

### S-19512: presence is counted, never negative
- Fixture: F-S without the default attach.
- Flow: `attach()`, `attach()`, `startTimedEntry(e,0)`, `detach()`, `detach()`, `detach()`.
- Expected: after start `[false, true]`; first detach adds nothing; second adds `false`; the
  third adds nothing and throws nothing; a following `attach()` adds `true` (count is 1, not 0).

### S-19513: rest and sets never count
- Fixture: F-S; `createNewSession()` with no modality; one effort from
  `(await repo.getExercises()).first` (assert `effortKind == 'set'`, exactly as
  `in_progress_work_timers_test.dart` "a set effort lists nothing"); `addEntry(e)`;
  `recordRestStart(e, 1)`.
- Expected: `inProgressRest()` is non-null and `calls == [false]`.

### S-19514: running set deleted
- Fixture: `cardio_endurance`; timed effort with two entries (`addEntry`); entry 0 started.
- Trigger: `deleteTimedEntry(e, 0)`.
- Expected: `[false, true, false]`; `inProgressWorkTimers()` empty.

### S-19515: platform without the native piece
- Fixture: `MethodChannelScreenAwakePort` on a `MethodChannel('omnitrain/screen_awake')` with
  (a) no mock handler (MissingPluginException), (b) a handler that throws
  `PlatformException(code: 'x')`, (c) a recording handler.
- Expected: (a) and (b) `setKeepAwake(true)` completes normally; (c) records exactly
  `MethodCall('setKeepAwake', true)` then `('setKeepAwake', false)`.
  `createScreenAwakePort()` with `debugDefaultTargetPlatformOverride = TargetPlatform.macOS`
  returns a no-op port (no channel traffic in a recording handler).

### S-19516: dedupe on a hot path, startup reset once
- Fixture: S-19501 after start.
- Flow: 20 calls of `updateSessionNote('n$i')` (each notifies), plus pause/resume ×3.
- Expected: `calls == [false, true]` (no extra calls). A fresh `WorkoutState(repo)` with no
  port argument constructs without error (default no-op).

### S-19517: port that throws does not break state
- Fixture: F-S with a `ThrowingScreenAwakePort` (every call throws `StateError`).
- Flow: start, pause, finish a timed entry.
- Expected: every call completes; `state.error` is null after each; the instance ends
  `finished`.

### S-19518: layer guard (structural)
- Fixture: the source tree.
- Expected: `grep -rln "screen_awake_channel" lib` returns exactly `lib/main.dart`; the channel
  name constant in `lib/core/platform/screen_awake_channel.dart` equals
  `'omnitrain/screen_awake'`.

### S-19519: native pieces present (source scan)
- Fixture: `ios/Runner/AppDelegate.swift`, `MainActivity.kt`, `project.pbxproj`.
- Expected: AppDelegate contains `"omnitrain/screen_awake"`, `"setKeepAwake"` and
  `isIdleTimerDisabled`, with the channel set up after `GeneratedPluginRegistrant.register`;
  MainActivity contains the channel name, `configureFlutterEngine`, `FLAG_KEEP_SCREEN_ON`,
  `addFlags` and `clearFlags`; `project.pbxproj` contains no `ScreenAwake`.

### S-19520: the live screen attaches and releases on pop (widget, Mock-only)
- Fixture: harness as `test/delete_focused_timer_test.dart` `_buildDeps` but
  `WorkoutState(repo, screenAwake: fake)`; session `cardio_endurance`; timed effort with entry 0
  started via `startTimedEntry` BEFORE pumping; a `MaterialApp` home with a button that pushes
  the session screen (so it can be popped).
- Flow: push, `pumpAndSettle`; then `Navigator.pop`, `pumpAndSettle`.
- Expected: after push `calls.last == true`; after pop `calls.last == false` and the timer is
  still in `inProgressWorkTimers()`.

### S-19521: edit mode never attaches (widget, Mock-only)
- Fixture: as S-19520, screen built with `editMode: true`.
- Expected: `calls == [false]` after pump and after pop; `screenAwake.attachedCount == 0`.

### S-19522: tapping Start on the screen acquires (widget, Mock-only)
- Fixture: as S-19520, entry 0 notStarted; open the detail view as
  `delete_focused_timer_test.dart` `_openDetailView` does.
- Trigger: tap the timer start control; `pump()`.
- Expected: `calls.last == true`.

## Iteration 1

### Phase 1: port, native channel, controller, wiring (@developer)
1. [ ] Add `ScreenAwakePort` + `noop()` (D-19509) — `lib/core/services/screen_awake_port.dart`
2. [ ] Add `MethodChannelScreenAwakePort`, `screenAwakeChannelName`, `createScreenAwakePort()`
   (D-19507, D-19508) — `lib/core/platform/screen_awake_channel.dart`
3. [ ] iOS channel inline in `ios/Runner/AppDelegate.swift`; Android in `MainActivity.kt`
   (D-19508)
4. [ ] Add `SessionScreenAwake` (`attach`, `detach`, `attachedCount`, `isKeepingAwake`,
   lifecycle observer, D-19501/05/06/07) — `lib/state/workout/session_screen_awake.dart`
5. [ ] `WorkoutState`: optional `screenAwake` param, `screenAwake` getter —
   `lib/state/workout/workout_state.dart`
6. [ ] `lib/main.dart`: pass `createScreenAwakePort()` to `WorkoutState(` (:389)
7. [ ] Tests S-19501–S-19519 — `test/helpers/fake_screen_awake_port.dart`,
   `test/session_screen_awake_test.dart`, `test/screen_awake_channel_test.dart`
8. [ ] Evidence (baseline analyze count, suite counts, red→green for S-19501 with item 5's
   wiring stashed) in the evidence file; Progress + Assumption Log here

**Done Criteria** (run until green; wrap with `bash .claude/scripts/macos/with-timeout.sh 900`):
`flutter analyze` (issue count ≤ baseline recorded at phase start);
`flutter test test/session_screen_awake_test.dart test/screen_awake_channel_test.dart test/in_progress_work_timers_test.dart test/remote_work_timer_state_test.dart test/health_effort_native_test.dart test/initstate_notify_contract_test.dart`;
`flutter test test/ui_standards_contract_test.dart test/docs_indexing_contract_test.dart`;
`grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` → empty.
**Predicted Files**: the 3 `lib/` files created in items 1, 2, 4; `lib/state/workout/workout_state.dart`;
`lib/main.dart`; `ios/Runner/AppDelegate.swift`;
`android/app/src/main/kotlin/dev/sasha/omnitrain/MainActivity.kt`; the 3 test files of item 7;
this plan's evidence file. Nothing else (not `pubspec.yaml`, not `project.pbxproj`, not the mixin).

### Phase 2: screen attach/detach, widget tests, docs (@developer)
1. [ ] `_WorkoutSessionScreenState.initState`: attach when `!widget.editMode`, remember it;
   `dispose`: detach first if attached (D-19505) — `lib/features/session/workout_session_screen.dart`
2. [ ] Widget tests S-19520–S-19522, Mock-only `testWidgets` (persisting taps Mock-only) —
   `test/session_screen_awake_widget_test.dart`
3. [ ] Docs: `SessionScreenAwake` section (structure, D-19501 rule as rationale, pointers to
   S-19501/S-19507/S-19510/S-19520) — `docs/state_management/workout_state.md` (27.8 KB, band 52 KB)
4. [ ] Docs: `ScreenAwakePort` + channel paragraph, pointer to S-19515/S-19519 —
   `docs/state_management/services_and_utils.md` (36.4 KB)
5. [ ] Docs: lookup rows for `ScreenAwakePort`, `SessionScreenAwake` — `docs/state_management.md` (11.2 KB)
6. [ ] Evidence + Progress + Assumption Log

**Done Criteria**: `flutter analyze` (≤ baseline);
`flutter test test/session_screen_awake_widget_test.dart --plain-name "Mock"`;
`flutter test test/session_screen_awake_test.dart test/initstate_notify_contract_test.dart test/session_screen_build_phase_notify_test.dart test/delete_focused_timer_test.dart test/count_up_screen_test.dart`;
`flutter test test/ui_standards_contract_test.dart test/docs_indexing_contract_test.dart`;
the hive-import grep above → empty.
**Predicted Files**: `lib/features/session/workout_session_screen.dart`,
`test/session_screen_awake_widget_test.dart`, the 3 docs above, this plan's evidence file.

### Phase 3: review (@code-reviewer)
Diff vs Predicted Files; per-S-id conformance; Impact table greps re-run; the conventions
table PASS/N/A/FAIL; findings to `2026-11-05-120-timer-screen-awake-plan.review.md`.
Owner device checks (governor relays, iPhone): (1) start a hold, leave the phone untouched
longer than Auto-Lock: screen stays on; (2) pause it: stays on; (3) let it finish: screen
locks after the normal Auto-Lock time; (4) with a timer running, go Back to Home: locks
normally; (5) watch-started timer with the session screen open: stays on.

## Files Affected

Created: `lib/core/services/screen_awake_port.dart`, `lib/core/platform/screen_awake_channel.dart`,
`lib/state/workout/session_screen_awake.dart`, 4 test files. Edited: `workout_state.dart`,
`main.dart`, `workout_session_screen.dart`, `AppDelegate.swift`, `MainActivity.kt`, 3 docs.
Read-only dependents: `watch_timer_push.dart`, the 11 screen construction sites.
About 220 predicted production lines.

## Notes

- Dependency graph: Phase 2 needs Phase 1 items 4–5. No reordering gains anything.
- Intermediate state after Phase 1: the controller exists but nothing attaches, so the app
  behaves exactly as today (S-19511 shape) on device.
- Intermediate on device (D-19510): app backgrounded past a timer's end, then reopened, holds
  for at most one tick (`_kTimerUpdateInterval`, `workout_session_screen.dart:53`) until the
  tick finishes the instance.
- No persisted data, schema, seed or watch contract changes; no legacy handling.

## Noticed, not planned

- `docs/state_management/watch_surface_wrist.md` is 52.2 KB, already past the 52 KB split band.
- `docs/modality_based_exercise_ui.md` is 47.7 KB, close to the band.
- `wakelock_plus` cannot be added without moving `package_info_plus` from 8 to 10.

## Progress

- [ ] Phase 1
- [ ] Phase 2
- [ ] Phase 3 review

## Assumption Log

## Feedback
