---
description: Build a phased implementation prompt pack with the Prompt Engineer agent (iterative Q&A + repo analysis).
argument-hint: <feature or problem to turn into prompts>
---

Invoke the `prompt-engineer` subagent via the Task tool for:

$ARGUMENTS

Handling rules:
- It must ask at least one clarification batch before producing the pack, even when the request
  looks clear. Surface each batch and WAIT for answers, then let it continue the Q&A loop until
  acceptance criteria are pinned rather than guessed.
- It writes one markdown file at `.github/agents/plans/[feature]-copilot-prompts.md`, with each
  phase carrying intent, a concrete prompt, and acceptance criteria. It writes no production
  code and does not hand off to other agents unless asked.
- When the pack is written, present its path and stop — executing the prompts is the user's call
  (or a `/developer` run).
