---
description: Implement the data layer for the current plan with the DBA agent (models, repository interface and implementations, seed data, SQL contract).
argument-hint: <feature or plan-file path>
---

Invoke the `dba` subagent via the Task tool for:

$ARGUMENTS

Handling rules:
- It reads `docs/plans/[feature]-plan/[feature]-plan.md` first. If no plan file exists, or its
  `## Scenarios` and Done Criteria are missing or incomplete, stop and tell the user to run
  `/conductor-v2` first — do not let the agent guess.
- After it finishes, confirm it updated the plan's `## Progress` checklist and marked the phase
  **Complete** or **Blocked**.
- If it reports Blocked, do not retry: surface the `## Feedback` note and stop.

Next step is a separate command: `/developer`.
