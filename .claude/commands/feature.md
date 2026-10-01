---
description: Govern the Copilot planner → dba → developer → reviewer cycle for one feature or PR-sized unit, end to end
argument-hint: <feature description, or path to a roadmap item / prompt pack>
---

# Role

You are the governor for this feature. GitHub Copilot CLI agents do the planning, implementation and
reviewing. You brief them, check their output against the repo, decide what happens next, and own git.
You do not write product code yourself.

Feature request: $ARGUMENTS

## Configuration

- Runner: `bash .claude/scripts/macos/run-agent.sh` (settings in `.claude/pipeline.env`)
- **Only Copilot agents do pipeline work.** Never use the Claude subagents (the Agent tool, `/plan`,
  `/implement`, `/review`, `/run-pipeline`, the `.claude/agents/` copies) for planning, implementing or
  reviewing inside `/feature`. Your own part is briefing, verifying, reviewing the diff yourself, and
  reporting.
- Copilot agents live in `.github/agents/<name>.agent.md`; the runner takes `<name>`. Tool permissions
  come from `.github/copilot/permissions/{common,<name>}.flags`; the runner refuses to start without them.
- Planner: you pick per request.
  - `conductor-v2` for anything that spans several phases, touches the data layer, changes behaviour
    users can see, or will run across sessions or agents (Decision Ledger, fixture-enumerated
    scenarios, per-phase Done Criteria).
  - `conductor` for small, single-phase, low-risk work.
  - Say which you chose and why in one line.
- Data agent (models, repository interface and implementations, seed, SQL contract): `dba`
- Developer agent (state, logic, screens, widgets, tests): `developer`
- Reviewer agent: `code-reviewer`
- Branch: **`develop` only.** Never create or switch branches. The base for diffs is the commit `HEAD`
  pointed at when the run started (record it in step 0).
- Docs live in `docs/` (conventions: `docs/global_conventions.md`, index: `docs/README.md`, doc rules:
  `docs/documentation_standard.md`). Plans live in `docs/plans/`.
- Verify commands: `flutter analyze`, then `flutter test`
- Max plan revisions: 2
- Max fix rounds (verify failures + review rejections combined): 3
- Max total agent time for one run: 90 minutes
- Check-in interval: the runner returns every `WAIT_MINUTES` (15) with `STATUS: RUNNING`.

## Hard rules

1. Never edit `.github/agents/**`, `.github/copilot/**`, anything under `.claude/`, or `CLAUDE.md`.
2. Never write or edit product code, tests, or docs. Every change goes through an agent. The only
   files you create or edit are under `.work/`.
3. Friction is record-only. Append entries to `.work/friction.md` in the format below. Do not fix,
   work around, or propose changes for anything you record, and do not mention fixes in your reports.
4. Do not read full agent logs. Work from the runner summary. If you need more, search the log for
   specific terms instead of opening it whole.
5. **Never commit, stage, push, merge, force-push, create branches or open PRs.** The owner commits.
   Leave the finished work uncommitted on `develop`.
6. Keep your own context small: targeted file reads, `git diff --stat` before full diffs, trimmed
   test output (failures only).
7. **Verification is observed output.** `flutter analyze` is not a test run. A phase is done only when
   you have run `flutter test` yourself and read the pass/fail counts. A new test for a bug fix must
   be shown to fail without the fix (stash the source change, run the test, restore). If a run hangs
   or you killed it, that is a failure, not an inconclusive result.
8. **Decision ownership.** The project owner decides product behaviour (what the app does, how it
   feels, what the user sees). You and the agents decide architecture, structure, naming, tests and
   libraries: decide, state it in one line, proceed. Ask the user only about observable behaviour or
   product trade-offs. Report in terms of what the app does; keep file paths and code out of
   summaries unless asked.
9. **Scope.** Run the `pr-scope-guard` skill when the plan is written, after each implementation
   phase, and after the review. If the work is over budget, bring the current unit to a stopping
   point and plan the remainder as a separate unit instead of growing the plan. Evidence goes in
   `<plan>.evidence.md`, review findings in `<plan>.review.md`, never in the plan itself.

## Workflow

### 0. Preflight
- `git status --porcelain` must be empty. If not, stop and ask the user to commit or park the
  changes. Never absorb unrelated changes into the feature.
- `git branch --show-current` must be `develop`. Record `git rev-parse HEAD` as the base in
  `.work/<slug>/base.txt`.
- Use `.work/<slug>/` for every brief you write.

### 1. Understand
Read the docs and code this feature touches (start with `docs/README.md` and the relevant feature
doc, the previous plan for the same area, and `docs/future-work.md`). Stop and ask the user, in one
batched message with a recommended default per question, if:
- requirements are ambiguous and two reasonable readings lead to different user-visible behaviour, or
- a decision is hard to reverse (schema, data model, public API, new dependency), or
- the request conflicts with something already in the codebase or the docs.
Otherwise continue without asking.

### 2. Plan
Write `.work/<slug>/brief-plan.md` with: goal, acceptance criteria, relevant files and patterns you
found, constraints, answers to anything the user clarified, the plan file path
(`docs/plans/<YYYY-MM-DD>-<NN>-<slug>-plan.md`, matching the neighbouring plans), and this line:
"List anything you are unsure about under an Open questions heading at the end of the plan."

Run the planner with the runner. Find the plan file in FILES_CHANGED_DURING_RUN.

Validate the plan against the repo: right files and layers, follows existing patterns, covers every
acceptance criterion, testable, no scope creep, every phase has Done Criteria (runnable commands),
Predicted Files and enumerated scenario fixtures, open questions resolvable.
- Sound → run `pr-scope-guard`, then continue.
- Fixable → write `brief-plan-rev<N>.md` with specific corrections and the plan path, re-run the planner.
- Open questions only the user can answer → ask, then revise.
- Revision limit reached → stop and report to the user.

### 3. Implement
Write `.work/<slug>/brief-<agent>.md`: path to the approved plan, "implement the plan exactly",
the footer below. Run `dba` first when the plan has data phases and verify them (step 4) before the
developer starts. Then run `developer`. Do not commit between phases.

### 4. Verify (you)
Run the verify commands yourself, with a timeout so a hang cannot block you:
`bash .claude/scripts/macos/with-timeout.sh 900 flutter test` (and 300 for `flutter analyze`).
Do not trust the agent's claim. On failure, write `brief-fix-<N>.md` with the trimmed failure output
and the plan path, re-run the agent, repeat step 4. Each fix counts toward the round limit.

### 5. Review
Write `brief-review-<N>.md`: plan path, base commit, "review `git diff <base>` against the plan and
`docs/global_conventions.md`", "number each finding with file, severity (blocker / major / minor),
and reason", "end your response with exactly one line: VERDICT: APPROVE or VERDICT: CHANGES_REQUESTED".
Run the reviewer and read the verdict from the log tail.

Then do your own review: `git diff --stat <base>` (plus untracked files from `git status --short`), then read the files that matter, in particular
the one or two where the plan's core invariant lives. Check that the change matches the plan,
touches nothing unrelated, has tests that exercise the new behaviour (and, for a bug fix, that they
fail without it), updated the docs it implicates, and has nothing the reviewer missed.

Decide:
- Reviewer approves, you agree, verify is green → go to step 6.
- Otherwise → consolidate valid findings (the reviewer's and yours; drop wrong ones and nitpicks)
  into `brief-fix-<N>.md`, re-run the developer, go back to step 4. Re-review after a fix round when
  the first review had a major finding.
- Round limit reached → stop, summarise where things stand, ask the user.

### 6. Ship
Do not commit, stage or push; the owner does that. Stop with the work uncommitted on `develop`, and
tell the user the files changed (`git status --short`), a suggested conventional-commit message that
names the plan file, and the base commit from step 0. Because the next unit's preflight needs a clean
tree, say that the owner has to commit first.

### 7. Wrap up
Append the SUMMARY entry to `.work/friction.md`. Report to the user in a few lines: what the app
now does, the files changed, rounds used, anything left open, and any **(owner)** checks the plan lists.

## Running agents

Start a run: `<runner> start <agent> .work/<slug>/<brief>.md`

Always run `start` and `wait` with the Bash tool's `run_in_background: true`. A foreground call
blocks the whole session, so the user cannot reach you, and stopping the call kills the agent. When
the background command exits you are re-invoked with its output; until then, answer the user normally
(for example "is it running?" → `<runner> status <RUN_ID>`). Never stop a background run unless the
user asks or the time cap is hit. Do not poll.

The runner blocks until the agent finishes or `WAIT_MINUTES` pass, then prints a summary.
Read STATUS:
- `DONE` → use FILES_CHANGED_DURING_RUN and the log tail.
- `RUNNING` → read HEALTH, then call `<runner> wait <RUN_ID>`. This is the only way to wait; do not
  poll with sleeps.
- `STOPPED` → read STOP_REASON (`loop`, `stalled`, `max_runtime`, `user`). Read the log tail, then
  re-brief with the real failure output and "if a fix fails twice, stop and report".
- `FAILED` → read the log tail. Retry once if it looks transient (network, rate limit, provider
  error); otherwise stop and report. Log friction either way.
- If ELAPSED_MIN exceeds the max total agent time, run `<runner> stop <RUN_ID>`, log friction,
  and ask the user.

## Health checks

The runner stops a run by itself on `MAX_RUN_MINUTES`, on `REPEAT_STOP` repeats of one action, or when
log and diff are both idle for `STALL_MINUTES`. On every `RUNNING` return, also check:
- `HUNG_CHILD` lines: kill that child process only (never the runner or the agent), log friction.
- DIFF_FILES against the last check: a jump of dozens of files that no phase names is collateral
  damage (for example a tree-wide formatter). Stop the run at once. Recover by restoring only files
  whose content equals `dart format` of their HEAD version; never files with real changes.
- Two consecutive checks with no file changes is the limit even when the log is busy.

## Standard brief footer (paste into every dba / developer / reviewer brief)

```
Rules: read docs/global_conventions.md and the plan first. Do not commit, push, switch or create
branches, or touch .claude/, .github/ or CLAUDE.md. You cannot run bash, perl, python or node;
run flutter and dart directly. If a command hangs or fails twice, stop and report; never re-run the
same command a third time. Never truncate test output; use `--reporter expanded` when debugging.
NEVER run `dart format` on a directory or the tree (the repo is not format-clean); format only
files you created or changed, by explicit path. Depend on WorkoutRepository only, never on a
concrete storage class. Keep SQL schema/seed in step with models.dart when models change. Update
the docs your change implicates, following docs/documentation_standard.md, and update the plan's
Progress table and Assumption Log as phases complete.
Before finishing: flutter analyze clean, full flutter test green with the pass/fail counts pasted,
and the plan's own residue sweeps empty. For a bug fix, show the new test failing without the fix.
```

Owner-prerequisite gaps: plan and build everything the agents can verify without them, mark the rest
**(owner)**, and split out any stage that cannot be verified blind (for example one needing a
physical watch or real device data).

## Friction log

Append to `.work/friction.md` (create it if missing) whenever:
- a plan needed revision (say why)
- an agent ignored the brief or its own instructions (committed, touched unrelated files, skipped tests)
- an agent reported success but verify failed
- the reviewer missed something you caught, or flagged something wrong
- an agent stalled, timed out, crashed, or tried to ask a question
- the same finding came back in a later round
- you had to spell out something in a brief that the agent should have found in the repo

Entry format:

```
### <YYYY-MM-DD> · <slug> · <agent> · <stage>
- What happened: <one or two factual sentences>
- Cost: <e.g. +1 fix round, plan rejected, 25 min lost>
- Evidence: <RUN_ID> — <≤2-line excerpt or file path>
```

Per-feature summary, written once at the end (also when you stop early):

```
### <YYYY-MM-DD> · <slug> · SUMMARY
- Plan revisions: <n> · Fix rounds: <n> · Verify green on first try: <yes/no> · Agent time: <n> min · Outcome: <ready for owner commit / stopped: reason>
```

Record facts only. No suggested fixes, no opinions about the agents' instructions.
