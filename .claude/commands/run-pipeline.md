---
description: Run the OmniTrain build pipeline (conductor → dba → developer → code-reviewer), stopping at the reviewer's verdict. Fixes are manual.
---

You are orchestrating the OmniTrain development pipeline for this request:

$ARGUMENTS

The shared plan file at `.github/agents/plans/[feature]-plan.md` is the single
source of truth. Each agent reads and updates it. Track the actual plan-file
path the conductor establishes and ensure each subsequent agent uses it.

Run these subagents in strict sequence, by name, using the Task tool. Do not
skip a step, do not reorder, do not run them in parallel:

1. Invoke the `conductor` subagent to analyze the request and produce the plan.
   - The conductor asks clarifying questions before planning. Surface those
     questions to the user and WAIT for answers before continuing. This is a
     designed checkpoint, not a stall.
   - Proceed only once the conductor has written the plan and named the next agent.

2. Invoke the `dba` subagent to implement the data layer per the plan.
   - Before continuing, confirm the dba updated the plan file's ## Progress.

3. Invoke the `developer` subagent to implement logic/UI per the plan.
   - The developer runs a mandatory Phase 0 scenario Q&A. Surface its questions
     to the user and WAIT for answers. Designed checkpoint.
   - Before continuing, confirm the developer updated ## Progress.

4. Invoke the `code-reviewer` subagent to review the completed work.

HARD STOP — this is the single human gate:
- After the code-reviewer produces its verdict, STOP — whether it APPROVES or
  finds issues. Present the reviewer's full verdict to the user.
- Do NOT automatically invoke the dba or developer to apply fixes. Any fix
  cycle is started manually by the user in a separate run.

STUCK / FAILURE HANDLING:
- If any agent marks a phase Blocked or writes a ## Feedback note that it could
  not complete the work, STOP immediately and surface it to the user.
- Never retry a failed agent or operation blindly. If the same operation fails
  repeatedly, treat it as stuck: stop and report what happened.

After creating the file, confirm its path and summarize what the command does.
