# OmniTrain

<!-- agentic-pipeline:begin — managed by the installer; change pipeline.config and re-run -->
## Development pipeline

This repository is built by a planned, multi-agent pipeline. **Claude Code** reads this file through
`CLAUDE.md` (`@AGENTS.md`). **Copilot agents run by the pipeline do not load it** (the runner passes
`--no-custom-instructions` to keep every request small): they get the same facts from their agent file
and `.github/copilot/agent-rules.md`, and the runner adds the "Known long-running or hanging commands"
section below to their prompt. Keep the two in step when a fact changes.
Agents come in two editions: `.claude/agents/<name>.md` for Claude Code subagents, and
`.github/agents/<name>.agent.md` for GitHub Copilot CLI (which prefers them over the `.claude/` files).

### Project variables

| Variable | Value |
|---|---|
| Project / stack | OmniTrain — Flutter/Dart (iOS/Android, web-safe), Material 3, Hive persistence, ChangeNotifier state; watchOS client in Swift (watch/watchos) |
| Source / tests | `lib/` / `test/` |
| Architecture docs / index | `docs/` / `docs/README.md` |
| Conventions (binding rule source) | `docs/global_conventions.md` |
| Doc standard | `docs/documentation_standard.md` |
| Plans | `docs/plans/<feature>-plan/<feature>-plan.md` |
| Layers | models `lib/data/models/` · persistence `lib/data/repositories/` · state `lib/state/` · screens `lib/features/` · shared UI `lib/widgets/` · core `lib/core/` |
| Persistence interface | `WorkoutRepository` — production `HiveWorkoutRepository`, tests `MockWorkoutRepository` |
| Schema artifact / seed | `scripts/sqlite_schema.sql` / `lib/mock/seed_data.dart` |
| Design system | `docs/design_system.md` |
| Lint / typecheck / test | `flutter analyze` / `(not used in this project)` / `flutter test` |
| Build / run | `(not used in this project)` / `flutter run` |
| Base branch | `develop` |

"(not used in this project)" means the concept does not exist here: skip every rule that mentions it.

### Invariant checks (every change must leave these clean)

`grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` returns nothing

### Rules for every agent

- **The plan file is the contract.** Read `docs/plans/<feature>-plan/<feature>-plan.md` before writing anything;
  write Progress, the Assumption Log and Feedback back to it. Coordinate through the plan, never through
  chat history. Decisions are `D-n`, scenarios `S-n`; both are stable and never reused. Evidence goes in
  `<feature>-plan.evidence.md` and review findings in `<feature>-plan.review.md`, beside the plan; the
  plan stays within `.github/copilot/pr-scope-budget.md`.
- **Git belongs to the governor.** Never commit, push, reset, switch or check out branches.
- **Shell commands.** Copilot agents: the gateway `.github/copilot/scripts/macos/gateway.sh` is the only shell command they may
  run (everything else is denied by `.github/copilot/permissions/`). Claude Code agents: wrap long
  commands in `bash .claude/scripts/macos/with-timeout.sh <seconds> <cmd…>` — 300 s for installs, code
  generation and builds, 900 s for the full test suite. Exit 124 = timed out: diagnose,
  never re-run unchanged.
- **Never run a formatter or rewriting tool on a directory or the whole tree** — only on files you
  created or changed, by explicit path.
- **Verification is observed output.** Paste real pass/fail counts; "compiles" is not "passes"; a
  bug-fix test must be shown to fail without the fix.
- **If a fix fails twice, stop and report.** Never run the same failing command a third time.
- Do not edit `.claude/`, `.github/agents/`, `.github/copilot/` or this file.

### Where things live

| Path | What |
|---|---|
| `.claude/agents/` | Claude Code editions of the agents (planner, dba, developer, code-reviewer) |
| `.github/agents/` | GitHub Copilot CLI editions of the same agents |
| `.github/copilot/` | Copilot permission profiles (`permissions/`), the gateway and its checks (`gateway.conf`, `scripts/`) |
| `.claude/commands/` | `/feature` (governor), `/plan`, `/implement`, `/review`, `/resume`, `/run-pipeline`, `/retro` |
| `.claude/skills/pr-scope-guard/` | applies the PR scope budget (`.github/copilot/pr-scope-budget.md`) at each checkpoint |
| `.claude/scripts/` | the Copilot runner, timeout wrapper and OpenCode wrapper (macos edition), plus the shared proxy |
| `.claude/pipeline.env` | runner settings (no secrets) |
| `.work/` (gitignored) | briefs, run logs (`.work/runs/<RUN_ID>/`), full gateway output (`.work/gateway/`), `friction.md` |
| `docs/plans/` | one folder per plan: plan, evidence and review files (committed) |

Project-specific timeouts and known hangs: see **Known long-running or hanging commands** below this
block.
<!-- agentic-pipeline:end -->

## Known long-running or hanging commands

<!-- Yours to edit; the installer never rewrites this section. List commands that run long or have
     hung, the timeout to use, and the known cause. For Copilot agents, add such commands as gateway
     checks (GATEWAY_EXTRA in pipeline.config) with a timeout. -->

- `flutter test` (full suite): several minutes; run it with a 900 s timeout. A widget test that opens
  the Hive harness, or awaits a real `Future.delayed`, inside `testWidgets` hangs forever at ~0% CPU
  (FakeAsync never advances real time). Run widget tests Mock-first and seed Hive in `setUp`.
- A test file whose Mock group is red can leave its Hive group hanging behind it: fix the red group
  first instead of re-running the whole file.
- `flutter analyze`: exits non-zero while the repo carries pre-existing info notices; compare the issue
  count with the plan's baseline.
- `swift test` in `watch/watchos`: compiles the watch package; the watch app target itself needs
  `xcodebuild` for a watchOS simulator, which only the governor runs.
