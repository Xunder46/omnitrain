# Review: 38c count-up screens · P1, P2a, P2b, Phase D · working tree on claude_develop (base 80928669)

Verdict: APPROVE WITH FIXES
Counts: blocker 0 · major 0 · minor 3 · tests: `+4845 ~1: All tests passed!` (gateway `test`, this run); `flutter analyze` 182 issues, 0 errors (gateway `lint`, this run — at the Phase 0 baseline)

Diff vs Predicted Files: conforms for the brief's 38c regions. The tree also carries the uncommitted
38a/38b work (set bar, ValueStepperRow widget, reps screen, their tests) — out of scope here. Two
regions the brief names sit outside the plan's per-phase Predicted Files and are treated as the
fix-round additions the evidence file records: `test/exercise_detail_emphasis_tier_test.dart`
(S-106/S-106b) and `docs/data_models.md`. `docs/design_system.md` is Phase D scope item 4.

## Findings

1. [Minor] `docs/plans/2026-10-15-38c-count-up-plan/2026-10-15-38c-count-up-plan.md:171-199` — the
   Progress table still marks every P1/P2/D item "pending" and the plan text never defines scenarios
   S-4276..S-4279, although `test/count_up_screen_test.dart` asserts them and the docs cite them by
   name. A maintainer reading the plan after this change would conclude the work never ran and would
   find four asserted scenarios with no definition. Fix: lead updates the Progress statuses and adds
   the four interaction-containment scenarios (S-4276 hold dies with its set, S-4277/S-4278 live
   digits open nothing, S-4279 hold editor keeps its dialog) to the scenario list. Guard: none
   (bookkeeping).
2. [Minor] `test/count_up_screen_test.dart:341,355` — S-4260's second run varies the stored
   `extra-weight` observation but not the exercise's load capability; the plan's scenario says
   "exercise without load and with load (includeLoad)". Both runs use `exercise-easy-run`. The timed
   branch of `_buildMetricWidget` has no capability branch (the weight section was deleted
   unconditionally), so the absence guard still fails without the change and the O-11 intent is
   covered; only the literal with-load axis is missing. Fix: if the seed data has a load-capable
   exercise that can be forced to `timed`, run the second case on it; otherwise record the deviation
   in the plan. Guard: the second S-4260 test.
3. [Minor] `docs/widget_catalog.md:78-117` (not touched by this diff; inherited from 38a/38b,
   surfaced by this diff's catalog additions) — the widget → page lookup table has no rows for
   `ValueStepperRow`, `SetSegmentBar`, `SetCountStepper` or `LoggedValuesLine`, all four documented
   in `docs/widget_catalog/session_widgets.md`. A reader using the index finds nothing for the
   widget the hold screen now depends on. Fix: add the four index rows (owner/docs keeper; outside
   38c's write scope).

## Assumption Log rulings

- A-1 (status row and `ELAPSED`/`COMPLETED` captions dropped): ratified. The code does exactly what
  D-3/D-4 say — both live branches render bare digits (`unitLabel: ''`, no status Row), the editor
  branches keep their captions, `round` keeps its status row (FI-5, visible at
  `workout_session_detail_view.dart:455-470`).
- A-2 (hold weight limits -200..999 from the reps screen's clamp): ratified. The row passes
  `metricType: 'weight'` (`workout_session_detail_view.dart:113`), so `MetricStepCalc`'s weight
  clamp owns the limits; S-4269 shows -10.0 stored and stepping to -7.5, and the docs state the
  limit with the popup.

## Brief questions

1. No path shows a weight control on a `timed` entry. The timed live branch returns a bare
   read-only `InlineMetricEditor` (`workout_session_detail_view.dart:276-285`); the timed editor
   branch builds the duration editor only (:243-273, the `entryData['extra-weight']` section is
   gone). `_buildPreviousValues` (`workout_session_screen.dart:1300-1301`) and `_persistEntryValues`
   (:1168-1176) only carry/store the data, per D-6. No other `lib/features/session` file renders an
   extra-weight editor (repo grep: only the detail view and data-path code).
2. The lock is `!widget.editMode && _isSetLogged(effortId, entryIndex, 'drill')`
   (`workout_session_detail_view.dart:120-121`). `_isSetLogged`
   (`workout_session_screen.dart:751`) reads, for `drill`,
   `_getTimedInstance(effortId, entryIndex)?.state == TimedState.finished`
   (`workout_session_screen.dart:763-765`) — so a live hold locks exactly when its instance is
   finished, and `widget.editMode` short-circuits the lock in the session editor.
3. `_buildWeightAdjustmentSection`, `_kTimedStatusRowBottomGap` and `_weightAdjustExpanded` have no
   references left in `lib/` or `test/`; the only remaining matches are prose under `docs/plans/`
   (excluded by the brief).
4. No test asserts nothing real. The file header states the digits are wall clock and the flow tests
   honour it: S-4261 pumps 3 s but asserts the button label and the absence of chrome, never a
   growing digit; every non-zero digit assertion (S-4273/S-4274/S-4275) reads an elapsed time seeded
   into the repository through the restore path. The stepping, lock, popup, long-press (with a
   counting repository) and layout assertions all read state that the change under test produces.
5. No stale claim found. Every test name the three docs cite was found on disk this run (including
   the 38a/38b names the expanded sections reuse); the only remaining `STOPPED`/`RUNNING`/
   `Weight adjustment` mentions in the touched docs describe the removal or the `round` exception,
   both true. `navigation_and_screens.md` and `state_management.md` mention none of the changed
   chrome, so they needed no update.

## Scenario coverage

- S-4260 -> `test/count_up_screen_test.dart` · `S-4260: an interval with no load shows digits and no chrome` + `S-4260: a stored extra weight changes nothing on an interval` (with-load axis: finding 2)
- S-4261 -> same file · `S-4261: Start leaves the digits plain and the button logs`
- S-4262 -> same file · `S-4262: the interval editor keeps its duration dialog only`
- S-4263 -> same file · `S-4263: logging an interval leaves its data untouched`
- S-4264 -> same file · `S-4264: a hold shows digits plus one weight row`
- S-4265 -> same file · `S-4265: the hold weight steps 2.5 kg at a time` + `S-4265: a pounds preference steps 5 lb and stores kg`
- S-4266 -> same file · `S-4266: a weight step does not stop a running hold`
- S-4267 -> same file · `S-4267: a logged hold locks both weight buttons` + `S-4267: a logged hold stays editable in the editor`
- S-4268 -> same file · `S-4268: the hold weight number opens Edit Weight`
- S-4269 -> same file · `S-4269: a stored 10.0 reads as 10.0, with no sign` + `S-4269: a stored -10.0 reads as -10.0 and plus gives -7.5`
- S-4270 -> same file · `S-4270: a long press survives the one-second rebuilds`
- S-4271 -> same file · `S-4271: with the rest strip up the hold's controls are reachable` + `S-4271b` + `S-4271c` (relations asserted instead of the probe's literal positions, reason recorded in the test)
- S-4272 -> `test/sports_emphasis_redesign_test.dart` · `S-001`/`S-002` stay green, no edit (per plan)
- S-4273 -> `test/count_up_screen_test.dart` · `S-4273: a paused interval shows its elapsed and Resume`
- S-4274 -> same file · `S-4274: a paused hold keeps its elapsed, weight and Resume`
- S-4275 -> same file · `S-4275: the reload keeps the elapsed time and the timer`
- S-4276 -> same file · `S-4276: a hold dies with its set when the arrows move focus` (scenario not in the plan text: finding 1)
- S-4277 -> same file · `S-4277: a live interval's digits open nothing on a tap` (finding 1)
- S-4278 -> same file · `S-4278: a live hold's digits open nothing on a tap` (finding 1)
- S-4279 -> same file · `S-4279: the hold editor keeps its duration dialog` (finding 1)

Reader migrations spot-checked against the plan's table: `timed_emphasis_redesign_test.dart`
(stopped/running/routine-backed rewritten to the absence rule, per-iteration `ValueKey` added),
`session_toolbar_rework_test.dart` (S-009/S-010/S-011/S-013 on the centre button),
`logger_shell_screen_test.dart` S-4217 (both buttons inert, number not tappable; editor editable),
`screen_widget_test.dart` (timed lbs inverted, drill lbs without the `+`, reveal and OutlinedButton
tests deleted, set guards kept), `exercise_detail_emphasis_tier_test.dart` (S-106 moved to the
hold's `weight` row, S-106b asserts no weight editor on an interval). All match the table's rule.

Project checks: no `hive_workout_repository` import added to `lib/state`, `lib/features`,
`lib/widgets`, `lib/core`; no data-model or schema change; no hex colour or raw button added by the
38c regions (the diff only deletes them); `test/helpers/ui_standards_allowlist.dart` is not in the
diff — no allowlist entry, no ratchet raised.
