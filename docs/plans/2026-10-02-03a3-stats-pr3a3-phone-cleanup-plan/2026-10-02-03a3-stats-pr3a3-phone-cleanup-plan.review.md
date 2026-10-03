# Review — Stats PR 3a3 (phone-only cleanup)

Reviewer: Code Reviewer agent. Base: `bca8d02` (HEAD). Scope: 30 modified files (11 `lib/`, 13 `test/`,
6 `docs/`) plus untracked plan folders. Review only — no product code, tests or docs were edited.

Layers in scope: `lib/core/utils`, `lib/core/services`, `lib/data/models`, `lib/data/datasources`,
`lib/state/workout`, `lib/features/session`, `lib/widgets/chart`, `test/`, `docs/`.
Layers skipped: `lib/data/repositories` (no changes), `lib/features/*` other than session (no changes).

## Verdict

**CHANGES_REQUESTED** — 3 substantive findings (F-1, F-2, F-3). The product change itself is correct
and well-evidenced; the blockers are a plan over the size ceiling and two false statements (one in
`lib/`, one in `docs/`).

## Fix set (this PR, one round)

| # | Severity | Location | Finding | Fix | Agent |
|---|---|---|---|---|---|
| F-1 | major | `lib/data/datasources/food_catalog_loader.dart:15-17`, `:35-36` | The new comment asserts `scripts/generate_food_catalog_seed.dart` produces the seed "using [parseCatalogJson]". The script does not import the loader and does not call `parseCatalogJson`; it decodes the JSON itself and keeps a local mirror of the category→group map. The comment states a relationship that does not exist. | Delete the claim; keep only what is true (the loader parses the bundled asset). Do not restate the script's behaviour. | @developer |
| F-2 | major | `docs/plans/2026-09-26-03-stats-pr3-distance-series-index.md` (status line vs table row for 3d) | The status line says 3d "is not planned yet", while the table row gives 3d a live plan path and `docs/plans/2026-10-02-03d-stats-pr3d-late-watch-entry-plan/` exists on disk with a plan marked `Status: READY`. Two claims in one document cannot both be true. Secondary: the "then PR 4" row still lists `3a3` as a dependency while the status line declares PR 4 done. | Make the status line and the table agree on 3d's state, and drop the stale `3a3` dependency from the PR 4 row. | @developer |
| F-3 | major | `docs/plans/2026-10-02-03a3-stats-pr3a3-phone-cleanup-plan/2026-10-02-03a3-stats-pr3a3-phone-cleanup-plan.md` (810 lines) | The plan exceeds the 800-line hard limit in `.github/agents/pr_scope_budget.md` §1 "At handoff". The overflow is the Assumption Log (12 entries; A-3a3-P1-1, A-3a3-P3-1 and A-3a3-P3-3 exceed the 3-line cap) and the Progress notes; A-3a3-P3-1 also carries a raw suite count. | Trim the Assumption Log entries to the 3-line cap and move the suite output to the evidence file. | @developer |

## Carried (follow-up plan, not this PR)

| # | Severity | Location | Finding | Fix | Agent |
|---|---|---|---|---|---|
| F-4 | minor | plan `## Scenarios` S-1315, S-1317, S-1304 | Three scenario registers overstate what their tests assert. S-1315's register claims "no DISTANCE section and no DISTANCE card; the draft falls back to `EffortDefaults`", but the test asserts only that no distance target and no distance row exist. S-1317's register says "0.00 elsewhere", but the test asserts `SessionDistanceCard.absentValue` (`'—'`), because a stored `0.0` renders as absence. S-1304's register asserts an extra weight of 12.0 that the test does not check. | Amend the three registers to the asserted outcomes. | @developer |
| F-5 | minor | `test/distance_source_test.dart:9` | The file header lists S-1302 as one of its scenarios, but the file contains no S-1302 test; S-1302 appears nowhere under `test/`. The scenario is genuinely covered by the retained `S-876`/`S-877` in `test/distance_source_import_test.dart`, but the register does not mark it "Retained existing test" the way S-1318/S-1319 are marked, and the header omits S-1310, which the file does contain. | Mark S-1302 as retained in the register and correct the header's scenario list. | @developer |
| F-6 | nit | plan Assumption Log A-3a3-P2-4 | The entry says `test/tmp_probe_inverse_b_test.dart` is a leftover the owner must delete. The file is not in `git-status` and the evidence file records it as no longer present. The entry is stale. | Delete the entry. | @developer |
| F-7 | nit | `test/utils_test.dart` | The diff reflows the ramp/contrast tests (~40 lines) with no behavioural change — unrelated formatting churn in a cleanup PR. | Leave as-is or revert; no action required. | — |
| F-8 | nit | `lib/data/models/models.dart:558` | The comment reads "a distance with no source is a distance with no source, never an entry", which appears to be a typo for "never `entered`". | Correct the word. | @developer |

## Step 5a — Acceptance criteria

All ten criteria have a corresponding implementation and a passing test. AC-1 (no `resolve` in `lib/`
or `test/`), AC-2 (only the phone write and the import store a positive distance, both with a source),
AC-3/AC-4 (no suffixed id minted; an unnumbered row is in no entry and is not deleted), AC-5 (delete
removes exactly the entry's rows), AC-6 (out-of-order store still yields entry-1 values), AC-8 (no
reader of a removed rule remains), AC-10 (a later write lands on its own entry) are each asserted by
the named scenarios. AC-7 and AC-9 are satisfied by the doc diffs and the governor's green runs.
No criterion is unmet.

## Step 5b — Scenario register

S-1301, S-1303–S-1311, S-1313–S-1317 have tests that assert the registered outcome and pass.
S-1312 is asserted by `test/state_test.dart` `S-1312`. S-1318/S-1319 are correctly marked as retained
existing tests (`S-864`, `S-883`) and both exist. S-1302 has no test of its own (F-5). Three registers
overstate their assertions (F-4). No scenario is unguarded.

## Step 5c — Documentation falsification

```
DOC FALSIFICATION: ❌ REJECT — docs/plans/2026-09-26-03-stats-pr3-distance-series-index.md — status line says 3d is "not planned yet" while the table row and the on-disk 3d plan folder say otherwise → make the two agree (F-2)
DOC FALSIFICATION: ❌ REJECT — lib/data/datasources/food_catalog_loader.dart:15-17,35-36 — comment claims the seed generator uses parseCatalogJson; it does not → delete the claim (F-1)
DOC FALSIFICATION: 🟡 WARNING — docs/plans/2026-10-02-03a3-...-plan.md — incomplete: the Assumption Log is stale on the tmp probe file (F-6)
DOC FALSIFICATION: 🟡 SCOPE — docs/constants_reference.md, docs/data_models.md, docs/distance_source.md, docs/session_summary.md, docs/state_management/workout_state.md, docs/stats_best_load_investigation.md — no scope declaration; verified anyway
```

Verified true against the post-change code: `docs/distance_source.md` (no `resolve`; the import's
absent-source rule is the only place `entered` is substituted; the timed-only rule matches
`getEffortDistanceEntries`), `docs/data_models.md` (a stored `0.0` reads as absence; no reader
substitutes `entered`), `docs/session_summary.md` and `docs/state_management/workout_state.md`
(their test pointers resolve to tests that exist and contain the named S-ids),
`docs/stats_best_load_investigation.md` (the retired vocabulary is gone). No other reference doc
under `docs/` still describes a removed rule.

## Step 5c-2 — Documentation standard

```
DOC STANDARD: ✅ PASS — no prohibited content added
```

The added prose in `docs/data_models.md`, `docs/distance_source.md`, `docs/session_summary.md` and
`docs/state_management/workout_state.md` is rule-and-pointer style and names the test that verifies
each behaviour. No step-by-step flow, no visual values, no control inventory, no restated numeric, no
copied code, no roadmap, no unshipped-change note.

## Step 5d — Global conventions

```
PASS (9 rules): repository interface only, no direct storage access from state/features, no dart:io in shared code, no platform checks in shared code, no Flutter imports in models, constants over magic numbers, no commented-out code, doc pointers name existing tests, no new analyzer findings
N/A (4 rules): no analytics/timestamp changes, no modality-config changes, no theme/token changes, no new screen
FAIL: none
```

## Architecture and code quality

No architecture violation. The removals (`DistanceSource.resolve`, `_sequentialGroups`,
`_entriesAreNumbered`, `_getMetricsPerEntry`, the positional branches, the `(?:-\d+)?` id pattern) are
unreachable from the phone UI, the importer, the clone path and the routine path — verified by
grepping every `EffortObservation` construction in `lib/`. Every production writer mints a numbered id
through `LoggedEntryRows.observationId`, preserves an existing id, or uses `_clonedRowId`, whose
fresh-id fallback covers suffixed and foreign ids. `_getMetricsPerEntry` has no remaining caller.
`DistancePairing.forEntries` is still reached from `StatsProgressService` and delegates to
`EntryRows.companions`, so the pairing contract is unchanged. The D-708 draft fix reads each entry's
own row for `timed`/`drill` and leaves the `set` and `round` branches alone, as the ledger requires.
No DRY violation, no god class, no magic number introduced. The retired tests (S-818d, S-819, S-859,
the odd-observation drill test) guarded only dead behaviour.

## Test coverage

New behaviour is covered: S-1301/S-1303/S-1310/S-1316 in `test/distance_source_test.dart`,
S-1304 in `test/row_invariants_guard_test.dart`, S-1305/S-1306 in `test/entry_rows_test.dart`,
S-1307 in `test/utils_test.dart`, S-1308/S-1309 in `test/entry_identity_test.dart`,
S-1311–S-1315 in `test/state_test.dart`, S-1317 in `test/session_summary_distance_test.dart`.
The red-first requirement is met for S-1311, S-1312 and S-1317 (evidence records the failing runs);
S-1313–S-1316 are declared guards in the plan and the evidence says so. Fixture-id updates in
`test/in_session_pr_toast_test.dart`, `test/services_test.dart` and
`test/data_tracking_fixes_test.dart` are mechanical and keep the PR logic untouched.

```
🧪 MISSING: test/distance_source_test.dart — S-1302 has no test (F-5)
```

## Triage (pr_scope_budget §1 "At review")

Three substantive findings, none spanning layers, so no split is required. F-1, F-2 and F-3 are one
round of fixes. F-4 through F-8 are carried to a follow-up plan through conductor-v2. No
review → fix → review loop is proposed.

Critical: 0 | Major: 3 | Minor: 2 | Nit: 3
