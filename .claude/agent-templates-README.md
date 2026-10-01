# Agent Templates

Portable, project-agnostic starting points for a five-agent build pipeline plus a
standalone prompt-pack author. Copy the ones you want into a new project's
`.claude/agents/`, fill in the **Project Variables** block at the top of each
file, and delete whatever does not apply.

These are templates, not active agents. They are deliberately kept out of
`.claude/agents/` so they are not registered as callable subagents.

## The pipeline

```
conductor ──▶ data-architect ──▶ developer ──▶ code-reviewer ──▶ human
   (plan)         (data layer)     (logic/UI)      (verify)      (decide)
```

- **conductor** — plans and routes. Never writes source code.
- **conductor-v2** — the same role with a Decision Ledger, fixture-enumerated
  scenarios, and per-phase Done Criteria. Use this one for work that spans
  several sessions or several agents; use plain `conductor` for smaller teams
  or shorter-lived work. **Install one or the other, not both.**
- **data-architect** — owns models, persistence interfaces, storage
  implementations, migrations, and seed/fixture data.
- **developer** — owns application logic, state, UI, navigation, and tests.
- **code-reviewer** — verifies against the plan and the conventions doc. Assesses
  and plans fixes; does not implement them. Terminal human checkpoint.
- **prompt-engineer** — standalone. Turns intent into a phased prompt pack for a
  different agent or a different tool to execute.

## Setup, in order

1. **Copy** the agent files you want into `.claude/agents/`.
2. **Write the conventions doc first.** Every template points at
   `{{CONVENTIONS_DOC}}` as its rule source. Without it the agents fall back to
   guessing. It should hold the cross-cutting rules that apply to every task:
   layering, naming, error handling, shared utilities, formatting, and whatever
   your project keeps getting wrong.
3. **Fill in the Project Variables block** in each copied file. Grep for `{{`
   afterwards — an unresolved placeholder is a bug, not a default.
4. **Set `model:`** per agent. Cheaper models are usually fine for mechanical,
   checklist-driven work; reserve stronger ones for planning and review.
5. **Set `tools:`** to the minimum each agent needs. The planner and reviewer
   should not be able to write source files.

## Project Variables

Every template opens with this block. Same names across all files.

| Placeholder | Meaning | Example |
|---|---|---|
| `{{PROJECT_NAME}}` | The application | `Acme Ledger` |
| `{{STACK}}` | Language and framework | `TypeScript + React` |
| `{{SOURCE_ROOT}}` | Application source root | `src/` |
| `{{TEST_ROOT}}` | Test root | `tests/` |
| `{{DOCS_ROOT}}` | Agent-facing architecture docs | `docs/architecture/` |
| `{{PLANS_ROOT}}` | Shared plan files | `docs/plans/` |
| `{{CONVENTIONS_DOC}}` | The standing cross-cutting rules | `docs/conventions.md` |
| `{{DOC_STANDARD}}` | What docs may/may not contain (optional) | `docs/doc-standard.md` |
| `{{MODEL_DIR}}` | Domain models / entities | `src/domain/models/` |
| `{{PERSISTENCE_DIR}}` | Repositories / data access | `src/data/repositories/` |
| `{{STATE_DIR}}` | State / application logic | `src/state/` |
| `{{UI_DIR}}` | Screens / pages / views | `src/features/` |
| `{{SHARED_UI_DIR}}` | Reusable presentational components | `src/components/` |
| `{{CORE_DIR}}` | Cross-cutting utilities and constants | `src/core/` |
| `{{DATA_INTERFACE}}` | The persistence abstraction | `LedgerRepository` |
| `{{PRIMARY_IMPL}}` | Production implementation | `PostgresLedgerRepository` |
| `{{TEST_IMPL}}` | Test/dev implementation | `InMemoryLedgerRepository` |
| `{{SCHEMA_ARTIFACT}}` | Schema contract file, if any | `db/schema.sql` |
| `{{SEED_FILE}}` | Seed / fixture data | `src/data/seed.ts` |
| `{{DESIGN_SYSTEM_DOC}}` | Component and theming rules | `docs/design-system.md` |
| `{{LINT_CMD}}` | Lint / static analysis | `npm run lint` |
| `{{TYPECHECK_CMD}}` | Type check, if separate | `npm run typecheck` |
| `{{TEST_CMD}}` | Full test suite | `npm test` |
| `{{BUILD_CMD}}` | Build | `npm run build` |
| `{{RUN_CMD}}` | Run locally | `npm run dev` |

Not every project has every one. Delete the rows and the prose that do not apply
rather than leaving a placeholder standing.

## Conventions the templates share

- **The plan file is the contract.** One markdown file per feature under
  `{{PLANS_ROOT}}`, read at the start of every agent session and written back at
  the end. It carries requirements, decisions, scenarios, phases, progress, and
  feedback. Agents coordinate through it, not through chat history.
- **Verification is observed output, not inference.** Lint passing is not a test
  run. A completion claim requires pasted pass/fail counts. A new test for a bug
  fix must be shown to fail without the fix.
- **Decide-and-log.** Implementers never stall on ambiguity: they pick the option
  most consistent with the recorded decisions, log the choice and the reasoning,
  and continue. The planner or reviewer ratifies or reverts it later.
- **Output discipline.** Surgical edits, no full-file rewrites, no echoing
  unchanged code, structured handoff summaries only.
- **Every defect class becomes a permanent guard.** A fix without a test that
  makes the defect impossible to reintroduce is not a finished fix.
