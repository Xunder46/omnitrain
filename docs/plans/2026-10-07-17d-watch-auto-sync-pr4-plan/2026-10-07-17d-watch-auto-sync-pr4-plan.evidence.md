# Evidence — watch auto-sync PR 4 (17d): the phone's other entry kinds reach the wrist

Plan: `2026-10-07-17d-watch-auto-sync-pr4-plan.md`
Review: `2026-10-07-17d-watch-auto-sync-pr4-plan.review.md`
Predecessor: `docs/plans/2026-10-06-17c-watch-auto-sync-pr3-plan/` (PR 3 — deletions)

Executors append here. The plan keeps one-line Progress entries; measured output lives here.

## How to read this file

- **Paste real counts.** A hung, timed-out (gateway exit 124) or killed command is a failure, not an
  inconclusive result.
- **"Compiles" is not "passes".** `gateway.sh lint` green is not a test run.
- **A new assertion must be shown red without the fix.**

## Baselines

Base branch: `develop`. Rebase point (commit): `3720c6c` (the `prove-red` base). Recorded by: Phase 1
executor (developer, Copilot CLI), 2026-10-07.

| Check | Command | Result | Date |
|---|---|---|---|
| lint | `.github/copilot/scripts/macos/gateway.sh lint` | 196 info / 0 error (exit 1 = the repo's pre-existing notices) — `.work/gateway/lint-20261007-132312-98343.log` | 2026-10-07 |
| test | `.github/copilot/scripts/macos/gateway.sh test` | 4052 passed / 0 failed / 1 skipped after Phase 1 — `.work/gateway/test-20261007-132337-98624.log:4686` | 2026-10-07 |
| swift | `.github/copilot/scripts/macos/gateway.sh swift-test` | **not run** — this phase changes no `.swift` file (D-134/D-138) | — |
| invariant | `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` | nothing | 2026-10-07 |

The plan's quoted baselines disagree (brief ≈4030/~1 skipped, 17b evidence 4020, plan 196/0 analyze and
325/0 swift). No pre-change full-suite log exists for this PR, so the pasted 4052 is the observed
endpoint and the pre-change total is 4048 by subtraction — Phase 1 adds exactly four tests, all in
`test/watch_session_projection_test.dart`, whose own baseline is recorded there (32 passed before them,
36 after).

Start this PR **after** 17c has merged: the base here must include 17c's `heldWristEntryIds` and its
durable lens, otherwise Phase 2 has nothing to extend.

## Facts recorded before implementing (Phase 1, item 1)

| Fact | Where read | What it says | Rule this pins |
|---|---|---|---|
| The stamp the importer writes for an imported non-set entry | `lib/core/services/watch_session_importer.dart:926` (timed) and `:970` (round); sensor summaries `:941`/`:984` | `createdAtMs: entry.loggedAtMs` — the record carries the wrist row's own stamp | D-133: **the first rule (stamp match)**; the window fallback was not needed |
| Whether a hold-effort window is derivable from the observation row alone | `lib/state/workout/session_core_entry.dart:134-156` and `lib/core/services/watch_session_importer.dart:99`, `:887-893` | Both writers of a hold write a `TimedInstance` (`drill` → `addTimedEntry`; `kindHold` → `BlockTypes.drill` → `_createTimedInstance`), so the window is always on the instance | D-130: the reconstructed-window branch **has no producer** → not implemented (Assumption 1) |
| The wrist's own spelling for `timed`/`hold`/`round` | `watch/watchos/Sources/WatchSessionEngine/WatchLoggingState.swift:587` (`metricPayload`, a hold's `extraLoadKg`) and `:628` (`windowPayload(coversDistance:)`) | A window is `startedAt` / `endedAt` with `loggedAt` = the end and `distanceMeters` only on a distance-covering entry; a hold adds `extraLoadKg`; a round adds `roundNumber` | D-130: the phone writes those names, that sign and those units (cited in the projections' doc comments) |

## Phase 1 — the phone projects its other kinds (@developer)

| # | Item | Status | Evidence |
|---|---|---|---|
| 1 | the two recorded facts | done | the table above; fact (a) holds (stamp rule), fact (b) has no producer (Assumption 1) |
| 2 | `PhoneEntries.projectTimed` / `projectHold` / `projectRound` + `_window` | done | `lib/core/sync_protocol/phone_entries.dart:102` / `:206` / `:147`, `_windowedEntry` `:345`, `_window` `:381`, `_distanceFields` `:395`, `_extraLoadFields` `:410`, `resolveRecordClaims` `:300`, kinds `:40-52`; `project` `:62` keeps its set-only contract |
| 3 | agreement with `WatchLoggingState.windowPayload` | done | field names/sign/units cited in the projections' doc comments (`:587`, `:628`); S-140/S-141 assert the field set both validators accept |
| 4 | `WatchInboxEntry.kindTimed/kindHold/kindRound` | done — **no change needed** | already present at `lib/data/models/models.dart:2618-2621`; nothing renamed, nothing migrated |
| 5 | `_entriesFor` per-kind dispatch | done | `lib/state/watch/watch_session_adoption_bridge.dart:245` (doc) / `:258` (the switch), set `:266`, timed `:274`, hold `:282`, round `:290`, `_stampsOf` `:300`, `_wireKind` `:317` (`drill` → `hold`), `_declaredKinds` `:60`, `_kindPrecedence` `:69` |
| 6 | `_wristRowStamps` per-kind claim | done | `_wristRowsBySlot` `:379` reads all four kinds; `heldWristEntryIds` `:336` stays set-scoped with the Phase-2 boundary documented at `:328`/`:342`; S-142, `test/watch_session_import_test.dart` green |
| 7 | S-140, S-141, S-142, S-143 | done | `test/watch_session_projection_test.dart:2225+` (helpers `:324`, `:390`); red first (32 passed / 4 failed), then 36 passed; `prove-red` RED AT `3720c6c` (base-commit re-run of the final file: 31 passed / 5 failed — the four scenarios plus the updated S-2 guard) |
| 8 | Progress + evidence | done | this file; the plan's Progress row + Assumption Log updated, phase **Complete** |

Done Criteria run:

```
.github/copilot/scripts/macos/gateway.sh lint                                        → 196 issues, 0 errors (baseline)
.github/copilot/scripts/macos/gateway.sh test test/watch_session_projection_test.dart \  → 138 passed, 0 failed
  test/watch_session_adoption_bridge_test.dart test/sync_protocol_fixtures_test.dart /
.github/copilot/scripts/macos/gateway.sh test test/watch_session_import_test.dart \    → 68 passed, 0 failed
  test/phone_manage_bridge_test.dart                                                /
.github/copilot/scripts/macos/gateway.sh test test/watch_session_projection_test.dart  → 36 passed, 0 failed (final)
.github/copilot/scripts/macos/gateway.sh test                                           → +4052 ~1, All tests passed! (exit 0)
.github/copilot/scripts/macos/gateway.sh test test/watch_session_projection_test.dart \
  --plain-name "projects the kinds"                                                    → +4, All tests passed! (S-140…S-143 by name, after the last edit)
```

Red→green table:

| Scenario | Red command / revert | Red output | Green output |
|---|---|---|---|
| S-140 | `prove-red 3720c6c test test/watch_session_projection_test.dart` (the `_entriesFor` dispatch is the change) | `Expected: ['entry-slot-plank-1'] Actual: []` — "D-131 the phone's timed record rides the answer, named by its slot and the record's own index" | 1 entry, `kind` `timed`, window + `loggedAt` = end, no `distanceMeters` (0, D-132); validators accept; the wrist engine holds it |
| S-141 | the same run | `Expected: Set:['entry-slot-burpee-0', 'entry-slot-burpee-1', 'entry-slot-hold-0'] Actual: Set:[]` | two `round` entries (`roundNumber` 1/2, `pausedMs` 5000 on the first only) + one `hold` with `extraLoadKg` 12.0 |
| S-142 | the same run | `Expected: ['entry-slot-plank-1', 'entry-slot-burpee-1'] Actual: []` | exactly those two ids once each; kinds `{timed, round}` |
| S-143 | the same run | `Expected: ['entry-slot-plank-2'] Actual: []` — "D-132 an instance that never started and a window of no length are omitted, never placeheld" | exactly the one good entry; `startedAt != endedAt`; `distanceMeters` 250.0 with its source |

The third full-suite run after the last test-file edit (the S-142 list assertion) is
`.work/gateway/test-20261007-132721-4736.log:4688` — `+4052 ~1: All tests passed!`, exit 0 (two earlier
runs, `.work/gateway/test-20261007-132027-93127.log:4686` and
`.work/gateway/test-20261007-132337-98624.log:4686`, printed the same counts).

`prove-red` verdict:

```
gateway: prove-red: 'test' on 3720c6c with your versions of: test/watch_session_projection_test.dart
gateway: prove-red: RED AT 3720c6c (exit 1). It proves the guard only if an assertion fails for the
reason the test guards; a compile or load error means the test could not run there …
```

The verbatim failures are in `.work/gateway/test-20261007-132710-4602.log` (lines 92–93, 129–164; the
base file ends `+31 -5: Some tests failed.` — the four scenarios at `:2280`, `:2349`, `:2472`, `:2554`
plus the updated S-2 guard at `:657`).

The run also reddens the pre-existing S-2 test (`:657`) — the expectation that had to change (below).

Mutation proofs (each: original line recorded → mutated → the named test fails for its own reason →
restore the exact original → re-run green, 36 passed):

| # | Original line | Mutant | Red, verbatim |
|---|---|---|---|
| M-1 | `phone_entries.dart:382` `_window`: `finishedAtMs <= startedAtMs` | `<` | S-143 `Actual: ['entry-slot-plank-1', 'entry-slot-plank-2']` — a zero-length window rode the wire |
| M-2 | `phone_entries.dart:397` `_distanceFields`: `metres <= 0` | `metres < 0` | S-140 `Expected: false Actual: <true>` — "D-132 a distance of 0 is omitted, never sent as 0" |
| M-3 | `phone_entries.dart:157` `projectRound`: `roundIndex + 1` | `roundIndex + 2` | S-141 `Expected: <1> Actual: <2>` — the wire's round number is 1-based |

Assumptions this phase leaves for the reviewer (the plan's Assumption Log):

1. **D-130's "a hold with no instance" branch is not implemented** — fact (b): both writers create a
   `TimedInstance`, so it would be dead code no test reaches, and I-5 forbids inventing a window.
2. **`extraLoadKg` has no exclusive minimum** in `envelope.schema.json` (a plain number), so the
   projection's only omission guards are `_window`'s and `_distanceFields`'s; a load of exactly 0 is
   omitted and nothing is clamped.
3. **The brief's "1-based" entry-id wording**: D-131's id carries the record's stored `entryIndex`
   (0-based in general — `entry-slot-bench-0` in the pre-existing S-31 tests; S-140's plank carries
   index 1). The 1-based value on the wire is `roundNumber`.
4. **Positional pairing**: `EntryRows.distanceEntries`/`companions` pair the k-th metric row with the
   k-th entry and `LoggedEntryRows.timedObservations` writes a row for every index — S-143's fixture was
   rebuilt to that shape after a sparse one hid the guards.
5. **The pre-existing S-2 expectation had to change** even though the plan's impact table predicted no
   existing assertion would: the `amrap` squat slot now resolves to `set` by capability precedence
   (D-130) where the base kept it out, and the `timed` slot's entry is omitted for lack of a window
   (D-132). `['entry-$bench-0']` + two `.single` reads became `['entry-$bench-0', 'entry-$squat-0']` +
   `.first`; the base-commit `prove-red` run shows the **updated** expectation red there for exactly
   that documented reason, so it guards the new behaviour. Reviewer: ratify or revert.

Residue sweep, Phase 1 view (Phase 3 owns the final one):

```
grep -rn "BlockTypes.set" lib/state/watch lib/core/sync_protocol
  lib/state/watch/watch_session_adoption_bridge.dart:61   _declaredKinds   (the set kind is one of four — not a set-only assumption)
  lib/state/watch/watch_session_adoption_bridge.dart:797  _effortKind fallback (a slot with no capability defaults to set)
grep -rn "kindSet" lib/state/watch
  lib/state/watch/watch_session_inbox.dart:171            (sets are still the only auto-deleted kind — Phase 2)
  lib/state/watch/watch_session_adoption_bridge.dart:332/:342  heldWristEntryIds, set-scoped with the Phase-2 boundary documented at :328
```

Diff footprint (`git-diff --stat`, code + tests only):
`phone_entries.dart` 311 changed lines, `watch_session_adoption_bridge.dart` 149,
`test/watch_session_projection_test.dart` 454 — 852 insertions, 62 deletions, all additive (new helpers,
projections, doc comments); no reformatting of untouched lines; `models.dart` untouched. No file outside
the plan's Predicted Files changed (the plan + its evidence file are the other two modified paths:
993 insertions / 94 deletions including the doc edits).

## Phase 2 — the wrist shows them; 17c's deletion covers them (@developer)

| # | Item | Status | Evidence |
|---|---|---|---|
| 1 | S-145 Dart twin | done | `test/watch_session_engine_test.dart` group `S-145 a phone entry of any kind is the wrist's own`, 2 tests: **2 passed / 0 failed**. Test 1 (timed + hold + round applied once each, with the phone's fields) mutation-proven below; test 2 asserts `loggedAt` order for a frame that carried round/hold/timed. |
| 2 | S-145 Swift | done, **no Swift production change** (D-134) | `watch/watchos/Tests/WatchSessionEngineTests/WatchPhoneEntriesTests.swift`: `testS145APhoneEntryOfEveryKindIsTheWristsOwn` + private `value`/`slot`/`phoneEntriesSnapshot` helpers. `swift-test --filter WatchPhoneEntriesTests` → **8 tests / 0 failures**; mutation → 8 failures; source restored byte-exact (absent from `git-status`). |
| 3 | `heldWristEntryIds` filter dropped + S-144 | done | `_claimKinds`, `_rowsOfKind`/`_stampsOf` split; `heldWristEntryIds` claims sets via `resolveClaims` and `timed`/`hold`/`round` via `resolveRecordClaims` over `getTimedInstances`/`getRoundInstances`. S-144 group in `test/watch_session_auto_push_test.dart`: **1 passed / 0 failed**; prove-red **RED AT `d4e64ee`** (exit 1). |
| 4 | regression suites | done | `test/watch_reconciliation_cross_stack_test.dart` + `test/watch_session_import_test.dart` + `test/watch_session_edit_restore_late_entry_test.dart`: **92 passed / 0 failed**. |
| 5 | Progress | done | plan `## Progress` Phase 2 row + Assumption Log 6–8. The two Phase-1 pins of brief item 4 (D-133, D-132) live in `test/watch_session_projection_test.dart` — a Phase 1 file, flagged as such. |

Done Criteria run:

```
.github/copilot/scripts/macos/gateway.sh test test/watch_session_auto_push_test.dart test/watch_session_engine_test.dart test/watch_session_projection_test.dart
→ 00:00 +114: All tests passed!

.github/copilot/scripts/macos/gateway.sh test test/watch_reconciliation_cross_stack_test.dart test/watch_session_import_test.dart test/watch_session_edit_restore_late_entry_test.dart
→ 00:03 +92: All tests passed!

.github/copilot/scripts/macos/gateway.sh swift-test --filter WatchPhoneEntriesTests
→ 8 tests, 0 failures
```

Red→green table:

| Guard | Red proof (mutation / prove-red) | Red output | Green output |
|---|---|---|---|
| S-144 | `prove-red d4e64ee test test/watch_session_auto_push_test.dart --plain-name "S-144"` | `RED AT d4e64ee (exit 1)`: expected 5 frames, actual 2 | `+1: All tests passed!` |
| S-145 Dart twin | mutation: `if (entry['kind'] != 'set') continue;` in `watch_session_engine.dart`'s `_applySnapshot` store loop | test 1 red — the `hold`/`round`/`timed` rows never reached the store | restored byte-exact, `+2: All tests passed!` |
| S-145 Swift | mutation: `if entry["kind"] as? String != "set" { continue }` in `WatchSessionEngine.applySnapshot`'s store loop (~:527) | **8 failures** | restored byte-exact, 8 tests / 0 failures |
| pin D-133 (`_rowsOfKind` ignores the kind) | mutation: `if (row.kind == kind) row,` → `row,` | `Expected: Set:['entry-slot-burpee-0'] Actual: Set:[]` — the timed row's stamp swallowed the round record's | restored byte-exact, `+2: All tests passed!` |
| pin D-132 (`_extraLoadFields` zero guard) | mutation: `if (weightKg == 0) return const {};` removed | `Expected: false Actual: <true>` — the field the phone must omit was sent | restored byte-exact, `+2: All tests passed!` |

Both pin mutations were reverted and `git-status` shows neither
`lib/state/watch/watch_session_adoption_bridge.dart`'s guard nor
`lib/core/sync_protocol/phone_entries.dart` carrying residue (`phone_entries.dart` is absent from
`git-status` entirely); no mutation was left applied.

Final counts for this phase (whole repo, after the phase):

| Check | Baseline | After Phase 2 | Delta explained |
|---|---|---|---|
| `test` (full) | `+4052 ~1` | **`+4057 ~1: All tests passed!`** | +5: S-145 ×2, S-144 ×1, pins D-133/D-132 ×2 |
| `swift-test` (full) | 334 tests / 0 failures | **335 tests / 0 failures** | +1: `testS145APhoneEntryOfEveryKindIsTheWristsOwn` |
| `lint` | 196 issues / 0 errors | **196 issues / 0 errors** (exit 1 = the pre-existing info notices) | none; no issue names a file this phase touched |
| invariant `import .*hive_workout_repository` in `lib/{state,features,widgets,core}` | none | **none** | — |

Diff footprint (`git-diff --stat`, this phase's files only): `watch_session_adoption_bridge.dart` 103
changed lines (32 deletions — the set-only body of `heldWristEntryIds`), `watch_session_engine_test.dart`
234 changed lines / 0 deletions, `watch_session_auto_push_test.dart` 208 changed lines / 3 deletions (the
`_slot` helper's parameter list and its hard-coded `'effortKind': 'set'`), `watch_session_projection_test.dart`
108 changed lines / 0 deletions, `WatchPhoneEntriesTests.swift` 166 changed lines (the header comment's
kind list extended, plus the new test and helpers). No Swift production file, no
`lib/core/sync_protocol/phone_entries.dart`, no `lib/watch/session/watch_session_engine.dart` — every
mutation target is byte-exactly restored.

Docs: no Phase 2 update required. The sentence this phase narrows, `docs/watch_session_sync.md:328`
("Only sets are carried"), was already false after Phase 1 and is Phase 3 item 1's explicit target; the
deletion bullet at `:348` stays true but is now narrower than the behaviour, and Phase 3 item 1's pass
carries the one-line correction (Assumption Log 9).

## Phase 3 — docs, contract sentence, residue sweep (@developer)

### Item 0 — the `heldWristEntryIds` defect (found by the governor in Phase 2)

Defect: for `timed`, `hold` and `round`, `heldWristEntryIds`
(`lib/state/watch/watch_session_adoption_bridge.dart`) took
`PhoneEntries.resolveRecordClaims(...)`'s **record** positions and applied them to `listed`, the list
of **wrist rows** (one per stamp). A phone-logged record before the wrist's own shifted every later
position by one, so the id read was the wrong row's or — when the wrist had fewer rows than the phone
had records — `listed[index]` threw `RangeError`. The push pass calls this on every flush (including
the S-123 seeding pass) and `AutoPush._pushOnce` catches `Exception` only, so the error escaped
`flush()` and no deletion was announced again at all.

Fix (one claim rule, shared by the projection and the ledger — 17c review F4): `resolveRecordClaims`
now returns `({Set<int> records, Set<int> stamps})`, mirroring `resolveClaims` for sets; the three
projections read `.records`, `heldWristEntryIds` reads `.stamps`.

Tests (written first): `test/watch_session_adoption_bridge_test.dart`
(`S-144 the ledger holds the row whose stamp claimed a record, not the record's position in the
phone's list` — three slots: a timed slot with the phone's record at index 0 and the wrist's at
index 1, a round slot of the same shape, and the counter-case with the wrist's record at index 0 and
the phone's at index 1) and `test/watch_session_auto_push_test.dart`
(`S-144 a phone-logged record before the wrist's own does not hide the deletion of the wrist's row` —
a timed slot and a round slot, the phone logging first and the wrist second, both deletions announced,
`failures` empty).

prove-red, both new tests against the code without the change:

```
$ .github/copilot/scripts/macos/gateway.sh prove-red c3e8f22 test test/watch_session_adoption_bridge_test.dart test/watch_session_auto_push_test.dart
RangeError (length): Invalid value: Only valid value is 0: 1
  watch_session_adoption_bridge.dart 395:26 — WatchSessionAdoptionBridge.heldWristEntryIds
RED AT c3e8f22 (exit 1) — 2 tests failed
```

That is the guarded defect itself, not a compile or setup error: the exception is thrown exactly where
a record index is used as a row index, in both new tests.

Green with the change:

```
$ .github/copilot/scripts/macos/gateway.sh test test/watch_session_adoption_bridge_test.dart test/watch_session_auto_push_test.dart
+55: All tests passed!
```

Mutation proof (the fix's two `resolveRecordClaims` reads, one at a time, each run against the same
two test files, each reverted byte-exactly):

| Mutation | Verdict |
|---|---|
| `heldWristEntryIds`'s `timed`/`hold` read back to `.records` | **RED** — `+53 -2: Some tests failed.`, both new tests fail with `RangeError (length): Invalid value: Only valid value is 0: 1` at `watch_session_adoption_bridge.dart 399:26 WatchSessionAdoptionBridge.heldWristEntryIds` |
| `heldWristEntryIds`'s `round` read back to `.records` | **RED** — `+53 -2: Some tests failed.`, the same throw at the same line |
| both restored | **GREEN** — `+55: All tests passed!`; `git-diff --stat` shows the file back at its 10 changed lines |

The throw is the defect itself (a record index used as a row index), and each new test names the
scenario it guards in its test name, so a regression fails by name.

| # | Item | Status | Evidence |
|---|---|---|---|
| 0 | the `heldWristEntryIds` defect, red-first | **done** | prove-red `RED AT c3e8f22` (RangeError at `:395`), `+55` green, mutation proof above |
| 1 | `docs/watch_session_sync.md` four kinds + the two omissions | **done** | "What does not sync": the four-kinds bullet (S-140/S-141/S-142, S-145), the claim-rule bullet (D-133 + the S-144 ledger test), the omission bullet (S-143, D-132), the D-135/D-136 bullet, and the deletion bullet widened from "a set removed on the phone" to any kind (S-120, S-144 ×2, S-35). `git-diff --stat`: 39 changed lines, all inside that section. Size: see the note below |
| 2 | PROTOCOL dated sentence | **done** | one row appended to the amendment table, `2026-10-07`, no schema/validator/version change; it names S-140/S-141/S-142/S-143/D-132/D-133, S-145, S-144 ×2 and the ledger test — every name grep-verified in its file (`watch/sync_protocol/PROTOCOL.md`, 1 changed line) |
| 3 | modality docs claim check | **done — no claim existed, nothing changed** | grep `watch\|wrist` in `docs/modality_tracking.md` + `docs/modality_based_exercise_ui.md`: 13 hits, none says what the wrist receives (`modality_tracking.md:105–108` is start paths, `modality_based_exercise_ui.md:338–342` is the discard/ late-entry rule). Same check in `docs/watch-app-setup-and-qa.md` (`timed\|hold\|round\|non-set\|only sets`): its one kind-related sentence (`:175`, "a set, a timed hold, a round or a drill") is about the wrist's own logging surface and stays true |
| 4 | residue sweep | **done** | both greps pasted below; every hit classified |
| 5 | full suite + swift | **done** | final table below; no Swift production or test file changed in Phase 3, so `swift-test` was not re-run (it was 335 / 0 after Phase 2) |
| 6 | Progress + final evidence table | **done** | plan Progress row and the final table below |

Size of `docs/watch_session_sync.md`: `wc -c` is denied by policy in this run and no gateway check
reports a file's byte size, so the number the brief quotes (~32.9 KB) stands as the base and the file's
growth is bounded by its 39 changed lines; the ceiling that matters is enforced by
`test/docs_indexing_contract_test.dart` (64 KiB, and the 52 KB band of `documentation_standard.md`),
which is green in the final run below. `docs/state_management/watch_surface.md` was **not touched**
(the brief's ~50,144 B against the 51,200 B ceiling).

Residue sweep output (both greps verbatim; run with the repo's file tools since the shell is the
gateway only):

```
BlockTypes.set in lib/state/watch, lib/core/sync_protocol
  watch_session_adoption_bridge.dart:61:  BlockTypes.set,          ← inside `_declaredKinds` (set, timed, round, drill)
  watch_session_adoption_bridge.dart:844: ?? BlockTypes.set;       ← the fallback kind when no modality config resolves

kindSet in lib/state/watch, lib/data/models
  models.dart:2618:  static const String kindSet = 'set';          ← the constant's definition
  models.dart:2630:  kindSet,                                      ← inside the all-kinds list (set, timed, hold, round)
  watch_session_inbox.dart:171: WatchInboxEntry.kindSet: ['sessionExerciseId', 'exerciseId', 'reps'],
                                                                   ← a set row's required fields (set-specific rule)
  watch_session_adoption_bridge.dart:71: WatchInboxEntry.kindSet,   ← inside `_claimKinds` (all four kinds)
```

| Hit | Set-specific rule, or documented boundary? | Verdict |
|---|---|---|
| `watch_session_adoption_bridge.dart:61` (`_declaredKinds`) | boundary — the protocol's four `effortKind` values, all four listed | fine |
| `watch_session_adoption_bridge.dart:71` (`_claimKinds`) | boundary — the four kinds a wrist row can claim a record for (D-133) | fine |
| `watch_session_adoption_bridge.dart:844` | set-specific — the fallback kind for a slot with no modality config, unrelated to which kinds are projected | fine |
| `models.dart:2618` / `:2630` | boundary — the constant and the list that contains all four kinds | fine |
| `watch_session_inbox.dart:171` | set-specific — the fields a set row must carry | fine |

No hit is a set-only gate on the projection, the ledger or the deletion path: `_entriesFor` dispatches
per kind (`watch_session_adoption_bridge.dart`), the projections live per kind in
`phone_entries.dart`, and the sweep contains no `if (kind == kindSet)`-shaped branch.


## Final counts vs baseline

| Check | Baseline (c3e8f22) | After Phase 3 | Delta explained |
|---|---|---|---|
| `.github/copilot/scripts/macos/gateway.sh test` (full) | `+4057 ~1: All tests passed!` | **`+4059 ~1: All tests passed!`** (exit 0, 1:42) | +2: item 0's two S-144 tests (`watch_session_adoption_bridge_test.dart`, `watch_session_auto_push_test.dart`); the `~1` skip is the same pre-existing one |
| `.github/copilot/scripts/macos/gateway.sh lint` | 196 issues / 0 errors (exit 1: the pre-existing info notices) | **196 issues / 0 errors** (exit 1, same notices) | none — a grep of the log for `phone_entries`, `watch_session_adoption_bridge`, `watch_session_auto_push` finds no hit, so no issue names a file this phase touched |
| `… test test/docs_indexing_contract_test.dart` | green | **`+9: All tests passed!`** | the doc pass; includes "no documentation file is within the warning band of the ceiling" (the 52 KB band), "no document carries a step-by-step flow walkthrough" and "every relative link resolves" |
| `.github/copilot/scripts/macos/gateway.sh swift-test` | 335 tests / 0 failures (after Phase 2) | **335 tests / 0 failures** (exit 0) | no `.swift` file changed in Phase 3 (`git-diff --stat` lists no `watch/watchos/**`), so the count is unchanged. Run anyway: the plan's Phase 3 Done Criteria names it. `xcodebuild` / a watchOS simulator stays out of scope for this role |
| invariant: `import .*hive_workout_repository` in `lib/{state,features,widgets,core}` | none | **none** | — |

Residue: no mutation was left applied. After the restore, `gateway.sh test` on the two S-144 files is
`+55: All tests passed!` and `git-diff --stat` shows `watch_session_adoption_bridge.dart` back at its
10 changed lines (the pre-mutation figure), with `phone_entries.dart` at 37. No scratch file was
created.

## Parity check (I-1)

I-1 wants the same payload from either store. The only per-store **payload** dump is for sets:
`test/watch_session_projection_test.dart:2178` runs `S-31 both stores project the same entries` once
per harness (`harnessFactories`) and compares `parity[harness.name] = jsonEncode(payload)` across the
two stores. The three sequences below run on the Mock twin only — that file's `repository` is
`MockWorkoutRepository()` (`:584`) and the S-140…S-143 group does not re-run per store — so their
payload-level equality is *inferred* from row-level parity (`test/watch_capture_repository_parity_test.dart`,
Hive ↔ Mock value-for-value) plus the projection being a pure read of those rows. It was **not
separately observed**, and nothing in Phase 1–3 added a per-store dump for the new kinds.

| Frame sequence | `HiveWorkoutRepository` payload | `MockWorkoutRepository` payload | Equal? |
|---|---|---|---|
| one `timed` instance | not dumped | `S-140 a phone timed entry reaches the wrist` | not separately observed |
| one `round` instance with pauses | not dumped | `S-141 a round and a hold carry their own fields` | not separately observed |
| one `hold` instance with an added weight | not dumped | `S-141 a round and a hold carry their own fields` | not separately observed |

## Out-of-bounds writes found by the reviewer

`<reviewer fills>`
