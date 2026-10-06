# Code Review — watch-session-sync PR 3a

Reviewer: code-reviewer (Copilot CLI edition). Scope: PR 3a = commits c615040 (Phase 1, contract) and
3964cdd (Phase 2, phone projection) on top of c452ba3, plus uncommitted Phase 4 docs.
Phase 3 (wrist re-statement) is PR 3b and is out of scope.

Layers in scope: state (`lib/state/watch/`), core (`lib/core/sync_protocol/`), docs, tests, watch contract.
Layers skipped: models, persistence implementations, features/screens, widgets.

Review complete: 8 findings, 2 critical, 3 warnings, 3 suggestions. Verdict: CHANGES_REQUESTED.

---

## Findings

Diff vs Predicted Files: conforms (Phase 1: PROTOCOL.md + reconciliation fixture; Phase 2: the
projection + its test; Phase 4: the three docs). One file outside the predicted set:
`lib/state/watch/live_session_mirror_debug_main.dart` (a `const <Object?>[]` → `<Object?>[]` tweak,
uncommitted) — harmless, but it belongs in the commit message or out of the diff.

Test run: `.github/copilot/scripts/macos/gateway.sh test` → `01:33 +3935 ~1: All tests passed!` (3935
passed, 1 skipped, 0 failed, exit 0). Swift and analyze not re-run here; the governor's counts stand
(swift 268 / 0, analyze 196 info / 0 error). The suite does not cover F1: a negative-weight set has no
test, so green here is not evidence that AC-6 holds.

---

### F1 — 🔴 CRITICAL — a negative weight makes the whole snapshot invalid

`lib/core/sync_protocol/phone_entries.dart:138` sends a set's weight verbatim as `loadKg`, but
`$defs.entry.loadKg` is `"minimum": 0` (`watch/sync_protocol/schemas/envelope.schema.json:199-202`) —
the schema carries negative load only in `extraLoadKg`, and says so in its own description ("Negative
is band assist, which is why this is not loadKg"). A negative weight on a **set** is a supported input
the phone deliberately stores: `metric_crown_widget.dart:31` clamps `weight` to `-200.0…999.0` and
`:169-172` gives the field a signed keyboard. Such a set has `reps >= 1`, so `_entry` projects it, the
validator rejects it as a `constraint_violation`, and by D-40's own rule a rejected entry rejects the
**whole** snapshot — the wrist then ignores the answer entirely and none of the phone's sets arrive.
This defeats Requirement 7 / AC-6 ("a rejected snapshot is impossible by construction") and D-40's
stated rule ("anything it cannot render is omitted, never placeheld"). `reps` and `loadKg` are
otherwise exactly right: `reps` is a non-null int ≥ 1, `loadKg` a non-null double (bodyweight 0.0
passes), and float noise cannot reach the wire — weights are persisted through
`MetricStepCalc.parseAndClamp`, which writes one decimal.
Fix: omit the group when its weight is negative (D-40's omission rule), or take the planner's call on
how a negative load on a set should travel; then pin it in the S-42 fixture with a negative-weight set
beside a sendable one. → @developer (+ one planner decision)

### F2 — 🟡 WARNING — the "one live row claims one group" premise is unenforced and unpinned

`claimedBy` (`phone_entries.dart:65-77`) claims exactly one group per stamp, the lowest-numbered, with
no provenance check; `_wristRowStamps` (`watch_session_adoption_bridge.dart:258-281`) supplies one
stamp per **live** wrist inbox row. The rule is therefore correct only while one live wrist row maps
to at most one session group at that stamp — a premise A-2 states as fact and S-34 pins for exactly
one arrangement (`test/watch_session_projection_test.dart:978`: one wrist group, one phone group, one
stamp, import first). Nothing enforces it: if two groups ever share one stamp, the second is
projected under a phone id, which violates "One entry, one row" and D-34's "the phone only ever names
its own entries" (the wrist would store its own set a second time, and the echo re-imports on a later
Sync); if a phone group ever takes the lowest number at a wrist stamp, the phone's set is dropped
instead.
I could not construct either path from the shipped code — that is why this is a warning, not a
critical. Fix: add the guard test (two groups at one wrist stamp, assert the invariant holds); if it
fails, the claim needs provenance rather than a stamp. → @developer

### F3 — 🟡 WARNING — a half-applied import row is unclaimed, so the wrist's own set is echoed back

`_wristRowStamps` skips rows whose `appliedAtMs == null`, but the importer writes a group's rows
before marking the row applied (`watch_session_importer.dart`, `_mergeHeld`). A store failure between
the two — the router deliberately continues to the mirror after a failed `inbox.receive`
(`lib/state/watch/watch_incoming_router.dart:96-97`), and the same frame composes the answer — leaves
rows the session already holds unclaimed, so that group is projected back under a phone id and the
wrist doubles its own set. This is the only constructible doubling path I found; probability is low
(a failure mid-import), the consequence is a permanent duplicate on both sides.
Fix: claim on the rows the session actually holds for that stamp, or make the write and the applied
mark one step. → @developer

### F4 — 💡 SUGGEST — the skipped-set check in `_entry` is unreachable

`phone_entries.dart:125`'s `set['skipped'] == true` cannot fire: `markSetSkipped` writes `valueInt: 0`
beside `valueBool: true` (`session_core_entry.dart:526-558`) and the update path clears the flag
whenever reps > 0 (`:250-256`), so a skipped set always has `reps < 1` and is already dropped by the
next clause. Dropping the clause turns no test red, which is the evidence that nothing pins it.
Fix: remove it, or add the test that makes it load-bearing. → @developer

### F5 — 💡 SUGGEST — `ordered`'s `entryId` tie-break has no test

`phone_entries.dart:104-105` breaks a same-instant tie by `entryId`, which is AC-6's determinism claim
and the wrist's own order; no fixture has two unclaimed groups at one stamp, so deleting the tie-break
turns nothing red. Fix: one fixture with two sets logged in the same millisecond. → @developer

### F6 — 🔴 CRITICAL (docs) — the two new "does not sync" bullets name no test

`docs/watch_session_sync.md:174-179` states two new behaviours (an edit to a set already on the wrist
does not update it; a delete does not reach the wrist) as prose with no verification pointer, while
every neighbouring bullet in the same list ends with one (`:168-173`). Phase 4's own criterion 1
requires "a citation naming the real tests for each sentence (S-31…S-43)" (plan `:391-393`), so the
phase is marked `[x]` with its criterion unmet; the documentation standard's §4.2 rejects describing
behaviour instead of pointing at where it is verified.
Fix: add the S-43 test, then point both bullets at it (and at the projection test) — the standard's
remedy is a test plus a pointer, never corrected prose. → @developer

### F7 — 🟡 WARNING — S-43 is cited as a guard but has no test

S-43 ("the phone is unreachable at Sync", plan `:303`) is listed under AC-6 (`:165`) and named as the
guard for the timers row of the Impact table (`:179`), but no test in `test/` references it — the
projection group covers S-31…S-34 and S-36…S-40, S-42 (`test/watch_session_projection_test.dart:787`).
An unowned scenario and an unbacked guard claim are the same gap. Fix: write it, or drop it from AC-6
and the Impact row. → @developer

### F8 — 💡 SUGGEST — the plan's Phase 4 item 2 and its Assumption Log disagree on D-35

Phase 4 item 2 (`:394-395`) instructs citing D-35 for "the wrist merges them by id", and
`docs/state_management/watch_surface.md:73` does; A-3 says no sentence may claim re-statement, and
D-35's rule (`:87-93`) is exactly the re-statement Phase 3 owns. The doc's sentence is true of the
pre-existing merge, so nothing is false today — but a 3b reader following the citation will expect the
rule to be shipped. Fix: cite D-31/D-33 there and record that Phase 3 must revisit the sentence.
→ planner

---

## Behavioural verification

**4a — Acceptance criteria.** AC-1…AC-5: met, each with its scenario test. AC-6: **not met** as stated
— "never emits an entry the validator would reject" is false for a negative weight (F1), and S-43 is
absent (F7).

**4b — Scenario register.** S-31…S-34, S-36…S-40, S-42 have tests whose assertions match their stated
outcomes and whose fixtures match what each scenario enumerates (S-34's same-millisecond fixture is
genuine, not a trivial stand-in). S-35 and S-41 are Phase 3's and correctly absent from 3a. **S-43 has
no test (F7).** S-34's fixture covers one arrangement only (F2).

**4c — Test run.** Re-run here: 3935 passed, 1 skipped, 0 failed, exit 0 (see the header). The handoff
carries pasted counts (flutter 3935 / 0 fail; swift 268 / 0; analyze 196 info, 0 error) and a Docs
section naming each implicated doc. No bug-fix test was claimed, so the fail-without-the-fix rule does
not apply. Mutation evidence
present in the evidence file: removing the provenance claim reddens S-33/S-34/S-37, and the
`skipped`-clause and tie-break mutants stay green (F4, F5).

**4d — Documentation falsification.** Implicated: `docs/watch_session_sync.md`,
`docs/state_management/watch_surface.md`, `docs/watch-app-setup-and-qa.md`, plus the protocol doc and
the plan set. Every test the three docs cite exists by group and name
(`watch_session_projection_test.dart` S-31/S-32/S-38/S-39/S-42, `watch_session_adoption_bridge_test.dart`
S-1, `live_mirroring_test.dart` S-32/S-39). No claim was made false by this change: the "sets logged on
the phone are not carried to the wrist" bullet is gone, `watch_surface.md`'s answer description matches
the post-change code, and `PROTOCOL.md`'s amendment (identity, one-to-one claim, no second store,
ordering, version-history row) matches both stacks — the wrist engines do early-return on a held id,
so "MUST NOT be stored a second time" is true and correctly scoped. `docs/watch-app-setup-and-qa.md`
step (g) is a numbered walkthrough step, but that document is the owner's manual QA script and the step
is marked not yet run — §3.6/§3.7 not triggered.
Result: ✅ PASS — no document was made false by this change; F6 covers the two bullets that are
incomplete rather than wrong.

**4e — Documentation standard.** ❌ REJECT — `docs/watch_session_sync.md:174-179` — class §4.2
(behaviour described instead of pointing at the test that verifies it) → F6. No other prohibited class
added: no hex literals, no control inventory, no restated numeric value, no copied code.
🟡 WARNING — the same two bullets are also incomplete in the "what does not sync" list they join.

**4f — Conventions.** PASS (11): repository interface untouched and still the only persistence door
(state reads through `WorkoutRepository`); no concrete store import in `lib/state/` or
`lib/core/sync_protocol/`; state injected by constructor, no screen touched; models and the SQL
contract untouched (`db_seed_test.dart` unaffected); doc size ceiling respected; no formatter run;
`lib/core/` stays platform-agnostic; no new magic number (ids and kinds are named constants); comments
explain why; public APIs carry doc comments; the invariant grep
(`hive_workout_repository` in state/features/widgets/core) is clean.
N/A (6): screen/component checklist sections (no `lib/features/` or `lib/widgets/` change), design-token
rules, model purity and round-trip rules, mock/production parity for a new store method, migrations,
watchOS Swift changes (the Swift side is unchanged in 3a).
FAIL (1): "a rejected snapshot is impossible by construction" — F1.

**4g — Impact.** 9 rows checked. Row 1 (`projectSession` readers) re-grepped: the listed production
readers are the complete set (`watch_sync_wiring.dart:149`, `watch_sync_request_handler.dart:102`) —
no unlisted reader, and the async change is awaited at all three call sites (the handler, the mirror's
`receive`, and the wiring) with no missed `await`. Rows 2, 3, 7, 9 read directly and hold. Row 8's pin
did flip to a non-empty expectation, as predicted. Row 6 (the "what does not sync" bullet) is done.
Row 5 (timers) cites S-43 as its guard, and S-43 does not exist (F7) — the row's claim is unbacked.
Row 4 is accurate (read-only). No unlisted readers found: ✅ PASS with the one unbacked guard.

## Counts

Critical: 2 (F1 correctness, F6 docs) | Warnings: 3 (F2, F3, F7) | Suggestions: 3 (F4, F5, F8).

## Triage (one round, no review→fix→review)

In this PR: F1 (critical — AC-6/R7 unmet for a supported input), F6 (critical — Phase 4 criterion 1
unmet and a documentation-standard rejection), F2 and F3 as the two guard tests (each a small fixture
beside the existing S-34/S-42 cases), F7 (write it or drop the claim — it is the same gap as F6).
Ride along: F4, F5 (one line each in the same file). F8 is a planner note for 3b. If F1's remedy needs
an owner decision on how a negative load travels, the mechanical part (omit, per D-40) can ship now
and the rest becomes a follow-up plan — do not grow this plan.

## Feedback

See this file, findings F1–F8; fix list: F1, F6, F7 and the F2/F3 guards in one round, F4/F5 alongside.

---

# Code review 2 (PR 3b)

Reviewer: code-reviewer (Copilot CLI edition). Scope: PR 3b = Phase 3 of
`2026-10-05-15d-watch-session-sync-pr3-plan.md` on top of 47e4f88, plus the untracked
`watch/watchos/Tests/WatchSessionEngineTests/WatchPhoneEntriesTests.swift`.

Layers in scope: watch engine (Dart twin `lib/watch/` + Swift `watch/watchos/`), tests, docs, plan.
Layers skipped: models, persistence implementations, features/screens, widgets, state (only read).

Findings are appended below as they are found.

Diff vs Predicted Files: conforms. Phase 3's Predicted Files are the two engines and the two test
files (Dart projection test + `WatchSessionEngineTests.swift`, "or a new `WatchPhoneEntriesTests.swift`
beside it, which SwiftPM picks up automatically" — the new file is the sanctioned alternative). Part B's
docs are the three in `## Files Affected` plus `PROTOCOL.md`; `test/watch_reconciliation_cross_stack_test.dart`
is in `## Files Affected`. The one predicted item that is **not** in the diff is the fixture change
(`fixtures/reconciliation/phone_entries_merge.json`), and A-22/A-23 justify it with observed runs in
both directions; the fixture is byte-identical to HEAD and the divergence is pinned in the cross-stack
test instead. Nothing outside the plan's file list is touched.

## Findings

- **G1 (minor)** — `watch/sync_protocol/PROTOCOL.md:288-289` and `docs/watch_session_sync.md:79-80`:
  the authority carve-out ("MUST NOT re-state an entry the phone holds from the watch's own snapshot")
  is unenforced and unverified. Neither engine has a provenance test — `_storeSnapshotEntry` /
  `storeSnapshotEntry` fold on any held id — and the phone's fallback answer
  (`lib/state/watch/watch_sync_request_handler.dart:101-110` → `live_session_mirror_state.dart:306-312`,
  reached when the phone has no session of its own but the mirror holds a ladder) does carry the
  watch's own UUID entries back to it, where the wrist folds them. Reason: the bullet's "Verified by"
  names tests for the re-statement half only, and the prohibited action is "by construction", not
  implemented. Effect today is nil — the mirror stores the watch's values verbatim (map copy, no
  normalisation), so the correction *equals* the row it folds over and nothing visible moves — but the
  doc states a rule the shipped client does not keep, and the only thing standing between it and a
  visible violation is that a phone cannot yet edit a mirrored watch row. Fix: pin it (an answer naming
  the wrist's own entry leaves `entries` and the stored rows unchanged), or reword both sentences to
  say the phone's answer carries the watch's own values verbatim, so a re-statement of them is a no-op.
  → @developer
- **G2 (minor)** — `lib/watch/session/watch_session_engine.dart:709-712`,
  `WatchSessionEngine.swift:726-728`: the held-id check reads the raw `_observations` /
  `storedObservations` list, unfiltered by `sessionId`, so an `entryId` shared by two sessions folds a
  correction onto the other session's row. Reason: before PR 3b a held id was *ignored*, so a collision
  cost nothing; the fold makes the same collision show another session's values. Not reachable today —
  phone ids are `entry-<sessionExerciseId>-<n>` over a per-session row id and watch ids are UUIDs — but
  nothing asserts that, and S-40 pins only the `entries` getter's session filter. Fix: filter the
  held-id check by session, or extend S-40 to a shared `entryId`. → @developer
- **G3 (minor)** — `lib/watch/session/watch_session_engine.dart:1365-1373`,
  `WatchSessionEngine.swift:1508`: `pruneConfirmed` drops the observation row but leaves
  `_entryCorrections[entryId]` (and `_deletedEntryIds`) in place, so after a prune a re-carried id is
  appended as a fresh row and the *stale* correction then overrides that row's stored payload — the
  newest snapshot stops being authoritative, which is exactly what fix 1 pinned. Reachable today only
  from the debug surface (`lib/watch/debug/watch_session_debug_surface.dart:276`; D-27 keeps production
  pruning off) and not by a relaunch (the lens is memory-only and `restore` does not rebuild it). Fix:
  drop a row's correction with the row in `pruneConfirmed`, pinned in the existing prune tests.
  → @developer
- **G4 (minor, bookkeeping)** — `2026-10-05-15d-watch-session-sync-pr3-plan.md:14`: `Next handoff:
  **@dba (Phase 1 — the contract)**` is stale (Phase 1 shipped in PR 3a; the next handoff is this
  review and the owner walkthroughs) and now contradicts the Status block three lines above it. Same
  file, `## Open questions`: numbers 8 and 9 are each used twice, and item 9 ("One plan, four phases,
  no 3a/3b split … *Default: one plan*") is contradicted by the Split note at the top of the file.
  Pre-existing rather than introduced by this diff — refresh it in the governor's bookkeeping pass.
  Also stale in the same file, by 6-7 lines: the Impact table's `_storeSnapshotEntry:697` (now 704) and
  Swift `storeSnapshotEntry:718` (now 724). The reader *names* in those rows are still correct.
  → governor

## Q1 — the two engines

`_storeSnapshotEntry` (`watch_session_engine.dart:704`) and `storeSnapshotEntry`
(`WatchSessionEngine.swift:724`) match: both guard on the id, and both fold the snapshot payload over
any earlier correction with the **newest winning** — Dart `{...?_entryCorrections[entryId], ...entry}`,
Swift `merging(entry) { _, corrected in corrected }` — then return. Same asymmetry as before the change
(Dart's `entry['entryId']! as String` throws on a malformed entry, Swift's `guard let` returns); not
this diff's.

- **(a) a second row** — no. The guard returns before `_store`/`store.append`, and the fold writes only
  into the in-memory lens; `entries` / `projectedEntries` iterate observations, and the counts
  (`entries.count` on both stacks) stay at one per id. The only way a row reappears is after
  `pruneConfirmed` dropped the original (G3) or a relaunch, neither of which doubles anything.
- **(b) rewrite the stored row** — no. `WatchObservationRecord.payload` is untouched; the row stays
  append-only. The only write to a held row is `withConfirmation` (in-memory `confirmedAt`, not
  persisted), which is the receipt the snapshot already was — pinned by `S-35 …append-only…` in both
  suites.
- **(c) resurrect a deleted id** — no. Both getters drop the deleted set **before** reading the
  corrections (`watch_session_engine.dart:215-216`, `WatchSessionEngine.swift:198-200`) and
  `_applySnapshot`/`applySnapshot` never clear the set, so a re-statement lands in a lens nobody reads
  for that id. Pinned by `S-35 a re-statement of a deleted id stays deleted` (Dart) and
  `testS35AReStatementOfADeletedIdStaysDeleted` (Swift).
- **(d) a wrist-side snapshot overwriting a phone value** — no. `_applySnapshot` is reached only from
  `applyMessage`, and the sole caller is `WatchSyncOrchestrator.receive`
  (`lib/watch/start/watch_sync_orchestrator.dart:138`); the wrist's own snapshot leaves through
  `sessionSnapshot()` and is never applied to itself. `applyMessage` does not inspect `origin`, so
  "the wrist's side cannot win" rests on there being no inbound path that carries wrist-authored values
  — which is the fallback-mirror path above, and its values are the watch's own verbatim. See G1.

## Q2 — the tests

Every new test asserts its claim and none asserts the old behaviour. On the pre-change code the
assertions that flip are red: `S-35 a re-statement is append-only and doubles nothing` and
`S-35 an edit reaches the wrist and a delete is not sent` (both assert `entries` = `[65.0, 62.5]`, which
the early return cannot produce — `engine.observations` = `[60.0, 62.5]` is the half that stays green),
`S-35 a second edit wins over the first` (70 over 65), the Swift `testS35AReStatementShowsThePhonesNewValue…`
and `testASecondEditWinsOverTheFirst`, and the cross-stack test (wrist 65 vs phone 60). Restoring the
pre-edit guard is the recorded mutation 3. Two tests pass both ways and are honest about it:
`S-35 a re-statement of a deleted id stays deleted` (a guard against a future reordering, not a
change-detector — recorded as red under mutation 2) and `S-41` (whose subject is survival and
confirmation of the wrist's own row, not the re-statement — the evidence says so plainly). Nothing is
vacuous: the fixtures are seeded, the answers are composed by the real graph, and the assertions are on
values the fold produces. `S-41` is meaningful: it pins that an answer naming no entries neither drops,
doubles nor confirms the wrist's row, and that only a `receipt` does — the neighbouring D-34/S-33
behaviour the re-statement could have broken. The cross-stack test mutates a deep copy of the fixture
(`jsonDecode(jsonEncode(...))`), so the shared file on disk is untouched, and it deliberately compares
no entry block to `expected` (A-22/A-23).

## Q3 — the docs

Every added sentence is true of the code, with the one carve-out in G1. Citations all resolve to
existing tests that assert the sentence they are attached to: the four Dart `S-35` names, the
cross-stack name, both Swift names, and the pre-existing `S-2` / `S-8 case A` / `S-6` groups and
`S-31 the phone's own sets arrive as entries`. `docs/watch_session_sync.md`'s removal of the
"an edit … does not update the wrist's copy" bullet is complete — a repo-wide grep for that sentence
and for the old test name `D-38 an edit leaves the wrist…` finds hits only inside
`docs/plans/**` history text; `docs/`, `lib/`, `test/`, `watch/` are clean. The delete bullet's
repointed citation (`S-35 an edit reaches the wrist and a delete is not sent`) does assert the delete
half. Nothing names an unshipped thing: `session_reconciler.dart` shipped in PR 3a, and the two engine
doc comments now state the phone-keeps-first / only-the-wrist-re-states asymmetry that A-24 records.
Step (g) of `docs/watch-app-setup-and-qa.md` is true of the code and is marked in the plan as an owner
step not yet run. The PROTOCOL wording is consistent with authority rule 1 and with the neighbouring
general bullet ("an `entryId` a receiver already holds is not stored a second time" — still true: it is
re-stated, not stored), and the version row correctly keeps v1 and claims no fixture change, which is
verifiable: no file under `watch/sync_protocol/fixtures/` is in the diff.

## Q4 — plan hygiene

Status, Progress, Assumption Log and Phase 3's checkboxes all agree with what shipped and with the
observed runs. A-19…A-24 are accurate, A-22/A-23 record the blocked fixture with the observation that
reproduces it, and A-24 ("only the wrist re-states") matches `SyncSessionReconciler._addEntry`'s
first-value-wins. Outstanding: G4's stale `Next handoff` line, the duplicated/contradicted open
questions, and the drifted line pointers.

## Q5 — the rest of the diff

Nothing unrelated. No formatter damage, no stray file: `git-status` lists exactly the eleven files above
plus the one new Swift test. The only non-plan, non-doc content is the one-line-per-file change in each
engine, the two test files, and the sanctioned new Swift test. The evidence file's additions are
in-scope records, and its counts match what I observed (3945/1, 275/0).

## Verification

- Acceptance criteria: PASS (AC-1…AC-6) — AC-4 is this PR's, met by both suites plus the cross-stack test.
- Scenario register: PASS — S-32, S-35, S-38, S-41 have passing, fixture-conformant tests on both
  stacks; S-31/S-33/S-34/S-36/S-37/S-39/S-40/S-42/S-43 unchanged and still green.
- Test run: `.github/copilot/scripts/macos/gateway.sh test` → `01:37 +3945 ~1: All tests passed!`
  (3945 passed, 1 skipped, 0 failed), `.work/gateway/test-20261006-103117-29176.log`.
  `.github/copilot/scripts/macos/gateway.sh swift-test` → `Executed 275 tests, with 0 failures
  (0 unexpected)`, exit 0, `.work/gateway/swift-test-20261006-103305-34202.log`. Both match the
  evidence. Red-without-the-fix is the implementer's recorded mutation 3 plus the two Dart mutations;
  my own reading confirms the pre-edit guard cannot produce the asserted values (I cannot run the
  mutation myself — source edits are outside this role's write scope).
- DOC FALSIFICATION: 🟡 WARNING (G1) — `PROTOCOL.md:288-289`, `docs/watch_session_sync.md:79-80`
  over-claim verification of a rule neither stack implements (no false claim about observable
  behaviour; the prohibited action is currently inert). Everything else PASS: `watch_surface.md`,
  `watch-app-setup-and-qa.md` step (g), the version row, and the plan's own prose are true of the
  post-change code. No document conflict found.
- DOC STANDARD: ✅ PASS — no prohibited content added; the added prose cites tests rather than
  restating values, and step (g) sits inside the existing owner walkthrough.
- CONVENTIONS: PASS (the applicable rules — plan-as-contract, evidence ≥ claim, no source edit without
  a test, docs cite tests, PR scope inside budget) | N/A (the layer rules for models, persistence,
  screens, components and the no-concrete-repository-import invariant: no file in those layers changed).
- IMPACT CHECK: ✅ PASS — the plan's rows all re-verified; the two reader line numbers it names
  (`watch_sync_wiring.dart:149`, `watch_sync_request_handler.dart:102`) still point at the readers, and
  my own grep of the touched surfaces (`_entryCorrections`, `entryCorrections`, `entryId`, `entries`)
  found no reader the plan did not list.
- Assumption Log: RATIFY A-19, A-20, A-21, A-22, A-23, A-24 (A-23/A-24 are worth promoting to numbered
  decisions: the fixture's single `expected` block cannot carry a two-stack divergence, and the
  re-statement is one-way). No REVERT; nothing to ESCALATE beyond G1's wording choice.

## Counts

Critical: 0 | Warnings: 4 minor (G1–G4) | Suggestions: 0. All four carry a named guard.

## Triage (one round, no review→fix→review)

Follow-up, not this PR: G1's missing provenance guard and its doc wording, G2's session filter,
G3's prune/lens interaction, G4's bookkeeping. Record them as a small follow-up plan row (or fix
G3/G2 in the next PR 4 pass, where pruning becomes real); nothing here blocks the merge.

## Feedback

See this file, "Code review 2 (PR 3b)", findings G1–G4. Nothing is blocking; G1's wording is the
only item that touches a contract sentence.
