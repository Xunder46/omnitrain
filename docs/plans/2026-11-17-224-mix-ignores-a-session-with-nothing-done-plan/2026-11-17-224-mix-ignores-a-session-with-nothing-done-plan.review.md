# Review: plan 224 mix-ignores-a-session-with-nothing-done · P1-P2 · 9e1e5a65..working tree
Verdict: APPROVE WITH FIXES
Counts: blocker 0 · major 1 · minor 4 · tests: not run (brief says the governor ran: new file 9 tests and 328 reader tests green, lint 181)
Diff vs Predicted Files: conforms for this plan's scope (`training_load.dart`, `stats_progress_service.dart`, new test file, `docs/training_load.md`). The working tree also carries other sessions' files (watch Swift, `test/stats_gallery_render_test.dart`, crew md files) — ignored per brief.
## Findings

1. [Major] `docs/training_load.md:66-68` — the first bullet still conditions the remainder on "A non-rolling session that holds a set effort". After this change `_hasSetEffort` (`stats_progress_service.dart:1003-1008`) also requires at least one stored observation row, so a session holding a row-less set effort (S-22404's emptied lift) gets nothing, and this bullet now contradicts the bullet two lines below and the code. A maintainer reading only the first bullet would re-derive the old rule. Fix: change the bullet to "holds a set effort with a stored row" (or cross-reference the next bullet). Guard: none needed — S-22404's first test already pins the behaviour; this is the doc catching up.

2. [Minor] `docs/training_load.md:85-92` — the Verified-by list names `training_load_test.dart`, `mix_no_sets_pure_test.dart` and `mix_no_sets_service_test.dart` but not `test/mix_session_with_nothing_done_test.dart` (S-22401..S-22404), the tests that pin the sentence added at :72. Plan 179's doc update added its own files to this list; this one did not. Fix: append the new file (and its scenario ids) to the list.

3. [Minor] `lib/core/models/interference.dart:52-54` — `InterferenceSession.hasSetEffort` is documented as "true when the session contains at least one effort whose section maps to Resistance", but `_hasSetEffort` now also requires a stored row. The diff made this comment false; the interference walk consumes the flag (`stats_progress_service.dart:727`). Fix: one-line comment update ("…that holds at least one stored row").

4. [Minor] plan "What the user sees" — "If it was the only workout in the window the Mix shows its 'no time yet' state for the window": a window whose only session is nothing-done returns null (`stats_progress_service.dart:809-812` — `windowSessionCount > 0` forces null even with `keepEmptyWindow: true`, `stats_progress_service.dart:561`), so no Mix card renders at all. `docs/stats_screen.md:245-247` documents exactly this ("a window that holds a session with zero time is still a null payload", S-17009) and the strip's own rule keeps the empty line out when a session sits in the span (`mix_layer.dart:120-131`). The behaviour is right and pre-documented; the plan's sentence is not. Fix: a Feedback line in the plan correcting the wording, so the owner's device check (Open item 1) looks for an absent card, not an empty-state line.

5. [Minor] skip-marked set gap — a session whose sets are all skip-marked still reads full Resistance: the skip marker is a reps row (`core/utils/entry_rows.dart:38-43`, written by `session_core_entry.dart` mark-skip; `_dropUnloggedSets` keeps it, `session_core_lifecycle.dart:141-142`), so `observationsOf(effort.id).isNotEmpty` is true and `_hasSetEffort` answers true. The sibling rule says the opposite: "a skip-marked set alone does not count" (`session_core_lifecycle.dart:172-174`). Not a regression (base behaved the same) and D-2's row-based rule covers it by design, but the plan's goal sentence "a session with no set that holds anything and no measured time contributes no time" does not hold on the skip path. List for the owner as a product decision; no code change requested here.

## Assumption Log rulings
- Entry 1 (base commit `9e1e5a65`, other sessions' files outside): ratified — the diff stat shows exactly those foreign files plus this plan's four.
- Entry 2 (no pre-existing S-224xx ids): ratified — the ids appear only in the new test file.

## Scenario coverage
- S-22401 -> `test/mix_session_with_nothing_done_test.dart` · 'S-22401 no set, no measured time, 2400 s: the map is empty'
- S-22402 -> same file · 'a set effort with no measured time keeps the remainder', 'a session with no effort at all keeps the remainder (the old rule)', 'a no-set session with measured time shares its whole duration (plan 179)', 'a rolling session with no measured time is unchanged'
- S-22403 -> same file · 'a session whose only exercise is a never-started round gives no time', 'a session with a finished round gives Sports its whole duration'
- S-22404 -> same file · 'a lift with nothing typed gives no time', 'a lift with one logged set gives Resistance only'
No scenario without a test.
