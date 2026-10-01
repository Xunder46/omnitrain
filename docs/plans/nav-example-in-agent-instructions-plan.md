# Navigation Example in Developer Agent Instructions — Plan

## Overview

Stop new screens from reintroducing the screen-overlap navigation glitch by correcting the navigation example in the developer agent's instruction files. The developer agent instruction file (`developer.agent.md`) currently shows `Navigator.push(context, MaterialPageRoute(...))` as its reference navigation example in two places — new features copy this example, which is how the glitch keeps reappearing. Update only those navigation example blocks to use `OmniNavigator.push` per the navigation contract.

This is a **TRIVIAL** change — pure doc-instruction hygiene, no schema, no state, no UI behavior change, no executable tests.

## Requirements

- Replace the two `Navigator.push(context, MaterialPageRoute(...))` example blocks in `.github/agents/developer.agent.md` (in the `_openDetail` and `_createNew` helper methods under the "List with Actions" common-pattern section) with `OmniNavigator.push(context, (_) => Screen(...))`.
- Do not touch any other line of any file.
- Do not modify `docs/navigation_contract.md` (it shows the old pattern only as an explicit anti-pattern — correct).
- Do not modify `docs/route-migration-audit.md` (it shows the old pattern as historical "Before" entries — correct).
- Do not modify `docs/navigation_and_screens.md` (already uses the correct `OmniNavigator` pattern).
- Do not touch `Navigator.of(context).pop()` or `Navigator.pop(context, ...)` references — pop is out of scope for the navigation contract (it covers pushes only).
- Verify no other instruction document presents the one-off approach as a recommended example.

## Acceptance Criteria

- [ ] The two navigation example blocks in `developer.agent.md` use `OmniNavigator.push(context, (_) => Screen(...))`.
- [ ] A line-level diff of `developer.agent.md` shows changes confined to those two navigation example blocks; every other line is unchanged.
- [ ] `docs/navigation_contract.md` is not modified.
- [ ] `docs/route-migration-audit.md` is not modified.
- [ ] No other instruction document presents `Navigator.push(context, MaterialPageRoute(...))` as a recommended or reference example.

## Scenarios

### S-001: Developer agent reference example uses the standard navigation path (TRIVIAL — single scenario note)
- Trigger: A future developer agent implementation reads the "List with Actions" common-pattern section in `.github/agents/developer.agent.md`.
- Precondition: `docs/navigation_contract.md` mandates `OmniNavigator` for screen pushes.
- Flow: Developer agent reads the reference example for opening a detail / form screen from a list.
- Expected outcome: The example shows `OmniNavigator.push(context, (_) => Screen(...))` — the standard, contract-compliant path.
- Edge case of: none

## Iteration 1

### DB Changes
N/A

### Backend Changes
N/A

### Frontend Changes

Surgical edit to `.github/agents/developer.agent.md`:

| Location | Before | After |
|---|---|---|
| `_openDetail` method body (~line 543–552) | `Navigator.push(context, MaterialPageRoute(builder: (_) => ExerciseDetailScreen(...)))` | `OmniNavigator.push(context, (_) => ExerciseDetailScreen(...))` |
| `_createNew` method body (~line 579–586) | `Navigator.push(context, MaterialPageRoute(builder: (_) => ExerciseFormScreen(...)))` | `OmniNavigator.push(context, (_) => ExerciseFormScreen(...))` |

No other code (no `lib/`, no `test/`) is touched.

### Implementation Steps

1. Replace the `_openDetail` example block — change only the body of `_openDetail`, keep the signature and the surrounding code intact.
2. Replace the `_createNew` example block — change only the body of `_createNew`, keep the signature and the surrounding code intact.
3. Run `git diff -- .github/agents/developer.agent.md` and confirm changes are confined to those two method bodies.

## Progress

- [x] Plan authored
- [x] `_openDetail` example updated in `developer.agent.md`
- [x] `_createNew` example updated in `developer.agent.md`
- [x] Diff verified — changes confined to the two navigation example blocks
- [x] Confirmed `docs/navigation_contract.md`, `docs/route-migration-audit.md`, and `docs/navigation_and_screens.md` are not modified
- [x] Confirmed no other instruction document presents the one-off approach as a recommended example

## Feedback

### Phase 0 Complete ✓

### Phase 1 Complete ✓

> **N/A — no DB or repository change.** This is a TRIVIAL instruction-doc edit; no model, repository, or seed-data file is touched.

### Phase 2 Complete ✓

> **N/A — no logic, state, feature, widget, or test change.** This is a TRIVIAL instruction-doc edit; only `.github/agents/developer.agent.md` was modified and only within the two navigation example blocks (`_openDetail` and `_createNew` bodies) under the "List with Actions" common-pattern section.

### Phase 3 Complete ✓

> Code Review: ✅ APPROVED
>
> Layers in scope: docs (`.github/agents/developer.agent.md` only)
> Layers skipped: models, repositories, state, features, widgets, core, lib/, test/, scripts/
>
> PASS (all applicable rules):
> - Diff is confined to the two `_openDetail` and `_createNew` method bodies; signatures, surrounding context, and all other lines are unchanged.
> - `docs/navigation_contract.md` is not modified (still shows the old pattern as an explicit anti-pattern — correct).
> - `docs/route-migration-audit.md` is not modified (still shows the old pattern as historical "Before" entries — correct).
> - No other instruction document presents `Navigator.push(context, MaterialPageRoute(...))` as a recommended or reference example. `docs/navigation_and_screens.md` already uses the correct `OmniNavigator` pattern.
> - `Navigator.of(context).pop()` (line 467) and `Navigator.pop(context, ...)` (lines 561, 565) are intentionally untouched — pop is not in scope for the navigation contract (it covers pushes only).
>
> N/A — no executable code/tests: per the task, "None — these are instruction documents with no executable behavior. Their correctness is enforced indirectly by Item 4's guard test, which fails the build if the pattern these files previously taught reappears in application code." No `test/` or `lib/` files are touched, and no new tests are authored.
