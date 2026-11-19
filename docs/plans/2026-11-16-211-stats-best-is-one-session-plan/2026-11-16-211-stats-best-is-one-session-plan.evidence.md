# Plan 211 — evidence

Base commit `ac1c9b33` on `claude_develop` (other sessions' `docs/plans/2026-11-15-208-fuel-burned-per-day-plan/` and `test/stats_gallery_render_test.dart` are outside this plan's scopes).

## What was built

- P1 (builder, 6.0 min): `computeExerciseMetrics(bestSingleSession: false)` and the private `_bestSingleSessionValue` (re-reads a duration or rounds total per `session.id`, largest wins, ties keep the earlier); doc comments; Records & Trends and Exercise Progress pass the flag; new `test/stats_best_single_session_test.dart` (S-21201..S-21204, S-21207, S-21208).
- P2 (builder, 6.4 min): new `test/stats_best_single_session_screen_test.dart` (S-21205, S-21206, Mock and Hive). The builder seeded in a nested `setUp` (not in the test body) because Hive hangs inside `testWidgets`; it asserted the Best through its pill because `5 rounds` also appears in the unchanged RECENT SESSIONS row.
- Lead additions: S-21209 (a tie keeps the earlier session, after mutant (i) survived); a second, slower distance run in S-21203 (after (c) was predicted to survive); docs in `docs/records_and_trends.md`; series index status.

## Lead verification

- New files: 14 + 4 tests green; the metric, records-screen, instrument-list (service and screen) and pace files green in the builders' runs; `ui_standards_contract_test` and `docs_indexing_contract_test` green (72 with the new files).
- Mutation pass, ten mutants: (a) records screen drops the flag, (a2) Exercise Progress drops it, (b) flag defaults to `true`, (c) guard removed (re-read every metric), (d) smallest wins, (e) grouped by day, (g) secondary figure is the total, (h) the Instruments caller passes the flag: all killed. (f) no `> 0` guard: SURVIVED, equivalent (a zero winner equals the total's own zero). (i) tie keeps the later session: SURVIVED, killed once S-21209 was added. Sources restored and compared after each.
- Review (crew-reviewer): APPROVE, 0 blocker, 0 major, 2 minor (table cells unqualified, fixed with "(these screens; a Stats window row keeps its total)"; series index status, updated).

## Final runs

Full suite (lead, 900 s cap): `+7757 ~4: All tests passed!`, 0 failures, about 6 min. `flutter analyze`: 181 issues (baseline 181), 0 errors. `plan-lint after`: clean (9 scenarios, 5 docs-delta rows).

## Not done / residual

- On a day with two sessions of one exercise the chart peak and that day's RECENT SESSIONS figure (the day's total) can exceed the Best (D-3, accepted, documented).
- (owner) A device check: three sessions of one cardio exercise with no distance (20, 35, 25 minutes): Records & Trends reads `35:00`; a Stats Instruments row for it still reads the window's total.
