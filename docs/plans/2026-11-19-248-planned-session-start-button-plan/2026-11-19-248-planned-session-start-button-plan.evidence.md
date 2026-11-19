# Evidence: plan 248 (planned rows start from a play button on today only)

Base commit 38a66c39, branch `claude_develop`, Windows machine (1,075 environment failures at base; the check is the failing-name set against the base set).

## Suites

| Check | Result |
|---|---|
| New tests `test/day_planned_start_button_test.dart` | +6 passed (S-24801..S-24806) |
| Three existing files that started a plan by tapping its row (taps moved to the play button) | passed together with the new file: 43 tests |
| Full suite, first run | +7099 passed, 1075 failed; 2 names outside the base set: `routine_session_modality_test` S-12203 and `screen_widget_test` "edit planned session opens shared form" (the reviewer found both too; one tapped the row, one the removed pencil) |
| After fixing those two taps | `routine_session_modality_test` + `screen_widget_test` + new file: +255 passed |
| `flutter analyze --no-pub` | 178 issues, 0 errors (baseline 178) |
| Contract tests (`docs_indexing_contract_test`, `ui_standards_contract_test`) | 11 red, every one in the base set (checked by name) |

## Mutation pass (lead, in place, restored and byte-compared by script)

8 mutants over `day_session_list_screen.dart`, all killed by the new file with specific failures (not compile errors: each run kept 3 to 5 tests green): Start on a future date, Start on a past day, row tap starts, row tap does nothing, Start button opens edit, bin starts, Start button removed, past-day row tap edits.

## Layout probe (deleted)

Three buttons (play, pencil, bin), 58-character title: title column 46 dp wide at 320 dp, 116 dp at 390 dp, no overflow exception. The pencil was removed (the row tap edits), leaving two buttons, the width the old pencil + bin cluster used.

## Crew runs

P1 builder 2.2 min (production + three test taps), P2 builder 4.0 min (new tests), reviewer 6.5 min. P2 was started once on the three-button design and stopped when the probe showed the squeezed title; the production code, plan and brief were rewritten before the second start. No run stopped on its own.
