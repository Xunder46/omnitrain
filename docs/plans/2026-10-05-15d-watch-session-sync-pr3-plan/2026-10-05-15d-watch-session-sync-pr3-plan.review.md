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
