---
description: Plan a request with the Conductor agent (clarify → plan file → named handoff). Planning only; stops before implementation.
argument-hint: <feature request>
---

Invoke the `conductor` subagent via the Task tool to plan this request:

$ARGUMENTS

Handling rules:
- Surface its clarifying questions and WAIT for answers. That round is the designed checkpoint.
- The Conductor writes plan markdown only — never source code. Note the plan-file path it
  establishes (`docs/plans/[feature]-plan.md`) and reuse it in later commands.
- When it presents the plan it also names the next handoff. Do NOT ask the user to approve the
  plan — in this single-agent command, stop after presenting it.
- If the plan lacks **Done Criteria**, **Predicted Files**, or fixture-enumerated **Scenarios**
  per phase, send it back once with that reason instead of accepting it.

Next step is a separate command: `/conductor-v2` (re-plan), `/dba`, or `/developer`.
