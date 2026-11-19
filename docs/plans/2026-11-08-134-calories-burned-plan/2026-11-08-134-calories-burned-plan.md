# Plan — 134: Calories burned in a session (134a: phone estimate and the Session Summary)

**Status**: built, reviewed (1 fix round) and verified by the lead 2026-11-09; uncommitted. Full suite `+7168 ~2` green, `flutter analyze` 181 (baseline). Open: owner device checks. 134b to 134e were built on 2026-11-09 (see the five plans beside this folder).
**Binding conventions**: `docs/global_conventions.md`, `docs/design_system.md` ("Shared pieces and rules per job").
**Base commit**: `ff398e1a7ec18409d9fc8c890bf35d2fde656e69` (branch `claude_develop`; the owner's tree is on that branch, no switch made).
**Evidence**: `2026-11-08-134-calories-burned-plan.evidence.md`; review: `...review.md` (beside this file).

## Overview

Owner request (2026-11-08): show the calories a session burned. Owner decisions, in the owner's words where it matters:

1. **Measured wins.** If the watch has active energy for a session, the phone shows that number and never estimates. Estimate only when the watch sent nothing. Same number on every surface.
2. **Estimate = modality-specific, exercise-agnostic** (owner, mid-turn). Custom exercises need no special case; every session has a modality or is Free Training.
3. **Active energy only** (above resting), so an estimate and a watch number mean the same thing.
4. **No body weight logged → show `—`**, no default weight.
5. **`~` before an estimate** (`~142 kcal`); a measured value has none.
6. **Saved at the end of the session**, not recomputed when body weight changes later.
7. **Session Summary**: Calories sits in the right half of the Effort row (where Change rating sits today); Change rating becomes a pen icon-only button inside the rating's own half.
8. **Fuel card** (Stats): `Training days: … kcal · … g protein`, `Rest days: …`, plus `Burned per session: ~310 kcal · 5 sessions` (average over the same 7 finished days). No "eaten minus burned" figure anywhere.

The lead split the work (scope budget: three tracks, phone / sync contract / watch):

| Unit | What | Where |
|---|---|---|
| **134a (this plan)** | the stored value, the estimate, the Session Summary row | phone |
| 134b | Fuel card wording + the burned line | phone, needs 134a |
| 134c | the watch's measured active energy reaches the phone (wire field, watch reads the total at session end, importer) | contract + watch + phone |
| 134d / 134e | phone active-session bar; watch rest screen running total + live feed | phone / watch |

Until 134c ships every session shows an estimate (`~`). The model and the screen already treat `measured` rows correctly (S-13407), so 134c adds no UI.

## Goal and acceptance

After a session ends the phone stores one active-energy value for it and the Session Summary shows it. Acceptance: S-13401 .. S-13412, as seeded; the architect's edge scenarios S-13414 (unknown modality id), S-13415 (zero/negative weight), S-13416 (set-only Free Training), S-13417 (a settle that throws) gate the same work.

## Decision Ledger

| ID | Decision | Backing |
|---|---|---|
| D-13401 | New model `SessionEnergy` (`sessionId`, `activeKcal` double unrounded, `source` `'estimated'` or `'measured'`, `bodyWeightKg` double? (the weight an estimate used; null on `measured`), `updatedAtMs`). One row per session, its own Hive box `session_energy` (key = sessionId), SQL table `app_session_energy` with `FOREIGN KEY (session_id) ... ON DELETE CASCADE`. It is NOT a `SensorSummary`: a summary is put-if-absent per (scope, target), its `source` CHECK allows only `'watch'` and it needs a heart rate or steps, so an estimate stored there would block the wrist's later session summary | scout sheet MODEL Q1, Q4; `models.dart` `SensorSummary`; `scripts/sqlite_schema.sql:1543` |
| D-13402 | Repository: `putSessionEnergy(SessionEnergy) -> Future<bool>` (upsert; returns false and writes nothing when a `measured` row exists and the new row is `estimated`; a `measured` row always replaces), `getSessionEnergy(String sessionId)`; every session delete removes the row (Hive `deleteSession` and its helper that already calls `_deleteSensorSummariesForSession`; Mock the same). Hive and Mock behave identically (parity test) | `hive_workout_repository.dart:3390-3447` (shape to copy), `mock_workout_repository.dart:2498` |
| D-13403 | Formula: `activeKcal = (MET − 1) × bodyWeightKg × hours`. MET by section: resistance **3.5**, cardio **7.0**, isometric **2.3**, sports **6.0**. The four numbers live in ONE map `kActiveEnergyMets` (new `lib/core/constants/active_energy.dart`), keyed by `ExerciseSection`; the modality id maps to its section (`resistance_lifting`→resistance, `cardio_endurance`→cardio, `isometric_stretching`→isometric, `sports`→sports) | owner decision 2; values are the lead's, owner-visible numbers, listed in the report |
| D-13404 | Hours: a session **with a modality** uses its whole duration (`endedAtMs − startedAtMs`, rests included: the activity tables' resistance and stretching figures already assume the rests) at that modality's MET. A **Free Training** session (`modality == null`) uses the per-section time split the Mix view already computes (`sessionTimeByModality`, measured seconds per section, Resistance takes the remainder) and sums `(MET − 1) × kg × section hours`. A rolling session has no duration: only its measured seconds count, and nothing measured → no row | `training_load.dart:191` `sessionTimeByModality`; `stats_progress_service.dart:916` `_sessionSplit`, `:942` `_measuredSecsFor`, `:980` `_dominantSectionFor` |
| D-13405 | The free-session split is reached through ONE new public method on `StatsProgressService`: `Future<Map<ExerciseSection, double>> sessionTimeBySectionFor(String sessionId)` that wraps `_sessionSplit`. Nothing re-implements the split. Only a Free Training session pays for it (it loads the history index once); modality sessions read no history | `stats_progress_service.dart:916`; the service's doc: "a caller that needs fresh data after a write constructs a new service" |
| D-13406 | Body weight: `repository.getLatestMeasurement('bodyweight')`, and the entry counts only when `unitId == MetricIds.unitKg` and `value > 0` (the guard `stats_progress_service.dart:2074` has; `ProfileState.latestBodyWeightKg` lacks it). No usable weight → no row is written (the screen reads `—`). The first estimate stores the weight it used in `bodyWeightKg`; a later recompute of an `estimated` row (D-13408) reuses that stored weight, so logging a new weight never rewrites an old session (owner decision 6) | scout INPUTS Q1.3, Q1.4 NOTICED |
| D-13407 | New `ActiveEnergyService(WorkoutRepository, StatsProgressService Function())` in `lib/core/services/active_energy_service.dart` with `Future<void> settle(String sessionId)`: loads the session; returns for an unfinished session; keeps a `measured` row untouched; otherwise computes D-13403..D-13406 and `putSessionEnergy`s an `estimated` row. All failures are caught: finishing a session never fails or waits on energy | `session_core_lifecycle.dart:8` `endSession` |
| D-13408 | Wiring in `SessionCore` (optional constructor argument like `_healthSync`, null in tests that do not care): `endSession` calls `settle(session.id)` after `updateSession` succeeds, inside its own try/catch outside the one that sets "Failed to end session"; `updateSessionEndTime` calls `settle` after its write (an edited duration changes an estimate; a `measured` row stays). Watch-run sessions end through `endSession` too (`watch_session_adoption_bridge.dart:852`), so they are covered | scout INPUTS Q4.2 |
| D-13409 | Read side: `SessionSummaryService.getSessionEnergy(sessionId)` returns `({int kcal, bool measured})?` (kcal rounded to whole at this boundary, null when no row) | `session_summary_service.dart:66` `getSessionHeartRate` (shape to copy) |
| D-13410 | Session Summary info card, Effort row (`session_summary_screen.dart:957-987`): `Row[ Expanded(effort pill with the pen button inside it, at its right edge), SizedBox(16), Expanded(_StatPill('Calories', …)) ]`. The Calories pill reads `~142 kcal` (estimated), `142 kcal` (measured), `—` (no row) and has no caption. It shows on every session including rolling ones (the Effort row is always visible). The pen is an `IconButton` with `tooltip: 'Change rating'` / `'Add rating'`, an explicit `shape`, a 48 dp minimum tap target, keeps `Key('omni_session_effort_rating_button')`, icon `Icons.edit_outlined` / `Icons.add`; it is no longer an `OmniUtilityButton`. The effort pill's own text and caption (`How hard the session felt`) stay | scout SCREENS Q1; `docs/design_system.md` "Button Variants" |
| D-13411 | The Calories pill refreshes when the open screen's session gets a `measured` row later (134c): the screen re-reads the energy where it re-reads heart rate (`_reloadHeartRateOnWristSummary`). 134a wires the re-read; its test seeds a `measured` row and fires `noteWristSummary` | `session_summary_screen.dart:239` |
| D-13412 | Whole-number display: `kcal.round()`; a value that rounds to 0 reads `0 kcal` (a real result), never `—` | decision of the lead |
| D-13413 | An unknown modality id (a `TrainingSession.modality` that names none of the four ids of D-13403 — e.g. a legacy constant like `'conditioning_mixed'`, which can arrive verbatim from a template's `focusModality`, `lib/core/services/routine_session_modality_backfill.dart:9`) is treated exactly like Free Training: per-section split from measured seconds, Resistance takes the remainder (the lead's answer, not yet seen by the owner). The three-branch order inside `ActiveEnergyService.settle` is: rolling → measured seconds only (nothing measured → no row); a modality `sectionForModality` names → whole duration at that MET; otherwise (Free Training or unknown id) → the per-section split of D-13405 | the lead's answer to Q-e; `lib/core/constants/modality.dart:14-19` (legacy ids exist), `test/watch_routine_focus_start_test.dart:304` (a wrist template can carry an arbitrary focus value); `mapModalityToActivityKind` (`lib/core/services/health_modality_mapper.dart`) resolves unknown ids through its `default` branch — the same convention |
| D-13420 | (fix round 1, review findings 1 and 2) `WatchSessionInbox` takes an optional `onSessionHistoryChanged(sessionId)` and calls it after every import pass with `pass.historyChanged`, inside its own try/catch; `main.dart` builds ONE `ActiveEnergyService` and gives it to `WorkoutState` and to the watch graph (`watch_sync_wiring.dart`), whose inbox gets `activeEnergy?.settle`. So a session the watch created (the phone held no row) gets its estimate, and a Free Training session priced before the wrist's timed entries arrived is priced again when they land. `settle` stays idempotent (a modality session recomputes the same value from the stored weight; a `measured` row is never touched). Replaces the A-1 claim that a late wrist entry never recomputes | review finding 1 (`watch_session_importer.dart:599-617`) and 2 (`watch_session_adoption_bridge.dart:852`, `_writeLadder`) |

## Scenarios

Fixtures: weight 80 kg unless said; every number re-derived by a throwaway script (the lead's, 2026-11-08).

| ID | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-13401 | resistance session, 3600 s, 80 kg, `endSession` | stored row: `estimated`, `activeKcal` 200.0 `[(3.5−1)×80×1]`, `bodyWeightKg` 80 | no row existed |
| S-13402 | isometric session 1102 s (the owner's 18m22s), 80 kg | 31.8355… stored; screen reads `~32 kcal` | no estimate |
| S-13403 | cardio 1800 s, 80 kg → 240.0; sports 5400 s, 70 kg → 525.0 | stored values as stated | no estimate |
| S-13404 | Free Training 3600 s, 80 kg; measured cardio 1200 s and isometric 600 s | 277.333… = 160 + 17.333 + 100 (cardio 6×80×1200/3600, isometric 1.3×80×600/3600, resistance remainder 1800 s 2.5×80×0.5) | no per-section sum |
| S-13405 | no bodyweight entry; and a latest entry with `unitId` `unit-lbs` | no row; screen `—`; a later `settle` after a kg entry is logged DOES write (the session is still finished) | n/a: guard for D-13406 (proven by mutating the unit check) |
| S-13406 | estimated row (80 kg) exists, then a 90 kg entry is logged, then the session duration is edited 1102 s → 1500 s | row recomputed with the stored 80 kg: 43.333…; `bodyWeightKg` still 80; and with no duration edit the row is unchanged after the 90 kg entry | no stored weight / recompute |
| S-13407 | a `measured` row (250.4) exists; `endSession` and a duration edit run | row untouched; `putSessionEnergy(estimated)` returns false and writes nothing; screen reads `250 kcal` with no `~` | no source rule |
| S-13408 | session deleted (`discardCurrentSession`) | its energy row is gone, Hive and Mock | no cascade |
| S-13409 | unfinished session, and a rolling session with nothing measured | no row for both; rolling with 600 s measured isometric → (2.3−1)×80×600/3600 = 17.333 | no lifecycle rule |
| S-13410 | repository parity on Mock AND Hive: put estimated, put measured (replaces), put estimated (refused, returns false), get, delete | identical results | the repository had no energy methods, so the test cannot even compile against the old code |
| S-13411 | Summary screen, standard session with rating 4 and an estimated row | Effort pill left with a pen (`Icons.edit_outlined`, tooltip `Change rating`, key unchanged) inside the left half; Calories pill right half `~32 kcal`; tapping the pen opens the rating sheet on the stored rating; an unrated session shows `Icons.add` / tooltip `Add rating`; the Calories pill's left edge is right of the pen's right edge | button was a labelled utility button beside the pill |
| S-13412 | the same screen: rolling session; session with no row; session with a late `measured` row arriving after open (`noteWristSummary`) | rolling shows the row with Calories; no row `—`; the pill updates to the measured figure without `~` | the screen had no Calories pill and no re-read of the energy when a wrist summary lands |
| S-13413 | SQL contract: `app_session_energy` round-trips a model row; refuses `source` outside the two values, negative kcal, a `measured` row with a weight, an `estimated` row without one | `test/db_seed_test.dart` group extended | no table |
| S-13414 | a session whose `modality` is a legacy id (`'conditioning_mixed'`), 3600 s, 80 kg, measured cardio 1200 s + isometric 600 s | stored 277.333… — the Free Training figure of S-13404, NOT a whole-duration estimate at any single MET | the seed had no branch for unknown ids |
| S-13415 | latest bodyweight entry `value` `0` (and again `−5`), `unitId` `unit-kg`, session finished 3600 s resistance | no row; screen `—` | D-13406's `value > 0` rule exists in no code today (`stats_progress_service.dart:2072-2076` checks the unit only), so the settle writes the check new — proven by mutating it |
| S-13416 | Free Training 3600 s, 80 kg, only set efforts (nothing measured) | resistance takes the remainder 3600 s → stored 200.0 | no remainder rule |
| S-13417 | a repository whose `putSessionEnergy` throws; `endSession` on a finished session | the session ends and is saved, no "Failed to end session", the energy row is absent (D-13407 swallows the failure) | no catch around the settle |
| S-13418 | a wrist session the phone does not hold: `session_end` `resistance_lifting` 3600 s at 80 kg through `WatchSessionInbox` with the callback | the finished session exists and an `estimated` row of 200.0 (weight 80); the same fixture through an inbox WITHOUT the callback stores none | the importer wrote a finished session and nothing settled it (review finding 1) |
| S-13419 | a wrist Free Training session (no modality) 3600 s with one finished cardio timed entry of 1200 s, 80 kg | stored 293.3333… = 160 (cardio 6 x 80 x 1200/3600) + 133.333 (remainder 2400 s at resistance) | the estimate saw no timed instance (review finding 2: all-resistance 200.0) |
| S-13420 | a second pass over an already applied session | the callback is not called again | n/a: guard of the `pass.historyChanged` condition (the lead proves it by mutation) |
| S-13421 | a callback that throws | the pass still imports the session and applies the end row | the call had no try/catch (the lead proves it by mutation) |

## Phases (outline; the architect expands)

| Phase | Agent | Write scope | Parallel |
|---|---|---|---|
| P1 data | crew-builder-data | `lib/data/models/models.dart`, `lib/data/repositories/**`, `scripts/sqlite_schema.sql`, `test/db_seed_test.dart`, new `test/session_energy_repository_test.dart`, `test/helpers/repository_harness.dart` only if the harness lists repositories | serial first |
| P2 logic | crew-builder-app | `lib/core/constants/active_energy.dart`, `lib/core/services/active_energy_service.dart`, `lib/core/services/stats_progress_service.dart` (one method), `lib/core/services/session_summary_service.dart`, `lib/state/workout/session_core*.dart`, `lib/state/workout/workout_state.dart`, `lib/main.dart`, tests | after P1 |
| P3 screen | crew-builder-app | `lib/features/session/session_summary_screen.dart`, `lib/widgets/buttons/omni_utility_button.dart` (doc comment only), tests listed below | after P2 |
| P4 docs | crew-docs-keeper | the Docs delta rows | after P3 |

**Parallelism.** P1 → P2A → P2B → P3 must run in this order (P2A cannot compile before P1's interface exists; P2B wires P2A's service; P3's screen needs P2B's injected service and the read-out). P4A and P4B touch disjoint doc files and could run together after P3, but they are small: run in order.

### P1 data (one crew-builder-data run)

Write scope: `lib/data/models/models.dart`, `lib/data/repositories/**`, `scripts/sqlite_schema.sql`, `test/db_seed_test.dart`, `test/session_energy_repository_test.dart`.

1. [ ] Add the red parity test — `test/session_energy_repository_test.dart` (new) · one body over the existing factories (`repository_harness.dart` already covers Mock + Hive; no harness edit): groups for S-13410 (put estimated, put measured replaces, put estimated refused returns false and writes nothing, get, read-your-write values) and S-13408 (both stores delete the row with the session). Plain `test()`, never `testWidgets` for a Hive write — inside FakeAsync a real Hive write never completes. Red: the interface has no energy methods, so the test does not even compile.
2. [ ] Add the red schema group — `test/db_seed_test.dart` · group `app_session_energy contract` — table exists beside `app_sensor_summary`, columns of D-13401, FK `ON DELETE CASCADE`, CHECKs refusing a bad `source`, negative kcal, a `measured` row with a weight, an `estimated` row without one. Red: no such table.
3. [ ] Add the model — `lib/data/models/models.dart` · `SessionEnergy` (after the `SensorSummary` section): fields of D-13401; constructor refuses an out-of-vocabulary `source`, a negative or non-finite kcal, `measured` with a weight, `estimated` without one; `sourceEstimated`/`sourceMeasured` constants; `toMap`/`fromMap` keys exactly the SQL column names `session_id`, `active_kcal`, `source`, `body_weight_kg`, `updated_at_ms`.
4. [ ] Append the interface methods — `lib/data/repositories/workout_repository.dart` · `putSessionEnergy(SessionEnergy) → Future<bool>`, `getSessionEnergy(String) → Future<SessionEnergy?>` (the interface ends at the sensor-summary block, ~:869).
5. [ ] Implement Hive — `lib/data/repositories/hive_workout_repository.dart`: box field beside `_sensorSummariesBox` (~:168), opened in `initialize()` beside `sensor_summaries` (~:241) as `session_energy`; `putSessionEnergy` check-then-put (a `measured` row refuses an `estimated` one, writes nothing); `getSessionEnergy` via `fromMap`.
6. [ ] Add the Hive cascade — `hive_workout_repository.dart` · `deleteSession`: `_sessionEnergyBox.delete(id)` beside the `_deleteSensorSummariesForSession(id)` call that already ends the method (~:1275).
7. [ ] Implement Mock — `lib/data/repositories/mock_workout_repository.dart` · map beside `_sensorSummaries` (~:141), identical put/get; cascade inside `deleteSession` (~:552) and cleared in `clear()` (~:1759).
8. [ ] Green the stored layer — the two test files of items 1-2 pass against both implementations.

Done criteria: `.github/copilot/scripts/macos/gateway.sh test` (files `test/session_energy_repository_test.dart`, `test/db_seed_test.dart`) green; `.github/copilot/scripts/macos/gateway.sh lint` shows no new issue compared with the plan's baseline count.
Predicted files: `lib/data/models/models.dart`, `lib/data/repositories/workout_repository.dart`, `lib/data/repositories/hive_workout_repository.dart`, `lib/data/repositories/mock_workout_repository.dart`, `scripts/sqlite_schema.sql`, `test/db_seed_test.dart`, `test/session_energy_repository_test.dart`. Nothing else may change. (`test/helpers/repository_harness.dart` needs no change: `harnessFactories` wraps Mock and Hive already.)

### P2A logic part A — compute + read (one crew-builder-app run)

Write scope: `lib/core/constants/active_energy.dart`, `lib/core/services/active_energy_service.dart`, `lib/core/services/stats_progress_service.dart`, `lib/core/services/session_summary_service.dart`, `test/active_energy_service_test.dart`.

1. [ ] Add the red service test — `test/active_energy_service_test.dart` (new; over `harnessFactories`, plain `test()`): fixtures S-13401 (3600 s resistance, stored 200.0, `bodyWeightKg` 80), S-13402 (isometric 1102 s, stored `31.8355…` unrounded; read rounds), S-13403, S-13404, S-13405 (no entry; lbs entry; then kg entry → row written), S-13406 (recompute with the stored 80; a new 90 kg entry changes nothing without an edit), S-13407 (measured untouched, put refused), S-13409 (unfinished; rolling nothing-measured; rolling 600 s isometric → 17.333…), S-13414 (unknown id), S-13415 (0 and −5 kg), S-13416, plus read-side `getSessionEnergy` rounding and `measured` flag. Red: the constants file and `ActiveEnergyService` do not exist.
2. [ ] Add the constants — `lib/core/constants/active_energy.dart` (new) · `kActiveEnergyMets` (D-13403's four numbers) and `ExerciseSection? sectionForModality(String modality)` — the four ids only; anything else returns null (the Free Training branch of D-13413). This map is new; no second one exists (Q-d).
3. [ ] Add the wrapper — `lib/core/services/stats_progress_service.dart` · `sessionTimeBySectionFor` (public; wraps `_sessionSplit`, :916): loads the history index once; an unknown or unfinished session id returns an empty map.
4. [ ] Add the service — `lib/core/services/active_energy_service.dart` (new) · `ActiveEnergyService.settle`: the three-branch order of D-13404 + D-13413 (rolling check first, whatever the modality value); weight per D-13406 (a stored estimated-row weight first, then `getLatestMeasurement('bodyweight')` with the `unit-kg` and `value > 0` guard — paid for by S-13415); no usable weight → no row; a `measured` row → return; every failure swallowed.
5. [ ] Add the read-out — `lib/core/services/session_summary_service.dart` · `getSessionEnergy` after `getSessionHeartRate` (:84): `({int kcal, bool measured})?`, kcal `.round()` here only.
6. [ ] Green part A — `test/active_energy_service_test.dart` passes.

Done criteria: `.github/copilot/scripts/macos/gateway.sh test` (files `test/active_energy_service_test.dart`, plus `test/db_seed_test.dart` and `test/session_energy_repository_test.dart` still green) ; lint as P1.
Predicted files: the five write-scope files. Nothing else may change.

### P2B logic part B — wire the session lifecycle (one crew-builder-app run)

Write scope: `lib/state/workout/session_core.dart`, `lib/state/workout/session_core_lifecycle.dart`, `lib/state/workout/workout_state.dart`, `lib/main.dart`, `test/active_energy_lifecycle_test.dart`.

1. [ ] Add the red wiring test — `test/active_energy_lifecycle_test.dart` (new; `WorkoutState` over the Mock repository): `endSession` stores S-13401's row; a `updateSessionEndTime` edit 1102 s → 1500 s recomputes an estimated row with the stored weight (S-13406); a `measured` row stays (S-13407); `discardCurrentSession` deletes the row (S-13408); a repository whose `putSessionEnergy` throws leaves the session saved with no "Failed to end session" (S-13417). Red: `WorkoutState` has no way to inject the service yet.
2. [ ] Add the optional argument — `lib/state/workout/session_core.dart` · `SessionCore` constructor (:99): `ActiveEnergyService? activeEnergy` beside `_healthSync`, stored as `_activeEnergy`; null in tests that do not care.
3. [ ] Settle at end — `lib/state/workout/session_core_lifecycle.dart` · `endSession` (:8): `await _activeEnergy?.settle(...)` inside its own `try`/`catch` swallowing everything, placed after the persistence block succeeded and before the health write (D-13408; S-13417 proves the isolation).
4. [ ] Same for the duration edit — `session_core_lifecycle.dart` · `updateSessionEndTime` (:161): `settle` after its own write, same shield.
5. [ ] Thread it through — `lib/state/workout/workout_state.dart` · `WorkoutState` constructor (:43): optional named `activeEnergy`, passed into `SessionCore` at :65.
6. [ ] Wire the app — `lib/main.dart` · the `WorkoutState` construction (~:393): `activeEnergy: ActiveEnergyService(repository, () => StatsProgressService(repository))` (a fresh `StatsProgressService` per settle, per that service's fresh-data rule); green the wiring test.

Done criteria: `.github/copilot/scripts/macos/gateway.sh test` (files `test/active_energy_lifecycle_test.dart`, and the P2A files re-run) ; lint as P1.
Predicted files: the five write-scope files. Nothing else may change.
Note on D-13407's "never fails or waits": this plan awaits the settle inside the swallowing try/catch so an `endSession` test can read its write deterministically (S-13401 lifecycle test); the wait is bounded by one repository read and at most one history index. Flagged to the lead as OQ-4.

### P3 screen (one crew-builder-app run)

Write scope: `lib/features/session/session_summary_screen.dart`, `lib/widgets/buttons/omni_utility_button.dart`, `test/session_summary_calories_test.dart`, `test/session_summary_effort_row_test.dart`, `test/rating_first_answer_summary_test.dart`, `test/header_standardization_test.dart`, `test/watch_session_summary_integration_test.dart`.

1. [ ] Add the red screen tests — `test/session_summary_calories_test.dart` (new; Mock harness copied from `test/session_summary_heart_rate_test.dart` — `_freshRepo`, `_appTheme`, `_useTallSurface`, `_buildSessionSummaryScreen`; pill reads via the `_pillValue` helper of `test/session_summary_effort_row_test.dart`): S-13411 (rated: pen `Icons.edit_outlined`, tooltip `Change rating`, key kept, tap opens the sheet on the stored rating; unrated: `Icons.add` / `Add rating`; Calories pill's left edge right of the pen's right edge), S-13402 string (`~32 kcal`), S-13407 string (`250 kcal`, no `~`), S-13412 (rolling shows the row; no row `—`; a late `measured` row lands through `noteWristSummary` and the pill updates without `~`). Red: no Calories pill.
2. [ ] Move the finder to key/tooltip — `test/session_summary_effort_row_test.dart`: `Change rating`/`Add rating` text finders become key `omni_session_effort_rating_button` + tooltip finders.
3. [ ] Same — `test/rating_first_answer_summary_test.dart` (:123, :170).
4. [ ] Same — `test/header_standardization_test.dart` (:1423).
5. [ ] Same — `test/watch_session_summary_integration_test.dart` (:345, :355, :380, :415-417). Items 2-5 are not a drive-by: the shape change breaks exactly these finders, and they must be updated in the same change as item 6.
6. [ ] Move the row and add the read — `lib/features/session/session_summary_screen.dart`: `_buildSessionInfoCard` becomes `Row[ Expanded(effort pill with the pen IconButton at its right edge — tooltip `Change rating`/`Add rating`, explicit shape, ≥48 dp target, key kept, `Icons.edit_outlined`/`Icons.add`) , SizedBox(16), Expanded(_StatPill('Calories', …)) ]`; `_loadAsyncData` reads `getSessionEnergy` beside the heart rate; `_reloadHeartRateOnWristSummary` re-reads the energy too (D-13410, D-13411).
7. [ ] Doc comment only — `lib/widgets/buttons/omni_utility_button.dart`: class doc stops naming the Session Summary among its uses; no code change.
8. [ ] Green the screen — all five test files pass.

Done criteria: `.github/copilot/scripts/macos/gateway.sh test` (the five files of this phase + the P2 files re-run) ; lint as P1.
Predicted files: the seven write-scope files. Nothing else may change.

### P4A docs part A (one crew-docs-keeper run)

Write scope: `docs/session_summary.md`, `docs/state_management/services_and_utils.md`, `docs/README.md`, `docs/state_management.md`. Items are rows 1, 2, 8, 9, 10, 11, 13, 14 of the Docs delta table below, applied verbatim from the table.

Done criteria: the eight sentences read exactly as the table's New markers; no doc file exceeds its 52 KB limit; `gateway.sh lint` count unchanged.
Predicted files: the four docs. Nothing else may change.

### P4B docs part B (one crew-docs-keeper run, after P4A)

Write scope: `docs/design_system.md`, `docs/widget_catalog/layout_and_inputs.md`, `docs/data_models.md`, `docs/db_integration.md`. Items are rows 3, 15, 4, 5, 6, 12.

Done criteria: as P4A for the six sentences.
Predicted files: the four docs. Nothing else may change.

## Readers to update (found by the scouts, not by tests)

- Tests that find the button by its text (`find.text('Change rating')` / `'Add rating'`) and must find it by key or tooltip: `test/session_summary_effort_row_test.dart` (37 matches), `test/rating_first_answer_summary_test.dart` (123, 170), `test/header_standardization_test.dart` (1423), `test/watch_session_summary_integration_test.dart` (345, 355, 380, 415-417). `test/omni_utility_button_test.dart` uses `Change rating` only as a sample label of the piece: untouched.
- `SessionCore` constructor callers: `workout_state.dart` and every test that builds one (grep `SessionCore(`); the new argument is optional.
- Every repository implementation of the interface (Hive, Mock, and any fake in `test/helpers`): grep `implements WorkoutRepository`.
- `deleteSession` and every path that deletes a session row in both repositories (the scouts name `_deleteSensorSummariesForSession`; the energy row dies at the same call sites).

## Input-reality checklist

1. **Writers**: body weight is written by the Profile screen (`profile_screen.dart:1032`, kg canonical, lbs input converted by `UnitFormatter.toCanonicalWeight`) and the Health import (`health_sync_service.dart:260`, kg); no other writer; `latestBodyWeightKg` ignores the unit, the stats service guards it: this plan uses the guarded form (D-13406). Session duration and modality come from `TrainingSession`; measured seconds from timed and round instances (the Mix code).
2. **Lifecycle**: unfinished → no row; rolling → measured seconds only; imported watch sessions end through `endSession`; an edited duration recomputes an `estimated` row (D-13408); late wrist entries after the end do NOT recompute (assumption A-1: for a modality session the whole duration is used, so only Free Training could move, and by a few percent); deleted → the row goes with the session.
3. **Settings**: kg/lb display setting does not matter (kg stored); the Effort Rating toggle does not touch this row (the Effort row has no toggle today).
4. **Time**: only a millisecond difference; no calendar logic.
5. **Cost**: one repository write per session end; Free Training adds one history-index load (D-13405).
6. **Words** (owner-visible): `Calories`, `~142 kcal`, `—`, tooltips `Change rating` / `Add rating`. Old wording found by grep (`Change rating`, `Add rating`, `omni_session_effort_rating_button`): `docs/session_summary.md:33`, `docs/design_system.md:310`, `docs/widget_catalog/layout_and_inputs.md:154`, `docs/watch-app-setup-and-qa.md:556` (prose "offers Add rating": still true as a tooltip, left), `session_summary_screen.dart:855` comment, `omni_utility_button.dart` doc comment.
7. **Competition**: the Effort row's right half was the button; now Calories. Rolling sessions show it too.

## Feature invariants (the architect's, one line each)

- A `measured` row is never rewritten: `putSessionEnergy` refuses an `estimated` row over it and writes nothing (S-13410); `settle` returns before computing (S-13407).
- An `estimated` row stores the weight it used in `bodyWeightKg`; every later recompute reuses it, so a weight logged after the end never rewrites a session (S-13406).
- `settle` never fails a session end and never raises through it: every failure swallowed, no error text set (S-13417).
- Rounding happens only at the read boundary (`getSessionEnergy`, the screen); storage keeps the unrounded double (S-13402).
- Hive and Mock behave identically on `session_energy`, and both cascade on every session-delete path (S-13410, S-13408).
- `settle` checks rolling before the modality lookup, so a rolling session never reads its wall duration whatever its `modality` value (D-13404, D-13413; the branch order in P2A item 4 — no fixture can produce the risky combination today, see OQ-4).
- The energy row's lifecycle equals the session's: unfinished → none, deleted → gone (S-13409, S-13408).

## Existing-functionality impact (file · what reads it today · effect · guarded by)

| Touch | What reads it today | Effect | Guarded by |
|---|---|---|---|
| `lib/data/models/models.dart` (`SensorSummary` ~:2515-2700) | the watch importer and the wrist adaptor store summaries; `getSensorSummariesBySession` bulk-reads them (`docs/db_integration.md` "Bulk per-session read") | `SessionEnergy` added beside; `SensorSummary` untouched | S-13413 |
| `lib/data/repositories/workout_repository.dart` (:855-869) | two implementers (Q-c), all app services | two methods appended at the end of the interface | S-13410 |
| `hive_workout_repository.dart` (:168, :241; `deleteSession` ~:1209-1280 already cascades via `_deleteSensorSummariesForSession` :3440) | `deleteSession` is the discard and calendar-delete path | box + methods + one cascade line | S-13410, S-13408 |
| `mock_workout_repository.dart` (:141; cascade :552; `clear()` ~:1759) | every test harness and fake (`extends MockWorkoutRepository`) | map + methods + cascade + clear entry | S-13410, S-13408 |
| `scripts/sqlite_schema.sql` (:1543-1570) | `test/db_seed_test.dart` executes schema + seed as SQL and asserts the contract | one table (FK cascade, CHECKs) after `app_sensor_summary`; no seed rows | S-13413 |
| `stats_progress_service.dart` (:916 `_sessionSplit`; :1515 `_sectionForKind`; :2072-2076 weight guard) | stats and signals pages (`docs/signals.md:240`), distance_source | one public wrapper appended; no private code touched | S-13404 |
| `session_summary_service.dart` (:66-84 `getSessionHeartRate`) | the summary screen's `_loadAsyncData` | one method appended beside it | S-13409 |
| `session_core.dart` (:99), `session_core_lifecycle.dart` (`endSession` :8, `updateSessionEndTime` :161), `workout_state.dart` (:43, only construction site :65), `main.dart` (:393) | end and duration-edit paths; the health write already sits outside the failure catch | one optional argument, two settle calls | S-13417, S-13401 |
| `session_summary_screen.dart` (:217-330; `_buildSessionInfoCard` 848-988) | the effort-row, rating-first, header and watch-integration tests | Effort row layout, energy read, wrist-refresh | S-13411, S-13412 |
| `omni_utility_button.dart` | `test/omni_utility_button_test.dart` (uses `Change rating` only as sample text) and the food form | doc comment only | S-13411 |
| watch (`lib/watch/`, `watch/watchos`) and the wire | 134c only — no energy field exists on the wire (scout WIRE) | untouched; no test of this plan reaches them | — |

A new entry in a shared registry: the two interface methods are the only compile-wide ripple — every fake under `test/helpers` extends `MockWorkoutRepository` and inherits, so no fake file is touched (the search: no test file declares `implements WorkoutRepository`).

## Phase 0 red tests (written first in each phase; each red for a stated reason)

| Guard | Test (file · what) | Harness | Red at the base commit because |
|---|---|---|---|
| S-13410, S-13408 | `test/session_energy_repository_test.dart` (new) | existing factories (`harnessFactories`), plain `test()` | the interface has no energy methods; the implementations cannot compile against it |
| S-13413 | `test/db_seed_test.dart` · `app_session_energy contract` | SQL execution (the existing :562 pattern) | no such table |
| S-13401…S-13409, S-13414, S-13415, S-13416 | `test/active_energy_service_test.dart` (new) | `harnessFactories`, plain `test()` — settle really writes Hive, so never inside `testWidgets` | `active_energy.dart` and `ActiveEnergyService` missing |
| S-13401, S-13406…S-13408, S-13417 | `test/active_energy_lifecycle_test.dart` (new) | `WorkoutState` over the Mock repository | no `activeEnergy` argument exists to inject a service |
| S-13402/07/11/12 strings and layout | `test/session_summary_calories_test.dart` (new) | the Mock harness of `test/session_summary_heart_rate_test.dart` (`_freshRepo`, `_appTheme`, `_useTallSurface`, `_buildSessionSummaryScreen`; `_pillValue` from `test/session_summary_effort_row_test.dart`) | no Calories pill; the pen is a labelled button; key finders still work but tooltip/icon assertions fail |
| the S-3211/S-3212 reader files | updated in P3 items 2-5, same change as the layout move | as-is | — |

Red-proving: `.github/copilot/scripts/macos/gateway.sh prove-red <base-ref> test -- <files>` for each new file; a guard that could pass unchanged must fail by construction. Note: a red Mock group can leave the Hive group hanging behind it in the same file — fix the red group first instead of re-running the file.

## Code questions of the brief (answered with the search that backs each)

**(a) `StatsProgressService` construction cost.** The constructor is `StatsProgressService(this._repository)` (`stats_progress_service.dart:87`) and only assigns — constructing one per settle is safe, and `_loadHistory` (:108-150) has no single-session variant; it loads every session, segment, effort, observation, timed and round instance plus one `getSensorSummariesBySession()` await, cached per instance. So the free-session path of D-13405 pays one full index per settle, and the settle factory hands it a fresh service (that service's own doc: a caller that needs fresh data constructs a new one). Prediction in A-1 follows the same source.

**(b) Wiring sites.** `WorkoutState` builds its `SessionCore` at `workout_state.dart:65` — the only construction site found. The `WorkoutState` constructor (:43) takes optional named arguments (`healthSync`, `watchLateEntryRecovery`, `clock`, `wristRunsSession`, `screenAwake`) passed from `main.dart:393-401`. The plan adds `activeEnergy` beside `healthSync` in all three; tests building `WorkoutState(repo)` keep working (null → endSession just skips the settle branch).

**(c) Interface implementers.** Exactly two in `lib/`: `HiveWorkoutRepository` (:43) and `MockWorkoutRepository` (:52) — the search over `implements WorkoutRepository`. Every fake under `test/helpers` extends `MockWorkoutRepository` and inherits the concrete methods, so the two abstract methods touch exactly those two files.

**(d) A modality-id → `ExerciseSection` map to reuse?** No. The four modality ids appear in twelve `lib/` files and none of them also contains `ExerciseSection`. What exists and is close: `_sectionForKind` (`stats_progress_service.dart:1515-1525`) maps effort KINDS (set/timed/hold/round) to sections, and `mapModalityToActivityKind` (`lib/core/services/health_modality_mapper.dart`) maps modality ids to `HealthActivityKind` — not sections. D-13403's map is therefore new (see OQ-2); it lives beside `kActiveEnergyMets` in `lib/core/constants/active_energy.dart`.

**(e) Other modality values in real data?** Yes. `lib/core/constants/modality.dart:14-19` keeps legacy ids (`strength_resistance`, `skill_technique`, `conditioning_mixed`, `mobility_flexibility`, `recovery_rehab`, `competition_match`); `TrainingSession.modality` receives a template's `focusModality` verbatim (`routine_session_modality_backfill.dart:9`, its backfill step 18), and a wrist template can carry an arbitrary focus value (`test/watch_routine_focus_start_test.dart:304`). The settle uses the legacy ids nowhere directly — they fall into the Free Training branch (D-13413).

## Progress

Baseline before building (2026-11-08, base commit above): `flutter analyze` 181 issues, 0 errors (pre-existing info notices).
Scope guard at plan acceptance (lead, by hand): 4 implementation phases, 17 scenarios, 15 docs rows, one track (phone); one soft signal only, so no split.

| Item | What | Status |
|---|---|---|
| P1.1 | red parity test `test/session_energy_repository_test.dart` | Planned |
| P1.2 | red schema group `test/db_seed_test.dart` | Planned |
| P1.3 | `SessionEnergy` model `lib/data/models/models.dart` | Planned |
| P1.4 | interface methods `lib/data/repositories/workout_repository.dart` | Planned |
| P1.5 | Hive box + methods `hive_workout_repository.dart` | Planned |
| P1.6 | Hive delete cascade | Planned |
| P1.7 | Mock map + methods + cascade + clear | Planned |
| P1.8 | green the stored layer | Planned |
| P2A.1 | red service test `test/active_energy_service_test.dart` | Planned |
| P2A.2 | constants `lib/core/constants/active_energy.dart` | Planned |
| P2A.3 | `sessionTimeBySectionFor` `stats_progress_service.dart` | Planned |
| P2A.4 | `ActiveEnergyService.settle` | Planned |
| P2A.5 | `getSessionEnergy` `session_summary_service.dart` | Planned |
| P2A.6 | green part A | Planned |
| P2B.1 | red wiring test `test/active_energy_lifecycle_test.dart` | Planned |
| P2B.2 | `SessionCore` argument | Planned |
| P2B.3 | settle at `endSession` | Planned |
| P2B.4 | settle at `updateSessionEndTime` | Planned |
| P2B.5 | `WorkoutState` passthrough | Planned |
| P2B.6 | wire `main.dart`, green | Planned |
| P3.1…P3.5 | the five screen test files red-then-updated | Planned |
| P3.6 | Effort row layout + energy read + wrist refresh | Planned |
| P3.7 | `omni_utility_button.dart` doc comment | Planned |
| P3.8 | green the screen files | Planned |
| P4A | docs rows 1, 2, 8, 9, 10, 11, 13, 14 | Planned |
| P4B | docs rows 3, 15, 4, 5, 6, 12 | Planned |

## Open questions

- **OQ-1 — the seeded D-13406 overclaims the existing guard.** It says the guard at `stats_progress_service.dart:2074` already has the `value > 0` rule; read this run, `latestBodyWeightKg` (:2072-2076) checks `entry == null || entry.unitId != MetricIds.unitKg` only. Kept as written; S-13415 stands as the guard's test and P2A item 4 writes the check new.
- **OQ-2 — D-13403 "Reuse it; do not add a second one"** presupposes an existing modality→section map; none exists (Q-d for the search). Not a contradiction in substance (the one maps kinds, not ids, in a different file for a different consumer); recorded here so the builder does not hunt for it.
- **OQ-3 — D-13407's "never fails or waits on energy".** P2B awaits the settle inside a swallowing try/catch (bounded by one repository read and at most one history index); if the lead insists on fire-and-forget, the lifecycle tests of S-13401/S-13406 need a settle-completion signal instead — the choice is visible before P2B runs.
- **OQ-4 — a rolling session with a non-null modality**: whether any writer today can produce that combination was not checked this run (no writer in the scout sheets suggests it); the settle branch order defends the case regardless, but it has no fixture-backed scenario. If the lead wants one, the fixture must construct the stored row directly — which no current writer does.
- **OQ-5 — A-1's "by a few percent"**: not re-derived this run; it names no test either, deliberately — the guard for the edge is the guard's absence (late wrist entries never recompute an estimate).

## Docs delta (the table)

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| docs/session_summary.md | MODIFIED | `once a rating exists and` | `pen button with the tooltip` | S-13411 |
| docs/session_summary.md | ADDED | - | `Calories pill` | S-13402, S-13407, S-13412 |
| docs/design_system.md | MODIFIED | `(Change rating on the Session` | `(the package-serving switch on the food form)` | S-13411 |
| docs/widget_catalog/layout_and_inputs.md | MODIFIED | `Used by Change rating /` | `Used by the package-serving switch on the food form` | S-13411 |
| docs/data_models.md | ADDED | - | `SessionEnergy` | S-13410 |
| docs/db_integration.md | ADDED | - | `app_session_energy` | S-13413 |
| docs/state_management/services_and_utils.md | ADDED | - | `ActiveEnergyService` | S-13401, S-13404 |
| docs/session_summary.md | MODIFIED | `an outlined Utility button with an edit/plus icon` | `an icon-only pen IconButton inside the effort pill` | S-13411 |
| docs/session_summary.md | MODIFIED | `the EFFORT row for every session` | `the EFFORT row with its Calories pill for every session` | S-13411 |
| docs/session_summary.md | MODIFIED | `then the EFFORT row (rolling sessions` | `then the EFFORT row with its Calories pill (rolling sessions` | S-13412 |
| docs/state_management/services_and_utils.md | ADDED | - | `getSessionEnergy` | S-13409 |
| docs/db_integration.md | ADDED | - | `putSessionEnergy` | S-13410 |
| docs/README.md | MODIFIED | `RoutineSessionService, SessionSummaryService, StatsProgressService,` | `RoutineSessionService, SessionSummaryService, ActiveEnergyService, StatsProgressService,` | D-13407 |
| docs/state_management.md | MODIFIED | `` `SessionSummaryService`, `HealthSyncService` `` | `SessionSummaryService`, `ActiveEnergyService`, `HealthSyncService` | D-13407 |
| docs/design_system.md | MODIFIED | `two migrated sites keep their keys` | `the food form keeps its key (`food_form_package_link`); the pen keeps `omni_session_effort_rating_button`` | S-13411 |
| docs/state_management/services_and_utils.md | ADDED | - | `after an inbox pass that changed a session's history` | S-13418, S-13419, D-13420 |

The architect completes the table: the other sentences of `session_summary.md` that describe the info card (lines 10, 57), `docs/README.md` if it lists models, and the stale-term sweep above. — Completed 2026-11-08 by the architect (rows 8-15). `docs/watch-app-setup-and-qa.md:556` ("offers Add rating") stays true as a tooltip and gets no row; `docs/README.md` models line is row 13; no other stale hit found in the sweep (searched `Change rating`, `Add rating`, `omni_session_effort_rating_button`, `SensorSummary`-adjacent model lists).

## Assumption Log

| ID | Assumption | Why |
|---|---|---|
| A-1 | (revised in fix round 1) a late wrist entry does recompute an estimate, through the inbox pass (D-13420); an edited duration does too (D-13408); a weight logged later never does | the review showed a wrist-run Free Training session would stay all-resistance without it |
| A-2 | The four MET values are the lead's defaults and the owner has not seen the exact numbers | the owner asked for the principle; values sit in one map |
