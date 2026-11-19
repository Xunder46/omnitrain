# Plan 222 — The Nutrition entry on Records & Trends sits below Recent PRs

Series: owner request 2026-11-17 ("move the nutrition full history strip below the recent PRs section"). Phone only (`lib/features/stats/records_and_trends_screen.dart`), one builder run, then docs. Status: BUILT, reviewed (APPROVE), verified, COMMITTED.

## Goal and acceptance

On Records & Trends the Nutrition entry sits directly under the ALL TIME card and above the Recent PRs list, so the personal records are pushed down by a nutrition shortcut. After this change the order is ALL TIME, Recent PRs, the Nutrition entry, then the search field and the exercise lists.

Acceptance: S-22201..S-22203 green, the ones marked "fails without" red at the base commit; `records_nutrition_entry_test`, `records_and_trends_screen_test`, `stats_heading_consistency_screen_test` green and unchanged; `flutter analyze` at baseline (181, 0 errors); full suite no new red.

## What the user sees

- Records & Trends reads top to bottom: ALL TIME, RECENT PRS, NUTRITION, the search field, the exercise lists.
- With no Recent PRs the Nutrition entry follows the ALL TIME card as before (it is still above the search field); with no food ever logged there is no Nutrition entry.
- On the first-use empty state the entry still follows the empty card (unchanged).
- To SEE it: any history with a personal record and logged food.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-1 | In `_buildContent` (`records_and_trends_screen.dart:160-178`) the line `..._nutritionEntry(context, themeColors),` moves out of the initial `children` list to directly after the Recent PRs block (`if (_recentPRs.isNotEmpty) {...}`), before the `children.add(const SizedBox(height: 24)); children.add(TextField(` search block. `_nutritionEntry` keeps its own leading 24 gap, so the spacing is one 24 in every case. The empty-state branch (`:151`) is unchanged. | `records_and_trends_screen.dart:150-180` |
| D-2 | No change to the entry's own widget, key `records_nutrition_entry`, label or navigation. | scope |

## Scenarios

| ID | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-22201 | Records & Trends (Mock) with a completed lift session (so a Recent PR exists) and old food logged (the fixtures of `test/records_nutrition_entry_test.dart` and `records_and_trends_screen_test.dart` S-913). | `records_nutrition_entry` top is greater than the `RecentPRList` bottom, and its bottom is less than the search field's top (`records_and_trends_search_field`). | the entry sits above the Recent PRs list |
| S-22202 | The same with no Recent PRs available (a history without a personal record) and food logged. | the entry is shown above the search field and below the ALL TIME card. | passes with and without the change on purpose: pins that the entry is never lost when there are no PRs (mutation: the entry added only inside the PR branch) |
| S-22203 | No food ever logged, with PRs. | no `records_nutrition_entry`; the PR list and the search field unchanged. | passes with and without the change on purpose: pins "absent when none logged" |

## Input-reality checklist

1. Writers and units: none; layout only.
2. Lifecycle: follows every load.
3. Settings: none.
4. Time: none.
5. Cost: none.
6. Words: none.
7. Slot competition: one 24 gap before the entry in every case, one before the search field.

## Phases

1. **P1 builder-app**, scope `lib/features/stats/records_and_trends_screen.dart`, `test/records_nutrition_entry_test.dart`: the move and S-22201..S-22203 added to the existing file (Mock group; it runs Mock and Hive groups, keep the position tests in the Mock group only since they are widget tests). No full suite.
2. **P2 lead**: docs, mutation pass, review, full suite.

## Readers

`test/records_nutrition_entry_test.dart`, `test/records_and_trends_screen_test.dart`, `test/stats_heading_consistency_screen_test.dart`, `test/stats_records_link_test.dart`. A test that asserts the entry's position relative to the ALL TIME card is reported, not edited.

## Mutation list (lead)

(a) the entry stays above the PR list; (b) the entry moves below the search field; (c) the entry is inside the PR branch only; (d) the entry is dropped.

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| `docs/records_and_trends.md` | MODIFIED | directly under the All-time | directly under the Recent PRs | S-22201 |

Stale-term sweep (`grep -rIn "directly under the All-time\|Nutrition entry" docs`): `records_and_trends.md:68`; the tree diagrams in `records_and_trends.md:53`, `nutrition.md:51` stay true.

## Open items

1. None.

## Predicted files

`records_and_trends_screen.dart` (+3/-2), `test/records_nutrition_entry_test.dart` (+80), one doc.

## Progress

- [x] Seeded
- [x] P1 build (5.4 min); the S-18713 reader updated by the lead
- [x] Docs, mutation pass (2 mutants killed), review (APPROVE, 1 minor docs clause fixed)

## Assumption Log

- 2026-11-17: base commit `964dc4c7` on `claude_develop` (plan 219 and the gate-test exclude are uncommitted in the tree); other sessions' `docs/plans/2026-11-15-208-fuel-burned-per-day-plan/` and `test/stats_gallery_render_test.dart` are outside this plan.
- 2026-11-17: scenario ids checked: none in the five-digit form.

## Feedback

- 2026-11-17: the S-18713 F-A order test in `stats_heading_consistency_screen_test.dart` now expects ALL TIME, RECENT PRS (when it renders), NUTRITION.
