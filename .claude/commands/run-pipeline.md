---
description: Run the OmniTrain build pipeline (conductor-v2 → dba → developer → code-reviewer). Mechanical fixes are applied automatically in one bounded pass; anything requiring a decision stops for you.
---

You are orchestrating the OmniTrain development pipeline for this request:

$ARGUMENTS

The shared plan file at `docs/plans/[feature]-plan/[feature]-plan.md` is the single
source of truth. Each agent reads and updates it. Track the actual plan-file
path the conductor establishes and ensure each subsequent agent uses it.

Run these subagents in strict sequence, by name, using the Task tool. Do not
skip a step, do not reorder, do not run them in parallel:

1. Invoke the `conductor-v2` subagent to analyze the request and produce the plan.
   - It asks ONE batched round of questions, each carrying a recommended
     default, so the user can answer "all defaults except Q3". Surface that
     round and WAIT for answers. This is a designed checkpoint, not a stall.
   - Do not expect a second question round, and do not ask the user to approve
     the plan — conductor-v2 presents it and names the next handoff.
   - Before continuing, confirm the plan carries **Done Criteria**, **Predicted
     Files**, and fixture-enumerated **Scenarios** per phase. A plan missing
     these cannot be verified mechanically downstream; send it back once with
     that reason rather than proceeding.

2. Invoke the `dba` subagent to implement the data layer per the plan.
   - Before continuing, confirm the dba updated the plan file's ## Progress.

3. Invoke the `developer` subagent to implement logic/UI per the plan.
   - The developer runs a mandatory Phase 0 scenario Q&A. Surface its questions
     to the user and WAIT for answers. Designed checkpoint.
   - Before continuing, confirm the developer updated ## Progress.

4. Invoke the `code-reviewer` subagent to review the completed work.

SCOPE CHECK — run the `pr-scope-guard` skill after step 1, after each implementation agent, and
after step 4. If it calls for a split:

- stop at a stopping point, where every item is done or not started and the suites are green;
- kick off conductor-v2 for the moved scope;
- report, instead of continuing the pipeline.

BOUNDED AUTO-FIX — exactly one pass, and only for findings with no decision
content:

- After the review, sort the findings into **mechanical** and **decision**.
- A finding is **mechanical** only if its correct form is fully derivable from
  something that already exists — the plan states an exact value, or the fix is
  a test assertion with one obvious target (tightening a loose or absent
  `expect`, asserting a value the plan already pins). Test-only fixes are
  mechanical by default: a wrong guess fails loudly in CI instead of shipping.
- A finding is a **decision** the moment the fix requires *choosing a
  user-visible value* the plan did not pin — a size, a percentage, a threshold,
  a label, an ordering. "e.g." and "tuned during dev" in a plan mean the value
  is NOT pinned. Never invent one.
- Invoke the `developer` (or `dba`, per the finding's layer) **once** to apply
  only the mechanical fixes, then re-run `flutter test` and `flutter analyze`.
  Do not re-invoke the reviewer, and do not start a second fix pass — one pass,
  then stop regardless of outcome.
- If a mechanical fix turns out to depend on an unresolved decision finding,
  leave it alone and say so. Do not partially apply it.

HARD STOP — this is the single human gate:
- After the bounded auto-fix pass, STOP. Present the reviewer's full verdict,
  then state plainly: which findings were auto-fixed and what the test run
  reported afterward, and which findings are left for the user and why each one
  needs a decision.
- Do NOT start a fix→review→fix loop. Any further cycle is started manually by
  the user in a separate run.

STUCK / FAILURE HANDLING:
- If any agent marks a phase Blocked or writes a ## Feedback note that it could
  not complete the work, STOP immediately and surface it to the user.
- Never retry a failed agent or operation blindly. If the same operation fails
  repeatedly, treat it as stuck: stop and report what happened.
- If the auto-fix pass leaves the suite red, STOP and report it. Do not attempt
  a follow-up fix.
