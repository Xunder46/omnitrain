# Evidence — plan 132a (water total in the user's volume unit)

- Base commit `331ce598`. Working tree uncommitted.
- Touched-file run (9 files): `+681: All tests passed!`; full suite `+7071 ~2: All tests passed!` (exit 0); `flutter analyze` 181 issues (base 181).
- Mutation pass (lead, 21 one-line mutations of the new production code, each restored byte-identical): all killed; M21 (litres `.round()` to `.floor()`) survived until the lead added `formatWaterTotal (ml unit): litres round to the nearest hundredth, not down (S-13201)` to `test/utils_test.dart`, then killed.
- Layout probe S-13211: see the plan's Progress.
- Unguarded by a test: `lib/main.dart` wiring (`NutritionState(repository, settings: settingsState)`), `NutritionState.dispose` listener removal.
- Crew runs: 3 scouts, 1 architect, 3 builders (P1, P2a, P2b), 1 docs keeper, 1 reviewer. No prover run: nearly every new guard names a symbol absent at base, so `prove-red` could only say "compile error"; the lead's mutation pass replaced it.

## Revision 1 (2026-11-08): the unit follows the Weight setting
- R1 builder: 5 items, gates green (utils 153, settings_state 57, state_test 240, nutrition_test 104, interaction_flow 56, water_tap_ledger 19, ui_standards 41); R2 docs keeper: 4 items plus sweep.
- Lead: full suite `+7068 ~2: All tests passed!`; `flutter analyze` 181; `plan-lint after` clean (24 rows); grep of `preferredVolumeUnit|setPreferredVolumeUnit|preferred_volume_unit|volumeLabelForUnit` in `lib` and `test`: empty.
- Mutation pass 20 of 20 killed (M22 mapping inverted, M23 unit read from the distance setting are new).

## Revision 2 (2026-11-08): the wire's glass digit counts taps
- R3 builder gates: water_tap_ledger +20, watch_sync_request_handler +46, watch_water_log +17, watch_transport +65, ui_standards +41; lint 181.
- Lead: full suite `+7071 ~2: All tests passed!`; `flutter analyze` 181; `plan-lint after` clean (28 rows); Swift `SyncProtocolFixturesTests` pass against the edited schema description and manifest note; 5 new mutants (step ignored in the division, handler and bridge pass 250, handler unit read from distance, build ignores the step) all killed.
