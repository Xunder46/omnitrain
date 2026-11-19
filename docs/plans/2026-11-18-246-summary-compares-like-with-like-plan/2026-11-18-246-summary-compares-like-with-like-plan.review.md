# Review: plan 246 · P1–P3 (service+model, screen caption, screen tests) · cd2fc178..working tree
Verdict: APPROVE WITH FIXES
Counts: blocker 0 · major 1 · minor 3 · tests: not run (brief: "Run no test"; lead's observed output, pasted below)
Diff vs Predicted Files: conforms, plus `test/food_catalog_load_test.dart` (the plan's Assumption Log already names it as an unrelated uncommitted file; 1-line `!` removal, not plan work)

Lead's observed counts (per brief, not re-run): 238 tests green across the comparison, services and summary test files; 10 hand-applied mutants killed (2 first-pass survivors: one script error aimed at a same-text different method, one closed by S-24614); analyze 178 issues = plan baseline; full-suite failing set equals the base commit's environment failures; plan-lint clean.

## Findings
1. [Major] `lib/core/services/session_summary_service.dart:546-552` (`_routineIdOf`) — D-24602's "an empty string counts as null" boundary for `routineTemplateId` is implemented but has no test: no test in `test/summary_comparison_basis_test.dart` or `test/services_test.dart` seeds `routineTemplateId: ''`. A mutant returning `id` as-is (treating `''` as a routine id) survives: a free session carrying an empty routine id would then be matched only against other empty-id sessions instead of same-modality type sessions, and the screen's basis would say `Compared with your last this routine (…)` for it. Fix: one added case in `test/summary_comparison_basis_test.dart` — current session with `routineTemplateId: ''`, with an earlier same-modality free session and an earlier `routineTemplateId: ''` session, expecting the type comparison and `isRoutine == false`. Guard: that new test case.
2. [Minor] `lib/core/services/session_summary_service.dart:505-507` — the `sort` on `startedAtMs` is not stable in Dart, so two like sessions with equal `startedAtMs` have an unspecified winner (which one becomes `like.first`, i.e. the figure and the caption's date). Same behaviour as the base commit and the plan does not name a tiebreak, so no Blocker; but the Input-reality line "several sessions in one day are ordered by start time" is silent on equal starts. Fix: deterministic tiebreak (e.g. compare `id` descending after `startedAtMs`) or a one-line doc note; a test is only possible after the tiebreak exists.
3. [Minor] `docs/data_models.md:358` — the summary-models table (rows `GroupDelta`, `VolumeComparison`, `SessionGroupMetrics`, …) does not list the new `GroupComparison` and `ComparisonBasis`, and no `## Docs delta` row names this edit; `docs/state_management/services_and_utils.md:68` now says the service returns `GroupComparison`, so a maintainer following that name into the model reference finds no entry for it. Fix: two table rows next to `GroupDelta` (class, file `lib/core/models/session_summary.dart`, purpose, Active).
4. [Minor] `docs/state_management/services_and_utils.md:68` — the Purpose column still reads "…returns delta map keyed by `'strength'`, `'cardio'`, `'rounds'`, `'isometric'`" while the Returns column now says `GroupComparison`; the service returns a `GroupComparison` whose `deltas` map is so keyed, plus a `basis`. Fix: "returns `GroupComparison`: `deltas` keyed by … and a `basis` naming the like session".

## Questions (brief items 1–5)
1. Yes. `compareGroupsToPreviousSession` (service:460-541) filters finished, not-current, started-before, then routine-current → `_routineIdOf(s) == currentRoutine`; else `_routineIdOf(s) == null && s.modality == currentSession.modality` (null == null matches Free Training to Free Training); `_routineIdOf` maps `''`→null. `basis` label per D-24603 (trimmed title, `this routine` fallback, `ModalityDisplay.getName`, `lib/core/constants/modality_display.dart:15-19`: null→`Free Training`, `resistance_lifting`→`Resistance / Lifting`). Nothing unreachable; only the tie order is unspecified (finding 2). Empty-string rule untested (finding 1).
2. Yes. The caption is built only inside `_buildGroupCards` (screen:1179-1192), which returns `const []` when `_groupMetrics` is empty, so it never appears without a group card; while `_isLoading` both `_groupDeltas` and `_comparisonBasis` are still empty (set together in one `setState`, screen:214-215) so no caption and no figure; the `anyFigure` check (screen:1165) hides the line when every delta is null (S-24614 covers the like-session-without-effort case). Edit Session → `_refreshSummary` → `_loadAsyncData` (screen:265-271, 471-488) re-sets both fields together; there is no path that updates `_groupDeltas` without `_comparisonBasis` (only assignment site is screen:214-215).
3. Yes. `lib/`: only the screen (state field 96-97, call 181, chip builder 1286) and the model/service files; all read `comparison.deltas`. `test/`: `services_test.dart` (4 calls, all `.deltas`) and `summary_comparison_basis_test.dart` (9 tests, `.deltas`). No caller still reads the old `Map`; `test/data_tracking_fixes_test.dart` calls the untouched `compareToPreviousSession` (per lead facts, stays green).
4. No. The four `services_test.dart` hunks add `.deltas` only; every assertion is the old one unchanged (checked the whole first test body at test/services_test.dart:1760-1806 — fixture unchanged, only result accessors changed). The second test's delta 100 = 500−400 confirms the fixture's previous session is still the compared one under the new filter.
5. All six `## Docs delta` rows applied: data_models.md (chip row), services_and_utils.md (both rows), README.md, session_summary.md chip line and `## Comparison basis` section — verified in the diff. Every test name quoted in `## Comparison basis` exists verbatim in the two new test files (group `Summary comparison basis (plan 246)`, all S-246xx names checked against the test strings). Behaviour sentences checked against the code and true, including the Free-Training-matches-only-Free-Training rule and the `this routine` fallback. One doc edit the table does not name: finding 3 (missing GroupComparison/ComparisonBasis rows in data_models.md); the imprecision of finding 4 is inside an applied row.

## Assumption Log rulings
1. Base commit / branch / unrelated uncommitted files — ratify (`test/food_catalog_load_test.dart` and `macos/Flutter/GeneratedPluginRegistrant.swift` are the working-tree files outside the plan's predicted set; the latter not shown by `git-diff -- lib test docs`; neither touched by the plan).
2. S-246xx ids unique — ratify (grep of `test/` shows only the two new plan-246 files using them).
3. Method keeps the name `compareGroupsToPreviousSession` — ratify (all doc and test sites consistent).
4. No architect run, plan-lint clean — ratify (not re-run; outside reviewer scope).
5. Windows base failing set (~1075) as the comparison baseline — ratify (cannot verify without running the suite; brief forbids it).

## Scenario coverage
S-24601 → `test/summary_comparison_basis_test.dart` · `S-24601 routine current compares with the same routine, not a free session` ✓
S-24602 → same file · `S-24602 routine current with only a free session before it has no figure and no basis` ✓
S-24603 → same file · `S-24603 routine current with only a different routine before it has no figure and no basis` ✓
S-24604 → same file · `S-24604 free null-modality current compares with the last free null-modality session, not a routine session` ✓
S-24605 → same file · `S-24605 type match excludes other modalities and routine sessions` ✓
S-24606 → same file · `S-24606 a group the like session lacks gets no figure, a group it has gets the delta` ✓
S-24607 → same file · `S-24607 unfinished and started-after-current sessions are skipped` ✓
S-24608 → same file · blank-title and null-title cases (two tests) ✓
S-24611 → `test/summary_comparison_caption_screen_test.dart` · `S-24611 a routine summary says it compares with the last run of that routine` ✓
S-24612 → same file · `S-24612 no like session means no line` ✓ (passes both ways by design; kills mutants only together with S-24614)
S-24613 → same file · `S-24613 a free session says it compares with the last session of its type` ✓
S-24614 → same file · `S-24614 a like session with no group shows no line` ✓ (kills the caption-shown-ignoring-delta mutant)
Guard proofs: taken from the lead's observed mutation pass (10/10 killed); no prove-red verdict file in the brief — unproven in the formal sense, not counted as a finding.

STATUS: COMPLETE — blocker 0 / major 1 / minor 3
