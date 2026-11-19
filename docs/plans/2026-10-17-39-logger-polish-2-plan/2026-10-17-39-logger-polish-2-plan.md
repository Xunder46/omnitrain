# Plan 39 — Logger polish round 2: labels under numbers, cardio weight back, big timers, hours, tighter sports screen

Status: BUILT and reviewed 2026-10-17 (no architect run: seed was complete, as in 38g). Uncommitted on claude_develop; owner commits. Base: `dc9ada9c` on `claude_develop`, tree clean. Not authorised to commit: the owner commits; never push; no branch work.
Follow-up of series 38 (`docs/plans/2026-10-15-38-logger-rework-series.md`). Scenario ids `S-47xx` (grep clean in `test/`, `docs/`, `watch/`, `lib/` on 2026-10-17). Analyze baseline: 181 issues, 0 errors.
Hard rules: no data-model change, no repository-interface change, no watch-wire change (the watch app is NOT touched; its clock formats stay).

## Goal and acceptance (what the user sees)

Owner requests (2026-10-17) and answers to the lead's questions (O-1..O-4):

- A1. **Cardio weight is back.** The cardio interval screen shows the same `− 0.0 KG +` row the isometric hold shows, under the digits (live logger, session editor, routine editor's interval detail — which is empty today). Same step (2.5 kg / 5 lb), same limits (-200..999), locked once the interval is logged live, hold-to-repeat as everywhere. The value is stored where old cardio weights always were (`extra-weight`); weights saved before series 38 show again. The interval's logged caption under the set bar stays time only. (O-2)
- A2. **Every adjustment control reads number, unit label, hint**, all centred, label directly under the number (no gap), in every modality: reps, weight (set and hold and interval), round length, in the live logger, session editor and routine editor. The hint is a small dim `tap to type` line under the unit label; it is absent when the control is locked (a logged set). (O-1)
- A3. **Count-up timers are huge.** Interval and hold digits (and their `ELAPSED` / `COMPLETED` caption below) are roughly 2.8x today's size (40 sp → 112 sp), as wide as the screen allows; a long value (`1:15:35`) shrinks to fit instead of clipping. The group stays at the top, same order (O-4). The sports ring digits grow about 20% (40 sp → 48 sp) and stay inside the ring's usable width (accounting for the circle) for every shape including `2:15:30`.
- A4. **Hours.** Any timer that reaches an hour reads `h:mm:ss` (`1:15:35`), under an hour it stays `mm:ss`: count-up digits, ring digits, round length row, the rest timer chip, the session timer in the header (live and edit), the per-exercise `… total` line in the exercise list and overview. The − / + steps and the typed popup now go up to 10 hours (36000 s), not 60 minutes (O-3).
- A5. **Sports screen higher.** The set bar block loses its dead space under the bars; the ring (and the round-length row and sets control under it) move up by that amount plus the gaps above the ring (the 8 dp spacer, the scroll area's 16 dp top padding). Same tightening applies to every screen that uses the shared body (it is one Column).
- A6. Unchanged: tap-to-type popups, hold-to-repeat, logged-set locking, set bar captions, rests, stored value shapes, the watch.

## Verified facts (read from code 2026-10-17)

- `lib/widgets/session/inline_metric_editor.dart`: `_formatValue` for `duration` pads `mm:ss` with no hours (`inline_metric_editor.dart:98-102`); `dominant` tier style = `displayLarge` (40 sp, `omni_theme.dart:716`) w300; `showUnitInline` puts the unit to the RIGHT of the number bottom-aligned (`:188-201`); the column mode puts the label under with a 16 dp gap (`:203-211`). `ValueStepperRow` always uses `showUnitInline: true` (`value_stepper_row.dart:236`).
- `MetricStepCalc.parseAndClamp` `duration` clamps `0..3600` (`metric_crown_widget.dart:38`); `ValueStepperRow` steps through it (`value_stepper_row.dart:156`). `showDurationEntryDialog` already takes h/m/s (no ceiling of its own).
- Timer display sites that drop or mis-handle hours: session header timer `workout_session_global_timer.dart:26-29` (`remainder(60)` — the hour silently disappears) and edit mode init `workout_session_edit_mode.dart:15-17` (same), while `_reformatElapsed` (`workout_session_edit_mode.dart:53-65`) already prints `h:mm:ss`; rest elapsed `_formatRestElapsed` `workout_session_global_timer.dart:66-73` (`75:35`); list totals `workout_session_list_view.dart:95-97` and `session_overview_screen.dart:206-208` (`mm:ss total`). `OmniDateUtils.formatClock(ms)` (`date_utils.dart:179`) is the caption shape (`m:ss`, no padding) — NOT the digits shape; leave it.
- Timed (cardio) already stores `extra-weight` end to end: `EffortDefaults` timed has `extraWeight` (`effort_defaults.dart:23-30`), `_persistEntryValues` timed branch writes it (`workout_session_screen.dart:1148-1160`), `LoggedEntryRows.timedObservations(extraWeightKg:)` (`session_core_entry.dart:171-181`), applicability row `metric-extra-weight`/`timed` (`seed_data.dart:4430`). Only the UI was removed (`_buildWeightAdjustmentSection`, 38c; routine timed branch returns `SizedBox.shrink`, `routine_setup_screen.dart:1359-1362`). The hold weight row to copy: `_buildHoldWeightRow` `workout_session_detail_view.dart:107-125`; routine `drill` branch `routine_setup_screen.dart:1376-1394`.
- Body layout: `workout_session_list_view.dart:810` set bar, `:822-825` scroll area with `vertical: 16`, `:828-834` metric widget then `SizedBox(24)`, sets control. Round branch starts with `SizedBox(height: 8)` then `TimerRing(size: 232)` (`workout_session_detail_view.dart:405-409`). `SetSegmentBar` cell is `SizedBox(height: 48)` with the 6 dp bar at the top (`set_segment_bar.dart:80-90`) = 42 dp of dead space under the bar when there are no captions (more than 5 sets), 18 dp under captions.
- Measured by arithmetic: 75:35 = 4535 s, 135:30 = 8130 s, 2:15:30 = 8130 s, 10 h = 36000 s.

## Decision Ledger

- D-1 One digits formatter: `OmniDateUtils.formatTimerDigits(int seconds)` in `lib/core/utils/date_utils.dart`: `mm:ss` (two-digit minutes) below 3600 s, `h:mm:ss` from 3600 s (hour unpadded, matching `_reformatElapsed`), negative → `00:00`. Every site in "Verified facts" calls it; `_reformatElapsed` too (one rule). `formatClock` (captions) unchanged.
- D-2 `MetricStepCalc` `duration` ceiling `0..36000` (named constant `MetricStepCalc.maxDurationSeconds`). `ValueStepperRow` doc comment updated. Reps/weight limits untouched.
- D-3 `InlineMetricEditor` gets two things: (a) a column layout used by `ValueStepperRow` — number, label directly under it (gap 0..2 dp, both `Alignment.center`, `textAlign.center`), then the hint line; the `showUnitInline` mode stays for any other caller but `ValueStepperRow` no longer uses it; (b) `showTapHint` (default false): when true and not read-only a `tap to type` line (key `tap-hint`, `labelSmall`, `textMuted`-like dim, no uppercase) sits under the label. The session-editor interval/hold `ELAPSED` editor (`InlineMetricEditor` with the duration dialog) also passes `showTapHint: true`. Read-only editors (live count-up digits, ring digits) never show it.
- D-4 `ValueStepperRow` row height grows by the label + hint lines (≈ 30 dp); the number keeps `MetricEmphasisTier.dominant` and the `FittedBox`. A row at the longest value (`-200.0`, `10:00:00`) must not overflow at 390 dp wide (FittedBox scales it).
- D-5 Cardio weight row = `_buildHoldWeightRow` generalised: rename to `_buildWeightRow(effortId, entryIndex, currentValue, effortKind)`, the locked test uses the kind's own logged check (`_isSetLogged(effortId, entryIndex, 'timed' | 'drill')`). Live `timed` branch: digits then the weight row; session-editor `timed` branch: editor then the weight row. Reads `entryData['extra-weight']` converted with `UnitFormatter.convertWeight` exactly as the drill branch does; writes `_updateMetricValue(..., 'extra-weight', value)`. Routine editor `timed` branch: the `drill` branch's row (key `'${effort.id}-$setIndex-weight'`, `MetricIds.extraWeight`), the O-11 comment replaced.
- D-6 New emphasis tier `MetricEmphasisTier.hero` (font size constant `kCountUpDigitsFontSize = 112`, w300, `letterSpacing -4`, `textDominant`) used by the live count-up branches (`timed`, `drill`), wrapped in a `FittedBox(fit: BoxFit.scaleDown)` bounded by the screen width minus 40 dp; the `ELAPSED` / `COMPLETED` caption keeps `labelMedium`. `_kTimedValuePadding` re-derived (bottom inset small enough that the weight row stays on screen with the rest strip up).
- D-7 Ring digits: `dominant` stays for rows; the round branch passes a new `valueFontSize` override (48 sp = 40 × 1.2) so no new tier is needed; the `FittedBox` inside `TimerRing` is bounded to the ring's usable chord: `width <= side - 2*strokeWidth - 24`. `TimerRing.size` stays 232.
- D-8 Tightening (decided by the lead; no tap-size standard pins this widget, `test/ui_standards_*` read 2026-10-17): `SetSegmentBar` cell, bar stays at the top of the cell: height 34 with captions (6 + 4 + 20 + 4), 18 without (6 + 12; was 48 for both). The round branch's leading `SizedBox(8)` is removed; the scroll area's padding `vertical: 16` becomes `only(top: 8, bottom: 16)`; `SizedBox(24)` between the metric widget and the sets control stays.
- D-9 Technical: all measuring is at 390 x 844 with the real font on the iPhone 17 simulator (lead), widget tests assert styles and keys (the test font is wider and measured the wrong thing in unit 34).

## Readers of shared things this seed changes (grep results, 2026-10-17)

- `InlineMetricEditor` `duration` format / `unitLabel` layout: `test/count_up_screen_test.dart`, `test/timed_emphasis_redesign_test.dart`, `test/exercise_detail_emphasis_tier_test.dart`, `test/sports_emphasis_redesign_test.dart`, `test/resistance_emphasis_redesign_test.dart`, `test/crown_control_tap_to_edit_test.dart`, `test/tap_to_edit_unification_test.dart`, `test/round_countdown_screen_test.dart`, `test/reps_screen_test.dart`, `test/value_stepper_row_test.dart`, `test/logger_shell_screen_test.dart`, `test/screen_widget_test.dart`, `test/interaction_flow_test.dart`, `test/pr2_launch_quality_hotfix_test.dart`, `test/exercise_set_last_value_test.dart`, `test/exercise_details_capability_grouping_test.dart`, `test/watch_live_refresh_screen_test.dart`, `test/routine_detail_screen_test.dart` (the builder greps again for the exact strings it changes: `'00:00'`, `'ELAPSED'`, `'REMAINING'`, `find.text('KG')`).
- "interval has no weight row" assertions (fail by design after D-5, to be flipped, not deleted): `test/count_up_screen_test.dart`, `test/routine_detail_screen_test.dart`, `test/logger_shell_screen_test.dart`, and any `findsNothing` on a `-weight` key found by `grep -rn "findsNothing" test | grep -i weight`.
- `MetricStepCalc` duration clamp: `test/crown_control_tap_to_edit_test.dart`, `test/value_stepper_row_test.dart`, `test/tap_to_edit_unification_test.dart` (grep `3600`).
- Header / rest / total strings: `test/utils_test.dart`, `test/screen_widget_test.dart`, `test/rest_*_test.dart`, `test/session_*_test.dart` (grep `'00:00'`, `' total'`).

## Scenarios (exact fixtures; "fails today" is derived from the code above and PROVEN by the builder's red run)

- S-4701 (`OmniDateUtils.formatTimerDigits`, pure). 0 → `00:00`; 59 → `00:59`; 600 → `10:00`; 3599 → `59:59`; 3600 → `1:00:00`; 4535 → `1:15:35`; 8130 → `2:15:30`; 36000 → `10:00:00`; -5 → `00:00`. Fails today: function missing (prover: mutations only).
- S-4702 (header timer past an hour). A live session started 4535 s ago shows `1:15:35` in the header timer (`_elapsedFormatted`); started 59 s ago shows `00:59`. Edit mode of a finished 4535 s session shows `1:15:35`. Fails today: `15:35` (the hour is dropped by `remainder(60)`).
- S-4703 (rest chip past an hour). An open rest 4535 s old reads `1:15:35`; 75 s reads `01:15`. Fails today: `75:35`.
- S-4704 (ceiling). `MetricStepCalc.parseAndClamp('duration','3601')` → 3601; `'36001'` → 36000; `'-5'` → 0. A `ValueStepperRow` duration at 3600 with step 15: `+` → 3615 (callback called once with 3615); at 36000 `+` calls nothing; `−` at 3615 → 3600. Fails today: 3600 / null.
- S-4705 (round length row text). A duration row with 8130 reads `2:15:30`, with 135 reads `02:15`. Fails today: `135:30` / `02:15`.
- S-4706 (list totals). Exercise-list `total` line for 4535 s of intervals reads `1:15:35 total`; 125 s reads `02:05 total`. Fails today: `75:35 total`.
- S-4707 (control anatomy). In a `ValueStepperRow` (reps, weight, duration; key `value-stepper-*`): the unit label's horizontal centre equals the number's, its top is within 4 dp of the number's bottom (test: `getRect` of the two `Text`s; with the test font the check is relative, not absolute), the hint `find.byKey(Key('tap-hint'))` with text `tap to type` is below the label and also centred; when `isReadOnly` the hint is absent. In the session editor the interval `ELAPSED` editor shows the hint. Fails today: the unit is to the right of the number (inline), no hint.
- S-4708 (cardio weight, live). Live cardio interval screen: a weight row exists (`ValueKey('<effortId>-0-weight')`, minus/plus `value-stepper-*-weight`), reads `0.0 KG`; tap `+` → `2.5`, stored `extra-weight` 2.5 (kg user); pounds user: `+` → `5.0` LBS and stored 2.2680… kg (convert like the drill row; assert the displayed value only plus the stored kg to 2 decimals); finishing and logging the interval then locks the row (buttons dead, no `tap-hint`); the interval's set-bar caption stays `m:ss` only. A hold screen still shows its row (no regression). Fails today: no weight row on the interval.
- S-4709 (cardio weight, editor). Session editor on a cardio interval shows the weight row unlocked even for a finished interval; routine editor `timed` effort detail shows the row; `+` writes `MetricIds.extraWeight` 2.5 kg for the set; an old routine with a stored extra-weight target of 10 kg shows `10.0`. Fails today: empty.
- S-4710 (hero digits). The live interval digits `Text` style `fontSize == kCountUpDigitsFontSize` (112) and sit inside a `FittedBox` (`scaleDown`); same for the hold; the `ELAPSED` caption below is unchanged; the ring digits `fontSize == 48`. Fails today: 40.
- S-4711 (tightening). With the shared body: the set bar block height is 34 with captions (≤ 5 sets) and 18 without (>5 sets); the round branch has no leading 8 dp spacer; the ring's top is `bar bottom + 8 (scroll padding)` — assert the ring's `getTopLeft.dy - setBar bottom` ≤ 12 dp. Fails today: ≥ 66 dp with captions.
- S-4712 (every adjustment control inventory). A list test walks `ValueStepperRow` usages in live set, hold, interval, round, session editor and routine editor builds and asserts each has the label under the number (S-4707 shape). Fails today: all inline.

## Phases

Serial: P1 → P2 → P3 → P4 (P1, P2, P4 share `inline_metric_editor.dart`; P3 and P4 share `workout_session_detail_view.dart`). Never run the full suite inside a builder run (the lead does). Each builder writes its report skeleton FIRST.

- P1 (crew-builder-app) — time format + ceiling. Items: (1) `OmniDateUtils.formatTimerDigits` + S-4701; (2) every display site in "Verified facts" calls it (`inline_metric_editor.dart` `duration` case, `workout_session_global_timer.dart` header + `_formatRestElapsed`, `workout_session_edit_mode.dart` init and `_reformatElapsed`, `workout_session_list_view.dart:95-97`, `session_overview_screen.dart:206-208`); (3) `MetricStepCalc.maxDurationSeconds` 36000 + `value_stepper_row.dart` doc; (4) S-4702..S-4706 (plain `test()` where a state-layer test can do it; widget tests Mock-first); (5) migrate the tests that read the old strings. Scope: `lib/core/utils/date_utils.dart`, `lib/widgets/session/inline_metric_editor.dart`, `lib/widgets/session/metric_crown_widget.dart`, `lib/widgets/session/value_stepper_row.dart` (doc only), `lib/features/session/workout_session_global_timer.dart`, `lib/features/session/workout_session_edit_mode.dart`, `lib/features/session/workout_session_list_view.dart`, `lib/features/session/session_overview_screen.dart`, `test/**`, `.work/crew/2026-10-17-39/**`.
- P2 (crew-builder-app) — control anatomy (D-3, D-4, S-4707, S-4712). Scope: `lib/widgets/session/inline_metric_editor.dart`, `lib/widgets/session/value_stepper_row.dart`, `lib/features/session/workout_session_detail_view.dart` (only the session-editor `ELAPSED` editors get `showTapHint: true`), `test/**`, `.work/crew/2026-10-17-39/**`.
- P3 (crew-builder-app) — cardio weight (D-5, S-4708, S-4709): live, editor, routine editor; flip the "no weight on interval" tests. Scope: `lib/features/session/workout_session_detail_view.dart`, `lib/features/routine/routine_setup_screen.dart`, `test/**`, `.work/crew/2026-10-17-39/**`.
- P4 (crew-builder-app) — hero digits, ring digits, tightening (D-6, D-7, D-8, S-4710, S-4711). Exact replacement code for the count-up branches goes into its brief (screen-branch rewrite rule). Scope: `lib/widgets/session/inline_metric_editor.dart`, `lib/widgets/session/timer_ring.dart`, `lib/widgets/session/set_segment_bar.dart`, `lib/features/session/workout_session_detail_view.dart`, `lib/features/session/workout_session_list_view.dart`, `test/**`, `.work/crew/2026-10-17-39/**`.
- P5 (crew-docs-keeper) then (crew-reviewer): docs `docs/modality_based_exercise_ui.md`, `docs/widget_catalog/*` (the session widgets), `docs/theme_and_settings.md` only if it states the ceiling, `docs/constants_reference.md` (new constants), `docs/rest_tracking.md` (the rest chip format), series index row.

## Guards to prove (the prover's list; the lead applies every mutation)

formatTimerDigits hour branch (mutate `< 3600` to `<= 3600`; drop the hour pad rule); header timer no longer calls it (revert to `remainder(60)`); rest chip; `maxDurationSeconds` (revert to 3600); label-under layout (revert to `showUnitInline: true`); hint hidden when read-only; cardio row locked when logged (use `'drill'` kind for the check); cardio row reads `extra-weight` not `weight`; hero font constant; ring font 48; set bar block height.

## Owner checks (owner)

(owner) Look at the cardio interval, the isometric hold, a sports period and a reps set on the phone; try a hold of more than an hour (the session editor lets you type it) and a 90-minute round length; the watch is not changed, so its clock still shows `75:35`.

## Assumption Log

- A-1 Hint wording `tap to type` (O-1 default, owner may reword).
- A-2 The tap strip of each set-bar segment shrinks to 18 dp high (no captions) / 34 dp (captions), below the usual 44 dp target; no written standard pins it; owner to confirm by hand.
- A-3 `112 sp` / `48 sp` are first guesses; the lead tunes them on the simulator (rule: device, not tests).

## Progress

| Phase | Status |
|---|---|
| P1 hours + ceiling | done (evidence file) |
| P2 label + hint | done (evidence file) |
| P3 cardio weight | done (evidence file) |
| P4 hero / ring / tightening | done (evidence file) |
| Fix 1 dialog ceiling | done (evidence file) |
| P5 docs | done (this run) |
| Review | not run |
