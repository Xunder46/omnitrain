---
description: Implement logic/UI for the current plan with the Developer agent (Phase 0 red tests → implementation → green tests, docs updated).
argument-hint: <feature or plan-file path>
---

Invoke the `developer` subagent via the Task tool for:

$ARGUMENTS

Handling rules:
- It reads `.github/agents/plans/[feature]-plan.md` first and tests against the plan's
  `## Scenarios` register. It does NOT run an interactive scenario Q&A — the register is the
  conductor's deliverable. If the register is missing or incomplete, stop and tell the user to
  run `/conductor-v2` first.
- Phase 0 is non-negotiable: tests are written and observed **failing** before implementation,
  then green. Require the actual `flutter test` pass/fail counts, not an inference from
  `flutter analyze`.
- After it finishes, confirm it updated the plan's `## Progress` checklist and marked the phase
  **Complete** or **Blocked**, and that it updated `navigation_and_screens.md`,
  `state_management.md`, and `widget_catalog.md`, or explicitly stated no update was needed.
- If it reports Blocked, do not retry: surface the `## Feedback` note and stop.

Next step is a separate command: `/code-reviewer`.
