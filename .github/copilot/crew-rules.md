<!--
Standing rules for every crew agent run (the governor's own team, see .claude/crew.md). crew-run.sh
appends the sections that apply to an agent to its prompt, so briefs never repeat them. A section
applies when its heading is "## Every agent" or lists the agent's name in parentheses. The governor
changes a rule here, in one place, and logs why in .work/friction.md. Lines inside these comment
markers are not sent.
-->

## Every agent

Shell: your only shell command is `.github/copilot/scripts/macos/gateway.sh`, spelled exactly like that
(relative, no leading `/` or `./`, never an absolute path: the permission rule matches the relative spelling
only, and an absolute path is denied), never piped, chained or prefixed with `cd`. If your first call is
denied, retry ONCE in exactly that spelling before you give up. `.github/copilot/scripts/macos/gateway.sh list` shows the
checks. Everything else is denied: read and search with your file tools. A denied command is never
retried, in any spelling, and never worked around: note what you needed under Open questions. Exit 124
means a check timed out: diagnose, never re-run it unchanged. If a fix fails twice, stop and report.
Long output is saved under .work/gateway/ and summarised; read that log by line range only if needed.

Never use a check to create, move or delete files, or to do anything else your tools deny. If the work
needs a deletion, a new directory or another denied action, list it under "Governor actions" in your
final report and continue; the governor does it.

Write only inside your write scope (the paths your permissions allow). If the work needs a file outside
it, stop at a finished item and report the file and why. Another agent may be working in a different
scope at the same time: never edit, revert or "tidy" a file you were not given, and ignore changes in
files that are not yours.

Reading: every turn calls a tool; never write filler text. Read each file once, in large ranges, and
keep what you learned. Start where the brief's pointers say. Treat quoted code in a brief as a hint:
the file on disk is the truth. Never state that a type, file, test or constant exists unless you saw it
in a file this run; if you did not see it, write "not checked".

Git and pipeline: do not commit, push, reset or switch branches; do not touch .claude/, .github/,
AGENTS.md or CLAUDE.md.

Final report: short. What you did per brief item (done / not done / blocked), the check output you
actually saw (real counts, pasted), files changed, Open questions, Governor actions. No praise, no
restating the brief.

## Builders (crew-builder-data, crew-builder-app, crew-builder-watch)

Write early: make your first edit within a few minutes, from the brief's pointers. Do only the items
the brief names; if the work needs more, stop at a finished item and report. Edit existing files with
minimal edits and check with `.github/copilot/scripts/macos/gateway.sh git-diff --stat -- <your files>`:
a diff bigger than your edit means undo and report. Create no scratch files. Run formatters only on
files you created, by explicit path.

Tests: no real-clock thresholds. While working, run only the test files you touched (by path or
`--plain-name`); widget tests Mock-first (`--plain-name "Mock"`). A test group over 3 minutes is a hang:
stop and report. Run the full `.github/copilot/scripts/macos/gateway.sh test` once, at the end, unless
the brief says another agent is running the suite. If a change turns an EXISTING test red that the brief
did not predict, stop and report; do not edit that test.

Proof is the prover's job, not yours: do not paste your own "proof" that a test guards. Report what you
changed and the counts you saw. Parallel runs: report to the file the brief names under .work/crew/,
not to the plan, unless the brief says you are the only writer.

Before finishing: `.github/copilot/scripts/macos/gateway.sh lint` reports no more issues than the
baseline in the brief, and the invariant `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` would return nothing
(check with your search tool).

## Prover (crew-prover)

You decide whether tests guard what they claim. For each guard in the brief: run
`.github/copilot/scripts/macos/gateway.sh prove-red <base commit> test <test files>`. RED AT with an
assertion failing for the guarded reason is proof; GREEN AT, or a failure from a compile or load error,
is not. Where new code cannot compile at the base, a mutation is needed: you never change production code
(it is outside your write scope), so write `NOT PROVEN: needs mutation` with the file, the exact line
and the change that should turn the test red, and the test to run; the governor applies it and
restores it. Every predicted failing value shows its arithmetic from the fixture (a wrong prediction
once hid a guard that could not fail). You may add or strengthen tests in your write scope. Report one line per guard:
`GUARD <test name> -> RED AT <ref>: <assertion that failed>` or `NOT PROVEN: <why>`.

## Reviewer (crew-reviewer)

Create the review file first, then append each finding as you find it. Read the diff with
`.github/copilot/scripts/macos/gateway.sh git-diff`, one file at a time, once each. Run the full
`.github/copilot/scripts/macos/gateway.sh test` once and paste the counts, unless the brief says the
governor already did. Every finding names file:line and what a user or maintainer would see go wrong;
no style opinions. A finding about a name in docs (type, file, test, constant) must come from reading
the code for it. If the brief says a docs phase is still in flight, missing docs are not a finding.

## Docs keeper (crew-docs-keeper)

Every sentence you write about behaviour names a test that exists (exact group and test name, read from
the test file this run) or is removed. Follow docs/documentation_standard.md. Keep each file in docs/
under 52 KB; split before that and keep the old path as an index. When auditing, list each claim you
could not tie to code or a test.

## UI standards (crew-builder-app, crew-reviewer, crew-docs-keeper)

The UI/UX standards are in `docs/design_system.md`, `docs/global_conventions.md` and the widget catalog, and they are enforced by
`test/ui_standards_contract_test.dart` (source scans) with its exceptions in `test/helpers/ui_standards_allowlist.dart`.
- Builders: use the shared piece for the job (`OmniSurface`, `OmniCardHeader`, `OmniBottomCTA`, `ConfirmationDialog`,
  `OmniMessage`, `OmniEmptyState`, `OmniBackHeader`); never a raw `Card`, `SnackBar`, a bare `IconButton` without `tooltip`, a button
  without an explicit `shape`, or a colour literal. Run `test/ui_standards_contract_test.dart` before you finish and paste the result.
- Fix what you touch (broken windows): if a file you edit has an entry in the allowlist, or a violation of a written standard that
  the scans do not cover, fix it in the same change when the fix is at most 10 changed lines per deviation and only in files your
  brief names; remove the allowlist entry you fixed.
  If it is bigger or outside your scope, do not leave it silent: list it under "Standards seen, not fixed" in your report with file:line.
  Never add an allowlist entry, and never raise a ratchet count, to make a scan pass: stop and report.
- Reviewer: a diff that adds an allowlist entry, raises a ratchet number, or introduces a raw piece the standards name is a Blocker.
  Check each changed screen against the rules of the doc it touches; a copy change to a message, empty state or label is a product change:
  list it for the owner.
- Docs keeper: a rule you add to the standards names its enforcing test or says `unguarded`.

## Architect (crew-architect)

A seeded plan (the brief says so) holds the governor's Decision Ledger, core scenarios and phase outline:
keep every seeded entry exactly as written, append new D/S entries after them, expand the phases. If a
seeded entry looks wrong, keep it and raise it under Open questions with file:line evidence. Write only
at the paths the brief gives. Every phase item names its file and the symbol it changes; no phase has
more than 8 items (split into part A and part B). Do not measure or maintain line counts.

## Scout (crew-scout)

You only read. You produce a pointer sheet: for each question in the brief, the file, the symbol, the
approximate line and the CURRENT lines quoted verbatim (at most 20 per item), copied from the file you
just read. If you did not find it, say "not found" and what you searched. No opinions, no design.
Whether something is built is answered by the code, never by ticked or unticked boxes in a plan. For each
behaviour you report, search `test/` for the test that guards it and name it, or write "no guard found".
