# Review — watch auto-sync PR 3 (17c): a deletion on the phone reaches the wrist

Plan: `2026-10-06-17c-watch-auto-sync-pr3-plan.md`
Evidence: `2026-10-06-17c-watch-auto-sync-pr3-plan.evidence.md`

The reviewer (the Code Reviewer agent) writes findings here. One table per phase, plus the checks the
plan assigns to the reviewer. Findings are quantified: count, examples, the root-cause line.

## Phase 1 — the phone announces its deletions

### Checklist conformance

| Phase item | Evidence in the evidence file | Verdict | Note |
|---|---|---|---|
| 1 `heldWristEntryIds` | | | |
| 2 `deleteEntryAs` | | | |
| 3 ledger + `_pushOnce` order | | | |
| 4 `_announceDeletions` | | | |
| 5 seam + wiring | | | |
| 6 S-35 flip | | | |
| 7 the new cases | | | |
| 8 Progress + evidence | | | |

### Diff vs Predicted Files

| Predicted | Touched | Out-of-bounds file |
|---|---|---|
| `lib/state/watch/watch_session_auto_push.dart` | | |
| `lib/state/watch/watch_session_adoption_bridge.dart` | | |
| `lib/state/watch/live_session_mirror_state.dart` | | |
| `lib/state/watch/watch_sync_wiring.dart` | | |
| `test/watch_session_auto_push_test.dart` | | |
| `test/watch_session_projection_test.dart` | | |

### Scenario conformance (fixture, then assertion)

| S-id | Fixture present as specified | Assertion as specified | Verdict |
|---|---|---|---|
| S-120 | | | |
| S-121 | | | |
| S-122 | | | |
| S-123 | | | |
| S-126 (first half) | | | |

### Impact Check re-run

| Plan row | Grep re-run | Dependent suite still green | Verdict |
|---|---|---|---|
| `LiveSessionMirrorState.deleteEntry` readers | | | |
| `_pushOnce` send-count assertions | | | |
| `_wristRowStamps` / `claimedBy` readers | | | |

## Phase 2 — the Dart twin keeps the deletion

`<same three tables>`

## Phase 3 — the Swift twin, PROTOCOL, docs

`<same three tables, plus:>`

### Doc conformance (S-127) — reviewer-owned

| Claim in the docs | Named test | Test exists | Test green |
|---|---|---|---|
| a deletion reaches the wrist | | | |
| the deletion survives a wrist relaunch | | | |
| a re-created id is not swallowed | | | |
| a skipped set is not sent | | | |
| a set's added weight is not sent separately | | | |

| Doc file | Size | Under 64 KiB | Under the 52 KB band |
|---|---|---|---|
| `docs/watch_session_sync.md` | | | |
| `docs/state_management/watch_surface.md` | | | |

### Structural guards required by this review

Every defect class this review finds converts into **one** permanent test. List them:

| Defect class | Guard test | File | Landed |
|---|---|---|---|
| | | | |

## Parity check (I-1)

| Frame sequence | Dart twin | Swift twin | Equal | Verdict |
|---|---|---|---|---|
| | | | | |

## Invariant check

- I-2 layer boundary: `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` → `<nothing / hits>`
- I-3 append-only: the delete path touches no row removal → `<grep / read>`
- I-5 session scoping: S-126 green → `<count>`

## Assumption Log adjudication

| Entry | Statement | Ledger-consistent? | Verdict (RATIFIED → D-x / REVERT + remediation / ESCALATE to Feedback) |
|---|---|---|---|
| | | | |

## Remediation sub-phases opened

| Sub-phase | Defect | Root cause line | Structural guard it must add |
|---|---|---|---|
| | | | |

## Escalated to Feedback

`<anything genuinely ambiguous — the only trigger to re-invoke the planner>`

---

# Code review 1 — 2026-10-07 (code-reviewer, Copilot CLI edition)

Range `8d00fab..9312088` (plan `8d00fab`, Phase 1 `0413112`, Phase 2 `c4e29e5`, Phase 3 `9312088`).
Layers in scope: state (`lib/state/watch/`), Dart wrist engine (`lib/watch/session/`), watchOS engine
(`watch/watchos/Sources/WatchSessionEngine/`), tests, docs. Skipped: models, repositories/persistence,
features/screens, widgets, `lib/core/` — nothing changed there. The three template tables above are
superseded by the per-phase verdicts below. **Verdict: CHANGES_REQUESTED — 1 blocker, 1 major, 4
minor.**

## Checks run — observed output

| Check | Observed result |
|---|---|
| `prove-red 8d00fab test test/watch_session_auto_push_test.dart test/watch_session_projection_test.dart` | **RED AT 8d00fab (exit 1)** — 60 passed / 4 failed. `S-35 an edit reaches the wrist and a delete is announced`, `S-120 …`, `S-121 …`, `S-122 …` all fail on assertion mismatches (no load/compile error). Legitimate. Log `.work/gateway/test-20261007-052007-66932.log` |
| `prove-red 0413112 test test/watch_session_engine_test.dart` | **RED AT 0413112 (exit 1)** — 32 passed / 4 failed: both S-124 cases and both S-125 cases fail on assertion mismatches. S-126 passes at base, as designed. Legitimate |
| Phase 3 guards | `prove-red` is **not applicable**: at `c4e29e5` the Swift tests do not compile against the base sources (`deletedEntryIds` absent), and a compile error is not a proof. The evidence's mutations a–d are the correct substitute for that phase; three of the four were re-read and their mutant text matches the shipped code |
| `test` (full suite) | `01:39 +4042 ~1: All tests passed!` — 4042 passed, 1 skipped, 0 failed. Matches the evidence baseline. Green includes `test/docs_indexing_contract_test.dart`, which settles the doc-size question below |
| `swift-test` | `Executed 333 tests, with 0 failures` — matches the evidence (baseline 325). Green **with** F1 present, which is the point: no Swift test drives a local transition after a delete |

## Findings

| # | Severity | Location | What | Fix | Owner |
|---|---|---|---|---|---|
| F1 | 🔴 BLOCKER | `watch/watchos/Sources/WatchSessionEngine/WatchSessionEngine.swift:1067,1080` | `transitionTo` builds its `WatchSessionRecord` without `deletedEntryIds` and appends it straight to the store, so any local wrist action — advance, select, finish, abandon, insert exercise — writes a newer row whose lens is empty; `restore():129` reads the lens off the newest row, so the deleted set comes back on the next launch, and the new row also becomes `current` (`:1081`). Only the 3 message-driven writers go through `storeSessionRow` (`:862`), which carries the union. The Dart twin is safe: its `_transitionTo` funnels through `_appendSessionRow` (`lib/watch/session/watch_session_engine.dart:1140`). So I-1 parity, AC-5 and S-124's Swift half (and the plan index's own acceptance line) fail for a state the tests never build | Write the row through `storeSessionRow` (or union `deletedEntryIds` onto it) — and add the guard in the remediation table | @developer |
| F2 | 🟡 MAJOR | `lib/state/watch/watch_session_auto_push.dart:262` | `changeId: 'del-$entryId'` is not unique per deletion event, and both receivers de-duplicate `changeId` durably (Dart `watch_session_engine.dart:146-153`, Swift `:121,553`). Because the phone reuses a minted entry number and a snapshot clears the tombstone for an id it carries (D-113.3/D-113.2), the sequence delete → re-log the same slot → delete again produces the **same** changeId, the second frame is dropped as a duplicate on both stacks, and the wrist keeps showing a set the phone has deleted. No test on either stack covers the second deletion | Make the id unique per deletion event (the deleted row's `loggedAt` is already the D-113.3 discriminator); AC-1's literal `del-<entryId>` wording then needs the planner's amendment — see Escalated | @developer |
| F3 | 🟡 MINOR | `lib/state/watch/live_session_mirror_state.dart:568` with `watch_session_auto_push.dart:262` | The delete frame's session id comes from the mirror's own `state['sessionId']`, while the snapshot path names the composed session. When the two differ, `_announceDeletions` asks to delete the *composed* session's entry ids under the *mirror's* session name, so a foreign id is told to the wrong session (the wrist refuses it, which leaves the phone's ledger and the wrist disagreeing rather than the deletion landing). The comment at `watch_session_auto_push.dart:229-235` claims the wrist's guard is what makes this safe; that is the wrong reason | Name the session explicitly on `deleteEntryAs` (as `reportLifecycleFor` does) and skip the local apply when the mirror does not hold that session | @developer |
| F4 | 🟡 MINOR | `lib/state/watch/watch_session_adoption_bridge.dart:291` | `heldWristEntryIds` calls `PhoneEntries.claimedBy` once per row with a single stamp, while `projectSession` calls it once per slot with every stamp. Two rows sharing a `loggedAt` can both claim a group under the per-row call and only one can under the projection's, so the two "held" sets disagree — the seam drifts from the rule it must mirror. Its doc comment (`:266-268`) claims it is "the same claim rule the projection uses, not a second one" | Call `claimedBy` the way `projectSession` does (one call, all stamps) or extract the shared helper and have both call sites use it | @developer |
| F5 | 💡 SUGGEST | `watch/watchos/Sources/WatchSessionEngine/WatchSessionEngine.swift:854` | `sameStamp` requires both values to be `String` (`nil,nil` → true; a non-string on either side → false), while Dart's `!=` compares `Object?` directly. Identical for wire `loggedAt` strings, divergent for any non-string stamp | Note the divergence in the plan/evidence, or normalise the stamp on both sides | @developer |
| F6 | 💡 SUGGEST | `docs/plans/2026-10-06-17-watch-auto-sync-index.md:59` | The series index still reads "Delete a set … Not carried", which this PR makes false | 17d's planner updates the index row; not a fix for this PR | @planner |

## The brief's seven questions, answered

1. **`_announceDeletions` ledger.** Sound on its own terms: the seed is `payload ids ∪ held wrist ids`
   (S-122/TRAP 1), ordering is ascending (`S-121`), a set logged and deleted inside one window never
   enters the ledger (`S-123`), and other sessions are dropped (`D-114`, mutation c). The defect is
   the *changeId*, not the ledger — **F2**.
2. **`heldWristEntryIds` claim-rule parity.** Not the projection's rule — **F4**.
3. **Receiver lens.** `restore()` reads the newest row (correct); the equal-`loggedAt` exception is
   implemented on both stacks and is what keeps a stale answer from un-hiding (S-35, mutation b); the
   replacement branch (differing `loggedAt`, `replacedEntryIds`) is correct and is covered
   (mutation a); `_replacedEntryIds` is memory-only on both stacks, consistent with the pre-existing
   memory-only correction lens and unchanged by 17c. The row-write funnel is **not** complete on the
   Swift side — **F1**; the stamp comparison differs — **F5**.
4. **Dart-only vs Swift-only behaviour.** I-1 is broken by F1 (the Swift twin loses the lens on a
   local transition; Dart does not) and by F3's session naming. Everything else matches: same three
   rules, same removal of the id from `replacedEntryIds` on delete and on prune, same union writer.
5. **Do the tests assert their claims?** Yes where they run. Both `prove-red` runs fail on real
   assertions, not load errors, and no new test is vacuous or base-green. Phase 3 legitimately used
   mutations instead of `prove-red` because its guards cannot compile at the base commit. The gap is
   a *missing* test, not a weak one: no Swift test covers a local transition after a delete (F1).
6. **Docs.** All cited Dart and Swift test names exist, including `S-59 a snapshot carries the assist,
   and omits only the row without reps` (`test/watch_session_projection_test.dart:1553`) and the three
   `WatchFileStoreTests` names; `extraLoadKg` prose matches `PROTOCOL.md:131` and the D-58 Swift test;
   both docs' re-pointed S-35 citations resolve. The three doc sizes are inside the band (the
   docs-indexing test, which fails at 0.80 × 64 KiB, is green in the full run). The *behavioural*
   claims are false — 4d below. D-117's two statements are stated and true.
7. **Plan hygiene.** The diff conforms to Predicted Files except one out-of-bounds file that is
   justified: `docs/watch-app-setup-and-qa.md` carried the now-false "Deleting a set on the phone is
   **not** carried", so editing it was required by 4d. Untouched predicted files are all conditional
   ("only if the record's map round trip lives there") and the evidence says why nothing was needed.
   One design decision needs escalation (F2/AC-1). Nothing else was left as an owner default.

## Diff versus Predicted Files

Conforms, with the one out-of-bounds write above (necessary, not scope creep). 19 files changed;
`FileWatchSessionStore.swift` and the three Dart store files were predicted-but-untouched with a
stated reason. Tests changed in exactly the three predicted files plus the two Swift suites.

## Scenario conformance (4b)

| Scenario | Test | Fixture conformant? | Verdict |
|---|---|---|---|
| S-120 | `S-120 the push names the set the phone dropped …` (Dart, red at base) | yes — two sets, ledger seeded, wrist holdings | PASS |
| S-121 | `S-121` (Dart) | yes | PASS |
| S-122 | `S-122` (TRAP 1, wrist-logged row) | yes | PASS |
| S-123 | `S-123` (no frame on the first pass) | yes | PASS |
| S-124 | Dart ×2, Swift ×2, file-store ×2 | yes, **but** every fixture writes the later row with a *message*; no fixture writes a *local action* row → the F1 defect class has no scenario | WARNING |
| S-125 | Dart ×2, Swift ×2 | yes (reused id, differing `loggedAt`) | PASS |
| S-126 | Dart, Swift ×2 | yes (foreign session + repeat) | PASS |
| S-127 | doc-conformance note; the file enumerates no claims, verified | — | PASS with the 4d caveats |
| — | second deletion of a reused id (F2) | no scenario, no test | WARNING |

## Test run verification (4c)

Paste counts above; both handoff claims ("`+4042 ~1`", "`333/0`") are confirmed by my own runs. The
Docs section of the handoff exists and names each implicated doc. Phase 3's guard proof is a mutation
table rather than `prove-red`, correctly justified.

## Documentation falsification (4d)

Implicated (derived from the changed files, then read): `docs/watch_session_sync.md` (scope declares
`lib/state/watch/`), `docs/state_management/watch_surface.md` (declares `lib/state/watch/`, `lib/watch/`
and the Swift engine it mirrors file for file), `watch/sync_protocol/PROTOCOL.md` (the wire contract),
`docs/watch-app-setup-and-qa.md` (no scope declaration, so implicated by every change). The remaining
`docs/` set carries no scope declaration, which by the rule implicates it too; I read the watch-session
documents that could speak to this behaviour and the rest hold no claim about deletions.

- ❌ REJECT — `docs/watch_session_sync.md:356` — "the lens is durable, so a wrist restart does not
  bring the set back" is false when a local action follows the delete on the wrist (F1) → fix F1, then
  **delete the prose and point at the guard test**; do not correct the sentence.
- ❌ REJECT — `docs/state_management/watch_surface.md:617` — "every session row written after a
  deletion carries that deletion" is false for a local-action row (F1) → same remedy.
- ❌ REJECT — `watch/sync_protocol/PROTOCOL.md:564` — "The receiver MUST rebuild the set of deleted ids
  from the rows it has stored, so a receiver restart does not bring a deleted entry back" is false for
  a restart after a local action (F1) → same remedy.
- ❌ REJECT — `docs/watch-app-setup-and-qa.md:388` — "it stays gone after the watch's app is
  relaunched" is false in that same case, and the sentence points a device claim at the **Dart** test
  while the device runs the Swift twin → same remedy, and point the device claim at a Swift test.
- 🟡 WARNING — `docs/plans/2026-10-06-17-watch-auto-sync-index.md:59` still reads "Not carried" (F6).
- 🟡 SCOPE — the docs set largely lacks scope declarations; that is what forces the broad read above,
  not a defect introduced here.
- ⚠️ CONFLICT — none. The docs agree with each other; they are all wrong in the same way.

## Documentation standard (4e)

✅ PASS — the diff adds rules and test pointers, no step walkthroughs, no visual values, no control
inventory, no restated numeric constants, no roadmap language. `PROTOCOL.md`'s added row is a dated
history entry in the document's established form.

## Workspace invariants and conventions (4f)

PASS: I-2 (`grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` →
nothing), I-3 (no row removal anywhere in the delete path; both Swift assertions still list the
observation), I-4 (a deletion is announced only for a previously announced id), repository-interface
and layer rules, button/theme rules (no screen touched), test placement (state and engine tests beside
their subjects).
FAIL: I-1 parity, I-5-adjacent session naming — F1, F3 → @developer.

## Impact (4g)

All 12 rows' greps re-run; each named reader still exists and its tests are green in the full run.
Readers the rows do not list: none for `deletedEntryIds` (engine + records + tests only) and none for
`heldWristEntryIds`/`deleteEntryAs` beyond the wiring. `docs/watch-app-setup-and-qa.md` was correctly
treated as a reader of the old behaviour and updated. Row 1's `deleteEntry` grep omitted the new push
tests, which is expected since they postdate the row.

## Assumption Log adjudication

| Entry | Verdict |
|---|---|
| The `heldWristEntryIds` seam is optional with a default, not forced | RATIFIED — promote to a numbered decision |
| D-113.2 shipped *scoped* (clear only when the wrist holds no row or the stamp differs) rather than literally | RATIFIED — it is what makes S-35 and the impact table consistent; promote, and amend D-113.2's wording |
| "`storeSessionRow` is the funnel every session row passes through" | **REVERT** — false for local transitions; that is F1's root cause |
| "The wrist's guard refuses any other session, so the mirror's own session id is safe" | **REVERT** — F3 |
| Phase 3 could not use `prove-red` and used mutations | RATIFIED — correct for a Swift-only phase |

## Remediation — one bounded pass

| Fix | Guard it must add (permanent) |
|---|---|
| F1: funnel `transitionTo`'s row through the lens-carrying writer | A Swift test that deletes an entry, performs a local transition (advance/select/finish), relaunches over the same store, and asserts the id is still hidden — plus a cross-stack parity assertion for that same sequence |
| F2: a per-deletion-event changeId | A Dart test that deletes a reused id, re-logs the slot, deletes again, and asserts the second deletion reaches the receiver (the changeIds differ) |
| F3: name the session on the delete frame | A test that announces a deletion while the mirror holds a different session and asserts the frame's `sessionId` is the composed one and no tombstone lands on the mirror's own session |
| F4: one claim call shape | A test with two wrist rows sharing one stamp, asserting `heldWristEntryIds` and `projectSession` agree |
| Docs: the four 4d rejects | Delete the stale prose and point at the guard tests above; no corrected prose |

Critical: 1 | Warnings: 2 | Suggestions: 2 | Out-of-bounds: 1 (justified)

## Escalated to Feedback

- **AC-1's literal `changeId: 'del-<entryId>'`** is the source of F2: as written it makes a second
  deletion of a reused id indistinguishable from a re-delivery. The planner must either amend AC-1
  (and D-116's wording) to a per-event id, or accept the swallow knowingly and document it as a limit.
  The implementer's code follows the plan exactly, so this is a plan decision, not an implementation
  error.

## Fix round 1 (developer, 2026-10-07)

Answering the findings one line each; the verdicts, the prove-red lines and the suite counts are in
`2026-10-06-17c-watch-auto-sync-pr3-plan.evidence.md` ("Fix round 1").

| Finding | Answer |
|---|---|
| F1 (blocker) | **Fixed.** The row's lens union lives in one helper, `carryingLens`, which both `storeSessionRow` and `transitionTo` call (Dart's twin already funnelled through `_appendSessionRow`; confirmed). Guards: Swift `testF1ALocalTransitionAfterADeleteKeepsTheLens` — **RED AT HEAD** — and the Dart parity pair `F1 the set stays hidden when the wrist advances after the delete` / `…finishes after the delete`, which pass at base as the parity half the review asked for. Doc sentences kept, since they are true again. |
| F2 (major) | **Fixed**, and the AC-1/D-110/D-116 amendment you escalated was written by this round (each marked "amended 2026-10-07 (review 1, F2)"), per the brief. The id is now `del-<entryId>-<clock ms>-<serial>`; guard `F2 a deletion is announced per delete event, not per entry` — **RED AT HEAD**. No receiver changed. |
| F3 (major) | **Fixed.** `deleteEntryAs(sessionId, entryId, {required changeId})` names the composed session; the local apply happens only when the mirror holds it; the misleading comment is gone. Guard `F3 …` — **RED AT HEAD**. |
| F4 (major) | **Fixed.** `PhoneEntries.resolveClaims` makes one pass per slot and returns the claimed groups *and* the claiming row indexes, so `heldWristEntryIds` and `projectSession` are the same rule on the same list. Guard `F4 two wrist rows of one slot that share a stamp hold one id …` — **RED AT HEAD**. |
| F5 (suggest) | **Aligned, not pinned.** Dart now uses `_sameStamp` (both null, or both `String` and equal), the Swift rule; the branch is unreachable through `WatchProtocolValidator`, which refuses a non-string `loggedAt` before either twin sees it, so a test would pass at HEAD and prove nothing. Recorded as a parity rule in the evidence file rather than as a test you would have to trust. |
| F7 (governor) | **Fixed.** An id whose frame was not handed to the transport stays owed, keeps the id it was minted with, and the next pass re-sends it; the exception still goes through `_report` and the rest of the loop is unaffected. Guard `F7 the next pass announces the deletion the failed one could not …` — **RED AT HEAD**. |
| Docs (4d rejects) | Kept, because F1 makes them true; the changeId sentence now follows the per-event shape, and `docs/watch_session_sync.md` and `docs/state_management/watch_surface.md` name the F2/F7 guards and the Swift F1 guard. `grep -rn "del-" docs watch/sync_protocol` finds no surviving literal (only this plan folder's history). |
| Out-of-bounds write (1) | Unchanged from the review's ruling: justified, and it is now on the plan's Files Affected row. |
