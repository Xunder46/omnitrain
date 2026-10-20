# Feature: 44 — Logger feedback round (arrows, rest chip, countdown ring, tap-to-type hint, reps layout, time format, title; the set-2 weight bug)

> Status: Iteration 1 active (planned 2026-10-19). Owner questions Q1–Q3 are open with recommended defaults; the plan is written on those defaults (D-12..D-14, marked DERIVED — vetoable).
> Next handoff: @developer (Phase 1). Phase 4 (@developer, diagnosis only) touches no `lib/` file and may run first or in parallel.
> Binding conventions: docs/global_conventions.md; docs/documentation_standard.md; docs/design_system.md ("Shared pieces and rules per job", "How these rules are enforced"); .github/copilot/pr-scope-budget.md
> Base: `claude_develop` @ `80afbcdd` plus OTHER sessions' uncommitted work (see "Working tree rule"). Scenario ids `S-51xx` (grep clean in `lib/`, `test/`, `docs/` on 2026-10-19).

## Working tree rule (binding on every agent)

The checkout holds other sessions' staged and unstaged work. **Never edit, format, stage, unstage, stash, revert or check out** any of these (state on 2026-10-19):
`.claude/commands/crew.md`, `.claude/crew.md`, everything under `docs/plans/2026-10-19-42a-*`, `docs/plans/2026-10-19-42b-*`, `docs/plans/2026-10-19-43-*`, `docs/plans/2026-10-19-43a-*`, `docs/session_summary.md`, `docs/state_management/watch_surface.md`, `docs/state_management/workout_state.md`, `docs/watch_session_capture.md`, `docs/watch_session_sync.md`, `lib/core/services/watch_session_importer.dart`, `lib/features/session/session_summary_screen.dart`, `lib/state/watch/live_session_mirror_state.dart`, `lib/state/watch/watch_session_auto_push.dart`, `lib/state/watch/watch_session_inbox.dart`, `lib/state/watch/watch_sync_wiring.dart`, `lib/state/workout/session_core_lifecycle.dart`, `lib/state/workout/workout_state.dart`, `test/rating_first_answer_*_test.dart`, `watch/sync_protocol/PROTOCOL.md`, `watch/watchos/**`.
- Run `git status --short` at the start and end of every phase; paste both into the evidence file. A file your phase changed outside its Predicted Files is a finding.
- Plan 43a (another session, not built yet) predicts edits to `lib/features/session/workout_session_screen.dart` (`_resyncExercisesFromState` only) and `lib/features/session/workout_session_timer_mixin.dart`. Phases 1–3 here touch neither. Phase 5 may touch `workout_session_screen.dart` only inside the one method its root cause names.
- If a needed edit falls in a listed file: stop, write it under `## Feedback`, report.
- Git belongs to the governor: no commit, push, branch, switch, reset.
- Part files (`workout_session_detail_view.dart`, `workout_session_list_view.dart`) cannot add imports; their library's imports live in `workout_session_screen.dart`. Every type this plan's screen code needs must come from a file that library already imports (`timer_ring.dart`, `set_segment_bar.dart`, `value_stepper_row.dart`, `inline_metric_editor.dart`, `settings_state.dart`).

## Overview

Owner QA of the exercise logger (session detail view) on 2026-10-19. Eight presentation changes on one track (phone app) plus one bug that is reproduced before anything is changed. No data-model, schema, repository-interface, watch or wire change. The one new persisted thing is four preference booleans through the existing `WorkoutRepository.get/setPreferenceBool` (no schema change: preferences are a generic key/value store in both repositories).

Owner decisions (2026-10-19, final, quoted from the request): O-1 forward arrow dims and disables at the last set of the last exercise; O-2 rest chip stays the pause/resume button: pause icon while running, play icon while paused, tonal fill, icon and digits orange (primary); O-3 countdown ring dim orange before Start (the focused-unlogged segment colour), bright on Start, keeps its fraction when paused, shows what is left when logged early, grey track only when fully drained; O-4 the ROUND LENGTH card stays; O-5 the `tap to type` hint goes per control once that control is tapped; O-6 the reps screen's controls sit slightly below vertical centre; O-7 one time format, the big timer's `mm:ss`; O-8 two lines for the exercise title; O-9 timers unchanged otherwise; O-10 no units on the `10×15` caption; O-11 reproduce the set-2-at-0.0 bug with a failing test before any change.

## Resolved Decisions (Ledger)

- **D-1 Forward arrow end rule (O-1).** In `_buildSetControls` (`lib/features/session/workout_session_detail_view.dart`) the forward arrow is disabled exactly when `_currentExerciseIndex == _exercises.length - 1` AND `_currentSet >= entries.length` of that exercise, in the live logger AND the session editor (both handlers are no-ops there today: `_nextSet` and `_nextSetInEditMode`). Disabled = the same `_buildNavArrow(isEnabled: false, onPressed: null)` branch the back arrow uses at the first set (identical fill and icon colour, no ink, tooltip `Next` kept). It re-enables on the next rebuild once the condition stops holding (a set or an exercise added by any path, including the watch). Kind-agnostic (set, interval, round, hold). The back arrow and the `+` (`SetCountStepper`) are unchanged. Precedent: the routine editor already disables its forward arrow at its last set (`routine_setup_screen.dart` `_buildSetControls`, `onPressed: _currentSet < totalEntries ? _nextSet : null`).
- **D-2 Rest chip (O-2).** One builder, `_buildRestOverlayChip` (`lib/features/session/workout_session_list_view.dart`), so the change shows on all three surfaces that host it (detail view, standard list view, rolling list view). Running: icon `Icons.pause`, fill `colorScheme.primaryContainer` (the per-theme tonal role defined in `buildTheme`, `lib/app.dart`), icon and digits `colorScheme.primary`. Paused: icon `Icons.play_arrow`, fill unchanged from today (the tile surface at today's opacity), icon and digits `colorScheme.primary` (DERIVED from O-2 "icon+digits stay orange": applied to both states; the fill and the icon carry the state). Screen-reader label `Pause rest` while running, `Resume rest` while paused. Tap behaviour, key `rest-overlay-chip`, padding, radius, min height and the identical-rect-across-states rule are unchanged. Contrast floor 3:1 (large text: `titleLarge` w600) for primary on each fill on all six `AppTheme`s; planner's arithmetic with the theme constants: running min 3.81 (crimsonDojo), paused min 4.61 (voidPulse).
- **D-3 One definition of the session progress colours.** "Dim primary" = the focused-unlogged segment fill of `SetSegmentBar` (today `scheme.primary.withAlpha(115)` inline in `_segment`); "track grey" = the unlogged segment fill (today `scheme.onSurface.withAlpha(51)`), which is also `TimerRing`'s track. Both move to one shared definition (suggested: a new `lib/widgets/session/session_progress_colors.dart`, imported by `set_segment_bar.dart` and `timer_ring.dart` only) and both widgets read it. Values do not change: `SetSegmentBar` stays pixel-identical (`test/set_shell_widgets_test.dart` pins both fills and must stay green untouched).
- **D-4 Countdown ring looks (O-3).** `TimerRing` gains a look with three values; its default is today's look so existing callers and `test/timer_ring_test.dart` keep their meaning:
  - *ready* — painted when the focused round has no instance or is `RoundState.notStarted` and is not running: a full circle (progress 1.0) in dim primary (D-3); the grey track is not painted (fully transparent), so the on-screen colour equals the segment's.
  - *counting* (default) — running, or paused mid-round: primary arc at `remaining / effectiveTarget` over the grey track (today's rule; sweep rules of plan 38d D-1 unchanged).
  - *logged early* = counting look, frozen: `RoundState.finished` with `completed == false` and `left = planned − round.actualDurationSecs > 0`, where `planned = round.plannedDurationSecs`, falling back to the branch's `effectiveTarget` when `planned <= 0`; progress = `left / planned`. Example: planned 180, logged at 60 → 120/180 = 0.6667. (DERIVED from O-3 "shows whatever is left": bright, like paused.)
  - *drained* — `_isEffortExpired(...)` is true, OR the round is finished with `completed == true`, OR logged early with `left <= 0`: grey track only, progress 0.0, no arc drawn (the painter draws nothing for the arc at 0).
  Start switches ready → counting at once (colour change, progress stays 1.0, then sweeps). The digits and captions (`REMAINING` / `COMPLETED`, the expired red caption) are unchanged. Edit mode shows no ring (unchanged). Count-up timers (interval, hold) have no ring (O-9).
- **D-5 One time format on the logger (O-7).** `_loggedValueText` (`workout_session_detail_view.dart`) formats timed, drill and round captions with `OmniDateUtils.formatTimerDigits(secs)` instead of `formatClock(secs * 1000)`: `00:42`, `01:35`, `1:02:05`. Every other logger readout already uses `formatTimerDigits` (header timer, rest chip, count-up digits, ring digits, round-length row). `formatClock` itself is unchanged: Stats (`native_value_format.dart`) and the watch (`lib/watch/logging/*`) keep `m:ss`. Set captions stay `reps×weight` without units (O-10).
- **D-6 Tap-to-type hint learned per control, remembered across sessions (O-5).** Call: per-control and remembered across sessions, because it is cheap — one boolean preference per control through `SettingsState` and the existing `WorkoutRepository` preference API, no schema change. Controls and keys: `reps` (`hint_seen_tap_to_type_reps`), `weight` — the set weight row AND the interval/hold load row, one control kind (`hint_seen_tap_to_type_weight`), `round_length` — live and session-editor ROUND LENGTH rows (`hint_seen_tap_to_type_round_length`), `elapsed` — the session editor's interval/hold `ELAPSED` editor (`hint_seen_tap_to_type_elapsed`). Default false (hint shown). Identity is the control kind, not the exercise or the set: learning `weight` on one exercise hides the weight hint on every exercise, set, hold and interval. Learned = the control's NUMBER was tapped (its type-in popup or duration dialog opened), whether or not the popup is confirmed; the hint disappears on that tap and is persisted at once. Read-only controls show no hint (unchanged). `SettingsState` loads the four flags in `initialize()` and exposes read + mark methods (names are a mechanic); `lib/state/workout/*` is NOT used (its `workout_state.dart` belongs to another session).
- **D-7 Reps screen anchoring (O-6).** For `effortKind == 'set'` (live and session editor) the visible group — from the top of the REPS row's box to the bottom of the `SetCountStepper` box — is placed inside the scroll area (the `Expanded` between the set bar and the `RestTimerStrip`) so that, with `free = areaHeight − groupHeight`: top gap = 0.6 × free and bottom gap = 0.4 × free (±2 dp). The group keeps its internal spacing. When `free < 0` the group is top-anchored as today and the area scrolls; nothing overflows. The rule is recomputed when the rest strip opens or closes (the area shrinks). Interval, hold and round screens keep today's top anchoring.
- **D-8 Exercise title on two lines (O-8).** The detail-view header title (exercise name) is `maxLines: 2`, `TextOverflow.ellipsis` after the second line. The list-view title (session name / `Edit Session`) and the subtitle line stay one line.
- **D-9 Unchanged (O-4, O-9, O-10).** The ROUND LENGTH card with its steppers; ring only for a preset time, bare digits for count-ups; the `10×15` caption without units; the `formatClock` function; watch surfaces.
- **D-10 Bug protocol (O-11).** Phase 4 reproduces before any change: one red test per confirmed path, in a new test file, no `lib/` edit. Candidate paths and fixtures are listed in S-5126. A hypothesis is CONFIRMED when its test is red for the stated reason (assert message names the observed `0.0`); RULED OUT when green. If none is red, Phase 4 reports "not reproduced", keeps the tests as passing guards, and Phase 5 does not run. A repro test whose fix is not in this plan lands with `skip:` naming the Feedback entry, never red.
- **D-11 Fix gate (Phase 5).** Phase 5 runs only for a confirmed path whose fix is (a) outside the working-tree-rule files, (b) at most ~30 production lines, and (c) either a mechanical defect (the code fails its own documented carry-forward contract: `docs/modality_based_exercise_ui.md`, "pre-filled from the previous set as the carry-forward does") or covered by D-14. Otherwise: stop, write the finding and a recommended default under `## Feedback`.
- **D-12 (DERIVED — vetoable, Q2) Only the number tap teaches.** `−`/`+` taps and holds never mark a hint learned (the hint teaches typing).
- **D-13 (DERIVED — vetoable, Q3) Routine editor unchanged.** `routine_setup_screen.dart` keeps showing the hint on every row; `ValueStepperRow` keeps showing it by default.
- **D-14 (DERIVED — vetoable, Q1) Carry rule if the cause is "set 2 existed before set 1's weight was entered".** Applies only when Phase 4 confirms H-1 or H-6: when a `set` entry is logged on the phone (`_logSet`, live, not skipped), the next set of the same exercise, if not logged and its stored `weight` is exactly 0.0, takes the logged set's weight (canonical kg). Reps never change; a non-zero weight is never overwritten; holds, intervals, rounds and watch-logged sets are untouched.

## Feature Invariants

- No change to `lib/data/models/`, `scripts/sqlite_schema.sql`, `scripts/sqlite_seed.sql`, `WorkoutRepository`'s interface, `lib/watch/`, `watch/`.
- Parity: the four hint keys read back identically from `MockWorkoutRepository` and `HiveWorkoutRepository`, including after a restart (`test/helpers/repository_harness.dart`).
- Layer boundary: features never call the repository for hints; the screen reads and marks them through `SettingsState`.
- Phases 1–3 change no stored entry value (presentation plus four preferences).
- `SetSegmentBar` fills are pixel-identical before and after (D-3).
- The rest chip's rect is identical across running and paused (existing guard in `test/pr4_session_controls_test.dart`).

## Requirements → Acceptance Criteria

- AC-1 (O-1) Forward arrow at the end is dim and dead, everywhere it is at the end → S-5109..S-5113.
- AC-2 (O-2) The rest chip shows its function and does not compete with the primary button → S-5114, S-5115.
- AC-3 (O-3) The ring has four honest looks → S-5101..S-5107.
- AC-4 (O-7) Logged time captions read like the big timers → S-5108.
- AC-5 (O-6) Reps controls sit slightly below centre and never overflow → S-5116..S-5118.
- AC-6 (O-8) Long exercise names get two lines → S-5119.
- AC-7 (O-5) Each hint goes once its own control is tapped, and stays gone → S-5120..S-5125.
- AC-8 (O-11) The set-2 bug is reproduced or reported as not reproduced → S-5126 (+ S-5127 if fixed).

## Existing-Functionality Impact

| Touched surface | Readers (grep that found them) | Effect | Guarded by |
|---|---|---|---|
| Forward arrow in `_buildSetControls` | `grep -rn "_nextSet\b\|_nextSetInEditMode" lib` → detail view only; tests tapping it: `grep -rln "Icons.arrow_forward" test` → 12 files (count_up, reps, session_toolbar_rework, interaction_flow, session_message, logger_shell, rest_timer_docked_strip, pr2_launch_quality_hotfix, resistance_emphasis_redesign, unified_rest_overlay, watch_live_refresh_screen, round_auto_expiry) | a test that taps forward at the very end now gets a dead button (it was a no-op before, so no flow changes) | S-5109..S-5113; P2 re-runs all 12 files |
| Rest chip icon/colours | `grep -rln "self_improvement" test` → `test/pr4_session_controls_test.dart`, `test/widget_test.dart`; `grep -rln "rest-overlay-chip" test` → 12 files (count_up_screen, delete_focused_set, logger_shell_screen, pr4_session_controls, reps_screen, rest_timer_docked_strip, round_auto_expiry, round_countdown_screen, screen_widget, timer_digits_hours, unified_rest_overlay, watch_live_refresh_screen); icon-absence asserts `Icons.pause`/`play_arrow` in `test/session_toolbar_rework_test.dart` (no rest open there: unaffected, re-run) | icon assertions flip to `pause`/`play_arrow` | S-5114, S-5115 |
| `SetSegmentBar` fills | `test/set_shell_widgets_test.dart` (pins `primary.withAlpha(115)`, `onSurface.withAlpha(51)`) | none (D-3 moves the definition only) | S-5102 + that test untouched |
| `TimerRing` | only caller: detail view round branch (`grep -rn "TimerRing(" lib`); tests: `test/timer_ring_test.dart`, `test/round_countdown_screen_test.dart`, `test/sports_emphasis_redesign_test.dart`, `test/round_auto_expiry_test.dart` | S-4411 (plan 38d) asserts `0.0` for a round logged early → becomes 0.6667 (superseded by S-5105); S-4401 adds a colour assertion | S-5101..S-5107 |
| Caption format | `grep -rnE "setCaptionText\(|captionTexts\(" test \| grep -E "[0-9]:[0-9]{2}"` → `count_up_screen_test.dart:410,607` (`0:00`), `logger_shell_screen_test.dart:264,265,285` (`0:42`,`0:38`,`1:35`) | strings flip to `00:00`, `00:42`, `00:38`, `01:35` | S-5108 |
| `formatClock` | `grep -rn "formatClock(" lib` → stats `native_value_format.dart`, watch `watch_logging_state.dart`, `watch_logging_screen.dart`, `watch_rest_screen.dart`, detail view | only the detail view stops calling it | S-5108; `test/utils_test.dart` untouched |
| Reps screen body | `test/reps_screen_test.dart` (rects of rows, `set-count-add`, chip top at :597), `test/rest_timer_docked_strip_test.dart` (no-overlap sweep, viewport overflow sweep), `test/logger_shell_screen_test.dart` (S-4711 tightening is round-only) | the group moves down; no-overlap must still hold | S-5116..S-5118; P2 re-runs those files |
| Header title | `_buildHeader` serves list and detail views (`workout_session_list_view.dart`) | detail only goes to 2 lines | S-5119 |
| `ValueStepperRow` / `InlineMetricEditor` hint | users: detail view, `routine_setup_screen.dart` (`grep -rn "ValueStepperRow(" lib`); hint tests: `grep -rln "tap-hint" test` → value_stepper_row, reps_screen, round_countdown_screen, count_up_screen, routine_detail_screen | fresh repos keep all hints shown, so existing presence tests stay green; routine editor unchanged (D-13) | S-5120..S-5125 |
| `SettingsState.initialize` | constructed in `lib/main.dart` and ~every screen test (`SettingsState(repo, fakePreferencesService())`) | four extra preference reads | S-5122; `test/settings_state_test.dart` |
| Invariant: `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` | — | must stay empty | every phase's Done Criteria |

## UI Standards Impact

Uses the shared pieces `SetSegmentBar`, `TimerRing`, `ValueStepperRow`, `SetCountStepper`, `OmniSurface` (inside the rows). No new hand-built piece, no new raw colour (all colours from `colorScheme` or the D-3 definition, which derives from `colorScheme`), no new allowlist entry, no ratchet change. None of the touched files carries an allowlist deviation (`grep` of `test/helpers/ui_standards_allowlist.dart` for each touched path: no hits). `docs/design_system.md` gains two rules (D-3 shared colours; D-2 tonal chip) without values.

## Scenarios

Shared harness: the pattern in `test/round_countdown_screen_test.dart` (`_buildDeps(modality:)`, `MockWorkoutRepository` with `hint_seen_exercise_info`/`hint_seen_exercise_notes` set true, `SettingsState(repo, fakePreferencesService())`, `FakeTimerAlertService`, surface 390×844, open the detail view by tapping the exercise name). Themes via `buildTheme(...)` as in `test/sports_emphasis_redesign_test.dart` `_themeWrappedApp`. Exercises: `exercise-barbell-squat` and `exercise-bench-press` (set), `exercise-easy-run` (timed), `exercise-plank-hold` (drill), the first catalog exercise whose capabilities contain `rounds` (round). Widget tests run Mock-first; nothing awaits a real delay except S-5106's expiry, which copies S-4415's `runAsync` wait.

### S-5101: ready ring
- Fixture: session modality `cardio_endurance`; one round effort, 1 round, planned 180 s, `RoundState.notStarted`; theme default. Repeat with modality `sports` (noun `Period`).
- Trigger: open the detail view.
- Expected: painter progress 1.0; `arcColor` == the D-3 dim primary == the fill of `set-segment-0` read from the same screen; `trackColor` alpha 0; digits `03:00`, caption `REMAINING`.
- Edge case of: none

### S-5102: dim primary and track grey are one definition, on every theme
- Fixture: each of the 6 `AppTheme` values; a `TimerRing` in the ready look and a `SetSegmentBar(count: 3, focusedIndex: 1, isLogged: i == 0)` in one themed `MaterialApp`.
- Expected: ring arc colour == segment 1 fill; ring track colour in the counting look == segment 2 fill; segment 0 fill == `primary`; values equal `primary.withAlpha(115)` / `onSurface.withAlpha(51)` (pixel-identical guard).
- Edge case of: S-5101

### S-5103: Start makes the ring bright
- Fixture: S-5101's.
- Trigger: tap `Start`, pump one frame.
- Expected: `arcColor == primary`, `trackColor == onSurface.withAlpha(51)`, progress 1.0, then falls on the next tick.
- Edge case of: S-5101

### S-5104: paused mid-round keeps its fraction
- Fixture: 1 round of 180 s started, paused, backdated 45 s (S-4410 seed).
- Expected: progress exactly 0.75 (135/180), arc primary, track grey, unchanged after two pumps; digits `02:15`.
- Edge case of: S-5103

### S-5105: logged early shows what is left (supersedes the ring clause of S-4411)
- Fixture: 1 round of 180 s started, paused, backdated 60 s, `endRoundEarly` (S-4411 seed): `finished`, `completed == false`, `actualDurationSecs == 60`.
- Expected: progress 120/180 = 0.6667 (±0.001), arc primary, track grey; digits `01:00`, caption `COMPLETED`; length row read-only, `03:00`.
- Edge case of: S-5104

### S-5106: drained means grey only
- Fixture A: S-4415's 15 s round run out on the wall clock (expired, `completed == true`). Fixture B (adversarial): 1 round of 180 s, paused, backdated 180 s, `endRoundEarly` → `actualDurationSecs == 180`, `completed == false`, `left == 0`.
- Expected (both): progress 0.0, `trackColor` grey; a recording canvas (as in `timer_ring_test.dart` "the canvas gets a full track circle…") receives no arc call. A: caption `COMPLETED`; expiry alert fired exactly once (unchanged).
- Edge case of: S-5105

### S-5107: each round shows its own look
- Fixture: 3 rounds of 180 s: round 1 logged early at 60 s, round 2 finished `completed == true` (`completeRound`), round 3 not started.
- Trigger: tap `set-segment-0`, `-1`, `-2` in turn.
- Expected: 0.6667 primary arc / 0.0 grey only / 1.0 dim primary, no grey track.
- Edge case of: S-5101

### S-5108: logged time captions read like the big timers
- Fixture: interval effort (easy run) with two intervals finished at 42 s and 38 s (copy `logger_shell_screen_test.dart`'s seed at :264); a hold finished at 0 s; a round logged early at 60 s; an interval finished at 3725 s; a squat set logged 10 reps at 15 kg.
- Expected captions: `00:42`, `00:38`; `00:00`; `01:00`; `1:02:05` (3725 = 1 h 2 min 5 s); the set caption is exactly what it read before (`10×` + `UnitFormatter.formatWeightValue(15.0)`).
- Edge case of: none

### S-5109: forward arrow at the end of the session
- Fixture: free session (modality null); exercise A squat with 2 sets, exercise B bench press with 1 set; nothing logged.
- Flow: A set 1 → forward enabled; A set 2 → enabled (goes to B); B set 1 → disabled.
- Expected at B set 1: the `Next` arrow's `InkWell.onTap == null`, its `Material.color` and icon colour equal the `Previous Set` arrow's colours at A set 1; tapping it leaves the screen on B set 1 (`Exercise 2 / 2`, `Set 1 of 1`).
- Edge case of: none

### S-5110: single exercise, single set
- Fixture: free session, one squat with one set, unlogged; then the same after `Log Set`.
- Expected: both arrows disabled before and after logging (`LOGGED` label shown after).
- Edge case of: S-5109

### S-5111: adding a set wakes the arrow
- Fixture: S-5110 before logging.
- Trigger: tap `set-count-add`.
- Expected: still on set 1 of 2, forward enabled; tap forward → set 2 of 2, forward disabled again.
- Edge case of: S-5110

### S-5112: session editor
- Fixture: one squat with 2 sets, both with values and both marked logged by a rest record, screen opened with `editMode: true` (the seeding `test/reps_screen_test.dart` S-4252 uses: `updateEntryValue` + `recordRestStart`).
- Expected: set 1 forward enabled; set 2 forward disabled; back enabled on set 2.
- Edge case of: S-5109

### S-5113: timer kinds
- Fixture: timed session, one easy-run effort with 1 interval not started; separately one round effort with 1 round not started.
- Expected: forward disabled on both; `Start` still works.
- Edge case of: S-5109

### S-5114: rest chip shows its function
- Fixture: free session, squat with 2 sets; log set 1 (rest opens, chip visible on the detail view).
- Expected running: `Icons.pause` inside `rest-overlay-chip`, no `Icons.self_improvement` anywhere; chip fill == `colorScheme.primaryContainer`; icon and digit text colour == `colorScheme.primary`; semantics label `Pause rest`. Tap the chip → paused: `Icons.play_arrow`, fill == today's paused fill, icon and digits `primary`, label `Resume rest`; chip rect identical to the running rect. Per theme (all 6, pure test): `OmniTheme.contrastRatio(primary, primaryContainer) >= 3.0` and `OmniTheme.contrastRatio(primary, colorsForTheme(t).surface) >= 3.0`.
- Edge case of: none

### S-5115: the same chip on the list views
- Fixture: S-5114 after logging; then back to the standard list view; separately a rolling session with one block holding one squat with a logged set.
- Expected: running chip carries `Icons.pause` and the `primaryContainer` fill on both list views.
- Edge case of: S-5114

### S-5116: reps controls slightly below centre
- Fixture: free session, squat with 3 sets, 390×844, no rest open; then the same after logging set 1 (rest strip open).
- Measure: `area` = rect of the scroll area; `group` = from `ValueKey('<effortId>-0-reps')` top to `set-count-add`'s enclosing `SetCountStepper` bottom; `free = area.height − group.height`.
- Expected (both states): `group.top − area.top == 0.6 × free ± 2` and `area.bottom − group.bottom == 0.4 × free ± 2`; `free > 0`; with the rest open the stepper's bottom stays above the chip's top (existing `reps_screen_test.dart` :597 guard).
- Edge case of: none

### S-5117: no overflow on a small phone
- Fixture: 320×568, rest open, exercise named by S-5119's long fixture, session editor and live.
- Expected: no overflow exception; the group is top-anchored when `free < 0`; scrolling makes `set-count-add` hittable.
- Edge case of: S-5116

### S-5118: timer screens keep their anchoring
- Fixture: one round (S-5101), one interval, one hold.
- Expected: ring top − set bar bottom ≤ 12 dp (S-4711 guard unchanged); count-up digits keep their position from before the phase (assert with the existing `test/count_up_hero_layout_test.dart` green, untouched).
- Edge case of: S-5116

### S-5119: two-line exercise title
- Fixture: a custom exercise created through the repository, name `Single-Arm Dumbbell Romanian Deadlift to Overhead Press Complex` (61 chars), `set` effort; a second exercise `exercise-barbell-squat` (`Barbell Back Squat`, fits one line); 390×844.
- Expected: the header title `Text` has `maxLines == 2` and `overflow == TextOverflow.ellipsis`; its rendered height is greater than one line of `titleLarge` for the long name and equal to one line for the short name; the list-view header title keeps `maxLines == 1`.
- Edge case of: none

### S-5120: a hint goes when its own control is tapped
- Fixture: fresh Mock repo (all four hint keys unset); free session, squat with 2 sets.
- Flow: both rows show `tap-hint` (2 found); tap the weight number → `Edit Weight` popup; cancel.
- Expected: weight row has no `tap-hint`, reps row still has it (1 found); navigate to set 2: same; `settingsState`'s weight flag true, reps false; repo `getPreferenceBool('hint_seen_tap_to_type_weight') == true`.
- Edge case of: none

### S-5121: steppers do not teach
- Fixture: S-5120's.
- Trigger: tap `value-stepper-plus-reps` 3 times and hold it 1 s.
- Expected: reps hint still shown; reps flag false.
- Edge case of: S-5120

### S-5122: remembered after a restart, identical on both stores
- Fixture: `RepositoryHarness` Mock and Hive (`test/helpers/repository_harness.dart`); mark `weight` and `round_length` learned through `SettingsState`.
- Trigger: `restart()`, new `SettingsState`, `initialize()`.
- Expected on both: weight true, round_length true, reps false, elapsed false; a new session screen over the restarted Mock repo shows no weight hint and a reps hint.
- Edge case of: S-5120

### S-5123: one weight control, one round-length control
- Fixture: weight learned (S-5120); session with a hold (plank), an interval (easy run) and a round effort, nothing logged.
- Expected: no hint on the hold's and the interval's weight rows; the ROUND LENGTH row shows a hint until its number is tapped (duration dialog, cancel), then not; the session editor's ROUND LENGTH row for the same session shows none.
- Edge case of: S-5120

### S-5124: the session editor's elapsed editor
- Fixture: one interval (easy run) finished at 95 s and one hold (plank) finished at 30 s, seeded the way `test/count_up_screen_test.dart`'s edit-mode tests seed a finished instance, screen opened with `editMode: true`, fresh repo.
- Expected: both `ELAPSED` editors show `tap-hint`; tap the interval's number (duration dialog), cancel → neither shows it (one control kind); elapsed flag true.
- Edge case of: S-5120

### S-5125: locked rows and the routine editor
- Fixture A: a logged squat set (live) with all flags false. Fixture B: all four flags true; routine editor (`RoutineSetupScreen`) on a squat effort with 1 set.
- Expected: A shows no hint on its read-only rows (unchanged). B shows `tap-hint` on the routine editor's reps and weight rows (D-13).
- Edge case of: S-5120

### S-5126: the set-2-at-0.0 repro matrix (Phase 4)
Every fixture: squat (`exercise-barbell-squat`, has `load`), kg user, Mock repo, live session unless stated. "Bug" = set 2's weight row reads `0.0` after set 1 was logged at 10 reps × 15.0 kg; the owner's expectation is `15.0`.
- H-1 Routine plan: a routine whose squat has 3 sets, reps target 10 on set indices 0..2, weight target 15 kg on set index 0 only (variant H-1b: one weight target with `setIndex: null`, which `session_core_io.dart` applies to set 0 only). Start the session from it; log set 1; read set 2.
- H-2 Watch path: a live session holding squat with 1 set; a wrist `set` entry 10×15 merged through the live-merge harness (`test/helpers/watch_capture_import_harness.dart` / `live_session_fixtures.dart`), then the phone taps `set-count-add`; read set 2. Read-only use of the importer: do not edit it.
- H-3 Session editor: a finished session with squat 1 set stored 10×0.0; `editMode: true`; step weight to 15.0 (buffered, not stored); tap `set-count-add`; read set 2.
- H-4 Type drop in `_buildPreviousValues` (`v is double`): last entry's `weight` read back as a non-`double`; first prove by reading `getExercisesWithEntries()` after a Hive round-trip whether that can happen at all; if it cannot, RULED OUT with that evidence.
- H-5 Delete then add (plan 41 numbering): squat 3 sets; set 1 logged 10×15; delete the focused set 2; tap `set-count-add`; read every unlogged set.
- H-6 Sets added before set 1's weight: add squat (1 set 10×0.0); tap `set-count-add` twice (sets 2, 3 copy 10×0.0); set set 1's weight to 15.0 with the stepper; `Log Set`; read set 2.
- Expected: a table in the evidence file, one row per hypothesis: red/green, the observed value, the root-cause line (file:line) for every red row.
- Edge case of: none

### S-5127: reserved — the fix's red→green, defined by Phase 4's report (Phase 5 only)

## Iteration 1

### Phase 1: ring looks, shared colours, caption format (@developer)
1. [ ] Move the two fills to one definition (D-3) and read it from `SetSegmentBar._segment` — new `lib/widgets/session/session_progress_colors.dart` · `lib/widgets/session/set_segment_bar.dart`
2. [ ] Add the ring look (ready / counting default / drained) to `TimerRing` and `TimerRingPainter` (no arc at progress 0; ready paints no track) — `lib/widgets/session/timer_ring.dart` · `TimerRing`, `TimerRingPainter`
3. [ ] Pick the look and the progress in the round branch per D-4 (logged-early math, drained rule) — `lib/features/session/workout_session_detail_view.dart` · `_buildMetricWidget` case `'round'`
4. [ ] Captions via `formatTimerDigits` (D-5) — same file · `_loggedValueText`
5. [ ] Tests S-5101..S-5108: extend `test/timer_ring_test.dart` and `test/round_countdown_screen_test.dart` (update S-4411's ring assertion to 0.6667 and cite S-5105 in its name; add colour assertions to S-4401/S-4410/S-4415); new `test/session_progress_colors_test.dart` (S-5102); flip the five caption strings in `test/count_up_screen_test.dart` and `test/logger_shell_screen_test.dart`; S-5108's round and hour cases in `test/round_countdown_screen_test.dart`/`test/logger_shell_screen_test.dart`
6. [ ] Show each new assertion red on the base code first (stash only your own `lib/` edits — never `git stash` the tree; copy the files aside instead), then green; paste the table in the evidence file
7. [ ] Docs: `docs/widget_catalog/session_widgets.md` (`TimerRing` looks, `SetSegmentBar` shared colours, test pointers; 37.9 KB of the 52 KB band), `docs/modality_based_exercise_ui.md` (ring looks and caption format, pointers to S-5101..S-5108; 42.5 KB), `docs/constants_reference.md` ("Timer Digit Formatting": captions now use `formatTimerDigits`; `formatClock` remains for Stats and the watch), `docs/design_system.md` (one rule under "Shared pieces and rules per job": the ring's ready look and the focused unlogged segment share one dim-primary definition, no values; 42.0 KB)

**Done Criteria** (run until green): `flutter analyze` (issue count ≤ the baseline you record at phase start); `flutter test test/timer_ring_test.dart test/round_countdown_screen_test.dart test/session_progress_colors_test.dart test/set_shell_widgets_test.dart test/count_up_screen_test.dart test/logger_shell_screen_test.dart test/round_auto_expiry_test.dart test/sports_emphasis_redesign_test.dart test/count_up_hero_layout_test.dart`; `flutter test test/ui_standards_contract_test.dart test/docs_indexing_contract_test.dart`; the invariant grep returns nothing; full suite `bash .claude/scripts/macos/with-timeout.sh 900 flutter test` (Copilot: through the gateway) with pasted counts.
**Predicted Files**: `lib/widgets/session/session_progress_colors.dart` (new), `lib/widgets/session/set_segment_bar.dart`, `lib/widgets/session/timer_ring.dart`, `lib/features/session/workout_session_detail_view.dart`, `test/timer_ring_test.dart`, `test/round_countdown_screen_test.dart`, `test/session_progress_colors_test.dart` (new), `test/count_up_screen_test.dart`, `test/logger_shell_screen_test.dart`, `docs/widget_catalog/session_widgets.md`, `docs/modality_based_exercise_ui.md`, `docs/constants_reference.md`, `docs/design_system.md`, this plan's evidence file.

### Phase 2: forward arrow, rest chip, reps anchoring, title (@developer)
1. [ ] Forward arrow end rule D-1 — `lib/features/session/workout_session_detail_view.dart` · `_buildSetControls`
2. [ ] Rest chip D-2 (icons, fills, foreground, semantics label) — `lib/features/session/workout_session_list_view.dart` · `_buildRestOverlayChip` (also fix its doc comment, which still describes the meditation icon)
3. [ ] Reps anchoring D-7 for `effortKind == 'set'` — same file · the detail body built after `_buildSetBar` (the `SingleChildScrollView` → `Column`), using a layout that knows the area height (mechanic free)
4. [ ] Title D-8 — same file · `_buildHeader` (detail branch only)
5. [ ] Tests S-5109..S-5119 in a new `test/logger_feedback_controls_test.dart`; update the icon assertions in `test/pr4_session_controls_test.dart` (:221, :239) and `test/widget_test.dart` (:629, :691) to `Icons.pause`; red-first table as in Phase 1
6. [ ] Re-run every file named in the Impact rows for the arrow, chip and body (list in Done Criteria) and paste counts
7. [ ] Docs: `docs/rest_tracking.md` ("Overlay Display": the chip's states and pointer to S-5114; 20.5 KB), `docs/modality_based_exercise_ui.md` (§5 drop "MM:SS"/positional prose that §3.2 forbids where you touch it; §6 arrow end rule, reps anchoring, two-line title with S-ids), `docs/design_system.md` (rule: the rest chip uses a tonal fill so it never competes with the primary filled action; no values)

**Done Criteria**: `flutter analyze` ≤ baseline; `flutter test test/logger_feedback_controls_test.dart test/pr4_session_controls_test.dart test/widget_test.dart test/reps_screen_test.dart test/rest_timer_docked_strip_test.dart test/unified_rest_overlay_test.dart test/timer_digits_hours_test.dart test/session_toolbar_rework_test.dart test/count_up_screen_test.dart test/interaction_flow_test.dart test/session_message_test.dart test/logger_shell_screen_test.dart test/pr2_launch_quality_hotfix_test.dart test/resistance_emphasis_redesign_test.dart test/watch_live_refresh_screen_test.dart test/round_auto_expiry_test.dart test/delete_focused_set_test.dart`; the two contract tests; invariant grep; full suite (900 s) with counts.
**Predicted Files**: `lib/features/session/workout_session_detail_view.dart`, `lib/features/session/workout_session_list_view.dart`, `test/logger_feedback_controls_test.dart` (new), `test/pr4_session_controls_test.dart`, `test/widget_test.dart`, `test/reps_screen_test.dart` (only if a rect assertion encodes the old top anchoring — log it), `docs/rest_tracking.md`, `docs/modality_based_exercise_ui.md`, `docs/design_system.md`, evidence file.

### Phase 3: tap-to-type hint learned per control (@developer)
1. [ ] Four flags in `SettingsState`: load in `initialize()`, read, mark (persist with `setPreferenceBool`, notify) — `lib/state/settings/settings_state.dart`
2. [ ] `ValueStepperRow`: a `showTapHint` switch (default true, D-13) and a notification when its number is tapped, fired for both the popup path and the `onEditorTap` path; `InlineMetricEditor` reports a number tap before it opens its popup — `lib/widgets/session/value_stepper_row.dart`, `lib/widgets/session/inline_metric_editor.dart`
3. [ ] Wire the four controls in the detail view (D-6, D-12): reps and weight rows (set), `_buildWeightRow` (hold, interval), both ROUND LENGTH rows, both edit-mode `ELAPSED` editors — `lib/features/session/workout_session_detail_view.dart`
4. [ ] Tests: S-5120, S-5121, S-5123..S-5125 in new `test/tap_hint_learned_test.dart` (widget, Mock-first); S-5122 as plain `test()` over both `RepositoryHarness` implementations in the same file; extend `test/settings_state_test.dart` (defaults false, mark persists); `test/value_stepper_row_test.dart` (switch off hides the hint; the tap notification fires once per number tap, never on `−`/`+`); red-first table
5. [ ] Docs: `docs/widget_catalog/session_widgets.md` (`ValueStepperRow`/`InlineMetricEditor` parameters, pointer to S-5120), `docs/modality_based_exercise_ui.md` (§1 hint rule as invariant + pointer), `docs/state_management/app_state.md` (`SettingsState`: the four flags, keys named, no values) and `docs/theme_and_settings.md` only if it lists `SettingsState` preferences
6. [ ] Consolidation and residue sweep for the whole plan: `grep -n "self_improvement" lib` → none; `grep -n "formatClock" lib/features/session` → none; `grep -rn "withAlpha(115)" lib/widgets/session` → only the D-3 definition; paste results

**Done Criteria**: `flutter analyze` ≤ baseline; `flutter test test/tap_hint_learned_test.dart test/settings_state_test.dart test/value_stepper_row_test.dart test/reps_screen_test.dart test/round_countdown_screen_test.dart test/count_up_screen_test.dart test/routine_detail_screen_test.dart test/logger_feedback_controls_test.dart`; the two contract tests; invariant grep; full suite (900 s) with counts.
**Predicted Files**: `lib/state/settings/settings_state.dart`, `lib/widgets/session/value_stepper_row.dart`, `lib/widgets/session/inline_metric_editor.dart`, `lib/features/session/workout_session_detail_view.dart`, `test/tap_hint_learned_test.dart` (new), `test/settings_state_test.dart`, `test/value_stepper_row_test.dart`, `docs/widget_catalog/session_widgets.md`, `docs/modality_based_exercise_ui.md`, `docs/state_management/app_state.md`, `docs/theme_and_settings.md` (conditional), evidence file.

### Phase 4: reproduce the set-2-at-0.0 bug — diagnosis only (@developer)
1. [ ] Write one test per hypothesis H-1..H-6 of S-5126 in new `test/set_weight_carry_repro_test.dart` (state-level `test()` where the path has no screen step; widget test Mock-first otherwise)
2. [ ] Run it; fill the evidence table (red/green, observed value, root-cause file:line for each red)
3. [ ] For each red row: say whether it is a mechanical defect (code breaks its documented carry-forward contract) or a missing rule (D-14), and whether the fix lands in a working-tree-rule file
4. [ ] Leave the file green: red tests get `skip: 'S-5126 Hn repro — fix in Phase 5'` (or `'… — see Feedback'` when D-11 blocks Phase 5); green tests stay as guards
5. [ ] Write the outcome in Progress (one line) and, when Phase 5 is blocked, a `## Feedback` entry with the finding and a recommended default. Not reproduced at all → say so and stop

**Done Criteria**: `flutter test test/set_weight_carry_repro_test.dart` green with skips counted; `flutter analyze` ≤ baseline; `git status --short` shows no `lib/` change from this phase.
**Predicted Files**: `test/set_weight_carry_repro_test.dart` (new), evidence file, this plan (Progress, Assumption Log, Feedback only).

### Phase 5 (conditional on Phase 4 and D-11): fix the confirmed path (@developer; @dba if the root-cause line is in `lib/data/`)
1. [ ] Un-skip the confirmed repro tests; implement the smallest fix at the named root-cause line (D-14 for H-1/H-6, or the documented carry-forward contract for H-3/H-5)
2. [ ] Red without the fix, green with it (copy the file aside, not `git stash`); table in evidence
3. [ ] Structural guard S-5127: the repro test itself, plus one test proving the rule's boundaries (a non-zero next weight is not overwritten; reps unchanged; a logged next set untouched)
4. [ ] Docs: `docs/modality_based_exercise_ui.md` ("Set Skip vs Delete"/carry-forward invariant + pointer)

**Done Criteria**: `flutter test test/set_weight_carry_repro_test.dart test/reps_screen_test.dart test/delete_focused_set_test.dart test/exercise_set_last_value_test.dart`; analyze ≤ baseline; contract tests; full suite (900 s) with counts.
**Predicted Files**: the one `lib/` file holding the root-cause line (expected `lib/features/session/workout_session_screen.dart` `_logSet` or `_addSet`, never `_resyncExercisesFromState`), `test/set_weight_carry_repro_test.dart`, `docs/modality_based_exercise_ui.md`, evidence file.

## Files Affected

Production: `lib/widgets/session/session_progress_colors.dart` (new), `lib/widgets/session/set_segment_bar.dart`, `lib/widgets/session/timer_ring.dart`, `lib/widgets/session/value_stepper_row.dart`, `lib/widgets/session/inline_metric_editor.dart`, `lib/features/session/workout_session_detail_view.dart`, `lib/features/session/workout_session_list_view.dart`, `lib/state/settings/settings_state.dart`; Phase 5 only: one root-cause file. Read-only dependents: `lib/features/routine/routine_setup_screen.dart` (uses `ValueStepperRow`, behaviour unchanged by D-13), `lib/core/utils/date_utils.dart` (no change). Estimate: about 250 production lines (Phases 1–3) plus up to 30 (Phase 5).

## Notes

- Dependency graph: P1 → P2 → P3 (P1, P2 and P3 all edit `workout_session_detail_view.dart`; P2 and P1 both re-read `set_segment_bar`/ring tests). P4 is independent (tests only) and can run before P1 or beside any phase; P5 needs P4 and must run after the phase currently editing `workout_session_screen.dart`'s library is closed. Re-ordering: running P3 first gives the most-noticed change (hints) earliest at no cost except a rebase of P1's detail-view edit.
- Intermediate states: after P1 the ring and captions are final while the chip still shows the meditation icon; after P2 everything but the hint is final; all suites green at every phase end.
- PR scope: one track, 5 phases (P5 conditional), about 280 production lines. Soft signals: more than 3 phases (one). Not over budget; P1–P3 can land as one PR and P4/P5 as another if the governor prefers.
- Legacy: none (no stored-data change; preferences default to "not learned").

## Progress

- [ ] P1 ring, colours, captions — not started
- [ ] P2 arrow, chip, layout, title — not started
- [ ] P3 tap hint — not started
- [ ] P4 bug repro — not started
- [ ] P5 bug fix — conditional, not started

## Assumption Log

(executors append: decision, options considered, choice + why; at most 3 lines each)

## Feedback

[empty]
