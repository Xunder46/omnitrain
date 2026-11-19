# 25 · UI/UX standards refresh (docs only)

Status: **Done 2026-10-13.** Owner answered D1-D8 = A (all recommended) and approved the screen fixes. Survey, docs phases 2a-2d done; screen fixes are plans 26-29, enforcement is plan 30. Proposals for the owner's own pipeline files: `proposed-pipeline-changes.md` (not applied). Verified: flutter test +4467 ~1, analyze 181 (baseline 195).
Branch `claude_develop`, base `6d17994`. No file under `lib/`, `test/` or any existing doc has been changed.

## Goal and acceptance

Make the written UI/UX standards describe what the phone app does today, and give the owner a list of gaps
to rule on. Phone app only (not `watch/`, not `lib/watch/`). Docs only: **no screen or code changes in this plan.**

- Every statement the survey found untrue (evidence file, "Stale") is corrected or removed.
- Every rule the survey found only in past plans or only in code (evidence, "Never written") is written as a rule
  with its reason and a pointer to the test that guards it, or marked *unguarded*.
- Decisions D1-D8 are recorded in the ledger below with the owner's answer; the standards state the chosen rule.
- `design_system.md` and the widget catalog pages lose the numeric values, control lists and change-log text that
  `docs/documentation_standard.md` §3/§6.1 prohibit; each is replaced by a token/constant name and where it lives.
- No claim in an edited doc is left without a test pointer or an explicit "unguarded" mark (§4.2).
- `test/docs_indexing_contract_test.dart` stays green (64 KiB ceiling). `flutter test` pass/fail line pasted.

## Decision Ledger

| Id | Decision | Owner answer |
|----|----------|--------------|
| D-1 | Where a screen and a written standard disagree: list case by case, owner decides each | decided 2026-10-12 |
| D-2 | This pass is docs only; screen fixes are queued as separate plans | decided 2026-10-12 |
| D-3 | Standards are written as rule + reason + test pointer, per `documentation_standard.md` (no values) | decided by governor (follows the repo's own standard) |
| D1 | Error and notice messages: shared look, plain wording, no raw error text (A) or document as is (B) | open |
| D2 | Empty screens: one shared pattern (A) or per screen (B) | open |
| D3 | Unsaved work: every Save-button screen warns before discarding (A) or document as is (B) | open |
| D4 | Delete confirmations: always confirm (A) or allow silent for low stakes (B) | open |
| D5 | Add a destructive colour to every theme, name exceptions (A) or keep fixed red as an exception (B) | open |
| D6 | Label case: document Stats' convention (A) or make all uppercase (B) | open |
| D7 | Bottom actions: name three cases (A) or move routine editor to the shared button (B) | open |
| D8 | Duplicate ways to do one job: name the preferred piece (A) or allow hand-built (B) | open |

## Scenarios (docs checks, not app behaviour)

- S-1 Every identifier the edited docs name exists in `lib/` (grep). Fails today for: the resume-dialog widget, the
  deprecated-widget stubs, the "General" modality option, the renamed Add Food tab.
- S-2 No edited doc contains the values listed in evidence ("Doc off standard"). Fails today in `design_system.md`.
- S-3 Every rule added names an existing test file, or says *unguarded*. (Fails by construction until written.)
- S-4 `test/docs_indexing_contract_test.dart` passes.

## Phases

| Phase | Owner agent | Scope | Mode |
|-------|-------------|-------|------|
| 1 Survey | crew-scout ×9 | `.work/crew/**` | done, read-only |
| 2a Stale statements | crew-docs-keeper | the docs named in evidence "Stale" | serial, **needs no decision**, can start now |
| 2b Unwritten rules and D1-D8 | crew-docs-keeper | `design_system.md`, `global_conventions.md`, the area docs | serial, **after answers** |
| 2c Strip values | crew-docs-keeper | `design_system.md`, `docs/widget_catalog/*` | serial, after 2b (same files) |
| 3 Review | crew-reviewer + governor check | read-only | after 2c |
| 4 Optional: guard tests | crew-prover / builder-app | `test/` only | only if the owner approves |

Each phase is at most 8 items per run: split by doc, not by rule. Nothing runs until the owner says go.

## Queued, not in this plan

Screen fixes for the eight "broken today" items and any D-choice that is option B in a "change the screen" sense.
Plan each as its own PR with the conductor. Do not add them here.

Evidence: `2026-10-12-25-ui-standards-refresh-plan.evidence.md`. Raw survey sheets: `survey/`.
