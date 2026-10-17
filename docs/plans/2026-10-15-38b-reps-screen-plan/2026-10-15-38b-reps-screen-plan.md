# Plan 38b — Reps screen: `ValueStepperRow` for reps and weight

Status: SEEDED by the lead. Base: working tree on `claude_develop` on top of the uncommitted 38a (HEAD `80928669`; `pubspec.yaml` has an unrelated change: never touch it). Not authorised to commit: the owner commits; never push.
Series: `docs/plans/2026-10-15-38-logger-rework-series.md` (its O-1..O-12 and T-1..T-4 bind this plan). 38a: `docs/plans/2026-10-15-38a-logger-shell-plan/`. Scenario ids `S-424x`..`S-425x` (grep'd free in `test/`, `docs/`, `lib/`, `watch/`).

## Goal and acceptance

What a user sees on the exercise screen for a resistance exercise (effort kind `set`), in a live session and in the session editor (both use the same `_buildMetricWidget` branch):

- A1. Under the 38a bar block, two full-width rows stacked: reps, then weight. Each row: `−` on the left, the big number with its unit (`REPS`, `KG`/`LBS`) in the middle, `+` on the right. The `−` and `+` buttons are at least 48 x 48 dp.
- A2. Tapping the number opens the existing edit popup (`showMetricEditPopup`: same title, same field, same clamping) — unchanged (O-12).
- A3. One tap on `−`/`+` changes the value by one step: reps by 1 (never below 0, never above 999); weight by 2.5 kg, or 5 lb when the unit setting is pounds (limits as the popup: -200..999 in the shown unit). The stored weight stays kilograms (FI-1).
- A4. Press and hold on `−` or `+` repeats the step and speeds up the longer it is held (slow repeat first, then faster). The number on screen follows the hold; the value is stored once, when the finger lifts. A single quick tap never repeats.
- A5. Live session: on a logged set both rows are locked: the buttons are dimmed and do nothing, the number is not tappable (38a rule, O-2). The session editor (`editMode`) never locks.
- A6. Everything else on the screen is as 38a left it: bar, count text, logged line, sets stepper, rest strip and chip, arrows-and-button row, `Log Set` logic, the PR toast. Reps and weight of the *current set* are what the rows edit (as the two editors did).
- A7. At 390 x 844 dp with the rest strip up the sets stepper is still reachable without scrolling past the rest strip (lead measures; if not, the row height gives way, not the touch targets).
- A8. `flutter analyze` not above the baseline in Progress (0 errors); `flutter test` not below the baseline pass count minus tests this plan removes (list in Progress); no allowlist entry, no ratchet raised.

## Feature invariants

- FI-1 Units: the shown weight is `UnitFormatter.convertWeight(kg)`; the value handed to the screen is in the shown unit and the screen converts it to kg through the existing `_updateMetricValue` path (`workout_session_screen.dart` `_updateMetricValue`, which calls `UnitFormatter.toCanonicalWeight`). The row never converts. Steps are in the shown unit (2.5 kg / 5 lb), the same numbers the watch uses (`WatchMetricStepping.kilogramsPerDetent` / `poundsPerDetent`).
- FI-2 Theme tokens only (`docs/global_conventions.md` "Theme tokens only"); palette ratchet in `test/palette_legibility_contract_test.dart`.
- FI-3 The row is registered in the `docs/design_system.md` shared-pieces table (T-1). No hand-built copy of a minus/number/plus row anywhere in `lib/features/`.
- FI-4 Phone code never imports `lib/watch` (the weight step lives in `lib/core`). A test pins the core numbers to the watch's constants so they cannot drift.
- FI-5 Touch targets >= 48 dp; tap-to-type keeps the existing popup; no new dialog or sheet (T-3).
- FI-6 No data-model, repository or watch-wire change (T-2).

## Decision Ledger

- D-1 `MetricStepping` (new, `lib/core/utils/metric_stepping.dart`, library-level abstract final class like `WatchMetricStepping`): `static const double kilogramsPerStep = 2.5; static const double poundsPerStep = 5; static const int repsPerStep = 1;` and `static double weightStepFor(String? weightUnit)` -> `poundsPerStep` when `UnitFormatter.normalizeWeightUnit(weightUnit) == 'lbs'` else `kilogramsPerStep`. Input is the unit string (`settings.preferredWeightUnit`), so core does not depend on `SettingsState`. Why not reuse `WatchMetricStepping`: it lives in `lib/watch` and phone code must not import it (series brief); it also returns a canonical-kg step, the phone row works in the shown unit. Pinned to the watch: a test asserts `MetricStepping.kilogramsPerStep == WatchMetricStepping.kilogramsPerDetent` and the same for pounds (tests may import `lib/watch`).
- D-2 `ValueStepperRow` (new, `lib/widgets/session/value_stepper_row.dart`, `StatefulWidget`): constructor `ValueStepperRow({super.key, required String metricType /* 'reps' | 'weight' */, required num currentValue /* shown unit */, required String unitLabel, required double step, bool isReadOnly = false, required ValueChanged<dynamic> onValueChanged})`. `onValueChanged` receives `int` for reps and `double` for weight, exactly what `InlineMetricEditor.onValueChanged` gives `_updateMetricValue` today. Layout: `Row(children: [stepButton(minus), Expanded(Center(FittedBox(fit: scaleDown, child: InlineMetricEditor(metricType, currentValue: shown, unitLabel, showUnitInline: true, emphasisTier: dominant, isReadOnly, padding: EdgeInsets.symmetric(horizontal: 8, vertical: 12), onValueChanged: ...)))), stepButton(plus)])` inside `Padding(horizontal 16)`. The number is the existing `InlineMetricEditor`, so the popup, the formatting, the read-only look and the finders of existing tests (`find.byType(InlineMetricEditor)`, `metricType`) keep working (A2).
- D-3 Step buttons (private widget in the same file): a 48 x 48 `Material`-circle target, icon `Icons.remove` / `Icons.add` (size 28), `Tooltip(message: 'Decrease reps' | 'Increase reps' | 'Decrease weight' | 'Increase weight', triggerMode: TooltipTriggerMode.manual)` (the default long-press trigger would fight the hold-to-repeat), `Semantics(button: true, label: same text)`, keys `value-stepper-minus-$metricType` / `value-stepper-plus-$metricType`. Colour `colorScheme.onSurface`; disabled/locked `onSurface` at alpha 0.3 (`withAlpha(77)`), no tap. Taps and holds use one `GestureDetector(behavior: HitTestBehavior.opaque, onTap, onLongPressStart, onLongPressEnd, onLongPressCancel)`. `ui_standards_contract_test.dart` rules for `IconButton` do not apply to this widget; if that contract flags it, fix the widget, never the contract.
- D-4 Step math: `base = (pending ?? currentValue)`; for weight round `base` to 1 decimal first (the shown precision) so repeated lb steps do not drift; `next = MetricStepCalc.parseAndClamp(metricType, (base ± step).toString())` (`lib/widgets/session/metric_crown_widget.dart:13`) — one clamp function for popup and buttons; for weight round the result to 1 decimal; if `next == base` do nothing (at a limit).
- D-5 Local value: the row keeps `pending` (the latest intended value). Tap: set `pending = next`, call `onValueChanged(next)` at once. Hold: after `onLongPressStart` the row steps repeatedly, updating only `pending` and the shown number; on `onLongPressEnd` it calls `onValueChanged(pending)` once; on `onLongPressCancel` / dispose it drops the hold without a store (a cancel after ticks commits the pending value too: treat Cancel like End). `pending` is cleared in `didUpdateWidget` whenever `currentValue` changed, and the shown number is `pending ?? currentValue`. This stops two quick taps from both reading a stale `currentValue` while the screen is still reloading.
- D-6 Repeat schedule (`const` in the file): first tick at `onLongPressStart` (Flutter delivers it after the ~500 ms long-press delay); then every 200 ms for the first 5 ticks, every 100 ms for the next 10, every 50 ms after. Same step on every tick (acceleration is by rate, not by step size, so weight stays on 2.5/5 multiples). `Timer` cancelled in `dispose`, on end and on cancel; a read-only row never starts one.
- D-7 Wiring: `_buildMetricWidget` case `'set'` (`lib/features/session/workout_session_detail_view.dart:219-246`) replaces the two `InlineMetricEditor`s by two `ValueStepperRow`s inside the same `Column(mainAxisSize: min)`; `isReadOnly: isLoggedNow` as today; `step: MetricStepping.repsPerStep.toDouble()` for reps and `MetricStepping.weightStepFor(widget.settingsState.preferredWeightUnit)` for weight; same `onValueChanged` closures (`_updateMetricValue(effortId, entryIndex, 'reps'|'weight', value)`). The `SizedBox(height: 8)` above stays. No change to the `timed`/`round`/`drill` branches (38c, 38d).
- D-8 Docs: row added to the shared-pieces table in `docs/design_system.md`; `docs/widget_catalog/session_widgets.md` gets the widget; `docs/modality_based_exercise_ui.md` set-effort description updated; `docs/README.md` only if it lists widgets.
- D-9 Out of scope (do not touch): count-up, countdown, hold weight (`extra-weight`) editor, routine editor (`RoutineSetupScreen` has its own editors), the rest chip and strip, watch.

## Existing-functionality impact

| Touched surface | What reads it | Effect |
|---|---|---|
| `_buildMetricWidget` `set` case | readers table below | two `InlineMetricEditor`s stay in the tree, inside the new rows (same `metricType`, same `isReadOnly`), so editor-based finders keep resolving; layout and any icon finder change |
| `Icons.add` / `Icons.remove` on the session screen | `SetCountStepper` already shows both icons (`set-count-add`, `set-count-remove`) | the new rows add two more of each: any `find.byIcon(Icons.add/remove)` test becomes ambiguous (readers table) |
| Vertical space | the sets stepper sits under the metric block (38a) | two taller rows push it down; lead measures at 390 x 844 with the rest strip up (playbook (o)) |

### Readers table (scout sheet, spot-checked; searched `test/` at the working tree)

| Test (file:line) | Reads | Effect | Change |
|---|---|---|---|
| `resistance_emphasis_redesign_test.dart:456,462` | `find.byType(InlineMetricEditor).at(0)/.at(1)` text size and colour | editors stay inside the rows in the same order (reps, weight) | none — guard |
| `pr2_launch_quality_hotfix_test.dart:483-502` S-003e | taps `InlineMetricEditor.first` (reps) | editor stays; tap lands on its centre | none — guard |
| `interaction_flow_test.dart:619` | taps `InlineMetricEditor.first`'s `GestureDetector.first` (editMode) | the row adds GestureDetectors, but the finder is `descendant of the editor` | none — guard (builder confirms) |
| `watch_live_refresh_screen_test.dart:472,497,505` | text inside `InlineMetricEditor` | unchanged | none — guard |
| `exercise_detail_emphasis_tier_test.dart:116-135` | `emphasisTier` of reps/weight editors | row passes `dominant` | none — guard |
| `logger_shell_screen_test.dart:117-125,328-371,783` | `_editorOf('reps'/'weight')`, `isReadOnly`, `_editorNumber` | editors stay | none — guard |
| `crown_control_tap_to_edit_test.dart` T-14 `:486-541` | first non-read-only editor, tap -> dialog | editors stay | none — guard |
| `screen_widget_test.dart:8044-8091` | `100.0` once, `LBS` once | unit shown once in the weight editor | none — guard |
| `session_toolbar_rework_test.dart:613,648,688,808,831,854,857,863` | bare `find.byIcon(Icons.remove)` (tap, `findsOneWidget`, `findsNothing`) | ambiguous: the new rows also show `Icons.remove`/`Icons.add` | migrate to `find.byKey(const Key('set-count-remove'))` (same intent: the sets stepper) |
| `watch_session_edit_restore_late_entry_test.dart:1003`, `unsaved_changes_dialog_test.dart:104` | bare `find.byIcon(Icons.add)` + tap | ambiguous | migrate to `find.byKey(const Key('set-count-add'))` |
| `exercise_set_last_value_test.dart:106`, `resistance_emphasis_redesign_test.dart:372,382`, `logger_shell_screen_test.dart` set-count keys | key / tooltip finders | `Add set` / `Remove set` / `set-count-*` untouched; the new tooltips are `Increase/Decrease reps/weight` | none — guard |
| `set_shell_widgets_test.dart:265,287` | widget-level `byIcon(Icons.remove), findsNothing` inside `SetCountStepper` | a different widget tree | none — guard |

Any other test that fails after P2 is a reader the scout missed: migrate it with the same rule (key finder, never a looser assertion) and list it in Progress.

### Framework-behaviour check (architect, 2026-10-15)

Checked every framework claim in D-3..D-6 against the repo and the framework's documented behaviour. The Flutter SDK source itself was not reachable this run (file tools are limited to the repo; the only allowed shell command is `gateway.sh`) — see Open questions.

- D-3 GestureDetector timing: `onLongPressStart` fires when the long-press deadline (Flutter's 500 ms timeout) expires, `onLongPressEnd` on pointer lift, `onLongPressCancel` when the recognizer loses the arena or the pointer is cancelled. Consistent with S-4244's pump arithmetic (first tick at t = 500 ms). S-4244/S-4245 are the executable proof: if the 500 ms assumption were wrong, their literal 16-at-1500 ms assertion fails.
- D-3 `TooltipTriggerMode.manual`: real enum value; in manual mode the `Tooltip` installs no long-press gesture of its own (the default on touch is `TooltipTriggerMode.longPress`, which would fight the hold-to-repeat). Claim sound.
- D-2 `FittedBox(fit: BoxFit.scaleDown)` around `InlineMetricEditor`: shrinks an over-wide child, never grows; inside `Expanded(Center(...))` it receives bounded constraints, so a long value scales down instead of overflowing. Claim sound.
- D-5/D-6 FakeAsync: `tester.pump(Duration)` advances `Timer.periodic` inside `testWidgets`, so the hold tests need no real delays. Claim sound.
- D-3 ui_standards claim: the S-2606 rule scans `IconButton` constructor calls in `lib/` (`test/ui_standards_contract_test.dart:91-98, 818-821`); the step buttons are `Material` + `GestureDetector`, so the rule does not apply. Verified.

## Core scenarios (exact fixtures)

Fixtures: widget tests with plain `testWidgets` and no real delays (`tester.pump(Duration)` advances the repeat timer inside FakeAsync); screen tests copy the pump helper of `test/logger_shell_screen_test.dart`. `MockWorkoutRepository`.

Core helper (`test/metric_stepping_test.dart`, plain `test`):
- S-4240 `weightStepFor('kg')` is 2.5, `weightStepFor('lbs')` 5, `weightStepFor(null)` and `weightStepFor('stone')` 2.5; reps step 1; the constants equal `WatchMetricStepping.kilogramsPerDetent` / `poundsPerDetent`. Fails today: file missing.

Widget (`test/value_stepper_row_test.dart`):
- S-4241 reps row, `currentValue: 10`, step 1: tap plus -> `onValueChanged(11)` (an `int`); tap minus -> `9`. With `currentValue: 0` minus calls nothing; with `999` plus calls nothing.
- S-4242 weight row, `currentValue: 60.0`, step 2.5: plus -> `62.5` (a `double`); minus -> `57.5`. Pounds: `currentValue: 220.5`, step 5: plus -> `225.5`, minus -> `215.5`. Weight `-200.0` minus calls nothing.
- S-4243 two taps in a row before the parent rebuilds (reps, `currentValue` stays 10): `onValueChanged` gets 11 then 12 (pending, D-5).
- S-4244 hold: press on plus (reps, 10), pump 500 ms (long-press delay), then pump 200 ms x 5, the number on screen reads above 13 while `onValueChanged` has not been called; lift: it is called exactly once with the shown value. Exact arithmetic: the first tick fires when `onLongPressStart` does (t = 500 ms) and every 200 ms after for 5 ticks (t = 700..1500 ms), so after pumping to t = 1500 ms there were 6 ticks and the number reads 16 (10 + 6). The test derives the schedule from the exported constants and asserts the literal 16.
- S-4245 acceleration: held for another 1000 ms after the last 200 ms tick the tick count is higher than 5 more (at 100 ms: 10 more -> 26) — the test asserts the shown number against the constants' schedule; a held row at the schedule's end speeds to 50 ms.
- S-4246 `isReadOnly: true`: both buttons exist, tapping or holding changes nothing, `onValueChanged` never called, and tapping the number opens no dialog; `isReadOnly: false`: tapping the number opens `Edit Reps` and `Ok` calls `onValueChanged`.
- S-4247 both buttons are at least 48 x 48 dp; tooltips `Decrease reps` / `Increase reps` / `Decrease weight` / `Increase weight`; the row's width equals the available width (full-width).
- S-4248 a hold cancelled by moving the finger far away still commits the pending value once (D-5); disposing mid-hold leaves no pending timer (the test ends with no `Timer is still pending` error).

Screen (`test/reps_screen_test.dart`, new):
- S-4250 Resistance `Barbell Back Squat`, 3 sets, set 1 reps 10, weight 60.0: the screen shows two rows (`value-stepper-plus-reps`, `value-stepper-plus-weight`); tapping reps plus makes the reps number 11 and the stored `entry['reps']` 11; weight plus makes stored weight 62.5. Fails today: no rows.
- S-4251 Pounds (`preferredWeightUnit` `lbs`), set weight 100.0 kg shown `220.5`: weight plus shows `225.5` and the stored weight equals `UnitFormatter.toCanonicalWeight(225.5, settings)` (the test derives the expected kg from the formatter).
- S-4252 Live, set 1 logged (`recordRestStart(effortId, 1)`), focused: plus/minus on both rows do nothing (stored values unchanged); an unlogged set's plus works. Edit mode (`editMode: true`) on the same data: plus changes the buffered value.
- S-4253 Holding plus on the reps row of the live screen for 2 s stores the value once (read the repository after lift: one change, equal to the shown number).
- S-4254 Tapping the weight number still opens `Edit Weight` and Ok applies (O-12).
- S-4255 Layout guard: with the rest strip up (log a set so the chip shows) at the 390 x 844 surface the `set-count-add` button is fully on screen (its rect bottom <= the rest strip's top); literal numbers recorded by the lead's probe go in this test (Phase 0b).
- S-4256 Unmoved: `Log Set` still logs the current values (the logged line shows the stepped value), and the rest chip appears (rest suites stay green, no edit).

### Edge scenarios (architect, added 2026-10-15)

- S-4257 (screen, `test/reps_screen_test.dart`): live, 2 sets (set 1 reps 10, set 2 reps 8); hold plus on the reps row of set 1; after the first ticks tap the `Next` arrow so the focused set becomes set 2; pump past the lift. Outcome: nothing is stored on either set (set 2 stays 8, set 1 keeps 10), the row now under the finger shows set 2's 8 and does not step it. Why it fails without the change: without a key the same row State survives the set change — `didUpdateWidget` clears `pending` (10 → 8 changed) but the running timer keeps stepping from the new `currentValue` and the lift commits to set 2, a set the user is no longer editing. Fix (one line, call site): `key: ValueKey('$effortId-$entryIndex-reps')` and `key: ValueKey('$effortId-$entryIndex-weight')` on the two rows in the `set` branch, so a set change discards the old State (its `dispose` cancels the timer per D-6) and the new row never saw the pointer down.
- S-4258 (widget, `test/value_stepper_row_test.dart`): weight row `currentValue: 999.0`, step 2.5: tap plus → `onValueChanged` never called (`MetricStepCalc.parseAndClamp` clamps to 999.0, `next == base` → no-op, D-4). Completes the clamp matrix (reps 0/999 and weight −200 are S-4241/S-4242). Fails without D-4's clamp: the row would emit 1001.5, a value the popup itself would never accept.
- S-4259 (widget, `test/value_stepper_row_test.dart`): hold running on plus (reps, `currentValue: 10`); after two ticks rebuild the row with `isReadOnly: true` (what the parent does when the watch logs the set mid-hold); pump past more ticks, lift. Outcome: the hold stops at the rebuild (timer cancelled in `didUpdateWidget`), `onValueChanged` is never called, the shown number reverts to the parent's value. Why it fails without the change: the lift handler would fire `onValueChanged(pending)` on a now-locked set and overwrite the watch's logged observation (O-2). Builder note: `didUpdateWidget` treats an `isReadOnly` false→true flip as a cancel-without-store — distinct from D-5's user cancel (arena lost while the user is still holding), which commits; the set is no longer editable, so the pending intent is dropped.

## Phase outline

- Phase 0 (lead): analyze count and full-suite pass count into Progress (carry 38a's: analyze 182, `+4788 ~1`; re-run before P1 to confirm the tree is unchanged). Scout readers sheet -> readers table. Phase 0b (after P2 wiring): throwaway probe of positions at 390 x 844 with the rest strip up -> S-4255 numbers.
- P1 `crew-builder-app`, scope `lib/core/utils/metric_stepping.dart,lib/widgets/session/value_stepper_row.dart,test/metric_stepping_test.dart,test/value_stepper_row_test.dart`: D-1..D-6, S-4240..S-4248. 4 files. Serial before P2 (P2 imports P1).
- P2 `crew-builder-app`, scope `lib/features/session/workout_session_detail_view.dart,test/reps_screen_test.dart` plus the reader test files the readers table lists: D-7, S-4250..S-4256 and the migrations.
- Phase D `crew-docs-keeper` (after P2 verified): D-8 docs + this plan's evidence.
- Then `crew-prover` (mutation list: no step, wrong unit step, pending dropped, commit on every tick, lock removed, no clamp) -> lead applies by script; `crew-reviewer`; lead looks at the screen on the iOS simulator at 390 x 844 (live, rest strip up; `Edit Session`; pounds).

### Phase P1 — `crew-builder-app` (runs first; P2 imports its widget)

Write scope: `lib/core/utils/metric_stepping.dart,lib/widgets/session/value_stepper_row.dart,test/metric_stepping_test.dart,test/value_stepper_row_test.dart` (both directories exist: `unit_formatter.dart` lives in `lib/core/utils/`, `inline_metric_editor.dart` in `lib/widgets/session/`).

Report: write `.work/crew/2026-10-15-38b-reps-screen/report-p1.md` FIRST as a skeleton, then fill it (8 items).

1. [ ] Red: write S-4240 (step constants, `weightStepFor` unit mapping, the watch pin) — `test/metric_stepping_test.dart` · `main`
2. [ ] Implement `MetricStepping` per D-1 (constants + `weightStepFor` via `UnitFormatter.normalizeWeightUnit`) — `lib/core/utils/metric_stepping.dart` · `MetricStepping`
3. [ ] Red: write S-4241..S-4248 (taps, pending, hold/acceleration against the planned schedule constants, read-only + popup, geometry/tooltips/full-width, cancel/dispose) — `test/value_stepper_row_test.dart` · `main`
4. [ ] Implement `ValueStepperRow` per D-2 (constructor, `Row` layout, `InlineMetricEditor` inside `FittedBox`, `Padding(horizontal: 16)`) — `lib/widgets/session/value_stepper_row.dart` · `ValueStepperRow`
5. [ ] Implement the step buttons per D-3 (48 x 48 `Material` circle, `Icons.remove`/`Icons.add` size 28, manual tooltips, `Semantics(button: true)`, keys, disabled `withAlpha(77)`) — `lib/widgets/session/value_stepper_row.dart` · `_StepButton`
6. [ ] Implement the step math per D-4 (base = `pending ?? currentValue`, 1-decimal round for weight, `MetricStepCalc.parseAndClamp`, no-op when `next == base`) — `lib/widgets/session/value_stepper_row.dart` · `_ValueStepperRowState`
7. [ ] Implement the pending/commit rules per D-5 (tap commits at once; hold commits once on End and on Cancel; `didUpdateWidget` clears `pending` when `currentValue` changed; read-only flip mid-hold drops the hold per S-4259) — `lib/widgets/session/value_stepper_row.dart` · `_ValueStepperRowState.didUpdateWidget`
8. [ ] Implement the repeat schedule per D-6 (exported const schedule: 200 ms x 5, 100 ms x 10, 50 ms after; `Timer` cancelled in dispose/end/cancel; a read-only row never starts one) — `lib/widgets/session/value_stepper_row.dart` · `_ValueStepperRowState`

Done criteria: `flutter test test/metric_stepping_test.dart test/value_stepper_row_test.dart` green (S-4240..S-4248); `flutter test test/ui_standards_contract_test.dart test/palette_legibility_contract_test.dart` green; `flutter analyze` at the Phase 0 baseline count.
Predicted files: the 4 scope files, nothing else.

### Phase P2 — `crew-builder-app` (after P1)

Write scope: `lib/features/session/workout_session_detail_view.dart,test/reps_screen_test.dart,test/session_toolbar_rework_test.dart,test/watch_session_edit_restore_late_entry_test.dart,test/unsaved_changes_dialog_test.dart`.

Report: write `.work/crew/2026-10-15-38b-reps-screen/report-p2.md` FIRST as a skeleton, then fill it (6 items).

1. [ ] Red: write S-4250..S-4254, S-4256 (rows present, stored values, pounds conversion, live lock + edit mode, hold stores once, popup, `Log Set`/rest chip) — `test/reps_screen_test.dart` · `main`
2. [ ] Replace the two `InlineMetricEditor`s by two `ValueStepperRow`s per D-7 (keys `ValueKey('$effortId-$entryIndex-reps')` / `-weight` per S-4257, steps from `MetricStepping`, same `onValueChanged` closures, `SizedBox(height: 8)` stays) — `lib/features/session/workout_session_detail_view.dart` · `_buildMetricWidget` case `'set'` (:211-247)
3. [ ] Write S-4257 (mid-hold set change via the arrows stores nothing on the new set) — `test/reps_screen_test.dart` · `main`
4. [ ] (moved) S-4255 layout guard is written in fix round 1 after the lead's Phase 0b probe — not in this phase
5. [ ] Migrate the bare `Icons.remove` finders to `find.byKey(const Key('set-count-remove'))` (same intent: the sets stepper) — `test/session_toolbar_rework_test.dart` · S-014/S-015/S-016 (:613, 648, 688), S-020/S-021/S-022 (:808, 831, 854, 857, 863)
6. [ ] Migrate the bare `Icons.add` taps to `find.byKey(const Key('set-count-add'))` — `test/watch_session_edit_restore_late_entry_test.dart` · :1003; `test/unsaved_changes_dialog_test.dart` · :104
7. [ ] Verify the guard readers stay green without edits (resistance_emphasis_redesign, pr2_launch_quality_hotfix, interaction_flow, watch_live_refresh, exercise_detail_emphasis_tier, logger_shell_screen, crown_control_tap_to_edit, screen_widget, exercise_details_capability_grouping) — (no edit)

Done criteria: `flutter test test/reps_screen_test.dart test/session_toolbar_rework_test.dart test/watch_session_edit_restore_late_entry_test.dart test/unsaved_changes_dialog_test.dart` green; the guard files of item 7 green; `flutter analyze` at the Phase 0 baseline count.
Predicted files: the 5 scope files, nothing else.

### Phase D — `crew-docs-keeper` (after P2 verified)

Write scope: `docs/design_system.md,docs/widget_catalog/session_widgets.md,docs/modality_based_exercise_ui.md,docs/README.md,docs/plans/2026-10-15-38b-reps-screen-plan/2026-10-15-38b-reps-screen-plan.evidence.md`.

1. [ ] Add a `ValueStepperRow` row to the shared-pieces table — `docs/design_system.md` · Shared pieces table (:484-486)
2. [ ] Add a `### ValueStepperRow` section after `SetCountStepper` (constructor, steps, hold behaviour, keys, tooltips; every behaviour sentence names an existing test) — `docs/widget_catalog/session_widgets.md`
3. [ ] Update the set-effort description: reps/weight render as `ValueStepperRow` rows (tap still opens the popup; logged sets locked) — `docs/modality_based_exercise_ui.md` · section 1 (:92) and the live-lock note (:211)
4. [ ] Update the `widgets/session/` tree line to include `ValueStepperRow` — `docs/README.md` · project-structure tree (:161)
5. [ ] Fill this plan's evidence file (per-phase check outputs, real counts) — `docs/plans/2026-10-15-38b-reps-screen-plan/2026-10-15-38b-reps-screen-plan.evidence.md`

Done criteria: every behaviour sentence names an existing test; each touched doc stays under 52 KB; docs-only phase, no test run required.
Predicted files: the 5 scope files.

Parallelism: P1 → P2 strictly (P2 imports P1's widget and constants; P2 cannot go green without P1). Phase D after P2 is verified (it documents what P2 built). No two phases have disjoint-enough scopes to run in parallel.

## Progress / Assumption Log / Feedback / Open questions

### Progress
- Final (lead-run): P1 builder 9 min, P2 builder 6 min, fix 1 (S-4255) 6 min, docs keeper 4 min, prover 10 min, fix 2 (3 guard tests) 4 min, reviewer 6 min. Mutations (prover list, applied by script, each restored byte-identical by `cmp`): 33 single-line mutations, 28 red at once, 3 more red after fix 2 (14 base rounding, 23 dimmed icon, 28 weight-row key), 2 unobservable (the `isReadOnly` guard in `_handleHoldStart` is unreachable because a locked row passes null handlers; `TooltipTriggerMode.manual` cannot be told apart in a widget test). Review: APPROVE WITH FIXES (1 blocker = a stale "unguarded" doc claim, fixed; 1 major = Assumption Log, filled; 1 minor = A-4). Simulator (iPhone 17): rows, tap, 2.5 s hold, Log Set, locked set looked at. Seeded 2026-10-15. Baseline before P1 (lead-run, 38a tree): analyze 182 (0 errors); full suite `+4788 ~1` all passed. Scope guard: plan ~210 lines, 3 phases, ~150 production lines predicted: inside the budget.

| Item | Status |
|---|---|
| P1.1 Red S-4240 (`test/metric_stepping_test.dart`) | pending |
| P1.2 `MetricStepping` (`lib/core/utils/metric_stepping.dart`) | pending |
| P1.3 Red S-4241..S-4248 (`test/value_stepper_row_test.dart`) | pending |
| P1.4 `ValueStepperRow` layout (`lib/widgets/session/value_stepper_row.dart`) | pending |
| P1.5 Step buttons `_StepButton` (same file) | pending |
| P1.6 Step math `_ValueStepperRowState` (same file) | pending |
| P1.7 Pending/commit rules `didUpdateWidget` (same file) | pending |
| P1.8 Repeat schedule (same file) | pending |
| P2.1 Red S-4250..S-4254, S-4256 (`test/reps_screen_test.dart`) | pending |
| P2.2 Wire two `ValueStepperRow`s (`workout_session_detail_view.dart` `_buildMetricWidget`) | pending |
| P2.3 S-4257 mid-hold set change | pending |
| P2.4 S-4255 layout guard | moved to fix round 1 (after the lead's probe) |
| P2.5 Migrate `Icons.remove` finders (`session_toolbar_rework_test.dart`) | pending |
| P2.6 Migrate `Icons.add` taps (`watch_session_edit_restore_late_entry_test.dart`, `unsaved_changes_dialog_test.dart`) | pending |
| P2.7 Guard readers verified green (no edit) | pending |
| D.1 Shared-pieces table row (`docs/design_system.md`) | pending |
| D.2 Widget-catalog section (`docs/widget_catalog/session_widgets.md`) | pending |
| D.3 Set-effort description (`docs/modality_based_exercise_ui.md`) | pending |
| D.4 Tree line (`docs/README.md`) | pending |
| D.5 Evidence file filled | pending |
| Architect: framework-behaviour check (D-3..D-6) | done — block under the Readers table; SDK source not reachable, see Open questions |
| Architect: reader sweep outside the Readers table | done — no missed reader of the `set` branch; one extra guard listed under Open questions |
| Architect: edge scenarios S-4257..S-4259 | done — block after S-4256 |

### Assumption Log
- A-1 (lead, ratified) Hold schedule 200 ms x 5, 100 ms x 10, 50 ms after, same step size (D-6): speed is a feel choice the owner may retune; behaviour on the screen is the same at any value.
- A-2 (lead, ratified) A lock that arrives mid-hold (the watch logged the set) drops the pending intent without storing it (S-4259): O-2 says a logged set is a logged set.
- A-3 (lead, ratified) A hold dies with its set when focus moves (S-4257, row keys carry the set): a hold never stores into a set the user is no longer editing.
- A-4 (lead, accepted, review MINOR 3) `_pending` can outlive a commit the store never took (an entry with no row for the metric: legacy or odd data; a normal new entry always has reps and weight rows): the stepped number stays until the screen reloads. Documented in the widget catalog; a code fix needs a write acknowledgement from `_updateMetricValue`, out of this plan.

### Feedback
- (none yet)

### Open questions (owner, report only)
- Long-press speed (200 ms, then 100 ms, then 50 ms per step, same step size) is the lead's choice; the owner can ask for faster/slower.
- (architect, report only) D-7 cites the `set` branch at `workout_session_detail_view.dart:219-246`; on disk it spans :211-247 (`case 'set':` at 211, the two editors at 228/238, the `Column` closes at 247). Content matches the seed; only the line numbers drifted (38a edits). Kept as seeded; P2 item 2 cites :211-247.
- (architect, report only) Reader the scout missed: `test/exercise_details_capability_grouping_test.dart` S-006 (~:449-480) mounts `WorkoutSessionScreen` with a `set` effort and asserts the editor set is exactly `{reps, weight}` via `_presentMetricTypes` (:131-136). D-2 keeps both editors in the tree, so it stays green — a guard, no migration. Listed here because the Readers table is kept as seeded.
- (architect, report only) Framework claims in D-3..D-6 could not be checked against the Flutter SDK source this run (file tools are limited to the repo; the only allowed shell command is `gateway.sh`). All four claims (500 ms long-press delay, `TooltipTriggerMode.manual` installing no competing gesture, `FittedBox` scaleDown, FakeAsync advancing `Timer.periodic` on `tester.pump`) match the framework's documented behaviour, and S-4244/S-4245 are the executable proof — see the Framework-behaviour check block.
- (architect, report only) S-4259's expected outcome (a read-only flip mid-hold drops the pending intent without a store) is my proposal: D-5's "treat Cancel like End" covers the user's own cancel (arena lost while the user is still holding), not an external lock. The owner may prefer committing the pending value on lock; O-2 (a logged set is locked) argues for dropping.
- (architect, report only) S-4257's expected outcome (the hold dies with the old row, nothing stored) is my proposal; the alternative (commit set 1's pending on set change) would need the old State to observe its own replacement, which a `State` cannot.
