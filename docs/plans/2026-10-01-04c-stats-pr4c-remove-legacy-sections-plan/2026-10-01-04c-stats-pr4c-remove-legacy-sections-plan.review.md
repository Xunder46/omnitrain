# Review — Stats PR 4c (remove the legacy Stats sections, the screen half)

Reviewer: Code Reviewer agent. Review 1. Tree reviewed: `develop` working tree, uncommitted.
Plan under review: `2026-10-01-04c-stats-pr4c-remove-legacy-sections-plan.md` (735 lines).
Evidence under review: `…evidence.md` (237 lines).

## Step 0 — Layer scoping

Layers in scope: `lib/features/stats/` (one file), `test/` (8 files touched + 1 added), `docs/`.
Layers skipped: `lib/data/models/`, `lib/data/repositories/`, `lib/state/`, `lib/widgets/`, `lib/core/`
(no changes in the diff).

Delivered diff: 21 tracked paths, +509 / −4507, plus 2 untracked plan folders and 1 untracked new test
file. Only one production file changed: `lib/features/stats/stats_screen.dart` (−1104 / +32, 1136
changed lines — inside the 1,500-line predicted-production hard limit).

## Step 5a — Acceptance Criteria

The plan carries `## Acceptance Criteria` (plan:175–188). Every criterion has a corresponding
implementation; no criterion is unimplemented. Verified: removed sections absent from the body;
`InstrumentList` and `FuelSection` still rendered; `ALL TIME` header restored; single entry point
retained for Records & Trends; PRs absent from Stats. No CRITICAL.

## Step 5b — Scenario Register

`## Scenarios` exists (plan:189–315). Each register entry maps to a test that exists and passes, and
each test asserts the register's stated outcome. The one scenario whose file was deleted (S-836,
km↔mi guard) is transcribed into the new guard file with the same assertion, and I confirmed the
transcription is faithful. No WARNING.

## Step 5c — Documentation falsification

DOC FALSIFICATION: ✅ PASS (32 top-level docs + `state_management/` + `widget_catalog/` — no scope
declarations exist, so rule (4) implicates the whole set; re-read against post-change `lib/`:
`stats_screen.md`, `navigation_and_screens.md`, `data_models.md`, `records_and_trends.md`,
`design_system.md`, `distance_source.md`, `session_summary.md`, `widget_catalog.md`,
`profile_and_measurements.md`, `app_philosophy.md`, `README.md`, `global_conventions.md`,
`documentation_standard.md`, `stats_best_load_investigation.md`, `docs-audit-2026-07-26.md`).
Every named file, type, constant, heading anchor and scenario ID in the touched documents exists in
the post-change tree. The three re-pointed `distance_source.md` claims are *stronger* than the plan's
Assumption 12 says and are correct as delivered (S-1001 asserts the `est.` suffix). The
`design_system.md` eyebrow claim resolves to `fuel_section.dart:83`. The `data_models.md` pointer to
`test/records_and_trends_screen_test.dart` for "Stats renders no PRs" is valid (S-913).
DOC FALSIFICATION: 🟡 WARNING — see finding 3 (false claim, but in a code comment, not in `docs/`).

## Step 5c-2 — Documentation standard enforcement

DOC STANDARD: ❌ REJECT — `docs/stats_screen.md:56` — class 2 (visual presentation) + class 4
(numeric value defined in source) — see finding 4.
DOC STANDARD: ❌ REJECT — `docs/stats_screen.md:37-38` — class 2 (layout) + behavioural prose with no
test pointer — see finding 5.
DOC STANDARD: ✅ PASS — no prohibited content added by the other nine changed documents.

## Step 5d — Global conventions

PASS (11 rules): repository-interface-only dependency, no storage access from features, DI via
constructor, environment safety (no `dart:io`, no platform checks, no SQLite import), no hardcoded
colours, no magic numbers introduced, docs-in-step-with-code, test-alongside-behaviour, plan-folder
layout, evidence-outside-plan, size ceilings respected.
N/A (4 rules): no models, repositories, state or analytics/timestamp changes in this diff.

## Findings

1. **major** | `docs/plans/…/…plan.md:392-393`, `:500-505`, `:532-549` | The plan's three scope
   declarations (`Predicted Files` ×2 and Phase 3 Done Criteria, "Nothing else — an out-of-bounds file
   is a finding") declare 3 changed files, but the delivered diff changes 21 tracked paths plus a new
   test file. Five touched documents are named nowhere in the plan (`app_philosophy.md`,
   `data_models.md`, `navigation_and_screens.md`, `profile_and_measurements.md`,
   `records_and_trends.md`) and `test/entry_identity_summary_test.dart` is missing from the Files
   Affected table. | Restate the three declarations to match the delivered diff (the widening is
   correct under the doc-falsification step; only the declaration is wrong), then re-run
   `pr-scope-guard`. | @developer

2. **minor** | `…plan.md:612` and `…evidence.md:114` | The recorded final test line is `+3230 ~1`;
   two fresh runs of the same tree print `+3229 ~1`. Against the recorded pre-change baseline
   (`+3256 ~1`, evidence:10) the real delta is −27, while the plan's formula predicts −25, so 2 tests
   are unaccounted for, not the 1 the evidence reconciles. The evidence also mixes bases (printed
   `+` for the delta, executed counts for the formula), which is what hides the second one. | Correct
   the recorded line to `+3229 ~1` and restate the residual as 2, or explain it. No live-behaviour
   test was lost — the retirements were re-read and guard removed surfaces only. | @developer

3. **minor** | `lib/features/stats/stats_screen.dart:73` | The comment claims "the same computation
   produces the PR data Records & Trends shows". It does not: this screen reads only
   `progressData.window`, and Records & Trends computes its own data. | Delete the clause. | @developer

4. **minor** | `docs/stats_screen.md:56` | An edited line restates a source-defined threshold and an
   icon ("with a flame icon once the streak reaches three days") — prohibited classes 2 and 4. Editing
   the line kept the prohibited content instead of removing it. | Drop the icon and the threshold;
   point at the test that verifies the streak presentation. | @developer

5. **minor** | `docs/stats_screen.md:37-38` | Newly added behavioural prose describes the loading
   state ("the body is a centred spinner"). No test asserts it — no stats test references
   `CircularProgressIndicator` — so the claim is unverified, and "centred" is class 2. | Replace with
   a test pointer, or add the assertion and point at it. | @developer

6. **minor** | `…plan.md:705` (Assumption 12) | The assumption says the re-pointed
   `docs/distance_source.md` claims cite `test/stats_legacy_removal_test.dart` (S-1209). As delivered
   they cite `test/instrument_list_screen_test.dart` (S-1001), which is the stronger citation. | Amend
   the assumption to match what shipped. | @developer

7. **nit** | `test/screen_widget_test.dart`, `test/header_standardization_test.dart` | Formatter churn
   inflates the diff. All 160 added lines in `screen_widget_test.dart` are reflow of *kept* tests (the
   feeling guards and the toggle test) — the file adds no new tests; ~21 lines in
   `header_standardization_test.dart:1131-1165` are the same. Plan-sanctioned
   (`gateway.sh format` on whole files), and the reflow brings previously unformatted code into the
   project style. | Accept; prefer formatting touched ranges only in future. | @developer

8. **minor** — carry to 4c2 | `docs/stats_best_load_investigation.md:169,247`,
   `docs/docs-audit-2026-07-26.md:22` | Dated records still name the removed Recent PRs / NUTRITION
   surface. The investigation record is dispositioned (superseded banner already assigned at
   `…4c2…plan.md:149`); the audit record is not dispositioned by anyone. | Keep the banner work in
   4c2; add the audit record to the same banner list. | @developer

## Check areas from the brief

1. **Nothing live removed** — checked, fine. `InstrumentList` and `FuelSection` are still rendered,
   `ALL TIME` and the aggregate card are intact, the Records & Trends entry point is unchanged, and
   the empty state is unchanged. The removed code is unreachable from the new body.
2. **The guard can fail** — checked, fine. `test/stats_legacy_removal_test.dart` scans the screen
   source for 10 forbidden fragments and runs 3 fixtures through 2 harnesses; the source scan fails if
   a fragment returns.
3. **Retired tests only guarded removed surfaces** — checked, fine. Every retired assertion I read in
   the eight touched test files targets a removed section, chart or pill. No retired test guarded
   behaviour that still exists.
4. **Assertion flips are non-vacuous** — checked, fine. Each `findsOneWidget → findsNothing` flip is
   paired with a positive assertion in the same test (`ALL TIME` retained, S-1015 re-targeted to
   ordering, S-913 tapping through and re-asserting the same PR names).
5. **Formatter churn** — checked; see finding 7.
6. **Test-count reconciliation** — checked; does not hold exactly. See finding 2.
7. **Docs** — checked; one falsification warning (finding 3, in code not in `docs/`) and two
   doc-standard rejections (findings 4, 5).
8. **Scope** — checked; the delivered diff is wider than declared (finding 1), but every widening is
   required by the doc-falsification step. Nothing outside `lib/features/stats/` was touched in
   `lib/`, and nothing in `watch/` or `scripts/`.

## Verification

- `.github/copilot/scripts/macos/gateway.sh lint` → `196 issues found. (ran in 4.8s)` (0 errors; bar ≤199 met).
- `.github/copilot/scripts/macos/gateway.sh test` → `01:22 +3229 ~1: All tests passed!` (exit 0; reproduced twice).

## Scope budget

Six substantive findings in this PR (1–6) — at the `pr_scope_budget.md` §1 threshold of 6, not over it,
so no split is needed. All six are cheap single-file edits: five prose/comment/plan lines and one
plan-scope restatement. Finding 1 is a plan-bookkeeping defect, not a code DESIGN defect spanning
layers, so the "DESIGN finding spans layers" split trigger does not fire. Finding 8 is not this PR's
work. Do not add scope: fix 1–6 in one round, then re-review.

## Recommended fix order

Fix now (one round, all cheap): 1, 2, 3, 4, 5, 6.
Carry to 4c2: 8.
Accept as-is: 7.

---

## Round 2 — re-review after fix round 1

Reviewer: Code Reviewer agent. Review 2. Tree: `develop` working tree, uncommitted — Round 1's tree plus
the fix round. Fix items: `.work/stats-pr4c/brief-fix-1.md`. Scope: F-1…F-8 and anything the fix round
broke; Round 1's passing work is not re-litigated.

### Step 0 — Layer scoping

Layers in scope: `docs/plans/…4c…/` (plan, evidence), `docs/stats_screen.md`, two test files, and the
comment region of `lib/features/stats/stats_screen.dart`.
Layers skipped: `lib/data/`, `lib/state/`, `lib/widgets/`, `lib/core/` — no fix-round change.

Diff shape unchanged from Round 1: 21 tracked paths, +633 / −4510, `test/stats_distance_estimate_test.dart`
deleted, `test/stats_legacy_removal_test.dart` new, 2 untracked plan folders.

### Fix verification

| Item | Result | What I read |
|------|--------|-------------|
| F-1 — scope declarations | ✅ PASS | The delivered-footprint note and the three declarations now name the ten reconciled docs and `test/entry_identity_summary_test.dart`; "one production file, 8 test files and 12 docs" matches the 21-path diff |
| F-2 — recorded line + name table | 🟡 PARTIAL | The name-level table is in the evidence (43 removed / 16 added / net −27); the plan's line and reconciliation predate F-7/F-8 — finding 1 |
| F-3 — comment | ✅ PASS | `lib/features/stats/stats_screen.dart:73-74` now reads "this screen reads the window (shared with the Instruments list below)"; the "PR data" clause is gone, and the surviving claim at `:66-67` is true — Records & Trends calls the same `computeTotals()` (`records_and_trends_screen.dart:78`) |
| F-4 — streak row | ✅ PASS | `docs/stats_screen.md` ALL TIME table: no icon, no threshold; points at `test/screen_widget_test.dart`, whose S-005 guard asserts the `STREAK` pill |
| F-5 — loading prose | ✅ PASS | The untested sentence is gone and no untested claim replaced it; side effect recorded as finding 2 |
| F-6 — Assumption 12 | ✅ PASS | Now cites `test/instrument_list_screen_test.dart` (S-1001), which exists and asserts the `est.` mark |
| F-7 — PR weight unit | ✅ PASS | `test/records_and_trends_screen_test.dart`, group `Recent PRs weight unit` (~450-486): seeds in `setUp`, asserts the row text `contains(_e1RmLabel(100, 5, settingsState))` (derived from `UnitFormatter`) and that no text under the list ends in `kg`; would fail if the conversion were skipped |
| F-8 — labels at max text scale | ✅ PASS | `test/nutrition_trend_screen_test.dart`, group `Calories / Macros labels at max text scale` (~316-360): seeds in `setUp`, pumps at 5.0× and asserts each label's height `closeTo(oneLine.height, 1)`; would fail if a label wrapped |

Both red proofs in the evidence match the assertions they cite (F-7: `116.7 lbs` vs `257.2 lbs`; F-8:
`200.0` vs `100.0`), and both mutations are recorded as reverted. Nothing else in the fix round's
footprint moved: no scratch file, no stray edit outside F-1…F-8, no formatter churn, no broken doc link.

### Findings

1. **minor** | `…plan.md` (Progress → "Phase 2 status", and the Phase 2 Done Criteria reconciliation) |
   The plan's only record of the suite line and of the name-level reconciliation is pre-fix-round —
   `+3229 ~1` and `3,257 − 43 + 16 = 3,230` — while a fresh full run prints `+3233 ~1` (3,234 cases);
   only the evidence's fix-round section carries the current line. This is Round 1 finding 2's defect,
   re-created because F-7/F-8 landed after F-2's correction. | Restate both places to the current line,
   or add one line pointing at the evidence's fix-round table. | @developer
2. **nit** | `docs/stats_screen.md:30` | "The body is one of two shapes" is now the document's only
   statement of the body's shape and does not match the code, which has three branches
   (`stats_screen.dart:138-160`: the spinner while `_isLoading`, the empty-state card, the three-block
   list) — the F-5 deletion removed the sentence that described the loading branch, while plan step 23
   still lists "the loading state" as delivered. | Drop the count (or scope it to the settled body), or
   record in the plan that the loading state stays undocumented because no test covers it. | @developer

### Step 5c — Documentation falsification

The fix round edited exactly one document, `docs/stats_screen.md`, so that is the change-derived
implication set for this round.

DOC FALSIFICATION: ✅ PASS — `docs/stats_screen.md` — the edited region (lines 30-58) is true of the
post-change code: the two shapes it enumerates are the two the code renders once `_isLoading` clears,
the streak row matches what the card feeds the pill, and each pointer names a test that exists
(`test/screen_widget_test.dart` for the pill, `S-1208`, `S-1112`, `S-913`). The rest of the file is
untouched by the fix round and was verified in Round 1.
DOC FALSIFICATION: 💡 SUGGEST — `docs/stats_screen.md:30` — the body-shape count no longer covers the
loading branch — see finding 2.
DOC FALSIFICATION: 🟡 WARNING — `…plan.md` — the plan's own recorded suite line is stale — see finding 1
(plan artifact, not a reference doc).

### Step 5c-2 — Documentation standard

DOC STANDARD: ✅ PASS — the fix round only removed content: the streak row's icon and three-day
threshold (class 2, class 4) and the untested loading-state sentence are gone, and each replacement is a
test pointer. No hex literal, walkthrough, control inventory, restated numeric or roadmap heading was
added; the three guard tests in `test/docs_indexing_contract_test.dart` pass in the run below.

### Step 5d — Global conventions

PASS (2 rules): units + canonical storage (F-7 derives its expected pounds figure from the shared
formatter rather than a copied literal); reuse the canonical owner (the doc points at tests instead of
restating values, and the screen still reads the shared service).
N/A (5 rules): theme tokens, card chrome, effort-kind analytics, timestamps, instrument-panel tone — the
fix round changes a comment, doc prose and two tests; no styling, analytics or timestamp code.

### Unit tests

No gaps. The two restored behaviours are the only new coverage; both seed in `setUp`, both run inside
their file's existing `harnessFactories` loop, and both are red-proven against a tracked file. No test
references removed or renamed code.

### Verification (Round 2, fresh runs)

- `.github/copilot/scripts/macos/gateway.sh lint` → `196 issues found. (ran in 2.9s)` — 0 errors, 1
  pre-existing warning (`lib/features/routine/routine_setup_screen.dart:1046`, untouched), bar ≤199 met.
- `.github/copilot/scripts/macos/gateway.sh test` → `01:26 +3233 ~1: All tests passed!` (exit 0) —
  matches the brief's expected `+3233 ~1`.

### Scope budget

Two findings, both prose-only and single-line: one plan line and one doc clause. No split, no second code
round — the code, the tests and lint are green as delivered. Finding 1 is what keeps this round from
approving; finding 2 is a suggestion.

Round 2 verdict: CHANGES_REQUESTED (finding 1).
