# Evidence — watch-session-sync PR 3a, Phase 1 (the contract)

Executor: @developer (Copilot CLI edition), 2026-10-05. Scope: the plan's Phase 1, items 1–7, per
`.work/watch-pr3/brief-dev-1.md` and the governor's split (PR 3a = Phases 1, 2, 4; PR 3b = Phase 3).

Phase 1 ships no production code: it is the contract, its fixtures and the tests that hold them.
"Red first" is therefore a **mutation** run — the expected values are made deliberately wrong, the
suites are shown to catch each one, and the exact originals are restored before the green run.

## Baselines (from the brief, before this phase)

| Check | Baseline |
|---|---|
| `gateway.sh test` | `+3913 ~1`, 0 failures |
| `gateway.sh swift-test` | 268 tests, 0 failures |
| `gateway.sh lint` | 196 issues, 0 errors |

## Red first — three mutations, all caught

RED run: `.github/copilot/scripts/macos/gateway.sh test test/sync_protocol_fixtures_test.dart test/watch_reconciliation_cross_stack_test.dart`
→ `00:00 +88 -3: Some tests failed.` (91 tests in the two files; 3 red).
Log: `.work/gateway/test-20261005-234834-23941.log`

| # | Mutation applied | Restored to | Observed red |
|---|---|---|---|
| 1 | `test/sync_protocol_fixtures_test.dart` — expected entry `'reps': 9` | `'reps': 8` | `S-31 phone-logged entries an entry names its slot, its exercise, its set and its log time [E]` … `Which: at location ['reps'] is <8> instead of <9>` |
| 2 | `test/watch_reconciliation_cross_stack_test.dart` — `containsAll([...named, 'entry-slot-bench-9'])` (an id no stack holds) | `containsAll(named.toSet())` | `S-31 a snapshot's own entries are absorbed by both stacks, once each [E]` … `Expected: contains all of ['entry-slot-bench-0', 'entry-slot-bench-0', 'entry-slot-bench-1', 'entry-slot-bench-9'] / Actual: ['entry-slot-bench-0', 'entry-slot-bench-1'] / Which: has too few elements (2 < 4)` |
| 3 | `watch/sync_protocol/fixtures/reconciliation/phone_entries_merge.json` — `expected.entries[2].loadKg: 62.75` | `62.5` | `S-004 every reconciliation fixture converges on its expected state [E]` … `Which: at location ['entries'][2]['loadKg'] is <62.5> instead of <62.75>` |

Mutation 3 is the one that proves the new reconciliation fixture is picked up by the register loop
(`S-004`) and actually replayed, not merely present: the loop reads the fixture from disk, runs it
through the phone reconciler and compares the whole converged state.

**A test defect of mine, found by the same run family.** The first restore turned the cross-stack
assertion green on the *intended* ids but red on the list's shape: `named` is collected from every
snapshot in the fixture, and snapshot 2 deliberately re-carries `entry-slot-bench-0`, so `named`
holds that id twice and `containsAll(named)` demanded a duplicate. The assertion was corrected to
`containsAll(named.toSet())` — the intent (every id the fixture names is held, no id doubled) is
unchanged and the no-doubling expectations below it already cover repetition. Run: `+90 -1`, the one
failure the `containsAll` above. No production or fixture value changed.

## Green

GREEN run (the exact originals restored, nothing else touched):
`+91: All tests passed!` — 91 tests in `test/sync_protocol_fixtures_test.dart` +
`test/watch_reconciliation_cross_stack_test.dart`, 0 failures.
Log: `.work/gateway/test-20261005-234854-24085.log` (first green attempt, `+90 -1`, is the test defect
above) and the corrected run `00:00 +91: All tests passed!` (same command, printed inline).

Both new fixtures are on the register, so the existing loops drive them without new loop code:

| Check | Result |
|---|---|
| `gateway.sh test test/live_mirroring_test.dart test/watch_session_engine_test.dart` | `+61: All tests passed!` — `phone: reconciliation/phone_entries_merge.json converges on its expected state` and `watch: reconciliation/phone_entries_merge.json converges on its expected state` both ran, asserting full `entries` equality on each stack |

## Phase Done Criteria — observed output

| Check | Command | Result |
|---|---|---|
| Flutter, whole suite | `gateway.sh test` | `01:31 +3920 ~1: All tests passed!` — 3920 passing, 1 skipped, **0 failures** (log `.work/gateway/test-20261005-234918-24413.log`) |
| Swift package | `gateway.sh swift-test` | `Executed 268 tests, with 0 failures (0 unexpected) in 1.015 seconds`, exit 0 (log `.work/gateway/swift-test-20261005-235327-29613.log`) |
| Lint | `gateway.sh lint` | `196 issues found. (ran in 2.9s)`, 0 errors; exit 1 on the pre-existing info notices, unchanged from the baseline. No issue mentions either edited test file (log `.work/gateway/lint-20261005-235333-29719.log`) |

`+3920` is `+3913` plus seven, and all seven are accounted for by observed tests:

- **3 new tests** written by this phase (S-31 ×2 in `test/sync_protocol_fixtures_test.dart`, S-31 ×1 in
  `test/watch_reconciliation_cross_stack_test.dart`).
- **4 register-generated tests**, because the loops iterate the fixture register and now see the two
  new files: `S-001 fixtures valid/session_snapshot_with_entries.json conforms to session_snapshot`
  (the `for` loop over `validFixtures`), `S-008/S-009 A phone snapshot adds the entries it logged,
  under its own ids converges on both stacks` (the `for` loop over reconciliation fixtures in the
  cross-stack file), and the `live_mirroring_test.dart` pair (`phone:` and `watch:` for the new
  reconciliation fixture).

`swift-test` is unchanged at 268: the Swift fixture replay validates the valid fixtures in one test
rather than one per file, and reads the new files through the same loader (0 failures).

## Final re-run after the last doc edit

After the series-index row gained the 3a/3b split, the tree the run above was measured against had
changed in `docs/` only, so the doc-size gates and the whole suite were re-run on the final tree:

| Check | Result |
|---|---|
| `gateway.sh test test/docs_indexing_contract_test.dart` | `+9: All tests passed!` — no file exceeds the 64 KiB ceiling, none in the warning band, all relative links resolve. The split note pushed neither the plan nor the index over the ceiling. Re-run green after the final plan edit (`## Notes` now points at the overrule), the only test that inspects `docs/`. |
| `gateway.sh test` | `01:35 +3920 ~1: All tests passed!` — same count as the run above, 0 failures (log `.work/gateway/test-20261005-235510-30218.log`), and again on the final tree after the `docs/plans/` edits: `01:35 +3920 ~1: All tests passed!` (log `.work/gateway/test-20261005-235741-35360.log`) |

## What this phase did not change

- No production code, no schema, no schema version, no model, no repository, no screen (as predicted —
  the wire already requires and validates `entries`).
- The PROTOCOL amendment documents D-33, D-34 and D-36 only. D-35's re-statement rule is Phase 3
  (PR 3b) and no sentence here claims it: a held id "MUST NOT be stored a second time" (dedup, which
  is the behaviour today) and nothing is said about the *values* of a re-stated id.
