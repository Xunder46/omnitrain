# PR Scope Budget

A PR's plan must stay small enough to plan, build, review and land in one pass. A plan that
runs to thousands of lines is either several PRs in one file or a feedback loop. This file sets
the budget and says what to do when a PR outgrows it.

It binds every role: the planner (conductor / conductor-v2), the implementers (developer, dba,
in Claude Code or Copilot), the reviewer (code-reviewer), and the session orchestrating them.
In Claude Code, the `pr-scope-guard` skill runs this procedure.

---

## 1. Budget

### At handoff: the plan is written, no code yet

Split if **any** hard limit is hit:

- the plan is over **800 lines**;
- more than **5 implementation phases**;
- more than about **1,500 lines of predicted production code** (tests, fixtures and docs don't
  count).

Split if **two or more** soft signals are present:

- the plan is over 500 lines;
- more than 3 phases;
- more than one track: the phone app (`lib/`), a watch client (`watch/watchos/`, `lib/watch/`),
  or the sync contract (`watch/sync_protocol/`, `watch/contract/`). A contract change may ride
  with its first consumer;
- more than 20 ledger decisions, or more than 30 scenarios;
- planning found a missing prerequisite: something the feature assumes exists and doesn't.

### During implementation

Stop and split when:

- the plan has grown more than **150 lines** past its handoff size, which means evidence is
  leaking into it (see §2);
- a phase uncovers **substantial unplanned work**:
  - a missing prerequisite feature;
  - a defect that needs its own design;
  - a new model, message, screen or migration the plan doesn't have;
  - anything that would need a new phase;
- the actual production diff exceeds the plan's prediction by more than half.

### At review

Split when:

- there are more than **6 substantive findings** (nits don't count);
- a DESIGN finding spans layers or needs scenarios of its own;
- a **second review round** would be needed on the same PR.

---

## 2. What the plan holds

Every plan is a folder, `docs/plans/<plan-name>/`, named after the plan file without `.md`. It holds the plan, `<plan-name>.evidence.md` and `<plan-name>.review.md`. A series index is a single file beside the plan folders.

- **The plan:**
  - decisions, requirements, scenarios, and phases with Done Criteria;
  - Open Items;
  - a Progress checklist with **one line per item**, stating its result;
  - Assumption Log entries of at most 3 lines each.
- **`<plan-name>.evidence.md`**, in the plan's folder: baselines, suite outputs, red→green tables,
  footprints, the detail behind Assumption Log entries. Implementers write here, not into the
  plan.
- **`<plan-name>.review.md`**, in the plan's folder: the reviewer's findings. The plan's `## Feedback` holds only a
  pointer to it and the fix checklist.

---

## 3. When a trigger fires

Never grow the current plan to absorb new scope or another round of feedback. Instead:

1. **Reach a stopping point.** Finish or roll back the item in progress, so every item is either
   done or not started. Get both suites green: `flutter test`, plus `swift test` in `watch/watchos`
   if Swift changed. Commit or stage as the owner has asked.
2. **Record it in the current plan, in 10 lines or fewer:** what is done, what moved, and where it
   went.
3. **Plan the rest separately.** Hand conductor-v2:
   - the moved scope;
   - the decision IDs and findings it depends on;
   - this budget.

   The result is a new plan. If that plan would itself be over budget, the result is instead an
   index plan plus the first PR's full plan (see below).
4. **Order the PRs.**
   - If the current PR can't ship without the moved work, the new PR goes first and the current
     one pauses. Say so in its Progress section.
   - Otherwise the current PR lands trimmed and the new one follows.
5. **Tell the owner:** the signals measured, the split, and the new plan paths. Ask first only if
   the split removes something user-visible from the current PR.

### Over budget at planning time

Write a **PR series**:

- A short index plan of at most 100 lines. For each PR it gives the order, a one-line scope and
  its dependencies, plus the decisions the PRs share.
- A full plan for the **first PR only**.

Plan each later PR when its turn comes, against the code as it is by then.

### Over budget at review time

- In this PR, fix only the CRITICAL findings and the cheap MECHANICAL ones, in one round.
- Everything else becomes a follow-up PR plan.
- No review → fix → review loops.

---

## Calibration

- **Stats redesign PR 1 (effort rating):** planned at about 700 lines on one track, and landed in
  one review round.
- **PR 2 (watch capture):**
  - It was planned at about 1,150 lines, with 8 phases across three tracks, and planning found a
    missing prerequisite: watch sessions never reached the phone's history.
  - It grew to about 3,400 lines, of which about 2,000 were evidence and review text.
  - It should have been three PRs: the sync contract plus the phone import; the watch-side
    summaries; and the rating prompt plus the Summary integration.
