# Review — a negative load (band assist) on a set works on the phone and the watch

Plan: `2026-10-06-16-watch-negative-load-plan.md`. Findings go here, one per item, quantified (count,
examples, the root-cause line). Findings are never written into the plan; defects open a Phase X.Y
remediation sub-phase with a structural guard.

## Checklist the reviewer owes

1. **Diff vs Predicted Files** per phase — an out-of-bounds file and an untouched predicted file are
   both findings.
2. **Per-S-x conformance** — S-58…S-67 exist as tests (or as fixture replays), each with the fixture
   its scenario enumerates; an assertion that passes only because the fixture is thinner than the
   scenario is a finding.
3. **Impact-Check conformance** — re-run every grep in the plan's Existing-Functionality Impact table;
   a reader of a touched surface the table does not name is a finding. Confirm the "deliberately
   untouched" list is untouched.
4. **Parity** — `MockWorkoutRepository` and `HiveWorkoutRepository` return the same set for a negative
   `weightKg`; the Dart and Swift floors agree with the schema (D-59) and with each other.
5. **The floor is one number** — no `-200` literal outside `wire_limits.dart` and
   `WatchMetricStepping.minimumLoadKg`; no `> 0` / `>= 0` load guard left in `lib/watch/` or
   `watch/watchos/Sources/`.
6. **Omission semantics** — only `reps < 1` and a below-floor load are omitted; a zero weight still
   sends no `loadKg`; the version-mismatch path is untouched (D-66).
7. **Docs** — `docs/watch_session_sync.md` no longer claims an assisted set cannot travel;
   `docs/state_management/watch_surface.md` is untouched; `docs/watch-app-setup-and-qa.md` has the
   owner step and no new "known gap".
8. **Assumption Log adjudication** — ratify (promote to a D-x) or revert each entry; an entry that
   contradicts a D-x or an invariant is a revert with a remediation item.

## Findings

### Code review 1 — whole feature (`git diff 906a6b1..HEAD`, Phase 1–3)

Reviewed range: `906a6b1..HEAD` (commits `69bddeb`, `49232ed`, `ce187bb`; plan commit `906a6b1`).

Observed, not claimed:

- `gateway.sh test` → **3980 passed, 1 skipped, 0 failed** (`All tests passed!`, log
  `.work/gateway/test-20261006-175615-69204.log:4613`). Matches the evidence file.
- `gateway.sh swift-test` → **302 executed, 0 failures** (log `.work/gateway/swift-test-20261006-175812-74337.log`).
- `gateway.sh lint` → **196 issues, all `info`, exit 1** — the repo's pre-existing baseline; no new issue
  in any changed file.

### F1 — 🟡 WARNING — the plan's own S-61 table states a behaviour the code does not have

`2026-10-06-16-watch-negative-load-plan.md:198` lists the dial row `(0, -1) → 0`, glossed "a positive dial
still stops at zero". Both stacks ship the opposite: `test/watch_logging_stepping_test.dart:221` and
`WatchLoggingTimersTests.testS061AnAssistedLoadStopsAtTheWireFloor` both assert the dial **crosses zero
into an assist** (`adjust(0, weight, -1) == -step`), which is D-62's decision. The tests are right; the
plan row is a pre-change leftover. **Fix**: delete the `(0, -1) → 0` row — the `(+2.5, -1) → 0` row already
carries the "a positive dial still stops at zero" case. One line, no code change. → @planner

### F2 — ❌ REJECT (documentation standard, class 3.4) — `docs/watch_session_sync.md:181-182`

"down to the wire's floor of −200 kg (D-58). The floor is one number — `WireLimits.minLoadKg`…" restates
the value in the same breath as naming the constant. `WireLimits.minLoadKg` is the owner; prose must not
be a second source of truth. **Fix**: "…as a negative `loadKg`, down to the wire's floor
(`WireLimits.minLoadKg`, D-58/D-59)…". One-line edit; the three test pointers stay. → @developer

### F3 — 🟡 WARNING (documentation standard, classes 3.1/3.2/3.4) — `docs/watch-app-setup-and-qa.md:467-478`

The new owner step is a numbered walkthrough ("Dial the load down past zero: the row shows a leading
minus, and the crown stops at −200 kg …"), restating the floor and a visual label. §6's named exceptions
are exhaustive and do not cover this file, and the whole file is walkthrough by genre — a pre-existing
condition this step deepens rather than invents. **Fix (in this PR)**: keep the step and its test
pointers, drop the restated value and the "the row shows a leading minus" clause. **Follow-up PR**: bring
the file's genre into conformance, or get it an explicit §6 exception. → @developer

### F4 — 🟡 WARNING (a documentation claim this change makes ambiguous) — `docs/state_management/watch_surface.md:240`

"metrics the wire has no key for (RPE, rest, band assist) are not sent" sits inside the paragraph about a
routine's **targets**, and S-66 now ships a routine whose assisted `weight` target travels as a negative
`loadKg`. D-65 ruled it true because "band assist" there means the `extra-weight` metric — which
`constants_reference.md:93` and `data_models.md:83` support — but a reader of that paragraph now reads
"an assisted target is not sent", which this PR makes false. **Fix**: name the metric — "(RPE, rest, the
`extra-weight` metric)". Two words; do not ship it as written. → @developer

### F5 — 🟡 WARNING (unplanned files inside the reviewed range)

`906a6b1..HEAD` also carries another feature's planning material (commit `b14b7d6`):
`docs/plans/2026-10-05-15-watch-session-sync-index.md`,
`docs/plans/2026-10-06-17-watch-auto-sync-index.md` and
`docs/plans/2026-10-06-17a-watch-auto-sync-pr1-plan/*`. Not this PR's work and not a defect in it, but it
would merge with it. **Decide at merge** whether that commit belongs in this branch. → governor

### F6 — 💡 SUGGEST (test precision) — `test/watch_session_import_test.dart:1096-1101`

S-65's "a refusal, not a clamp to −200" half rests on the outbound `constraint_violation` (`:1080-1093`);
the local assertion that the entry keeps `-200.0` would hold just as well if `_effectiveEntry` clamped
instead of refusing. Add one assertion that separates them — that no correction row for the −240 value
was stashed, or that the entry is unchanged from its *pre-correction* value. → @developer

### Verified good (not findings)

- **The floor is one number, in five places.** All three schema sites (`envelope.schema.json`
  `$defs.entry.loadKg` + `$defs.metricTargets.loadKg`, `structure_change.schema.json`
  `$defs.correction.loadKg`), `WireLimits.minLoadKg`, `WatchMetricStepping.minimumLoadKg` and the phone's
  own editor (`lib/widgets/session/metric_crown_widget.dart:36`, pre-existing) all say −200. No `> 0` /
  `>= 0` load guard survives in `lib/watch/` or `watch/watchos/Sources/` (`WatchSensorSummaries.swift:140`
  is steps). `watch/contract/watch_logging_contract.json` carries no load bound, so nothing there drifted.
- **Both floor tests read the repository, not a copy.** `test/watch_wire_limits_test.dart` decodes all
  three JSON minimums; `testS059TheWireFloorMatchesTheSchema` reads the same schema through
  `Fixtures.repositoryRoot`, which is derived from `#filePath`, so it is cwd-independent.
- **Omission semantics are consistent.** `PhoneEntries._entry` omits on `reps < 1` or a below-floor load
  only; the wrist's own emitter always omitted a zero load, and every phone reader of the projected
  `loadKg` defaults with `?? 0.0` (`watch_session_importer.dart:870, 1026, 1346`), so absent ≡ 0.0 still
  holds. No production reader branches on `containsKey('loadKg')` — only tests do. The D-60 change (a zero
  weight now writes no key) is therefore invisible downstream; the updated S-2 assertion is the guard.
- **A negative load survives the fold.** `WatchSessionEngine` stores snapshot payloads verbatim and
  `_effectiveEntry` passes an uncorrected negative through (`_real(effective['loadKg'])`); S-67 asserts
  both stacks converge on the same three values.
- **Display.** Both stacks special-case zero before formatting, so `-0.0` cannot print; S-064 asserts
  `-20.0 kg` and `-44.1 lbs`.
- **Impact table re-run.** Every row's grep re-run holds: `scripts/sqlite_schema.sql`'s effort-observation
  `CHECK`s constrain "at most one value column", never sign; `clampTo` has exactly one caller; the
  "deliberately untouched" files (routine-target path, `docs/state_management/watch_surface.md`) are
  untouched. No reader of a touched surface is missing from the table.
- **Diff vs Predicted Files.** All three phases' predicted files are present; the two extra test files
  Phase 1 added (`test/sync_protocol_fixtures_test.dart`, `test/watch_reconciliation_cross_stack_test.dart`)
  are recorded in A-P1-1 and named in Files Affected. No predicted file is missing.
- **Doc falsification.** No `docs/` file still claims a band-assisted set cannot travel; the old claim was
  rewritten with test pointers. Nothing false found (F4 is the one ambiguity, above).

### Assumption Log adjudication

- A-P1-1, A-P1-2, A-P1-3 — **RATIFY**. Fixture-level choices, consistent with D-58/D-66.
- A-P2-1 — **RATIFY, promote to a decision.** The zero-load omission is a wire-visible behaviour change;
  it deserves a `D-` number rather than an assumption entry.
- A-P2-2, A-P2-3 — **RATIFY**. Correct, and A-P2-3's "already landed" is true in the diff.
- A-P3-1, A-P3-2, A-P3-3 — **RATIFY**. A-P3-3 (`gateway.sh format` refuses tracked files) is a real
  tooling limit, not a shortcut.
- No silent guess found in the diff that the log fails to record.

### Guards owed

- F1 → the plan row is the guard (the two stepping tests already pin the behaviour).
- F2, F3, F4 → documentation-only; the tests named in each already guard the behaviour, so no new test.
- F6 → one extra assertion inside the existing S-65 test.

### Answers to the brief's questions

1. **Do all floors agree on −200?** Yes — three schema sites, `WireLimits.minLoadKg`,
   `WatchMetricStepping.minimumLoadKg`, the phone editor's clamp, and both floor tests that read the
   schema. Nothing in either stack floors a set's load at 0 any more.
2. **Is the D-60 omission change visible where the plan did not look?** No. Every phone reader of a
   projected `loadKg` defaults to 0.0, no production reader branches on key presence, and the wrist's own
   emitter already omitted zero — so absent ≡ 0.0 before and after. The updated S-2 assertion is the only
   place that had to move.
3. **Does a negative load display and survive?** Yes: both formatters special-case zero so no `-0.0`, and
   a negative load survives the snapshot fold, the correction path and the re-carried snapshot (S-64, S-65,
   S-67).
4. **Are the tests meaningful?** Yes — the floor tests read the repository's own schema rather than a copy
   (`Fixtures.repositoryRoot` is cwd-independent), S-59/S-60 compare a decoded id → `loadKg` map rather
   than substrings, and the evidence file records red-first mutations for each gate. F6 is the one
   precision gap.
5. **Is the documentation still true?** Yes — no doc still claims an assisted set cannot travel. It does
   add two pieces of content the documentation standard prohibits (F2 clear-cut, F3 genre-wide), and F4 is
   now ambiguous.
6. **Is the plan still truthful?** One stale row: F1. Everything else — decisions, scenarios, acceptance
   criteria, Progress, Assumption Log — matches the diff.

### Scope triage

Six findings, one of them a documentation-standard rejection and five cheap. No design finding spans
layers, and no code change is requested, so this is **one bounded documentation pass, no second review
round**: F1 (plan row), F2, F3, F4 in this PR; F5 at merge; F6 with any future touch of that test file.
Nothing here is worth a follow-up plan except F3's file-wide conformance question.

VERDICT: CHANGES_REQUESTED — documentation only; the code is approved as it stands.
