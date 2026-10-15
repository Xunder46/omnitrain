# Review — watch auto-sync PR 4 (17d): the phone's other entry kinds reach the wrist

## Code review 1 (17d)

Range reviewed: `git diff 3720c6c..HEAD` (phases 1, 2, 3). Findings numbered F1, F2, …; severities
blocker / major / minor.



Plan: `2026-10-07-17d-watch-auto-sync-pr4-plan.md`
Evidence: `2026-10-07-17d-watch-auto-sync-pr4-plan.evidence.md`

**Runs, by me.** `gateway.sh test` → `+4059 ~1: All tests passed!` (0 failures); `gateway.sh lint` →
196 issues, 0 errors (exit 1 = the repo's pre-existing info notices); `gateway.sh swift-test` →
`Executed 335 tests, with 0 failures`. All three match the evidence file.

**Guards spot-checked with `prove-red`** (a guard green at its base proves nothing):

| Guard | Base | Result |
|---|---|---|
| Phase 1 — S-140…S-143 and the two pins | `3720c6c` | **RED**, 7 failures (S-140…S-143, the D-133 pin, the D-132 hold pin, the documented S-2 expectation) |
| Phase 2 — S-144 (auto-push) | `d4e64ee` | **RED** — both S-144 groups fail |
| Phase 3 — S-144 (deletion ledger) | `c3e8f22` | **RED** — `RangeError` at `watch_session_adoption_bridge.dart:395` (`heldWristEntryIds`) |

**Findings — 1 blocker, 1 major, 6 minor.**

| # | Severity | Where | Finding | Fix | Owner |
|---|---|---|---|---|---|
| F1 | **blocker** | `docs/watch_session_sync.md:26` | The Structure table names `WatchSessionAdoptionBridge._wristRowStamps`, a member this change removed: Phase 1 split it into `_rowsOfKind`/`_stampsOf` (`watch_session_adoption_bridge.dart:314`/`:324`), so the doc points a reader at a symbol that does not exist | name the current read, or drop the symbol-level prose and point at `S-142 a wrist-logged entry of any kind is not doubled` | @developer |
| F2 | major | `docs/watch_session_sync.md:24`, `:64` | Both still describe the answer as the phone's logged *sets* ("the sets it logged"; "reads each `set` slot's row groups … emits one `set` entry per row"), contradicting the file's own new bullet at `:327-338` that all four kinds ride | state the four kinds in both places and point at `S-140`/`S-141` instead of restating fields | @developer |
| F3 | minor | `docs/state_management/watch_surface.md:604-635` | The deletion and ledger bullets speak of sets only ("the dropped set", "a hidden set cannot be re-derived") while the push now announces any kind's id | say "the dropped entry" and cite `S-144` | @developer |
| F4 | minor | `…-plan.md:99` (and `:97`) | D-132's omission list claims a `loggedAt` "below the wire minimum (the same floor a set already respects)" — no such floor exists: `wire_limits.dart:18-21` holds `minLoadKg` alone, and neither validator enforces a `loggedAt` minimum | strike the bullet; fold `:97` into Assumption 2, which already records the exclusive-minimum error | @planner |
| F5 | minor | `…-plan.md:221` | The impact row's cited evidence `grep -n "_wristRowStamps" lib test` now returns nothing — the rename stranded the row | restate the row against `_rowsOfKind`/`_stampsOf` (and see F1) | @planner |
| F6 | minor | `test/watch_session_projection_test.dart:2181`, `:2228-2680` | The three new sequences are asserted on the Mock harness only; the store-parity loop (`S-31`) compares both stores for the set frame, so the ordering the positional pairing needs (`distances[position]`, `extraLoads[position]`) is unpinned for the new kinds (Assumption 11 records the gap as a follow-up) | add the three sequences to the parity loop, or record why the store parity needs no extension | @developer |
| F7 | minor | `watch/sync_protocol/PROTOCOL.md` | ~52.5 KB and unguarded: `test/docs_indexing_contract_test.dart` covers `docs/` only, and this PR adds a row to it | none required now; add the file to that test's set if it should be capped | @developer |
| F8 | minor | `docs/plans/2026-10-06-17-watch-auto-sync-index.md:116` | The 17d row says "**shipped 2026-10-07**" while the PR is in review and this review is not a pass | "in review" until it merges | @planner |

The code itself passes every behavioural check (Q1–Q6 below); the blocker is a documentation falseness
under the doc-falsification rule — a doc naming a member the change deleted — which is a rejection
whatever else is right.

## Phase 1 — the phone projects its other kinds

### Checklist conformance

| Phase item | Evidence in the evidence file | Verdict | Note |
|---|---|---|---|
| 1 the two recorded facts | evidence §Phase 1 item 1 | ✅ | `wire_limits.dart:18-21` holds `minLoadKg` alone — the plan's `:97`/`:99` wording overstates it (F4) |
| 2 the three projections + `_window` | evidence `:50` | ✅ | `phone_entries.dart` `projectTimed:102`, `projectRound:147`, `projectHold:206`, `_windowedEntry:352`, `_window:388`; every field passes the schema and both validators (Q1) |
| 3 agreement with `WatchLoggingState.windowPayload` | evidence §Phase 1 item 3; `WatchLoggingState.swift:628` | ✅ | field for field: the window from `startedAt`/`endedAt`; `distanceMeters`+`distanceSource` only on `timed` with distance > 0; `extraLoadKg` only on `hold` ≠ 0; `pausedMs` only on `round` |
| 4 the kind constants | evidence `:52` | ✅ | `models.dart:2618-2621` already carried all four; nothing renamed, nothing migrated, the file correctly untouched |
| 5 `_entriesFor` dispatch | evidence `:53` | ✅ | `watch_session_adoption_bridge.dart:258-300`; `_claimKinds:70` covers every kind a projection arm serves |
| 6 `_wristRowStamps` per kind | evidence `:54` | ✅, with a naming finding | the member was split into `_rowsOfKind:314` / `_stampsOf:324`; the rename left `docs/watch_session_sync.md:26` naming the old one — **F1** |
| 7 the four scenarios | evidence §Phase 1 item 7; `test/watch_session_projection_test.dart:2228` | ✅ | S-140 `:2253`, S-141 `:2313`, S-142 `:2394`, S-143 `:2601`; `prove-red 3720c6c` → RED, 7 failures |
| 8 Progress + evidence | plan `:479-492`; evidence §Phase 1 | ✅ | the counts match my own runs (above) |

### Diff vs Predicted Files

| Predicted | Touched | Out-of-bounds file |
|---|---|---|
| `lib/core/sync_protocol/phone_entries.dart` | ✅ +318 | none |
| `lib/state/watch/watch_session_adoption_bridge.dart` | ✅ +169/−57 | none |
| `lib/data/models/models.dart` (constants only) | ⬜ untouched | none — the constants already existed (`models.dart:2618-2621`, evidence `:52`), so the "if absent" clause never fired |
| `test/watch_session_projection_test.dart` | ✅ +562 | none |
| `test/sync_protocol_fixtures_test.dart` | ⬜ untouched | none — it ran as a regression guard (evidence `:63`); `project`'s set-only contract is unchanged |

The range touches 18 files: the five product paths above, four more test/doc paths, the plan, the
evidence, this review file, the series index (**F8**) and three pipeline files under `.claude/`/
`.github/` (ignored per the brief).

### Scenario conformance (fixture, then assertion)

| S-id | Fixture present as specified | Assertion as specified | Verdict |
|---|---|---|---|
| S-140 | ✅ `:2253` — a phone `timed` instance with a distance and its source | ✅ asserts the `timed` shape field by field (kind, entryId, loggedAt, window, distance, source) | ✅ conformant |
| S-141 | ✅ `:2313` — a `round` with pauses and a `hold` with an added weight | ✅ asserts `roundNumber` = `roundIndex + 1` and the presence of `pausedMs`/`extraLoadKg` | ✅ conformant |
| S-142 | ✅ `:2394` — wrist inbox rows of each kind beside the phone's own records | ✅ asserts the wrist's own entry is absent from `entries` (one entry, not two) | ✅ conformant |
| S-143 | ✅ `:2601` — never-started, zero-window, zero-distance and zero-added-load rows beside expressible ones | ✅ asserts the omissions and that the rest of the snapshot still arrives | ✅ conformant |

Each of the four is a real fixture, not a trivial one: S-142 and S-143 both carry the near-miss rows
(the same millisecond, the same slot) that the 17c reviews found missing, and each fails at `3720c6c`.

### Impact Check re-run

| Plan row | Grep re-run | Dependent suite still green | Verdict |
|---|---|---|---|
| `PhoneEntries.project` callers | re-run: `project` keeps its signature and its set-only body (`phone_entries.dart:62`); the three siblings sit beside it | ✅ the projection and fixtures suites are green | ✅ row holds |
| `_entriesFor` callers | re-run: the only caller is `projectSession` (`watch_session_adoption_bridge.dart:217`) | ✅ the projection suite is green | ✅ row holds |
| `_wristRowStamps` / the set claim rule | re-run: `grep -n "_wristRowStamps" lib test` → **nothing**; the read is `_rowsOfKind:314`/`_stampsOf:324` | ✅ the set behaviour is pinned by the pre-existing S-33/S-34 groups | ⚠️ stale row — its grep no longer names the surface it tracks (**F5**) |
| the validators / `$defs.entry` untouched | re-run: `message_validator.dart`, `SyncProtocolValidator.swift` and `envelope.schema.json` are outside the 18-file diff | ✅ both validators' suites are green | ✅ row holds |

## Phase 2 — the wrist shows them; 17c's deletion covers them

**Checklist.** 1 the Dart twin's S-145 (`test/watch_session_engine_test.dart:1146`) ✅ · 2 the Swift half
of S-145 (`WatchPhoneEntriesTests.swift`, +166) ✅ with **no Swift production change** — the only
`watch/watchos/` diff in the range is that test file, so D-134 held ✅ · 3 `heldWristEntryIds`'s
`kindSet` filter dropped, S-144 added ✅ · 4 the cross-stack and import regression suites, 92 passed
(evidence §Phase 2 item 4) ✅ · 5 Progress and the red→green table ✅.

**Diff vs Predicted Files.** `lib/state/watch/watch_session_adoption_bridge.dart` ✅ ·
`test/watch_session_engine_test.dart` ✅ · `test/watch_session_auto_push_test.dart` ✅ ·
`watch/watchos/Tests/WatchSessionEngineTests/*` ✅ (test file only) · no Swift production file ✅.
Out of bounds: the two Phase-1 pins in `test/watch_session_projection_test.dart` (declared as
Assumption 6). Unfinished: none.

**Impact re-run.** `grep -n "heldWristEntryIds" lib test` → the bridge `:364`, the push seam
(`watch_session_auto_push.dart:62/69/89/286`), the wiring `:205`, three tests. The set behaviour is
unchanged and the ledger now names non-set ids too ✅. No reader the plan did not list was found.

| S-id | Fixture | Assertion | Verdict |
|---|---|---|---|
| S-144 | ✅ `watch_session_auto_push_test.dart:2054`/`:2230` — a phone `timed` entry and a wrist-logged row, through the real push | ✅ the announced id is the phone's minted id for its own entry and the wrist's own id for the wrist's | ✅ conformant; `prove-red d4e64ee` → RED |
| S-145 (Dart) | ✅ `watch_session_engine_test.dart:1146` — a phone frame carrying all four kinds | ✅ the fields arrive, and a second application doubles nothing | ✅ conformant |
| S-145 (Swift) | ✅ `testS145APhoneEntryOfEveryKindIsTheWristsOwn` — the phone's payload applied twice | ✅ `engine.entries`, `observations`, the shown slot's `fields`, `nextRoundNumber` — non-vacuous (the kind-filter mutation killed 8 tests, evidence §Phase 2 item 2) | ✅ conformant |

**Swift production files must be untouched** (D-134). Any diff under
`watch/watchos/Sources/WatchSessionEngine/` other than a test file is a finding.

## Phase 3 — docs, contract sentence, residue sweep

### Doc conformance

| Claim in the docs | Named test | Test exists | Test green |
|---|---|---|---|
| which kinds the phone projects | `S-140 a phone timed entry reaches the wrist`, `S-141 a round and a hold carry their own fields` (`docs/watch_session_sync.md:327-338`) | ✅ both exist | ✅ |
| a `round` carries its round number | `S-141 …` | ✅ | ✅ |
| a `hold` carries its added load | `S-141 …`, `D-132 a hold held with nothing added is projected without the field` | ✅ | ✅ |
| an unrepresentable entry is omitted | `S-143 an unrepresentable instance is omitted, not faked` | ✅ | ✅ |
| a skipped set is not sent | `S-59 a snapshot carries the assist, and omits only the row without reps` | ✅ | ✅ |
| a set's added weight is not sent separately | `S-59 …` (the same bullet) | ✅ | ✅ |
| the rest timer does not travel | `test/watch_logging_timers_test.dart`, `S-79 a snapshot leaves the wrist's countdown running and stops the phone's own` | ✅ | ✅ |
| a deletion of any kind reaches the wrist | `S-144 a non-set entry the wrist logged leaves under the wrist's own id…`, `S-144 a phone-logged record before the wrist's own does not hide the deletion of the wrist's row`, `S-124`/`S-125` | ✅ all four exist | ✅ |

Every test the doc names was looked up by its exact group and test name; none is a paraphrase, and the
omissions list (never started, zero-length window, zero distance, hold of zero added load, skipped set,
rest timer) is each backed by the test it names.

| Doc file | Size | Under 64 KiB | Under the 52 KB band |
|---|---|---|---|
| `docs/watch_session_sync.md` | not measurable with this role's tools (no `wc`, the gateway only) | ✅ guarded — `test/docs_indexing_contract_test.dart` is green (`+9`) with the 64 KiB ceiling | ✅ guarded — that test's 52 KB warning-band case is green (Assumption 10) |
| `docs/modality_tracking.md` (if touched) | untouched | n/a | n/a |
| `docs/modality_based_exercise_ui.md` (if touched) | untouched | n/a | n/a |
| `watch/sync_protocol/PROTOCOL.md` | ~52.5 KB (brief's figure; same measuring limit) | ❌ **unguarded** — not in the index test's file set | ❌ same — **F7** |

### Residue sweep

In `lib/` — **none**. The `BlockTypes.set` / `kindSet` hits in `lib/state/watch` and
`lib/core/sync_protocol` are set-specific rules (`_entry`, `resolveClaims`, `_claimKinds`' set arm, the
set arm of `_entriesFor`) or the documented boundaries. The set-scoped note that Phase 2 had to carry is
gone.

In `docs/` — four: `watch_session_sync.md:24`/`:64` (**F2**), `:26` (**F1**),
`state_management/watch_surface.md:604-635` (**F3**). No sets-only claim survives in
`docs/modality_tracking.md`, `docs/modality_based_exercise_ui.md` or `docs/watch-app-setup-and-qa.md`
(the last says "all four effort kinds" at `:298`), and nothing anywhere claims a non-set deletion is
not carried.

### Structural guards required by this review

| The ledger's claim rule drifting from the projection's (17c's F4 class) | `S-144 the ledger holds the row whose stamp claimed a record, not the record's position in the phone's list` | `test/watch_session_adoption_bridge_test.dart:1172` | ✅ RED at `c3e8f22` (`RangeError` at `:395`) |
| A kind-blind claim (`_rowsOfKind` ignoring the kind) | `D-133 a timed row never claims a round record written at the same millisecond` | `test/watch_session_projection_test.dart` (pin) | ✅ mutation-proven (evidence §Phase 1) |
| A zero added load riding the wire | `D-132 a hold held with nothing added is projected without the field` | `test/watch_session_projection_test.dart` (pin) | ✅ mutation-proven |
| A non-set entry never leaving the wrist's ledger | `S-144 a non-set entry the wrist logged leaves under the wrist's own id…` | `test/watch_session_auto_push_test.dart:2054` | ✅ RED at `d4e64ee` |
| Store parity for the new kinds — the one class this PR leaves unguarded | none yet | — | ❌ open (**F6**) |

## Parity check (I-1)

| Frame sequence | `HiveWorkoutRepository` | `MockWorkoutRepository` | Dart twin | Swift twin | Verdict |
|---|---|---|---|---|---|
| one `timed` instance | not asserted | ✅ S-140 (Mock harness) | ✅ S-145 Dart | ✅ S-145 Swift | ⚠️ Mock + both twins; the store parity is inferred (Assumption 11) — **F6** |
| one `round` with pauses | not asserted | ✅ S-141 | ✅ S-145 Dart | ✅ S-145 Swift | ⚠️ same — **F6** |
| one `hold` with an added weight | not asserted | ✅ S-141, S-143 | ✅ S-145 Dart | ✅ S-145 Swift | ⚠️ same — **F6** |

The inference is sound as far as it goes — the projections are pure reads over the interface, no
repository method changed, and the Mock and Hive implementations of `getTimedInstances`/
`getRoundInstances` are ordered by `entryIndex`/`roundIndex` alike — but the ordering is what the
positional pairing (`distances[position]`, `extraLoads[position]`) rests on, and nothing in the suite
pins it for the new kinds on the Hive store.

## Invariant check

- I-2 layer boundary: `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` → **nothing**; the only importer is `lib/main.dart:20` → ✅ PASS
- I-3 omit, never placeholder: S-143 green, and the payload carries no `0`/placeholder field — the omission assertions require the key to be *absent* → ✅ PASS
- I-4 one entry per real record: S-142 green (one entry, not two) → ✅ PASS

## Conventions verification (`docs/global_conventions.md`, 4f)

```
PASS (4): units + canonical storage (the wire carries canonical kg and the records' own instants, no
label, no conversion, no display-unit value); effort-kind drives analytics (the projection keys on the
slot's kind and its records, never on a session label or modality name); timestamps are source data
(the window comes from persisted wall-clock stamps, never a counter); reuse the canonical owner (the
readers `EntryRows`/`LoggedEntryRows` and the claim rules `resolveClaims`/`resolveRecordClaims` are
reused — the very class 17c's F4 was about).
N/A (3): theme tokens only, card chrome via OmniSurface, instrument panel — no screen, widget or theme
file is in the diff.
FAIL: none.
```

## Assumption Log adjudication

| 1 | D-130's "a hold with no instance" branch omitted as dead code | yes — the writers (`session_core_entry.dart:134-156`, `watch_session_importer.dart:887-893`) always write a `TimedInstance` for a hold | **RATIFIED** — promote to a numbered decision (a permanent "no untestable branch" rule) |
| 2 | `extraLoadKg` has no exclusive minimum | yes — I read the schema: a plain number | **RATIFIED** — and the plan's `:97` prose still contradicts it (**F4**) |
| 3 | the id carries the record's 0-based index (not "1-based") | yes — `entry-slot-…-0` in the pre-existing S-31 tests | **RATIFIED** — D-131 stands; only `roundNumber` is 1-based |
| 4 | positional pairing (the k-th metric row with the k-th entry) | yes — `getTimedInstances`/`getRoundInstances` are ordered by index in both stores | **RATIFIED** — the ordering is what **F6** would pin |
| 5 | the pre-existing S-2 expectation had to change | yes — the `amrap` squat slot now resolves to `set` and the plank is omitted for lack of a window | **RATIFIED** — `prove-red 3720c6c` shows the updated expectation red there for exactly that reason |
| 6 | the two pins live in the Phase 1 test file | yes | **RATIFIED** — a documented cross-phase placement; Phase 2's Predicted Files list should ideally have named the file |
| 7 | S-144 needed no new production API | yes — the fixture logs through the same `TimerManager` path the pre-existing S-122 test uses | **RATIFIED** |
| 8 | S-145's Swift half reads the public surface as the "per-kind tally" | yes — the tallies are private; the test asserts `engine.entries`/`observations`/`fields`/`nextRoundNumber` | **RATIFIED** — no Swift production change was needed (D-134 held) |
| 9 | Phase 3 had to widen the deletion bullet too | yes — done at `docs/watch_session_sync.md:373-385`, naming `S-144` | **RATIFIED** |
| 10 | the doc's size could not be measured | yes — I cannot measure it either; the guard is the index test | **RATIFIED** — its warning-band case is green, so the file is under 52 KB |
| 11 | the parity table is "not separately observed" for the new kinds | yes — the S-31 dump is sets-only | **RATIFIED**, with the guard of **F6** — the follow-up should be the parity-loop extension, not a later dump |

No entry is REVERT, none is ESCALATE, and the log is not suspiciously empty: every judgement call the
implementer made is on it.

## Remediation sub-phases opened

| Sub-phase | Defect | Root cause line | Structural guard it must add |
|---|---|---|---|
| F1 — a doc naming a member the code no longer has | `docs/watch_session_sync.md:26` names `_wristRowStamps`, removed by this change | `lib/state/watch/watch_session_adoption_bridge.dart` (the `_rowsOfKind`/`_stampsOf` split) | the doc's remedy itself: point at `S-142` rather than a private member; and, so the class cannot recur, extend `test/docs_indexing_contract_test.dart` to check that every `Type.member` token in `docs/*.md` resolves in `lib/` |
| F6 — store parity for the new kinds | the three sequences are Mock-only; the ordering the pairing needs is unpinned on Hive | `test/watch_session_projection_test.dart:2181` (the S-31 loop) | add the three sequences to that loop, which already compares both stores' payloads |
| F2, F3 — sets-only residue in two docs | `docs/watch_session_sync.md:24`/`:64`, `docs/state_management/watch_surface.md:604-635` | the same Phase-1 rename and the Phase-2 widening | none needed: the prose is corrected by pointing at `S-140`/`S-141`/`S-144`, and the tests it points at already exist |
| F4, F5, F8 — plan prose and the index row | `…-plan.md:97`/`:99`/`:221`, `docs/plans/2026-10-06-17-watch-auto-sync-index.md:116` | plan text written before the code | none — plan prose is not guarded by design; the correction is the fix |

All of these are one-line mechanical corrections and land in a single pass; **no re-review is needed**
after them, and nothing substantive is deferred to a follow-up PR plan.

## Escalated to Feedback

Nothing genuinely ambiguous came out of the code: every Assumption-Log entry is ledger-consistent, the
four owner defaults (skipped set, a set's added weight, a running `timed` entry, the rest timer) are
stated in the plan's Open questions with implementable, reversible defaults, and no decision
contradicts another. The planner's items are F4, F5 and F8 — prose and a date, not design — so this is
a fix round, **not** a re-plan.

## Fix round 1 (2026-10-07) — the findings' fixes

| # | Fixed in | One line |
|---|---|---|
| F1 | `docs/watch_session_sync.md:26` | the Structure row no longer names the removed `_wristRowStamps`: it says the answer is read per kind through the current `_rowsOfKind`/`_stampsOf` reads and points at `S-142 a wrist-logged entry of any kind is not doubled`; a grep of `docs/` and `watch/sync_protocol/` leaves no hit that names the member as live code (the rest are dated plan/review records) |
| F2 | `docs/watch_session_sync.md:24`, `:64` | both now name the four kinds the answer carries and point at `S-140 a phone timed entry reaches the wrist` / `S-141 a round and a hold carry their own fields`, instead of restating fields or speaking of sets alone |
| F3 | `docs/state_management/watch_surface.md:604-635` | "the dropped entry" and "a hidden entry cannot be re-derived from its rows", citing `S-144 a non-set entry the wrist logged leaves under the wrist's own id, and one the phone logged under the id the phone minted`; reworded shorter so the file does not grow — `test/docs_indexing_contract_test.dart` `+9: All tests passed!` |
| F4 | plan `:97`/`:99`, Assumption 2 | D-132's `loggedAt`-floor bullet is struck (no floor exists: `WireLimits` holds `minLoadKg` alone, and no validator enforces a `loggedAt` minimum) and the `extraLoadKg`-0 bullet folded into Assumption 2; both marked "amended 2026-10-07 (review 1, F4)" |
| F5 | plan impact row `:221` | restated against `_rowsOfKind`/`_stampsOf` (`watch_session_adoption_bridge.dart:314`/`:324`) with "(review 1, F5)" |
| F6 | `test/watch_session_projection_test.dart` | `S-31 both stores pair each kind's rows the same way` added inside the parity loop: it seeds a timed, a round and a hold sequence per harness and pins `distances[position]`/`extraLoads[position]` on both stores; mutation proof in the evidence file |
| F7 | none, as briefed | `watch/sync_protocol/PROTOCOL.md` is ~52.5 KB and outside `test/docs_indexing_contract_test.dart`'s set; adding it to that test would fail its 52 KB band, so the split is a separate PR |
| F8 | `docs/plans/2026-10-06-17-watch-auto-sync-index.md` | the 17c and 17d rows — and the coverage table's 17c mention — now read "built and committed on develop 2026-10-07, not pushed" |

Fix-round runs: full `test` `+4061 ~1: All tests passed!` (baseline `+4059 ~1`; +2 = the parity-loop test on Mock
and Hive), `lint` 196 issues / 0 errors = baseline with no issue naming a touched file, `docs_indexing_contract_test.dart`
`+9`, invariant grep clean. No `lib/` change remains: the mutation used as F6's proof was restored exactly and
`git-diff --stat` does not list `phone_entries.dart`. F1's suggested structural guard — checking every `Type.member`
token in `docs/*.md` against `lib/` — is not among the brief's seven items and is not added here; it stands as a
follow-up. No re-review is needed, per this review's own §"Remediation sub-phases opened".
