---
description: Review the completed work with the Code Reviewer agent. Human checkpoint — the pipeline stops here.
argument-hint: <feature or plan-file path>
---

Invoke the `code-reviewer` subagent via the Task tool for:

$ARGUMENTS

Handling rules:
- It reads `.github/agents/plans/[feature]-plan.md` first and reviews against the plan's intent.
- It assesses and plans refactoring — it does not edit source code.
- **Human checkpoint**: it is the end of the automated pipeline. Do NOT invoke any further agent
  after it, and do not start a fix → review → fix loop.
- Present the reviewer's full verdict, then stop and wait for the user's instruction. The user
  decides whether to approve, send findings back to `/dba` or `/developer`, or re-plan with
  `/conductor-v2`.
- If the reviewer wrote a `## Feedback` section to the plan file, relay it and stop.
