# The crew

An experiment started 2026-10-10: the governor (Claude) designs, runs and improves its own team of
Copilot CLI agents, alongside the shared pipeline (`/feature`, `.github/agents/{conductor*,dba,developer,code-reviewer}`),
which the owner keeps and which this team never edits. Everything of the crew's is a new file; deleting
the files listed below removes the experiment.

Question under test: can a leaner, more specialised team, with two model families and safe parallel
runs, build with fewer fix rounds and fewer tokens per changed line than the shared pipeline?

## What belongs to the crew

| Path | What |
|---|---|
| `.github/agents/crew-*.agent.md` | the eight agents |
| `.github/copilot/permissions/crew-*.flags` | each agent's write ceiling (paths), on top of the shared `common.flags` (read-only use) |
| `.github/copilot/crew-rules.md` | standing rules, injected by the runner by role |
| `.claude/crew.env` | models per agent, limits, parallelism cap |
| `.claude/scripts/macos/crew-run.sh` | the crew's runner (copy-and-change of `run-agent.sh`) |
| `.claude/commands/crew.md` | the governor's playbook (`/crew <request>`) |
| `.claude/crew.md` | this charter and the change log |

Shared and read-only for the crew: `common.flags`, `gateway.sh` and `gateway.conf`, `with-opencode.sh`,
`with-timeout.sh`, `pipeline-stats.sh`, `pr-scope-budget.md`, `AGENTS.md`'s hang notes.

## Roster

| Agent | Model | Writes | Why this model |
|---|---|---|---|
| crew-scout | glm-5.3-flash | `.work/crew/**` | read-heavy, 1M context, cheap input; output is verified by quotation |
| crew-architect | glm-5.3-flash | plans | since 2026-10-13: deepseek died twice on a provider error (19f; 4 good runs otherwise); glm planned 19f and 23e1 cleanly |
| crew-builder-data | deepseek-v4.1-flash | data layer, tests, docs | proven builder here |
| crew-builder-app | deepseek-v4.1-flash | state, features, widgets, core, tests, docs | proven builder here |
| crew-builder-watch | deepseek-v4.1-flash | watch package, contract, `lib/watch`, tests, docs | proven builder here |
| crew-prover | glm-5.3-flash | tests only | a second model family checks the builders' tests |
| crew-reviewer | glm-5.3-flash | review files | a second model family reviews |
| crew-docs-keeper | glm-5.3-flash | docs, plan evidence | cross-checks claims against code; second family |

Model facts used for the split (aggregators, not vendor figures, June–Oct 2026): DeepSeek V4.1 Flash is
strong on agentic terminal work (Terminal-Bench 2.1 90.6%, DeepSWE 74.2%) but has a 96.5% hallucination
rate on Omniscience, matching this repo's history of invented names and false "done" claims. GLM 5.3 Flash
(Coding Index 71.5, Agentic Index 50.9) has no history here. The split is a hypothesis; `friction.md` and
`pipeline-stats.sh` decide.

## Principles

1. The write scope is the safety mechanism for parallel work: a run's write permission is a list of
   paths, the runner refuses overlapping scopes and caps live writers (`MAX_PARALLEL_WRITERS`).
2. Small fixed prefix: every request re-sends the agent file plus rules. Agent files stay lean; project
   knowledge is pulled from `docs/` by pointer, not pasted.
3. A different model checks the work than wrote it (build deepseek, prove/review/docs glm).
4. Nobody grades their own tests: the prover decides whether a guard guards.
5. The governor verifies every claim itself (analyze count, full suite, diff vs predicted files,
   mutations re-applied by hand). Agents' "done" is a claim.
6. Parallelism buys time, not tokens; more agents means more fixed prefixes. Spawn extra agents only for
   disjoint work that would otherwise wait.
7. Unchanged from the shared pipeline: gateway-only shell, no allow-all, no git by agents, `develop` only,
   the owner commits unless they say otherwise, the owner decides product behaviour.

## Change log

- 2026-10-10: created. Eight agents, runner, rules, command. Smoke tests (recorded in `.work/friction.md`):
  both models reach OpenCode Go; two scouts ran in parallel; write scope enforced by permissions; overlap
  and writer-cap refusals fire. No product work run yet.
- 2026-10-10: runner fixes found by the smoke tests: scope globs were shell-expanded; `check` dry-run command
  added; git warning for not-yet-existing scope directories silenced.
- 2026-10-10 (unit 19d, the first real unit): agent descriptions quoted and `check`/`start` validate the frontmatter (6 of 8 files could not load); a narrowed `--scope` keeps `.work/crew/**`; `crew-builder-watch` may write `ios/OmniTrain Watch App/**`. Result of the unit and the measured numbers: `.work/friction.md` "[crew] SUMMARY (first crew unit)". Open follow-ups: the prover must show the arithmetic behind a predicted failing value; split `docs/state_management/watch_surface.md` (52,408 bytes) before the next watch unit.
- 2026-10-10 (unit 19e): `crew-rules.md`: the gateway is spelled relative only, one retry if denied (the prover called it by an absolute path and could run no check). Practice added: builders that share one Swift package run serially, only trees that cannot break each other's compile run in parallel; a prover shows the arithmetic behind a predicted failing value, the governor applies every mutation; a review round is followed by a closed fix brief per finding, never an open invitation. Measured: `.work/friction.md` "[crew] SUMMARY (second crew unit)".
- 2026-10-10 (unit 19f): no change to agents, runner or rules (the 19e fixes held). Practice added: a model failure twice with the same provider error means change the model for that run (architect on glm-5.3-flash) and give the baselines in the brief, never a third identical retry; a source-guard family is proven by mutating each guarded line (including the second call site and the "moved to another function" forms); the governor reads every fix a builder makes for a race or a lock, because the fix itself shipped a double resume. Measured: `.work/friction.md` "[crew] SUMMARY (third crew unit)". Candidate for the next unit: default the architect to glm-5.3-flash.
- 2026-10-11 (units 23a, 23b, 23c; owner QA fixes): no change to agents, runner or rules. Practice added (from `.work/friction.md` "[crew] SUMMARY (units 4-6)"): a seed that changes a rule names every reader of the shared fixtures it touches; proof mutations are the governor's, never a builder brief; a scout gets one question and returns a test, not a pointer sheet; use run ids (not globs) in Monitor waits.
- 2026-10-11 (unit 23e1, batched exercise list: contract + wrist store): no change to agents, runner or rules. Practice added (from `.work/friction.md` "[crew] SUMMARY (exercise batches)"): the seed of a handler that frames can reach concurrently names how frames are dispatched and carries a SuspendingStore interleaving test; a builder is never briefed to mutate production code from a tests-only scope (second time this was nearly repeated: put it in the governor checklist before writing any fix brief).
- 2026-10-11 (unit 23e2, the phone sends batches): no change to agents, runner or rules. Practice added: run the reviewer after the docs keeper when docs are part of the unit (a parallel reviewer reported the not-yet-written docs as a Blocker). Measured: `.work/friction.md` "[crew] SUMMARY (the phone sends batches)".
- 2026-10-13 (units 25-30, UI standards refresh): `crew-rules.md` gained a "UI standards" section (builders use the shared pieces, fix what they touch, never add an allowlist entry or raise a ratchet; the reviewer treats both as Blockers). `commands/crew.md` gained a pre-run checklist (mkdir for builders, `git add -N` so reviewers see new files, no computations asked of agents, prover may overlap a builder's `test/**`). Friction answered: a reviewer stopped after 43 denied `python3` calls (brief asked for contrast ratios) and another looped on an empty `git-diff --stat` (untracked files); measure: reviewer runs that end STOPPED should be 0 in the next unit. Prover found it can carry an untracked production file into the base checkout so screen tests go red for the right reason; keep. Measured: `.work/friction.md` "[crew] SUMMARY (UI standards)".
- 2026-10-13 (retro over all 363 runs, owner approved): runner gained earlier, role-aware stops: `DENIED_STOP=12` for every agent; for checkers (scout, architect, reviewer) `CHECKER_REPEAT_STOP=25` repeats of one non-edit command and, for scout and reviewer, `CHECKER_READ_STOP=25` reads of one file. Replayed on every past run: catches all four known loops (43 denied, 40 and 50 identical git-diffs, 73 reads) with no false stop on a healthy crew run; builders keep `REPEAT_STOP=40` (they re-run one test 15-23 times legitimately). Architect default moved to glm-5.3-flash. Practices that lived only in this log moved into the playbook and rules: readers of shared fixtures in the seed, docs keeper before reviewer, narrow scouts and a governor repro test for "X does not appear" bugs, scouts answer from code (not plan boxes) and name the guarding test, the prover shows its arithmetic, "fix what you touch" capped at 10 changed lines per deviation in briefed files. Friction log entries 2026-10-01..09 moved to `.work/friction-archive-2026-10-01-to-09.md`. Measure: no crew run burns more than ~25 repeats before stopping; reviewer runs ending STOPPED stay at 0.

- 2026-10-14 (unit 32, Training Mix card + Session Summary clarity): no change to agents, runner or rules. Playbook pre-run checklist gained (e) never run the full suite while a prover run is live (its temporary checkout broke `pre_release_gate_ios_artifact_test`), and (f) scope every diff/status check to the plan's paths when another session shares the tree. Answers `.work/friction.md` "[crew] governor · verify" (2026-10-14); measure: no full-suite run overlaps a prover run in the next unit. Measured: `.work/friction.md` "[crew] SUMMARY" 2026-10-14.

- 2026-10-14 (unit 33, muscle hierarchy PR 1): no change to agents, runner or rules. Practice added (from `.work/friction.md` "[crew] SUMMARY" 2026-10-14): scouts get at most 4 questions and no "quote everything in range" asks across 5+ files (two broad scouts looped and were stopped); when a seed changes a type shared across `lib/data` and `lib/core`, add the new member beside the old one in phase A and delete the old one in a later phase (no compile-broken window); a prover brief for tests that use new APIs asks for mutations only (prove-red is a compile error there) and the lead runs them with a script (`mutate.py` pattern: apply by line, run the guard, restore, `cmp`); architects can draft per-chunk data (tagging) with `--scope .work/crew/<unit>/** --allow-overlap`. Measure: scouts stopped for `loop` should be 0 in the next unit.

- 2026-10-14 (unit 34, muscle editor PR 2): no change to agents, runner or rules. Practice added (from `.work/friction.md` "[crew] SUMMARY" unit 34): a brief for a NEW widget names the exact Flutter widget per state and gives one file plus its test per run (a 7-item brief with design latitude and four design-doc reads ended STOPPED/no_write after 15 min and 55k reasoning tokens); the lead checks every architect impact row that cites framework behaviour (PopScope does not intercept a direct `Navigator.pop()`); when a prover list contains a mutation that does not compile the lead writes a compiling variant; mutate by line number with a substring check and restore with `cmp` (the `mutate2.py` pattern). Measure: builder runs ending STOPPED/no_write should be 0 in the next unit.

- 2026-10-14 (unit 35, muscle hierarchy PR 3): no change to agents, runner or rules. Playbook (`commands/crew.md`) verify step gained "UI units: look at the screen" on the simulator (answers `.work/friction.md` 2026-10-14 "test measured the wrong thing", unit 34). Practice added: for a seed that touches a shared type across `lib/data`, `lib/core` and `lib/state`, order the phases so each compiles (additive first, removal last), and remove a legacy API only after every caller and test has moved (unit 35 did this in three runs with no red window); a prover list is applied by script, one mutation per line with the quoted current text checked first (26 mutations ~15 min, all restored by `cmp`). Measure: builder runs ending STOPPED/no_write stayed at 0 in this unit (all 11 builder runs finished).

- 2026-10-15 (plan 36: routine start sync, units 36a/36b/36c, owner QA fixes): no change to agents, runner or models. `crew-rules.md`: reviewers read files in ranges of at least 100 lines, at most twice, and write the verdict after one pass; docs keepers never search `.work/`. Playbook pre-run checklist gained (g) no `.work/` paths in docs/reviewer briefs, (h) reviewer briefs carry facts plus at most 5 narrow questions, (i) stored-data tests run under Mock and Hive, (j) grep scenario id ranges before numbering, (k) no production-code mutation in a builder brief, (l) grep exact-payload assertions before adding a field to a compared message. Answers `.work/friction.md` entries of 2026-10-15 (36b docs keeper loop; 36c reviewer loops x2). Measure: runs stopped for `loop` should be 0 in the next unit (this unit: 3 of 29). Cost: 29 runs, 209 agent-minutes, 28.0k input tokens per changed line (3400 lines, 3 commits; the shared pipeline's 27k).
