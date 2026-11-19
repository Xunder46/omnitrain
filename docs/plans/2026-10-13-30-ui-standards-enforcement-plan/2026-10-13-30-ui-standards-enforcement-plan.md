# 30 · Keep the standards true: enforcement and visibility

Status 2026-10-13: Built (ratchets for sheets and dialogs, widened colour ratchet, docs symbol and value checks). All five mutations caught by the governor. E-7 is `proposed-pipeline-changes.md` in the plan 25 folder (not applied). Final: flutter test +4467 ~1, analyze 181.

Parent: `docs/plans/2026-10-12-25-ui-standards-refresh-plan/`. Owner asked 2026-10-13: "enforce or redefine so these don't happen again ...
so 'broken windows' are fixed when caught". Starts after plans 26-29.

## Why the problems happened (from the survey)

1. Rules lived in prose and in plans; only a few had a test. A new violation could not fail anything (shape rule: 8 breaks; labels: 18).
2. Docs drifted because nothing compared them with the code (30+ untrue statements; the audit doc still described a deleted widget).
3. A known deviation had no home: it was either silently tolerated or lost in a plan. Nobody saw the pile growing (71 raw snackbars, 16 raw sheets).
4. Builders and reviewers were never told which shared pieces the standards require.

## What this plan adds (all inside the repo, none touches the owner's pipeline files)

| Id | Change | Effect |
|----|--------|--------|
| E-1 | Ratchet tests in `test/ui_standards_contract_test.dart`: raw `showModalBottomSheet(` outside shared files may not exceed today's 16; raw `AlertDialog(` outside `lib/widgets/dialogs` and `lib/widgets/pickers` may not exceed today's count; `Colors.white/black` per-file counts (done in plan 26) | Growth of known debt fails the build; the number only goes down |
| E-2 | Allowlist self-check (plan 26): an entry whose violation is fixed makes a test fail until the entry is removed | Fixed windows stay fixed and the list shrinks by itself |
| E-3 | Docs symbol check in `test/docs_indexing_contract_test.dart`: every `OmniXxx` class and `OmniTheme.member` named in `docs/design_system.md` and `docs/widget_catalog*` exists in `lib/` | The "doc names a thing that no longer exists" class fails the build |
| E-4 | Docs value check in the same file: `docs/design_system.md` and `docs/widget_catalog*` carry no number followed by `dp`, `px`, `ms` or `%` | Prevents the values from creeping back (documentation standard 3.4) |
| E-5 | `crew-rules.md` "UI standards" section (done by the governor 2026-10-13): builders use the shared pieces, fix what they touch, never add an allowlist entry; reviewer treats new entries and raised ratchets as Blockers | Visibility at the moment of change |
| E-6 | `docs/design_system.md` and `docs/global_conventions.md`: a section "How the rules are enforced" listing each rule, its test, or `unguarded`, the ratchet files, and the rule "fix what you touch" (docs phase 2b) | One place to see the state of every standard |
| E-7 | `proposed-pipeline-changes.md` in the plan 25 folder: wording for the owner's files (`AGENTS.md` invariant checks, plan template, developer/reviewer agent rules). NOT applied: those files are the owner's | Owner decides |

## Scenarios

- S-3001 Ratchet: a temporary extra `showModalBottomSheet(` in a scratch lib file makes the sheet ratchet fail (governor mutation, not a builder task).
- S-3002 E-3: temporarily renaming `OmniEmptyState` in the catalog to `OmniEmptyStatez` makes the symbol check fail (governor mutation).
- S-3003 E-4: temporarily adding "12 dp" to `design_system.md` makes the value check fail (governor mutation).
- S-3004 Allowlist self-check: removing a `Color(0x...)` allowlist target line fails the self-check (governor mutation).

## Phases

| Phase | Agent | Scope | Items |
|-------|-------|-------|-------|
| 1 | crew-builder-app | `test/**` only | E-1, E-3, E-4 (no production code) |
| 2 | crew-docs-keeper | `docs/design_system.md`, `docs/global_conventions.md`, `docs/widget_catalog.md`, `docs/widget_catalog/*` | E-6 plus the new rules from owner decisions D1-D8 (docs phase 2b of plan 25) |
| 3 | governor | | S-3001..S-3004 mutations, E-7 file, crew.md change log |
