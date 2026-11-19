# Plan 208 evidence

Implementers: baselines (flutter analyze count, red/green of every named test file), red-then-green tables per scenario, suite outputs. Plan: `2026-11-15-208-fuel-burned-per-day-plan.md`.

## Baseline

- Base commit `d5b4dc18b522777b52967be43a840d0a9ed4feea` on branch `claude_develop` (the working tree is shared with another session that has unrelated uncommitted watch/timer edits).
- `flutter analyze` before the first edit: **181 issues** (0 errors).
- After the build: **181 issues**, none in the files this plan touches that were not already there.

## How the build ran (crew, one concern per run)

| Run | What | Result seen by the governor |
|---|---|---|
| P1a | production: calories-only split (`FuelSummary`, service counts, `FuelSection`, two arguments in `test/stats_gallery_render_test.dart`) | diff read against the brief: identical to the exact text given |
| P2a | production: `HealthActiveEnergySource`, gateway per-day read with the `dayQuery` seam, `HealthPrefs.readActiveEnergyKey`, `SettingsState` switch and gate, `main.dart` wiring, `test/health_active_energy_read_test.dart` | diff read; one builder deviation (an explicit `as` cast in `main.dart`, correct: the declared type does not promote) |
| P1b | tests: `test/fuel_section_widget_test.dart`, `test/fuel_row_screen_test.dart` rewritten for the split (S-20801..S-20805) | 14 + 58 tests green |
| P2b | production: Settings row on iOS and Android; new `test/health_active_energy_settings_screen_test.dart` (S-20829) | the nine other Settings readers stayed green with no edit |
| P3a | production: `burnedPerDayAverage`, `hasRecentFood`, the burn-only card, the reader and its timeout, `StatsScreen` wiring | diff read; lead ran `dart format` by path on the five files that were format-clean at the base |
| P3b | tests: `test/fuel_burned_per_day_test.dart` (service scenarios, Mock and Hive) | 33 tests green |
| P3c1 | tests: widget scenarios in `test/fuel_section_widget_test.dart` (order, wording, burn-only, not tappable) | 24 tests green |
| P3c2 | tests: `test/fuel_burned_per_day_screen_test.dart` (wiring, tap, hide, empty state) | 14 tests green |
| P2c | tests: `test/health_active_energy_startup_wiring_test.dart` (S-20850), added after the lead's mutation prep found `main.dart`'s `activeEnergySource:` line unguarded | 2 tests green |
| docs | crew-docs-keeper over the 7 docs of the Docs delta, then the lead fixed the two stale claims the keeper reported outside its scope (`docs/widget_catalog.md`, `docs/state_management/app_state.md`) | `plan-lint after` clean (34 scenario rows, 17 docs-delta rows); `data_models.md` 51,948 B |
| lead edits | `ios/Runner/Info.plist` sentence (D-10), `android/.../AndroidManifest.xml` `READ_ACTIVE_CALORIES_BURNED` (D-16) (outside the builders' write ceiling); three tests-only additions after the mutation pass (below) | |

Added during the build and not in the scenario tables: **S-20849** (the Stats empty state keeps no Fuel card, `test/fuel_burned_per_day_screen_test.dart`), **S-20850** (the startup hands the gateway to the switch, `test/health_active_energy_startup_wiring_test.dart`), **S-20851** (a `FuelSummary` built without `hasRecentFood` is the normal tappable card, `test/fuel_section_widget_test.dart`).

## Red-then-green (how guards were proved)

The builders wrote tests after the production code (the plan's "write the test first" was not followed for P2 and P3 because the production code was briefed as exact text first). The proof that each guard guards is therefore the governor's mutation pass, not a base-commit red run: a mutation script (in the governor's scratchpad, backup kept outside the tree, `cmp` after every restore) applied one single-line change at a time to the new code and ran the relevant test files.

- 51 mutants: thresholds (`kFuelMinSplitDays` 2 to 1, `kFuelMinActiveEnergyDays` 3 to 2 and 4), comparison arms (`>=` to `>` on both split sides, `<` to `<=` on the floor, `<= 0` to `< 0`, the finite check dropped), the window (includes today; includes d8; reader given shifted days; 14-day visibility edge), the gate (each of the two burn arms dropped), the failure arms (timeout dropped, catch rethrows), every burn-only branch in `FuelSection` (tappable, logged-days, figures, sentence, per-session always / never, per-day hidden, `_burnOnly` forced false), the Stats wiring (reader argument dropped), the Settings state (gate `!= on` to `== off`, wrong persistence key, wrong load key, null source grants), the Settings row (iOS gate, Android gate, value, `onChanged`, denied notice, label), the gateway (DST day bounds run under `TZ=America/New_York`, end boundary, start boundary, no summing, day result dropped, a throwing day propagates), the unavailable gateway, and the `main.dart` wiring (the file is CRLF: the mutant text uses `\r\n`).
- First pass: 46 killed, 3 alive, 2 skipped by the script (one text occurred 3 times, one was the CRLF file).
  - Alive 08 (`hasRecentFood` default `false`) and 26 (figures drawn in burn-only mode when a summary carries them): closed by lead-written widget tests `S-20851` and `S-20841 burn-only never draws intake figures, even from a summary that carries them`.
  - Alive 34 (switch gate `== off`, so a denied switch would read): closed by the lead-written `S-20824 ... a refused switch (denied) reads nothing and never calls the source` on Mock and Hive.
  - Skipped 11 and 51: the mutation text was made unique / CRLF-aware and both are killed.
- Second pass over 08, 11, 26, 34, 51: **all killed**. Result: **51 of 51 killed, 0 equivalent mutants left**; every restore was byte-identical (`cmp`).
- Guards that pass on purpose before and after the change (S-20806, S-20832, S-20842, S-20843, S-20845): each has a named killing mutant above (floor 2 and 4, gate arms 18/19, visibility edge 21).

## Suite lines (governor, observed)

- Relevant files, one run: `+235 ~1` all passed (`fuel_section_widget_test`, `fuel_row_screen_test`, `fuel_summary_window_test`, `fuel_burned_summary_test`, `stats_fuel_horizon_screen_test`, `stats_gallery_render_test`, `fuel_burned_per_day_test`, `fuel_burned_per_day_screen_test`, `health_active_energy_read_test`, `health_active_energy_settings_screen_test`, `health_platform_test`); the one skip is an existing gallery test.
- DST scenarios: `TZ=America/New_York flutter test test/health_active_energy_read_test.dart --plain-name "S-20821"` → 1 passed, not skipped; `TZ=America/New_York flutter test test/fuel_burned_per_day_test.dart --plain-name "S-20835"` → 2 passed, not skipped.
- Contract tests: `test/ui_standards_contract_test.dart` + `test/docs_indexing_contract_test.dart` → 54 passed.
- Full suite (`with-timeout.sh 900 flutter test`, 7 min): **+8110 ~4 -1**. The one failure is `test/watch_timer_push_test.dart` `S-6323 ... the phone finishing the old one does not stop the new clock`: a phone-to-watch timer message the test expects to be empty. It is in the watch timer code another live session has uncommitted (`lib/state/workout/timer_manager.dart`, `lib/state/watch/watch_timer_adoption.dart`, `lib/state/workout/session_core_io.dart`), none of which this plan touches; this change does not import any of it. It was not reproduced on the base commit (no isolated base checkout was made), so it is reported as "not caused by this plan, owned by the other session", not as "pre-existing".
- Invariants: `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` → empty; `grep -rln "package:health/" lib | grep -v health_platform_gateway_io.dart` → empty.

## Provider and runner notes

All builder runs finished first time (9 builder runs, one docs run, one review run so far); no run stopped for loop, denied, filler or no_write. One shared-runner effect: the other session's writer runs share the two-writer cap, so Phase 2a had to wait for a slot and the order was reshuffled (1b before 2b).
