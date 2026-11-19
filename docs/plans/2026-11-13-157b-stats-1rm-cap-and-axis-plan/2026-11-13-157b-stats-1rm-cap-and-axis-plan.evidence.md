# Evidence: plan 157b — Est. 1RM counts at most 12 reps; the axis is decided by majority

Baseline commit `cd117f79` (branch `claude_develop`; 157a uncommitted in the same tree, disjoint files).

## New tests

- `test/est_1rm_cap_and_axis_test.dart` — 19 tests: `S-15801 epley1RM counts at most 12 reps of a set` (plain, no store) and S-15802..S-15810b (S-15802, S-15803, S-15804, S-15805, S-15806, S-15807, S-15808, S-15809, S-15810b) inside group `` `${harness.name} — Est. 1RM cap and axis majority (plan 157b)` `` on Mock and Hive.
- `watch/watchos/Tests/WatchSessionEngineTests/WatchPersonalBestsTests.swift` — `testS15810AnEstimateCountsAtMostTwelveReps`.

## Probe (cap alone)

With only the cap applied to `epley1RM`, the 15 reader test files (609 tests) stayed green — no existing test encoded the uncapped formula.

## Axis change

One existing fixture went red: `test/exercise_metric_service_test.dart` `S-904 the Resistance value, and the axis that decides it` (Pull-up held one weightless and one weighted entry — a tie). The lead changed it to two weightless entries and one weighted, so the premise "weightless entries decide the axis" still holds as a majority.

## Swift

- `WatchPersonalBestsTests`: 22 tests.
- Whole package (`swift test --package-path watch/watchos`): 1427 tests, 0 failures.

## Mutation pass

- Phone: 10 mutants, 8 killed after two tests-only additions (skipped sets tallied, running session counted). 2 equivalent:
  - the kind check `effortKind != 'set'` in the tally — a non-set effort's rows hold no reps row and tally nowhere;
  - the requested-ids filter — every caller reads the result only with `contains` over its own ids.
- Swift: 3 of 3 mutants killed in an isolated copy of the package.

## Docs

Applied this run by the docs keeper: the four rows of the plan's `## Docs delta` table (services_and_utils.md axis bullet + cap sentence, watch_surface_wrist_logging.md formula, stats_best_load_investigation.md formula) and the stale-term sweep in the run report.
