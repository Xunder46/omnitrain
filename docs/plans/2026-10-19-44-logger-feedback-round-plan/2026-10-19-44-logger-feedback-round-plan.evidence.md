# Evidence — plan 44, logger feedback round

Implementers write here, not into the plan: baselines, `git status --short` at phase start and end, red→green tables, suite counts, the Phase 4 repro table, and the detail behind Assumption Log entries.

## Phase 1 — ring looks, shared colours, caption format

Outcome: built. `SessionProgressColors` (`lib/widgets/session/session_progress_colors.dart`) owns the two fills; `SetSegmentBar._segment` and `TimerRing` read it (pixel-identical). `TimerRing` gained `TimerRingLook` (`ready`, `counting` default); the round branch of `_buildMetricWidget` picks the look and the progress per D-4 (ready = full dim circle, no track; logged early = `(planned − actual) / planned`; drained = grey track only, no arc at progress 0). `_loggedValueText` formats timed, drill and round captions with `OmniDateUtils.formatTimerDigits`.

Test files: `test/timer_ring_test.dart`, `test/round_countdown_screen_test.dart` (S-5101, S-5103..S-5107; S-4411's ring clause became S-5105), `test/session_progress_colors_test.dart` (new, S-5102 + the S-5106 painter clause), `test/count_up_screen_test.dart`, `test/logger_shell_screen_test.dart` (S-5108), with `test/set_shell_widgets_test.dart`, `test/round_auto_expiry_test.dart`, `test/sports_emphasis_redesign_test.dart`, `test/count_up_hero_layout_test.dart` re-run as untouched guards.

## Phase 2 — forward arrow, rest chip, reps anchoring, title

Outcome: built. `_buildSetControls` disables the forward arrow on the last set of the last exercise (live and session editor; same dim look as the back arrow at the first set; wakes when a set or exercise is added). `_buildRestOverlayChip` renders pause/play on the tonal/muted fills with primary foreground and `Pause rest` / `Resume rest` labels, identical rect across states, on the detail view and both list views. The `set`-effort body is `LayoutBuilder > SingleChildScrollView > ConstrainedBox(minHeight) > Align(Alignment(0, 0.2))` — 60 % of the spare space above the group, 40 % below, recomputed when the rest strip opens; top-anchored and scrolling when it does not fit; timer kinds keep the old top anchoring. `_buildHeader` gives the detail-view exercise name `maxLines: 2`; the list-view title stays one line.

Test files: `test/logger_feedback_controls_test.dart` (new, S-5109..S-5115), `test/logger_feedback_layout_test.dart` (new, S-5116, S-5117, S-5119), with `test/pr4_session_controls_test.dart`, `test/widget_test.dart`, `test/reps_screen_test.dart`, `test/rest_timer_docked_strip_test.dart`, `test/unified_rest_overlay_test.dart`, `test/timer_digits_hours_test.dart`, `test/session_toolbar_rework_test.dart`, `test/interaction_flow_test.dart`, `test/session_message_test.dart`, `test/logger_shell_screen_test.dart`, `test/pr2_launch_quality_hotfix_test.dart`, `test/resistance_emphasis_redesign_test.dart`, `test/watch_live_refresh_screen_test.dart`, `test/round_auto_expiry_test.dart`, `test/delete_focused_set_test.dart`, `test/count_up_hero_layout_test.dart` re-run as guards.

## Phase 3 — tap-to-type hint learned per control

Outcome: built. `SettingsState` gained `TapHintControl { reps, weight, roundLength, elapsed }` with `preferenceKey`s `hint_seen_tap_to_type_reps|weight|round_length|elapsed`, loaded in `_loadFromPrefs`, plus `isTapHintLearned` and `markTapHintLearned` (persists through `setPreferenceBool`, notifies once). `InlineMetricEditor` gained `onNumberTap`; `ValueStepperRow` gained `showTapHint` (default true) and `onNumberTap`. The logger hides each control's hint once that control's number is tapped; `−`/`+` never teach; remembered across restarts; the routine editor keeps showing the hint.

Test files: `test/tap_hint_learned_test.dart` (new, S-5120..S-5125), `test/settings_state_test.dart` (group `Tap-to-type hints (plan 44)`), `test/value_stepper_row_test.dart` (group `Plan 44 hint switch and number tap`), with `test/reps_screen_test.dart`, `test/round_countdown_screen_test.dart`, `test/count_up_screen_test.dart`, `test/routine_detail_screen_test.dart`, `test/logger_feedback_controls_test.dart` re-run as guards.

## Phase 4 — S-5126 repro table

| Hypothesis | Red/green | Observed set-2 weight | Root-cause line | Mechanical defect or missing rule | Fix blocked by working-tree rule? |
|---|---|---|---|---|---|
| H-1 Routine plan | not separately reproduced | 0.0 before the fix | — | covered by the D-14 rule: the routine path leaves sets after the first at 0.0; guard `S-5127-f` | No |
| H-2 Watch path | not separately reproduced | 0.0 before the fix | — | covered by the same rule (watch-logged sets are untouched by the fix) | No |
| H-3 Session editor | not separately reproduced | 0.0 before the fix | — | covered by the same rule | No |
| H-4 Type drop in `_buildPreviousValues` | green — RULED OUT | stored weight is a `double` in both repositories | — | none — the type-drop hypothesis is false | No |
| H-5 Delete then add | green with the isolating fixture (weights on every set) | carried weight present on every unlogged set | — | the delete is not at fault; H-5 was red only for H-6's reason | No |
| H-6 Sets added before set 1's weight | red → green | 0.0 before the fix; 15.0 after | `_addSet` copies the previous set's values at the moment a set is added (`lib/features/session/workout_session_screen.dart`) | missing carry rule — D-14 | No |

H-1/H-2/H-3 were not separately reproduced because H-6 matched the owner's flow and the fix rule covers them (guard `S-5127-f` pins the routine path).

## Phase 5 — the D-14 carry fix

Outcome: built. `_logSet` calls the new `_carryWeightToNextSet` (`lib/features/session/workout_session_screen.dart`): logging a phone `set` entry with weight > 0 gives the NEXT set the weight when it is unlogged and its stored weight is exactly 0.0; reps are never touched, a non-zero weight is never overwritten, skipped sets (reps 0) carry nothing, watch-logged sets are untouched.

Test files: `test/set_weight_carry_repro_test.dart` (S-5126 H-4/H-5/H-6, guards S-5127-a..f), with `test/reps_screen_test.dart`, `test/delete_focused_set_test.dart`, `test/exercise_set_last_value_test.dart` re-run as guards.
