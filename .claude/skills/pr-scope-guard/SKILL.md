---
name: pr-scope-guard
description: Check an OmniTrain PR against the scope budget in `.github/agents/pr_scope_budget.md`, and split oversized work instead of growing the plan. Use at every PR checkpoint: when a plan is written or handed off, after each implementation phase, and after a code review. Also use whenever a plan passes about 500 lines, a phase uncovers substantial unplanned work, or a review returns more than a handful of findings. When over budget, it gets the current PR to a stopping point and kicks off conductor-v2 to plan the remainder as separate PRs.
---

# PR scope guard

The budget, the rules on what belongs in a plan, and the split procedure are in
`.github/agents/pr_scope_budget.md`. Read it first; this skill is how to apply it from
Claude Code.

## 1. Measure (read-only and cheap)

- **The plan:**
  - line count, from `wc -l <plan>`;
  - phases, from `grep -c '^### Phase' <plan>`;
  - ledger decisions and distinct scenario ids;
  - which tracks it touches: the phone `lib/`, the watch `watch/watchos/` or `lib/watch/`, and
    the contract `watch/sync_protocol/` or `watch/contract/`.
- **Growth since handoff:** compare the plan's line count at the commit that handed it off with
  its line count now.
- **The diff:** production code (`lib/`, `watch/watchos/Sources/`) against tests, fixtures and
  docs, using `git diff --shortstat <base> -- <paths>`. Compare it with the plan's Predicted
  Files.
- **The review:** findings by severity, and by kind (MECHANICAL, DESIGN or DECISION).

## 2. Decide

- **Within budget:** say so in one line and continue.
- **Over budget, or unsure:** split. Small PRs are cheap; an oversized one is not.

## 3. Split (budget file §3)

1. **Stopping point.**
   - Every item is either done or not started. Roll back half-done work, and check that the
     rollback doesn't break anything that `swift test` on macOS can't see, such as `#if os(watchOS)`
     views.
   - Both suites are green.
   - The work is committed or staged as the owner has asked. Never merge unless asked.
2. **Record it in the current plan, in 10 lines or fewer:** what is done, what moved, and the new
   plan's path.
3. **Kick off conductor-v2** with the Agent tool (`subagent_type: conductor-v2`, `model: opus`).
   Brief it with:
   - the current plan's path, and the exact sections to read (the moved items, the relevant
     decision IDs, the findings), not the whole plan;
   - the moved scope, as a list;
   - "stay within `.github/agents/pr_scope_budget.md`; if still over, write an index plan plus
     the first PR's plan";
   - whether the owner is available. If not: resolve questions with defaults marked "owner to
     confirm".
4. **Order.** Don't start building the new plan until the current PR has landed or is explicitly
   paused, unless the new PR has to go first.
5. **Report to the owner:**

   ```
   Scope check: <plan> — <N> lines, <P> phases, tracks <…>, <F> findings. Over: <triggers>.
   Stopping point: <done / rolled back>; <committed | staged>.
   Split: <new plan path(s)> — <one line each>. Order: <new first | current first>.
   Needs you: <only if the split drops something user-visible from the current PR>.
   ```

## 4. Keep plans lean while briefing agents

- Tell implementers to write evidence to `<plan>.evidence.md`, and reviewers to write findings to
  `<plan>.review.md`. The plan keeps one-line checkboxes.
- Point each agent at the sections it needs (its phase, the ledger, the relevant findings), never
  "read the whole plan".
- The model per task and verification are covered by the memory notes on verifying agent claims.
  In short: use Opus for planning and review, Sonnet for mechanical fixes, and re-run the suites
  yourself before accepting "done".
