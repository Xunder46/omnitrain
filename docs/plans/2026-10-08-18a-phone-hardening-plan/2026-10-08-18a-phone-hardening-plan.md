# Feature: phone hardening — the two crashes in the owner's QA log

> Status: Iteration 1 active (planned 2026-10-08; nobody could answer questions in this run, so every
> owner-visible choice carries a recommended default under `## Open questions` at the end and the plan
> proceeds on those defaults)
> Next handoff: @code-reviewer (Phase 4 complete — all four phases implemented)
> Binding conventions: `docs/global_conventions.md`; plus `docs/state_management/workout_state.md`
> (state layer), `docs/db_integration.md` (migrations), `docs/session_summary.md` (summary numbers)
> Series: `docs/plans/2026-10-08-18-watch-qa-index.md` (18a = this plan; 18b = the watch rest count-up)

## Overview

Two phone-side crashes from the first real-device QA of the watch app. Both are independent of the
watch work and of each other.

1. **A synchronous notify during the first build.** Verbatim from the owner's `flutter run` log:
   `setState() or markNeedsBuild() called during build`, thrown while dispatching notifications for
   `WorkoutState`; stack `SessionCore._setLoading` (`lib/state/workout/session_core.dart:~213`) <-
   `SessionCoreIOMethods.loadSessionData` (`lib/state/workout/session_core_io.dart:~137`) <-
   `WorkoutState.loadSessionData` <- `_WorkoutSessionScreenState._loadExercises`
   (`lib/features/session/workout_session_screen.dart:~432`) <- `initState` (`:~236`); the listener
   marked dirty is a `ListenableBuilder`/`AnimatedBuilder` (`_AnimatedState._handleChange`) inside a
   `LayoutBuilder` being built. It fires when the screen opens with an existing session.
2. **A session whose end precedes its start.** Verbatim: `Unhandled Exception: Invalid argument(s):
   1791419191803 #0 int.clamp #1 SessionSummaryService.computeSessionRestTimeMs
   (lib/core/services/session_summary_service.dart:~33) #2 _SessionSummaryScreenState._loadAsyncData
   (session_summary_screen.dart:~191)`. `num.clamp` throws `ArgumentError(lowerLimit)` when
   `lowerLimit > upperLimit`; the printed argument is `windowStart` = `session.startedAtMs`, so the
   stored row has `endedAtMs < startedAtMs`.

What ships: the app stops crashing, the store stops holding an inverted window, and a structural guard
makes the first defect class impossible to reintroduce. No user-visible rule changes.

## Resolved Decisions (Ledger)

- **D-150 — An initial load never runs inside the first build.** `_WorkoutSessionScreenState.initState`
  (`lib/features/session/workout_session_screen.dart:226`) schedules its load with
  `WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _loadExercises(); })` instead of
  calling `_loadExercises()` at `:236` directly, so the first `notifyListeners()` of that load
  (`_loadExercises` `:415` -> `loadSessionData` `session_core_io.dart:131` -> `_setLoading(true)`
  `:137` -> `_notify()` `session_core.dart:213-216`) happens after the frame that mounted the screen.
  Everything else about the load is unchanged: `_isLoading` already starts `true` (`:109`) so the
  spinner is the first frame's content; `_loadExercises` keeps its `!hasSession -> createNewSession()`
  + `loadSessionData()` calls (`:425-428`), its `catch` that sets `_hasError` (`:507-511`), edit mode
  and rolling-session reordering. The state layer's synchronous notify is **not** changed — a notify
  outside a build is legitimate, and moving it would hide the trap for every future caller.
- **D-151 — The rule, not just the site.** No `initState` in `lib/features/**` may synchronously call a
  method that reaches `WorkoutState`/`SettingsState.notifyListeners()`. Every such site defers through
  `WidgetsBinding.instance.addPostFrameCallback` (or `Future.microtask`); what moves is the call, never
  the callee's own notify. Sites whose `initState` only calls pure readers stay as they are. A
  grep-based contract test (Phase 1 item 7) makes the class permanent.
- **D-152 — The summary can never throw on an inverted session window.** In
  `SessionSummaryService.computeSessionRestTimeMs` (`lib/core/services/session_summary_service.dart:15`)
  `windowEnd` becomes `max(windowStart, session.endedAtMs ?? DateTime.now().millisecondsSinceEpoch)`
  (`:21-22`), so `windowStart <= windowEnd` holds before the clamps at `:33-34`. The clamps and the
  `end > start` filter at `:36` stay. Pinned outcome: a session whose stored `endedAtMs < startedAtMs`
  has an empty window, every rest clips to it, the method returns `0`, and the summary screen renders
  the session with its other metrics untouched.
- **D-153 — An end is never stored before its start (phone-owned writers).** Every writer that derives
  `endedAtMs` from the phone's own clock or from a phone-entered duration stores
  `max(startedAtMs, candidate)`: `SessionCoreLifecycleMethods.endSession`
  (`lib/state/workout/session_core_lifecycle.dart:21`, `now` at `:28`) and
  `SessionCoreLifecycleMethods.updateSessionEndTime` (`:152`). And
  `SessionCoreLifecycleMethods.resetSessionTimerStart` (`:59`) **writes nothing when
  `_currentSession!.endedAtMs != null`**: a session that already has an end is history, and the start
  moving after it is the only way an inverted pair can be produced. The identified mechanism:
  `resetSessionTimerStart` is called from `workout_session_screen.dart:1458` when
  `isFirstExercise && !editMode`, while `WatchSessionAdoptionBridge.onLifecycle`
  (`lib/core/services/watch_session_adoption_bridge.dart:~646`) ends the phone's adopted session when
  the wrist ends it — adding the first exercise afterwards rewrites the start past the stored end.
  Wire-owned values are exempt: `WatchSessionImporter._createSession`
  (`lib/core/services/watch_session_importer.dart:516-517`) keeps the wrist's `startedAt`/`endedAt`
  exactly as sent, because the wrist's own clock is the authority for the wrist's session; D-152 keeps
  the summary safe if such a pair is inverted.
- **D-154 — Rows already inverted in the store are repaired once.** `currentDataVersion` goes 14 -> 15
  (`lib/core/constants/data_version.dart`) with one appended step in both repositories
  (`HiveWorkoutRepository._dataMigrationSteps` `hive_workout_repository.dart:272` and its Mock mirror
  `mock_workout_repository.dart:267`): every session row with `endedAtMs != null && endedAtMs <
  startedAtMs` is rewritten to `endedAtMs = startedAtMs`. The start is never moved (calendar and period
  math key on it) and a running row (`endedAtMs == null`) is never touched. Both repositories run the
  same repair over their own store, so `getSession` returns the same value in both for the same seeded
  row — the parity invariant is what makes the two implementations interchangeable.

## Feature Invariants

- `HiveWorkoutRepository` and `MockWorkoutRepository` produce the same observable output for the same
  inputs, migration steps included (D-154).
- `lib/state/` depends on `WorkoutRepository` only; no phase here touches a concrete implementation
  outside the two repositories.
- A persisted session row is only ever written through the state layer's lifecycle methods; nothing in
  this PR writes a session row from a screen.
- The SQL contract is unaffected: no schema change, so `scripts/sqlite_schema.sql`,
  `scripts/sqlite_seed.sql` and `test/db_seed_test.dart` are untouched by every phase.

## Requirements

- R-1 Opening `WorkoutSessionScreen` (live or edit mode, rolling or watch-adopted session) throws no
  build-phase notification error, and still shows the spinner then the session. (D-150, D-151)
- R-2 No other `initState` in `lib/features/**` has the same trap, and a test prevents a new one.
  (D-151)
- R-3 `SessionSummaryService.computeSessionRestTimeMs` never throws; an inverted window contributes no
  rest, an ordinary session's rest total is unchanged. (D-152)
- R-4 An end can no longer be stored before its start by any phone-owned writer. (D-153)
- R-5 Rows already stored inverted are repaired once, identically in both repositories. (D-154)
- R-6 Every fix ships with a test that is red at the base (`prove-red`). (all)

## Acceptance Criteria

- AC-1 -> S-150: mounting the session screen under an ancestor that listens to `WorkoutState` raises no
  exception.
- AC-2 -> S-151: the spinner-then-content sequence and the failing-load path are preserved.
- AC-3 -> S-152: the second `initState` loader is fixed and covered.
- AC-4 -> S-153, S-154: the inverted window yields `0` instead of throwing; the normal case is
  unchanged.
- AC-5 -> S-155: the real writer path can no longer produce an inverted pair.
- AC-6 -> S-156: a store holding an inverted row is repaired, once, in both repositories.

## Existing-Functionality Impact

| Touched surface | What already reads it (grep) | Effect of the change | Guarded by |
|---|---|---|---|
| `WorkoutSessionScreen.initState` / `_loadExercises` | `WorkoutSessionScreen(` appears in `test/screen_widget_test.dart` (~30 pumps), `test/pr4_session_controls_test.dart:53`, `test/exercise_detail_emphasis_tier_test.dart` (5), `test/screen_widget_test.dart:9279`; production entry points `lib/features/home/home_screen.dart` (5 pushes, see `docs/history/route-migration-audit.md:29-34`) | the load runs one frame later; frame 1 is the spinner exactly as today (`_isLoading = true`, `:109`) | S-150, S-151 |
| `WorkoutState.loadSessionData` | definition `session_core_io.dart:131`; callers `workout_session_screen.dart:428`, `session_overview_screen.dart:56`, `session_core_lifecycle.dart:376`; tests `test/watch_session_auto_push_test.dart:625/673/700/1222`, `test/watch_session_edit_restore_summaries_test.dart:238/455`, `test/screen_widget_test.dart:8057/8521/8527` | none — the method and its notify are unchanged; only *when the screen* calls it moves | S-151 |
| `resetSessionTimerStart` | definition `session_core_lifecycle.dart:59`; single call site `workout_session_screen.dart:1458` (`isFirstExercise && !editMode`) | a session that already ended keeps its window when a first exercise is added afterwards | S-155 |
| `endedAtMs` writers | `endSession` `session_core_lifecycle.dart:21/28`, `updateSessionEndTime` `:152`, `WatchSessionImporter._createSession` `watch_session_importer.dart:516-517` (exempt, D-153) | no inverted pair is produced by the phone; a running row is untouched | S-155, S-156 |
| `endedAtMs` readers | guards (`!= null`) across `session_core*.dart`, `stats_progress_service.dart`, calendar code, and the summary's window (`session_summary_service.dart:22`) | an inverted row can no longer exist; nothing else changes | S-156 |
| `computeSessionRestTimeMs` | `grep -rn computeSessionRestTimeMs lib/` -> only caller `lib/features/session/session_summary_screen.dart:192`; documented at `docs/session_summary.md:217/249` | an inverted window yields `0` instead of throwing; normal sessions unchanged | S-153, S-154 |
| Migration step list + `currentDataVersion` | `test/data_migration_test.dart` (sequence, shim, retry, idempotency), `docs/db_integration.md:156-215` (the append-a-step rule; no per-step table exists) | one appended step, version 15; no meta-box key, no schema change | S-156 |
| `SessionOverviewScreen.initState` | `_initializeSession` `session_overview_screen.dart:48` (called from `initState` `:46`), `_isLoading` `:41`; screen used from the session entry flows (`docs/navigation_and_screens.md`) | the same deferral as D-150; the spinner/error path is unchanged | S-152 |

## Scenarios

### S-150: opening the session screen with an existing session notifies nobody during build
- Fixture: `MockWorkoutRepository` with one in-progress session (1 segment, 1 slot for a
  `load`-capable exercise, 1 logged set at `entryIndex 0`, `endedAtMs: null`); a `WorkoutState` on it;
  the harness is `MaterialApp(home: ListenableBuilder(listenable: workoutState, builder: (_, __) =>
  WorkoutSessionScreen(workoutState: …, editMode: false, …)))` — the ancestor listens to the same
  state, which is exactly the production hierarchy (an `AnimatedBuilder` on `WorkoutState` inside a
  `LayoutBuilder` that is building).
- Trigger: `await tester.pumpWidget(harness)` — one pump; no `pumpAndSettle`, no real `Future.delayed`
  (FakeAsync would hang).
- Flow: `initState` (`:226`) -> post-frame callback -> `_loadExercises` (`:415`) ->
  `loadSessionData` (`session_core_io.dart:131`) -> `_setLoading(true)` (`:137`) -> `_notify()`
  (`session_core.dart:213-216`).
- Expected outcome: `tester.takeException()` is `null`; after `await tester.pump()` the seeded set is
  on screen.
- Red without the change because: at the base the notify runs while the ancestor `ListenableBuilder`'s
  element is the current build target, so its `markNeedsBuild` throws `setState() or markNeedsBuild()
  called during build`; `tester.takeException()` returns that `FlutterError` (and the row is never
  built).
- Edge case of: none.

### S-151: the load still shows the spinner, then the session, and still reports failure
- Fixture: (a) the S-150 fixture; (b) the same Mock with no session at all and `getSession` throwing,
  so `_loadExercises` takes its `!hasSession -> createNewSession()` branch (`:425-427`) and its `catch`
  (`:507-511`).
- Trigger: `pumpWidget` then `pump()`.
- Flow: as S-150.
- Expected outcome: (a) the spinner is on screen after the first pump and the seeded row after the
  post-frame pump; (b) `_hasError` is set and no exception escapes the frame.
- Red without the change because: **negative guard** — it passes at the base too. Its mutations:
  dropping the post-frame call to `_loadExercises()` makes the seeded row never appear (the row
  assertion fails); removing `_setLoading(true)` from `loadSessionData` leaves `_isLoading` false after
  the first frame (the spinner assertion fails).
- Edge case of: S-150.

### S-152: the second `initState` loader has the same trap and the same fix
- Fixture: `SessionOverviewScreen` mounted inside the same ancestor `ListenableBuilder(listenable:
  workoutState)`; Mock with **no** current session, so `_initializeSession` (`:48`) calls
  `createNewSession()` (`:54`) and then `loadSessionData()` (`:56`) — both notify.
- Trigger: one `pumpWidget`.
- Flow: `initState` (`:46`) -> `_initializeSession` (`:48`).
- Expected outcome: `tester.takeException()` is `null`; after a `pump()` the screen shows its body
  (spinner `:41` off).
- Red without the change because: at the base the synchronous `createNewSession()`/`loadSessionData()`
  notify during build and the ancestor's `markNeedsBuild` throws the same `FlutterError`.
- Edge case of: S-150 (same defect class, second site).

### S-153: an inverted session window still renders its summary
- Fixture: Mock session `s` with `startedAtMs = 1_791_419_191_803` and
  `endedAtMs = 1_791_419_191_803 - 3_600_000` (the exact value from the owner's log, one hour before
  its start); one segment, one effort on it, and on that effort one closed rest
  `restStartMs = startedAtMs + 1_000`, `restEndMs = startedAtMs + 61_000`.
- Trigger: `await SessionSummaryService(mock).computeSessionRestTimeMs(s.id)`; then
  `pumpWidget` of the summary screen on `s`.
- Flow: `computeSessionRestTimeMs` (`:15`) -> window (`:21-22`) -> clamps (`:33-34`) -> `end > start`
  filter (`:36`) -> merge (`:40-57`).
- Expected outcome: the method returns `0` (an empty window clips every rest to zero length); the
  summary screen renders the session's title with no exception.
- Red without the change because: at the base `windowStart` (1791419191803) is passed as `lowerLimit`
  with a smaller `upperLimit`, so `clamp` throws `ArgumentError(1791419191803)` and the call fails —
  exactly the owner's log.
- Edge case of: S-154.

### S-154: an ordinary session's rest total is unchanged, overlaps merged once
- Fixture: Mock session `s` `startedAtMs = 1_000_000`, `endedAtMs = 1_600_000`; one effort with three
  rests: `(1_030_000, 1_090_000)`, `(1_080_000, 1_120_000)` (overlaps the first), `(1_100_000,
  1_130_000)` (overlaps the second) and one before the window `(900_000, 950_000)`.
- Trigger: `computeSessionRestTimeMs(s.id)`.
- Flow: as S-153.
- Expected outcome: `100_000` — the merged union is `1_030_000 … 1_130_000`; the rest before the
  window contributes nothing (`end > start` filter, `:36`).
- Red without the change because: **negative guard** — it passes at the base. Its mutations: replacing
  `windowEnd` with `windowStart` unconditionally returns `0` (fails the total); skipping the merge in
  step 3 double-counts the overlaps (`60_000 + 40_000 + 30_000 = 130_000`, fails the total); dropping
  the `end > start` filter would clip the pre-window rest to a zero-length interval (still `0`, so
  that mutation is only visible through the merge one).
- Edge case of: S-153.

### S-155: the first exercise added after an end cannot invert the window
- Fixture: Mock repository + `WorkoutState`; a session created by `createNewSession()`; then
  `endSession()` (D-153's writer, the phone clock); then `resetSessionTimerStart()`.
- Trigger: the real writer path above, in a plain `test()` (Mock-first; a 2 ms real delay between the
  end and the reset is allowed here — this is not `testWidgets`, so FakeAsync does not apply).
- Flow: `endSession` (`:21`) -> `resetSessionTimerStart` (`:59`) -> `getSession`.
- Expected outcome: the stored row satisfies `endedAtMs != null && endedAtMs >= startedAtMs`, and
  `startedAtMs` is the value `endSession` left (the reset wrote nothing).
- Red without the change because: at the base `resetSessionTimerStart` writes `startedAtMs =
  DateTime.now().millisecondsSinceEpoch` (`:65`), which is after `endedAtMs`, so the assertion
  `endedAtMs >= startedAtMs` fails.
- Edge case of: S-156 (what a store held before this fix).

### S-156: a stored inverted row is repaired once, in both repositories
- Fixture: three session rows — `a`: `startedAtMs = 1_700_000_000_000`, `endedAtMs =
  1_699_999_000_000` (inverted); `b`: `startedAtMs = 1_700_000_000_000`, `endedAtMs: null` (running);
  `c`: `startedAtMs = 1_700_000_000_000`, `endedAtMs = 1_700_000_060_000` (correct). Hive: the rows in
  the sessions box at `data_version = 14`. Mock: the same three rows seeded in memory.
- Trigger: open the repository (Hive) / run the Mock's migration steps, then `getSession` on each id,
  then run the steps again.
- Flow: `DataMigrationService.run()` -> step 15 -> the repair body.
- Expected outcome: `a.endedAtMs == a.startedAtMs` with `a.startedAtMs` untouched; `b.endedAtMs` is
  still `null`; `c` is byte-identical; Hive and Mock return equal values for all three; the device's
  `data_version` is `15`; a second run changes nothing.
- Red without the change because: at the base no step 15 exists, so `a` keeps `endedAtMs <
  startedAtMs` and the assertion on the repaired value fails.
- Edge case of: S-153 (the guard covers the window while this repairs the store).

## Iteration 1

### Phase 1: the build-phase notify — the session screen, its siblings, and a permanent guard (@developer)

1. [x] `_WorkoutSessionScreenState.initState` — replace the direct `_loadExercises()` call
   (`lib/features/session/workout_session_screen.dart:236`) with
   `WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _loadExercises(); })`; leave the
   observer, the settings listener and the ticker above it untouched · `initState` (`:226-239`)
2. [x] `_WorkoutSessionScreenState._loadExercises` — confirm nothing else needs to move: the spinner is
   the first frame's content (`_isLoading = true`, `:109`), `!hasSession -> createNewSession()` +
   `loadSessionData()` (`:425-428`), the `catch` -> `_hasError` (`:507-511`) and the rolling-session
   reordering all stay as they are · `_loadExercises` (`:415`)
3. [x] New `test/session_screen_build_phase_notify_test.dart` — S-150: the ancestor-`ListenableBuilder`
   harness, Mock-first, `pumpWidget` + `pump()` only (no `pumpAndSettle`, no real delay) ·
   `S-150`
4. [x] Same file — S-151: spinner on the first frame, the seeded row after the post-frame pump, and the
   failing-load path with no escaping exception · `S-151`
5. [x] `_SessionOverviewScreenState.initState` (`lib/features/session/session_overview_screen.dart:46`)
   — the same post-frame deferral around `_initializeSession()` (`:48`), keeping `_isLoading` (`:41`)
   and the `try/catch/finally` · `initState` / `_initializeSession`
6. [x] The audit: grep `lib/features/**/*.dart` for `initState` bodies that call a notifying method
   (`loadSessionData`, `createNewSession`, `resetSessionTimerStart`, `loadHistoricalSession`,
   `endSession`). Candidates already seen and to be **checked, not assumed**: `my_routines_screen.dart`
   (`initState` `:48`), `exercise_library_detail_screen.dart` (`initState` `:61`),
   `lib/features/profile/widgets/measurement_sparkline.dart` (`initState` `:114`). Defer every site
   whose chain reaches a synchronous `notifyListeners()`; leave a site that only calls pure readers;
   add one test per fixed site in the S-150 shape (`test/<screen>_build_phase_notify_test.dart`) and
   list every checked site in `<…>.evidence.md` with its verdict · the audit's sites
7. [x] New `test/initstate_notify_contract_test.dart` — the structural guard: scan
   `lib/features/**/*.dart` for an `initState` body that calls a known notifying method without an
   intervening `addPostFrameCallback` / `Future.microtask`, and fail naming the file, the method and
   the reason (`WorkoutState.notifyListeners()` during build throws `setState() or markNeedsBuild()
   called during build`; see `docs/global_conventions.md`). Pattern:
   `test/palette_legibility_contract_test.dart` · `initStateNotifyContractTest`
8. [x] New `test/session_screen_build_phase_notify_test.dart` — one item per defect class, not one per
   site: the same file also asserts that a **second** screen pumped in the same frame (the overview
   screen) does not throw, so the guard and the fix agree · `S-152`

**Done Criteria** (run until green): `.github/copilot/scripts/macos/gateway.sh lint`;
`.github/copilot/scripts/macos/gateway.sh test test/session_screen_build_phase_notify_test.dart test/initstate_notify_contract_test.dart`;
`.github/copilot/scripts/macos/gateway.sh test test/screen_widget_test.dart test/pr4_session_controls_test.dart test/exercise_detail_emphasis_tier_test.dart`;
`.github/copilot/scripts/macos/gateway.sh prove-red <base-ref> test test/session_screen_build_phase_notify_test.dart -- lib/features/session/workout_session_screen.dart`

**Predicted Files**: `lib/features/session/workout_session_screen.dart`,
`lib/features/session/session_overview_screen.dart`, the audit's other screens (named in item 6, only
those with a real trap), `test/session_screen_build_phase_notify_test.dart`,
`test/initstate_notify_contract_test.dart`, `test/<site>_build_phase_notify_test.dart` per fixed site,
`docs/plans/2026-10-08-18a-phone-hardening-plan/2026-10-08-18a-phone-hardening-plan.evidence.md`

**Phase 1 verification notes (Conductor, date):** _(filled at verification)_

### Phase 2: the summary never throws on an inverted window (@developer)

1. [x] `SessionSummaryService.computeSessionRestTimeMs` — `windowEnd` becomes
   `max(windowStart, session.endedAtMs ?? DateTime.now().millisecondsSinceEpoch)`; keep the clamps
   (`:33-34`), the `end > start` filter (`:36`) and the merge (`:40-57`) · `computeSessionRestTimeMs`
   (`lib/core/services/session_summary_service.dart:15`, window at `:21-22`)
2. [x] New `test/session_summary_inverted_window_test.dart` — S-153: the exact inverted pair from the
   owner's log returns `0` and the summary screen renders the session · `S-153`
3. [x] Same file — S-154: the ordinary session's total (`100_000` with three overlapping rests and one
   before the window) as the negative guard · `S-154`
4. [x] The clamp audit: grep `lib/` for `.clamp(` and confirm the two session-window clamps in
   `session_summary_service.dart:33-34` are the only ones whose bounds are session data (every other
   call site has constant bounds); record the list and the verdict in
   `<…>.evidence.md` · the audit's result
5. [x] `docs/session_summary.md` — the lines that name `computeSessionRestTimeMs` (`:217`, `:249`):
   state that rests are clipped to the session's window and that a session whose end precedes its
   start contributes no rest, naming S-153 as the test · the rest-time sentences

**Done Criteria** (run until green): `.github/copilot/scripts/macos/gateway.sh lint`;
`.github/copilot/scripts/macos/gateway.sh test test/session_summary_inverted_window_test.dart`;
every existing suite whose name mentions the summary (the implementer resolves the list from `test/`);
`.github/copilot/scripts/macos/gateway.sh prove-red <base-ref> test test/session_summary_inverted_window_test.dart -- lib/core/services/session_summary_service.dart`

**Predicted Files**: `lib/core/services/session_summary_service.dart`,
`test/session_summary_inverted_window_test.dart`, `docs/session_summary.md`,
`docs/plans/2026-10-08-18a-phone-hardening-plan/2026-10-08-18a-phone-hardening-plan.evidence.md`

**Phase 2 verification notes (Conductor, date):** _(filled at verification)_

### Phase 3: an end is never stored before its start (@developer)

1. [x] `SessionCoreLifecycleMethods.resetSessionTimerStart` — return after `_clearError()` without
   writing when `_currentSession!.endedAtMs != null`; update the method's doc comment to say a
   finished window is never reopened · `resetSessionTimerStart`
   (`lib/state/workout/session_core_lifecycle.dart:59`)
2. [x] `SessionCoreLifecycleMethods.endSession` — store `max(_currentSession!.startedAtMs, now)` as
   `endedAtMs` (keep `now` for `updatedAtMs`); the early return when `endedAtMs != null` stays ·
   `endSession` (`:21`, `now` at `:28`)
3. [x] `SessionCoreLifecycleMethods.updateSessionEndTime` — store
   `max(_currentSession!.startedAtMs, _currentSession!.startedAtMs + durationSecs * 1000)` so a
   zero-or-negative duration can never invert the window · `updateSessionEndTime` (`:152`)
4. [x] New `test/session_window_never_inverted_test.dart` — S-155: the real writer path
   (`createNewSession` -> `endSession` -> `resetSessionTimerStart`) with a 2 ms delay, asserting
   `endedAtMs >= startedAtMs` and that the reset wrote nothing · `S-155`
5. [x] Same file — the writer table: after each phone-owned writer (`endSession`,
   `updateSessionEndTime` with `durationSecs: 0`, `resetSessionTimerStart`) the row satisfies
   `endedAtMs == null || endedAtMs >= startedAtMs` · `S-155`
6. [x] The residue sweep: grep `lib/` for `endedAtMs:` assignments and list every writer with its rule
   in `<…>.evidence.md` — `endSession`, `updateSessionEndTime` and `resetSessionTimerStart` per
   D-153, `WatchSessionImporter._createSession` (`watch_session_importer.dart:516-517`) exempt and
   named as such · the sweep's result

**Done Criteria** (run until green): `.github/copilot/scripts/macos/gateway.sh lint`;
`.github/copilot/scripts/macos/gateway.sh test test/session_window_never_inverted_test.dart`;
`.github/copilot/scripts/macos/gateway.sh test test/pr4_session_controls_test.dart test/watch_session_edit_restore_summaries_test.dart`;
`.github/copilot/scripts/macos/gateway.sh prove-red <base-ref> test test/session_window_never_inverted_test.dart -- lib/state/workout/session_core_lifecycle.dart`

**Predicted Files**: `lib/state/workout/session_core_lifecycle.dart`,
`test/session_window_never_inverted_test.dart`,
`docs/plans/2026-10-08-18a-phone-hardening-plan/2026-10-08-18a-phone-hardening-plan.evidence.md`

**Phase 3 verification notes (Conductor, date):** _(filled at verification)_

### Phase 4: repair the rows already stored inverted (@dba)

**Phase 4 status: Complete** (2026-10-08, @dba) — all five items landed; the per-item results are in
`## Progress` and the baselines, red/green table and mutation table in the evidence file.

1. [x] `currentDataVersion` 14 -> 15 · `lib/core/constants/data_version.dart:34` — done; the literal was
   also carried in `docs/constants_reference.md:544` and is updated there
2. [x] Append the step to `HiveWorkoutRepository._dataMigrationSteps()`
   (`lib/data/repositories/hive_workout_repository.dart:272`) as
   `_MethodStep(15, 'clampInvertedSessionWindows', () => repo._clampInvertedSessionWindows())`, and add
   the private body beside its siblings (`:619+` style): read each session row from the sessions box,
   rewrite `endedAtMs = startedAtMs` when `endedAtMs != null && endedAtMs < startedAtMs`, skip
   unchanged rows so a re-run writes nothing · `_dataMigrationSteps` / `_clampInvertedSessionWindows` —
   landed as planned (`lib/data/repositories/hive_workout_repository.dart:308`, body `:508-519`), plus a
   `@visibleForTesting dataMigrationStepsForTest()` accessor so the sequence test can read the list
3. [x] The Mock mirror (`lib/data/repositories/mock_workout_repository.dart:267`) — the same repair over
   the in-memory rows, so a store holding an inverted row converges to the same value in both
   repositories (give `_MockMigrationStep` (`:25`) a body hook if it has none) · `_dataMigrationSteps`
   / `_MockMigrationStep` — done; `_MockMigrationStep` gained the optional body, so step 15 runs the
   same repair over the in-memory rows and the parity loop is green
4. [x] `test/data_migration_test.dart` — the new step's sequence entry (version 15, name), the S-156
   three-row fixture, idempotency (a second run writes nothing) and the Hive↔Mock parity assertion on
   the repaired values · `S-156` — all three tests added (`+3`); the Hive test seeds a store at
   `data_version = 14`, watches the box for writes (exactly one, on the inverted key) and re-runs
   step 15 to prove the second pass writes nothing
5. [x] Confirm no doc change is owed: `docs/db_integration.md:156-215` states the append-a-step rule and
   lists no individual step, so nothing in it becomes false; record that reading in
   `<…>.evidence.md`. (If the file is found to enumerate steps, add the row instead.) ·
   `docs/db_integration.md` — confirmed as planned: the section names no individual step, so no edit
   was owed there; the reading and its one nuance are recorded in the evidence file. The bump's value
   *is* duplicated in `docs/constants_reference.md:544` and that row was updated to `15`

**Done Criteria** (run until green): `.github/copilot/scripts/macos/gateway.sh lint`;
`.github/copilot/scripts/macos/gateway.sh test test/data_migration_test.dart test/db_seed_test.dart`;
`.github/copilot/scripts/macos/gateway.sh prove-red <base-ref> test test/data_migration_test.dart -- lib/core/constants/data_version.dart lib/data/repositories/hive_workout_repository.dart`

**Predicted Files**: `lib/core/constants/data_version.dart`,
`lib/data/repositories/hive_workout_repository.dart`,
`lib/data/repositories/mock_workout_repository.dart`, `test/data_migration_test.dart`,
`docs/plans/2026-10-08-18a-phone-hardening-plan/2026-10-08-18a-phone-hardening-plan.evidence.md`

**Phase 4 verification notes (Conductor, date):** _(filled at verification)_

## Files Affected (whole feature)

| File | Phase | Notes |
|---|---|---|
| `lib/features/session/workout_session_screen.dart` | 1 | `initState` deferral only |
| `lib/features/session/session_overview_screen.dart` | 1 | the same deferral |
| the audit's other screens | 1 | only those with a real trap (item 6) |
| `lib/core/services/session_summary_service.dart` | 2 | `windowEnd` guard |
| `lib/state/workout/session_core_lifecycle.dart` | 3 | three writers |
| `lib/core/constants/data_version.dart` | 4 | 14 -> 15 |
| `lib/data/repositories/hive_workout_repository.dart` | 4 | step 15 |
| `lib/data/repositories/mock_workout_repository.dart` | 4 | step 15 mirror |
| `test/session_screen_build_phase_notify_test.dart` | 1 | new |
| `test/initstate_notify_contract_test.dart` | 1 | new |
| `test/session_summary_inverted_window_test.dart` | 2 | new |
| `test/session_window_never_inverted_test.dart` | 3 | new |
| `test/data_migration_test.dart` | 4 | extended |
| `docs/session_summary.md` | 2 | rest clipping sentence |
| `docs/state_management/workout_state.md` | 3 | the `endSession()` / `updateSessionEndTime()` rows |
| `docs/modality_based_exercise_ui.md` | 3 | the duration Save bullet |
| `docs/plans/2026-10-08-18a-phone-hardening-plan/*` | 1-4 | this plan + its evidence file |

## Notes

- **Dependency graph.** Phase 2 is what stops the crash a user sees today and touches one file — if the
  PR is split, ship Phase 2 first, then Phase 1, then 3+4. Phases 1, 2 and 3 touch disjoint files and
  may run in any order; Phase 4 (the migration) is independent of all of them and only needs
  `currentDataVersion`, so it must not run in parallel with another phase that edits the same two
  repositories.
- **Intermediate states.** After Phase 2 an inverted row still exists in a user's store and shows rest
  `0`. After Phase 3 no new inverted row can be written. After Phase 4 the stored row is normalised, so
  the guard in Phase 2 has nothing left to guard on real data (it stays for the wire-owned case of
  D-153).
- **Legacy handling.** The legacy `bool` migration markers stay inert and the back-compat shim is
  untouched; a device at version 14 runs only the new step 15.
- **Watch-adopted sessions** open `WorkoutSessionScreen` like any other (`docs/state_management/
  watch_surface.md`); the fix is in the screen's own `initState`, so no watch-side behaviour changes.
- **Not in scope.** The `endSession` early return when a session already ended (the wrist ended it, the
  phone's Finish writes nothing) is today's behaviour and stays; see Open question 3.

## Progress

2026-10-08 · Phase 1 · item 1 — `_WorkoutSessionScreenState.initState` now defers `_loadExercises()` through `addPostFrameCallback` (`lib/features/session/workout_session_screen.dart:226-242`) · evidence "S-150 / S-151 / S-152 red at base", "… green after"
2026-10-08 · Phase 1 · item 2 — `_loadExercises` left as it was: spinner first frame (S-151(a)), `createNewSession()`/`loadSessionData()` unchanged, `catch` -> `_hasError` (S-151(b)) · evidence "S-150 / S-151 / S-152 green after", mutation row
2026-10-08 · Phase 1 · item 3 — new `test/session_screen_build_phase_notify_test.dart`, S-150 red at 1665f64 (`persistentCallbacks` + `setState() or markNeedsBuild() called during build`) · evidence "The three new files together"
2026-10-08 · Phase 1 · item 4 — S-151 in the same file: spinner first frame (red at base), the seeded set after the post-frame pump, and the failing load reporting on screen with nothing thrown · evidence mutation row (the negative guard is proven by mutation, not by red-at-base)
2026-10-08 · Phase 1 · item 5 — `_SessionOverviewScreenState.initState` defers `_initializeSession()` the same way (`lib/features/session/session_overview_screen.dart:44-50`) · evidence S-152 row
2026-10-08 · Phase 1 · item 6 — the audit: 3 real traps (the two session screens and `my_routines_screen.dart`), 2 sites left as pure readers; a sweep of the six notifying method names over `lib/features` found 25 hits in 8 files, none in another `initState` · evidence "The item-6 audit" + "R-2 red at base"
2026-10-08 · Phase 1 · item 7 — new `test/initstate_notify_contract_test.dart`: a fixture test plus a scan of every `initState` under `lib/features`, red at 1665f64 naming the three sites · evidence "initstate_notify_contract_test red at base"
2026-10-08 · Phase 1 · item 8 — S-152 in `test/session_screen_build_phase_notify_test.dart`: the overview screen pumped in the same frame as the session screen notifies nobody and throws nothing · evidence S-152 row
2026-10-08 · Phase 1 · verification — `lint` 196 issues / 0 errors (baseline), full `test` `+4068 ~1: All tests passed!`, invariant grep clean, `git-diff --stat` = 3 source files, 7 lines each including the comment · evidence "Full suite", "`lint`"
2026-10-08 · Phase 2 · item 1 — `windowEnd` is now `math.max(windowStart, session.endedAtMs ?? DateTime.now().millisecondsSinceEpoch)`; the clamps (`:33-34`), the `end > start` filter and the merge are untouched (`lib/core/services/session_summary_service.dart:19-26`, +6/-2) · evidence "S-153 / S-154 green after" and the two mutation rows
2026-10-08 · Phase 2 · item 2 — new `test/session_summary_inverted_window_test.dart`, S-153: the owner's exact inverted pair returns `0` and the summary screen renders its title; red at 15bab66 with the owner's own `ArgumentError` · evidence "S-153 / S-154 red at base"
2026-10-08 · Phase 2 · item 3 — S-154 in the same file: `100000` from three overlapping rests plus one before the window; non-vacuous via the merge mutation (`130000` without the merge) · evidence S-154 mutation row
2026-10-08 · Phase 2 · item 4 — the clamp audit: 50 `.clamp(` sites in 28 files under `lib/`; `session_summary_service.dart:33-34` is the only one taking session-data bounds — every other site is a constant pair, a guarded list index/length, a layout metric or a single-value cap · evidence "The `.clamp(` audit"
2026-10-08 · Phase 2 · item 5 — `docs/session_summary.md`: the clipping bullet, the load-order item 7 and the `computeSessionRestTimeMs` bullet now state `max(startedAtMs, endedAtMs)` and name S-153; `test/docs_indexing_contract_test.dart` green (`+9`) · evidence "Item 5 — the doc update"
2026-10-08 · Phase 2 · verification — `lint` 196 issues / 0 errors (baseline), full `test` `01:41 +4070 ~1: All tests passed!`, the 8 summary-named suites `+87`, invariant grep clean, `git-diff --stat` = 1 source file (+6/-2) plus the new test file · evidence "Full suite", "`lint`"
2026-10-08 · Phase 3 · items 1-3 — `resetSessionTimerStart` returns without writing when an end exists (doc comment updated), `endSession` stores `math.max(startedAtMs, now)`, `updateSessionEndTime` stores `math.max(startedAtMs, startedAtMs + durationSecs * 1000)` (`lib/state/workout/session_core_lifecycle.dart`, +14/-2; plus the `dart:math` import in `session_core.dart`, +2) · evidence "S-155 green after" and the guard-mutation table
2026-10-08 · Phase 3 · items 4-5 — new `test/session_window_never_inverted_test.dart`: the S-155 headline path plus a four-row writer table; red at 323fcfe with `+3 -2`, both failures the guarded order · evidence "S-155 red at base"
2026-10-08 · Phase 3 · item 6 — the `endedAtMs:` sweep: 16 sites in 9 files, three phone writers fixed, six carry-through sites unchanged, `WatchSessionImporter._createSession` named exempt (D-153), four readers/parse helpers and one seed literal · evidence "The `endedAtMs:` writer sweep"
2026-10-08 · Phase 3 · verification — `lint` 196 issues / 0 errors (baseline), full `test` `01:58 +4075 ~1: All tests passed!` on the final tree, the neighbouring pair `+19`, the docs contract `+9`, invariant grep clean, `git-diff --stat` = the two source files only · evidence "Full suite", "`lint`"
2026-10-08 · Phase 3 · docs — `docs/state_management/workout_state.md` (`endSession()` / `updateSessionEndTime()` rows) and `docs/modality_based_exercise_ui.md` (the duration Save bullet) now state `max(startedAtMs, …)` and name the S-155 tests · Assumption 12
2026-10-08 · Phase 4 · item 1 — `currentDataVersion` 14 -> 15 (`lib/core/constants/data_version.dart:34`); the same literal in `docs/constants_reference.md:544` is updated with it · evidence "the value's second home"
2026-10-08 · Phase 4 · item 2 — step 15 `clampInvertedSessionWindows` appended to the Hive sequence with its guarded loop (`hive_workout_repository.dart:508-519`): only `ended_at_ms < started_at_ms` rows are rewritten, unchanged rows are skipped so a re-run writes nothing · evidence "The S-156 mutations" rows 1-2
2026-10-08 · Phase 4 · item 3 — the Mock mirror: `_MockMigrationStep` gained the optional body, step 15 rebuilds an inverted row with `endedAtMs: startedAtMs` and every other field carried through, no `updatedAtMs` change · evidence the parity row
2026-10-08 · Phase 4 · item 4 — three S-156 tests in `test/data_migration_test.dart` (sequence entry; Mock repair + idempotent re-run; Hive store seeded at 14 with one watched write, a second pass writing nothing, and the Hive↔Mock `.toMap()` parity loop) · evidence "The S-156 fixture" / "The S-156 mutations"
2026-10-08 · Phase 4 · item 5 — `docs/db_integration.md:156-215` enumerates no individual step, so nothing in it became false: read and recorded, no edit owed · evidence the db_integration row
2026-10-08 · Phase 4 · verification — `prove-red bc96cd2 test test/data_migration_test.dart` reports RED AT bc96cd2 by compile error (new code), so three mutations carry the proof, `+1 -2` each; `lint` 196 issues / 0 errors (baseline — one `unnecessary_import` in the new test fixed first), full `test` `01:57 +4078 ~1: All tests passed!`, the Done-Criteria pair `+20`, invariant grep clean, `git-diff --stat` = 3 source files + 1 test file · evidence "Phase 4 verification"

## Assumption Log

1. **Harness shape (items 3, 4, 8).** The plan's literal tree — the screen mounted directly under the
   listening `ListenableBuilder` — cannot show the defect: `markNeedsBuild` allows marking the current
   build target dirty. Chose a `_MountedBelowTheListener` element between listener and screen; proven
   red at 1665f64 and green after, with and without the fix.
2. **S-151(b)'s fixture (item 4).** The planned "Mock with no session, `getSession` throws" cannot set
   `_hasError`: the state layer absorbs repository errors and `_loadExercises` catches only its own
   reads. Chose a repository whose watch-inbox read throws (`_RefusingInboxRepository`) with a session
   present and `editMode: true`; it passes at base, so the guard is proven by the recorded mutation.
3. **S-151(a) is not a negative guard (items 3, 4).** At base the whole load finishes inside
   `pumpWidget`, so the first frame is never the spinner — the assertion is red at base.
4. **`prove-red` form (all phases).** The plan's `-- lib/features/…` carries my *fixed* source into the
   base worktree and never carries the new untracked test, so the check cannot load it. Chose
   `prove-red 1665f64 test <test file>` (a plain file argument is carried, `lib/` stays at base);
   Phases 2–4's Done Criteria list the unusable form.
5. **S-152 needs a taller surface.** The default 800x600 test view overflows the overview screen's
   `Column` (`session_overview_screen.dart:179`), so the test sets `tester.view.physicalSize` to
   800x1600 and resets it on teardown.
6. **One row added to `docs/global_conventions.md`** ("No state notification during the build phase",
   `Last Updated` refreshed). Item 7 points readers there for the reason, and the rule is mechanically
   checked by the new contract test; this file is outside the plan's Predicted Files.
7. **The Phase-2 doc edit went one place wider than item 5 (item 5).** The plan named `:217` and
   `:249`, but the "Rest Time and Duration" bullet still described clipping as `startedAtMs` to
   `endedAtMs` — false after item 1 — so it was updated too. All three sentences name
   `test/session_summary_inverted_window_test.dart` (`S-153`).
8. **The clamp audit ran with the file tools (item 4).** The gateway exposes no grep check, so the
   `.clamp(` sweep and the call-site reads used the file-tool grep over `lib/`; the pattern, the 50
   sites and the classification are recorded in the evidence section, since no shell alternative
   exists in Copilot mode.
9. **`updateSessionEndTime`'s clamp is unobservable by design (Phase 3, item 3).** Its mutation stays
   green: the pre-existing `if (durationSecs <= 0) return;` — pinned by `test/state_test.dart:1576`
   and `test/session_edit_duration_test.dart`, which the plan did not predict — makes every
   non-positive duration a no-op, and a positive one always yields a candidate above `startedAtMs`.
   Chose to keep the clamp (D-153's rule for every writer, and it survives the guard moving) and to
   leave the guard alone; removing it instead would turn those two suites red.
10. **The `dart:math` import went into `session_core.dart` (Phase 3, items 2-3).** The three writers
    live in the `session_core_lifecycle.dart` extension, but the members are private to
    `session_core.dart`, so the `math.max` calls compile against the library's single import block —
    one added import, +2 lines, outside the plan's Predicted Files.
11. **The future-start fixture is seeded through the repository (Phase 3, items 4-5).** `SessionCore`
    has no injectable clock, so `endSession`'s clamp cannot be reached by moving time: the test seeds
    a `TrainingSession` whose `startedAtMs` is an hour ahead of the phone clock, loads it with
    `loadHistoricalSession`, then ends it. That is the fixture that makes the clamp's mutation red.
12. **Two doc rows state the stored expression (Phase 3, items 2-3).** The `endSession()` and
    `updateSessionEndTime()` rows of `docs/state_management/workout_state.md` and the Save bullet of
    `docs/modality_based_exercise_ui.md` now carry the `max(startedAtMs, …)` form and name the S-155
    tests; all three sites are outside the plan's Predicted Files, which list no doc this phase.
13. **The repair leaves `updatedAtMs` alone (Phase 4, items 2-3).** D-154 names only the end, and a
    fresh timestamp on every run would break both the Hive↔Mock parity comparison and the "a re-run
    writes nothing" requirement; the byte-identical snapshot the Hive test takes pins this.
14. **Two test-side additions outside the phase's predicted surface (Phase 4, item 4).**
    `dataMigrationStepsForTest()` (`@visibleForTesting`) on both repositories exposes the private step
    list to the sequence test, and three S-002 assertions now read `_lastLegacyMarkerVersion = 14`:
    the shim maps to the last *legacy marker*, so the old `currentDataVersion` expectation only held
    while the constant stood at 14 — and mapping the shim to `currentDataVersion` instead would skip
    the repair on exactly the devices that need it. Reviewer: ratify the S-002 edit.
15. **The proof is by mutation, not by red-at-base (Phase 4, item 4).** The new tests cannot even
    compile without `dataMigrationStepsForTest()`, so `prove-red bc96cd2 test …` reports RED AT the
    base ref as a load error; three mutations then carry the guard proof, each restored exactly.

## Feedback

_(empty — the reviewer or the owner folds a note here; non-empty triggers a new Iteration block)_

## Open questions

Owner-visible choices only; each carries the default this plan proceeded on. Nobody could answer in
this run, so the plan proceeds on the defaults.

1. **What should a session whose end is before its start show for its rest time?** *Default taken
   (D-152):* `0` — an empty window, and the session still shows with its other numbers. Alternative:
   hide the rest stat for such a session (more surface, no extra truth).
2. **Should the phone repair the row already stored on your device, or only stop making new ones?**
   *Default taken (D-154):* repair it once through a data-migration step (version 15), identically in
   both repositories. Alternative: leave history as it is and rely on the summary guard — the store
   would keep a session whose end precedes its start.
3. **The wrist ends a session while you keep logging on the phone.** *Default taken (unchanged
   behaviour):* the finished window stays history — the start is not rewritten (D-153) and a later
   Finish writes nothing, because `endSession` returns early when `endedAtMs != null`
   (`session_core_lifecycle.dart:22`). Alternative: the phone's next logged set reopens the session
   (clears the end) — that is a product change, not a crash fix, so it is not in this PR.
