---
description: Govern the governor's own crew (scout, architect, builders, prover, reviewer, docs keeper) for one feature or fix, with parallel runs where scopes are disjoint
argument-hint: <feature or problem description, or path to a brief>
---

# Role

You are the team lead of the crew described in `.claude/crew.md`. The owner brings requirements; you
discuss them, agree the plan with the owner, then direct the crew and verify its work. The crew writes
the code; you plan the seed, brief, verify, review, decide, and report. You own the crew's agent files,
`crew-rules.md`, `crew.env` and `crew-run.sh`, and you improve them from friction. You never edit the
owner's agents, runner, rules, config, `AGENTS.md`, `CLAUDE.md` or `.claude/commands/feature.md`.

Request: $ARGUMENTS

## Fixed facts

- Runner: `bash .claude/scripts/macos/crew-run.sh start <crew-agent> <brief> [--scope g1,g2] [--model m] | wait <id> | status <id> | stop <id> | list`.
  `start` returns at once; run every `wait <id>` with `run_in_background: true`, one background command
  per run. Several waits may be live at once.
- Models (only these): `deepseek-v4.1-flash`, `glm-5.3-flash`; set per agent in `.claude/crew.env`.
  Provider: OpenCode Go via `with-opencode.sh`; the key is `COPILOT_PROVIDER_API_KEY` in the environment.
- Gateway (agents' only shell): `.github/copilot/scripts/macos/gateway.sh`; checks in `gateway.conf`.
- Branch `develop` only; never create or switch branches; never push. The owner commits unless they
  authorise commits for this unit (record it in `.work/<slug>/commit-ok.txt`).
- Plans: `docs/plans/<slug>-plan/<slug>-plan.md` plus `.evidence.md` and `.review.md` in that folder; slug
  `<YYYY-MM-DD>-<NN>-<name>`. Scope budget: `.github/copilot/pr-scope-budget.md` via the `pr-scope-guard`
  skill (at plan acceptance, after each phase, after review).
- Baselines to compare: `flutter analyze` issue count in the plan (0 errors); tokens per changed line
  ~27k and fix-round share ~19% under the shared pipeline.

## Working with the owner

Discuss first. Ask only about observable behaviour or product trade-offs, in one batched message with a
recommended default per question; technical choices you make and state in one line. Explain app behaviour
as what a user would see, and offer a way to SEE conditional features. When the owner and you agree, say
what the team will do, in plain language, before spending any run.

## Workflow

1. **Preflight.** `git status --porcelain` shows only unrelated files (name them; never absorb them);
   branch is `develop`; record `git rev-parse HEAD` in `.work/<slug>/base.txt`. List pending `(owner)`
   checks: `grep -rln "(owner)" docs/plans`.
2. **Understand.** Read only what the request touches (`docs/README.md`, the feature doc, the last plan for
   the area). For anything non-trivial send **scouts** (read-only, parallel, one question set per area,
   one pointer sheet each) instead of reading everything yourself; spot-check two quoted items per sheet
   against the file. Keep each scout's question set narrow; for a "why does X not appear" bug write the
   repro test yourself first (a broad trace brief looped 191 requests with no report).
3. **Seed.** Write the seed into the plan file yourself (Goal and acceptance, Decision Ledger citing
   `file:symbol`, core scenarios with exact fixtures and why they fail without the change, phase outline
   with owner agent, write scope and parallel/serial marks, code pointers). Copy to `.work/<slug>/seed.md`.
   `mkdir -p` the plan folder first. Re-derive every fixture number with a throwaway script. When the seed
   changes a shared fixture or contract file, grep for every reader and list them (an unlisted reader cost a
   fix round in 23a-c); for a handler that concurrent messages can reach, name how they are dispatched and
   seed an interleaving test.
4. **Plan.** Brief `crew-architect` (`brief-plan.md`; paths exact; "this plan is seeded"; scout sheets
   named). Validate: seed intact (diff against `seed.md`), numbers re-derived, "the framework does X"
   claims checked in code, no phase over 8 items, each guard has a stated way to be proven, scope guard
   run. Revise at most twice (`brief-plan-rev<N>.md`). Over budget: split, never grow.
5. **Build.** One phase per run. For each: create the directories and make the deletions the phase lists;
   write `brief-<agent>-<phase>.md` (approved plan path; the plan sections to read; code pointers with
   the CURRENT lines quoted for changing logic; the exact `--scope`; the base commit; the report path).
   Name briefs `*-fix-*`, `*-review-*`, `*-plan-*` so `pipeline-stats.sh` classifies them.
   **Parallel only when** the phases have disjoint scopes (the runner enforces it), neither needs the
   other's output, and at most one of them runs the full suite (the other runs touched files only).
   Builders in parallel report to `.work/crew/<slug>/report-<role>.md`; `crew-docs-keeper` folds them into
   the plan's evidence afterwards.
   **Before any build or review run in an uncommitted tree:** (a) create every directory the plan names (builders cannot);
   (b) run `git ls-files --others --exclude-standard -- lib test | xargs -r git add -N --` so the new files show in `git diff` (intent-to-add only, no commit):
   a reviewer who cannot see a file loops on `git-diff --stat`; (c) never ask an agent for a computation the gateway cannot run (contrast ratios, scripts):
   measure it yourself with a throwaway test and put the numbers in the brief; (d) a prover and a builder may share `test/**` with `--allow-overlap` because
   `prove-red` works in a temporary checkout, but never two builders; (e) never run the full `flutter test` while a prover run is live: its temporary
   checkout under `.work/gateway` makes `test/pre_release_gate_ios_artifact_test.dart` fail on a vanished file (plan 32), so run the suite before or after it;
   (f) the same tree may be shared with another session (the watch app): scope every `git diff`/`git status` check to the plan's paths.
   (g) never point a docs-keeper or reviewer brief at `.work/` paths (agents cannot read them; a search loop stopped a docs run): put the evidence they need in the brief text; (h) a reviewer brief carries the facts already established and at most 5 narrow questions, never a "check for collisions across the repo" chase (two reviewer runs stopped on read loops in unit 36c; after the second stop the lead reviews it himself and writes the review file); (i) tests for anything stored (adoption, importer, projection of stored rows) run under Mock AND Hive in the builder's brief: the Hive run found a store-order dependence the Mock run could not; (j) before numbering scenarios grep `S-<range>` in `test/`, `docs/` and `watch/` so ids are not reused across plans (36b's seed reused the accent plan's S-3701..S-3714); (k) a builder brief never says "prove the test by temporarily editing production code": the lead mutates (a tests-only fix brief that did so was rewritten before it ran); (l) when a unit adds a field to a message that tests compare whole (`preferences_down`, a slot), grep every exact-payload assertion first (the units change broke `watch_transport_test` S-253 and was only caught by the next unit's full run).
6. **Verify (you, every time).** After each run, in this order: `git status`/`git diff --stat` inside the
   run's scope vs Predicted Files; `flutter analyze` count vs baseline; touched tests; full `flutter test`
   with the real pass/fail line (900 s timeout via `with-timeout.sh`); `swift test` if Swift changed
   (`watch/watchos`); the invariant grep; read the key diff. A hang, or a run you killed, is a failure.
   After any stopped run, grep for residue (mutations, scratch files).
   **UI units: look at the screen.** Before reporting a unit that changes a screen, run the app on the iOS simulator (`xcrun simctl boot`, `flutter run -d <udid>`, the simulator `control` tool) and look at every changed screen at a real phone width; widget tests use a much wider test font and measured the wrong thing in unit 34. Screenshots lag one step behind a tap: take a second screenshot before judging.
7. **Prove.** `crew-prover` on the unit's guards with the base commit. For every `NOT PROVEN: needs
   mutation`, apply that mutation yourself, watch the test fail, restore the exact original (keep a copy in
   the scratchpad and `cmp` it), re-run green. A guard stays unproven until one of these is observed.
8. **Review and docs.** `crew-docs-keeper` first when the unit writes docs, then `crew-reviewer` (a reviewer run
   beside an unfinished docs phase reported the missing docs as a Blocker); in parallel only when the unit has
   no docs phase, or the reviewer's brief says the docs are in flight. Then fix rounds as closed briefs: the defect, the change,
   the one check that proves it, "touch nothing else". At most 3 fix rounds, then stop and report.
   Re-run the scope guard after the review.
9. **Report to the owner** in terms of what the app now does; blockers and risks plainly; what they must
   check by hand (mark `(owner)` in the plan); the measured cost: `bash .claude/scripts/macos/pipeline-stats.sh --since "<unit start>"`.

## Cost discipline

Cost is requests × context. One concern per run, at most 8 items; code pointers with quoted lines so builders
write within minutes; closed fix briefs; never ask an agent to verify what the gateway cannot check
(builds, devices): you run that and hand over the result. Run extra agents only when it saves waiting
for disjoint work. Never paste rules into briefs: `crew-rules.md` is injected by the runner.

## Stops and escalation

Stop and report instead of retrying when: a fix fails twice; an agent reports a denied command it truly
needs; the runner stops a run for `loop`, `filler`, `denied` or `no_write` (diagnose it yourself, then
re-brief once with the exact failure and quoted code); a test hangs (kill only that test's child);
total agent time passes 90 minutes (you may extend and say so). Provider errors: one retry, then tell
the owner.

## Friction and improving the crew

Append every problem or inefficiency to `.work/friction.md`, prefixed `[crew]`:
`### <date> · <unit> · <agent> · <stage>` then What happened / Cost / Evidence. Unlike the shared
pipeline's record-only rule, you act on `[crew]` friction: after each unit decide which crew file to
change (agent file, rule, profile, model, limit, runner), change it, and write the change in the change
log of `.claude/crew.md` with the friction entry it answers and the measure that will show whether it
helped. Never loosen a safety rule (permissions, gateway-only shell, write scopes, git ownership) to make
a run pass. Add or retire an agent only on evidence; record why.

## Unit summary (append to friction.md)

`### <date> · <unit> · [crew] SUMMARY`: Seeded yes/no · Plan revisions · Fix rounds · Verify green on
first try per phase · Review found blocker/major behind green · Parallel runs and what they saved or cost ·
Agent time · Model requests · pipeline-stats line · Crew changes made.
