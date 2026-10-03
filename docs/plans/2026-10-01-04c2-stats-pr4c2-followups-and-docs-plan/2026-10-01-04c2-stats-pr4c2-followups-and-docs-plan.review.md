# Review — Stats PR 4c2 (service/model retirement, carried items, docs)

Reviewer: Code Reviewer agent. Base `HEAD` (`c6a60548`). Change: uncommitted on `develop`, 22 tracked
files (`+3225` suite) plus 2 untracked (`lib/widgets/chart/scrollable_trend_chart.dart`,
`docs/nutrition.md`). Plan under review:
`docs/plans/2026-10-01-04c2-stats-pr4c2-followups-and-docs-plan/…-plan.md`; evidence: `…evidence.md`.

**Verdict: CHANGES_REQUESTED.** 2 major, 2 minor, 3 nits. Three substantive findings (≤ 6) — no split
required. One bounded fix round: findings 1–3, then re-run both gates.

Layers in scope: `lib/core/models`, `lib/core/services`, `lib/features` (stats, nutrition, profile
widgets), `docs/`, `test/`.
Layers skipped: `lib/data/repositories`, `lib/state`, `lib/data/datasources` bodies, `scripts/`,
`watch/` — untouched by this diff (verified with `git-diff HEAD --name-status`).

## Gates re-run by me (after all review reads; tree unchanged)

- `.github/copilot/scripts/macos/gateway.sh lint` → final line `196 issues found. (ran in 2.7s)`;
  `error •` count = 0. Bar (≤199, 0 errors, 196 expected): **met**. No issue line names any changed
  file — in particular no `unused_element` / unused import in either retired source file.
- `.github/copilot/scripts/macos/gateway.sh test` → final line `+3225 ~1: All tests passed!`
  (1 m 16 s). Bar: **met**, matches the recorded baseline.

## Findings

1. **major** — `test/stats_progress_test.dart` (retired timed-effort cases) — the retirement dropped a
   guard on **live** behaviour. Two retired tests each carried an assertion about the surviving
   `topLifts` field: the timed-effort test in `Effort-type keying` (removed name at diff `337`; its
   live assertion at diff `395` — a timed exercise must **not** appear in `topLifts`) and the
   timed-only test of `Empty states` (removed name at diff `504`; live assertions at diff `526` and
   `536` — `topLifts` is empty for a timed-only history). D-655's rule (`…-plan.md:83`) is explicit
   that a test mixing removed and live assertions "keeps its live half", and the plan repeats it at
   `…-plan.md:191`; the same change kept the live half in three identical situations
   (`… → appears in topLifts`, `topLifts is non-empty`, `topLifts and recentPRs are empty`), so the
   two timed cases are an inconsistency inside this change, not a house style. Consequence: nothing in
   the suite now asserts that a timed effort stays out of `topLifts` — `_addTimedEffort` is gone and
   the token "timed" survives in that file only in a comment (`test/stats_progress_test.dart:1767`).
   The drill equivalent is still guarded (S-008, kept per D-655). Fix: restore the live half — one
   test seeding a timed-only effort asserting `data.topLifts` is empty (the same shape as the retired
   diff `504` test minus the `topCardio` half). → @developer
2. **major** — `docs/nutrition.md:211-213` — false claim, class-5c rejection (prose asserting something
   untrue about the current product). The "Catalog loading" paragraph states that `FoodCatalogLoader`
   is the only loader and that "every environment goes through it — the Hive-backed repository and the
   in-memory mock alike". The Hive repository does (`lib/data/repositories/hive_workout_repository.dart:331`),
   but the mock reads the generated hardcoded mirror instead
   (`lib/data/repositories/mock_workout_repository.dart:220`), and `BundledCatalogSource.foodCatalog`
   (`lib/core/services/bundled_catalog_source.dart:36`) reads the same mirror. The *outcome* clause in
   that paragraph ("catalog rows are identical on web and native") is true and genuinely enforced by
   the parity groups in `test/food_catalog_load_test.dart:876` and `:1619`. Fix: delete the mechanism
   sentence (or replace it with the parity pointer) — do not restate the loader wiring. Same
   overstatement is in the loader's own class doc, `lib/data/datasources/food_catalog_loader.dart:13-15`
   (pre-existing source drift: it claims both repositories go through the loader and then contradicts
   itself in the parenthesis). → @developer
3. **minor** — `docs/nutrition.md:137-138` — overstates widget purity. The Widgets section asserts that
   no widget in `lib/features/nutrition/widgets/` "reads a repository or mutates state". No widget reads
   a repository (true), but one writes through its state owner: `log_food_row.dart:288` and `:291` call
   the nutrition state's log/unlog mutators, and `food_form.dart:401` reaches the image service off
   `foodLibraryState`. Fix: state the rule that actually holds (widgets touch no repository or storage;
   writes go through the state owners) or delete the clause. → @developer
4. **minor** — plan record hygiene (no code impact, all in the plan file the reviewer may not edit):
   (a) two `## Feedback` sections exist (`…-plan.md:602` and `:663`) and the executor's Phase-3 report
   went into the first while the second is the designated reviewer pointer — the duplicate should be
   collapsed; (b) the Assumption Log numbering repeats an entry (`…-plan.md:619` region: 11 followed by
   a second 7); (c) the `## Files Affected` Phase-3 row (`…-plan.md:526` region) omits the one doc that
   actually carried a stale claim (`docs/stats_screen.md`) and the frozen record
   (`docs/docs-audit-2026-07-26.md`), while naming five docs that were left unchanged; (d) Progress
   item 12 / the first Feedback section record Phase 3 as "Blocked (verification)" on the belief that
   "no command can be executed in this environment" — the refusals came from the *invocation form* (a
   `cd … &&` prefix, a `sh`/`bash` wrapper, or an absolute path); the literal relative form runs both
   gates green (above), so the recorded cause is inaccurate and would discourage the next agent from
   verifying. → @conductor-v2 / owner (record-only; not a code fix)
5. **nit** — `docs/data_models.md:391-392` restates a literal default from source ("`0` when unset")
   in the `FuelSummary` section; `kFuelWindowDays` in the same paragraph is correctly named-only. Small
   §3.4 risk in a document whose exception covers relationships, not values. → @developer
6. **nit** — `lib/widgets/chart/scrollable_trend_chart.dart:35-40` — the class doc still lists
   "cardio pace, cardio duration" among the Stats screen charts it replaces; both were removed in 4c
   and nothing on the Stats screen renders them. Pre-existing text, preserved byte-for-byte by the
   move (the Phase-3 comment fix touched only line 1), so it is out of this PR's scope — recorded so
   the next Stats touch corrects it. → @developer
7. **nit** — governor fact not reproducible. The recorded Phase-1 diff is "25 removed / 11 added /
   net −14"; counting test declarations in `git-diff HEAD -- test/` I get **20 removed / 9 added /
   net −11** (`fuel_row_screen_test.dart` +3, `stats_legacy_removal_test.dart` +1,
   `stats_progress_test.dart` −20/+5), with the same result under a strict and a loose pattern. A
   name-level diff can differ from a declaration count only through renames, which move both counts
   equally, so the net cannot be −14. The conclusion (net-negative; the removals are the retired
   surfaces) is unaffected. Ask the governor to state the method. → governor

## Check areas

1. **Retirement complete and safe — checked, fine.** No removed name survives in
   `lib/core/services/stats_progress_service.dart` or `lib/core/models/stats_progress.dart`; the
   analyzer reports no unused element or import in either; `topLifts` is built from the set-effort
   training days only (`stats_progress_service.dart:292`, `:359`, `:434`) and the survivors named in
   the brief (`recentPRs`, `computeNutritionTrend:1254`, `computeFuelSummary:1345`,
   `computeAdherence:1788`, `resolveWindow:1607`, `computeTotals`, `computeExerciseMetrics`,
   `computeInstrumentSections`) are intact and still behave as the docs describe. `scripts/`,
   `lib/data/` and `watch/` are untouched; the PR parity suites (`test/in_session_pr_toast_test.dart`,
   `test/pr_toast_test.dart`) are untouched and green.
2. **The D-666 guard and residue sweep — checked, fine apart from finding 1.** The sweep
   (`test/stats_legacy_removal_test.dart:510-518`, names at `:82-105`) reads both source files as text
   and asserts the absence of 22 names; it cannot pass vacuously (a bad path throws from
   `readAsStringSync`), and it would fail if any name returned — the evidence's M-3 red proof is the
   same mechanism. Against D-655's table the repointed groups kept their live halves (only the
   removed-output assertions went), with the two timed-effort exceptions in finding 1.
3. **Carried items — checked, fine.** The move is content-preserving: 369 lines before and after, the
   deleted and new bodies match apart from the two relative imports and the corrected line-1 path
   comment (Phase-2 delta of 6 bytes is exactly the two `../`); the old path is referenced nowhere in
   `lib/`, `test/` or `docs/` outside the plan/evidence records; `lib/widgets/chart/` is the right
   home because the Stats screen and the profile measurement sheet both consume it, and
   `nutrition_trend_card.dart` no longer imports from the Stats feature. The Fuel row's
   `Semantics(label: 'Nutrition trend', button: true)` wraps the whole tappable row, keeps
   `Key('fuel_row')`, and the assertion is real — label text, `button == true`, and tap-through to
   `NutritionTrendScreen` (a swallowed tap fails it). The narrow-width and 2.0-scale cases
   (`test/fuel_row_screen_test.dart`, S-1259/S-1260/S-1261) assert no exception, the row's presence,
   real values and a ≥44 dp target; the evidence's M-5 red (`RenderFlex overflowed by 678 pixels`)
   shows they would fail without the fix.
4. **Docs — two defects (findings 2 and 3), the rest checked, fine.** Scope block present and accurate
   (§4.1); no hex, line numbers, hashes, walkthroughs, roadmap or "until" phrases; 14,399 bytes (well
   under the 64 KiB ceiling); linked from `docs/README.md`; all 33 `lib|test|scripts` paths it names
   exist (0 misses), all seven link targets resolve and both anchors exist
   (`data_models.md:276`, `:375`). Every other behavioural sentence I opened maps to a test that
   asserts it — the four independent screen loads, the primer's reopen-without-marking-seen, the
   calories-only target form, the copy-vs-log distinction, the group-delete bundled guard, the
   cancel-vs-uncategorised sentinel, catalog-id photograph resolution, the `Foods I Eat` ordering rule,
   the trend/adherence/fuel computations and the `FuelSummary` invariants. The reconciled docs are true
   of the code as it now stands; the two frozen records gained only a `HISTORY` banner; the
   `stats_screen.md` one-line value-type list matches the model file; no `docs/` file outside `plans/`
   names a retired output. `docs/design_system.md` was not modified by this diff.
5. **Scope and hygiene — checked, fine apart from findings 4 and 7.** The diff matches the plan's
   `Files Affected` table plus the declared governor deletion (the moved chart) and the two new
   untracked files; no scratch, probe or placeholder file; no formatter churn outside the re-indented
   `fuel_section.dart` (declared in Assumption Log 6). Plan/evidence counts are honest except the
   two items in findings 4 and 7.

## Acceptance criteria and scenarios

- A-1 … A-10 all have an implementation and a passing test; A-6/A-7/A-8/A-9 are the new coverage
  (S-1259/S-1260/S-1261, S-1262, S-1263). A-1's "same `topLifts`" is asserted by the repointed tests
  but, for the timed-effort case, no longer asserted at all — see finding 1, which is an A-1 gap in
  coverage rather than a behavioural difference.
- Scenario register: S-1252 … S-1263 map to existing or new tests that pass and assert the stated
  outcomes. S-1251/S-1256 are defined only as scenarios — no test names them, and the pre/post
  execution they describe was impossible without a checkout (Assumption Log 3), so their intent is
  carried by the repointed tests instead. Recorded as a 🟡 WARNING for the register, not a blocker.

## Global conventions and documentation standard

- `PASS` — the applicable rules of `docs/global_conventions.md` (architecture boundaries, repository
  interface discipline, theme tokens, no magic numbers introduced, tests updated with behaviour).
  `N/A` — the rules covering analytics/timestamp/modality-config changes: this diff removes
  projections and adds no analytics.
- `DOC STANDARD` — no prohibited content added to any document: the added text is relationships,
  invariants and test pointers; no code blocks, field tables, control inventories, visual values or
  roadmap notes. Finding 5 is the one borderline numeric restatement.
- `DOC FALSIFICATION` — every implicated document read against the post-change tree. Two false claims
  (findings 2 and 3, both in the new `docs/nutrition.md`); no document asserts anything else untrue
  about the current product; no conflict found between two documents on the same area; no stale
  reference to a removed class, file or constant.

## Fix list for this round (bounded — then re-run both gates)

1. Finding 1: restore the timed-effort `topLifts` guard in `test/stats_progress_test.dart`.
2. Finding 2: delete or repoint the `docs/nutrition.md` catalog-loader sentence.
3. Finding 3: correct or delete the widget-purity clause in `docs/nutrition.md`.
4. Findings 4–7: record-only; fold into the plan file when it is next edited, or carry as a
   follow-up note. No code change.

Not in this round (needs a decision, not a fix): the plan's two `## Feedback` sections and the
contradiction between D-655's rule and its `Empty states` table row, which is what produced finding 1.

---

# Round 2 — re-review after fix round 1

**Verdict: APPROVE.** All seven fix items verified; one non-blocking nit. Scope is the fix-round
delta only (F-1…F-7) plus what it could have broken; the parts that passed in Round 1 are not
re-reviewed.

Layers in scope: `test/` (one file), `docs/` (two files), plan + evidence records. Layers skipped:
`lib/data/repositories`, `lib/state`, `lib/core/models`, `lib/features`, `scripts/`, `watch/` — no
fix-round edit (per `gateway.sh git-status` and the per-file diff stats). `lib/core/services/` was
edited and reverted; the file is byte-identical to its pre-fix state (below).

## Fix-round findings

1. 💡 **NIT (non-blocking)** — `docs/nutrition.md:137` — the purity clause says no widget in
   `lib/features/nutrition/widgets/` "touches a repository or storage directly", but
   `lib/features/nutrition/widgets/food_thumbnail_io.dart:38,48` resolves a path through the injected
   `ImageStorageService` and reads it with `File(...)` for `Image.file`. True for repositories and app
   persistence, one exception at the render edge — and `docs/nutrition.md:142` names that same widget's
   stub/IO split, so no reader is misled into wrong work. Fix (optional): scope the clause to
   repository access / persistence ownership. | @developer
2. 💡 **NIT (non-blocking)** — `…-plan.evidence.md:331` — the Phase-3 size table still records
   `docs/nutrition.md` at 14,399 bytes, a pre-fix measurement; the fix round edited that file without
   restating its size. The table is phase-scoped, so this is record drift, not a false claim. |
   @developer

## F-1 — the two restored `topLifts` guards — ✅ verified

- `test/stats_progress_test.dart:141` `_addTimedEffort` seeds a real timed effort through
  `MockWorkoutRepository` only — segment, an `effortKind: 'timed'` effort, a finished `TimedInstance`,
  and weight + reps observations. It is called at `:573` and `:629` and nowhere else: no dead helper.
- `:555` (group `Effort-type keying`) asserts only that the timed exercise is absent from `topLifts`
  (`:584`); `:617` (group `Empty states`) asserts only that `topLifts` is empty (`:638`). Both are
  plain `test()`, both sit in the groups the retired cases came from, and neither references a removed
  output.
- The mutation proof matches the assertions it cites. `--plain-name "timed"` matches exactly those two
  test names (`+0 -2`), and the recorded failing lines are those two `expect(` calls —
  `test/stats_progress_test.dart:582:9` (`Expected: false / Actual: <true>`) and `:638:7`
  (`Expected: empty / Actual: [Instance of 'LiftProgress']`). The helper's weight/reps rows are what
  makes the red real: a weight-less timed instance is skipped by the entry-row filter whatever the
  switch does, so the mutation would otherwise stay green.
- No mutation residue, confirmed independently: `lib/core/services/stats_progress_service.dart:234-243`
  is `case 'set'` plus `default: break;`, and the file's diff stat is back to `1 file changed, 24
  insertions(+), 463 deletions(-)` — identical to the evidence's "before" row.
- Counts agree: the file went `+55` → `+57`, the full suite `+3225 ~1` → `+3227 ~1`, and its diff stat
  is `171 insertions(+), 1133 deletions(-)`.

## F-2 — `docs/nutrition.md` Catalog loading — ✅ verified

`docs/nutrition.md:214-215` now claims only the outcome ("rows are identical on web and native") and
points at the `FoodCatalogSeed parity` (`test/food_catalog_load_test.dart:876`) and `Loader ↔ seed
parity (drift guard)` (`:1619`) groups. Both exist and together assert exactly that: the first pins
the seed mirror's row count to the JSON asset's, the second asserts every seed entry equals
`FoodCatalogLoader.parseCatalogJson`'s output field-for-field. The carriers are what make the parity
claim meaningful — the Hive path loads the JSON (`hive_workout_repository.dart:331`), while the mock
(`mock_workout_repository.dart:220`) and `BundledCatalogSource` (`bundled_catalog_source.dart:36`)
read the seed mirror. The false mechanism sentence is gone; no loader wiring is restated.

## F-3 — `docs/nutrition.md` widget purity — ✅ verified (one nit above)

The "reads a repository or mutates state" overstatement is gone. The replacement
(`docs/nutrition.md:137`) states the checkable half — no repository/storage access, writes through the
state owners — and the call sites that falsified the old clause (`log_food_row.dart`'s log/unlog
mutators, `food_form.dart`'s service reached off `foodLibraryState`) are exactly what the new wording
accommodates. It names no clause I cannot back with the code I read, apart from the render-edge
exception in finding 1. Re-read the whole document for leftovers of the same species: no other
loader-mechanism or purity claim remains; the remaining behavioural sentences map to the tests named
in its own "Where these claims are verified" table.

## F-4 — plan record hygiene — ✅ verified

- One `## Feedback` section (`…-plan.md:651`); it holds the reviewer pointer and the ticked checklist,
  and the executor's Phase-3 report now lives in Progress item 12 and in the evidence file.
- Assumption Log runs 1…12 with no repeat (`11` → `12`), and the `Semantics`-wrapper re-indent
  sentence is back in entry 6, the entry it describes.
- The `Files Affected` Phase-3 rows (`…-plan.md:542-543`) now name the real set: `docs/nutrition.md`
  (new) plus `docs/README.md`, `docs/widget_catalog.md`, `docs/data_models.md`, `docs/app_philosophy.md`,
  `docs/stats_screen.md`, `docs/docs-audit-2026-07-26.md`, `docs/stats_best_load_investigation.md` —
  an exact match for `git-status`'s modified-doc list. The five docs it wrongly named are gone.
- Progress item 12 and the Phase-3 status now record the invocation form as the cause of the earlier
  refusals and the gates as observed green; the string "Blocked (verification)" survives only inside
  the fix checklist that describes its removal. The phase status is **Complete**.
- "Nothing else changed" could not be diff-verified: the plan folder is untracked, so no pre-fix
  snapshot exists. Verified instead by reading the four named regions; they are internally consistent
  and the Progress table matches the evidence.

## F-5 — `docs/data_models.md` FuelSummary — ✅ verified

The `FuelSummary` section (`docs/data_models.md:375-399`) no longer restates a literal default. The
fields and their has-flags are named only (`hasCalorieTarget` / `hasProteinTarget`, "the Fuel row's
absent marker"); the remaining `null` and `0` mentions are absence semantics, not a restated constant.
`kFuelWindowDays` is still name-only.

## F-7 — the counting method in the evidence — ✅ verified

`…-plan.evidence.md:458-470` states the method honestly — the governor ran the full suite at HEAD in a
scratch worktree and again on the working tree with the JSON reporter, then compared **executed
test-case names** — and contrasts it with the declaration count (20 removed / 9 added / net −11). The
numbers it quotes are the evidence's own: the post-4c baseline `+3233 ~1` (`:147`) and the Phase-1
close `+3219 ~1: All tests passed!` (`:145`), a delta of 14. Nothing invented; the loop-over-both-
implementations explanation accounts for executed cases exceeding declarations on both sides.

## Anything the fix round broke — none found

Doc links: the two edited docs keep their link sets and both anchors (`data_models.md#nutrition-models`,
`#fuelsummary`); `test/docs_indexing_contract_test.dart` is green in the full suite. No new
unverifiable claim beyond the two nits above. No stray edit: `git-status` lists only the expected
tracked files plus the two declared untracked ones and the plan folder — no scratch, probe or
placeholder file. No formatter churn: the fix round's diff stat is confined to the test file and the
two docs.

## Gates re-run by me (tree unchanged during the run)

- `.github/copilot/scripts/macos/gateway.sh lint` → `196 issues found. (ran in 2.6s)`. `error •` count
  = 0 (all 196 lines read); one `warning •`, the pre-existing
  `lib/features/routine/routine_setup_screen.dart:1046:12`. Bar (≤199, 0 errors, 196 expected): **met**.
- `.github/copilot/scripts/macos/gateway.sh test` → `01:17 +3227 ~1: All tests passed!`. Bar: **met**,
  two above Round 1's `+3225 ~1` — exactly the two restored guards.

## Documentation checks (this round's delta)

- `DOC STANDARD: ✅ PASS` — no prohibited content added: the added text is a test pointer (the
  preferred form) and a rule; no hex, line numbers, hashes, walkthroughs, field tables or roadmap
  notes. The one deletion is in `docs/data_models.md`.
- `DOC FALSIFICATION: ✅ PASS (2 implicated re-read)` — `docs/nutrition.md` and `docs/data_models.md`
  verified against the post-fix tree. The rest of the set was falsified in Round 1 against the same
  tree, and the fix round's only code delta is a test file, which cannot falsify a claim (adding tests
  can only make a test pointer truer). No conflict found between two documents.
- `DOC FALSIFICATION: 💡 WARNING` — `docs/nutrition.md` — incomplete only in the literal sense of
  finding 1; the section's intent is stated and its exception is named two sentences later.
- Global conventions: `PASS (1 rule): effort-kind drives analytics` — the restored guards assert it
  directly and the service's `'set'`-only switch confirms it. `N/A (6 rules): no unit, theme, card
  chrome, timestamp, canonical-owner or instrument-panel change in this round's delta`.

## Fix list for this round

None — no changes requested. Both nits are non-blocking and may be folded into the next touch of these
files.

---
⏸️ **PIPELINE COMPLETE** — Waiting for your confirmation.
Ready to merge.
