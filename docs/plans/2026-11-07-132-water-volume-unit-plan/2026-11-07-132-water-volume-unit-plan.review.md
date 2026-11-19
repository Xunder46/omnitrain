# Review — plan 132 (water total in the user's volume unit, 132a phone only)

# Review: 2026-11-07-132-water-volume-unit-plan · P1, P2a, P2b, P3 · HEAD..working tree
Verdict: APPROVE
Counts: blocker 0 · major 0 · minor 2 · tests: not run this review (per brief, the governor ran them: every touched file green — 681 tests in the nine touched files — then the full suite; counts live in the plan's Progress, not seen here)
Diff vs Predicted Files: conforms (26 files: 10 lib, 8 test, 8 docs — all inside the plan's predicted set; the only absent predicted file is `test/first_run_path_test.dart`, untouched because P2b item 6's re-derivation found no `water_tracker_label` placement change to make; it ran green with the nine)

## Findings

1. [Minor] `test/water_tap_ledger_test.dart:45` — `expect(kWatchWaterTapsPerDay, 500)` was moved out of the pre-existing `waterGlassesFor` test into the new `waterStepMlFor` test; the plan's Readers section said lines 28–33 "stay as-is". The assertion itself is preserved and still runs, so nothing a user sees changes; a maintainer diffing the file sees a changed guard the plan promised untouched. Fix: none required; move the expect back into the `waterGlassesFor` test if the next pass touches the file. Guard: the existing assertions themselves (S-13203's new test keeps the constant pinned).
2. [Minor] `docs/state_management/nutrition_state.md:64` — the `applyWatchWaterTap` row was rewritten to `±waterStepMl` but is the only changed behaviour sentence in the touched docs that names no test (`Verified by` is on every other new/changed sentence in `data_models.md`, `nutrition_state.md`, `db_integration.md`, `nutrition.md`, `home_screen.md`). The step behind watch taps is in fact tested (S-13205's watch-tap ladder), so the sentence is true — it just points nowhere. Fix: append `verified by test/state_test.dart` (group `NutritionState volume unit`: S-13205, watch-taps part) to the row, or fold the row into the neighbouring `test/watch_water_log_test.dart` S-94a sentence. Guard: the docs-keeper's own rule (P3 done criteria).

## Narrow questions

1. **Listener lifecycle.** `NutritionState` adds `_onSettingsChanged` in its constructor (`lib/state/nutrition_state.dart:18`, after `_rememberedWaterVolumeUnit` is snapshotted at line 16, so the first settings notify is not mistaken for a unit change) and removes it in `dispose()` at `lib/state/nutrition_state.dart:35–37` — `removeListener` runs before `super.dispose()`. App code: `lib/main.dart:339` is the only construction site with `settings:`; nothing in `main.dart` calls `NutritionState.dispose`, so on the happy path the listener is added and never removed — but both states live for the process lifetime, the same lifetime every other state has today, so nothing leaks beyond a unit the app already owns. A notify after dispose cannot come through the listener: it is removed first, so a later `SettingsState.notifyListeners` finds no callback; nor can the listener outlive the disposed `NutritionState` and throw from `notifyListeners`. Note (not a finding): no scenario names a dispose path, and no test exercises `dispose()` + unit flip; the removal is hygiene following the `watch_timer_adoption.dart` precedent and is unproven by a test.
2. **Normalisation pinned.** Yes — the three copies (`lib/core/constants/water_constants.dart:29–34` inlined in `waterStepMlFor`, `lib/core/utils/unit_formatter.dart:157–160` in `normalizeVolumeUnit`, `lib/state/settings/settings_state.dart:189–194`/`349–359` inline in setter and load) are each pinned by a test enumerating the same aliases: `test/utils_test.dart` `normalizeVolumeUnit collapses floz variants and unknowns to ml` (`'fl oz'`, `'floz'`, `'oz'`, `'OZ'`, `' floz '`, null, `'bogus'`), `test/water_tap_ledger_test.dart:36–47` `waterStepMlFor: 250 ml by default, 237 ml for the floz unit (S-13203)` (`'floz'`, `'fl oz'`, `'oz'`, null, `'stone'`), and `test/settings_state_test.dart` `SettingsState normalizes preferred volume unit variants, unknowns fall back to ml (S-13204)` (`'fl oz'`, `'OZ'`, `'floz'`, `'litre'`). If any one copy dropped an alias (e.g. `'oz'` from `waterStepMlFor`), its own test goes red; the step and the label cannot split silently.
3. **UI standards.** No written standard broken. Both `IconButton`s keep the explicit `shape:` + `OmniTheme.buttonIconRadius` contract (`lib/features/nutrition/widgets/water_tracker_control.dart:116–119, 151–154`), both have tooltips from `formatWaterSpoken`, no colour literal (only `themeColors.*` and `theme.colorScheme.primary`), no raw `Card`/`SnackBar`. The new Settings row reuses the section's shared `_SettingsRow` + `_SegmentedToggle` + `_SurfaceDivider` pieces exactly like the Distance/Height rows, labelled via `volumeLabelForUnit`. No allowlist entry was added, no ratchet moved (`test/helpers/ui_standards_allowlist.dart` has no water entry; the contract test is green per the governor).
4. **Doc sentences name real tests.** Checked: data_models.md points at `test/state_test.dart` `incrementWaterForDate stores +250 ml and notifies` (state_test.dart:4375 ✓), `decrementWaterForDate at 0 is a no-op (no negative ml)` (:4409 ✓) and group `daily water log` (:4357 ✓), and `test/water_tap_ledger_test.dart` group `water constants (D-11)` + the S-13203 test (water_tap_ledger_test.dart:27, 37 ✓); nutrition_state.md points at S-13216 and S-13206 (both in state_test's `NutritionState volume unit` group ✓) and test/nutrition_test.dart's S-13208 ✓; nutrition.md points at S-13210 (`tooltips and the Semantics label speak the amounts (fl oz)` ✓), S-13207's `1500 ml in ml reads 1.5 L with step 250 ml` ✓ and S-13208 ✓ — every name exists verbatim. CRLF: `git diff --stat` shows `docs/data_models.md | 9 +-` and `docs/state_management/nutrition_state.md | 12 +-` — only the touched lines changed, so no line-ending rewrite happened.
5. **Assumption Log rulings.** See block below — all four ratified.

## Assumption Log rulings

- A-1 (US step = 8 fl oz = 237 ml, not the 250 glass shown as 8.45 oz): **ratify**. Implemented as `kWaterOzStepMl = 237` with the owner's non-objection on record; re-derivable arithmetic (8 × 29.5735295625 = 236.588 → 237) and pinned by S-13203 in `utils_test` + `water_tap_ledger_test`. Changing it later is one constant, as the log says.
- A-2 (wrist counts whole 250 ml glasses until 132b): **ratify**. The gap is stated only where the wire is described, as agreed: the `water_constants.dart` header ("The watch wire still counts whole glasses of [kWaterGlassMl]"), the `constants_reference.md` `waterGlassesFor` row, and `docs/nutrition.md`'s wire paragraphs (431–437 untouched); the phone-side docs claim only the phone side.
- A-3 (`millilitres` spelling in home_screen.md): **ratify, applied** — the keeper rewrote the sentence carrying it and `millilitres` no longer appears anywhere in `docs/widget_catalog/home_screen.md`.
- A-4 (no back-compat for water rows): **ratify**. Storage shape is unchanged (ml keyed by `dateMs`, `applyWaterTap` ledger untouched per S-13212), so no migration is owed.

## Docs delta

All 25 rows applied; markers gone from their docs (old markers absent, new markers present in the diff — consistent with the governor's clean `plan-lint after`):

| Doc | Change | Status |
|---|---|---|
| docs/constants_reference.md | MODIFIED `Milliliters per logged glass` → `Milliliters per tap with the ml unit` | applied |
| docs/constants_reference.md | ADDED `kWaterOzStepMl` | applied |
| docs/constants_reference.md | MODIFIED display-boundary sentence | applied |
| docs/constants_reference.md | ADDED `waterStepMlFor(unit)` | applied |
| docs/data_models.md | MODIFIED storage-boundary sentence | applied |
| docs/data_models.md | REMOVED `waterTodayGlasses` row | applied |
| docs/data_models.md | MODIFIED increment row | applied |
| docs/data_models.md | MODIFIED canonical-step sentence | applied |
| docs/data_models.md | MODIFIED decrement row | applied |
| docs/state_management/nutrition_state.md | MODIFIED storage-boundary sentence | applied |
| docs/state_management/nutrition_state.md | REMOVED `Derived by waterGlassesFor(waterTodayMl)` row | applied |
| docs/state_management/nutrition_state.md | ADDED `waterVolumeUnit` row | applied |
| docs/state_management/nutrition_state.md | MODIFIED increment row | applied |
| docs/state_management/nutrition_state.md | MODIFIED decrement row | applied |
| docs/state_management/nutrition_state.md | MODIFIED `applyWatchWaterTap` row | applied (but see Finding 2: no test name) |
| docs/state_management/nutrition_state.md | MODIFIED `.waterTodayGlasses` → `.waterVolumeUnit` consumer sentence | applied |
| docs/widget_catalog/home_screen.md | MODIFIED total-in-unit sentence | applied |
| docs/widget_catalog/home_screen.md | MODIFIED step-sourcing sentence | applied |
| docs/db_integration.md | MODIFIED `the on-screen total` sentence | applied |
| docs/db_integration.md | MODIFIED `deltaMl` = ± the current step | applied |
| docs/db_integration.md | MODIFIED tap-step sentence | applied |
| docs/theme_and_settings.md | MODIFIED units bullet (Volume added) | applied |
| docs/state_management/app_state.md | ADDED `preferredVolumeUnit` | applied |
| docs/state_management/app_state.md | ADDED `setPreferredVolumeUnit(String)` | applied |
| docs/nutrition.md | ADDED water-control total paragraph | applied |

Doc edit the table does not name: `docs/constants_reference.md` — the `waterGlassesFor(volumeMl)` row was rewritten to "The whole-glass count the watch wire still sends for a stored volume (the phone's own screen shows the total in the user's unit instead); the one place it is derived". Extra edit beyond the 25 rows, but true (matches the `water_constants` header and the untouched `watch_reference_sync` wire) and consistent with the delta's intent — listed, not charged.

## Scenario coverage

- S-13201 → test/utils_test.dart · `formatWaterTotal (ml unit): ml below 1000, litres with at most two decimals above`; `formatWaterSpoken (ml unit): milliliter and liter, singular at 1`; plus the rounding add-on `litres round to the nearest hundredth, not down (S-13201)` (the mutation-pass survivor)
- S-13202 → test/utils_test.dart · `formatWaterTotal (fl oz unit): whole rounded ounces`; `formatWaterSpoken (fl oz unit): fluid ounces, singular at 1`
- S-13203 → test/water_tap_ledger_test.dart · `waterStepMlFor: 250 ml by default, 237 ml for the floz unit (S-13203)`; test/utils_test.dart · `waterStepLabel: the per-tap amount for each unit (S-13203)`
- S-13204 → test/settings_state_test.dart · default, variants, persist+reload, notify-once (four tests)
- S-13205 → test/state_test.dart · `S-13205 the fl oz unit steps 237 ml through plus, minus and watch taps; the ml unit still steps 250`
- S-13206 → test/state_test.dart · `S-13206 a unit switch notifies NutritionState exactly once; another setting is silent; waterTodayMl never rewrites`
- S-13207 → test/nutrition_test.dart · four parametrised `S-13207 <ml> ml in <unit> reads <total> with step <step>` cases + `S-13207 each tap calls its own callback exactly once` (callback-fired-once and minus-disabled-at-0 are asserted per case)
- S-13208 → test/nutrition_test.dart · `S-13208 the card follows a volume-unit change with no other call`
- S-13209 → test/interaction_flow_test.dart · `S-13209 the Volume row follows Distance and flips the unit` (order Distance < Volume < Height asserted positionally)
- S-13210 → test/nutrition_test.dart · `S-13210 tooltips and the Semantics label speak the amounts (ml)` and `(fl oz)`
- S-13211 → not a committed test (per plan/brief): the governor's 390×844 probe with real font metrics; no doc claim about it
- S-13212 → test/watch_water_log_test.dart · glass asserts rewritten to `waterTodayMl` (:156, :294); test/watch_sync_request_handler_test.dart · S-94a-24's `waterPayload()['glasses'] == waterGlassesFor(nutrition.waterTodayMl)` — the wire guard itself; test/water_tap_ledger_test.dart · `waterGlassesFor` + `kWatchWaterTapsPerDay` assertions kept
- S-13213 → test/state_test.dart · `S-13213 a plus parked mid-write keeps the unit it read at its closure start; the queued next write uses the new unit` (gated `_GatedWaterRepo`, notify count 4)
- S-13214 → test/nutrition_test.dart · `S-13214 an unknown volume unit reads as ml`; test/utils_test.dart · `normalizeVolumeUnit collapses floz variants and unknowns to ml` + `waterStepLabel('bogus')`
- S-13215 → test/state_test.dart · `S-13215 a 237 ml step reaches a non-multiple day and floors exactly at 0` (526 → 289 → 52 → 0, one write at 0, then +237)
- S-13216 → test/state_test.dart · `S-13216 a null-settings NutritionState stays ml; an unbound SettingsState mutation notifies nothing here`

No scenario of S-13201…S-13216 is without a test that would fail without the change (S-13211 by design: probe, not a test).
