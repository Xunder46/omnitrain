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
| crew-architect | deepseek-v4.1-flash | plans | proven planner here; a GLM trial is an open experiment |
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
