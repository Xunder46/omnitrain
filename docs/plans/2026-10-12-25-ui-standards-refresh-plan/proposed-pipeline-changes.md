# Proposed changes to the pipeline files (for the owner to decide; NOT applied)

These files are yours (`AGENTS.md` says agents do not edit them), so they are proposals. The crew's own files already carry the same rules
(`.github/copilot/crew-rules.md` "UI standards", `.claude/commands/crew.md` pre-run checklist). Why: the survey found the standards were rules in prose with no
check, so breaks accumulated unseen (8 wrong button shapes, 18 unlabeled buttons, about 70 raw messages). Since 2026-10-13 the checks exist, but only runs that
execute the tests see them.

1. `AGENTS.md`, "Invariant checks (every change must leave these clean)": add
   `flutter test test/ui_standards_contract_test.dart test/docs_indexing_contract_test.dart` passes (new UI breaks and stale doc names/values fail here).
2. `AGENTS.md`, "Rules for every agent": add "Fix what you touch: if a file you edit has a listed deviation (see `test/helpers/ui_standards_allowlist.dart`) or
   breaks a written UI standard, fix it in the same change when it is a few lines; otherwise list it under 'Standards seen, not fixed' in your report. Never add an
   allowlist entry or raise a ratchet to make a check pass: stop and report."
3. `.github/copilot/agent-rules.md` (shared pipeline): copy the "UI standards" section from `.github/copilot/crew-rules.md` for developer and code-reviewer roles.
4. `.github/agents/code-reviewer.agent.md`: add to the Blocker list "adds an allowlist entry, raises a ratchet number, or introduces a raw piece the standards name
   (`Card`, `SnackBar`, bare `IconButton`, shapeless button, colour literal)". Add to Major "a copy change to a message, empty state or label is a product change: list it for the owner".
5. Plan template used by the conductors: add a line "UI standards impact: which shared pieces (`docs/design_system.md`, 'Shared pieces and rules per job') this change uses; any new
   exception, with the owner-approved reason".
6. `CLAUDE.md`, "Working Rules": one line pointing at the section "Shared pieces and rules per job" and "How these rules are enforced" in `docs/design_system.md`.
7. `.claude/commands/feature.md` (shared governor): copy the crew pre-run checklist (mkdir before builders, `git add -N` before reviewers, no computations asked of agents).
