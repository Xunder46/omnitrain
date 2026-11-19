# Evidence: plan 256 (Daily Nutrition search with "Add & log")

Base commit cbdd199d, branch `claude_develop`, Windows machine (1,075 environment failures at base; the check is the failing-name set against the base set).

## Suites

| Check | Result |
|---|---|
| `test/nutrition_search_screen_test.dart` (S-25601..S-25612, S-25610b, S-25611) | +13 passed |
| Readers (12 nutrition/screen files) | +319 passed, 1 red, in the base set |
| Full suite | +7239 passed, 1074 failed, 0 names outside the base set |
| `flutter analyze --no-pub` | 178 issues, 0 errors (baseline 178) |

## Mutation pass (lead, in place, restored and byte-compared by script)

14 mutants over `nutrition_screen.dart`: library filter removed, case-sensitive match, query not trimmed, in-library catalog foods offered, cap removed, no `addCatalogFoodToLibrary`, logs on today, search not cleared, search hidden in the empty state, count food logs the reference amount, order removed, clear button hidden, empty message removed, removed rows shown while searching. First pass: 2 alive (the 20-row cap, a count food with reference 2): closed by S-25611 and S-25610b. The review's removed-rows sentence had no test: S-25612 added, its mutant killed.

## Crew runs

P1 2.1 min, P2 6.9, tests-only fix 3.2, tests-only fix 2.6, reviewer 11.3. No run stopped.
