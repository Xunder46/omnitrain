# Plan 38c — Count-up screens: plain elapsed digits, weight row on holds only

Status: SEEDED by the lead. Base: working tree on `claude_develop` on top of the uncommitted 38a and 38b (HEAD `80928669`; `pubspec.yaml` has an unrelated change: never touch it). Not authorised to commit: the owner commits; never push.
Series: `docs/plans/2026-10-15-38-logger-rework-series.md` (O-1..O-12, T-1..T-4 bind this plan). 38a: `docs/plans/2026-10-15-38a-logger-shell-plan/`. 38b: `docs/plans/2026-10-15-38b-reps-screen-plan/` (`ValueStepperRow`, `MetricStepping`). Scenario ids `S-4260`..`S-4279` (grep'd free in `test/`, `docs/`, `lib/`, `watch/`).

## Goal and acceptance

What a user sees for the two count-up effort kinds in the live session (`timed` = cardio interval, `drill` = isometric hold) and in the session editor:

- A1. Live, interval and hold: the hero is the elapsed time as plain large digits (`00:00`, `01:12`), no ring, no unit caption under it, no status row (no play/pause glyph, no `STOPPED` / `RUNNING` / `PAUSED` text). Running is conveyed by the digits ticking.
- A2. No time stepper or time input before Start. The only way to produce a value is `Start` -> run -> `Log Interval` / `Log Hold`, which locks the elapsed time to the set (unchanged behaviour). The button never dims; there is no Pause control (O-1). After a log, focus moves to the next unlogged set (38a, unchanged). A paused set restored from storage still shows `Resume` (unchanged, it is the only way out of that state).
- A3. Cardio interval (`timed`) shows no weight control anywhere, live or in the editor, whatever the exercise carries (O-11). Old intervals that stored an extra-weight value keep it in the data; the screen just does not show it.
- A4. Hold (`drill`) shows one full-width weight row under the digits: `ValueStepperRow` (minus left, big number with the unit, plus right; tap the number for the existing popup; long-press repeats). Always visible, no `Weight adjustment` button. It is the hold's only input. Step 2.5 kg or 5 lb (`MetricStepping`). Editable before Start and while the timer runs; locked once the hold is logged in a live session (38a rule, O-2); never locked in the session editor.
- A5. Session editor (`editMode`): interval = the duration editor only (tap opens `Edit Interval Duration`); hold = the duration editor (`Edit Hold Duration`) plus the weight row. Navigation-only controls and screen-level Save unchanged.
- A6. Unchanged: set bar, count text, logged line (time as `m:ss`), sets stepper, rest strip and chip, arrows-and-button row, rounds (38d) and reps (38b) screens.
- A7. At 390 x 844 dp with the rest strip up the sets stepper stays reachable and the hold's weight buttons are at least 48 x 48 dp (lead probes first).
- A8. `flutter analyze` not above 182 (0 errors); `flutter test` not below `+4822 ~1` minus tests this plan removes (listed in Progress); no allowlist entry, no ratchet raised.

## Feature invariants

- FI-1 Units: the shown hold weight is `UnitFormatter.convertWeight(kg)`; the row hands the screen a shown-unit `double` and `_updateMetricValue(..., 'extra-weight', v)` converts to kg (`workout_session_screen.dart` `_updateMetricValue`, which converts `weight` and `extra-weight`). The row never converts.
- FI-2 Theme tokens only; the palette ratchet stays green.
- FI-3 No hand-built minus/number/plus row: the hold uses `ValueStepperRow` (design_system shared-pieces rule from 38b).
- FI-4 No data-model, repository, summary or watch change (T-2). `extra-weight` stays the stored key for both kinds; `timed` entries keep writing/carrying it exactly as today.
- FI-5 Round (`round`) branch untouched (38d): its status row and labels stay.

## Decision Ledger

- D-1 (owner O-11, lead wiring) `timed` branch of `_buildMetricWidget` (`workout_session_detail_view.dart`): live = digits only; editor = duration editor only; the `entryData['extra-weight'] != null` weight sections are deleted from both.
- D-2 `drill` branch: live = digits + `ValueStepperRow`; editor = duration editor + `ValueStepperRow`. The row is `ValueStepperRow(key: ValueKey('$effortId-$entryIndex-weight'), metricType: 'weight', currentValue: <shown unit>, unitLabel: _preferredWeightUnitLabel, step: MetricStepping.weightStepFor(widget.settingsState.preferredWeightUnit), isReadOnly: <live && logged>, onValueChanged: (v) => _updateMetricValue(effortId, entryIndex, 'extra-weight', v))`. Technical decision (lead, one line): the row's `metricType` is `weight`, not `extra-weight`, because `ValueStepperRow` takes `reps | weight`; the stored key stays `extra-weight` through the closure. Visible consequences: the number has no `+` sign, the popup title is `Edit Weight`, and the popup/step limit is -200..999 (the reps screen's) instead of -100..200; negative values (band assist) still work. Per-set key as in 38b so a set change discards a hold in progress (S-4257 reasoning).
- D-3 Status row: deleted from `timed` and `drill` (glyph + `STOPPED` / `RUNNING` / `PAUSED`). Why (lead, decided for the owner's spec "digits big, no extra chrome"): the digits ticking say running, `Start` / `Log ...` say what the button does, O-1 says there is no pause, and a pause glyph suggests a control that does not exist. `round` keeps its status row (38d decides).
- D-4 Unit captions: `ELAPSED` / `COMPLETED` under the digits are dropped in the live view (empty `unitLabel`; `InlineMetricEditor` prints no caption then). `COMPLETED` repeated `LOGGED` and the logged line; `ELAPSED` is the only word left of the old chrome and the owner's spec asks for plain digits. The digits turn no colour when finished (plain `textDominant`). One-line revert if the owner wants the caption back.
- D-5 Dead code removed with the change (fix what you touch): `_buildWeightAdjustmentSection`, `_weightAdjustExpanded` (`workout_session_screen.dart:196`) and, if nothing else reads them, `_kTimedValuePadding` / `_kTimedStatusRowBottomGap`. The digits keep a top padding of `_kTimedValuePadding`-like 32 so the hero does not touch the bar block (builder keeps the constant if still used).
- D-6 Old data (open decision, lead, technical): stored cardio `extra-weight` rows stay untouched in summaries, stats and exports; nothing is migrated, hidden or recomputed (T-2; stats already count them as extra load). Only the live/editor screens stop showing and editing them. A new interval still gets its `extra-weight` row at creation (`session_core_entry.dart`), a log still re-persists the stored value (`_persistEntryValues`): not touched.
- D-7 Out of scope: countdown / rounds (38d), routine editor (`RoutineSetupScreen` keeps its extra-weight editors, 38e), the data model, watch app, the rest chip.

## Existing-functionality impact

| Touched surface | What reads it | Effect |
|---|---|---|
| `timed` live view | tests that read `STOPPED` / `RUNNING` / the play and pause glyphs / `Weight adjustment` / the `extra-weight` editor | go away (readers table) |
| `drill` live view | tests that read `Weight adjustment` or expand the section | the section is gone, the row is always there |
| `Icons.add` / `Icons.remove` on a hold screen | bare icon finders | the weight row adds a second pair (readers table) |
| `_weightAdjustExpanded` | `workout_session_screen.dart:196`, detail view only | deleted |
| Vertical space | sets stepper under the metric block | hold: digits + one row; interval: digits only (less than today) |

### Readers table (scout sheet, spot-checked against the files; `test/` at the working tree)

| Test (file:line) | Kind / mode | Reads | Change |
|---|---|---|---|
| `timed_emphasis_redesign_test.dart:282` free stopped states (timed + drill) | live | `STOPPED` colour, play glyph colour, `Weight adjustment` button style, dominant digits via `_metricValueText` (:270) | keep the dominant-digits assertion; replace the status and button assertions by absence (`STOPPED`, play glyph, `Weight adjustment` all `findsNothing`); drill also finds the weight row |
| `timed_emphasis_redesign_test.dart:337` running states | live | `RUNNING` colour, pause glyph colour | digits dominant stays; `RUNNING` and pause glyph `findsNothing` |
| `timed_emphasis_redesign_test.dart:379` routine-backed stopped | live | `STOPPED` colour, play glyph colour | same as :282 |
| `timed_emphasis_redesign_test.dart:452` weight chip absent | timed live | `Weight adjustment` `findsNothing` | none — still true, guard |
| `session_toolbar_rework_test.dart:469,501,520` S-009/S-010/S-011 | timed live | play glyph before Start, `RUNNING` / pause glyph after | rewrite on the button: before Start `Start`; after `Log Interval`; glyphs and status text `findsNothing` (same intent: Start begins the timer) |
| `session_toolbar_rework_test.dart:703` S-013 | timed live | `RUNNING` after a set round-trip, `PAUSED` absent | replace by: the button still reads `Log Interval` after the round-trip, no `Resume` (the timer was not paused) |
| `logger_shell_screen_test.dart:375` S-4217 logged hold | drill live | extra-weight editor read-only, `Weight adjustment` enabled, `+10.0` tap | migrate to the row: both weight buttons inert, number shows `10.0`, tapping it opens no dialog |
| `logger_shell_screen_test.dart:420` S-4217 edit mode | drill edit | extra-weight editor editable, `+10.0` opens dialog | migrate: row buttons active, number `10.0` opens `Edit Weight` |
| `logger_shell_screen_test.dart:449` S-4217 collapsed section | drill live | `Weight adjustment` disabled | delete (no collapsed section any more; S-4264 and S-4267 replace it) |
| `screen_widget_test.dart:8095` timed extra-weight in lbs | timed live | `+50.0`, `LBS` | invert: a timed screen with stored extra-weight shows neither `+50.0` nor a weight row (S-4260 covers it; the test is rewritten to the lbs case) |
| `screen_widget_test.dart:8148` drill extra-weight in lbs | drill live | `+50.0`, `LBS` once | migrate: `50.0` and `LBS` once (no `+` sign) |
| `screen_widget_test.dart:8201` timed reveals extra weight on tap | timed live | `Weight adjustment` button, `EXTRA KG` never | delete (interval has no weight control; S-4260 replaces it) |
| `screen_widget_test.dart:8349` OutlinedButton styling | timed live | `Weight adjustment` is an `OutlinedButton` | delete (the button is gone; no replacement needed) |
| `screen_widget_test.dart:8290,8344` | set live | `Weight adjustment` `findsNothing` | none — guard |
| `sports_emphasis_redesign_test.dart` (`_statusLineText` :216, :281-533) | **round** | `STOPPED` / `RUNNING` glyph pairs | none — round is unchanged (S-4272 guard) |
| `RoutineSetupScreen` tests (`screen_widget_test.dart` 1687-1876, `timed_emphasis_redesign_test.dart:418`), bare `InlineMetricEditor` tests (`interaction_flow_test.dart:262`, `tap_to_edit_unification_test.dart:481`, `crown_control_tap_to_edit_test.dart`) | other screens / widgets | extra-weight editor | none — out of scope (38e) |
| Bare `Icons.add` / `Icons.remove` on a hold screen | — | — | none found (scout Q4) |

Any other test that fails after P1 is a reader the scout missed: migrate it with the same rule (assert absence of the removed chrome, or the row's key; never a looser assertion) and list it in Progress.

## Core scenarios (exact fixtures)

Fixtures: `testWidgets` with no real delays, `MockWorkoutRepository`; copy the screen helpers of `test/logger_shell_screen_test.dart` (`_buildDeps`, `_buildSessionScreen`, `_openDetailView`). New file `test/count_up_screen_test.dart`.

- S-4260 Interval, live, not started: the digits read `00:00`; none of `STOPPED`, `ELAPSED`, `COMPLETED`, `Weight adjustment`; no play/pause glyph; no `ValueStepperRow`; no `extra-weight` editor; the button reads `Start`. Run twice: exercise without load and with load (`includeLoad`) and an `extra-weight` observation of 5.0 on set 1 (O-11: whatever the exercise carries). Fails today: status row and weight section.
- S-4261 Interval: tap `Start`, pump 3 s of wall clock the way `test/session_toolbar_rework_test.dart` S-010 does: the digits advance, the button reads `Log Interval`, no `RUNNING`, no pause glyph. Tap `Log Interval`: `LOGGED` shows, the logged line reads the locked time as `m:ss`, focus is on interval 2. Fails today: `RUNNING` and glyph.
- S-4262 Interval, editor (`editMode: true`) with the 5.0 observation: the `duration` editor is there and tapping its number opens `Edit Interval Duration`; no `Weight adjustment`, no `extra-weight` editor, no weight row.
- S-4263 Interval data untouched: with a stored `extra-weight` 5.0, log the interval; the repository still holds 5.0 on that entry afterwards (D-6).
- S-4264 Hold, live, not started, no weight stored: digits `00:00`; none of `STOPPED`, `ELAPSED`, `Weight adjustment`; exactly one `ValueStepperRow` (`value-stepper-plus-weight` / `value-stepper-minus-weight`) showing `0.0` and the unit; no `extra-weight` editor; `Start` button. Fails today: the collapsed `Weight adjustment` button.
- S-4265 Hold weight steps: plus -> stored `extra-weight` 2.5 kg; a second plus -> 5.0; minus -> 2.5. Pounds (`lbs`): plus -> the stored kg equals `UnitFormatter.toCanonicalWeight(5.0, settings)`. Fails today: no row.
- S-4266 Hold, timer running: tap `Start`, pump 2 s, tap weight plus: the timer keeps running (digits keep advancing, still `Log Hold`) and the weight is stored (a reload does not reset or stop the timer). Fails without the change: no row; guards the reload path.
- S-4267 Hold lock: log the hold (Start, pump, `Log Hold`): `LOGGED` shows, both weight buttons are inert (taps change nothing in the repository), the number is not tappable (no dialog). Editor (`editMode`) on a logged hold: the plus changes the buffered value and the number opens `Edit Weight`.
- S-4268 Hold popup: tapping the weight number opens `Edit Weight`; `Ok` with `12.5` stores `extra-weight` 12.5 (O-12).
- S-4269 Hold, existing weight 10.0 stored: the row shows `10.0` (no `+` sign, no collapsed button); a stored -10.0 (band assist) shows `-10.0` and plus gives -7.5.
- S-4270 Hold weight long-press while the timer runs (edge): hold plus for 2 s with the timer ticking; the stepped number is not dropped by the one-second rebuilds and the value is stored once on lift.
- S-4271 Layout, 390 x 844, rest strip up (lead probes, numbers recorded in the test): the sets stepper is fully above the strip; the hold's weight buttons are at least 48 x 48.
- S-4276 (prover list, fix 3) Hold dies with its set: hold plus on hold 1, move focus with the `Next` arrow mid-hold, lift: nothing stored on either hold, hold 2 still reads `0.0` (guards the per-set row key).
- S-4277 / S-4278 (fix 3) The live digits of an interval / a hold are read-only: tapping them opens no dialog.
- S-4279 (fix 3) Hold editor keeps its duration dialog (`Edit Hold Duration`), mirror of S-4262.
- S-4272 Rounds unmoved: the `round` screen still shows its status row (existing sports/round suites stay green, no edit).

### Code-behaviour check (architect, 2026-10-15)

The three candidates the lead flagged, answered from the working tree; quotes are `file:line` as read this run.

- The `drill` branch IS rebuilt every second while the timer runs: the per-effort timer fires `_onEffortTick` every `_kTimerUpdateInterval` = 1 s (`workout_session_screen.dart:53`), and `_onEffortTick` ends in `setState(() { _effortElapsed[timerKey] = elapsed; })` (`workout_session_timer_mixin.dart:641-644`). A `ValueStepperRow` hold in progress survives it: the row's key `ValueKey('$effortId-$entryIndex-weight')` is stable across those rebuilds, so the row's State is reused, and `didUpdateWidget` clears `_pending` only `if (widget.currentValue != oldWidget.currentValue)` (`lib/widgets/session/value_stepper_row.dart:60-63`) — the tick passes the same stored weight, so the hold's pending steps and its repeat timer are untouched; the lift commits once (`_handleHoldRelease`). This is exactly S-4270's mechanism, so no extra scenario is spent on it.
- A weight step while the hold runs does not reset the timer: `_updateMetricValue` for `extra-weight` persists (`updateEntryValue`) and reloads (`await _loadExercises()`, `workout_session_screen.dart:1466-1472`), but its post-reload sync writes `_effortTargetDuration` only for the keys `duration` / `round-duration` (:1477-1484) — `_effortElapsed` is never written there ("Do NOT overwrite _effortElapsed", :1483-1484). The reload's `_restoreTimerStateFromPersisted` re-derives elapsed from the `TimedInstance`'s wall clock (`_effortElapsed[timerKey] = (instance.elapsedMs / 1000).round()`, `workout_session_timer_mixin.dart:161`) and preserves running with `_effortRunning[timerKey] ??= false` (:157), so the rest overlay also stays hidden (`_shouldShowRestOverlay` returns false while any `_effortRunning` entry is true, `workout_session_global_timer.dart:96-101`). S-4275 pins this.
- A `timed`/`drill` entry restored from storage in `paused` state: `_restoreTimerStateFromPersisted` case `TimedState.paused` sets `_effortElapsed` from the instance and `_effortRunning[timerKey] = false` (`workout_session_timer_mixin.dart:162-165`). The detail view then renders the digits at the restored elapsed with no status row (after D-3), and the centre button takes the `Resume` branch: `_isTimerEntryPaused` reads the instance state (`workout_session_detail_view.dart:925-935`) and `_buildSetControls` builds `_buildTimerToggleButton(effortId, theme, 'Resume')` (:873-875). The doc comment at :921-924 says why the branch must stay: without `Resume` a paused entry is a dead end (the in-progress lock blocks every other timer and nothing restarts this one). S-4273 pins the interval, S-4274 the hold's weight row.

### Edge scenarios (architect, added 2026-10-15)

- S-4273 (screen, `test/count_up_screen_test.dart`): interval restored from storage in `paused` state (seed a `TimedInstance` with `state: TimedState.paused`, `elapsedMs` 75000): the digits read `01:15`, none of `STOPPED` / `PAUSED` / `ELAPSED`, no play glyph, and the centre button reads `Resume` (not `Start`, not `Log Interval`). Tapping `Resume` starts the timer (digits advance, the button becomes `Log Interval`). Why it fails without the change: D-3 deletes the status row whose `PAUSED` text was the only paused signal, and a builder following "no pause control" (O-1) too far could delete the `Resume` branch (`workout_session_detail_view.dart:873-875`) — the comment at :921-924 says the entry would then be a dead end. A2 keeps `Resume`.
- S-4274 (screen, same file): hold restored paused with 10.0 stored: digits at the restored elapsed, no status row, the weight row is editable (plus stores 12.5 while still paused — the hold is not logged, so the lock must not apply) and the button reads `Resume`. Why it fails without the change: replacing the collapsed section with the row must not broaden the lock beyond `_isSetLogged` (the live drill lock at `workout_session_detail_view.dart:726-729`); a "paused inputs locked" reading would strand the weight of a hold the user paused mid-session.
- S-4275 (screen, same file): hold timer running, weight plus tapped, the reload lands (`_updateMetricValue` → `_loadExercises`): the digits keep advancing from the wall clock (not from 0), the button still reads `Log Hold`, and no rest chip appears while the timer runs. Why it fails without the change: the reload's `_restoreTimerStateFromPersisted` runs on every step; a plain `_effortRunning[timerKey] = false` there (instead of the `??=` at `workout_session_timer_mixin.dart:157`) or an elapsed clobber would fake-pause or reset the hold — and with the status row gone (D-3) the rest chip would be the only visible symptom. Sharpens S-4266 with the rest-chip assertion and the mechanism quoted above.

## Phase outline

- Phase 0 (lead, done): baselines analyze 182 (0 errors) and full suite `+4822 ~1` carried from 38b; scout readers sheet -> readers table.
- P1 `crew-builder-app`, scope `lib/features/session/workout_session_detail_view.dart,lib/features/session/workout_session_screen.dart,test/count_up_screen_test.dart`: D-1..D-5, S-4260..S-4270. Serial before P2.
- P2a `crew-builder-app`, scope `test/timed_emphasis_redesign_test.dart,test/session_toolbar_rework_test.dart`: the migrations of the table's first two files. P2b `crew-builder-app`, scope `test/logger_shell_screen_test.dart,test/screen_widget_test.dart`: the other two. P2a and P2b are tests-only with disjoint scopes and run in parallel after P1 (neither runs the full suite).
- Phase 0b (lead, after P1): throwaway probe at 390 x 844 -> S-4271 numbers; fix round writes the guard.
- Phase D `crew-docs-keeper`: `docs/modality_based_exercise_ui.md`, `docs/widget_catalog/session_widgets.md`, `docs/design_system.md` (ValueStepperRow row), evidence file; after the last test-adding round.
- Then `crew-prover` (mutation list) -> lead applies by script; `crew-reviewer`; lead looks at interval and hold on the iPhone 17 simulator.

### Phase P1 — `crew-builder-app` (runs first; P2a/P2b migrate its readers)

Write scope: `lib/features/session/workout_session_detail_view.dart,lib/features/session/workout_session_screen.dart,test/count_up_screen_test.dart`.

Report: write `.work/crew/2026-10-15-38c-count-up/report-p1.md` FIRST as a skeleton, then fill it (8 items). Builders never run the full suite.

1. [ ] Red: write S-4260..S-4263 (interval live not started, twice: exercise without load and with load + a stored `extra-weight` 5.0; start/log round-trip; editor; data untouched) — `test/count_up_screen_test.dart` · `main`
2. [ ] Red: write S-4264..S-4269 (hold row present, kg/lbs steps, live lock + editor, popup, stored 10.0 / -10.0) — `test/count_up_screen_test.dart` · `main`
3. [ ] Red: write S-4270 (long-press while the timer ticks: the stepped number survives the per-second rebuilds, one store on lift) — `test/count_up_screen_test.dart` · `main`
4. [ ] D-1: timed live = digits only (`unitLabel: ''`, no status Row, no weight section); timed editor = the duration editor only (delete the `entryData['extra-weight'] != null` section) — `lib/features/session/workout_session_detail_view.dart` · `_buildMetricWidget` case `'timed'` (:255-404)
5. [ ] D-2: drill live = digits + one `ValueStepperRow` (key `ValueKey('$effortId-$entryIndex-weight')`, `metricType: 'weight'`, `currentValue` in the shown unit read with the num-safe cast `(entryData['extra-weight'] as num?)?.toDouble()` — see Open questions (b), `unitLabel: _preferredWeightUnitLabel`, `step: MetricStepping.weightStepFor(widget.settingsState.preferredWeightUnit)`, `isReadOnly: !widget.editMode && _isSetLogged(...)`, `onValueChanged: (v) => _updateMetricValue(effortId, entryIndex, 'extra-weight', v)`); drill editor = the duration editor + the same row (never locked) — same file · case `'drill'` (:591-747)
6. [ ] D-3 + D-4: delete the status Rows (glyph + `STOPPED`/`RUNNING`/`PAUSED`) and the `ELAPSED`/`COMPLETED` captions in both live branches; the digits keep a top padding of 32 (keep `_kTimedValuePadding` if still used, else fold it in) — same file · both live branches
7. [ ] D-5: delete `_buildWeightAdjustmentSection` (:106-155) and `_kTimedStatusRowBottomGap` (:10, no reader left); delete `_weightAdjustExpanded` (`lib/features/session/workout_session_screen.dart:196`) — both files
8. [ ] Green: the new file passes; the round guard stays green (S-4272, no edit); any reader the scout missed is migrated by the absence rule and listed in Progress — `test/count_up_screen_test.dart`, `test/sports_emphasis_redesign_test.dart`

Done criteria: `flutter test test/count_up_screen_test.dart test/sports_emphasis_redesign_test.dart` green (S-4260..S-4270, S-4272); `flutter analyze` at the Phase 0 baseline (182, 0 errors). The four reader files of P2a/P2b are expected red after P1 and are NOT in this phase's gateway (P1 must not touch them — scope); `test/value_stepper_row_test.dart` stays green untouched.

Predicted files: the 3 scope files, nothing else.

### Phase P2a — `crew-builder-app` (after P1; parallel with P2b, disjoint scopes)

Write scope: `test/timed_emphasis_redesign_test.dart,test/session_toolbar_rework_test.dart`.

Report: write `.work/crew/2026-10-15-38c-count-up/report-p2a.md` FIRST as a skeleton, then fill it (6 items). Builders never run the full suite.

1. [ ] Migrate the free stopped states (timed + drill): keep the dominant-digits assertion (`_metricValueText`); `STOPPED`, the play glyph and `Weight adjustment` become `findsNothing`; the drill case also finds the weight row (`value-stepper-plus-weight`) — `test/timed_emphasis_redesign_test.dart` · :282
2. [ ] Migrate the running states: digits dominant stays; `RUNNING` and the pause glyph `findsNothing` — same file · :337
3. [ ] Migrate the routine-backed stopped state: the same absence rule as item 1 — same file · :379
4. [ ] Verify the weight-chip-absent guard stays green without edits (S-4260 keeps it true) — same file · :452 (no edit)
5. [ ] Migrate S-009/S-010/S-011 to the button: before Start the centre button reads `Start`, after it reads `Log Interval`; the glyphs and the status text are `findsNothing` (same intent: Start begins the timer) — `test/session_toolbar_rework_test.dart` · :469, :501, :520
6. [ ] Migrate S-013: after the set round-trip the button still reads `Log Interval` and there is no `Resume` (the timer was not paused); the `RUNNING` assertions are dropped — same file · :703

Done criteria: `flutter test test/timed_emphasis_redesign_test.dart test/session_toolbar_rework_test.dart` green; `flutter analyze` at the Phase 0 baseline.
Predicted files: the 2 scope files, nothing else.

### Phase P2b — `crew-builder-app` (after P1; parallel with P2a, disjoint scopes)

Write scope: `test/logger_shell_screen_test.dart,test/screen_widget_test.dart`.

Report: write `.work/crew/2026-10-15-38c-count-up/report-p2b.md` FIRST as a skeleton, then fill it (7 items). Builders never run the full suite.

1. [ ] Migrate the logged-hold lock test: both weight buttons inert (taps change nothing in the repository), the number shows `10.0` and tapping it opens no dialog — `test/logger_shell_screen_test.dart` · :375
2. [ ] Migrate the edit-mode test: the row's buttons are active and the number `10.0` opens `Edit Weight` — same file · :420
3. [ ] Delete the collapsed-section test (no collapsed section any more; S-4264 and S-4267 replace it) — same file · :449
4. [ ] Rewrite the timed lbs test inverted: a timed screen with a stored extra-weight shows neither `+50.0` nor a weight row (S-4260's lbs case) — `test/screen_widget_test.dart` · :8095
5. [ ] Migrate the drill lbs test: `50.0` and `LBS` once (no `+` sign) — same file · :8148
6. [ ] Delete the timed-reveals-extra-weight test and the OutlinedButton-styling test (the button is gone; S-4260 replaces the first, the second needs no replacement) — same file · :8201, :8349
7. [ ] Verify the set-branch guards stay green without edits (`Weight adjustment` `findsNothing` on a set screen) — same file · :8290, :8344 (no edit)

Done criteria: `flutter test test/logger_shell_screen_test.dart test/screen_widget_test.dart` green; `flutter analyze` at the Phase 0 baseline.
Predicted files: the 2 scope files, nothing else.

### Phase D — `crew-docs-keeper` (after the last test-adding round is verified)

Write scope: `docs/modality_based_exercise_ui.md,docs/widget_catalog/session_widgets.md,docs/design_system.md,docs/plans/2026-10-15-38c-count-up-plan/2026-10-15-38c-count-up-plan.evidence.md`.

1. [ ] Update the timed/drill descriptions: live = plain elapsed digits (no ring, no status row, no unit caption), hold = digits + the `ValueStepperRow` weight row (stored key `extra-weight`, step from the unit setting, locked once logged); editor = the duration editor (+ the row on a hold) — `docs/modality_based_exercise_ui.md` · the effort-kind sections (:111-135) and the live-lock note (:216-224)
2. [ ] Update the `InlineMetricEditor` session-context note: live timed/drill render with `unitLabel: ''` (no caption) and no status label below the value — `docs/widget_catalog/session_widgets.md` · :55
3. [ ] Extend the `ValueStepperRow` section with the hold use: third call site, `metricType: 'weight'` with the stored key `extra-weight` through the closure, popup `Edit Weight`, limits -200..999 — same file · :146
4. [ ] Check the shared-pieces row and the no-hand-built rule still hold for the hold's use; extend the wording only if it names the reps/weight call sites exclusively — `docs/design_system.md` · :486, :509
5. [ ] Fill this plan's evidence file (per-phase check outputs, real counts) — `docs/plans/2026-10-15-38c-count-up-plan/2026-10-15-38c-count-up-plan.evidence.md`

Done criteria: every behaviour sentence names an existing test; each touched doc stays under 52 KB; docs-only phase, no test run required.
Predicted files: the 4 scope files.

Parallelism: P1 → (P2a ∥ P2b) strictly: both migrate readers of the screen P1 changes and cannot go green before it; their scopes are disjoint test files, so they run in parallel after P1. Phase D after P2a and P2b are verified (it documents what they settled, including any reader the scout missed). Phase 0b (lead, after P1): throwaway probe at 390 x 844 → S-4271 numbers; the lead's fix round writes the guard into `test/count_up_screen_test.dart` (P1's file — the lead applies fixes by script, as in 38b).

## Progress / Assumption Log / Feedback / Open questions

### Progress
- Final (lead-run): scout 2 min; architect 7.5 min (edge scenarios S-4273..S-4275); P1 builder 18 min; P2a 8.5 min and P2b 4.5 min in parallel; fix 1 (S-4271 layout) 4.5 min; fix 2 (one reader the scout missed: `exercise_detail_emphasis_tier_test` S-106, found by the full run) 2 min; prover 6.5 min; fix 3 (4 mutations the prover marked unproven) 6.5 min; docs keeper 5.5 min; reviewer 9.5 min. Mutations (prover list, applied by script, restored by `cmp`): 21 on `workout_session_detail_view.dart`, 17 red at once, 4 unproven closed by fix 3 and then red (21 of 21). Review: APPROVE WITH FIXES (0 blocker, 0 major, 3 minor): Progress table and S-4276..S-4279 now written here; S-4260 now also runs on a load-carrying exercise (lead added a third test, `count_up_screen_test` 26 tests); the missing `ValueStepperRow` / `SetSegmentBar` / `SetCountStepper` / `LoggedValuesLine` rows in `docs/widget_catalog.md` (inherited from 38a/38b, outside this plan) are listed for the owner. Final lead-run: full suite `+4846 ~1` all passed (baseline `+4822 ~1`: 3 tests deleted, 27 added), analyze 182 (baseline), invariant grep clean, docs contract tests green. Simulator (iPhone 17): hold and interval looked at. Seeded 2026-10-15. Baseline (lead-run, 38b tree): analyze 182 (0 errors); full suite `+4822 ~1` all passed (carried from 38b, re-run before P1).

| Item | Status |
|---|---|
| P1.1 Red S-4260..S-4263 (`test/count_up_screen_test.dart`) | done |
| P1.2 Red S-4264..S-4269 (same file) | done |
| P1.3 Red S-4270 (same file) | done |
| P1.4 D-1 timed branches (`workout_session_detail_view.dart` case `'timed'`) | done |
| P1.5 D-2 drill branches + weight row (same file, case `'drill'`) | done |
| P1.6 D-3+D-4 status rows and captions (same file, both live branches) | done |
| P1.7 D-5 dead code (`_buildWeightAdjustmentSection`, `_weightAdjustExpanded`, `_kTimedStatusRowBottomGap`) | done |
| P1.8 Green + round guard (S-4272) | done |
| P2a.1 Migrate stopped states (`timed_emphasis_redesign_test.dart` :282) | done |
| P2a.2 Migrate running states (:337) | done |
| P2a.3 Migrate routine-backed stopped (:379) | done |
| P2a.4 Guard :452 verified (no edit) | done |
| P2a.5 Migrate S-009/S-010/S-011 (`session_toolbar_rework_test.dart` :469/:501/:520) | done |
| P2a.6 Migrate S-013 (:703) | done |
| P2b.1 Migrate logged-hold lock (`logger_shell_screen_test.dart` :375) | done |
| P2b.2 Migrate edit mode (:420) | done |
| P2b.3 Delete collapsed-section test (:449) | done |
| P2b.4 Rewrite timed lbs inverted (`screen_widget_test.dart` :8095) | done |
| P2b.5 Migrate drill lbs (:8148) | done |
| P2b.6 Delete reveal + styling tests (:8201, :8349) | done |
| P2b.7 Guards :8290/:8344 verified (no edit) | done |
| D.1 timed/drill descriptions (`docs/modality_based_exercise_ui.md`) | done |
| D.2 `InlineMetricEditor` note (`docs/widget_catalog/session_widgets.md`) | done |
| D.3 `ValueStepperRow` hold use (same file) | done |
| D.4 Shared-pieces wording (`docs/design_system.md`) | done |
| D.5 Evidence file filled | done |
| Architect: code-behaviour check (the lead's three candidates) | done — block after S-4272 |
| Architect: edge scenarios S-4273..S-4275 | done — block after the code-behaviour check |
| Architect: claims (a)-(d) checked | done — Open questions (architect) |

### Assumption Log
- A-1 (lead) Dropping `ELAPSED` / `COMPLETED` and the status row is my reading of "digits big, no extra chrome"; revert is a one-line change (D-3, D-4).
- A-2 (lead) Hold weight uses the reps screen's weight limits (-200..999) instead of the old -100..200 (D-2).

### Feedback
- (none yet)

### Open questions (owner, report only)
- Is the bare `00:00` without any caption fine, or do you want a small `ELAPSED` back?

### Open questions (architect, report only)
- (a) CONFIRMED: `InlineMetricEditor` prints no caption with `unitLabel: ''` — both render branches guard on `widget.unitLabel.isNotEmpty` (`lib/widgets/session/inline_metric_editor.dart:188` inline, :207 stacked), so an empty label renders the bare number with no `SizedBox` and no `Text`. D-4's mechanism holds as seeded.
- (b) Not from today's writers, but the drill read is the one unguarded cast: every writer of a timed/drill `extra-weight` row stores `valueReal` (`double?`, `lib/core/models/session_summary.dart:200`) and every builder maps `valueReal ?? 0.0` (`lib/state/workout/session_summary_builder.dart:376,379`; `lib/core/utils/observation_grouper.dart:139`; `lib/core/utils/entry_rows.dart:47`), and `updateEntryValue` converts a non-double before storing (`value is double ? value : (value as num).toDouble()`, `lib/state/workout/session_core_entry.dart:354`). But the drill branch reads `entryData['extra-weight'] as double? ?? 0.0` (`workout_session_detail_view.dart:601`) while every other reader uses the num-safe form (:322, :390; `workout_session_screen.dart:1159`; `lib/core/services/stats_progress_service.dart:1520,1727`). P1 item 5 therefore wires the row with `(entryData['extra-weight'] as num?)?.toDouble()` — the same value today, no cast crash if a future writer stores an int.
- (c) CONFIRMED: repo-wide grep — `_weightAdjustExpanded` is declared at `workout_session_screen.dart:196` and read/written only in the detail view (:115, :127); `_kTimedValuePadding` / `_kTimedStatusRowBottomGap` are declared at `workout_session_detail_view.dart:9-10` and used only at :349, :381, :687, :719. No test reads either (the only other matches are prose in `docs/plans/`). D-5's deletion is safe; the digits keep a top-32 padding per D-5.
- (d) CONFIRMED with one caveat: `_updateMetricValue` converts `extra-weight` when `value is double` (`workout_session_screen.dart:1438-1441`) before the `widget.editMode` branch (:1444), so both live (persist via `updateEntryValue`, :1466-1470) and edit (buffer + `entries[entryIndex][metricKey] = value`, :1449-1462) handle the key. `ValueStepperRow` emits a `double` for `metricType: 'weight'` (`MetricStepCalc.parseAndClamp('weight', ...)` returns a clamped double, `lib/widgets/session/metric_crown_widget.dart:36`), so the guard holds. Caveat: an `int` value would skip the unit conversion (the `value is double` guard) and reach `updateEntryValue` unconverted — unreachable from the row, but it is the write-side twin of the int-shaped hole claim (b) flags on the read side.
- The drill editor today calls `_buildWeightAdjustmentSection` unconditionally (`workout_session_detail_view.dart:657`) while the timed editor gates it on `entryData['extra-weight'] != null` (:316); the drill live branch is also unconditional (:722) vs the timed live branch gated (:384). D-2's always-visible row makes the distinction disappear — noted so the builder does not read the gate as intentional behaviour to preserve.
- Readers-table spot check: the seeded line numbers for `timed_emphasis_redesign_test.dart` (:282/:337/:379/:452), `session_toolbar_rework_test.dart` (:469/:501/:520/:703), `logger_shell_screen_test.dart` (:375/:420/:449) and `screen_widget_test.dart` (:8095/:8148/:8201/:8349/:8290/:8344) all match the `testWidgets` declarations on disk this run. No drift; the table stands as seeded.
