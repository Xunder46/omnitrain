# Review: plan 120 timer-screen-awake · Phase 3 · base..working tree
Verdict: APPROVE
Counts: blocker 0 · major 0 · minor 1 · tests: not run (brief says the governor did; established facts: 52+ targeted tests green, analyze 181 = baseline with none in these files)
Diff vs Predicted Files: conforms for this unit's paths. The working tree also carries changes outside the plan's Predicted Files — `lib/data/models/models.dart`, `lib/state/workout/timer_manager.dart`, `lib/state/routine/routine_state.dart`, `docs/data_models.md`, `docs/my_routines.md`, `test/models_test.dart`, `test/state_test.dart`, `test/watch_timer_adoption_test.dart` — which the brief attributes to concurrent sessions in this tree; not reviewed, not counted against this unit.

## Findings
1. [Minor] docs/state_management/workout_state.md:82 — the foreground rule is stated as "resumed or inactive; paused, hidden and detached are off", but `lib/state/workout/session_screen_awake.dart` `_isForeground` also treats a `null` lifecycle state as foreground (D-19506 explicitly includes null: no lifecycle event yet). A maintainer asking "why is the hold on before any lifecycle callback" finds no answer in the doc. Fix: add "or no lifecycle event yet" to the parenthetical. Guard: none (doc sentence; behaviour is tested by S-19510's shape).

## Assumption Log rulings
The plan's `## Assumption Log` is empty; no entries to rule on. D-19503/04/05 were ratified by the owner (Q1–Q3 accepted, noted in the plan). Whether the builders logged implementation assumptions lives in the plan's evidence file, which is outside this review's path list — not checked.

## Scenario coverage
- S-19501 -> test/session_screen_awake_test.dart · "S-19501 a running timed interval keeps awake" ([false, true], isKeepingAwake true)
- S-19502 -> test/session_screen_awake_test.dart · "S-19502 paused keeps awake, resume sends nothing" ([false, true] throughout)
- S-19503 -> test/session_screen_awake_test.dart · "S-19503 expiry / finish releases (hold and round)" (drill finishTimedEntry and round completeRound each [false, true, false]; rest adds no call)
- S-19504 -> test/session_screen_awake_test.dart · "S-19504 a paused round ended early releases" ([false, true, false])
- S-19505 -> test/session_screen_awake_test.dart · "S-19505 two timers at once" ([false, true] through completeRound, [false, true, false] after finishTimedEntry)
- S-19506 -> test/session_screen_awake_test.dart · "S-19506 a watch-started timer adopted keeps awake" (adopt true, [false, true], finish → [false, true, false])
- S-19507 -> test/session_screen_awake_test.dart · "S-19507 screen disposed while running" (detach [false, true, false], timers length 1, re-attach adds true)
- S-19508 -> test/session_screen_awake_test.dart · "S-19508 a discarded session releases" ([false, true, false], currentSession null)
- S-19509 -> test/session_screen_awake_test.dart · "S-19509 a session ended while running releases" (timed and paused-round states each end [..., true, false])
- S-19510 -> test/session_screen_awake_test.dart · "S-19510 backgrounded and back" (inactive/hidden add nothing, paused adds false, resumed adds true)
- S-19511 -> test/session_screen_awake_test.dart · "S-19511 not attached means never awake" (start and adopt with no attach → [false])
- S-19512 -> test/session_screen_awake_test.dart · "S-19512 presence is counted, never negative" (attach×2, detach×3 with the third a no-op, re-attach adds true)
- S-19513 -> test/session_screen_awake_test.dart · "S-19513 rest and sets never count" (inProgressRest non-null, calls [false])
- S-19514 -> test/session_screen_awake_test.dart · "S-19514 a running set deleted releases" ([false, true, false], inProgressWorkTimers empty)
- S-19515 -> test/screen_awake_channel_test.dart · "S-19515a no handler…", "S-19515b a throwing handler is swallowed", "S-19515c a recording handler sees both calls in order", "S-19515d createScreenAwakePort on macOS is a no-op, no channel traffic"
- S-19516 -> test/session_screen_awake_test.dart · "S-19516 dedupe on a hot path, startup reset once" (20 notes + 3 pause/resume → [false, true]; fresh WorkoutState without a port constructs)
- S-19517 -> test/session_screen_awake_test.dart · "S-19517 a port that throws does not break state" (error null after each call, instance finished)
- S-19518 -> test/screen_awake_channel_test.dart · "S-19518 the channel file is imported by lib/main.dart alone", "S-19518 the channel name constant" (independently confirmed by grep this run: only `lib/main.dart` imports the channel)
- S-19519 -> test/screen_awake_channel_test.dart · "S-19519 the iOS piece is inline in AppDelegate after the registrant", "S-19519 the Android piece is in MainActivity.kt", "S-19519 project.pbxproj has no ScreenAwake"
- S-19520 -> test/session_screen_awake_widget_test.dart · "S-19520: a live session screen attaches on push and releases on pop, and the running timer survives the pop"
- S-19521 -> test/session_screen_awake_widget_test.dart · "S-19521: an edit-mode session screen never attaches and never detaches" (calls [false], attachedCount 0)
- S-19522 -> test/session_screen_awake_widget_test.dart · "S-19522: tapping Start on the session screen acquires the keep-awake" (calls.last true)

All 22 scenario ids have a test that asserts the plan's expected value.

## The five questions
1. **D-19501/05/06/07 conformance — yes.** `_evaluate` computes `want = _attached > 0 && _foreground && _hasWorkTimer()` and sends only on change (D-19501, dedupe). Presence is a refcount; `detach` returns when the count is 0, so it never goes negative and an extra detach is a no-op (D-19505). Foreground is null/resumed/inactive; the observer is added on the first attach and removed on the last detach, and the state is read from `WidgetsBinding.instance.lifecycleState` at attach (D-19506). The port is called once with `false` at construction, `unawaited` on the notify path, `_sent` is recorded before the send so a failed call still counts as attempted, and both `_evaluate` and `_send` swallow errors with `debugPrint`; the class has no `notifyListeners` (D-19507).
2. **No path found where the hold stays ON after the screen leaves.** Detach is the first statement of `_WorkoutSessionScreenState.dispose`, guarded by a `_screenAwakeAttached` flag set only when attach happened, so a later throw in dispose cannot skip it and an edit-mode screen neither attaches nor detaches. A replaced route disposes the old screen like a pop. A throwing port cannot wedge the controller: sync throws are caught in `_send`, async ones in `catchError`, and the OS-level flags are per-process/per-window (D-19508). The one accepted residual is D-19507's no-retry rule: if the OFF call fails after a successful ON, the native hold persists until process death or the next successful evaluation — plan-ratified, not a defect.
3. **AppDelegate health lines untouched.** The diff shows the ScreenAwake block inserted after the `HealthEffortChannel.register` lines and before `return super.application(...)`; the health lines appear only as context, order preserved (registrant → health → screen awake → super). Matches the S-90-8 guard's expectation.
4. **Docs vs code — one Minor (finding 1).** Everything else checked true against the code: the `screenAwake` constructor param and getter, the no-op fallback, the refcount/lifecycle-observer description, the construction-time `false`, the swallowed port errors, the channel name, the platform split of `createScreenAwakePort()`, the "only main.dart imports the channel" claim (grep-confirmed), and every named test in both "Verified by" paragraphs exists verbatim with the quoted names.
5. **Outside Predicted Files:** only the concurrent-session files listed under "Diff vs Predicted Files"; nothing else.
