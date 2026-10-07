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

| # | Item | Status | Evidence |
|---|---|---|---|
| 1 | `docs/watch_session_sync.md` four kinds + the two omissions | | |
| 2 | PROTOCOL dated sentence | | |
| 3 | modality docs claim check | | |
| 4 | residue sweep | | |
| 5 | full suite + swift | | |
| 6 | final table | | |

Residue sweep output (paste both greps verbatim):

```
grep -rn "BlockTypes.set" lib/state/watch lib/core/sync_protocol
grep -rn "kindSet" lib/state/watch lib/data/models
```

| Hit | Set-specific rule, or documented boundary? | Verdict |
|---|---|---|
| | | |

## Final counts vs baseline

| Check | Baseline | After Phase 3 | Delta explained |
|---|---|---|---|
| `.github/copilot/scripts/macos/gateway.sh test` | | | |
| `.github/copilot/scripts/macos/gateway.sh swift-test` | | | |
| `.github/copilot/scripts/macos/gateway.sh lint` | | | |

## Parity check (I-1)

| Frame sequence | `HiveWorkoutRepository` payload | `MockWorkoutRepository` payload | Equal? |
|---|---|---|---|
| one `timed` instance | | | |
| one `round` instance with pauses | | | |
| one `hold` instance with an added weight | | | |

## Out-of-bounds writes found by the reviewer

`<reviewer fills>`
