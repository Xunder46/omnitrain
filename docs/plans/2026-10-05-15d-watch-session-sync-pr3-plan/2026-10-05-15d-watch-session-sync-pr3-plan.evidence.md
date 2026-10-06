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

---

# Evidence — watch-session-sync PR 3a, Phase 2 (the phone's projection)

Executor: @developer (Copilot CLI edition), 2026-10-05. Scope: the plan's Phase 2, items 1–7, per
`.work/watch-pr3/brief-dev-2b.md` (governor's split: PR 3a = Phases 1, 2, 4; PR 3b = Phase 3).
Baselines inherited from Phase 1's final tree: `test` `+3920 ~1`, `swift-test` 268 / 0, `lint` 196 / 0.

Phase 2 changes production code, so "red first" is two things: the scenario tests were written against
the register before the projection filled `entries` (every S-31…S-42 assertion on entries was red while
the answer carried none — the failure shape was `Bad state: No element` from the radio, i.e. the phone
answered nothing), and each load-bearing line was then **mutated** and shown to be caught.

## Red first — four mutations, all caught

Each mutation was applied to the working tree, the run observed, and the exact original restored before
the next one. The four cover the four decisions the code exists to honour: the answer carries entries
(D-31), the wrist's own row claims its group (D-34), the wire cannot carry every set (D-40), and
nothing comes from a clock (D-36/D-39).

| # | Mutation applied | Restored to | Observed red |
|---|---|---|---|
| 1 | `watch_session_adoption_bridge.dart` — `'entries': const <Object?>[]` | `'entries': PhoneEntries.ordered(entries)` | 8 of 10 red: `S-31 the phone's own sets arrive as entries`, `S-32 the same answer twice doubles nothing`, `S-33 the wrist's own set is not sent back to it`, `S-34 one live row claims one ladder group`, `S-37 a phone entry counts like the wrist's own`, `S-38 the wrist adopts a session it does not hold`, `S-40 two sessions do not share entries`, `S-42 a set the wire cannot carry is omitted`. `S-36` and `S-39` stayed green — both already expect no entries or an echo. |
| 2 | `watch_session_adoption_bridge.dart` — `wristLoggedAtMs: const []` | `wristLoggedAtMs: wristStamps[effort.id] ?? const []` | 3 red: `S-33`, `S-34`, `S-37` — each showed the extra `entry-slot-bench-1` that the wrist's own row should have claimed, i.e. the phone sending the wrist its own set back. |
| 3 | `phone_entries.dart` — `if (set['skipped'] == true \|\| reps < 1) return null;` → `if (reps < -1) return null;` | the two-condition guard | `S-42` red: `Expected: ['entry-slot-bench-1'] / Actual: ['entry-slot-bench-0', 'entry-slot-bench-1']` — the skipped set reappears on the wire. |
| 4 | `phone_entries.dart` — `'loggedAt': utcIso(DateTime.fromMillisecondsSinceEpoch(stampOf(group), isUtc: true))` → `utcIso(DateTime.now().toUtc())` | the row's own instant | `S-39` red: `Differ at offset 110` — `…05:13:02.014789Z` vs `…05:13:02.024155Z`, two Syncs of one unchanged ladder differing only in the clock reading. Reason line: "S-39 byte-identical: the ids come from the ladder and the instants from the rows, never from a clock or a counter". |

Mutation 4's transcript, verbatim:

```
00:00 +0 -1: …/test/watch_session_projection_test.dart: S-31…S-42 the sets the phone logged ride the
answer S-39 the projection is deterministic, and an echo is not sent [E]
  Expected: '[{"entryId":"entry-slot-bench-0",…,"loggedAt":"2026-10-06T05:13:02.014789Z",…},…
    Actual: '[{"entryId":"entry-slot-bench-0",…,"loggedAt":"2026-10-06T05:13:02.024155Z",…},…
     Which: is different.
            Expected: ... 05:13:02.014789Z","s ...
              Actual: ... 05:13:02.024155Z","s ...
                                    ^
             Differ at offset 110
  S-39 byte-identical: the ids come from the ladder and the instants from the rows, never from a clock
  or a counter
  test/watch_session_projection_test.dart 1113:7      main.<fn>.<fn>
00:20 +0 -1: Some tests failed.
```

Command: `.github/copilot/scripts/macos/gateway.sh test --plain-name "the projection is deterministic"`.

## Green

| Run | Result |
|---|---|
| `gateway.sh test test/watch_session_projection_test.dart test/live_mirroring_test.dart` (final tree, all four mutations reverted) | `00:00 +65: All tests passed!` — 65 tests across the two files, 0 failures. Includes the ten S-31…S-42 projection tests, the two mirror-level tests, the Mock/Hive parity pair and the byte-equality test. |
| `gateway.sh test --plain-name "the sets the phone logged ride the answer"` | `+10: All tests passed!` |
| `gateway.sh test --plain-name "S-31"` | `+18: All tests passed!` — the new projection group, the pre-existing fixture tests and the Mock/Hive parity trio |

## Test defect of mine, found by the red run

The first attempt failed with `Bad state: No element` from `lastOfType('session_snapshot')` in all ten
new tests, and the same shape broke the **pre-existing** `S-2` test. The cause was the import list, not
the projection: `test/helpers/repository_harness.dart`'s `seedExercise` passes capabilities inline to
`createExercise`, but `MockWorkoutRepository.createExercise` stores only the exercise and
`getExerciseById` reads a separate capability map filled by `setExerciseCapabilities` — so every
seeded exercise came back capability-less, `_slotFor` returned null for every slot, and `projectSession`
returned null. Fixed by taking `seedExercise` from `helpers/watch_capture_import_harness.dart` (which
calls `setExerciseCapabilities`) and `hide`-ing the other, with the reason in a comment at the import.
No production code was involved; the production failure mode this exposes (a slot with no capability is
not a slot the wrist can hold) is intended and asserted by `S-2`.

## Footprint

`gateway.sh git-diff --stat`: `live_session_mirror_state.dart` 19, `watch_session_adoption_bridge.dart`
79, `watch_sync_request_handler.dart` 2, `live_mirroring_test.dart` 87, `watch_session_projection_test.dart`
702 (untracked new: `lib/core/sync_protocol/phone_entries.dart`). Nothing outside the plan's Predicted
Files except that new file, which the plan predicts.

## Phase Done Criteria — observed output

| Check | Command | Result |
|---|---|---|
| Flutter, whole suite | `gateway.sh test` | `01:50 +3935 ~1: All tests passed!` — 3935 passing, 1 skipped, **0 failures** (log `.work/gateway/test-20261006-011449-68216.log`) |
| Swift package | `gateway.sh swift-test` | `Executed 268 tests, with 0 failures (0 unexpected) in 1.036 (1.054) seconds`, exit 0 — unchanged, no Swift file touched (log `.work/gateway/swift-test-20261006-011647-73252.log`) |
| Lint | `gateway.sh lint` | `196 issues found. (ran in 3.0s)`, 0 errors; exit 1 on the pre-existing info notices, unchanged from the baseline. No issue mentions any of the five touched files (log `.work/gateway/lint-20261006-011651-73314.log`) |

`+3935` is Phase 1's `+3920` plus fifteen, all accounted for by observed tests: the **10** S-31…S-42
projection tests, the **2** mirror-level tests in `test/live_mirroring_test.dart`, the **2**
`S-31 both stores project the same entries` runs (Mock and Hive) and the **1** byte-equality test.

### Final re-run after the doc and plan edits

The run above predates the `docs/watch_session_sync.md` and plan edits, so the gates were re-run on the
final tree:

| Check | Result |
|---|---|
| `gateway.sh test test/docs_indexing_contract_test.dart` | `+9: All tests passed!` — no file over the 64 KiB ceiling, none in the warning band, every relative link resolves, every page reachable. The new Structure rows and the rewritten "What does not sync" prose pushed neither the doc nor the plan over the ceiling. |
| `gateway.sh test` | `01:36 +3935 ~1: All tests passed!` — same count, 0 failures (log `.work/gateway/test-20261006-011729-73574.log`), the final-tree run. Re-run once more after the last wording tweak in the doc's omission bullet: `01:37 +3935 ~1: All tests passed!` (log `.work/gateway/test-20261006-011944-78410.log`) |
| `gateway.sh test test/docs_indexing_contract_test.dart` (after that last tweak) | `+9: All tests passed!` |
| Standing invariant | `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` returns nothing |

Phase 2 item 6's regressions ran inside the whole suite: `test/watch_session_merge_test.dart` and
`test/watch_session_finish_test.dart` — both inject `projectSession` — pass on the final tree.

## What this phase did not change

- No model, schema, migration, repository or seed; no screen, widget or route; no new phone surface
  (D-42): the answer's `timers` is still `const <String, Object?>{}`.
- No Swift file: the wrist's treatment of a re-statement is Phase 3 (PR 3b). `swift-test` staying at
  268 / 0 is the observed proof that nothing on the watch side moved.
- No write on the projection path (D-41): `projectSession` only reads observations and inbox rows.
