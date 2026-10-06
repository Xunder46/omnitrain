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

---

# Evidence — watch-session-sync PR 3a, Phase 4 (docs, walkthrough, residue sweep)

Executor: @developer (Copilot CLI edition), 2026-10-06. Scope: the plan's Phase 4, items 1–6, per
`.work/watch-pr3/brief-dev-4.md` (governor's split: PR 3a = Phases 1, 2, 4; PR 3b = Phase 3 —
**not shipped**). Phase 3 is untouched; no sentence in the docs claims a re-statement.

Baselines inherited from Phase 2's final tree: `test` `+3935 ~1`, `swift-test` 268 / 0, `lint` 196 / 0.

## Docs written

| File | What changed |
|---|---|
| `docs/watch_session_sync.md` | Finished the "What does not sync" limits: added the two new limits (an edit to a set already on the wrist does not update the wrist's copy; a delete does not reach the wrist), named the phone's rest timer plainly, dropped the "yet" from the sets-only bullet, and repointed the manual-Sync bullet at `S-1 a wrist snapshot becomes the phone's in-progress session` instead of a bare file. The "what now syncs" half (the sets the phone logs ride its answer as `entries`) and the discarded-session limit were already in place from Phase 2. |
| `docs/state_management/watch_surface.md` | One statement added to the existing "What this phone asserts is its own session" paragraph: the projection carries the ladder and the `set` entries the phone logged, and the wrist's snapshot merge stores the ones it does not already hold (D-31, D-33, D-35). An edit inside the paragraph, not a new section; the file stays inside the 52 KB band. |
| `docs/watch-app-setup-and-qa.md` | One phone→wrist step added to the one-session walkthrough as step **(g)**, marked (owner), not yet run: two sets logged on the phone appear on the watch's logging screen in the phone's order at that Sync, and a set logged on the watch earlier is not doubled. No "edit one and Sync again" step is present. |

## Residue sweeps

| Sweep | Result |
|---|---|
| `grep -rn "entries': const <Object?>" lib/` | One hit initially — `lib/state/watch/live_session_mirror_debug_main.dart:143`, the debug harness's own seeded snapshot (not the projection). Changed to `'entries': <Object?>[],`, the shape `watch_sync_wiring.dart:55` already uses for the same kind of seed. Re-run: no matches. |
| `grep -rn "not carried to the wrist" docs/*.md docs/state_management` | No matches in any top-level `docs/*.md` file or under `docs/state_management/`; the phrase survives only inside `docs/plans/…`, which the sweep scope excludes. |
| `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` | No matches. |

## Phase Done Criteria — observed output

| Check | Command | Result |
|---|---|---|
| Flutter, whole suite | `gateway.sh test` | `01:33 +3935 ~1: All tests passed!` — 3935 passing, 1 skipped, **0 failures** (log `.work/gateway/test-20261006-013446-272.log`), the final-tree run after the plan and evidence edits; unchanged from the Phase 2 baseline. The earlier run on the same tree before those edits was `01:35 +3935 ~1` (log `.work/gateway/test-20261006-013154-95135.log`). |
| Swift package | `gateway.sh swift-test` | `Executed 268 tests, with 0 failures (0 unexpected) in 1.024 (1.042) seconds`, exit 0 (log `.work/gateway/swift-test-20261006-013337-99776.log`) — no Swift file touched. |
| Lint | `gateway.sh lint` | `196 issues found. (ran in 2.6s)`, 0 errors; exit 1 on the pre-existing info notices, unchanged from the baseline. No issue names a file this phase touched (log `.work/gateway/lint-20261006-013414-99948.log`). |
| Docs guard | `gateway.sh test test/docs_indexing_contract_test.dart` | `+9: All tests passed!` — no file over the 64 KiB ceiling, none in the warning band, every relative link resolves, every page reachable. Also included in the final-tree full-suite run above. |

## Not claimed

- The owner walkthrough (step **(g)**) has **not** been run: the governor could not tap through the
  simulator (no Screen Recording permission). It is documented for the owner; nothing here says it
  passed.
- The governor's watch-app build (`xcodebuild … "OmniTrain Watch App"`) is the governor's, not an
  agent's; this phase runs no `xcodebuild`.

---

# Evidence — watch-session-sync PR 3a, fix round 1 (the review's F1–F8)

Executor: @developer (Copilot CLI edition), 2026-10-06. One bounded pass per `.work/watch-pr3/brief-fix-1.md`.
Findings: `...pr3-plan.review.md`. Baselines inherited from the Phase 4 tree: `test` `+3935 ~1`,
`swift-test` 268 / 0, `lint` 196 / 0. **No Swift file was touched**, so `swift-test` staying at 268 / 0
is the observed proof that nothing on the watch side moved.

## What each finding became

| Finding | Change | Test that now pins it |
|---|---|---|
| **F1** (critical) — a set logged with a negative weight (band assist, the crown clamps to −200) projected `loadKg < 0`; `$defs.entry.loadKg` has `minimum: 0`, and a rejected entry rejects the **whole** snapshot | `PhoneEntries._entry` returns null when `weightKg < 0`, beside the existing `reps < 1`; the doc comment now states both omissions in the schema's own terms. `extraLoadKg` *is* declared on a `set` entry and would take −20, but its documented meaning is *a hold's* load, D-40 already says a set's added weight is not sent, and carrying it needs a Swift-side assertion this round cannot add. **Omitted** (plan A-14) | `S-42 a set the wire cannot carry is omitted` — extended with a `loadKg: -20.0` group beside the sendable one: exactly one entry, `loadKg` 60.0, the validator clean, `'-20'` absent from the encoded array, and the wrist holding that one set after the answer is applied |
| **F3** — `_wristRowStamps` skipped rows with `appliedAtMs == null`, but the importer writes a group's rows *before* it marks the inbox row applied, so a failure between the two left the group unclaimed and echoed the wrist's own set back to it under a phone id — a permanent duplicate, since staged rows are never deleted | The skip is dropped: a row claims on `originWatch` + `kindSet` + slot + `loggedAtMs`, staged or applied. The doc comment that justified the old rule was rewritten to say why a staged row must claim (plan A-15) | `S-34 a staged row claims its group before it is marked applied` — the fixture *is* the half-applied state, and the answer carries only the phone's own set |
| **F2** (guard test) | Added, with the invariant written down below | `S-34 a second watch row at one stamp claims the second group` |
| **F4** — the `set['skipped'] == true` clause is unreachable (a skipped set is written with `reps` 0) | Removed; `reps < 1` kept, with a comment saying so | the pre-existing skipped-set half of `S-42` — proven to still be doing the work, see MUTATION-F4 |
| **F5** — no test covered the `entryId` tie-break | Added | `S-31 two phone sets at one instant answer in 'entryId' order` |
| **F6** — S-43 was in the register and unanswered | Added | `S-43 the phone is unreachable at Sync` |
| **F7** — an edit that does **not** reach the wrist and a delete that is not sent had no test | Added, citing the wrist-side once-each rule rather than restating it | `D-38 an edit leaves the wrist's copy and a delete is not sent` |
| **F8** — `watch_surface.md` cited D-35 for a sentence PR 3a implements as D-31/D-33 | `(D-31, D-33, D-35)` → `(D-31, D-33)` | none — a decision citation; PR 3b must revisit the sentence (plan A-16) |

Docs: `docs/watch_session_sync.md` gained the band-assist limit (F1) and a test pointer on each of the
edit and delete bullets (F6/F7). `docs/documentation_standard.md` §4.2 asks for a test plus a pointer,
so no prose was rewritten and no duplicate explanation was added.

## F2 — the invariant, stated

`claimedBy` walks the watch-inbox stamps in order and, for each, takes the **first unclaimed** group
whose stamp equals it, scanning groups in ascending entry number: **one row claims exactly one group**,
and the lowest-numbered match wins. In the F2 fixture four sets sit in one slot — the phone's own at T1,
then three at T2: the two groups the staged watch rows wrote (numbers 1 and 2) and a third set the
*phone* logged in that same millisecond (number 3). The first row claims group 1, the second row claims
group 2 (it cannot take 1 again — claimed numbers are skipped), and group 3 is left unclaimed and so is
projected. What the wrist ends up holding, after it applies the answer and re-adds its own two rows, is
**four** rows — `entry-slot-bench-0`, `entry-slot-bench-3` and the two wrist ids — i.e. neither doubled
nor short, which is the whole point of the one-to-one claim. A second watch row at one stamp therefore
claims the second group *by construction*, and a row per group is what keeps a same-millisecond
coincidence a benign under-projection instead of a loss (D-34).

## RED by mutation — observed output

Each mutation was applied to `lib/`, the named test run alone, the output recorded, and the exact
original line restored immediately; the file went green again after each restore (final targeted run
`+24`, log `test-20261006-020532-23568.log`). No step ended with a mutation in place.

| Mutation | Test run | Observed |
|---|---|---|
| F1: the `if (weightKg < 0) return null;` guard commented out (the negative weight is sent as `loadKg: -20.0`) | `S-42 a set the wire cannot carry is omitted` | `Expected: ['entry-slot-bench-1']` / `Actual: ['entry-slot-bench-1', 'entry-slot-bench-2']` — `00:00 +0 -1 … Some tests failed.` (log `test-20261006-020447-23102.log`) |
| F3: the `if (row.appliedAtMs == null) continue;` skip restored in `_wristRowStamps` | `S-34 a staged row claims its group before it is marked applied` | `Expected: ['entry-slot-bench-0']` / `Actual: ['entry-slot-bench-0', 'entry-slot-bench-1']` — the wrist's own set sent back under a phone id, i.e. the doubling (`test-20261006-020458-23229.log`) |
| F5: the tie-break in `ordered()` replaced by `return 0;` | `S-31 two phone sets at one instant answer in 'entryId' order` | `Expected: ['entry-slot-bench-10', 'entry-slot-bench-9']` / `Actual: ['entry-slot-bench-9', 'entry-slot-bench-10']` — the store's own order, which is what the tie-break exists to override (`test-20261006-020507-23310.log`) |
| F4: the `reps < 1` guard weakened to `reps < 0` (with the `skipped` clause already deleted) | `S-42 a set the wire cannot carry is omitted` | `Expected: ['entry-slot-bench-1']` / `Actual: ['entry-slot-bench-0', 'entry-slot-bench-1']` — the skipped set reappears, so it is the **reps** rule, not the deleted `skipped` clause, that omits it (`test-20261006-020518-23432.log`) |

One earlier red is worth recording as self-inflicted and fixed in the test, not in the product: the
first run of the new `S-43` test asserted the wrist's held order as `['entry-slot-bench-0',
'entry-slot-bench-1', <wrist id>]`, but `'9f2c1d2e…'` sorts *before* `'entry-slot-bench-1'` byte-wise,
so the real order is `['entry-slot-bench-0', <wrist id>, 'entry-slot-bench-1']`. Corrected in the test
(exactly the protocol order F5 pins); no source line was changed for it (log
`test-20261006-020422-22848.log`, `+23 -1`).

## Final runs on the fix round's tree

| Check | Command | Result |
|---|---|---|
| The touched test file | `gateway.sh test test/watch_session_projection_test.dart` | `00:00 +24: All tests passed!` — 24 tests, 0 failures; 19 before this round (log `.work/gateway/test-20261006-020532-23568.log`) |
| Flutter, whole suite | `gateway.sh test` | `01:34 +3940 ~1: All tests passed!` — 3940 passing, 1 skipped, **0 failures**, against the Phase 4 baseline of `+3935 ~1`: the five net-new tests, and nothing regressed (log `test-20261006-020537-23643.log`) |
| Swift package | `gateway.sh swift-test` | `Executed 268 tests, with 0 failures (0 unexpected)`, exit 0 — unchanged from the baseline, no Swift file touched (log `swift-test-20261006-020726-28330.log`) |
| Lint | `gateway.sh lint` | `196 issues found. (ran in 2.9s)`, 0 errors, exit 1 on the pre-existing info notices — unchanged from the baseline, and no issue names a file this round touched (`phone_entries`, `watch_session_adoption_bridge`, `watch_session_projection_test` all absent from the log; log `lint-20261006-020731-28429.log`) |

## Files, and one that is not mine

The round touched `lib/core/sync_protocol/phone_entries.dart`,
`lib/state/watch/watch_session_adoption_bridge.dart`, `test/watch_session_projection_test.dart`,
`docs/watch_session_sync.md`, `docs/state_management/watch_surface.md`, the plan and this file — nothing
else.

`lib/state/watch/live_session_mirror_debug_main.dart` appears in the working tree diff with **exactly
one line** changed: `'entries': const <Object?>[],` → `'entries': <Object?>[],`, the `const` dropped so
the debug harness's seeded snapshot carries the shape `watch_sync_wiring.dart` uses. That is Phase 4's
residue-grep fix, already recorded above; **this fix round did not touch the file**, and no line of it
affects the projection.

# Evidence — watch-session-sync PR 3b, Phase 3 (the wrist takes a re-statement)

The brief: `.work/watch-pr3b/brief-dev-3a.md`, part A (Phase 3, items 1–5). Part B (PROTOCOL.md,
`docs/`, the plan's Progress row) is a later run and is untouched here.

## Baselines (from the brief, before this phase)

| Check | Baseline |
|---|---|
| `gateway.sh test` (whole suite) | `+3940 ~1` (3940 passing, 1 skipped) |
| `gateway.sh swift-test` | `Executed 268 tests, with 0 failures` |
| `gateway.sh lint` | `196 issues found`, 0 errors, exit 1 on the pre-existing info notices |

## Red first — Dart

Three tests were written on the projection register before any engine line changed
(`test/watch_session_projection_test.dart`): `S-35 a re-statement is append-only and doubles nothing`,
`S-41 the wrist's own set survives an answer with no phone entries`, and a fourth,
`S-35 a re-statement of a deleted id stays deleted`, added once the fold existed. The F7 test was also
flipped from "the wrist never re-states" to `S-35 an edit reaches the wrist and a delete is not sent`.

`gateway.sh test test/watch_session_projection_test.dart` → `+24 -2`:

| Test | Expected | Actual |
|---|---|---|
| `S-35 a re-statement is append-only and doubles nothing` (line 1003) | `[65.0, 62.5]` | `[60.0, 62.5]` |
| `S-35 an edit reaches the wrist and a delete is not sent` (line 1664) | `[65.0, 62.5]` | `[60.0, 62.5]` |

Noted honestly: `S-41` passed on the old code as well. Its subject is *survival and confirmation* of
the wrist's own set (which the old code never broke), not the re-statement; it guards the change that
follows. The append-only assertion inside the F7 test (`engine.observations` `[60.0, 62.5]`) is the
half that fails only under mutation 2.

Green after the engine edit: `+26: All tests passed!`.

## Red first — Swift

`watch/watchos/Tests/WatchSessionEngineTests/WatchPhoneEntriesTests.swift` (new, six tests: S-32, S-35
×2 — the re-statement and the deleted id — S-38, S-41, and the `phone_entries_merge.json` replay) was
written after the engine edit, so its red was captured the mutation way — mutation 3 below restores the
pre-edit guard verbatim and is byte-identical to the file's state before this phase.

## Mutations — three, all caught

| # | Mutation (original line recorded, restored exactly) | Red |
|---|---|---|
| 1 | Dart, `_storeSnapshotEntry`'s fold loses one payload key: `...entry,` → `... (Map<String, Object?>.from(entry)..remove('loadKg')),` | `test/watch_session_projection_test.dart` `+25 -2`: the same two S-35 tests, `Expected: [65.0, 62.5] Actual: [60.0, 62.5]` — a fold that drops the edited value re-states nothing |
| 2 | Dart, the fold's `return;` removed, so a held id is folded **and** appended: the row count doubles | `test/watch_session_projection_test.dart` `+22 -5`: `S-32` (940), `S-35` append-only (1003), `S-35` stays-deleted (1092), `S-35` edit reaches the wrist (1664), `S-43` (1759). The clearest: `S-32` `Actual: ['entry-slot-bench-0', 'entry-slot-bench-0', 'entry-slot-bench-0', 'entry-slot-bench-1', 'entry-slot-bench-1', 'entry-slot-bench-1']` |
| 3 | Swift, the re-statement removed (the held id short-circuits again): `storeSnapshotEntry`'s guard restored to `guard let entryId = …, !storedObservations.contains(…) else { return }` | `gateway.sh swift-test` `Executed 274 tests, with 1 failure`: `testS35AReStatementShowsThePhonesNewValueAndLeavesTheRow` at line 124, `("Optional(60.0)") is not equal to ("Optional(65.0)")` |

Each mutation was restored to the recorded original and re-run green before the next one; the final
tree was re-run in full (below). No mutation was left applied.

## One test defect, found by the first green run

The S-41 test asserted the wrist's own `loadKg` as `Double`; `setEvent` writes `80` as `Int`, so the
assertion read `nil` and failed (274 executed, 1 failure). Fixed in the test only
(`as? Int`); no source line was involved.

## The fixture change (brief pointer 6) — attempted, proven impossible, reverted

Pointer 6 asks for the wrist to "show 65" in `watch/sync_protocol/fixtures/reconciliation/phone_entries_merge.json`,
whose second answer re-carries `entry-slot-bench-0`. Empirically, that fixture cannot carry the
divergence D-35 creates:

| Fixture state | `test/live_mirroring_test.dart --plain-name phone_entries_merge` |
|---|---|
| snapshot 2's bench-0 `loadKg` 65, `expected` bench-0 60 | watch test red: `[0]['loadKg'] is <65> instead of <60>`; phone test green |
| snapshot 2's bench-0 `loadKg` 65, `expected` bench-0 65 | phone test red: `is <60> instead of <65>`; watch test green |
| reverted to HEAD | `+2: All tests passed!` |

One `expected` block is deep-compared to both stacks by three readers — `test/live_mirroring_test.dart`'s
phone test (`expect(phone.state, equals(expected))`) and watch test
(`expect([for (final e in engine.entries) e.payload], equals(expected['entries']))`),
`test/sync_protocol_fixtures_test.dart` S-004 (`expect(reconciled.convergedState(), equals(fixture['expected']))`),
and Swift `WatchLiveMirroringTests.testEveryReconciliationFixtureConverges`
(`engine.entries.map(\.payload)` vs `expected["entries"]`). The phone's reconciler keeps the **first**
value for an id it already holds (`SyncSessionReconciler._addEntry`'s
`if (_entries.containsKey(entryId)) return;`), which D-35 pairs with the wrist's re-statement. So
`expected` must be 60 or 65, never both, and any value reddens one of those unpredicted tests. Both
edits were reverted byte-identically: `gateway.sh git-status` lists four modified files and one new
test file, and the fixture is **not** among them. The divergence is pinned instead in
`test/watch_reconciliation_cross_stack_test.dart`, which compares no entry block to `expected`
(`S-35 a held id the phone edited is re-stated on the wrist, not resaved`: wrist bench-0 = 65, once;
phone bench-0 = 60). Governor decision needed — see `## Open questions`.

## Final runs on this phase's tree

| Check | Command | Result |
|---|---|---|
| Both touched Dart files | `gateway.sh test test/watch_session_projection_test.dart test/watch_reconciliation_cross_stack_test.dart` | `00:00 +44: All tests passed!` — 44 tests, 0 failures (log `.work/gateway/test-20261006-0948…`) |
| Flutter, whole suite | `gateway.sh test` | `01:39 +3944 ~1: All tests passed!` — 3944 passing, 1 skipped, **0 failures**, against the baseline `+3940 ~1`: the four net-new tests, nothing regressed (log `.work/gateway/test-20261006-094824-86810.log`) |
| Swift package | `gateway.sh swift-test` | `Executed 274 tests, with 0 failures (0 unexpected)`, exit 0 — against the baseline 268 / 0: the six net-new tests, nothing regressed (log `.work/gateway/swift-test-20261006-095008-91683.log`) |
| Lint | `gateway.sh lint` | `196 issues found. (ran in 3.0s)`, 0 errors, exit 1 on the pre-existing info notices — unchanged from the baseline, and no issue names a file this phase touched (log `.work/gateway/lint-20261006-095012-91735.log`) |
| Invariant | `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` | no matches |

## Footprint

`lib/watch/session/watch_session_engine.dart`, `test/watch_session_projection_test.dart`,
`test/watch_reconciliation_cross_stack_test.dart`,
`watch/watchos/Sources/WatchSessionEngine/WatchSessionEngine.swift`, and the new
`watch/watchos/Tests/WatchSessionEngineTests/WatchPhoneEntriesTests.swift` — nothing else. The fixture
is byte-identical to HEAD, `lib/core/sync_protocol/session_reconciler.dart` is untouched, and no
`docs/` file, PROTOCOL.md or plan Progress row was changed (part B).

`test/watch_session_engine_test.dart` (the brief's allowed home for the stays-deleted test) is
untouched: the test lives with S-31…S-43 in the projection file's own group, where the rest of the
register is.

## PR 3b fix 1 — the newest snapshot wins over an earlier correction

The brief: `.work/watch-pr3b/brief-fix-1.md` (D-35 only, tests only). Both mutations the governor ran
against Phase 3 survived because every scenario re-stated an id only **once**, so no test had an
earlier correction for the fold order to beat. One test per stack now edits a set twice.

| Stack | Test added | Passes unmutated |
|---|---|---|
| Dart | `test/watch_session_projection_test.dart` `S-35 a second edit wins over the first` — edit 60→65, Sync + apply; 65→70, Sync + apply; `entries` loadKg `70.0`, `observations` still `60.0`, one row | `+1` (`flutter test --plain-name …` → `All tests passed!`) |
| Swift | `watch/watchos/Tests/WatchSessionEngineTests/WatchPhoneEntriesTests.swift` `testASecondEditWinsOverTheFirst` — snapshots 60, 65, 70; `entries` loadKg 70, stored row loadKg 60, one row | `Executed 1 test, with 0 failures` |

Each surviving mutation was then re-applied to show the new test RED, and restored byte-for-byte
(`git-diff --stat` keeps `watch_session_engine.dart` at 15 and `WatchSessionEngine.swift` at 16 lines,
the same counts Phase 3 left):

| # | Mutation (recorded, restored verbatim) | Red |
|---|---|---|
| 1 | Dart `_storeSnapshotEntry`'s fold order swapped to `{...entry, ...?_entryCorrections[entryId]}` (the old value beats the re-stated one) | `flutter test --plain-name "S-35 a second edit wins over the first"` → `+0 -1`: `Expected: [70.0, 62.5]` / `Actual: [65.0, 62.5]`, `Which: at location [0] is <65.0> instead of <70.0>`, `test/watch_session_projection_test.dart 1761` |
| 2 | Swift `storeSnapshotEntry`'s merge closure `{ held, _ in held }` instead of `{ _, corrected in corrected }` | `swift test --filter WatchPhoneEntriesTests.testASecondEditWinsOverTheFirst` → `Executed 1 test, with 1 failure`: `("Optional(65.0)") is not equal to ("Optional(70.0)")`, `WatchPhoneEntriesTests.swift:159` |

Final runs on the restored tree:

| Check | Command | Result |
|---|---|---|
| Flutter, whole suite | `gateway.sh test` | `01:36 +3945 ~1: All tests passed!` — 3945 passing, 1 skipped, **0 failures**, against the baseline `+3944 ~1`: the one net-new test, nothing regressed (log `.work/gateway/test-20261006-100719-5673.log`) |
| Swift package | `gateway.sh swift-test` | `Executed 275 tests, with 0 failures (0 unexpected)`, exit 0 — against the baseline 274 / 0: the one net-new test, nothing regressed (log `.work/gateway/swift-test-20261006-100719-5674.log`) |
| Lint | `gateway.sh lint` | `196 issues found. (ran in 3.0s)`, 0 errors, exit 1 on the pre-existing info notices — unchanged from the baseline, and no issue names `watch_session_projection_test.dart` (log `.work/gateway/lint-20261006-100912-10830.log`) |
| Invariant | `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` | no matches |

Footprint: the two test files only; no engine line changed.

## PR 3b, part B — the contract sentence, docs, walkthrough, plan bookkeeping

The brief: `.work/watch-pr3b/brief-dev-3b.md`. Docs only: no code, test or fixture line changed.
Files: `watch/sync_protocol/PROTOCOL.md` (the re-statement bullet under "Idempotency and
reconciliation" and a new `1 (amended) | 2026-10-06` version-history row),
`docs/state_management/watch_surface.md` (the phone's own-session paragraph now names D-35),
`docs/watch_session_sync.md` (a new D-35 decision paragraph; the "an edit does not update the wrist's
copy" bullet removed; the delete bullet's citation repointed at the renamed test),
`docs/watch-app-setup-and-qa.md` (step (g) extended with the edit and the delete), this plan's
Progress/Assumption Log.

Every behaviour sentence added cites a test that asserts it: the wrist-side
`WatchPhoneEntriesTests.testS35AReStatementShowsThePhonesNewValueAndLeavesTheRow` /
`testASecondEditWinsOverTheFirst`, and the Dart `S-35 a re-statement is append-only and doubles nothing`
/ `S-35 a second edit wins over the first` / `S-35 an edit reaches the wrist and a delete is not sent`
and `S-35 a held id the phone edited is re-stated on the wrist, not resaved`.

### Residue sweeps (observed)

| Sweep | Command | Result |
|---|---|---|
| The removed claim and the old test name | `grep -rn "does not update the wrist's copy\|an edit leaves the wrist" docs/ watch/ lib/ test/` | **no hits outside `docs/plans/` history text** — the only matches are rows of this evidence file (this sweep's own command, a Phase 4 record and the F7 review table); `docs/watch_session_sync.md`, `watch/`, `lib/` and `test/` are clean |
| The standing layer invariant | `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` | no matches |
| The docs size/indexing guard | `gateway.sh test test/docs_indexing_contract_test.dart` | `00:00 +9: All tests passed!` — 9 passing, 0 failures; every doc inside the band (`watch_surface.md` ~41 KB, well under 52 KB) |
| Flutter, whole suite | `gateway.sh test` | `01:40 +3945 ~1: All tests passed!` — 3945 passing, 1 skipped, **0 failures**, unchanged from part A's `+3945 ~1`; no Dart source, test or fixture line changed (log `.work/gateway/test-20261006-102023-16098.log`) |
| Swift package | `gateway.sh swift-test` | `Executed 275 tests, with 0 failures (0 unexpected)`, exit 0 — the tree part A left, re-run to observe the plan's claim (log `.work/gateway/swift-test-20261006-102542-21753.log`) |
| Lint | `gateway.sh lint` | `196 issues found. (ran in 2.5s)`, 0 errors, exit 1 on the pre-existing info notices — the plan's baseline, and no issue names a file part B touched (log `.work/gateway/lint-20261006-101913-15669.log`) |

### Footprint (part B)

`watch/sync_protocol/PROTOCOL.md` (+15), `docs/state_management/watch_surface.md` (+15/-3),
`docs/watch_session_sync.md` (+24/-6), `docs/watch-app-setup-and-qa.md` (+5/-1), this plan and this
evidence file. No code, test, fixture or seed file.

## PR 3b fix 2 — G1 (doc wording) and G4 (plan bookkeeping), docs only

The brief: `.work/watch-pr3b/brief-fix-2.md`. No code and no test changed.

Review G1: `watch/sync_protocol/PROTOCOL.md`'s idempotency bullet, its `2026-10-06` version row and
`docs/watch_session_sync.md`'s D-35 paragraph claimed the watch "MUST NOT / never re-states an entry
the phone holds from the watch's own snapshot" — a watch-side rule no engine enforces and no test
asserts. The sentences now state only the mechanism: the watch re-states, for an id it holds, the
values the phone's snapshot carries; a phone receiving a watch snapshot keeps the values it holds
(the watch does not edit existing records, authority rule 1), so its model does not re-state; and the
answer carries the watch's own values for the watch's own entries, so a re-statement of one is a
no-op. The receiver-side `MUST` the engines do keep — a held `entryId` is re-stated from the payload,
never stored as a second row and never a rewritten record — is unchanged. The citations name only
tests that assert their sentence: the wrist-side Swift pair, the phone half of
`test/watch_reconciliation_cross_stack_test.dart` (`S-35 a held id the phone edited is re-stated on
the wrist, not resaved`), the two Dart projection tests and the projection edit test.

Review G4: the plan's `Next handoff` line now names the owner walkthroughs (code review 2: APPROVE;
the G2/G3 follow-ups belong to the durable-store (PR 4) plan), the status block's stale "the review
of PR 3b" is dropped, and `## Open questions` no longer reuses 8 and 9 — those items are 12 and 13,
with 13 (the one-PR/no-split item) marked superseded by the governor's Split note. The Impact table
was left untouched.

G1 proof — `grep -n` for `MUST NOT re-state` or `never re-states` across `watch/sync_protocol/PROTOCOL.md`
and `docs/watch_session_sync.md`: no matches.

| Check | Command | Result |
|---|---|---|
| Docs guard | `gateway.sh test test/docs_indexing_contract_test.dart` | `00:00 +9: All tests passed!` — 9 passing, 0 failures |
| Flutter, whole suite | `gateway.sh test` | `01:41 +3945 ~1: All tests passed!` — 3945 passing, 1 skipped, **0 failures**, unchanged from fix 1's `+3945 ~1` (log `.work/gateway/test-20261006-104119-38631.log`) |
| Lint | `gateway.sh lint` | `196 issues found. (ran in 3.0s)`, 0 errors, exit 1 on the pre-existing info notices — the baseline, and no issue names a file this pass touched (log `.work/gateway/lint-20261006-104316-43345.log`) |
| Invariant | `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` | no matches |

Footprint: `watch/sync_protocol/PROTOCOL.md`, `docs/watch_session_sync.md`, this plan and this evidence
file. No code, test, fixture or seed file. `swift-test` was not re-run: no Swift file changed.

