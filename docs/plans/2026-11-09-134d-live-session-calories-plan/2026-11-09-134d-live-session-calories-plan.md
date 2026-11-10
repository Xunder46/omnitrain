# Plan — 134d: calories so far, on the active session screen

**Status**: built, reviewed and verified 2026-11-09; uncommitted. Evidence: `docs/plans/2026-11-09-134e-wrist-rest-calories-plan/2026-11-09-134e-wrist-rest-calories-plan.evidence.md` (one file for 134b to 134e).
**Binding conventions**: `docs/global_conventions.md`, `docs/design_system.md`.
**Base commit**: `ff398e1a7ec18409d9fc8c890bf35d2fde656e69` (branch `claude_develop`; the uncommitted plan 134a is in the tree and required: `ActiveEnergyService`, `kActiveEnergyMets`).
**Parent plan**: `docs/plans/2026-11-08-134-calories-burned-plan/2026-11-08-134-calories-burned-plan.md`.

## Overview

Owner (2026-11-08): on the session details screen, during an active session, show the calories on the opposite side of the session time label, in the same bar.

What the user sees: the bar under the header reads `Session Time` / `00:18:22` on the left (as today) and, on the right, `Calories` / `~100 kcal`. The number climbs with the clock. `~` always, because while a session runs the phone can only estimate (the watch's measured total reaches the phone when the session ends: plan 134c; a live watch-to-phone feed is NOT in this unit, see Assumption Log A-1). With no body weight logged the value reads `—`. A session opened to edit its duration (edit mode) shows no Calories chip, and a rolling session (which has no Session Time chip) has none either.

## Goal and acceptance

The chip described above on the active session screen. Acceptance: S-13440 .. S-13449.

## Decision Ledger

| ID | Decision | Backing |
|---|---|---|
| D-13440 | `ActiveEnergyService` gains (a) public `Future<double?> latestWeightKg()` — the existing private `_latestWeightKg` renamed, same body (kg unit, finite, above zero); `settle` calls it; and (b) `static double? liveKcal({required String? modality, required int elapsedSecs, required double? weightKg})` = `(MET − 1) × kg × elapsedSecs / 3600` with the MET of `sectionForModality(modality)` when the modality id names a section, else the RESISTANCE MET (Free Training, an unknown id); null when `weightKg` is null, not finite or `<= 0`, or `elapsedSecs < 0`. The private instance `_kcal(section, secs, kg)` becomes a `static` shared by `settle`'s estimate and `liveKcal`, so there is ONE formula | `lib/core/services/active_energy_service.dart:49-79`; 134a D-13403 |
| D-13441 | `WorkoutState` keeps the `activeEnergy` it is given (a final field, besides passing it to `SessionCore`) and exposes `Future<double?> latestBodyWeightKg() async => _activeEnergy?.latestWeightKg()` (null without the service). The screen never builds a service or reads the repository for this | `workout_state.dart:50-80`; `WorkoutState` is the screen's only state dependency for the session |
| D-13442 | The live figure for a Free Training session uses the resistance MET for the whole elapsed time. The exact per-section split (`sessionTimeBySectionFor`) needs the full history index (all sessions, segments, efforts, instances) and cannot run on a 1 s tick; the stored value written at the end (134a) stays exact. So a Free Training session that has timed cardio or holds can step when it ends (the lead's call, listed to the owner) | `stats_progress_service.dart:108-139` `_loadHistory`, `:944-952` `sessionTimeBySectionFor` returns empty for an unfinished session |
| D-13443 | Screen state in `_WorkoutSessionScreenState` (`workout_session_screen.dart`, beside `_elapsedFormatted` at :161): `int _elapsedSecs = 0`, `double? _liveWeightKg`, `double? _liveKcal`, `int _liveTicks = 0`. `_tick()` (`workout_session_global_timer.dart:9-31`) stores the elapsed seconds it already computes (0 in the "no exercise yet" branch) and recomputes `_liveKcal` from them with `ActiveEnergyService.liveKcal(modality: currentSession.modality, elapsedSecs: _elapsedSecs, weightKg: _liveWeightKg)`, inside the same `_updateUi`. The weight is read by `_loadLiveWeight()` once from `initState` (only when `!widget.editMode`) and again on every 60th tick (a weight logged while the screen is open appears within a minute); the call sets `_liveWeightKg` and recomputes `_liveKcal` immediately | `workout_session_screen.dart:246-260` initState; the tick |
| D-13444 | The chip: new `_buildSessionCaloriesWidget(ThemeData theme)` in `workout_session_list_view.dart` beside `_buildSessionTimeWidget`, mirroring its look: `Container(key: Key('omni_session_live_calories'), margin bottom 8)` holding a `Column(crossAxisAlignment: end)` of the label `Calories` (`titleSmall`, `OmniTheme.colors.textSecondary`) and a `Row(mainAxisSize: min)` of `Icon(Icons.local_fire_department_outlined, size 16, textSecondary)`, `SizedBox(width: 8)` and `Text(label, key: Key('omni_session_live_calories_value'), titleMedium, tabular figures, textDominant)`. `label` = `'~${kcal.round()} kcal'`, or `'—'` when `_liveKcal` is null. Both places that build the bar (`:454` empty state and `:507` populated, each `Row(children: [_buildSessionTimeWidget(theme)])`) become `Row(children: [_buildSessionTimeWidget(theme), const Spacer(), if (!widget.editMode) Flexible(fit: FlexFit.tight, flex: 20, child: _buildSessionCaloriesWidget(theme))])` and the chip's content sits in `FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerRight, ...)` (built form, P2 deviation: the plain `Spacer` form overflowed the 320 dp guard by 2 dp in the test font; the lead accepted it, at 390 dp nothing scales) | `workout_session_list_view.dart:9-58, 452-455, 505-508` |
| D-13445 | The time chip does not move (the regression guard `test/screen_widget_test.dart` 'Session Time chip position is unchanged') | scout PHONE Q4 |

## Scenarios

| ID | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-13440 | `liveKcal` pure: resistance 1800 s 80 kg; cardio 600 s 80 kg; isometric 3600 s 80 kg; sports 5400 s 70 kg; `null` modality 3600 s 80 kg; `'conditioning_mixed'` 3600 s 80 kg | 100.0; 80.0; 104.0 (`closeTo` 1e-9); 525.0; 200.0; 200.0 | `liveKcal` does not exist |
| S-13441 | `liveKcal` guards: weight null; weight 0; weight -5; weight NaN; elapsed -1; elapsed 0 with weight 80 | null, null, null, null, null, and 0.0 (a real result, never null) | no guards |
| S-13442 | final equals live: a finished resistance session of exactly 3600 s at 80 kg through `settle` (Mock AND Hive) | the stored `activeKcal` equals `liveKcal(modality: resistance, elapsedSecs: 3600, weightKg: 80)` (200.0) | two formulas could drift (guards the shared static) |
| S-13443 | `latestWeightKg()` (Mock AND Hive): none logged; a kg entry 80; then a newer `unit-lbs` entry 176; a kg entry 0; two kg entries 80 then 82 (newest) | null; 80.0; null (the latest entry wins and is not kg, the rule of S-13405); null; 82.0 | no public reader |
| S-13444 | `WorkoutState(repo, activeEnergy: service).latestBodyWeightKg()` with an 80 kg entry; and `WorkoutState(repo).latestBodyWeightKg()` | 80.0; null | no passthrough |
| S-13445 | screen: resistance modality session backdated 1800 s, 80 kg logged, one exercise, 390x844 | `Calories` label and `~100 kcal` in `omni_session_live_calories_value`; `Session Time` still shown | the screen had no Calories chip at all |
| S-13446 | the same without a body weight | the value reads `—` | no rule for a missing weight |
| S-13447 | geometry, 390x844: the Calories chip's left edge is right of the time chip's right edge; its right edge is within 1 dp of 370 (the bar's 20 dp padding); both chips' tops are equal within 1 dp | as stated | the chip would sit elsewhere or wrap |
| S-13448 | Free Training session (`modality` null) backdated 1800 s, 80 kg | `~100 kcal` (resistance MET, D-13442) | no Free Training rule |
| S-13449 | a session with no exercise yet (the clock holds `00:00`) and 80 kg; and the edit-mode screen (`editMode: true`) of a session | `~0 kcal` with the clock at `00:00`; in edit mode the text `Calories` is absent and `Session Time` is present | the chip would show a number the clock does not, and in edit mode a stale one |

## Phases (outline)

| Phase | Agent | Write scope | Parallel |
|---|---|---|---|
| P1 service + state | crew-builder-app | `lib/core/services/active_energy_service.dart`, `lib/state/workout/workout_state.dart`, new `test/active_energy_live_test.dart` | parallel with 134b P1 (disjoint scopes) |
| P2 screen | crew-builder-app | `lib/features/session/workout_session_screen.dart`, `lib/features/session/workout_session_global_timer.dart`, `lib/features/session/workout_session_list_view.dart`, new `test/session_live_calories_test.dart` | after P1 |
| P3 docs | crew-docs-keeper | the Docs delta rows | after P2 |

### P1 (one crew-builder-app run)

Write the report FIRST as a skeleton. Never run the full `flutter test`. Do not touch the 134b files (`fuel_summary.dart`, `stats_progress_service.dart`, `fuel_*`): another run owns them, and `flutter analyze` findings in those files are not yours.

1. New `test/active_energy_live_test.dart` with S-13440 .. S-13444. Red first. For S-13442/S-13443 copy the structure of `test/active_energy_service_test.dart` (read its first 90 lines: `harnessFactories`, seeding a weight, plain `test()`); S-13444 copies `test/active_energy_lifecycle_test.dart`'s `_energy(repo)` and `_freshRepo`.
2. `active_energy_service.dart` per D-13440.
3. `workout_state.dart` per D-13441 (a doc comment on the method; keep the existing constructor doc).
4. Run `bash .github/copilot/scripts/macos/gateway.sh test -- test/active_energy_live_test.dart`, then `-- test/active_energy_service_test.dart`, then `-- test/active_energy_lifecycle_test.dart`. Paste counts.

### P2 (one crew-builder-app run)

Write the report FIRST as a skeleton. Never run the full suite. No layout change beyond the briefed lines.

1. New `test/session_live_calories_test.dart` with S-13445 .. S-13449: copy the helper block of `test/timer_digits_hours_test.dart` (lines 1-127: `_phone`, `_freshRepo`, `_Deps`, `_buildDeps`, `_addTimedExercise`, `_buildSessionScreen`, `_pumpSession`, `_backdateSessionStart`) and change `_buildDeps` to build `WorkoutState(repo, activeEnergy: ActiveEnergyService(repo, () => StatsProgressService(repo)))` and `createNewSession(isRolling: false, modality: <param>)`. Weight: `repo.saveMeasurementEntry(BodyMeasurementEntry(id: 'bw1', measurementType: 'bodyweight', value: 80.0, unitId: 'unit-kg', recordedAtMs: <now>))` before `_pumpSession`. Plain `testWidgets` with a Mock repository, no real waits (as the copied file does). Red first.
2. Production code per D-13443 and D-13444 (the exact statements are in the Decision Ledger).
3. Run `-- test/session_live_calories_test.dart`, `-- test/timer_digits_hours_test.dart`, `-- test/session_edit_duration_test.dart`, and `-- test/ui_standards_contract_test.dart`. Then the one screen test `-- test/screen_widget_test.dart --plain-name "Session Time chip position is unchanged"`. Paste counts.

### P3 docs (one crew-docs-keeper run)

Run no test. Execute the Docs delta rows.

## Readers to update (found by the lead)

| Reader | What it reads | Action |
|---|---|---|
| `test/screen_widget_test.dart` (8856, 8880, 10204) | `Session Time` chip present/absent/position | untouched; run by name in P2 |
| `test/timer_digits_hours_test.dart`, `test/session_edit_duration_test.dart` | the clock, the chip in edit mode | untouched; run in P2 |
| every test that builds `WorkoutSessionScreen` | the whole screen | untouched; the full suite proves it |
| `active_energy_service.dart` `_latestWeightKg` | `settle` only | renamed public, same body |

## Input-reality checklist

1. **Writers**: body weight is written by the Profile screen and the Health import (kg canonical); this unit only reads it (`latestWeightKg`, the same guarded read as `settle`).
2. **Lifecycle**: chip only on the non-rolling, non-edit screen of an open session; when the session ends the screen pops to the Summary, which shows the stored value (D-13442: a Free Training session with timed cardio can differ from the last live figure).
3. **Settings**: a weight logged while the screen is open appears within 60 ticks (D-13443); no unit setting for energy.
4. **Time**: the figure uses the clock's own seconds, so the two cannot disagree; the clock holds `00:00` until the first exercise exists, so the figure holds `~0 kcal` (a real zero); a start in the future gives a negative elapsed and `—`.
5. **Cost**: one repository read per 60 s; arithmetic per second inside the existing `setState`.
6. **Words**: `Calories`, `~N kcal`, `—`. No older wording on this screen (grep `Calories` in `lib/features/session`: only the Summary's pill).
7. **Competition**: the bar's right side was empty; the chip takes it; the rest strip and the CTA are untouched.

## Feature invariants

- One formula: the live figure and the stored estimate come from the same static (S-13442).
- The chip never shows a measured (un-`~`) value in this unit.
- A session that ends shows the Summary, never this chip.

## Existing-functionality impact

| Touch | What reads it today | Effect | Guarded by |
|---|---|---|---|
| `active_energy_service.dart` | `main.dart`, `settle` callers, 134a tests | rename + one static + a shared static formula | S-13442, the 134a suites |
| `workout_state.dart` | every screen | one field, one method | S-13444 |
| `workout_session_screen.dart`, `_global_timer`, `_list_view` | the active session screen | fields, tick lines, one chip, two bar rows | S-13445..S-13449, the screen suites |

## Assumption Log

| ID | Assumption | Why |
|---|---|---|
| A-1 | The live figure is always an estimate (`~`); a watch-measured live total does not reach the phone before the session ends | the wire has no live sensor frame (scout WATCH Q3: only per-entry summaries at log time and the whole-session summary at the end); a new frame type is a separate plan |
| A-2 | A Free Training session's live figure uses the resistance MET for the whole elapsed time (D-13442) | the exact split cannot run per tick |

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| docs/modality_based_exercise_ui.md | ADDED | - | `**Live calories.**` | S-13445, S-13446, S-13447, S-13448, S-13449 |
| docs/state_management/services_and_utils.md | MODIFIED | `Stores the active-energy estimate of a finished session (D-13407).` | `Stores the active-energy estimate of a finished session (D-13407) and computes the running estimate the open session screen shows (D-13440).` | S-13440, S-13442 |
| docs/state_management/services_and_utils.md | ADDED | - | `latestWeightKg()` | S-13443 |
| docs/state_management/services_and_utils.md | ADDED | - | `liveKcal(` | S-13440, S-13441 |
| docs/state_management/services_and_utils.md | ADDED | - | `latestBodyWeightKg` | S-13444 |

Stale-term sweep (2026-11-09): `grep -rIn "Session Time"` over `docs` outside `docs/plans`, `docs/history`, `docs/releases` found nothing, so no REMOVED or MODIFIED row for the chip.

## Progress

| Item | What | Status |
|---|---|---|
| P1.1 | red `test/active_energy_live_test.dart` | Planned |
| P1.2 | service static + public weight | Planned |
| P1.3 | `WorkoutState.latestBodyWeightKg` | Planned |
| P1.4 | green P1 | Planned |
| P2.1 | red `test/session_live_calories_test.dart` | Planned |
| P2.2 | screen state, tick, chip, two bars | Planned |
| P2.3 | green P2 + neighbours | Planned |
| P3 | Docs delta rows | Planned |
