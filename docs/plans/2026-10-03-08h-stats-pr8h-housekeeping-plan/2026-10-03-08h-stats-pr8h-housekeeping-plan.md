# Feature: Stats PR 8h — housekeeping (copy constants and plan-file bookkeeping)

> **Status:** READY (planner) — not started. Independent of 8a and 8b; it may be merged before, between
> or after them.
> **Next handoff:** @developer (Phase 1, the only phase)
> **Source of scope:** the Stats PR 8 series seam (`docs/plans/2026-10-03-08-stats-pr8-index.md`) and the
> drift the 8a/8b research turned up.
> **Binding conventions:** `docs/global_conventions.md`. Budget: `.github/agents/pr_scope_budget.md`.
> **Evidence:** `2026-10-03-08h-stats-pr8h-housekeeping-plan.evidence.md` (this folder). Review findings:
> `.review.md`. Neither is written into this file.

## Scope check

| Measure | This plan | Soft | Hard |
|---|---|---|---|
| Plan lines | 250 (measured) | 500 | 800 |
| Phases | 1 | >3 | >5 |
| Tracks | 1 (`lib/`, `test/`, `docs/plans/`) | >1 | — |
| Ledger decisions | 5 (D-1601…D-1605) | >20 | — |
| Scenarios | 3 (S-2301…S-2303) | >30 | — |
| Predicted production lines | ~8 | — | ~1,500 |

**Verdict:** zero soft signals, zero hard. This is a housekeeping PR: two copy strings stop hardcoding a
number that a constant already owns, and four plan files that describe finished work stop saying they have
not started. (The brief expected roughly 120 lines; the extra length is the executor block, which every
plan carries because an executor sees only its own plan file plus `docs/global_conventions.md`.)

## What this PR does

Two shipped cards state a window length as a literal (`3 weeks`, `4 weeks`) while the constant that owns
that window sits next to them. If either window changes, the card would lie. This PR derives both, keeping
the rendered text byte-identical, and adds the guard that keeps it that way. It also brings three plan
files' status lines and open-question answers up to date with what has actually shipped.

## Out of scope

- Any behaviour change, any new signal, any priority change. The rendered strings must not change by one
  byte.
- `lib/core/models/fuel_vs_load.dart` and `lib/core/models/protein_consistency.dart` — 8a and 8b write
  theirs derived from the start, and their own guards cover them.
- Anything in `docs/` outside `docs/plans/`. In particular this PR adds no doc and removes none, so the
  64 KiB ceiling is not in play (H-3 records the measurements only).

## Findings from research

- **F-1/F-2 — two copy builders hardcode a window a constant owns.** `lib/core/models/interference.dart`
  writes `'… over the last 3 weeks.'` (~line 376) while `kInterferenceSportsLoadWindowDays = 21` (line 40)
  owns that window; `lib/core/models/modality_mix_shift.dart` writes `'… over the last 4 weeks, …'`
  (~line 143) while `kModalityMixShiftPeriodDays = 28` (line 12) owns it. Same defect class, two files.
- **F-3 — five suites pin the rendered text**, so a derivation that is off by one week or adds a space
  fails loudly (`test/interference_test.dart`, `test/interference_signal_screen_test.dart`,
  `test/modality_mix_shift_test.dart`, `test/modality_mix_shift_signal_screen_test.dart`,
  `test/signals_layer_screen_test.dart`). `test/progression_rate_test.dart` and
  `test/progression_samples_service_test.dart` also assert `4 weeks`, for the Progression Rate window — a
  different constant, which is why D-1603 scopes the guards per file.
- **F-4 — four plan files describe finished work as unstarted.** The 7 index says
  `Status: READY (planner) — neither half started.`; 7a and 7b say `Status: READY (planner) — not
  started.`; 6b says `Status: READY (planner) — not started; blocked on 6a`. PR 7a shipped as `b3b91fa`,
  PR 7b as `2b6e8e5`, and 6b's block is long past.

## Resolved Decisions (Ledger)

**D-1601 — Derive the sports-load window.** In `crossModalityInterferenceCopy` the literal `3 weeks` is
replaced by an interpolation of `kInterferenceSportsLoadWindowDays ~/ 7`. The rendered observation is
byte-identical to today's.

**D-1602 — Derive the Mix period.** In `modalityMixShiftCopy` the literal `4 weeks` is replaced by an
interpolation of `kModalityMixShiftPeriodDays ~/ 7`. The rendered observation is byte-identical to
today's.

**D-1603 — Guards are per file, and prove derivation rather than spelling.** One new test per file scans
that file's **stripped** source (comments removed, in the `_strippedSource` style of
`test/interference_test.dart`) for the literal it must no longer contain, and asserts the built copy still
contains the rendered words. A repository-wide scan is wrong: two other suites legitimately assert
`4 weeks` for the Progression Rate window.

**D-1604 — Plan-file bookkeeping is status and answers only.** The three plan files named in F-4 get their
status line updated, and the open questions the owner answered on 2026-10-03 are marked answered. No plan's
Ledger, scenarios, phases or Progress is rewritten, and no new plan content is invented.

**D-1605 — No doc work for the size ceiling.** This PR touches no `docs/` file outside `docs/plans/`, so
the 64 KiB ceiling and `test/docs_indexing_contract_test.dart` are unaffected; the measured sizes are
recorded in the evidence file as a baseline for 8a and 8b.

## Scenarios

### S-2301: the interference card's window is derived
- **Fixture:** an `Interference` result with `hasSportsLoadRise == true`, a non-zero
  `sportsLoadRisePercent`, `lo == hi` and a populated `k`/`n`.
- **Trigger:** `crossModalityInterferenceCopy(result)`; then a scan of `lib/core/models/interference.dart`'s
  stripped source.
- **Flow:** D-1601, D-1603.
- **Expected outcome:** the observation still ends `'Sports load is up 30% over the last 3 weeks.'` — the
  same string as before the change — the stripped source contains no `3 weeks` literal, and the file still
  contains `kInterferenceSportsLoadWindowDays ~/ 7`.
- **Edge case of:** none.

### S-2302: the Mix card's period is derived
- **Fixture:** a `ModalityMixShift` with a reported section, a non-zero `recentPercent`, a
  `baselinePercent`, and both the `grownSection == null` and `grownSection != null` cases.
- **Trigger:** `modalityMixShiftCopy(shift)` for both; then a scan of
  `lib/core/models/modality_mix_shift.dart`'s stripped source.
- **Flow:** D-1602, D-1603.
- **Expected outcome:** both observations still read `… over the last 4 weeks, down from its usual N%.` and
  the grown clause is unchanged; the stripped source contains no `4 weeks` literal; the file still contains
  `kModalityMixShiftPeriodDays ~/ 7`.
- **Edge case of:** none.

### S-2303: the plan files report what shipped
- **Fixture:** the four plan files named in F-4, read before editing.
- **Trigger:** read each one's status line and open-questions table after the edit.
- **Flow:** D-1604.
- **Expected outcome:** the 7 index reads DONE with both halves named; 7a reads DONE with `b3b91fa`; 7b
  reads DONE with `2b6e8e5`; 6b no longer claims it is blocked on 6a; and the owner's 2026-10-03 answers
  are recorded, changing no other row: 7a's O-1 and O-2 read `Answered 2026-10-03: owner kept the shipped
  wording`; 7b's O-1 and O-5 read `Answered 2026-10-03: owner confirmed the default`; 6b's Progression
  Rate suggestion-wording row reads `Answered 2026-10-03: owner kept the shipped wording` (or, if that row
  does not exist, the Assumption Log says so and only the status line changed); 7b's D-1321 gets no new row
  and this plan's Assumption Log carries the one line confirming it. Every other line of those files is
  unchanged.
- **Edge case of:** none.

## Iteration 1

### Executor block

- **Branch:** work on `develop`. Never create a branch, never commit, never stage, never push — the owner
  commits.
- **Shell:** every command goes through the gateway, spelled in full:
  `.github/copilot/scripts/macos/gateway.sh <list|lint|test [paths]|format <file paths>|pub-get|git-status|git-diff|git-log|git-show>`.
  The bare form is denied. No `git`, `grep`, `sed`, `awk` or `wc` in a shell. A denied command is never
  retried. A gateway `test` over 3 minutes is a hang: stop and report it.
- **Red first:** the two guards are written before the derivation and must be observed failing.
- **Mutations:** one at a time, observed, restored, re-run green; never end a step with one applied.
- **Evidence:** to
  `docs/plans/2026-10-03-08h-stats-pr8h-housekeeping-plan/2026-10-03-08h-stats-pr8h-housekeeping-plan.evidence.md`.
  Never into this plan.
- **Ambiguity:** never stop; pick the Ledger-consistent option, log it in the Assumption Log, continue.
- **Baseline (measured on `develop` at `2b6e8e5`):** `flutter analyze` → `196 issues found.` with 0 errors;
  `flutter test` → `+3635 ~1: All tests passed!`. If 8a or 8b merged first, re-measure at the start of the
  run, compare against that instead, and say so in the evidence file.

### Phase 1: derive the two windows, guard them, and update the four plan files (@developer)

1. [x] Read `lib/core/models/interference.dart` around line 376, `lib/core/models/modality_mix_shift.dart`
   around line 143, and `test/interference_test.dart`'s `_strippedSource` helper.
2. [x] Write the two guards first, in the suites that already own those files' copy tests
   (`test/interference_test.dart`, `test/modality_mix_shift_test.dart`): S-2301's and S-2302's stripped-source
   scans, each asserting its file contains no `3 weeks` / `4 weeks` literal and does contain `~/ 7` on the
   owning constant. Run them and record the failure.
3. [x] Make the two derivations (D-1601, D-1602): one interpolation each, nothing else in either builder.
4. [x] Re-run step 2's suites to green, then
   `flutter test test/interference_test.dart test/modality_mix_shift_test.dart test/interference_signal_screen_test.dart test/modality_mix_shift_signal_screen_test.dart test/progression_rate_test.dart test/progression_samples_service_test.dart test/signals_layer_screen_test.dart`.
   Every `3 weeks` / `4 weeks` assertion must pass **unmodified** — a failure means the derivation is not
   byte-identical, a defect in step 3, not a test to update.
5. [x] Mutations, one at a time, each restored: **(a)** put the `3 weeks` literal back in
   `lib/core/models/interference.dart` — S-2301's scan must fail; **(b)** change
   `kInterferenceSportsLoadWindowDays ~/ 7` to `~/ 14` — `test/interference_test.dart`'s existing
   `over the last 3 weeks.` assertion must fail; **(c)** put the `4 weeks` literal back in
   `lib/core/models/modality_mix_shift.dart` — S-2302's scan must fail. Record all three red→green pairs.
6. [x] Update the four plan files (D-1604), reading each before editing and changing only status lines and
   open-question statuses: `docs/plans/2026-10-03-07-stats-pr7-index.md` (status → DONE, both halves named
   with `b3b91fa` and `2b6e8e5`); the 7a and 7b plans (status → DONE); and the 6b plan (status → DONE, its
   suggestion-wording open question marked answered by the owner on 2026-10-03).
7. [x] Mark the owner's 2026-10-03 answers (all "keep as shipped"), changing no other row:
   - 7a's Open questions **O-1** (modality nouns and suggestion wording) and **O-2** (statement vs option
     tone) → **Answered 2026-10-03: owner kept the shipped wording**.
   - 7b's Open questions **O-1** (a sports session's load is its Sports component) and **O-5** (a
     follow-up shared by two hard sessions counts once) → **Answered 2026-10-03: owner confirmed the
     default**.
   - 6b's Open questions table: the row about the Progression Rate suggestion wording ("The current
     approach is working.") → **Answered 2026-10-03: owner kept the shipped wording**; if no such row
     exists, record that in the Assumption Log and edit only the status line.
   - 7b's third default (D-1321, exact-duration windows) has no open-question row: do not add one; append
     one line to this plan's Assumption Log stating the owner confirmed D-1321 on 2026-10-03.
   Do not answer a question the owner never answered.
8. [x] Record every `docs/` file's byte count and its share of the 64 KiB ceiling in the evidence file
   (D-1605). No doc is edited.

**Done Criteria** (run until green):
`flutter analyze` (expect `196 issues found.`, 0 errors — or the re-measured baseline if 8a/8b merged
first, stated in the evidence file);
`flutter test test/interference_test.dart test/modality_mix_shift_test.dart test/interference_signal_screen_test.dart test/modality_mix_shift_signal_screen_test.dart test/docs_indexing_contract_test.dart`;
full `flutter test` with its summary line.

**Predicted Files:** `lib/core/models/interference.dart`, `lib/core/models/modality_mix_shift.dart`
(EDIT — one interpolation each); `test/interference_test.dart`, `test/modality_mix_shift_test.dart`
(EDIT — one guard each); `docs/plans/2026-10-03-07-stats-pr7-index.md`,
`docs/plans/2026-10-03-07a-stats-pr7a-mix-shift-plan/2026-10-03-07a-stats-pr7a-mix-shift-plan.md`,
`docs/plans/2026-10-03-07b-stats-pr7b-interference-plan/2026-10-03-07b-stats-pr7b-interference-plan.md`,
`docs/plans/2026-10-03-06b-stats-pr6b-progression-rate-plan/2026-10-03-06b-stats-pr6b-progression-rate-plan.md`
(EDIT — status lines and open-question answers only).

**Phase 1 verification notes (Conductor, date):** _(added at verification)_

## Governor actions

- @developer owns the only phase. No `lib/features/` file is touched.
- If step 4 shows a changed `3 weeks` / `4 weeks` assertion, stop: D-1601 and D-1602 are byte-preserving.
- If step 6 needs a plan's Ledger, scenarios or Progress rewritten, stop: D-1604 is status and answers
  only, and the rest is a different PR.
- The owner commits. No agent commits, branches or pushes.

## Files Affected (whole feature)

| File | Change |
|---|---|
| `lib/core/models/interference.dart` | EDIT — the sports-load window is derived |
| `lib/core/models/modality_mix_shift.dart` | EDIT — the Mix period is derived |
| `test/interference_test.dart`, `test/modality_mix_shift_test.dart` | EDIT — one derivation guard each |
| the 7 index, 7a, 7b and 6b plan files under `docs/plans/` | EDIT — status lines and answers only |

Nothing in `lib/features/`, `lib/data/`, `scripts/`, `watch/` or `docs/` outside `docs/plans/`. No file
8a or 8b creates is touched.

## Notes

- **Dependency graph:** none. This plan is independent of 8a and 8b in both directions; no ordering
  requirement, either way.
- **Predicted intermediate state:** after step 3 the app is behaviourally identical and only the source
  shape changed; after step 6 the four plan files describe reality.
- **Legacy handling:** none. No field, schema or stored value changes.
- **Why the guards matter:** F-1 and F-2 are one defect class — a rendered window length that a constant
  owns but the string ignores. The guards make a third instance impossible to reintroduce in either file.

## Open questions

| # | Item | Owner | Status |
|---|---|---|---|
| O-1 | D-1603's guards scan one file each rather than the repository, because the Progression Rate window legitimately renders `4 weeks` | Owner | Defaulted — **owner to confirm**; a repo-wide guard would have to whitelist those two suites |
| O-2 | D-1604's bookkeeping marks only the questions the brief records as answered; unanswered rows are left untouched | Owner | Defaulted — **owner to confirm** |
| O-3 | 6b's status becomes DONE rather than "superseded" | Owner | Defaulted — **owner to confirm**; its shipped signal is live |

## Progress

| Item | Status | Evidence |
|---|---|---|
| Plan lines re-measured | done | 251 lines (read back from this file after Phase 1) |
| Phase 1 | Complete | guards red→green in `test/interference_test.dart` + `test/modality_mix_shift_test.dart`; 7 neighbouring suites `+146: All tests passed!`; three mutation pairs red→green in the evidence file; four plan files updated; analyze + full-suite summary in the evidence file |

## Assumption Log

_Executors append here: decision made, options considered, choice and why. The Conductor marks each
RATIFIED (promoted to a D-x) or REVERT (remediation)._

- **A-1 (Phase 1, step 7) —** 7b's D-1321 (exact-duration windows) has no open-question row, and D-1604 forbids adding one, so the owner's 2026-10-03 confirmation of D-1321 is recorded here instead: the owner confirmed D-1321 as shipped.
- **A-2 (Phase 1, step 7) —** 6b closes with "Open Items", not an "Open questions" table, and no row in it mentions the Progression Rate suggestion wording ("The current approach is working."). Per step 7's fallback, only 6b's status line changed; this note records why no row was marked.
- **A-3 (Phase 1, step 8) —** the gateway exposes no byte-count command (`list` prints the check menu only), so the doc sizes were measured with a temporary probe test (`test/_doc_size_probe_test.dart`, `dart:io` `lengthSync` over `docs/**/*.md`) run once through `gateway.sh test` and deleted immediately after; the measured numbers are in the evidence file.

## Feedback

[empty — the Conductor folds non-empty entries into a new Iteration block and clears this one]
