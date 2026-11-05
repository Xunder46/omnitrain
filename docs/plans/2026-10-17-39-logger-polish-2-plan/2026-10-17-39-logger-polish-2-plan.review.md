# Review: 2026-10-17-39-logger-polish-2 · P1-P5 · HEAD..working tree
Verdict: APPROVE WITH FIXES
Counts: blocker 0 · major 2 · minor 1 · tests: 5038 passed / 0 failed / 1 skipped (`+5038 ~1: All tests passed!`); analyze 181 issues, 0 errors = baseline
Diff vs Predicted Files: conforms; 3 files outside the phase scopes, each justified — `lib/widgets/session/duration_entry_dialog.dart` (the `maxSecs` param: A4 "the typed popup now goes to 10 h" + Progress row "Fix 1 dialog ceiling" + U-19..U-21), `docs/data_models.md` and `docs/my_routines.md` (P5 duty: their behaviour sentences described the removed interval row and named the flipped tests)

## Findings

1. [Major] `docs/widget_catalog/session_widgets.md:320` — the Verified-by sentence quotes the test name `S-4707/S-4704: the widest weight and duration values do not overflow`, but the test (`test/value_stepper_row_test.dart:1006`) is named `S-4707/S-4704: the widest weight and duration values do not overflow 390 x 844`. A maintainer grepping the doc's quoted name finds nothing. Fix: quote the full name. Guard: none needed (doc-only).
2. [Major] `docs/modality_based_exercise_ui.md:221` — the Verified-by sentence quotes `routine setup shows one weight row for a timed effort and a drill effort across all themes`, but the test (`test/timed_emphasis_redesign_test.dart:422`) reads `routine setup shows one weight row for a timed effort and a drill across all themes` (no second "effort"). Grep on the quoted name fails. Fix: match the test name. Guard: none needed (doc-only).
3. [Minor] `lib/features/session/session_overview_screen.dart:206` — the overview's per-exercise `… total` line now calls `OmniDateUtils.formatTimerDigits`, but no test would fail if it reverted to hand-padded `mm:ss`: S-4706's two tests drive the exercise-list line (`test/timer_digits_hours_test.dart`), and the `SessionOverviewScreen` group in `test/screen_widget_test.dart` asserts no total text at all. A4 names both surfaces; only one is guarded. Fix: one overview-screen case in the S-4706 group (4535 s → `1:15:35 total`), or accept as unguarded.

## Assumption Log rulings

- A-1 hint wording `tap to type` — ratify: implemented verbatim (`inline_metric_editor.dart`, key `tap-hint`, `labelSmall` + `textMuted`, no uppercase); owner may reword later.
- A-2 tap strip 18 dp / 34 dp below the 44 dp target — ratify: implemented as the named constants `kSetBarPlainHeight` / `kSetBarCaptionedHeight`; the owner saw the tightened sports screen on the device (brief facts) and the plan's hand-check is satisfied by that look.
- A-3 `112 sp` / `48 sp` first guesses — ratify: pinned as `kCountUpDigitsFontSize` / `kRingDigitsFontSize`, owner saw the 112 sp digits on the simulator (brief facts).

## Scenario coverage

- S-4701 → `test/utils_test.dart` · group `OmniDateUtils.formatTimerDigits` (0/59/600/3599, 3600/4535/8130, 36000, −5)
- S-4702 → `test/timer_digits_hours_test.dart` · 3 header tests (4535 s live, 59 s live, edit mode)
- S-4703 → `test/timer_digits_hours_test.dart` · 2 rest-chip tests (4535 s, 75 s)
- S-4704 → `test/crown_control_tap_to_edit_test.dart` · 3 `parseAndClamp` tests; `test/value_stepper_row_test.dart` · plus at 3600 / minus at 3615 / plus at the ceiling; `test/round_countdown_screen_test.dart` · 2 row tests; `test/tap_to_edit_unification_test.dart` · U-19..U-21 (dialog `maxSecs`)
- S-4705 → `test/value_stepper_row_test.dart` · 8130/135 shapes + `10:00:00` fits 320x568
- S-4706 → `test/timer_digits_hours_test.dart` · 2 list-total tests (overview line unguarded — finding 3)
- S-4707 → `test/value_stepper_row_test.dart` · group `S-4707 anatomy` (6 tests: reps/weight/duration shape, locked hides hint, widest values, locked duration)
- S-4708 → `test/count_up_screen_test.dart` · group `Cardio weight — live (S-4708)` (6 tests incl. pounds→kg, lock on log, caption time-only, hold regression) + `test/cardio_interval_weight_storage_test.dart` (Mock/Hive parity, restart survival)
- S-4709 → `test/count_up_screen_test.dart` · editor group (finished interval editable, Save stores kg) + storage test + `test/routine_detail_screen_test.dart` · S-4507 restored (old 10 kg target reads back, steps to 12.5)
- S-4710 → `test/count_up_hero_layout_test.dart` · group `S-4710 hero count-up digits` (interval 112 sp, hold 112 sp, `1:15:35`, ring 48 sp + chord) + constants test
- S-4711 → `test/count_up_hero_layout_test.dart` · group `S-4711 tightened body` (34 dp captioned, 18 dp plain, ring ≤ 12 dp of bar) + `test/set_shell_widgets_test.dart` heights
- S-4712 → spread, not one literal inventory test: `test/value_stepper_row_test.dart` anatomy group + hint assertions per surface — `test/reps_screen_test.dart` (live set, 2 hints), `test/count_up_screen_test.dart` (live hold, session-editor interval), `test/round_countdown_screen_test.dart` (round row), `test/routine_detail_screen_test.dart` (routine editor, 2 hints). Every surface the scenario names has an assertion that fails without the change.

## Brief questions answered

1. No other timer display in `lib/features/session/` or `lib/widgets/session/` hand-pads `mm:ss`. Remaining `padLeft(2` hits: `session_summary_screen.dart:1364` (a wall-clock minute, not a timer) and the duration dialog's h/m/s prefill fields; `session_summary_screen.dart:1306` is the `2h 15m` summary shape, which already handles hours.
2. Yes: both branches read `entryData['extra-weight']` through `UnitFormatter.convertWeight` (`workout_session_detail_view.dart:238` timed, `:482` drill), both write `_updateMetricValue(..., 'extra-weight', ...)` which converts display→canonical kg (`workout_session_screen.dart:1455-1457`), same `ValueKey('$effortId-$entryIndex-weight')`, and the lock is `!editMode && _isSetLogged(effortId, entryIndex, effortKind)` with `timed` → `TimedState.finished` (`workout_session_screen.dart:763-766`) — exactly when the interval is logged.
3. Yes: `_buildExtraWeightRow` (`routine_setup_screen.dart:1390-1412`) reads `MetricIds.extraWeight` through `_fromCanonicalWeight` and writes through `setTargetValue(..., MetricIds.unitKg, targetMin: _toCanonicalWeight(value))`; both the `timed` (`:1364`) and `drill` branches call it.
4. No unintentional layout change. In `lib/` the only `InlineMetricEditor` callers are `ValueStepperRow` and the five detail-view sites; the column-mode centring (`crossAxisAlignment: center`, `textAlign: center` on the label) affects exactly the surfaces A2 centres, the `unitGap` default 16 preserves the old gap for callers that pass none, and read-only editors never show the hint (`showTapHint` default false).
5. Spot-checked more than five claims against the code — all true except the two truncated test names in findings 1-2: the `maxSecs` caller inventory (3 round-length callers pass it, the whole-session/interval/hold dialogs pass nothing), the weight-row lock/editability sentences, the constants table values, the set-bar pinned-bar/chord sentences, the rest-chip format sentence, and every other new test name quoted in the five changed docs.
