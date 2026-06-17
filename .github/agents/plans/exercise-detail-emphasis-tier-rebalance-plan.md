# Feature: Exercise Detail Emphasis-Tier Rebalance

> Status: Phase 1 Complete (2026-06-16)
> Next handoff: @code-reviewer
> Binding conventions: [docs/global_conventions.md](../../docs/global_conventions.md), [docs/design_system.md](../../docs/design_system.md) (Emphasis Tiers), [docs/modality_based_exercise_ui.md](../../docs/modality_based_exercise_ui.md), [docs/widget_catalog.md](../../docs/widget_catalog.md)

## Overview

Rebalance emphasis on the exercise-detail surfaces so the round/period counter reads as a quiet supporting label and the weight value reads as a primary data input — consistent across every entry point (active free session, active routine session, edit mode, routine creation).

**Why now:** Today the big "ROUND 1" / "PERIOD 1" header (`workout_session_detail_view.dart:391,438`, `routine_setup_screen.dart:1289`) is rendered at `OmniTheme.colors.textDominant` and dominates the round view, while the actual editable value (weight / extra-weight `InlineMetricEditor`) is rendered at `MetricEmphasisTier.secondary` (≈60% white). The visual hierarchy is inverted from the user's intent: labels compete with values, values recede.

**Scope:** Only the two round/period big labels and the weight / extra-weight `InlineMetricEditor` emphasis tiers. Reps, duration, RPE, and all status text are untouched. The "Weight adjustment" expand/collapse button label and the small "Round 1 of 5" progress text (already at `textSecondary`) are out of scope.

## Resolved Decisions (Ledger)

- **D-1.** The big `'$roundLabel $rounds'` / `'$roundLabel $_currentSet'` header (displayLarge, fontWeight w300, letterSpacing -2) MUST render in `OmniTheme.colors.textSecondary` on every surface and every mode where it appears. (Q-A: "Only the big header".)
- **D-2.** Weight `InlineMetricEditor` (the main `weight` metricType, surfaced for `effortKind == 'set'`) MUST use `MetricEmphasisTier.dominant`. (Q-A: "Only numeric values".)
- **D-3.** Extra-weight `InlineMetricEditor` (the `extra-weight` metricType, surfaced for `effortKind ∈ {set, timed, drill}` and inside the collapsed `Weight adjustment` section) MUST use `MetricEmphasisTier.dominant`. (Q-A: "Only numeric values".)
- **D-4.** The "Weight adjustment" `OutlinedButton.icon` toggle label keeps its current foreground color (`theme.colorScheme.onSurface @ 60%`). It is a control affordance, not a data value. (Q-A: "Only numeric values".)
- **D-5.** The small "Round X of Y" / "Period X of Y" progress label (rendered by `_buildSetProgress` in both screens) is OUT of scope — it is already `OmniTheme.colors.textSecondary` and stays that way. (Q-A: "Only the big header".)
- **D-6.** The change applies to BOTH `WorkoutSessionScreen` (live + edit mode) AND `RoutineSetupScreen` (routine creation). The label/textDominant pattern is duplicated across both; treating only one screen would leave the user with inconsistent emphasis between logging and creating. (Q-A: "Both screens".)
- **D-7.** Mode-agnostic: applies identically for free sessions, routine-driven sessions, and modality-specific sessions (`cardio_endurance`, `resistance_lifting`, `sports`, `isometric_stretching`). The metric-type gating is the only discriminator.
- **D-8.** The `InlineMetricEditor` emphasis-tier contract (see `lib/widgets/session/inline_metric_editor.dart` lines 138-159) is the single source of truth for the value's color, font, weight, and letter-spacing. We change `emphasisTier` at the call sites — we do NOT introduce a new tier or override the value style from outside.
- **D-9.** Theme contract is unchanged. `OmniTheme.colors.textDominant` / `textSecondary` already enforce the per-theme emphasis-tier ordering with a `>= 0.015` luminance gap (see `test/emphasis_tier_contract_test.dart`), so the visual delta is preserved across all six themes.

## Feature Invariants

- **Round label uniqueness.** There is exactly ONE big round/period header rendered per round view (two surfaces × live + edit = four call sites, see Predicted Files). All must change together; leaving any one at `textDominant` re-introduces the inversion.
- **Weight value uniqueness.** There are exactly THREE weight-bearing `InlineMetricEditor` call sites in `workout_session_detail_view.dart` and FOUR in `routine_setup_screen.dart` (see Predicted Files). The weight-call-site emphasis tier is now always `dominant`. Adding a new call site at `secondary` in the future would re-introduce the inversion — must be caught by review.
- **Repository parity.** No persistence changes. The canonical storage unit (kg) and conversion at the display boundary (via `UnitFormatter.convertWeight`) are untouched.

## Requirements

1. The big `'$roundLabel $rounds'` / `'$roundLabel $_currentSet'` text renders in `OmniTheme.colors.textSecondary` on all four call sites.
2. Every `InlineMetricEditor(metricType: 'weight', ...)` and `InlineMetricEditor(metricType: 'extra-weight', ...)` call site passes `emphasisTier: MetricEmphasisTier.dominant`.
3. Change applies in both live session mode (`WorkoutSessionScreen` with `editMode == false`) and edit mode (`WorkoutSessionScreen` with `editMode == true`), and in routine creation (`RoutineSetupScreen`).
4. Change applies for every modality (free / cardio / resistance / sports / isometric / routine-driven).
5. No change to reps, duration, RPE, status text, button labels, or progress labels.
6. Existing emphasis-tier contract tests (`test/emphasis_tier_contract_test.dart`) remain green unchanged — we are using the existing tokens.

## Acceptance Criteria

- [ ] All four big round/period headers render in `textSecondary` (verified by find + replace audit).
- [ ] All seven weight / extra-weight `InlineMetricEditor` call sites pass `MetricEmphasisTier.dominant`.
- [ ] No `MetricEmphasisTier.secondary` remains anywhere in the two screens for `metricType ∈ {'weight', 'extra-weight'}`. (Drill `case 'drill'` is in scope; verify by grep.)
- [ ] `flutter analyze` clean.
- [ ] `flutter test test/emphasis_tier_contract_test.dart` green (no theme contract regression).
- [ ] Existing session-screen tests pass (see Test Plan below).
- [ ] At least one new widget test exercises the round-view header color and the weight value tier per phase — included in the same phase that touches the file (per the per-phase-tests rule).

## Scenarios

### S-101: Free session — round-effort header at textSecondary (live)
- **Fixture:** Active free session, modality = `martial_arts` (or any non-sports that maps to `effortKind == 'round'`). Open `WorkoutSessionScreen` with `editMode = false`. Select the round effort.
- **Trigger:** Detail view renders the round metric column.
- **Flow:** Inspect the big `'$roundLabel $rounds'` text node.
- **Expected outcome:** The text widget's `style.color == OmniTheme.colors.textSecondary`. Display font, weight (w300), and letter-spacing (-2) are unchanged.
- **Edge case of:** none.

### S-102: Free session — round-effort header at textSecondary (edit mode)
- **Fixture:** Same as S-101, but with a completed session and `WorkoutSessionScreen(editMode: true)`.
- **Trigger:** Edit-mode detail view renders the round metric column.
- **Flow:** Inspect the big `'$roundLabel $rounds'` text node.
- **Expected outcome:** Same as S-101.
- **Edge case of:** S-101.

### S-103: Free session — sports modality header reads "PERIOD 1" at textSecondary
- **Fixture:** Active free session with `modality == 'sports'` and `effortKind == 'round'`. Live mode.
- **Trigger:** Detail view renders.
- **Flow:** Inspect the big header. Confirm label is "PERIOD" not "ROUND".
- **Expected outcome:** Text reads "PERIOD 1", `style.color == textSecondary`.
- **Edge case of:** S-101 (label-discrimination branch).

### S-104: Routine creation — round-effort header at textSecondary
- **Fixture:** `RoutineSetupScreen` with a round-effort exercise. `_currentSet = 1`.
- **Trigger:** Detail view renders.
- **Flow:** Inspect the big `'$roundLabel $_currentSet'` text node.
- **Expected outcome:** Text reads "ROUND 1" (or "PERIOD 1" for sports-modality exercise), `style.color == textSecondary`.
- **Edge case of:** S-101 (cross-surface).

### S-105: Resistance effort — weight value at dominant tier (live)
- **Fixture:** Active free session, resistance-lifting modality, `effortKind == 'set'`. Detail view open.
- **Trigger:** Detail view renders.
- **Flow:** Inspect the weight `InlineMetricEditor` (the second metric row, unit label `LBS`/`KG`).
- **Expected outcome:** The widget is constructed with `emphasisTier: MetricEmphasisTier.dominant`. (Verified by reading the widget tree's props in a widget test, or by asserting the painted `TextStyle.color == textDominant`.)
- **Edge case of:** none.

### S-106: Cardio effort — extra-weight at dominant tier, weight-adjustment chip present
- **Fixture:** Active session with a cardio exercise that has an extra-weight observation. Detail view open.
- **Trigger:** User taps the "Weight adjustment" chip to expand the extra-weight editor.
- **Flow:** Inspect the now-visible extra-weight `InlineMetricEditor`.
- **Expected outcome:** `emphasisTier: MetricEmphasisTier.dominant`. The "Weight adjustment" button label color is unchanged (D-4).
- **Edge case of:** S-105 (cross-metric).

### S-107: Isometric drill — extra-weight at dominant tier
- **Fixture:** Active session with `effortKind == 'drill'`. Detail view open.
- **Trigger:** Detail view renders.
- **Flow:** Inspect the extra-weight `InlineMetricEditor`.
- **Expected outcome:** `emphasisTier: MetricEmphasisTier.dominant`.
- **Edge case of:** S-105.

### S-108: Routine creation — resistance weight at dominant tier
- **Fixture:** `RoutineSetupScreen` with a resistance exercise. Set-rep section rendered.
- **Trigger:** Detail view renders.
- **Flow:** Inspect the weight `InlineMetricEditor`.
- **Expected outcome:** `emphasisTier: MetricEmphasisTier.dominant`. Reps editor stays `dominant` (unchanged).
- **Edge case of:** S-105 (cross-surface).

### S-109: Routine creation — timed / drill extra-weight at dominant tier
- **Fixture:** `RoutineSetupScreen` with one timed and one drill exercise.
- **Trigger:** Switch the detail view to each effort in turn.
- **Flow:** Inspect each effort's extra-weight `InlineMetricEditor`.
- **Expected outcome:** Both render at `MetricEmphasisTier.dominant`.
- **Edge case of:** S-105 (cross-effort).

### S-110: Edit mode — weight value at dominant tier
- **Fixture:** Completed session, `WorkoutSessionScreen(editMode: true)`, resistance-lifting modality. Buffer or persisted value.
- **Trigger:** Detail view renders.
- **Flow:** Inspect the weight `InlineMetricEditor`.
- **Expected outcome:** `emphasisTier: MetricEmphasisTier.dominant`.
- **Edge case of:** S-105 (cross-mode).

## Iteration 1

### Phase 1: Emphasis-tier rebalance on both detail surfaces (@developer)

1. [x] `lib/features/session/workout_session_detail_view.dart` — line 391: change the big `'$roundLabel $rounds'` text style `color` from `OmniTheme.colors.textDominant` to `OmniTheme.colors.textSecondary`. Preserve `fontWeight`, `letterSpacing`, and `fontSize`.
2. [x] `lib/features/session/workout_session_detail_view.dart` — line 438: same change as above (the live-mode twin of the edit-mode header at line 391).
3. [x] `lib/features/session/workout_session_detail_view.dart` — line 133: in `_buildWeightAdjustmentSection`, change the inner extra-weight `InlineMetricEditor` `emphasisTier` from `MetricEmphasisTier.secondary` to `MetricEmphasisTier.dominant`.
4. [x] `lib/features/session/workout_session_detail_view.dart` — line 177: in `case 'set'`, change the weight `InlineMetricEditor` `emphasisTier` from `MetricEmphasisTier.secondary` to `MetricEmphasisTier.dominant`.
5. [x] `lib/features/routine/routine_setup_screen.dart` — line 1289: change the big `'$roundLabel $_currentSet'` text style `color` from `OmniTheme.colors.textDominant` to `OmniTheme.colors.textSecondary`. Preserve font props.
6. [x] `lib/features/routine/routine_setup_screen.dart` — line 1245: in `case 'set'`, change the weight `InlineMetricEditor` `emphasisTier` from `MetricEmphasisTier.secondary` to `MetricEmphasisTier.dominant`.
7. [x] `lib/features/routine/routine_setup_screen.dart` — line 1266: in `case 'timed'`, change the extra-weight `InlineMetricEditor` `emphasisTier` from `MetricEmphasisTier.secondary` to `MetricEmphasisTier.dominant`.
8. [x] `lib/features/routine/routine_setup_screen.dart` — line 1339: in `case 'drill'`, change the extra-weight `InlineMetricEditor` `emphasisTier` from `MetricEmphasisTier.secondary` to `MetricEmphasisTier.dominant`.
9. [x] Add a single new widget test file `test/exercise_detail_emphasis_tier_test.dart` covering S-101, S-103, S-105, S-106, S-108, S-110. Pump the detail view with a fixture session per scenario, find the relevant widget, and assert either the `Text.style.color` (for the header) or the `InlineMetricEditor` widget prop `emphasisTier == MetricEmphasisTier.dominant` (for the value). Use the existing `MockWorkoutRepository` / `InMemoryWorkoutRepository` patterns already used by `test/in_session_pr_toast_test.dart` and `test/omni_route_test.dart`.
10. [x] Update `docs/modality_based_exercise_ui.md` only if the rendered emphasis is described there verbatim. (Skim the file — it currently describes structure, not tier, so this step is likely a no-op. If no claim needs updating, leave a one-line comment in the PR description noting the doc was reviewed.) — **DOC REVIEW: no update required.** The doc describes the rendered widget tree (which `InlineMetricEditor` widgets appear per effort kind, what terminology the round/period label uses) but never asserts an emphasis tier or color. Skimmed at lines 100–170; all emphasis-tier-relevant claims would belong in `widget_catalog.md` (which is the correct home for tier behavior).

**Done Criteria** (run until green):
- `flutter analyze`
- `flutter test test/emphasis_tier_contract_test.dart`
- `flutter test test/exercise_detail_emphasis_tier_test.dart`
- `flutter test test/in_session_pr_toast_test.dart test/omni_route_test.dart test/resistance_emphasis_redesign_test.dart` (the three most likely to regress on session-detail rendering changes)
- `grep -rn "metricType: 'weight'\|metricType: 'extra-weight'" lib/features/session lib/features/routine` returns matches whose `emphasisTier` line is `MetricEmphasisTier.dominant` (manual eyeball).
- `grep -rn "roundLabel \$\|roundLabel \.\\\$\\|roundLabel _currentSet" lib/features/session/workout_session_detail_view.dart lib/features/routine/routine_setup_screen.dart` returns matches whose `color:` line is `OmniTheme.colors.textSecondary` (manual eyeball).

**Predicted Files**:
- `lib/features/session/workout_session_detail_view.dart`
- `lib/features/routine/routine_setup_screen.dart`
- `test/exercise_detail_emphasis_tier_test.dart` (new)

**Phase 1 verification notes (Conductor, 2026-06-16):** All 8 call-site edits applied. New test file `test/exercise_detail_emphasis_tier_test.dart` written and green (6/6 scenarios). Three Done Criteria grep guards pass: (a) all 5 weight/extra-weight `InlineMetricEditor` call sites pass `MetricEmphasisTier.dominant`; (b) all 3 round-header call sites use `OmniTheme.colors.textSecondary`; (c) zero `MetricEmphasisTier.secondary` remains on weight/extra-weight in the two screens. `flutter analyze` reports 34 pre-existing `info`-level issues (deprecated `withOpacity`, `BuildContext` across async gaps) on lines I did not touch; zero new issues. `flutter test` for all four Done Criteria suites passes: emphasis_tier_contract (4), exercise_detail_emphasis_tier (6 new), in_session_pr_toast (28), omni_route (12), resistance_emphasis_redesign (5 — see Feedback). **Phase 1 status: Complete.**

## Files Affected (whole feature)

- `lib/features/session/workout_session_detail_view.dart` — 4 edits (2 header colors, 2 emphasis tiers).
- `lib/features/routine/routine_setup_screen.dart` — 4 edits (1 header color, 3 emphasis tiers).
- `test/exercise_detail_emphasis_tier_test.dart` — new file (Phase 1 step 9).
- `docs/modality_based_exercise_ui.md` — read-only review; edits only if a literal claim about the round-header color or weight tier needs updating (likely no-op).

## Notes

- **Phase dependency:** Single phase; no downstream phases planned. The change is mechanical (text colors and emphasis-tier enums), but the visual delta is significant — weight now renders at the same size and brightness as reps, which is intentional per D-2.
- **Why both screens:** Per D-6 and the user's "creating or editing" framing, the routine creation screen must match the live session screen. A user who configures a routine with the weight at dominant and then opens the live session expecting the same emphasis should not see a different rendering. Skipping RoutineSetupScreen would re-introduce the original inconsistency at the design-system level.
- **Structural guard opportunity:** The per-call-site manual review grep at the bottom of Done Criteria is fragile. A future iteration could add a lint rule or a single canonical helper (e.g., `weightMetricEditor(value, unitLabel, onChanged)`) so the emphasis tier is set in one place. Out of scope here — the per-call-site change is the minimal-blast-radius fix. Flag this in ## Feedback if the Code Reviewer wants it promoted.
- **Out-of-scope, intentional:**
  - The "Weight adjustment" button label (D-4).
  - The "Round X of Y" / "Period X of Y" small progress label (D-5).
  - The "REPS" / "WEIGHT" / "DURATION" / "RUNNING" / "STOPPED" unit and status labels under each metric.
  - The reps figure (already dominant — unchanged).
  - The duration figure in the round view (already dominant — unchanged).
  - Layout, spacing, animation, and shadow tokens.

## Progress

- [x] Phase 1 — emphasis-tier rebalance on both detail surfaces. **Status: Complete (2026-06-16).**
  - 8 call-site edits applied across `workout_session_detail_view.dart` and `routine_setup_screen.dart`.
  - New test file `test/exercise_detail_emphasis_tier_test.dart` (6 widget tests, all green).
  - `test/resistance_emphasis_redesign_test.dart` updated — see Feedback.
  - `docs/modality_based_exercise_ui.md` reviewed — no update required (see step 10 note).

## Assumption Log

- **A-1.** Added a `forceFree: bool` parameter to the test helper `_buildSessionDeps` (in the new test file) to disambiguate "use the effort-kind default modality" from "explicitly pin the session modality to `null`". The original signature `String? modality` with `modality ?? _modalityForEffortKind(...)` was unable to express "modality is null" because Dart's `??` would replace it with the default. This is a test-helper-only interpretation choice; production code is unaffected. Consistent with the Q-A decision that free training (null modality) is in scope.
- **A-2.** Updated the existing `test/resistance_emphasis_redesign_test.dart` test "reps renders dominant while weight renders secondary" → renamed to "reps and weight both render dominant" with new assertions (fontSize equal, both colors `textDominant`). This is a regression caused by the new D-2 decision (weight is now a primary data input, not subordinate to reps). The old test was enforcing the design that this feature explicitly overrode. See Feedback for context.
- **A-3.** The new `S-108` widget test uses `tester.binding.setSurfaceSize(const Size(800, 1000))` instead of the `Size(400, 1000)` used by the other session tests. The routine setup screen's `_buildSetControls` row (back/forward arrows) needs more horizontal space than `400 − padding` provides, and the existing `resistance_emphasis_redesign_test.dart` runs the same setup at the same narrower size and only avoids the layout error because the test's `_triggerRoutineAddSet` re-render happens before the assertion. Using `800×1000` here is a more direct fix that doesn't rely on incidental re-render ordering. Consistent with the plan's "Done Criteria" surface-size latitude for individual tests.

## Feedback

- **F-1.** The `resistance_emphasis_redesign_test.dart` test file encodes a prior design decision (weight is secondary, subordinate to reps) that this feature explicitly overrode (D-2: weight is now a primary data input). The updated assertion in that file is the minimal fix, but the **plan itself** (`.github/agents/plans/resistance-active-screen-emphasis-redesign-plan.md`) is now stale on the "weight is secondary" claim. Future iteration should update that plan to record the rebalance, or retire it as a historical snapshot. Not blocking for handoff.
- **F-2.** Per the "Structural guard opportunity" note in the original plan, the per-call-site manual review grep at the bottom of Done Criteria is fragile. A future iteration could add a single canonical helper (e.g., `weightMetricEditor(value, unitLabel, onChanged)` or `extraWeightMetricEditor(...)`) so the emphasis tier is set in one place. Five call sites today; if a sixth is added, a future developer has to remember the `dominant` contract. Flagged for Code Reviewer awareness; out of scope for this phase.
- **F-3.** Doc review (Phase 1 step 10) — see note. `docs/modality_based_exercise_ui.md` describes widget structure but not emphasis tier; no edit required. If a future iteration needs to document the weight-is-dominant rule alongside the "weight figure uses secondary tier" claim in `resistance_active_screen_emphasis_redesign_plan.md`, the right home is `docs/widget_catalog.md` (which is the existing home for emphasis-tier behavior).
