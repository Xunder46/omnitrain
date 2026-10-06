<!--
Standing rules for every Copilot agent run. The runner appends the sections that apply to the agent
to its prompt, so briefs never repeat them and a stale copy cannot spread from brief to brief.
A section applies when its heading is "## Every agent" or lists the agent's name in parentheses.
Change a rule here (through /retro), never in a brief. Lines inside these comment markers are not sent.
-->

## Every agent

Shell: your only shell command is the gateway, `.github/copilot/scripts/macos/gateway.sh`, spelled exactly like that and never
piped, chained or prefixed with `cd` (`.github/copilot/scripts/macos/gateway.sh list` shows the checks; each runs with its own
timeout). Everything else is denied by policy: read and search with your file tools. A denied command
is never retried, in any spelling, and never worked around: record what you needed under Open
questions. Exit 124 means a check timed out: diagnose it, never re-run it unchanged. If a fix fails
twice, stop and report; never run the same failing check a third time. Long output is saved under
.work/gateway/ and summarised: read that log by line range only when the summary is not enough.

Never use a test, a build or any other check to create, move or delete files or directories, or to do
anything else your tools deny. If the work needs a deletion, a new directory or another denied action,
list it under "Governor actions" in your final report and continue with the rest; the governor does it.
(A check that deletes tracked files is reverted by the gateway.)

Reading: every turn calls a tool; never write filler text. Read each file you need once, in large
ranges, and keep what you learned: do not re-read a section you already have unless you changed it.
Start where the brief's pointers say. Read in `.work/` only your brief and the gateway logs it names.

Git and pipeline: do not commit, push, reset or switch branches; do not touch .claude/, .github/,
AGENTS.md or CLAUDE.md.

## Implementers (developer, dba)

Work: write early. Make your first edit within the first few minutes, from the brief's pointers; read
further only to finish the item in hand. If a pointer is wrong, say so in your report and continue.

Files: create no scratch or probe files; remove one you made with `.github/copilot/scripts/macos/gateway.sh delete-scratch`. Run
formatters only on files you created, by explicit path. Edit existing files with minimal edits, then
check them with `.github/copilot/scripts/macos/gateway.sh git-diff --stat`: a diff bigger than your edit means undo and report.

Tests: no real-clock thresholds (bracket between timestamps, or poll to a deadline). Every new guard is
shown red first, or by a mutation: record the original line, change it, see the test fail, restore the
EXACT original, re-run green; never end a step with a mutation applied. If a change turns an EXISTING
test red that the plan did not predict, stop and report; do not edit that test. If a step's text
contradicts the plan's decisions, follow the decisions and log it in the Assumption Log.

Plan: update the plan's Progress table (one line per item) and Assumption Log as phases complete; put
baselines, suite outputs and red/green tables in the plan's .evidence.md, never in the plan.

OmniTrain: depend on WorkoutRepository only; keep `scripts/sqlite_schema.sql` and the seed in step with
models.dart; update the docs your change implicates, following docs/documentation_standard.md, and make
every doc sentence about behaviour name a test that exists (exact group + test name). Widget tests run
Mock-first (`--plain-name "Mock"`).

Before finishing: `.github/copilot/scripts/macos/gateway.sh lint` reports no more issues than the plan's
baseline (it exits non-zero on the repo's pre-existing info notices; files you touched have none), full
`.github/copilot/scripts/macos/gateway.sh test` green (paste the real counts), `.github/copilot/scripts/macos/gateway.sh swift-test`
green if Swift changed, the project invariant checks clean (`grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` returns nothing), and the plan's own residue sweeps.

## Reviewer (code-reviewer)

Create the plan's .review.md first, then append each finding as you find it. Run the full
`.github/copilot/scripts/macos/gateway.sh test` once and paste the counts; read the diff with `.github/copilot/scripts/macos/gateway.sh git-diff`, one file at a
time, once each.

## Planners (conductor, conductor-v2)

Write only at the paths your brief gives. Every phase item names its file and the symbol (function,
class or test) it changes, so implementers can start editing without research. Do not measure or
maintain line counts.
