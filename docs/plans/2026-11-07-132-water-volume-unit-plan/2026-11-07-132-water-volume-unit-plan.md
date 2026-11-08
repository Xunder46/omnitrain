# Plan — 132: the water tracker shows the day's total in the user's volume unit (132a phone; 132b wire and watch planned only)

**Status**: seeded by the lead (2026-11-07), not built. Base commit in `.work/2026-11-07-132-water-volume-unit/base.txt`.
**Binding conventions**: `docs/global_conventions.md`, `docs/design_system.md`.
**Evidence**: `2026-11-07-132-water-volume-unit-plan.evidence.md` beside this file. Review: `…review.md`.

## Overview

Today the water control on the calorie-ring card shows a glass icon, a 9 pt `250 ml` caption and a bare glass count. Nobody
who has been told "drink 2 or 3 litres" (or "64 oz") can read progress off a glass count. The owner's decisions
(2026-11-07, chat): show the running total; **no daily target**; **no bottle sizes**; the unit follows the Units setting
(ml / L for metric, fl oz for US) **on the phone and on the watch**.

Two PRs (scope budget: two tracks, phone and contract+watch):

- **132a (this plan, built first)**: the Volume unit setting, the total on the phone's control, the per-tap step per unit.
- **132b (planned only, after 132a lands)**: `water_down` carries the day's ml, `preferences_down` carries the volume unit, the wrist
  shows and steps in it. Its decisions are in the ledger (D-13220…) so they are not lost; its scenarios are written when it is seeded.

Until 132b lands, a US user's phone steps 8 fl oz while the wrist still counts whole 250 ml glasses (its count is `volumeMl ~/ 250`),
so the wrist can read one glass low after a few taps. A metric user sees no change on the wrist. Accepted for the gap (A-2).

## Goal and acceptance

**Revision 1 (2026-11-08) replaces point (1): there is no Volume setting and no Volume row; the unit follows the Weight setting (D-13225).** Original text: 132a: (1) Settings > Preferences has a Volume row (`ml` / `fl oz`), default `ml`, applied at once like every unit. (2) The water
control's big number is the day's total in that unit (`750 ml`, `1.5 L`, `48 oz`), the caption under the icon is the per-tap step
(`250 ml` or `8 oz`), minus and plus step by it. (3) Stored water stays ml; switching the unit rewrites nothing and the screen
changes at once, even when the Nutrition screen was open behind Settings. (4) The wrist's taps are applied by the phone at the
phone's current step. (5) VoiceOver/tooltips say the amounts (`Add 250 milliliters`). Acceptance: S-13201…S-13210; S-13211 is the
lead's layout probe; the owner's device checks are marked `(owner)` in Progress.

## Decision Ledger

| ID | Decision | Backing |
|---|---|---|
| D-13201 | New `SettingsState.preferredVolumeUnit`, `'ml'` or `'floz'`, default `'ml'`, key `preferred_volume_unit`, normalised like distance (`'fl oz'`, `'floz'`, `'oz'` any case → `'floz'`, everything else → `'ml'`); a Volume row in `_MeasurementsSection` after Distance, subtitle `Used for water` | owner 2026-11-07; pattern `settings_state.dart` `setPreferredDistanceUnit` / `_loadFromPrefs`, `settings_screen.dart` Distance row |
| D-13202 | Stored water is ml only; the unit changes display and step, never storage | `water_constants.dart` header; `data_models.md` water section |
| D-13203 | Step per tap: ml unit 250 ml (`kWaterGlassMl`, unchanged), fl oz unit 237 ml (`kWaterOzStepMl`, 8 fl oz rounded; 8 × 29.5735 = 236.59). One owner: `waterStepMlFor(unit)` in `water_constants.dart`; an unknown or null unit is 250 | lead's recommendation in chat 2026-11-07, owner did not object (A-1); arithmetic re-derived (below) |
| D-13204 | Total text (ml unit): under 1000 ml `N ml`; from 1000 ml litres with at most two decimals, trailing zeros dropped (`1 L`, `1.25 L`, `1.5 L`, `1.76 L`); fl oz unit: whole ounces `N oz` (`ml / 29.5735295625`, `round()`). Compact text says `oz`; Settings and spoken text say `fl oz` / `fluid ounces`. Spoken: `N milliliters`, `1 liter`, `1.5 liters`, `N fluid ounces`, singular at exactly 1 | lead; table below |
| D-13205 | `NutritionState` takes an optional `SettingsState? settings` (named, default null = ml); exposes `waterVolumeUnit` and `waterStepMl`; adds a listener that notifies only when the normalised volume unit changed; `dispose` removes it. `lib/main.dart` passes `settingsState`. Other construction sites (tests, debug mains) are untouched | `main.dart:339`; keeps `CalorieRingCard(nutritionState:)` callers (8 test sites) unchanged |
| D-13206 | `increment/decrementWaterForDate` and `applyWatchWaterTap` use `waterStepMl` (decrement still floors at 0 ml) | `nutrition_state.dart` 111, 127, 150 (the only writers of water; `grep saveWaterVolumeForDate\|applyWaterTap` in `lib/`) |
| D-13207 | `NutritionState.waterTodayGlasses` is deleted (the phone no longer shows a glass count); its tests assert on `waterTodayMl`. `waterGlassesFor` and `kWaterGlassMl` stay: the wire's `glasses` still uses them until 132b | `watch_reference_sync.dart:738`; readers listed in the Readers section |
| D-13208 | `WaterTrackerControl` keeps its shape (icon over caption, minus, number slot, plus) and its keys; the number slot shows the total, the caption shows the step; the control takes `volumeMl` and `volumeUnit` and formats through `UnitFormatter` (pure helpers, no state access) | `water_tracker_control.dart`; keys `water_tracker_label`, `water_tracker_count` kept |
| D-13209 | Helpers live in `UnitFormatter` (the app's one units file): `normalizeVolumeUnit`, `volumeLabelForUnit` (`ml` / `fl oz`), `formatWaterTotal(int ml, String? unit)`, `formatWaterSpoken(int ml, String? unit)`, `waterStepLabel(String? unit)` (`250 ml` / `8 oz`) | `unit_formatter.dart` has weight, distance, height and no volume |
| D-13210 | No water target, no bottle or glass-size choice | owner 2026-11-07 |
| D-13220 | (132b) `water_down.payload.volumeMl` (integer ≥ 0, required) replaces `glasses`; the wrist keeps no glass count | contract change rides with its first consumer |
| D-13221 | (132b) `preferences_down.payload.volumeUnit` optional, enum `ml`, `floz`; absent means the wrist reads ml (same rule as weight/distance) | `preferences_down.schema.json` `weightUnit` |
| D-13222 | (132b) The wrist shows `volumeMl` of the frame plus its unconfirmed taps × the step of the unit it holds; the step table and the text rules are one JSON contract file under `watch/contract/` read by the Dart and Swift tests | `watch_effort_rating_contract.json` pattern |
| D-13223 | (132b) A wrist tap stays "one glass, add or remove" on the wire; the phone applies it at the phone's unit at apply time. A unit switched on the phone reaches the wrist at its next sync, so taps in between are valued at the old step on the wrist until the frame corrects them | A-2 |
| D-13224 | (132b) The wrist bar redraws when new units arrive, not only on the minute timeline | `WatchSyncOrchestrator.swift:208` applies preferences without announcing water |
| D-13225 | **Revision 1 (owner, 2026-11-08; supersedes D-13201 and D-13221).** No new setting. The water unit follows the existing Weight preference: `lbs` gives fl oz, `kg` gives ml. `UnitFormatter.volumeUnitForWeightUnit(String? weight)` is the one mapping (`normalizeWeightUnit(weight) == 'lbs'` gives `'floz'`, everything else `'ml'`). Removed: `SettingsState.preferredVolumeUnit`, `setPreferredVolumeUnit`, the key `preferred_volume_unit`, the Volume row, `UnitFormatter.volumeLabelForUnit` | owner chat 2026-11-08; `unit_formatter.dart` `normalizeWeightUnit`; `weightUnit` already reaches the wrist in `preferences_down` |
| D-13226 | `NutritionState.waterVolumeUnit` is `volumeUnitForWeightUnit(_settings?.preferredWeightUnit)`; the listener still notifies only when the derived unit changes (kg to lbs or back), never for another setting | D-13205, `nutrition_state.dart` `_onSettingsChanged` |
| D-13227 | (132b) the wire needs no `volumeUnit`: the wrist derives its unit from the `weightUnit` it already holds (absent: kg, so ml) with the same mapping, pinned by one contract table read by Dart and Swift tests | D-13222; `WatchPhonePreferences.units` |
| D-13228 | The Weight row's subtitle (`Used for exercises and volume`) is left as it is; whether it should mention water is the owner's copy call | UI copy is a product decision |
| D-13229 | **Revision 2 (owner, 2026-11-08: "fix it").** The watch stays on plain glass digits (no wire change, no schema field), but the count is a count of taps: `water_down.glasses` is `volumeMl ~/ step`, where step is the phone's current per-tap step (250 ml with kg, 237 ml with lbs). `waterGlassesFor(volumeMl, [stepMl = kWaterGlassMl])` stays the one owner of the division; `buildWaterDown` and `readWaterDown` take a required `stepMl`; the two senders pass it: `WatchSyncRequestHandler` from `waterStepMlFor(UnitFormatter.volumeUnitForWeightUnit(_settings.preferredWeightUnit))`, `WatchWaterLogBridge` from `_nutrition.waterStepMl`. A unit switched mid-day keeps the stored ml and the count follows the new step | `watch_reference_sync.dart` `buildWaterDown` (one caller `readWaterDown`, two callers: `watch_sync_request_handler.dart:298`, `watch_water_log_bridge.dart:170`); `NutritionState.waterStepMl` |

## Scenarios

Fixtures re-derived with a throwaway script (8 fl oz = 236.588 ml → 237; ml/29.5735295625 rounded).

| ID | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-13201 | `UnitFormatter.formatWaterTotal(ml, 'ml')` for 0, 250, 750, 763, 1000, 1250, 1500, 1763, 2000, 3000; `formatWaterSpoken` for 1, 250, 1000, 1500, 2000 | `0 ml`, `250 ml`, `750 ml`, `763 ml`, `1 L`, `1.25 L`, `1.5 L`, `1.76 L`, `2 L`, `3 L`; spoken `1 milliliter`, `250 milliliters`, `1 liter`, `1.5 liters`, `2 liters` | the helpers do not exist; the control showed a bare glass count |
| S-13202 | `formatWaterTotal(ml, 'floz')` for 0, 237, 250, 500, 948, 1000, 1422, 1896, 3000; spoken for 30, 237 | `0 oz`, `8 oz`, `8 oz`, `17 oz`, `32 oz`, `34 oz`, `48 oz`, `64 oz`, `101 oz`; spoken `1 fluid ounce`, `8 fluid ounces` | no ounce conversion exists anywhere in the app |
| S-13203 | `waterStepMlFor('ml')`, `('floz')`, `(null)`, `('stone')`; `waterStepLabel` for the two units | 250, 237, 250, 250; `250 ml`, `8 oz` | the step is the single constant 250 |
| S-13204 | `SettingsState` default; `setPreferredVolumeUnit('fl oz')`, `('OZ')`, `('floz')`, `('litre')`; reload a second `SettingsState` over the same repository | default `ml`; the first three give `floz`, the fourth `ml`; the reloaded state has the saved value; one notification per set | no such preference exists |
| S-13205 | `NutritionState(repo, settings: floz)` with 0 ml stored: plus, plus, minus; then minus at 0; then `applyWatchWaterTap` add and remove on a loaded day, each with a fresh `tapId`; repeat with the ml unit | floz: 237, 474, 237; minus at 0 stays 0 with no write and no notification; tap add 474, tap remove 237. ml: 250, 500, 250 (as today) | every write adds or subtracts 250 whatever the setting |
| S-13206 | 1000 ml stored with the ml unit; a listener counts notifications; `settings.setPreferredVolumeUnit('floz')` then `setPreferredAppTheme` (any non-volume setting) then plus | `waterTodayMl` stays 1000 after the switch; exactly one notification from the unit switch and none from the other setting; plus then stores 1237 | the state does not know the settings and never notifies on a unit change |
| S-13207 | `WaterTrackerControl` pumped with (750 ml, `ml`), (1500, `ml`), (711, `floz`), (0, `floz`); tap plus, tap minus | keys `water_tracker_count` text `750 ml`, `1.5 L`, `24 oz`, `0 oz`; `water_tracker_label` text `250 ml`, `250 ml`, `8 oz`, `8 oz`; minus disabled at 0; each tap calls its callback once | the count key held the glass number (`3`) and the label always said `250 ml` |
| S-13208 | `CalorieRingCard` over `NutritionState(repo, settings:)` with 1000 ml loaded and the card pumped; then `settings.setPreferredVolumeUnit('floz')` and one `tester.pump()` | the card shows `1 L` before and `34 oz` after, with no other call; the step caption changes `250 ml` → `8 oz` | the card read only the glass count and no setting, so it could not change |
| S-13209 | Settings screen on the Mock harness: Volume row present after Distance with options `ml` and `fl oz`, `ml` selected; tap `fl oz` | `settingsState.preferredVolumeUnit == 'floz'` and the toggle shows `fl oz` selected | no Volume row exists |
| S-13210 | `WaterTrackerControl` tooltips and Semantics label for (1500, `ml`) and (711, `floz`) | tooltips `Add 250 milliliters` / `Remove 250 milliliters` and `Add 8 fluid ounces` / `Remove 8 fluid ounces`; semantics `Water today: 1.5 liters` and `Water today: 24 fluid ounces` | tooltips said `Add one glass` and the label `…glasses of 250ml` |
| S-13211 | Lead's layout probe at 390×844 (and with the rest strip up): the card row with the sodium chip at its widest (`Na 10,000 mg`) and the control at its widest (`2.75 L`, `101 oz`, `10.5 L`) | no overflow, both visible above the fold | a wider total in a slot sized for a one-digit count is the layout risk of the change |
| S-13212 | Existing watch tests (`watch_water_log_test.dart`, `watch_sync_request_handler_test.dart` S-94a-21…25, `water_tap_ledger_test.dart`) run unchanged except `waterTodayGlasses` → `waterTodayMl` | `water_down.glasses` is still `volumeMl ~/ 250` with the ml unit | guards that 132a leaves the wire as it was |
| S-13213 | Unit switch with a tap in flight, floz unit, 0 ml stored, Mock harness: a `MockWorkoutRepository` subclass resolves its first `getWaterVolumeForDate` only when the test releases it; `incrementWaterForDate` called and not awaited, then `await settings.setPreferredVolumeUnit('ml')`, then the release, then one awaited `incrementWaterForDate`, then one awaited `decrementWaterForDate` | the in-flight tap stores 237 (its step was read once when its closure body started, before the switch); the second tap +250 → 487; the minus −250 → 237; `waterTodayMl` never negative; one notification per write and the switch's one (S-13206's count); no second write interleaves the first's read-modify-write (`_waterChain`) | a step read per repository call, or a write not read-once-per-closure, would let the switched unit change a write already in flight, or interleave two write chains |
| S-13214 | `WaterTrackerControl(volumeMl: 1500, volumeUnit: 'bogus')`; also `formatWaterTotal(1500, 'bogus')` and `waterStepLabel('bogus')` | count `1.5 L`, caption `250 ml` — an unknown or unnormalised string is normalised through `normalizeVolumeUnit` to ml at every entry point | today the widget's inputs are a glass count and a literal `250 ml`; no normalisation path exists |
| S-13215 | floz unit, 763 ml stored (not a multiple of the step): minus, minus, minus, minus, then plus | 526, 289, 52, 0 — the fourth minus floors exactly at 0 with one write (value 0); `waterTodayMl` is never negative at any point; then plus → 237 | the old floor only ever saw 250-multiples, so `current - step < 0` was unreachable except at `current < 250`; the 237 step makes a remainder day reachable and must floor, not clamp negative |
| S-13216 | `NutritionState(repo, settings: null)` beside a real `SettingsState`; then `setPreferredVolumeUnit('floz')` on that SettingsState | `waterVolumeUnit == 'ml'` and `waterStepMl == 250`; plus/minus step 250 and `applyWatchWaterTap` ±250; mutating the unbound SettingsState produces no notification from this state (no listener was added) | the null default must mean exactly today's behaviour; binding a listener to a null source or defaulting to floz would change every existing construction site (139 test files build the real `SettingsState` and `NutritionState` without it) |
| S-13217 | `UnitFormatter.volumeUnitForWeightUnit` for `kg`, `lbs`, `LBS`, ` lbs `, `lb`, null, `stone` | `ml`, `floz`, `floz`, `floz`, `ml`, `ml`, `ml` (`lb` is not a stored spelling: `SettingsState` writes `lbs`) | no mapping exists; the unit was a separate setting |
| S-13218 | `NutritionState(repo, settings:)` with the default weight unit; `setPreferredWeightUnit('lbs')`; then `setPreferredDistanceUnit('miles')`; then plus; then `setPreferredWeightUnit('kg')` | `waterVolumeUnit` `floz` after the first, exactly one notification from it and none from the distance change; plus stores 237 ml; the last call returns `ml` with one notification | the weight unit did nothing to water; only the removed volume setting did |
| S-13219 | Settings screen pumped as in the existing weight/distance toggle test | no text `Volume` and no text `Used for water`; the existing weight toggle assertions still hold | the Volume row existed |
| S-13220 | `waterGlassesFor(volumeMl, stepMl)` for (0, 237), (236, 237), (237, 237), (948, 237), (1000, 237), (948, 250), and `waterGlassesFor(250)` with no step | 0, 0, 1, 4, 4, 3, 1 | the division had one hard-coded glass of 250 ml: 948 ml (four 8 oz taps) read 3 |
| S-13221 | `WatchSyncRequestHandler` answering a wrist that asks, with 948 ml stored today: once with weight unit `lbs`, once with `kg` | `water_down.glasses` 4 with `lbs`, 3 with `kg` | the frame always divided by 250, so a pounds user's four taps read 3 |
| S-13222 | `WatchWaterLogBridge` with a `NutritionState` bound to settings with weight unit `lbs`: four wrist taps `add` (fresh ids) on a loaded day, then read the `water_down` it sends after the last acknowledgement | stored 948 ml and the frame's `glasses` is 4, the tap count; the same four taps under `kg` store 1000 ml and frame 4 | the frame divided by 250, so the same four taps gave 3 for a pounds user |

## Readers (every place the change touches)

- Per-glass constant and glass count in `lib/`: `water_constants.dart:12,17`, `nutrition_state.dart:71,111,127,150`, `watch_reference_sync.dart:738`, `workout_repository.dart:693` (doc comment), `water_tracker_control.dart` (labels), `calorie_ring_card.dart:301`.
- Tests that read the glass count or 250: `test/state_test.dart` (4331-4508, 15 hits), `test/nutrition_test.dart` (402, 528, 542, 550, 591, 606), `test/watch_water_log_test.dart` (156, 283, 298-302), `test/watch_sync_request_handler_test.dart` (1844-2013, S-94a-21…24), `test/water_tap_ledger_test.dart` (28-33 stays, 162 stays), `test/first_run_path_test.dart` (209, 238: the key `water_tracker_label` position).
- Units readers (a new setting must not break them): `test/settings_state_test.dart`, `test/interaction_flow_test.dart`; `SettingsState` is built for real in 139 test files, so the new field needs a default and no constructor change.
- `CalorieRingCard(nutritionState:)` callers: `nutrition_screen.dart:251`, 8 test sites; unchanged by D-13205.

## Input-reality checklist

1. Writers: only `NutritionState` writes water (`increment/decrementWaterForDate`, `applyWatchWaterTap`, via `WatchWaterLogBridge.receive`); no Health or import writer (`grep` above). Unit: always ml.
2. Lifecycle: the cache is single-day and cleared by `rolloverToDate`; the unit does not touch it. Past days are not shown.
3. Settings: the volume unit changes the answer; changed while the Nutrition screen is open behind Settings, `NutritionState` notifies and the card rebuilds (S-13206, S-13208).
4. Time: unchanged (the day key is local midnight).
5. Cost: no extra read; formatting runs in the control's build.
6. Words: swept in Docs delta; new strings are the tooltips, the semantics label, the Settings row and subtitle.
7. Slot competition: the control shares the card's bottom row with the sodium chip; a wider number is the risk (S-13211).
8. Concurrency: the unit listener only notifies; the water chain (`_serialiseWater`) is untouched; the step is read inside the queued closure so a unit switch between two taps applies to the later tap (S-13205 steps use one unit per run).

## Feature invariants

- Stored water is ml only; the volume unit changes display and step, never storage, and switching rewrites nothing (D-13202).
- Every volume label, step and spoken string goes through `UnitFormatter` / `waterStepMlFor`; never hardcode `250` or `237` (global conventions, Units + canonical storage; D-13203, D-13209).
- The step is read once per water-write closure at body start; a unit switch after that applies to a later tap (D-13206, S-13213).
- A minus floors at 0 ml whatever the step, and a minus at 0 ml is no write and no notification (D-13206, S-13215).
- A unit switch notifies once, only when the normalised unit actually changed; other settings' changes notify `SettingsState`'s listeners but never `NutritionState` (D-13205, S-13206).
- An unknown or null volume unit is ml — 250 ml everywhere (D-13203, S-13203, S-13214).

## Existing-functionality impact

Searches run this pass: `waterTodayGlasses` in `lib/`+`test/` (6 files), `kWaterGlassMl` (40 hits, 9 files), `water_tracker_|WaterTrackerControl` in `lib/` (3 files), `preferredDistanceUnit|preferredVolumeUnit` (9 files, no volume hit anywhere — the field is new), `UnitFormatter` in `test/` (unit helpers tested in `test/utils_test.dart`; no volume helper exists).

| Touched surface | Readers (search and result) | Effect | Guarded by |
|---|---|---|---|
| `NutritionState.waterTodayGlasses` (deleted) | `calorie_ring_card.dart:305` (the only lib reader); tests: `state_test.dart` 4347…4508 (14 waterTodayGlasses asserts), `nutrition_test.dart` 591, 606, `watch_water_log_test.dart` 156, 298, `watch_sync_request_handler_test.dart` 1986, 1989 | getter deleted; card switches to `waterTodayMl`+unit in P2a; state asserts rewritten to `waterTodayMl` in P1 | D-13207, S-13212 |
| `kWaterGlassMl` / `waterGlassesFor` | `nutrition_state.dart` 111, 127, 150 (the three writers); `water_tracker_control.dart` 62, 88, 91; `workout_repository.dart:693` doc; `models.dart:2393` doc; the wire's `waterGlassesFor` at `watch_reference_sync.dart:738` stays | the three writers read `waterStepMl`; the wire keeps `kWaterGlassMl` whole glasses | D-13203, D-13206, S-13205, S-13212 |
| `WaterTrackerControl` keys | `water_tracker_label` asserted at `nutrition_test.dart` 402, 550 and `first_run_path_test.dart` 209, 238; `water_tracker_count` in no test today; `water_tracker_control/minus/plus` in none | keys kept; texts change under them; P2b asserts `water_tracker_count` content for the first time | D-13208, S-13207 |
| `SettingsState` | built for real in 139 test files, no fake/stub subclass (`grep implements\|extends SettingsState test/` — none); unit keys read in 9 files (`preferredDistanceUnit` list in Readers) | new default `'ml'` field, no constructor change; setters/load pattern copied from distance | D-13201, S-13204 |
| Settings screen rows | `_MeasurementsSection` holds Start of Week / Weight / Distance / Height (sections pinned by `test/header_standardization_test.dart`, rows not enumerated); row tests in `test/interaction_flow_test.dart` | a fifth row (Volume) after Distance; pinned labels unchanged | D-13201, S-13209 |
| `CalorieRingCard` rebuild path | one `ListenableBuilder(listenable: widget.nutritionState)` at `calorie_ring_card.dart:92-93` wraps the whole card | a unit-switch notification from `NutritionState` rebuilds it with no new plumbing | S-13206, S-13208 |
| `lib/main.dart` construction sites | `NutritionState(repository)` once, `main.dart:339`; states are never `.dispose()`d in main (grep: only `_healthLifecycleListener?.dispose()` at 330) | construct with `settings: settingsState`; `dispose` stays uncalled on the happy path, like today | D-13205 |
| Watch water chain | `watch_reference_sync.dart:738`, `watch_water_log_bridge.dart:170` unchanged; `watch_sync_request_handler.dart` `_preferencesFrame` untouched (no volume field — 132b) | zero changes; S-13212 runs the existing watch tests | S-13212, D-13220 |


## Phases

| Phase | Agent | Write scope | Items | Mode |
|---|---|---|---|---|
| P1 core, settings, state | `crew-builder-app` | `lib/core/constants/water_constants.dart`, `lib/core/utils/unit_formatter.dart`, `lib/state/settings/settings_state.dart`, `lib/state/nutrition_state.dart`, `lib/main.dart`, `lib/data/repositories/workout_repository.dart` (doc comment), tests for S-13201…S-13206 and the glass-count rewrites in `test/state_test.dart`, `test/watch_water_log_test.dart`, `test/watch_sync_request_handler_test.dart` | 7 | serial |
| P2a screen production code | `crew-builder-app` | `lib/features/nutrition/widgets/water_tracker_control.dart`, `lib/features/nutrition/widgets/calorie_ring_card.dart`, `lib/features/settings/settings_screen.dart`, `lib/state/nutrition_state.dart` (delete `waterTodayGlasses` only) | 4 (exact code in the brief) | serial after P1 |
| P2b screen tests | `crew-builder-app` | `test/nutrition_test.dart`, `test/first_run_path_test.dart`, a Settings screen test file | S-13207…S-13210 | serial after P2a |
| P3 docs | `crew-docs-keeper` | `docs/**` per the Docs delta | rows below | after P2b |

Lead after P2b: layout probe (S-13211), full suite, prover, review.

### P1 — core helpers, the setting, the state, the wiring (expands the seed's P1 row)

Write scope: `lib/core/constants/water_constants.dart`, `lib/core/utils/unit_formatter.dart`, `lib/state/settings/settings_state.dart`, `lib/state/nutrition_state.dart`, `lib/main.dart`, `lib/data/models/models.dart` (doc comment only), `lib/data/repositories/workout_repository.dart` (doc comment only), `test/utils_test.dart`, `test/water_tap_ledger_test.dart`, `test/settings_state_test.dart`, `test/state_test.dart`, `test/nutrition_test.dart` (state-level asserts only: 591, 606), `test/watch_water_log_test.dart`, `test/watch_sync_request_handler_test.dart`.

1. [ ] Add `const int kWaterOzStepMl = 237;` and `int waterStepMlFor(String? unit)` (ml → 250, floz → 237, anything else → 250); refresh the header comment's "each glass / glass count" wording to "per-tap step" — lib/core/constants/water_constants.dart · `waterStepMlFor`
2. [ ] Add the volume helpers: `normalizeVolumeUnit` (`'fl oz'`/`'floz'`/`'oz'` any case/trim → `'floz'`, else `'ml'`), `volumeLabelForUnit` (`'ml'` / `'fl oz'`), `formatWaterTotal(int ml, String? unit)`, `formatWaterSpoken(int ml, String? unit)`, `waterStepLabel(String? unit)` — lib/core/utils/unit_formatter.dart · `UnitFormatter`
3. [ ] Add `_preferredVolumeUnit` (default `'ml'`), `preferredVolumeUnit`, `setPreferredVolumeUnit` (normalise like distance, persist under `preferred_volume_unit`, one `notifyListeners`), and the `_loadFromPrefs` block — lib/state/settings/settings_state.dart · `setPreferredVolumeUnit`, `_loadFromPrefs`
4. [ ] Take `SettingsState? settings` (named, default null); expose `waterVolumeUnit` (normalised via `UnitFormatter.normalizeVolumeUnit`) and `waterStepMl` (`waterStepMlFor`); add the listener that notifies only when the normalised unit changed; add `dispose()` removing it; read `waterStepMl` once at body start in `incrementWaterForDate`, `decrementWaterForDate`, `applyWatchWaterTap` (the decrement floor is `current - waterStepMl < 0 → 0`) — lib/state/nutrition_state.dart · `incrementWaterForDate`, `decrementWaterForDate`, `applyWatchWaterTap`
5. [ ] Construct with `settings:` at the single app site; KEEP `waterTodayGlasses` for now (the card still reads it until P2a deletes it, so the tree compiles after P1: lead's change to the architect's order) — lib/main.dart · `NutritionState(...)` (line 339)
6. [ ] Refresh the two stale per-glass doc comments (`deltaMl` = the step, not ±`kWaterGlassMl`; the display boundary is the volume-unit total) — lib/data/repositories/workout_repository.dart · `applyWaterTap` (line 693); lib/data/models/models.dart · `WaterLogEntry` block comment (line 2393)
7. [ ] Rewrite the glass-count asserts to `waterTodayMl` (S-13212 keeps the wire-side glasses asserts untouched) — test/state_test.dart · NutritionState water group (4331–4508); test/watch_water_log_test.dart · 156, 298; test/watch_sync_request_handler_test.dart · 1986, 1989
8. [ ] Add the S-13201 (ml+floz totals/spoken), S-13203 (step table) tests and, in the state suites, S-13204 (setting, persistence, reload, one notify), S-13205 (floz and ml ladders incl. minus-at-0 no-write/no-notify and watch taps), S-13206 (unit-switch notify count, other settings silent, 1237), and the edge scenarios S-13213, S-13215, S-13216 — test/utils_test.dart · UnitFormatter volume group; test/water_tap_ledger_test.dart · step-helper test beside `waterGlassesFor`; test/settings_state_test.dart · volume-unit group; test/state_test.dart · NutritionState volume-unit group

Done Criteria:
- `.github/copilot/scripts/macos/gateway.sh test -- test/utils_test.dart`
- `.github/copilot/scripts/macos/gateway.sh test -- test/water_tap_ledger_test.dart`
- `.github/copilot/scripts/macos/gateway.sh test -- test/settings_state_test.dart`
- `.github/copilot/scripts/macos/gateway.sh test -- test/state_test.dart`
- `.github/copilot/scripts/macos/gateway.sh test -- test/watch_water_log_test.dart`
- `.github/copilot/scripts/macos/gateway.sh test -- test/watch_sync_request_handler_test.dart`
- `.github/copilot/scripts/macos/gateway.sh test -- test/nutrition_test.dart`
- `.github/copilot/scripts/macos/gateway.sh lint` (compare against the repo's pre-existing info-notice baseline; count must not grow)

Prover: prove-red at the base commit with the new test files carried — every new guard names a symbol that does not exist there (`waterStepMlFor`, `setPreferredVolumeUnit`, `preferredVolumeUnit`, `waterVolumeUnit`, `waterStepMl`), so the carried files fail to compile, which is the red; S-13212's rewritten asserts (`state_test.dart`, `watch_water_log_test.dart`, `watch_sync_request_handler_test.dart`) must fail at base too (`waterTodayGlasses` is still the old getter). One mutation line for after: flipping `waterStepMlFor`'s floz branch to return `kWaterGlassMl` turns S-13203 and S-13205 red.

Notes for this phase's brief: stored-data tests for the `preferred_volume_unit` preference string run under Mock and Hive where the harness offers both; today only the Mock harness exists for `SettingsState` preference storage (`test/settings_state_test.dart` has no Hive group), so Mock-only is accepted and no Hive group is added. These are state tests, not screen tests, so the screen rule below does not bind.

### P2a — screen production code (expands the seed's P2a row; the governor pastes this section's items into the builder brief as exact text)

Write scope: `lib/features/nutrition/widgets/water_tracker_control.dart`, `lib/features/nutrition/widgets/calorie_ring_card.dart`, `lib/features/settings/settings_screen.dart`, `lib/state/nutrition_state.dart` (item 4 only).

1. [ ] Change the parameter shape to `volumeMl`/`volumeUnit` (drop `glasses`); the count slot shows `UnitFormatter.formatWaterTotal(volumeMl, volumeUnit)` inside the `water_tracker_count` key block; the caption shows `UnitFormatter.waterStepLabel(volumeUnit)` inside the `water_tracker_label` key block; the Semantics label on the control becomes `Water today: ${UnitFormatter.formatWaterSpoken(volumeMl, volumeUnit)}` and the plus/minus tooltips `Add …` / `Remove …` from `formatWaterSpoken`; minus disabled when `volumeMl <= 0`; keys `water_tracker_control`, `water_tracker_minus`, `water_tracker_count`, `water_tracker_plus`, `water_tracker_label` all kept — lib/features/nutrition/widgets/water_tracker_control.dart · `WaterTrackerControl`
2. [ ] In the bottom row, pass `volumeMl: widget.nutritionState.waterTodayMl` and `volumeUnit: widget.nutritionState.waterVolumeUnit` (the callbacks keep `increment/decrementWaterForDate(OmniDateUtils.todayMidnightMs())`) — lib/features/nutrition/widgets/calorie_ring_card.dart · the `WaterTrackerControl` call site (lines 291–311)
3. [ ] Add the Volume row after Distance in `_MeasurementsSection`: group value `UnitFormatter.normalizeVolumeUnit(widget.settingsState.preferredVolumeUnit)`, options `ml` and `fl oz` labelled with `UnitFormatter.volumeLabelForUnit`, `onChanged: widget.settingsState.setPreferredVolumeUnit` — lib/features/settings/settings_screen.dart · `_MeasurementsSection`
4. [ ] Delete the `waterTodayGlasses` getter and its doc block (its last lib reader is the card, changed in item 2) — lib/state/nutrition_state.dart · `waterTodayGlasses`

Done Criteria:
- `.github/copilot/scripts/macos/gateway.sh test -- test/first_run_path_test.dart` (the `water_tracker_label` placement guard must still hold across the re-layout)
- `.github/copilot/scripts/macos/gateway.sh lint` (baseline compare)

Prover: not applicable by itself — the behavioural guards live in P2b. Expected and accepted at this checkpoint: `test/nutrition_test.dart`'s control asserts (542, 550) are red until P2b; never run the full `flutter test` to "confirm" them.

### P2b — screen tests (expands the seed's P2b row)

Write scope: `test/nutrition_test.dart`, `test/first_run_path_test.dart`, `test/interaction_flow_test.dart`.

1. [ ] S-13207: pump the control with (750, ml), (1500, ml), (711, floz), (0, floz); assert the `water_tracker_count` and `water_tracker_label` texts, minus disabled at 0, and that each tap fires its callback exactly once — test/nutrition_test.dart · water-control testWidgets group
2. [ ] S-13208: pump `CalorieRingCard` over `NutritionState(repo, settings:)` with 1000 ml loaded; `setPreferredVolumeUnit('floz')` then one `tester.pump()`; assert `1 L` → `34 oz` and the caption `250 ml` → `8 oz` with no other calls — test/nutrition_test.dart · calorie-ring-card group
3. [ ] S-13210: assert the tooltips and the Semantics label for (1500, ml) and (711, floz) — test/nutrition_test.dart · same group
4. [ ] S-13214: pump the control with `volumeUnit: 'bogus'`; assert ml formatting falls out — test/nutrition_test.dart · same group
5. [ ] S-13209: on the Mock screen harness with `setUp` seeding, open Settings, assert the Volume row after Distance with `ml` selected, tap `fl oz`, assert `preferredVolumeUnit == 'floz'` and the toggle selection — test/interaction_flow_test.dart · settings-screen group
6. [ ] Re-derive the `water_tracker_label` placement checks against the new captions (280 → 86 px text width changes are expected; key positions stay) — test/first_run_path_test.dart · 209, 238

Done Criteria:
- `.github/copilot/scripts/macos/gateway.sh test -- test/nutrition_test.dart`
- `.github/copilot/scripts/macos/gateway.sh test -- test/interaction_flow_test.dart`
- `.github/copilot/scripts/macos/gateway.sh test -- test/first_run_path_test.dart`
- `.github/copilot/scripts/macos/gateway.sh test -- test/watch_water_log_test.dart` (untouched regression)

Prover: prove-red at the base commit — the new screen tests assert `formatWaterTotal`/`waterStepLabel`/`volumeUnit` texts the widget did not carry at base, so they fail there. Mutation line: making `waterStepLabel` return `250 ml` for floz turns the S-13207 caption asserts red; making the Semantics label hardcode `glasses` turns S-13210 red.

Rules for the briefs on every phase (the governor copies these into the builder briefs verbatim):
- Every builder brief opens with "Never run the full `flutter test`"; the runner is `gateway.sh test -- <file>`, one file per gate, only the files named in that phase's Done Criteria.
- Stored-data tests (the `preferred_volume_unit` preference string) run under Mock and Hive where the harness offers both; for `SettingsState` only the Mock harness exists today, so Mock-only stands.
- A screen test that taps a control which writes a preference (S-13208, S-13209) runs on the Mock harness only and seeds in `setUp`.

### P3 — docs (expands the seed's P3 row)

Write scope: `docs/constants_reference.md`, `docs/data_models.md`, `docs/db_integration.md`, `docs/state_management/nutrition_state.md`, `docs/state_management/app_state.md`, `docs/widget_catalog/home_screen.md`, `docs/theme_and_settings.md`, `docs/nutrition.md` — the rows each item names.

1. [ ] Apply the two constants_reference rows: `kWaterGlassMl` note, the `kWaterOzStepMl` row, and the display-boundary sentence — docs/constants_reference.md · `water_constants.dart` table and paragraph
2. [ ] Apply the five data_models rows: the storage-boundary sentence, the `waterTodayGlasses` row removal, the increment and decrement row wording, the canonical-amount sentence — docs/data_models.md · `WaterLogEntry` / NutritionState water section
3. [ ] Apply the three db_integration rows — docs/db_integration.md · Daily Water Log
4. [ ] Apply the four nutrition_state.md rows — docs/state_management/nutrition_state.md · water table rows 58–64 and the NutritionScreen listener sentence
5. [ ] Apply the app_state.md rows (added field, default, setter row) — docs/state_management/app_state.md · SettingsState field/method tables
6. [ ] Apply the home_screen row (total instead of glass count; the `millilitres` spelling goes with the surrogate sentence, A-3) — docs/widget_catalog/home_screen.md · `WaterTrackerControl` section
7. [ ] Apply the theme_and_settings row (Volume joins the units bullet) — docs/theme_and_settings.md · Overview bullet; the section-list rule at 121–129 stays as it is (it deliberately does not enumerate unit rows)
8. [ ] Apply the nutrition.md row (the control shows the day's total in the unit; the watch wording at 431–437 stays — that is the wire, 132b's) — docs/nutrition.md · water-control paragraphs

Done criteria: no gateway test — docs only. The keeper confirms, per row, that the Old marker is present in the file before editing and that each changed behaviour sentence still names a test (`test/utils_test.dart`, `test/settings_state_test.dart`, `test/state_test.dart`, `test/nutrition_test.dart`, `test/interaction_flow_test.dart`) and stays under 52 KB per file.

Prover: prove-red carries no test files; the guard is the Docs delta's Old markers, which the reviewer greps today — each must be gone from its doc after P3.

Phases and ordering: no two phases run in parallel. P1 → P2a serial (the card and screen consume `waterTodayMl`/`waterVolumeUnit`/`normalizeVolumeUnit` produced in P1; `waterTodayGlasses` is deleted in P2a together with the card's last read of it, so the tree compiles after every phase); P2a → P2b serial (the screen tests assert the new widget texts); P3 after P2b (the docs claim only built behaviour; the markers name S-13207…S-13210 results).

### Revision 1 (owner, 2026-11-08): the unit follows the Weight setting

132a was built with its own Volume setting; the owner asked for none, because the Weight preference already says which system the user prefers. Retired: S-13204 (the setting) and S-13209 (the Volume row); their tests are removed, their ids are never reused. S-13205, S-13206, S-13208, S-13213, S-13215 and S-13216 keep their meaning but set the unit with `setPreferredWeightUnit('lbs')` instead. The revision is two more runs on the built tree, then the docs:

- **R1** (`crew-builder-app`): items 1. `UnitFormatter.volumeUnitForWeightUnit`, remove `volumeLabelForUnit`; 2. `SettingsState`: remove the field, getter, setter, key and load block; 3. `SettingsScreen`: remove the Volume row and its divider; 4. `NutritionState.waterVolumeUnit` derives from the weight unit; 5. tests: remove S-13204 and S-13209, switch the unit-setting calls of S-13205/6/8/13/15/16 to the weight unit, add S-13217, S-13218, S-13219.
- **R2** (`crew-docs-keeper`): the rows of the Docs delta that name the Volume setting.
- The lead re-runs the touched files, the mutation pass (the mutants that touched removed code are replaced by two on the derivation), the full suite, and `plan-lint after`.

### Revision 2 (owner, 2026-11-08): the wrist's glass digits count taps for pounds users

The owner kept the watch on plain digits (no room for a total). Left alone, a pounds user's four 8 oz taps store 948 ml and the wire's `volumeMl ~/ 250` reads 3. One run: **R3** (`crew-builder-app`) changes `water_constants.dart` (`waterGlassesFor` takes an optional step), `watch_reference_sync.dart` (`buildWaterDown`, `readWaterDown` take `stepMl`), the two senders, and adds S-13220..S-13222 in `test/water_tap_ledger_test.dart`, `test/watch_sync_request_handler_test.dart`, `test/watch_water_log_test.dart`. The lead edits the four contract/doc sentences of the Docs delta (one is under `watch/`, outside the keeper's ceiling) and runs the mutation pass.

## Progress

- [x] Preflight, scouts, seed, architect pass; P1, P2a, P2b, P3 built 2026-11-07 (uncommitted)
- [x] Revision 1 (owner, 2026-11-08: no new setting, the unit follows the Weight preference): R1 builder run and R2 docs run done
- [x] Verified by the lead after the revision: touched files green, full suite `+7068 ~2: All tests passed!`, `flutter analyze` 181 = base, removed-symbol grep empty, `plan-lint after` clean (24 rows), mutation pass 20/20 killed (3 mutants of the removed setting dropped, 2 on the weight mapping added)
- [x] Review of the first version: APPROVE (0 blocker, 0 major, 2 minor, one fixed). The revision only removes code and adds three small tests; the lead reviewed its diff (no second crew review).
- [ ] (owner) Settings > Weight: switch to lbs, open Nutrition: the water total reads `N oz` and plus adds 8 oz; switch back to kg: ml.
- [ ] (owner) On the phone, the water control and the sodium chip both fit on the card row.
- [ ] (owner) `main.dart` passes `settings: settingsState` to `NutritionState`: no test sees it. After a real app start, a weight-unit change in Settings changes the Nutrition total.
- [ ] (owner) Copy call: the Weight row's subtitle says `Used for exercises and volume` and does not mention water (D-13228).
- [x] 132b (a total on the watch) dropped by the owner (2026-11-08): the watch keeps plain glass digits, there is little room on the wrist.
- [x] Revision 2 (owner: "fix it"): the wire's `glasses` is `volumeMl ~/ phone step`, so a pounds user's four 8 oz taps read 4 on the wrist (D-13229, S-13220..S-13222). R3 builder run; the lead edited the contract sentences and simplified `waterGlassesFor` (the builder had added a branch only to satisfy an old source scan; the scan test S-94a-24 now accepts the new owner line). Full suite `+7071 ~2: All tests passed!`, analyze 181, `plan-lint after` clean (28 rows), `swift test --filter SyncProtocolFixturesTests` passed, mutation pass 25/25 killed on the wire step and the mapping (5 new).

**S-13211 probe (lead, throwaway, deleted).** 390x844, the app's own text theme with real Roboto metrics (the test font is far too wide): widest control 171 pt (`750 ml`), `2.75 L` 166, `101 oz` 159, `1000 oz` 170; sodium chip at `Na 10,000 mg` 80 pt; gap at least 72 pt; no overflow. Control bottom y=361 of 844.

## Assumption Log

- A-1: the US step is 8 fl oz (237 ml), not the 250 ml glass shown as 8.45 oz. The lead recommended it in chat and the owner's answer did not object; if the owner prefers a plain conversion, `kWaterOzStepMl` is the one value to change.
- A-2: between 132a and 132b a US user's wrist counts 250 ml glasses. 132b's own mismatch window (a unit switched on the phone reaches the wrist at its next sync) is accepted: the frame that arrives with that sync corrects the total.
- A-3: spelling is American (`milliliters`, `liters`) like `docs/data_models.md` and the code comments; `docs/widget_catalog/home_screen.md` says `millilitres` and is corrected where the keeper touches that sentence.
- A-4: no existing user data and no back-compat for water rows (storage is unchanged anyway).

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| `docs/constants_reference.md` | MODIFIED | `Milliliters per logged glass` | `Milliliters per tap with the ml unit` | D-13203, S-13203 |
| `docs/constants_reference.md` | ADDED | - | `kWaterOzStepMl` | D-13203, S-13203 |
| `docs/data_models.md` | MODIFIED | `the on-screen glass count is derived at the display boundary` | `the on-screen total is shown in the user's volume unit` | D-13202, S-13207 |
| `docs/data_models.md` | REMOVED | `Derived from `waterTodayMl ~/ kWaterGlassMl`. The displayed count` | - | D-13207, S-13205 |
| `docs/data_models.md` | MODIFIED | `Adds `kWaterGlassMl` (250 ml), persists, updates the cache, notifies.` | `Adds the water step (250 ml, or 237 ml with the fl oz unit)` | D-13206, S-13205 |
| `docs/state_management/nutrition_state.md` | MODIFIED | `the on-screen glass count is derived at the display boundary` | `the on-screen total is shown in the user's volume unit` | D-13202, S-13207 |
| `docs/state_management/nutrition_state.md` | REMOVED | `Derived by `waterGlassesFor(waterTodayMl)`` | - | D-13207, S-13205 |
| `docs/state_management/nutrition_state.md` | ADDED | - | `waterVolumeUnit` | D-13205, S-13206 |
| `docs/state_management/nutrition_state.md` | MODIFIED | `Adds `kWaterGlassMl` (250 ml), persists via the repository` | `Adds the water step (`waterStepMl`)` | D-13206, S-13205 |
| `docs/widget_catalog/home_screen.md` | MODIFIED | `The glass count is derived from stored millilitres at the display` | `The number is the day's total in the user's volume unit` | D-13208, S-13207 |
| `docs/db_integration.md` | MODIFIED | `the on-screen glass count` | `the on-screen total` | D-13202, S-13207 |
| `docs/theme_and_settings.md` | ADDED | - | `the water control's unit follows the Weight` | D-13225, S-13217 |
| `docs/nutrition.md` | ADDED | - | `The water control shows the day's total` | D-13204, S-13207 |
| `docs/constants_reference.md` | MODIFIED | `The whole-glass count the watch wire still sends for a stored volume` | `The whole-tap count the watch wire sends for a stored volume` | D-13229, S-13220 |
| `watch/sync_protocol/PROTOCOL.md` | MODIFIED | `divided by one glass and rounded down` | `divided by one tap's step and rounded down` | D-13229, S-13221 |
| `watch/sync_protocol/schemas/messages/water_down.schema.json` | MODIFIED | `Whole glasses: the day's volume divided by one glass, rounded down` | `Whole taps: the day's volume divided by one tap's step, rounded down` | D-13229, S-13221 |
| `watch/sync_protocol/fixtures/manifest.json` | MODIFIED | `volume divided by the glass, rounded down` | `volume divided by one tap's step, rounded down` | D-13229, S-13221 |
| `docs/state_management/nutrition_state.md` | ADDED | - | `follows the weight unit` | D-13226, S-13218 |
| `docs/constants_reference.md` | MODIFIED | `on-screen glass count is derived at the display boundary` | `on-screen total is shown in the user's volume unit` | D-13202, S-13207 |
| `docs/constants_reference.md` | ADDED | - | `waterStepMlFor(unit)` | D-13203, S-13203 |
| `docs/db_integration.md` | MODIFIED | `` `deltaMl` = ±`kWaterGlassMl` `` | `` `deltaMl` = ± the current step `` | D-13206, S-13205 |
| `docs/db_integration.md` | MODIFIED | `amount is canonical at `kWaterGlassMl = 250`` | `the tap step is `waterStepMlFor`, 250 ml or 237 ml with fl oz` | D-13203, S-13215 |
| `docs/data_models.md` | MODIFIED | `The canonical per-glass amount lives in `kWaterGlassMl`` | `The tap step lives in `waterStepMlFor(unit)`` | D-13203, S-13203 |
| `docs/data_models.md` | MODIFIED | `Subtracts `kWaterGlassMl` (floors at 0 ml), persists` | `Subtracts the step (`waterStepMl`, floors at 0 ml)` | D-13206, S-13215 |
| `docs/state_management/nutrition_state.md` | MODIFIED | `Subtracts `kWaterGlassMl` (floors at 0 ml), persists` | `Subtracts the step (`waterStepMl`, floors at 0 ml)` | D-13206, S-13215 |
| `docs/state_management/nutrition_state.md` | MODIFIED | `` `applyWaterTap` with ±`kWaterGlassMl` `` | `` `applyWaterTap` with ±`waterStepMl` `` | D-13206, S-13205 |
| `docs/state_management/nutrition_state.md` | MODIFIED | `.waterTodayGlasses` through a single | `waterVolumeUnit` through a single | D-13207, S-13208 |
| `docs/widget_catalog/home_screen.md` | MODIFIED | `the per-glass amount is sourced from` | `the step amount is sourced from `waterStepMlFor`` | D-13209, S-13210 |

## Feedback

(empty)

## Open questions

1. Does `CalorieRingCard` rebuild when `NutritionState` notifies? Yes. The card holds its own `ListenableBuilder(listenable: widget.nutritionState)` at `lib/features/nutrition/widgets/calorie_ring_card.dart:92-93` wrapping the whole build, so a unit-switch notification reaches the water control with no new plumbing. Verified this pass by reading the file; the card's own comment at 283–290 says the same.
2. Does `NutritionState` have a `dispose` today? No — `grep dispose\|addListener\|removeListener` over `lib/state/nutrition_state.dart` this pass returns only the class declaration line. Where the listener is removed: the precedent for a class that takes another state is `lib/watch/watch_timer_adoption.dart:100-103` (`dispose()` — "Removes every listener this class added") and `lib/watch/watch_session_auto_push.dart:448-450`, and D-13205's own text says `dispose` removes it. Note: nobody calls `NutritionState.dispose` today and nothing in `main.dart` disposes states at all (grep `dispose` in `main.dart` → only `_healthLifecycleListener?.dispose()` at line 330), so the `dispose()` is hygiene following that precedent, not a new call site to wire.
3. Do the repositories' comments name `kWaterGlassMl` where the change makes them stale? `lib/data/repositories/workout_repository.dart:693` — "[deltaMl] is `kWaterGlassMl` (add) or `-kWaterGlassMl` (remove)" on the abstract `applyWaterTap`; it becomes stale because the delta is now ± `waterStepMl`. Neither `HiveWorkoutRepository` nor `MockWorkoutRepository` mentions `kWaterGlassMl` in its own text (grep this pass over `lib/data`: only line 693). `lib/features/nutrition/widgets/water_tracker_control.dart:17,21,88,91` and `lib/data/models/models.dart:2393` also carry it; the control is P2a's file, and P1's item 6 covers the repository and `models.dart` doc comments.
4. Seed gap, raised with evidence (kept as written): the seed's P1 write scope omits `test/nutrition_test.dart`, but deleting `waterTodayGlasses` breaks that file's compile — `test/nutrition_test.dart:591` and `:606` assert `expect(nutrition.waterTodayGlasses, …)` (verified this pass). The P1 section above adds the file (state-level asserts only) and lists it in the scope. The seed's own Readers section already lists `nutrition_test.dart` as a glass-count reader, so only the P1 row's test file list missed it.
5. Seed gap, raised with evidence (scope extended in P1 item 6): `lib/data/models/models.dart:2388-2393` (`WaterLogEntry` block comment: "the on-screen "glass count" is derived at the display boundary (`volumeMl ~/ kWaterGlassMl`)") is named by no phase's Write scope in the seed table. It is a doc comment only; P1's scope line above includes it.
6. A-3 notes `docs/widget_catalog/home_screen.md:141` says `millilitres` while `docs/data_models.md:546` says `milliliters`; the seed's home_screen row rewrites that very sentence, so the spelling goes with it — no separate row added.
7. `test/water_tap_ledger_test.dart:28-33` ("waterGlassesFor is whole glasses of kWaterGlassMl") and `:162` stay as-is — D-13207 keeps `waterGlassesFor` for the wire. S-13203's step-helper test lands in the same file next to it; no row of the delta touches this.
8. The gateway `test` check compiles whole files. `test/nutrition_test.dart` is listed in P1's Done Criteria though its widget asserts (542, 550) still describe today's control — they pass at P1 (the widget is untouched until P2a) and go red at P2a until P2b greens them; never used as a P2a gate.

