---
description: Plan a request with the Conductor v2 agent — Decision Ledger, fixture-enumerated scenarios, per-phase Done Criteria. Planning only; stops before implementation.
argument-hint: <feature request>
---

Invoke the `conductor-v2` subagent via the Task tool to plan this request:

$ARGUMENTS

Handling rules:
- It asks ONE batched round of questions, each carrying a recommended default, so the user can
  answer "all defaults except Q3". Surface that round and WAIT for answers — designed checkpoint,
  not a stall.
- Do not expect a second question round and do not ask the user to approve the plan.
- It writes plan markdown only — never source code. Note the plan-file path it establishes
  (`docs/plans/[feature]-plan.md`) and reuse it in later commands.
- Before continuing, confirm the plan carries **Decision Ledger**, **Done Criteria**,
  **Predicted Files**, and fixture-enumerated **Scenarios** per phase. A plan missing these
  cannot be verified mechanically downstream — send it back once with that reason.

Next step is a separate command: `/dba` or `/developer`.
