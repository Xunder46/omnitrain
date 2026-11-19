# Evidence: plan 247 (Daily Nutrition day switcher)

Base commit 9cf691e9, branch `claude_develop`, Windows machine (1,075 environment failures at base; the check is the failing-name set against the base set).

## Suites

| Check | Result |
|---|---|
| New state tests `test/nutrition_day_view_state_test.dart` | +38 passed (Mock and Hive twins, plus Mock-only gated reads) |
| New screen tests `test/nutrition_day_switcher_screen_test.dart` | +13 passed |
| Readers set (25 files nearest the changed code, plus `ui_standards_contract_test` and `docs_indexing_contract_test`) | +514 passed, 62 failed, 0 names outside the base set |
| Full suite before the review fixes | +7093 passed, 1072 failed, 0 names outside the base set |
| `flutter analyze --no-pub` | 178 issues, 0 errors (baseline 178) |
| One existing test changed | `test/first_run_path_test.dart` S-12914: literal `todayConsumedSodium > 0` became `totals.sodium > 0` |

## Mutation pass (lead, in place, restored and byte-compared by script)

29 mutants over `nutrition_state.dart`, `nutrition_day_totals.dart`, `nutrition_screen.dart`, `log_food_row.dart`, `omni_card_header.dart`, `water_tracker_control.dart`: all killed. First pass: 3 alive (past-view clamp with a clock moved back, minus at 0 on an earlier day writing and notifying, the loading spinner) closed by S-24718, S-24719, S-24732; two "kills" that were compile errors (mutant e's first form, mutant t's header mutant failing every screen test) re-run in a valid form. Review fixes: three more mutants killed by S-24733 (tap apply without re-check), S-24734 (no epoch re-read), S-24735 (no year in title).

## Layout probe (deleted)

390x844, header: previous arrow 16 to 64 dp, title box 64 to 184 on an earlier day (83 dp wide on today where `Change target` takes the right half: 195 to 374), next arrow after the title. No overflow at 1.0x and 1.3x text.

## Crew runs

P1 state 3.9 min, P2b row 3.7, P3 state tests 6.1, P2a screen 7.2, P4 screen tests 4.7, P5 tests-only 3.1, docs keeper 4.8, reviewer 6.9, P6 review fixes 2.6. No run stopped, denied-command count 0 to 1 per run, no fix round on the builders' own output.
