# Feature: 72 — the session summary fills in the watch's heart rate when it arrives after the screen opened

> Status: Iteration 1 active. No owner question (the heart-rate row appears by itself a moment later instead of needing a reopen). One track: phone (`lib/`). Depends on plan 71's Phase 1 (`WatchSessionImport.sensorSummaryAttached`).
> Next handoff: `crew-builder-app` (Phase 1 production + unit tests, Phase 2 screen test).
> Base: `c1b1c5f0` on `claude_develop`. Never create or switch branches; git belongs to the governor.
> Binding: `docs/global_conventions.md`; `.github/copilot/pr-scope-budget.md`; the repository pattern.

## Overview

| What you do | Now | After 72 |
|---|---|---|
| Finish a workout on the phone; the summary screen opens at once; the watch's heart-rate numbers arrive a few seconds later | The screen read heart rate once when it opened, so no heart-rate row until you leave and reopen | The Avg / Max heart-rate row appears by itself when the numbers arrive |
| Heart rate was there already | Shown | Shown, unchanged |
| The summary of an older session (opened from the calendar) while the watch delivers something | — | Re-reads only if the numbers are for that session |

Code facts (scouts + lead, 2026-10-24):
- `SessionSummaryScreen` (`lib/features/session/session_summary_screen.dart`) reads heart rate once, in `_loadAsyncData` (l.202-204, `widget.sessionSummaryService.getSessionHeartRate(currentSession.id)`), called from `initState` (l.164) and from `_refreshSummary` (l.267-272). It listens to `widget.workoutState` only for `_closeAutoSheetOnOutsideRating` (l.288). The heart-rate row is `_heartRate` (l.99, row key `omni_session_heart_rate_row`).
- The phone stores the wrist's summary in `WatchSessionImporter` (`_attachSessionSummary`); `WatchSessionInbox._settleNow` (`lib/state/watch/watch_session_inbox.dart` l.436-466) calls `_onSessionRowsChanged` and `_onSessionRated` after a pass and nothing when only a summary was written. Plan 71 adds `WatchSessionImport.sensorSummaryAttached`.
- Wiring: `lib/state/watch/watch_sync_wiring.dart` l.158-181 `_WiringAdoptionBridge` keeps the bound `WorkoutState` and exposes `adoptRating(sessionId, rating)`; l.226-240 builds the inbox with `onSessionRowsChanged: adoption.refreshHeldEfforts`, `onSessionRated: adoption.adoptRating`.
- `WorkoutState` (`lib/state/workout/workout_state.dart`, `class WorkoutState extends ChangeNotifier`, l.18) is what the summary screen already holds; it notifies the whole app, so a dedicated small notifier is used (D-3).

## Decision Ledger

- **D-1** `WatchSessionInbox` gains `Future<void> Function(String sessionId)? onSensorSummaryAttached` (constructor named parameter beside `onSessionRated`, a field, and the call in `_settleNow` right after the `_onSessionRated` block: `if (pass.sensorSummaryAttached) await _onSensorSummaryAttached?.call(sessionId);`). Fired once per pass that wrote the summary, never otherwise.
- **D-2** `_WiringAdoptionBridge` gets `Future<void> noteSensorSummary(String sessionId) async { _boundState?.noteWristSummary(sessionId); }`, and the wiring passes `onSensorSummaryAttached: adoption.noteSensorSummary`.
- **D-3** `WorkoutState` gets `final ValueNotifier<({String sessionId, int count})?> wristSummary = ValueNotifier(null);` and `void noteWristSummary(String sessionId)` which sets `wristSummary.value = (sessionId: sessionId, count: (wristSummary.value?.count ?? 0) + 1)`. The count makes a second arrival for the same session a new value. It does not call `notifyListeners()`. `dispose()` of `WorkoutState` (if it has one) disposes the notifier.
- **D-4** `SessionSummaryScreen`: `initState` adds a listener on `widget.workoutState.wristSummary`; `dispose` removes it. The handler reads `widget.workoutState.wristSummary.value`; when it is non-null, its `sessionId` equals `widget.workoutState.currentSession?.id` and the screen is `mounted`, it re-reads ONLY the heart rate (`getSessionHeartRate`) and `setState(() => _heartRate = heartRate)`. It does not call `_loadAsyncData` (no loading flicker, no re-run of the group deltas, PRs or calendar read).
- **D-5** Out of scope: the summary on the watch; summaries of effort blocks; any change to when the phone finishes; the summary of a session whose screen is closed (it reads storage when next opened).
- **D-6** Waiting readers: none (a pure notification).

## Scenarios (ids `S-102xx`; grep 2026-10-24: unused)

- **S-10201 (inbox) the callback fires for a pass that stored a summary and for no other.** Fixture: `WatchSessionInbox` over Mock with a recording `onSensorSummaryAttached`; stage a followed completed end with avg 133 / max 171 for a session in history (plan 71's staging helper in `test/watch_followed_end_import_test.dart`; copy it) and call `receive`/the settle path the existing inbox tests use. Expected: callback called once with the session id. Arms (each its own test): an end with no heart rate → not called; the same end settled again → not called a second time; a set row only → not called. Fails today: the parameter does not exist.
- **S-10202 (WorkoutState) `noteWristSummary` publishes the session and counts.** Fixture: fresh `WorkoutState`; call twice with `'a'` then once with `'b'`. Expected: values `(a,1)`, `(a,2)`, `(b,3)`; `notifyListeners` not called (a listener on the state itself stays at 0).
- **S-10203 (wiring) the bridge forwards.** Fixture: build the graph the way `test/watch_sync_wiring_test.dart` (find the name with `grep -ln "createWatchSync" test`) does; bind a `WorkoutState`; run a settle that attaches a summary. Expected: the bound state's `wristSummary.value?.sessionId` is the session id.
- **S-10204 (screen, `testWidgets`, Mock-first, no real delays) the heart-rate row appears when the numbers arrive.** Fixture: copy the harness of `test/session_summary_heart_rate_test.dart` group S-9654..S-9657 (read it: it seeds a session and pumps `SessionSummaryScreen`): a completed session with NO heart rate; pump the screen; expect `find.byKey(const Key('omni_session_heart_rate_row'))` finds nothing; write `SensorSummary` (avg 127.6, max 171.2 as that test does, through `_seedHeartRate`) then call `workoutState.noteWristSummary(sessionId)`; `await tester.pump()` twice. Expected: the row is found and shows `128 bpm` / `171 bpm` (use the exact formatting the S-9654 test asserts).
- **S-10205 (screen) a summary for another session does not re-read.** Same fixture; call `noteWristSummary('some-other-session')` after seeding the summary for this one. Expected: no heart-rate row (the notification named a different session). One `getSessionHeartRate` call is counted via a counting subclass of the Mock (copy `_CountingRepo` from `test/state_test.dart` l.4917).
- **S-10206 (screen) the listener is removed on dispose.** Fixture: pump the screen, pump an empty `SizedBox`, call `noteWristSummary` and pump. Expected: no exception, no `setState after dispose`.
- **S-10207 (source guard) the screen's listener** — the exact statements `widget.workoutState.wristSummary.addListener(` and `widget.workoutState.wristSummary.removeListener(` occur in the file, the handler contains `getSessionHeartRate(` and does not contain `_loadAsyncData(` (extract the handler by its method name).

## Phase 1: production code and unit tests (`crew-builder-app`)

1. [ ] D-1 — `watch_session_inbox.dart`.
2. [ ] D-2 — `watch_sync_wiring.dart`.
3. [ ] D-3 — `workout_state.dart` (find the existing `dispose()`; if none, none is added).
4. [ ] D-4 — `session_summary_screen.dart` (exact code in the brief).
5. [ ] Tests S-10201..S-10203, S-10207 — new `test/watch_summary_notify_test.dart`.
6. [ ] Docs: `docs/state_management/watch_surface.md`, one sentence on the new callback (find where `onSessionRated` is described: `grep -n "onSessionRated" docs -r`).
7. [ ] Report FIRST as a skeleton, then fill it.

## Phase 2: screen tests (`crew-builder-app`, a separate run)

1. [ ] S-10204..S-10206 — new `test/session_summary_late_heart_rate_test.dart`, starting by copying the harness block of `test/session_summary_heart_rate_test.dart`.

**Done**: P1: `flutter test test/watch_summary_notify_test.dart test/watch_followed_end_import_test.dart test/watch_session_inbox_test.dart` (find the inbox test names with `ls test | grep inbox`), `test/session_summary_heart_rate_test.dart`, `flutter analyze` ≤ 180; P2: `flutter test test/session_summary_late_heart_rate_test.dart test/session_summary_heart_rate_test.dart`. Never the full suite.

## Owner device checks

- (owner) ODC-1 Finish a phone workout with the watch on the wrist; open the summary; the heart-rate row appears within a few seconds without leaving the screen.

## Progress
- [x] Phase 1
- [x] Phase 2

## Assumption Log
- Mutants J1..J6 killed; J5 (no `mounted` check) needed S-10206b (a read in flight when the screen goes away).

## Feedback
