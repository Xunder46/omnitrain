# Review: plan 222 nutrition-entry-below-recent-prs · P1+P2 · 964dc4c7..working tree
Verdict: APPROVE
Counts: blocker 0 · major 0 · minor 1 · tests: builders' runs pasted in the brief (222: 7 green; the S-18713/F-A reader green); full suite not run per brief
Diff vs Predicted Files: conforms, outside: `test/stats_heading_consistency_screen_test.dart` (the F-A order reader — brief-sanctioned "S-18713 order"; the file also carries plan 219's records-link tap change at :938-944, which belongs to 219)

## Findings
1. [Minor] docs/records_and_trends.md:68 — "directly under the Recent PRs list" is unconditional, but with no Recent PRs the entry sits directly under the ALL TIME card (S-22202 pins exactly that, and the plan's own "What the user sees" says so). Fix: one clause — "directly under the Recent PRs list when it renders, otherwise directly under the All-time card". Guard: docs only.

## Assumption Log rulings
- Base commit `964dc4c7` with plan 219 uncommitted in the tree — ratify (219's files visible in the diff stat; the `records_and_trends_screen_test.dart` and part of the `stats_heading_consistency_screen_test.dart` hunks are 219's, excluded per brief).
- "Scenario ids checked: none in the five-digit form" — ratify: no other S-222xx seen in the files read this run; repo-wide uniqueness not checked.

## Scenario coverage
S-22201 -> test/records_nutrition_entry_test.dart · 'S-22201 with a recent PR and old food logged, the entry sits below the PR list and above the search field' | present
S-22202 -> same file · 'S-22202 with food logged and no PR available, the entry stays between the ALL TIME card and the search field' | present
S-22203 -> same file · 'S-22203 with a recent PR and no food logged, the entry is absent' | present

## Brief questions
Q4 — verdict OK. S-22201 fails at base (the entry sits above the Recent PRs list, so `entry.top > prList.bottom` fails). S-22202 and S-22203 pass on both by design (pins: the entry is never lost without PRs; absent when nothing logged). The S-22202 fixture is meaningful: `seedHoldEffort(effortKind: 'timed')` writes four finished 60 s instances with no observation rows (test/helpers/repository_harness.dart:267-292), so `ex-ride` yields a cardio duration summary that survives the plan-221 guard, and `recentPRs` covers only lifts with a logged set (`stats_progress_service.dart:169`), so no `RecentPRList` renders — the position assertions compare real widgets.
D-1 verified: the move is exactly as decided (`records_and_trends_screen.dart:167-181`); `_nutritionEntry` keeps its own leading 24 (:381-386), so the spacing is one 24 in every case (no-PR: card, 24, entry, 24, search; with PRs: card, 24, PR list, 24, entry, 24, search); the empty-state branch (:151-158) is unchanged and still carries the entry; the entry's key `records_nutrition_entry`, label and navigation are untouched.
Q5 — the MODIFIED sentence is true of the new order; the tree diagrams (`records_and_trends.md:53`, `nutrition.md:51`) make no position claim between the entry and the PR list and stay true; `nutrition.md:56` and `navigation_and_screens.md:186` describe when the entry appears, not where, and stay true. Nothing else stale outside plans/history/releases (finding 1 is a precision nit, not a stale term).

## Docs delta
docs/records_and_trends.md MODIFIED `directly under the All-time` -> `directly under the Recent PRs` -> applied (:68; marker differs only in the unconditional wording, finding 1)
No doc edit outside the table needed; the plan's sweep rows check out.
