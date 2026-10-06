# Code Review — Stats PR 5a (training-load definitions + Mix layer data), round 1

Reviewer: Code Reviewer agent (findings transcribed by the governor because the reviewer run had no create tool). Base `8be0918`. Verdict: **CHANGES_REQUESTED** (1 major, 3 minor, 2 nits; no blocker). Observed by the reviewer: `test/training_load_test.dart` + `test/mix_layer_service_test.dart` `+87: All tests passed!`; `test/docs_indexing_contract_test.dart` `+9`. Governor: analyzer `196 issues found.`, full suite `+3364 ~1` at the end of Phase 2.

## Findings
1. **major** — `test/mix_layer_service_test.dart` (S-1511 group, ~line 514): the register's S-1511 fixture B (a period-scoped window built through `StatsProgressService.resolveWindow(periods: [...])`, `isPeriodScoped: true`) has no test; only a hand-built `StatsWindow(isPeriodScoped: false)` is exercised, yet `docs/training_load.md` and `docs/state_management/services_and_utils.md` both cite S-1511 as verified. Fix: one test that builds the window through `resolveWindow` with a `TrainingPeriod` containing `now` and asserts the bar covers the period's sessions and the baseline ends at the local-midnight day of the window's own start.
2. **minor** — plan line ~191: S-1511's registered expected outcome ("Baseline load = 120 ... a `resistance` baseline segment at 100%") contradicts the same plan's Phase 2 step 2 and the code (the measure is time there, so `baselineSegments` is empty). The test notes the divergence but its comment points at the evidence file, which never mentions it (the note is in the plan's Assumption Log). Fix: correct the register entry; repoint the test comment.
3. **minor** — `docs/constants_reference.md` ("Training Load Constants" section): the four rows state rules but name no test. Fix: one `Verified by test/training_load_test.dart` line (the "the constants" group).
4. **minor** — `lib/core/models/training_load.dart` `sessionLoadMinutes`: a `sessionFeeling` outside 1-5 is unguarded. Unreachable through the UI today. Decision (governor): do NOT clamp (no invented behaviour); state in the doc comment that the caller guarantees a rating of 1 to 5 (the stored rating's range) and that out-of-range values are not clamped here.
5. **nit** — evidence S-1513 parity row records `unrated=5`; the parity window holds one of the fixture's five sessions, so the value is 1. Fix: correct the row.
6. **nit** — measured/dominant are computed for every completed session in history: no change requested (one pass over the cached snapshot, D-919).

## Carried (no action)
`baselineTotal > 0` is unobservable (harmless); Phase 2's M1 mutated `training_load.dart` rather than the service file the step named (justified, tests fail); the README row names no test (index rows do not); the value types have no `==`/`toString`.

Verified, no findings: pack fidelity recomputed by hand (60 min x 4 = 240; 20-min hold rated 3 = R 40 min/120, I 20 min/60; 900/3600 = 0.25 inclusive; baseline blocks and `ratedBaselineWeeks == 2`; strip totals); one effort->modality mapping home; pure-Dart model file; DST-safe calendar arithmetic; midnight and week-boundary attribution by start; unfinished sessions skipped; null on zero window time; percentages sum to 100 with the stated tie-breaks; single cached history read; scope clean.

VERDICT: CHANGES_REQUESTED

## Fix round 1

All six findings are closed; the checklist is ticked in the plan's Feedback section and the
per-finding lines plus the mutation proof for finding 1's test are in
`2026-10-02-05a-stats-pr5a-mix-data-plan.evidence.md` (§ Fix round 1).
`gateway.sh test test/mix_layer_service_test.dart` → `00:00 +40: All tests passed!`;
`gateway.sh test test/mix_layer_service_test.dart test/training_load_test.dart test/docs_indexing_contract_test.dart`
→ `00:01 +98: All tests passed!`; `gateway.sh lint` → `196 issues found. (ran in 3.2s)`.
